---
phase: 168-nhl-only-and-hl-nhl-gantt-episode-subsets
plan: 01
subsystem: gantt-episode-subsets
tags: [nhl, hl-nhl, gantt, chemo-combos, episode-subsets, internal]
dependency_graph:
  requires:
    - R/142_gantt_180_export.R (gantt_episodes_180.csv snapshot, 2026-08-14)
    - chemo-combos workbook (HiPerGator only)
    - R/00_config.R (Phase 168 CONFIG keys)
  provides:
    - output/internal/nhl_gantt_subsets_<date>.xlsx (KEY/NHL_only_episodes/HL_NHL_episodes/QC)
    - output/internal/nhl_only_episodes_<date>.csv
    - output/internal/hl_nhl_episodes_<date>.csv
  affects:
    - R/39_run_all_investigations.R (registered)
    - R/88_smoke_test_comprehensive.R (SMOKE-168-01)
tech_stack:
  added: [readxl (sheet read with col_types="text")]
  patterns:
    - probe-first gate (IS_LOCAL NULL paths, file.exists check, silent skip)
    - norm_key() applied both sides of join (trim + strip .0+$ + empty->NA)
    - chemo-only E-J join via row-split/rejoin preserving order with .row index
    - stopifnot invariants for row-count and E-J placement
    - tools::md5sum + file.size snapshot identity with warning on mismatch
key_files:
  created:
    - R/170_nhl_gantt_subsets.R
    - tests/testthat/test-170-nhl-gantt-subsets.R
    - slurm/168_nhl_gantt_subsets.sbatch
  modified:
    - R/00_config.R (Phase 168 CONFIG block + MD5 pinned)
    - R/39_run_all_investigations.R (R/170 registration)
    - R/88_smoke_test_comprehensive.R (Section 15aq SMOKE-168-01)
    - R/SCRIPT_INDEX.md (R/170 row, count 112->113)
decisions:
  - "chemo_value = 'Chemotherapy' confirmed from R/20_treatment_inventory.R (mutate(treatment_type = 'Chemotherapy'))"
  - "gantt_180_snapshot_md5 pinned to 69dc62e86be8e0647f6a4623dda901b6 from confirmed HiPerGator run"
  - "Tasks 2-4 implemented in single commit with Task 1 (all target same file R/170); documented as deviation"
metrics:
  duration_minutes: ~45
  completed_date: "2026-10-08"
  tasks_completed: 5
  files_created: 3
  files_modified: 5
requirements_completed: [NHLSUB-01, NHLSUB-02, NHLSUB-03, NHLSUB-04]
---

# Phase 168 Plan 01: NHL-Only and HL+NHL Gantt Episode Subsets Summary

**One-liner:** Strict NHL-only (849 patients) and HL+NHL (176 patients, 0 overlap) subsets of the pinned 2026-08-14 `gantt_episodes_180` snapshot, with chemo-combos columns E-J left-joined at (patient_id, episode_number) grain on chemo rows only, verified by snapshot MD5 and drug-name cross-check (1,134 exact, 0 mismatches).

## What Was Built

`R/170_nhl_gantt_subsets.R` produces two filtered views of the 2026-08-14 `gantt_episodes_180.csv` snapshot:

- **NHL_only_episodes** — all gantt rows for patients where every chemo-combos episode is marked `Definitely NHL` and none are `Definitely HL` or `HL and NHL` (Group 1 strict: 849 patients)
- **HL_NHL_episodes** — all gantt rows for patients where any episode is marked `HL and NHL` (Group 2: 176 patients, 0 overlap with Group 1)

Both datasets have chemo-combos columns E-J (`Definitely HL`, `Definitely NHL`, `Initial`, `Relapse`, `Notes`, `HL and NHL`) left-joined onto chemo rows only (`treatment_type == "Chemotherapy"`); all other treatment types (Radiation, SCT, Death, HL Diagnosis) have E-J columns as NA, enforced by `stopifnot`.

Delivered as:
- `output/internal/nhl_gantt_subsets_20261008.xlsx` (KEY / NHL_only_episodes / HL_NHL_episodes / QC)
- `output/internal/nhl_only_episodes_20261008.csv`
- `output/internal/hl_nhl_episodes_20261008.csv`

## HiPerGator Run Results (2026-10-08)

| Metric | Value |
|--------|-------|
| Tests | 39 PASS / 0 FAIL |
| Snapshot size | 6,549,041 bytes (matches CONFIG exactly) |
| Snapshot MD5 | 69dc62e86be8e0647f6a4623dda901b6 (pinned) |
| Group 1 strict (NHL-only) | 849 patients |
| Group 2 (HL+NHL) | 176 patients |
| Group overlap | 0 |
| Unexpected E/F/J values | 0 |
| drug_names: exact matches | 1,134 |
| drug_names: normalised-only | 0 |
| drug_names: mismatches | 0 |
| SMOKE-168-01 | 9 PASS / 0 FAIL |

## Deviations from Plan

### Structural

**1. [Tasks 2-4 collapsed into Task 1 commit]**
- **Found during:** Implementation
- **Issue:** Tasks 2, 3, and 4 all target the same file (`R/170_nhl_gantt_subsets.R`). Writing the file once with all sections was more reliable than writing it in 3 partial passes that would each leave the file in a broken/incomplete state between commits.
- **Fix:** All SECTION 1B-4 code written in a single pass; committed as Task 1. Verified all required greps for Tasks 2, 3, and 4 before the Task 5 commit. No code was missed or incorrectly omitted.
- **Impact:** 2 commits instead of 5 for the implementation; functionally equivalent.

### Auto-Fixed

None — plan executed correctly with the single structural deviation above.

## Known Stubs

None — all outputs are wired to real data from the HiPerGator-confirmed inputs.

## Self-Check: PASSED

- R/170_nhl_gantt_subsets.R: present (created in commit 32c6bf9)
- tests/testthat/test-170-nhl-gantt-subsets.R: present (created in commit 32c6bf9)
- slurm/168_nhl_gantt_subsets.sbatch: present (created in commit 40f9fa6)
- Commits verified: 32c6bf9, 40f9fa6, 5064b5c
- SMOKE-168-01: 9 PASS / 0 FAIL (HiPerGator confirmed)
- Workbook approved (Task 7 human-verify gate passed)
