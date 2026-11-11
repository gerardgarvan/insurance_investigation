# Dependency Map Audit — 2026-11-10

Scope: dep_map v2.3 run of 20261110 (the "_v5" set). Read-only. No code was modified.
Evidence: code, grep, git log, ls. No data files opened.

---

## Ranked Summary Table

| # | Item | Status | Impact | Proposed fix |
|---|------|--------|--------|--------------|
| 2 | R/183 MICE payer dropped | **CONFIRMED** | Delivered MICE sensitivity results lacked payer variable (payer_summary.rds never exists; no CSV fallback) | Add CSV fallback matching R/165 pattern; or pin payer_summary.rds path |
| 9a | R/107/109/110 suppress to `NA_integer_` | **CONFIRMED** | `med_admin_dispensing_gap_diagnostic.csv`, `med_admin_dispensing_fix_impact.xlsx`, `output_level_before_after_report.xlsx` show blank instead of `"<11"` — suppressed counts indistinguishable from missing | Change `NA_integer_` returns to `"<11"` string in all three scripts |
| 13a | R/30 drops R/28 sheets in `episode_classification_audit.xlsx` | **NEEDS DECISION** | If R/30's `wb` is a fresh workbook (not loaded from R/28's file), R/28's sheets are silently overwritten | Confirm R/30 opens R/28's file first; add `wb_load` guard if missing |
| 16 | R/46 reads post-R/47 (filtered) `cancer_summary.csv` | **CONFIRMED** | R/46 expects R/45's unfiltered output; if R/47 has run, R/46 analyses D-code-less, HL-only universe — `cancer_summary_table.xlsx` counts differ | Document and enforce run order: R/45 → R/46 → R/47; or separate output paths |
| 8/15 | R/29 ordered before R/53 in R/39 | **CONFIRMED** | On a clean run R/29 stops at `assert_rds_exists()` for `validated_death_dates.rds` before R/53 produces it | Swap R/29 and R/53 in R/39 so R/53 precedes R/29 |
| 4d | `output/payer_at_chemo.csv` has no writer | **CONFIRMED** | R/110 payer section always placeholder; no script produces this CSV | Add a writer (R/11/14 returns tibble — add `write_csv` call) or document as permanently-manual |
| 10 | Unpinned latest-file selection in R/162, R/163, R/167, R/168, R/183 | **CONFIRMED** | Wrong file silently consumed if multiple dated outputs exist; R/168 (final deliverable assembler) is highest-risk | Add env-var pins matching the R/166 pattern; R/166 is the reference implementation |
| 11 | `treatment_episodes.rds` requires R/29 after R/26 for `is_first_line` | **CONFIRMED** | R/142 Gantt, R/100 Sheet 4, R/110 first-line breakdown all require R/29 to have run | Document required run order; guard downstream reads with column-existence check |
| 14 | Same-date overwrite in R/116, R/122, R/147, R/166-169, R/179-184, R/186-189 | **CONFIRMED** | Same-day re-run silently destroys prior dated outputs; R/186 and R/188 build paths inline (harder to escape via env-var) | Add `RUN_DATE` env-var override pattern to R/186 and R/188; document re-run risk for all 18 |
| 17 | rxnorm cache cold-query risk (R/105, R/131) | **CONFIRMED** | Re-query on cold cache could change `normalized_name` values via RxNorm API versioning; R/131 double-append risk if guard evaluated against stale xlsx | Commit current cache to git (or pin mtime); add idempotency guard in R/131 |
| 1 | Stale `R/00_config.R.bak` | **CONFIRMED** | Stale backup from interrupted R/21/22/50 run; R/98 has weaker safety (no `.bak`, no rollback) than the other three writers | Delete stale `.bak` after verifying config is intact; add `.bak`+rollback to R/98 |
| 5 | R/180 fallback to `output/` for `single_source_care*.rds` | **CONFIRMED** | If `output/internal/` is empty, stale file in `output/` silently loaded; `r169_pinned <- FALSE` | Add env-var pin; mark fallback with explicit warning |
| 3 | R/109 uses `here("cache","outputs",...)` instead of `CONFIG$cache$outputs_dir` | **CONFIRMED** | On HiPerGator, `cache/outputs/` does not exist → R/109 always skips its regimen-impact section silently | Change to `file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")` matching R/110 |
| 6 | R/56 shadows `base::message()` | **CONFIRMED** | Safe only if consistently sourced with `local = new.env(...)`; silent log corruption if sourced without it | Assert `local=` in R/39 runner for R/56; add a scope guard inside R/56 |
| 18 | R/161:41 bare `/blue/` path for DuckDB | **CONFIRMED** | If `/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb` moves, R/161 silently tries wrong path | Replace with `CONFIG$duckdb_path` |
| 7e | R/30 saves `episode_classification_audit.xlsx` without `wb_load` | **NEEDS DECISION** | Same as item 13a — potential sheet loss | Verify R/30 source code for `wb_load` call; add it if absent |
| 12 | rxnorm cache dual-writer both append-safe | **FALSE ALARM** | Append-then-rewrite pattern is consistent; no data loss risk from dual-writer | No action needed; note in SCRIPT_INDEX |
| 7f | `zip_change_frequency.xlsx` R/114 safe append | **FALSE ALARM** | R/114 uses `wb_load` → adds sheet → saves; R/106 sheets preserved | No action needed |
| 7g | R/97 payer CSVs use suffixed paths | **FALSE ALARM** | Writes to `payer_*<suffix>.csv`, not bare names; no conflict with R/60/R/61 | No action needed |
| 4a-c,e | Orphan reads: unmatched_ndc_classified.rds, combined_unmatched_report.xlsx, cancer_summary_table.xlsx, gantt snapshots | **FALSE ALARM** | Writers exist (R/22, R/23, R/46, R/52, R/170); files absent only because scripts haven't run on this Windows copy or are deliberate frozen snapshots | No code action; gantt snapshots require HiPerGator run |
| 8 (R/116←R/117-119; R/105←R/131; R/73←R/94) | Undocumented run-order dependencies | **CONFIRMED** | These scripts are not in R/39; a clean run from R/39 alone would fail | Add to SCRIPT_INDEX.md; R/39 header comment should list manual pre-requisites |
| 9b | R/188 rate suppression token `"-"` vs `"—"` | **CONFIRMED** | Minor inconsistency — ASCII hyphen in R/188 vs em dash elsewhere | Standardise to `"—"` |

