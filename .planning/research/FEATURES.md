# Feature Research

**Domain:** Episode-Level Cancer Linkage & First-Line Therapy Identification
**Researched:** 2026-05-29
**Confidence:** MEDIUM

## Feature Landscape

### Table Stakes (Users Expect These)

Features clinical researchers assume exist in cancer treatment pipelines. Missing these = pipeline feels incomplete or untrustworthy.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Encounter-specific cancer diagnosis linkage | Encounter-level data needed for episode-specific context; patient-level conflates unrelated diagnoses | MEDIUM | Direct match on ENCOUNTERID, fallback to temporal proximity (closest diagnosis within window); existing pipeline has patient-level join |
| Death date validation | EHR death dates are notoriously incomplete/inaccurate (89% of post-death encounters due to missing death status); impossible dates corrupt survival analysis | MEDIUM | Already implemented in Phase 59 with impossible death exclusion; now extend to analysis table (counts with death dates, death as last encounter, post-death encounters) |
| Treatment episode boundaries | Clinical researchers expect clear start/stop definition for treatment episodes (not continuous streams) | MEDIUM | Need gap threshold (45 days is standard in claims research) or regimen change detection; existing pipeline detects treatment presence but lacks episode boundaries |
| First-line therapy identification | Standard requirement for observational oncology studies; distinguishes initial treatment (prognostic) from salvage therapy | MEDIUM | Requires 60-day "clean period" with no prior chemotherapy (standard in claims research); age restriction 21+ for adult protocols (pediatric vs adult cutoff) |
| Regimen-level classification | Drug-based treatment identification insufficient; clinical meaning requires regimen names (ABVD, BV+AVD, etc.) | HIGH | Multi-agent temporal windowing (28-day cycle for HL regimens); agent-based matching with dropped-agent tolerance (ABVD→AVD still first-line per RATHL trial) |

### Differentiators (Competitive Advantage)

Features that set this pipeline apart from typical cancer registry or claims-only approaches.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Hybrid encounter-diagnosis linkage strategy | Direct ENCOUNTERID match preferred, temporal fallback ensures coverage when encounter link missing | MEDIUM | Most pipelines do one or the other; hybrid approach maximizes accuracy + coverage; fallback window needs specification (7/30/60 days?) |
| Second cancer confirmation with temporal separation | 7-day-apart rule prevents duplicate diagnoses from administrative re-coding; detects true second primaries | LOW | Already implemented in Phase 51 for cancer site confirmation; extends pattern to encounter-level HL flag |
| Granular treatment source validation | Drop ICD diagnosis codes from SCT detection (diagnosis = history/status, not procedure occurrence) | LOW | Tightens specificity by restricting to procedural/dispensing evidence (PROCEDURES, PRESCRIBING, DISPENSING only); reduces false positives |
| NDC/RxNorm-based agent identification | Already implemented in Phase 40; enables granular regimen matching beyond billing codes | MEDIUM | Existing API infrastructure + keyword matching; extends to multi-agent temporal windows for regimen classification |
| Regimen-specific timing rules | BV+AVD post-2019 (FDA approval 3/20/2018), Nivo+AVD post-2024 (FDA approval pending 4/8/2026) | LOW | Prevents anachronistic regimen identification in historical data; aligns with real-world treatment availability |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems in clinical research pipelines.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Exact agent match for regimen classification | Precision feels safer than tolerance | Bleomycin routinely dropped from ABVD per RATHL trial (PET-2 negative) or toxicity; exact match misclassifies 27.5% of real-world ABVD as "non-regimen" | Allow dropped agents (ABVD→AVD), forbid added agents (ABVD+X is not ABVD) |
| Include ICD diagnosis codes for procedure detection | More data sources = better coverage | ICD DX codes indicate history/status, not procedure occurrence; including creates false positives (patient with "hx of SCT" coded as SCT recipient even if procedure elsewhere/never) | Restrict to procedural/dispensing tables (PROCEDURES, PRESCRIBING, DISPENSING) for authoritative evidence |
| Global cancer flag on patient | Simpler than encounter-level linkage | Conflates unrelated diagnoses across time; patient with HL in 2015 + breast cancer in 2022 has every encounter flagged HL+breast; episode-specific context lost | Encounter-level linkage with temporal proximity fallback |
| Pediatric + adult protocols combined | Larger sample size for analysis | Treatment protocols diverge significantly (pediatric reduces cumulative chemo/radiation to limit late toxicity; adult prioritizes cure rate); combining conflates biologically distinct populations | Restrict first-line regimen analysis to adults 21+ (adult protocol population) |
| Flexible cycle windows (any timeframe) | Accommodates scheduling delays | Without standardized window, regimen matching becomes arbitrary; 28-day ABVD cycle with agents delivered across 90 days likely represents multiple cycles or treatment interruptions | Use protocol-defined cycle window (28 days for HL regimens) with small tolerance (±3 days per clinical trial standards) |

