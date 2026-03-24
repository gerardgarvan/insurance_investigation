# Phase 1: Foundation & Data Loading - Context

**Gathered:** 2026-03-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Configure HiPerGator paths, load PCORnet CDM CSV tables with correct data types, and build utility functions for attrition logging and date parsing. This phase establishes the data loading infrastructure that all downstream phases depend on. No data transformation, filtering, or visualization happens here.

</domain>

<decisions>
## Implementation Decisions

### Config structure
- **D-01:** Use nested lists for organization (CONFIG$data_dir, PCORNET_PATHS$ENROLLMENT, ICD_CODES$hl_icd10, PAYER_MAPPING$...) — prioritize human readability with clear comments per section
- **D-02:** HiPerGator-native paths only — data CSVs at `/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915`, R project at `/blue/erin.mobley-hl.bcu/R`. No local development switching or environment variable abstraction needed
- **D-03:** ICD codes defined as inline character vectors in config (ICD_CODES$hl_icd10, ICD_CODES$hl_icd9) — all 149 codes visible in one place
- **D-04:** Payer mapping rules defined in config (PAYER_MAPPING list) — prefix-to-category mapping. Harmonization script (Phase 2) applies the mapping but doesn't define it
- **D-05:** Analysis parameters included in config (CONFIG$analysis with thresholds like min_enrollment_days, dx_window_days) — central place to tweak without hunting through scripts
- **D-06:** Explicit table list in config (PCORNET_TABLES vector) — loader iterates this list, no auto-discovery

### CSV loading strategy
- **D-07:** Primary load set = 6 standard CDM tables (ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC) + 3 TUMOR_REGISTRY tables. TUMOR_REGISTRY tables are needed for HL diagnosis dates and treatment dates (DT_CHEMO, DT_RAD, etc.)
- **D-08:** Use readr::read_csv with explicit col_types — reliable, good error messages, sufficient for this cohort size
- **D-09:** Multi-format date parsing with fallback — try YYYY-MM-DD first, then DDMMMYYYY (SAS DATE9), then YYYYMMDD. Log warnings for unparseable dates
- **D-10:** Warn and skip on missing/inaccessible CSV files — log warning, continue loading other tables. Pipeline can work with partial data
- **D-11:** Use column names as-is from the CSVs — no renaming to CDM standard names. Patient ID column is `ID` (not `PATID`). All downstream code references actual column names
- **D-12:** Print load summary per table — table name, row count, column count, parse warnings
- **D-13:** Store loaded tables in a named list (pcornet$ENROLLMENT, pcornet$DIAGNOSIS, etc.) — clean namespace, easy to iterate
- **D-14:** CSV file naming pattern: `TABLE_Mailhot_V1.csv` (e.g., ENROLLMENT_Mailhot_V1.csv, DIAGNOSIS_Mailhot_V1.csv)
- **D-15:** SOURCE column in every table = partner/site identifier (AMS, UMI, FLM, VRT)

### Utility function design
- **D-16:** Manual log_attrition() calls — init_attrition_log() creates empty data frame, log_attrition(step_name, n_after) appends rows. User controls step names and what gets logged
- **D-17:** Attrition tracks patient-level counts (unique ID count), not row-level — clinically meaningful for CONSORT diagrams
- **D-18:** Attrition log includes percentage excluded at each step — columns: step_name, n_before, n_after, n_excluded, pct_excluded. Ready for waterfall chart labels
- **D-19:** No HIPAA suppression utilities — data stays on HiPerGator's HIPAA-compliant environment, exploratory outputs don't need suppression
- **D-20:** parse_pcornet_date() utility function — reusable date parser using lubridate that tries multiple SAS export formats with fallback
- **D-21:** 00_config.R auto-sources all utils_*.R files — any script that sources config gets utilities automatically
- **D-22:** Simple message() calls with glue for logging — no custom log wrapper needed

### Project scaffolding
- **D-23:** Numbered R/ scripts following architecture research: R/00_config.R, R/01_load_pcornet.R, R/02_harmonize_payer.R, R/03_cohort_predicates.R, R/04_build_cohort.R, R/05_visualize_waterfall.R, R/06_visualize_sankey.R, plus R/utils_*.R files
- **D-24:** No main.R orchestrator — scripts sourced manually in RStudio for interactive exploration
- **D-25:** Initialize renv from the start for reproducible package management on HiPerGator
- **D-26:** Create full output directory structure upfront: output/figures/, output/tables/, output/cohort/

### Claude's Discretion
- Exact col_types specifications per table (based on csv_columns.txt schema)
- Internal structure of the parse_pcornet_date() function
- renv initialization details
- .Rprofile and .gitignore contents

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Data schema
- `csv_columns.txt` — Complete column listing for all 22 PCORnet CDM CSV files in the Mailhot extract. Defines actual column names (ID not PATID), file naming pattern (TABLE_Mailhot_V1.csv), and column counts per table

### Payer mapping reference
- `C:\cygwin64\home\Owner\Data loading and cleaing\docs\PAYER_VARIABLES_AND_CATEGORIES.md` — Defines the exact 9-category payer mapping and dual-eligible rules to replicate in R. Includes prefix-to-category mapping, sentinel value handling, and encounter-level dual-eligible logic

### Architecture patterns
- `.planning/research/ARCHITECTURE.md` — Recommended project structure, numbered script pattern, named predicate pattern, attrition logging pattern, data flow diagrams
- `.planning/research/STACK.md` — Technology stack decisions (readr, tidyverse, ggalluvial, renv), version pinning, HiPerGator module loading, anti-patterns to avoid

### Project context
- `.planning/PROJECT.md` — Core value, constraints, key decisions, context about Python pipeline relationship
- `.planning/REQUIREMENTS.md` — LOAD-01, LOAD-02, LOAD-03 requirements for this phase

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- No existing R code — greenfield project. All scripts will be created from scratch

### Established Patterns
- Python pipeline at `C:\cygwin64\home\Owner\Data loading and cleaing\` provides reference payer mapping logic but is not consumed by R pipeline
- PCORnet CDM column names in this extract use `ID` (not `PATID`) for patient identifier across all tables
- CSV naming pattern `TABLE_Mailhot_V1.csv` is consistent across all 22 files

### Integration Points
- Data input: `/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915` (22 CSV files)
- R project location: `/blue/erin.mobley-hl.bcu/R`
- HiPerGator module: `module load R/4.4.2`
- Python pipeline payer doc: cross-reference for validation in Phase 2

</code_context>

<specifics>
## Specific Ideas

- TUMOR_REGISTRY tables (3 of them) should be in the primary load set because they contain HL-specific diagnosis dates and treatment dates (DT_CHEMO, DT_RAD) that will be needed to establish diagnosis dates when available
- Config must be "very human readable" — clear section headers, comments explaining each block, descriptive variable names
- The 22 CSV files are from OneFlorida+ Mailhot HL cohort extract dated 2025-09-15

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-foundation-data-loading*
*Context gathered: 2026-03-24*
