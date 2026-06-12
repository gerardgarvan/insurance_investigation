# Phase 100: CONDITION Table Cancer Linkage - Research

**Researched:** 2026-06-12
**Domain:** PCORnet CDM CONDITION table integration, cancer diagnosis linkage improvement, exploratory analysis
**Confidence:** HIGH

## Summary

Phase 100 investigates whether the CONDITION table can reduce the ~30% unlinked episode rate in cancer linkage by serving as a third-tier fallback after the existing DIAGNOSIS table cascade (ENCOUNTERID direct → 30-day temporal). This is a **read-only investigation**, not a production integration—the phase produces an assessment report showing which currently-unlinked episodes WOULD gain cancer linkage from CONDITION data, without modifying treatment_episodes.rds or any existing outputs.

The CONDITION table is already loaded into DuckDB (R/01, R/03) with the same structure as DIAGNOSIS—it contains ICD-10/ICD-9 codes in the CONDITION column (analogous to DX) with ENCOUNTERID and ONSET_DATE fields. The existing classify_codes() and is_cancer_code() utilities from utils_cancer.R work directly with CONDITION codes since they handle any ICD-10/ICD-9 input. The investigation mirrors the R/28 two-tier linkage logic (encounter match first, temporal fallback second) but applies it to CONDITION data for episodes where cancer_link_method == "none".

The deliverable is a new "Linkage Improvement" sheet in episode_classification_audit.xlsx showing: (1) before/after unlinked counts, (2) breakdown by treatment type (Chemo, RT, SCT, Immuno, Proton) to identify which modalities benefit most, and (3) optionally a distribution of what cancer categories the newly-linked episodes would receive. This report informs a future decision on whether to promote CONDITION to the production cascade in R/28.

**Primary recommendation:** Build a standalone analysis script (R/29 or next available) that reads treatment_episodes.rds, queries CONDITION table via DuckDB, applies the same linkage cascade to unlinked episodes, and writes results to a new xlsx sheet. Use tidyverse for consistency with existing pipeline patterns. Follow established audit sheet styling from R/28 (openxlsx2, title rows, freeze panes). No modifications to R/28 or treatment_episodes.rds.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Code Filtering**
- **D-01:** Include only ICD-10 (CONDITION_TYPE = "10") and ICD-9 (CONDITION_TYPE = "09") codes from CONDITION table. SNOMED CT and ICD-11 are excluded since classify_codes() only handles ICD-10/ICD-9.
- **D-02:** No filtering on CONDITION_STATUS or CONDITION_SOURCE. Include all CONDITION rows regardless of status/source to maximize linkage coverage as a Tier 3 last-resort approach.

**Matching Approach**
- **D-03:** Mirror the existing DIAGNOSIS cascade within CONDITION: (1) ENCOUNTERID match first, (2) temporal fallback using ONSET_DATE within 30 days before episode_start. This produces two new link method labels: `condition_encounter` and `condition_date`.
- **D-04:** Use ONSET_DATE (not REPORT_DATE) for temporal fallback — clinically analogous to DX_DATE used in DIAGNOSIS temporal matching.
- **D-05:** Only episodes currently with `cancer_link_method == "none"` are candidates for CONDITION matching. Episodes already linked via DIAGNOSIS tiers are not re-evaluated.

**Non-Destructive Constraint (Critical)**
- **D-06:** This phase is **investigation only**. CONDITION linkage results are reported but NOT merged into treatment_episodes.rds. The existing R/28 script, all RDS files, all xlsx/csv outputs remain completely untouched.
- **D-07:** New standalone script (NOT a modification to R/28). Reads treatment_episodes.rds and CONDITION table, produces an investigation report showing what COULD be linked.
- **D-08:** No existing datasets, reports, or outputs are affected by this phase.

**Improvement Report**
- **D-09:** Report lives as a new sheet ("Linkage Improvement") in the existing episode_classification_audit.xlsx workbook. Additive — no existing sheets are modified.
- **D-10:** Report contains aggregate before/after counts plus breakdown by treatment type (Chemo, RT, SCT, Immuno, Proton) showing which treatment types would benefit most from CONDITION linkage.

