# Architecture Patterns for Encounter-Level Cancer Linkage & First-Line Therapy Identification

**Domain:** Episode-Level Cancer Linkage, Regimen Identification
**Researched:** 2026-05-29
**Confidence:** HIGH (derived from existing codebase architecture)

## Executive Summary

The existing R pipeline architecture follows a linear numbered-script pattern (R/00 through R/59) with centralized configuration, DuckDB backend abstraction, and RDS caching for intermediate artifacts. Integration of encounter-level cancer linkage and first-line therapy regimen identification requires **minimal architectural changes** — new functionality fits within established patterns:

1. **ENCOUNTERID propagation** through treatment episode detection (modify R/44a)
2. **Encounter-level cancer diagnosis linkage** via new join logic (extend R/49 or new R/60)
3. **First-line regimen labeling** as a new post-processing script (new R/61)
4. **New Gantt output files** (R/49 variant with _v2 suffix or new R/62)
5. **SCT code tightening** (modify extraction logic in R/44a)

**Key principle:** Extend, don't replace. Preserve existing outputs for backward compatibility.

---

## Current Architecture Overview

### Script Numbering Pattern

```
R/00_config.R              # Configuration + TREATMENT_CODES lists
R/01_load_pcornet.R        # DuckDB table loading via get_pcornet_table()
R/44a_treatment_episodes.R # Episode detection (90-day window, triggering_codes)
R/49_gantt_data_export.R   # Gantt CSV generation (episodes + detail)
R/55_cancer_summary_refined.R # HL cohort confirmation, first_hl_dx_date
```

Scripts are **idempotent** (can be re-run) and **self-contained** (source dependencies explicitly).

### Data Flow (Current State)

```
DuckDB pcornet.duckdb
  ├── PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, DIAGNOSIS, ENCOUNTER
  │   └── (via get_pcornet_table("TABLE_NAME") in R/01)
  │
  ├── R/44a: Extract treatment dates WITH CODES
  │   ├─> Per-type extraction functions (extract_chemo_dates_with_codes, etc.)
  │   ├─> Stack and dedup on (ID, treatment_date, triggering_code)
  │   ├─> assign_episode_ids() with 90-day window from episode start
  │   └─> Output: treatment_episodes.rds (episode-level)
  │             treatment_episode_detail.rds (date+code level)
  │
  ├── R/55: Confirm HL cohort, compute first_hl_dx_date
  │   ├─> Filter to patients with 2+ C81 codes 7+ days apart
  │   ├─> Compute first_hl_dx_date from min(DIAGNOSIS, TUMOR_REGISTRY)
  │   └─> Output: confirmed_hl_cohort.rds (ID, first_hl_dx_date, source)
  │
  └── R/49: Gantt CSV export
      ├─> Join patient-level cancer_category from cancer_summary.csv
      ├─> Add death rows (pseudo-treatment type)
      ├─> Add HL Diagnosis rows (pseudo-treatment type)
      └─> Output: gantt_episodes.csv, gantt_detail.csv
```

**Missing from current architecture:**
- ENCOUNTERID tracking in episode detection
- Encounter-level cancer diagnosis linkage
- Regimen labeling logic
- First-line therapy detection

---

## Integration Point 1: ENCOUNTERID Propagation in Episode Detection

### Current State (R/44a_treatment_episodes.R)

Treatment dates extracted from 7 source types WITHOUT ENCOUNTERID:

```r
# Example: extract_chemo_dates_with_codes()
px_dates <- get_pcornet_table("PROCEDURES") %>%
  filter((PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) | ...) %>%
  select(ID, treatment_date = PX_DATE, triggering_code = PX) %>%
  collect()
```

**Output:** (ID, treatment_date, triggering_code)

### Required Change: Add ENCOUNTERID Column

```r
# Modified extraction (same tables, +1 column)
px_dates <- get_pcornet_table("PROCEDURES") %>%
  filter((PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) | ...) %>%
  select(ID, ENCOUNTERID, treatment_date = PX_DATE, triggering_code = PX) %>%
  collect()
```

