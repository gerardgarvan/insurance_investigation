# Phase 94: Make Proton Therapy a Distinct Category from Radiation - Research

**Researched:** 2026-06-09
**Domain:** Treatment categorization in R PCORnet pipeline
**Confidence:** HIGH

## Summary

This phase separates proton beam therapy (CPT codes 77520, 77522, 77523, 77525) from the general "Radiation" treatment category into its own distinct "Proton Therapy" category throughout the entire R pipeline. The work follows established patterns from existing treatment types (Chemotherapy, Radiation, SCT, Immunotherapy) and requires updates to configuration vectors, cohort predicates, episode detection dispatch, xlsx styling, and smoke tests.

The pipeline already has strong architectural patterns for treatment types: a single TREATMENT_TYPES vector drives for-loops across all analysis scripts, DRUG_GROUPINGS provides code-to-category mapping, and TREATMENT_TYPE_COLORS defines xlsx styling. Adding "Proton Therapy" leverages these existing patterns with minimal script-level changes beyond R/00_config.R updates and a new has_proton() predicate function.

**Primary recommendation:** Follow the "add new treatment type" pattern established by existing categories. Update TREATMENT_TYPES vector to include "Proton Therapy", split proton codes from radiation_cpt into new proton_cpt list, add DRUG_GROUPINGS entries for 4 proton codes, create has_proton() predicate (copying has_radiation() pattern), extend TREATMENT_TYPE_COLORS with visually distinct color, and add if/else branches in R/25 and R/26 type dispatchers. Most downstream scripts (R/20, R/24, R/56, R/57, R/52, R/88) auto-adapt via TREATMENT_TYPES iteration.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Category Naming:**
- D-01: New category name is "Proton Therapy" (not "Proton" or "Proton Beam")
- D-02: This string appears in DRUG_GROUPINGS values, TREATMENT_TYPES vector, TREATMENT_TYPE_COLORS, GANTT_TREATMENT_TYPES, xlsx sheet names, Gantt labels, and all summary outputs

**Detection Code Scope:**
- D-03: Full split — proton codes removed from TREATMENT_CODES$radiation_cpt and placed in new TREATMENT_CODES$proton_cpt list
- D-04: New has_proton() predicate function added in R/10_cohort_predicates.R (parallel to existing has_radiation())
- D-05: R/26 episode detection handles "Proton Therapy" as a separate treatment type with its own code list lookup
- D-06: 4 codes affected: 77520 (Simple), 77522 (Simple w/ Compensation), 77523 (Intermediate), 77525 (Complex)
- D-07: DRUG_GROUPINGS entries for these 4 codes change from "Radiation" to "Proton Therapy"

**Downstream Output Handling:**
- D-08: Full treatment — Proton Therapy gets its own xlsx sheet in treatment reports (R/20, R/24), own Gantt color in TREATMENT_TYPE_COLORS, own smoke test section, own row in summary tables
- D-09: TREATMENT_TYPES becomes 5 elements: c("Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Proton Therapy")
- D-10: All for(type in TREATMENT_TYPES) loops automatically pick up the new category — no per-loop changes needed unless there's type-specific branching

**Aggregation Behavior:**
- D-11: Standalone only — "Proton Therapy" appears as its own row, "Radiation" appears as its own row (now 11 codes instead of 15). No combined "Radiation (All)" row.
- D-12: Prior outputs that lumped proton into radiation will naturally show different counts. This is expected and intentional.

### Claude's Discretion

