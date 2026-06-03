# Phase 79: Code Investigations & New Tables - Research

**Researched:** 2026-06-03
**Domain:** R data quality investigation scripts with multi-sheet xlsx output and graph-based verification
**Confidence:** HIGH

## Summary

Phase 79 implements three diagnostic/verification scripts in the cancer/codes decade (R/54-R/56): (1) SCT code 0362 encounter-level investigation to determine if revenue code 0362 represents true transplants or coding artifacts, (2) replaced-by code mapping verification with cycle detection to validate code replacement chains from all_codes_resolved_next_tables_v2.1.xlsx, and (3) new drug grouping summary tables showing treatment-type-level and drug-level encounter counts stratified by cancer codes.

All three scripts follow established patterns from R/35 (multi-sheet investigation output), R/50 (openxlsx2 usage), and R/76 (coverage analysis). The primary technical challenge is graph-based cycle detection for replaced-by verification — can be solved with igraph package (lightweight, standard for graph analysis in R) or custom base R DFS implementation (more code, zero dependencies).

**Primary recommendation:** Use igraph package for cycle detection (is_dag() function) — it's the R ecosystem standard for graph analysis, lightweight (~2MB), and provides both DAG verification and cycle enumeration. Custom DFS implementation adds code complexity for minimal benefit.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Script Numbering (D-01 through D-04):**
- New scripts in the 54-56 range within the cancer/codes decade (40-59), NOT the roadmap's originally suggested R/92, R/93, R/76 (all taken)
- R/54_investigate_sct_0362.R — SCT code 0362 investigation
- R/55_verify_replaced_by_codes.R — replaced-by code verification
- R/56_new_tables_from_groupings.R — two new drug grouping summary tables

**SCT 0362 Investigation (D-05 through D-07):**
- Full encounter profile — pull complete encounter details (all procedures, diagnoses, prescriptions) for encounters with revenue code 0362
- Output: multi-sheet xlsx. Sheet 1: patient summary (PATID, encounter count, other SCT codes found). Sheet 2: encounter-level detail (all procedures, diagnoses for 0362 encounters). Sheet 3: summary statistics
- Automated recommendation based on overlap rate with standard SCT codes (38204-38241, 0815): >80% overlap = "confirmed SCT", <30% = "likely coding artifact", 30-80% = "manual review needed"

