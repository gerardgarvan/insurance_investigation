# Phase 63: Enhanced Gantt Export - Research

**Researched:** 2026-05-31
**Domain:** R data pipeline - CSV export with enriched treatment episode metadata
**Confidence:** HIGH

## Summary

Phase 63 produces Gantt v2 CSV files by reading enriched `treatment_episodes.rds` and `treatment_episode_detail.rds` artifacts (populated by Phases 60-62) and writing new v2 CSVs with 17 columns (14 v1 columns + 3 new columns). The implementation is **significantly simpler** than v1 because encounter-level cancer categories, regimen labels, and first-line flags are pre-computed in the RDS artifacts — no re-derivation needed.

**Primary recommendation:** Create standalone `R/63_gantt_v2_export.R` following the R/49 structure but with simpler cancer linkage logic (direct read from RDS, no PREFIX_MAP re-application). Duplicate Death/HL Diagnosis pseudo-treatment row construction (~200 lines) from R/49 to maintain script independence. v2 schema documented in script header comments following R/49 pattern.

## User Constraints

<user_constraints>

### Locked Decisions (from CONTEXT.md)

**v2 Column Schema:**
- **D-01:** v2 is a superset of v1 — all 14 existing v1 columns plus 3 new columns: cancer_link_method, regimen_label, is_first_line
- **D-02:** cancer_category column keeps the same name in v2 but uses encounter-level data from treatment_episodes.rds (Phase 61) instead of patient-level derivation from cancer_summary.csv (Phase 57 pattern in R/49)
- **D-03:** is_hodgkin in v2 is derived from the encounter-level cancer_category (already in treatment_episodes.rds), not from patient-level cancer_summary.csv

**Script Architecture:**
- **D-04:** New standalone R/63_gantt_v2_export.R script — does NOT modify R/49
- **D-05:** R/63 reads enriched treatment_episodes.rds directly (cancer_category, cancer_link_method, is_hodgkin, regimen_label, is_first_line are pre-computed by Phases 61-62)
- **D-06:** R/63 is simpler than R/49 because it does NOT re-derive cancer categories from cancer_summary.csv or PREFIX_MAP — the RDS already has encounter-level values
- **D-07:** Accept code duplication for Death/HL Diagnosis row construction (~200 lines shared with R/49). Scripts remain self-contained per project pattern (same pattern as PREFIX_MAP duplication across R/47, R/49, R/53, R/55, R/61)

**Schema Documentation:**
- **D-08:** v2 schema documented in R/63's header comment block — column name, type, source, and description. Same pattern as R/49's header comments listing expected columns. No extra output artifact needed.

**Death/HL Diagnosis Rows:**
- **D-09:** v2 includes Death and HL Diagnosis pseudo-treatment rows (same as v1)
- **D-10:** New v2 columns on pseudo-treatment rows: cancer_link_method="none", regimen_label=NA, is_first_line=FALSE. Ensures v2 is a complete superset of v1.

### Claude's Discretion