- Exact Gantt color choice for Proton Therapy (should be visually distinct from Radiation's green)
- Order of "Proton Therapy" within TREATMENT_TYPES (end or after Radiation)
- Whether CODE_SUBCATEGORY_MAP needs a "Proton Therapy" entry
- Handling of proton-specific ICD-10-PCS codes if any exist in TREATMENT_CODES (e.g., D70 beam radiation includes proton modality qualifiers)
- Whether R/25 get_gap_threshold() needs a proton-specific gap threshold or inherits from radiation

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Project Constraints (from CLAUDE.md)

**Runtime environment:** RStudio on UF HiPerGator — scripts must work in that environment
**R packages:** tidyverse ecosystem (dplyr, ggplot2, stringr, lubridate), ggalluvial for Sankey, scales, janitor, glue
**Code style:** Filtering logic uses named predicate functions (has_*, with_*, exclude_*) — no opaque one-liners
**Technology Stack:** R 4.4.2+, tidyverse 2.0.0+, dplyr 1.2.0+, openxlsx2 for xlsx generation

## Standard Stack

This phase uses existing R pipeline infrastructure. No new libraries required.

### Core Dependencies

| Library | Version | Purpose | Already Installed |
|---------|---------|---------|-------------------|
| dplyr | 1.2.0+ | Data transformation, case_when() for categorization | ✓ |
| glue | 1.8.0+ | Logging messages with embedded expressions | ✓ |
| openxlsx2 | Latest | Multi-sheet xlsx generation with styling | ✓ |

**Installation:** Not applicable — all dependencies already in place from existing phases.

## Architecture Patterns

### Treatment Type Registration Pattern

The pipeline uses a centralized registration pattern in R/00_config.R that drives all downstream analysis:

```r
# Standard treatment types for analysis
TREATMENT_TYPES <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy")

# Treatment type colors for xlsx styling (8-char hex with FF alpha prefix)
TREATMENT_TYPE_COLORS <- list(
  Chemotherapy      = list(fill = "FFDCEEFB", font = "FF0B5394"), # light blue / dark blue
  Radiation         = list(fill = "FFDDF4E1", font = "FF274E13"), # light green / dark green
  SCT               = list(fill = "FFFFF4D6", font = "FF7F6000"), # light yellow / dark olive
  Immunotherapy     = list(fill = "FFE8DCF4", font = "FF4C1D7A")  # light purple / dark purple
)

# Treatment types recognized in Gantt output
GANTT_TREATMENT_TYPES <- c(TREATMENT_TYPES, "HL Diagnosis")
```

**For Proton Therapy:**

```r
# Add to TREATMENT_TYPES (position: user's discretion, recommend after Radiation)
TREATMENT_TYPES <- c("Chemotherapy", "Radiation", "Proton Therapy", "SCT", "Immunotherapy")

# Add color to TREATMENT_TYPE_COLORS (recommend orange/amber to distinguish from green Radiation)
TREATMENT_TYPE_COLORS <- list(
  # ... existing entries ...
  `Proton Therapy`  = list(fill = "FFFDE7CC", font = "FF8B4513")  # light orange / saddle brown
)
```

### Code-to-Category Mapping Pattern

DRUG_GROUPINGS is the single source of truth for code → category mapping:

```r
DRUG_GROUPINGS <- c(
  # Chemotherapy (183 codes)
  "J9354" = "Chemotherapy",
  # ...

  # Radiation (15 codes currently, will be 11 after proton split)
  "77417" = "Radiation",
  "77470" = "Radiation",
  # ... (no proton codes here currently)

  # SCT (36 codes after v2.3 cleanup)
  "38241" = "SCT",
  # ...
)
```

**Current state:** The 4 proton codes (77520, 77522, 77523, 77525) are NOT in DRUG_GROUPINGS. They exist in TREATMENT_CODES$radiation_cpt and CODE_DESCRIPTIONS but are not mapped to a category for episode detection.

**After Phase 94:**

```r
DRUG_GROUPINGS <- c(
  # ... existing entries ...

  # Proton Therapy (4 codes) -- NEW SECTION
  "77520" = "Proton Therapy",
  "77522" = "Proton Therapy",
  "77523" = "Proton Therapy",
  "77525" = "Proton Therapy",

  # Radiation (11 codes) -- UNCHANGED CODES, just fewer
  "77417" = "Radiation",
  "77470" = "Radiation",
  # ... (existing codes, proton codes removed)
)
```

### Treatment Code List Pattern

TREATMENT_CODES provides code lists for detection across multiple sources:

```r
TREATMENT_CODES <- list(
  # Chemotherapy
  chemo_cpt = c("J9354", "J9017", ...),
  chemo_ndc = c("2001102", "134547", ...),
  chemo_rxnorm = c("1622", "2105", ...),

  # Radiation (currently includes proton codes at lines 2584-2587)
  radiation_cpt = c(
    # Treatment Planning
    "77261", "77262", "77263", ...,
    # Treatment Delivery
    "77385", "77386", "77387", ...,
    # Proton Beam (77520-77525) -- THESE SHOULD MOVE
    "77520", "77522", "77523", "77525",
    # Brachytherapy
    "77750", "77763", ...
  ),

  # SCT
  sct_cpt = c("38230", "38240", ...),
  # ...
)
```

**After Phase 94:**

```r
TREATMENT_CODES <- list(
  # ... existing entries ...

  # Radiation (11 codes, proton removed)
  radiation_cpt = c(
    # Treatment Planning
    "77261", "77262", "77263", ...,
    # Treatment Delivery
    "77385", "77386", "77387", ...,
    # Brachytherapy (proton section removed)
    "77750", "77763", ...
  ),

  # Proton Therapy (4 codes) -- NEW LIST
  proton_cpt = c(
    "77520",  # Proton treatment delivery; simple, without compensation
    "77522",  # Proton treatment delivery; simple, with compensation
    "77523",  # Proton treatment delivery; intermediate
    "77525"   # Proton treatment delivery; complex
  )
)
```

### Cohort Predicate Pattern

R/10_cohort_predicates.R defines has_* functions that detect treatment evidence across multiple PCORnet source tables:

```r
has_radiation <- function() {
  rad_ids <- character(0)

  # Initialize source counters for aggregate logging
  n_tr <- 0L
  n_px <- 0L
  n_dx <- 0L
  n_drg <- 0L
  n_rev <- 0L

  # TUMOR_REGISTRY: radiation dates
  tr_tbl <- get_pcornet_table("TUMOR_REGISTRY_ALL")
  if (!is.null(tr_tbl)) {
    rad_tr <- tr_tbl %>%
      filter(!is.na(DT_RAD_START)) %>%
      distinct(ID) %>%
      pull(ID)
    rad_ids <- c(rad_ids, rad_tr)
    n_tr <- length(rad_tr)
  }

  # PROCEDURES: CPT codes
  proc_tbl <- get_pcornet_table("PROCEDURES")
  if (!is.null(proc_tbl)) {
    rad_px <- proc_tbl %>%
      filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) %>%
      distinct(ID) %>%
      pull(ID)
    rad_ids <- c(rad_ids, rad_px)
    n_px <- length(rad_px)
  }

  # ... DX, DRG, Revenue sources ...

  result <- tibble(ID = unique(rad_ids), HAD_RADIATION = 1L)
  message(glue("[Treatment] has_radiation: {nrow(result)} patients total"))
  message(glue("  Sources: TR={n_tr}, PX={n_px}, DX={n_dx}, DRG={n_drg}, REV={n_rev}"))
  result
}
```

**For Proton Therapy:** Copy this pattern, replacing:
- Function name: has_proton()
- Code lists: TREATMENT_CODES$proton_cpt
- Column name: HAD_PROTON
- Log messages: "has_proton"

**Note:** Proton therapy has NO tumor registry dates (PCORnet doesn't capture proton-specific dates), NO diagnosis codes, NO DRG codes, NO revenue codes. Only source is PROCEDURES with PX_TYPE == "CH" and PX in proton_cpt. The predicate will be simpler than has_radiation().

### Episode Detection Dispatch Pattern

R/26_treatment_episodes.R dispatches to type-specific extraction functions:

```r
extract_dates_with_codes <- function(type) {
  message(glue("\n--- Extracting {type} dates (with triggering codes) ---"))

  if (type == "Chemotherapy") {
    return(extract_chemo_dates_with_codes())
  } else if (type == "Radiation") {
    return(extract_radiation_dates_with_codes())
  } else if (type == "SCT") {
    return(extract_sct_dates_with_codes())
  } else if (type == "Immunotherapy") {
    return(extract_immunotherapy_dates_with_codes())
  } else {
    stop(glue("Unknown treatment type: {type}"))
  }
}
```

**After Phase 94:**

```r
extract_dates_with_codes <- function(type) {
  message(glue("\n--- Extracting {type} dates (with triggering codes) ---"))

  if (type == "Chemotherapy") {
    return(extract_chemo_dates_with_codes())
  } else if (type == "Radiation") {
    return(extract_radiation_dates_with_codes())
  } else if (type == "Proton Therapy") {
    return(extract_proton_dates_with_codes())  # NEW BRANCH
  } else if (type == "SCT") {
    return(extract_sct_dates_with_codes())
  } else if (type == "Immunotherapy") {
    return(extract_immunotherapy_dates_with_codes())
  } else {
    stop(glue("Unknown treatment type: {type}"))
  }
}
```

R/25_treatment_durations.R has the same pattern in extract_all_dates().

### xlsx Sheet Generation Pattern

R/20_treatment_inventory.R, R/24_treatment_codes_resolved.R, R/56_new_tables_from_groupings.R, R/57_drug_grouping_instances.R all iterate TREATMENT_TYPES to generate per-type xlsx sheets:

```r
for (type in TREATMENT_TYPES) {
  type_data <- results_list[[type]]
  sheet_name <- paste(type, "Durations")

  wb$add_worksheet(sheet_name)
  wb$add_data(sheet = sheet_name, x = type_data)

  # Apply styling
  fill_color <- TREATMENT_TYPE_COLORS[[type]]$fill
  font_color <- TREATMENT_TYPE_COLORS[[type]]$font
  wb$add_fill(sheet = sheet_name, dims = "A1:Z1", color = fill_color)
  wb$add_font(sheet = sheet_name, dims = "A1:Z1", color = font_color, bold = TRUE)
}
```

**Impact of adding "Proton Therapy" to TREATMENT_TYPES:** These loops automatically generate a new sheet for Proton Therapy with no script changes beyond config updates.

### Anti-Patterns to Avoid

**1. Don't add proton codes to DRUG_GROUPINGS without removing from radiation_cpt:**
- Leads to double-counting in episode detection
- DRUG_GROUPINGS and TREATMENT_CODES must stay synchronized

**2. Don't reuse Radiation's green color for Proton Therapy:**
- Colors must be visually distinct in xlsx outputs and Gantt charts
- Recommend warm color (orange/amber) to contrast with Radiation's green

**3. Don't forget to update GANTT_TREATMENT_TYPES:**
- GANTT_TREATMENT_TYPES <- c(TREATMENT_TYPES, "HL Diagnosis")
- If TREATMENT_TYPES changes, GANTT_TREATMENT_TYPES auto-updates (it's derived)

**4. Don't create extract_proton_dates_with_codes() from scratch:**
- Copy extract_radiation_dates_with_codes() and modify
- Proton has fewer sources (only PROCEDURES CPT), so function is simpler

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Type-specific code extraction | Custom proton extraction logic | Copy extract_radiation_dates_with_codes() pattern | Established pattern handles multiple sources (though proton only has PX), logging, code deduplication |
| xlsx styling | Manual hex color selection | Follow TREATMENT_TYPE_COLORS pattern | Consistent with existing 4 treatment types; 8-char hex with FF alpha prefix |
| Episode detection dispatch | Custom dispatcher | Extend existing if/else chain in R/25, R/26 | Centralized dispatch makes type handling explicit and maintainable |
| Smoke test validation | New validation framework | Extend Section 15 in R/88 | Existing comprehensive smoke test covers DRUG_GROUPINGS, TREATMENT_TYPES, source detection |

**Key insight:** The pipeline already has strong abstractions for treatment types. Adding a 5th category is primarily a configuration exercise (update vectors in R/00_config.R) plus a few dispatch branches (R/10, R/25, R/26). Most scripts auto-adapt via TREATMENT_TYPES iteration.

## Runtime State Inventory

> This section is omitted — Phase 94 is not a rename/refactor/migration. It's a category split within existing treatment detection infrastructure.

## Common Pitfalls

### Pitfall 1: Forgetting to Remove Proton Codes from radiation_cpt

**What goes wrong:** Proton codes remain in both TREATMENT_CODES$radiation_cpt and new TREATMENT_CODES$proton_cpt, causing extract_radiation_dates_with_codes() to still pick them up. Episodes get classified as "Radiation" instead of "Proton Therapy" because radiation branch executes first in if/else chain.

**Why it happens:** DRUG_GROUPINGS mapping ("77520" = "Proton Therapy") controls episode classification via R/28, but date extraction in R/26 still uses TREATMENT_CODES lists. If a code is in radiation_cpt, it gets extracted as radiation dates.

**How to avoid:**
1. Remove 4 proton codes from radiation_cpt vector (lines 2584-2587 in R/00_config.R)
2. Create new proton_cpt vector with those 4 codes
3. Add inline comment documenting the move: "# Proton codes moved to proton_cpt (Phase 94)"

**Warning signs:**
- Smoke test shows 0 Proton Therapy episodes but >0 patients with proton codes
- treatment_episodes.rds has treatment_type = "Radiation" with triggering_code in (77520, 77522, 77523, 77525)
- Radiation episode counts unchanged after phase completion

### Pitfall 2: Inconsistent Category Naming

**What goes wrong:** DRUG_GROUPINGS uses "Proton Therapy", TREATMENT_TYPES uses "Proton", TREATMENT_TYPE_COLORS uses "Proton Beam". Downstream scripts that match on category name fail (e.g., xlsx styling lookups, Gantt color assignment).

**Why it happens:** Multiple vectors define the category name, and it's easy to use slight variations.

**How to avoid:**
1. Establish canonical name first: "Proton Therapy" per D-01
2. Use exact string in ALL locations: DRUG_GROUPINGS values, TREATMENT_TYPES element, TREATMENT_TYPE_COLORS key, log messages
3. Use backticks for TREATMENT_TYPE_COLORS key if name has spaces: `Proton Therapy` = list(...)

**Warning signs:**
- openxlsx2 crashes with "Unknown treatment type" during styling
- Gantt export shows blank treatment_category for proton codes
- grep for "Proton" finds 3+ variations (Proton, Proton Therapy, Proton Beam)

### Pitfall 3: Not Updating Smoke Test

**What goes wrong:** R/88_smoke_test_comprehensive.R validates core_categories = c("Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Supportive Care"). After adding "Proton Therapy" to DRUG_GROUPINGS, smoke test Section 15 fails because it expects exactly 5 categories, not 6.

**Why it happens:** Smoke test hardcodes expected category counts and names. Adding a new treatment type requires updating validation logic.

**How to avoid:**
1. Update core_categories vector in smoke test to include "Proton Therapy"
2. Update expected treatment type count from 4 to 5
3. Add validation that proton codes (77520, 77522, 77523, 77525) map to "Proton Therapy" in DRUG_GROUPINGS

**Warning signs:**
- /gsd:verify-work fails with "Expected 5 categories, found 6"
- Smoke test Section 15 shows "Unknown category: Proton Therapy"

### Pitfall 4: Missing has_proton() in Cohort Building

**What goes wrong:** R/14_build_cohort.R calls has_chemo(), has_radiation(), has_sct(), has_immunotherapy() to add HAD_* flags. If has_proton() is not called, cohort data never gets HAD_PROTON column, and downstream scripts that expect it (e.g., for cohort stratification) fail.

**Why it happens:** Cohort building predicate calls are explicit (not driven by TREATMENT_TYPES loop), so adding a new predicate requires manual integration in R/14.

**How to avoid:**
1. Define has_proton() in R/10_cohort_predicates.R
2. Add has_proton() call in R/14_build_cohort.R alongside has_radiation()
3. Join result to cohort tibble: cohort <- cohort %>% left_join(has_proton(), by = "ID")

**Warning signs:**
- cohort.rds has columns HAD_CHEMO, HAD_RADIATION, HAD_SCT, HAD_IMMUNOTHERAPY but no HAD_PROTON
- Downstream analysis scripts error with "Column HAD_PROTON not found"

## Code Examples

### Example 1: Adding Proton Therapy to TREATMENT_TYPES

```r
# R/00_config.R lines 3348-3370

# BEFORE Phase 94
TREATMENT_TYPES <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy")

# AFTER Phase 94
# Position: after Radiation, before SCT (groups beam therapies together)
TREATMENT_TYPES <- c("Chemotherapy", "Radiation", "Proton Therapy", "SCT", "Immunotherapy")
```

### Example 2: Splitting Proton Codes from radiation_cpt

```r
# R/00_config.R lines 2528-2605

# BEFORE Phase 94
radiation_cpt = c(
  # Treatment Planning
  "77261", "77262", "77263",
  # ... other codes ...

  # Proton Beam Treatment Delivery (77520-77525)
  "77520",  # Proton treatment delivery; simple, without compensation
  "77522",  # Proton treatment delivery; simple, with compensation
  "77523",  # Proton treatment delivery; intermediate
  "77525",  # Proton treatment delivery; complex

  # Hyperthermia
  "77605",
  # ... brachytherapy codes ...
)

# AFTER Phase 94
radiation_cpt = c(
  # Treatment Planning
  "77261", "77262", "77263",
  # ... other codes ...

  # Hyperthermia (proton section removed, moved to proton_cpt)
  "77605",
  # ... brachytherapy codes ...
),

# NEW: Proton therapy CPT codes (split from radiation_cpt, Phase 94)
proton_cpt = c(
  "77520",  # Proton treatment delivery; simple, without compensation
  "77522",  # Proton treatment delivery; simple, with compensation
  "77523",  # Proton treatment delivery; intermediate
  "77525"   # Proton treatment delivery; complex
)
```

### Example 3: Adding Proton Codes to DRUG_GROUPINGS

```r
# R/00_config.R lines 1571-1593 (after existing Radiation entries)

# BEFORE Phase 94
  "77412" = "Radiation", # Replaces 77413, 77414, 77416

  # NOTE: 5 false-positive codes removed (v2.3 Phase 90, CLEAN-01):
  # ...

# AFTER Phase 94
  "77412" = "Radiation", # Replaces 77413, 77414, 77416

  # Proton Therapy (4 codes) -- Phase 94: split from Radiation
  "77520" = "Proton Therapy",
  "77522" = "Proton Therapy",
  "77523" = "Proton Therapy",
  "77525" = "Proton Therapy",

  # NOTE: 5 false-positive codes removed (v2.3 Phase 90, CLEAN-01):
  # ...
```

### Example 4: Adding Proton Color to TREATMENT_TYPE_COLORS

```r
# R/00_config.R lines 3357-3366

# BEFORE Phase 94
TREATMENT_TYPE_COLORS <- list(
  Chemotherapy      = list(fill = "FFDCEEFB", font = "FF0B5394"), # light blue / dark blue
  Radiation         = list(fill = "FFDDF4E1", font = "FF274E13"), # light green / dark green
  SCT               = list(fill = "FFFFF4D6", font = "FF7F6000"), # light yellow / dark olive
  Immunotherapy     = list(fill = "FFE8DCF4", font = "FF4C1D7A"), # light purple / dark purple
  `HL Diagnosis`    = list(fill = "FFFFF0D6", font = "FF8B6914"), # light gold / dark gold
  Death             = list(fill = "FFFDE8E8", font = "FF991B1B"), # light red / dark red
  `Supportive Care` = list(fill = "FFD5F5F0", font = "FF0E6655"), # light teal / dark teal
  Unrelated         = list(fill = "FFF3F4F6", font = "FF6B7280")  # light gray / medium gray
)

# AFTER Phase 94
TREATMENT_TYPE_COLORS <- list(
  Chemotherapy      = list(fill = "FFDCEEFB", font = "FF0B5394"), # light blue / dark blue
  Radiation         = list(fill = "FFDDF4E1", font = "FF274E13"), # light green / dark green
  `Proton Therapy`  = list(fill = "FFFDE7CC", font = "FF8B4513"), # light orange / saddle brown
  SCT               = list(fill = "FFFFF4D6", font = "FF7F6000"), # light yellow / dark olive
  Immunotherapy     = list(fill = "FFE8DCF4", font = "FF4C1D7A"), # light purple / dark purple
  `HL Diagnosis`    = list(fill = "FFFFF0D6", font = "FF8B6914"), # light gold / dark gold
  Death             = list(fill = "FFFDE8E8", font = "FF991B1B"), # light red / dark red
  `Supportive Care` = list(fill = "FFD5F5F0", font = "FF0E6655"), # light teal / dark teal
  Unrelated         = list(fill = "FFF3F4F6", font = "FF6B7280")  # light gray / medium gray
)
```

**Color choice rationale:** Orange/amber provides strong visual distinction from Radiation's green while staying within medical treatment color conventions. Light orange (#FDE7CC) / saddle brown (#8B4513) maintains readability on white backgrounds.

### Example 5: has_proton() Predicate Function

```r
# R/10_cohort_predicates.R (add after has_radiation() definition)

#' Identify patients with proton therapy evidence
#'
#' Combines evidence from:
#'   - PROCEDURES: PX_TYPE == "CH" and PX in TREATMENT_CODES$proton_cpt
#'
#' Note: Proton therapy does NOT use TUMOR_REGISTRY (no proton-specific date columns),
#' DIAGNOSIS (no proton-specific ICD codes), DRG, or Revenue codes.
#' Only detection source is CPT codes in PROCEDURES.
#'
#' @return Tibble with columns: ID, HAD_PROTON (integer 1 for all rows)
#'
has_proton <- function() {
  proton_ids <- character(0)

  # Initialize source counter for aggregate logging
  n_px <- 0L

  # PROCEDURES: CPT codes only
  proc_tbl <- get_pcornet_table("PROCEDURES")
  if (!is.null(proc_tbl)) {
    proton_px <- proc_tbl %>%
      filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$proton_cpt) %>%
      distinct(ID) %>%
      pull(ID)
    proton_ids <- c(proton_ids, proton_px)
    n_px <- length(proton_px)
  }

  result <- tibble(ID = unique(proton_ids), HAD_PROTON = 1L)
  message(glue("[Treatment] has_proton: {nrow(result)} patients total"))
  message(glue("  Sources: PX={n_px}"))
  result
}
```

### Example 6: Episode Detection Dispatch for Proton Therapy

```r
# R/26_treatment_episodes.R lines 390-407 (extract_dates_with_codes function)

# ADD NEW BRANCH
extract_dates_with_codes <- function(type) {
  message(glue("\n--- Extracting {type} dates (with triggering codes) ---"))

  if (type == "Chemotherapy") {
    return(extract_chemo_dates_with_codes())
  } else if (type == "Radiation") {
    return(extract_radiation_dates_with_codes())
  } else if (type == "Proton Therapy") {
    return(extract_proton_dates_with_codes())  # NEW
  } else if (type == "SCT") {
    return(extract_sct_dates_with_codes())
  } else if (type == "Immunotherapy") {
    return(extract_immunotherapy_dates_with_codes())
  } else {
    stop(glue("Unknown treatment type: {type}"))
  }
}

# DEFINE NEW EXTRACTION FUNCTION (add after extract_radiation_dates_with_codes)
#' Extract proton therapy dates with triggering codes
#'
#' Sources: PROCEDURES (CPT only)
#'
#' Returns tibble with columns: ID, treatment_date, triggering_code
#'
#' Note: Simpler than radiation extraction — only one source (PROCEDURES CPT)
#'
extract_proton_dates_with_codes <- function() {
  # PROCEDURES: CPT codes
  px_dates <- tibble(ID = character(), treatment_date = as.Date(character()), triggering_code = character())

  proc_tbl <- get_pcornet_table("PROCEDURES")
  if (!is.null(proc_tbl)) {
    px_dates <- proc_tbl %>%
      filter(PX_TYPE == "CH" & PX %in% TREATMENT_CODES$proton_cpt) %>%
      filter(!is.na(PX_DATE)) %>%
      select(ID, treatment_date = PX_DATE, triggering_code = PX) %>%
      distinct()

    message(glue("  PROCEDURES: {nrow(px_dates)} proton CPT procedure records"))
  }

  # Return combined results (only one source, so just px_dates)
  return(px_dates)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Lumping all beam radiation into "Radiation" | Separate "Proton Therapy" from "Radiation" | Phase 94 (2026-06-09) | Enables proton-specific treatment tracking, separate Gantt visualization, distinct sub-category summaries |
| 15 radiation codes in DRUG_GROUPINGS | 11 radiation + 4 proton codes split | Phase 94 | Historical comparison requires noting that prior outputs aggregated proton with radiation |

**Deprecated/outdated:** N/A — this is new categorization, not replacing deprecated patterns.

## Open Questions

### Question 1: Should proton therapy use radiation's gap threshold (90 days) or a custom threshold?

**What we know:**
- R/25_treatment_durations.R defines get_gap_threshold() to determine max days between treatment dates to consider them part of the same cycle
- Current thresholds: Chemotherapy = 90 days (default), Radiation has no override (uses 90), SCT has no override (uses 90), Immunotherapy has no override (uses 90)
- Proton therapy is a radiation modality (beam therapy) with similar fractionation patterns to EBRT

**What's unclear:**
- Whether proton fractionation schedules differ enough from conventional radiation to warrant a shorter gap threshold
- Clinical protocols for proton therapy (e.g., pediatric cases may have longer interruptions)

**Recommendation:**
- Default to 90-day threshold (same as radiation) for Phase 94
- Add comment in code flagging this as a clinical validation item
- If clinical reviewers identify proton-specific gap patterns, update in future phase

### Question 2: Are there ICD-10-PCS proton-specific codes we should add?

**What we know:**
- ICD-10-PCS Section D = Radiation Therapy
- Body System 0-9, A-W = anatomical regions
- Root Type 0 = Beam Radiation
- Modality Qualifier (6th character) includes: 0 = Photons, 1 = Heavy Particles (protons)
- Example: D0011ZZ = "Beam Radiation of Brain using Heavy Particles"

**What's unclear:**
- Whether PCORnet PROCEDURES.PX_TYPE == "3I" (ICD-10-PCS) contains proton-specific codes
- Whether TREATMENT_CODES should have proton_icd10pcs list to capture D*01* codes (modality 1 = Heavy Particles)
- Prevalence of ICD-10-PCS coding vs CPT coding for proton therapy in OneFlorida+ data

**Recommendation:**
- Phase 94 focuses on CPT codes only (D-03, D-06 specify 4 CPT codes)
- After phase completion, run audit query: "SELECT DISTINCT PX FROM PROCEDURES WHERE PX_TYPE = '3I' AND PX LIKE 'D%01%' (ICD-10-PCS beam radiation with heavy particles modality)
- If results show >0 proton ICD-10-PCS codes, create follow-up phase to add proton_icd10pcs list

### Question 3: Does CODE_SUBCATEGORY_MAP need a "Proton Therapy" entry?

**What we know:**
- R/56_new_tables_from_groupings.R uses 3-tier lookup for sub-categories: xlsx column G → CODE_SUBCATEGORY_MAP → code-type fallback
- CODE_SUBCATEGORY_MAP provides fallback sub-category mappings when xlsx lookup fails
- Current entries: Chemotherapy (medication names), Radiation (by type: IMRT, Brachytherapy, etc.), SCT (autologous vs allogeneic)

**What's unclear:**
- Whether "Proton Therapy" should have sub-categories (e.g., "Proton - Simple", "Proton - Complex")
- Whether all 4 proton codes should map to a single sub-category "Proton Therapy"
- Whether xlsx column G in all_codes_resolved2.xlsx already has proton sub-category mappings

**Recommendation:**
- Start with no CODE_SUBCATEGORY_MAP entry for Proton Therapy (let code-type fallback handle it: all map to "CPT")
- After phase completion, inspect output/episode_level_drug_grouping_tables.xlsx Sheet 1 to verify sub_category column shows reasonable values for proton rows
- If all show "CPT" (generic fallback) and clinical reviewers want "Simple"/"Intermediate"/"Complex" distinctions, add CODE_SUBCATEGORY_MAP entries in follow-up

## Environment Availability

> This section is skipped — Phase 94 is code/config-only changes with no external dependencies beyond existing R pipeline infrastructure.

## Sources

### Primary (HIGH confidence)

- **Codebase inspection:** R/00_config.R (TREATMENT_TYPES, TREATMENT_CODES, DRUG_GROUPINGS, TREATMENT_TYPE_COLORS definitions)
- **Codebase inspection:** R/10_cohort_predicates.R (has_radiation() pattern, treatment detection sources)
- **Codebase inspection:** R/25_treatment_durations.R, R/26_treatment_episodes.R (type-specific dispatch patterns, for-loop iteration over TREATMENT_TYPES)
- **Codebase inspection:** R/20_treatment_inventory.R, R/56_new_tables_from_groupings.R (xlsx sheet generation driven by TREATMENT_TYPES)
- **Codebase inspection:** R/88_smoke_test_comprehensive.R (validation of DRUG_GROUPINGS categories)
- **Phase 94 CONTEXT.md:** User decisions (D-01 through D-12) constraining implementation approach

### Secondary (MEDIUM confidence)

- **AMA CPT Manual structure:** Comment in R/00_config.R lines 2511-2524 documents CPT Radiation Oncology chapter structure (77261-77799), identifies 77520-77525 as Proton Beam Treatment Delivery subset
- **ICD-10-PCS structure:** ICD-10-PCS Section D (Radiation Therapy), Modality Qualifier 1 = Heavy Particles (protons) — flagged as open question for future investigation

### Tertiary (LOW confidence)

- **Clinical proton fractionation patterns:** No authoritative source consulted — flagged as open question for gap threshold validation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all dependencies already in pipeline, no new libraries
- Architecture patterns: HIGH — treatment type registration pattern well-established across 4 existing types, codebase inspection confirms TREATMENT_TYPES drives downstream iteration
- Code examples: HIGH — extracted from actual codebase (R/00_config.R, R/10, R/25, R/26), verified line numbers and patterns
- Pitfalls: MEDIUM — inferred from pattern analysis and likely failure modes, not observed in production
- Open questions: MEDIUM — identified from partial information (ICD-10-PCS structure known, prevalence in data unknown)

**Research date:** 2026-06-09
**Valid until:** 90 days (stable codebase, no major refactoring planned per v2.3 completion)