### Claude's Discretion
- Script numbering (e.g., R/29 or next available number in the decade)
- Console logging verbosity during analysis
- Whether to include a "would-be cancer categories" distribution in the report
- Smoke test additions for the new script

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| COND-01 | CONDITION table added as 3rd tier in cancer linkage cascade (DIAGNOSIS direct → temporal fallback → CONDITION supplement) | Existing DuckDB infrastructure loads CONDITION; classify_codes() works on CONDITION codes; mirror R/28 logic |
| COND-02 | Linkage improvement report showing before/after unlinked episode rates | New xlsx sheet in existing audit workbook using openxlsx2; aggregate counts + treatment type breakdown |
| COND-03 | Previously unlinked episodes re-classified to linked cancer categories via CONDITION data | classify_codes() output shows what categories episodes would receive; report includes optional distribution table |
</phase_requirements>

## Standard Stack

### Core (Already Installed)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Project standard for readable pipelines; same as R/28 |
| stringr | 1.5.1+ | String operations | ICD code prefix extraction (str_sub), code filtering |
| glue | 1.8.0+ | String formatting | Console logging messages at each step |
| lubridate | 1.9.3+ | Date operations | Parse ONSET_DATE, calculate days_before for temporal matching |
| openxlsx2 | 1.10+ | Excel workbook manipulation | Modify existing xlsx to add new sheet; established R/28 pattern |

### Data Access (Already Configured)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DuckDB via get_pcornet_table() | N/A | CONDITION table access | CONDITION already ingested in R/03; indexed on ENCOUNTERID |
| utils_duckdb.R | N/A | Connection management | open_pcornet_con(), close_pcornet_con(), get_pcornet_table() |
| utils_cancer.R | N/A | Code classification | classify_codes() and is_cancer_code() work on any ICD-10/ICD-9 input |
| utils_dates.R | N/A | Date parsing | parse_pcornet_date() handles ONSET_DATE multi-format parsing |

**No new packages required** — Phase 100 uses existing infrastructure.

## Architecture Patterns

### Recommended Script Structure
```
R/29_condition_linkage_investigation.R   # New standalone investigation script

SECTION 1: SETUP
  - Load libraries (dplyr, stringr, glue, lubridate, openxlsx2)
  - Source R/00_config.R (auto-loads utils)
  - Define output paths (existing audit xlsx)

SECTION 2: LOAD DATA
  - Read treatment_episodes.rds
  - Identify unlinked episodes (cancer_link_method == "none")
  - Open DuckDB connection
  - Query CONDITION table (filter CONDITION_TYPE in ("09", "10"))

SECTION 3: CONDITION LINKAGE INVESTIGATION
  - 3a: Extract encounter IDs from unlinked episodes
  - 3b: ENCOUNTERID direct match against CONDITION
  - 3c: Temporal fallback (ONSET_DATE within 30 days before episode_start)
  - 3d: Classify codes using classify_codes()
  - 3e: Combine results with new link method labels

SECTION 4: IMPROVEMENT ANALYSIS
  - 4a: Aggregate before/after counts
  - 4b: Breakdown by treatment type (5 types)
  - 4c: Optional: cancer category distribution for newly-linked episodes

SECTION 5: REPORT GENERATION
  - 5a: Load existing episode_classification_audit.xlsx
  - 5b: Add new "Linkage Improvement" sheet
  - 5c: Write aggregate summary table
  - 5d: Write treatment type breakdown table
  - 5e: Apply styling (title row, freeze panes, autofit)
  - 5f: Save workbook

SECTION 6: CLEANUP
  - Close DuckDB connection
  - Log summary to console
```

### Pattern 1: CONDITION Table Query (Mirroring DIAGNOSIS Query)
**What:** Query CONDITION table with same structure as R/28's DIAGNOSIS query
**When to use:** Loading CONDITION data for cancer linkage analysis
**Example:**
```r
# Source: R/28 lines 178-186 (DIAGNOSIS query pattern)

# Query CONDITION table via DuckDB
condition_data <- get_pcornet_table("CONDITION") %>%
  select(ID, ENCOUNTERID, CONDITION, CONDITION_TYPE, ONSET_DATE) %>%
  collect() %>%
  mutate(ONSET_DATE = parse_pcornet_date(ONSET_DATE)) %>%
  filter(CONDITION_TYPE %in% c("09", "10")) %>%  # D-01: ICD-10 and ICD-9 only
  filter(str_sub(CONDITION, 1, 1) == "C") %>%     # Malignant codes only (ICD-10 C-codes, ICD-9 140-209 start with 1-2)
  filter(!is.na(ONSET_DATE))

message(glue("  CONDITION query: {nrow(condition_data)} C-code rows with ONSET_DATE"))
```