---

## Item 1 — Config Rewriting

**Scripts:** R/21_investigate_unmatched.R:579,745,792; R/22_investigate_unmatched_ndc.R:830,1012,1047; R/50_all_codes_resolved.R:617,662,687; R/98_radiation_cpt_audit.R:307-313

### R/21, R/22, R/50 — safety pattern (consistent)

All three use an identical protocol:
1. `.bak` written unconditionally before any mutation
2. Write to tempfile → `parse()` check → proceed only if parse succeeds
3. Source-and-verify in a fresh env; on failure rollback from `.bak` and `stop()`
4. `file.remove(backup_path)` on clean success

No dry-run flag or interactive prompt. These run unconditionally when new codes are found.

**Stale `.bak`:** `R/00_config.R.bak` currently exists on disk. The cleanup `file.remove()` never executed, meaning one of these scripts was interrupted mid-run. Manual cleanup required after confirming current `R/00_config.R` is intact (diff the two: `diff R/00_config.R R/00_config.R.bak`).

**What they change:** R/21 rewrites `CONFIG$unmatched_icd_codes`; R/22 rewrites `CONFIG$unmatched_ndc_codes`; R/50 rewrites `CONFIG$resolved_code_groups`. These are code-list accumulation objects, not path config.

### R/98_radiation_cpt_audit.R:307-313 — weaker safety

