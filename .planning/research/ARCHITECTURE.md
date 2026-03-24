# Architecture Research

**Domain:** PCORnet CDM R Analysis Pipeline
**Researched:** 2026-03-24
**Confidence:** MEDIUM

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                   ANALYSIS ORCHESTRATION                     │
│                     (main script / runner)                   │
├─────────────────────────────────────────────────────────────┤
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │  Config    │  │  Loader    │  │ Harmonizer │            │
│  │  (params,  │  │  (CSVs →   │  │  (payer    │            │
│  │   paths)   │  │  tables)   │  │  mapping)  │            │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘            │
│        │                │                │                   │
├────────┴────────────────┴────────────────┴───────────────────┤
│                   COHORT CONSTRUCTION                        │
│                  (named predicate filters)                   │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │            Attrition Logger                         │    │
│  │     (captures N before/after each filter)           │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│                      VISUALIZATION                           │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │ Waterfall  │  │   Sankey   │  │  Tables    │            │
│  │ (attrition)│  │  (flow)    │  │ (summary)  │            │
│  └────────────┘  └────────────┘  └────────────┘            │
├─────────────────────────────────────────────────────────────┤
│                      COMPLIANCE                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │        Small Cell Suppression (<11 counts)          │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

PCORnet CDM analysis pipelines in R follow a **layered pipeline architecture** where data flows sequentially through stages, with each layer transforming or filtering the dataset. The architecture prioritizes **transparency** (every operation is logged), **reproducibility** (same input → same output), and **regulatory compliance** (HIPAA small cell suppression).

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **Config** | Define file paths, parameters, constants | Single `00_config.R` script with named lists/vectors |
| **Loader** | Read raw CSV files with correct data types | `readr::read_csv()` with col_types specification per PCORnet table |
| **Harmonizer** | Map payer values to standardized categories | Custom functions using `dplyr::case_when()` or lookup tables |
| **Cohort Constructor** | Apply sequential filters with named predicates | `has_*()`, `with_*()`, `exclude_*()` functions returning logical vectors |
| **Attrition Logger** | Track patient counts before/after filters | Data frame accumulating step name, N before, N after, N excluded |
| **Waterfall Visualizer** | Show cumulative cohort attrition | `ggplot2` with `geom_bar()` or `geom_col()` showing exclusions |
| **Sankey Visualizer** | Show patient flow through states | `ggalluvial::geom_alluvium()` + `geom_stratum()` |
| **Suppression Layer** | Mask counts 1-10 in all outputs | Function wrapping all output-generating code |

## Recommended Project Structure

```
insurance_investigation/
├── R/
│   ├── 00_config.R                # Paths, ICD code lists, payer mappings
│   ├── 01_load_pcornet.R          # Load 22 PCORnet CDM CSV tables
│   ├── 02_harmonize_payer.R       # 9-category payer mapping + dual-eligible
│   ├── 03_cohort_predicates.R     # has_*, with_*, exclude_* filter functions
│   ├── 04_build_cohort.R          # Apply filter chain with attrition logging
│   ├── 05_visualize_waterfall.R   # Attrition waterfall chart
│   ├── 06_visualize_sankey.R      # Patient flow Sankey diagram
│   ├── utils_attrition.R          # Attrition logging helpers
│   ├── utils_suppression.R        # HIPAA small cell suppression (<11)
│   └── utils_validation.R         # Data quality checks (optional)
├── data/
│   └── raw/                       # Symlinks or paths to HiPerGator CSVs
│       ├── ENROLLMENT.csv
│       ├── DIAGNOSIS.csv
│       ├── PROCEDURES.csv
│       └── ... (22 tables total)
├── output/
│   ├── figures/
│   │   ├── waterfall_attrition.png
│   │   └── sankey_patient_flow.png
│   ├── tables/
│   │   └── attrition_log.csv
│   └── cohort/
│       └── final_cohort.csv       # Filtered patient IDs (suppression applied)
├── docs/
│   └── PAYER_MAPPING.md           # Documentation of 9 payer categories
├── .Rprofile                       # RStudio project settings
├── renv.lock                       # Package version lockfile (renv)
└── main.R                          # Orchestrator script (sources R/* in order)
```

