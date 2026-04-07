# Phase 18: One Enrolled Person Does Not Have an HL Diagnosis Caught - Context

**Gathered:** 2026-04-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Investigate and fix why one specific enrolled patient is classified as "Neither" (HL_VERIFIED=0) in the cohort pipeline despite the user believing they should have HL evidence. The patient has lymphoma/cancer ICD codes (per gap analysis output) but they are not matching the HL-specific code lists. The fix is targeted: if the root cause is a missing code, add it; if the patient is correctly excluded, document and close.

</domain>

<decisions>
## Implementation Decisions

### Root cause investigation
- **D-01:** The patient is enrolled but classified as "Neither" — they have lymphoma/cancer codes visible in the gap analysis but the specific codes haven't been examined yet.
- **D-02:** The investigation starts by examining `neither_lymphoma_codes.csv` (output from `09_dx_gap_analysis.R`) to identify the patient's exact ICD codes. This is a HiPerGator-first step: user runs the gap analysis, shares the CSV, then Claude diagnoses the root cause.
- **D-03:** Possible root causes to check: (a) missing C81.xx variant in `ICD_CODES$hl_icd10`, (b) DX_TYPE mismatch preventing matching, (c) code normalization issue in `normalize_icd()`, (d) histology code outside 9650-9667 range, (e) patient has non-HL lymphoma codes and is correctly excluded.

### Fix scope
- **D-04:** If root cause is a missing code in the ICD list, add just the specific missing code(s). No broad audit of all C81 variants — targeted fix only.
- **D-05:** If the patient turns out to have non-HL lymphoma codes (correctly excluded), document the finding and close — no code changes needed.
- **D-06:** If root cause is a normalization or matching bug (e.g., `normalize_icd()` failing on a specific format), fix the bug in `utils_icd.R`.

### Validation approach
- **D-07:** After any fix, run a full pipeline rerun from `04_build_cohort.R` to verify the updated HL_SOURCE breakdown and cohort count. This confirms both the fix and no regressions.
- **D-08:** If the result is "document and close" (patient correctly excluded), update the gap analysis notes but no pipeline rerun needed.

### Claude's Discretion
- How to structure the diagnostic script changes if a code needs to be added
- Whether to update `09_dx_gap_analysis.R` with the findings
- Exact format of documentation if the exclusion is confirmed correct

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### HL identification logic
- `R/utils_icd.R` — `is_hl_diagnosis()` and `is_hl_histology()` functions that determine HL matching
- `R/00_config.R` — `ICD_CODES$hl_icd10`, `ICD_CODES$hl_icd9`, `ICD_CODES$hl_histology` code lists
- `R/03_cohort_predicates.R` — `has_hodgkin_diagnosis()` predicate that builds HL_SOURCE map and filters "Neither"

### Gap analysis
- `R/09_dx_gap_analysis.R` — Existing gap analysis script for "Neither" patients (Sections 1-7: loads excluded patients, explores DIAGNOSIS/ENROLLMENT/TR, classifies gaps, writes CSVs)

### Cohort pipeline
- `R/04_build_cohort.R` — Cohort build pipeline where HL_SOURCE is computed and patients are flagged

### Prior phase context
- `.planning/phases/06-use-debug-output-to-rectify-issues/06-CONTEXT.md` — D-02 established "Neither" exclusion pattern, D-20 established HL_SOURCE column

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `09_dx_gap_analysis.R`: Already investigates "Neither" patients with full diagnosis exploration, lymphoma code filtering, enrollment/TR cross-reference, and gap classification. Outputs to `output/diagnostics/neither_lymphoma_codes.csv`.
- `is_hl_diagnosis()` in `utils_icd.R`: ICD-9/10 matching with `normalize_icd()` normalization. The function to fix if code list needs expansion.
- `ICD_CODES` in `00_config.R`: Central configuration for all HL code lists. The place to add missing codes.
- `excluded_no_hl_evidence.csv`: Output containing the excluded "Neither" patients with their IDs and sources.

### Established Patterns
- HL identification uses two sources: DIAGNOSIS (ICD-9/10) and TUMOR_REGISTRY (ICD-O-3 histology)
- Code normalization removes dots for consistent matching (`normalize_icd()`)
- "Neither" patients are excluded from cohort and written to separate CSV
- Gap classifications: phantom record, coding gap, has lymphoma/cancer codes, non-HL diagnoses only

### Integration Points
- Input: `output/diagnostics/neither_lymphoma_codes.csv` from HiPerGator (user shares)
- Fix target: `R/00_config.R` (ICD_CODES) or `R/utils_icd.R` (normalization) depending on root cause
- Validation: Full pipeline rerun via `source("R/04_build_cohort.R")`
- Output: Updated cohort with corrected HL_SOURCE breakdown

</code_context>

<specifics>
## Specific Ideas

- The workflow is: user runs `09_dx_gap_analysis.R` on HiPerGator, shares `neither_lymphoma_codes.csv`, Claude examines the specific codes for the one patient, diagnoses root cause, and either adds the missing code or documents correct exclusion.
- This is a single-patient investigation, not a broad code audit.
- The user observed the count mismatch at the enrollment-to-HL-flagged step (everyone has enrollment but one drops at HL identification).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 18-one-enrolled-person-does-not-have-an-hl-diagnosis-caught*
*Context gathered: 2026-04-07*