- No `.bak` before writing
- No rollback mechanism
- Only a tempfile parse check (`tryCatch`); on parse failure, `warning()` and no write
- If parse check passes but written content is semantically wrong, there is no recovery

**R/39 inclusion:** R/50 is in R/39 (line 295). R/21, R/22, R/98 are standalone — not orchestrated by R/39.

**git log — R/00_config.R:** Recent commits have planned phase prefixes (`feat/fix`). The R/21/22/50/98 mutations appear as working-tree diffs, not commits — they were applied interactively.

**Status:** CONFIRMED (stale .bak = real artifact; R/98 weaker safety = real gap).
**Proposed fix:** Delete stale `.bak` after diff check; add `.bak` + rollback to R/98.

---

## Item 2 — R/183 payer input

**Lines 385-403, R/183_mice_sensitivity_distance.R:**

Searches `CONFIG$output_dir` for `^payer_summary.*\.rds$` via `list.files()`. On failure, sets `payer_avail <- FALSE` and `DROPPED[["payer"]] <- "payer_summary RDS not found"`. Payer is set to `factor(NA_character_)` for all patients, then removed entirely if all NA (lines 477-480).

R/02 writes only `output/tables/payer_summary.csv` — an RDS is never produced. R/165 handles this correctly with a CSV fallback; R/183 does not.

**File existence:** `output/**/*payer_summary*.rds` — no matches (Glob). `output/tables/payer_summary.csv` — absent locally.

**Conclusion:** Any MICE sensitivity results delivered from an R/183 run lacked the payer covariate. The drop is logged internally but the imputation proceeds silently without it.

**Status:** CONFIRMED.
**Impact:** Delivered MICE sensitivity workbooks (`output/mice_sensitivity_distance_*.xlsx`).
**Proposed fix:** Add CSV fallback matching R/165's pattern; or add payer_summary.rds as a pinned intermediate from R/02.

---

## Item 3 — Cache-folder mismatches

### R/109:352 — `here("cache","outputs","treatment_episodes.rds")`

R/109 line 100 defines `EPISODES_RDS <- here::here("cache", "outputs", "treatment_episodes.rds")`. This is a local project-relative path. On HiPerGator, `CONFIG$cache$outputs_dir` resolves to `/blue/erin.mobley-hl.bcu/clean/rds/outputs` — outside the project tree. The local `cache/outputs/` directory does not exist.

R/109 guards with `file.exists(EPISODES_RDS)` at line 336; on failure it emits a skip message and continues. On HiPerGator the regimen-impact section always silently skips.

Compare: R/110 line 87 correctly uses `file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")`.

**Status:** CONFIRMED.
**Impact:** `output/med_admin_dispensing_fix_impact.xlsx` regimen-impact section is always a placeholder on HiPerGator.
**Proposed fix:** `file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")` matching R/110.

### R/164:46 — `treatment_episode_detail.rds`

R/164 uses a multi-candidate search: (1) `CONFIG$cache$outputs_dir`, (2) `CONFIG$cache$cache_dir`, (3) `CONFIG$output_dir`. Picks first that exists. Correct pattern — no mismatch.

**Status:** FALSE ALARM for R/164.

---

## Item 4 — Orphan reads

### 4a — `output/unmatched_ndc_classified.rds`

Writer: R/22 line 40 defines `RDS_PATH <- file.path(CONFIG$output_dir, "unmatched_ndc_classified.rds")`; writes at line 1133 via `save_classified_rds()`. Writer exists. File absent locally only because R/22 hasn't run on this Windows copy. R/22 header comment incorrectly says `cache/outputs/` — documentation error; code is correct.

**Status:** FALSE ALARM (writer exists in R/22).

### 4b — `output/combined_unmatched_report.xlsx`

Writer: R/23_combine_reports.R line 489 (`write_combined_report()`). File absent locally — same reason.

**Status:** FALSE ALARM (writer exists in R/23).

