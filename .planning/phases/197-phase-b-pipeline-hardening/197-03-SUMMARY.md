---
phase: 197
plan: "03"
name: pin-unpinned-latest-file-picks
status: complete
completed: 2026-11-11
duration_min: 35
tasks_completed: 6
files_created: 1
files_modified: 8
commit: 52b3d48
tags: [refactor, io, pinning, hardening]
key_decisions:
  - "D-197-03: resolve_input() is the canonical helper for dated input resolution; R/183's bespoke load_pin() helper is left in place (D-15 contract; not migrated)"
  - "D-197-03b: R/191 optional SES pick (warn-and-continue) deliberately left unpinned"
  - "D-197-03c: R/165 ses_path optional pick deliberately left unpinned (warn-not-stop pattern)"
---

# Phase 197 Plan 03: Pin Unpinned Latest-File Picks — Summary

**One-liner:** `resolve_input()` helper centralises env-var override + version-aware sort + stop-on-missing; applied to 7 scripts replacing bare `list.files`/`file.mtime` picks.

## Objective

22 scripts used `list.files()` / `file.mtime()` to pick the "latest" dated output with no reproducibility guarantee. This plan extracts the pinning pattern into a shared helper and applies it to the highest-risk scripts.

## Tasks Completed

| Task | Description | Outcome |
|------|-------------|---------|
| 0 | Grep reference implementation (R/165, R/166) + audit list | Done — R/165 inline pattern extracted |
| 1 | Create `resolve_input()` in `R/utils/utils_io.R` | Done — auto-sourced by 00_config.R |
| 2 | Apply to 6 high-priority scripts (R/162–R/183) | Done — R/183 already fully pinned (D-15) |
| 3 | Apply to remaining scripts (R/177, R/179) | Done |
| 4 | Version-suffix sort correctness | Done — `ver_key()` logic in helper |
| 5 | Parse checks (brace + paren balance) | Passed — all 0 |
| 6 | Commit | 52b3d48 |

## Pinned Scripts

| Script | Input Label | Env Var | Notes |
|--------|-------------|---------|-------|
| R/162 | patient_modality_dates | `R162_PATIENT_MODALITY_RDS` | Was: `file.info()$mtime` |
| R/163 | enc_distance | `R163_R122_RDS` | Was: `file.mtime()` |
| R/167 | treatment_episode_detail_180 | `R167_EPISODE_RDS` | Was: `sort()[1L]` |
| R/167 | survivorship_dated_events | `R167_DATED_EVENTS_RDS` | Was: `sort()[1L]` |
| R/167 | survivorship_rates_parts (follow-up) | `R167_RATES_PARTS_RDS` | Was: `sort()[1L]` |
| R/167 | surveillance_modality_patient (fallback) | `R167_SURV_PATIENT_RDS` | Was: `sort()[1L]` |
| R/168 | survivorship_rates_parts | `R168_RATES_PARTS_RDS` | Was: `sort()[1L]` |
| R/168 | survivorship_echo_parts | `R168_ECHO_PARTS_RDS` | Was: `sort()[1L]` |
| R/180 | enc_distance (fallback) | `R180_R122_RDS` | Env var pre-existing; fallback now uses helper |
| R/180 | single_source_care (fallback) | `R180_R169_RDS` | Env var pre-existing; fallback now uses helper |
| R/179 | enc_distance (fallback) | `R179_R122_RDS` | Env var pre-existing; fallback now uses helper |
| R/179 | zip_problem_inventory (fallback) | `R179_R121_RDS` | Env var pre-existing; fallback now uses helper |
| R/177 | zip_problem_inventory | `R177_R121_RDS` | Was: `file.mtime()` with partial env-var guard |
| R/177 | enc_distance | `R177_R122_RDS` | Was: `file.mtime()` with partial env-var guard |

## Deliberately Left Unpinned

| Script | Pick | Reason |
|--------|------|--------|
| R/183 | All 5 inputs | Already fully pinned with bespoke `load_pin()` (D-15); migration not needed |
| R/165 (line 187) | enc_ses_index (R/116) | Optional input — warns and continues with empty tibble; stop() would break runs where R/116 not available |
| R/191 (line 890) | enc_ses_index (R/116) | Soft optional — empty string default, outer `if(nchar > 0)` guard handles missing gracefully |
| R/86, R/87, R/88, R/89 | Various `list.files` | Smoke-test/tooling scripts scanning codebase structure — not production input picks |
| R/01 | cache mtime comparisons | File-freshness logic, not an input resolution pick |
| R/119, R/122a | Directory scans | Enumerate all files in a directory by design |
| R/164 | detail_path `file.mtime` display | Display only (mtime shown in message), path already resolved upstream |

## Deviations from Plan

None. Plan executed as written. R/183 is confirmed as already fully pinned (D-15), documented above.

## Helper: resolve_input()

**File:** `R/utils/utils_io.R` (auto-sourced by `R/00_config.R` D-04 glob)

Behaviour:
1. If `env_var` is set → use that path; stop if file missing; log `(pinned=TRUE)`.
2. If unset → `list.files(dir, pattern)`; apply version-aware sort (`_vN` numeric desc, then alphabetical desc for YYYYMMDD-stamped files); use first candidate; log `(pinned=FALSE)`.
3. Stop if no candidates found.

Version sort: `_v10` > `_v2` via `ver_key()` extracting numeric N; date-stamped files fall back to alphabetical descending (correct for YYYYMMDD).

## Self-Check

- `R/utils/utils_io.R` exists: FOUND
- Commit 52b3d48 exists: FOUND
- Brace balance: all 8 edited files = 0
- Paren balance: utils_io.R = 0, R/167 = 0

## Self-Check: PASSED
