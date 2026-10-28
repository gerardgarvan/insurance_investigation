# AM-DRAFT
<!-- commit: 56db9ae -->
<!-- Phase 192 draft — Plans 02 and 03. Plan 02 provides §0–§3, §4 frame, §5–§8, §11, A1–A4. Plan 03 fills repo-only domain blocks inside the markers. -->
<!-- Status flags: DRAFTED | CORRECTION | TEAM-INPUT-NEEDED | OPEN-QUESTION-SEE-§8 -->
<!-- Grammar defined in 192-01-PLAN.md and 192-01-SUMMARY.md. -->

---

## 0. Front Matter (Update with Each Data Freeze)

- [S0-FM-01] Document title: Analytic Manual (AM): Blood Cancer United Hodgkin Lymphoma Study
  STATUS: DRAFTED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L1-L1

- [S0-FM-02] Project title: [TEAM INPUT NEEDED]
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L5-L5

- [S0-FM-03] Grant number: [TEAM INPUT NEEDED]
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L7-L7

- [S0-FM-04] Data sources: EHR (primary), Claims (secondary) — existing text preserved; claims integration status pending team decision.
  STATUS: OPEN-QUESTION-SEE-§8
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L9-L9

- [S0-FM-05] Current data freeze version: Extract name: Mailhot_V1_20250915. Receipt/freeze date: [date to confirm]. DuckDB build date: [date to confirm].
  STATUS: DRAFTED
  CITE: R/00_config.R:IS_LOCAL

- [S0-FM-06] Current analytic version: v3.13
  STATUS: DRAFTED
  CITE: .planning/STATE.md

- [S0-FM-07] Document version: [Set in Phase 193]
  STATUS: TEAM-INPUT-NEEDED
  CITE: .planning/phases/192-draft-new-content/192-CONTEXT.md

- [S0-FM-08] Date last updated: [Set in Phase 193]
  STATUS: TEAM-INPUT-NEEDED
  CITE: .planning/phases/192-draft-new-content/192-CONTEXT.md

- [S0-FM-09] Team roles: MPI: Ray Mailhot, MD, MPH; MPI: Erin Mobley, PhD, MPH; PhD Biostatistician (analytic lead): Amy Crisp, PhD; Masters-Level Biostatistician (analyst): Gerard Garvan, MS
  STATUS: DRAFTED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L19-L27

---

## 1. Data Ingest & Change Log

| Date | Data source | Description of change | Impact on cohort or variables | Action taken | Map ID | Status | Cite |
|------|-------------|----------------------|------------------------------|--------------|--------|--------|------|
| 2025-09-15 [date type to confirm] | OneFlorida+ PCORnet CDM (Mailhot_V1_20250915) | Initial extract received: 22 CDM CSV tables including ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC, DISPENSING, MED_ADMIN, LAB_RESULT_CM, PROVIDER, TUMOR_REGISTRY1/2/3 | Foundation for all cohort construction and analysis | Loaded via R/03_duckdb_ingest.R into DuckDB at /blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb | S1-LOG-01 | DRAFTED | R/00_config.R:IS_LOCAL |
| [date to confirm] | DuckDB database build | Initial DuckDB ingest of all CSV tables (Phase 29); atomic write with round-trip verification | All subsequent pipeline queries use DuckDB | R/03_duckdb_ingest.R: all tables ingested with PATID + ENCOUNTERID indexes | S1-LOG-01 | DRAFTED | R/00_config.R:IS_LOCAL |
| [date to confirm] | DEATH_CAUSE table | Added as 14th PCORnet table; provides ICD-classifiable cause-of-death data | Death-cause NHL flag and diagnostic scripts now have cause-of-death source | R/103_death_cause_diagnostic.R; Phase 118/119 work | S1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | MED_ADMIN / DISPENSING chemo detection (INTEGRATED) | NDC-to-RxNorm crosswalk added; get_chemo_hits() helper corrected RXNORM_CUI mismatch in DISPENSING and MED_ADMIN tables | Additional chemo detections enabled across all downstream outputs | R/utils/utils_treatment.R:get_chemo_hits() | S1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | LDS_ADDRESS_HISTORY (INTEGRATED) | Patient address history table integrated for ZIP9 temporal lookup | ZIP9 resolution and ADI/SDI assignment enabled across encounter timeline | R/utils/utils_address.R:get_zip9_at_date() | S1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | Neighborhood Atlas ADI 2024 (RECEIVED) | External reference file: Area Deprivation Index 2024 edition, national ZIP-level rankings | ADI assignment for patient ZIP codes | Loaded in Phase 144 SES index script | S1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | HRSA ZCTA crosswalk (RECEIVED) | HRSA ZIP-to-ZCTA crosswalk for distance calculation fallback tiers | Enables Tier 2 and Tier 3 distance computation for non-canonical ZIPs | R/122_encounter_distance.R:compute_encounter_distance() | S1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | RUCA codes (RECEIVED) | USDA Rural-Urban Commuting Area classification reference data | Rurality classification for patient and encounter ZIPs | Phase 116 rurality script | S1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | SDI (RECEIVED) | Social Deprivation Index reference data at county and ZIP level | Social deprivation covariate | Phase 144 SES index script | S1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | VariableDetails.xlsx Surveillance Strategy sheet (RECEIVED) | Team-supplied reference file defining surveillance modality codes | Survivorship encounter codeset | R/utils/utils_surveillance.R | S1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |

---

## 2. Cohort Construction History

2.1 Current Cohort Definition (Authoritative)

- [S2-COH-01] Inclusion Criteria: Patients with at least two separate encounters bearing a Hodgkin Lymphoma diagnosis code (ICD-10 C81.x or ICD-9 201.x) at least seven days apart. Identified via get_hl_any_dx_ids() from the DIAGNOSIS table.
  STATUS: DRAFTED
  CITE: R/utils/utils_treatment.R:get_hl_any_dx_ids()

- [S2-COH-02] Exclusion Criteria: Patients whose multiple treatment lines are clearly NHL-only are removed from the dataset (DEC-009). Patients with ambiguous HL/NHL classification who cannot be confirmed as NHL-only are retained (DEC-010).
  STATUS: DRAFTED
  CITE: DEC-009
  CITE: DEC-010

- [S2-COH-03] Index Date Definition: The earliest HL diagnosis code date (DX_DATE, with ADMIT_DATE as fallback) from the DIAGNOSIS table for ICD-10 C81.x or ICD-9 201.x codes. The TUMOR_REGISTRY date is not consulted in the production anchor function.
  STATUS: OPEN-QUESTION-SEE-§8
  CITE: R/utils/utils_treatment.R:get_hl_any_dx_ids()
  CITE: D-191-02

- [S2-COH-04] Observation Window Requirements: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L56-L58

2.2 Historical Cohort Definitions (Do Not Delete)

- [S2-COH-05] Historical definition changes are documented in the A2 table below.
  STATUS: DRAFTED
  CITE: .planning/STATE.md

---

## 3. Variable and Phenotype Decision Log

