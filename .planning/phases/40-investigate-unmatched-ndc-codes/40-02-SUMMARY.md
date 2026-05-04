---
phase: 40-investigate-unmatched-ndc-codes
plan: 02
subsystem: data-investigation
tags: [R, config-update, NDC, RXNORM, programmatic-modification]

# Dependency graph
requires:
  - phase: 40-01
    provides: unmatched_ndc_classified.rds artifact with NDC/RXNORM classification
  - phase: 39-investigate-unmatched-codes
    provides: Config update function template (update_config_treatment_codes pattern)
provides:
  - update_config_ndc_codes() function in R/40_investigate_unmatched_ndc.R
  - Pattern for programmatic R config modification with NDC and RXNORM vector creation
affects: [R/00_config.R, drug-detection, TREATMENT_CODES-expansion]

# Tech tracking
tech-stack:
  added: []
  patterns: [Dual code-type vector mapping (NDC + RXNORM), Category-specific vector routing]

key-files:
  created: []
  modified:
    - R/40_investigate_unmatched_ndc.R

key-decisions:
  - "Separate NDC and RXNORM category maps enable code_type-specific vector routing"
  - "New NDC vectors created before existing supportive_care_hcpcs anchor"
  - "Existing chemo_rxnorm expanded; new RXNORM vectors created for other categories"
  - "Drug name truncated to 40 chars in inline comments (Phase 40 attribution)"

patterns-established:
  - "Dual code-type processing loop (NDC then RXNORM) with category-specific vector maps"
  - "Vector existence detection via grep with per-category creation vs expansion logic"

requirements-completed: [D-10, D-11]

# Metrics
duration: 2min
completed: 2026-05-04
---

# Phase 40 Plan 02: NDC/RXNORM Config Update Function Summary

**Config update function with NDC vector creation, RXNORM expansion, and dual code-type routing following Phase 39 template**

## Performance

- **Duration:** 2 min
- **Started:** 2026-05-04T16:41:32Z
- **Completed:** 2026-05-04T16:43:58Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Added SECTION 8 (280 lines) with update_config_ndc_codes() function to R/40_investigate_unmatched_ndc.R
- Dual code-type category maps route NDC to new vectors (chemo_ndc, supportive_care_ndc, immunotherapy_ndc, sct_ndc)
- RXNORM routing expands existing chemo_rxnorm (4 CUIs) or creates new vectors (supportive_care_rxnorm, immunotherapy_rxnorm, sct_rxnorm)
- Parse/source validation with backup-rollback on failure (Phase 39 proven pattern)
- Step 6 added to main execution calling update_config_ndc_codes(RDS_PATH)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add config update function and wire into main execution** - `5c4c425` (feat)

**Plan metadata:** (next commit)

## Files Created/Modified
- `R/40_investigate_unmatched_ndc.R` - Added SECTION 8 (update_config_ndc_codes function, 280 lines) and Step 6 in main execution

## Decisions Made

1. **Dual code-type mapping:** Separate ndc_category_map and rxnorm_category_map enable routing same classification to different vector names based on code_type (NDC vs RXNORM). Avoids single-map ambiguity.

2. **NDC vectors inserted before supportive_care_hcpcs:** Anchor detection pattern searches for supportive_care_hcpcs first (Phase 39 addition), falls back to chemo_revenue if not found. Keeps new NDC vectors grouped with treatment detection codes.

3. **RXNORM expansion vs creation:** Existing chemo_rxnorm vector (4 CUIs from ABVD regimen) is expanded. New RXNORM vectors (supportive_care_rxnorm, immunotherapy_rxnorm, sct_rxnorm) are created as needed.

4. **Drug name truncation:** Inline comments truncate drug_name to 40 chars (Phase 40 attribution) matching Phase 39 description truncation pattern for readability.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - function execution deferred until HiPerGator run with RDS artifact present.

## Next Phase Readiness

- R/40_investigate_unmatched_ndc.R ready for execution on HiPerGator
- First run will load unmatched_ndc_classified.rds from Plan 01, programmatically update R/00_config.R
- TREATMENT_CODES will gain new NDC vectors and expanded/new RXNORM vectors
- Future treatment detection scripts can match on both NDC and RXNORM codes

## Known Stubs

None.

## Self-Check: PASSED

**Modified files:**
- FOUND: R/40_investigate_unmatched_ndc.R (1084 lines, +280 from Plan 01)

**Function signature:**
- FOUND: `update_config_ndc_codes <- function(classified_codes_path)` at line 750

**Required elements:**
- FOUND: SECTION 8 header comment
- FOUND: readRDS(classified_codes_path) to load Plan 01 output
- FOUND: chemo_ndc in ndc_category_map
- FOUND: supportive_care_ndc in ndc_category_map
- FOUND: chemo_rxnorm in rxnorm_category_map
- FOUND: supportive_care_rxnorm in rxnorm_category_map
- FOUND: file.copy(config_path, backup_path) backup creation
- FOUND: parse(config_path) validation
- FOUND: source(config_path, local = env) validation
- FOUND: file.copy(backup_path, config_path) rollback on error
- FOUND: file.remove(backup_path) on success
- FOUND: Step 6 in SECTION 7 main execution
- FOUND: update_config_ndc_codes(RDS_PATH) function call

**Commits:**
- FOUND: 5c4c425 (feat(40-02): add config update function for NDC/RXNORM codes)

---
*Phase: 40-investigate-unmatched-ndc-codes*
*Completed: 2026-05-04*
