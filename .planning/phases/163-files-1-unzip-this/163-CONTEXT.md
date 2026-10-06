# Phase 163 — Drop diagnosis-code surveillance rows; Codeset_summary by modality

**Script:** R/147 (surveillance modality frequency)
**Builds on:** Phase 158 (R/147), 159 (lab modalities), 160 (A3, breast denominators, Codeset_summary), 161 (death dates / follow-up end), 162 (R/162 export)
**Reference run:** surveillance_modality_frequency_20261006.xlsx

## Goal

1. Stop counting surveillance events from DIAGNOSIS-table codes. Surveillance modalities are measured from procedure and lab records only.
2. Rebuild the Codeset_summary sheet so codes are presented per modality rather than in one modality x tier x match list plus a separate cross-modality analyte list.

## Scope of "remove diagnosis"

Four codeset rows use `cdm_table = DIAGNOSIS`. All are sensitivity-tier ICD-10 screening Z-codes:

| row | modality | code | 1006 n_patients (codeset hits) |
|---|---|---|---|
| SC039 | Echocardiogram | Z13.6 | 581 |
| SC047 | Electrocardiogram | Z13.6 | 581 |
| SC065 | Mammogram | Z12.31 | 849 |
| SC090 | Pulmonary function test | Z13.83 | 48 |

These are the only codes in the sensitivity tier for those four modalities, so their sensitivity tier becomes empty and `any` equals `primary` (the same pattern Stress test and Thyroid function already show).

**Out of scope:** the HL denominator, anchor date and confirmed-cohort logic. These read DIAGNOSIS for C81*/201* and must not change. Only the surveillance-event collection stops reading DIAGNOSIS.

## Decisions

- **D-01 Exclusion mechanism.** R/147 filters codeset rows with `cdm_table %in% EXCLUDED_CDM_TABLES` (constant, `"DIAGNOSIS"`) immediately after the codeset loads, logs the excluded row IDs, and removes the DIAGNOSIS surveillance collector. surveillance_codeset.xlsx is left unchanged so it still mirrors the VariableDetails "Surveillance Strategy" sheet; row IDs are not renumbered. *Alternative:* delete the four rows from the codeset file instead (simpler code, but the exclusion is no longer visible in the output and returns if the codeset is regenerated).
- **D-02 Codeset_summary layout.** One sheet, stacked blocks, one block per modality in the existing modality sort order, separated by a blank row and a modality header row. Each block contains:
  - *Codes:* one row per tier x match x code_system with n_codes, n_codes_present (seen in this run) and the code list; threshold column kept for analyte rules.
  - *Analytes (lab modalities only):* one row per analyte named in that modality's rules, with n_codes, n_codes_present and codes. Shared analytes (e.g., CREATININE in BMP, CMP and KIDNEY) repeat in each block by design.
  The current cross-modality "Codes per analyte" block is removed. *Alternative:* one sheet per modality (14 sheets).
- **D-03 Excluded rows are removed, not zeroed.** The four excluded rows are removed from A_code_presence entirely (not kept with zero counts, so Z13.6, Z12.31 and Z13.83 do not appear in the sheet). They are listed by ID only in KEY ("Diagnosis codes (163 D-01)") and QC ("Codeset rows excluded (DIAGNOSIS)" = 4). The existing QC row "DIAGNOSIS rows collected" is replaced by this new row. The QC presence check compares against the kept codeset (163 rows) and must be 0.

## Implementation requirements (executor must preserve)

- **Collector removal:** Remove the DIAGNOSIS surveillance collector itself, not just filter its output. No DIAGNOSIS rows are collected at all.
- **Assertion:** Add `stopifnot(!any(codeset$cdm_table %in% EXCLUDED_CDM_TABLES))` after splitting, before matching — ensures no excluded row slips through.
- **Codeset_summary blocks:** Code rows split by `code_system`; include `n_codes_present` (codes seen in this run). Analyte rows come from each modality's own rule rows, not the full Lab_Analytes list.
- **Verification against 1006 workbook:**
  - Denominator N / confirmed-cohort N / person-years: 9,331 / 9,282 / 40,298.9 — unchanged
  - B_modality_primary and C primary_* columns: identical across all modalities
  - Echo, ECG, Mammogram, PFT: sensitivity = 0 patients/dates; any-tier equals primary (e.g., Mammogram any_n_patients 1,157 → 1,003; Echo 4,699 → 4,582; ECG 4,945 → 4,827; PFT 2,574 → 2,556)
  - Only remaining "diagnosis" text is in the HL denominator and anchor lines (KEY/QC)
  - Write a comparison script (R/147 output vs 1006 file, sheet by sheet) rather than checking by eye

## Locked (carry forward)

- L-2: A3 never changes any count.
- L-4: tiers and modalities come only from the codeset (D-01 filters by CDM table, not by tier).
- Suppression 1-10 → <11; KEY stays leftmost.
- R/162 is unaffected: it already drops all `_any` columns.
