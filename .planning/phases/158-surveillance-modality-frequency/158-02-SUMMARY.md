---
phase: 158-surveillance-modality-frequency
plan: "02"
subsystem: surveillance-utils
tags: [counting-functions, TDD, presence-audit, follow-up, suppression]
dependency_graph:
  requires:
    - 158-01 (load_surveillance_codeset, normalize_surv_code, surv_components, hl_any_dx_from_tibble)
  provides:
    - match_coded_events()
    - build_component_events()
    - build_code_presence()
    - compute_followup()
    - classify_event_window()
    - compute_modality_stats()
    - build_patient_modality()
    - suppress_small()
    - suppress_table()
  affects:
    - R/utils/utils_surveillance.R
    - tests/testthat/test-158-surveillance-counts.R
tech_stack:
  added: []
  patterns:
    - Pure function utils module (no DuckDB, no CONFIG)
    - TDD RED-GREEN with synthetic fixture data
    - Component-all-same-day rule with near_miss reporting
    - Pooled person-years denominator (whole cohort, not per-event patients)
key_files:
  created:
    - tests/testthat/test-158-surveillance-counts.R
  modified:
    - R/utils/utils_surveillance.R
decisions:
  - "type_ok flag retained on matched events; type_filter mismatch rows excluded from counts but reported (n_records_other_type, other_types)"
  - "component_all_same_day: near_miss counts ID x dates with partial components"
  - "compute_modality_stats pools person-years over whole denominator, not just event patients (D-26)"
  - "anchor-day events are pre by default; anchor_day_is_post parameter toggles (D-25)"
metrics:
  duration_minutes: 3
  tasks_completed: 1
  tasks_total: 1
  files_created: 1
  files_modified: 1
  completed_date: "2026-09-24"
---

# Phase 158 Plan 02: Counting Functions and Synthetic-Fixture Tests

**One-liner:** Appended 9 pure counting functions to utils_surveillance.R covering code matching, component-all-same-day, code presence, follow-up, event windowing, modality frequency, patient-level output, and small-cell suppression; pinned by 40 synthetic-fixture expectations.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 (RED) | Add failing test file for all counting rules | 91da34d | tests/testthat/test-158-surveillance-counts.R |
| 1 (GREEN) | Append counting functions to utils_surveillance.R | 56472cb | R/utils/utils_surveillance.R |

## Key Decisions

1. **type_ok flag design** — `match_coded_events()` retains rows whose `PX_TYPE`/`DX_TYPE` does not match `type_filter` (marks `type_ok = FALSE`). `build_code_presence()` routes these to `n_records_other_type` / `other_types`, making legacy codes like `C4`/`HC` visible without polluting counts. Matches D-29 exactly.
2. **Pooled person-years** — `compute_modality_stats()` divides total event dates by `sum(followup$person_years)` over the whole denominator, not just patients with events. This implements D-26: rates are not inflated by restricting the denominator to event-patients.
3. **Zero-count rows preserved** — `compute_modality_stats()` uses a `left_join` from `keys` into stats, ensuring every modality key row is in the output even with zero events. Consistent with A_code_presence rule (D-18).

## Deviations from Plan

None — plan executed exactly as written.

## Verification (Structural Fallback — Rscript unavailable on Windows dev host)

Per plan `<verification>` section, since `Rscript` is not available in this Windows environment, the structural fallback was applied:

- **Brace/paren balance:** utils_surveillance.R balances at 0 (braces: 21/21, parens: 406/406).
- **All 15 exported functions present** (verified via Python pattern count — each appears at minimum twice: definition + reference):
  - `match_coded_events`, `build_component_events`, `build_code_presence` — confirmed
  - `compute_followup`, `classify_event_window`, `compute_modality_stats` — confirmed
  - `build_patient_modality`, `suppress_small`, `suppress_table` — confirmed
  - `load_surveillance_codeset`, `normalize_surv_code`, `surv_components` — confirmed (part 1)
  - `surv_sql_in`, `surv_code_where`, `hl_any_dx_from_tibble` — confirmed (part 1)

**Testthat run deferred to HiPerGator** — 158-04 Task 2 must run `testthat::test_dir('tests/testthat', filter = '158', stop_on_failure = TRUE)` on HiPerGator before anything that depends on counting functions executes against real data. 40 new expectations + 28 from 158-01 = 68 total pending real execution.

## Known Stubs

None.

## Self-Check: PASSED

- [x] R/utils/utils_surveillance.R exists and is extended (243 lines added)
- [x] tests/testthat/test-158-surveillance-counts.R exists (145 lines, 40 expectations)
- [x] Commits 91da34d (RED) and 56472cb (GREEN) present in git log
- [x] Brace/paren balance verified at 0
- [x] All 9 new functions + 6 part-1 functions present in file
