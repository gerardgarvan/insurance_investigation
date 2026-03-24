<!-- GSD:project-start source:PROJECT.md -->
## Project

**PCORnet Payer Variable Investigation (R Pipeline)**

A standalone R-based exploration pipeline that loads raw PCORnet CDM CSV files for a Hodgkin Lymphoma cohort (OneFlorida+), builds a filtered cohort using human-readable named predicates, and produces attrition waterfall and Sankey/alluvial visualizations stratified by payer type. Runs on RStudio on HiPerGator.

**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

### Constraints

- **Runtime environment**: RStudio on UF HiPerGator — scripts must work in that environment
- **R packages**: tidyverse ecosystem (dplyr, ggplot2, stringr, lubridate), ggalluvial for Sankey, scales, janitor, glue
- **Data access**: Raw CSVs on HiPerGator filesystem — paths configured in `R/00_config.R`
- **HIPAA compliance**: All patient counts 1-10 must be suppressed in any output
- **Code style**: Filtering logic uses named predicate functions (`has_*`, `with_*`, `exclude_*`) — no opaque one-liners
- **Payer fidelity**: Must match the Python pipeline's 9-category payer mapping exactly, including dual-eligible detection
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core Framework
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| R | 4.4.2+ | Base language | HiPerGator standard; load via `module load R/4.4.2` |
| tidyverse | 2.0.0+ | Data manipulation ecosystem | Industry standard for readable R pipelines; includes dplyr, ggplot2, stringr, lubridate |
| dplyr | 1.2.0+ | Data transformation | Mature, optimized for readability over raw speed; case_when() for payer harmonization |
| renv | 1.1.4+ | Package management | Reproducibility on HPC; creates project-local libraries with global cache symlinks |
### Data Loading
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| vroom | 1.7.0+ | Primary CSV loader | 1.23 GB/sec via lazy loading (Altrep); multi-threaded; matches readr syntax |
| readr | 2.2.0+ | Fallback CSV loader | Vroom dependency; solid backup if lazy loading causes issues |
| data.table | 1.16.2+ | NOT recommended for this project | 10-50x faster than vroom, but opaque syntax conflicts with "named predicate" requirement |
### Data Manipulation & Transformation
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | String operations | ICD code normalization (dotted vs undotted formats), payer category mapping |
| lubridate | 1.9.3+ | Date/time operations | Parse enrollment dates, diagnosis dates, calculate time-to-treatment |
| janitor | 2.2.1+ | Data cleaning | clean_names() for PCORnet column consistency, tabyl() for quick crosstabs |
| glue | 1.8.0 | String formatting | Readable logging messages with embedded expressions |
| here | 1.0.2 | Path management | Project-relative paths that work in RStudio & SLURM jobs: `here("data", "ENROLLMENT.csv")` |
- **stringr:** Consistent API for all string operations. PCORnet ICD codes come in multiple formats (C81.00, C8100); stringr's `str_remove()`, `str_detect()` handle normalization cleanly.
- **lubridate:** Date arithmetic is core to cohort selection (enrollment windows, diagnosis timing). lubridate makes `ymd()`, `interval()`, `%within%` readable.
- **janitor:** The clean_names() function handles PCORnet's mixed-case column names; tabyl() replaces table() for cleaner frequency outputs.
- **glue:** Logging attrition steps needs readable messages. `glue("Removed {n_removed} patients without HL diagnosis")` beats paste0.
- **here:** HiPerGator SLURM jobs change working directory; here() anchors paths to project root automatically.
### Cohort Building & Attrition Logging
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tidylog | 1.1.0 | Automatic pipeline logging | Wraps dplyr/tidyr to print N rows added/removed at each step |
| pointblank | 0.12.3+ | Data validation (optional) | Deep validation if data quality issues emerge; overkill for v1 |
- **tidylog:** Solves the attrition logging requirement automatically. Load it (`library(tidylog)`) and every dplyr operation logs before/after counts: `filter: removed 1,234 rows (12%), 9,876 remaining`. No manual logging code needed. Perfect for "logged attrition at every step."
- **pointblank:** Not needed for v1 (out of scope: "replicating Python pipeline's data cleaning"). Reserve for v2 if systematic validation becomes necessary.
### Visualization
| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| ggplot2 | 4.0.1+ | Base plotting | Grammar of graphics; publication-quality (though v1 only needs "exploratory quality") |
| ggalluvial | 0.12.5 | Sankey/alluvial diagrams | Purpose-built for enrollment → diagnosis → treatment flows; integrates with ggplot2 |
| scales | 1.3.0+ | Axis formatting | Format percentages, suppress small cells (HIPAA compliance via label functions) |
| consort | 0.3.0+ (optional) | Waterfall/CONSORT diagrams | Auto-generates CONSORT flow diagrams; alternative to manual ggplot waterfall |
- **ggplot2 4.0.1:** Major release (Sept 2025) with S7 rewrite. Stable, widely documented.
- **ggalluvial:** The standard for alluvial plots in R. `geom_alluvium()` + `geom_stratum()` creates payer-stratified flows. Alternatives (ggsankey, ggsankeyfier) lack maturity or have sparse documentation.
- **scales:** Needed for HIPAA suppression. `label_number(big.mark = ",")` for counts, custom label functions to replace 1-10 with "<11".
- **consort:** Creates CONSORT 2025-compliant attrition diagrams automatically from filter logs. May be easier than building waterfalls manually with ggplot. Evaluate during implementation.
### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| forcats | 1.0.0+ | Factor management | Reorder payer categories for visualizations (largest first, etc.) |
| purrr | 1.0.2+ | Functional programming | map() for applying functions across multiple tables, if needed |
| tibble | 3.2.1+ | Modern data frames | Included in tidyverse; better printing than base data.frame |
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
# data.table approach (fast but opaque)
# dplyr approach (slower but readable)
- Input format is CSV (given)
- One-time conversion overhead not justified for exploratory v1
- Consider for v2 if query performance becomes a bottleneck
## Installation
### On HiPerGator (HPC Environment)
# Load R module (check available versions with `module spider R`)
# Start R interactively
# In R console:
# Install renv for package management
# Initialize renv for this project (run once)
# Install core packages
# Snapshot the environment
# Exit R
- renv creates a project-local library with symlinks to HiPerGator's global cache (efficient disk usage)
- renv.lock file pins exact versions for reproducibility
- Other users run `renv::restore()` to recreate the exact environment
- The `module load R/4.4.2` command must be in every SLURM script
### On Local RStudio (Optional Development)
# Install tidyverse and supporting packages
# Clone project and restore environment
## Anti-Patterns to Avoid
### 1. Don't Use data.table Syntax in This Project
# AVOID: data.table (fast but opaque)
# PREFER: dplyr (readable)
### 2. Don't Use setwd() for Paths
# AVOID: Absolute or relative paths
# PREFER: here() for project-relative paths
### 3. Don't Mix Base R and Tidyverse Pipes
# AVOID: Mixing base R subset with pipes
# PREFER: Consistent dplyr
### 4. Don't Install Packages in SLURM Scripts
# AVOID in SLURM script:
# PREFER: Install once interactively, then snapshot
# Interactive session:
# SLURM script just loads the module and runs code
### 5. Don't Use read.csv() or read_csv() Without Type Specification for PCORnet
# AVOID: Letting vroom guess all types
# PREFER: Specify critical column types
## HiPerGator-Specific Considerations
### Module Loading Order
# In SLURM script, load R before running
### Memory and Threading
- **vroom** is multi-threaded by default. On HiPerGator, request appropriate CPU cores:
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
| Package | Min Version | Why |
|---------|-------------|-----|
| tidyverse | 2.0.0 | Major release (July 2025), includes dplyr 1.2.0, ggplot2 4.0.0 |
| vroom | 1.7.0 | Latest performance optimizations |
| ggalluvial | 0.12.5 | Stable API |
| tidylog | 1.1.0 | Latest (May 2024); updates infrequent but stable |
| janitor | 2.2.1 | Latest (July 2025) |
| glue | 1.8.0 | Latest (July 2025) |
- scales, stringr, lubridate, forcats (tidyverse dependencies; updated together)
- purrr, tibble (included in tidyverse)
## Sources
- Context7: N/A (R ecosystem not available in Context7 as of 2026-03-24)
- Official CRAN: Primary source for version numbers and package documentation
- Official Package Documentation: tidyverse.org, rstudio.github.io
- Benchmarks: vroom benchmarks, data.table vs tidyverse comparisons
- HiPerGator Documentation: Weecology Wiki, UF HiPerGator guides
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
- Core stack (tidyverse, vroom, ggplot2, dplyr): **HIGH** (official CRAN releases, extensive benchmarks)
- Visualization (ggalluvial, scales): **HIGH** (mature packages, published methodology)
- Logging (tidylog): **MEDIUM** (less widespread adoption, but stable 1.1.0 release)
- CONSORT diagrams (consort): **MEDIUM** (designed for RCTs, may need adaptation for observational cohorts)
- HiPerGator specifics (module loading, renv): **HIGH** (official UF documentation)
- All CRAN versions verified against official CRAN pages (accessed 2026-03-24)
- Benchmarks verified from vroom official documentation
- HiPerGator guidance from Weecology Wiki (UF-affiliated resource)
- PCORnet CDM v7.0 specification available (Jan 2025) but no R-specific tooling documented
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
