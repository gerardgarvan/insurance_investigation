# Phase 93: Cross-Use Flag Implementation - Research

**Researched:** 2026-06-08
**Domain:** Temporal date arithmetic, data frame enrichment, boolean flag aggregation (R/dplyr)
**Confidence:** HIGH

## Summary

Phase 93 adds two annotation columns to treatment_episodes.rds: (1) `is_sct_conditioning_context` — a temporal boolean flag marking chemotherapy episodes within 30 days before SCT episode start, and (2) `immuno_confidence` — a categorical flag distinguishing 8 vitamin combo codes from 3 CAR-T codes with classification ambiguity. Both columns are metadata annotations alongside existing `treatment_type`, not reclassifications. The implementation follows Phase 91's xlsx metadata enrichment pattern (named vector lookups with `sapply()` over comma-separated triggering codes) and extends the Gantt v2 schema from 21/19 columns to 22/20 columns.

**Primary recommendation:** Use lubridate's `as.numeric(difftime())` for day calculations (established pattern from R/02 payer harmonization), aggregate questionable codes via Phase 91's `aggregate_cross_use_flag()` pattern with any-positive logic, and add defensive column fallback in R/52 matching Phase 92's pattern (lines 205-219).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**SCT Conditioning Temporal Context:**
- **D-01:** 30-day window hardcoded (not configurable). Chemotherapy episodes with triggering codes within 30 days before SCT episode start get `is_sct_conditioning_context = TRUE`.
- **D-02:** Applies to chemotherapy episodes only. Immunotherapy near SCT is NOT flagged.
- **D-03:** Output format: boolean `is_sct_conditioning_context` (TRUE/FALSE) in Gantt CSVs; additionally `days_to_nearest_sct` integer column in treatment_episodes.rds only (not exported to CSVs). Gives analysts re-thresholding flexibility.
- **D-04:** NA for non-chemotherapy episodes in both columns.

**Questionable Code Identification:**
- **D-05:** Hardcoded named vector `QUESTIONABLE_IMMUNO_CODES` in R/00_config.R mapping code to reason string.
- **D-06:** 8 multivitamin codes flagged as "questionable-vitamin": 891815, 891790, 1090823, 1313925, 1248142, 891716, 1090824, 891793.
- **D-07:** 3 CAR-T codes flagged as "questionable-CAR-T vs immunotherapy": 2479140 (Lisocabtagene Maraleucel RxNorm), XW033C3, XW043C3 (ICD-10-PCS procedure codes).
- **D-08:** Total: 11 questionable codes (8 vitamin + 3 CAR-T), not 10 as originally estimated.

**Confidence Column Design:**
- **D-09:** New standalone column `immuno_confidence` — separate from existing `sct_cross_use_flag`.
- **D-10:** Column values: NA (not questionable), "questionable-vitamin" (IMMU-02), "questionable-CAR-T vs immunotherapy" (IMMU-02).
- **D-11:** New column added to Gantt v2 exports. Episodes schema goes from 21 to 22 columns. Detail schema goes from 19 to 20 columns. V1 exports unchanged.
- **D-12:** Episode aggregation: any-questionable propagates. If ANY triggering code in the episode is questionable, the episode gets the flag. Matches Phase 91 D-09 aggregation pattern.

**Aggregation Rules:**
- **D-13:** `is_sct_conditioning_context` is an annotation only — treatment_type stays "Chemotherapy". No reclassification to "SCT Conditioning". Preserves mutual exclusivity.
- **D-14:** Aggregation rules documented as inline comments in R/28 and R/52. No separate markdown document.
- **D-15:** Smoke test performs full cross-tab validation: treatment_type sum check (each episode has exactly one category) PLUS cross-tab of is_sct_conditioning_context vs treatment_type confirming the flag only appears on Chemotherapy episodes.

### Claude's Discretion

