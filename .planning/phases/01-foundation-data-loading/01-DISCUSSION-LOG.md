# Phase 1: Foundation & Data Loading - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-24
**Phase:** 01-foundation-data-loading
**Areas discussed:** Config structure, CSV loading strategy, Utility function design, Project scaffolding

---

## Config Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Nested lists | CONFIG$data_dir, PCORNET_PATHS$ENROLLMENT — grouped by domain. Cleaner namespace | |
| Flat variables | DATA_DIR, ENROLLMENT_PATH — simple top-level assignments | |
| You decide | Claude picks | |

**User's choice:** Nested lists, with emphasis on being "very human readable"
**Notes:** User stressed readability as a priority for the config structure

---

| Option | Description | Selected |
|--------|-------------|----------|
| Environment variable with fallback | Sys.getenv() with defaults — one config works everywhere | |
| Manual path switching | Comment/uncomment lines for HiPerGator vs local | |
| You decide | Claude picks | |

**User's choice:** HiPerGator-native paths only
**Notes:** Data on /orange/erin.mobley-hl.bcu/Mailhot_V1_20250915, R project on /blue/erin.mobley-hl.bcu/R. No local development workflow needed.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Inline vectors in config | ICD_CODES$hl_icd10 and ICD_CODES$hl_icd9 in 00_config.R | |
| External CSV/text file | Load from data/reference/hl_icd_codes.csv | |
| You decide | Claude picks | |

**User's choice:** Inline vectors in config

---

| Option | Description | Selected |
|--------|-------------|----------|
| In config | PAYER_MAPPING list in 00_config.R | |
| In harmonization script | Payer mapping logic in 02_harmonize_payer.R | |
| You decide | Claude picks | |

**User's choice:** In config

---

| Option | Description | Selected |
|--------|-------------|----------|
| Include analysis params | CONFIG$analysis with min_enrollment_days, dx_window_days, etc. | |
| Paths, codes, and mappings only | Config focused on data references | |
| You decide | Claude picks | |

**User's choice:** Include analysis params

---

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit table list in config | PCORNET_TABLES vector lists all 22 table names | |
| Auto-discover CSVs | Loader finds all *.csv files in data directory | |
| You decide | Claude picks | |

**User's choice:** Explicit table list in config

---

## CSV Loading Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Primary tables only | Load 6 core tables by default, others on demand | |
| All 22 tables at once | Load everything upfront | |
| You decide | Claude picks | |

**User's choice:** Primary tables + TUMOR_REGISTRY
**Notes:** Include TUMOR_REGISTRY1/2/3 because they contain dates needed to establish diagnosis date when available

---

| Option | Description | Selected |
|--------|-------------|----------|
| readr::read_csv | Standard tidyverse reader, reliable | |
| vroom::vroom | Faster via lazy loading | |
| You decide | Claude picks | |

**User's choice:** readr::read_csv

---

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-format with fallback | Try YYYY-MM-DD, then DDMMMYYYY, then YYYYMMDD | |
| Strict single format | Assume YYYY-MM-DD, fail if not | |
| You decide | Claude picks | |

**User's choice:** Multi-format with fallback

---

| Option | Description | Selected |
|--------|-------------|----------|
| Warn and skip | Log warning, continue loading other tables | |
| Fail immediately | Stop pipeline if any CSV missing | |
| You decide | Claude picks | |

**User's choice:** Warn and skip

---

| Option | Description | Selected |
|--------|-------------|----------|
| Keep original PCORnet names | PATID, ENR_START_DATE stay as-is | |
| Clean to snake_case | patid, enr_start_date via clean_names() | |
| You decide | Claude picks | |

**User's choice:** Use columns as-is (ID not PATID)
**Notes:** Patient ID column is actually `ID` in this extract, not `PATID`. User confirmed to use actual column names without renaming.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Inspect headers, map to CDM names | Rename non-standard columns to CDM spec | |
| Use columns as-is | Keep whatever names CSVs have | |
| You decide | Claude picks | |

**User's choice:** Use columns as-is
**Notes:** Referred to csv_columns.txt for actual column names

---

| Option | Description | Selected |
|--------|-------------|----------|
| Standard 6 CDM tables | ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC | |
| Include TUMOR_REGISTRY too | Add TUMOR_REGISTRY1/2/3 to default load set | |
| You decide | Claude picks | |

