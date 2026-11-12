---
phase: 197
name: phase-b-pipeline-hardening
status: complete
completed_plans: 9
started: 2026-11-11
code_complete: 2026-11-11
completed: 2026-11-12
milestone: cross-milestone
tags: [hardening, run-order, pinning, versioning, config-safety, mice, dep-map]

dependency_graph:
  requires: [Phase 196-A complete, dep_map audit 2026-11-10]
  provides: [treatment_episodes single-owner, resolve_input helper, versioned_output_path helper, config rollback, dep_map v6]
  affects: [R/26, R/29, R/39, R/02, R/05-R/09 (utils), R/105, R/131, R/21, R/22, R/50, R/98, R/107-R/110, R/116, R/122, R/142, R/147, R/162, R/163, R/165-R/169, R/177, R/179-R/184, R/186-R/189, R/191, R/tools/check_cohort_fingerprint.R, R/tools/mice_convergence_diagnostic.R]

key_files:
  created:
    - R/utils/utils_io.R
    - R/utils/utils_config_safety.R
    - R/tools/mice_convergence_diagnostic.R
    - .planning/phases/197-phase-b-pipeline-hardening/197-MICE-CONVERGENCE.md (placeholder)
    - .planning/phases/197-phase-b-pipeline-hardening/197-RERUN-VERIFICATION.md
  modified:
    - R/39_run_all_investigations.R
    - R/26_treatment_episodes.R
    - R/29_first_line_and_death_analysis.R
    - R/142_gantt_180_export.R
    - R/110_output_level_before_after_report.R
    - R/100_ruca_rurality_summary.R
    - R/02_harmonize_payer.R
    - R/105_normalize_supportive_care_meaning.R
    - R/131_update_xlsx_med_admin_and_normalized_name.R
    - R/21_investigate_unmatched.R
    - R/22_investigate_unmatched_ndc.R
    - R/50_all_codes_resolved.R
    - R/98_radiation_cpt_audit.R
    - R/tools/check_cohort_fingerprint.R
    - R/183_mice_sensitivity_distance.R
    - R/SCRIPT_INDEX.md
    - .planning/phases/196-phase-a-delivered-output-fixes/RERUN-AND-REISSUE.md
    - (R/116, R/122, R/147, R/162, R/163, R/165-R/169, R/177, R/179-R/184, R/186-R/189, R/191 — versioned_output_path and resolve_input applied)

decisions:
  - "D-197-01: R/29 sole final writer of treatment_episodes.rds; R/26 writes treatment_episodes_stage1.rds (intermediate); R/53 must run before R/29"
  - "D-197-03: resolve_input() is canonical for dated-input resolution; R/183 bespoke load_pin() retained (D-15 contract)"
  - "D-197-03b: R/191 optional SES pick deliberately left unpinned (warn-and-continue)"
  - "D-197-03c: R/165 ses_path optional pick deliberately left unpinned (warn-not-stop)"
  - "D-197-04a: versioned_output_path() uses date-suffix (stem_YYYYMMDD.ext); R/188 date-prefix convention changed to suffix for consistency"
  - "D-197-04b: RUN_DATE env-var override added to all scripts with dated outputs"
  - "D-197-04c: R/107, R/109, R/110, R/46, R/47, R/48 have undated output filenames; versioned_output_path() not applicable"
  - "D-197-04d: overwrite=TRUE changed to overwrite=FALSE in all openxlsx::saveWorkbook calls that now use versioned paths"
  - "D-197-04e: Pre-existing paren-balance deltas in R/122, R/168, R/179, R/181, R/184 confirmed pre-existing"
  - "D-197-05: R/105 sole writer of rxnorm_ingredient_cache.csv; R/131 reads cache in-memory only"
  - "D-197-06-a: trim_config_bak() matches timestamped pattern only; plain .bak from pre-197 runs must be manually cleaned"
  - "D-197-06-b: R/21, R/22, R/50 backup_path switched to timestamped form for trim_config_bak() compatibility"
  - "D-197-09 (resolved): COLLAPSE_RARE_SOURCE=FALSE correct; UCI distance NA is a data gap, not a rare-level problem"
  - "D-197-12 (resolved 2026-11-12): maxit=20 retained — convergence diagnostic confirms R-hat < 1.1 for all continuous/binary variables within maxit; no rerun required"

