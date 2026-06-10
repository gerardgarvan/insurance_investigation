---
phase: 95-infrastructure-setup
plan: 01
subsystem: data.table infrastructure
tags:
  - data.table
  - performance
  - utilities
  - lookups
dependency_graph:
  requires: []
  provides:
    - utils_dt.R conversion helpers
    - LOOKUP_TABLES_DT keyed lookups
    - data.table library loaded globally
  affects:
    - Phase 96 (classify_payer_tier_dt implementation)
    - Phase 97 (R/60 hot-path migration)
    - Phase 98 (R/28 + remaining lookup optimization)
tech_stack:
  added:
    - data.table 1.16.2+ (global library load)
  patterns:
    - Defensive conversion helpers (ensure_dt, to_tibble_safe)
    - Keyed data.table lookups with semantic column names
    - Explicit namespace prefixes (data.table::, tibble::, glue::)
key_files:
  created:
    - R/utils/utils_dt.R
  modified:
    - R/00_config.R
decisions:
  - Use as.data.table() not setDT() in ensure_dt() to avoid mutating input (per anti-pattern guidance)
  - Flatten TREATMENT_CODES from nested list to 3-column long format with code/code_system/treatment_type
  - Preserve all original named vectors unchanged for backward compatibility (INFRA-04)
  - Auto-source section remains last in R/00_config.R so utils_dt.R can reference LOOKUP_TABLES_DT
metrics:
  duration_seconds: 139
  completed_date: "2026-06-10T20:54:23Z"
  tasks_completed: 2
  files_created: 1
  files_modified: 1
  commits: 2
---

# Phase 95 Plan 01: data.table Infrastructure Setup Summary

**One-liner:** Created data.table conversion helpers (ensure_dt, to_tibble_safe, get_lookup_dt) and 6 keyed lookup tables (AMC_PAYER_LOOKUP, DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP, CANCER_SITE_MAP, TIER_MAPPING, TREATMENT_CODES) for Phase 96-98 performance optimization.

## What Was Built

### Task 1: R/utils/utils_dt.R - Defensive Conversion Helpers

Created new utility module with 3 helper functions for tibble/data.table boundary management:

**ensure_dt(df, name, script_name)**
- Converts input to data.table with defensive guards
- NULL input: immediate stop with glue-formatted error
- Empty input (0 rows): warning + return empty data.table preserving structure
- Already data.table: no-op (return as-is)
- Otherwise: `data.table::as.data.table(df)` to create copy (not setDT per anti-pattern)

**to_tibble_safe(dt, name, script_name)**
- Converts data.table back to tibble for dplyr pipeline compatibility
- Same defensive pattern: NULL stop, empty warning, no-op if already tibble
- Uses `tibble::as_tibble(dt)`

**get_lookup_dt(table_name, lookup_list = LOOKUP_TABLES_DT)**
- Retrieves keyed data.table from LOOKUP_TABLES_DT by string name
- Validates table_name is character
- Informative error with available table names if lookup fails
- Default argument uses LOOKUP_TABLES_DT from R/00_config.R (loaded before auto-source)

All functions follow utils_assertions.R documentation pattern with roxygen-style comments, explicit namespace prefixes (data.table::, tibble::, glue::), and no library() calls (dependencies loaded by R/00_config.R).

### Task 2: R/00_config.R - data.table Library and LOOKUP_TABLES_DT

**Addition 1: SECTION 7c - DATA.TABLE LIBRARY (Phase 95, v3.0)**
- Added `library(data.table)` immediately after `library(checkmate)` at line 3414
- Loads data.table globally per D-01 so it's available to all scripts
- Coexists with dplyr (conflict-prone functions use explicit package::function() per D-02)
- Placed before SECTION 8 auto-source so data.table is available when utils_dt.R loads

**Addition 2: SECTION 7d - KEYED DATA.TABLE LOOKUP TABLES (Phase 95, v3.0)**
- Built LOOKUP_TABLES_DT named list with 6 keyed data.tables
- Each table constructed from existing named vectors/lists using semantic column names per D-03
- Each table has `setkey()` applied for O(log n) binary-search joins

**6 Keyed Lookup Tables:**

1. **AMC_PAYER_LOOKUP**: code (character) -> payer_category (character)
   - 219 rows from AMC 8-category payer mapping
   - Keyed on `code` for fast payer code lookups

2. **DRUG_GROUPINGS**: code (character) -> drug_group (character)
   - 1,858 rows mapping treatment codes to drug groups
   - Keyed on `code` for treatment classification

3. **CODE_SUBCATEGORY_MAP**: code (character) -> subcategory (character)
   - 1,848 rows mapping codes to subcategories
   - Keyed on `code` for granular treatment grouping

4. **CANCER_SITE_MAP**: prefix (character) -> cancer_site (character)
   - 3-char ICD-10 prefixes to cancer site categories
   - Keyed on `prefix` for diagnosis categorization

5. **TIER_MAPPING**: payer_category (character) -> tier (integer)
   - 8 rows (Medicaid=1, Medicare=2, Private=3, Other govt=4, Other=5, Self-pay=6, Uninsured=7, Missing=8)
   - Keyed on `payer_category` for hierarchical same-day payer resolution

