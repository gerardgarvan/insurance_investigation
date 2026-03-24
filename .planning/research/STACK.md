# Technology Stack

**Project:** PCORnet CDM Payer Analysis Pipeline (R)
**Researched:** 2026-03-24
**Environment:** RStudio on UF HiPerGator (HPC SLURM scheduler)

## Recommended Stack

### Core Framework

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| R | 4.4.2+ | Base language | HiPerGator standard; load via `module load R/4.4.2` |
| tidyverse | 2.0.0+ | Data manipulation ecosystem | Industry standard for readable R pipelines; includes dplyr, ggplot2, stringr, lubridate |
| dplyr | 1.2.0+ | Data transformation | Mature, optimized for readability over raw speed; case_when() for payer harmonization |
| renv | 1.1.4+ | Package management | Reproducibility on HPC; creates project-local libraries with global cache symlinks |

**Rationale:** tidyverse prioritizes readability over maximum performance, which aligns with the requirement for "human-readable named predicates." For a 22-table PCORnet extract on HPC, readability is more valuable than microsecond optimizations.

**Confidence:** HIGH (official CRAN releases, HiPerGator documentation)

### Data Loading

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| vroom | 1.7.0+ | Primary CSV loader | 1.23 GB/sec via lazy loading (Altrep); multi-threaded; matches readr syntax |
| readr | 2.2.0+ | Fallback CSV loader | Vroom dependency; solid backup if lazy loading causes issues |
| data.table | 1.16.2+ | NOT recommended for this project | 10-50x faster than vroom, but opaque syntax conflicts with "named predicate" requirement |

**Rationale:** Vroom provides the best balance of speed (10-100x faster than base R) and tidyverse integration. It reads CSVs lazily, so you only pay for columns actually used—ideal for 22-table PCORnet extracts where not all columns are needed. Falls back to readr if issues arise.

**Alternative considered:** data.table::fread() is the fastest (100ms vs 10sec for large files), but its concise syntax (`DT[i, j, by]`) conflicts with the project's requirement for readable predicate functions. Save data.table for performance-critical production pipelines.

**Confidence:** HIGH (official vroom benchmarks, tidyverse integration)

### Data Manipulation & Transformation

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | String operations | ICD code normalization (dotted vs undotted formats), payer category mapping |
| lubridate | 1.9.3+ | Date/time operations | Parse enrollment dates, diagnosis dates, calculate time-to-treatment |
| janitor | 2.2.1+ | Data cleaning | clean_names() for PCORnet column consistency, tabyl() for quick crosstabs |
| glue | 1.8.0 | String formatting | Readable logging messages with embedded expressions |
| here | 1.0.2 | Path management | Project-relative paths that work in RStudio & SLURM jobs: `here("data", "ENROLLMENT.csv")` |

**Rationale:**
- **stringr:** Consistent API for all string operations. PCORnet ICD codes come in multiple formats (C81.00, C8100); stringr's `str_remove()`, `str_detect()` handle normalization cleanly.
- **lubridate:** Date arithmetic is core to cohort selection (enrollment windows, diagnosis timing). lubridate makes `ymd()`, `interval()`, `%within%` readable.
- **janitor:** The clean_names() function handles PCORnet's mixed-case column names; tabyl() replaces table() for cleaner frequency outputs.
- **glue:** Logging attrition steps needs readable messages. `glue("Removed {n_removed} patients without HL diagnosis")` beats paste0.
- **here:** HiPerGator SLURM jobs change working directory; here() anchors paths to project root automatically.

**Confidence:** HIGH (all are mature, stable CRAN packages)

### Cohort Building & Attrition Logging

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tidylog | 1.1.0 | Automatic pipeline logging | Wraps dplyr/tidyr to print N rows added/removed at each step |
| pointblank | 0.12.3+ | Data validation (optional) | Deep validation if data quality issues emerge; overkill for v1 |

**Rationale:**
- **tidylog:** Solves the attrition logging requirement automatically. Load it (`library(tidylog)`) and every dplyr operation logs before/after counts: `filter: removed 1,234 rows (12%), 9,876 remaining`. No manual logging code needed. Perfect for "logged attrition at every step."
- **pointblank:** Not needed for v1 (out of scope: "replicating Python pipeline's data cleaning"). Reserve for v2 if systematic validation becomes necessary.

**Alternative considered:** Manual logging with custom wrappers. Rejected because tidylog is zero-effort and produces CONSORT-ready attrition counts automatically.

