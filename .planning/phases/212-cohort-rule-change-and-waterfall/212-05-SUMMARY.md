# 212-05 SUMMARY — PENDING HIPERGATOR (incomplete)

Order: probe -> R/212 dry run -> user review -> (plan 04 R/47 write, not yet executed) -> verify.

## Step 1: probe (plan 01)
```
module load R/4.5
R --no-save
```
```r
source("R/00_config.R")
probe_inputs("212", tables = c("DIAGNOSIS", "ENCOUNTER", "DEMOGRAPHIC", "TUMOR_REGISTRY_ALL"),
             files = c("output/confirmed_hl_cohort.rds"))
```
Paste back the column lines listed in 212-01-SUMMARY.md. Sync `.planning/schemas/212_schema_*.md` back to the local repo; R/212 needs it on HiPerGator too (it is written there by the probe).

## Step 2: R/212 dry run (read-only)
```r
source("R/212_cohort_rule_waterfall.R", local = new.env(parent = globalenv()))
```
Optional second run with the other encounter rule: `Sys.setenv(DISTINCT_ENC_REQUIRE_DIFF_DATES = "FALSE")` before sourcing.
Paste back: the console checkpoint lines (counts per step, rule A / fallback line, TR-HL line, output path). On error: the error plus ~20 lines.

## PASTED OUTPUT
(pending)

## Review gate
- Gerard reviews `output/212_cohort_waterfall_<RUN_DATE>.xlsx` and D-212-01..10 before plan 04 (R/47 write) runs.