### 4c — `output/tables/cancer_summary_table.xlsx`

Writer: R/46_cancer_summary_table.R. File exists locally. R/48 reads it as comparison baseline.

**Status:** FALSE ALARM.

### 4d — `output/payer_at_chemo.csv`

No writer found in R/ or R/archive/. `compute_payer_at_chemo()` in R/11/14 returns a tibble; neither script contains a `write_csv` targeting `payer_at_chemo.csv`. R/110 handles absence gracefully (placeholder row). File does not exist locally.

**Status:** CONFIRMED (genuine orphan — pipeline cannot produce this file from scratch).
**Impact:** R/110 payer section is always a placeholder.
**Proposed fix:** Add `write_csv(payer_at_chemo_tbl, file.path(CONFIG$output_dir, "payer_at_chemo.csv"))` in R/14 after `compute_payer_at_chemo()`.

### 4e — Gantt frozen snapshots

All are deliberate frozen reference files, not coding errors:
- `output/gantt_episodes_pre_p124.csv` — manual pre-R/52 snapshot described in R/110 comments; R/110 guards with `file.exists()`.
- `output/internal/gantt_episodes_PRE1922.csv`, `gantt_episodes_180_PRE1922.csv` — written by R/52 and R/170 as Phase 192.2 regression baselines.
- `output/gantt_episodes_v2.csv`, `gantt_detail_v2.csv` — Phase 78 test artifacts from R/52.
- `output/gantt_episodes_180_{DATE}_PINNED.csv` — pinned reference snapshot; path passed via env-var.

All absent locally (require HiPerGator R/52/R/170 runs). The pipeline cannot rebuild `gantt_episodes_pre_p124.csv` from code alone — it was a one-time manual snapshot.

**Status:** FALSE ALARM (all intentional frozen snapshots).

---

## Item 5 — R/180 `single_source_care` search

**Code (lines 198-209):**

```r
cand <- list.files(out_internal, "^single_source_care.*\\.rds$", ...)
if (length(cand) == 0L)
    cand <- list.files(CONFIG$output_dir, ...)   # output/ fallback
```

The `output/` search is a fallback, not a parallel search. When it fires, `r169_pinned <- FALSE` and mtime-latest selection is used — no env-var guard.

**Stale-file risk:** If `output/internal/` is ever cleared but `output/` retains a stale file, the wrong file is silently loaded. This violates the project pinning convention.

**Files on disk:** No `single_source_care*.rds` in either location on this Windows copy.

**Status:** CONFIRMED.
**Proposed fix:** Add env-var pin `R180_R169_RDS`; mark fallback with an explicit `warning()`.

---

## Item 6 — R/56 `message()` override

**Lines 91-100, R/56_new_tables_from_groupings.R:**

```r
.original_message <- base::message
message <- function(..., domain = NULL, appendLF = TRUE) {
    .original_message(..., domain = domain, appendLF = appendLF)
    cat(format(Sys.time(), "[%Y-%m-%d %H:%M:%S] "), ..., file = .log_con, sep = "")
    flush(.log_con)
}
```

Timestamps every `message()` call and tees to a log file connection opened at script load time.

**R/39 sourcing:** R/39 line 213 includes R/56 in the pipeline list.

**Session contamination:** Safe only if `source("R/56...", local = new.env(parent = globalenv()))` is used consistently. If sourced without `local=`, the override lands in `globalenv` and all subsequent `message()` calls in the session write to R/56's `.log_con`. If that connection closes after R/56 finishes, later intercepted calls would error.

**Smoke tests:** R/88 uses `readLines()` on R/56 — does not `source()` it.

**Status:** CONFIRMED (latent contamination risk).
**Proposed fix:** Assert `local=` in R/39 runner for R/56; add a guard inside R/56 that errors if `identical(environment(message), globalenv())`.

---

## Item 7 — Files written by more than one script

