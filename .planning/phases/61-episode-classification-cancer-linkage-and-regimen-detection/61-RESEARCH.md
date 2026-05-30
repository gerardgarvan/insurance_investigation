# Phase 61: Episode Classification - Cancer Linkage & Regimen Detection - Research

**Researched:** 2026-05-30
**Domain:** Encounter-level diagnosis linkage, regimen pattern matching, episode classification
**Confidence:** HIGH

## Summary

Phase 61 classifies treatment episodes by linking cancer diagnoses at the encounter level (replacing patient-level linkage from R/49) and labeling chemotherapy episodes with specific regimen names (ABVD, BV+AVD, Nivo+AVD). This is **not a greenfield implementation** — it extends existing patterns from Phase 60 (RDS enrichment), Phase 55 (cancer category classification via PREFIX_MAP), and Phase 59 (openxlsx2 audit workbooks).

The core technical challenge is **two-tier linkage**: (1) direct ENCOUNTERID join to DIAGNOSIS table for encounter-level cancer categories, with (2) temporal fallback to closest diagnosis within 30 days when ENCOUNTERID is NULL. Regimen matching operates at **episode level** (all drugs present anywhere in episode) with **dropped-agent tolerance** for bleomycin (ABVD → AVD variant allowed per RATHL trial) but **zero tolerance for added agents** (ABVD + X disqualifies). Temporal availability rules enforce adoption dates (BV+AVD post-2019, Nivo+AVD post-2024).

**Primary recommendation:** Follow Phase 60's RDS enrichment pattern — load treatment_episodes.rds, add 4 columns (cancer_category, cancer_link_method, is_hodgkin, regimen_label), save in-place. Use existing PREFIX_MAP from R/49 for cancer category classification. Leverage drug_name_lookup.rds (Phase 60 artifact) for regimen matching via string detection. Produce standalone audit xlsx following Phase 59 multi-sheet pattern.

## User Constraints (from CONTEXT.md)

<user_constraints>
### Locked Decisions

**Cancer Linkage Strategy:**
- **D-01:** Cancer diagnosis linked to treatment episodes via ENCOUNTERID (direct match from DIAGNOSIS table). When ENCOUNTERID match succeeds, cancer_link_method = "encounter_id".
- **D-02:** When ENCOUNTERID match fails, temporal fallback uses closest DIAGNOSIS record with DX_DATE <= episode_start within 30-day window. cancer_link_method = "closest_date".
- **D-03:** Temporal fallback looks backward only (DX_DATE <= episode_start). Diagnosis should precede treatment.
- **D-04:** When multiple cancer diagnoses exist near the same treatment episode, closest date wins. If same date, prefer HL (C81) diagnoses since this is an HL study.
- **D-05:** DIAGNOSIS table only for encounter-level linkage. TUMOR_REGISTRY excluded (no ENCOUNTERID, limited DX_DATE granularity). TUMOR_REGISTRY remains used only for confirmed_hl_cohort.rds (Phase 55).
- **D-06:** HL flag (is_hodgkin) derived from encounter-level cancer_category, not patient-level problem list. TRUE when cancer_category indicates Hodgkin Lymphoma.
- **D-07:** Second cancer confirmation requires 2+ diagnoses at least 7 days apart at encounter level (per SC4). Same confirmation logic as Phase 55 but scoped to encounter-level linkage.
- **D-08:** Episodes with no ENCOUNTERID match AND no temporal match get cancer_link_method = "none" and cancer_category = NA.

**Regimen Matching:**
- **D-09:** Regimen matching operates at episode level (all drugs across the full episode), not cycle level. An ABVD episode spanning 6 months just needs all required drugs present somewhere in the episode's drug_names.
- **D-10:** Three regimen definitions:
  - ABVD = {doxorubicin, bleomycin, vinblastine, dacarbazine} (all 4 required)
  - BV+AVD = {brentuximab, doxorubicin, vinblastine, dacarbazine} (brentuximab replaces bleomycin)
  - Nivo+AVD = {nivolumab, doxorubicin, vinblastine, dacarbazine} (nivolumab replaces bleomycin)
