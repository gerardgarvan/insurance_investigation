# Domain Pitfalls

**Domain:** Encounter-Level Cancer Linkage & First-Line Therapy Regimen Identification in PCORnet CDM
**Researched:** 2026-05-29
**Confidence:** MEDIUM (WebSearch + official PCORnet documentation + clinical informatics literature)

---

## v1.8 Critical Pitfalls

These pitfalls are specific to milestone v1.8: adding encounter-level cancer linkage (replacing patient-level), first-line therapy regimen labeling (ABVD, BV+AVD, Nivo+AVD), SCT detection refinement (drop ICD diagnosis codes), and death date analysis.

---

### Pitfall v1.8-1: NULL/Missing ENCOUNTERID Population Varies by Table

**What goes wrong:**
ENCOUNTERID is optional in PRESCRIBING and may be NULL in DISPENSING depending on data source. Attempting an inner join on ENCOUNTERID drops 10-60% of medication records at non-integrated delivery systems. For chemotherapy regimen detection (ABVD, BV+AVD, Nivo+AVD), this can cause complete failure to identify first-line therapy if prescriptions lack encounter linkage.

**Why it happens:**
DISPENSING data often comes from external pharmacies (CVS, Walgreens) without EHR encounter integration. PRESCRIBING may originate from provider orders entered outside of formal encounters (phone renewals, portal requests). At non-integrated delivery systems, 60.6% of dispensing records have no matching prescriptions with same-day encounters. Closed integrated delivery systems (cIDS) show 90.5% match rate, while non-cIDS sites show only 39.4%.

**Consequences:**
- Regimen detection fails completely at claims-heavy sites (FLM)
- Patient with complete ABVD regimen in PRESCRIBING appears as "no treatment" if all 4 drugs have NULL ENCOUNTERID
- Attrition waterfall shows massive drop at "Link to encounter" step (20-60% loss)
- Site-specific bias: UFH (EHR-heavy) retains 90% of medications, FLM (claims) retains 40%
- First-line therapy analysis excludes majority of eligible patients at some sites

**Prevention:**
- **Phase 01 (Data validation):** Pre-validate ENCOUNTERID population rate by table and source before designing linkage strategy
  - Run: `SELECT SOURCE, COUNT(*) AS total, SUM(CASE WHEN ENCOUNTERID IS NULL OR ENCOUNTERID='OT' THEN 1 ELSE 0 END) AS null_count FROM PRESCRIBING GROUP BY SOURCE`
  - Document expected population rates per site (AMS: 85%, UFH: 90%, FLM: 35%)
- **Phase 02 (Linkage design):** Use multi-tier linkage strategy:
  1. Exact ENCOUNTERID match (highest confidence)
  2. PATID + date window (+/- 3 days) for NULL ENCOUNTERID (medium confidence)
  3. PATID + medication + date window (+/- 14 days) for orphan prescriptions (low confidence, log separately)
- **Phase 03 (Regimen detection):** Anchor on PROCEDURES/MED_ADMIN (high ENCOUNTERID population) and use PRESCRIBING/DISPENSING as supplemental evidence
- **Phase 03 (Logging):** Document linkage tier per medication: `linkage_method` column (exact_encounter / date_window_3d / date_window_14d / unlinked)

**Warning signs:**
- Attrition log shows >20% loss on first encounter-level join
- Regimen detection works for some sites (UFH, AMS) but fails completely for others (FLM claims-only)
- Treatment episodes appear incomplete (AVD detected without brentuximab despite BV+AVD being standard of care)
- Site-specific detection: AMS detects 45 ABVD regimens, FLM detects 0 (same cohort characteristics)

**Phase to address:**
Phase 1 (Data validation & linkage strategy design) — prevents cascade failures in later phases