## Feature Dependencies

```
[Encounter-level cancer linkage]
    └──requires──> [ENCOUNTERID in DIAGNOSIS table]
                       └──fallback──> [Temporal proximity matching (date-based)]

[First-line therapy identification]
    └──requires──> [Treatment episode boundaries (gap threshold)]
    └──requires──> [60-day clean period detection]
    └──requires──> [Age filtering (21+ for adult protocols)]

[Regimen classification (ABVD, BV+AVD, Nivo+AVD)]
    └──requires──> [NDC/RxNorm agent identification (Phase 40 existing)]
    └──requires──> [28-day cycle window matching]
    └──requires──> [Dropped-agent tolerance logic]
    └──requires──> [Temporal availability rules (BV+AVD post-2019, Nivo+AVD post-2024)]

[Death date analysis table]
    └──requires──> [Death date validation (Phase 59 existing)]
    └──enhances──> [Encounter-level linkage (identifies impossible post-death encounters)]

[Tightened SCT detection]
    └──modifies──> [Existing treatment detection (Phase 9)]
    └──removes──> [DIAGNOSIS table ICD codes for SCT]
```

### Dependency Notes

- **Encounter-level cancer linkage requires ENCOUNTERID:** PCORnet DIAGNOSIS table includes ENCOUNTERID (nullable); direct match is highest-confidence linkage, but temporal fallback needed for ~10-30% of diagnoses with missing encounter link (based on typical PCORnet data quality).
- **First-line therapy requires episode boundaries:** Cannot identify "first" line without defining where one episode ends and next begins; 45-day gap is standard in claims research (Treatment of costs associated with adverse events: assessment suggests this threshold).
- **Regimen classification requires NDC/RxNorm agent identification:** Phase 40 infrastructure already maps drug codes to generic names via API + keyword matching; extends to multi-agent temporal matching for regimen patterns.
- **Temporal availability rules prevent anachronistic regimen IDs:** BV+AVD FDA approval 3/20/2018 for stage III/IV cHL; any BV+AVD identification before 2019 is likely miscoding (allow 1-year lag for adoption). Nivo+AVD approval pending 4/8/2026 (PDUFA date), so post-2024 threshold conservative but avoids pre-approval off-label confusion.
- **Death date analysis enhances encounter linkage:** Post-death encounters signal either missing death dates (most common: 89% of post-death activity due to incomplete EHR death status) or incorrect death dates; analysis table quantifies data quality for cohort.

## MVP Definition

### Launch With (v1.8)

Minimum viable product for episode-level cancer linkage and first-line therapy identification.