**Confidence:** MEDIUM (tidylog is maintained but not as widely used as dplyr; may have edge cases with complex joins)

### Visualization

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| ggplot2 | 4.0.1+ | Base plotting | Grammar of graphics; publication-quality (though v1 only needs "exploratory quality") |
| ggalluvial | 0.12.5 | Sankey/alluvial diagrams | Purpose-built for enrollment → diagnosis → treatment flows; integrates with ggplot2 |
| scales | 1.3.0+ | Axis formatting | Format percentages, suppress small cells (HIPAA compliance via label functions) |
| consort | 0.3.0+ (optional) | Waterfall/CONSORT diagrams | Auto-generates CONSORT flow diagrams; alternative to manual ggplot waterfall |

**Rationale:**
- **ggplot2 4.0.1:** Major release (Sept 2025) with S7 rewrite. Stable, widely documented.
- **ggalluvial:** The standard for alluvial plots in R. `geom_alluvium()` + `geom_stratum()` creates payer-stratified flows. Alternatives (ggsankey, ggsankeyfier) lack maturity or have sparse documentation.
- **scales:** Needed for HIPAA suppression. `label_number(big.mark = ",")` for counts, custom label functions to replace 1-10 with "<11".
- **consort:** Creates CONSORT 2025-compliant attrition diagrams automatically from filter logs. May be easier than building waterfalls manually with ggplot. Evaluate during implementation.

**Alternative for waterfall:** Build manually with `geom_col()` + `geom_text()` in ggplot2 if consort package doesn't fit the use case (it's designed for RCTs, may not map to observational cohorts).

**Confidence:** HIGH (ggplot2, scales, ggalluvial are core tidyverse ecosystem; consort is MEDIUM confidence—check fit during Phase 1)

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| forcats | 1.0.0+ | Factor management | Reorder payer categories for visualizations (largest first, etc.) |
| purrr | 1.0.2+ | Functional programming | map() for applying functions across multiple tables, if needed |
| tibble | 3.2.1+ | Modern data frames | Included in tidyverse; better printing than base data.frame |

**Rationale:** All included in tidyverse meta-package. forcats for payer category ordering in plots, purrr if batch operations across 22 tables become necessary (unlikely for v1).

**Confidence:** HIGH (tidyverse core)

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Data loading | vroom | data.table::fread | 10-50x faster but opaque syntax (`DT[i, j, by]`) conflicts with named predicate requirement |
| Data loading | vroom | arrow::read_parquet | Parquet is 5-10x smaller and faster than CSV, but CSVs are the input format from PCORnet |
| Pipeline logging | tidylog | Manual wrappers | Reinventing the wheel; tidylog does this automatically |
| Alluvial plots | ggalluvial | ggsankey, ggsankeyfier | Less mature; ggalluvial is the established standard (PMC publication, 0.12.5 stable release) |
| CONSORT diagrams | consort | flowchart, ggconsort | consort auto-generates from data; others require manual node definition |
| Package management | renv | Docker/Singularity | renv is sufficient for R-only project; containers add complexity for HPC module system |
| Validation | (deferred to v2) | pointblank, validate, assertthat | Out of scope for v1; Python pipeline handles cleaning |

**data.table deep dive:** While data.table is objectively faster (especially for joins and group operations), the project explicitly requires "human-readable named predicates" and code that "reads like a clinical protocol." Data.table's concise syntax is powerful but not self-documenting:

```r
# data.table approach (fast but opaque)
DT[has_hl == TRUE & !is.na(enroll_date), .N, by = payer_cat]

# dplyr approach (slower but readable)
patients %>%
  filter(has_hl_diagnosis) %>%
  filter(!is.na(enrollment_date)) %>%
  count(payer_category)
```

For a research pipeline where maintainability and transparency matter more than milliseconds, dplyr wins. Reserve data.table for production ETL where performance is critical.

**arrow::read_parquet consideration:** Converting 22 PCORnet CSV tables to Parquet would yield 5-6x compression and 7-10x faster queries. However:
- Input format is CSV (given)
- One-time conversion overhead not justified for exploratory v1
- Consider for v2 if query performance becomes a bottleneck

**Confidence on alternatives:** HIGH (data.table, arrow are well-benchmarked; decision rationale is clear)

## Installation

### On HiPerGator (HPC Environment)