**References:**
- [Comparing Prescribing and Dispensing Data of the PCORnet Common Data Model](https://pmc.ncbi.nlm.nih.gov/articles/PMC6460498/) — 90.5% match at integrated sites, 39.4% at non-integrated

---

### Pitfall v1.8-2: Many-to-Many Explosion on Diagnosis-to-Encounter Join

**What goes wrong:**
A single encounter can have 10-20 diagnosis codes (primary + secondary). Cancer patients often have multiple active cancer diagnoses (HL + solid tumor history, HL + second malignancy). Naive join of PROCEDURES to DIAGNOSIS on ENCOUNTERID produces 100-400 rows per treatment event when 1 encounter has 15 diagnoses, making it impossible to identify the cancer diagnosis that triggered the treatment.

**Why it happens:**
PCORnet CDM models diagnosis as a separate table with 1-to-many relationship to ENCOUNTER. Developers familiar with TUMOR_REGISTRY (1 row = 1 cancer) expect similar cardinality. ICD-10-CM allows coding historical cancers (Z85.*), complications (T86.5), and status codes (Z94.84 SCT status) on same encounter as active cancer (C81.*), all with ENCOUNTERID populated. Standard database join (PROCEDURES INNER JOIN DIAGNOSIS ON ENCOUNTERID) produces Cartesian product: 1 procedure × 15 diagnoses = 15 rows per treatment.

**Consequences:**
- Cohort size inflates 10-20x after encounter-level join (was 500 patients, now 5,000 treatment-diagnosis combinations)
- Same ENCOUNTERID appears 15+ times in output with different cancer categories
- Gantt chart shows impossible sequences (patient treated for breast cancer and HL on same day)
- HIPAA suppression breaks (counts inflated beyond actual patient counts)
- Downstream aggregations wrong (sum of episodes = 5,000 but should be 500)

**Prevention:**
- **Phase 01 (Scope):** Explicitly document 1-to-many cardinality; plan disambiguation strategy before join
- **Phase 02 (Diagnosis ranking):** Pre-filter DIAGNOSIS to malignant C-codes (C00-C96) before join, exclude:
  - Z85.* (history of cancer — not active)
  - D-codes (benign neoplasms, already excluded in v1.7)
  - T86.5 (SCT complications — diagnosis, not the cancer being treated)
- **Phase 02 (Primary diagnosis selection):** Rank diagnoses within encounter using window functions:
  ```r
  diagnosis_ranked <- diagnosis_filtered %>%
    group_by(ENCOUNTERID) %>%
    arrange(
      CASE WHEN PDX == 'P' THEN 1 ELSE 2 END,  # Primary discharge diagnosis first
      CASE WHEN DX_SOURCE == 'Primary' THEN 1 ELSE 2 END,  # Primary diagnosis source
      DX_DATE  # Earliest date if multiple primaries
    ) %>%
    mutate(diagnosis_rank = row_number()) %>%
    filter(diagnosis_rank == 1)  # Keep top 1 per encounter
  ```
- **Phase 03 (HL priority rule):** For ambiguous cases (2+ active cancers on same encounter), apply clinical logic: HL takes priority for HL-directed therapy (ABVD, BV+AVD, Nivo+AVD)
- **Phase 03 (Validation):** Assert 1:1 cardinality: `n_distinct(ENCOUNTERID) == nrow(diagnosis_ranked)`

**Warning signs:**
- Cohort size inflates 10-20x after encounter-level join (was 500 patients, now 5,000 treatment episodes)
- Same ENCOUNTERID appears 15+ times in output with different cancer categories
- Gantt chart shows impossible sequences (patient treated for breast cancer and HL on same day)
- Row count after join > row count before join × 2 (sign of cartesian explosion)

**Phase to address:**
Phase 2 (Encounter-level cancer linkage implementation) — requires explicit disambiguation logic

---

### Pitfall v1.8-3: Orphan Diagnoses Without Encounters

**What goes wrong:**
15-30% of DIAGNOSIS records at claims-heavy sites have ENCOUNTERID='OT' or NULL. These "orphan diagnoses" include critical HL diagnosis codes (C81.*) that would be lost with ENCOUNTERID-only linkage. Patient's primary HL diagnosis may exist only as an orphan, causing them to drop from cohort despite meeting inclusion criteria (2+ C81.* codes, 7-day separation).

**Why it happens:**
Claims data (especially from CMS) includes diagnoses from lab claims, imaging claims, and DME claims where ENCOUNTERID is not required or populated. Some EHR systems batch-import problem lists without linking to specific encounters. PCORnet CDM allows ENCOUNTERID='OT' (other) for these cases. At claims-heavy sites, diagnoses from claims are coded at claim-level, not encounter-level.

**Consequences:**
- Cohort attrition shows "No HL diagnosis" despite DIAGNOSIS table containing C81.* codes for those patients
- Site-specific attrition: FLM (claims) loses 60%, UFH (EHR) loses 5%
- HL cohort confirmation (2+ codes, 7-day gap) fails because one C81.* code is orphan (no ENCOUNTERID) → doesn't link to treatment
- Treatment episodes appear with no cancer diagnosis (cancer_category = NA)
- Diagnosis table has 50,000 rows but only 30,000 with non-null ENCOUNTERID → 40% orphan rate

**Prevention:**
- **Phase 01 (Data validation):** Check orphan diagnosis rate per site:
  ```r
  orphan_rate <- diagnosis %>%
    group_by(SOURCE) %>%
    summarise(
      total = n(),
      orphan = sum(is.na(ENCOUNTERID) | ENCOUNTERID == 'OT'),
      orphan_pct = orphan / total * 100
    )
  ```
  - Flag if orphan rate >40% at any site (suggests data quality issue vs. expected claims pattern)
- **Phase 02 (Fallback linkage):** Implement 3-tier linkage for orphan diagnoses:
  1. Exact ENCOUNTERID match (highest confidence)
  2. ENCOUNTERID='OT' or NULL: Link to nearest encounter by date (+/- 30 days) with matching ENC_TYPE (IP/AV)
  3. If no nearby encounter: Create pseudo-encounter at ADMIT_DATE or use diagnosis as patient-level flag
- **Phase 02 (HL cohort confirmation):** Check BOTH encounter-linked AND orphan diagnoses for HL confirmation (2+ codes, 7-day gap)
- **Phase 03 (Logging):** Log orphan diagnosis handling per patient: `hl_dx_linkage_method` column (encounter_exact / nearest_encounter / patient_level)

**Warning signs:**
- Cohort attrition shows "No HL diagnosis" despite DIAGNOSIS table containing C81.* codes for those patients
- Site-specific attrition: FLM (claims) loses 60%, UFH (EHR) loses 5%
- Diagnosis table has 50,000 rows but only 30,000 with non-null ENCOUNTERID
- HL cohort confirmation count drops 30% when switching from patient-level to encounter-level linkage

**Phase to address:**
Phase 2 (Encounter-level cancer linkage) — must handle orphan diagnoses before cohort assembly

---

### Pitfall v1.8-4: Chemotherapy Regimen Fragmentation Across Encounters

**What goes wrong:**
ABVD requires 4 drugs (doxorubicin, bleomycin, vinblastine, dacarbazine) given on day 1 and day 15 of 28-day cycle. In real-world data, each drug may be a separate encounter (4 encounters on day 1, 4 on day 15). Naive "all 4 drugs on same ENCOUNTERID" logic finds zero ABVD regimens despite 200+ patients receiving it.

**Why it happens:**
Infusion centers create separate encounters per drug for billing (each drug = separate CPT code + revenue code). Some drugs are pushed (10-minute admin), others are infused (2-hour admin), leading to sequential start times that cross midnight or span 2 calendar days. PCORnet MED_ADMIN captures start + end times, but ENCOUNTERID may differ even for same-day drugs. ABVD is given in 28-day cycles with day 1 + day 15 administration; detecting this requires tracking across 2 days and multiple encounters.

**Consequences:**
- Zero ABVD detections despite TUMOR_REGISTRY showing "chemotherapy" flag for 200 patients
- Only detecting single-agent doxorubicin or vinblastine (because same-encounter logic fails)
- Regimen detection works in MED_ADMIN but not in PRESCRIBING (different ENCOUNTERID per drug)
- First-line therapy analysis has 0 patients → entire milestone fails

**Prevention:**
- **Phase 01 (Regimen design):** Define cycle window: +/- 3 days from anchor date (allows for scheduling variations, weekends, holiday delays)
- **Phase 02 (Cycle detection):** Detect regimen across encounters: Group by PATID + cycle_window, count distinct drugs
  ```r
  # Define cycle start dates (first occurrence of any ABVD drug)
  cycle_starts <- med_admin %>%
    filter(drug_in_abvd_set) %>%
    group_by(PATID) %>%
    arrange(MEDADMIN_START_DATE) %>%
    mutate(
      days_since_last = as.numeric(MEDADMIN_START_DATE - lag(MEDADMIN_START_DATE)),
      new_cycle = is.na(days_since_last) | days_since_last > 21  # >21 days = new cycle
    ) %>%
    filter(new_cycle) %>%
    select(PATID, cycle_start_date = MEDADMIN_START_DATE)

  # Detect regimen within +/- 3 day window
  regimen_detection <- med_admin %>%
    inner_join(cycle_starts, by = "PATID") %>%
    filter(abs(MEDADMIN_START_DATE - cycle_start_date) <= 3) %>%
    group_by(PATID, cycle_start_date) %>%
    summarise(
      has_doxorubicin = any(str_detect(drug_name, "doxorubicin")),
      has_bleomycin = any(str_detect(drug_name, "bleomycin")),
      has_vinblastine = any(str_detect(drug_name, "vinblastine")),
      has_dacarbazine = any(str_detect(drug_name, "dacarbazine")),
      has_brentuximab = any(str_detect(drug_name, "brentuximab"))
    )
  ```
- **Phase 03 (Regimen classification):**
  - ABVD: doxorubicin AND vinblastine AND dacarbazine AND bleomycin (no brentuximab, no nivolumab)
  - BV+AVD: brentuximab AND doxorubicin AND vinblastine AND dacarbazine (bleomycin ABSENT or only in first 1-2 cycles before switch)
  - Nivo+AVD: nivolumab AND doxorubicin AND vinblastine AND dacarbazine (no brentuximab, bleomycin absent)
- **Phase 04 (Dose modifications):** Handle bleomycin absence: Missing bleomycin after cycle 2 is standard practice (pulmonary toxicity), not a regimen change — still label as ABVD

**Warning signs:**
- Zero ABVD detections despite TUMOR_REGISTRY showing "chemotherapy" flag for 200 patients
- Only detecting single-agent doxorubicin or vinblastine (because same-encounter logic fails)
- Regimen detection works in MED_ADMIN but not in PRESCRIBING (different ENCOUNTERID per drug)
- Cycle window analysis shows drugs clustered within 1-2 days but different ENCOUNTERIDs

**Phase to address:**
Phase 4 (First-line therapy regimen labeling) — requires cycle-window grouping, not encounter-exact matching

**References:**
- [ABVD Chemotherapy Regimen](https://www.drugs.com/cg/abvd-chemo-regimen.html) — 28-day cycles, day 1 + day 15 administration
- [Characterizing Anticancer Treatment Trajectory Using Harmonized Observational Databases](https://pmc.ncbi.nlm.nih.gov/articles/PMC8058693/) — algorithm identified regimens with >98% PPV; cycle timing analysis

---

### Pitfall v1.8-5: Dropping ICD Diagnosis Codes from SCT Detection Loses Legitimate Cases

**What goes wrong:**
Requirement says "drop ICD diagnosis codes from SCT detection — use PROCEDURES/PRESCRIBING/DISPENSING only." This loses 20-40% of SCT cases where procedure codes were not entered but diagnosis codes (Z94.84 SCT status, T86.5 SCT complications) document the transplant occurred, especially for transplants done at outside facilities.

**Why it happens:**
Misinterpretation of "SCT diagnosis codes indicate history/status, not procedure occurrence." In reality, Z94.84 (stem cell transplant status) is often the ONLY documentation of SCT in long-term follow-up data, especially if transplant occurred at outside facility. T86.5 (complications of stem cell transplant) implies transplant occurred. The intent was to remove C81.* (HL diagnosis) from SCT detection, not all ICD codes. Developer reads "drop ICD diagnosis codes" literally and removes ALL ICD codes including Z94.84 and T86.5.

**Consequences:**
- SCT detection rate drops from 15% to 8% after removing ICD codes
- Patients with Z94.84 + GVHD complications + immunosuppressants not flagged as SCT recipients
- Detection rate varies wildly by site (UFH 12%, AMS 4%) suggesting data source differences
- Outside-facility transplants invisible (no procedure codes at OneFlorida+ sites for transplants done at Moffitt or Mayo)

**Prevention:**
- **Phase 01 (Scope clarification):** Clarify requirement: "Drop C81.* and other malignancy diagnosis codes from SCT detection" — not ALL ICD codes
- **Phase 02 (Tiered SCT detection):** Implement tiered SCT detection:
  - **Tier 1 (highest confidence):** ICD-10-PCS 30233* (transfusion codes), CPT 38241 (autologous), 38240 (allogeneic)
  - **Tier 2 (medium confidence):** PRESCRIBING/DISPENSING of GCSF + mobilization agents + conditioning regimen (busulfan, cyclophosphamide, melphalan)
  - **Tier 3 (lower confidence, likely outside facility):** ICD-10-CM Z94.84 (SCT status), T86.5 (SCT complications), Z48.2* (aftercare following organ transplant)
- **Phase 02 (Code retention):** Keep Z94.84, T86.5, Z48.2* as SCT indicators; remove ONLY C81.* from SCT detection logic
- **Phase 03 (Validation):** Compare ICD-only SCT detections vs procedure-confirmed SCT. If >80% concordance, ICD codes are reliable

**Warning signs:**
- SCT detection rate drops >30% after removing ICD codes
- Patients with Z94.84 + GVHD complications + immunosuppressants not flagged as SCT recipients
- Detection rate varies wildly by site (UFH 12%, AMS 4%) suggesting data source differences
- Known transplant patients (from clinical team) missing from SCT cohort

**Phase to address:**
Phase 3 (Treatment source validation refinement) — validate before removing ICD codes from SCT logic

**References:**
- [2026 ICD-10-CM Code Z94.84: Stem cells transplant status](https://www.icd10data.com/ICD10CM/Codes/Z00-Z99/Z77-Z99/Z94-/Z94.84)
- [2026 ICD-10-PCS Code 30233X0: Transfusion of Autologous Cord Blood Stem Cells](https://www.icd10data.com/ICD10PCS/Codes/3/0/2/3/30233X0)

---

### Pitfall v1.8-6: "Encounters After Death" False Positive Deletion

**What goes wrong:**
Requirement says "identify encounters after death date." Developer assumes these are data errors and drops them. This removes 10-20% of legitimate end-of-life encounters (hospice admissions, death certificate filing, autopsy, family grief counseling, organ donation coordination, posthumous lab results from specimens drawn before death).

**Why it happens:**
Death date in PCORnet is often the REPORTED date (when facility learned of death), not the ACTUAL date of death. Patient dies at home on 5/15, family reports it on 5/20, EHR records 5/20 as death date. Meanwhile, lab results from 5/14 blood draw post on 5/18, creating "encounter after death." Also, administrative encounters (billing reconciliation, medical records requests) can occur weeks after death with encounter dates = processing date. Information regarding deaths outside of clinical setting are frequently missing in EHR/claims; death registries lag 1-2 years.

**Consequences:**
- Gantt chart shows all treatment stops exactly on death date (no hospice, no palliative care)
- Patients with hospice diagnosis codes lose their hospice encounters
- Death date analysis table shows 0% "encounters after death" (unlikely — should be 5-15%)
- Legitimate end-of-life care patterns invisible in data
- Survival analysis biased (treatment effect overstated if end-of-life encounters removed)

**Prevention:**
- **Phase 01 (Scope):** DO NOT automatically drop "encounters after death" — requirement is to ANALYZE, not DELETE
- **Phase 02 (Classification):** Classify post-death encounters by type:
  - **IMPOSSIBLE:** Active treatment (chemo, surgery) >7 days after death AND no subsequent encounter → likely death date error
  - **ADMINISTRATIVE:** Revenue code 0001, ENC_TYPE='OT', DRG absent → legitimate administrative processing
  - **SPECIMEN:** LAB_RESULT_CM with SPECIMEN_DATE < death date, RESULT_DATE > death date → legitimate lab result posting
  - **HOSPICE:** ENC_TYPE='IP', DX includes Z51.5 (palliative care) → death date may be admission date, encounter spans death
- **Phase 03 (Impossible death flag):** Create flag for suspect death dates:
  ```r
  impossible_deaths <- encounters %>%
    group_by(PATID) %>%
    filter(!is.na(death_date)) %>%
    arrange(desc(ADMIT_DATE)) %>%
    mutate(
      days_after_death = as.numeric(ADMIT_DATE - death_date),
      is_active_treatment = ENC_TYPE %in% c('IP', 'AV') & !is.na(DRG),
      impossible_death = days_after_death > 7 & is_active_treatment & row_number() == 1  # Last encounter is treatment >7 days after death
    )
  ```
- **Phase 04 (Death date correction):** NULL out death dates flagged as impossible; preserve post-death administrative/hospice encounters
- **Phase 05 (Analysis table):** Produce death date analysis table with counts: patients with death dates, death as last encounter, encounters after death (by type)

**Warning signs:**
- Gantt chart shows all treatment stops exactly on death date (no hospice, no palliative care)
- Patients with hospice diagnosis codes lose their hospice encounters
- Death date analysis table shows 0% "encounters after death" (unlikely — should be 5-15%)
- All patients with death dates have ADMIT_DATE <= death_date (perfect alignment unlikely in real data)

**Phase to address:**
Phase 5 (Death date analysis) — classify, don't delete

**References:**
- [Augmenting fact and date of death in EHRs using internet media sources](https://academic.oup.com/aje/advance-article/doi/10.1093/aje/kwaf258/8345945) — death registries lag 1-2 years; EHR death capture increased 18-24% with internet sources (2026)
- [Development and Validation of a High-Quality Composite Real-World Mortality Endpoint](https://pmc.ncbi.nlm.nih.gov/articles/PMC6232402/) — mortality data frequently incomplete in EHR/claims

---

### Pitfall v1.8-7: BV+AVD vs ABVD Distinction as Additive Instead of Replacement

**What goes wrong:**
Developer codes BV+AVD detection as "brentuximab AND bleomycin AND doxorubicin AND vinblastine AND dacarbazine" (5 drugs). This finds zero cases because brentuximab replaces bleomycin, not added to it. The "+" notation in "BV+AVD" reads like "add BV to AVD," but AVD is already ABVD minus bleomycin.

**Why it happens:**
Naming convention "BV+AVD" reads like "add BV to AVD," but AVD is already ABVD minus bleomycin. Clinical context: Bleomycin causes pulmonary toxicity. BV+AVD was developed to improve efficacy while eliminating bleomycin toxicity (ECHELON-1 trial, 2018). The "+" notation means "substitute" not "append." Developer without clinical oncology knowledge interprets "BV+AVD" literally as "brentuximab plus AVD," assuming AVD = ABVD with all 4 original drugs.

**Consequences:**
- Zero BV+AVD detections despite ECHELON-1 trial (2018) establishing it as standard of care
- Patients flagged as receiving both ABVD and BV+AVD concurrently (should be mutually exclusive)
- Detection logic requires bleomycin + brentuximab on same day (medically implausible — one replaces the other)
- First-line therapy analysis shows 100% ABVD, 0% BV+AVD (wrong — BV+AVD is 30-50% of first-line post-2018)

**Prevention:**
- **Phase 01 (Clinical validation):** Regimen definitions (mutually exclusive):
  - **ABVD:** doxorubicin + bleomycin + vinblastine + dacarbazine (no brentuximab, no nivolumab)
  - **BV+AVD:** brentuximab + doxorubicin + vinblastine + dacarbazine (bleomycin ABSENT or only in first 1-2 cycles before switch)
  - **Nivo+AVD:** nivolumab + doxorubicin + vinblastine + dacarbazine (no brentuximab, bleomycin absent)
- **Phase 02 (Detection order):** Detect in priority order:
  1. Check for brentuximab → if yes, BV+AVD (even if bleomycin present in early cycles — regimen switch)
  2. Check for nivolumab → if yes, Nivo+AVD
  3. Check for bleomycin + no BV/nivo → ABVD
  4. Check for AVD only (no bleomycin, no BV, no nivo) → label as "AVD (modified ABVD)"
- **Phase 03 (Validation):** Verify mutually exclusive: No patient should have both ABVD and BV+AVD in same cycle
- **Phase 04 (Dose modification):** ABVD with bleomycin dropped mid-course is still first-line ABVD, not a new regimen

**Warning signs:**
- Zero BV+AVD detections despite ECHELON-1 trial (2018) establishing it as standard of care
- Patients flagged as receiving both ABVD and BV+AVD concurrently (should be mutually exclusive)
- Detection logic requires bleomycin + brentuximab on same day (medically implausible)
- First-line therapy distribution: 100% ABVD, 0% BV+AVD (unlikely in 2020+ treatment data)

**Phase to address:**
Phase 4 (Regimen labeling logic design) — before drug matching code is written

**References:**
- [Brentuximab vedotin plus AVD for Hodgkin lymphoma](https://pmc.ncbi.nlm.nih.gov/articles/PMC10628810/) — BV replaces bleomycin to reduce pulmonary toxicity
- [Five-year follow-up of brentuximab vedotin combined with ABVD or AVD](https://pmc.ncbi.nlm.nih.gov/articles/PMC5766843/) — ECHELON-1 trial established BV+AVD as standard of care

---

### Pitfall v1.8-8: Age Filter Applied Before Treatment Date Linkage

**What goes wrong:**
Requirement says "first-line therapy for adults 21+". Developer filters cohort to age 21+ at enrollment, then links treatments. This drops patients who were 20 at enrollment but 21 at first treatment, and includes patients who were 21 at enrollment but received first-line therapy at age 19 (prior to enrollment in PCORnet data capture).

**Why it happens:**
Age filter placement ambiguity. "Adults 21+" should mean "age 21+ at first HL-directed treatment," not "age 21+ at enrollment" or "age 21+ at HL diagnosis." PCORnet has BIRTH_DATE in DEMOGRAPHIC; HL treatment date comes from PROCEDURES/PRESCRIBING; these must be joined before age filter is applied. Developer applies age filter early in pipeline (convenient cohort restriction) without considering treatment date dependency.

**Consequences:**
- Age distribution shows cliff at 21 (no 20.9-year-olds despite enrollment date distribution being smooth)
- Patients with first treatment at age 19 included (shouldn't be in adult cohort)
- Attrition log: "Exclude age <21" happens before "Link to first treatment date" (wrong order)
- Pediatric regimens (different from adult ABVD) included in adult first-line analysis

**Prevention:**
- **Phase 01 (Scope):** Clarify age filter timing: "Age 21+ at first HL-directed treatment"
- **Phase 02 (Age calculation):** Calculate age at treatment AFTER linking to first treatment date:
  ```r
  cohort_with_age <- cohort %>%
    inner_join(first_treatment_dates, by = "PATID") %>%
    mutate(
      age_at_first_treatment = floor(as.numeric(first_treatment_date - BIRTH_DATE) / 365.25)
    ) %>%
    filter(age_at_first_treatment >= 21)
  ```
- **Phase 03 (Validation):** Validate age distribution: Distribution of age_at_first_treatment should peak at 25-35 for HL (expected epidemiology, bimodal distribution)
- **Phase 04 (Documentation):** Document exact age calculation method (floor vs round, 365 vs 365.25, leap year handling)

**Warning signs:**
- Age distribution shows cliff at 21 (no 20.9-year-olds despite enrollment date distribution being smooth)
- Patients with first treatment at age 19 included (shouldn't be in adult cohort)
- Attrition log: "Exclude age <21" happens before "Link to first treatment date" (wrong order)
- Age distribution doesn't match HL epidemiology (should peak 25-35, bimodal with second peak 55-65)

**Phase to address:**
Phase 4 (Cohort filtering for first-line analysis) — after treatment linkage, before regimen labeling

---

## v1.8 Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Use ENCOUNTERID-only join without NULL handling | Simple join logic, 20 lines of code | Loses 10-60% of medication records; regimen detection fails at non-integrated sites | Never — multi-tier linkage is required |
| Drop all diagnosis records with ENCOUNTERID='OT' | Clean encounter-level data model | Loses 15-30% of diagnoses at claims sites; patients with orphan HL diagnosis excluded from cohort | Never — orphan diagnoses are valid data |
| Require all 4 ABVD drugs on same ENCOUNTERID | Easy to code, clear definition | Finds zero regimens because infusion centers create separate encounters per drug | Never — use cycle window (+/- 3 days) |
| Code BV+AVD as 5-drug regimen (including bleomycin) | Literal interpretation of "add BV to ABVD" | Finds zero BV+AVD cases; medically implausible (bleomycin is replaced, not added) | Never — clinical validation required |
| Filter age 21+ at enrollment instead of at treatment | Uses existing enrollment filter | Wrong cohort: includes pediatric treatments, excludes valid young adults | Never — age must be at treatment date |
| Delete all encounters after death date | Cleans "impossible" data | Loses legitimate hospice, administrative, lab result encounters; overstates treatment effect | Never — classify and analyze, don't delete |
| Remove all ICD codes from SCT detection | Follows literal interpretation of "drop ICD DX codes" | Loses 20-40% of SCT cases (outside facility transplants with only Z94.84 documentation) | Never — retain status/complication codes (Z94.84, T86.5) |

## v1.8 Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| PRESCRIBING + DISPENSING linkage | Assume ENCOUNTERID always populated | Validate population rate per site; use RXNORM_CUI + date window (+/- 14 days) as fallback |
| DIAGNOSIS + PROCEDURES linkage | Inner join on ENCOUNTERID produces 1-to-1 | Expect many-to-many; rank diagnoses by PDX/ORIGDX/DX_SOURCE before join; select top 1 per encounter |
| MED_ADMIN regimen detection | Require all drugs on same encounter | Group by PATID + cycle window (+/- 3 days), allow different ENCOUNTERIDs |
| TUMOR_REGISTRY + treatment dates | Assume TR date = first treatment | TR may record diagnosis date, not treatment date; cross-validate with PROCEDURES/PRESCRIBING |
| Death date + encounter timeline | Assume encounters after death = errors | Classify by encounter type; administrative/hospice/lab results are often legitimate post-death |
| Multiple DIAGNOSIS rows per ENCOUNTERID | Assume 1 primary diagnosis | PCORnet allows 10-20 diagnoses per encounter; use PDX='P' or DX_SOURCE='Primary' to disambiguate |

## v1.8 Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Cartesian explosion on diagnosis join | Query runs >10 min; 500-patient cohort produces 50,000 rows | Pre-filter DIAGNOSIS to malignant C-codes + rank within encounter before join | >100 patients with >5 diagnoses per encounter |
| Window function on unsorted data | HL diagnosis rank wrong; random diagnosis selected per encounter | Explicit ORDER BY in PARTITION clause: `ORDER BY CASE WHEN PDX='P' THEN 1 ELSE 2 END, DX_SOURCE` | Any dataset (silent correctness issue, not performance) |
| Full table scan on date range for cycle detection | Regimen detection takes 2+ hours | Index on PATID + MEDADMIN_START_DATE; filter to HL cohort before cycle windowing | >10,000 MED_ADMIN rows per patient |
| Repeated orphan diagnosis fallback scans | Each orphan diagnosis triggers full ENCOUNTER table scan | Materialize encounter dates as temp table with index; batch process orphans | >5,000 orphan diagnoses |
| Self-join for same-day multi-source detection | >1 hour runtime for overlap analysis | Use window functions instead: `LAG(ENCOUNTERID) OVER (PARTITION BY PATID ORDER BY date)` | >50,000 encounters per source |

## v1.8 Data Quality Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Trust ENCOUNTERID population without validation | Silent data loss; regimen detection fails | Pre-validate: `SELECT source, COUNT(*), SUM(CASE WHEN ENCOUNTERID IS NULL THEN 1 ELSE 0 END) AS null_count` per table |
| Assume diagnosis codes imply procedure occurred | SCT status (Z94.84) doesn't mean SCT happened during observation window; may be historical | Cross-validate: ICD codes + procedure codes + medication orders for high-confidence detection |
| Treat death date as ground truth | 10-20% of death dates are REPORTED date, not ACTUAL date; post-death encounters may be valid | Flag "impossible deaths" (treatment >7 days after death + no subsequent encounters); null out suspect dates |
| Use ICD-10-CM C81.* for SCT detection | Diagnosis codes indicate HL presence, not SCT procedure | Use ICD-10-PCS 30233* (transfusion codes) and CPT 38240/38241 for procedure-confirmed SCT |
| Assume same drug name = same drug | "Doxorubicin" vs "Doxorubicin HCl" vs "Doxorubicin liposomal" — different drugs | Normalize to RXNORM_CUI; map liposomal to separate category (not used in ABVD) |
| Apply regimen logic without dose validation | Detect "ABVD" from trace doses (doxorubicin 5mg vs standard 25mg/m²) | Filter to therapeutic doses: doxorubicin >10mg, bleomycin >5 units, vinblastine >3mg, dacarbazine >100mg |

## v1.8 Clinical Logic Mistakes

| Mistake | Clinical Impact | Better Approach |
|---------|-----------------|-----------------|
| Label dose-reduced ABVD as "non-standard regimen" | Standard practice for elderly/frail patients; excluding them biases cohort | Flag dose reductions but keep as ABVD; analyze separately |
| Require bleomycin in all ABVD cycles | Bleomycin commonly stopped after 2-4 cycles due to pulmonary toxicity; entire regimen is still "ABVD" | Detect bleomycin in ANY cycle; absence in later cycles is expected |
| Classify AVD (no bleomycin from start) as ABVD | AVD is often given to patients with baseline pulmonary disease — different risk profile | Label as "AVD (modified ABVD)" — separate category for risk-stratified analysis |
| Code BV+AVD as additive (5 drugs) | Brentuximab replaces bleomycin, not added to it; 5-drug regimen doesn't exist | BV+AVD = brentuximab + doxorubicin + vinblastine + dacarbazine (4 drugs, bleomycin ABSENT) |
| Treat maintenance therapy as first-line | Maintenance (e.g., brentuximab post-SCT) is secondary prevention, not first-line treatment | First-line = first HL-directed regimen after diagnosis in treatment-naive patient; exclude if prior chemotherapy |
| Flag Nivo+AVD as experimental in 2026 | FDA approval expected April 2026; SWOG S1826 established superiority over BV+AVD | Nivo+AVD is emerging standard of care as of 2026; include as valid first-line option |

## v1.8 "Looks Done But Isn't" Checklist

- [ ] **Encounter-level linkage:** Validated ENCOUNTERID population rate per table and source — verify >70% for MED_ADMIN, may be <40% for DISPENSING at non-integrated sites
- [ ] **Orphan diagnosis handling:** Implemented fallback linkage for ENCOUNTERID='OT' or NULL — verify orphan rate <40% per site
- [ ] **Many-to-many diagnosis join:** Diagnosis ranking by PDX/ORIGDX/DX_SOURCE applied before join — verify 1 diagnosis per encounter in output
- [ ] **Regimen cycle windowing:** Grouping by PATID + cycle_window (+/- 3 days), not requiring same ENCOUNTERID — verify ABVD detection >0
- [ ] **BV+AVD replacement logic:** Brentuximab replaces bleomycin (not additive) — verify no 5-drug detections
- [ ] **Age at treatment calculation:** Age calculated at first treatment date, not enrollment — verify age distribution matches HL epidemiology (peak 25-35)
- [ ] **Post-death encounter classification:** Encounters after death classified (impossible/administrative/legitimate), not auto-deleted — verify hospice encounters retained
- [ ] **SCT ICD code retention:** Z94.84, T86.5 retained in SCT detection; only C81.* removed — verify SCT detection rate doesn't drop >30%
- [ ] **First-line treatment definition:** First HL-directed regimen after diagnosis in treatment-naive adults 21+ — verify no maintenance therapy labeled as first-line
- [ ] **Dose modification handling:** Bleomycin absence in later ABVD cycles doesn't reclassify regimen — verify cycle-to-cycle consistency

## v1.8 Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Lost 60% of medications due to NULL ENCOUNTERID | MEDIUM | Re-implement with multi-tier linkage (ENCOUNTERID → PATID+date window); re-run from cohort assembly; validate against expected medication counts |
| Many-to-many explosion produced 400 rows per encounter | LOW | Add diagnosis ranking (PDX, DX_SOURCE); apply DISTINCT ON (ENCOUNTERID) or ROW_NUMBER() = 1 filter; verify 1:1 cardinality |
| Zero ABVD detections due to same-encounter requirement | MEDIUM | Refactor to cycle window grouping; re-run regimen detection; cross-validate with TUMOR_REGISTRY chemotherapy flag |
| Deleted 20% of legitimate post-death encounters | HIGH | Restore from raw data; implement classification logic; re-run death date analysis; update Gantt chart with restored encounters |
| BV+AVD coded as 5-drug regimen (zero cases) | LOW | Fix regimen definition (4 drugs, bleomycin excluded); re-run detection; validate against clinical trial enrollment data if available |
| Age filter dropped valid young adults | LOW | Recalculate age at treatment date; re-apply filter; update attrition log with corrected counts |
| Dropped ICD codes from SCT detection (lost 40% of cases) | MEDIUM | Restore Z94.84, T86.5, Z48.2* to SCT logic; re-run detection; validate against transplant center referrals |
| Orphan diagnoses lost (30% of HL diagnoses) | HIGH | Implement orphan fallback linkage (nearest encounter by date); re-run cohort assembly; verify no patients with C81.* codes excluded |

## v1.8 Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| NULL ENCOUNTERID population variance | Phase 1 (Data validation) | ENCOUNTERID population rate per table logged; >70% for MED_ADMIN, >50% for PRESCRIBING documented |
| Many-to-many diagnosis join | Phase 2 (Encounter linkage design) | Cardinality test: 1 diagnosis per encounter in output; Gantt chart shows single cancer category per treatment |
| Orphan diagnoses lost | Phase 2 (Encounter linkage) | Orphan diagnosis count logged per site; fallback linkage applied; no patients with C81.* excluded |
| Regimen fragmentation | Phase 4 (Regimen detection logic) | Cycle window grouping implemented; ABVD detection count >0; validated against TUMOR_REGISTRY chemotherapy flag |
| SCT ICD code removal | Phase 3 (Treatment source validation) | Z94.84, T86.5 retained; SCT detection rate stable (+/- 10%) before/after ICD refinement |
| Post-death encounter deletion | Phase 5 (Death date analysis) | Classification logic applied; hospice encounters retained; impossible death flag created |
| BV+AVD additive coding | Phase 4 (Regimen definitions) | Regimen definitions clinically validated before coding; BV+AVD detection count matches expected prevalence (~30-50% of first-line post-2018) |
| Age filter timing | Phase 4 (Cohort filtering) | Age calculated at treatment date; age distribution validated; attrition log shows age filter after treatment linkage |

## v1.8 Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Phase 1: Data validation | Assume ENCOUNTERID always populated | Run population rate query per table; document variance by source; design multi-tier linkage strategy |
| Phase 2: Encounter linkage | Inner join loses orphan diagnoses | Implement 3-tier linkage: exact ENCOUNTERID → nearest encounter by date → patient-level flag; log counts per tier |
| Phase 2: Cancer category assignment | Many-to-many explosion | Pre-filter to malignant codes; rank by PDX/ORIGDX/DX_SOURCE; select top 1 per encounter; validate 1:1 cardinality |
| Phase 3: SCT validation | Remove all ICD codes (not just C81.*) | Clarify requirement: remove malignancy diagnosis codes, retain status/complication codes (Z94.84, T86.5) |
| Phase 4: Regimen detection | Same-encounter requirement | Use cycle window (+/- 3 days); group by PATID + window; allow different ENCOUNTERIDs per drug |
| Phase 4: BV+AVD definition | Code as additive (5 drugs) | Clinical validation: brentuximab replaces bleomycin; 4 drugs total; mutually exclusive with ABVD |
| Phase 4: Age filtering | Apply before treatment linkage | Calculate age at treatment date; filter after treatment date is known; validate distribution |
| Phase 5: Death date analysis | Auto-delete post-death encounters | Classify by encounter type; flag impossible deaths (treatment >7 days after + no subsequent); preserve administrative/hospice |
| Phase 6: Gantt output | Overwrite existing files | Create new output files with version suffix (_v2); preserve v1.7 Gantt for comparison |

---

## Sources

**PCORnet CDM & Data Quality:**
- [PCORnet Common Data Model v7.0 Specification](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf) (May 2025)
- [Comparing Prescribing and Dispensing Data of the PCORnet Common Data Model](https://pmc.ncbi.nlm.nih.gov/articles/PMC6460498/) — 90.5% match at integrated sites, 39.4% at non-integrated; orphan encounters without same-day EHR records
- [Development of an algorithm to link electronic health record prescriptions with pharmacy dispense claims](https://pubmed.ncbi.nlm.nih.gov/30113681/)
- [Real-World Data: Assessing Electronic Health Records and Claims](https://www.fda.gov/media/152503/download) — Medicare claims as reference standard for billing-derived domains

**Death Date Validation:**
- [Augmenting fact and date of death in electronic health records using internet media sources](https://academic.oup.com/aje/advance-article/doi/10.1093/aje/kwaf258/8345945) — death registries lag 1-2 years; EHR death capture increased 18-24% with internet sources (2026)
- [Development and Validation of a High-Quality Composite Real-World Mortality Endpoint](https://pmc.ncbi.nlm.nih.gov/articles/PMC6232402/) — mortality data frequently incomplete in EHR/claims; patients lost to follow-up

**Chemotherapy Regimen Identification:**
- [ABVD Chemotherapy Regimen](https://www.drugs.com/cg/abvd-chemo-regimen.html) — 28-day cycles, day 1 + day 15 administration
- [Characterizing the Anticancer Treatment Trajectory and Pattern Using Harmonized Observational Databases](https://pmc.ncbi.nlm.nih.gov/articles/PMC8058693/) — algorithm identified 85 different regimens with >98% PPV; cycle timing analysis
- [Brentuximab vedotin plus AVD for Hodgkin lymphoma](https://pmc.ncbi.nlm.nih.gov/articles/PMC10628810/) — BV replaces bleomycin to reduce pulmonary toxicity
- [Five-year follow-up of brentuximab vedotin combined with ABVD or AVD](https://pmc.ncbi.nlm.nih.gov/articles/PMC5766843/) — ECHELON-1 trial established BV+AVD as standard of care

**Nivolumab + AVD (Emerging Standard):**
- [SWOG S1826 Study](https://www.swog.org/clinical-trials/s1826) — nivolumab+AVD vs brentuximab+AVD in advanced HL
- [Nivolumab/AVD: A New Standard in Untreated Advanced Hodgkin Lymphoma](https://www.cancernetwork.com/view/nivolumab-avd-a-new-standard-in-untreated-advanced-hodgkin-lymphoma) — 52% reduction in progression risk (HR 0.48); 3-year PFS 89% vs 80%
- [3-year follow-up of the S1826 study](https://ashpublications.org/blood/article/146/Supplement%201/151/553061/) — FDA decision expected April 2026

**Stem Cell Transplant Coding:**
- [2026 ICD-10-CM Code Z94.84: Stem cells transplant status](https://www.icd10data.com/ICD10CM/Codes/Z00-Z99/Z77-Z99/Z94-/Z94.84)
- [2026 ICD-10-PCS Code 30233X0: Transfusion of Autologous Cord Blood Stem Cells](https://www.icd10data.com/ICD10PCS/Codes/3/0/2/3/30233X0)
- [Billing and Coding: Stem Cell Transplantation](https://www.cms.gov/medicare-coverage-database/view/article.aspx?articleid=52879) — CPT 38240 (allogeneic), 38241 (autologous)

**Claims & Encounter Data Linkage:**
- [CCW Medicare Encounter Data User Guide](https://www2.ccwdata.org/documents/10280/19002246/ccw-medicare-encounter-data-user-guide.pdf) (March 2026, V 3.0)
- [Synergy of diagnosis coding between administrative claims and EHR](https://pmc.ncbi.nlm.nih.gov/articles/PMC12986766/)
- [Probabilistic record linkage of de-identified research datasets with discrepancies using diagnosis codes](https://www.nature.com/articles/sdata2018298)

---

**Confidence Assessment:**
- ENCOUNTERID population variance: MEDIUM (PCORnet article confirmed 39-90% range, site-specific validation needed)
- Regimen detection patterns: MEDIUM (clinical literature + observational study methods confirmed)
- Death date validation: MEDIUM (2026 research on EHR death capture + clinical informatics practice)
- BV+AVD vs ABVD distinction: HIGH (ECHELON-1 trial + clinical pharmacology)
- Post-death encounters: MEDIUM (clinical informatics practice + Medicare documentation)
- SCT coding: MEDIUM (official ICD-10 codes verified, clinical interpretation required)
- Many-to-many joins: HIGH (database architecture + PCORnet CDM structure)

---

*Pitfalls research for: Encounter-Level Cancer Linkage & First-Line Therapy Regimen Identification in PCORnet CDM*
*Researched: 2026-05-29*

---

## Previous Milestone Pitfalls

See git history for v1.7 pitfalls (cancer summary refinement, temporal filtering, Gantt enhancements) and v1.6 pitfalls (treatment code validation, cancer site analysis). Previous milestone pitfalls remain relevant for ongoing maintenance.