- Exact placement of new columns in R/28 episode enrichment pipeline (after existing Phase 91 enrichment step)
- Smoke test section numbering (follow existing convention)
- Comment wording for aggregation rule documentation
- `days_to_nearest_sct` computation details (nearest SCT episode start date per patient, looking forward only)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IMMU-01 | Questionable immunotherapy codes (8 vitamin combos, 2 CAR-T) flagged with confidence column in Gantt output | Named vector lookup pattern from Phase 91, aggregate_cross_use_flag() reuse for any-positive logic |
| IMMU-02 | Flag values distinguish vitamin combos ("questionable-vitamin") from CAR-T ambiguity ("questionable-CAR-T vs immunotherapy") | Two-category categorical column with NA default; hardcoded mapping in R/00_config.R per D-05 |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data frame transformation | Established in project; mutate() for column addition, filter() for temporal subset |
| lubridate | 1.9.3+ | Date arithmetic | Already used in R/02 (payer harmonization) and R/28 (cancer linkage) for temporal calculations |
| stringr | 1.5.1+ | String operations | Established pattern for code splitting (str_split) in Phase 91 aggregate functions |
| glue | 1.8.0 | String interpolation | Standard for logging messages across pipeline |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| openxlsx2 | Latest | Styled xlsx export | Smoke test audit outputs (follows R/28 pattern) |

**Installation:**
All packages already in renv.lock from previous phases. No new installations required.

**Version verification:** Existing renv.lock verified in Phase 90-92 implementations.

## Architecture Patterns

### Recommended Column Addition Flow

**Pattern from R/28 Phase 91 enrichment (lines 556-586):**

```r
# Step 1: Pre-enrichment row count for validation
pre_enrichment_count <- nrow(episodes)

# Step 2: Add new columns via mutate
episodes <- episodes %>%
  mutate(
    # Temporal context flag (D-01, D-02, D-03)
    is_sct_conditioning_context = compute_sct_conditioning_flag(...),

    # Days to nearest SCT (RDS-only, D-03)
    days_to_nearest_sct = compute_days_to_sct(...),

    # Immunotherapy confidence (D-09, D-10, D-12)
    immuno_confidence = sapply(triggering_codes, aggregate_immuno_confidence,
                               lookup_vec = QUESTIONABLE_IMMUNO_CODES, USE.NAMES = FALSE)
  )

# Step 3: Validate row count preserved
assert_true(nrow(episodes) == pre_enrichment_count,
            .var.name = glue("[R/28 ERROR] Phase 93 enrichment changed row count"))

# Step 4: Log enrichment results
n_with_conditioning_flag <- sum(episodes$is_sct_conditioning_context == TRUE, na.rm = TRUE)
n_with_confidence_flag <- sum(!is.na(episodes$immuno_confidence), na.rm = TRUE)
message(glue("  Conditioning context: {n_with_conditioning_flag} chemo episodes within 30d before SCT"))
message(glue("  Confidence flags: {n_with_confidence_flag} episodes with questionable codes"))
```

### Temporal Flag Computation Pattern

**From R/02_harmonize_payer.R lines 312-313 (date arithmetic):**

```r
# Calculate days between dates
mutate(days_from_dx = as.numeric(ADMIT_DATE - first_hl_dx_date)) %>%
  filter(!is.na(days_from_dx) & abs(days_from_dx) <= dx_window)
```

**From R/28_episode_classification.R lines 224-225 (temporal filtering):**

```r
# Backward-only 30-day window
filter(DX_DATE <= episode_start) %>%
  mutate(days_before = as.numeric(episode_start - DX_DATE))
```

**Adapted for Phase 93 conditioning context:**

```r
# For each chemotherapy episode, find SCT episodes within 30 days after
compute_sct_conditioning_flag <- function(patient_episodes) {
  # Filter to SCT episodes for this patient
  sct_episodes <- patient_episodes %>%
    filter(treatment_type == "Stem Cell Transplant") %>%
    select(patient_id, sct_start = episode_start)

  # For each chemotherapy episode, check if within 30 days before any SCT
  patient_episodes %>%
    filter(treatment_type == "Chemotherapy") %>%
    left_join(sct_episodes, by = "patient_id", relationship = "many-to-many") %>%
    mutate(
      days_to_sct = as.numeric(sct_start - episode_start),
      is_within_window = !is.na(days_to_sct) & days_to_sct >= 0 & days_to_sct <= 30
    ) %>%
    group_by(patient_id, episode_number) %>%
    summarise(
      is_sct_conditioning_context = any(is_within_window, na.rm = TRUE),
      days_to_nearest_sct = min(days_to_sct[days_to_sct >= 0], na.rm = TRUE),
      .groups = "drop"
    )
}
```

