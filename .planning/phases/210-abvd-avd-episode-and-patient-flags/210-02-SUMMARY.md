---
phase: 210-abvd-avd-episode-and-patient-flags
plan: 02
requirements-completed: [ABVD-01, ABVD-02, ABVD-03]
key-files:
  modified: [R/142_gantt_180_export.R, R/SCRIPT_INDEX.md]
---

# Phase 210 Plan 02: R/142 ABVD/AVD flags wiring Summary

R/142 now derives `abvd_episode` / `avd_episode` from `drug_names` plus J-code evidence (`triggering_codes`) through `compute_abvd_avd_flags()`, exports 34 columns, and writes an aggregate-only flag dictionary.

## What changed
- `R/142_gantt_180_export.R` Section 4C4: `compute_abvd_avd_flags(drug_names, treatment_type, abvd_class = abvd_class, code_text = triggering_codes)`. `abvd_class` unchanged (descriptive; used only for the JCODE_ABVD fallback). `ever_abvd` / `ever_avd` = `any()` over full patient history. `ever_abvd_plus` commented DEPRECATED. Message prints `AVD_INCLUDES_BV_NIVO`.
- stopifnot additions: mutual exclusion, avd only on Chemotherapy rows, `ever_avd` not NA, `ever_abvd` / `ever_avd` identical to `patient_ever_flag()`.
- QC "Phase 210 flags" sub-block (all counts via `fmt_sup`, no IDs): episode and patient counts, both-flag patients, `ever_abvd_plus`, `abvd_class` x flag cross-tabs, old-rule vs new-rule disagreement counts, and the line `JCODE_ABVD fallback episodes (no drug/code evidence, abvd_episode kept TRUE): <n>`.
- `abvd_jcode_fallback` is not exported. `EPISODES_SCHEMA` and final `select()` append `avd_episode`, `ever_avd` (34 columns; 1-32 unchanged). Header comment and Section 6 message updated.
- After the episodes CSV write: `output/gantt_episodes_180_flag_dictionary.csv` = `abvd_flag_dictionary()` plus row `column = "qc: jcode_abvd_fallback_episodes"`, `level = qc`, `definition = <suppressed count string>` (1-10 -> `<11`), `status = qc`. Phase 211 can read it.
- `R/SCRIPT_INDEX.md`: R/142 mention (34 columns, Phase 210, dictionary) and R/206 row (34 columns, four flags recomputed). No utils module rows exist in the index (no `utils_regimen` entry), so no utils row added.
- Plan wording change: plan assumed JCODE_ABVD with blank drugs -> FALSE. Per user adjustment it stays `abvd_episode` TRUE as fallback when no drug or J-code evidence is reachable. The old-rule comparison counts remain.

## Task 0 / probe
- `.planning/schemas/203_schema_inputs_20261114.md` section 2 and `EPISODES_SCHEMA`. Names: `patient_id`, `treatment_type`, `drug_names`, `triggering_codes`, `abvd_class`, `abvd_episode`, `ever_abvd`, `ever_abvd_plus`; label "Chemotherapy".

## Consumer grep results (no edits)
- `grep -ln` for `abvd_episode|ever_abvd|avd_episode` in `R/28_*`, `R/29_*`, `R/52_*`: no matches (A4 holds).
- R/204 L29 `FLAG_COLS <- c("ever_abvd", "immune_flag", "ever_brentuximab")`: reads by name, works on 34 columns. Not edited (adding `ever_avd` would break its read on 32-col pre files). Its flag-delta check will show an `ever_abvd` change across the Phase 210 boundary (definition changed; expected).
- R/205 L270, L286-287: reads `abvd_class`, `ever_abvd` by name; works, semantics changed.

## R/88 lines for Phase 213 (CHAIN-02; not edited)
- L7528-7529: `AUTOIMMUNE-FLAG-192.2 [c2] gantt_episodes_180.csv has 32 columns` (`length(gantt_180_hdr_bb) == 32L`).
- L7678-7679: `IMMUNE-FLAG-199 [c1] ... has 32 columns` (`length(g180_nms) == 32L`).
- L7956: `p201_skip_fn("ABVD-TR-201 [c1] 32 columns (file absent ...)")`; L7987: `ABVD-TR-201 [c1] gantt_episodes_180.csv has 32 columns`.
- L8438: `DECISIONS-206 [b] delivered file has 32 columns` (`ncol(p206_g) == 32L`).
- New checks needed: `avd_episode` at col 33, `ever_avd` at col 34, mutual exclusion, `ever_avd` iff any `avd_episode`. [d5]/[d6] (BV+AVD / Nivo+AVD rows `abvd_episode` FALSE) and [e2] remain valid.

## Verification
- `tools/rcheck.sh parse R/142_gantt_180_export.R`: 0 failed.
- `tools/rcheck.sh test 210`: 0 failures, 0 errors (only warning: reference Excel absent locally, unrelated).
- Real run: PENDING HIPERGATOR (plan 04).

## Assumptions
- Dictionary CSV directory taken from `dirname(OUTPUT_EPISODES)` (= `CONFIG$output_dir`).
- QC fallback count is computed over all episodes (flag is Chemotherapy-only by helper design).
- Whether `triggering_codes` holds J-codes for chemo rows is unverified (see 210-01); fallback count on HiPerGator will show reach.
- Commit message wording not blocked by the concurrent plan 03 edits to R/206 (not touched).

## Deviations from Plan
- User adjustment (J-code evidence, fallback, QC count and dictionary QC row) as described above.

## Self-Check: PASSED