**User's choice:** Include TUMOR_REGISTRY too
**Notes:** TUMOR_REGISTRY contains HL-specific staging and treatment dates (DT_CHEMO, DT_RAD)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, SOURCE = site ID | Partner site identifier (AMS, UMI, FLM, VRT) | |
| No, something else | Different meaning | |
| Not sure | Need to check | |

**User's choice:** Yes, it's the site ID

---

| Option | Description | Selected |
|--------|-------------|----------|
| Summary per table | Print table name, row count, column count, parse warnings | |
| Silent loading | No output during loading | |
| You decide | Claude picks | |

**User's choice:** Summary per table

---

| Option | Description | Selected |
|--------|-------------|----------|
| Named list | pcornet$ENROLLMENT, pcornet$DIAGNOSIS | |
| Separate objects | enrollment_df, diagnosis_df in global env | |
| You decide | Claude picks | |

**User's choice:** Named list

---

## Utility Function Design

| Option | Description | Selected |
|--------|-------------|----------|
| Manual log_attrition() | init_attrition_log() + log_attrition() after each filter | |
| tidylog auto-logging | Auto-prints row counts for every dplyr operation | |
| Both combined | tidylog for console + manual for structured log | |
| You decide | Claude picks | |

**User's choice:** Manual log_attrition()

---

| Option | Description | Selected |
|--------|-------------|----------|
| < 11 with '<11' label | Standard CMS suppression | |
| < 11 with '*' label | Asterisk replacement | |
| You decide | Claude picks | |

**User's choice:** Don't do HIPAA suppression
**Notes:** Data stays on HiPerGator, exploratory analysis. No suppression needed.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Skip entirely | Don't build suppression utilities at all | |
| Include but don't apply | Write utility for reference only | |

**User's choice:** Skip entirely

---

| Option | Description | Selected |
|--------|-------------|----------|
| Patient level | Count unique IDs — clinically meaningful | |
| Row level | Count rows — simpler but misleading | |
| Both | Track n_patients and n_rows | |

**User's choice:** Patient level

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, include % | step_name, n_before, n_after, n_excluded, pct_excluded | |
| Just counts | step_name, n_before, n_after only | |
| You decide | Claude picks | |

**User's choice:** Yes, include %

---

| Option | Description | Selected |
|--------|-------------|----------|
| Sourced by config | 00_config.R sources all utils_*.R files | |
| Sourced individually | Each script sources utils it needs | |
| You decide | Claude picks | |

**User's choice:** Sourced by config

---

| Option | Description | Selected |
|--------|-------------|----------|
| Utility function | parse_pcornet_date() in utils | |
| Inline in loader | Date parsing in 01_load_pcornet.R | |
| You decide | Claude picks | |

**User's choice:** Utility function

---

| Option | Description | Selected |
|--------|-------------|----------|
| Simple message() calls | Standard R message() with glue | |
| Log utility with timestamps | log_msg() with timestamps and severity | |
| You decide | Claude picks | |

**User's choice:** Simple message() calls

---

## Project Scaffolding

| Option | Description | Selected |
|--------|-------------|----------|
| Numbered scripts | R/00_config.R, R/01_load_pcornet.R, etc. | |
| Different structure | Alternative layout | |
| You decide | Claude picks | |

**User's choice:** Numbered scripts

---

| Option | Description | Selected |
|--------|-------------|----------|
| main.R orchestrator | Sources all scripts in order | |
| Manual sourcing | Run scripts manually in RStudio | |
| Both | main.R + standalone scripts | |

**User's choice:** Manual sourcing in RStudio

---

| Option | Description | Selected |
|--------|-------------|----------|
| Set up renv now | Initialize renv from start | |
| Defer to later | Install globally, renv later | |
| You decide | Claude picks | |

**User's choice:** Set up renv now

---

| Option | Description | Selected |
|--------|-------------|----------|
| Full structure now | Create output/figures/, output/tables/, output/cohort/ upfront | |
| Create as needed | Each phase creates its own directories | |

**User's choice:** Full structure now

---

## Claude's Discretion

- Exact col_types specifications per table
- Internal structure of parse_pcornet_date()
- renv initialization details
- .Rprofile and .gitignore contents

## Deferred Ideas

None — discussion stayed within phase scope