metrics:
  duration_minutes: ~175 (9 plans, 2026-11-11)
  completed_date: 2026-11-11
  tasks_completed: ~45
  files_created: 4
  files_modified: ~35
---

# Phase 197 — Phase B: Pipeline Hardening Summary

## One-liner

Hardened pipeline mechanics from the 2026-11-10 dependency audit: single-owner contracts for treatment_episodes.rds and rxnorm cache, `resolve_input()` for reproducible dated-input resolution, `versioned_output_path()` for overwrite-safe dated outputs, timestamped config rollback, and standalone MICE convergence diagnostic tool.

## Plans Completed

| Plan | Name | Commit | Key change |
|------|------|--------|-----------|
| 197-01 | run-order-r39-script-index | 8c0803d | R/53 before R/29; R/26→stage1; is_first_line guards |
| 197-02 | column-guard-after-r29 | 413bb7c | Post-write validation block in R/29 (dup-key, type, required columns) |
| 197-03 | pin-unpinned-latest-file-picks | 52b3d48 | resolve_input() helper; 14 env vars applied across 7 scripts |
| 197-04 | overwrite-protection-versioned-output | 5293a04 | versioned_output_path() helper; 17 scripts updated; RUN_DATE env var |
| 197-05 | rxnorm-cache-single-owner | 52a7190 | R/131 write_csv calls removed; R/105 sole writer; idempotency guard fixed |
| 197-06 | config-safety-r98-bak-cleanup | 27b7bb8 | Timestamped .bak + rollback in R/98; trim_config_bak() util; R/21/22/50 updated |
| 197-07 | small-fixes-fingerprint-r02-sort | c4a2620 | Fingerprint tool path fix; R/02 sort by ID before write_csv |
| 197-08 | mice-r183-convergence-diagnostic | 6b5c754 | COLLAPSE_RARE_SOURCE flag in R/183; mice_convergence_diagnostic.R tool |
| 197-09 | dep-map-rerun-delta-summary | (this plan) | Phase summary; rerun verification table; dep_map command |

## Decisions Made

**D-197-01 (Plan 01):** R/29 is the sole final writer of `treatment_episodes.rds`. R/26 writes `treatment_episodes_stage1.rds` as an intermediate. R/53 must run before R/29 (provides `validated_death_dates.rds`). Three downstream readers (R/142, R/110, R/100) were noted as having `stopifnot("is_first_line" %in% names())` guards.

**Errata (Phase 199 fix):** The R/142 guard was incorrect — R/142 reads `treatment_episodes_180_enriched.rds` (built by R/28, never passes through R/29), which does not carry `is_first_line`. The guard has been removed (commit to follow). R/110 and R/100 both read `treatment_episodes.rds` (the 90-day file written by R/29), so their guards are correct and unchanged.

**D-197-03 (Plan 03):** `resolve_input()` is the canonical helper for dated-input resolution. R/183's bespoke `load_pin()` retained under its D-15 contract — no migration needed.

**D-197-03b/c (Plan 03):** R/191 and R/165 optional SES picks deliberately left unpinned — warn-and-continue pattern is correct behavior when R/116 output is absent.

**D-197-04a (Plan 04):** `versioned_output_path()` builds `stem_YYYYMMDD.ext`. R/188 date-prefix convention changed to date-suffix for consistency.

**D-197-04b (Plan 04):** `RUN_DATE` env-var override added to all scripts with dated outputs for cross-script date coordination.

**D-197-04c (Plan 04):** R/107, R/109, R/110, R/46, R/47, R/48 confirmed N/A — undated fixed-name outputs, no same-date overwrite risk.

**D-197-05 (Plan 05):** R/105 is sole writer of `data/reference/rxnorm_ingredient_cache.csv`. R/131 resolves CUIs in-memory only.

**D-197-06-a/b (Plan 06):** `trim_config_bak()` matches timestamped pattern only. R/21, R/22, R/50 backup_path updated to timestamped form. Stale `R/00_config.R.bak` on HiPerGator documented for Gerard to verify and delete.

