# Quick 261114-sir: Phase 205 revision (label mapping, dictionary, LOT, first-line)

Task 0: schema probe not applicable. No new pipeline input names; R/205 reads columns already used by R/142 (`abvd_class`, `ever_abvd`, keys) and stage2 (`drug_names`, `treatment_type`).

- A. `assign_regimen()` episode-level fallback, never-NA, `regimen_basis`, both separators (R/utils/utils_regimen.R, R/28).
- B. REGIMEN_DICT additions (R/00_config.R).
- C. ABVD_PLUS kept as loose class.
- D. `assign_lot()` recognized-only, family rules.
- E. R/29 first-line via `first_line_eligible()`.
- F. R/205: path fix, baseline reconciliation.
- G. Tests: tests/testthat/test-205-regimen-revision.R, edits to 205 dict/lot tests.
- H. REGL-06-decisions.md.
- Verify: `tools/rcheck.sh parse <files>`; `tools/rcheck.sh test 205`.