| Construct | Initial plan | Issue identified | Decision made | Rationale | Date | Affected analyses | Map ID | Status | Cite |
|-----------|-------------|-----------------|--------------|-----------|------|-------------------|--------|--------|------|
| Cancer diagnosis confirmation | Require at least one HL-coded encounter | Incidental coding and data errors inflate apparent HL prevalence | Two separate encounters with a diagnosis of the same cancer type at least seven days apart required; applies to all cancer types | Prevents incidental code from driving cohort inclusion | 2026-05-29 | Cohort construction; cancer summary table | S3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L1640-L1650 |
| Insurance harmonization — same-day hierarchy | Apply payer hierarchy within a day when multiple tiers present | Multiple payer records on a single day with differing tiers | Hierarchy: Medicaid (incl. codes 93/14/FLM source) > Medicare > Private (incl. Tricare) > Other > Self-pay or Uninsured → Uninsured > All missing → missing | Deterministic resolution per guidance from Amy | 2026-05-01 | All payer-stratified analyses | S3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L1837-L1850 |
| ADI — ZIP9 extrapolation from matching encounter | Require ZIP9 for ADI; no fallback defined | Some encounters have only ZIP5 or no ZIP | If 5-digit ZIP in one encounter matches 9-digit ZIP in another encounter for the same patient, extrapolate 9-digit to 5-digit encounter | Team confirmed ZIPs consistent longitudinally | 2026-08-18 | ADI covariate assignment | S3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L810-L820 |
| ADI — population-weighted average for ZIP5-only | — | Encounters with only ZIP5 have no direct ZIP9 | Use population-weighted average ADI of the 5-digit ZIP when no 9-digit is available | Accepted standard for ZIP5-level ADI approximation | 2026-08-25 | ADI covariate assignment | S3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L689-L700 |
| RUCA — ZIP5 acceptable | Require ZIP9 for RUCA lookup | RUCA works natively at ZIP code level | Can use 5-digit ZIP for RUCA assignment | RUCA database supports 5-digit ZIP directly | 2026-08-25 | Rurality covariate | S3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L689-L700 |
| Relapse vs refractory definition | Single category: refractory/relapse HL | Clinically and analytically distinct | Relapse = change in tx regimen with break of 90+ days from end of initial tx; Refractory = change in regimen with break of fewer than 90 days | Two separate concepts clinically | 2026-09-11 | Episode classification; survival analyses | S3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L390-L410 |
| NHL-only episode exclusion | Include all patients with any HL code | Patients with multiple clearly NHL-only tx lines contaminate HL cohort | Patients whose multiple lines of tx are clearly NHL-only are removed from the dataset | Ensure cohort specificity for HL study | 2026-09-22 | Cohort; all analyses | S3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L210-L225 |
| Uncertain HL inclusion | Exclude borderline HL/NHL patients | Ambiguous HL/NHL classification in data | Err on side of including patients who may not be a true HL if information is not definite | Conservative inclusion reduces false exclusions | 2026-09-22 | Cohort | S3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L210-L225 |
| Distance cutoff — far from care binary | Binary distance variable with unresolved cutoff | Uncertainty about evidence-based cutoff | 100 miles, based on doi.org/10.1182/blood-2023-182477 | Published literature reference for HL care distance threshold | 2026-10-13 | Far-from-care analyses | S3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L3-L30 |
| Drug name normalization — brand to generic | Use raw drug names from source tables | Brand-name proliferation impedes regimen identification | Convert all brand names to generic equivalents (e.g., adriamycin to doxorubicin); includes liposomal variants | Consistency for regimen detection and reporting | 2026-10-13 | Chemo classification; regimen identification; all outputs | S3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L3-L30 |
| Survivorship — remove diagnosis table from modality codes | Include all encounter types as survivorship encounters | Diagnosis-coded encounters inflate modality counts | Remove diagnosis table data from surveillance modality codes for survivorship care | Modality classification should reflect active care delivery | 2026-10-13 | Survivorship modality rates | S3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L3-L30 |

---

## 4. Data Cleaning and Harmonization Rules

### Cancer Diagnosis Date {#S4-DXDT}

- [S4-DXDT-01] Expected Structure: Each patient in the cohort should have a deterministic HL anchor date from which treatment timing and survivorship windows are measured.
  STATUS: DRAFTED
  CITE: R/utils/utils_treatment.R:get_hl_any_dx_ids()

- [S4-DXDT-02] Observed Issues: Not everyone has a diagnosis date that makes sense for HL.
  STATUS: DRAFTED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L89-L91
  CITE: am_verification_20261027.xlsx:V3_DXDATE

- [S4-DXDT-03] Cleaning Rules Applied: The pipeline anchor date is the earliest HL diagnosis code date from the DIAGNOSIS table (DX_DATE with ADMIT_DATE as fallback), filtered to ICD-10 C81.x or ICD-9 201.x codes. The Tumor Registry date (DATE_OF_DIAGNOSIS) is not consulted in the production anchor function.
  STATUS: OPEN-QUESTION-SEE-§8
  CITE: R/utils/utils_treatment.R:get_hl_any_dx_ids()
  CITE: D-191-03

- [S4-DXDT-04] Unresolved Issues: None documented in available sources.
  STATUS: DRAFTED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L140-L140

### Source {#S4-SRC}

- [S4-SRC-01] Expected Structure: ENCOUNTER.SOURCE identifies the contributing institution for each encounter. Partner sites include AMS, UMI, FLM (claims-only), VRT (death-only), UFH.
  STATUS: DRAFTED
  CITE: R/169_single_source_care.R:build_single_source_result()

- [S4-SRC-02] Observed Issues: LNK is present in the DEMOGRAPHIC table; V1_SOURCE confirms SOURCE distribution across all CDM tables with LNK present in DEMOGRAPHIC and assessed in ENCOUNTER.
  STATUS: DRAFTED
  CITE: am_verification_20261027.xlsx:V1_SOURCE
  CITE: R/169_single_source_care.R:build_single_source_result()

- [S4-SRC-03] Cleaning Rules Applied: SOURCE values are normalized using NULLIF(UPPER(TRIM(SOURCE)), '') to exclude blank entries. Single-health-system care flags are derived from ENCOUNTER.SOURCE, not from DEMOGRAPHIC.SOURCE.
  STATUS: DRAFTED
  CITE: R/169_single_source_care.R:build_single_source_result()

- [S4-SRC-04] Unresolved Issues: None documented in available sources.
  STATUS: DRAFTED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L121-L121

### Cancer Diagnosis {#S4-DX}

- [S4-DX-01] Expected Structure: All patients in the cohort should have confirmed HL based on ICD-9 (201.x) or ICD-10 (C81.x) diagnosis codes with two-encounter, seven-day confirmation. Patients with clearly NHL-only episodes are excluded (DEC-009).
  STATUS: DRAFTED
  CITE: R/utils/utils_treatment.R:get_hl_any_dx_ids()
  CITE: R/utils/utils_cancer.R:is_cancer_code()
  CITE: DEC-009

- [S4-DX-02] Observed Issues: Many patients appear to be listed with HL when they likely have NHL. NHL classification is implemented to address this; team decided to err on the side of inclusion for ambiguous cases (DEC-010).
  STATUS: DRAFTED
  CITE: am_verification_20261027.xlsx:V4_DXSCOPE
  CITE: DEC-009
  CITE: DEC-010

- [S4-DX-03] Cleaning Rules Applied: Two separate encounters with a diagnosis of the same cancer type at least seven days apart are required (DEC-003). In the cancer summary table this rule applies to all 54 cancer categories; in the HL cohort-entry step the seven-day rule is applied to HL codes specifically (C81/201).
  STATUS: OPEN-QUESTION-SEE-§8
  CITE: R/49_cancer_summary_pre_post.R:two_or_more_unique_dates_gt_7()
  CITE: R/utils/utils_treatment.R:get_hl_any_dx_ids()
  CITE: DEC-003
  CITE: D-191-04

- [S4-DX-04] Unresolved Issues: None documented in available sources.
  STATUS: DRAFTED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L140-L140

### Insurance {#S4-INS}

- [S4-INS-01] Expected Structure: Payer type is available in ENCOUNTER.PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY. The pipeline maps raw payer codes to an 8-category framework (AMC_PAYER_LOOKUP).
  STATUS: DRAFTED
  CITE: R/00_config.R:AMC_PAYER_LOOKUP
  CITE: R/60_tiered_same_day_payer.R:resolve_same_day_payer()

- [S4-INS-02] Observed Issues: Large amount of missingness for Insurance; V2_INSURANCE confirms non-trivial unmapped patient-days (Self-pay, Other, Other govt categories).
  STATUS: DRAFTED
  CITE: am_verification_20261027.xlsx:V2_INSURANCE
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L148-L150

#### CORRECTION S4-INS-03
- Target: §4 / S4-INS-03
- Anchor: "Insurance was harmonized across all visits on a given day for a" (docs/analytic_manual/AnalyticManual_2026.01.30.md:L154)
- Action: REPLACE
- Replacement: Insurance was harmonized across all visits on a given day for a given individual using an 8-category AMC framework with the following priority hierarchy: (1) Medicaid — including encounters with raw codes 93 or 14, or where SOURCE = FLM; (2) Medicare; (3) Private — including Tricare (code 311); (4) Other govt — government programs such as VA/TRICARE not captured in Private tier; (5) Other; (6) Self-pay; (7) Uninsured; (8) All missing → missing (no change).
- Provenance: D-191-05; DEC-002
  STATUS: CORRECTION
  CITE: R/60_tiered_same_day_payer.R:resolve_same_day_payer()
  CITE: R/00_config.R:AMC_PAYER_LOOKUP
  CITE: R/00_config.R:TIER_MAPPING
  CITE: DEC-002

- [S4-INS-04] Unresolved Issues: Confirmed in Phase 191 that the five clean tier categories (Medicaid, Medicare, Private, Uninsured, Missing) match the manual's stated hierarchy. Tier-count difference (6 manual vs 8 code) resolved by CORRECTION to S4-INS-03 above.
  STATUS: DRAFTED
  CITE: am_verification_20261027.xlsx:V2_INSURANCE
  CITE: R/60_tiered_same_day_payer.R:resolve_same_day_payer()