### Structure Rationale

- **Numbered `R/` scripts:** Scripts run in dependency order (`00_` before `01_`, etc.). Numbering makes execution sequence explicit.
- **Utility functions separate:** `utils_*.R` files contain reusable functions sourced by multiple analysis scripts. Not numbered because they're libraries, not steps.
- **Config first:** `00_config.R` defines all paths, constants, ICD codes, and payer mappings in one place. All other scripts load this first.
- **Modular stages:** Each script has one responsibility (load, harmonize, filter, visualize). Makes debugging easier and enables skipping/rerunning individual stages.
- **Output isolation:** All generated artifacts (figures, tables, cohorts) go to `output/`, never mixed with source code or raw data.
- **Data symlinks:** Raw data stays on HiPerGator filesystem; `data/raw/` contains symlinks to avoid duplication.

## Architectural Patterns

### Pattern 1: Sequential Numbered Scripts (Pipeline Runner)

**What:** A set of numbered R scripts (00, 01, 02...) where each script performs one stage of analysis and passes data to the next via saved RDS files or global environment objects.

**When to use:** For linear pipelines where each stage depends on the previous, and intermediate inspection is valuable (e.g., QA after each step).

**Trade-offs:**
- **Pros:** Easy to understand, simple to debug (run up to step N), flexible (can skip steps manually)
- **Cons:** Doesn't automatically detect when to re-run steps, relies on manual orchestration, harder to parallelize

**Example:**
```r
# main.R — orchestrator script
source("R/00_config.R")
source("R/01_load_pcornet.R")      # Creates 'pcornet_raw' list
source("R/02_harmonize_payer.R")   # Creates 'pcornet_harmonized' list
source("R/03_cohort_predicates.R") # Defines filter functions
source("R/04_build_cohort.R")      # Creates 'cohort' + 'attrition_log'
source("R/05_visualize_waterfall.R")
source("R/06_visualize_sankey.R")

# Or run interactively in RStudio:
# File > Source each script in order
```

### Pattern 2: Named Predicate Functions (Filter Chain)

**What:** Filtering logic encapsulated in functions with descriptive names (`has_diagnosis()`, `with_enrollment()`, `exclude_missing_payer()`) that return logical vectors. Compose filters by passing data through a chain with logging at each step.

**When to use:** When cohort construction logic needs to be readable, auditable, and reusable. Essential for clinical research where inclusion/exclusion criteria must be transparent.

**Trade-offs:**
- **Pros:** Self-documenting (function names describe criteria), testable (each predicate can be unit tested), composable (mix and match filters)
- **Cons:** Requires upfront function design, more verbose than inline filtering

**Example:**
```r
# R/03_cohort_predicates.R
has_hodgkin_diagnosis <- function(diagnosis_df) {
  # ICD-10: C81.* (77 codes), ICD-9: 201.* (72 codes)
  hl_icd10 <- paste0("C81.", c("00", "01", ..., "9A"))
  hl_icd9  <- paste0("201.", c("00", "01", ..., "98"))

  diagnosis_df %>%
    filter(DX_TYPE %in% c("09", "10")) %>%
    mutate(DX_CLEAN = str_remove(DX, "\\.")) %>%
    filter(DX_CLEAN %in% c(hl_icd10, hl_icd9)) %>%
    pull(PATID) %>%
    unique()
}

with_enrollment_period <- function(enrollment_df, min_days = 30) {
  enrollment_df %>%
    mutate(enrollment_days = as.numeric(ENR_END_DATE - ENR_START_DATE)) %>%
    filter(enrollment_days >= min_days) %>%
    pull(PATID) %>%
    unique()
}

exclude_missing_payer <- function(enrollment_df) {
  enrollment_df %>%
    filter(!is.na(PAYER_HARMONIZED) & PAYER_HARMONIZED != "Unknown") %>%
    pull(PATID) %>%
    unique()
}

# R/04_build_cohort.R — apply filters with logging
attrition_log <- data.frame()
cohort <- pcornet_raw$ENROLLMENT

attrition_log <- log_attrition(attrition_log, "Initial cohort", nrow(cohort))

hl_patients <- has_hodgkin_diagnosis(pcornet_raw$DIAGNOSIS)
cohort <- cohort %>% filter(PATID %in% hl_patients)
attrition_log <- log_attrition(attrition_log, "Has Hodgkin diagnosis", nrow(cohort))

enrolled_patients <- with_enrollment_period(cohort, min_days = 30)
cohort <- cohort %>% filter(PATID %in% enrolled_patients)
attrition_log <- log_attrition(attrition_log, "Enrollment ≥30 days", nrow(cohort))

# ... continue filter chain
```

