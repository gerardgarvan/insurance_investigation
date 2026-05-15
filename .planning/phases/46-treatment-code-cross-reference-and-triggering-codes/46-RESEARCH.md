# Phase 46: Treatment Code Cross-Reference & Triggering Codes — Research

**Researched:** 2026-05-15
**Domain:** R pipeline — openxlsx2 styled reports, DuckDB-backed data queries, episode CSV modification
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Gap report scope
- D-01: Cross-reference all 4 active treatment types: chemotherapy, radiation, SCT, immunotherapy
- D-02: Merge both documents as source — TreatmentVariables_2024.07.17.docx (broad, 6 categories) AND Treatment_Variable_Documentation.docx (implementation-focused, adds Q-codes, ICD-10-PCS patterns, doxorubicin detail)
- D-03: Include external xlsx files in comparison: PCS Codes Cancer Tx.xlsx, ComprehensiveSurgeryCodes.xlsx, MSDRGs.xlsx (all now in project directory)

#### Range handling
- D-04: Compare at range level, not individual code expansion. For each docx range, report: what the docx says, what config covers, and what's intentionally excluded with rationale
- D-05: Range coverage summary format: "Docx says X-Y. Config covers A-B (N codes). Gap: C-D intentionally excluded (reason)." Annotate with Phase 45 rationale where applicable.

#### Triggering codes format
- D-06: Comma-separated `triggering_codes` column in episode CSVs (e.g., "77427,77412,77386"). One row per episode preserved.
- D-07: Include ALL codes that matched TREATMENT_CODES within the episode's date window, not just the first code
- D-08: Bare codes only — no type prefix (PX_TYPE is implied by code format)
- D-09: Triggering codes appear in BOTH CSV and styled xlsx output for consistency
- D-10: Modify existing R/44_treatment_episodes.R to add the triggering_codes column

#### Gap report output
- D-11: Styled xlsx with one sheet per treatment type (Chemo, Radiation, SCT, Immunotherapy) plus a summary sheet
- D-12: Each sheet shows codes in doc but not config AND codes in config but not doc
- D-13: Codes added via Phase 45 audit (42 radiation codes) shown in gap report with annotation "Added via Phase 45 audit — confirmed treatment codes in patient data"
- D-14: Include patient count and encounter count from PROCEDURES data for each gap code (requires DuckDB query on HiPerGator)

#### Docx parsing strategy
- D-15: Hardcode code lists from both docx files into R data structures. The docx content is static (dated 2024.07.17). Most reliable approach.
- D-16: Also hardcode code lists from external xlsx files (PCS Codes Cancer Tx.xlsx, ComprehensiveSurgeryCodes.xlsx, MSDRGs.xlsx) rather than reading at runtime
- D-17: All hardcoded data structures serve as the "reference" side of the two-way comparison

### Claude's Discretion
- Exact R data structure format for hardcoded docx/xlsx code lists (named lists, tribbles, etc.)
- Sheet styling details (colors, column widths, conditional formatting)
- Console output format and progress messages
- How to handle codes that appear in both docs with different categorizations
- Summary sheet content and layout

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TXREF-01 | Two-way gap report: codes in docx/xlsx reference but not in config, and codes in config but not in reference docs, for all 4 treatment types | Hardcoded reference structures + TREATMENT_CODES named list comparison; Phase 45 xlsx pattern for output |
| TXREF-02 | triggering_codes column in episode CSV and xlsx output showing which TREATMENT_CODES matched within each episode's date window | Modification to R/44_treatment_episodes.R calculate_episodes_detailed() + extract_all_dates() pattern |
</phase_requirements>

---

## Summary

Phase 46 has two independent deliverables that share a common dependency on `R/00_config.R` TREATMENT_CODES. Deliverable 1 (gap report) is a new script producing a multi-sheet xlsx comparing hardcoded reference code lists against the live config. Deliverable 2 (triggering codes) is a targeted modification to the existing `R/44_treatment_episodes.R` to capture which specific codes triggered each episode.

