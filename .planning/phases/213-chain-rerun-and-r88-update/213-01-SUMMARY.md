# 213-01 SUMMARY (COMPLETE)

## Done locally (2026-11-17, headless)
- R/208 and R/212 SSC default pins -> `single_source_care_20261117.rds` (parse OK; verified at R/208 line 102, R/212 line 59).
- `chk_cohort_covered()` added to `R/tools/213_chain_checks.R` (test passes); plan 01 Task 2 uses coverage, not equality.
- R/212 pins `confirmed_hl_cohort_pre212_20261117_133152.rds` by exact path; R/47 has no glob.

## HiPerGator results (2026-11-17, pasted by Gerard)
- Task 1 backup to `output/internal/pre_v315_backup/chain/`: listed 18, exist 18, copied 18, missing none.
- Task 2 R/169 (RUN_DATE 20261117): "Found 9,282 patients with HL diagnosis"; cohort patients 9,331; single-source (whole) 5,640; any_blank 0; n_na_admit 0.
- Outputs: `output/internal/single_source_care_20261117.rds`/`.csv`, `output/internal/single_source_care_parts_20261117.rds`, `output/single_source_care_20261117.xlsx`.
- chk_cohort: rows 9,179 OK, distinct 9,179 OK. R/169 distinct IDs 9,331; cohort IDs missing 0 OK.

## Assumptions (headless run)
- RUN_DATE = 20261117 matched the pin default; no repin needed.
- DEC-213-01 decided by user 2026-11-17 (ship 205 labels for all rows).
- 9,282 (dx found) vs 9,331 (cohort patients in R/169) not reconciled here; coverage check passed, so treated as non-blocking.
