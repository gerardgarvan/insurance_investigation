# Phase 92: Gantt v2 Schema Extension - Research

**Researched:** 2026-06-08
**Domain:** R-based CSV export schema extension — propagating enriched metadata from treatment_episodes.rds to Gantt v2 CSV files
**Confidence:** HIGH

## Summary

Phase 92 extends the Gantt v2 CSV exports (gantt_episodes_v2.csv and gantt_detail_v2.csv) to include 5 new metadata columns added by Phase 91: medication_name, code_type, source_table, treatment_line, and sct_cross_use_flag. The enriched columns already exist in treatment_episodes.rds (populated by R/28_episode_classification.R in Phase 91) and must be propagated to the CSV export layer via R/52_gantt_v2_export.R.

This is a **column selection and propagation task**, not an enrichment task. All 5 columns are pre-computed in the RDS input — R/52 just needs to select them alongside existing columns and preserve column order for backward compatibility.

**Primary recommendation:** Modify R/52_gantt_v2_export.R Section 4 (column selection) to append 5 new columns to episodes_export and detail_export. Episodes schema extends from 16→21 columns (appending medication_name, code_type, source_table, treatment_line, sct_cross_use_flag at end). Detail schema extends from 14→19 columns (same 5 columns appended). Death and HL Diagnosis pseudo-rows populate new columns with NA (same pattern as existing regimen_label/is_first_line columns).

**Key insight:** NO NEW STACK COMPONENTS OR ENRICHMENT LOGIC. This is a pure **select() modification** — the hard work (xlsx loading, lookup mapping, episode-level aggregation) was done in Phase 91. Phase 92 is a 30-line change to R/52's column selection lists plus smoke test schema validation.

## User Constraints

*Phase 92 had no `/gsd:discuss-phase` session — no CONTEXT.md exists. All decisions are Claude's discretion within the requirements.*

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GANTT-06 | Gantt v2 detail CSV includes same 5 new columns at per-date level | Detail table joins enriched episodes data (R/52 lines 298-327); Phase 91 verified treatment_episodes.rds contains all 5 columns |
| GANTT-07 | Existing v1 Gantt exports unchanged (backward compatible) | R/51 (v1 export) and R/52 (v2 export) are separate scripts (separate output files); v1 reads pre-Phase-91 columns only; no cross-contamination |

## Standard Stack

### Core (All Already Validated)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Column selection and row binding | Industry standard; `select()` for column control, `bind_rows()` for pseudo-treatment rows; used in all 98 pipeline scripts |
| readr/base R | N/A | CSV writing | `write.csv()` used throughout project; no change needed |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| glue | 1.8.0+ | String formatting for logging | Readable logging messages with embedded expressions; used across all pipeline scripts |
| checkmate | 2.3.2+ | Schema validation assertions | Validate column counts, detect schema drift; established in Phase 72 |

**Installation:**
```r
# NO NEW PACKAGES TO INSTALL - all dependencies already in project renv
# Phase 92 uses only dplyr::select(), base::write.csv(), glue::glue()
```

## Architecture Patterns

### Recommended Modification Structure
```
R/
├── 28_episode_classification.R  # Phase 91: Created 5 new columns in treatment_episodes.rds ✓
├── 51_gantt_data_export.R       # v1 export: UNCHANGED (backward compatible) ✓
└── 52_gantt_v2_export.R         # Phase 92: Extend select() to propagate 5 new columns
```

### Pattern 1: Column Selection Extension (Episodes Table)

**What:** Modify R/52 Section 4 (lines 256-292) to append 5 new columns from enriched treatment_episodes.rds.

**When to use:** This is the REQUIRED pattern for Phase 92. Append new columns at end (non-breaking change).