- [x] **Encounter-level cancer linkage** — Direct ENCOUNTERID match with temporal proximity fallback; HL flag on encounter, not patient (replaces patient-level join from v1.7)
- [x] **Second cancer confirmation with 7-day separation** — Extends Phase 51 pattern to encounter-level HL flag; prevents duplicate diagnoses from re-coding
- [x] **Death date analysis table** — Counts: patients with death dates, death as last encounter, post-death encounters; quantifies data quality for cohort
- [x] **Tightened SCT detection** — Drop ICD DIAGNOSIS codes, restrict to PROCEDURES/PRESCRIBING/DISPENSING (procedural evidence only)
- [x] **First-line therapy identification for adults 21+** — 60-day clean period detection; age filter to adult protocol population
- [x] **Regimen classification (ABVD, BV+AVD, Nivo+AVD)** — 28-day cycle window matching with dropped-agent tolerance (ABVD→AVD allowed); temporal availability rules (BV+AVD post-2019, Nivo+AVD post-2024)

### Add After Validation (v1.x)

Features to add once core encounter-level linkage and regimen ID validated.

- [ ] **Treatment episode boundary formalization** — Explicit start/stop dates with 45-day gap threshold; currently implicit in first-line logic but not generalized
- [ ] **Multi-line therapy sequencing** — First-line → second-line → third-line progression tracking; requires episode boundaries + regimen change detection
- [ ] **Regimen expansion to other HL protocols** — Stanford V, BEACOPP, escalated BEACOPP (not in milestone scope but logical extension)
- [ ] **Pediatric protocol regimen identification** — Age <21 cohort with pediatric-specific regimens (dose-reduced protocols); requires separate validation
- [ ] **Treatment response integration** — Link PET scan results (Phase 10 surveillance modality) to regimen classification for response-adapted pathway analysis (e.g., RATHL bleomycin drop logic)

### Future Consideration (v2+)

Features to defer until episode-level linkage patterns established.

- [ ] **Cross-site cancer correlation** — For patients with multiple cancer sites, analyze temporal relationship + treatment overlap; requires robust encounter-level linkage first
- [ ] **Salvage regimen classification** — Second-line+ regimens (ICE, DHAP, GDP, brentuximab monotherapy); defer until first-line validated
- [ ] **Treatment intensity scoring** — Cumulative dose metrics for anthracyclines, alkylators (late toxicity analysis); requires complete episode boundaries
- [ ] **Payer x regimen interaction analysis** — Does payer type correlate with specific first-line regimens (BV+AVD vs ABVD)?; deferred per PROJECT.md out of scope

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Encounter-level cancer linkage | HIGH (episode-specific context essential) | MEDIUM (ENCOUNTERID match + temporal fallback) | P1 |
| Death date analysis table | HIGH (data quality transparency) | LOW (extends Phase 59 validation) | P1 |
| Tightened SCT detection | MEDIUM (specificity improvement) | LOW (remove DIAGNOSIS table from existing logic) | P1 |
| First-line therapy ID (adults 21+) | HIGH (standard observational oncology requirement) | MEDIUM (60-day clean period + age filter) | P1 |
| Regimen classification (3 regimens) | HIGH (clinical interpretability) | HIGH (28-day cycle window + multi-agent matching + dropped-agent logic) | P1 |
| Treatment episode boundaries | MEDIUM (needed for multi-line sequencing) | MEDIUM (45-day gap threshold formalization) | P2 |
| Multi-line therapy sequencing | MEDIUM (salvage therapy analysis) | HIGH (episode boundaries + regimen change detection) | P2 |
| Regimen expansion (Stanford V, BEACOPP) | LOW (ABVD, BV+AVD, Nivo+AVD cover most advanced HL) | MEDIUM (repeat multi-agent matching for new regimens) | P2 |
| Pediatric protocol regimen ID | LOW (adult protocols are primary focus) | MEDIUM (age <21 + pediatric-specific regimens) | P3 |
| Treatment response integration | MEDIUM (research value but not core linkage) | HIGH (PET scan result parsing + response-adapted logic) | P3 |
| Salvage regimen classification | LOW (defer until first-line established) | HIGH (second-line+ regimens more variable) | P3 |
| Payer x regimen interaction | LOW (out of scope per PROJECT.md) | MEDIUM (stratified regimen analysis) | P3 |