### Pattern 3: Attrition Logging Wrapper (Cohort Tracking)

**What:** A helper function that wraps every filtering operation, capturing the cohort size before and after the filter, along with a description of the criterion applied.

**When to use:** Mandatory for clinical cohort studies where attrition must be reported (e.g., CONSORT diagrams, waterfall charts). Enables automatic visualization generation.

**Trade-offs:**
- **Pros:** Automatic audit trail, enables reproducible attrition reporting, catches unexpected exclusions
- **Cons:** Adds boilerplate to filter code, requires discipline to use consistently

**Example:**
```r
# R/utils_attrition.R
init_attrition_log <- function() {
  data.frame(
    step = character(),
    n_before = integer(),
    n_after = integer(),
    n_excluded = integer(),
    pct_excluded = numeric(),
    stringsAsFactors = FALSE
  )
}

log_attrition <- function(log_df, step_name, n_after, n_before = NULL) {
  if (is.null(n_before)) {
    # Infer from previous step
    n_before <- if (nrow(log_df) > 0) tail(log_df$n_after, 1) else n_after
  }

  n_excluded <- n_before - n_after
  pct_excluded <- if (n_before > 0) round(100 * n_excluded / n_before, 1) else 0

  rbind(log_df, data.frame(
    step = step_name,
    n_before = n_before,
    n_after = n_after,
    n_excluded = n_excluded,
    pct_excluded = pct_excluded
  ))
}

# Usage:
attrition <- init_attrition_log()
cohort <- initial_data
attrition <- log_attrition(attrition, "Initial enrollment", nrow(cohort))

cohort <- cohort %>% filter(AGE >= 18)
attrition <- log_attrition(attrition, "Age ≥18", nrow(cohort))
```

### Pattern 4: Small Cell Suppression Layer (Compliance)

**What:** A wrapper function applied to all output-generating code that replaces counts between 1 and 10 with a suppression symbol (e.g., "<11" or asterisk) to comply with HIPAA and CMS policies.

**When to use:** Required for all outputs (tables, figures, exported datasets) derived from healthcare data that could potentially re-identify individuals.

**Trade-offs:**
- **Pros:** Ensures regulatory compliance, prevents accidental disclosure
- **Cons:** May reduce utility of exploratory analysis, requires careful implementation

**Example:**
```r
# R/utils_suppression.R
suppress_small_cells <- function(x, threshold = 11, replacement = "<11") {
  ifelse(x > 0 & x < threshold, replacement, as.character(x))
}

apply_suppression_to_table <- function(df, count_cols) {
  df %>%
    mutate(across(all_of(count_cols), ~suppress_small_cells(., threshold = 11)))
}

# Usage in summary tables:
summary_table <- cohort %>%
  group_by(PAYER_HARMONIZED, SITE) %>%
  summarise(n_patients = n(), .groups = "drop") %>%
  apply_suppression_to_table(count_cols = "n_patients")

# Usage in figures (requires pre-aggregation):
plot_data <- cohort %>%
  count(PAYER_HARMONIZED) %>%
  mutate(n_suppressed = as.numeric(suppress_small_cells(n, threshold = 11, replacement = "10.5")))
```

## Data Flow

### End-to-End Analysis Flow

```
[HiPerGator CSVs]
    ↓
[01_load] → 22 PCORnet CDM tables loaded into list 'pcornet_raw'
    ↓
[02_harmonize] → Add 'PAYER_HARMONIZED' column (9 categories)
    ↓
[03_predicates] → Define has_*(), with_*(), exclude_*() functions
    ↓
[04_build_cohort] → Apply filters sequentially
    ↓                  ↓
    ↓            [attrition_log] → data frame tracking N at each step
    ↓
[05_waterfall] → ggplot2 bar chart from attrition_log
    ↓
[06_sankey] → ggalluvial flow diagram from cohort + payer strata
    ↓
[output/] → PNG figures, CSV tables (all with suppression applied)
```

