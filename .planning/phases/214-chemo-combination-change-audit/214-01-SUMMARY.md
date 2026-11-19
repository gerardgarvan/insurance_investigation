# 214-01 SUMMARY: helpers, R/214 script, tests, registration (local)

## Done
- `R/utils/utils_combo_audit.R`: `normalise_combo`, `classify_combos`, `match_episodes`, `attribute_cause`, `combo_added_drugs`, `rollup_cause`, `suppress_combo_counts` (reuses `suppress_display` from utils_distance_cbc.R).
- `R/214_combo_change_audit.R`: COMBO-01..06, pinned `R214_*` inputs, workbook (KEY first, Arial, UF colours) plus suppressed team copy. Gantt column constants marked `# UNVERIFIED`.
- `R/tools/214_probe_combo_inputs.R`: Task 0 probe (CSVs local; Gantt files on HiPerGator).
- `tests/testthat/test-214-combo-audit.R`: 31 expectations, 0 failed, 0 skipped.
- Registered: R/39 (after R/208), R/88 (one check), SCRIPT_INDEX.
- Parse checks exit 0 on all 6 changed R files.

## Local result: reference files confirmed
- Headers: chemo_combo_check.csv = `drug_names` (BOM); unique_chemo_drugs.csv = `drug_names`; change list = status, combination_normalized, old_file_string, new_file_string, related_combination, hypothesized_cause_UNCONFIRMED.
- Classification of old (498) vs new (504, blank excluded) = 314 unchanged / 161 label_only / 29 new / 21 dropped; matches the change list row for row.

## Assumptions (headless run)
- Q-214-01: unit = episode-level drug_names string compared after normalisation (as supplied). Q-214-02: blank row kept as "(blank)", excluded from the 314/161/29/21 classification (the reference list omits it), counted by treatment_type in Specific checks. Q-214-04: cause (b) wording stays "consistent with".
- Change-list column is `hypothesized_cause_UNCONFIRMED` (not `cause`). It is compared via a Hypothesis_check sheet, free text, no automated agreement count.
- Added-code list = all RITUXIMAB_CODES and MTX_CODES from config (config does not mark which were added in Phase 200).
- `triggering_codes` match is substring on config code values; its delimiter is unverified.

## PENDING HIPERGATOR (plan 214-02; not run)
Plan 214-02 stays incomplete. Sync the repo, then:
```
module load R/4.5
R --no-save
source("R/tools/214_probe_combo_inputs.R", local = new.env(parent = globalenv()))
```
Paste back: the checkpoint line, or the error plus ~20 lines. Read `.planning/schemas/214_schema_<date>.md` and confirm the UNVERIFIED column constants.
```
source("R/214_combo_change_audit.R", local = new.env(parent = globalenv()))
```
Paste back: the `[COMBO-01]`..`[COMBO-06]` lines (incl. per-candidate `[COMBO-02]` extra/missing), plus the QC sheet rows; or the error plus ~20 lines.
```
testthat::test_file("tests/testthat/test-214-combo-audit.R")
```
Paste back: the summary line.
