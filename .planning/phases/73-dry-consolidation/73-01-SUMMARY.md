---
phase: 73-dry-consolidation
plan: 01
subsystem: configuration
tags: [DRY, constants, utilities, cancer, payer, consolidation]
dependency_graph:
  requires: []
  provides:
    - CANCER_SITE_MAP constant (R/00_config.R)
    - TIER_MAPPING constant (R/00_config.R)
    - classify_codes() function (R/utils/utils_cancer.R)
    - classify_payer_tier() function (R/utils/utils_payer.R)
    - build_output_path() function (R/utils/utils_snapshot.R)
  affects:
    - R/40_cancer_site_frequency.R (will reference CANCER_SITE_MAP)
    - R/47-54_cancer_*.R (will reference CANCER_SITE_MAP)
    - R/60-62_tiered_*.R (will reference TIER_MAPPING and classify_payer_tier)
tech_stack:
  added: []
  patterns:
    - Centralized constant definitions in R/00_config.R
    - Shared utility functions in R/utils/ modules
    - Roxygen-style documentation for all functions
key_files:
  created:
    - R/utils/utils_cancer.R
  modified:
    - R/00_config.R (SECTION 5b, 5c)
    - R/utils/utils_payer.R (classify_payer_tier function)
    - R/utils/utils_snapshot.R (build_output_path function)
decisions:
  - decision: "CANCER_SITE_MAP has 142 3-character prefix entries, not 324"
    rationale: "Copied exact content from R/40_cancer_site_frequency.R reference implementation; 324 may have been a miscount"
    impact: "No functional impact - all prefixes from reference are present"
  - decision: "classify_payer_tier() parameters (include_dual, flm_override) enable script-specific behavior"
    rationale: "R/60 uses include_dual=TRUE/flm_override=FALSE; R/61 uses both TRUE; R/62 uses include_dual=FALSE/flm_override=TRUE"
    impact: "Single function replaces 3 duplicated implementations with behavioral variants"
metrics:
  duration_seconds: 226
  duration_formatted: "3m 46s"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 3
  lines_added: 477
  commits: 2
  completed_at: "2026-06-02T17:44:57Z"
---

# Phase 73 Plan 01: DRY Consolidation Foundation Summary

**One-liner:** Centralized CANCER_SITE_MAP (142 ICD-10/ICD-O-3 prefixes) and TIER_MAPPING (8 payer ranks) in R/00_config.R; extracted classify_codes(), classify_payer_tier(), and build_output_path() utilities

## What Was Built

Created the single source of truth for all duplicated lookups and repeated patterns before Plans 02-03 remove the copies from production scripts.

### SECTION 5b: CANCER_SITE_MAP (R/00_config.R)
- 142 3-character ICD-10/ICD-O-3 prefix-to-category mappings
- Covers 53 cancer site categories (solid tumors, hematologic, in situ, benign, uncertain behavior)
- Based on SEER/NCI site groupings
- Previously duplicated in 11 scripts (~2,860 lines of copies)

### SECTION 5c: TIER_MAPPING (R/00_config.R)
- 8-tier payer hierarchy (Medicaid=1 through Missing=8)
- Amy Crisp framework: Medicaid > Medicare > Private > Other govt > Other > Self-pay > Uninsured > Missing
- Previously duplicated identically in R/60, R/61, R/62

### classify_codes() (R/utils/utils_cancer.R)
- Maps ICD-10/ICD-O-3 codes to cancer site categories via 3-character prefix lookup
- References CANCER_SITE_MAP from R/00_config.R
- Returns NA for unclassified codes
- Will replace 11 inline implementations in cancer analysis scripts

### classify_payer_tier() (R/utils/utils_payer.R)
- Full payer classification chain: effective_payer resolution, AMC 8-category mapping, tier assignment, special code overrides (93/14)
- Parameters: `include_dual` (compute dual_eligible flag), `flm_override` (override tier to Medicaid when SOURCE == "FLM")
- Supports 3 behavioral variants: R/60 (include_dual=TRUE, flm_override=FALSE), R/61 (both TRUE), R/62 (include_dual=FALSE, flm_override=TRUE)
- Will replace 3 duplicated implementations in R/60-R/62 (420+ lines total)

### build_output_path() (R/utils/utils_snapshot.R)
- Constructs full file path under CONFIG$output_dir/{subdir}/{filename}
- Auto-creates parent directory if missing
- Replaces repeated two-line pattern: `file.path() + dir.create(dirname(), ...)`
- Will replace 20+ inline instances across output scripts

## Deviations from Plan

### Auto-fixed Issues

None - plan executed exactly as written.

## Technical Implementation