### Key Data Flows

1. **Loading Flow:** `00_config.R` defines `PCORNET_PATHS` (named list of CSV paths) → `01_load_pcornet.R` iterates through paths using `readr::read_csv()` with table-specific `col_types` → stores result in named list `pcornet_raw` (e.g., `pcornet_raw$ENROLLMENT`, `pcornet_raw$DIAGNOSIS`).

2. **Harmonization Flow:** `02_harmonize_payer.R` reads payer mapping rules from `00_config.R` → applies `case_when()` logic to `ENROLLMENT$RAW_PAY_TYPE` → adds `PAYER_HARMONIZED` column with 9 categories → detects dual-eligible (Medicare + Medicaid overlap) → stores enhanced list as `pcornet_harmonized`.

3. **Cohort Construction Flow:** `04_build_cohort.R` starts with full `ENROLLMENT` table → applies named predicates one at a time → each filter returns vector of `PATID` values meeting criterion → cohort restricted to matching `PATID` using `filter(PATID %in% qualifying_ids)` → after each filter, `log_attrition()` captures N before/after → final `cohort` data frame contains only patients meeting all criteria.

4. **Attrition Logging Flow:** `utils_attrition.R` provides `init_attrition_log()` and `log_attrition()` → after each filter in `04_build_cohort.R`, `log_attrition()` called with step name and current cohort size → function calculates N excluded and % excluded → appends row to accumulating `attrition_log` data frame → final log saved to `output/tables/attrition_log.csv` and passed to `05_visualize_waterfall.R`.

5. **Visualization Flow (Waterfall):** `05_visualize_waterfall.R` reads `attrition_log` → creates `ggplot()` with `geom_col()` showing cumulative exclusions as stacked bars → applies theme and labels → saves to `output/figures/waterfall_attrition.png`.

6. **Visualization Flow (Sankey):** `06_visualize_sankey.R` reads final `cohort` → joins with `DIAGNOSIS` (for HL diagnosis date) and `PROCEDURES`/`PRESCRIBING` (for treatment type) → creates long-format data frame with `axis1` (enrollment period), `axis2` (diagnosis date), `axis3` (treatment type), stratified by `PAYER_HARMONIZED` → uses `ggalluvial::ggplot(aes(axis1, axis2, axis3))` + `geom_alluvium()` + `geom_stratum()` → saves to `output/figures/sankey_patient_flow.png`.

7. **Suppression Flow:** Before any output (table or figure) is saved, data is aggregated and `suppress_small_cells()` applied to count columns → ensures no cell with 1-10 patients appears in output → replaces with "<11" string or rounds to boundary value (10.5 for plotting).

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1k-100k patients (typical PCORnet single-site) | Current architecture handles well in-memory with tidyverse. Load all tables upfront. |
| 100k-1M patients (multi-site PCORnet) | Consider `arrow` package for larger-than-RAM CSV reading, or convert CSVs to Parquet format. Filter early (e.g., restrict to HL patients in `01_load` before loading all tables). |
| 1M+ patients (national PCORnet network) | Distributed query model (PCORnet standard approach): each site runs pipeline locally, aggregates counts, sends suppressed results to coordinating center. Never centralize raw data. Use SQL backend (DuckDB, SQLite) instead of in-memory R. |

### Scaling Priorities

1. **First bottleneck:** Loading all 22 PCORnet CSV tables into memory. **Fix:** Use `arrow::read_csv_arrow()` for lazy evaluation, or load only necessary columns (`col_select` in `read_csv()`). Apply diagnosis filter early to reduce patient set before loading other tables.

2. **Second bottleneck:** Large joins between tables (e.g., `ENROLLMENT` ⋈ `DIAGNOSIS` ⋈ `PROCEDURES`). **Fix:** Use `data.table` backend (`dtplyr`) for faster joins, or use SQL via `DBI` + `duckdb` for out-of-memory joins. Pre-filter to cohort before joining.

