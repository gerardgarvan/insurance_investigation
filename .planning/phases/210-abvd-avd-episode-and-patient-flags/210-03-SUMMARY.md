---
phase: 210-abvd-avd-episode-and-patient-flags
plan: 03
requirements-completed: [ABVD-01, ABVD-02, ABVD-03]
key-files:
  modified: [R/206_apply_decisions_gantt180.R]
---

# Phase 210 Plan 03: R/206 flag recompute Summary

R/206 now recomputes abvd_episode / avd_episode with `compute_abvd_avd_flags()` and writes a 34-column Gantt file plus a flag dictionary CSV.

## What changed (R/206_apply_decisions_gantt180.R)
- Sources `R/00_config.R`; `stopifnot(exists("compute_abvd_avd_flags"))`; `ABVD_EPISODE_CLASSES` removed; `SCHEMA_34` added.
- Helper call passes `abvd_class = out$abvd_class` (final, after decision logic) and `code_text = out$triggering_codes`. Overlap of the two flags halts the run.
- `ever_abvd` / `ever_avd` via `patient_ever_flag()`; `ever_abvd_plus` keeps old definition (commented DEPRECATED). `abvd_jcode_fallback` is not written to the output (34 cols).
- QC: SCHEMA_34 checks and read-back; constancy loop includes `ever_avd`; ever_* equals any(episode flag); flags only on Chemotherapy rows; no row with both flags. The old stop on abvd_episode differing from base is now an informational base-vs-new cross-tab (all four cells, suppressed) and avd_episode TRUE counts by abvd_class.
- Console: ever_avd patients, abvd/avd episode counts, and "JCODE_ABVD fallback episodes (no drug/code evidence, abvd_episode kept TRUE): <count>" (all via `fmt_sup`).
- Writes `output/gantt_episodes_180_flag_dictionary.csv` (dictionary rows plus `qc: jcode_abvd_fallback_episodes`, count 1-10 shown as `<11`, in the definition column; level and status = `qc`).
- Unchanged: decision logic, pinned inputs, PRE_COPY no-overwrite, CHANGES_CSV, EXPECTED_ROWS.

## Task 0
- Probe: `.planning/schemas/203_schema_inputs_20261114.md` section 2; `SCHEMA_32` (R/206) contains `triggering_codes` and `abvd_class`, confirmed in the constant.

## Verification
- `tools/rcheck.sh parse R/206_apply_decisions_gantt180.R`: 0 failed.
- `tools/rcheck.sh test 210`: 0 failures, 0 errors (warning: reference Excel absent locally, unrelated).
- Real run: PENDING HIPERGATOR (plan 04).

## Assumptions
- Dictionary QC row stores the suppressed count in the `definition` column.
- Whether `triggering_codes` holds J-codes for chemo rows is unconfirmed (see 210-01); verify on HiPerGator via the fallback count.

## Deviations from Plan
- User adjustment: J-code evidence and fallback arguments, fallback QC line and dictionary row (above).

## Self-Check: PASSED