**D-197-NN (Plan 08 — pending):** `COLLAPSE_RARE_SOURCE` defaults `FALSE`. Will activate only after Gerard reviews diagnostic output from `mice_convergence_diagnostic.R` and confirms collapsing "UCI" and other sub-30 levels is appropriate.

## Helpers Added (R/utils/)

Both are auto-sourced by `R/00_config.R` via the `R/utils/*.R` glob.

**`resolve_input(label, dir, pattern, env_var, ...)`** (`R/utils/utils_io.R`)
- If env_var is set → use that path; stop if missing; log `(pinned=TRUE)`.
- If unset → `list.files(dir, pattern)`; version-aware sort (`_vN` numeric desc, then YYYYMMDD desc); use first candidate; log `(pinned=FALSE)`.
- Stops if no candidates found.

**`versioned_output_path(stem, ext, dir, run_date)`** (`R/utils/utils_io.R`)
- Builds `dir/stem_run_date.ext`.
- Returns immediately if path does not exist.
- If `VERSIONED_OUTPUT=FALSE` → `stop()`.
- Otherwise increments `_v2`, `_v3`, ... until a free path is found.

**`trim_config_bak(config_path, keep = 5L)`** (`R/utils/utils_config_safety.R`)
- Lists timestamped `.bak` files matching `<basename>.<YYYYMMDD_HHMMSS>.bak`.
- Sorts newest-first; removes all beyond `keep` count.

## Pinned vs Deliberately Left List (from Plan 03)

### Pinned

| Script | Input | Env Var |
|--------|-------|---------|
| R/162 | patient_modality_dates | `R162_PATIENT_MODALITY_RDS` |
| R/163 | enc_distance | `R163_R122_RDS` |
| R/167 | treatment_episode_detail_180 | `R167_EPISODE_RDS` |
| R/167 | survivorship_dated_events | `R167_DATED_EVENTS_RDS` |
| R/167 | survivorship_rates_parts | `R167_RATES_PARTS_RDS` |
| R/167 | surveillance_modality_patient (fallback) | `R167_SURV_PATIENT_RDS` |
| R/168 | survivorship_rates_parts | `R168_RATES_PARTS_RDS` |
| R/168 | survivorship_echo_parts | `R168_ECHO_PARTS_RDS` |
| R/180 | enc_distance (fallback) | `R180_R122_RDS` |
| R/180 | single_source_care (fallback) | `R180_R169_RDS` |
| R/179 | enc_distance (fallback) | `R179_R122_RDS` |
| R/179 | zip_problem_inventory (fallback) | `R179_R121_RDS` |
| R/177 | zip_problem_inventory | `R177_R121_RDS` |
| R/177 | enc_distance | `R177_R122_RDS` |

### Deliberately Left Unpinned

| Script | Pick | Reason |
|--------|------|--------|
| R/183 | All 5 inputs | Already pinned via bespoke `load_pin()` (D-15) |
| R/165 (line 187) | enc_ses_index | Optional; warns and continues with empty tibble |
| R/191 (line 890) | enc_ses_index | Soft optional; outer `if(nchar > 0)` guard |
| R/86–R/89 | Various | Smoke-test/tooling scripts scanning codebase structure |
| R/01 | cache mtime comparisons | File-freshness logic, not an input resolution pick |
| R/119, R/122a | Directory scans | Enumerate all files in directory by design |
| R/164 | detail_path display | Display only; path already resolved upstream |

## dep_map Rerun (Pending — HiPerGator)

The dep_map tool must be rerun after all Phase 197 code changes to confirm that run-order, duplicate-writer, and unpinned-pick findings are resolved.

### HiPerGator command

```
module load R/4.5
R --no-save

source("R/00_config.R", local = new.env(parent = globalenv()))
source("R/tools/dep_map.R", local = new.env(parent = globalenv()))
```

Expected output files in `output/dep_map/` (new `_vN` set, where N = next after current highest):

- `dep_map_run_order_v*.csv`
- `dep_map_duplicate_writers_v*.csv`
- `dep_map_unpinned_picks_v*.csv`
- `dep_map_risk_report_v*.md`