- **D-11:** Dropped-agent tolerance: ONLY bleomycin can be dropped from ABVD (per RATHL trial standard of care). AVD (doxorubicin + vinblastine + dacarbazine, no bleomycin) still classified as ABVD variant. Missing doxorubicin, vinblastine, or dacarbazine = unknown regimen.
- **D-12:** Added agents disqualify: ABVD + any other agent is NOT ABVD (per SC7).
- **D-13:** Temporal availability rules: BV+AVD only for episodes starting post-2019, Nivo+AVD only post-2024 (per SC8).
- **D-14:** Non-matching chemotherapy episodes get regimen_label = NA (no label forced).

**Output Structure:**
- **D-15:** New standalone script R/61_episode_classification.R. Loads treatment_episodes.rds and treatment_episode_detail.rds, adds cancer linkage + regimen columns, saves treatment_episodes.rds back in-place. Does not modify R/44a or R/49.
- **D-16:** Columns added to treatment_episodes.rds: cancer_category, cancer_link_method, is_hodgkin, regimen_label.
- **D-17:** Standalone audit xlsx produced (following Phase 60 audit pattern) with sheets for: cancer linkage method distribution, cancer category frequency, regimen distribution, unlinked episode summary.
- **D-18:** Audit xlsx + flat CSV output to output/ directory.

### Claude's Discretion

- Drug name string matching strategy (base ingredient substrings vs explicit name lists, based on drug_name_lookup.rds contents)
- Column ordering for new columns in treatment_episodes.rds
- Audit xlsx sheet count, styling, and column layout
- Console logging detail level
- How to handle the BV+AVD regimen when both brentuximab AND bleomycin appear in the same episode (edge case)
- Whether to produce a CSV export alongside the audit xlsx
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LINK-01 | Cancer diagnosis linked to treatment episodes via ENCOUNTERID (direct match) | DuckDB DIAGNOSIS query with ENCOUNTERID join, PREFIX_MAP classification |
| LINK-02 | Temporal proximity fallback when ENCOUNTERID is NULL or missing (closest diagnosis within window) | Date arithmetic with lubridate, DX_DATE <= episode_start filter, 30-day window |
| LINK-03 | HL flag derived from encounter-level diagnosis, not patient-level | is_hodgkin = (cancer_category == "Hodgkin Lymphoma") after PREFIX_MAP classification |
| LINK-04 | Second cancer confirmation requires 2+ diagnoses 7 days apart (encounter-level) | Group by patient + cancer category, count distinct DX_DATE with 7-day threshold (Phase 55 pattern) |
| REG-01 | Treatment episodes labeled with regimen name (ABVD, BV+AVD, Nivo+AVD) based on drug composition | String detection in drug_names column (str_detect), regimen definition tables |
| REG-02 | Dropped-agent tolerance — ABVD with bleomycin dropped (→AVD) still classified as first-line | Conditional logic: if(dox & vin & dac & !bleo) → "ABVD" (AVD variant) |
| REG-03 | Nothing added — ABVD+X is not ABVD | Count unique drugs in episode, disqualify if > expected count for regimen |
| REG-04 | Temporal availability rules — BV+AVD post-2019, Nivo+AVD post-2024 | Filter episode_start >= as.Date("2019-01-01") for BV+AVD, >= as.Date("2024-01-01") for Nivo+AVD |
</phase_requirements>

## Standard Stack

### Core Libraries (Already in Project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data manipulation | Project standard for all transformations; used in every phase |
| glue | 1.8.0+ | String formatting | Project standard for logging messages |
| lubridate | 1.9.3+ | Date arithmetic | Project standard for date operations; needed for 30-day window calculation |
| openxlsx2 | 1.9+ | Excel audit workbook | Project standard for audit artifacts (Phases 55, 59, 62) |
| stringr | 1.5.1+ | String operations | Project standard; needed for drug name substring matching |

### Supporting (Already Available)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| vroom | 1.7.0+ | CSV loading | Only if CSV inputs needed (not expected for Phase 61) |

**Installation:**
No new packages required. All dependencies already installed per project renv.lock.

**Version verification:** Not required — all packages frozen in project renv.lock and verified in prior phases.

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 61_episode_classification.R  # NEW: Standalone script for cancer linkage + regimen detection
├── 00_config.R                  # REUSE: TREATMENT_CODES, PREFIX_MAP reference
├── utils_duckdb.R               # REUSE: get_pcornet_table(), open_pcornet_con()
├── utils_dates.R                # REUSE: parse_pcornet_date()
└── 44a_treatment_episodes.R     # REFERENCE: episode structure (NOT modified)