```bash
# Load R module (check available versions with `module spider R`)
module load R/4.4.2

# Start R interactively
R

# In R console:
# Install renv for package management
install.packages("renv")

# Initialize renv for this project (run once)
renv::init()

# Install core packages
install.packages(c(
  "tidyverse",    # Meta-package: dplyr, ggplot2, stringr, lubridate, readr, etc.
  "vroom",        # Fast CSV loading
  "janitor",      # Data cleaning
  "glue",         # String formatting
  "here",         # Path management
  "tidylog",      # Automatic logging
  "ggalluvial",   # Alluvial/Sankey plots
  "scales",       # Formatting for plots
  "forcats",      # Factor management (included in tidyverse but explicit for clarity)
  "consort"       # CONSORT diagrams (optional, evaluate during Phase 1)
))

# Snapshot the environment
renv::snapshot()

# Exit R
quit(save = "no")
```

**Notes:**
- renv creates a project-local library with symlinks to HiPerGator's global cache (efficient disk usage)
- renv.lock file pins exact versions for reproducibility
- Other users run `renv::restore()` to recreate the exact environment
- The `module load R/4.4.2` command must be in every SLURM script

### On Local RStudio (Optional Development)

```r
# Install tidyverse and supporting packages
install.packages(c(
  "tidyverse", "vroom", "janitor", "glue", "here",
  "tidylog", "ggalluvial", "scales", "consort", "renv"
))

# Clone project and restore environment
renv::restore()
```

## Anti-Patterns to Avoid

### 1. Don't Use data.table Syntax in This Project

**Why:** Conflicts with "human-readable named predicates" requirement. Example:

```r
# AVOID: data.table (fast but opaque)
DT[payer %in% c("Medicare", "Medicaid"), `:=`(dual_eligible = TRUE)]

# PREFER: dplyr (readable)
patients <- patients %>%
  mutate(dual_eligible = payer_category %in% c("Medicare", "Medicaid"))
```

**Exception:** If performance becomes a critical bottleneck (>10 minute runtimes), consider data.table for specific slow operations while keeping the overall pipeline in dplyr.

### 2. Don't Use setwd() for Paths

**Why:** Breaks when running SLURM jobs or collaborating. Use here() instead:

```r
# AVOID: Absolute or relative paths
source("../R/01_load_data.R")
df <- read_csv("../../data/ENROLLMENT.csv")

# PREFER: here() for project-relative paths
source(here("R", "01_load_data.R"))
df <- vroom(here("data", "ENROLLMENT.csv"))
```

### 3. Don't Mix Base R and Tidyverse Pipes

**Why:** Inconsistent syntax confuses readers. Pick one style:

```r
# AVOID: Mixing base R subset with pipes
patients %>%
  filter(has_hl_diagnosis) %>%
  .[.$age >= 18, ]    # Base R subset syntax

# PREFER: Consistent dplyr
patients %>%
  filter(has_hl_diagnosis) %>%
  filter(age >= 18)
```

### 4. Don't Install Packages in SLURM Scripts

**Why:** Creates race conditions when multiple jobs run simultaneously. Use renv::restore() in an interactive session, then submit jobs:

```bash
# AVOID in SLURM script:
Rscript -e "install.packages('dplyr')"

# PREFER: Install once interactively, then snapshot
# Interactive session:
R
renv::restore()
quit()

# SLURM script just loads the module and runs code
module load R/4.4.2
Rscript my_analysis.R
```

### 5. Don't Use read.csv() or read_csv() Without Type Specification for PCORnet

**Why:** PCORnet has many date columns, ID columns (PATID, ENCOUNTERID) that may parse incorrectly. Specify column types:

```r
# AVOID: Letting vroom guess all types
enrollment <- vroom("ENROLLMENT.csv")

# PREFER: Specify critical column types
enrollment <- vroom(
  "ENROLLMENT.csv",
  col_types = cols(
    PATID = col_character(),
    ENR_START_DATE = col_date(format = "%Y-%m-%d"),
    ENR_END_DATE = col_date(format = "%Y-%m-%d"),
    CHART = col_character()
  )
)
```

## HiPerGator-Specific Considerations

### Module Loading Order

```bash
# In SLURM script, load R before running
module load R/4.4.2
Rscript pipeline.R
```

### Memory and Threading

- **vroom** is multi-threaded by default. On HiPerGator, request appropriate CPU cores:
  ```bash
  #SBATCH --cpus-per-task=4
  #SBATCH --mem=16G
  ```