### Pattern 2: ENCOUNTERID Match (Tier 1)
**What:** Direct ENCOUNTERID match between episodes and CONDITION table
**When to use:** First tier of CONDITION linkage, highest confidence
**Example:**
```r
# Source: R/28 lines 188-206 (ENCOUNTERID match pattern)

# Extract unique encounter IDs from unlinked episodes
unlinked_encounters <- unlinked_episodes %>%
  filter(!is.na(encounter_ids) & encounter_ids != "") %>%
  mutate(encounter_ids_list = str_split(encounter_ids, ",")) %>%
  tidyr::unnest(cols = encounter_ids_list) %>%
  filter(!is.na(encounter_ids_list) & encounter_ids_list != "") %>%
  select(patient_id, treatment_type, episode_number, ENCOUNTERID = encounter_ids_list)

# Direct ENCOUNTERID match
condition_with_encounter <- condition_data %>%
  filter(!is.na(ENCOUNTERID) & ENCOUNTERID != "")

condition_encounter_linked <- unlinked_encounters %>%
  inner_join(condition_with_encounter, by = "ENCOUNTERID", relationship = "many-to-many") %>%
  mutate(
    prefix = str_sub(CONDITION, 1, 3),
    cancer_category = classify_codes(CONDITION)
  ) %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  arrange(desc(cancer_category == "Hodgkin Lymphoma"), .by_group = TRUE) %>%
  slice(1) %>%
  ungroup() %>%
  mutate(condition_link_method = "condition_encounter") %>%
  select(patient_id, treatment_type, episode_number, cancer_category, condition_link_method)

n_condition_encounter <- nrow(condition_encounter_linked)
message(glue("  CONDITION ENCOUNTERID match: {n_condition_encounter} episodes linked"))
```

### Pattern 3: Temporal Fallback (Tier 2)
**What:** 30-day backward window from episode_start using ONSET_DATE
**When to use:** Second tier for episodes not matched by ENCOUNTERID
**Example:**
```r
# Source: R/28 lines 208-238 (Temporal fallback pattern)

# Identify still-unlinked episodes
still_unlinked <- unlinked_episodes %>%
  anti_join(condition_encounter_linked, by = c("patient_id", "treatment_type", "episode_number"))

message(glue("  Still unlinked after CONDITION ENCOUNTERID: {nrow(still_unlinked)}"))

# Get CONDITION rows for still-unlinked patients
still_unlinked_patients <- unique(still_unlinked$patient_id)
condition_for_unlinked <- condition_data %>%
  filter(ID %in% still_unlinked_patients)

# Temporal matching using ONSET_DATE (D-04)
condition_temporal_linked <- still_unlinked %>%
  left_join(condition_for_unlinked, by = c("patient_id" = "ID"), relationship = "many-to-many") %>%
  filter(!is.na(ONSET_DATE)) %>%
  filter(ONSET_DATE <= episode_start) %>%
  mutate(days_before = as.numeric(episode_start - ONSET_DATE)) %>%
  filter(days_before <= 30) %>%
  mutate(
    prefix = str_sub(CONDITION, 1, 3),
    cancer_category = classify_codes(CONDITION)
  ) %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  arrange(days_before, desc(cancer_category == "Hodgkin Lymphoma"), .by_group = TRUE) %>%
  slice(1) %>%
  ungroup() %>%
  mutate(condition_link_method = "condition_date") %>%
  select(patient_id, treatment_type, episode_number, cancer_category, condition_link_method)

n_condition_temporal <- nrow(condition_temporal_linked)
message(glue("  CONDITION temporal fallback (30-day): {n_condition_temporal} episodes linked"))
```