**Note for this project:** OneFlorida+ HL cohort is small (~thousands of patients), so in-memory tidyverse is sufficient. No optimization needed for v1.

## Anti-Patterns

### Anti-Pattern 1: Inline Anonymous Filtering

**What people do:**
```r
cohort <- cohort %>%
  filter(AGE >= 18 & AGE <= 65) %>%
  filter(!is.na(PAYER_TYPE)) %>%
  filter(DIAGNOSIS_DATE > as.Date("2010-01-01"))
```

**Why it's wrong:** Filters are opaque (what clinical criterion does "AGE >= 18" represent?). No attrition tracking. Difficult to test or reuse logic. Chain of operations doesn't describe the cohort selection protocol.

**Do this instead:** Extract filters into named predicate functions with clear clinical semantics. Wrap each filter in attrition logging.
```r
has_adult_age <- function(df) df %>% filter(AGE >= 18 & AGE <= 65) %>% pull(PATID)
exclude_missing_payer <- function(df) df %>% filter(!is.na(PAYER_TYPE)) %>% pull(PATID)
after_study_start <- function(df) df %>% filter(DIAGNOSIS_DATE > as.Date("2010-01-01")) %>% pull(PATID)

cohort <- apply_filter(cohort, has_adult_age, "Adult age (18-65)", attrition_log)
cohort <- apply_filter(cohort, exclude_missing_payer, "Known payer type", attrition_log)
cohort <- apply_filter(cohort, after_study_start, "After study start date", attrition_log)
```

### Anti-Pattern 2: Hardcoded Paths and Constants

**What people do:**
```r
# In R/02_harmonize_payer.R
enrollment <- read_csv("C:/Users/Owner/Data/ENROLLMENT.csv")

# In R/05_visualize_waterfall.R
ggsave("C:/Users/Owner/Documents/insurance_investigation/output/figures/waterfall.png")
```

**Why it's wrong:** Breaks when moved to different machine (e.g., local → HiPerGator). Impossible to reuse code for different datasets. Hard to maintain (path changes require editing multiple files).

**Do this instead:** Define all paths in `00_config.R` using relative paths or environment variables. Reference via config object.
```r
# R/00_config.R
CONFIG <- list(
  data_dir = Sys.getenv("PCORNET_DATA_DIR", default = "data/raw"),
  output_dir = "output",
  figures_dir = "output/figures"
)

PCORNET_PATHS <- list(
  ENROLLMENT = file.path(CONFIG$data_dir, "ENROLLMENT.csv"),
  DIAGNOSIS  = file.path(CONFIG$data_dir, "DIAGNOSIS.csv")
)

# R/02_harmonize_payer.R
source("R/00_config.R")
enrollment <- read_csv(PCORNET_PATHS$ENROLLMENT)

# R/05_visualize_waterfall.R
source("R/00_config.R")
ggsave(file.path(CONFIG$figures_dir, "waterfall.png"))
```

### Anti-Pattern 3: Forgetting Small Cell Suppression

**What people do:** Generate summary tables or figures directly from aggregated counts without checking for small cells.

```r
summary_table <- cohort %>%
  group_by(SITE, PAYER_HARMONIZED) %>%
  summarise(n = n()) %>%
  write_csv("output/tables/summary.csv")
```

**Why it's wrong:** Violates HIPAA safe harbor rules and CMS cell size policy (n=1-10 must be suppressed). Could lead to patient re-identification. Fails IRB compliance.

**Do this instead:** Always apply suppression function before saving outputs.
```r
source("R/utils_suppression.R")

summary_table <- cohort %>%
  group_by(SITE, PAYER_HARMONIZED) %>%
  summarise(n = n(), .groups = "drop") %>%
  apply_suppression_to_table(count_cols = "n") %>%
  write_csv("output/tables/summary.csv")
```

### Anti-Pattern 4: Silent Data Type Mismatches

**What people do:** Load CSVs without specifying column types, relying on `readr` auto-detection.

```r
enrollment <- read_csv("ENROLLMENT.csv")  # Dates might be read as characters
```