### ADI {#S4-ADI}

- [S4-ADI-01] Expected Structure: Nine-digit ZIP codes are required for direct ADI assignment.
  STATUS: DRAFTED
  CITE: R/utils/utils_address.R:approximate_zip9()
  CITE: R/utils/utils_address.R:get_zip9_at_date()

- [S4-ADI-02] Observed Issues: Some encounters have only a five-digit ZIP or no ZIP.
  STATUS: DRAFTED
  CITE: R/utils/utils_address.R:normalize_zip5_raw()
  CITE: R/utils/utils_address.R:approximate_zip9()

- [S4-ADI-03] Cleaning Rule — ZIP9 extrapolation: If a five-digit ZIP in one encounter matches a nine-digit ZIP in another encounter for the same patient, the nine-digit ZIP is extrapolated to the five-digit-only encounter (DEC-005).
  STATUS: DRAFTED
  CITE: R/utils/utils_address.R:approximate_zip9()
  CITE: DEC-005

- [S4-ADI-04] Cleaning Rule — population-weighted average: When no ZIP9 is available, the population-weighted average ADI of the five-digit ZIP is used (DEC-004). Provenance columns zip5_modal_freq and zip5_modal_share document the assignment.
  STATUS: DRAFTED
  CITE: R/utils/utils_address.R:approximate_zip9()
  CITE: DEC-004

- [S4-ADI-05] Cleaning Rule — non-matching five-digit ZIP: When a five-digit ZIP does not match any nine-digit ZIP for that patient, the population-weighted average ADI of the five-digit ZIP is applied to the missing-ZIP encounter (DEC-004).
  STATUS: DRAFTED
  CITE: R/utils/utils_address.R:approximate_zip9()
  CITE: DEC-004

- [S4-ADI-06] Unresolved Issues: None documented in available sources.
  STATUS: DRAFTED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L205-L205

### Treatment Window {#S4-TRT}

- [S4-TRT-01] Expected Structure: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L207-L211

- [S4-TRT-02] Observed Issues: End-of-treatment rule has not been established; pending confirmation with Sharon.
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L213-L215

- [S4-TRT-03] Cleaning Rules Applied: Treatment episode windows of 90-day and 180-day duration are implemented in the pipeline Gantt export. A formal end-of-treatment rule for survivorship window definition is pending.
  STATUS: DRAFTED
  CITE: R/142_gantt_180_export.R:EPISODE_GAP_DAYS

- [S4-TRT-04] Unresolved Issues: End-of-treatment date rules pending confirmation with Sharon.
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L221-L223

### Initial Treatment vs. Relapse {#S4-REL}

- [S4-REL-01] Expected Structure: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L225-L229

- [S4-REL-02] Observed Issues: How to distinguish initial treatment from relapse has not been established; awaiting Sharon's return of chemo episodes.
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L231-L233

- [S4-REL-03] Cleaning Rules Applied: Relapse is defined as a change in tx regimen with a break of 90 or more days from the end of initial tx to the start of a second line. Refractory disease is defined as a change in regimen with a break of fewer than 90 days (DEC-007).
  STATUS: DRAFTED
  CITE: docs/analytic_manual/TeamMtgNotes2026.md:L390-L410
  CITE: DEC-007

- [S4-REL-04] Unresolved Issues: Waiting for Sharon to return chemo episodes.
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L239-L241

### Death {#S4-DTH}

- [S4-DTH-01] Expected Structure: Death dates are resolved from the DEATH table using a source-priority rule. Cause-of-death data (DEATH_CAUSE table) is available for diagnostic use but is not used for patient exclusion.
  STATUS: DRAFTED
  CITE: R/utils/utils_death.R:resolve_death_date()

- [S4-DTH-02] Observed Issues: Cause of death is unreliable or missing for some patients. Death dates occurring before the last treatment encounter are present in the data.
  STATUS: DRAFTED
  CITE: R/utils/utils_death.R:resolve_death_date()
  CITE: am_verification_20261027.xlsx:V6_DEATH

- [S4-DTH-03] Cleaning Rule — grace window: If a death date falls within a grace window prior to the last treatment encounter, the death record is not used to define the end of the observation window. The current code applies a grace window of 30 days at all production call sites.
  STATUS: OPEN-QUESTION-SEE-§8
  CITE: R/utils/utils_death.R:resolve_death_date()
  CITE: D-191-06

- [S4-DTH-04] Cleaning Rule — cause of death not used for exclusion: Cause of death is not used to exclude patients. NHL as a cause of death does not trigger exclusion from the cohort.
  STATUS: DRAFTED
  CITE: R/utils/utils_death.R:resolve_death_date()
  CITE: R/10_cohort_predicates.R:has_hl_diagnosis()

- [S4-DTH-05] Unresolved Issues: None documented in available sources.
  STATUS: DRAFTED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L264-L266

### Survivorship Encounters {#S4-SRV}

- [S4-SRV-01] Expected Structure: Survivorship encounters are identified by surveillance modality codes defined in VariableDetails.xlsx (Surveillance Strategy sheet). Modality categories include imaging (CT, PET, echo, etc.), laboratory, and clinic visit types.
  STATUS: DRAFTED
  CITE: R/utils/utils_surveillance.R:classify_surveillance_encounter()
  CITE: R/147_surveillance_modality_frequency.R:MODALITY_LABELS

- [S4-SRV-02] Observed Issues: None documented in available sources.
  STATUS: DRAFTED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L274-L276

- [S4-SRV-03] Cleaning Rules Applied: Diagnosis table data is excluded from surveillance modality code classification; only PROCEDURES, PRESCRIBING, and lab-based codes qualify (DEC-012).
  STATUS: DRAFTED
  CITE: R/utils/utils_surveillance.R:classify_surveillance_encounter()
  CITE: DEC-012

- [S4-SRV-04] Unresolved Issue — VariableDetails: VariableDetails.xlsx Surveillance Strategy sheet needs team completion.
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L282-L284

- [S4-SRV-05] Unresolved Issue — treatment windows: Treatment windows must be defined before survivorship windows can be finalized.
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L286-L286

### Distance from Patient to Encounter Location {#S4-DIST}

- [S4-DIST-01] Expected Structure: Distance from patient residential ZIP to encounter facility ZIP is calculated using a three-tier method and expressed in miles.
  STATUS: DRAFTED
  CITE: R/122_encounter_distance.R:compute_encounter_distance()

- [S4-DIST-02] Observed Issues: None documented in available sources.
  STATUS: DRAFTED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L294-L296

- [S4-DIST-03] Cleaning Rule — distance method: Distance is calculated using a three-tier fallback method. Tier 1: zipcodeR::zip_distance() directly on raw five-digit ZIPs. Tier 2: zipcodeR on HRSA-crosswalked ZCTAs for pairs unresolved in Tier 1. Tier 3: haversine on gazetteer centroids of crosswalked ZCTAs.
  STATUS: OPEN-QUESTION-SEE-§8
  CITE: R/122_encounter_distance.R:compute_encounter_distance()
  CITE: D-191-07

- [S4-DIST-04] Cleaning Rule — nine-digit to five-digit ZIP: Where a nine-digit ZIP is available, the five-digit prefix is extracted for distance computation.
  STATUS: DRAFTED
  CITE: R/utils/utils_address.R:normalize_zip9()
  CITE: R/utils/utils_address.R:normalize_zip5()

- [S4-DIST-05] Cleaning Rule — temporally closest ZIP fallback: Where an encounter has no ZIP code, the temporally closest prior address record for that patient is used (match_type = most_recent_before).
  STATUS: DRAFTED
  CITE: R/utils/utils_address.R:get_zip9_at_date()
  CITE: R/122_encounter_distance.R:compute_encounter_distance()

#### CORRECTION S4-DIST-06
- Target: §4 / S4-DIST-06
- Anchor: "Should consider binary option, in which case, what to use for" (docs/analytic_manual/AnalyticManual_2026.01.30.md:L310)
- Action: REPLACE
- Replacement: The binary far-from-care cutoff is 100 miles, based on doi.org/10.1182/blood-2023-182477. This value is configured in CONFIG$far_from_care_cutoff_mi and applied in all far-from-care analyses. The earlier uncertainty between 120 mi and 200 mi was resolved by team decision on 2026-10-13.
- Provenance: D-191-08; DEC-008
  STATUS: CORRECTION
  CITE: R/00_config.R:IS_LOCAL
  CITE: DEC-008

<!-- BEGIN REPO-ONLY DOMAINS -->

### Single-Health-System Care Flag {#S4-SHS}