**Example:**
```r
# R/52_gantt_v2_export.R Section 4 (MODIFIED)
# Current: 16 columns (patient_id through cause_of_death)
# Phase 92: 21 columns (add 5 metadata columns at end)

episodes_export <- episodes %>%
  select(
    # --- Existing 16 columns (unchanged) ---
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag, triggering_codes,
    encounter_ids, drug_names, drug_group
  ) %>%
  mutate(
    triggering_code_descriptions = sapply(triggering_codes, map_codes_to_descriptions, USE.NAMES = FALSE),
    cause_of_death = NA_character_  # Treatment rows get NA per D-78-10
  ) %>%
  left_join(
    episodes %>% select(
      patient_id, episode_number, treatment_type,
      cancer_category, is_hodgkin, cancer_link_method,
      regimen_label, is_first_line,
      # --- Phase 92: Add 5 new columns ---
      medication_name, code_type, source_table, treatment_line, sct_cross_use_flag
    ),
    by = c("patient_id", "episode_number", "treatment_type")
  ) %>%
  mutate(
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  ) %>%
  select(
    # --- Existing 16 columns ---
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag, triggering_codes,
    encounter_ids, drug_names, triggering_code_descriptions,
    cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line,
    drug_group, cause_of_death,
    # --- Phase 92: Add 5 new columns at end (non-breaking) ---
    medication_name, code_type, source_table, treatment_line, sct_cross_use_flag
  )
```

### Pattern 2: Column Selection Extension (Detail Table)

**What:** Modify R/52 Section 4 detail_export (lines 296-327) to append 5 new columns from enriched episodes join.

**When to use:** Detail table doesn't have these columns directly — must join from episodes (same pattern as regimen_label/is_first_line).

**Example:**
```r
# R/52_gantt_v2_export.R Section 4 (MODIFIED)
# Current: 14 columns (patient_id through cause_of_death)
# Phase 92: 19 columns (add 5 metadata columns at end)

episodes_v2_cols <- episodes %>%
  select(
    patient_id, treatment_type, episode_number, cancer_category, is_hodgkin,
    cancer_link_method, regimen_label, is_first_line,
    # --- Phase 92: Add 5 new columns ---
    medication_name, code_type, source_table, treatment_line, sct_cross_use_flag
  )

detail_export <- detail %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop, historical_flag
  ) %>%
  mutate(
    triggering_code_description = sapply(triggering_code, lookup_description, USE.NAMES = FALSE),
    cause_of_death = NA_character_  # Treatment detail rows get NA per D-78-10
  ) %>%
  left_join(episodes_v2_cols, by = c("patient_id", "treatment_type", "episode_number")) %>%
  mutate(
    cancer_category = ifelse(is.na(cancer_category), "", cancer_category),
    is_hodgkin = ifelse(is.na(is_hodgkin), FALSE, is_hodgkin)
  ) %>%
  select(
    # --- Existing 14 columns ---
    patient_id, treatment_type, treatment_date, triggering_code,
    ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop, historical_flag,
    triggering_code_description,
    cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line,
    cause_of_death,
    # --- Phase 92: Add 5 new columns at end (non-breaking) ---
    medication_name, code_type, source_table, treatment_line, sct_cross_use_flag
  )
```

### Pattern 3: Pseudo-Treatment Row Extension (Death and HL Diagnosis)

**What:** Modify death_episodes, death_detail, hl_dx_episodes, hl_dx_detail construction (R/52 Sections 4B and 4C) to include 5 new columns with NA values.

**When to use:** Pseudo-treatment rows (Death, HL Diagnosis) have no triggering codes → new metadata columns get NA (same pattern as regimen_label).

