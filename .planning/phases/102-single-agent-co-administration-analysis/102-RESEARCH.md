# Phase 102: Single-Agent Co-Administration Analysis - Research

**Researched:** 2026-06-12
**Domain:** Temporal self-join analysis, chemotherapy co-administration pattern detection, fragmented billing identification
**Confidence:** HIGH

## Summary

Phase 102 creates a standalone investigation script (R/58) that identifies single-agent chemotherapy encounters and finds all co-administered chemotherapies within a ±30-day temporal window. This reveals fragmented billing patterns where multi-drug regimens (ABVD, BV+AVD) appear as separate single-agent encounters instead of being billed together.

The analysis requires a **temporal self-join** on the treatment_episode_detail.rds dataset filtered to chemotherapy-only encounters that are NOT already classified as multi-agent regimens. The primary technical challenge is efficiently joining each single-agent encounter against all other encounters for the same patient within the date window, producing a detail table (one row per encounter-drug pair) and a pattern summary table (ranked by frequency).

**Primary recommendation:** Use data.table's **rolling join** with IDate columns for efficient temporal window matching. Follow R/57's established pattern: read treatment_episode_detail.rds, filter to qualifying encounters, perform self-join with date arithmetic, produce two-sheet xlsx via openxlsx2.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Single-Agent Definition:**
- D-01: "Single-agent" means one chemotherapy triggering_code per patient-date. Group by (patient_id, treatment_date) — if only 1 chemo code appears on that date, the encounter qualifies.
- D-02: Include encounters with no resolved drug_name (drug_name is NA). Use triggering_code as the identifier. Some chemo is billed via J-codes without RxNorm resolution — these should not be excluded.

**Window & Scope:**
- D-03: ±30-day window from treatment_date. For each single-agent chemo encounter, find all OTHER chemo encounters for the same patient within 30 days before or after.
- D-04: Chemo-to-chemo only. Only Chemotherapy treatment_type encounters are included in both the single-agent base and the co-administration window. Radiation, SCT, Immunotherapy, Proton Therapy are excluded.
- D-05: Exclude encounters already classified as part of a multi-agent regimen (regimen_label = ABVD, BV+AVD, or Nivo+AVD from R/28). Only analyze truly unclassified single-agent encounters — these are the ones that might represent fragmented billing.

**Output Structure:**
- D-06: Two-sheet xlsx output: Sheet 1 = "Co-Administration Detail" (COADMIN-01), Sheet 2 = "Pattern Summary" (COADMIN-02).
- D-07: Detail table format: one row per (single-agent encounter, co-administered drug) pair. Multiple rows if multiple co-admin drugs found within ±30 days. Columns include days_apart for temporal analysis.
- D-08: Drug identification: show both human-readable sub_category_name AND triggering_code. Sub-category names from R/57's reference xlsx mapping pattern (CODE_SUBCATEGORY_MAP or direct xlsx lookup).

**Script Placement:**
- D-09: New standalone script: R/58_co_administration_analysis.R. Follows R/57 in the drug grouping decade. Reads same treatment_episode_detail.rds input.
- D-10: Self-contained investigation script — loads its own data, produces its own output. Does not modify any upstream RDS files or existing outputs.

### Claude's Discretion