**Paste back:** the full content of `dep_map_risk_report_v*.md` (the new version).

### Delta to confirm

| Finding (pre-Phase 197) | Expected post-197 state |
|-------------------------|------------------------|
| R/26 and R/29 both write treatment_episodes.rds | RESOLVED — R/26 writes stage1, R/29 writes canonical |
| R/105 and R/131 both write rxnorm_ingredient_cache.csv | RESOLVED — R/131 write_csv calls removed |
| R/53 listed after R/29 in R/39 | RESOLVED — R/53 swapped to before R/29 |
| 14+ list.files/file.mtime unpinned picks | RESOLVED — resolve_input() applied to 14 sites |
| 61 same-date overwrite sites | RESOLVED — versioned_output_path() applied to 17 scripts |

## Rerun Order for Gerard

See `197-RERUN-VERIFICATION.md` for the full ordered table with expected outcomes.

Summary order:

1. R/02 — sort check (`head(5)` by ID)
2. R/14 — cohort counts unchanged
3. R/26 — `treatment_episodes_stage1.rds` written
4. R/53 — `validated_death_dates.rds` present
5. R/29 — `treatment_episodes.rds` written, column guard passes
6. R/107, R/109, R/110 — versioned output paths (_v2 on same date)
7. R/46, R/47, R/48 — cancer summary outputs unchanged
8. R/165 — regression check vs Phase 195 baseline passes
9. R/183 — `COLLAPSE_RARE_SOURCE=FALSE` behavior unchanged (do NOT rerun MICE)
10. `check_cohort_fingerprint.R` — PASS vs pre_phaseA baseline
11. `mice_convergence_diagnostic.R` — produces 197-MICE-CONVERGENCE.md
12. `dep_map.R` — new risk report shows zero critical run-order and duplicate-writer issues

## Phase C Backlog (Out of Scope)

- R/56 `message()` scope guard
- Hard-coded absolute paths in R/161 and R/122a
- Consolidated suppression util (10 `sup()` copies)
- Em-dash cleanup (R/188 `"-"` vs `"—"`)
- R/02 enrollment-completeness % bug
- LNK payer partner investigation
- R/48 Comparison TOTAL row

## Bug Fixes Included in Phase 197 (commits b82c86b–a30bb5c)

### R/28 — Hodgkin label fix (commit a30bb5c / 197-11)

`is_hodgkin` was always 0 due to a label mismatch; fixed to match the actual
`histology_category` values in `cohort_final`. Second-cancer filter now excludes
second HL diagnoses correctly.

| Metric | Before | After |
|--------|--------|-------|
| is_hodgkin = TRUE | 0 | 10,101 |
| second-cancer pairs | 13,026 | 5,511 |

### R/29 — first-line fan-out fix (commit b2098f4 / 197-11)

`is_first_line` was fanning out across all treatment types (chemo, radiation,
immunotherapy) for each patient instead of being restricted to chemo episodes only
before the first-line flag was set.

| Metric | Before | After |
|--------|--------|-------|
| first_line patients | 2,174 | 1,379 |
| chemo/ABVD classification | inflated | corrected |

### R/109 Section 7 and Section 9 fixes (commits ee37a97–b633edd / 197-12, 197-13)

- **Section 7 stale-global regression (197-12):** `after` object from Section 6
  was used in Section 7 logic instead of the correct `chemo_after` frame; fixed.
- **Section 9 D-06 key mismatch (197-13):** episodes join used `patient_id` vs `ID`
  mismatch; fixed to use `ID` consistently.

### R/109 D-09 — NDC re-query (commit b82c86b / 197-15)

Second-pass RxNav query for OBSOLETE NDCs run on HiPerGator 2026-11-12:

- 7,739 unmatched NDCs queried via `ndcstatus.json?ndc=`
- 6,802 recovered (mostly OBSOLETE records)
- 25 of those matched `chemo_rxnorm`
- Cache written: `CONFIG$cache$outputs_dir/rxnav_ndc_requery_cache.rds`

**Incremental impact vs `treatment_episode_detail.rds`** (baseline: chemo 4,498 pts, 63,745 pt-dates):