cache/outputs/
├── treatment_episodes.rds       # MODIFIED: + cancer_category, cancer_link_method, is_hodgkin, regimen_label
├── treatment_episode_detail.rds # READ ONLY: per-date encounter IDs
├── drug_name_lookup.rds         # READ ONLY: code → drug name mapping (Phase 60)
└── confirmed_hl_cohort.rds      # READ ONLY: 7-day HL confirmation (Phase 55)

output/
├── episode_classification_audit.xlsx  # NEW: Multi-sheet audit workbook
└── episode_classification_audit.csv   # NEW (optional): Flat export
```

### Pattern 1: RDS Enrichment (Phase 60 Pattern)
**What:** Load artifact RDS, add columns, save in-place
**When to use:** Adding metadata to existing episode/cohort data
**Example:**
```r
# Phase 60 pattern for reference
episodes <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))

# Add new columns
episodes <- episodes %>%
  mutate(
    cancer_category = NA_character_,
    cancer_link_method = NA_character_,
    is_hodgkin = FALSE,
    regimen_label = NA_character_
  )

# Save back in-place
saveRDS(episodes, file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))
```

### Pattern 2: Two-Tier Linkage (ENCOUNTERID → Temporal Fallback)
**What:** Try direct join first, fall back to temporal proximity for unmatched rows
**When to use:** Linking episodes to diagnoses when ENCOUNTERID population is incomplete (39-90% per site)
**Example:**
```r
# STEP 1: Extract unique encounter IDs from episodes
# treatment_episodes.rds has encounter_ids column (comma-separated)
# Need to unnest for join
episode_encounters <- episodes %>%
  mutate(encounter_ids_list = str_split(encounter_ids, ",")) %>%
  unnest(cols = encounter_ids_list) %>%
  filter(!is.na(encounter_ids_list) & encounter_ids_list != "") %>%
  select(patient_id, episode_number, treatment_type, encounter_ids_list) %>%
  rename(ENCOUNTERID = encounter_ids_list)

# STEP 2: Direct ENCOUNTERID match
diagnosis_data <- get_pcornet_table("DIAGNOSIS") %>%
  filter(!is.na(ENCOUNTERID)) %>%
  filter(str_sub(DX, 1, 1) == "C") %>%  # Malignant only (D-codes excluded)
  select(ID, ENCOUNTERID, DX, DX_DATE, DX_TYPE, PDX) %>%
  collect() %>%
  mutate(DX_DATE = parse_pcornet_date(DX_DATE))

# Join on ENCOUNTERID
encounters_linked <- episode_encounters %>%
  inner_join(diagnosis_data, by = "ENCOUNTERID")

# Classify cancer codes
encounters_linked <- encounters_linked %>%
  mutate(
    prefix = str_sub(DX, 1, 3),
    cancer_category = PREFIX_MAP[prefix],
    cancer_link_method = "encounter_id"
  )

# STEP 3: Temporal fallback for unlinked episodes
# Identify episodes with no ENCOUNTERID match
episodes_unlinked <- episodes %>%
  anti_join(encounters_linked, by = c("patient_id", "episode_number", "treatment_type"))

# Get all diagnoses for these patients with DX_DATE
temporal_candidates <- get_pcornet_table("DIAGNOSIS") %>%
  filter(ID %in% !!episodes_unlinked$patient_id) %>%
  filter(str_sub(DX, 1, 1) == "C") %>%
  select(ID, DX, DX_DATE) %>%
  collect() %>%
  mutate(DX_DATE = parse_pcornet_date(DX_DATE)) %>%
  filter(!is.na(DX_DATE))

# For each unlinked episode, find closest diagnosis within 30 days before episode_start
temporal_linked <- episodes_unlinked %>%
  left_join(temporal_candidates, by = c("patient_id" = "ID")) %>%
  filter(DX_DATE <= episode_start) %>%  # Backward only (D-03)
  mutate(days_before = as.numeric(episode_start - DX_DATE)) %>%
  filter(days_before <= 30) %>%  # 30-day window (D-02)
  mutate(
    prefix = str_sub(DX, 1, 3),
    cancer_category = PREFIX_MAP[prefix],
    is_hl = (cancer_category == "Hodgkin Lymphoma")
  ) %>%
  group_by(patient_id, episode_number, treatment_type) %>%
  arrange(days_before, desc(is_hl)) %>%  # Closest first, prefer HL (D-04)
  slice(1) %>%
  ungroup() %>%
  mutate(cancer_link_method = "closest_date")