- Column ordering in detail and summary tables
- Whether to include cancer_linked flag from Phase 101 in the co-admin detail
- Sub-category name resolution approach (reuse R/57's xlsx lookup pattern vs CODE_SUBCATEGORY_MAP from R/00_config.R)
- Console summary messages and attrition logging
- R/88 smoke test validation section structure and check count

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| COADMIN-01 | Detail table showing each single-agent chemo encounter with all co-administered chemotherapies found within ±30 days | Temporal self-join pattern (data.table or dplyr), openxlsx2 Sheet 1 output |
| COADMIN-02 | Pattern summary table showing most common co-administration pairings and their frequencies | Group-by aggregation on (drug_A, drug_B) pairs, sorted descending by count, openxlsx2 Sheet 2 output |

</phase_requirements>

## Standard Stack

### Core Libraries (Already in Project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| data.table | 1.16.2+ | Temporal self-join engine | Already adopted in Phase 95-99 for hot-path performance; rolling joins and IDate optimized for temporal windows |
| dplyr | 1.2.0+ | Data filtering and aggregation | Project standard for readable pipelines; used for filtering to single-agent base before data.table conversion |
| openxlsx2 | Latest | Two-sheet xlsx output | Established in R/57, R/28, R/52; wb_workbook() → add_worksheet() → add_data() → save() pattern |
| glue | 1.8.0 | Console logging | Project standard for attrition messages and section headers |

### Supporting Libraries (Already Available)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| lubridate | 1.9.3+ | Date arithmetic for ±30-day window | Convert treatment_date to Date class if needed; calculate days_apart via `as.numeric(date1 - date2)` |
| stringr | 1.5.1+ | Sub-category name resolution | Extract drug names from semicolon-separated strings if needed |

### Already Loaded via R/00_config.R

All libraries above are sourced when R/58 loads R/00_config.R. **No new package installations required.**

## Architecture Patterns

### Recommended Script Structure
```
R/58_co_administration_analysis.R
├── SECTION 1: SETUP AND CONFIGURATION
│   ├── Load libraries (via source("R/00_config.R"))
│   ├── Define file paths (input: treatment_episode_detail.rds, treatment_episodes.rds)
│   └── Define output path (output/co_administration_analysis.xlsx)
├── SECTION 2: LOAD AND FILTER DATA
│   ├── Load treatment_episode_detail.rds
│   ├── Load treatment_episodes.rds (for regimen_label filter)
│   ├── Filter to Chemotherapy treatment_type only (D-04)
│   ├── Anti-join to exclude regimen-classified encounters (D-05)
│   └── Group by (patient_id, treatment_date) to identify single-agent encounters (D-01)
├── SECTION 3: BUILD SUB-CATEGORY MAPPINGS
│   ├── Load reference xlsx (same pattern as R/57 Section 3)
│   ├── Build code_to_subcategory lookup
│   └── Map triggering_codes to human-readable names
├── SECTION 4: TEMPORAL SELF-JOIN (±30-DAY WINDOW)
│   ├── Convert to data.table with IDate columns
│   ├── Perform rolling join or manual date arithmetic
│   ├── Filter to ±30-day range (D-03)
│   └── Exclude self-matches (same encounter)
├── SECTION 5: BUILD DETAIL TABLE (COADMIN-01)
│   ├── One row per (single-agent encounter, co-administered drug) pair
│   ├── Add days_apart column (temporal distance)
│   ├── Add sub_category_name for both single-agent drug and co-admin drug
│   └── Sort by patient_id, treatment_date, days_apart
├── SECTION 6: BUILD PATTERN SUMMARY TABLE (COADMIN-02)
│   ├── Group by (drug_A, drug_B) pairs
│   ├── Count frequency
│   ├── Sort descending by count
│   └── Top N patterns (e.g., top 50 for exploratory analysis)
├── SECTION 7: WRITE XLSX OUTPUT
│   ├── wb_workbook()
│   ├── Sheet 1: "Co-Administration Detail"
│   ├── Sheet 2: "Pattern Summary"
│   └── wb$save()
└── SECTION 8: CONSOLE SUMMARY
    ├── Total single-agent encounters identified
    ├── Encounters with co-administered drugs found
    ├── Total co-administration pairs
    └── Top 10 most common pairings
```

### Pattern 1: Temporal Self-Join (data.table Approach)

**What:** Join a table to itself on patient_id with date range constraints to find co-occurring events within a time window.

**When to use:** When finding all encounters within ±N days of an index encounter for the same patient.

**Example (data.table rolling join):**
```r
# Source: data.table vignettes + project Phase 95-99 patterns
# Convert to data.table with IDate for performance
library(data.table)

single_agent_dt <- as.data.table(single_agent_encounters)
setkey(single_agent_dt, patient_id, treatment_date)

all_chemo_dt <- as.data.table(all_chemo_encounters)
setkey(all_chemo_dt, patient_id, treatment_date)

# Self-join with date range filter
# Rolling join approach: match on patient_id, then filter by date arithmetic
coadmin_pairs <- single_agent_dt[all_chemo_dt,
  on = .(patient_id),
  allow.cartesian = TRUE,
  nomatch = NULL
]

# Filter to ±30-day window and exclude self-matches
coadmin_pairs <- coadmin_pairs[
  abs(as.numeric(treatment_date - i.treatment_date)) <= 30 &
  ENCOUNTERID != i.ENCOUNTERID
]

# Calculate days_apart
coadmin_pairs[, days_apart := as.numeric(i.treatment_date - treatment_date)]
```

**Alternative (dplyr non-equi join):**
```r
# Source: dplyr 1.2.0+ join_by() with inequality
# Requires dplyr 1.2.0+ for join_by() helper
library(dplyr)

coadmin_pairs <- single_agent_encounters %>%
  inner_join(
    all_chemo_encounters,
    by = join_by(
      patient_id == patient_id,
      closest(treatment_date >= treatment_date - 30),
      closest(treatment_date <= treatment_date + 30)
    ),
    relationship = "many-to-many",
    suffix = c("_index", "_coadmin")
  ) %>%
  filter(ENCOUNTERID_index != ENCOUNTERID_coadmin) %>%
  mutate(days_apart = as.numeric(treatment_date_coadmin - treatment_date_index))
```

**Recommendation:** Use **data.table approach** since project already adopted data.table in Phase 95-99 for performance-critical joins. The cartesian join with manual date filtering is more explicit and debuggable than dplyr's non-equi join syntax.

### Pattern 2: Single-Agent Encounter Identification

**What:** Group by (patient_id, treatment_date) and count distinct triggering_codes to identify single-agent encounters.

**When to use:** When determining if an encounter represents monotherapy vs combination therapy.

**Example:**
```r
# Source: R/28 regimen detection pattern (Section 5)
single_agent_encounters <- treatment_detail %>%
  filter(treatment_type == "Chemotherapy") %>%
  group_by(patient_id, treatment_date, ENCOUNTERID) %>%
  summarise(
    n_distinct_chemo_codes = n_distinct(triggering_code),
    triggering_code = first(triggering_code),  # Single code if n=1
    .groups = "drop"
  ) %>%
  filter(n_distinct_chemo_codes == 1)
```

### Pattern 3: Pattern Summary via Pair Counting

**What:** Create standardized (drug_A, drug_B) pairs where drug_A < drug_B alphabetically to avoid duplicate pairs (A+B vs B+A).

**When to use:** When summarizing co-occurrence patterns and need symmetric pair counts.

**Example:**
```r
# Create sorted pairs to avoid A+B / B+A duplication
pattern_summary <- coadmin_detail %>%
  mutate(
    drug_pair = paste(
      sort(c(index_drug_name, coadmin_drug_name)),
      collapse = " + "
    )
  ) %>%
  group_by(drug_pair) %>%
  summarise(
    n_instances = n(),
    n_patients = n_distinct(patient_id),
    .groups = "drop"
  ) %>%
  arrange(desc(n_instances))
```

### Anti-Patterns to Avoid

**1. Don't modify treatment_episodes.rds or treatment_episode_detail.rds**
- R/58 is an investigation script (per D-10)
- Read-only access to RDS files
- Never saveRDS() back to cache/outputs/ directory

**2. Don't use episode-level data for co-administration windows**
- Episodes aggregate multiple dates (episode_start to episode_stop)
- Co-administration needs **encounter-level dates** (treatment_date)
- Use treatment_episode_detail.rds, NOT treatment_episodes.rds, for temporal joins

**3. Don't count self-matches in co-administration pairs**
- Same encounter (same ENCOUNTERID) should not match itself
- Filter: `ENCOUNTERID_index != ENCOUNTERID_coadmin` after join

**4. Don't forget to handle NA drug_name values**
- D-02 requires including encounters with drug_name = NA
- Use triggering_code as fallback identifier
- Sub-category name resolution must handle unmapped codes gracefully

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Temporal joins with date ranges | Custom loop over patients with nested date comparisons | data.table keyed join with cartesian product + date filter | Hand-rolled loops are O(n²) per patient; data.table's keyed join is optimized for temporal operations with IDate storage |
| Excel multi-sheet workbooks | writexl or xlsx (archived) | openxlsx2 (already in project) | R/57, R/28, R/52 all use openxlsx2; consistency matters; writexl lacks styling support |
| Sub-category name lookups | Reimplementing xlsx parsing | Reuse R/57 Section 3 pattern (wb_load → wb_to_df → named vector) | R/57 already solved this; same reference xlsx, same code pattern |
| Regimen-classified encounter filtering | Querying R/28 output and reconstructing logic | Anti-join on treatment_episodes.rds regimen_label column | R/28 already classified regimens; D-05 just needs to exclude those rows |

**Key insight:** This phase is 80% reusing existing patterns (R/57 data loading, R/28 regimen detection, data.table joins from Phase 95-99, openxlsx2 from Phase 88-91) and 20% new logic (temporal self-join, pair summarization). Focus effort on the temporal join correctness, not reinventing data loading or xlsx export.

## Common Pitfalls

### Pitfall 1: Cartesian Explosion Without Keying
**What goes wrong:** Joining single_agent_encounters to all_chemo_encounters without patient_id key creates full cartesian product (every row matched to every other row across ALL patients).

**Why it happens:** Forgetting `on = .(patient_id)` in data.table join, or missing `by = "patient_id"` in dplyr join.

**How to avoid:** Always key on patient_id FIRST, then apply date range filters. Use `allow.cartesian = TRUE` explicitly to signal intentional many-to-many join within patient.

**Warning signs:** Join produces millions of rows when input is thousands; R session hangs during join operation.

### Pitfall 2: Including Regimen-Classified Encounters in Single-Agent Base
**What goes wrong:** Encounters that R/28 already classified as ABVD appear in single-agent analysis, confusing the investigation.

**Why it happens:** Not anti-joining treatment_episodes.rds regimen_label before filtering to single-agent encounters.

**How to avoid:**
```r
# Load regimen classifications from R/28
regimen_episodes <- readRDS("cache/outputs/treatment_episodes.rds") %>%
  filter(!is.na(regimen_label)) %>%
  select(patient_id, episode_number)

# Exclude from detail before single-agent filtering
treatment_detail <- treatment_detail %>%
  anti_join(regimen_episodes, by = c("patient_id", "episode_number"))
```

**Warning signs:** Pattern summary shows "doxorubicin + bleomycin + vincristine" as top pattern (this is ABVD and should already be classified).

### Pitfall 3: Double-Counting Symmetric Pairs (A+B and B+A)
**What goes wrong:** Pattern summary counts "doxorubicin + bleomycin" and "bleomycin + doxorubicin" as separate patterns.

**Why it happens:** Not standardizing drug pair order before grouping.

**How to avoid:** Use `pmin(drug_A, drug_B)` and `pmax(drug_A, drug_B)` to create sorted pairs, or use `paste(sort(c(drug_A, drug_B)), collapse = " + ")`.

**Warning signs:** Pattern summary has duplicate entries that are alphabetically reversed; total count is ~2x expected.

### Pitfall 4: Including Zero-Day Window (Same-Date Matches)
**What goes wrong:** Co-administration pairs include the index encounter's other drugs billed on the same date, which are NOT co-administered drugs (they're part of the same single-agent encounter).