| Source | Rows | Patients |
|--------|------|----------|
| MED_ADMIN matches | 190 | 53 |
| DISPENSING matches | 557 | 87 |
| PRESCRIBING | not checked (no NDC column) | — |

- **629 pt-dates** added; 327 already detected by other sources → **302 NEW dates** for **62 pts**
- **2 NEW chemo patients** (both in `cohort_final`)
- **12 patients** with earlier first-chemo date (median 19.5 d earlier, max 685 d)

**vs. July 14 delivered workbook:**

- Before-After Summary and Timing Shift sections: identical
- Regimen Impact: previously empty → ABVD 2526 → 2555 (+29; upper bound, reflects re-queried matches)

### source_hints note

`source_hints` column in `treatment_episode_detail.rds` records which pipeline
source (MED_ADMIN, DISPENSING, PRESCRIBING, manual RXNORM match) contributed each
chemo date. The D-09 re-query rows carry `source_hints = "rxnav_obsolete_requery"`.
Downstream scripts that filter or pivot on `source_hints` should be aware of this
new label.

## Tool Fixes (2026-11-12 — Plans 10–13)

Three standalone-tool bugs found and fixed before HiPerGator verification run:

### check_cohort_fingerprint.R (Plan 10)
Added `if (!exists("CONFIG")) source("R/00_config.R")` after library loads.
Without this, running the script in a fresh R session failed with
"object 'CONFIG' not found" (CONFIG is used to build `cohort_path`).

### mice_convergence_diagnostic.R (Plans 11–12)
Two bugs fixed:

1. **chainMean array extraction**: `mids$chainMean` in mice >= 3 is a 3D array
   `[n_vars × m × maxit]` with dimnames, not a named list. `names(cm)` returned NULL
   → `vars_imp` was NULL → `bind_rows(list())` returned an empty data frame with no
   `variable` column → `group_by(rhat_df, variable)` failed. Fixed by detecting the
   array structure and using `dimnames(cm)[[1]]` / `cm[v,,]` instead of `names(cm)` /
   `cm[[v]]`.

2. **Collapse recommendation replaced**: The old report flagged any `main_source` level
   with n < 30 as a "collapse candidate". This was wrong:
   - TMC (n=29) and CHP (n=23) are below 30 but have **0% missing distance** →
     collapsing does not fix the loggedEvents issue (they already contribute observed rows).
   - UCI (n=211, 100% missing distance) is the actual cause of the loggedEvents: among
     rows with observed distance, main_sourceUCI is always 0 (a constant predictor), so
     MICE drops it. This is a **data issue** (UCI has no FACILITY_LOCATION in the
     PCORnet extract), not a rare-level problem. Collapsing UCI into "Other" would not
     change the missingness pattern.
   - New report section: n and % missing `dist_to_source_facility_mi` by main_source,
     with per-level flags explaining the MICE behavior.
   - `COLLAPSE_RARE_SOURCE=FALSE` confirmed as correct default.

### UCI Facility ZIP Investigation (Plan 13)

Root cause: UCI ENCOUNTER rows have blank/null FACILITY_LOCATION in the PCORnet CDM
extract. After normalization in R/122, `zip5_facility = NA` for all UCI encounters →
no UCI row in `src_fac_zip` → no facility centroid for UCI → distance = NA for all
211 UCI patients.

Findings documented in `197-UCI-DISTANCE.md`:
- 211 UCI + 48 NA-source patients (259 total) have imputed distance in MICE.
- Complete-case OR 0.834 vs MICE OR 0.846 — estimates agree.
- NA main_source (48 patients): those patients have only post-anchor encounters with
  SOURCE = NA (data quality gap, not a pipeline bug).
- ORL 25.4% missing: ORL has a facility ZIP; the 127 missing distances are
  patient-side (no valid pat_zip5 for those patients in LDS_ADDRESS_HISTORY).
- Proposed `data/reference/source_facility_zip_override.csv` (UCI ZIP5 to be
  confirmed by Amy/Erin — D-197-10).

### Decision updates

**D-197-NN → resolved as D-197-09:**
`COLLAPSE_RARE_SOURCE=FALSE` is correct. The loggedEvents for main_sourceUCI are due
to UCI having 100% missing distance (constant predictor among observed rows), not a
rare-level issue. No collapse needed.