#### Expected Structure

- [S4-SHS-01] Expected Structure: Patients have encounters from one or more contributing SOURCE values. The pipeline produces two binary flags: `single_source_care` (all non-blank encounters came from a single institution) and `single_source_care_post` (the same rule applied to post-treatment encounters only). A `primary_source` column records the most frequent non-blank SOURCE value, with alphabetical tiebreaking.
  STATUS: DRAFTED
  CITE: R/169_single_source_care.R:build_single_source_result():L44-L90

#### Observed Issues

- [S4-SHS-01] Observed Issues: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/169_single_source_care.R:build_single_source_result():L48-L90

#### Cleaning Rules Applied

- [S4-SHS-01] Cleaning Rule — blank SOURCE exclusion: SOURCE values are normalized using NULLIF(UPPER(TRIM(SOURCE)), '') before any flag computation; blank SOURCE entries are excluded from the single-source determination.
  STATUS: DRAFTED
  CITE: R/169_single_source_care.R:build_single_source_result():L64-L86

- [S4-SHS-01] Cleaning Rule — NA assignment: `single_source_care` is NA where `n_encounters` equals zero; `single_source_care_post` is NA where `n_encounters_post` equals zero.
  STATUS: DRAFTED
  CITE: R/169_single_source_care.R:build_single_source_result():L64-L86

#### Unresolved Issues

- [S4-SHS-01] Unresolved Issues: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/169_single_source_care.R:build_single_source_result():L48-L90

---

### Chemo Detection {#S4-CHM}

#### Expected Structure

- [S4-CHM-01] Expected Structure: Chemotherapy hits are drawn from three PCORnet medication tables — PRESCRIBING, DISPENSING, and MED_ADMIN — via the `get_chemo_hits()` helper. Each returned row carries the patient ID, treatment date, triggering code, and a `source` column identifying the originating table path ("PRESCRIBING", "DISPENSING (NDC)", "MED_ADMIN (RX)", or "MED_ADMIN (NDC)").
  STATUS: DRAFTED
  CITE: R/utils/utils_treatment.R:get_chemo_hits():L181-L290

#### Observed Issues

- [S4-CHM-01] Observed Issue — RXNORM_CUI mismatch: DISPENSING and MED_ADMIN rows in the Mailhot V1 extract lacked usable RXNORM_CUI values for direct RxNorm matching. Without a crosswalk, chemo hits from these two tables were silently dropped (Phase 122 SUMMARY).
  STATUS: DRAFTED
  CITE: R/utils/utils_treatment.R:get_chemo_hits():L205-L290

#### Cleaning Rules Applied

- [S4-CHM-01] Cleaning Rule — NDC-to-RxNorm crosswalk: An NDC-to-RxNorm crosswalk (`data/reference/ndc_rxnorm_crosswalk.rds`, built by `R/108_build_ndc_rxnorm_crosswalk.R`) is loaded and passed to `get_chemo_hits()`. For DISPENSING and MED_ADMIN NDC-path rows, `normalize_ndc()` strips hyphens from the raw NDC before lookup.
  STATUS: DRAFTED
  CITE: R/utils/utils_treatment.R:normalize_ndc():L123-L125
  CITE: R/utils/utils_treatment.R:load_ndc_crosswalk():L136-L141

- [S4-CHM-01] Cleaning Rule — graceful degradation: If the crosswalk is NULL or empty, the NDC-path DISPENSING and MED_ADMIN branches log a message and return zero rows rather than erroring.
  STATUS: DRAFTED
  CITE: R/utils/utils_treatment.R:get_chemo_hits():L210-L213

#### Unresolved Issues

- [S4-CHM-01] Unresolved Issues: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/utils/utils_treatment.R:get_chemo_hits():L181-L290

---

### Drug-Name Normalization {#S4-NRM}

#### Expected Structure

- [S4-NRM-01] Expected Structure: Drug names from all three medication tables are normalized to canonical generic equivalents before regimen detection. Normalization is applied to `MEDICATION_LOOKUP` values at config load time so that all downstream code receives pre-normalized names.
  STATUS: DRAFTED
  CITE: R/00_config.R:MEDICATION_LOOKUP:L2636-L2733
  CITE: DEC-011

#### Observed Issues

- [S4-NRM-01] Observed Issue — brand-name proliferation: Brand names and salt variants (adriamycin, adriamycin pfs, adriamycin rdf; vinblastine sulfate) appear across medication tables. Without normalization these aliases produce distinct drug-name values that fail regimen detection logic.
  STATUS: DRAFTED
  CITE: R/00_config.R:MEDICATION_LOOKUP:L2750-L2812

#### Cleaning Rules Applied

- [S4-NRM-01] Cleaning Rule — brand-to-generic mapping: `canonicalize_drug_name()` maps brand and salt variants to generic equivalents. Examples: adriamycin → Doxorubicin; vinblastine sulfate → Vinblastine; liposomal doxorubicin variants included. Applied to all MEDICATION_LOOKUP values on config load (DEC-011 CONFIRMED 2026-10-13).
  STATUS: DRAFTED
  CITE: R/00_config.R:MEDICATION_LOOKUP:L2750-L2814
  CITE: DEC-011

- [S4-NRM-01] Cleaning Rule — JCODE supplement: J-code entries (`MEDICATION_LOOKUP_JCODE_SUPPLEMENT`) are merged into `MEDICATION_LOOKUP` after canonicalization so that HCPCS J-codes resolve to the same generic names as RxNorm-derived entries.
  STATUS: DRAFTED
  CITE: R/00_config.R:MEDICATION_LOOKUP_JCODE_SUPPLEMENT:L2720-L2733

#### Unresolved Issues

- [S4-NRM-01] Unresolved Issues: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/00_config.R:MEDICATION_LOOKUP:L2750-L2814

---

### First-Line Regimen Labeling {#S4-REG}

#### Expected Structure

- [S4-REG-01] Expected Structure: Treatment episodes are assigned a regimen label (ABVD, BV+AVD, Nivo+AVD, or unlabeled) based on the drug combination detected within the episode. Drug-name detection takes priority over J-code detection.
  STATUS: DRAFTED
  CITE: R/28_episode_classification.R:calculate_episodes_detailed():L328-L352

#### Observed Issues

- [S4-REG-01] Observed Issues: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/28_episode_classification.R:calculate_episodes_detailed():L295-L365

#### Cleaning Rules Applied

- [S4-REG-01] Cleaning Rule — ABVD labeling: An episode is labeled ABVD when it contains doxorubicin + bleomycin + vinblastine + dacarbazine with no brentuximab or nivolumab and at most four unique drugs.
  STATUS: DRAFTED
  CITE: R/28_episode_classification.R:calculate_episodes_detailed():L338-L342

- [S4-REG-01] Cleaning Rule — BV+AVD labeling: An episode is labeled BV+AVD when it contains brentuximab + doxorubicin + vinblastine + dacarbazine without bleomycin or nivolumab, and the episode start is on or after 2019-01-01.
  STATUS: DRAFTED
  CITE: R/28_episode_classification.R:calculate_episodes_detailed():L328-L335

- [S4-REG-01] Cleaning Rule — Nivo+AVD labeling: An episode is labeled Nivo+AVD when it contains nivolumab + doxorubicin + vinblastine + dacarbazine.
  STATUS: DRAFTED
  CITE: R/28_episode_classification.R:calculate_episodes_detailed():L328-L352

#### Unresolved Issues

- [S4-REG-01] Unresolved Issue — first-line qualification: The full first-line qualification logic (including the `is_first_line` column) is pending Sharon's episode review. Rule to be confirmed against code — see S4-REG-01.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/utils/utils_anthracycline_echo.R:last_anthracycline_dose():L24-L28

---

### Treatment Episodes {#S4-EPI}

#### Expected Structure

- [S4-EPI-01] Expected Structure: Chemotherapy dates are collapsed into contiguous treatment episodes using a gap threshold measured from episode start. Each episode has an episode start, episode stop, length in days, and list of drugs. Two window sizes are produced: a 90-day and a 180-day variant.
  STATUS: DRAFTED
  CITE: R/26_treatment_episodes.R:calculate_episodes_detailed():L511-L590
  CITE: R/00_config.R:GAP_THRESHOLD:L4054-L4054

#### Observed Issues

- [S4-EPI-01] Observed Issues: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/26_treatment_episodes.R:calculate_episodes_detailed():L511-L590

#### Cleaning Rules Applied