The gap report is cleanly modeled on the Phase 45 pattern (`R/45_radiation_cpt_audit.R`): hardcode the reference side as R data structures, query DuckDB PROCEDURES for patient/encounter counts for gap codes, produce a styled multi-sheet openxlsx2 workbook. The only material complexity is organizing code lists from multiple source documents across four treatment types — this is a documentation and data-structure design challenge, not a technical one.

The triggering codes modification requires understanding how `extract_all_dates()` currently loses the code identity during date extraction (it returns only `ID` and `treatment_date`). The fix is to preserve the matching code in the extract functions, then group-by episode to collect unique codes within each episode's window.

**Primary recommendation:** Implement as two separate scripts — `R/46_treatment_cross_reference.R` (new, gap report) and modify `R/44_treatment_episodes.R` in place (triggering codes). Both use established project patterns with no new library dependencies.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | current (project-wide) | Data manipulation, group_by/summarise for episode aggregation | Used in all pipeline scripts |
| stringr | current | str_detect for prefix matching, str_c for comma-joining codes | Used in all treatment scripts |
| glue | current | String interpolation in messages and cell content | Project standard |
| purrr | current | map_chr for per-code operations | Used in Phase 45 |
| openxlsx2 | current | Styled multi-sheet xlsx output | Project standard since Phase 42 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tibble | current | tribble() for compact inline data structure definition | Ideal for hardcoded reference tables |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| tribble() for reference data | named list | tribble is more readable for multi-column reference tables; named lists are better for single-vector code lookups |
| Hardcoded reference data (D-15/D-16) | Runtime docx/xlsx parsing | Hardcoding is more reliable; docx structure is not machine-friendly; runtime parsing adds dependencies |

**Installation:** No new packages required. All libraries already in project environment.

---

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 44_treatment_episodes.R   # MODIFY: add triggering_codes to calculate_episodes_detailed()
├── 46_treatment_cross_reference.R   # NEW: gap report script
output/
└── tables/
    └── treatment_cross_reference.xlsx   # NEW: gap report output
