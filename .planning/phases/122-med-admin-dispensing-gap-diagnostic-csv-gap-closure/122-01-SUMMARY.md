---
phase: 122-med-admin-dispensing-gap-diagnostic-csv-gap-closure
plan: "01"
subsystem: treatment-detection
tags: [fix, helpers, fixtures, col-spec, ndc-crosswalk]
dependency_graph:
  requires: []
  provides:
    - normalize_ndc() in utils_treatment.R
    - load_ndc_crosswalk() in utils_treatment.R
    - get_chemo_hits() in utils_treatment.R
    - corrected DISPENSING_SPEC (no phantom RXNORM_CUI)
    - corrected MED_ADMIN_SPEC (no phantom RXNORM_CUI)
    - corrected MED_ADMIN + DISPENSING fixtures (real column layout)
  affects:
    - R/10_cohort_predicates.R (Plan 02 consumer)
    - R/25_treatment_durations.R (Plan 02 consumer)
    - R/26_treatment_episodes.R (Plan 02 consumer)
    - R/11_treatment_payer.R (Plan 02 consumer)
    - R/27_drug_name_resolution.R (Plan 02 consumer)
    - R/20_treatment_inventory.R (Plan 02 consumer)
    - R/76_treatment_source_coverage.R (Plan 02 consumer)
tech_stack:
  added: []
  patterns:
    - named-vector O(1) NDC->RxCUI crosswalk lookup
    - graceful-degrade helper (message + NULL/character(0), never crash)
    - safe_table() wrapping for all PCORnet table access
    - RX/ND branch separation in get_chemo_hits MED_ADMIN block
key_files:
  created:
    - R/utils/utils_treatment.R (appended: normalize_ndc, load_ndc_crosswalk, get_chemo_hits)
  modified:
    - R/01_load_pcornet.R
    - tests/fixtures/MED_ADMIN_Mailhot_V1.csv
    - tests/fixtures/DISPENSING_Mailhot_V1.csv
decisions:
  - "get_chemo_hits uses safe_table() (already in utils_treatment.R) rather than inline tryCatch as specified in plan action"
  - "ENCOUNTERID omitted from get_chemo_hits return; roxygen note added; callers add it if source has it (Open Question 1)"
  - "DISPENSING fixture NDC hit: 00069306030 (11-digit no-hyphen); synthetic CUI 3639 (Doxorubicin); RDS deferred to HiPerGator (no R binary on Windows executor)"
  - "ndc_rxnorm_crosswalk.rds deferred: create on HiPerGator with saveRDS(setNames('3639','00069306030'), here::here('data','reference','ndc_rxnorm_crosswalk.rds')) before Plan 03 smoke test"
  - "normalize_ndc uses native pipe (|>) matching RESEARCH.md snippet; dplyr uses explicit dplyr:: namespace to avoid any load-order ambiguity"
metrics:
  duration: "3 minutes"
  completed_date: "2026-07-14"
  tasks_completed: 3
  files_modified: 4
---

# Phase 122 Plan 01: Foundation — Col-Spec Fix + Shared Helpers + Corrected Fixtures Summary

**One-liner:** Root-cause phantom RXNORM_CUI col_spec removed from DISPENSING/MED_ADMIN specs; normalize_ndc + load_ndc_crosswalk + get_chemo_hits helpers added to utils_treatment.R; fixtures corrected to real extract layout exercising RX-direct + NDC-crosswalk + filtered-out branches.

## What Was Built

### Task 1: R/01_load_pcornet.R col_spec fix

The two phantom `RXNORM_CUI = col_character()` declarations removed:

- **DISPENSING_SPEC** (was line 322): `RXNORM_CUI = col_character(), # KEY: chemo matching per D-12` deleted. Block comment updated to: `# NDC is the key column in this extract; RXNORM_CUI absent (D-12 revised Phase 122: NDC->RxNorm crosswalk used for chemo matching)`.
- **MED_ADMIN_SPEC** (was line 345): same deletion. Block comment updated to: `# MEDADMIN_CODE + MEDADMIN_TYPE encode the drug code; RXNORM_CUI absent (D-12 revised Phase 122: RX-typed=RxNorm CUI, ND-typed=NDC via crosswalk)`.
- **PRESCRIBING_SPEC** (line 153): untouched — PRESCRIBING genuinely has RXNORM_CUI.

Root-cause mechanism closed: vroom can no longer inject an all-NA RXNORM_CUI column into DISPENSING or MED_ADMIN loads.

### Task 2: utils_treatment.R — three new helpers

**normalize_ndc(ndc):** Strips hyphens, left-pads to 11 digits using stringr. Vectorized.

**load_ndc_crosswalk():** Reads `here::here("data","reference","ndc_rxnorm_crosswalk.rds")`. Returns named character vector (NDC -> RxCUI) or `character(0)` with two-line message when absent. Never calls `stop()`.