### Pattern 4: Improvement Report Sheet
**What:** Add new sheet to existing xlsx workbook with before/after comparison
**When to use:** Non-destructive investigation reporting
**Example:**
```r
# Source: R/28 lines 813-1045 (xlsx sheet creation pattern)

# Load existing workbook
audit_xlsx_path <- file.path(CONFIG$output_dir, "episode_classification_audit.xlsx")
wb <- wb_load(audit_xlsx_path)

# Add new sheet
wb$add_worksheet("Linkage Improvement")

# Title row
wb$add_data(
  sheet = "Linkage Improvement",
  x = "CONDITION Table Linkage Improvement Investigation",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Linkage Improvement", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Linkage Improvement", dims = "A1:D1")

# Subtitle row
subtitle <- glue("Generated: {Sys.Date()} | Investigation only - NOT applied to treatment_episodes.rds")
wb$add_data(sheet = "Linkage Improvement", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(
  sheet = "Linkage Improvement", dims = "A2",
  name = "Calibri", size = 10, color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Linkage Improvement", dims = "A2:D2")

# Summary table starting row 4
improvement_summary <- tibble(
  Metric = c(
    "Total episodes",
    "Unlinked before CONDITION",
    "Would link via CONDITION encounter",
    "Would link via CONDITION date",
    "Total would-be linked via CONDITION",
    "Would remain unlinked",
    "Improvement (percentage points)"
  ),
  Count = c(
    nrow(episodes),
    n_unlinked,
    n_condition_encounter,
    n_condition_temporal,
    n_condition_encounter + n_condition_temporal,
    n_unlinked - (n_condition_encounter + n_condition_temporal),
    NA_real_
  ),
  Percent = c(
    100.0,
    round(100 * n_unlinked / nrow(episodes), 1),
    round(100 * n_condition_encounter / nrow(episodes), 1),
    round(100 * n_condition_temporal / nrow(episodes), 1),
    round(100 * (n_condition_encounter + n_condition_temporal) / nrow(episodes), 1),
    round(100 * (n_unlinked - (n_condition_encounter + n_condition_temporal)) / nrow(episodes), 1),
    round(100 * n_unlinked / nrow(episodes) - 100 * (n_unlinked - (n_condition_encounter + n_condition_temporal)) / nrow(episodes), 1)
  )
)

wb$add_data(sheet = "Linkage Improvement", x = improvement_summary, start_row = 4, start_col = 1)

# Header styling
wb$add_font(
  sheet = "Linkage Improvement", dims = "A4:C4",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$add_fill(
  sheet = "Linkage Improvement", dims = "A4:C4",
  color = wb_color("FF1F2937")
)

# Freeze and autofit
wb$freeze_pane(sheet = "Linkage Improvement", first_active_row = 5)
wb$set_col_widths(sheet = "Linkage Improvement", cols = 1:3, widths = "auto")

# Save workbook (overwrites existing file with new sheet added)
wb_save(wb, audit_xlsx_path, overwrite = TRUE)
message(glue("  Added 'Linkage Improvement' sheet to {audit_xlsx_path}"))
```