- Column ordering within v2 CSVs (likely: v1 columns in original order, then cancer_link_method, regimen_label, is_first_line appended)
- Whether to include a summary message at end of R/63 showing v1 vs v2 column comparison
- How to handle edge cases where treatment_episodes.rds is missing Phase 61/62 columns (guard clauses similar to R/62's pattern)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

All packages already in use in existing scripts. No new dependencies required.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Project standard; used in all R scripts |
| glue | 1.8.0 | String formatting | Project standard for logging messages |
| lubridate | 1.9.3+ | Date operations | Project standard for date parsing |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | String operations | Comma-separated list construction (paste unique) |

**Installation:**
Not required — all packages already installed in project renv environment.

**Version verification:** Project uses renv.lock from Phase 01 setup. No new packages needed for Phase 63.

## Architecture Patterns

### Recommended Project Structure

Phase 63 follows established project patterns from R/49. No new structure needed.

```
R/
├── 49_gantt_data_export.R        # v1 Gantt export (UNCHANGED)
├── 63_gantt_v2_export.R          # NEW v2 Gantt export
└── [existing infrastructure scripts]

output/
├── gantt_episodes.csv            # v1 output (12-14 columns, depending on R/49 re-run status)
├── gantt_detail.csv              # v1 output (11-13 columns)
├── gantt_episodes_v2.csv         # NEW v2 output (17 columns)
└── gantt_detail_v2.csv           # NEW v2 output (15 columns)
```

### Pattern 1: Enriched RDS Read-Through (Simpler than R/49)

**What:** Read pre-enriched treatment_episodes.rds with all Phase 60-62 columns already present. No re-derivation of cancer categories or regimen labels.

**When to use:** Phase 63 only — this is the key simplification over R/49's patient-level PREFIX_MAP re-application.

**Example:**
```r
# R/63 (SIMPLE): Read enriched RDS directly
episodes <- readRDS(EPISODES_RDS)
# Columns already present: cancer_category, cancer_link_method, is_hodgkin, regimen_label, is_first_line

# v2 export is just column selection + pseudo-treatment rows
episodes_export <- episodes %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag,
    triggering_codes, encounter_ids, drug_names,
    triggering_code_descriptions,
    cancer_category, cancer_link_method, is_hodgkin,
    regimen_label, is_first_line
  )
```

**Contrast with R/49 (COMPLEX):**
```r
# R/49: Load cancer_summary.csv, apply PREFIX_MAP per patient, join back
cancer_summary <- read.csv(CANCER_SUMMARY_CSV)
# ... 300 lines of PREFIX_MAP definition ...
cancer_summary <- cancer_summary %>%
  mutate(
    prefix = str_sub(str_remove_all(cancer_code, "\\."), 1, 3),
    cancer_category = PREFIX_MAP[prefix]
  ) %>%
  group_by(ID) %>%
  summarise(
    cancer_category = paste(unique(sort(cancer_category)), collapse = ", "),
    is_hodgkin = any(cancer_category == "Hodgkin Lymphoma")
  )

episodes_export <- episodes %>%
  left_join(cancer_summary, by = c("patient_id" = "ID"))
```

**Key insight:** R/63 avoids ~400 lines of cancer category derivation because Phase 61 pre-computed encounter-level values in the RDS.

### Pattern 2: Pseudo-Treatment Row Construction (Code Duplication from R/49)

**What:** Death and HL Diagnosis rows are NOT in treatment_episodes.rds (they're not real treatment episodes). They must be constructed from `validated_death_dates.rds` and `confirmed_hl_cohort.rds` and appended to both episodes and detail export tables.

**When to use:** Both R/49 and R/63 — duplicate this ~200 line pattern.

**Example:**
```r
# Source: R/49 lines 580-702 (Death rows) and 668-767 (HL Diagnosis rows)

# --- Death pseudo-treatment rows ---
death_data <- validated_deaths %>%
  filter(!is.na(DEATH_DATE)) %>%
  select(ID, DEATH_DATE)

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
    cancer_link_method = "none",   # NEW for v2
    is_hodgkin = FALSE,
    regimen_label = NA_character_, # NEW for v2
    is_first_line = FALSE          # NEW for v2
  ) %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag,
    triggering_codes, encounter_ids, drug_names,
    triggering_code_descriptions,
    cancer_category, cancer_link_method, is_hodgkin,
    regimen_label, is_first_line
  )

# Append to episodes export
episodes_export <- bind_rows(episodes_export, death_episodes) %>%
  arrange(patient_id, episode_start, treatment_type)
```

**Why duplicate instead of refactor:** Project pattern established in CONTEXT.md D-07 — PREFIX_MAP is duplicated across R/47, R/49, R/53, R/55, R/61 to keep scripts self-contained. Same applies to pseudo-treatment row construction.

### Pattern 3: Column Order Convention (v1 Columns First, Then v2 Additions)

**What:** Maintain v1 column order (patient_id through is_hodgkin) then append v2 columns (cancer_link_method, regimen_label, is_first_line) for easier comparison and backward compatibility.

**When to use:** v2 CSV column selection in R/63.

**Expected v2 episodes schema (17 columns):**
```r
# v1 columns (1-14):
patient_id, treatment_type, episode_number,
episode_start, episode_stop, episode_length_days,
distinct_dates_in_episode, historical_flag,
triggering_codes, encounter_ids, drug_names,
triggering_code_descriptions,
cancer_category, is_hodgkin

# v2 additions (15-17):
cancer_link_method, regimen_label, is_first_line
```

**Expected v2 detail schema (15 columns):**
```r
# v1 columns (1-13):
patient_id, treatment_type, treatment_date, triggering_code,
ENCOUNTERID, drug_name,
episode_number, episode_start, episode_stop, historical_flag,
triggering_code_description,
cancer_category, is_hodgkin

# v2 additions (14-15):
cancer_link_method, regimen_label, is_first_line
```

**Note on detail table v2 columns:** The detail table does NOT have triggering_codes (it's singular triggering_code) or encounter_ids (it's singular ENCOUNTERID) or drug_names (it's singular drug_name). But it DOES get cancer_link_method, regimen_label, is_first_line joined from the parent episode via patient_id + episode_number.

### Pattern 4: Guard Clauses for Missing Phase 61/62 Columns

**What:** If treatment_episodes.rds is missing expected columns (regimen_label, is_first_line, cancer_link_method), warn and add default values instead of crashing.

**When to use:** R/63 Section 2 (data loading), following R/62's established pattern.

**Example:**
```r
# Source: R/62 lines 79-85
episodes <- readRDS(OUTPUT_RDS)

# Guard for missing columns from Phase 61
if (!"regimen_label" %in% names(episodes)) {
  warning("regimen_label column not found in treatment_episodes.rds — Phase 61 not yet run. v2 export will have NA values.")
  episodes <- episodes %>% mutate(regimen_label = NA_character_)
}
if (!"cancer_link_method" %in% names(episodes)) {
  warning("cancer_link_method column not found in treatment_episodes.rds — Phase 61 not yet run. v2 export will have NA values.")
  episodes <- episodes %>% mutate(cancer_link_method = "none")
}
if (!"is_first_line" %in% names(episodes)) {
  warning("is_first_line column not found in treatment_episodes.rds — Phase 62 not yet run. v2 export will have FALSE values.")
  episodes <- episodes %>% mutate(is_first_line = FALSE)
}
```

### Anti-Patterns to Avoid

- **Modifying R/49:** v1 export must remain unchanged for backward compatibility (D-04). All v2 logic goes in new R/63 script.
- **Re-deriving cancer categories from cancer_summary.csv:** Phase 61 pre-computed encounter-level cancer_category in treatment_episodes.rds. Don't reload cancer_summary.csv or re-apply PREFIX_MAP (D-06).
- **Skipping pseudo-treatment rows:** Death and HL Diagnosis rows are required in v2 CSVs (D-09). They're not in treatment_episodes.rds, so they must be constructed from validated_death_dates.rds and confirmed_hl_cohort.rds.
- **Different column order than v1:** Keep v1 columns in original order, append v2 columns at end. Makes diff/comparison easier.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CSV export | Custom write logic | write.csv() | Base R; handles quoting, escaping, NA serialization correctly |
| Comma-separated lists | Manual paste0 loops | paste(unique(sort(x)), collapse = ", ") | Project pattern; ensures dedupe + sort + join |
| Date parsing | Custom string manipulation | parse_pcornet_date() from utils_dates.R | Handles PCORnet sentinel dates (1900-01-01) and NA cases |
| Column existence checks | tryCatch() on column access | `if (!"col" %in% names(df))` | Explicit; produces clear warning messages (R/62 pattern) |

**Key insight:** R/63 is mostly column selection + pseudo-treatment row appending. The hard work (cancer linkage, regimen detection, first-line ID) was done by Phases 61-62. Don't re-implement any of that logic.

## Common Pitfalls

### Pitfall 1: Forgetting to Propagate v2 Columns to Detail Table

**What goes wrong:** Episodes table gets cancer_link_method/regimen_label/is_first_line, but detail table is left with only v1 columns. Visualization tools that join both tables fail.

**Why it happens:** treatment_episode_detail.rds does NOT have cancer_link_method/regimen_label/is_first_line columns (they're episode-level, not detail-level). Must join from episodes.

**How to avoid:** After loading detail RDS, join v2 columns from episodes via patient_id + episode_number before export.

**Warning signs:** detail_export has only 13 columns instead of 15 in v2.

**Code example:**
```r
# CORRECT: Join v2 columns from episodes to detail
episodes_v2_cols <- episodes %>%
  select(patient_id, episode_number, cancer_link_method, regimen_label, is_first_line)

detail_export <- detail %>%
  left_join(episodes_v2_cols, by = c("patient_id", "episode_number")) %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop, historical_flag,
    triggering_code_description,
    cancer_category, is_hodgkin,
    cancer_link_method, regimen_label, is_first_line  # v2 columns from join
  )
```

### Pitfall 2: Using Patient-Level cancer_category from cancer_summary.csv

**What goes wrong:** R/63 loads cancer_summary.csv and re-applies PREFIX_MAP per patient (R/49 pattern), producing patient-level cancer categories instead of encounter-level categories. v2 output doesn't reflect the encounter-specific linkage from Phase 61.

**Why it happens:** Copying R/49 Section 2B (lines 105-280) without recognizing that Phase 61 changed the data model.

**How to avoid:** DO NOT load cancer_summary.csv in R/63. DO NOT use PREFIX_MAP. Read cancer_category directly from treatment_episodes.rds (it's already encounter-level from Phase 61).

**Warning signs:** R/63 script includes `read.csv(CANCER_SUMMARY_CSV)` or has 300+ lines of PREFIX_MAP definition.

**Verification:** Check R/63 Section 2 — it should NOT contain `PREFIX_MAP <-` or `read.csv(CANCER_SUMMARY_CSV)`.

### Pitfall 3: Missing Pseudo-Treatment Row v2 Column Defaults

**What goes wrong:** Death and HL Diagnosis rows are created with v1 columns only. When appended to episodes_export (which has 17 columns), bind_rows() fails with column mismatch error.

**Why it happens:** Copying Death/HL Diagnosis construction from R/49 without adding the 3 new v2 columns.

**How to avoid:** When constructing death_episodes and hl_dx_episodes, explicitly set cancer_link_method="none", regimen_label=NA_character_, is_first_line=FALSE (per D-10).

**Warning signs:** Error message: "Can't combine `..1` <chr> and `..2` <lgl>" or "Column count mismatch" when bind_rows() executes.

**Code example:**
```r
# CORRECT: v2 defaults on pseudo-treatment rows
death_episodes <- death_data %>%
  mutate(
    # ... v1 columns ...
    cancer_link_method = "none",       # NEW
    regimen_label = NA_character_,     # NEW
    is_first_line = FALSE              # NEW
  )
```

### Pitfall 4: Column Alignment Mismatch Between Episodes and Pseudo-Rows

**What goes wrong:** bind_rows(episodes_export, death_episodes) produces silent column misalignment because columns are in different order. Data appears in wrong columns in CSV.

**Why it happens:** Not using explicit select() to enforce column order before bind_rows().

**How to avoid:** Use the R/49 pattern (lines 734-756) — verify column sets with setdiff() before binding, and enforce identical column order via select() in both episodes_export and death_episodes/hl_dx_episodes.

**Warning signs:** CSV opens in Excel and treatment_type appears in wrong column, or dates appear as text.

**Code example:**
```r
# R/49 pattern: Verify column alignment before binding
expected_ep_cols <- colnames(episodes_export)
death_ep_cols <- colnames(death_episodes)
missing_in_death <- setdiff(expected_ep_cols, death_ep_cols)
extra_in_death <- setdiff(death_ep_cols, expected_ep_cols)

if (length(missing_in_death) > 0) {
  stop(glue("Death episodes missing columns: {paste(missing_in_death, collapse = ', ')}"))
}
if (length(extra_in_death) > 0) {
  warning(glue("Death episodes has extra columns: {paste(extra_in_death, collapse = ', ')}"))
}

# Bind only if alignment is verified
episodes_export <- bind_rows(episodes_export, death_episodes)
```

## Code Examples

Verified patterns from project codebase.

### Load Enriched RDS and Select v2 Columns

```r
# Source: Pattern from R/49 lines 96-102 + 534-548, adapted for v2
episodes <- readRDS(EPISODES_RDS)
detail <- readRDS(DETAIL_RDS)

# Guard clauses for missing Phase 61/62 columns (R/62 pattern, lines 79-85)
if (!"cancer_link_method" %in% names(episodes)) {
  warning("cancer_link_method not found — Phase 61 not run. Using default 'none'.")
  episodes <- episodes %>% mutate(cancer_link_method = "none")
}
if (!"regimen_label" %in% names(episodes)) {
  warning("regimen_label not found — Phase 61 not run. Using default NA.")
  episodes <- episodes %>% mutate(regimen_label = NA_character_)
}
if (!"is_first_line" %in% names(episodes)) {
  warning("is_first_line not found — Phase 62 not run. Using default FALSE.")
  episodes <- episodes %>% mutate(is_first_line = FALSE)
}

# v2 episodes export: 17 columns (v1 14 + v2 3)
episodes_export <- episodes %>%
  select(
    patient_id, treatment_type, episode_number,
    episode_start, episode_stop, episode_length_days,
    distinct_dates_in_episode, historical_flag,
    triggering_codes, encounter_ids, drug_names,
    triggering_code_descriptions,
    cancer_category, is_hodgkin,
    cancer_link_method, regimen_label, is_first_line  # v2 additions
  )
```

### Construct Death Pseudo-Treatment Rows with v2 Columns

```r
# Source: R/49 lines 580-630, adapted for v2
VALIDATED_DEATHS_RDS <- file.path(CONFIG$cache$outputs_dir, "validated_death_dates.rds")

if (file.exists(VALIDATED_DEATHS_RDS)) {
  validated_deaths <- readRDS(VALIDATED_DEATHS_RDS)

  death_data <- validated_deaths %>%
    filter(!is.na(DEATH_DATE)) %>%
    select(ID, DEATH_DATE)

  if (nrow(death_data) > 0) {
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
        cancer_link_method = "none",      # v2 default per D-10
        regimen_label = NA_character_,    # v2 default per D-10
        is_first_line = FALSE             # v2 default per D-10
      ) %>%
      select(
        patient_id, treatment_type, episode_number,
        episode_start, episode_stop, episode_length_days,
        distinct_dates_in_episode, historical_flag,
        triggering_codes, encounter_ids, drug_names,
        triggering_code_descriptions,
        cancer_category, is_hodgkin,
        cancer_link_method, regimen_label, is_first_line
      )

    # Verify column alignment before binding (R/49 pattern, lines 734-756)
    expected_cols <- colnames(episodes_export)
    death_cols <- colnames(death_episodes)
    missing <- setdiff(expected_cols, death_cols)
    extra <- setdiff(death_cols, expected_cols)

    if (length(missing) > 0) {
      stop(glue("Death episodes missing columns: {paste(missing, collapse = ', ')}"))
    }

    episodes_export <- bind_rows(episodes_export, death_episodes) %>%
      arrange(patient_id, episode_start, treatment_type)

    message(glue("  Added {nrow(death_episodes)} Death rows"))
  }
}
```

### Join v2 Columns to Detail Table

```r
# Pattern: Detail table needs v2 columns joined from episodes (episode-level)
episodes_v2_cols <- episodes %>%
  select(patient_id, episode_number, cancer_link_method, regimen_label, is_first_line)

detail_export <- detail %>%
  left_join(episodes_v2_cols, by = c("patient_id", "episode_number")) %>%
  select(
    patient_id, treatment_type, treatment_date, triggering_code,
    ENCOUNTERID, drug_name,
    episode_number, episode_start, episode_stop, historical_flag,
    triggering_code_description,
    cancer_category, is_hodgkin,
    cancer_link_method, regimen_label, is_first_line  # v2 columns from join
  )
```

### Write v2 CSVs

```r
# Source: R/49 lines 777-781, adapted for v2 filenames
OUTPUT_EPISODES_V2 <- file.path(CONFIG$output_dir, "gantt_episodes_v2.csv")
OUTPUT_DETAIL_V2 <- file.path(CONFIG$output_dir, "gantt_detail_v2.csv")

write.csv(episodes_export, OUTPUT_EPISODES_V2, row.names = FALSE)
message(glue("  Wrote {OUTPUT_EPISODES_V2} ({format(nrow(episodes_export), big.mark = ',')} rows)"))

write.csv(detail_export, OUTPUT_DETAIL_V2, row.names = FALSE)
message(glue("  Wrote {OUTPUT_DETAIL_V2} ({format(nrow(detail_export), big.mark = ',')} rows)"))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Patient-level cancer categories (R/49 via cancer_summary.csv) | Encounter-level cancer categories (Phase 61 via ENCOUNTERID linkage) | Phase 61 (2026-05-30) | v2 CSVs reflect which cancer drove each treatment episode, not just patient's cancer history |
| Regimen identification via manual review | Automated regimen detection (ABVD, BV+AVD, Nivo+AVD) with drug composition matching | Phase 61 (2026-05-30) | v2 CSVs include regimen_label for first-line-eligible episodes |
| First-line therapy identification via manual review | Automated first-line detection (60-day clean period, age 21+) | Phase 62 (2026-05-31) | v2 CSVs include is_first_line flag for episodes |

**Deprecated/outdated:**
- PREFIX_MAP re-application in Gantt export: R/49 loads cancer_summary.csv and re-applies PREFIX_MAP per patient. R/63 reads cancer_category directly from treatment_episodes.rds (encounter-level, pre-computed by Phase 61).
- Manual cancer linkage: R/49 joins patient-level cancer summary to all episodes. R/63 uses ENCOUNTERID-linked cancer_category from Phase 61.

## Open Questions

None — phase scope is well-defined and all inputs are available from Phases 60-62.

## Environment Availability

**Skipped:** Phase 63 is code-only (R script creation, RDS read, CSV write). No external dependencies beyond R packages already in renv environment.

## Validation Architecture

**Skipped:** Per `.planning/config.json` workflow.nyquist_validation is explicitly `false`.

## Sources

### Primary (HIGH confidence)
- `R/49_gantt_data_export.R` — v1 Gantt export implementation (816 lines). Column selection pattern (lines 534-548), pseudo-treatment row construction (lines 580-767), column alignment verification (lines 734-756).
- `R/61_episode_classification.R` — Phase 61 implementation showing cancer_category, cancer_link_method, is_hodgkin, regimen_label columns added to treatment_episodes.rds.
- `R/62_first_line_and_death_analysis.R` — Phase 62 implementation showing is_first_line column added to treatment_episodes.rds. Guard clause pattern for missing columns (lines 79-85).
- `R/44a_treatment_episodes.R` — Produces treatment_episodes.rds and treatment_episode_detail.rds (primary inputs for R/63).
- `.planning/phases/63-enhanced-gantt-export/63-CONTEXT.md` — User decisions from /gsd:discuss-phase session.
- Project git history: Commits d1ca3f7 (Phase 60 R/49 update), c7c642a (Phase 63 context).

### Secondary (MEDIUM confidence)
- `.planning/phases/60-foundation-encounterid-propagation-and-drug-name-resolution/60-CONTEXT.md` — Confirms R/49 was updated in Phase 60 to add encounter_ids and drug_names columns.
- `.planning/REQUIREMENTS.md` — OUT-01 (v2 files preserve v1), OUT-02 (v2 includes encounter-level cancer category, HL flag, drug names).

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH (all packages already in use, no new dependencies)
- Architecture: HIGH (v2 is simplified version of R/49 with direct RDS read, well-defined column schema)
- Pitfalls: HIGH (identified from R/49 patterns and Phase 61/62 implementations)

**Research date:** 2026-05-31
**Valid until:** 90 days (stable codebase, no upstream dependency changes expected)