**Priority key:**
- P1: Must have for v1.8 launch (episode-level linkage + first-line therapy)
- P2: Should have, add in v1.9+ (episode boundaries, multi-line sequencing)
- P3: Nice to have, future consideration v2+ (pediatric, salvage, payer interactions)

## Clinical Research Standards Comparison

| Feature | PCORnet Standard | SEER-Medicare Approach | Our Implementation |
|---------|------------------|------------------------|---------------------|
| Cancer diagnosis linkage | Patient-level via TUMOR_REGISTRY tables | Registry-EHR linkage via PATID + date proximity | Hybrid: ENCOUNTERID direct match → temporal proximity fallback (encounter-specific) |
| Treatment episode definition | Not standardized in CDM | 45-day gap threshold in claims research | 60-day clean period for first-line ID; 45-day gap for episode boundaries (deferred to v1.9) |
| Regimen identification | CPT/HCPCS codes in PROCEDURES | NDC codes in Part D + CPT in claims | NDC/RxNorm API (Phase 40) + 28-day cycle window + multi-agent matching |
| Death date validation | DEATH_DATE in DEMOGRAPHIC table | NDI linkage for gold standard | Phase 59: impossible death exclusion + death date analysis table |
| SCT detection | ICD-10-PCS + CPT codes | Procedure codes only (no ICD DX) | Tightened: PROCEDURES/PRESCRIBING/DISPENSING only (drop ICD DX) |

## Domain-Specific Patterns

### Encounter-Level Cancer Linkage

**Standard approach:** Cancer registries (SEER, state registries) provide patient-level cancer flags; EHR/claims linkage typically at patient level.

**Limitation:** Patient with HL (2015) + breast cancer (2022) has all encounters flagged for both; episode-specific context lost.

**Evidence:** "Low agreement occurs when EHR cancer information originated from encounter diagnoses without being noted on the problem list" (Assessing Cancer History Accuracy in Primary Care EHRs Through Cancer Registry Linkage, PMC8246795). Encounter-level diagnosis data less reliable than formal problem list, but MORE specific to the clinical episode.

**Our approach:** Hybrid linkage (ENCOUNTERID direct match → temporal proximity fallback) provides episode-specific context while maintaining coverage.

### First-Line Therapy Identification

**Standard approach:** 60-day "clean period" with no prior chemotherapy in claims research; identifies treatment-naive patients.

**Evidence:** "Evidence of initiation of a new course of chemotherapy is based on the earliest claim for chemotherapy during the study period that was preceded by a 60-day or longer period without any other claims for chemotherapy" (CanMED-NDC: Assessment of Systemic Breast Cancer Treatment Patterns).

**Age cutoff rationale:** Pediatric vs adult HL protocols diverge significantly. At age 21, patients may receive either protocol depending on treatment center, but adult protocols are standard. "Presently, treatment approaches for pediatric and adult patients are merging, focusing on improving outcomes while reducing late effects in both populations" (Treatment patterns and outcomes in adolescents and young adults with HL, PMC7541154).

**Our approach:** 60-day clean period + age 21+ filter restricts to adult protocol population for regimen matching.

### Regimen Classification

**ABVD (Adriamycin, Bleomycin, Vinblastine, Dacarbazine):**
- Gold standard for advanced HL since 1970s
- 28-day cycle: Day 1 and Day 15 dosing
- **Dropped-agent tolerance critical:** "For patients with advanced HL who have a negative PET scan after 2 cycles (PET-2 negative), Bleomycin can be safely dropped (AVD only) for subsequent cycles. This strategy maintains the same high cure rate (3-year PFS ~85%) but significantly lowers the rate of pulmonary toxicity" (ABVD regimen, multiple sources).
- Real-world data: 27.5% of ABVD patients transition to AVD per RATHL trial or pulmonary toxicity (Los Angeles County Hospital Study, 2025).