- [S4-EPI-01] Cleaning Rule — episode segmentation: `assign_episode_ids()` starts a new episode when `treatment_date - episode_start >= gap_threshold`. The default gap threshold is 90 days (`R/00_config.R:GAP_THRESHOLD = 90`, L4054). A 180-day variant is produced in the same script with `gap_threshold = 180L`.
  STATUS: DRAFTED
  CITE: R/25_treatment_durations.R:assign_episode_ids():L492-L512
  CITE: R/00_config.R:GAP_THRESHOLD:L4054-L4054
  CITE: R/26_treatment_episodes.R:L906

- [S4-EPI-01] Cleaning Rule — distinct constructs: Episode segmentation (gap measured from episode start), relapse/refractory classification (90-day break from end of initial treatment line — DEC-007), and Gantt display window (90-day or 180-day export file) are three separate constructs. A decision about one does not govern the others.
  STATUS: DRAFTED
  CITE: R/26_treatment_episodes.R:calculate_episodes_detailed():L511-L590
  CITE: DEC-007

#### Unresolved Issues

- [S4-EPI-01] Unresolved Issue — end-of-treatment date for survivorship: The formal end-of-treatment date rule for survivorship window definition is pending Sharon confirmation (see S4-TRT-04 and §8).
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L221-L223

---

### Anthracycline Exposure {#S4-ANT}

#### Expected Structure

- [S4-ANT-01] Expected Structure: Per-patient anthracycline exposure is summarized as two dates: `last_dose_firstline_dt` (last anthracycline admin date within first-line episodes) and `last_dose_ever_dt` (last admin date across all episodes). These are used as the clock start for echo surveillance rate calculations.
  STATUS: DRAFTED
  CITE: R/utils/utils_anthracycline_echo.R:last_anthracycline_dose():L58-L90

#### Observed Issues

- [S4-ANT-01] Observed Issue — first_line column absence: The `first_line` column is absent from `treatment_episode_detail_180.rds`. When all `first_line` values are FALSE or NA, `last_dose_firstline_dt` is NA for that patient (D-08a).
  STATUS: DRAFTED
  CITE: R/utils/utils_anthracycline_echo.R:last_anthracycline_dose():L24-L28

#### Cleaning Rules Applied

- [S4-ANT-01] Cleaning Rule — first-line dose: `last_anthracycline_dose()` filters rows where `first_line == TRUE` to derive `last_dose_firstline_dt`; rows with `first_line == FALSE` or NA are excluded from the first-line clock.
  STATUS: DRAFTED
  CITE: R/utils/utils_anthracycline_echo.R:last_anthracycline_dose():L71-L85

- [S4-ANT-01] Cleaning Rule — ever dose: `last_dose_ever_dt` is the maximum admin_date across all episode rows regardless of first-line status.
  STATUS: DRAFTED
  CITE: R/utils/utils_anthracycline_echo.R:last_anthracycline_dose():L58-L90

#### Unresolved Issues

- [S4-ANT-01] Unresolved Issues: Not documented in available sources beyond the D-08a note above.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/utils/utils_anthracycline_echo.R:last_anthracycline_dose():L24-L28

---

### CBC Definition {#S4-CBC}

#### Expected Structure

- [S4-CBC-01] Expected Structure: A complete blood count (CBC) event is defined as the co-occurrence of WBC (LOINC 6690-2), hemoglobin (LOINC 718-7), and platelet (LOINC 777-3) results for the same patient on the same date. This definition is specific to the distance-CBC association analysis; it is not applied to survivorship encounter classification.
  STATUS: DRAFTED
  CITE: R/utils/utils_distance_cbc.R:build_cbc_events():L89-L145

#### Observed Issues

- [S4-CBC-01] Observed Issues: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/utils/utils_distance_cbc.R:build_cbc_events():L108-L145

#### Cleaning Rules Applied

- [S4-CBC-01] Cleaning Rule — three-LOINC requirement: `build_cbc_events()` filters LAB_RESULT_CM to the three LOINC codes via SQL push-down, then retains only dates where all three codes are present for the same patient (ID × date grouping).
  STATUS: DRAFTED
  CITE: R/utils/utils_distance_cbc.R:build_cbc_events():L114-L143

- [S4-CBC-01] Cleaning Rule — DuckDB push-down: LAB_RESULT_CM is large; the LOINC filter and ID filter are applied in SQL before results are returned to R to reduce memory use.
  STATUS: DRAFTED
  CITE: R/utils/utils_distance_cbc.R:build_cbc_events():L105-L135

#### Unresolved Issues

- [S4-CBC-01] Unresolved Issues: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/utils/utils_distance_cbc.R:build_cbc_events():L108-L145

---

### Rurality {#S4-RUR}

#### Expected Structure

- [S4-RUR-01] Expected Structure: Rurality is assigned at the encounter level using RUCA (USDA 2020 ZIP Code Data) joined on ZIP5. Four RUCA categories: Metropolitan (codes 1–3), Micropolitan (4–6), Small town (7–9), Rural (10), Not coded (99). Five-digit ZIP is acceptable for RUCA assignment (DEC-006).
  STATUS: DRAFTED
  CITE: R/116_encounter_ses_index.R:RUCA_PATH:L214-L237
  CITE: DEC-006

#### Observed Issues

- [S4-RUR-01] Observed Issue — missing reference file: If the RUCA reference file (`data/reference/RUCA-codes-2020-zipcode.xlsx`) is absent, `ruca_code` and `ruca_category` are NA for all encounters; the script degrades gracefully with a message.
  STATUS: DRAFTED
  CITE: R/116_encounter_ses_index.R:RUCA_PATH:L236-L237

#### Cleaning Rules Applied

- [S4-RUR-01] Cleaning Rule — ZIP5 join: RUCA lookup joins the encounter-level ZIP5 column using `left_join` on ZIP5 with `na_matches = "never"` to exclude NA ZIPs from the join.
  STATUS: DRAFTED
  CITE: R/116_encounter_ses_index.R:RUCA_PATH:L344-L345

- [S4-RUR-01] Cleaning Rule — primary RUCA code: The USDA 2020 primary RUCA code (column `PrimaryRUCA`, sheet "RUCA 2020 ZIP Code Data") is used; the code is truncated to integer before category assignment.
  STATUS: DRAFTED
  CITE: R/116_encounter_ses_index.R:RUCA_PATH:L216-L228

#### Unresolved Issues

- [S4-RUR-01] Unresolved Issue — RUCC fallback: A RUCC (Rural-Urban Continuum Code) fallback is noted in AM-MAP-02 but was not located in the R/116 code. Rule to be confirmed against code — see S4-RUR-01.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/116_encounter_ses_index.R:RUCA_PATH:L1-L520

---

### Social Deprivation Index {#S4-SDI}

#### Expected Structure

- [S4-SDI-01] Expected Structure: The Social Deprivation Index (SDI; Robert Graham Center) is assigned at the encounter level using ZIP5 as the geographic unit. SDI scores range 0–100. SDI is ZIP5-level only; no ZIP9 or census-tract granularity is used.
  STATUS: DRAFTED
  CITE: R/116_encounter_ses_index.R:SDI_PATH:L240-L265

#### Observed Issues

- [S4-SDI-01] Observed Issue — missing or malformed reference file: If `data/reference/zip5_sdi_reference.csv` is absent or lacks the expected ZIP5/SDI_score columns, `sdi_score` is NA for all encounters; the script logs the available column names and continues.
  STATUS: DRAFTED
  CITE: R/116_encounter_ses_index.R:SDI_PATH:L244-L264

#### Cleaning Rules Applied

- [S4-SDI-01] Cleaning Rule — ZIP5 normalization and join: `normalize_zip5_raw()` is applied to the reference ZIP5 column before join; SDI is joined by ZIP5 with `na_matches = "never"`.
  STATUS: DRAFTED
  CITE: R/116_encounter_ses_index.R:SDI_PATH:L252-L254
  CITE: R/116_encounter_ses_index.R:SDI_PATH:L346-L347

#### Unresolved Issues

- [S4-SDI-01] Unresolved Issues: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/116_encounter_ses_index.R:SDI_PATH:L240-L265

---

### Diagnoses of Interest (Rituximab / Methotrexate) {#S4-DOI}

#### Expected Structure

- [S4-DOI-01] Expected Structure: Diagnosis codes indicating non-malignant conditions associated with rituximab or methotrexate use (autoimmune, inflammatory, hematologic) are flagged via prefix match against `DOI_CODE_MAP` (defined in `R/00_config.R`). Both ICD-10 and ICD-9 codes are handled.
  STATUS: DRAFTED
  CITE: R/utils/utils_doi.R:is_doi_code():L52-L78
  CITE: R/utils/utils_doi.R:classify_doi_codes():L98-L115