**Why it's wrong:** PCORnet CDM has specific data types (dates, integers, coded values). Auto-detection can fail (e.g., PATID with leading zeros truncated, dates parsed incorrectly). Silent failures lead to incorrect analyses.

**Do this instead:** Explicitly specify `col_types` for each PCORnet table based on CDM specification.
```r
# R/01_load_pcornet.R
ENROLLMENT_SPEC <- cols(
  PATID = col_character(),
  ENR_START_DATE = col_date(format = "%Y-%m-%d"),
  ENR_END_DATE = col_date(format = "%Y-%m-%d"),
  CHART = col_character(),
  ENR_BASIS = col_character(),
  RAW_BASIS = col_character(),
  RAW_CHART = col_character()
)

enrollment <- read_csv(PCORNET_PATHS$ENROLLMENT, col_types = ENROLLMENT_SPEC)
```

## Integration Points

### External Systems

| System | Integration Pattern | Notes |
|--------|---------------------|-------|
| HiPerGator Filesystem | Direct file paths via symlinks or environment variable | CSVs stored at `/blue/...` or `/orange/...` paths. Set `PCORNET_DATA_DIR` in `.Renviron`. |
| RStudio on HiPerGator | Interactive execution in RStudio Server | Load project via `.Rproj` file, run scripts interactively or via `main.R` orchestrator. |
| Python Pipeline | Manual comparison (not automated) | Python pipeline at `C:\cygwin64\home\Owner\Data loading and cleaing\` is separate. R pipeline does not consume Python output; both analyze same raw CSVs independently. |
| PCORnet CDM v7.0 | Schema validation (optional) | Use `utils_validation.R` to check table names, column names, value domains against CDM spec. Not required for v1. |

### Internal Component Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| **Config ↔ All Stages** | Global environment via `source()` | `00_config.R` defines `CONFIG`, `PCORNET_PATHS`, `ICD_CODES`, `PAYER_MAPPING`. All other scripts source this first. |
| **Loader ↔ Harmonizer** | Named list `pcornet_raw` in global env | `01_load` creates list of data frames. `02_harmonize` reads from list, adds columns, saves as `pcornet_harmonized`. |
| **Predicates ↔ Cohort Builder** | Function definitions | `03_predicates` defines functions but doesn't execute them. `04_build_cohort` sources predicates file and calls functions. |
| **Cohort Builder ↔ Visualizers** | Shared data frames (`cohort`, `attrition_log`) | `04_build_cohort` creates objects in global env. `05_` and `06_` scripts read these objects. Alternative: save to RDS and load. |
| **Utils ↔ All Stages** | Function libraries via `source()` | `utils_*.R` files are sourced by any script needing their functions. No execution on source, only definitions. |

### Recommended Communication Strategy

For v1, use **global environment with sequential sourcing** (simplest, works well for linear pipelines run interactively in RStudio). For v2 (if automation needed), consider **RDS intermediate files** (each stage saves output to `output/intermediate/stagename.rds`, next stage loads from file) or **`{targets}` pipeline** (automatic dependency tracking and caching).

## Build Order and Dependencies

### Suggested Phase Structure for Roadmap

**Phase 1: Foundation**
1. **Config** (`00_config.R`) — No dependencies. Defines all constants.
2. **Loader** (`01_load_pcornet.R`) — Depends on Config. Validates CSVs load correctly.
3. **Utilities** (`utils_*.R`) — Depends on Config. Attrition logging and suppression functions.

**Phase 2: Harmonization**
4. **Payer Harmonizer** (`02_harmonize_payer.R`) — Depends on Loader. Implements 9-category mapping and dual-eligible detection. Critical path item.

**Phase 3: Cohort Construction**
5. **Predicate Functions** (`03_cohort_predicates.R`) — Depends on Loader, Harmonizer. Defines `has_*`, `with_*`, `exclude_*` filters for HL diagnosis, enrollment, payer.
6. **Cohort Builder** (`04_build_cohort.R`) — Depends on Predicates, Utilities. Applies filter chain with attrition logging. Core deliverable.

**Phase 4: Visualization**
7. **Waterfall Chart** (`05_visualize_waterfall.R`) — Depends on Cohort Builder (needs `attrition_log`). Demonstrates attrition tracking works.
8. **Sankey Diagram** (`06_visualize_sankey.R`) — Depends on Cohort Builder (needs final `cohort`). Demonstrates payer stratification and patient flow.

**Parallel Work:** Utilities and Predicates can be developed in parallel with earlier phases if specs are clear.

**Integration Points:** After Phase 2, validate payer harmonization against Python pipeline output (manual spot-check). After Phase 3, validate cohort size matches expected range (hundreds to low thousands for HL).

**Critical Path:** Config → Loader → Harmonizer → Cohort Builder → Visualizations. Waterfall and Sankey can be done in parallel once `04_build_cohort.R` is complete.

## Sources

**PCORnet CDM Specification:**
- [PCORnet Common Data Model v7.0 Specification](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf) — Official schema and data types
- [PCORnet Common Data Model](https://pcornet.org/data/common-data-model/) — Overview and resources

**R Pipeline Architecture:**
- [Building Data Pipelines with {targets}](https://bookdown.org/pdr_higgins/rmrwr/building-data-pipelines-with-targets.html) — Modern R pipeline patterns
- [Structuring R Projects](https://www.r-bloggers.com/2018/08/structuring-r-projects/) — Directory organization
- [Building Data Pipelines using R](https://towardsdatascience.com/building-data-pipelines-using-r-d9883cbc15c6/) — Sequential pipeline design
- [R Script Naming Convention](https://r4ds.hadley.nz/workflow-scripts.html) — Numbered script patterns

**Cohort Analysis and Attrition:**
- [visR: CONSORT Flow Diagram](https://rdrr.io/cran/visR/f/vignettes/Consort_flow_diagram.Rmd) — Attrition table generation
- [dtrackr: CONSORT Example](https://cran.r-project.org/web/packages/dtrackr/vignettes/consort-example.html) — Automated attrition tracking
- [Using {flowchart} for CONSORT Diagrams](https://bookdown.org/pdr_higgins/rmrwr/using-the-flowchart-package-for-consort-diagrams-in-r.html) — Clinical trial flow diagrams

**Functional Programming and Predicates:**
- [Common Higher-Order Functions in R](https://stat.ethz.ch/R-manual/R-devel/library/base/html/funprog.html) — Filter, Map, Reduce
- [Building Reproducible Analytical Pipelines: Functional Programming](https://raps-with-r.dev/fprog.html) — Predicate functions and pipelines
- [Functional Programming and Unit Testing](https://b-rodrigues.github.io/fput/tidyverse.html) — Testing predicates

**Visualization:**
- [Alluvial Plots in ggplot2](https://cran.r-project.org/web/packages/ggalluvial/vignettes/ggalluvial.html) — Sankey/alluvial diagrams with ggalluvial
- [Alluvial and Sankey Plots for Clinical Data](https://www.lexjansen.com/pharmasug-cn/2024/DV/Pharmasug-China-2024-DV10003_Final_Paper.pdf) — Patient flow visualization
- [Waterfall Charts in Oncology Trials](https://pharmasug.org/proceedings/2012/DG/PharmaSUG-2012-DG13.pdf) — Clinical waterfall chart patterns

**Small Cell Suppression:**
- [CMS Cell Size Suppression Policy](https://resdac.org/articles/cms-cell-size-suppression-policy) — HIPAA compliance standard (n < 11)
- [Masking Small Cell Sizes for SEER-MHOS](https://healthcaredelivery.cancer.gov/seer-mhos/support/small_cell_sizes.html) — Suppression thresholds
- [Statistical Disclosure Control in Web-Based Data Query Systems](https://pmc.ncbi.nlm.nih.gov/articles/PMC5409873/) — Suppression strategies

**Data Validation:**
- [The validate Package](https://cran.r-project.org/web/packages/validate/vignettes/cookbook.html) — Data validation infrastructure for R
- [dataverifyr Package](https://davzim.github.io/dataverifyr/) — Lightweight data validation

---
*Architecture research for: PCORnet CDM R Analysis Pipeline (Payer Investigation)*
*Researched: 2026-03-24*