**Why it happens:** Filtering to `abs(days_apart) <= 30` includes days_apart = 0.

**How to avoid:** Use `abs(days_apart) > 0 & abs(days_apart) <= 30`, OR exclude self-matches via `ENCOUNTERID != ENCOUNTERID_coadmin` (which implicitly excludes same-encounter drugs).

**Warning signs:** Detail table shows days_apart = 0 rows; single-agent encounter has co-admin drug with identical treatment_date.

### Pitfall 5: Missing Sub-Category Names for J-Codes Without RxNorm
**What goes wrong:** Triggering codes like J9000 (doxorubicin J-code) have drug_name = NA and don't map to reference xlsx, resulting in blank sub_category_name in output.

**Why it happens:** Reference xlsx may not include all J-codes; R/57 has fallback labels but script needs to replicate this.

**How to avoid:** Use R/57's 3-tier resolution pattern: (1) Reference xlsx, (2) CODE_SUBCATEGORY_MAP, (3) Code-type fallback (e.g., "Chemo HCPCS (no xlsx mapping)").

**Warning signs:** Pattern summary has rows with empty drug names; human reviewers can't interpret "J9000 + J9040" without medication names.

## Code Examples

Verified patterns from project codebase:

### Loading Treatment Episode Detail with Regimen Filter
```r
# Source: R/28 Section 3 (loading) + R/57 Section 2 (validation)
source("R/00_config.R")
source("R/utils/utils_assertions.R")

DETAIL_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")

assert_rds_exists(DETAIL_RDS, script_name = "R/58")
assert_rds_exists(EPISODES_RDS, script_name = "R/58")

detail <- readRDS(DETAIL_RDS)
episodes <- readRDS(EPISODES_RDS)

# Filter to chemotherapy only (D-04)
chemo_detail <- detail %>%
  filter(treatment_type == "Chemotherapy")

# Exclude regimen-classified encounters (D-05)
regimen_encounters <- episodes %>%
  filter(!is.na(regimen_label)) %>%
  select(patient_id, episode_number)

chemo_detail <- chemo_detail %>%
  anti_join(regimen_encounters, by = c("patient_id", "episode_number"))

message(glue("Chemotherapy encounters (excluding regimens): {nrow(chemo_detail)}"))
```