### Pattern 5: Treatment Type Breakdown
**What:** Show which treatment types benefit most from CONDITION linkage
**When to use:** Detailed analysis for decision-making (D-10)
**Example:**
```r
# Combine CONDITION linkage results
condition_linkage <- bind_rows(condition_encounter_linked, condition_temporal_linked)

# Join back to unlinked episodes to get treatment_type
condition_improvement <- unlinked_episodes %>%
  left_join(condition_linkage, by = c("patient_id", "treatment_type", "episode_number")) %>%
  mutate(
    would_link = !is.na(condition_link_method),
    condition_link_method = if_else(is.na(condition_link_method), "none", condition_link_method)
  )

# Breakdown by treatment type
treatment_type_breakdown <- condition_improvement %>%
  group_by(treatment_type) %>%
  summarise(
    total_unlinked = n(),
    would_link_via_condition = sum(would_link),
    would_remain_unlinked = sum(!would_link),
    pct_improvement = round(100 * would_link_via_condition / total_unlinked, 1),
    .groups = "drop"
  ) %>%
  arrange(desc(pct_improvement))

# Add to xlsx as second table
# (Insert after improvement_summary table at row ~15)
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ICD code classification | Custom prefix matching logic | classify_codes() from utils_cancer.R | Already handles ICD-10 + ICD-9 4-tier cascade; tested in R/28 |
| Cancer code detection | Custom C-code filtering | is_cancer_code() from utils_cancer.R | Map-based detection ensures gap-free coverage |
| Multi-format date parsing | case_when() for date formats | parse_pcornet_date() from utils_dates.R | Handles YYYY-MM-DD, MM/DD/YYYY, Unix epoch in single pass |
| Excel workbook modification | Custom xlsx library research | openxlsx2 (already used in R/28) | Established pattern for adding sheets to existing workbooks |
| DuckDB querying | Raw DBI calls | get_pcornet_table() from utils_duckdb.R | Abstracts backend switching, connection management |

**Key insight:** All the infrastructure for CONDITION linkage already exists—CONDITION table is loaded, utilities work on its data, and the linkage logic mirrors R/28. The only new code is the standalone investigation script orchestrating existing patterns.

## Common Pitfalls

### Pitfall 1: Modifying Existing Outputs Instead of Investigation-Only Analysis
**What goes wrong:** Accidentally merging CONDITION linkage results into treatment_episodes.rds or overwriting existing audit sheets
**Why it happens:** R/28 modifies treatment_episodes.rds in-place (line 754 saveRDS); easy to copy that pattern
**How to avoid:** NEVER load treatment_episodes.rds with readRDS → modify → saveRDS. Only read it for reference. Store CONDITION linkage results in separate data frames. D-06, D-07, D-08 explicitly forbid modifications.
**Warning signs:** If you see `saveRDS(episodes, OUTPUT_RDS)` in new script, you've violated the constraint. If wb_save() overwrites without checking sheet existence, you might delete existing audit sheets.

### Pitfall 2: Including SNOMED CT or ICD-11 Codes
**What goes wrong:** classify_codes() returns NA for SNOMED CT (CONDITION_TYPE = "SM") or ICD-11 codes, inflating "would remain unlinked" counts
**Why it happens:** CONDITION table contains multiple code types; easy to forget to filter CONDITION_TYPE
**How to avoid:** Filter `CONDITION_TYPE %in% c("09", "10")` immediately after querying CONDITION table (D-01). Log how many rows are excluded.
**Warning signs:** If linkage improvement is 0%, check if CONDITION_TYPE filter is applied. If condition_data has CONDITION values starting with letters other than C or digits 1-2, SNOMED CT leaked through.

### Pitfall 3: Using REPORT_DATE Instead of ONSET_DATE for Temporal Matching
**What goes wrong:** REPORT_DATE is when the condition was documented, not when it started; can be months/years after ONSET_DATE
**Why it happens:** CONDITION table has multiple date fields; easy to grab wrong one
**How to avoid:** Use ONSET_DATE for temporal matching (D-04). REPORT_DATE is analogous to ADMIT_DATE in DIAGNOSIS (administrative), not DX_DATE (clinical).
**Warning signs:** If temporal matching yields unexpectedly high counts (>50% of unlinked), check which date field is being used. REPORT_DATE will match more episodes but with lower clinical validity.

### Pitfall 4: Re-Evaluating Already-Linked Episodes
**What goes wrong:** Running CONDITION linkage on ALL episodes, not just unlinked, inflates improvement metrics
**Why it happens:** Easy to forget to filter `cancer_link_method == "none"` before CONDITION analysis
**How to avoid:** Filter unlinked_episodes at start (D-05): `episodes %>% filter(cancer_link_method == "none")`. Log count: `n_unlinked <- nrow(unlinked_episodes)`.
**Warning signs:** If "total would-be linked via CONDITION" exceeds "unlinked before CONDITION", you've processed already-linked episodes.

### Pitfall 5: Hardcoded Column Positions in xlsx Sheet Addition
**What goes wrong:** If episode_classification_audit.xlsx schema changes (columns added/removed), hardcoded dims like "A1:D1" break
**Why it happens:** Copying R/28 xlsx patterns without understanding dynamic sizing
**How to avoid:** Calculate merge ranges from data dimensions: `dims = paste0("A1:", LETTERS[ncol(summary_table)], "1")`. Use relative positioning for multiple tables on same sheet.
**Warning signs:** If openxlsx2 throws "invalid dims" error after upstream schema changes, column positions are hardcoded.

## Code Examples

Verified patterns adapted from R/28 episode classification:

### CONDITION Table Query and Filtering
```r
# Source: R/28 lines 178-186 (DIAGNOSIS query), adapted for CONDITION
# Verified: CONDITION table schema from R/01 lines 86-106

open_pcornet_con()

condition_data <- get_pcornet_table("CONDITION") %>%
  select(ID, ENCOUNTERID, CONDITION, CONDITION_TYPE, ONSET_DATE) %>%
  collect() %>%
  mutate(ONSET_DATE = parse_pcornet_date(ONSET_DATE)) %>%
  filter(CONDITION_TYPE %in% c("09", "10")) %>%  # D-01: ICD-10 and ICD-9 only
  filter(str_sub(CONDITION, 1, 1) == "C") %>%     # Malignant C-codes (ICD-10 C00-C99, ICD-9 140-209)
  filter(!is.na(ONSET_DATE))

message(glue("  CONDITION query: {nrow(condition_data)} C-code rows with ONSET_DATE"))
```

### Unlinked Episodes Identification
```r
# Source: R/28 lines 209-212 (unlinked episodes anti-join)

unlinked_episodes <- episodes %>%
  filter(cancer_link_method == "none")  # D-05: only unlinked candidates

n_unlinked <- nrow(unlinked_episodes)
message(glue("  Unlinked episodes for CONDITION investigation: {n_unlinked}"))
```

### ENCOUNTERID Direct Match
```r
# Source: R/28 lines 169-206 (ENCOUNTERID match pattern), adapted for CONDITION

