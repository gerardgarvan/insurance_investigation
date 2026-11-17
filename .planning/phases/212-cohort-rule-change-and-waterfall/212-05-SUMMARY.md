# 212-05 SUMMARY — COMPLETE 2026-11-17

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
Dry run reviewed by user 2026-11-17 (HiPerGator, DISTINCT_ENC_REQUIRE_DIFF_DATES = TRUE):
- old 7,696; lost_2enc 0; gained_drop7 1,635; gained_trhl 0; lost_trnhl 152; new 9,179.
- gained_trhl 0: all 174 TR-HL patients not in the old cohort were already gained by drop7.
- Rules (a) and (b) give identical results: all 9,331 DEMOGRAPHIC patients have >= 2 active HL dx dates. Keep DISTINCT_ENC_REQUIRE_DIFF_DATES = TRUE.
- The extract was pulled on HL dx, so the 2-encounter rule is non-binding; the TR-NHL exclusion is the only rule that removes patients.
- Check: all 1,635 gained have active C81/201 codes. Distinct active-HL dates among gained: 2 = 554; 3-4 = 341; 5-9 = 273; 10+ = 467.
- Gained by DEMOGRAPHIC SOURCE (reference only, includes LNK): LNK 590, UAB 518, ORL 307, FLM 78, UMI 40, AVH 39, UFH 21, EMY 13, UCI 12, others <11.
- Gains concentrate at UAB and ORL, consistent with the 7-day rule being more restrictive at those sites. Site attribution is being moved to R/169 primary_source (D-212-06); the by-primary_source gain table comes from the re-run below.

## Review gate
- Gerard reviews `output/212_cohort_waterfall_<RUN_DATE>.xlsx` and D-212-01..10 before plan 04 (R/47 write) runs.


## Review outcome (2026-11-17)
- User approved applying the rule. D-212-06 revised (R/169 primary_source). Plan 04 code complete (212-04-SUMMARY.md).

## Step 3: apply and verify (commands; run done, see Final result)
Prerequisite: `output/internal/single_source_care_20261008.rds` (R/169) exists. Sync the repo first (R/47, R/212, R/utils/utils_cohort_rule.R).
```
module load R/4.5
R --no-save
```
```r
# 3a. apply (writes the rds; backup first, stops if backup fails)
source("R/47_cancer_summary_refined.R", local = new.env(parent = globalenv()))
# 3b. verify rds
x <- readRDS("output/confirmed_hl_cohort.rds")
cat(nrow(x), "rows;", ncol(x), "cols;", dplyr::n_distinct(x$ID), "distinct IDs
")   # expect 9179; 3; 9179
print(table(x$first_hl_dx_source, useNA = "ifany"))                                   # first_hl_dx_source distribution
cat("NA first_hl_dx_date:", sum(is.na(x$first_hl_dx_date)), "
")
bk <- list.files("output/internal/pre_v315_backup", pattern = "pre212", full.names = TRUE)
print(basename(bk))
# 3c. TR-HL-only patients (in new cohort, not in the backup) with NA date
old <- readRDS(tail(sort(bk), 1))
cat("old:", dplyr::n_distinct(old$ID), "
")                                          # expect 7696
cat("new not in old:", sum(!x$ID %in% old$ID), "; of those NA date:",
    sum(!x$ID %in% old$ID & is.na(x$first_hl_dx_date)), "
")                        # expect <= 1635 (gained patients also TR-NHL-only are removed)
# 3d. old (backup) vs new waterfall, site table by R/169 primary_source
Sys.setenv(R212_COHORT_RDS = tail(sort(bk), 1))
source("R/212_cohort_rule_waterfall.R", local = new.env(parent = globalenv()))
```
- Expected: new 9,179; lost_2enc 0; gained_drop7 1,635; gained_trhl 0; lost_trnhl 152 in the 212 console lines.
- TR-HL-only with NA date: expected 0 (gained_trhl is 0, so no patient enters via TR-HL alone). Anything else: report.
- R/212 prints `site = R/169 primary_source: from R/169 N; computed N; unassigned N`. Paste that line.
- Site table: paste the `waterfall_by_site` sheet rows (new, gained_drop7, lost_trnhl) and the `site_label_origin` sheet. Quick view:
```r
library(openxlsx); f <- tail(sort(Sys.glob("output/212_cohort_waterfall_*.xlsx")), 1)
print(read.xlsx(f, "waterfall_by_site"), row.names = FALSE); print(read.xlsx(f, "site_label_origin"))
```
- Paste back: the 3b/3c lines, the R/212 console lines (waterfall steps, site-label line), and the two sheet prints. On error: error + ~20 lines.
- Close-out: copy `output/212_cohort_waterfall_<RUN_DATE>.xlsx` unchanged into this phase folder.
- Rollback: copy the pre212 backup over `output/confirmed_hl_cohort.rds`.

## Final result (HiPerGator 2026-11-17, R/47 applied after two fixes)
- Fixes before the final apply: select via `any_of`; first_hl_dx_date computed on Rule A rows (COALESCE(DX_DATE, ADMIT_DATE)).
- `output/confirmed_hl_cohort.rds`: 9,179 patients, 0 NA first_hl_dx_date.
- first_hl_dx_source: Both 58 / DIAGNOSIS 8,728 / TUMOR_REGISTRY 393.
- Waterfall (R/212 vs original cohort): old 7,696; lost_2enc 0; gained_drop7 1,635; gained_trhl 0; lost_trnhl 152; new 9,179.
- By R/169 primary_source, old -> new: AMS 330->335; AVH 544->628; CHP <11->27; EMY 519->533; FLM 3,412->3,601; NCH 44->45; ORL 34->500; TMA 13->73; TMC 15->54; UAB 341->894; UCI 225->237; UFH 779->758; UMI 1,194->1,249; USF 239->245.
- Old-cohort backup (the only valid "old"): `output/internal/pre_v315_backup/confirmed_hl_cohort_pre212_20261117_133152.rds`.
- `confirmed_hl_cohort_intermediate_NAdates_20261117_134033.rds` (renamed from the 134033 backup) is an intermediate with NA dates. Never use as "old".
- R/212 default `R212_COHORT_RDS` now pins the 133152 file (R/212_cohort_rule_waterfall.R, pin_old). Env var still overrides.
- Remaining: copy `output/212_cohort_waterfall_<RUN_DATE>.xlsx` unchanged into this phase folder (on HiPerGator sync-back).

## Assumptions (headless run)
- Final counts and the backup file name were taken from the user's message; no HiPerGator access here.
- R/47's backup glob `pre212` matches only the 133152 file once the 134033 file is renamed; I did not re-verify the glob.

## Phase 213 reruns (cohort changed 7,696 -> 9,179; see ROADMAP chain order)
- R/169 first: `single_source_care` / primary_source must cover the 1,483 net new patients (re-run R/208's pinned R208_SSC_RDS to the new file).
- Then chain: R/26 -> R/28 -> R/28 p143 -> R/53 -> R/29 -> R/52 -> R/142 -> R/206 -> R/88.
- Other readers of `confirmed_hl_cohort.rds` (check, rerun if they feed deliverables): R/31, R/32, R/34, R/48, R/49, R/59, R/77, R/177, R/39, R/115 (cites "7-day confirmed"), R/203 -> R/208 (pins R/169 and R/203 files).
- R/45 `cancer_summary.csv` is unchanged by this rule; R/47 re-filters it to the new cohort.
