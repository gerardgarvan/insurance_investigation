---
phase: 201-abvd-and-tumor-registry-lymphoma-flags-in-gantt-180
plan: 01
status: partial — awaiting Task 3 (HiPerGator run)
completed_tasks: 2 of 3
subsystem: gantt-export
tags: [abvd, tumor-registry, gantt, episode-flags]
dependency_graph:
  requires: [Phase 199 gantt_episodes_180.csv at 26 columns, Phase 200 D-200-01]
  provides: [gantt_episodes_180.csv at 30 columns, classify_abvd_episode(), build_tr_lymphoma_flags()]
  affects: [R/88 smoke test, AC handoff]
tech_stack:
  added: []
  patterns: [prefix-family matching for drug name variants, three-state logical flags]
key_files:
  created:
    - tests/testthat/test-201-abvd-tr-flags.R
  modified:
    - R/00_config.R
    - R/utils/utils_cancer.R
    - R/142_gantt_180_export.R
decisions:
  - "D-01: ABVD recomputed post-4D canonicalization to avoid salt-variant over-counting (R/28 B-01 backlog)"
  - "D-04: Three-state TR flags (TRUE/FALSE/NA) using HISTOLOGICAL_TYPE and MORPH columns"
  - "D-05: nhl_histology ships with UNVERIFIED caveat; unlisted 9590-9999 codes printed in QC"
metrics:
  duration: ~35 min (Tasks 1-2)
  completed_date: 2026-11-14
  tasks: 2
  files: 4
---

# Phase 201 Plan 01: ABVD and TR Flags — Partial Summary (Tasks 1–2 Complete)

Tasks 1 and 2 complete; Task 3 (HiPerGator run) is the checkpoint.

## What was built

### Task 1 — Config constants and helpers

**R/00_config.R** (after `BRENTUXIMAB_DRUG`, before `AUTOIMMUNE_DX_TYPE_ACCEPT`):

```r
ABVD_COMPONENTS      <- c("Doxorubicin", "Bleomycin", "Vinblastine", "Dacarbazine")
AVD_COMPONENTS       <- c("Doxorubicin", "Vinblastine", "Dacarbazine")
ABVD_EXCLUDING_DRUGS <- c(BRENTUXIMAB_DRUG, "Nivolumab")
```

Canonical token rationale (from DRUG_NAME_ALIASES inspection):
- `"Doxorubicin"` — `doxorubicin hydrochloride` alias present; bare form is canonical.
- `"Bleomycin"` — no alias in DRUG_NAME_ALIASES; only bare generic reaches drug_names.
- `"Vinblastine"` — `vinblastine sulfate` alias present; collapses to bare form.
- `"Dacarbazine"` — no alias; bare generic only.
- `"Nivolumab"` — alias present (opdivo -> Nivolumab).
- `"Brentuximab Vedotin"` — alias present (adcetris, brentuximab -> Brentuximab Vedotin).

Note: HiPerGator token printout (Task 3) will confirm any unexpected variants in the live extract.

**R/utils/utils_cancer.R** — two functions added at end of file:

`classify_abvd_episode(drug_names, regimen_label_r28)`:
- Splits semicolons, maps tokens to families via case-insensitive prefix regex.
- Returns `"ABVD"` / `"AVD"` / `"JCODE_ABVD"` / `"ABVD_PLUS"` / `NA`.
- `abvd_episode` uses `result %in% c("ABVD","AVD","JCODE_ABVD")`.

`build_tr_lymphoma_flags(patient_ids)`:
- Queries `TUMOR_REGISTRY_ALL`, detects `HISTOLOGICAL_TYPE` / `MORPH` columns dynamically.
- Three-state logic: `NA` = not in TR; `TRUE` = HL/NHL code found; `FALSE` = in TR, no match.
- Attributes: `tr_hl_ids_all` (all TR-HL IDs for D-06), `unlisted_lymphoid` (D-05 codes).
- `stop()` if TUMOR_REGISTRY_ALL unavailable (all-NA silent return forbidden, D-04).

**tests/testthat/test-201-abvd-tr-flags.R** — 9 unit tests:

| Input | r28 | Expected |
|-------|-----|----------|
| `"Bleomycin;Dacarbazine;Doxorubicin;Vinblastine"` | NA | ABVD |
| `"Dacarbazine;Doxorubicin;Vinblastine"` | NA | AVD |
| `"Brentuximab Vedotin;Dacarbazine;Doxorubicin;Vinblastine"` | NA | NA |
| `"Bleomycin;Dacarbazine;Doxorubicin;Rituximab;Vinblastine"` | NA | ABVD_PLUS |
| `"Bleomycin;Dacarbazine;Doxorubicin Hydrochloride;Vinblastine;Vinblastine Sulfate"` | NA | ABVD (5 tokens → 4 families) |
| `""` | `"ABVD"` | JCODE_ABVD |
| `""` | NA | NA |
| `"Cyclophosphamide;Doxorubicin;Vincristine"` | NA | NA |
| vectorized 4-row | mixed | ABVD/AVD/JCODE_ABVD/NA |

All 9 pass locally (one expected warning: MEDICATION_LOOKUP empty without data reference Excel).

### Task 2 — R/142 Sections 4C4 / 4C5, schema, regression

Changes to `R/142_gantt_180_export.R`:

- **Header**: Outputs line updated to "30 columns".
- **EPISODES_SCHEMA**: 4 columns appended with `# Phase 201` comment.
- **Section 2**: `stopifnot("regimen_label missing …")` after `assert_df_valid`.
- **Section 4 joins**: `regimen_label` added to `left_join` select and downstream `select`; `NA_character_` assigned on Death and HL Diagnosis pseudo-rows.
- **Section 4C4** (new, after Section 4C3 / immune-flag QC, before column trim): calls `classify_abvd_episode()`, sets `abvd_episode` and `ever_abvd`, `stopifnot` guards, D-08 QC block (counts, cross-tab, top disagreement rows).
- **Section 4C5** (new, after Section 4D): calls `build_tr_lymphoma_flags()`, left-joins, `stopifnot` guards, D-08 TR QC block (counts, cross-tab, unlisted codes), D-06 absent-patient CSV write to `output/internal/tr_hl_not_in_gantt_180.csv`.
- **Column trim**: updated to 30 columns; drops `regimen_label`, `abvd_class`, `tr_present`.
- **PRE201 regression**: saves `gantt_episodes_180_PRE201.csv` (26-col guard) before write; post-write check on row count, names[1:26], multiset comparison. Prints `"Phase 201 regression: PASS (26 original columns unchanged)"`.
- **Section 6**: added `message(glue("  Phase 201 columns 27-30: {paste(EPISODES_SCHEMA[27:30], collapse = ', ')}"))`.
- Parse: `tools/rcheck.sh parse R/142_gantt_180_export.R` exits 0.

## Awaiting Task 3 (HiPerGator)

Paste back after running with `Sys.setenv(RUN_PRE201_REGRESSION = "TRUE")`:
1. Section 4C4 ABVD QC block output (counts; cross-tab abvd_episode × regimen_label; top disagreements)
2. Section 4C5 TR QC block output (tr_present; tr_hl_dx/tr_nhl_dx TRUE/FALSE/NA; both-TRUE; unlisted codes)
3. D-06 absent-from-Gantt counts (n_r1, n_r2, n_r3)
4. `"Phase 201 regression: PASS"`

Summary will be completed with the QC numbers once the HiPerGator run is pasted back.

## Commits

- `feafa44` — feat(201-01): add ABVD constants, classify_abvd_episode(), build_tr_lymphoma_flags(), unit tests
- `652916f` — feat(201-01): update R/142 with Sections 4C4/4C5, 30-column schema, PRE201 regression

## Self-Check: PARTIAL

Tasks 1–2 artifacts verified:
- `R/00_config.R`: ABVD_COMPONENTS, AVD_COMPONENTS, ABVD_EXCLUDING_DRUGS present (grep confirmed)
- `R/utils/utils_cancer.R`: classify_abvd_episode(), build_tr_lymphoma_flags() present (parse OK)
- `tests/testthat/test-201-abvd-tr-flags.R`: 9 tests pass locally
- `R/142_gantt_180_export.R`: parses cleanly; 11 "Phase 201" references; 37 column-name references

Task 3 (HiPerGator): pending.