**BV+AVD (Brentuximab vedotin + Doxorubicin, Vinblastine, Dacarbazine):**
- FDA approval: March 20, 2018 for stage III/IV cHL
- First new first-line regimen in 40 years
- 23% reduction in progression risk vs ABVD (ECHELON-1 trial)
- **Temporal rule:** Exclude pre-2019 (allow 1-year adoption lag after FDA approval)

**Nivo+AVD (Nivolumab + Doxorubicin, Vinblastine, Dacarbazine):**
- FDA PDUFA date: April 8, 2026 (pending approval)
- SWOG S1826 trial: 1-year PFS 94% vs 86% for BV+AVD
- Substantially lower peripheral neuropathy (28% vs 54%)
- **Temporal rule:** Post-2024 threshold (conservative, avoids pre-approval confusion)

**28-day cycle window:**
- Standard for HL regimens (ABVD 28-day cycle, BV+AVD 28-day cycle)
- Clinical trial protocols allow ±3 days tolerance: "acceptable for individual chemotherapy doses to be delivered within a 24-hour window before and after the protocol-defined date" (chemotherapy cycle window standards)
- **Our implementation:** 28-day window with small tolerance for scheduling delays (exact tolerance TBD during implementation; 3-7 days reasonable)

### Death Date Validation

**EHR death date quality issues:**
- "Nearly 90% of encounters and appointments occurred because the health system EHR did not record the death" (Patient characteristics and health system encounters of decedents not marked deceased, PMC11521374)
- "Name matching is complicated by misspellings, use of abbreviations, name changes due to marriage or divorce, and use of nicknames" (same source)
- Impossible dates: Encounters after documented death signal either missing death dates (most common) or incorrect death dates

**Phase 59 validation:** Already excludes patients with encounters after death date if death date < HL diagnosis date (impossible sequence).

**Analysis table extension:** Quantifies data quality by counting (1) patients with death dates, (2) death as last encounter (expected pattern), (3) post-death encounters (data quality flag).

### Treatment Source Validation

**ICD diagnosis codes problematic for procedures:**
- Z94.84 (stem cells transplant status) indicates history, not procedure occurrence
- Diagnosis codes appear in EHR for screening orders, care planning, historical context
- **Evidence:** "Cancer diagnostic codes may appear in EHR records because they are associated with orders for screening but are not necessarily indicative of a cancer diagnosis" (Assessing Cancer History Accuracy, PMC8246795)

**Procedural evidence authoritative:**
- CPT codes in PROCEDURES table (38205, 38230 for SCT harvesting/infusion)
- ICD-10-PCS codes for autologous vs allogeneic SCT (30230C0, etc.)
- NDC codes in PRESCRIBING/DISPENSING for conditioning regimens

**Our approach:** Drop DIAGNOSIS table from SCT detection; restrict to PROCEDURES, PRESCRIBING, DISPENSING for authoritative procedural/dispensing evidence.

## Implementation Complexity Notes

### MEDIUM Complexity: Encounter-Level Cancer Linkage
- **Why MEDIUM:** Direct ENCOUNTERID match is straightforward (inner join); temporal proximity fallback requires date windowing logic (closest diagnosis within X days of encounter).
- **Dependency on existing:** Phase 2 ICD code normalization, Phase 51 second cancer confirmation (7-day-apart rule).
- **Fallback window specification:** Needs decision (7/30/60 days?). Shorter = higher specificity, longer = higher coverage. Recommend 30 days (typical encounter-to-coding lag in EHR systems).

### MEDIUM Complexity: First-Line Therapy Identification
- **Why MEDIUM:** Requires 60-day lookback window (check for any prior chemotherapy); age filtering straightforward from DEMOGRAPHIC.
- **Dependency on existing:** Needs treatment episode detection (Phase 9 existing, but no episode boundaries yet).
- **Edge case:** Patient with HL treatment in 2015, recurrence in 2023 with new treatment — second treatment is first-line for recurrence or second-line overall? Define as first-line if 60-day clean period met (treat recurrence as new treatment episode).