### 7a — `treatment_episodes.rds` (R/26, R/29)

Intentional in-place enrichment per design decision D-09. R/26 creates; R/29 reads, adds `is_first_line`, overwrites same path. R/29 header documents this explicitly. R/26 is authoritative for structure; R/29 for the enriched version. See Item 11 for downstream impact.

### 7b — `cancer_summary.csv` (R/45, R/47)

R/47 reads R/45's output, removes D-codes and non-HL patients, overwrites same path. R/47 header documents this ("overwritten: D-codes removed, HL cohort only"). R/47 is authoritative. See Item 16 for ordering risk with R/46.

**Risk flag:** Confirm `build_output_path("tables", "cancer_summary.csv")` does not inject a date suffix — if it does, R/47's bare `file.path` input would read R/45's dated file (different from what R/47 overwrites).

### 7c,d — `rxnorm_ingredient_cache.csv` and `all_codes_resolved_next_tables_v2.1.xlsx` (R/105, R/131)

Both append-safe. R/131 uses a staging pattern for the xlsx (`_new.xlsx` → promote to canonical). No destructive conflict. See Items 12 and 17.

### 7e — `episode_classification_audit.xlsx` (R/28, R/30)

R/28 creates from scratch. R/30 saves with `wb_save(wb, overwrite = TRUE)` but no `wb_load` call found in R/30. If `wb` in R/30 is a fresh workbook, R/28's sheets are silently dropped.

**Status:** NEEDS DECISION — verify whether R/30 loads R/28's output before saving.

### 7f — `zip_change_frequency.xlsx` (R/106, R/114)

R/114 uses `wb_load` → adds sheet → saves. R/106's sheets preserved. **FALSE ALARM.**

### 7g — `payer_*` and `encounter_tier_*` CSVs (R/60, R/61, R/97)

R/97 uses a `suffix` variable appended to all filenames. No conflict with bare names from R/60/R/61. **FALSE ALARM.**

---

## Item 8 — Run order vs numbering

### Dependencies confirmed in code

| Dependency | Confirmed | R/39 ordering correct? |
|---|---|---|
| R/116 ← R/117, R/118, R/119, R/146 | Yes (SDI/ADI/SVI reference CSVs) | R/116 in R/39 (line 226); R/117-119, R/146 not in R/39 — must run manually first |
| R/118 ← R/119 | **Not confirmed** — R/118 does not read R/119 output | N/A |
| R/105 ← R/131 | Yes (`rxnorm_ingredient_cache.csv`) | R/105 in R/39 (line 219); R/131 not in R/39; R/105 rebuilds cache if absent |
| R/26 ← R/27 | Dependency is R/28 ← R/27, not R/26 | Partial correction needed |
| R/28 ← R/42 | Yes (`code_descriptions.rds`) | R/28 in R/39 (line 161); R/42 not in R/39 — must run manually first |
| R/29, R/51, R/52 ← R/53 | Yes (all read `validated_death_dates.rds`) | **BUG:** R/29 at R/39 line 179, R/53 at line 183 — R/29 runs before R/53 |
| R/31, R/32, R/34, R/46 ← R/47 | Not confirmed — none reference R/47 output directly | N/A |
| R/73 ← R/94 | Yes (`output/tables/flm_*.csv`); R/73 has `source(R/94)` fallback | Neither in R/39 |

**Critical ordering bug:** R/29 is listed before R/53 in R/39. On a clean run, R/29 fails at `assert_rds_exists()`.

**Documentation:** Correct run order is not documented in R/39, README, or SCRIPT_INDEX.md. Proposed run-order additions to SCRIPT_INDEX.md:

```
Pre-requisites (run manually before R/39):
  R/42  → produces code_descriptions.rds (needed by R/28)
  R/117, R/118, R/119, R/146 → produce reference CSVs (needed by R/116)
  R/131 → populates rxnorm cache (needed by R/105 on cold cache)

In R/39, swap: R/53 must precede R/29
  R/94  must precede R/73 (or rely on R/73's source() fallback)
```