### Identifying Single-Agent Encounters
```r
# Source: R/28 Section 5 regimen detection pattern (n_unique_drugs calculation)
single_agent_base <- chemo_detail %>%
  group_by(patient_id, treatment_date, ENCOUNTERID) %>%
  summarise(
    n_chemo_codes = n_distinct(triggering_code),
    triggering_code = if_else(n_chemo_codes == 1, first(triggering_code), NA_character_),
    drug_name = if_else(n_chemo_codes == 1, first(drug_name), NA_character_),
    episode_number = first(episode_number),
    .groups = "drop"
  ) %>%
  filter(n_chemo_codes == 1)

message(glue("Single-agent encounters identified: {nrow(single_agent_base)}"))
```

### Temporal Self-Join (data.table)
```r
# Source: Phase 95-99 data.table patterns + data.table vignettes
library(data.table)

# Convert to data.table
single_dt <- as.data.table(single_agent_base)
all_chemo_dt <- as.data.table(chemo_detail %>% select(patient_id, treatment_date, triggering_code, drug_name, ENCOUNTERID))

# Cartesian join on patient_id
coadmin_dt <- single_dt[all_chemo_dt,
  on = .(patient_id),
  allow.cartesian = TRUE,
  nomatch = NULL
]

# Filter to ±30-day window, exclude self-matches
coadmin_dt <- coadmin_dt[
  abs(as.numeric(i.treatment_date - treatment_date)) <= 30 &
  abs(as.numeric(i.treatment_date - treatment_date)) > 0 &
  ENCOUNTERID != i.ENCOUNTERID
]

# Add days_apart
coadmin_dt[, days_apart := as.numeric(i.treatment_date - treatment_date)]

# Convert back to tibble for dplyr pipeline
coadmin_pairs <- as_tibble(coadmin_dt)

message(glue("Co-administration pairs found: {nrow(coadmin_pairs)}"))
```

