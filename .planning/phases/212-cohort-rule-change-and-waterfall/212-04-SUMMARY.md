# 212-04 SUMMARY — CODE COMPLETE, RUN PENDING HIPERGATOR

- `R/47_cancer_summary_refined.R` Sections 4-6: 7-day rule replaced by `hl_confirmed_two_encounters()` + `build_tr_lymphoma_flags()` + `apply_cohort_rule_v315()`; `confirmed_patients` = `$new`. `dx_hl` pull now includes ENCOUNTERID (and ADMIT_DATE when present).
- Section 5/6: left join from `confirmed_patients`, so TR-HL-only patients stay (NA date allowed, D-212-08). rds stays 3 columns. Prints `first_hl_dx_source` distribution and the NA-date count.
- Section 6: timestamped backup `output/internal/pre_v315_backup/confirmed_hl_cohort_pre212_<YYYYMMDD_HHMMSS>.rds` before `saveRDS`; `stop()` if the copy fails or sizes differ.
- `build_tr_lymphoma_flags()` closes the shared `pcornet_con`; R/47 reopens it afterwards (CLAUDE.md single-connection rule).
- Verify: `tools/rcheck.sh parse R/47_cancer_summary_refined.R` exit 0; `tools/rcheck.sh test 212` 0 failures. R/47 itself needs HiPerGator DuckDB (not run locally).

## Deviations
- R/47 prints waterfall totals only, no site breakdown. The site table (R/169 primary_source, D-212-06) is produced by R/212 after the apply.
- Column constants ENCOUNTERID / ADMIT_DATE rely on the 212 probe; the probe file is on HiPerGator, not in this checkout.

## Assumptions (headless run)
- R/47 backup runs on every execution when the rds exists, including re-runs; each gets its own timestamp.