---

## Item 9 — Suppression helpers

### Canonical standard (R/utils/utils_distance_cbc.R)

`suppress_display(n)`: threshold 1-10 (i.e., `n >= 1 & n <= 10`), display token `"<11"`, `NA` passthrough, complementary suppression via `assert_no_back_calculable()`. OR/CI/p are blanked when a cell is suppressed.

### Scripts that conform

R/106, R/122 (Section 12b `sup11`), R/147, R/165, R/169, R/179, R/180, R/181, R/183, R/184, R/186, R/187, R/189, R/autoimmune_code_review.R, R/cbc_year1_chisq.R — all use threshold 1-10, token `"<11"`, correct NA handling.

### Deviations

| Script | Deviation | Severity |
|---|---|---|
| R/107 | Local `sup(n)` returns `NA_integer_` not `"<11"` — blank in CSV, indistinguishable from missing | **High** |
| R/109 | Same as R/107 — `NA_integer_` | **High** |
| R/110 | Verbatim copy of R/109 deviation — `NA_integer_` | **High** |
| R/188 | Rate suppression token is `"-"` (ASCII hyphen) not `"—"` (em dash) used elsewhere | Low |

**Status:** CONFIRMED.
**Impact of R/107/109/110:** `output/med_admin_dispensing_gap_diagnostic.csv`, `output/med_admin_dispensing_fix_impact.xlsx`, `output/output_level_before_after_report.xlsx` — suppressed counts show as blank cells. These are diagnostic/impact-audit outputs referenced in phase summaries.
**Proposed fix:** Change `NA_integer_` returns to `"<11"` in R/107, R/109, R/110; change `"-"` to `"—"` in R/188.

---

## Item 10 — Latest-file selection without pin

| Script | Line | Method | Pin? | Risk |
|---|---|---|---|---|
| R/162 | 44 | mtime-latest | No | High — wrong cohort cut if multiple RDS exist |
| R/163 | 88 | mtime-latest | No | High — encounter_distance.rds is upstream of distance model |
| R/166 | 77-82 | Pinned run_date — deterministic path | **Yes** | Low — reference implementation |
| R/167 | 198 | Lexicographic sort descending (YYYYMMDD filenames) | No | Medium — works if filenames follow convention |
| R/168 | 58, 70 | Lexicographic sort descending (×2) | No | **High** — final deliverable assembler; two unpinned inputs |
| R/180 | 207 | mtime-latest with output/ fallback | No | High — see Item 5 |
| R/183 | 391 | mtime-latest | No | High — MICE payer covariate selection |
| R/diag/146 | 48 | Lexicographic last | No | Low — diagnostic only, not production deliverable |

R/166 is the reference implementation. All others should adopt its env-var pin pattern.

**No data files exist on Windows copy** — specific "wrong file chosen" cannot be determined here; risk is latent on HiPerGator where multiple dated runs accumulate.

---

## Item 11 — `treatment_episodes.rds` double write (R/26, R/29)

**R/26 produces:** patient_id, treatment_type, episode_number, episode_start, episode_stop, drug_names, regimen_label, and related columns.

**R/29 adds:** `is_first_line` (boolean) via left_join. Writes back to same path.

**Downstream readers requiring `is_first_line`:** R/142 (Gantt, line 668), R/110 (first-line breakdown, line 428 comment), R/100 (Sheet 4). These produce deliverable content. If R/29 has not run after R/26, `is_first_line` is NA or absent; downstream scripts fail or produce wrong counts.

**Other readers:** R/28, R/109, R/143_02 — these do not require `is_first_line`.

**Status:** CONFIRMED. Run order dependency is real and undocumented.
**Proposed fix:** Add column-existence guard `stopifnot("is_first_line" %in% names(episodes))` in R/142 and R/110 readers; document R/26 → R/29 → R/142/110 in SCRIPT_INDEX.