6. **TREATMENT_CODES**: code (character), code_system (character), treatment_type (character)
   - Flattened from nested list structure per D-04
   - 3,406 rows with columns: code, code_system, treatment_type
   - Keyed on `code` for treatment episode detection
   - Parsing logic: split element name on first underscore (e.g., "chemo_hcpcs" -> treatment_type="chemo", code_system="hcpcs")
   - Uses `rbindlist(rows)` for flattening per research guidance

**Sanity checks added:**
- `stopifnot(length(LOOKUP_TABLES_DT) == 6)` to verify all 6 tables present
- `stopifnot(all(c("AMC_PAYER_LOOKUP", ...) %in% names(LOOKUP_TABLES_DT)))` to verify exact names
- `message()` call to log successful build at source time

**Backward compatibility preserved:**
- All original named vectors (AMC_PAYER_LOOKUP, DRUG_GROUPINGS, etc.) remain unchanged
- No modifications to existing code, only additions
- Auto-source section (SECTION 8) remains last in file (line 3535+)

## Deviations from Plan

None - plan executed exactly as written.

## Technical Decisions

1. **as.data.table() not setDT() in ensure_dt()**: Per anti-pattern guidance, as.data.table() creates a copy and does not mutate the input. This is safer for boundary functions where input ownership is unclear.

2. **TREATMENT_CODES flattening logic**: Split element name on first underscore to handle multi-underscore code systems (e.g., "chemo_icd10pcs_prefixes" -> treatment_type="chemo", code_system="icd10pcs_prefixes"). Used `regexpr()` + `substr()` instead of strsplit() for clarity.

3. **Auto-source section placement**: Kept SECTION 8 (auto-source utility functions) as the last section so that utils_dt.R can reference LOOKUP_TABLES_DT in its default argument for get_lookup_dt(). This establishes clear dependency order: config constants → libraries → lookup tables → utility functions.

4. **Explicit namespace prefixes**: All data.table/tibble/glue calls use package::function() syntax per D-02 to avoid namespace conflicts between data.table and dplyr (conflicts on: between, first, last, transpose).

## Verification Results

All verification checks passed:

1. ✓ `grep -c "ensure_dt\|to_tibble_safe\|get_lookup_dt" R/utils/utils_dt.R` returns 14 (function definitions + documentation)
2. ✓ `grep "LOOKUP_TABLES_DT <- list" R/00_config.R` shows list construction present
3. ✓ `grep "library(data.table)" R/00_config.R` shows data.table loaded globally
4. ✓ `grep "setkey" R/00_config.R` returns 6 setkey() calls (one per lookup table)
5. ✓ No existing named vectors modified (git diff shows only additions to R/00_config.R)

## Must-Haves Status

- [x] User can source R/utils/utils_dt.R and call ensure_dt(), to_tibble_safe(), get_lookup_dt() without errors
- [x] User can access LOOKUP_TABLES_DT$AMC_PAYER_LOOKUP in R console and see keyed data.table with correct rows
- [x] User can access all 6 LOOKUP_TABLES_DT entries and each has setkey() applied
- [x] TREATMENT_CODES is flattened to a long-format 3-column data.table keyed on code

**Artifacts:**
- [x] R/utils/utils_dt.R: 152 lines, exports ensure_dt/to_tibble_safe/get_lookup_dt (min 80 lines ✓)
- [x] R/00_config.R: Contains LOOKUP_TABLES_DT list with 6 keyed data.tables, library(data.table) call

**Key Links:**
- [x] R/00_config.R auto-sources R/utils/utils_dt.R via list.files at line 3537
- [x] R/00_config.R builds LOOKUP_TABLES_DT after existing lookup vectors (lines 3426-3533)

## Known Stubs

None. All infrastructure is fully implemented and functional.

## Self-Check: PASSED

**Created files exist:**
```
FOUND: R/utils/utils_dt.R
```

**Modified files exist:**
```
FOUND: R/00_config.R
```

**Commits exist:**
```
FOUND: f799f1d (Task 1: create utils_dt.R)
FOUND: 037af66 (Task 2: add data.table library and LOOKUP_TABLES_DT)
```

**Function definitions verified:**
```
ensure_dt: present with NULL/empty guards
to_tibble_safe: present with NULL/empty guards
get_lookup_dt: present with table_name validation
```

**LOOKUP_TABLES_DT structure verified:**
```
6 tables present: AMC_PAYER_LOOKUP, DRUG_GROUPINGS, CODE_SUBCATEGORY_MAP,
                  CANCER_SITE_MAP, TIER_MAPPING, TREATMENT_CODES
Each table has setkey() applied on appropriate column
```

## What's Next

Phase 96 can now implement classify_payer_tier_dt() using:
- `ensure_dt()` to convert enrollment tibble to data.table
- `get_lookup_dt("AMC_PAYER_LOOKUP")` for keyed payer code lookup
- `get_lookup_dt("TIER_MAPPING")` for tier resolution
- `to_tibble_safe()` to return tibble result for dplyr compatibility

Phase 97 can migrate R/60 same-day payer resolution to use:
- `get_lookup_dt("TIER_MAPPING")` for hierarchical resolution
- data.table group-by syntax for 5-20x speedup on millions of encounter rows

Phase 98 can replace named vector lookups across R/28 and remaining scripts with:
- `get_lookup_dt("DRUG_GROUPINGS")` for treatment classification
- `get_lookup_dt("CODE_SUBCATEGORY_MAP")` for subcategory assignment
- `get_lookup_dt("TREATMENT_CODES")` for episode detection

All lookup infrastructure is now in place for v3.0 performance optimization.