# STEP 4: Combine and merge back to episodes
all_linked <- bind_rows(
  encounters_linked %>% select(patient_id, episode_number, treatment_type, cancer_category, cancer_link_method),
  temporal_linked %>% select(patient_id, episode_number, treatment_type, cancer_category, cancer_link_method)
)

# Left join back to episodes (unmatched get NA)
episodes <- episodes %>%
  left_join(all_linked, by = c("patient_id", "episode_number", "treatment_type")) %>%
  mutate(
    cancer_link_method = if_else(is.na(cancer_link_method), "none", cancer_link_method),
    is_hodgkin = (cancer_category == "Hodgkin Lymphoma")
  )
```

### Pattern 3: Regimen Detection via Drug Name String Matching
**What:** Match comma-separated drug_names against regimen definitions with dropped-agent tolerance
**When to use:** Labeling chemotherapy episodes with specific regimen names
**Example:**
```r
# Regimen definitions (drug name substrings to detect)
# Based on drug_name_lookup.rds — RxNorm returns names like "doxorubicin hydrochloride"
# Use base ingredient substrings for robust matching

regimen_defs <- tribble(
  ~regimen, ~required_drugs, ~dropped_ok,
  "ABVD", c("doxorubicin", "bleomycin", "vinblastine", "dacarbazine"), "bleomycin",
  "BV+AVD", c("brentuximab", "doxorubicin", "vinblastine", "dacarbazine"), NA_character_,
  "Nivo+AVD", c("nivolumab", "doxorubicin", "vinblastine", "dacarbazine"), NA_character_
)

# Helper: Check if drug_names contains a substring (case-insensitive)
has_drug <- function(drug_names, drug_substring) {
  str_detect(tolower(drug_names), tolower(drug_substring))
}

# Classify regimens
episodes <- episodes %>%
  mutate(
    # ABVD: all 4 OR AVD variant (dox+vin+dac, no bleo) (D-11)
    has_dox = has_drug(drug_names, "doxorubicin"),
    has_bleo = has_drug(drug_names, "bleomycin"),
    has_vin = has_drug(drug_names, "vinblastine"),
    has_dac = has_drug(drug_names, "dacarbazine"),
    has_brex = has_drug(drug_names, "brentuximab"),
    has_nivo = has_drug(drug_names, "nivolumab"),

    # Count unique drugs (for added-agent disqualification)
    n_unique_drugs = str_count(drug_names, ",") + 1,

    # ABVD or AVD variant (dropped bleomycin OK)
    is_abvd = (has_dox & has_vin & has_dac & !has_brex & !has_nivo),

    # BV+AVD (post-2019 only)
    is_bv_avd = (has_brex & has_dox & has_vin & has_dac & !has_bleo &
                 episode_start >= as.Date("2019-01-01")),

    # Nivo+AVD (post-2024 only)
    is_nivo_avd = (has_nivo & has_dox & has_vin & has_dac & !has_bleo &
                   episode_start >= as.Date("2024-01-01")),

    # Added-agent disqualification (D-12)
    # ABVD should be 3-4 drugs (AVD=3, ABVD=4)
    # BV+AVD / Nivo+AVD should be exactly 4 drugs
    abvd_valid = is_abvd & n_unique_drugs <= 4,
    bv_avd_valid = is_bv_avd & n_unique_drugs == 4,
    nivo_avd_valid = is_nivo_avd & n_unique_drugs == 4,

    # Final regimen label
    regimen_label = case_when(
      bv_avd_valid ~ "BV+AVD",
      nivo_avd_valid ~ "Nivo+AVD",
      abvd_valid ~ "ABVD",
      TRUE ~ NA_character_
    )
  ) %>%
  select(-starts_with("has_"), -starts_with("is_"), -ends_with("_valid"), -n_unique_drugs)
```

### Pattern 4: Multi-Sheet Audit Workbook (Phase 59 Pattern)
**What:** openxlsx2 workbook with styled header, multiple summary sheets
**When to use:** All audit artifacts
**Example:**
```r
# Source: R/59_death_date_validation.R lines 374-392
wb <- wb_workbook()