```

Output paths follow existing conventions: `file.path(CONFIG$output_dir, "tables", "treatment_cross_reference.xlsx")`.

Per-type CSV output paths are already established in Phase 44: `output/{type}_episodes.csv`. The triggering_codes column is added to these existing files.

### Pattern 1: Hardcoded Reference Data Structure

Reference code lists from docx/xlsx files should be stored as named lists of character vectors, organized by treatment type and code category. This mirrors how TREATMENT_CODES is organized in `R/00_config.R`.

**What:** A top-level named list `REFERENCE_CODES` with sub-lists per treatment type, each containing named character vectors of codes from the source documents.

**When to use:** All gap report operations — this is the "reference side" for both directions of the two-way comparison.

**Example:**
```r
# Source: Locked decision D-15/D-16; mirrors TREATMENT_CODES structure in R/00_config.R
REFERENCE_CODES <- list(
  chemotherapy = list(
    hcpcs_jcodes = c("J9000", "J9040", ...),  # From TreatmentVariables docx
    icd9_codes   = c("99.25", "99.28"),
    icd10pcs_prefixes = c("3E03305", ...),
    drg_codes    = c("837", "838", "839", "846", "847", "848"),
    revenue_codes = c(...)
  ),
  radiation = list(
    cpt_ranges   = list(
      list(range = "70010-79999", docx_text = "Radiology CPT codes", config_covers = "77261-77799", rationale = "AMA chapter structure — imaging excluded by design; see Phase 45 audit")
    ),
    icd9_codes   = c("92.20", "92.21", ...),
    icd10pcs_prefixes = c("D70", "D71", "D72", "D7Y"),
    drg_codes    = c("849")
  ),
  sct = list(
    cpt_codes    = c("38230", "38232", "38240", "38241", "38242", "38243"),
    hcpcs_codes  = c("S2140", "S2142", "S2150"),
    icd9_codes   = c("41.00", "41.01", ...),
    icd10pcs_codes = c("30230C0", ...),
    drg_codes    = c("014", "016", "017"),
    pcs_xlsx_codes = c(...)  # From PCS Codes Cancer Tx.xlsx
  ),
  immunotherapy = list(
    cart_icd10pcs = c("XW033C7", ...),
    drg_codes     = c("018"),
    q_codes       = c("Q0083", "Q0084", "Q0085")  # From Treatment_Variable_Documentation.docx
  )
)
```

### Pattern 2: Two-Way Comparison Function

For each treatment type and code category, compute set differences in both directions.

**What:** A function that takes a reference vector and a config vector and returns a list with `in_ref_not_config` and `in_config_not_ref` vectors.

**Example:**
```r
# Source: Base R set operations — no library dependency
compare_code_lists <- function(reference_codes, config_codes) {
  list(
    in_ref_not_config = setdiff(reference_codes, config_codes),
    in_config_not_ref = setdiff(config_codes, reference_codes)
  )
}
```

For prefix/range-based matching (radiation ICD-10-PCS, chemo ICD-10-PCS), the comparison logic must account for prefix matching — exact setdiff is wrong for these. The reference stores prefixes and the config stores prefixes; compare those directly. Document ranges (like radiation CPT 70010-79999) require the range-level narrative approach defined by D-04/D-05 rather than code-by-code comparison.

### Pattern 3: Triggering Codes in extract_all_dates()

The existing `extract_all_dates()` chain (in `R/43_treatment_durations.R`, sourced by `R/44_treatment_episodes.R`) discards code identity — it returns only `ID` and `treatment_date`. To add triggering codes, we need a parallel extraction that also returns the matching `PX` (code) column.

**What:** A new extraction function (or modified version) that returns `ID`, `treatment_date`, and `triggering_code`. Then in `calculate_episodes_detailed()`, after assigning episode_ids, group by episode and use `paste(sort(unique(triggering_code)), collapse = ",")` to build the comma-separated string.

**Critical constraint (D-07):** Include ALL codes that matched within the episode's date window — not just the first or dominant code. Use `distinct(ID, treatment_date, triggering_code)` before episode aggregation to avoid duplicates from multi-source stacking.

**Example pattern for PROCEDURES source:**
```r
# Modified to return triggering_code alongside treatment_date
px_dates_with_codes <- get_pcornet_table("PROCEDURES") %>%
  filter(
    (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) |
    (PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) |
    (PX_TYPE == "10" & str_detect(PX, rad_icd10pcs_rx)) |
    (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$radiation_revenue)
  ) %>%
  filter(!is.na(PX_DATE)) %>%
  select(ID, treatment_date = PX_DATE, triggering_code = PX) %>%
  collect()
```

Non-PROCEDURES sources (DIAGNOSIS, ENCOUNTER, TUMOR_REGISTRY) produce date evidence but not a meaningful single "code" — they should contribute NA or a sentinel label (e.g., "Z51.0", "DRG849", "TR_RAD") so they don't break episode aggregation logic.

**Episode aggregation with triggering codes:**
```r
# After stack_and_dedup (or equivalent), combine across sources:
group_by(ID, episode_id) %>%
summarise(
  episode_start = min(treatment_date),
  episode_stop  = max(treatment_date),
  episode_length_days = as.numeric(max(treatment_date) - min(treatment_date)),
  distinct_dates_in_episode = n_distinct(treatment_date),
  triggering_codes = paste(sort(unique(na.omit(triggering_code))), collapse = ","),
  .groups = "drop"
)
```

### Pattern 4: DuckDB Patient/Encounter Counts for Gap Codes (D-14)

For codes that appear in the reference but not in config (or vice versa), query PROCEDURES to get patient_count and encounter_count. This is the same pattern as Phase 45 Section 4.

```r
# Source: Phase 45 pattern (R/45_radiation_cpt_audit.R, Section 4)
gap_codes <- c("code1", "code2", ...)  # codes to investigate

proc_tbl <- get_pcornet_table("PROCEDURES") %>%
  filter(PX %in% gap_codes) %>%
  group_by(code = PX) %>%
  summarise(
    patient_count   = n_distinct(ID),
    encounter_count = n(),
    .groups = "drop"
  ) %>%
  collect()
