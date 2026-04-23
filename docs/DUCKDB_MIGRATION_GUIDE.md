# DuckDB Migration Guide

**Audience:** Future script authors adding new diagnostic or analysis scripts to the PCORnet R pipeline.
**Last updated:** 2026-04-23 (Phase 32)

---

## 1. Overview

The PCORnet R pipeline supports two data backends:

- **RDS mode** (`USE_DUCKDB = FALSE`): Tables are loaded from `.rds` files into an in-memory `pcornet` list. Each table is accessed as `pcornet$TABLE_NAME`.
- **DuckDB mode** (`USE_DUCKDB = TRUE`, default since Phase 32): Tables are queried from a DuckDB file via lazy SQL. Each table is accessed via `get_pcornet_table("TABLE_NAME")`, which returns a `tbl_dbi` object.

**Why DuckDB?** RDS mode loads all tables into memory at startup (several GB). DuckDB uses lazy evaluation -- queries are translated to SQL and only the requested subset is materialized. This reduces startup time, peak memory, and enables columnar analytics on large PCORnet tables.

**What didn't change:** All downstream analysis code uses dplyr verbs. The `get_pcornet_table()` dispatcher returns a dplyr-compatible object in both modes. Scripts that follow the patterns below work transparently on either backend.

---

## 2. Connection Pattern

Every script that accesses PCORnet data should use this pattern:

```r
source("R/00_config.R")  # Loads USE_DUCKDB flag + utilities

# For scripts in the main pipeline chain (sourced via 04_build_cohort.R):
#   Connection is handled by 01_load_pcornet.R -- no action needed.

# For standalone scripts (not sourced via the main chain):
if (USE_DUCKDB) {
  if (!exists("pcornet_con", envir = .GlobalEnv)) {
    open_pcornet_con()                    # Opens read-only DuckDB connection
  }
} else {
  if (!exists("pcornet", envir = .GlobalEnv)) {
    source("R/01_load_pcornet.R")         # Loads RDS tables into pcornet list
  }
}
```

**Connection lifecycle:**
- `open_pcornet_con()` opens a read-only DuckDB connection, creates the `TUMOR_REGISTRY_ALL` view, and stores the connection as `pcornet_con` in the global environment.
- `close_pcornet_con()` disconnects and removes `pcornet_con`.
- The connection is global by design (not per-script) so multiple scripts can share it in an interactive session.

**Important:** Never call `open_pcornet_con()` inside a function body. It modifies the global environment. Call it at script top-level only.

---

## 3. `get_pcornet_table()` and `materialize()`

### `get_pcornet_table(table_name)`

The backend dispatcher. Returns:
- **RDS mode:** An in-memory tibble from `pcornet$TABLE_NAME`.
- **DuckDB mode:** A lazy `tbl_dbi` object (SQL query not yet executed).

```r
# Access a table (works in both modes):
encounters <- get_pcornet_table("ENCOUNTER")
diagnosis  <- get_pcornet_table("DIAGNOSIS")
```

Returns `NULL` if the table doesn't exist (matches original `pcornet$TABLE` semantics).

### `materialize(lazy_tbl)`

Converts a lazy `tbl_dbi` to an in-memory tibble. In RDS mode, this is a no-op (data is already in memory).

```r
# Materialize when you need in-memory operations:
enc_df <- get_pcornet_table("ENCOUNTER") %>%
  filter(ENC_TYPE %in% c("IP", "AV")) %>%
  select(ID, ENCOUNTERID, ENC_TYPE, ADMIT_DATE, SOURCE) %>%
  materialize()

# Now enc_df is a tibble -- safe for nrow(), sum(), split(), etc.
nrow(enc_df)
```

---

## 4. When to Call `collect()` / `materialize()`

**Rule of thumb:** Keep queries lazy as long as possible. Materialize at the boundary where you need in-memory R operations.