- **ggplot2** and dplyr are single-threaded. More cores won't help unless processing multiple files in parallel.

### renv Cache Location

- renv uses a global cache at `~/.cache/R/renv` by default
- On HiPerGator, this is in your home directory (not a problem unless cache grows >100GB)
- Check cache size: `renv::paths$cache()`

### Package Installation Tips

- Some packages (e.g., stringi, curl) have system dependencies
- HiPerGator has most preinstalled, but if installation fails, check for missing libraries
- Contact HiPerGator support if system library issues arise

## Version Pinning Strategy

**For reproducibility, pin these in renv.lock:**

| Package | Min Version | Why |
|---------|-------------|-----|
| tidyverse | 2.0.0 | Major release (July 2025), includes dplyr 1.2.0, ggplot2 4.0.0 |
| vroom | 1.7.0 | Latest performance optimizations |
| ggalluvial | 0.12.5 | Stable API |
| tidylog | 1.1.0 | Latest (May 2024); updates infrequent but stable |
| janitor | 2.2.1 | Latest (July 2025) |
| glue | 1.8.0 | Latest (July 2025) |

**Don't pin minor versions for:**
- scales, stringr, lubridate, forcats (tidyverse dependencies; updated together)
- purrr, tibble (included in tidyverse)

**Rationale:** Major versions (2.0, 4.0) indicate API changes; minor/patch versions (1.7.0 → 1.7.1) are usually safe to upgrade. Pin majors, float minors unless a specific bug fix is needed.

## Sources

**Tool Hierarchy:**
- Context7: N/A (R ecosystem not available in Context7 as of 2026-03-24)
- Official CRAN: Primary source for version numbers and package documentation
- Official Package Documentation: tidyverse.org, rstudio.github.io
- Benchmarks: vroom benchmarks, data.table vs tidyverse comparisons
- HiPerGator Documentation: Weecology Wiki, UF HiPerGator guides

**Key References:**
- [CRAN tidyverse](https://cran.r-project.org/package=tidyverse)
- [dplyr changelog](https://dplyr.tidyverse.org/news/index.html) - version 1.2.0 released Feb 2026
- [ggplot2 4.0.0 announcement](https://tidyverse.org/blog/2025/09/ggplot2-4-0-0/)
- [vroom documentation](https://vroom.tidyverse.org/) - version 1.7.0
- [ggalluvial documentation](https://corybrunson.github.io/ggalluvial/) - version 0.12.5
- [tidylog CRAN](https://cran.r-project.org/web/packages/tidylog/index.html) - version 1.1.0
- [janitor package](https://cran.r-project.org/web/packages/janitor/janitor.pdf) - version 2.2.1, July 2025
- [glue package](https://glue.tidyverse.org/) - version 1.8.0, July 2025
- [here package](https://here.r-lib.org/) - version 1.0.2, Sept 2025
- [pointblank documentation](https://rstudio.github.io/pointblank/) - version 0.12.3, Nov 2025
- [consort package](https://cran.r-project.org/web/packages/consort/vignettes/consort_diagram.html)
- [HiPerGator R Guide](https://wiki.weecology.org/docs/computers-and-programming/hipergator-reference/)
- [vroom vs fread vs readr benchmarks](https://vroom.tidyverse.org/articles/benchmarks.html)
- [data.table vs tidyverse comparison](https://wetlandscapes.com/blog/a-comparison-of-r-dialects/)
- [renv for HPC reproducibility](https://bioinformatics.ccr.cancer.gov/docs/reproducible-r-on-biowulf/L3_PackageManagement/)

**Confidence Levels:**
- Core stack (tidyverse, vroom, ggplot2, dplyr): **HIGH** (official CRAN releases, extensive benchmarks)
- Visualization (ggalluvial, scales): **HIGH** (mature packages, published methodology)
- Logging (tidylog): **MEDIUM** (less widespread adoption, but stable 1.1.0 release)
- CONSORT diagrams (consort): **MEDIUM** (designed for RCTs, may need adaptation for observational cohorts)
- HiPerGator specifics (module loading, renv): **HIGH** (official UF documentation)

**Search Verification:**
- All CRAN versions verified against official CRAN pages (accessed 2026-03-24)
- Benchmarks verified from vroom official documentation
- HiPerGator guidance from Weecology Wiki (UF-affiliated resource)
- PCORnet CDM v7.0 specification available (Jan 2025) but no R-specific tooling documented