**D-197-10 (new — open):** Amy/Erin to confirm UCI institutional ZIP5 for override
file. Default: keep UCI distance as NA (imputed by MICE).

**D-197-11 (new — open):** Gerard to decide whether to implement the override CSV
mechanism in R/183 when D-197-10 is resolved.

## dep_map Standalone Status

dep_map.R is already self-contained: wrapped in `local({...})`, uses
`here::here()` only as an optional fallback for root detection (falls back to
`getwd()`), no CONFIG or session-global dependencies. Runs via
`Rscript R/tools/dep_map.R` or `source("R/tools/dep_map.R")` without pre-loading
R/00_config.R.

build_hrsa_crosswalk.R uses `here::here()` but no CONFIG — standalone. ✓

## HiPerGator Verification Results (2026-11-12, commit 7d76eed)

| Step | Tool | Result |
|------|------|--------|
| 5 | `check_cohort_fingerprint.R` | PASS — 8,770 rows, 8,770 IDs, md5 4cee245c… |
| 6 | `mice_convergence_diagnostic.R` | PASS — 11 imputed vars extracted (4 non-imputed skipped); all continuous/binary vars converge within maxit=20; COLLAPSE_RARE_SOURCE=FALSE confirmed |
| 7 | `dep_map.R` | PASS — gate 15/15; resolve_input() 100% resolved (n=14); outputs `*_20261112.*`; zero critical run-order or duplicate-writer findings |

**D-197-12 (resolved):** maxit=20 retained. converge_at by variable:

- d01: adi=11, dist=6, log_dist=8, main_source=11\*, payer=8\*, sex=9, single_source_care_post=7
- d02: adi=8, dist=9, far=9, main_source=9\*, payer=9\*, sex=6, single_source_care_post=10

(\* informational — categorical vars excluded from maxit recommendation)

**Small tool tweak (2026-11-12):** `mice_convergence_diagnostic.R` — added `final_rhat` column (R-hat at last iteration) next to `max_rhat`; labeled `max_rhat` as "max over all iterations (early iterations expected high)" in console and Markdown table.

## Open Items Carried Forward (not blocking Phase 197 closure)

- **D-197-10 (open):** UCI facility ZIP — all 29,158 UCI encounters have blank FACILITY_LOCATION; 211 patients affected; awaiting Amy/Erin confirmation of institutional ZIP5 for `source_facility_zip_override.csv`.
- **D-197-11 (open):** Override CSV implementation in R/183 — gates on D-197-10 resolution.
- **48 patients NA main_source:** cause unconfirmed (ENCOUNTER has no NA SOURCE rows at cohort level); data quality gap, not a pipeline bug.
- **chemo_rxnorm SME scope (open):** oral methotrexate 2.5 mg, gemcitabine, carboplatin, etoposide, bendamustine — awaiting Amy/Erin confirmation.
- **Phase 198 (planned):** R/108 obsolete-NDC fallback (gates on chemo_rxnorm scope SME confirmation).
- **Phase C backlog (unchanged):** R/56 scope guard, hard-coded absolute paths, consolidated `sup()`, em-dash cleanup, R/02 enrollment-completeness % bug, LNK payer investigation, R/48 Comparison TOTAL row.

## Deviations from Plan (Phase-Level)

- **[Rule 1 - Bug] R/98 tmp_verify removed before file.copy (Plan 06):** Initial draft removed `tmp_verify` before `file.copy`; replaced with `writeLines(config_text, config_path)` using in-memory content.
- **[Rule 2 - Missing] R/21/22/50 plain .bak invisible to trim_config_bak() (Plan 06):** Plain `.bak` paths updated to timestamped form so the new helper can find and prune them.
- **[Rule 1 - Convention] R/188 date-prefix changed to date-suffix (Plan 04):** Original `{YYYYMMDD}_188_...xlsx` double-embeds the date under `versioned_output_path()`. Changed to suffix for consistency.
- **[Rule 1 - Bug] R/02 filename differs from plan template (Plan 07):** Plan named `R/02_load_encounter_payer.R`; actual file is `R/02_harmonize_payer.R`. Applied fix to correct file.