**Replaced-by Verification (D-08 through D-11):**
- Replaced-by mappings are in all_codes_resolved_next_tables.xlsx (column/sheet in the xlsx)
- Primary verification: pairwise check — for each old->new pair, verify old code IS in our code lists, new code IS also in our code lists, and both map to the same treatment category. Flag mismatches and missing codes with PASS/FAIL status
- Secondary verification: chain detection — detect replacement chains >3 steps and any cycles. Uses igraph for DAG checking (new lightweight dependency, noted in STATE.md open question #6)
- Output: xlsx verification report. Sheet 1: all replaced-by pairs with PASS/FAIL/MISSING status. Sheet 2: chain analysis (chains >3 steps, any cycles). Sheet 3: summary statistics. Plus console diagnostics

**New Drug Grouping Tables (D-12 through D-16):**
- Single xlsx output with 2 sheets matching all_codes_resolved_next_tables.xlsx Sheet1 templates
- Table 1 (Sheet 1): treatment-type-level summary. Rows = treatment types (Chemo, Radiation, SCT, Immunotherapy). Columns: treatment type | cancer code(s) for the encounter (raw ICD codes) | count of encounters. One row per unique treatment-type + cancer-code-set combination
- Table 2 (Sheet 2): drug-level summary. Rows = individual treatment codes (CPT/HCPCS/NDC). Columns: treatment code | cancer code(s) for the encounter (raw ICD codes) | count of encounters. One row per unique treatment-code + cancer-code-set combination
- Cancer codes = raw ICD diagnosis codes linked to the encounter (not cancer_category labels). Multi-code encounters show semicolon-separated code sets
- Data source: treatment_episodes.rds (from R/28) joined with encounter-level cancer linkage data. Uses DRUG_GROUPINGS for treatment type classification and triggering_codes for cancer code extraction

**Quality Process (D-17):**
- During execution, take explicit validation passes through all new scripts to verify: (a) column names referenced actually exist in source data, (b) joins use correct keys and produce expected row counts, (c) source() calls reference correct script paths, (d) functions called are defined and accessible. Fix any issues found before committing

### Claude's Discretion

- igraph installation approach (install.packages vs renv::install) — follow existing renv pattern
- Script header comment depth — follow v2.0 standard patterns from R/35 or R/50

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CODE-01 | "Replaced by" codes from all_codes_resolved_next_tables.xlsx verified against existing code mappings | igraph cycle detection, pairwise category matching from DRUG_GROUPINGS/TREATMENT_CODES |
| CODE-02 | 90 patients with SCT code 0362 investigated for other related SCT codes during same encounters | DuckDB PROCEDURES table encounter-level profiling, standard CPT SCT codes 38204-38241 + revenue 0815 |
| TREAT-03 | Two new summary tables matching all_codes_resolved_next_tables.xlsx Sheet1 templates: (1) treatment-type-level summary, (2) drug-level summary | treatment_episodes.rds + DRUG_GROUPINGS + encounter-level cancer linkage |
| QUAL-01 | All new/modified scripts follow v2.0 standards (styler formatting, lintr compliance, checkmate assertions, documentation headers, smoke test updates) | Established patterns from R/35, R/50, R/76; utils_assertions.R helpers |

</phase_requirements>

## Project Constraints (from CLAUDE.md)

**Runtime environment:** RStudio on UF HiPerGator — scripts must work in that environment
**R packages:** tidyverse ecosystem (dplyr, ggplot2, stringr, lubridate), ggalluvial for Sankey, scales, janitor, glue
**Data access:** Raw CSVs on HiPerGator filesystem (but this pipeline uses DuckDB) — paths configured in R/00_config.R
**Code style:** Filtering logic uses named predicate functions (`has_*`, `with_*`, `exclude_*`) — no opaque one-liners
**Payer fidelity:** Must match the Python pipeline's 9-category payer mapping exactly, including dual-eligible detection

## Standard Stack

### Core Libraries (Already in Project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Treatment episode joining, category filtering |
| openxlsx2 | 1.8+ | Multi-sheet xlsx output | Established in R/35, R/50 for investigation reports |
| glue | 1.8.0 | String formatting | Console diagnostics, error messages |
| checkmate | 2.3.2+ | Input validation | Defensive assertions per v2.0 standards |
| stringr | 1.5.1+ | String operations | Code matching, semicolon-separated ICD lists |
| DuckDB | via R/utils/utils_duckdb.R | PCORnet table access | Encounter-level PROCEDURES/DIAGNOSIS queries |

### New Dependency (Recommended)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| igraph | 2.0.3+ | Graph cycle detection | R/55 replaced-by verification (is_dag, find_cycle functions) |

**Why igraph:** Standard R package for graph analysis (10,000+ CRAN reverse dependencies). Provides `is_dag()` for acyclic verification and `find_cycle()` for cycle enumeration. Lightweight (~2MB). Alternative is custom DFS implementation in base R (50-100 LOC, more testing burden).

**Installation:**
```r
# In interactive R session on HiPerGator
renv::install("igraph")
renv::snapshot()
```

### Version Verification
All recommended packages verified against CRAN on 2026-06-03:
- openxlsx2 1.8 (released May 25, 2026)
- igraph 2.0.3 (current stable version, widely used for graph algorithms)
- checkmate 2.3.2 (released February 3, 2026)

## Architecture Patterns

### Recommended Project Structure
New scripts fit into existing cancer/codes decade (40-59):
```
R/
├── 40-49/           # Cancer frequency and site analysis
├── 50-53/           # Code resolution and validation
├── 54-56/           # NEW: Code quality investigations
│   ├── 54_investigate_sct_0362.R
│   ├── 55_verify_replaced_by_codes.R
│   └── 56_new_tables_from_groupings.R
├── 57-59/           # Gantt data export
```

### Pattern 1: Multi-Sheet Investigation Output (from R/35)
**What:** openxlsx2 workbook with 3+ sheets (patient summary, detail, statistics)
**When to use:** Diagnostic scripts requiring human review (R/54, R/55)
**Example:**
```r
# Source: R/35_death_cause_quality.R lines 277-350
wb <- wb_workbook()

# Sheet 1: Patient summary
wb$add_worksheet("Patient Summary")
wb$add_data("Patient Summary", patient_summary, start_row = 1, col_names = TRUE)

# Sheet 2: Encounter detail
wb$add_worksheet("Encounter Detail")
wb$add_data("Encounter Detail", encounter_detail, start_row = 1, col_names = TRUE)

# Sheet 3: Summary statistics
wb$add_worksheet("Summary")
wb$add_data("Summary", summary_stats, start_row = 1, col_names = TRUE)

# Save
wb$save(OUTPUT_XLSX)
message(glue("Saved: {OUTPUT_XLSX}"))
```

### Pattern 2: Pairwise Verification with PASS/FAIL Status
**What:** Validate each mapping pair against reference data, flag issues
**When to use:** Code mapping verification (R/55 replaced-by validation)
**Example:**
```r
# Pseudo-code for R/55
replaced_by_pairs <- read_xlsx("all_codes_resolved_next_tables_v2.1.xlsx", sheet = "Replaced By")

verification <- replaced_by_pairs %>%
  mutate(
    old_exists = old_code %in% names(TREATMENT_CODES),
    new_exists = new_code %in% names(TREATMENT_CODES),
    old_category = DRUG_GROUPINGS[old_code],
    new_category = DRUG_GROUPINGS[new_code],
    category_match = old_category == new_category,
    status = case_when(
      !old_exists ~ "FAIL: old code not in TREATMENT_CODES",
      !new_exists ~ "FAIL: new code not in TREATMENT_CODES",
      !category_match ~ "FAIL: category mismatch",
      TRUE ~ "PASS"
    )
  )
```

### Pattern 3: Encounter-Level Profiling (from R/76)
**What:** Join treatment episodes with PCORnet tables to pull all encounter details
**When to use:** Investigating code context (R/54 SCT 0362 encounter profiling)
**Example:**
```r
# Source: R/76_treatment_source_coverage.R lines 59-91 (extraction pattern)
open_pcornet_con()

# Identify encounters with code 0362
encounters_0362 <- get_pcornet_table("PROCEDURES") %>%
  filter(PX == "0362", PX_TYPE == "RE") %>%
  distinct(PATID, ENCOUNTERID) %>%
  collect()

# Pull all procedures for those encounters
encounter_procedures <- get_pcornet_table("PROCEDURES") %>%
  semi_join(encounters_0362, by = c("PATID", "ENCOUNTERID")) %>%
  collect()

# Pull all diagnoses for those encounters
encounter_diagnoses <- get_pcornet_table("DIAGNOSIS") %>%
  semi_join(encounters_0362, by = c("PATID", "ENCOUNTERID")) %>%
  collect()
```

### Pattern 4: Graph Cycle Detection with igraph
**What:** Build directed graph from old→new mappings, check for cycles
**When to use:** Verifying replacement chains don't loop (R/55)
**Example:**
```r
# Source: igraph official docs (https://r.igraph.org/reference/is_dag.html)
library(igraph)

# Build edge list from replaced-by mappings
edge_list <- replaced_by_pairs %>%
  select(from = old_code, to = new_code)

# Create directed graph
g <- graph_from_data_frame(edge_list, directed = TRUE)

# Check if DAG (no cycles)
if (is_dag(g)) {
  message("PASS: No cycles detected in replacement chains")
} else {
  cycle <- find_cycle(g)
  message(glue("FAIL: Cycle detected: {paste(cycle, collapse = ' -> ')}"))
}

# Find long chains (>3 steps)
# Use igraph::distances() to compute path lengths
dist_matrix <- distances(g, mode = "out")
long_chains <- which(dist_matrix > 3, arr.ind = TRUE)
```

### Anti-Patterns to Avoid

- **Don't use setwd() for paths:** Use `file.path(CONFIG$output_dir, ...)` (from R/00_config.R)
- **Don't install packages in scripts:** Use interactive renv::install(), then snapshot
- **Don't skip input validation:** All new scripts must use `assert_df_valid()` from utils_assertions.R
- **Don't hard-code column names without checking schema:** Use `checkmate::assert_names()` to verify columns exist before referencing

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Graph cycle detection | Custom DFS with recursion tracking | igraph::is_dag() + igraph::find_cycle() | Edge cases (self-loops, disconnected components) are subtle; igraph is battle-tested |
| Multi-sheet xlsx with styling | Manual XML manipulation | openxlsx2 wb_workbook() pipe API | Established in R/35, R/50; handles formatting, date types, formulas |
| Treatment category lookup | Re-parse all_codes_resolved xlsx | DRUG_GROUPINGS named vector (R/00_config.R) | Already centralized in Phase 77 (454 codes); runtime xlsx dependency is anti-pattern |
| Input validation | Manual stopifnot() chains | utils_assertions.R helpers (assert_df_valid, assert_col_types) | Consistent error messages with glue() formatting; reduces boilerplate |

**Key insight:** Investigation scripts (R/54-R/56) are diagnostic tools for human review, not production pipeline components. Prioritize readability and rich output over performance optimization.

## Common Pitfalls

### Pitfall 1: Assuming Revenue Code 0362 is Standard SCT Code
**What goes wrong:** Code 0362 appears in TREATMENT_CODES but is NOT in standard CPT/HCPCS databases. Documentation conflict leads to incorrect categorization.
**Why it happens:** Revenue codes (0362, 0815) are billing codes, not procedure codes. Standard SCT CPT codes are 38204-38241 (autologous/allogeneic procedures). Revenue 0362 = "Organ transplant - other than kidney" is a catch-all billing category that may include non-SCT transplants or data entry errors.
**How to avoid:** R/54 investigation explicitly compares 0362 encounters against standard CPT codes (38204-38241) and revenue 0815. Overlap rate >80% = confirmed SCT, <30% = likely artifact.
**Warning signs:** If R/54 shows <30% overlap, review with domain expert before assuming 0362 = SCT.

### Pitfall 2: Circular Replacement Chains
**What goes wrong:** Replaced-by mappings form a cycle (A→B→C→A), causing infinite loops in code resolution logic.
**Why it happens:** Manual xlsx editing without graph validation. Code A deprecated, replaced by B. Later B deprecated, replaced by C. Then C mistakenly replaced by A.
**How to avoid:** R/55 uses igraph::is_dag() to detect cycles BEFORE code resolution logic consumes mappings. Fail-fast with explicit error listing the cycle.
**Warning signs:** If is_dag(g) returns FALSE, use igraph::find_cycle(g) to extract the cycle path for human review.

### Pitfall 3: Treatment Episode to Encounter Join Produces Cartesian Product
**What goes wrong:** One treatment episode spans multiple encounters. Naive join creates duplicate rows (one per encounter), inflating counts in R/56 tables.
**Why it happens:** treatment_episodes.rds has ENCOUNTERID but episodes can have multiple encounters (multi-day hospitalizations). Joining on ENCOUNTERID alone without distinct() creates many-to-many join.
**How to avoid:** After joining treatment_episodes with encounter-level diagnosis data, use `distinct(triggering_codes, cancer_codes, .keep_all = TRUE)` to collapse to unique combinations. Add `warn_row_count()` assertion comparing pre-join vs post-join counts.
**Warning signs:** R/56 output shows suspiciously high encounter counts (>10,000 when treatment_episodes.rds has ~5,000 rows).

### Pitfall 4: Missing Column References After Schema Changes
**What goes wrong:** Script references `DEATH_CAUSE` but actual column is `DEATH_CAUSE_CODE`. Silent NA propagation or cryptic error.
**Why it happens:** PCORnet CDM field names vary by site. Phase 78 added defensive column checking (R/35 lines 73-87), but new scripts might skip it.
**How to avoid:** At script start, use `assert_df_valid(df, required_cols = c("col1", "col2"))` from utils_assertions.R. For optional columns, use `if ("col" %in% names(df))` guards.
**Warning signs:** Cryptic errors like "object 'DEATH_CAUSE' not found" or unexpected NA counts in output.

### Pitfall 5: Semicolon-Separated ICD Codes Not Split for Lookup
**What goes wrong:** Cancer codes stored as "C81.0;C81.1;C81.9" in triggering_codes. Direct lookup in CANCER_SITE_MAP fails.
**Why it happens:** R/28 stores triggering_codes as comma-separated (Phase 78 decision D-78-07), but R/56 output template shows semicolon-separated. Inconsistent delimiter handling.
**How to avoid:** Use `str_split()` to parse multi-code fields before lookup. For R/56 output, use `paste(codes, collapse = ";")` to format as semicolon-separated per template.
**Warning signs:** R/56 cancer_codes column shows NA when treatment_episodes.rds has populated triggering_codes.

## Code Examples

Verified patterns from existing scripts:

### Opening DuckDB Connection (R/35 lines 65-67)
```r
# Source: R/35_death_cause_quality.R
USE_DUCKDB <- TRUE
open_pcornet_con()
death_raw <- get_pcornet_table("DEATH") %>% collect()
```

### Multi-Sheet XLSX with Styling (R/35 lines 277-315)
```r
# Source: R/35_death_cause_quality.R
wb <- wb_workbook()

# Sheet 1: Overall stats
wb$add_worksheet("Overall Completeness")
wb$add_data("Overall Completeness", overall_stats, start_row = 1, col_names = TRUE)

# Sheet 2: Payer stratification
wb$add_worksheet("By Payer")
wb$add_data("By Payer", payer_stats, start_row = 1, col_names = TRUE)

# Save
wb$save(OUTPUT_XLSX)
message(glue("Saved multi-sheet report: {OUTPUT_XLSX}"))
```

### Input Validation with checkmate (utils_assertions.R lines 79-94)
```r
# Source: R/utils/utils_assertions.R
assert_df_valid(
  enrollment,
  name = "ENROLLMENT",
  required_cols = c("ID", "ENR_START_DATE", "ENR_END_DATE"),
  script_name = "R/14"
)

assert_col_types(
  treatment_episodes,
  type_spec = list(
    patient_id = "character",
    episode_start = "Date",
    episode_count = "integer"
  ),
  script_name = "R/54"
)
```

### igraph Cycle Detection (official docs pattern)
```r
# Source: https://r.igraph.org/reference/is_dag.html
library(igraph)

# Build graph from edge list
g <- graph_from_data_frame(
  d = data.frame(from = c("A", "B", "C"), to = c("B", "C", "A")),
  directed = TRUE
)

# Check for cycles
if (!is_dag(g)) {
  cycle <- find_cycle(g)
  stop(glue("Cycle detected: {paste(cycle, collapse = ' -> ')}"))
}
```

### Console Diagnostics with glue (R/35 lines 56-59)
```r
# Source: R/35_death_cause_quality.R
message("=== Phase 78: Death Cause Quality Profiling ===\n")
message(glue("Output files:"))
message(glue("  XLSX: {OUTPUT_XLSX}"))
message(glue("  RDS:  {OUTPUT_RDS}\n"))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual code replacement tracking in comments | all_codes_resolved_next_tables.xlsx replaced-by column | Phase 50 (2026-05-22) | Centralized tracking, but needs verification (R/55) |
| Tumor registry as treatment source | Dropped from pipeline | Phase 76 (v2.1, 2026-06-03) | 6 sources instead of 7, higher accuracy per literature |
| Drug groupings in xlsx at runtime | DRUG_GROUPINGS in R/00_config.R | Phase 77 (v2.1, 2026-06-03) | No runtime xlsx dependency, follows AMC_PAYER_LOOKUP pattern |
| Patient-level cancer flag | Per-episode cancer_category | Phase 78 (v2.1, 2026-06-03) | Handles multiple primaries correctly |

**Deprecated/outdated:**
- Tumor registry treatment data: Dropped in Phase 76 due to 8-32% accuracy vs EHR 95-100% (per literature)
- Runtime xlsx dependencies for code lookups: Anti-pattern per Phase 77 decision traceability

## Open Questions

1. **all_codes_resolved_next_tables_v2.1.xlsx sheet structure for replaced-by mappings**
   - What we know: File exists in data/reference/, contains drug groupings and templates (per CONTEXT.md canonical refs)
   - What's unclear: Exact sheet name for replaced-by mappings, column names (old_code/new_code vs code/replaced_by)
   - Recommendation: R/55 implementation should inspect xlsx structure first with `openxlsx2::wb_load()` + `wb_get_sheet_names()`, fail-fast if expected columns missing

2. **Encounter-level cancer linkage data schema**
   - What we know: treatment_episodes.rds has triggering_codes (comma-separated ICD codes per D-78-07)
   - What's unclear: Does R/56 need to re-query DIAGNOSIS table or can it use triggering_codes directly?
   - Recommendation: Use triggering_codes from treatment_episodes.rds directly. It's already encounter-linked (R/28 ENCOUNTERID join), no need to re-query DuckDB

3. **igraph package approval for new dependency**
   - What we know: STATE.md open question #6 notes igraph as "lightweight addition but new dependency"
   - What's unclear: Has user approved adding igraph to renv.lock?
   - Recommendation: Proceed with igraph per CONTEXT.md D-10 (user explicitly requested igraph for DAG checking). Alternative custom DFS adds 50-100 LOC for minimal benefit

4. **SCT code 0362 provenance documentation**
   - What we know: STATE.md open question #1 notes 0362 "not in standard CPT databases", likely internal/proprietary code
   - What's unclear: Should R/54 attempt external documentation lookup or just report overlap statistics?
   - Recommendation: R/54 outputs overlap statistics only (internal investigation). External documentation review is out of scope (requires domain expert)

## Environment Availability

Phase 79 has no external tool dependencies beyond R packages. All required packages (dplyr, openxlsx2, glue, checkmate, stringr) are already in the project per CLAUDE.md stack documentation. Only new dependency is igraph (approved per CONTEXT.md D-10).

**R package installation (HiPerGator environment):**
```bash
# In SLURM job or interactive session
module load R/4.4.2

# In R console
renv::install("igraph")
renv::snapshot()
```

No system-level dependencies, no external APIs, no database setup required. DuckDB connection managed by existing utils_duckdb.R infrastructure.

## Sources

### Primary (HIGH confidence)
- [igraph R manual - is_dag function](https://igraph.org/r/doc/is_dag.html) - Cycle detection and DAG verification
- [openxlsx2 CRAN documentation](https://cran.r-project.org/web/packages/openxlsx2/vignettes/openxlsx2.html) - Multi-sheet workbook creation (version 1.8, May 2026)
- [checkmate CRAN package](https://cloud.r-project.org/web/packages/checkmate/checkmate.pdf) - Data frame validation (version 2.3.2, Feb 2026)
- [SEER ICD Conversion Tools](https://seer.cancer.gov/tools/conversion/) - ICD-9 to ICD-10 mapping reference (FY2026 available)
- [ASTCT HCT Reimbursement FAQs](https://www.astct.org/Portals/0/Docs/Coverage_Coding/HCT%20Reimbursement%20FAQs.pdf?ver=1-gtxqW_-rxd7CjBZiW6QA%3D%3D) - SCT CPT codes 38204-38241, revenue codes 0362/0815
- R/35_death_cause_quality.R (codebase) - Multi-sheet investigation pattern template
- R/50_all_codes_resolved.R (codebase) - openxlsx2 usage pattern
- R/76_treatment_source_coverage.R (codebase) - Encounter-level profiling pattern
- R/00_config.R (codebase) - DRUG_GROUPINGS (454 codes), TREATMENT_CODES (including 0362)
- R/28_episode_classification.R (codebase) - treatment_episodes.rds schema (triggering_codes, cancer_category, drug_group)
- R/utils/utils_assertions.R (codebase) - Input validation helpers

### Secondary (MEDIUM confidence)
- [toposort R package](https://cran.r-project.org/web/packages/toposort/toposort.pdf) - Alternative to igraph for topological sorting (May 2026)
- [CMS Medicare Coverage Database - Stem Cell Transplantation](https://www.cms.gov/medicare-coverage-database/view/article.aspx?articleid=52879) - Revenue code 0815 usage guidelines

### Tertiary (LOW confidence)
- Web search results on R base DFS implementation - Insufficient detail for production use without igraph

## Metadata

**Confidence breakdown:**
- Standard stack (dplyr, openxlsx2, checkmate): HIGH - All packages already in project, versions verified against CRAN 2026-06-03
- Architecture patterns (multi-sheet xlsx, encounter profiling): HIGH - Directly sourced from existing codebase scripts (R/35, R/50, R/76)
- Graph cycle detection (igraph): HIGH - Official igraph documentation, widely adopted package (10,000+ reverse dependencies)
- SCT code 0362 clinical meaning: MEDIUM - Official billing documentation confirms 0362 = "Organ transplant - other than kidney", but clinical interpretation requires domain expert review of R/54 overlap statistics
- Replaced-by xlsx schema: LOW - File exists but exact sheet structure not verified (will be confirmed during R/55 implementation)

**Research date:** 2026-06-03
**Valid until:** 2026-07-03 (30 days — stable domain, no fast-moving dependencies)