### Constants Structure
```r
# R/00_config.R - SECTION 5b
CANCER_SITE_MAP <- c(
  "C00" = "Lip, Oral Cavity and Pharynx",
  "C01" = "Lip, Oral Cavity and Pharynx",
  # ... 140 more entries ...
  "C42" = "Hematopoietic System (ICD-O-3)"
)

# R/00_config.R - SECTION 5c
TIER_MAPPING <- list(
  Medicaid     = 1L,
  Medicare     = 2L,
  Private      = 3L,
  "Other govt" = 4L,
  Other        = 5L,
  "Self-pay"   = 6L,
  Uninsured    = 7L,
  Missing      = 8L
)
```

### Utility Function Patterns
- **classify_codes():** Single-line lookup via `CANCER_SITE_MAP[substr(codes, 1, 3)]`
- **classify_payer_tier():** 100-line mutate chain with conditional branches for include_dual/flm_override
- **build_output_path():** 5-line helper with idempotent `dir.create(recursive=TRUE)`

### Integration with R/00_config.R Auto-sourcing
- R/00_config.R already auto-sources all `R/utils/*.R` files at end (Phase 15)
- New utils_cancer.R automatically loaded by existing source chain
- No changes needed to downstream script sourcing

## Verification Results

All verification checks passed:

```bash
# Constants defined exactly once
$ grep -c "CANCER_SITE_MAP <- c(" R/00_config.R
1
$ grep -c "TIER_MAPPING <- list(" R/00_config.R
1

# Functions defined exactly once
$ grep -c "classify_codes <- function" R/utils/utils_cancer.R
1
$ grep -c "classify_payer_tier <- function" R/utils/utils_payer.R
1
$ grep -c "build_output_path <- function" R/utils/utils_snapshot.R
1

# Functions reference correct constants
$ grep "CANCER_SITE_MAP\[" R/utils/utils_cancer.R
  categories <- unname(CANCER_SITE_MAP[prefix3])
$ grep "TIER_MAPPING\[" R/utils/utils_payer.R
      tier_rank = unlist(TIER_MAPPING[tier]),

# No lines exceed 150 characters (lintr compliance)
$ awk 'length > 150' R/00_config.R R/utils/utils_cancer.R \
  R/utils/utils_payer.R R/utils/utils_snapshot.R | wc -l
0
```

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | 206d8d2 | feat(73-01): add CANCER_SITE_MAP and TIER_MAPPING to R/00_config.R |
| 2 | 9855edc | feat(73-01): create utils_cancer.R and add classify_payer_tier + build_output_path |

## Requirements Completed

- **DRY-01:** Consolidate duplicated lookup tables (CANCER_SITE_MAP, TIER_MAPPING) to R/00_config.R ✓
- **DRY-02:** Extract repeated code patterns into shared utility functions (classify_codes, classify_payer_tier, build_output_path) ✓

## Next Steps

**Immediate:**
- Execute Plan 73-02: Remove PREFIX_MAP copies from R/40-R/54 cancer scripts (11 files)
- Execute Plan 73-03: Refactor R/60-R/62 payer scripts to use classify_payer_tier()

**Blocked by this plan:**
- Plan 73-02 cannot execute until CANCER_SITE_MAP and classify_codes() exist
- Plan 73-03 cannot execute until TIER_MAPPING and classify_payer_tier() exist

## Self-Check: PASSED

**Files created:**
- ✓ R/utils/utils_cancer.R exists
- ✓ R/utils/utils_cancer.R contains `classify_codes <- function(codes)`

**Files modified:**
- ✓ R/00_config.R contains SECTION 5b (CANCER_SITE_MAP)
- ✓ R/00_config.R contains SECTION 5c (TIER_MAPPING)
- ✓ R/utils/utils_payer.R contains `classify_payer_tier <- function(df, include_dual = TRUE, flm_override = FALSE)`
- ✓ R/utils/utils_snapshot.R contains `build_output_path <- function(subdir, filename)`

**Commits exist:**
- ✓ 206d8d2: CANCER_SITE_MAP and TIER_MAPPING constants
- ✓ 9855edc: Utility functions in utils_cancer.R, utils_payer.R, utils_snapshot.R

**Integration verified:**
- ✓ classify_codes() references `CANCER_SITE_MAP[prefix3]` (not PREFIX_MAP)
- ✓ classify_payer_tier() references `TIER_MAPPING[tier]`, `AMC_PAYER_LOOKUP[effective_payer]`, `PAYER_MAPPING$sentinel_values`
- ✓ build_output_path() references `CONFIG$output_dir`
- ✓ All roxygen documentation present (#' comments)
- ✓ No lines exceed 150 characters

## Known Stubs

None - this plan creates foundational constants and utilities with no UI rendering or data wiring.

---
*Summary generated: 2026-06-02T17:44:57Z*
*Phase 73 Plan 01 execution time: 3m 46s*