#### Observed Issues

- [S4-DOI-01] Observed Issues: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/utils/utils_doi.R:is_doi_code():L52-L78

#### Cleaning Rules Applied

- [S4-DOI-01] Cleaning Rule — DX_TYPE gating: `is_doi_code()` matches ICD-9 codes only against numeric-leading DOI_CODE_MAP keys and ICD-10 codes only against alpha-leading keys. This prevents cross-version false matches. ICD-9 records with DX_TYPE == "SM" or missing DX_TYPE are excluded.
  STATUS: DRAFTED
  CITE: R/utils/utils_doi.R:is_doi_code():L62-L78

- [S4-DOI-01] Cleaning Rule — 4-then-3-character prefix cascade: `classify_doi_codes()` tries the 4-character prefix first, then the 3-character prefix, to allow both specific and category-level matches.
  STATUS: DRAFTED
  CITE: R/utils/utils_doi.R:classify_doi_codes():L107-L115

#### Unresolved Issues

- [S4-DOI-01] Unresolved Issues: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/utils/utils_doi.R:is_doi_code():L52-L78

---

### HL vs NHL Classification {#S4-CLS}

#### Expected Structure

- [S4-CLS-01] Expected Structure: Patients with ICD-10 C81.x or ICD-9 201.x codes are classified as HL. Patients whose treatment episodes are clearly NHL-only are excluded from the cohort (DEC-009). Patients with ambiguous HL/NHL classification are retained (DEC-010).
  STATUS: DRAFTED
  CITE: R/utils/utils_cancer.R:classify_codes():L97-L115
  CITE: DEC-009
  CITE: DEC-010

#### Observed Issues

- [S4-CLS-01] Observed Issue — mixed HL/NHL codes: Many patients have diagnoses for both HL and NHL. Gantt-based episode detection is used to identify episodes that are clearly NHL-only, but the precise episode-level classification logic was not located in a single function.
  STATUS: DRAFTED
  CITE: R/utils/utils_cancer.R:classify_codes():L97-L115
  CITE: DEC-009

#### Cleaning Rules Applied

- [S4-CLS-01] Cleaning Rule — NHL-only exclusion: Patients whose multiple treatment lines are clearly NHL-only are removed from the dataset (DEC-009 CONFIRMED 2026-09-22).
  STATUS: DRAFTED
  CITE: DEC-009

- [S4-CLS-01] Cleaning Rule — uncertain HL inclusion: Patients who cannot be definitively confirmed as NHL-only are retained in the cohort, erring on the side of inclusion (DEC-010 CONFIRMED 2026-09-22).
  STATUS: DRAFTED
  CITE: DEC-010

#### Unresolved Issues

- [S4-CLS-01] Unresolved Issue — episode-level NHL classification code location: The episode-level NHL exclusion logic (which translates DEC-009 into a code path) was not located in a single identifiable function. Rule to be confirmed against code — see S4-CLS-01.
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/utils/utils_cancer.R:classify_codes():L97-L115

---

### Post-Death Encounters {#S4-PDE}

#### Expected Structure

- [S4-PDE-01] Expected Structure: Encounters occurring after the patient's resolved death date are identified and quantified. Post-death encounters are not removed from the encounter table; they are flagged via the `post_death_activity_days` column and the `death_flag` variable.
  STATUS: DRAFTED
  CITE: R/utils/utils_death.R:resolve_death_date():L50-L116

#### Observed Issues

- [S4-PDE-01] Observed Issue — post-death encounters present in data: Some patients have encounters recorded after their death date. Phase 29 (`R/29_first_line_and_death_analysis.R:L258–L259`) reports the patient count with post-death activity.
  STATUS: DRAFTED
  CITE: R/29_first_line_and_death_analysis.R:DEATH_RDS:L258-L259
  CITE: R/51_post_death_encounter_investigation.R:OUTPUT_XLSX

#### Cleaning Rules Applied

- [S4-PDE-01] Cleaning Rule — post-death activity flag: `resolve_death_date()` computes `post_death_activity_days` as the number of days from `death_date_raw` to `last_observed`; the value is zero where no post-death activity exists (L101–L112). `death_flag` distinguishes alive, deceased-confirmed, and deceased-inferred states.
  STATUS: DRAFTED
  CITE: R/utils/utils_death.R:resolve_death_date():L101-L116

#### Unresolved Issues

- [S4-PDE-01] Unresolved Issues: Not documented in available sources beyond the death grace-window question (D-191-06, recorded in §8 and S4-DTH-03).
  STATUS: TEAM-INPUT-NEEDED
  CITE: R/utils/utils_death.R:resolve_death_date():L50-L116

<!-- END REPO-ONLY DOMAINS -->

---

## 5. Cross-System Reconciliation (EHR vs Claims)

- [S5-REC-01] Dataset loading: The pipeline reads the OneFlorida+ PCORnet CDM extract loaded into DuckDB. No separate claims dataset is loaded or joined.
  STATUS: DRAFTED
  CITE: R/00_config.R:PCORNET_TABLES

- [S5-REC-02] Record provenance: Whether claims-derived records are present within the CDM tables (e.g., via LNK SOURCE values, ENC_TYPE values, or RAW_ fields) has not been determined.
  STATUS: OPEN-QUESTION-SEE-§8
  CITE: am_verification_20261027.xlsx:V1_SOURCE
  CITE: D-191-01

- [S5-REC-03] Reconciliation: No EHR-vs-claims reconciliation rules are implemented in the pipeline.
  STATUS: DRAFTED
  CITE: R/00_config.R:PCORNET_TABLES

- [S5-REC-04] Precedence rules for conflicts: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L328-L330

- [S5-REC-05] Sensitivity analyses planned: Not documented in available sources.
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L332-L334

---

## 6. Quality Assurance and Validation Checklist

- [S6-QA-01] Date logic checks: Executed. The comprehensive smoke test (R/88) includes date-logic sections across all pipeline scripts. R/88 ALL CHECKS PASSED 2026-10-23.
  STATUS: DRAFTED
  CITE: R/88_smoke_test.R:SMOKE_SECTIONS

- [S6-QA-02] Distribution checks: Executed. V2_INSURANCE, V3_DXDATE, V4_DXSCOPE, V6_DEATH distribution checks run in Phase 191; results in am_verification_20261027.xlsx.
  STATUS: DRAFTED
  CITE: am_verification_20261027.xlsx:V2_INSURANCE

- [S6-QA-03] Cross-source validation: Executed. Phase 191 verification script ran independent re-derivations against AM statements. Results in am_verification_20261027.xlsx.
  STATUS: DRAFTED
  CITE: am_verification_20261027.xlsx:V1_SOURCE

- [S6-QA-04] Masters biostatistician sign-off: Not signed off.
  STATUS: DRAFTED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L344-L344

- [S6-QA-05] PhD biostatistician sign-off: Not signed off.
  STATUS: DRAFTED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L346-L346

- [S6-QA-06] MPI sign-off: Not signed off.
  STATUS: DRAFTED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L348-L348

- [S6-QA-07] Notes: Phase 191 verification produced verdicts for all 24 FILLED-NEEDS-CHECK and BLOCKED map rows. Six OPEN D-191 mismatches and one CONFIRMED correction (D-191-08) documented. CONFIRMED corrections will be applied as tracked changes in Phase 193.
  STATUS: DRAFTED
  CITE: .planning/phases/191-verify-existing-entries/AM-VERDICTS.md

---

## 7. Analysis Status Tracker

| Aim / Analysis | Dataset version | Status | Notes | Map ID | Status flag | Cite |
|----------------|----------------|--------|-------|--------|-------------|------|
| Aim 1: treatment | Mailhot_V1_20250915 (v3.12) | Pipeline infrastructure complete; payer-stratified treatment analysis workbooks produced. Pending: episode boundary formalization and relapse definition. | Gantt export with regimen labels and payer tiers produced through Phase 164. | S7-TRK-01 | DRAFTED | .planning/STATE.md |
| Aim 2: survivorship care | Mailhot_V1_20250915 (v3.12) | Survivorship modality rate workbook delivered 2026-10-09 (Phase 165/186); per-modality annual and biannual rates produced; anthracycline-to-echo timing computed (Phase 188). | Rate of 0.2501 echo per person-year since last anthracycline dose (Phase 188). | S7-TRK-02 | DRAFTED | .planning/STATE.md |
| Rad onc subgroup analysis | — | Not yet implemented. PROVIDER table available with provider specialty type; approach described in manual note. | Not documented in available sources beyond manual note and STATE.md reference. | S7-TRK-03 | TEAM-INPUT-NEEDED | docs/analytic_manual/AnalyticManual_2026.01.30.md:L358-L359 |