### Named Vector Lookup with Any-Positive Aggregation

**From R/28 lines 544-554 (aggregate_cross_use_flag pattern):**

```r
# Reusable pattern for immuno_confidence
aggregate_immuno_confidence <- function(codes_str, lookup_vec) {
  if (is.na(codes_str) || codes_str == "") return(NA_character_)
  codes <- str_split(codes_str, ",")[[1]]
  flags <- sapply(codes, function(c) {
    val <- lookup_vec[c]
    if (is.null(val) || is.na(val)) NA_character_ else val
  }, USE.NAMES = FALSE)
  flags <- flags[!is.na(flags) & flags != ""]
  if (length(flags) > 0) return(flags[1])  # First non-NA flag wins
  return(NA_character_)
}

# Usage in mutate
episodes <- episodes %>%
  mutate(
    immuno_confidence = sapply(triggering_codes, aggregate_immuno_confidence,
                               lookup_vec = QUESTIONABLE_IMMUNO_CODES, USE.NAMES = FALSE)
  )
```

### Gantt Export Schema Extension

**From R/52 lines 205-219 (defensive column fallback):**

```r
# Phase 93: Add defensive fallback for new columns
if (!"is_sct_conditioning_context" %in% names(episodes)) {
  warning("is_sct_conditioning_context column not found — Phase 93 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(is_sct_conditioning_context = NA)
}
if (!"days_to_nearest_sct" %in% names(episodes)) {
  # RDS-only column — safe to skip in Gantt export
}
if (!"immuno_confidence" %in% names(episodes)) {
  warning("immuno_confidence column not found — Phase 93 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(immuno_confidence = NA_character_)
}
```

**Column selection update (append at end per D-11):**

```r
# Episodes schema: 21 -> 22 columns
episodes_for_export <- episodes %>%
  select(
    patient_id, treatment_type, episode_number, episode_start, episode_stop,
    episode_length_days, distinct_dates_in_episode, historical_flag,
    triggering_codes, encounter_ids, drug_names,
    cancer_category, cancer_link_method, is_hodgkin, regimen_label,
    triggering_code_description, drug_group,
    medication_name, code_type, source_table, treatment_line, sct_cross_use_flag,
    is_sct_conditioning_context, immuno_confidence  # NEW Phase 93
  )

# Detail schema: 19 -> 20 columns (same columns minus episode aggregates)
```

### Smoke Test Cross-Tab Validation

**From R/88 Section 15 pattern (existing treatment_type validation):**