### HIGH Complexity: Regimen Classification
- **Why HIGH:** Multi-agent temporal matching across 28-day window requires:
  1. Agent identification from NDC/RxNorm (Phase 40 existing)
  2. Temporal clustering (group agents within 28-day cycle)
  3. Pattern matching (ABVD = Doxorubicin + Bleomycin + Vinblastine + Dacarbazine OR Doxorubicin + Vinblastine + Dacarbazine)
  4. Dropped-agent tolerance logic (allow missing Bleomycin, forbid added agents)
  5. Temporal availability rules (BV+AVD post-2019, Nivo+AVD post-2024)
- **Dependency on existing:** Phase 40 NDC/RxNorm API + keyword matching.
- **Testing critical:** Real-world ABVD patterns vary (full ABVD, AVD, dose reductions); validation against known treatment cohorts needed.

### LOW Complexity: Death Date Analysis Table
- **Why LOW:** Extends Phase 59 validation logic; simple counts (patients with death dates, death as last encounter, post-death encounters).
- **Dependency on existing:** Phase 59 death date validation + impossible death exclusion.
- **Output format:** Summary table (counts + percentages) for data quality reporting.

### LOW Complexity: Tightened SCT Detection
- **Why LOW:** Remove DIAGNOSIS table from existing Phase 9 multi-source detection; restrict to PROCEDURES/PRESCRIBING/DISPENSING.
- **Dependency on existing:** Phase 9 treatment detection logic.
- **Impact:** May reduce SCT detection counts (if some patients only have ICD DX codes, no procedural evidence); this is expected and improves specificity.

## Sources