### Building Pattern Summary with Sorted Pairs
```r
# Create symmetric pairs (alphabetical order to avoid A+B / B+A duplication)
pattern_summary <- coadmin_pairs %>%
  mutate(
    # Use sub_category names if available, fall back to triggering_code
    drug_A = coalesce(sub_category_name, triggering_code),
    drug_B = coalesce(i.sub_category_name, i.triggering_code),
    # Sort pair alphabetically
    drug_pair = pmap_chr(list(drug_A, drug_B), ~ paste(sort(c(...)), collapse = " + "))
  ) %>%
  group_by(drug_pair) %>%
  summarise(
    n_instances = n(),
    n_patients = n_distinct(patient_id),
    .groups = "drop"
  ) %>%
  arrange(desc(n_instances))

message(glue("Unique drug pair patterns: {nrow(pattern_summary)}"))
message(glue("Top pattern: {pattern_summary$drug_pair[1]} ({pattern_summary$n_instances[1]} instances)"))
```

### Multi-Sheet XLSX Output (openxlsx2)
```r
# Source: R/57 Section 7 (Phase 101 dual-output pattern)
library(openxlsx2)

OUTPUT_XLSX <- file.path(CONFIG$output_dir, "co_administration_analysis.xlsx")

wb <- wb_workbook()

# Sheet 1: Co-Administration Detail (COADMIN-01)
wb$add_worksheet("Co-Administration Detail")
wb$add_data("Co-Administration Detail", coadmin_detail, start_row = 1, col_names = TRUE)

# Sheet 2: Pattern Summary (COADMIN-02)
wb$add_worksheet("Pattern Summary")
wb$add_data("Pattern Summary", pattern_summary, start_row = 1, col_names = TRUE)

wb$save(OUTPUT_XLSX)

message(glue("Saved output: {OUTPUT_XLSX}"))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Base R loops for temporal joins | data.table keyed joins with IDate | Phase 95-99 (v3.0) | 10-50x performance improvement on hot paths; project adopted data.table for all lookup-heavy operations |
| xlsx package (archived 2017) | openxlsx2 (R6-based) | Phase 88 (v2.0) | Modern API with method chaining (`wb$add_worksheet()`); maintained and actively developed |
| dplyr 1.0.x mutating joins | dplyr 1.2.0 non-equi joins with join_by() | Feb 2026 release | Temporal joins possible in pure dplyr, but data.table still faster for this use case |

**Deprecated/outdated:**
- **xlsx package:** Archived on CRAN; use openxlsx2 instead
- **tibbletime package:** No longer maintained; use lubridate + dplyr for time-based filtering
- **Base R `merge()` for large tables:** Replaced by data.table joins for performance

## Open Questions

1. **Should cancer_linked flag from Phase 101 be included in co-administration detail?**
   - What we know: R/57 (Phase 101) added cancer_linked flag to encounter-level tables
   - What's unclear: Whether co-administration analysis needs to stratify by cancer-linked vs unlinked
   - Recommendation: Include cancer_linked in detail table (easy filter for users), omit from pattern summary (too granular). Marked as Claude's Discretion in CONTEXT.md.

2. **Should pattern summary be limited to top N patterns or show all?**
   - What we know: Pattern summary is for exploratory analysis (success criteria: "most common pairings ranked by frequency")
   - What's unclear: Whether to cap at 50, 100, or show all pairs
   - Recommendation: Show all pairs (sortable in Excel), add console message showing top 10. Limiting to top N loses long-tail patterns that might be clinically interesting.

3. **Should days_apart be signed (negative = before index, positive = after) or absolute?**
   - What we know: D-07 specifies "days_apart for temporal analysis"; D-03 specifies "30 days before or after"
   - What's unclear: Whether temporal direction matters for fragmented billing detection
   - Recommendation: Use **signed days_apart** (negative = co-admin occurred before index encounter). Preserves temporal ordering for users who want to analyze sequence patterns.

## Validation Architecture

> nyquist_validation is explicitly set to false in .planning/config.json — validation section omitted per protocol.

## Sources

### Primary (HIGH confidence)
- Project codebase: R/57_drug_grouping_instances.R (Section 2-3 data loading, Section 7 openxlsx2 output)
- Project codebase: R/28_episode_classification.R (Section 5 regimen detection, n_unique_drugs pattern)
- Project codebase: R/utils/utils_dt.R (ensure_dt, to_tibble_safe, data.table conversion patterns from Phase 95-99)
- Project codebase: R/00_config.R (CONFIG paths, TREATMENT_CODES, CODE_SUBCATEGORY_MAP)
- Project CLAUDE.md: Technology Stack section — data.table 1.16.2+, dplyr 1.2.0+, openxlsx2 verified as project standard

### Secondary (MEDIUM confidence)
- [data.table CRAN manual (v1.18.4, May 2026)](https://cran.r-project.org/web/packages/data.table/data.table.pdf) — IDate efficiency, rolling joins
- [Joins in data.table vignette](https://cran.r-project.org/web/packages/data.table/vignettes/datatable-joins.html) — Keyed join syntax, cartesian join patterns
- [dplyr 1.2.0 release notes (Feb 2026)](https://tidyverse.org/blog/2026/02/dplyr-1-2-0/) — Non-equi joins with join_by() helper
- [openxlsx2 reference manual](https://cran.r-universe.dev/openxlsx2/doc/manual.html) — wb_workbook(), add_worksheet(), add_data() API

### Tertiary (LOW confidence)
- [Temporal joins blog post (Crunchy Data)](https://www.crunchydata.com/blog/temporal-joins) — General concept, not R-specific
- [Chemotherapy billing guidelines 2026](https://annexmed.com/oncology-coding-billing-guidelines) — Fragmented billing context, not analysis methods

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already in project (verified via R/00_config.R, CLAUDE.md, and Phase 95-101 code)
- Architecture: HIGH - Reusing established patterns from R/57 (data loading, xlsx output), R/28 (regimen detection), Phase 95-99 (data.table joins)
- Pitfalls: HIGH - Derived from project-specific constraints (D-01 through D-10) and data.table join semantics (cartesian explosion, self-match exclusion)

**Research date:** 2026-06-12
**Valid until:** 2026-07-12 (30 days; stable domain with existing project patterns)