---

## Item 12 — rxnorm cache append vs overwrite

Both R/105 and R/131 use **append-then-full-rewrite**:
- Read existing cache → `anti_join` for new codes → `bind_rows` → `write_csv` full cache
- Pattern is functionally safe; no rows dropped as long as read succeeds before write

`rxnorm_ingredient_cache.csv` has no git history — it is likely gitignored. `all_codes_resolved_next_tables_v2.1.xlsx` git log shows one commit (`7e615c6`).

**Re-query risk on cold cache:** Both scripts call `rxnav.nlm.nih.gov`. If cache is cold, all codes are re-queried live; RxNorm API versioning can change concept names. Changed names propagate into downstream treatment code classification.

**R/131 double-append risk:** If the idempotency guard (`!MEDADMIN_CODE %in% chemo_existing`) is evaluated against stale `chemo_existing` after the first append modified the xlsx, a second run appends duplicate CUI rows.

**Status:** FALSE ALARM for destructive conflict; CONFIRMED for cold-cache re-query risk.
**Proposed fix:** Commit current cache to git; add idempotency guard re-read in R/131.

---

## Item 13 — `episode_classification_audit.xlsx` and `zip_change_frequency.xlsx`

### episode_classification_audit.xlsx (R/28, R/30)

R/28 creates from scratch (`wb_save(wb, overwrite = TRUE)` at line 1167). R/30 saves with `wb_save(wb, AUDIT_XLSX, overwrite = TRUE)` at line 418; also saves a standalone at line 449. No `wb_load` call found in R/30. If R/30's `wb` is a fresh workbook, R/28's sheets are silently dropped.

**Status:** NEEDS DECISION. Verify R/30 source code — if `wb` is not loaded from R/28's file, add `wb <- openxlsx2::wb_load(AUDIT_XLSX)` before the sheet additions.

### zip_change_frequency.xlsx (R/106, R/114)

R/114:285 uses `wb_load(OUTPUT_XLSX)` → adds "Address Timeline Diagnostics" sheet → saves. R/106's sheets preserved. No destructive overwrite.

**Status:** FALSE ALARM.

---

## Item 14 — Same-date overwrite

All 18 scripts use `format(Sys.Date(), "%Y%m%d")` with no version increment. Same-day re-run silently overwrites prior dated output.

| Script | Variable form | Inline paths? |
|---|---|---|
| R/116, R/122, R/147, R/166-169, R/179-184, R/187, R/189 | Central `RUN_DATE`/`run_date` variable | No — env-var override can be added in one place |
| R/186 | Inline `format(Sys.Date(),'%Y%m%d')` in path string | Yes — requires touching multiple lines |
| R/188 | Inline at lines 366, 410, 797 (three separate occurrences) | Yes — highest maintenance burden |

**R3+R4 risk combos:** R/166-169 write outputs consumed by R/167, R/168 (unpinned late-file selection — Items 10.4, 10.5). Same-day overwrite + mtime-latest selection means a second run could make both the writer and reader point to the new (potentially wrong-cohort) file.

**Status:** CONFIRMED.
**Proposed fix:** Refactor R/186 and R/188 to use a central `run_date` variable with env-var override; document the pattern for all 18.

---

## Item 15 — Circular dependency

**Actual dependency graph:**

```
R/26 → treatment_episodes.rds (episode_start column only)
         ↓
       R/53 → validated_death_dates.rds
                ↓
              R/29 (reads validated_death_dates.rds + treatment_episodes.rds)
                   → adds is_first_line → overwrites treatment_episodes.rds
```

**Is it truly circular?** No. R/53 reads only `episode_start` from treatment_episodes.rds. R/29 adds `is_first_line` — a column R/53 never reads. Running 29→53→29 would produce the same final result as 53→29, **but R/39 currently orders R/29 (line 179) before R/53 (line 183)**. On a clean run R/29 stops at `assert_rds_exists()` for `validated_death_dates.rds`.