```

### Pattern 5: Multi-Sheet openxlsx2 Workbook (Gap Report)

Follows Phase 44/45 pattern exactly. Sheet order: Summary, Chemotherapy, Radiation, SCT, Immunotherapy.

```r
# Source: Phase 44 R/44_treatment_episodes.R and Phase 45 R/45_radiation_cpt_audit.R
wb <- wb_workbook()
wb$add_worksheet("Summary")
# ... add data with wb$add_data(), style with wb$add_font(), wb$add_fill()
# Use int2col() for column refs (not int_to_col())
# Use format(x, big.mark=',') for thousands separators in glue() strings
wb$save(OUTPUT_PATH)
```

### Anti-Patterns to Avoid
- **Using int_to_col():** openxlsx2 uses `int2col()` — established pitfall from Phase 45
- **Python-style format spec in glue:** `glue("{x:,}")` fails in R; use `format(x, big.mark=',')`
- **Runtime docx/xlsx parsing for reference data:** Locked out by D-15/D-16; use hardcoded data
- **Expanding ranges to individual codes:** D-04 locks range-level comparison, not code-level expansion
- **Discarding code identity in date extraction:** The existing extract functions return only ID + treatment_date; the triggering codes modification must explicitly select PX alongside PX_DATE
- **Non-PROCEDURES sources contributing triggering codes ambiguously:** Diagnosis codes (Z51.0), DRG codes, and TUMOR_REGISTRY dates are valid date evidence but produce different "code" formats — handle consistently (include or annotate)

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-sheet xlsx styling | Custom cell-by-cell formatting loops | Established openxlsx2 pattern from Phase 44/45 | Already battle-tested; `wb$add_fill()`, `wb$add_font()`, `int2col()` gotchas already resolved |
| Code list comparison | Custom diff algorithm | Base R `setdiff()` | Exact set difference is what's needed; vectorized and correct |
| DuckDB patient counts | Custom SQL wrapper | `get_pcornet_table() %>% filter() %>% group_by() %>% summarise() %>% collect()` | Established Phase 29-45 pattern |
| Episode aggregation | Re-implementing window logic | Source from `R/43_treatment_durations.R` — `assign_episode_ids()` already exists | Do not duplicate episode logic |

**Key insight:** Phase 46 is almost entirely composition of existing patterns. The main work is (1) documenting the reference code lists accurately, and (2) threading triggering_code through the date extraction pipeline.

---

## Common Pitfalls

### Pitfall 1: Triggering Codes From Non-PROCEDURES Sources
**What goes wrong:** extract_all_dates() stacks 4-7 sources. Non-PROCEDURES sources (DIAGNOSIS, ENCOUNTER, TUMOR_REGISTRY) don't have a single meaningful "code" column — DIAGNOSIS has DX, ENCOUNTER has DRG, TUMOR_REGISTRY has date columns only. If triggering_code is pulled from each source naively, you get mixed code namespaces (ICD-10-CM Z codes, DRG numbers, NAs) in the same comma-separated string.
**Why it happens:** D-08 says "bare codes only" which suggests clean CPT/HCPCS/ICD codes; Z51.0 and "DRG849" are valid but visually different.
**How to avoid:** Decision D-08 says "bare codes only — no type prefix (PX_TYPE is implied by code format)." For the triggering_codes column, a pragmatic approach is to include only PROCEDURES-sourced codes (which have unambiguous bare codes) and note the count of additional date evidence from other sources. Alternatively, include all codes and rely on code format to imply type (Z51.0 reads as ICD-10, 77427 reads as CPT). Planner should pick one approach and apply consistently.
**Warning signs:** triggering_codes column containing values like "DRG849" or "TUMOR_REG" or mixed Z-codes alongside CPT codes in the same cell.

### Pitfall 2: Range vs. Code Comparison for Radiation CPT
**What goes wrong:** The docx says "70010-79999" as a range. If you try to do setdiff() with individual config codes, you get 62+ codes in config "not in reference" because no individual config code matches the string "70010-79999".
**Why it happens:** Ranges are not individual codes; direct string comparison fails.
**How to avoid:** D-04 mandates range-level narrative comparison, not code expansion. The Radiation sheet should have a narrative row explaining the Phase 45 finding: "Docx says 70010-79999. Config covers 77261-77799 (62 codes). Gap: 70010-77260, 77800-79999 intentionally excluded — AMA chapter structure confirms these are Diagnostic Imaging, not Radiation Treatment (Phase 45 audit)."

### Pitfall 3: Losing Code Identity in the Episode Window
**What goes wrong:** The current `calculate_episodes_detailed()` function summarises to episode level using `min(treatment_date)`, `max(treatment_date)`, etc. If triggering_code is added but uses `unique()` at the wrong step, it may aggregate across patients rather than within episodes.
**Why it happens:** The group_by chain is `group_by(ID, episode_id)` — triggering_code must be collected within this same group, not before or after.
**How to avoid:** Add `triggering_codes = paste(sort(unique(na.omit(triggering_code))), collapse = ",")` inside the same `summarise()` that computes episode_start/episode_stop. Verify the output has expected values with a spot-check row on a known patient.

### Pitfall 4: Phase 45 Annotation for Radiation Codes
**What goes wrong:** D-13 requires that the 42 radiation codes added in Phase 45 be annotated in the gap report. If the script checks `in_config` and `!in_reference` at time of execution, those codes will appear as "config but not in reference doc" — which is correct but needs the annotation.
**Why it happens:** Phase 45 codes were auto-added to config; the reference docx predates Phase 45 expansion.
**How to avoid:** Create a hard-coded vector `PHASE45_ADDED_CODES` listing the 42 codes added by Phase 45. When building the gap report rows, check if a config-only code is in this vector and apply the annotation "Added via Phase 45 audit — confirmed treatment codes in patient data."

### Pitfall 5: csv Column Order Change Breaks Downstream
**What goes wrong:** Inserting triggering_codes into the CSV changes column count. If any downstream script reads these CSVs with positional column access (e.g., `df[, 7]`) rather than named access, it will silently use the wrong column.
**Why it happens:** Hard to know without reading all downstream scripts.
**How to avoid:** Append triggering_codes as the LAST column in both CSV and xlsx output. The Phase 44 schema is `patient_id, episode_number, episode_start, episode_stop, episode_length_days, distinct_dates_in_episode, historical_flag` — add triggering_codes as column 8. This is the safest approach for backward compatibility.

---

## Code Examples

Verified patterns from existing project scripts:

### openxlsx2 Worksheet with int2col
```r
# Source: R/45_radiation_cpt_audit.R
n_cols <- 8L
wb$merge_cells(sheet = SHEET1, dims = glue("A1:{int2col(n_cols)}1"))
wb$add_fill(sheet = SHEET1, dims = glue("A2:{int2col(n_cols)}2"),
            color = wb_color(DARK_HEADER_FILL))
