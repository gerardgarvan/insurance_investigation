---
phase: "161"
plan: "04"
subsystem: follow-up computation
tags: [compute_followup, fu_status, death_flag, D6, backward-compat]
dependency_graph:
  requires: [161-03]
  provides: [compute_followup-v2]
  affects: [147_surveillance_modality_frequency, any caller of compute_followup]
tech_stack:
  added: []
  patterns: [column-fingerprint deprecation shim, D6 posthumous-dx override]
key_files:
  modified:
    - R/utils/utils_surveillance.R
decisions:
  - "Backward-compat shim uses column fingerprint (last_enc_date vs last_observed) to detect legacy callers automatically — no changes required to R/147 until 161-07."
  - "fu_days and person_years floored at 0 via pmax; negative raw values become 0 in person_years but fu_status still reports 'negative' for diagnostic visibility."
  - "D6 override sets follow_end = hl_anchor_date, preserving the patient in the denominator; fu_status becomes 'zero' rather than 'negative'."
metrics:
  duration_minutes: ~15
  completed: "2026-10-01"
  tasks_completed: 1
  files_modified: 1
---

# Phase 161 Plan 04: compute_followup() — Shared Activity, Resolved Death, 3-Level fu_status

One-liner: Rewrote `compute_followup()` to consume `get_last_activity()` and `resolve_death_date()` outputs, apply D2/D6 rules, and emit `fu_status` as `positive`/`zero`/`negative` with a `fu_reason` column.

## Old vs New Signature

**Old (pre-161):**
```r
compute_followup(denominator, last_enc, death, cutoff)
# last_enc:  ID, last_enc_date   (encounter-only, admit date)
# death:     ID, death_date      (raw; multiple rows per ID allowed)
# returns:   ID, hl_anchor_date, last_enc_date, death_date, follow_end,
#            fu_days, fu_status ("ok"/"zero_or_negative"/"no_followup_date"),
#            person_years
```

**New (161-04):**
```r
compute_followup(denominator, activity, death_resolved, cutoff,
                 last_enc = NULL, death = NULL)
# activity:       ID, last_enc_any, last_activity_any, last_observed
#                 — output of get_last_activity() (utils_activity.R)
# death_resolved: ID, death_date_resolved, death_flag
#                 — output of resolve_death_date() (utils_death.R)
# returns:   ID, hl_anchor_date, last_enc_any, last_activity_any,
#            last_observed, obs_end, death_date_resolved, death_flag,
#            follow_end_raw, posthumous_dx, follow_end,
#            fu_days, fu_status, fu_reason, person_years
```

## The Three fu_status Levels

| Value | Condition | Expected frequency |
|---|---|---|
| `"positive"` | `follow_end > hl_anchor_date` | Vast majority of cohort |
| `"zero"` | `follow_end == hl_anchor_date` | Same-day last contact; also D6 cases where posthumous dx overrides follow_end to anchor |
| `"negative"` | `follow_end < hl_anchor_date` | Should be 0 after D6 fix; diagnostic signal if nonzero |

`fu_reason` values: `"posthumous_dx"`, `"same_day_last_contact"`, `"check_definition"` (negative), or `NA` (positive without special condition).

## D2: Credible Death Definition

`death_date_resolved` is `NA` when `resolve_death_date()` judged the recorded death implausible (activity recorded more than `grace_days` after death, no consistent date across sources). When `NA`, `pmin(..., na.rm = TRUE)` excludes it and censoring falls at `obs_end`. The patient is NOT treated as dead.

## D6: Posthumous Diagnosis Override

`posthumous_dx = !is.na(death_date_resolved) & death_date_resolved < hl_anchor_date`.

When TRUE, `follow_end` is set to `hl_anchor_date` (not `follow_end_raw`). This prevents the patient from contributing negative person-time while keeping them in the denominator with at least zero follow-up days. `fu_reason = "posthumous_dx"`.

## How death_flag Flows Through

`resolve_death_date()` assigns one of: `plausible`, `conflicting_resolved`, `implausible_post_activity`, `conflicting_unresolved`, `no_death_record`. `compute_followup()` joins this column and carries it untouched. Patients absent from `death_resolved` receive `"no_death_record"` via `dplyr::coalesce()`.

Callers can filter or tabulate `death_flag` directly from the `followup` tibble — no secondary join to a death table is needed.

## Backward-Compatibility Shim

The old positional call `compute_followup(denominator, last_enc, death, cutoff)` maps `last_enc`-data into the `activity` parameter and `death`-data into `death_resolved`. The shim detects this by column fingerprint:

- `"last_enc_date" %in% names(activity) && !"last_observed" %in% names(activity)` → legacy enc path
- `"death_date" %in% names(death_resolved) && !"death_date_resolved" %in% names(death_resolved)` → legacy death path

When either trigger fires:
1. A deprecation warning is emitted (message references 161-07 as the removal milestone).
2. The legacy tibble is reshaped to match the new column contract (`last_enc_date` → `last_enc_any`, `death_date` min-aggregated → `death_date_resolved`).
3. Execution continues through the new core logic unchanged.

**R/147_surveillance_modality_frequency.R** (the one identified caller) requires no code change until 161-07.

## What Callers Need to Handle

- `fu_status == "zero_or_negative"` and `"no_followup_date"` no longer exist. Any downstream `case_when` or `filter` on those values must be updated to `"zero"` / `"negative"`.
- New output columns (`obs_end`, `posthumous_dx`, `follow_end_raw`, `fu_reason`, `death_flag`, `death_date_resolved`, `last_enc_any`, `last_activity_any`, `last_observed`) will appear in the result tibble; callers that `select()` specific columns are unaffected.
- `person_years` is now always >= 0 (floored via `pmax(0, ...)`); old code floored implicitly by the `fu_status == "ok"` guard.

## Deviations from Plan

### Auto-added: backward-compat column-fingerprint shim

**Rule:** 2 (missing critical functionality — without it the positional legacy call silently passes wrong-structured data into the new core logic)
**Found during:** Task implementation
**Issue:** New positional parameter order (`activity` before `death_resolved`) means old `compute_followup(denominator, last_enc, death, EXTRACT_CUTOFF)` calls would pass `last_enc`-shaped data into `activity` and `death`-shaped data into `death_resolved`, causing join failures or silent wrong results.
**Fix:** Added column-fingerprint detection at function entry; reshaped legacy tibbles before the core logic runs; emits deprecation warning in all legacy paths.
**Files modified:** `R/utils/utils_surveillance.R`
**Commit:** b7ec36e

## Known Stubs

None. The function is complete and self-contained; the D6 and D2 rules are fully implemented.

## Self-Check: PASSED

- `R/utils/utils_surveillance.R` modified: confirmed (128 lines added, 19 removed per commit output).
- Commit b7ec36e exists on main.
- No new untracked files generated.
