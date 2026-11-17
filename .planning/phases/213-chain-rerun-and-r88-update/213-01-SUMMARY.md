# 213-01 SUMMARY (INCOMPLETE)

## Done locally (2026-11-17, headless)
- R/208 and R/212 SSC default pins -> `single_source_care_20261117.rds` (parse OK).
- `chk_cohort_covered()` added to `R/tools/213_chain_checks.R` (test passes); plan 01 Task 2 uses coverage, not equality.
- R/212 pins `confirmed_hl_cohort_pre212_20261117_133152.rds` by exact path; R/47 has no glob.

## Assumptions (headless run)
- RUN_DATE = 20261117 for R/169. If another date is used on HiPerGator, set `R208_SSC_RDS` / `R212_SSC_RDS` or repin.
- DEC-213-01 decided by user 2026-11-17 (ship 205 labels for all rows).

## PENDING HIPERGATOR
- Task 1 backup and Task 2 R/169 + checks: commands in 213-01-PLAN.md. Paste back into this file.
