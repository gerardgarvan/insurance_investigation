---
phase: quick
plan: 261111-cxn
type: summary
date: 2026-11-11
commit: 6637ec4
files_modified:
  - R/109_med_admin_dispensing_fix_impact_audit.R
  - R/110_output_level_before_after_report.R
---

# Quick Task 261111-cxn: Fix suppress_small Applied Before Arithmetic

**One-liner:** Deferred suppress_small() to display-only in R/109 and R/110 so delta, sort, and join arithmetic all operate on raw integers.

## Problem

Commit 338ba5f introduced suppress_small() calls inside summarise/tibble constructors. Because suppress_small() returns character `"<11"` for counts 1–10, any subsequent arithmetic (`delta = after - before`, `arrange(desc(delta_pts))`) crashes with "non-numeric argument to binary operator".

## Call-Site Classification and Changes

### R/107 — no changes (all call sites SAFE)

| Line | Call | Classification | Action |
|------|------|----------------|--------|
| 212, 218 | `n_patients = suppress_small(...)` in list() → bind_rows → CSV | SAFE | None |
| 335, 341, 347, 353, 395, 401 | Same pattern | SAFE | None |
| 415 | `headline_new_patients <- suppress_small(...)` → glue() only | SAFE | None |
| 417 | `headline_earlier <- suppress_small(...)` → glue() only | SAFE | None |

### R/109 — two unsafe sites fixed

**Fix 1: df_before_after_summary (lines 240–268)**

| Before | After |
|--------|-------|
| `before = c(suppress_small(n_distinct(before$ID)), nrow(before))` | `before = c(n_distinct(before$ID), nrow(before))` (raw integer) |
| `after = c(suppress_small(n_distinct(after$ID)), nrow(after))` | `after = c(n_distinct(after$ID), nrow(after))` (raw integer) |
| `mutate(delta = after - before)` crashed on character | `delta` computed directly in `df_before_after_summary_raw` from raw integers |
| — | Display table `df_before_after_summary` created separately with `before_disp`, `after_disp`, `delta_disp`; delta blanked (NA_character_) when either endpoint < 11 |
| — | `stopifnot()` guard on `before` and `delta` integer types before suppression |

**Fix 2: df_ingredient_delta sort on character (line 331)**

| Before | After |
|--------|-------|
| `mutate(across(c(n_pts_before, n_pts_after, delta_pts), suppress_small))` before `arrange(desc(delta_pts))` | `df_ingredient_delta_raw` built with raw integers; `arrange(desc(delta_pts))` on numeric |
| suppress_small applied before sort | Display table `df_ingredient_delta` created after sort with `_disp` columns; `delta_pts` blanked when either endpoint < 11 |
| — | `stopifnot()` guard on `delta_pts` integer type |

**Remaining SAFE sites in R/109 (unchanged):**

| Line | Call | Reason safe |
|------|------|-------------|
| 234 | `n_patients = suppress_small(n_distinct(ID))` in df_source_counts | No arithmetic on n_patients after |
| 301 | `n_patients_earlier = suppress_small(...)` in df_timing_shift | glue() display only |
| 572 | `n_patients = suppress_small(n_distinct(ID))` in combined_freq | sort is on n_rows, not n_patients |

### R/110 — compute_episode_summary helper fixed

**Fix: remove suppress_small from helper; apply at display join (lines 220–268)**

| Before | After |
|--------|-------|
| `pts_any_chemo <- suppress_small(dplyr::n_distinct(...))` | `pts_any_chemo <- dplyr::n_distinct(...)` (raw integer) |
| `pts_dispensing <- suppress_small(dplyr::n_distinct(...))` | `pts_dispensing <- dplyr::n_distinct(...)` (raw integer) |
| `pts_med_admin <- suppress_small(dplyr::n_distinct(...))` | `pts_med_admin <- dplyr::n_distinct(...)` (raw integer) |
| `df_summary` join immediately did `delta = after - before` on character | `df_summary_raw` joins raw integer columns; `delta = after - before` computed numerically |
| — | `stopifnot()` guards on integer types of before/after/delta in df_summary_raw |
| — | `patient_count_metrics` vector identifies which rows need suppression |
| — | Display table `df_summary` created with `before_disp`, `after_disp`, `delta_disp`; delta blanked when either endpoint < 11 |

**R/110 SAFE sites (unchanged):**

| Line | Call | Reason safe |
|------|------|-------------|
| 393 | `n_patients = suppress_small(dplyr::n())` in df_timing_summary | No arithmetic on n_patients after |
| 435 | `n_patients = suppress_small(dplyr::n_distinct(...))` in df_payer | No arithmetic after |
| 500 | `n_patients = suppress_small(...)` in df_unmapped (detail RDS path) | sort on n_episodes |
| 545 | `n_patients = suppress_small(...)` in df_unmapped (fallback path) | sort on n_episodes |

## Verification

- Brace balance: both files BALANCED
- grep confirm: all suppress_small calls appear only in `_disp` assignments, final display mutate blocks, or glue() messages
- No suppress_small call feeds arithmetic, sort, or filter in either file

## Deviations

None — plan executed as written.

## Self-Check

- R/109 commit: 6637ec4 — FOUND
- R/110 commit: 6637ec4 — FOUND (same commit)
- SUMMARY.md: this file