**Example:**
```r
# R/52_gantt_v2_export.R Section 4B (MODIFIED)
# Death pseudo-treatment rows: Add 5 new columns with NA values

death_episodes <- death_data %>%
  mutate(
    patient_id = ID,
    treatment_type = "Death",
    episode_number = 1L,
    episode_start = DEATH_DATE,
    episode_stop = DEATH_DATE,
    episode_length_days = 0L,
    distinct_dates_in_episode = 1L,
    historical_flag = FALSE,
    triggering_codes = "",
    encounter_ids = "",
    drug_names = "",
    triggering_code_descriptions = "",
    cancer_category = "",
    is_hodgkin = FALSE,
    cancer_link_method = "none",
    regimen_label = NA_character_,
    is_first_line = FALSE,
    drug_group = NA_character_,
    # --- Phase 92: Add 5 new columns with NA (no treatment codes) ---
    medication_name = NA_character_,
    code_type = NA_character_,
    source_table = NA_character_,
    treatment_line = NA_character_,
    sct_cross_use_flag = NA_character_
    # cause_of_death already in death_data from mapping above
  ) %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag, triggering_codes,
    encounter_ids, drug_names, triggering_code_descriptions,
    cancer_category, is_hodgkin, cancer_link_method, regimen_label, is_first_line,
    drug_group, cause_of_death,
    medication_name, code_type, source_table, treatment_line, sct_cross_use_flag
  )

# Same pattern for death_detail, hl_dx_episodes, hl_dx_detail
```

### Anti-Patterns to Avoid

- **Don't re-derive metadata in R/52:** Phase 91 already computed medication_name, code_type, source_table, treatment_line, sct_cross_use_flag in R/28. R/52 must select pre-computed columns, not re-derive them from xlsx lookups.
- **Don't insert columns mid-list:** Append new columns at end to preserve backward compatibility (existing column positions unchanged).
- **Don't modify R/51 (v1 export):** Requirement GANTT-07 demands v1 unchanged. R/51 reads pre-Phase-91 columns only; no risk of contamination.
- **Don't forget pseudo-treatment rows:** Death and HL Diagnosis rows lack these columns in current code → must be added with NA values (same pattern as regimen_label).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Column schema validation | Manual `ncol()` checks without expected value | `checkmate::assert_true(ncol(df) == expected)` with descriptive error | Clear failure message, single-line assertion |
| Pseudo-row column alignment | Manual `colnames()` comparison with custom error handling | Existing R/52 pattern (lines 413-424, 456-467) | Already established, proven in Death/HL Diagnosis row construction |
| Data quality cleanup for new columns | Custom string normalization for medication_name/code_type | sapply(clean_multi_value, ...) from Phase 64 pattern | Phase 64 cleanup (lines 724-738) handles semicolon-separated multi-value fields |

**Key insight:** R/52 already has proven patterns for column validation (Section 4C2, lines 813-823) and pseudo-row construction (Sections 4B-4C). Reuse these for 5 new columns.

## Common Pitfalls

### Pitfall 1: Column Order Mismatch Between Treatment Rows and Pseudo-Treatment Rows

**What goes wrong:** Treatment rows (episodes_export) have 21 columns in order A. Death pseudo-rows have 21 columns in order B (different order). `bind_rows()` succeeds but column order in CSV is wrong, breaking downstream Tableau dashboards that assume fixed column positions.

**Why it happens:** `bind_rows()` matches columns by name, not position. If death_episodes uses `select(patient_id, treatment_type, medication_name, ...)` while episodes_export uses `select(patient_id, treatment_type, ..., medication_name)`, bind_rows() aligns them but final CSV may have inconsistent column order.

**How to avoid:**
1. **Explicit column order in select():** Both treatment rows and pseudo-rows use identical `select(col1, col2, ..., col21)` order
2. **Column alignment validation (R/52 pattern, lines 413-424):** Before `bind_rows()`, assert `all(colnames(death_episodes) == colnames(episodes_export))`
3. **Final schema verification (R/52 pattern, lines 813-823):** After all `bind_rows()`, assert `ncol(episodes_export) == 21` and print `colnames(episodes_export)` to console

**Warning signs:**
- Pseudo-row construction uses different `select()` order than main export
- No column alignment validation before `bind_rows()`
- CSV header inspection shows columns in unexpected order

### Pitfall 2: Missing Guard Clauses for Phase 91 Columns