```

### Thousands Separator in glue
```r
# Source: R/45_radiation_cpt_audit.R (Phase 45 established fix)
message(glue("  Materialized {format(nrow(proc_materialized), big.mark = ',')} procedure records"))
# NOT: glue("{nrow(proc_materialized):,}")  -- Python syntax, fails in R
```

### DuckDB Group-By Count Pattern
```r
# Source: R/45_radiation_cpt_audit.R Section 4
codes_in_data <- bind_rows(codes_7x, codes_gx) %>%
  group_by(code = PX, px_type = PX_TYPE) %>%
  summarise(
    encounter_count = n(),
    patient_count   = n_distinct(ID),
    .groups = "drop"
  ) %>%
  arrange(code, px_type)
```

### classify_code_str Pattern (avoids if_else type issues)
```r
# Source: R/45_radiation_cpt_audit.R — use purrr::map_chr not if_else for per-code ops
codes_classified <- codes_in_data %>%
  mutate(
    classification = purrr::map_chr(code, function(c) {
      classify_code_str(c, classification_table)$classification
    })
  )
```

### TREATMENT_TYPE_COLORS Usage
```r
# Source: R/44_treatment_episodes.R
colors <- TREATMENT_TYPE_COLORS[[type]]
wb$add_fill(sheet = sheet_name, dims = "A2:G2", color = wb_color(colors$fill))
wb$add_font(sheet = sheet_name, dims = "A2:G2",
            name = "Calibri", size = 11, bold = TRUE, color = wb_color(colors$font))