---

## 8. Open Questions and Decision Parking Lot

| Item | Notes | Date added | Map ID | Status | Cite |
|------|-------|------------|--------|--------|------|
| Manual: Data sources: EHR (primary), Claims (secondary). Code: pipeline loads PCORnet CDM via DuckDB and has no claims dataset loaded. Which should the manual record? | MISMATCH; D-191-01; S0-FM-04 | 2026-10-28 | S0-FM-04 | OPEN-QUESTION-SEE-§8 | .planning/phases/191-verify-existing-entries/AM-VERDICTS.md |
| Manual: Use diagnosis date from Tumor Registry as default. Code: get_hl_any_dx_ids() reads DIAGNOSIS only; TR is not consulted. Which should the manual record? | MISMATCH; D-191-02; D-191-03; S4-CMNT-02; S4-DXDT-03 | 2026-10-28 | S4-DXDT-03 | OPEN-QUESTION-SEE-§8 | .planning/phases/191-verify-existing-entries/AM-VERDICTS.md |
| Manual: 7-day rule applies to all cancer types (S4-DX-03). Code: R/49 applies rule to all cancer categories; cohort-entry step in get_hl_any_dx_ids() applies rule to HL codes only. Which should the manual record? | MISMATCH; D-191-04; S4-DX-03 | 2026-10-28 | S4-DX-03 | OPEN-QUESTION-SEE-§8 | .planning/phases/191-verify-existing-entries/AM-VERDICTS.md |
| Manual: if death date is 14 days prior to last treatment encounter, ignore death. Code: all production call sites use grace_days = 30 days. Which should the manual record? | MISMATCH; D-191-06; S4-DTH-03 | 2026-10-28 | S4-DTH-03 | OPEN-QUESTION-SEE-§8 | .planning/phases/191-verify-existing-entries/AM-VERDICTS.md |
| Manual: using the zipcodeR package to calculate distance. Code: three-tier method (zipcodeR direct, zipcodeR on HRSA-crosswalked ZCTAs, haversine on gazetteer centroids). Which should the manual record? | MISMATCH; D-191-07; S4-DIST-03 | 2026-10-28 | S4-DIST-03 | OPEN-QUESTION-SEE-§8 | .planning/phases/191-verify-existing-entries/AM-VERDICTS.md |
| Location of the OneFLquestions document referenced in Amy Crisp's comment c0 (2026-10-23). S4-CMNT-01 is BLOCKED pending receipt of this document. | OPEN-DEPENDENCY; DEC-001 | 2026-10-27 | S4-CMNT-01 | OPEN-QUESTION-SEE-§8 | .planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md |
| End-of-treatment date rules pending confirmation with Sharon. Treatment window cannot be finalized until Sharon returns chemo episode review. | OPEN-DEPENDENCY; S4-TRT-04; S4-REL-04 | 2026-10-28 | S4-TRT-04 | OPEN-QUESTION-SEE-§8 | .planning/STATE.md |
| D-15 primary analysis method and D-165-01 — far-from-care CBC association analysis method confirmation (patient-level Fisher vs Rao-Scott) — awaiting Amy and Erin. D-09 capture finding reported to Amy and Erin. | OPEN-DEPENDENCY; D-165-01 | 2026-10-28 | S8-PRK-02 | OPEN-QUESTION-SEE-§8 | .planning/STATE.md |
| Data-completeness check vs Medicaid claims: parked pending resolution of claims integration question (D-191-01). | OPEN-DEPENDENCY; D-191-01 | 2026-10-28 | S8-PRK-02 | OPEN-QUESTION-SEE-§8 | .planning/STATE.md |

---

## 11. Known Data Limitations and Implications

- [S11-LIM-01] Care outside the system: The OneFlorida+ PCORnet CDM extract captures encounters at contributing partner sites only. Care received outside these systems — including out-of-network visits, non-partner facilities, and pharmacy dispensing — is not captured and may affect completeness of treatment and survivorship encounter data.
  STATUS: DRAFTED
  CITE: R/00_config.R:IS_LOCAL
  CITE: .planning/STATE.md

- [S11-LIM-02] Claims and LNK source status: Whether the extract contains claims-derived records (e.g., through LNK SOURCE values or FLM claims-only site) has not been determined. The pipeline does not load or join a separate claims dataset.
  STATUS: OPEN-QUESTION-SEE-§8
  CITE: am_verification_20261027.xlsx:V1_SOURCE
  CITE: D-191-01

- [S11-LIM-03] Insurance missingness and unmapped categories: A non-trivial proportion of patient-days have unmapped or missing payer type (Self-pay, Other, Other govt). Payer-stratified analyses may be affected by differential missingness.
  STATUS: DRAFTED
  CITE: am_verification_20261027.xlsx:V2_INSURANCE
  CITE: R/60_tiered_same_day_payer.R:resolve_same_day_payer()

- [S11-LIM-04] Distance measurement: Distance is computed as straight-line distance between ZIP-code centroids, not driving distance or travel time. ZIP centroid-based approximation may introduce measurement error, particularly in rural areas with large ZIP geographies.
  STATUS: DRAFTED
  CITE: R/122_encounter_distance.R:compute_encounter_distance()

- [S11-LIM-05] ZIP imputation for ADI: Where a nine-digit ZIP is unavailable, the population-weighted average ADI of the five-digit ZIP is used (DEC-004). This approximation introduces measurement error in the ADI covariate for encounters without nine-digit ZIP records.
  STATUS: DRAFTED
  CITE: R/utils/utils_address.R:approximate_zip9()
  CITE: DEC-004

- [S11-LIM-06] Death capture: Death dates come from the DEATH table in the PCORnet CDM extract; deaths occurring outside participating sites or not reported to the contributing institutions may not be captured.
  STATUS: DRAFTED
  CITE: R/utils/utils_death.R:resolve_death_date()
  CITE: am_verification_20261027.xlsx:V6_DEATH

- [S11-LIM-07] Planned sensitivity or mitigation strategies: Not documented in available sources beyond what is noted above.
  STATUS: TEAM-INPUT-NEEDED
  CITE: docs/analytic_manual/AnalyticManual_2026.01.30.md:L460-L465

---

## APPENDIX A. Embedded Working Tables

### A2. Cohort Definition History

| Version | Date | Change Description | Rationale | Approved By | Map ID | Status | Cite |
|---------|------|--------------------|-----------|-------------|--------|--------|------|
| v1.0 — C81 only | [date to confirm] | Cohort defined using ICD-10 C81.x codes only | Initial implementation | Not documented in available sources | SA2-COH-01 | DRAFTED | .planning/STATE.md |
| v1.x — C81 plus 201.x | [date to confirm] | ICD-9 201.x HL codes added to cohort definition | Cross-system category-level confirmation enabled | Not documented in available sources | SA2-COH-01 | DRAFTED | .planning/STATE.md |
| v2.0 — seven-day confirmation added | 2026-05-29 [decided] | Two-encounter seven-day separation rule required for cohort entry (DEC-003) | Prevent incidental codes from driving cohort inclusion | Amy Crisp; Ray Mailhot; Gerard Garvan | SA2-COH-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L1640-L1650 |
| v2.1 — NHL-only exclusion | 2026-09-22 [decided] | Patients with multiple lines of tx clearly NHL-only removed from dataset (DEC-009) | Ensure HL cohort specificity | Amy Crisp; Erin Mobley; Ray Mailhot | SA2-COH-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L210-L225 |

### A4. Analysis Status Tracker

| Aim / Analysis | Dataset Version | Status | Owner | Notes | Map ID | Status flag | Cite |
|----------------|----------------|--------|-------|-------|--------|-------------|------|
| Aim 1: treatment | Mailhot_V1_20250915 (v3.12) | Pipeline infrastructure complete; payer-stratified workbooks produced | Gerard Garvan | Pending episode boundary formalization and relapse definition (Sharon). | SA4-TRK-01 | DRAFTED | .planning/STATE.md |
| Aim 2: survivorship care | Mailhot_V1_20250915 (v3.12) | Survivorship modality rate workbook delivered 2026-10-09; anthracycline-to-echo timing computed | Gerard Garvan | Rate of 0.2501 echo per person-year since last anthracycline (Phase 188). | SA4-TRK-01 | DRAFTED | .planning/STATE.md |
| Rad onc subgroup analysis | — | Not yet implemented | Not documented in available sources | PROVIDER table available with specialty type; approach described in manual note. | SA4-TRK-01 | TEAM-INPUT-NEEDED | docs/analytic_manual/AnalyticManual_2026.01.30.md:L358-L359 |