**What goes wrong:** If treatment_episodes.rds was regenerated without running Phase 91 R/28 (e.g., re-ran older pipeline version), the 5 new columns don't exist. R/52's `select(medication_name, ...)` throws error: "Can't select columns that don't exist."

**Why it happens:** Phase 91 columns are conditional — they only exist if R/28 sourced utils_xlsx_lookups.R and applied enrichment (R/28 lines 562-580). If R/28 is from pre-Phase-91 codebase, treatment_episodes.rds lacks these columns.

**How to avoid:**
1. **Guard clauses (R/52 pattern, lines 159-187):** Before selecting new columns, check existence with `if (!"medication_name" %in% names(episodes))` and mutate defaults
2. **Default values:** `medication_name = NA_character_`, `code_type = NA_character_`, etc. (not empty strings — NA preserves type safety)
3. **Warning messages:** `warning("medication_name column not found in treatment_episodes.rds — Phase 91 not yet run. Using default NA.")`

**Warning signs:**
- No guard clauses for Phase 91 columns
- Assumes treatment_episodes.rds always has enriched columns
- No version detection logic

### Pitfall 3: Forgetting Data Quality Cleanup for Multi-Value Fields

**What goes wrong:** medication_name, code_type, source_table in treatment_episodes.rds use semicolons as separator (Phase 91, D-04). But Phase 64 cleanup (R/52 Section 4D, lines 624-823) only applies to triggering_codes, drug_names, triggering_code_descriptions. New columns bypass cleanup → literal "NA" strings, inconsistent separators, duplicate values appear in CSV.

**Why it happens:** Phase 64 cleanup (lines 724-738) applies `clean_multi_value()` to hardcoded column list. Adding new multi-value columns requires extending cleanup logic.

**How to avoid:**
1. **Extend cleanup to new columns:** Apply `clean_multi_value()` to medication_name, code_type, source_table
2. **Verify separator consistency:** Phase 91 uses semicolons (D-04), Phase 64 cleanup converts commas→semicolons — new columns already use semicolons, so cleanup is deduplication only
3. **treatment_line is single-value:** Do NOT apply multi-value cleanup to treatment_line (aggregated to single F/S/E/N per Phase 91 D-03)
4. **sct_cross_use_flag is single-value:** Do NOT apply multi-value cleanup to sct_cross_use_flag (aggregated via any-positive logic per Phase 91 D-09)

**Warning signs:**
- New multi-value columns not in Phase 64 cleanup section
- CSV inspection shows "NA;NA;Doxorubicin" instead of "Doxorubicin"
- Duplicate medication names in semicolon-separated list

### Pitfall 4: Schema Drift Between Episodes and Detail Tables

**What goes wrong:** Episodes table has 21 columns (16 existing + 5 new). Detail table has 18 columns (14 existing + 4 new) — forgot sct_cross_use_flag. Schema asymmetry breaks downstream join logic (e.g., Tableau union between episodes and detail).

**Why it happens:** Episodes and detail tables require separate modifications (R/52 lines 256-292 vs. 296-327). Easy to update one but forget the other.

**How to avoid:**
1. **Parallel modification:** Update episodes_export and detail_export in same commit
2. **Column count assertions (R/52 lines 813-823):** `assert_true(ncol(episodes_export) == 21)`, `assert_true(ncol(detail_export) == 19)`
3. **Explicit column lists:** Comment "5 new Phase 92 columns" in both select() blocks for traceability
4. **Smoke test validation:** Check both CSVs have correct column counts and order

**Warning signs:**
- Only one table modified in code diff
- No column count assertions updated
- Smoke test only validates one CSV schema

## Code Examples

Verified patterns from existing codebase:

### Column Alignment Validation Before bind_rows()
```r
# Source: R/52_gantt_v2_export.R (lines 413-424)
# Verify column alignment before binding death rows

expected_ep_cols <- colnames(episodes_export)
death_ep_cols <- colnames(death_episodes)
missing_in_death_ep <- setdiff(expected_ep_cols, death_ep_cols)
extra_in_death_ep <- setdiff(death_ep_cols, expected_ep_cols)

if (length(missing_in_death_ep) > 0) {
  stop(glue("Death episodes missing columns: {paste(missing_in_death_ep, collapse = ', ')}"))
}
if (length(extra_in_death_ep) > 0) {
  warning(glue("Death episodes has extra columns: {paste(extra_in_death_ep, collapse = ', ')}"))
}
```

### Guard Clauses for Conditional Columns
```r
# Source: R/52_gantt_v2_export.R (lines 180-183)
# Guard clause pattern for Phase 78 drug_group column

if (!"drug_group" %in% names(episodes)) {
  warning("drug_group column not found in treatment_episodes.rds — Phase 78 R/28 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(drug_group = NA_character_)
}

# Phase 92: Add guard clauses for 5 new columns
if (!"medication_name" %in% names(episodes)) {
  warning("medication_name column not found in treatment_episodes.rds — Phase 91 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(medication_name = NA_character_)
}
if (!"code_type" %in% names(episodes)) {
  warning("code_type column not found in treatment_episodes.rds — Phase 91 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(code_type = NA_character_)
}
if (!"source_table" %in% names(episodes)) {
  warning("source_table column not found in treatment_episodes.rds — Phase 91 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(source_table = NA_character_)
}
if (!"treatment_line" %in% names(episodes)) {
  warning("treatment_line column not found in treatment_episodes.rds — Phase 91 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(treatment_line = NA_character_)
}
if (!"sct_cross_use_flag" %in% names(episodes)) {
  warning("sct_cross_use_flag column not found in treatment_episodes.rds — Phase 91 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(sct_cross_use_flag = NA_character_)
}
```

### Final Schema Verification
```r
# Source: R/52_gantt_v2_export.R (lines 813-823)
# Column count verification after all modifications

# Phase 92: Update expected counts
expected_ep_cols <- 21  # was 16, Phase 92: +5 metadata columns
expected_detail_cols <- 19  # was 14, Phase 92: +5 metadata columns

if (ncol(episodes_export) != expected_ep_cols) {
  stop(glue("ERROR: episodes_export has {ncol(episodes_export)} columns, expected {expected_ep_cols}"))
}
if (ncol(detail_export) != expected_detail_cols) {
  stop(glue("ERROR: detail_export has {ncol(detail_export)} columns, expected {expected_detail_cols}"))
}

message("  Column count verification: PASSED")
message(glue("  Episodes columns: {paste(colnames(episodes_export), collapse = ', ')}"))
message(glue("  Detail columns: {paste(colnames(detail_export), collapse = ', ')}"))
```

### Data Quality Cleanup for Multi-Value Fields
```r
# Source: R/52_gantt_v2_export.R (lines 724-738)
# Phase 64 cleanup pattern extended for Phase 92 columns

# Step 1: Clean multi-value fields (separator + dedup + drop blanks)
episodes_export <- episodes_export %>%
  mutate(
    triggering_codes = sapply(triggering_codes, clean_multi_value, USE.NAMES = FALSE),
    drug_names = sapply(drug_names, clean_multi_value, USE.NAMES = FALSE),
    triggering_code_descriptions = sapply(triggering_code_descriptions, clean_multi_value, USE.NAMES = FALSE),
    # Phase 92: Add 3 multi-value columns (medication_name, code_type, source_table)
    medication_name = sapply(medication_name, clean_multi_value, USE.NAMES = FALSE),
    code_type = sapply(code_type, clean_multi_value, USE.NAMES = FALSE),
    source_table = sapply(source_table, clean_multi_value, USE.NAMES = FALSE)
    # treatment_line and sct_cross_use_flag are single-value — skip cleanup
  )

detail_export <- detail_export %>%
  mutate(
    triggering_code = sapply(triggering_code, clean_multi_value, USE.NAMES = FALSE),
    triggering_code_description = sapply(triggering_code_description, clean_multi_value, USE.NAMES = FALSE),
    # Phase 92: Add 3 multi-value columns (same pattern)
    medication_name = sapply(medication_name, clean_multi_value, USE.NAMES = FALSE),
    code_type = sapply(code_type, clean_multi_value, USE.NAMES = FALSE),
    source_table = sapply(source_table, clean_multi_value, USE.NAMES = FALSE)
  )

message("  Multi-value fields cleaned (separator: semicolon, deduped, blanks dropped)")
```