```

### Episode Aggregation With Triggering Codes (new pattern for Phase 46)
```r
# Adapted from R/44_treatment_episodes.R calculate_episodes_detailed()
# Key addition: triggering_code must be retained through the group_by chain
dates_df %>%
  group_by(ID) %>%
  arrange(treatment_date, .by_group = TRUE) %>%
  mutate(episode_id = assign_episode_ids(treatment_date, gap_threshold)) %>%
  group_by(ID, episode_id) %>%
  summarise(
    episode_start               = min(treatment_date),
    episode_stop                = max(treatment_date),
    episode_length_days         = as.numeric(max(treatment_date) - min(treatment_date)),
    distinct_dates_in_episode   = n_distinct(treatment_date),
    triggering_codes            = paste(sort(unique(na.omit(triggering_code))), collapse = ","),
    .groups = "drop"
  )
```

---

## Key Technical Facts About Existing Code

### R/44_treatment_episodes.R — Modification Target

- `calculate_episodes_detailed()` takes `dates_df` with columns `ID` and `treatment_date`
- The function is self-contained in 44; it does NOT live in 43 (unlike `assign_episode_ids()` and `extract_all_dates()` which are in 43 and sourced)
- Current output schema: `patient_id, episode_number, episode_start, episode_stop, episode_length_days, distinct_dates_in_episode, historical_flag`
- The PROCEDURES source in `extract_radiation_dates()` selects only `ID, treatment_date = PX_DATE` — the code column (PX) is dropped at this step
- To add triggering codes, `extract_all_dates()` must be extended or a parallel `extract_all_dates_with_codes()` must be created

**Recommended approach:** Create a new `extract_all_dates_with_codes(type)` function in 44 that returns `ID`, `treatment_date`, and `triggering_code`. This avoids modifying the upstream 43 functions (which feed other scripts) and keeps the Phase 44 change self-contained.

### TREATMENT_CODES in R/00_config.R — Reference Side

Current structure relevant to gap report:
- `chemo_hcpcs`: 96 J-codes (J9000-J9999 range)
- `chemo_rxnorm`: ~100 RxNorm CUIs — NOTE: these are not CPT/HCPCS codes; they don't appear in the docx reference in the same form. Cross-reference is not meaningful for RxNorm.
- `radiation_cpt`: 62 codes (77261-77799 range, post-Phase 45 expansion)
- `sct_cpt`: 6 codes; `sct_hcpcs`: 3 S-codes
- `sct_icd10pcs`: 38 exact 7-char codes
- `cart_icd10pcs_prefixes`: 31 XW prefix codes (immunotherapy)
- ICD-9, ICD-10-PCS prefixes, DRG codes, revenue codes across all types

**Gap report scope by code type:**
- HCPCS/CPT: direct code-level setdiff
- ICD-9: direct code-level setdiff
- ICD-10-PCS: prefix-level comparison (both reference and config store prefixes)
- DRG: direct setdiff
- RxNorm: not in docx reference — omit from gap report or note "RxNorm not specified in reference documents"
- Revenue codes: check if reference documents specify revenue codes

### External xlsx Files (D-03, D-16)

Three files in project root are treated as reference sources:
- `PCS Codes Cancer Tx.xlsx` — likely ICD-10-PCS codes for cancer treatment (maps to sct_icd10pcs and cart_icd10pcs)
- `ComprehensiveSurgeryCodes.xlsx` — likely maps to SCT CPT or surgical codes
- `MSDRGs.xlsx` — DRG codes for all treatment types (chemo_drg, radiation_drg, sct_drg)

These should be read ONCE at research/planning time (manually, by the developer) to extract their code lists, then hardcoded per D-16. The planner should direct: read these files at plan execution time as a setup step, then hardcode the discovered codes.

### Phase 45 Radiation Codes Added

The 42 codes added by Phase 45 audit are already in `TREATMENT_CODES$radiation_cpt` with inline comments `# auto-added Phase 45: found in PROCEDURES data`. The gap report script can identify these by checking for that comment pattern OR by maintaining a hardcoded `PHASE45_ADDED_CODES` vector.

