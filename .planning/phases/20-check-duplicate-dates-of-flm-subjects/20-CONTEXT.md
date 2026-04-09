# Phase 20: Check Duplicate Dates of FLM Subjects - Context

**Gathered:** 2026-04-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Investigate whether FLM-sourced patients in the OneFlorida+ cohort have duplicate ENCOUNTER rows on the same date from multiple data sources. Quantify the duplication, compare payer/insurance data completeness across sources for those duplicate-date encounters, and recommend which source to prefer when duplicates exist. Output is a standalone diagnostic R script with CSV files to `output/tables/`.

</domain>

<decisions>
## Implementation Decisions

### Duplicate Definition
- **D-01:** "Duplicate date" = same patient (ID) with multiple ENCOUNTER rows on the same date, grouped by ID + date only (not considering ENC_TYPE)
- **D-02:** Check BOTH same-date collisions (different rows, same date) AND exact row duplicates (fully identical rows across all columns)
- **D-03:** Check ALL time-related columns in the ENCOUNTER table (ADMIT_DATE, ADMIT_TIME, DISCHARGE_DATE, DISCHARGE_TIME), not just ADMIT_DATE
- **D-04:** Key focus: identify encounters on the same date that come from DIFFERENT SOURCE values in the ENCOUNTER table

### Investigation Scope
- **D-05:** FLM patients identified via `DEMOGRAPHIC.SOURCE == "FLM"` — use those patient IDs to filter the ENCOUNTER table
- **D-06:** Check ALL FLM patients in raw data, not just HL cohort members
- **D-07:** ENCOUNTER table only — do not check DIAGNOSIS, PROCEDURES, or other tables
- **D-08:** For duplicate-date encounters from multiple sources, compare which source has more complete payer/insurance data

### Payer Completeness Comparison
- **D-09:** Compare payer data completeness on BOTH PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY across sources
- **D-10:** Use the same missingness definition as Phase 19 (D-01): NA, empty string, NI, UN, OT, 99, 9999 all count as missing
- **D-11:** Goal: determine which source consistently provides better payer data when multiple sources exist for the same patient-date

### Concern & Purpose
- **D-12:** Both data quality (quantify the duplication problem) AND pipeline impact (assess whether duplicates affect encounter counts, payer mode, treatment detection)
- **D-13:** Root cause is unknown — this investigation is exploratory, no specific hypothesis
- **D-14:** Script should report findings AND recommend which source to prefer for payer data when duplicates exist

### Output & Deliverables
- **D-15:** Standalone diagnostic R script (next available number after Phase 19's script). Sources its own dependencies. Not part of main pipeline sequence
- **D-16:** CSV output files to `output/tables/` — consistent with existing pipeline pattern
- **D-17:** Three CSV outputs:
  - Patient-level duplicate summary (N encounters, N duplicate dates, N multi-source dates, payer completeness per source)
  - Date-level detail (one row per patient-date with duplicate encounters: which sources, payer data present/missing per source)
  - Aggregate summary (overall FLM duplicate rates, multi-source rates, payer completeness comparison)
- **D-18:** Console logging for quick HiPerGator review, detailed breakdowns in CSV files

### Claude's Discretion
- Exact CSV file names and column structures
- Script number (next available after existing scripts)
- Console logging format and verbosity
- How to structure the payer completeness recommendation (e.g., percentage-based ranking of sources)
- Whether to include visualizations or keep as CSV/console only
- Additional breakdowns beyond the specified three CSVs if informative patterns emerge

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### ENCOUNTER table structure
- `R/01_load_pcornet.R` lines 118-144 — ENCOUNTER_SPEC with 19 columns including ADMIT_DATE, ADMIT_TIME, DISCHARGE_DATE, DISCHARGE_TIME, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, SOURCE
- `R/00_config.R` line 107 — SOURCE column = partner/site identifier (AMS, UMI, FLM, VRT)

### Payer handling and missingness definitions
- `R/02_harmonize_payer.R` — Payer harmonization logic, sentinel handling, enrollment completeness
- `R/00_config.R` — PAYER_MAPPING with sentinel_values, unavailable_codes, unknown_codes

### Prior phase context (missingness patterns)
- `.planning/phases/19-investigate-insurance-missingness-source-uf-specifically/19-CONTEXT.md` — Phase 19 missingness definition (D-01 through D-04) to reuse for payer completeness comparison

### Standalone diagnostic script pattern
- `R/date_range_check.R` — Example of standalone diagnostic script pattern (source dependencies, console output)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/01_load_pcornet.R` `load_pcornet_table()` function: loads ENCOUNTER and DEMOGRAPHIC tables with caching support
- `R/00_config.R` PAYER_MAPPING$sentinel_values: c("NI", "UN", "OT") — reuse for missingness classification
- Phase 19 missingness definition pattern: NA, empty, NI, UN, OT, 99, 9999

### Established Patterns
- Patient ID column is `ID` (not PATID) across all tables
- SOURCE column in DEMOGRAPHIC identifies partner site (FLM for Florida Medical)
- SOURCE column also exists in ENCOUNTER table — may differ from DEMOGRAPHIC.SOURCE for cross-site patients
- Standalone diagnostic scripts: source("R/01_load_pcornet.R"), use message() + glue() for logging, write_csv() to output/tables/
- Console logging via `message()` + `glue()`

### Integration Points
- Input: `pcornet$ENCOUNTER` (all 19 columns, especially ADMIT_DATE, ADMIT_TIME, DISCHARGE_DATE, DISCHARGE_TIME, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY, SOURCE, ID)
- Input: `pcornet$DEMOGRAPHIC` (ID, SOURCE) — filter for SOURCE == "FLM" to get patient IDs
- Output: CSV files to `output/tables/` with FLM duplicate date analysis

</code_context>

<specifics>
## Specific Ideas

- Identify all FLM patients via DEMOGRAPHIC.SOURCE == "FLM", then filter ENCOUNTER table to those IDs
- For each patient-date, check if multiple ENCOUNTER rows exist
- When duplicates found, check if ENCOUNTER.SOURCE differs across the duplicate rows (cross-site encounters)
- Compare PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY completeness across different SOURCE values
- Recommend which source to prefer based on payer data completeness rates

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 20-check-duplicate-dates-of-flm-subjects*
*Context gathered: 2026-04-09*