### A1. Data Ingest & Change Log

| Date | Data source | Description of change | Impact on cohort or variables | Action taken | Map ID | Status | Cite |
|------|-------------|----------------------|------------------------------|--------------|--------|--------|------|
| 2025-09-15 [date type to confirm] | OneFlorida+ PCORnet CDM (Mailhot_V1_20250915) | Initial extract received: 22 CDM CSV tables including ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC, DISPENSING, MED_ADMIN, LAB_RESULT_CM, PROVIDER, TUMOR_REGISTRY1/2/3 | Foundation for all cohort construction and analysis | Loaded via R/03_duckdb_ingest.R into DuckDB at /blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb | SA1-LOG-01 | DRAFTED | R/00_config.R:IS_LOCAL |
| [date to confirm] | DuckDB database build | Initial DuckDB ingest of all CSV tables (Phase 29); atomic write with round-trip verification | All subsequent pipeline queries use DuckDB | R/03_duckdb_ingest.R: all tables ingested with PATID + ENCOUNTERID indexes | SA1-LOG-01 | DRAFTED | R/00_config.R:IS_LOCAL |
| [date to confirm] | DEATH_CAUSE table | Added as 14th PCORnet table; provides ICD-classifiable cause-of-death data | Death-cause NHL flag and diagnostic scripts now have cause-of-death source | R/103_death_cause_diagnostic.R; Phase 118/119 work | SA1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | MED_ADMIN / DISPENSING chemo detection (INTEGRATED) | NDC-to-RxNorm crosswalk added; get_chemo_hits() helper corrected RXNORM_CUI mismatch in DISPENSING and MED_ADMIN tables | Additional chemo detections enabled across all downstream outputs | R/utils/utils_treatment.R:get_chemo_hits() | SA1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | LDS_ADDRESS_HISTORY (INTEGRATED) | Patient address history table integrated for ZIP9 temporal lookup | ZIP9 resolution and ADI/SDI assignment enabled across encounter timeline | R/utils/utils_address.R:get_zip9_at_date() | SA1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | Neighborhood Atlas ADI 2024 (RECEIVED) | External reference file: Area Deprivation Index 2024 edition, national ZIP-level rankings | ADI assignment for patient ZIP codes | Loaded in Phase 144 SES index script | SA1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | HRSA ZCTA crosswalk (RECEIVED) | HRSA ZIP-to-ZCTA crosswalk for distance calculation fallback tiers | Enables Tier 2 and Tier 3 distance computation for non-canonical ZIPs | R/122_encounter_distance.R:compute_encounter_distance() | SA1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | RUCA codes (RECEIVED) | USDA Rural-Urban Commuting Area classification reference data | Rurality classification for patient and encounter ZIPs | Phase 116 rurality script | SA1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | SDI (RECEIVED) | Social Deprivation Index reference data at county and ZIP level | Social deprivation covariate | Phase 144 SES index script | SA1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |
| [date to confirm] | VariableDetails.xlsx Surveillance Strategy sheet (RECEIVED) | Team-supplied reference file defining surveillance modality codes | Survivorship encounter codeset | R/utils/utils_surveillance.R | SA1-LOG-01 | DRAFTED | .planning/phases/192-draft-new-content/192-02-INPUTS.md |

### A3. Variable & Phenotype Decision Log

| Construct | Initial plan | Issue identified | Decision made | Rationale | Date | Affected analyses | Map ID | Status | Cite |
|-----------|-------------|-----------------|--------------|-----------|------|-------------------|--------|--------|------|
| Cancer diagnosis confirmation | Require at least one HL-coded encounter | Incidental coding and data errors inflate apparent HL prevalence | Two separate encounters with a diagnosis of the same cancer type at least seven days apart required; applies to all cancer types | Prevents incidental code from driving cohort inclusion | 2026-05-29 | Cohort construction; cancer summary table | SA3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L1640-L1650 |
| Insurance harmonization — same-day hierarchy | Apply payer hierarchy within a day when multiple tiers present | Multiple payer records on a single day with differing tiers | Hierarchy: Medicaid (incl. codes 93/14/FLM source) > Medicare > Private (incl. Tricare) > Other > Self-pay or Uninsured → Uninsured > All missing → missing | Deterministic resolution per guidance from Amy | 2026-05-01 | All payer-stratified analyses | SA3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L1837-L1850 |
| ADI — ZIP9 extrapolation from matching encounter | Require ZIP9 for ADI; no fallback defined | Some encounters have only ZIP5 or no ZIP | If 5-digit ZIP in one encounter matches 9-digit ZIP in another encounter for the same patient, extrapolate 9-digit to 5-digit encounter | Team confirmed ZIPs consistent longitudinally | 2026-08-18 | ADI covariate assignment | SA3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L810-L820 |
| ADI — population-weighted average for ZIP5-only | — | Encounters with only ZIP5 have no direct ZIP9 | Use population-weighted average ADI of the 5-digit ZIP when no 9-digit is available | Accepted standard for ZIP5-level ADI approximation | 2026-08-25 | ADI covariate assignment | SA3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L689-L700 |
| RUCA — ZIP5 acceptable | Require ZIP9 for RUCA lookup | RUCA works natively at ZIP code level | Can use 5-digit ZIP for RUCA assignment | RUCA database supports 5-digit ZIP directly | 2026-08-25 | Rurality covariate | SA3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L689-L700 |
| Relapse vs refractory definition | Single category: refractory/relapse HL | Clinically and analytically distinct | Relapse = change in tx regimen with break of 90+ days from end of initial tx; Refractory = change in regimen with break of fewer than 90 days | Two separate concepts clinically | 2026-09-11 | Episode classification; survival analyses | SA3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L390-L410 |
| NHL-only episode exclusion | Include all patients with any HL code | Patients with multiple clearly NHL-only tx lines contaminate HL cohort | Patients whose multiple lines of tx are clearly NHL-only are removed from the dataset | Ensure cohort specificity for HL study | 2026-09-22 | Cohort; all analyses | SA3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L210-L225 |
| Uncertain HL inclusion | Exclude borderline HL/NHL patients | Ambiguous HL/NHL classification in data | Err on side of including patients who may not be a true HL if information is not definite | Conservative inclusion reduces false exclusions | 2026-09-22 | Cohort | SA3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L210-L225 |
| Distance cutoff — far from care binary | Binary distance variable with unresolved cutoff | Uncertainty about evidence-based cutoff | 100 miles, based on doi.org/10.1182/blood-2023-182477 | Published literature reference for HL care distance threshold | 2026-10-13 | Far-from-care analyses | SA3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L3-L30 |
| Drug name normalization — brand to generic | Use raw drug names from source tables | Brand-name proliferation impedes regimen identification | Convert all brand names to generic equivalents (e.g., adriamycin to doxorubicin); includes liposomal variants | Consistency for regimen detection and reporting | 2026-10-13 | Chemo classification; regimen identification; all outputs | SA3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L3-L30 |
| Survivorship — remove diagnosis table from modality codes | Include all encounter types as survivorship encounters | Diagnosis-coded encounters inflate modality counts | Remove diagnosis table data from surveillance modality codes for survivorship care | Modality classification should reflect active care delivery | 2026-10-13 | Survivorship modality rates | SA3-DEC-01 | DRAFTED | docs/analytic_manual/TeamMtgNotes2026.md:L3-L30 |

---

## Not drafted

All 12 repo-only domain blocks (S4-SHS-01 through S4-PDE-01) are now drafted inside the `<!-- BEGIN REPO-ONLY DOMAINS --> / <!-- END REPO-ONLY DOMAINS -->` markers in §4. No EMPTY-REPO-CAN-ANSWER map IDs remain undrafted.

Fields with no locatable code source carry one "Not documented in available sources." unit with status TEAM-INPUT-NEEDED, per D-25:
- S4-SHS-01 Observed Issues and Unresolved Issues
- S4-CHM-01 Unresolved Issues
- S4-NRM-01 Unresolved Issues
- S4-EPI-01 Observed Issues
- S4-CBC-01 Observed Issues and Unresolved Issues
- S4-SDI-01 Unresolved Issues
- S4-DOI-01 Observed Issues and Unresolved Issues
- S4-ANT-01 Unresolved Issues

Items that cannot be fully confirmed against code are recorded as TEAM-INPUT-NEEDED under Unresolved Issues:
- S4-RUR-01: RUCC fallback not located in R/116 code
- S4-REG-01: full first-line qualification logic (is_first_line column) pending Sharon episode review
- S4-CLS-01: episode-level NHL exclusion code path not located in a single function
