---
phase: 200
plan: "01"
subsystem: treatment-episodes
tags: [immunotherapy, med-admin, dispensing, rxnorm, hcpcs, smoke-test]
key-files:
  created:
    - R/tools/check_immuno_fix_preview.R
  modified:
    - R/26_treatment_episodes.R
    - R/00_config.R
    - R/88_smoke_test_comprehensive.R
    - R/142_gantt_180_export.R
    - R/52_gantt_v2_export.R
    - R/170_nhl_gantt_subsets.R
decisions:
  - "D-200-R1: Rituximab biosimilar Q-codes and RxNorm CUIs moved to chemo, not immunotherapy"
  - "D-200-R2: Vitamin RxNorm CUIs excluded from MED_ADMIN/DISPENSING branches via immuno_ma_codes"
  - "D-200-R3: PRE199/PRE1922 regression comparisons gated behind env vars — baselines pre-date Phase 200 outputs"
metrics:
  completed: "2026-11-12"
---

# Phase 200 Plan 01: Immunotherapy MED_ADMIN/DISPENSING Capture Fix — Summary

**One-liner:** Vitamin-excluded immuno_ma_codes + rituximab reclassified to chemo + env-var-gated regression baselines + R/88 15bc Phase 200 structural checks.

## Tasks Completed

- **Task 0:** Created `R/tools/check_immuno_fix_preview.R` — preflight tool that calls `get_chemo_hits()` for DISPENSING and MED_ADMIN, prints patient/date counts by drug, runs brentuximab gate check (expected ~184; warns if < 150), and separately reports vitamin CUI contribution excluded by D-200-R2.

- **Task 1:** Edited `R/26_treatment_episodes.R` — added `immuno_ma_codes` block (setdiff of `immunotherapy_rxnorm` minus vitamin CUIs); updated DISPENSING and MED_ADMIN `get_chemo_hits()` calls to use `immuno_ma_codes`; updated phase-label comments to Phase 200.

- **Task 2:** Edited `R/00_config.R`:
  - J8610 added to `MTX_CODES$hcpcs` (source of truth); removed duplicate literal from `IMMUNE_DRUG_DEFS$Methotrexate`; added J8610 to `chemo_hcpcs`.
  - Q5115/Q5119/Q5123 removed from `immunotherapy_hcpcs`; added to `chemo_hcpcs`, `DRUG_GROUPINGS`, and `MEDICATION_LOOKUP_JCODE_SUPPLEMENT`.
  - Rituximab CUIs (121191, 1719312, 2049106) removed from `immunotherapy_rxnorm`; appended to `chemo_rxnorm`.
  - `MEDICATION_LOOKUP_JCODE_SUPPLEMENT` extended with names for Q5115/Q5119/Q5123, J8610, and the three rituximab CUIs.

- **Task 3:** Gated regression baseline blocks behind env vars:
  - `R/142_gantt_180_export.R`: PRE199 save block and comparison block wrapped in `if (Sys.getenv("RUN_PRE199_REGRESSION") == "TRUE")`.
  - `R/52_gantt_v2_export.R`: PRE1922 `save_pre1922()` calls wrapped in the same pattern for `RUN_PRE1922_REGRESSION`.
  - `R/170_nhl_gantt_subsets.R`: Section 4.5 entire block wrapped in `if (Sys.getenv("RUN_PRE1922_REGRESSION") == "TRUE")`.

- **Task 4:** Edited `R/88_smoke_test_comprehensive.R` section 15bc:
  - [g] check changed from bidirectional (`==`) to one-directional (`!has_bren | bren_flag`).
  - New [f-autoimmune] local() block: `immune_flag TRUE implies has_autoimmune_dx TRUE`.
  - New Phase 200 local() block with checks [5a] no RXNORM_CUI guard / get_chemo_hits present, [5b] immuno_ma_codes used (not raw immunotherapy_rxnorm), [5c] J8610 and Q5 codes in chemo_hcpcs with MEDICATION_LOOKUP names.
  - Summary message updated with IMMUNE-FLAG-200 line.

- **Task 5:** Brace-balance confirmed — diffs in R/00_config.R and R/88 are pre-existing (string literals in glue/regex). Committed: `59d8671`.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All new code paths are either live logic or gate checks. The preflight tool is read-only by design.

## Next Steps (Plan 200-02)

Run `R/tools/check_immuno_fix_preview.R` on HiPerGator before the main chain. Gate: brentuximab patients >= 150. Then run the main pipeline chain.