### Encounter-Level Cancer Linkage
- [SEER-MHOS 2026 Update: Data Linkage](https://oncodaily.com/voices/seer-mhos-2026-437534) — MEDIUM confidence (WebSearch only, press release format)
- [Linkage of UK CPRD with national cancer registry](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6326001/) — HIGH confidence (peer-reviewed methodology)
- [Implementing Cancer Registry Data with PCORnet CDM](https://pmc.ncbi.nlm.nih.gov/articles/PMC11658786/) — HIGH confidence (PCORnet-specific implementation)
- [Population-based registry linkages to improve validity of EHR cancer research](https://pmc.ncbi.nlm.nih.gov/articles/PMC8208472/) — HIGH confidence (EHR-registry linkage best practices)
- [Assessing Cancer History Accuracy in Primary Care EHRs Through Cancer Registry Linkage](https://pmc.ncbi.nlm.nih.gov/articles/PMC8246795/) — HIGH confidence (encounter diagnosis vs problem list accuracy)

### First-Line Therapy Regimen Identification
- [Defining Treatment Regimens and Lines of Therapy Using Real-World Data in Oncology](https://www.tandfonline.com/doi/full/10.2217/fon-2020-1041) — HIGH confidence (peer-reviewed methodology for observational data)
- [CanMED-NDC: Assessment of Systemic Breast Cancer Treatment Patterns](https://academic.oup.com/jncimono/article/2020/55/46/5837301) — HIGH confidence (NDC-based regimen identification in SEER-Medicare)
- [Treatment episode definition in cancer research](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5898735/) — MEDIUM confidence (assessment of costs, 45-day gap threshold)

### Death Date Validation
- [Development and Validation of High-Quality Composite Real-World Mortality Endpoint](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6232402/) — HIGH confidence (peer-reviewed validation methodology)
- [Patient characteristics and health system encounters of decedents not marked deceased in EHR](https://pmc.ncbi.nlm.nih.gov/articles/PMC11521374/) — HIGH confidence (89% post-death encounters finding)
- [Augmenting fact and date of death in EHRs using internet media sources](https://academic.oup.com/aje/advance-article/doi/10.1093/aje/kwaf258/8345945) — HIGH confidence (EHR death date augmentation validation)

### Hodgkin Lymphoma Regimen-Specific
- [ABVD real-world experience from Los Angeles County hospital](https://journals.sagepub.com/doi/10.1177/20503121251365462) — HIGH confidence (2025 real-world data, 27.5% ABVD→AVD transition rate)
- [Real-Life Retrospective Turkey Data of De-Escalation of ABVD to AVD](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12524585/) — MEDIUM confidence (non-US data, different healthcare system)
- [Brentuximab vedotin FDA approval for HL](https://lymphomahub.com/medical-information/brentuximab-vedotin-for-the-treatment-of-hodgkin-lymphoma) — HIGH confidence (FDA approval 3/20/2018 confirmed)
- [FDA Expands Approval of Brentuximab for Hodgkin Lymphoma](https://www.cancer.gov/news-events/cancer-currents-blog/2018/brentuximab-fda-expanded-indication-hodgkin-lymphoma) — HIGH confidence (NCI official announcement)
- [Nivolumab/AVD: A New Standard in Untreated Advanced HL](https://www.cancernetwork.com/view/nivolumab-avd-a-new-standard-in-untreated-advanced-hodgkin-lymphoma) — MEDIUM confidence (PDUFA date 4/8/2026, approval pending)
- [S1826 Data Confirm Nivo-AVD Benefit in HL](https://www.swog.org/news-events/news/2024/10/23/s1826-data-confirm-nivo-avd-benefit-hodgkin-lymphoma) — HIGH confidence (SWOG official trial results)

### Pediatric vs Adult Protocols
- [Treatment patterns and outcomes in adolescents and young adults with HL](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7541154/) — HIGH confidence (IMPACT Cohort Study on age-based protocol differences)
- [Childhood Hodgkin Lymphoma Treatment](https://www.cancer.gov/types/lymphoma/hp/child-hodgkin-treatment-pdq) — HIGH confidence (NCI treatment guidelines)

### Stem Cell Transplant Detection
- [Coding of Bone Marrow Transplants and Stem Cell Transplants](https://libmaneducation.com/coding-of-bone-marrow-transplants-and-stem-cell-transplants/) — MEDIUM confidence (coding education resource)
- [CMS Manual System for SCT codes](https://www.cms.gov/files/document/r11707cp.pdf) — HIGH confidence (official CMS guidance)
- [ICD-10-CM Z94.84: Stem cells transplant status](https://www.icd10data.com/ICD10CM/Codes/Z00-Z99/Z77-Z99/Z94-/Z94.84) — HIGH confidence (official ICD-10 code definition as status, not procedure)

### Chemotherapy Cycle Windows
- [How Often Is Chemotherapy Given? A Patient's Guide](https://honcology.com/blog/how-often-is-chemotherapy-given) — MEDIUM confidence (patient education, confirms 28-day cycle standard)
- [Why Is Chemotherapy Given Every 21 Days?](https://qba-meditours.com/en/blog/why-is-chemotherapy-given-every-21-days/) — LOW confidence (not peer-reviewed, but confirms cycle timing standards)

### PCORnet Cancer Treatment Episode Identification
- [Exploration of PCORnet Data Resources for Assessing Use of Molecular-Guided Cancer Treatment](https://pmc.ncbi.nlm.nih.gov/articles/PMC7469597/) — HIGH confidence (PCORnet-specific cancer treatment identification best practices)

### Second Primary Cancer Detection
- [Second primary cancer risk - different definitions of multiple primaries](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4005906/) — MEDIUM confidence (time separation thresholds for second primaries)
- [Mode of primary cancer detection as indicator of screening for second primary](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3517745/) — MEDIUM confidence (second cancer detection patterns)

---
*Feature research for: Episode-Level Cancer Linkage & First-Line Therapy Identification*
*Researched: 2026-05-29*
*Confidence: MEDIUM (high confidence on clinical standards, medium on PCORnet-specific implementation patterns)*
