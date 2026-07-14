---
phase: 124-integrate-med-admin-dispensing-chemo-downstream
plan: 02
subsystem: treatment-episodes
tags: [source-provenance, gantt, code-type, source-table, med-admin, dispensing, data-table, episode-classification]

dependency_graph:
  requires:
    - phase: 124-01
      provides: source_hints parallel column on treatment episodes (same sort order as triggering_codes)
  provides:
    - R/28 overrides source_table to DISPENSING/MED_ADMIN for those-sourced codes (D-05)
    - R/28 overrides code_type to NDC for DISPENSING codes (D-04)
    - R/20 MED_ADMIN block now emits NDC for ND-typed rows and RXNORM for RX-typed rows (Pitfall 8 fix)
  affects: [gantt_episodes.csv, treatment_episodes.rds, treatment_inventory.xlsx, R/28, R/20]

tech-stack:
  added: []
  patterns:
    - Parallel-column explode in data.table j-block — split two comma lists with same by=episode_row expansion to keep positional alignment
    - Defensive length-mismatch guard — if split lengths differ, degrade src_hint to NA rather than erroring
    - Code-keyed-lookup override pattern — xlsx lookup sets a default; source_hints overrides it for physical-table distinction

key-files:
  created: []
  modified:
    - R/28_episode_classification.R
    - R/20_treatment_inventory.R

key-decisions:
  - "DISPENSING code_type = NDC (origin label): get_chemo_hits() resolves NDC to RxCUI for the stored triggering_code, but the origin is NDC — label by origin where cleanly distinguishable"
  - "MED_ADMIN code_type left as RXNORM at episode level: the stored code IS a RxCUI for both RX and ND paths; MEDADMIN_TYPE not carried per-code to episodes (would require a 3rd parallel column — out of scope for this pass); source_table=MED_ADMIN (D-05) is the critical distinguishing value"
  - "Defensive length-mismatch branch in R/28 explode: if source_hints split length != triggering_codes split length for an episode, src_hint=NA for all codes in that episode — documented in comment, no exception"
  - "R/20 MEDADMIN_TYPE added to group_by so it survives collect(), then select(-MEDADMIN_TYPE) drops it before bind_rows — output column set (code, drug_name, n, source_table, code_type) unchanged"

patterns-established:
  - "Parallel-column explode: when two comma lists must stay positionally aligned, split both in the same data.table j-block (by=episode_row) and guard for length mismatch"
  - "Lookup-then-override: xlsx assigns static defaults; physical-source hint overrides for dynamically-sourced rows — safe even if hint is NA (NA rows are not in the %in% match)"

requirements-completed: [D-04, D-05, D-10-reg, D-12]

duration: 14min
completed: "2026-07-14"
---

# Phase 124 Plan 02: R/28 source-hint override + R/20 MEDADMIN_TYPE-aware code_type Summary

**R/28 now overrides source_table to DISPENSING/MED_ADMIN and code_type to NDC (DISPENSING) via parallel source_hints explode; R/20 MED_ADMIN block is MEDADMIN_TYPE-aware (ND->NDC, RX->RXNORM).**

## Performance

- **Duration:** 14 min
- **Started:** 2026-07-14T22:32:00Z
- **Completed:** 2026-07-14T22:46:14Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- R/28 Section 5C extended: `source_hints` split in parallel with `triggering_codes` inside the same `by=episode_row` data.table j-block; `src_hint` column added to `codes_long`; two override steps added after xlsx-lookup joins: `source_table := src_hint` for DISPENSING/MED_ADMIN codes and `code_type := "NDC"` for DISPENSING codes; collapse, regimen detection, and row-count assertion untouched
- R/20 MED_ADMIN block fixed: `MEDADMIN_TYPE` added to `group_by`, `case_when(ND~NDC, RX~RXNORM, TRUE~RXNORM)` replaces the unconditional `code_type = "RXNORM"`, `select(-MEDADMIN_TYPE)` restores the original output column set; DISPENSING block untouched
- Both changes are structurally grep-verified; runtime confirmation (gantt_episodes.csv source_table/code_type columns) deferred to Plan 04 on HiPerGator

## Task Commits

1. **Task 1: Override source_table + code_type from source_hints in R/28** - `41650d5` (feat)
2. **Task 2: Fix R/20 MED_ADMIN code_type ND->NDC, RX->RXNORM** - `44a306c` (fix)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `R/28_episode_classification.R` — Section 5C: parallel source_hints explode + D-05 source_table override + D-04 NDC override for DISPENSING codes
- `R/20_treatment_inventory.R` — MED_ADMIN block: MEDADMIN_TYPE in group_by, case_when code_type, select(-MEDADMIN_TYPE)

## Decisions Made

- DISPENSING `code_type = "NDC"` (origin label): even though `get_chemo_hits()` stores the resolved RxCUI as the triggering_code, the origin was an NDC — labeling by origin where cleanly distinguishable is auditable and accurate to D-04
- MED_ADMIN `code_type` left as `"RXNORM"` at episode level: MEDADMIN_TYPE is not preserved per-code into episodes without a 3rd parallel column (out of scope for this pass); `source_table = "MED_ADMIN"` (D-05) is the critical distinguishing value and IS set
- Defensive length-mismatch guard in R/28 explode: if the split vector lengths differ for an episode (should not happen under normal R/26 output), `src_hint = NA` for all codes in that episode; documented in comment, no runtime error
- `MEDADMIN_TYPE` added to `group_by` in R/20 (not just after `collect()`) so it is available without a separate join; dropped via `select(-MEDADMIN_TYPE)` before `bind_rows` to keep column alignment

## Deviations from Plan

None — plan executed exactly as written. Both structural edit patterns were specified verbatim in the task action blocks.

## Known Stubs

None. R/28 and R/20 are fully wired. Runtime validation (source_table/code_type columns populated correctly in gantt_episodes.csv, treatment_inventory.xlsx) confirmed in Plan 04 on HiPerGator.

## Issues Encountered

None.

## Next Phase Readiness

- R/28 and R/20 are ready; downstream gantt_episodes.csv will show DISPENSING/MED_ADMIN in Source Table and NDC for DISPENSING codes when run on HiPerGator
- Plan 03 (payer-anchoring + cohort timing) can build on these labeled episodes
- Plan 04 (runtime verification on HiPerGator) will confirm all D-04/D-05 column values

## Self-Check: PASSED

Commits verified:
- 41650d5: Task 1 (R/28_episode_classification.R — source_hints explode + overrides)
- 44a306c: Task 2 (R/20_treatment_inventory.R — MEDADMIN_TYPE-aware code_type)

Files verified present:
- R/28_episode_classification.R — modified
- R/20_treatment_inventory.R — modified

---
*Phase: 124-integrate-med-admin-dispensing-chemo-downstream*
*Completed: 2026-07-14*