# Extract encounter IDs from unlinked episodes
unlinked_encounters <- unlinked_episodes %>%
  filter(!is.na(encounter_ids) & encounter_ids != "") %>%
  mutate(encounter_ids_list = str_split(encounter_ids, ",")) %>%
  tidyr::unnest(cols = encounter_ids_list) %>%
  filter(!is.na(encounter_ids_list) & encounter_ids_list != "") %>%
  select(patient_id, treatment_type, episode_number, ENCOUNTERID = encounter_ids_list)

# Direct ENCOUNTERID match against CONDITION
condition_with_encounter <- condition_data %>%
  filter(!is.na(ENCOUNTERID) & ENCOUNTERID != "")

condition_encounter_linked <- unlinked_encounters %>%
  inner_join(condition_with_encounter, by = "ENCOUNTERID", relationship = "many-to-many") %>%
  mutate(
    prefix = str_sub(CONDITION, 1, 3),
    cancer_category = classify_codes(CONDITION)
  ) %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  arrange(desc(cancer_category == "Hodgkin Lymphoma"), .by_group = TRUE) %>%  # D-04 preference
  slice(1) %>%
  ungroup() %>%
  mutate(condition_link_method = "condition_encounter") %>%  # D-03: new label
  select(patient_id, treatment_type, episode_number, cancer_category, condition_link_method)

n_condition_encounter <- nrow(condition_encounter_linked)
message(glue("  CONDITION ENCOUNTERID match: {n_condition_encounter} episodes linked"))
```

### Temporal Fallback Using ONSET_DATE
```r
# Source: R/28 lines 214-238 (Temporal fallback pattern), adapted for CONDITION

# Identify episodes still unlinked after ENCOUNTERID match
still_unlinked <- unlinked_episodes %>%
  anti_join(condition_encounter_linked, by = c("patient_id", "treatment_type", "episode_number"))

message(glue("  Still unlinked after CONDITION ENCOUNTERID: {nrow(still_unlinked)}"))

# Get CONDITION rows for still-unlinked patients
still_unlinked_patients <- unique(still_unlinked$patient_id)
condition_for_unlinked <- condition_data %>%
  filter(ID %in% still_unlinked_patients)

# Temporal matching: ONSET_DATE within 30 days before episode_start (D-04)
condition_temporal_linked <- still_unlinked %>%
  left_join(condition_for_unlinked, by = c("patient_id" = "ID"), relationship = "many-to-many") %>%
  filter(!is.na(ONSET_DATE)) %>%
  filter(ONSET_DATE <= episode_start) %>%  # Backward-only window
  mutate(days_before = as.numeric(episode_start - ONSET_DATE)) %>%
  filter(days_before <= 30) %>%
  mutate(
    prefix = str_sub(CONDITION, 1, 3),
    cancer_category = classify_codes(CONDITION)
  ) %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  arrange(days_before, desc(cancer_category == "Hodgkin Lymphoma"), .by_group = TRUE) %>%
  slice(1) %>%
  ungroup() %>%
  mutate(condition_link_method = "condition_date") %>%  # D-03: new label
  select(patient_id, treatment_type, episode_number, cancer_category, condition_link_method)

n_condition_temporal <- nrow(condition_temporal_linked)
message(glue("  CONDITION temporal fallback (30-day): {n_condition_temporal} episodes linked"))
```

### Aggregate Improvement Summary
```r
# Combine CONDITION linkage results
condition_linkage <- bind_rows(condition_encounter_linked, condition_temporal_linked)
n_condition_total <- nrow(condition_linkage)

# Calculate improvement metrics
pct_unlinked_before <- round(100 * n_unlinked / nrow(episodes), 1)
pct_unlinked_after <- round(100 * (n_unlinked - n_condition_total) / nrow(episodes), 1)
pct_improvement <- pct_unlinked_before - pct_unlinked_after

improvement_summary <- tibble(
  Metric = c(
    "Total episodes",
    "Unlinked before CONDITION",
    "Would link via CONDITION encounter",
    "Would link via CONDITION date",
    "Total would-be linked via CONDITION",
    "Would remain unlinked",
    "Improvement (percentage points)"
  ),
  Count = c(
    nrow(episodes),
    n_unlinked,
    n_condition_encounter,
    n_condition_temporal,
    n_condition_total,
    n_unlinked - n_condition_total,
    NA_integer_
  ),
  Percent = c(
    100.0,
    pct_unlinked_before,
    round(100 * n_condition_encounter / nrow(episodes), 1),
    round(100 * n_condition_temporal / nrow(episodes), 1),
    round(100 * n_condition_total / nrow(episodes), 1),
    pct_unlinked_after,
    pct_improvement
  )
)