**New output:** (ID, ENCOUNTERID, treatment_date, triggering_code)

### Impact on Episode Calculation

`calculate_episodes_detailed()` currently groups by (ID, episode_id) and aggregates:
- `triggering_codes = paste(sort(unique(na.omit(triggering_code))), collapse = ",")`

**Add parallel aggregation for ENCOUNTERID:**
- `encounter_ids = paste(sort(unique(na.omit(ENCOUNTERID))), collapse = ",")`

**Result:** Episode-level output gains `encounter_ids` column (comma-separated list).

### Data Source Coverage for ENCOUNTERID

| Source Table | Has ENCOUNTERID? | Fallback if NULL |
|--------------|------------------|------------------|
| PROCEDURES | Yes (always populated) | N/A |
| PRESCRIBING | Yes (may be NULL) | Use treatment_date for temporal join |
| DISPENSING | Yes (may be NULL) | Use treatment_date for temporal join |
| MED_ADMIN | Yes (may be NULL) | Use treatment_date for temporal join |
| DIAGNOSIS | Yes (always populated) | N/A |
| ENCOUNTER (DRG) | Primary key (ENCOUNTERID) | N/A |
| TUMOR_REGISTRY | No ENCOUNTERID column | Use treatment_date for temporal join |

**Recommendation:** Always include ENCOUNTERID in extraction, allow NAs, aggregate with `na.omit()`.

---

## Integration Point 2: Encounter-Level Cancer Diagnosis Linkage

### Current State (R/49_gantt_data_export.R)

Patient-level join from `cancer_summary.csv`:

```r
# Lines 390-402
cancer_categories_per_patient <- cancer_summary %>%
  group_by(ID) %>%
  summarise(
    cancer_category = paste(sort(unique(category)), collapse = ","),
    .groups = "drop"
  )

# Lines 536-540
episodes_export <- episodes %>%
  left_join(cancer_categories_per_patient, by = c("patient_id" = "ID"))
```

**Problem:** Conflates all cancer diagnoses for the patient (no temporal or encounter-specific linkage).

### Required Change: Encounter-Level Linkage

**New approach:** Join DIAGNOSIS to episodes via ENCOUNTERID (primary), fallback to closest date.

```r
# Step 1: Extract all cancer diagnoses with ENCOUNTERID and date
cancer_dx <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C")) %>%  # All C-codes
  select(ID, ENCOUNTERID, DX_DATE, DX_norm) %>%
  collect()

# Step 2: Classify codes
cancer_dx$category <- classify_codes(cancer_dx$DX_norm)

# Step 3: For each episode row, link cancer diagnoses
#   a. Match on (ID, ENCOUNTERID) if ENCOUNTERID in episode's encounter_ids
#   b. Fallback: match on ID, find diagnosis with min(abs(DX_DATE - episode_start))
#   c. Aggregate categories for the episode

# Pseudocode:
episodes_with_cancer <- episodes %>%
  rowwise() %>%
  mutate(
    linked_cancer_dx = link_cancer_to_episode(
      patient_id, encounter_ids, episode_start, cancer_dx
    )
  )
```