```r
# SECTION 15f: PHASE 93 CROSS-USE FLAG VALIDATION (IMMU-01, IMMU-02) ----

message("\n[PHASE-93] Cross-use flag implementation validation...")

r28_lines <- readLines("R/28_episode_classification.R", warn = FALSE)

# Check 1: QUESTIONABLE_IMMUNO_CODES exists in R/00_config.R
config_lines <- readLines("R/00_config.R", warn = FALSE)
check(
  "R/00_config.R defines QUESTIONABLE_IMMUNO_CODES",
  any(grepl("QUESTIONABLE_IMMUNO_CODES", config_lines))
)

# Check 2-3: R/28 includes Phase 93 columns
check(
  "R/28 select() includes is_sct_conditioning_context",
  any(grepl("is_sct_conditioning_context", r28_lines, fixed = TRUE))
)
check(
  "R/28 select() includes immuno_confidence",
  any(grepl("immuno_confidence", r28_lines, fixed = TRUE))
)

# Check 4: R/28 comment updated to 24 columns (22 + days_to_nearest_sct in RDS only)
check(
  "R/28 comment updated to reflect Phase 93 column count",
  any(grepl("23 columns|24 columns", r28_lines))
)

# Check 5-6: R/52 Gantt export includes new columns
r52_lines <- readLines("R/52_gantt_v2_export.R", warn = FALSE)
check(
  "R/52 select() includes is_sct_conditioning_context (IMMU-01)",
  any(grepl("is_sct_conditioning_context", r52_lines, fixed = TRUE))
)
check(
  "R/52 select() includes immuno_confidence (IMMU-02)",
  any(grepl("immuno_confidence", r52_lines, fixed = TRUE))
)

# Check 7-8: R/52 expected column counts updated
check(
  "R/52 episodes expected column count is 22",
  any(grepl('expected_cols.*22|ncol.*22', r52_lines))
)
check(
  "R/52 detail expected column count is 20",
  any(grepl('expected_detail_cols.*20|ncol.*20', r52_lines))
)

# Runtime validation (if treatment_episodes.rds exists)
if (file.exists("cache/outputs/treatment_episodes.rds")) {
  episodes <- readRDS("cache/outputs/treatment_episodes.rds")

  # Check 9: is_sct_conditioning_context only appears on Chemotherapy episodes (D-02, D-13)
  non_chemo_with_flag <- episodes %>%
    filter(treatment_type != "Chemotherapy" & is_sct_conditioning_context == TRUE)
  check(
    "is_sct_conditioning_context flag only on Chemotherapy episodes",
    nrow(non_chemo_with_flag) == 0
  )

  # Check 10: Non-chemotherapy episodes have NA for conditioning flag (D-04)
  non_chemo <- episodes %>% filter(treatment_type != "Chemotherapy")
  check(
    "Non-chemotherapy episodes have NA for is_sct_conditioning_context",
    all(is.na(non_chemo$is_sct_conditioning_context))
  )

  # Check 11: immuno_confidence has only expected values (D-10)
  valid_confidence_values <- c(NA_character_, "questionable-vitamin", "questionable-CAR-T vs immunotherapy")
  check(
    "immuno_confidence contains only valid values",
    all(episodes$immuno_confidence %in% valid_confidence_values | is.na(episodes$immuno_confidence))
  )

  # Check 12: Mutual exclusivity preserved (D-13)
  treatment_type_counts <- episodes %>%
    count(patient_id, episode_number) %>%
    filter(n > 1)
  check(
    "Each episode has exactly one treatment_type (mutual exclusivity preserved)",
    nrow(treatment_type_counts) == 0
  )
}
```

### Anti-Patterns to Avoid

- **Don't reclassify treatment_type:** `is_sct_conditioning_context` is metadata, not a new treatment category. Keeps treatment_type as "Chemotherapy" per D-13.
- **Don't use global temporal windows:** Temporal calculation is per-patient (each patient's SCT episodes only affect their own chemotherapy episodes).
- **Don't break backward compatibility:** Gantt v1 exports unchanged; new columns only in v2 per D-11.
- **Don't skip defensive column fallback:** R/52 must handle missing columns gracefully for partial-run scenarios.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Date arithmetic | Custom day counters | lubridate::as.numeric(difftime(date1, date2)) | Already established in R/02 and R/28; handles leap years, DST |
| Episode-level flag aggregation | Custom string parsers | Reuse aggregate_cross_use_flag() pattern from Phase 91 | Proven pattern with any-positive logic; handles comma-separated codes |
| Cross-tab validation | Manual group_by summaries | Smoke test check() helper with count() | Established pattern in R/88 for structural validation |
| Column fallback | Stop on missing columns | Defensive mutate with NA defaults | Phase 92 pattern (R/52 lines 205-219); allows partial runs |

**Key insight:** This phase extends existing patterns (Phase 91 named vector lookups, Phase 92 schema extension) rather than introducing new complexity. Temporal calculation is the only novel logic, but lubridate date arithmetic is already used in 3+ scripts (R/02, R/28, R/03).

## Runtime State Inventory