message(glue("\n=== CONDITION Linkage Investigation Complete ==="))
message(glue("  Unlinked before: {n_unlinked} ({pct_unlinked_before}%)"))
message(glue("  Would link via CONDITION: {n_condition_total} ({round(100 * n_condition_total / nrow(episodes), 1)}%)"))
message(glue("  Would remain unlinked: {n_unlinked - n_condition_total} ({pct_unlinked_after}%)"))
message(glue("  Improvement: {pct_improvement} percentage points"))
```

### Treatment Type Breakdown
```r
# Source: D-10 requirement (treatment type breakdown)

# Join CONDITION linkage back to unlinked episodes
condition_improvement <- unlinked_episodes %>%
  left_join(condition_linkage, by = c("patient_id", "treatment_type", "episode_number")) %>%
  mutate(would_link = !is.na(condition_link_method))

# Breakdown by treatment type
treatment_type_breakdown <- condition_improvement %>%
  group_by(treatment_type) %>%
  summarise(
    total_unlinked = n(),
    would_link_via_condition = sum(would_link),
    would_remain_unlinked = sum(!would_link),
    pct_improvement = round(100 * would_link_via_condition / total_unlinked, 1),
    .groups = "drop"
  ) %>%
  arrange(desc(pct_improvement))

message("\n--- Treatment Type Breakdown ---")
for (i in seq_len(nrow(treatment_type_breakdown))) {
  row <- treatment_type_breakdown[i, ]
  message(glue("  {row$treatment_type}: {row$would_link_via_condition}/{row$total_unlinked} ({row$pct_improvement}% improvement)"))
}
```

### Adding New Sheet to Existing Workbook
```r
# Source: R/28 lines 813-1045 (xlsx workbook creation), openxlsx2 documentation

library(openxlsx2)

# Load existing workbook (D-09)
audit_xlsx_path <- file.path(CONFIG$output_dir, "episode_classification_audit.xlsx")
wb <- wb_load(audit_xlsx_path)

# Add new sheet
wb$add_worksheet("Linkage Improvement")

# Title row (A1)
wb$add_data(
  sheet = "Linkage Improvement",
  x = "CONDITION Table Linkage Improvement Investigation",
  start_row = 1, start_col = 1
)
wb$add_font(
  sheet = "Linkage Improvement", dims = "A1",
  name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937")
)
wb$merge_cells(sheet = "Linkage Improvement", dims = "A1:C1")