# Sheet 1: Summary
wb$add_worksheet("Linkage Summary")
wb$add_data(sheet = "Linkage Summary", x = "Episode Classification Audit",
            start_row = 1, start_col = 1)
wb$add_font(sheet = "Linkage Summary", dims = "A1",
            name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Linkage Summary", dims = "A1:D1")

subtitle <- glue("Generated: {Sys.Date()} | Episodes: {nrow(episodes)}")
wb$add_data(sheet = "Linkage Summary", x = subtitle, start_row = 2, start_col = 1)
wb$add_font(sheet = "Linkage Summary", dims = "A2",
            name = "Calibri", size = 10, color = wb_color("FF6B7280"))
wb$merge_cells(sheet = "Linkage Summary", dims = "A2:D2")

# Add summary data table starting row 4
summary_data <- tribble(
  ~Metric, ~Count,
  "Total episodes", nrow(episodes),
  "Linked via ENCOUNTERID", sum(episodes$cancer_link_method == "encounter_id", na.rm = TRUE),
  "Linked via temporal fallback", sum(episodes$cancer_link_method == "closest_date", na.rm = TRUE),
  "Unlinked", sum(episodes$cancer_link_method == "none", na.rm = TRUE)
)

wb$add_data(sheet = "Linkage Summary", x = summary_data, start_row = 4)

# Save workbook
wb_save(wb, file.path(CONFIG$output_dir, "episode_classification_audit.xlsx"))
```

### Anti-Patterns to Avoid
- **Don't modify R/44a_treatment_episodes.R:** Phase 61 is standalone (D-15). Cancer linkage is a separate enrichment step, not part of episode extraction.
- **Don't link to TUMOR_REGISTRY for encounter-level linkage:** TUMOR_REGISTRY has no ENCOUNTERID and limited DX_DATE granularity (D-05). Use DIAGNOSIS table only.
- **Don't classify regimens at cycle level:** Regimen detection operates at full episode level — all drugs anywhere in episode (D-09).
- **Don't allow added agents to ABVD:** ABVD + any other drug disqualifies the episode from ABVD classification (D-12).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ICD-10-CM prefix → cancer category mapping | Custom nested case_when | PREFIX_MAP named vector (R/49 lines 120-379) | Already defined, tested, and used in R/49 gantt export; 380-line comprehensive mapping |
| Date parsing with multiple formats | Custom strptime wrappers | parse_pcornet_date() (R/utils_dates.R) | Project standard; handles OneFlorida+ date format variations |
| DuckDB connection management | Direct dbConnect/dbDisconnect | open_pcornet_con(), close_pcornet_con(), get_pcornet_table() | Project standard abstraction layer (Phase 30); handles read-only mode, TEMP views |
| Drug name lookup | Re-query RxNorm API | drug_name_lookup.rds (Phase 60 artifact) | Already cached; 100% of codes resolved for this cohort |
| Excel workbook styling | Manual cell formatting | openxlsx2 wb_workbook() + wb_add_font() pattern from R/59 | Project standard; consistent audit aesthetic |

**Key insight:** Phase 61 is **integration-heavy, not innovation-heavy**. Nearly every component exists — the value is in combining encounter linkage (new) with existing PREFIX_MAP (R/49), drug_name_lookup (Phase 60), and audit patterns (Phase 59).

## Common Pitfalls

### Pitfall 1: Unnesting encounter_ids Without Handling Empty Strings
**What goes wrong:** treatment_episodes.rds has encounter_ids as comma-separated strings. Some are "" (empty string) or NA. `str_split("", ",")` returns `list(c(""))` (one-element vector with empty string), not `list(character(0))`. After unnest(), this creates a row with ENCOUNTERID = "" which will fail to join or produce spurious matches.

**Why it happens:** str_split() always returns a non-empty vector, even for empty input.

**How to avoid:**
```r
episode_encounters <- episodes %>%
  mutate(encounter_ids_list = str_split(encounter_ids, ",")) %>%
  unnest(cols = encounter_ids_list) %>%
  filter(!is.na(encounter_ids_list) & encounter_ids_list != "")  # CRITICAL
```

**Warning signs:** Join produces 0 matches when ENCOUNTERID population is known to be 39-90%; or join produces matches for every episode (spurious "" matches).

### Pitfall 2: Temporal Fallback Without Deduplication Creates Duplicate Episodes
**What goes wrong:** A patient has 3 cancer diagnoses on the same date (or within 30 days). Temporal fallback join creates 3 rows for one episode. When merged back to episodes, you get duplicate rows or overwritten values.

**Why it happens:** left_join(diagnosis_data) without group_by/slice(1) produces Cartesian product when multiple diagnoses match.

**How to avoid:**
```r
temporal_linked <- episodes_unlinked %>%
  left_join(temporal_candidates, by = c("patient_id" = "ID")) %>%
  filter(DX_DATE <= episode_start, days_before <= 30) %>%
  group_by(patient_id, episode_number, treatment_type) %>%  # CRITICAL
  arrange(days_before, desc(is_hl)) %>%  # Closest first, prefer HL (D-04)
  slice(1) %>%  # Take only the best match
  ungroup()
```

**Warning signs:** nrow(all_linked) > nrow(episodes); episodes with duplicate patient_id + episode_number after merge.

### Pitfall 3: Drug Name Matching on Exact Strings (Not Substrings)
**What goes wrong:** drug_name_lookup.rds returns names like "doxorubicin hydrochloride" (RxNorm full name). Matching `drug_names == "doxorubicin"` will fail. Even `str_detect(drug_names, "doxorubicin")` can fail if case differs ("Doxorubicin").

**Why it happens:** RxNorm returns full chemical names with salts/formulations, and case varies.

**How to avoid:**
```r
has_drug <- function(drug_names, drug_substring) {
  str_detect(tolower(drug_names), tolower(drug_substring))  # Case-insensitive substring
}
```

**Warning signs:** Regimen detection produces 0 ABVD classifications when manual inspection of drug_names shows "doxorubicin hydrochloride, bleomycin sulfate, vinblastine sulfate, dacarbazine".

### Pitfall 4: Temporal Availability Rules Applied to Wrong Date
**What goes wrong:** BV+AVD approved 2018, widely adopted ~2019. If you filter on episode_stop >= 2019-01-01, you'll allow episodes that START in 2018 and end in 2019. The decision is about when treatment was initiated, not completed.

**Why it happens:** Misunderstanding of "post-2019" — refers to episode start date (treatment initiation), not end date.

**How to avoid:**
```r
is_bv_avd = (has_brex & has_dox & has_vin & has_dac &
             episode_start >= as.Date("2019-01-01"))  # Use episode_start, not episode_stop
```

**Warning signs:** BV+AVD episodes detected in 2018 (before adoption); audit shows BV+AVD start dates in 2017-2018.

### Pitfall 5: Added-Agent Disqualification Counting Comma-Separated Drugs Incorrectly
**What goes wrong:** drug_names = "doxorubicin, bleomycin, vinblastine, dacarbazine" has 3 commas. `str_count(drug_names, ",")` = 3. So n_unique_drugs = 3 + 1 = 4. BUT if drug_names = "doxorubicin" (single drug), str_count = 0, n_unique_drugs = 1. This is CORRECT. However, if drug_names = "" (empty string), str_count = 0, n_unique_drugs = 1 (WRONG — should be 0).

**Why it happens:** Comma counting assumes non-empty strings. Empty strings have 0 commas but are not 1 drug.

**How to avoid:**
```r
n_unique_drugs = if_else(drug_names == "" | is.na(drug_names),
                         0L,
                         as.integer(str_count(drug_names, ",") + 1))
```

**Warning signs:** Episodes with drug_names = NA classified as ABVD; regimen detection fails silently.

## Code Examples

Verified patterns from existing codebase:

### ENCOUNTERID Propagation (Phase 60 Pattern)
```r
# Source: R/44a_treatment_episodes.R lines 450-470 (Phase 60)
# Episode detail has per-date ENCOUNTERID
# Aggregate to comma-separated unique list per episode
episodes <- episode_detail %>%
  group_by(patient_id, treatment_type, episode_number) %>%
  summarise(
    encounter_ids = paste(sort(unique(ENCOUNTERID[!is.na(ENCOUNTERID)])), collapse = ","),
    .groups = "drop"
  )
```

### PREFIX_MAP Cancer Category Classification (R/49 Pattern)
```r
# Source: R/49_gantt_data_export.R lines 120-379
PREFIX_MAP <- c(
  "C00" = "Lip, Oral Cavity and Pharynx",
  "C01" = "Lip, Oral Cavity and Pharynx",
  # ... 380 lines total ...
  "C81" = "Hodgkin Lymphoma",
  "C82" = "Non-Hodgkin Lymphoma",
  "C83" = "Non-Hodgkin Lymphoma",
  # ... etc ...
)

# Source: R/49_gantt_data_export.R lines 383-387
classify_codes <- function(cancer_code) {
  prefix <- str_sub(cancer_code, 1, 3)
  PREFIX_MAP[prefix]
}
```

### DuckDB DIAGNOSIS Query
```r
# Source: R/55_cancer_summary_refined.R pattern
open_pcornet_con()

diagnosis_data <- get_pcornet_table("DIAGNOSIS") %>%
  filter(ID %in% !!patient_ids) %>%
  select(ID, ENCOUNTERID, DX, DX_DATE, DX_TYPE, PDX) %>%
  collect() %>%
  mutate(DX_DATE = parse_pcornet_date(DX_DATE))

close_pcornet_con()
```

### 7-Day Second Cancer Confirmation (Phase 55 Pattern)
```r
# Source: R/55_cancer_summary_refined.R lines 200-230 (adapted for encounter-level)
second_cancers <- diagnosis_data %>%
  filter(str_sub(DX, 1, 3) != "C81") %>%  # Non-HL cancers
  mutate(
    prefix = str_sub(DX, 1, 3),
    cancer_category = PREFIX_MAP[prefix]
  ) %>%
  group_by(ID, cancer_category) %>%
  arrange(DX_DATE) %>%
  mutate(
    days_since_first = as.numeric(DX_DATE - first(DX_DATE)),
    is_second_dx = (row_number() > 1 & days_since_first >= 7)
  ) %>%
  filter(any(is_second_dx)) %>%  # Keep only categories with 2+ diagnoses 7+ days apart
  ungroup()
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Patient-level cancer category (R/49) | Encounter-level cancer linkage | Phase 61 (v1.8) | Eliminates false linkage of unrelated cancers to HL treatment episodes |
| Manual drug code → name lookup | Cached RxNorm API lookup (drug_name_lookup.rds) | Phase 60 | Zero runtime API calls; 100% coverage for cohort codes |
| ICD DX codes for SCT detection | PROCEDURES/PRESCRIBING/DISPENSING only | Phase 60 | Tighter SCT detection (ICD codes too broad) |

**Deprecated/outdated:**
- R/49 patient-level cancer category linkage: Still exists for Gantt v1 backward compatibility, but Phase 63 (Gantt v2) will use encounter-level cancer_category from Phase 61.

## Open Questions

1. **BV+AVD with both brentuximab AND bleomycin in same episode**
   - What we know: Regimen definitions are mutually exclusive (brentuximab *replaces* bleomycin, not additive)
   - What's unclear: If both appear in drug_names, is this a protocol deviation, coding error, or separate treatment cycles?
   - Recommendation: Disqualify as ABVD and BV+AVD (added-agent rule D-12). Label as NA. Document count in audit xlsx for clinical review.

2. **Granularity of "added agents" disqualification**
   - What we know: ABVD + X is not ABVD (D-12)
   - What's unclear: Does "X" include supportive meds (anti-nausea, growth factors) or only other chemotherapy agents?
   - Recommendation: Since drug_name_lookup.rds only resolves chemo codes (D-06), "added agents" automatically scoped to chemo only. Supportive meds not captured.

3. **Second cancer confirmation at encounter level vs episode level**
   - What we know: SC4 requires 2+ diagnoses 7+ days apart at encounter level (D-07)
   - What's unclear: Does "encounter level" mean 2+ distinct ENCOUNTERID with same cancer category, or 2+ DX_DATE regardless of ENCOUNTERID?
   - Recommendation: Follow Phase 55 pattern — group by patient + cancer_category, count distinct DX_DATE >= 7 days apart. ENCOUNTERID is metadata, not part of confirmation logic.

## Validation Architecture

> Validation section included per config.json workflow.nyquist_validation default (not explicitly disabled).

### Test Framework
| Property | Value |
|----------|-------|
| Framework | None — R testing not yet established in project |
| Config file | None — see Wave 0 |
| Quick run command | N/A |
| Full suite command | N/A |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LINK-01 | ENCOUNTERID join produces cancer_category for matched episodes | unit | N/A — manual verification via audit xlsx | ❌ Wave 0 |
| LINK-02 | Temporal fallback within 30 days when ENCOUNTERID NULL | unit | N/A | ❌ Wave 0 |
| LINK-03 | is_hodgkin derived from encounter-level cancer_category | unit | N/A | ❌ Wave 0 |
| LINK-04 | Second cancer requires 2+ diagnoses 7+ days apart | unit | N/A | ❌ Wave 0 |
| REG-01 | Regimen labels assigned correctly for ABVD, BV+AVD, Nivo+AVD | unit | N/A | ❌ Wave 0 |
| REG-02 | AVD variant (no bleomycin) classified as ABVD | unit | N/A | ❌ Wave 0 |
| REG-03 | ABVD + added agents disqualified | unit | N/A | ❌ Wave 0 |
| REG-04 | Temporal availability rules enforced (BV+AVD post-2019, Nivo+AVD post-2024) | unit | N/A | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** Manual inspection of audit xlsx after script execution
- **Per wave merge:** Full audit xlsx review + spot-check treatment_episodes.rds
- **Phase gate:** Audit xlsx shows expected distributions; R/62 runs without regimen_label warnings

### Wave 0 Gaps
- [ ] R testing framework selection (testthat 3.x recommended for R projects, but not yet adopted)
- [ ] test/test-episode-classification.R — unit tests for regimen detection logic
- [ ] test/fixtures/ — sample treatment_episodes.rds with known regimen compositions
- [ ] CI integration — R CMD check or similar (not applicable to non-package R scripts)

*(Current validation strategy: Audit xlsx manual review + downstream script success (R/62). Formal testing deferred to future roadmap.)*

## Sources

### Primary (HIGH confidence)
- Project codebase:
  - R/44a_treatment_episodes.R — episode extraction, ENCOUNTERID propagation pattern
  - R/49_gantt_data_export.R lines 120-387 — PREFIX_MAP definition, classify_codes() function
  - R/55_cancer_summary_refined.R lines 200-230 — 7-day confirmation pattern for second cancers
  - R/59_death_date_validation.R lines 374-420 — openxlsx2 audit workbook pattern
  - R/60_drug_name_resolution.R — drug_name_lookup.rds artifact structure
  - R/62_first_line_and_death_analysis.R lines 78-81 — regimen_label guard for downstream consumption
  - R/00_config.R lines 419-427 — TREATMENT_CODES for ABVD, BV, Nivo
  - R/utils_duckdb.R — get_pcornet_table() dispatcher pattern
  - R/01_load_pcornet.R lines 44-61 — DIAGNOSIS table column spec (ENCOUNTERID, DX, DX_DATE)
- .planning/phases/61-episode-classification-cancer-linkage-and-regimen-detection/61-CONTEXT.md — User decisions from /gsd:discuss-phase (locked decisions D-01 through D-18)
- .planning/REQUIREMENTS.md — LINK-01 through LINK-04, REG-01 through REG-04

### Secondary (MEDIUM confidence)
- Clinical trial references (from 61-CONTEXT.md):
  - RATHL trial — randomized non-inferiority trial showing AVD (no bleomycin) non-inferior to ABVD after 2 cycles; establishes dropped-agent tolerance (D-11)
  - ECHELON-1 trial — BV+AVD FDA approval 2018, widely adopted ~2019; establishes temporal availability (D-13)
  - CheckMate 205/Keynote-204 derivatives — Nivo+AVD recent adoption ~2024; establishes temporal availability (D-13)

### Tertiary (LOW confidence)
- None — all research grounded in existing codebase patterns and user-provided context

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all packages already in project renv.lock, no new dependencies
- Architecture: HIGH - reuses existing patterns from Phases 55, 59, 60, 62 verbatim
- Pitfalls: HIGH - based on actual OneFlorida+ data characteristics (ENCOUNTERID 39-90% population, comma-separated string handling)

**Research date:** 2026-05-30
**Valid until:** 2026-06-30 (30 days — stable domain, established project patterns)
