---
phase: 161
plan: "01"
subsystem: duckdb-ingest
tags: [bugfix, death-table, imputation-flag, date-parsing]
key-files:
  modified:
    - R/01_load_pcornet.R
    - R/03_duckdb_ingest.R
decisions:
  - "Fix upstream in R/01 (NOT_DATE_COLS), not downstream in R/03 — values were already NULL by the time R/03 saw them"
  - "Add a hard stop() in R/03 rather than a silent coerce — regression must fail loudly"
  - "DEATH_TIME_IMPUTE not present in this extract (absent from DEATH_SPEC); no action needed"
---

# Phase 161 Plan 01: DEATH_DATE_IMPUTE — Fix Type-Cast Loss Summary

One-liner: Added DEATH_DATE_IMPUTE to R/01 NOT_DATE_COLS exclusion list and a defensive stop() guard in R/03 so the B/D/M/N imputation flag is preserved as VARCHAR through the full pipeline.

## Root Cause

`R/01_load_pcornet.R` uses a name-pattern regex to detect date columns for automatic parsing:

```r
date_cols <- names(df)[str_detect(names(df), "(?i)(DATE|...)")]
```

`DEATH_DATE_IMPUTE` matches because its name contains "DATE". It was then passed through `parse_pcornet_date()`, which converts non-parseable strings to `NA` and returns a `Date` class column. All B/D/M/N flag values became `NA Date`. When R/03 wrote that column to DuckDB, it was typed as DATE with 0 non-null values.

The existing exclusion list `NOT_DATE_COLS` only contained `DXDATE_IMPUTED`. `DEATH_DATE_IMPUTE` was not listed.

## Files Changed

### R/01_load_pcornet.R (line ~510)

Added `DEATH_DATE_IMPUTE` to `NOT_DATE_COLS`:

```r
NOT_DATE_COLS <- c("DXDATE_IMPUTED", "DEATH_DATE_IMPUTE")
```

With an explanatory comment identifying the column as a PCORnet CDM B/D/M/N flag.

### R/03_duckdb_ingest.R (before the pre-1900 sentinel block)

Added a defensive guard that:
1. Detects if DEATH_DATE_IMPUTE arrives typed as Date (meaning values were lost upstream).
2. If so, calls `stop()` with a clear message pointing to the upstream cause.
3. If it arrives correctly as character, coerces it explicitly with `as.character()` (idempotent, documents intent).

This ensures that any future regression in R/01 fails loudly at ingest time rather than silently writing NULLs.

## What Was NOT Changed

- `DEATH_TIME_IMPUTE` — not present in the DEATH_SPEC for this extract; no action needed.
- `R/88_smoke_test_comprehensive.R` — had no existing assertions about `DEATH_DATE_IMPUTE` type; the new guard in R/03 serves as the regression check.
- No schema changes; DuckDB type inference from the R data frame will now correctly assign VARCHAR.

## Deviations from Plan

The plan described checking the raw CSV and RDS cache interactively (Steps 2-3). Those steps require running on HiPerGator. Instead, the root cause was identified by static analysis of R/01 (the `NOT_DATE_COLS` exclusion list and the date-name regex). The fix location and mechanism exactly match what Step 4 of the plan specified.

Steps 1 (snapshot output/before_161) and 6 (rebuild) must still run on HiPerGator.

## What Still Needs to Run on HiPerGator

### Step 1 — Snapshot pre-161 outputs (run before rebuilding)

```bash
cd /blue/erin.mobley-hl.bcu/insurance_investigation
mkdir -p output/before_161
cp -p output/*147* output/before_161/ 2>/dev/null
cp -p output/*E_patient_modality_dates* output/before_161/ 2>/dev/null
ls -l output/before_161/   # must not be empty
```

### Step 6 — Rebuild RDS cache and DuckDB

```bash
module load R/4.4.2

# Delete the stale DEATH cache so R/01 re-reads the raw CSV
rm /blue/erin.mobley-hl.bcu/clean/rds/raw/DEATH.rds

# Rebuild the DEATH RDS (only DEATH was affected; other tables unchanged)
Rscript R/01_load_pcornet.R

# Rebuild DuckDB from fresh RDS files
Rscript R/03_duckdb_ingest.R
```

### Step 7 — Verify

```r
source("R/00_config.R")
con <- DBI::dbConnect(duckdb::duckdb(), CONFIG$cache$duckdb_path, read_only = TRUE)

# Should show B, D, M, N distribution (or NA only if raw extract has no flags)
DBI::dbGetQuery(con, "SELECT DEATH_DATE_IMPUTE, COUNT(*) AS n FROM DEATH GROUP BY 1 ORDER BY n DESC")

# Must return 0 rows (no DATE-typed column whose name does not end in _DATE)
DBI::dbGetQuery(con, "
  SELECT table_name, column_name, data_type
    FROM information_schema.columns
   WHERE data_type = 'DATE' AND NOT regexp_matches(upper(column_name), '_DATE$')")

DBI::dbDisconnect(con, shutdown = TRUE)
```

## Acceptance Criteria Status

| Criterion | Status |
|---|---|
| Step where flag values lost is identified | DONE — R/01 date-name regex, line 511 |
| DEATH_DATE_IMPUTE excluded from date parse in R/01 | DONE — commit c6b6140 |
| Defensive stop() guard in R/03 | DONE — commit c6b6140 |
| DEATH_DATE_IMPUTE is VARCHAR in pcornet.duckdb | Pending HiPerGator rebuild |
| Value distribution matches raw extract | Pending HiPerGator verification |
| No DATE-typed column whose name does not end in _DATE | Pending HiPerGator verification |

## Self-Check: PASSED

- R/01_load_pcornet.R: edit confirmed (NOT_DATE_COLS now includes DEATH_DATE_IMPUTE)
- R/03_duckdb_ingest.R: edit confirmed (stop() guard inserted before pre-1900 block)
- Commit c6b6140 exists (2 files changed, 20 insertions, 1 deletion)