**get_chemo_hits(table_name, chemo_rxnorm, ndc_crosswalk=NULL):** Single shared entry point for all three PCORnet med tables:
- PRESCRIBING: filters RXNORM_CUI %in% chemo_rxnorm; coalesces RX_ORDER_DATE/RX_START_DATE
- DISPENSING: NDC crosswalk path; guards on NDC column presence AND non-empty crosswalk
- MED_ADMIN: RX-typed branch (MEDADMIN_CODE direct CUI match) + ND-typed branch (MEDADMIN_CODE as NDC via crosswalk); requires all 3 columns present
- All branches: `dplyr::distinct(ID, treatment_date, triggering_code)` pre-dedup (Pitfall 4)
- ENCOUNTERID omitted from return; callers add it if source has it

### Task 3: Fixture corrections + crosswalk RDS

**MED_ADMIN_Mailhot_V1.csv** (11 columns, was 12):
- Dropped: RXNORM_CUI
- 4 data rows: RX hit (3639 Doxorubicin CUI), ND hit (NDC 00069306030), NI filtered row, RX non-chemo row

**DISPENSING_Mailhot_V1.csv** (13 columns, was 15):
- Dropped: RXNORM_CUI, RAW_DISPENSE_MED_NAME
- 2 data rows: NDC crosswalk hit (00069306030), NDC miss (12345678901)

**ndc_rxnorm_crosswalk.rds:** DEFERRED — no R binary on Windows executor (see Known Stubs section).

## Structural Verification (Windows executor — no Rscript)

| Check | Result |
|-------|--------|
| `grep -c "^  RXNORM_CUI = col_character" R/01_load_pcornet.R` | 1 (PRESCRIBING only) |
| `grep -c "D-12 revised Phase 122" R/01_load_pcornet.R` | 2 (DISPENSING + MED_ADMIN comments) |
| `grep -c "RXNORM_CUI = col_character(), # KEY" R/01_load_pcornet.R` | 0 |
| `grep -c "^get_chemo_hits <- function" utils_treatment.R` | 1 |
| `grep -c "^load_ndc_crosswalk <- function" utils_treatment.R` | 1 |
| `grep -c "^normalize_ndc <- function" utils_treatment.R` | 1 |
| `MEDADMIN_TYPE == "RX"` in utils_treatment.R | present |
| `MEDADMIN_TYPE == "ND"` in utils_treatment.R | present |
| `ndc_crosswalk[normalize_ndc` count in utils_treatment.R | 2 (DISPENSING + MED_ADMIN ND) |
| `return(character(0))` count in utils_treatment.R | 2 (graceful crosswalk-absent) |
| ENCOUNTERID in get_chemo_hits select() | 0 (roxygen note only) |
| Brace balance in 3 new functions | balanced |
| MED_ADMIN fixture has no RXNORM_CUI | confirmed |
| DISPENSING fixture has no RXNORM_CUI, no RAW_DISPENSE_MED_NAME | confirmed |
| MED_ADMIN: >=1 RX, >=1 ND, >=1 NI row | confirmed (2 RX, 1 ND, 1 NI) |
| DISPENSING: hit + miss NDC rows | confirmed |
| Column count MED_ADMIN (11) consistent | confirmed |
| Column count DISPENSING (13) consistent | confirmed |

## Deviations from Plan

None — plan executed exactly as written, with one HiPerGator deferral documented as expected.

## Known Stubs

| Stub | File | Notes |
|------|------|-------|
| `data/reference/ndc_rxnorm_crosswalk.rds` missing | data/reference/ | No R binary on Windows executor. load_ndc_crosswalk() degrades gracefully to character(0) so no crash. **Must create on HiPerGator before Plan 03 smoke test passes for DISPENSING/MED_ADMIN ND paths.** Exact command: `saveRDS(setNames("3639", "00069306030"), here::here("data","reference","ndc_rxnorm_crosswalk.rds"))` — NDC `00069306030` -> CUI `3639` (Doxorubicin). This covers the fixture's NDC hit row and enables both the DISPENSING and MED_ADMIN ND branches to exercise locally against fixtures. |

## Self-Check: PASSED

Files created/modified:
- `R/01_load_pcornet.R` — FOUND
- `R/utils/utils_treatment.R` — FOUND
- `tests/fixtures/MED_ADMIN_Mailhot_V1.csv` — FOUND
- `tests/fixtures/DISPENSING_Mailhot_V1.csv` — FOUND

Commits:
- `d30945d` — FOUND (fix(122-01): remove phantom RXNORM_CUI col_spec)
- `7343c90` — FOUND (feat(122-01): add normalize_ndc + load_ndc_crosswalk + get_chemo_hits)
- `61c8e46` — FOUND (feat(122-01): correct MED_ADMIN + DISPENSING fixtures)