### Must materialize before:
- `nrow()`, `ncol()`, `dim()` (need actual row count)
- `n_distinct()` (R-side distinct count)
- `sum()`, `mean()`, etc. on a column (outside `summarise()`)
- `saveRDS()`, `write_csv()` (serialization)
- `split()`, `for` loops, `apply()` family
- `bind_rows()` across lazy and in-memory objects
- `lubridate::interval()`, `time_length()` (R-side date math)
- `str_detect()` with complex regex patterns
- Custom R functions (anything not in dbplyr's translation table)
- `janitor::get_dupes()`, `data.table::as.data.table()`

### Safe to keep lazy:
- `filter()`, `select()`, `mutate()` with simple expressions
- `group_by()` + `summarise()` with standard aggregates (`n()`, `sum()`, `mean()`)
- `left_join()`, `inner_join()`, `semi_join()` (between lazy tables)
- `arrange()`, `distinct()`
- `rename()`, `relocate()`
- `%in%` with literal vectors
- `is.na()`, `!is.na()`

### The "materialize-early" pattern for diagnostic scripts:

Diagnostic scripts (R/20-R/24) do most of their work in-memory with complex R operations. The correct pattern is:

```r
# Load and immediately materialize
enc_tbl <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ENCOUNTERID, ENC_TYPE, ADMIT_DATE, SOURCE,
         PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY) %>%
  materialize()

# All downstream logic operates on the in-memory tibble
enc_tbl %>%
  group_by(SOURCE) %>%
  summarise(n_enc = n(), n_patients = n_distinct(ID))
```

---

## 5. Known Translation Gaps

See `docs/DUCKDB_TRANSLATION_NOTES.md` for the complete catalog (12 gaps documented across Phases 30-32). The top issues to watch for:

### Gap #1: Custom R functions in `filter()`

dbplyr cannot translate custom R functions to SQL. If you have a helper like `is_valid_code(x)`, it will silently fall back to fetching all data to R and filtering locally -- defeating lazy evaluation.

**Fix:** Inline the logic using dplyr-translatable operations:
```r
# Bad:  filter(is_valid_code(DX))
# Good: filter(DX %in% valid_codes)
```

### Gap #7: `nchar(trimws(x))` for empty-string detection

`nchar(trimws(x)) == 0` does not translate to SQL. Use direct comparison:
```r
# Bad:  filter(nchar(trimws(PAYER_TYPE_PRIMARY)) == 0)
# Good: filter(is.na(PAYER_TYPE_PRIMARY) | PAYER_TYPE_PRIMARY == "")
```

### Gap #4: `str_detect()` with complex regex

Dynamic regex patterns constructed with `paste0()` may not translate. Use the materialize-then-filter pattern:
```r
# Materialize the subset, then apply R-side regex
px_subset <- get_pcornet_table("PROCEDURES") %>%
  filter(PX_TYPE == "10") %>%
  materialize() %>%
  filter(str_detect(PX, complex_regex_pattern))
```

### General rule

If a dplyr chain produces an error like `"Column not found"` or `"Translation not supported"`, the typical fix is to insert `materialize()` before the problematic step. This converts the lazy query to an in-memory tibble, and all subsequent R operations work normally.

---

## 6. Template Script

Copy-pasteable skeleton for a new diagnostic script with DuckDB support:

```r
# ==============================================================================
# XX_my_new_diagnostic.R -- [Brief description]
# ==============================================================================
#
# Phase [N]: [REQ-ID]
# Purpose: [What this script does]
#
# Output: output/tables/[output_file].csv
#
# DuckDB migration: Uses get_pcornet_table() for backend-transparent access.
#   Materializes early because downstream logic uses [nrow/sum/split/etc.].
#
# Standalone script -- NOT part of the main pipeline sequence.
# ==============================================================================

# --- Dependencies ---
source("R/00_config.R")

library(dplyr)
library(glue)
library(readr)

# --- Backend setup (standalone script pattern) ---
if (USE_DUCKDB) {
  if (!exists("pcornet_con", envir = .GlobalEnv)) {
    open_pcornet_con()
  }
} else {
  if (!exists("pcornet", envir = .GlobalEnv)) {
    source("R/01_load_pcornet.R")
  }
}

message("\n", strrep("=", 60))
message("[DIAGNOSTIC] My New Diagnostic")
message(strrep("=", 60))

# ==============================================================================
# 1. LOAD DATA
# ==============================================================================

# Load tables via backend dispatcher; materialize for in-memory operations
encounters <- get_pcornet_table("ENCOUNTER") %>%
  select(ID, ENCOUNTERID, ENC_TYPE, ADMIT_DATE, SOURCE,
         PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY) %>%
  materialize()

demographic <- get_pcornet_table("DEMOGRAPHIC") %>%
  select(ID, SOURCE, SEX, RACE, HISPANIC, BIRTH_DATE) %>%
  materialize()

message(glue("  Loaded {nrow(encounters)} encounters, {nrow(demographic)} patients"))

# ==============================================================================
# 2. ANALYSIS
# ==============================================================================

# [Your analysis logic here -- operates on in-memory tibbles]

results <- encounters %>%
  group_by(SOURCE, ENC_TYPE) %>%
  summarise(
    n_encounters = n(),
    n_patients   = n_distinct(ID),
    .groups      = "drop"
  )

# ==============================================================================
# 3. OUTPUT
# ==============================================================================

dir.create(file.path(CONFIG$output_dir, "tables"), showWarnings = FALSE, recursive = TRUE)
output_path <- file.path(CONFIG$output_dir, "tables", "my_new_diagnostic.csv")
write_csv(results, output_path)
message(glue("\n  Output written to: {output_path}"))

# ==============================================================================
# 4. CONSOLE SUMMARY
# ==============================================================================

message(strrep("=", 60))
message("[DIAGNOSTIC] Complete")
message(strrep("=", 60))
```

---

## 7. Parity Test Methodology

When migrating an existing RDS-based script to DuckDB, verify output equivalence:

### Step 1: Capture RDS baseline

```r
USE_DUCKDB <- FALSE
source("R/01_load_pcornet.R")
source("R/XX_my_script.R")
# Save key output objects
saveRDS(results, "output/parity/XX_rds_baseline.rds")
```

### Step 2: Run with DuckDB

```r
USE_DUCKDB <- TRUE
open_pcornet_con()
source("R/XX_my_script.R")
saveRDS(results, "output/parity/XX_duckdb_result.rds")
```

### Step 3: Compare

```r
rds_baseline <- readRDS("output/parity/XX_rds_baseline.rds")
ddb_result   <- readRDS("output/parity/XX_duckdb_result.rds")

# Dimension check
stopifnot(nrow(rds_baseline) == nrow(ddb_result))
stopifnot(ncol(rds_baseline) == ncol(ddb_result))

# Column name check
stopifnot(identical(sort(colnames(rds_baseline)), sort(colnames(ddb_result))))

# Value check (for data frames with simple types)
mismatches <- anti_join(rds_baseline, ddb_result)
message(glue("Mismatched rows: {nrow(mismatches)}"))
if (nrow(mismatches) > 0) {
  message("PARITY FAILED -- investigate mismatches")
  print(head(mismatches))
} else {
  message("PARITY PASSED")
}
```

### What to expect

- **Exact match** is the goal. DuckDB and RDS should produce identical output for the same input data.
- **Row ordering** may differ. Use `arrange()` before comparison, or use `anti_join()` which is order-independent.
- **Floating-point differences** are unlikely in this pipeline (mostly counts and categories), but if present, use `all.equal()` with tolerance instead of `identical()`.
- **Known exceptions:** None as of Phase 32. All 5 diagnostic scripts and the cohort pipeline produce identical output on both backends.

---

## References

- `R/utils_duckdb.R` -- Source code for `get_pcornet_table()`, `materialize()`, `open_pcornet_con()`, `close_pcornet_con()`
- `docs/DUCKDB_TRANSLATION_NOTES.md` -- Complete catalog of 12 translation gaps with workarounds
- `R/00_config.R` -- `USE_DUCKDB` flag and `CONFIG$cache$duckdb_path`
- `R/28_benchmark_cohort.R` -- Benchmark script example
- `R/20_all_source_missingness.R` -- Example migrated diagnostic script

---
*Migration guide created Phase 32, Plan 02 (2026-04-23)*