The most robust approach: hardcode the Phase 45 code list directly in the gap report script using the known codes from the config (identifiable by their `# auto-added Phase 45` comment).

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| int_to_col() | int2col() | Phase 45 | Breaks if wrong function used |
| httr | httr2 | Phase 40 | Not relevant here — no API calls |
| RDS-backed queries | DuckDB tbl_dbi via get_pcornet_table() | Phase 29-32 | Use DuckDB for all PROCEDURES queries |
| Per-patient summary only | Per-episode detail rows | Phase 44 | Phase 44 already handles episodes; Phase 46 extends it |

---

## Open Questions

1. **Which codes specifically did Phase 45 add to radiation_cpt?**
   - What we know: The Phase 45 audit auto-added 42 codes; they have `# auto-added Phase 45` comments in 00_config.R
   - What's unclear: The exact list is in 00_config.R but needs to be read carefully at plan execution time
   - Recommendation: The implementation plan should include a step to grep 00_config.R for `auto-added Phase 45` to extract the exact list for hardcoding in the gap report script

2. **Triggering codes for Tumor Registry date evidence**
   - What we know: TR dates come from columns like DT_RAD, DT_CHEMO — no individual treatment code, just a date
   - What's unclear: D-07 says "all codes that matched TREATMENT_CODES" — TR dates don't match a specific code
   - Recommendation: Planner should decide: either (a) omit TR-sourced dates from triggering_codes (they're supplemental date evidence, not code evidence) or (b) use a sentinel like "TR_RAD" or "TR_CHEMO". Option (a) is cleaner for the stated purpose ("which code triggered this?")

3. **External xlsx file contents**
   - What we know: Files exist in project root (PCS Codes Cancer Tx.xlsx, ComprehensiveSurgeryCodes.xlsx, MSDRGs.xlsx)
   - What's unclear: Exact column structure and whether code lists are already organized by treatment type
   - Recommendation: First plan task should be to read and document these files' schemas so the hardcoded reference structures can be built correctly

4. **How to handle chemo RxNorm in gap report**
   - What we know: config has ~100 RxNorm CUIs; neither docx specifies RxNorm CUIs
   - What's unclear: Whether to include RxNorm in the gap report or note it as "config-only, not in reference scope"
   - Recommendation: Include a note row on the Chemotherapy sheet: "RxNorm CUIs: N codes in config; not specified in reference documents (drug lookup-derived)"

---

## Sources

### Primary (HIGH confidence)
- Direct read of `R/44_treatment_episodes.R` — episode generation code, current schema, modification target
- Direct read of `R/45_radiation_cpt_audit.R` — template pattern for the gap report script
- Direct read of `R/00_config.R` (TREATMENT_CODES section) — config-side code lists for all 4 types
- Direct read of `R/utils_treatment.R` — shared helpers
- Direct read of `R/43_treatment_durations.R` — extract_all_dates() and assign_episode_ids() patterns

### Secondary (MEDIUM confidence)
- `.planning/STATE.md` — Phase 45 completion status and key decisions
- `.planning/phases/46-treatment-code-cross-reference-and-triggering-codes/46-CONTEXT.md` — all user decisions

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already in project; no new dependencies
- Architecture: HIGH — both deliverables follow established Phase 44/45 patterns with minor extensions
- Pitfalls: HIGH — based on direct code reading; triggering code loss pitfall verified against actual extract_all_dates() implementation
- Reference code lists: MEDIUM — external xlsx file contents not directly read; recommend reading at plan execution time

**Research date:** 2026-05-15
**Valid until:** 2026-06-15 (stable domain; only risk is if 00_config.R TREATMENT_CODES changes before implementation)