## Open Questions

1. **Should medication_name, code_type, source_table receive simplification like drug_names?**
   - What we know: Phase 64 applies `simplify_drug_name()` to drug_names (R/52 lines 740-747), extracting generic names and removing dosage forms
   - What's unclear: medication_name is from xlsx column 3 (human-readable medication names) — is it already simplified or does it need cleanup?
   - Recommendation: Inspect xlsx column 3 values during implementation. If medication_name contains dosage forms (e.g., "Doxorubicin 50 MG Injection"), apply `simplify_drug_name()`. If already generic ("Doxorubicin"), skip.

2. **Should smoke test Section 52 validate column order or just column count?**
   - What we know: R/52 has schema verification (lines 813-823) checking column count only
   - What's unclear: Is column order stability critical for downstream consumers (Tableau)?
   - Recommendation: Validate both column count (21/19) AND column order (assert first 16/14 columns unchanged, last 5 are Phase 92 additions). Prevents accidental reordering.

3. **Should Phase 64 cleanup (Section 4D) run before or after Phase 92 column selection?**
   - What we know: Phase 64 cleanup happens after pseudo-rows are bound (lines 624-823)
   - What's unclear: Do Phase 92 columns need cleanup, or are they already clean from Phase 91?
   - Recommendation: Inspect treatment_episodes.rds values for medication_name, code_type, source_table. If semicolon-separated lists contain duplicates or blanks, apply cleanup. If clean from Phase 91, skip (but add comment explaining why).

## Environment Availability

> Phase 92 has no external dependencies (code-only changes to R/52, reading existing treatment_episodes.rds).

Step 2.6: SKIPPED (no external dependencies identified)

## Sources

### Primary (HIGH confidence)
- **Codebase inspection:**
  - R/52_gantt_v2_export.R — Current v2 export schema (16 episodes columns, 14 detail columns), pseudo-row construction pattern, guard clauses, schema validation
  - R/51_gantt_data_export.R — v1 export (unchanged, backward compatible)
  - R/28_episode_classification.R (lines 562-593) — Phase 91 enrichment creating 5 new columns in treatment_episodes.rds
  - .planning/phases/91-reference-data-loader-metadata-enrichment/91-RESEARCH.md — Column derivation logic, D-04 semicolon separator, D-03 treatment_line aggregation, D-09 cross_use_flag aggregation

- **Official documentation:**
  - [dplyr select() reference](https://dplyr.tidyverse.org/reference/select.html) — Column selection syntax, NSE
  - [dplyr bind_rows() reference](https://dplyr.tidyverse.org/reference/bind_rows.html) — Column alignment by name, handling mismatched schemas

### Secondary (MEDIUM confidence)
- **Requirements documents:**
  - .planning/REQUIREMENTS.md — GANTT-06 (detail CSV extends with 5 columns), GANTT-07 (v1 unchanged)
  - .planning/STATE.md — Phase 92 success criteria (21 episodes columns, 19 detail columns, backward compatibility)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — No new libraries, only dplyr::select() and base::write.csv()
- Architecture: HIGH — Codebase patterns well-established (R/52 column selection, guard clauses, schema validation)
- Column propagation logic: HIGH — 5 columns already exist in treatment_episodes.rds from Phase 91; R/52 just selects them
- Pseudo-row handling: HIGH — Death/HL Diagnosis row construction pattern proven in R/52 Sections 4B-4C

**Research date:** 2026-06-08
**Valid until:** 60 days (R/52 structure stable, Phase 91 enrichment verified complete)