**New columns in episode output:**
- `cancer_category` (episode-specific, not patient-level)
- `cancer_link_method` ("encounter_id" | "closest_date" | "none")
- `is_hodgkin` (TRUE if "Hodgkin Lymphoma" in episode's cancer_category)

### Implementation Pattern

**Option A: Extend R/49** (Gantt export script)
- Add encounter-level linkage logic before writing CSVs
- Replace patient-level join with episode-level join
- Preserve backward compatibility by checking for `encounter_ids` column

**Option B: New R/60_encounter_cancer_linkage.R**
- Standalone script that enhances `treatment_episodes.rds`
- Output: `treatment_episodes_with_cancer.rds`
- R/49 consumes the enhanced RDS instead of original

**Recommendation:** Option A (extend R/49) for simplicity. Use helper function `link_cancer_to_episode()` defined in-script.

---

## Integration Point 3: First-Line Therapy Regimen Labeling

### Requirements

- **Age filter:** Adults 21+ at first HL diagnosis
- **Regimen definitions:**
  - ABVD: doxorubicin + bleomycin + vinblastine + dacarbazine
  - BV+AVD: brentuximab vedotin + doxorubicin + vinblastine + dacarbazine
  - Nivo+AVD: nivolumab + doxorubicin + vinblastine + dacarbazine
- **Cycle matching:** 28-day cycles, agents may be dropped (ABVD→AVD allowed)
- **First-line definition:** Treatment episodes AFTER HL diagnosis, no other regimens first

### Data Requirements

1. **Age at diagnosis:** Join DEMOGRAPHIC (BIRTH_DATE) with confirmed_hl_cohort (first_hl_dx_date)
2. **Drug-level detail:** Use `treatment_episode_detail.rds` (has triggering_code per date)
3. **RxNorm to drug name mapping:** Build from TREATMENT_CODES$chemo_rxnorm + manual curation

### Architecture Pattern: New R/61_first_line_regimen_labeling.R

```
Inputs:
  - cache/outputs/treatment_episodes.rds
  - cache/outputs/treatment_episode_detail.rds
  - cache/outputs/confirmed_hl_cohort.rds
  - DuckDB DEMOGRAPHIC (for age calculation)
  - New: REGIMEN_DEFINITIONS in R/00_config.R (RxNorm CUI -> drug name)

Process:
  1. Filter to adults 21+ at first HL diagnosis
  2. Filter to chemotherapy episodes AFTER first_hl_dx_date
  3. For each episode, extract unique drug names from triggering_codes
  4. Match against regimen definitions (allow subset matching for dropped agents)
  5. Classify episode as ABVD | BV+AVD | Nivo+AVD | Other
  6. Identify first-line episodes (earliest regimen post-diagnosis per patient)

Output:
  - cache/outputs/regimen_labeled_episodes.rds
    Columns: patient_id, treatment_type, episode_number, regimen_label, is_first_line
```

**Integration with Gantt export:** R/49 can optionally join regimen_labeled_episodes.rds to add `regimen_label` column to output.

### Regimen Matching Logic (Pseudocode)

```r
# In R/61
REGIMEN_DEFINITIONS <- list(
  ABVD = list(
    required = c("doxorubicin", "bleomycin", "vinblastine", "dacarbazine"),
    allow_subset = TRUE  # AVD = ABVD with bleomycin dropped
  ),
  BV_AVD = list(
    required = c("brentuximab vedotin", "doxorubicin", "vinblastine", "dacarbazine"),
    allow_subset = TRUE
  ),
  Nivo_AVD = list(
    required = c("nivolumab", "doxorubicin", "vinblastine", "dacarbazine"),
    allow_subset = TRUE
  )
)

classify_regimen <- function(episode_drugs, definitions) {
  for (regimen_name in names(definitions)) {
    required <- definitions[[regimen_name]]$required
    if (all(required %in% episode_drugs)) return(regimen_name)
    if (definitions[[regimen_name]]$allow_subset) {
      # At least 3 of 4 required drugs (allow 1 dropped)
      if (sum(required %in% episode_drugs) >= length(required) - 1) {
        return(paste0(regimen_name, " (partial)"))
      }
    }
  }
  return("Other")
}
```

---

## Integration Point 4: New Gantt Output Files

### Current State

R/49 outputs:
- `output/gantt_episodes.csv`
- `output/gantt_detail.csv`

**Problem:** Overwriting existing outputs breaks backward compatibility with external Gantt tools.

### Required Change: Versioned Output Files

**Option A: Version suffix**
```r
OUTPUT_EPISODES_V2 <- file.path(CONFIG$output_dir, "gantt_episodes_v2.csv")
OUTPUT_DETAIL_V2   <- file.path(CONFIG$output_dir, "gantt_detail_v2.csv")
```

**Option B: Separate subdirectory**
```r
OUTPUT_DIR_V2 <- file.path(CONFIG$output_dir, "gantt_v2")
dir.create(OUTPUT_DIR_V2, showWarnings = FALSE, recursive = TRUE)
OUTPUT_EPISODES_V2 <- file.path(OUTPUT_DIR_V2, "gantt_episodes.csv")
OUTPUT_DETAIL_V2   <- file.path(OUTPUT_DIR_V2, "gantt_detail.csv")
```

**Recommendation:** Option A (suffix) for discoverability. External tools can easily find both versions.

### Implementation Pattern

**New script: R/62_gantt_export_v2.R** (clone of R/49 with enhancements)

Differences from R/49:
1. Read from `regimen_labeled_episodes.rds` instead of `treatment_episodes.rds`
2. Use encounter-level cancer linkage (not patient-level)
3. Add `regimen_label`, `cancer_link_method` columns
4. Output to `gantt_episodes_v2.csv`, `gantt_detail_v2.csv`
5. Preserve R/49 unchanged (backward compatibility)

**Alternative:** Add flag to R/49 for output format version:
```r
OUTPUT_VERSION <- 2  # Set to 1 for original format, 2 for enhanced
```

**Recommendation:** New R/62 script for clarity (follows project pattern of clone-and-enhance for variants).

---

## Integration Point 5: SCT Code Tightening (Drop ICD Diagnosis Codes)

### Current State (R/44a_treatment_episodes.R, lines 295-321)

SCT extraction includes DIAGNOSIS table:

```r
# 2. DIAGNOSIS: Z94.84/T86.5/T86.09/Z48.290/T86.0 (ICD-10 only) — bare DX code
dx_dates <- NULL
if (!is.null(get_pcornet_table("DIAGNOSIS"))) {
  dx_dates <- get_pcornet_table("DIAGNOSIS") %>%
    filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
    filter(!is.na(DX_DATE)) %>%
    select(ID, treatment_date = DX_DATE, triggering_code = DX) %>%
    collect()
}
```

### Required Change: Comment Out DIAGNOSIS Source

```r
# 2. DIAGNOSIS: REMOVED per v1.8 (diagnosis codes indicate history/status, not procedure)
# Diagnosis codes like Z94.84 (bone marrow transplant status) are post-SCT documentation,
# not evidence of SCT procedure occurrence. SCT detection now uses PROCEDURES, PRESCRIBING,
# DISPENSING only (procedural evidence sources).
dx_dates <- NULL
```

**Impact:**
- `extract_sct_dates_with_codes()` returns fewer dates
- Episode detection still works (PROCEDURES, ENCOUNTER DRGs remain)
- Triggering codes in SCT episodes will exclude Z94.84, T86.5, etc.

**Validation:** Compare SCT episode counts before/after change. Document difference in script header.

---

## Component Boundaries and Dependencies

### Modified Components

| Component | Type | Modification | Backward Compatible? |
|-----------|------|--------------|----------------------|
| R/44a (episode detection) | Modify | Add ENCOUNTERID, drop SCT DX codes | Yes (new column, existing columns unchanged) |
| R/49 (Gantt export) | Modify OR clone | Encounter-level cancer linkage | No (output schema changes) |
| R/00_config.R | Extend | Add REGIMEN_DEFINITIONS | Yes (new config, existing untouched) |

### New Components

| Component | Type | Purpose | Consumes | Produces |
|-----------|------|---------|----------|----------|
| R/60_encounter_cancer_linkage.R | New (optional) | Link cancer dx to episodes | treatment_episodes.rds, DIAGNOSIS | treatment_episodes_with_cancer.rds |
| R/61_first_line_regimen_labeling.R | New | Classify first-line therapy | treatment_episode_detail.rds, confirmed_hl_cohort.rds | regimen_labeled_episodes.rds |
| R/62_gantt_export_v2.R | New (clone of R/49) | Enhanced Gantt CSVs | regimen_labeled_episodes.rds | gantt_episodes_v2.csv, gantt_detail_v2.csv |

### Dependency Graph

```
DuckDB (DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC)
  │
  ├─> R/44a (modified: +ENCOUNTERID, -SCT DX codes)
  │    └─> treatment_episodes.rds, treatment_episode_detail.rds
  │
  ├─> R/55 (unchanged)
  │    └─> confirmed_hl_cohort.rds
  │
  ├─> [NEW] R/60 (optional: encounter-level cancer linkage)
  │    │─> Input: treatment_episodes.rds, DIAGNOSIS
  │    └─> Output: treatment_episodes_with_cancer.rds
  │
  ├─> [NEW] R/61 (regimen labeling)
  │    │─> Input: treatment_episode_detail.rds, confirmed_hl_cohort.rds, DEMOGRAPHIC
  │    └─> Output: regimen_labeled_episodes.rds
  │
  ├─> R/49 (unchanged, original Gantt)
  │    └─> gantt_episodes.csv, gantt_detail.csv
  │
  └─> [NEW] R/62 (enhanced Gantt)
       │─> Input: regimen_labeled_episodes.rds, [cancer linkage data]
       └─> Output: gantt_episodes_v2.csv, gantt_detail_v2.csv
```

**Execution order:**
1. R/44a (episode detection with ENCOUNTERID)
2. R/55 (HL cohort confirmation)
3. R/60 (encounter-level cancer linkage, optional)
4. R/61 (regimen labeling)
5. R/49 (original Gantt, unchanged)
6. R/62 (enhanced Gantt v2)

---

## Data Schema Changes

### treatment_episodes.rds (R/44a output, enhanced)

**Current columns:**
```
patient_id, treatment_type, episode_number, episode_start, episode_stop,
episode_length_days, distinct_dates_in_episode, historical_flag, triggering_codes
```

**New columns (add to end for backward compatibility):**
```
encounter_ids  # Comma-separated ENCOUNTERIDs (from all dates in episode)
```

**Schema version:** v2 (column added, existing columns unchanged)

### regimen_labeled_episodes.rds (R/61 output, new artifact)

**Columns:**
```
patient_id, treatment_type, episode_number, episode_start, episode_stop,
episode_length_days, distinct_dates_in_episode, historical_flag,
triggering_codes, encounter_ids,
regimen_label,        # "ABVD" | "BV+AVD" | "Nivo+AVD" | "ABVD (partial)" | "Other"
is_first_line,        # TRUE if earliest regimen post-diagnosis for this patient
age_at_diagnosis,     # Age in years when first HL diagnosed
drugs_in_episode      # Comma-separated drug names (for QA)
```

**Subset of treatment_episodes:** Only chemotherapy episodes for adults 21+ post-diagnosis.

### gantt_episodes_v2.csv (R/62 output, enhanced Gantt)

**New columns vs. gantt_episodes.csv:**
```
encounter_ids           # From enhanced treatment_episodes
cancer_category         # Encounter-level (not patient-level)
cancer_link_method      # "encounter_id" | "closest_date" | "none"
is_hodgkin              # Episode-specific HL flag
regimen_label           # For chemotherapy episodes only
is_first_line           # For regimen-labeled episodes only
```

**Schema change:** Additional columns at end, existing columns preserved.

---

## Build Order and Phasing Strategy

### Phase 60: ENCOUNTERID Propagation + SCT Code Tightening
**Scope:** Modify R/44a only
**Output:** Enhanced treatment_episodes.rds with `encounter_ids` column
**Validation:** Compare episode counts before/after. SCT episodes should decrease (DX codes removed).

**Acceptance criteria:**
- `encounter_ids` column populated for PROCEDURES, PRESCRIBING, ENCOUNTER sources
- SCT episodes exclude Z94.84, T86.5, etc. triggering codes
- Backward compatibility: existing columns unchanged

---

### Phase 61: First-Line Therapy Regimen Labeling
**Scope:** New R/61_first_line_regimen_labeling.R
**Dependencies:** Phase 60 (for encounter_ids), R/55 (for confirmed_hl_cohort.rds)
**Output:** regimen_labeled_episodes.rds

**Acceptance criteria:**
- Age filter at 21+ years at first HL diagnosis
- Regimen classification for ABVD, BV+AVD, Nivo+AVD (with partial matching)
- First-line flag based on chronological order post-diagnosis
- QA table: regimen distribution, first-line vs. subsequent

---

### Phase 62: Encounter-Level Cancer Linkage
**Scope:** Extend R/49 OR new R/60
**Dependencies:** Phase 60 (for encounter_ids)
**Output:** Encounter-level cancer categories in Gantt export

**Option A (recommended):** Extend R/49 with encounter-level linkage logic
**Option B:** New R/60 produces treatment_episodes_with_cancer.rds, R/62 consumes it

**Acceptance criteria:**
- Cancer categories linked via ENCOUNTERID (primary) or closest date (fallback)
- `cancer_link_method` column documents linkage type
- QA: Compare patient-level vs. encounter-level HL flags (expect changes)

---

### Phase 63: Enhanced Gantt Export (v2)
**Scope:** New R/62_gantt_export_v2.R
**Dependencies:** Phase 61 (regimen labels), Phase 62 (encounter cancer linkage)
**Output:** gantt_episodes_v2.csv, gantt_detail_v2.csv

**Acceptance criteria:**
- Preserves R/49 output (gantt_episodes.csv unchanged)
- New columns: encounter_ids, regimen_label, is_first_line, cancer_link_method
- QA: Row counts match between v1 and v2 (same episodes, enhanced columns)

---

## Architectural Patterns to Follow

### 1. Clone-and-Enhance for Variants
**Pattern:** When modifying existing outputs, clone the script with version suffix (R/49 → R/62) rather than modifying in place.
**Rationale:** Preserves backward compatibility with external tools, allows side-by-side comparison.
**Example:** R/33 (multi-source overlap baseline) → R/33_multi_source_overlap_av_th.R (AV+TH subset)

### 2. RDS Artifacts for Intermediate Products
**Pattern:** Save intermediate results as .rds files in `cache/outputs/`.
**Rationale:** Enables downstream scripts to consume enriched data without re-running entire pipeline.
**Example:** treatment_episodes.rds, confirmed_hl_cohort.rds, [new] regimen_labeled_episodes.rds

### 3. Centralized Configuration in R/00_config.R
**Pattern:** All code lists, thresholds, and mappings in R/00_config.R.
**Rationale:** Single source of truth, enables global changes without script edits.
**Example:** TREATMENT_CODES list, [new] REGIMEN_DEFINITIONS

### 4. Backend Abstraction via get_pcornet_table()
**Pattern:** Use `get_pcornet_table("TABLE_NAME")` for all data access, never direct DuckDB SQL.
**Rationale:** Enables RDS fallback, future backend changes transparent to scripts.
**Example:** `get_pcornet_table("DIAGNOSIS") %>% filter(...)`

### 5. Semantic Versioning for Output Schemas
**Pattern:** When adding columns, append to end. Document version in script header.
**Rationale:** Tools expecting original schema continue working, new consumers opt into enhanced columns.
**Example:** treatment_episodes.rds v1 (9 cols) → v2 (10 cols, +encounter_ids)

### 6. In-Script Helper Functions for Complex Logic
**Pattern:** Define reusable logic as functions within the script (not in utils files unless used by 3+ scripts).
**Rationale:** Keeps related code together, avoids premature abstraction.
**Example:** `classify_regimen()`, `link_cancer_to_episode()` defined in R/61, R/62 respectively

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| ENCOUNTERID missing in key sources (PRESCRIBING, DISPENSING) | Medium | Medium | Allow NAs, aggregate with na.omit(), fallback to date-based linkage |
| Regimen drug name mapping incomplete | High | Medium | Start with known RxNorm CUIs in TREATMENT_CODES, manual curation for BV/Nivo |
| Encounter-level linkage produces different HL cohort | High | High | QA: Compare patient-level vs. encounter-level HL flags, document differences |
| New Gantt v2 schema breaks external tools | Low | High | Preserve v1 outputs, version new files clearly (_v2 suffix) |
| First-line classification ambiguous for multi-regimen episodes | Medium | Medium | Require single regimen per episode, flag ambiguous cases for review |

---

## Performance Considerations

| Operation | Expected Complexity | Notes |
|-----------|---------------------|-------|
| ENCOUNTERID extraction | O(n) where n = treatment rows | Same as current triggering_code extraction |
| Encounter-level cancer join | O(n*m) where n = episodes, m = diagnoses/patient | Use rowwise() + vectorized date difference |
| Regimen classification | O(k*d) where k = chemo episodes, d = drugs/episode | Small k (adults 21+ chemo only), small d (<10 drugs/episode) |
| Gantt CSV export | O(n) | Same as current R/49 (just more columns) |

**Bottleneck risk:** LOW. All operations linear or small-set pattern matching. DuckDB backend already optimized.

---

## Testing Strategy

### Unit-Level Validation

1. **ENCOUNTERID propagation:** Verify encounter_ids populated for all non-TUMOR_REGISTRY sources
2. **SCT code tightening:** Confirm Z94.84, T86.5 absent from SCT triggering_codes
3. **Regimen classification:** Test classify_regimen() with known drug combinations
4. **First-line detection:** Verify chronological ordering post-diagnosis

### Integration-Level Validation

1. **Episode count parity:** treatment_episodes.rds row count before/after Phase 60 should match (same episodes, +1 column)
2. **Gantt v1 vs. v2 row parity:** gantt_episodes.csv and gantt_episodes_v2.csv same row counts (same episodes, enhanced columns)
3. **HL flag comparison:** Patient-level HL flags (current) vs. encounter-level HL flags (new) — document differences

### QA Tables to Produce

1. **Phase 60 QA:** Episode counts by treatment type (before/after SCT code removal)
2. **Phase 61 QA:** Regimen distribution (ABVD, BV+AVD, Nivo+AVD, Other), first-line vs. subsequent
3. **Phase 62 QA:** Cancer linkage method distribution (encounter_id vs. closest_date vs. none)
4. **Phase 63 QA:** Gantt v1 vs. v2 schema comparison table

---

## Open Questions for Implementation

1. **Encounter-level cancer linkage fallback:** When ENCOUNTERID match fails, what date window for "closest diagnosis"? (Recommendation: +/- 30 days from episode_start)
2. **Partial regimen matching threshold:** ABVD→AVD allowed (3 of 4 drugs). Should BV+AVD→BV+AD (missing vinblastine) also count? (Recommendation: Require 3 of 4, flag as "partial")
3. **First-line classification:** If patient has ABVD episode and BV+AVD episode on same date, which is first-line? (Recommendation: Both flagged, manual review for multi-regimen same-date cases)
4. **Death date analysis table:** Where does this fit? R/59 already produces validated_death_dates.rds. (Recommendation: New R/64_death_date_analysis.R for summary table, separate from Gantt integration)

---

## Sources

**HIGH confidence** — All findings derived from existing codebase analysis:

- R/44a_treatment_episodes.R (lines 1-961): Episode detection architecture, triggering_codes pattern
- R/49_gantt_data_export.R (lines 1-785): Gantt export architecture, patient-level cancer join
- R/55_cancer_summary_refined.R (lines 1-859): HL cohort confirmation, first_hl_dx_date computation
- R/00_config.R (lines 1-200): Configuration centralization pattern, TREATMENT_CODES structure
- R/01_load_pcornet.R (lines 1-200): DuckDB backend abstraction, table schema specifications
- .planning/PROJECT.md: Milestone context, feature requirements, out-of-scope boundaries

**No external research required** — all patterns extracted from existing working code.