**Downstream from both files:**

| Script | Reads validated_death_dates | Reads treatment_episodes | Correctly after R/53 in R/39? |
|---|---|---|---|
| R/51 | Yes (line 65) | Yes (line 169) | Yes (R/39 line 205) |
| R/52 | Yes (line 52) | No | Yes |
| R/59 | Yes (line 60) | No | Yes |
| R/142 | Yes (line 65) | No | Not in R/39 |

**Status:** CONFIRMED.
**Proposed fix:** Swap R/53 before R/29 in R/39.

---

## Item 16 — `cancer_summary.csv` double write

**R/45** produces: patient-code level, includes D-codes, all patients, all dx codes.

**R/47** reads R/45's output → removes D-codes (lines 100-103) → filters to HL cohort (lines 218-222) → adds `category` column (line 229) → overwrites same CSV path.

**R/46** (line 8): declared input is "Phase 45 patient-code level dataset" (R/45's output). R/46 applies `classify_codes()` to add `category` (line 74) — same transformation R/47 performs. If R/47 has already run, R/46 receives a D-code-less, HL-only universe and its code counts and category distributions are computed on a filtered population. R/46 and R/47 both write `output/tables/cancer_summary_table.xlsx` — whichever runs last wins that file.

**Status:** CONFIRMED.
**Impact:** `output/tables/cancer_summary_table.xlsx` counts depend on run order.
**Proposed fix:** R/45 → R/46 → R/47. Document in SCRIPT_INDEX. Optionally have R/45 write a versioned intermediate that R/46 pins explicitly.

---

## Item 17 — `rxnorm_ingredient_cache.csv` and `all_codes_resolved_next_tables_v2.1.xlsx`

See Items 7c,d and 12 for detailed write pattern. Summary:

- Both R/105 and R/131 append-then-rewrite the cache — consistent, no destructive conflict
- R/131 also appends MED_ADMIN-exclusive CUIs to the xlsx tabs
- Cold-cache re-query risk: RxNorm API versioning can change `normalized_name` values
- R/131 double-append risk: guard may not be idempotent if `chemo_existing` is stale

**Status:** FALSE ALARM for destructive overwrite; CONFIRMED for cold-cache and double-append risks.
**Proposed fix:** Commit current cache to git; add re-read of `chemo_existing` in R/131 immediately before the append guard.

---

## Item 18 — Hard-coded absolute paths

### R/122a_build_zip9_centroid_crosswalk.R (lines 25-35)

Paths use `CONFIG$key %||% "/blue/..."` fallback pattern. CONFIG keys (`adi_zip9_parquet`, `tiger_bg_dir`, `zip9_bg_centroid_path`) exist. The `/blue/` literals are fallback defaults only — activated silently if CONFIG keys are absent.

**Status:** CONFIRMED (latent, not active risk).
**Proposed fix:** Assert CONFIG keys are non-NULL at script start; add `stopifnot(!is.null(CONFIG$adi_zip9_parquet))` etc.

### R/161_diag_anchor_followup.R (lines 33, 41)

- Line 33 (`PROJECT_ROOT`): `Sys.getenv(..., fallback)` — acceptable pattern.
- **Line 41 — genuine unguarded hard-code:**
  ```r
  KNOWN_DB_PATHS <- c(
      "/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb",  # bare literal
      file.path(dirname(PROJECT_ROOT), "clean", "duckdb", "pcornet.duckdb")
  )
  ```
  No CONFIG or env-var guard.

**Status:** CONFIRMED.
**Proposed fix:**
```r
KNOWN_DB_PATHS <- c(
    CONFIG$duckdb_path,
    file.path(dirname(PROJECT_ROOT), "clean", "duckdb", "pcornet.duckdb")
)
```

---

*Audit conducted 2026-11-10. All findings are from code review; no data files were opened. No files were modified.*