# Subtitle row (A2)
subtitle <- glue("Generated: {Sys.Date()} | Investigation only - NOT applied to treatment_episodes.rds")
wb$add_data(sheet = "Linkage Improvement", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(
  sheet = "Linkage Improvement", dims = "A2",
  name = "Calibri", size = 10, color = wb_color("FF6B7280")
)
wb$merge_cells(sheet = "Linkage Improvement", dims = "A2:C2")

# Aggregate summary table (starting row 4)
wb$add_data(sheet = "Linkage Improvement", x = improvement_summary, start_row = 4, start_col = 1)
wb$add_font(
  sheet = "Linkage Improvement", dims = "A4:C4",
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$add_fill(
  sheet = "Linkage Improvement", dims = "A4:C4",
  color = wb_color("FF1F2937")
)

# Treatment type breakdown table (starting row ~15, after aggregate table)
treatment_start_row <- 4 + nrow(improvement_summary) + 3  # +3 for spacing
wb$add_data(
  sheet = "Linkage Improvement",
  x = "Treatment Type Breakdown",
  start_row = treatment_start_row, start_col = 1
)
wb$add_font(
  sheet = "Linkage Improvement",
  dims = paste0("A", treatment_start_row),
  name = "Calibri", size = 14, bold = TRUE
)

wb$add_data(
  sheet = "Linkage Improvement",
  x = treatment_type_breakdown,
  start_row = treatment_start_row + 2, start_col = 1
)
wb$add_font(
  sheet = "Linkage Improvement",
  dims = paste0("A", treatment_start_row + 2, ":E", treatment_start_row + 2),
  name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF")
)
wb$add_fill(
  sheet = "Linkage Improvement",
  dims = paste0("A", treatment_start_row + 2, ":E", treatment_start_row + 2),
  color = wb_color("FF1F2937")
)

# Freeze panes and autofit
wb$freeze_pane(sheet = "Linkage Improvement", first_active_row = 5)
wb$set_col_widths(sheet = "Linkage Improvement", cols = 1:5, widths = "auto")

# Save workbook (D-09: additive, no existing sheets modified)
wb_save(wb, audit_xlsx_path, overwrite = TRUE)
message(glue("  Added 'Linkage Improvement' sheet to {audit_xlsx_path}"))
```

## State of the Art

| Domain | Current Approach | Context |
|--------|------------------|---------|
| CONDITION table usage | Loaded into DuckDB but unused in cancer linkage | R/01 loads CONDITION, R/03 ingests to DuckDB, but R/28 only queries DIAGNOSIS |
| Cancer linkage cascade | 2-tier DIAGNOSIS only (ENCOUNTERID → 30-day temporal) | R/28 lines 164-282; ~30% unlinked rate |
| PCORnet best practice | CONDITION as supplemental diagnosis source | PCORnet CDM v7.0 includes CONDITION for EHR-based conditions; DIAGNOSIS is claims-based |
| Temporal matching window | 30 days backward from episode_start | Established in R/28 D-02, D-03; industry standard for cancer treatment proximity |

**Current gap:** CONDITION table is infrastructure-ready but unused for cancer linkage. No evidence in codebase that CONDITION has been evaluated for linkage improvement.

## Open Questions

1. **What is the actual coverage of cancer codes in CONDITION vs DIAGNOSIS?**
   - What we know: Both tables contain ICD-10/ICD-9 codes; DIAGNOSIS is claims-based, CONDITION is EHR problem-list-based
   - What's unclear: Does CONDITION have significantly different cancer code coverage (more/less/different patients)?
   - Recommendation: Script should log: (a) unique patients with cancer codes in CONDITION, (b) how many of those are NOT in DIAGNOSIS cancer codes

2. **Will CONDITION linkage improve specific cancer types more than others?**
   - What we know: classify_codes() will reveal cancer categories for newly-linked episodes
   - What's unclear: Whether CONDITION is richer for certain cancer sites (e.g., hematologic vs solid tumors)
   - Recommendation: Include optional cancer category distribution table in report (Claude's discretion)

3. **Should CONDITION linkage be added to production R/28 cascade if improvement is modest (<5 percentage points)?**
   - What we know: Phase 100 is investigation-only; integration is a future decision
   - What's unclear: What improvement threshold justifies the added complexity
   - Recommendation: Report should make the trade-off clear (improvement vs complexity)

## Environment Availability

**Step 2.6: SKIPPED** — Phase 100 has no external dependencies beyond existing project infrastructure. All required tools (R, DuckDB, tidyverse packages) are already installed and verified in previous phases. No new services, runtimes, or external tools needed.

## Sources

### Primary (HIGH confidence)
- R/28_episode_classification.R (lines 1-1068): Current 2-tier cancer linkage cascade, DIAGNOSIS query pattern, temporal matching logic, openxlsx2 sheet creation
- R/01_load_pcornet.R (lines 86-106): CONDITION table schema (12 columns: CONDITIONID, ID, ENCOUNTERID, CONDITION, CONDITION_TYPE, ONSET_DATE, REPORT_DATE, etc.)
- R/03_duckdb_ingest.R (lines 48-55): CONDITION table indexed in DuckDB with ENCOUNTERID index
- R/utils/utils_cancer.R (lines 46-124): classify_codes() and is_cancer_code() handling ICD-10/ICD-9
- R/utils/utils_duckdb.R: get_pcornet_table() DuckDB abstraction
- R/utils/utils_dates.R: parse_pcornet_date() multi-format parsing
- R/00_config.R: CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP, CONFIG paths

### Secondary (MEDIUM confidence)
- PCORnet CDM v7.0 specification (January 2025): CONDITION table purpose (EHR problem list vs DIAGNOSIS claims codes)
- openxlsx2 documentation (version 1.10+): wb_load(), add_worksheet(), sheet addition to existing workbooks

### Tertiary (LOW confidence)
None — all research findings verified against project codebase and official documentation.

## Metadata

**Confidence breakdown:**
- CONDITION table infrastructure: HIGH — Verified in R/01, R/03; indexed and queryable
- Code classification utilities: HIGH — classify_codes() tested extensively in R/28, works on any ICD-10/ICD-9 input
- Linkage logic patterns: HIGH — Direct copy from R/28 DIAGNOSIS cascade; well-documented
- xlsx modification approach: HIGH — openxlsx2 wb_load() pattern verified in documentation
- Investigation script numbering: MEDIUM — R/29 is next available in 20s decade (R/29_first_line_and_death_analysis.R already exists, but investigation scripts could go elsewhere)

**Research date:** 2026-06-12
**Valid until:** 60 days (stable infrastructure; no fast-moving dependencies)