> Phase 93 is code-only enrichment with no external dependencies. Skipping runtime state inventory.

## Common Pitfalls

### Pitfall 1: Off-by-One Errors in Temporal Windows
**What goes wrong:** Conditioning window calculated as "< 30 days" instead of "<= 30 days", missing episodes on the boundary.
**Why it happens:** Inconsistent inequality operators between window filter and documentation.
**How to avoid:** Use `days_to_sct >= 0 & days_to_sct <= 30` explicitly (matches D-01's "within 30 days before").
**Warning signs:** Smoke test finds chemotherapy episodes exactly 30 days before SCT without the flag set.

### Pitfall 2: Many-to-Many Join Explosion
**What goes wrong:** Patient with multiple SCT episodes creates duplicate chemotherapy episode rows during temporal join.
**Why it happens:** `left_join(sct_episodes, by = "patient_id")` without `relationship = "many-to-many"` warning suppression.
**How to avoid:** Use `relationship = "many-to-many"` parameter, then `group_by(patient_id, episode_number)` and aggregate with `any()` for boolean flag.
**Warning signs:** Row count assertion fails after enrichment (more rows out than in).

### Pitfall 3: NA Propagation in Boolean Flags
**What goes wrong:** `is_sct_conditioning_context` becomes NA instead of FALSE for chemotherapy episodes with no nearby SCT.
**Why it happens:** `any(is_within_window)` returns NA when all values are NA (no SCT episodes for patient).
**How to avoid:** Use `any(is_within_window, na.rm = TRUE)` or `isTRUE(any(is_within_window))` to collapse NA to FALSE.
**Warning signs:** Smoke test cross-tab shows NA values for chemotherapy episodes (expected: TRUE or FALSE only per D-03).

### Pitfall 4: Questionable Code Lookup Key Mismatch
**What goes wrong:** Immunotherapy RxNorm codes in triggering_codes are integers, but QUESTIONABLE_IMMUNO_CODES keys are strings.
**Why it happens:** Inconsistent type handling between code extraction and named vector lookup.
**How to avoid:** Verify key type in R/00_config.R definition (check if quoted or bare integers), match in triggering_codes split.
**Warning signs:** All immunotherapy episodes with multivitamin codes get NA instead of "questionable-vitamin" flag.

### Pitfall 5: Column Count Constant Desync
**What goes wrong:** Smoke test expects 22 columns but R/28 comment says 23 columns.
**Why it happens:** `days_to_nearest_sct` is RDS-only (not in Gantt export), but counted in total column comment.
**How to avoid:** Document RDS vs CSV column counts separately: "24 columns in RDS (includes days_to_nearest_sct), 22 in Gantt v2 CSV".
**Warning signs:** Smoke test column count check fails despite correct schema.

## Code Examples

Verified patterns from existing codebase:

### Temporal Backward Window (30 days before event)
```r
# Source: R/28_episode_classification.R lines 224-225
# Adapted for SCT conditioning context

# Per-patient temporal join to find chemotherapy episodes within 30 days before SCT
sct_dates <- episodes %>%
  filter(treatment_type == "Stem Cell Transplant") %>%
  select(patient_id, sct_start = episode_start)

chemo_with_context <- episodes %>%
  filter(treatment_type == "Chemotherapy") %>%
  left_join(sct_dates, by = "patient_id", relationship = "many-to-many") %>%
  mutate(
    days_to_sct = as.numeric(sct_start - episode_start),
    is_within_window = !is.na(days_to_sct) & days_to_sct >= 0 & days_to_sct <= 30
  ) %>%
  group_by(patient_id, episode_number) %>%
  summarise(
    is_sct_conditioning_context = any(is_within_window, na.rm = TRUE),
    days_to_nearest_sct = if_else(
      any(is_within_window, na.rm = TRUE),
      min(days_to_sct[days_to_sct >= 0], na.rm = TRUE),
      NA_integer_
    ),
    .groups = "drop"
  )
```

### Any-Positive Flag Aggregation
```r
# Source: R/28_episode_classification.R lines 544-554
# Reused for immuno_confidence

aggregate_immuno_confidence <- function(codes_str, lookup_vec) {
  if (is.na(codes_str) || codes_str == "") return(NA_character_)
  codes <- str_split(codes_str, ",")[[1]]
  flags <- sapply(codes, function(c) {
    val <- lookup_vec[c]
    if (is.null(val) || is.na(val)) NA_character_ else val
  }, USE.NAMES = FALSE)
  flags <- flags[!is.na(flags) & flags != ""]
  if (length(flags) > 0) return(flags[1])
  return(NA_character_)
}

# Named vector in R/00_config.R
QUESTIONABLE_IMMUNO_CODES <- c(
  "891815" = "questionable-vitamin",
  "891790" = "questionable-vitamin",
  "1090823" = "questionable-vitamin",
  "1313925" = "questionable-vitamin",
  "1248142" = "questionable-vitamin",
  "891716" = "questionable-vitamin",
  "1090824" = "questionable-vitamin",
  "891793" = "questionable-vitamin",
  "2479140" = "questionable-CAR-T vs immunotherapy",
  "XW033C3" = "questionable-CAR-T vs immunotherapy",
  "XW043C3" = "questionable-CAR-T vs immunotherapy"
)
```

### Defensive Column Fallback
```r
# Source: R/52_gantt_v2_export.R lines 205-219
# Extended for Phase 93 columns

if (!"is_sct_conditioning_context" %in% names(episodes)) {
  warning("is_sct_conditioning_context column not found — Phase 93 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(is_sct_conditioning_context = NA)
}
if (!"immuno_confidence" %in% names(episodes)) {
  warning("immuno_confidence column not found — Phase 93 not yet run. Using default NA.")
  episodes <- episodes %>% mutate(immuno_confidence = NA_character_)
}
```

### Smoke Test Cross-Tab Validation
```r
# Source: R/88_smoke_test_comprehensive.R pattern
# New Section 15f for Phase 93

# Cross-tab: is_sct_conditioning_context should only appear on Chemotherapy
conditioning_crosstab <- episodes %>%
  count(treatment_type, is_sct_conditioning_context)

non_chemo_with_flag <- conditioning_crosstab %>%
  filter(treatment_type != "Chemotherapy" & is_sct_conditioning_context == TRUE)

check(
  "is_sct_conditioning_context flag only on Chemotherapy episodes (D-02)",
  nrow(non_chemo_with_flag) == 0
)
```

## Environment Availability

> Phase 93 is code-only enrichment within existing R environment. No external dependencies beyond packages already in renv.lock. Skipping environment availability audit.

## Validation Architecture

> Skipped — workflow.nyquist_validation is explicitly set to false in .planning/config.json.

## Sources

### Primary (HIGH confidence)
- Existing codebase: R/28_episode_classification.R (Phase 91 pattern), R/52_gantt_v2_export.R (Phase 92 schema extension), R/02_harmonize_payer.R (lubridate date arithmetic), R/88_smoke_test_comprehensive.R (validation patterns)
- CONTEXT.md decisions D-01 through D-15 (user-locked constraints)
- R/00_config.R lines 2158-2170 (immunotherapy codes), lines 2739-2770 (CAR-T ICD-10-PCS codes)

### Secondary (MEDIUM confidence)
- lubridate documentation for `as.numeric(difftime())` — verified against existing codebase usage (R/02, R/28, R/03)
- dplyr 1.2.0 many-to-many join behavior — verified against project's renv.lock version

### Tertiary (LOW confidence)
- None — all research based on existing codebase patterns and locked user decisions

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages already in project renv.lock
- Architecture patterns: HIGH - Direct reuse of Phase 91 (named vector lookup) and Phase 92 (schema extension) patterns
- Temporal logic: HIGH - lubridate date arithmetic established in 3+ existing scripts
- Pitfalls: MEDIUM - Inferred from common dplyr join and NA handling issues; not project-specific failures

**Research date:** 2026-06-08
**Valid until:** 2026-07-08 (30 days - stable R ecosystem and locked project patterns)
