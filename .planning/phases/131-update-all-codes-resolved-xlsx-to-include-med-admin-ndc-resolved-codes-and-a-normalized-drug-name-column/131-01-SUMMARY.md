---
phase: 131-update-all-codes-resolved-xlsx-to-include-med-admin-ndc-resolved-codes-and-a-normalized-drug-name-column
plan: 01
subsystem: config
tags: [r, openxlsx2, stringr, drug-name-normalization, rxnorm, hcpcs, medication-lookup]

# Dependency graph
requires:
  - phase: 120-supportive-care-rxnorm-normalization
    provides: "R/105_normalize_supportive_care_meaning.R writes a 'Normalized Meaning' column (col G) to the Supportive Care sheet, plus the rule_based_ingredient() strip logic this plan adapts"
provides:
  - "MEDICATION_LOOKUP consults Supportive Care col G (Phase 120 R/105 output) instead of the wrong column-3 code-type label, with graceful column-3 fallback when col G is absent"
  - "fallback_normalize_medication(description, code_type) — vectorized 3-tier heuristic normalizer (multi-ingredient passthrough / HCPCS J-code strip / RxNorm-STR strip) with a never-blank guarantee"
affects: [131-02, 131-03, 131-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-sheet column selector (med_col) instead of a single hardcoded column index, so MEDICATION_LOOKUP can consume enrichment columns added by later phases without breaking other sheets"
    - "Vectorized heuristic string-stripping fallback (adapted from a one-time reference-Excel enrichment script) kept as a standalone R/00_config.R function rather than importing the source script, since that script is not a shared utility module"

key-files:
  created: []
  modified:
    - R/00_config.R

key-decisions:
  - "Reuse Phase 120's R/105 col G output for Supportive Care names instead of re-deriving them via the new Phase 131 fallback normalizer (per 131-CONTEXT.md's post-research decision)"
  - "fallback_normalize_medication() copies R/105's formulation/salt word lists and strip sequence rather than importing R/105, since R/105 is a one-time reference-Excel enrichment script, not a shared utils file"
  - "HCPCS J-code branch and RxNorm-STR branch both route through canonicalize_drug_name() so fallback output stays consistent with MEDICATION_LOOKUP's brand->generic collapsing"

patterns-established:
  - "Fallback normalizers for reference-data gaps should never return blank for non-blank input — mirrored R/105's never-blank contract exactly (falls back to lowercased first word of input)"

requirements-completed: [MEDXLSX-01, MEDXLSX-02]

# Metrics
duration: 15min
completed: 2026-07-22
---

# Phase 131 Plan 01: Medication-Naming Infrastructure Summary

**MEDICATION_LOOKUP now reads Supportive Care's Phase-120 "Normalized Meaning" column (col G) instead of its wrong column-3 code-type label, and a new vectorized `fallback_normalize_medication()` heuristic covers everything MEDICATION_LOOKUP doesn't (multi-ingredient compounds, HCPCS J-codes, RxNorm-STR strings).**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-07-22
- **Tasks:** 2 completed
- **Files modified:** 1 (R/00_config.R)

## Accomplishments
- MEDICATION_LOOKUP's builder loop now selects column 7 for the Supportive Care sheet when it has >= 7 columns (col G, "Normalized Meaning" written by R/105), falling back to column 3 for that sheet and unconditionally for all other sheets — degrades gracefully today since this repo's copy of the reference Excel has not yet had R/105 materialize col G (confirmed dims A1:F173).
- Added `fallback_normalize_medication(description, code_type)`, a fully vectorized 3-tier heuristic normalizer: (1) multi-ingredient `" / "`-delimited compound passthrough, (2) HCPCS `"Injection, X, dose"` extraction, (3) RxNorm-STR-style strip (pack wrappers, quantity prefixes, brand brackets, dose/unit/percent tokens, formulation words, salt words) adapted from R/105's `rule_based_ingredient()`. Never returns blank for non-blank input; returns `NA_character_` only for NA/blank input.

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire Supportive Care col G into MEDICATION_LOOKUP** - `6a0ab2a` (feat)
2. **Task 2: Add fallback_normalize_medication() heuristic normalizer** - `faa5206` (feat)

_Note: no TDD tasks in this plan (both `tdd="false"`); verification was grep-based per the plan's stated dual-environment convention (openxlsx2/duckdb/here not installed in this dev sandbox)._

## Files Created/Modified
- `R/00_config.R` - MEDICATION_LOOKUP builder loop now uses a per-sheet `med_col` selector (col 7 for Supportive Care when present, col 3 otherwise); added `fallback_normalize_medication()` function (~113 lines) after the `DRUG_NAME_ALIASES`/`canonicalize_drug_name()` block, before "SECTION 6: ANALYSIS PARAMETERS"

## Decisions Made
- Reused Phase 120's R/105 col-G output for Supportive Care rather than having the new fallback normalizer re-derive those names, per 131-CONTEXT.md's post-research decision — avoids duplicating RxNav-informed normalization logic that R/105 already performs with cache-backed accuracy.
- Copied (rather than sourced/imported) R/105's `rule_based_ingredient()` strip sequence and word lists into the new function, since R/105 is a one-time reference-Excel enrichment script executed on HiPerGator, not a reusable utility module.

## Deviations from Plan

None - plan executed exactly as written. Both tasks matched the plan's exact code blocks (the `med_col` conditional and the `fallback_normalize_medication()` three-branch structure), and all specified grep verifications passed on the first attempt.

## Issues Encountered

None. As anticipated by the plan, `Rscript` is not available in this dev environment (confirmed: `Rscript --version` → command not found), so runtime execution/sourcing of `R/00_config.R` could not be performed here. Verification was structural: all four grep checks from the plan passed (`med_col <- if (sheet_name == "Supportive Care"...` count 1, `sheet_df[[med_col]]` count 1, `sheet_df[[3]]` count 0 in the loop, `fallback_normalize_medication <- function` count 1, plus confirmation of the `" / "` detection, `"^Injection,"` regex, and `canonicalize_drug_name(` calls inside the new function). Additionally performed a manual brace-balance check isolating just the new function's start/end lines (2659-2745), confirming it opens and closes cleanly. Full syntax parsing (`Rscript -e "parse('R/00_config.R')"`) is deferred to HiPerGator per the plan's stated verification approach.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `MEDICATION_LOOKUP` and `fallback_normalize_medication()` are both ready for Plan 131-03 (R/50 column-population wiring) to consume, once Plan 131-02's MED_ADMIN/DISPENSING detection rework lands first.
- No blockers identified. Runtime confirmation of both pieces (MEDICATION_LOOKUP correctly picking up col G once R/105 materializes it, and fallback_normalize_medication() producing sane output against real NDC-resolved descriptions) is deferred to HiPerGator, consistent with this project's established dual-environment convention.

---
*Phase: 131-update-all-codes-resolved-xlsx-to-include-med-admin-ndc-resolved-codes-and-a-normalized-drug-name-column*
*Completed: 2026-07-22*

## Self-Check: PASSED

- FOUND: R/00_config.R
- FOUND: .planning/phases/131-.../131-01-SUMMARY.md
- FOUND commit: 6a0ab2a
- FOUND commit: faa5206
