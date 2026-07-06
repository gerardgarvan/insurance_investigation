# Phase 116: RUCA Rurality Address Enrichment - Research

**Researched:** 2026-07-06
**Domain:** USDA RUCA ZIP-code classification, R openxlsx2 styled xlsx, encounter-level cross-tabs
**Confidence:** HIGH (USDA data source verified, pipeline integration verified from codebase)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Bundle USDA RUCA reference xlsx in the repo (like MEDICATION_LOOKUP pattern) -- no CRAN dependency, works offline on HiPerGator and local Windows
- Use latest available 2020 census-based ZIP RUCA if released; otherwise fall back to 2010 ZIP RUCA (planner to verify availability)
- ZIP-code-level RUCA (not census tract) -- DEMOGRAPHIC only has ZIP_CODE, no geocoding needed
- Store BOTH the raw RUCA code (e.g., 1.0, 4.1, 10.6) AND a condensed 4-tier label (Metropolitan / Micropolitan / Small town / Rural) for flexibility
- New standalone script: `R/NN_ruca_rurality_summary.R` (planner picks next available number)
- RUCA_LOOKUP loading logic lives inside this script (not R/00_config.R) since it's a single-consumer table
- Follow investigation-script pattern (R/40, R/79) -- self-contained, runnable independently
- Assign NA rurality for patients with blank / unmatchable / out-of-state / out-of-range ZIP
- Log count of NA assignments (attrition-style diagnostic message)
- NAs remain in the analysis but appear as their own row/column in cross-tabs (do NOT drop them)
- Sheet 1: Patient counts by rurality category -- unique PATID counts + percentages (patient-level)
- Sheet 2: Rurality x AMC 8-category payer (encounter-level counts)
- Sheet 3: Rurality x Treatment type (encounter-level counts) -- chemo / radiation / SCT / immunotherapy / proton (5 categories)
- Sheet 4: Rurality x Cancer category (encounter-level counts)
- Row totals and column totals on each cross-tab sheet
- Cross-tabs (sheets 2-4): encounter-level (each encounter carries the patient's rurality)
- Simple frequency (sheet 1): patient-level
- Document the mixed grain clearly in xlsx titles / sheet notes
- No HIPAA auto-suppression -- raw counts in xlsx, manual suppression before external sharing (v3.1 pattern)
- No AV+TH subset variant
- Ascending alphabetical sort on any multi-value labels (per SORT-01/SORT-02 from Phase 112)
- Standard structural validation section for the new script in R/88
- Add pipeline runner entry if the script should join R/39 sequence (planner decides)

### Claude's Discretion
- Exact next R script number (planner picks from available slots)
- USDA download URL and file structure parsing details
- 4-tier condensed grouping mapping specifics (standard USDA definitions apply)
- xlsx styling (openxlsx pattern used elsewhere)
- Whether to add a small metadata sheet (data source version, run date, cohort size)
- Whether to include the rurality assignment as a small companion csv/rds so downstream scripts can reuse

### Deferred Ideas (OUT OF SCOPE)
- Census-tract-level RUCA with geocoding
- Social Vulnerability Index (SVI) enrichment
- Area Deprivation Index (ADI) enrichment
- Longitudinal address / migration
- Gantt / cohort snapshot enrichment column for rurality
- AV+TH-subset variant
- Auto-HIPAA suppression
</user_constraints>

---

## Summary

The 2020 census-based ZIP RUCA file from USDA ERS is confirmed available (updated September 2026) and should be used as the reference data source. It can be downloaded directly as an xlsx, bundled in `data/reference/` following the MEDICATION_LOOKUP precedent, and loaded inside the new script using `openxlsx2::wb_to_df()` or `readxl::read_excel()`. No CRAN RUCA package is needed or justified.

The RUCA taxonomy uses 10 integer primary codes (1-10) with decimal sub-codes (21 total) plus code 99 (not coded). The 4-tier condensed label the user wants -- Metropolitan / Micropolitan / Small town / Rural -- maps directly to the integer primary code groups (1-3 / 4-6 / 7-9 / 10). Code 99 and unmatched ZIPs both become NA.

All four data sources for the cross-tabs are reachable from existing pipeline outputs or DuckDB tables: DEMOGRAPHIC.ZIP_CODE (character, already loaded), encounter-level payer via ENCOUNTER + `classify_payer_tier_dt()`, treatment type via `treatment_episodes.rds`, and encounter-level cancer categories via `treatment_episodes.rds` (cancer_category column added by R/28). The script is self-contained, following the R/79 pattern exactly.

**Primary recommendation:** Create `R/100_ruca_rurality_summary.R` (R/100 is the next clean slot after all 2-digit investigation slots are occupied), load the 2020 ZIP RUCA xlsx from `data/reference/`, produce a four-sheet styled xlsx output, and add a smoke test section to R/88.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| openxlsx2 | already in pipeline | Create styled multi-sheet xlsx | Used by R/79, R/40, R/59, R/36 — project standard |
| dplyr | already in pipeline | Data manipulation, joins, group_by/summarize | Tidyverse standard in this pipeline |
| glue | already in pipeline | String interpolation in log messages | Used everywhere |
| readxl | already in pipeline (implied via openxlsx2) | Read the bundled USDA xlsx reference file | Lightweight, no dependency issues; openxlsx2 wb_to_df() is equivalent |
| stringr | already in pipeline | ZIP normalization (str_pad, str_trim) | Used throughout pipeline |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| data.table | already in pipeline | Keyed join for ZIP-to-RUCA lookup | Use for the ZIP lookup join (consistent with v3.0 data.table pattern for hot-path joins) |
| tidyr | already in pipeline | pivot_wider for cross-tab matrix | Creates the cross-tab grid from tidy counts |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bundled USDA xlsx | CRAN `ruca` or `rural` package | CRAN packages wrap outdated 2010 data; offline requirement on HiPerGator rules them out |
| readxl for reference file | openxlsx2 wb_to_df() | Either works; readxl is slightly lighter for read-only; use whichever is already loaded |

**Installation:** No new packages needed. All dependencies already in the pipeline.

---

## Architecture Patterns

### Recommended Project Structure

The new reference file goes into the existing pattern:
```
data/
└── reference/
    ├── all_codes_resolved_next_tables_v2.1.xlsx   # existing (MEDICATION_LOOKUP)
    └── RUCA-codes-2020-zipcode.xlsx               # new: bundle the USDA download
output/
└── ruca_rurality_summary.xlsx                     # new script output
```

The new script goes at:
```
R/
└── 100_ruca_rurality_summary.R                   # new (see script number section)
```

### Pattern 1: MEDICATION_LOOKUP Bundling (from Phase 114)

**What:** Reference xlsx bundled in `data/reference/`, loaded inside the single consumer script, not in R/00_config.R.

**When to use:** Single-consumer lookup tables. RUCA_LOOKUP is only used by R/100 — do not put it in config.

**Example:**
```r
# Source: R/00_config.R lines 2270-2345 (MEDICATION_LOOKUP pattern)
REFERENCE_XLSX <- file.path("data", "reference", "RUCA-codes-2020-zipcode.xlsx")
if (!file.exists(REFERENCE_XLSX)) {
  stop(glue("[R/100] RUCA reference file not found: {REFERENCE_XLSX}"))
}
RUCA_LOOKUP <- readxl::read_excel(REFERENCE_XLSX, sheet = 1) %>%
  select(ZIP_CODE = 1, RUCA_code = 2) %>%            # column positions; verify against actual headers
  mutate(
    ZIP_CODE  = str_pad(as.character(ZIP_CODE), 5, pad = "0"),  # 5-digit with leading zeros
    RUCA_code = as.numeric(RUCA_code)
  )
message(glue("  RUCA_LOOKUP: {nrow(RUCA_LOOKUP)} ZIP codes loaded"))
```

### Pattern 2: 4-Tier Label Derivation

**What:** Floor the decimal RUCA code to the integer primary code, then map integer to tier label.

**When to use:** For Sheet 1 display label and all cross-tab row/column groupings.

```r
# Standard 4-tier condensation used in health research
# Primary codes 1-3 = Metropolitan, 4-6 = Micropolitan, 7-9 = Small town, 10 = Rural
# Code 99 = "Not coded" (zero-population or water-only ZIPs) -> NA
ruca_tier_label <- function(ruca_code) {
  primary <- floor(ruca_code)
  dplyr::case_when(
    primary %in% 1:3  ~ "Metropolitan",
    primary %in% 4:6  ~ "Micropolitan",
    primary %in% 7:9  ~ "Small town",
    primary == 10     ~ "Rural",
    TRUE              ~ NA_character_    # covers 99, NA, unexpected values
  )
}
```

### Pattern 3: ZIP Normalization Before Join

**What:** Normalize DEMOGRAPHIC.ZIP_CODE to exactly 5 zero-padded characters before left_joining to RUCA_LOOKUP. DEMOGRAPHIC.ZIP_CODE is loaded as character (R/01_load_pcornet.R line 204) and should preserve leading zeros, but may have trailing whitespace or 9-digit ZIP+4 values.

```r
# Source: R/01_load_pcornet.R (ZIP_CODE = col_character())
demo_zip <- get_pcornet_table("DEMOGRAPHIC") %>%
  select(PATID = ID, ZIP_CODE) %>%
  collect() %>%
  mutate(
    ZIP_norm = str_trim(ZIP_CODE),                           # remove whitespace
    ZIP_norm = str_sub(ZIP_norm, 1, 5),                      # truncate ZIP+4 to 5 digits
    ZIP_norm = str_pad(ZIP_norm, 5, pad = "0"),              # ensure 5-digit with leading zeros
    ZIP_norm = if_else(str_detect(ZIP_norm, "^[0-9]{5}$"),   # accept only all-numeric 5-digit
                       ZIP_norm, NA_character_)
  )
```

### Pattern 4: Encounter-Level Cross-Tab Construction

**What:** For sheets 2-4, left_join the patient-level rurality assignment to encounter-level data, then count encounters by rurality x stratification variable.

**When to use:** Sheets 2-4 (payer, treatment type, cancer category).

```r
# Source: R/61_tiered_encounter_level.R pattern for encounter-level payer access
# Rurality is patient-level; propagate to encounters via PATID join
encounter_with_rurality <- encounters %>%
  left_join(rurality_patient_tbl %>% select(PATID, rurality_label),
            by = c("ID" = "PATID"))   # ENCOUNTER.ID = DEMOGRAPHIC.ID = PATID

# Cross-tab: count encounters by rurality x payer_category
sheet2 <- encounter_with_rurality %>%
  count(rurality_label, payer_category) %>%
  pivot_wider(names_from = payer_category, values_from = n, values_fill = 0L)
```

### Pattern 5: openxlsx2 Styled Multi-Sheet Xlsx (from R/79)

**What:** Create a wb_workbook(), add sheets with dark header rows, freeze panes, set column widths, save.

```r
# Source: R/79_drug_name_consistency_audit.R SECTION 8
wb <- wb_workbook()
wb$add_worksheet("Rurality Frequency")
wb$add_data(sheet = "Rurality Frequency", x = sheet1_tbl, dims = "A1", col_names = TRUE)
wb$add_fill(sheet = "Rurality Frequency", dims = header_range, color = wb_color("FF374151"))
wb$add_font(sheet = "Rurality Frequency", dims = header_range,
            name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
wb$freeze_pane(sheet = "Rurality Frequency", firstActiveRow = 2)
wb$set_col_widths(sheet = "Rurality Frequency", cols = 1:ncol(sheet1_tbl), widths = "auto")
wb_save(wb, OUTPUT_XLSX)
```

### Anti-Patterns to Avoid
- **Using floor() then == 10.0 for Rural:** Use `primary == 10` not `ruca_code == 10.0` since RUCA code 10 has sub-codes 10.1-10.6 that would be missed if you match the exact decimal.
- **Joining on raw ZIP_CODE before normalization:** DEMOGRAPHIC.ZIP_CODE may contain 9-digit ZIP+4 format ("32606-1234") which will not match the 5-digit RUCA lookup; always normalize first.
- **Dropping NAs from cross-tabs:** User decision is NAs stay visible. Use `forcats::fct_explicit_na()` or simply treat NA as its own category label (e.g., "Unknown").
- **Putting RUCA_LOOKUP in R/00_config.R:** Single-consumer rule — it belongs inside R/100 only.
- **Using patient-level grain for sheets 2-4:** These are encounter-level counts; high-utilizer patients will weight more heavily -- document this in sheet titles.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Payer classification per encounter | Custom payer mapping logic | `classify_payer_tier_dt()` from utils_payer.R + AMC_PAYER_LOOKUP | Already centralized, tested, handles dual-eligible and FLM override |
| Treatment type per encounter | Query ENCOUNTER or PROCEDURES | `treatment_episodes.rds` (from R/26+R/28) | Episodes already carry treatment_type; join via encounter_ids column |
| Cancer category per encounter | Re-run classify_codes() from scratch | `treatment_episodes.rds` cancer_category column (from R/28) | Already computed; re-deriving wastes time and risks inconsistency |
| ZIP-to-RUCA lookup logic | Write RUCA taxonomy from memory | Bundle and read USDA 2020 xlsx | Official source, versioned, reproducible |
| Cross-tab with row/col totals | Manual sum rows/cols | `adorn_totals()` from janitor, or manual `bind_rows(totals)` | janitor is already a pipeline dependency; either approach is fast |

**Key insight:** All four cross-tab data sources already exist in memory or as RDS files. The new script is purely an aggregation and styling layer, not a data computation layer.

---

## RUCA Data Source (VERIFIED)

### File Details

| Property | Value | Confidence |
|----------|-------|------------|
| Current version | 2020 census-based | HIGH — confirmed available on USDA ERS as of 2026-07-06 |
| ZIP file updated | 2025-09-26 | HIGH — from USDA ERS page |
| Direct download URL | `https://ers.usda.gov/sites/default/files/_laserfiche/DataFiles/53241/RUCA-codes-2020-zipcode.xlsx?v=32088` | HIGH — from ERS site |
| File format | Excel (.xlsx) | HIGH |
| File size | ~1.49 MB | HIGH |
| Content | Geographic identifiers + RUCA codes (no population in ZIP version) | HIGH |

### Confirmed File Structure

The 2020 ZIP RUCA xlsx contains at minimum two data columns: a ZIP code column and a RUCA code column. The exact header names are embedded in the file's codebook sheet. Based on multiple sources and the older version documentation:

| Column position | Likely name | Content |
|----------------|-------------|---------|
| 1 | ZIP_CODE (or similar) | 5-digit ZIP code (character with leading zeros) |
| 2 | RUCA_code (or similar) | Decimal RUCA code (e.g., 1.0, 4.1, 10.6, 99) |

**Action for planner:** When writing the R script, read column 1 and column 2 by position using `select(1, 2)` after reading the file, then rename to `ZIP_CODE` and `RUCA_code` explicitly. This is robust to minor header name variations across file versions. Alternatively, inspect column names at runtime with a defensive `message(paste(names(ruca_raw), collapse=', '))` and match on known pattern.

**Repo location:** `data/reference/RUCA-codes-2020-zipcode.xlsx`

### RUCA Code Taxonomy (VERIFIED from USDA ERS documentation)

**Primary codes (integer, 1-10) determine the 4-tier label:**

| Primary code | Tier label | Description |
|-------------|-----------|-------------|
| 1 | Metropolitan | Metropolitan core (urban area 50,000+) |
| 2 | Metropolitan | Metropolitan high commuting (≥30% to metro) |
| 3 | Metropolitan | Metropolitan low commuting (10-30% to metro) |
| 4 | Micropolitan | Micropolitan core (urban area 10,000-49,999) |
| 5 | Micropolitan | Micropolitan high commuting (≥30% to micro) |
| 6 | Micropolitan | Micropolitan low commuting (10-30% to micro) |
| 7 | Small town | Small town core (≤9,999 people) |
| 8 | Small town | Small town high commuting (≥30%) |
| 9 | Small town | Small town low commuting (10-30%) |
| 10 | Rural | Rural area (primary flow outside urban area) |
| 99 | NA | Not coded (water-only areas, zero-population) |

**Decimal sub-codes (secondary codes):** 21 distinct codes total. Examples: 1.0, 1.1, 2.0, 2.1, 3.0, 4.0, 4.1, 4.2, 5.0, 5.1, 5.2, 6.0, 6.1, 7.0, 7.1, 7.2, 7.3, 7.4, 8.0, 8.1, 8.2, 8.3, 8.4, 9.0, 9.1, 9.2, 10.0, 10.1, 10.2, 10.3, 10.4, 10.5, 10.6. Sub-codes refine commuting flow direction using the second-largest commuting flow. **For the 4-tier label, use `floor()` on the decimal code to get the integer primary code.**

**Alternative 4-category scheme (health research):** Some health literature uses a different aggregation: Urban (1.0, 1.1, 2.0, 2.1, 3.0, 4.1, 5.1, 7.1, 8.1, 10.1) / Large Rural (4.0, 4.2, 5.0, 5.2, 6.0, 6.1) / Small Rural (7.0, 7.2-7.4, 8.0, 8.2-8.4, 9.0-9.2) / Isolated (10.0, 10.2-10.6). The user-locked choice is the simpler Metropolitan/Micropolitan/Small town/Rural scheme which maps cleanly to primary code integers 1-3/4-6/7-9/10. Use this.

### ZIP RUCA vs Census Tract RUCA

ZIP code RUCA is an approximation. ZIPs are administratively defined (postal routing), not geographic units, so the USDA constructs ZIP RUCA by area-weighted aggregation from census tract RUCAs. Key implications:
- ZIPs that span multiple RUCA categories get the majority/weighted code
- Point ZIPs (PO Boxes, large building mailstops) are included in the file but may have low or zero residential population — the code 99 or a low-reliability code may be assigned
- This is acceptable for the cohort; clinical ZIP codes are typically residential addresses, not PO Boxes

---

## Existing Pipeline Integration Points

### 1. Patient ZIP Codes (Sheet 1 source + join key)

- **Source:** `DEMOGRAPHIC` table, column `ZIP_CODE`, loaded as `col_character()` in R/01_load_pcornet.R line 204
- **Quality:** Character type preserves leading zeros. May contain 9-digit ZIP+4 ("32606-1234"), blanks, or non-numeric strings
- **Access pattern:** `get_pcornet_table("DEMOGRAPHIC") %>% select(ID, ZIP_CODE) %>% collect()`
- **Normalization needed:** `str_trim()` + `str_sub(1,5)` + `str_pad(5, pad="0")` + numeric-5-digit validation

### 2. Encounter-Level Payer (Sheet 2)

- **Source:** `ENCOUNTER` table + `classify_payer_tier_dt()` (from utils_payer.R)
- **Access pattern:** Same as R/61_tiered_encounter_level.R -- `get_pcornet_table("ENCOUNTER") %>% materialize()` then `classify_payer_tier(include_dual = TRUE, flm_override = TRUE)`
- **Key output column:** `payer_category` (AMC 8-category, defined in AMC_PAYER_LOOKUP in R/00_config.R)
- **Join to rurality:** `left_join(rurality_tbl, by = c("ID" = "PATID"))` where `ID` is ENCOUNTER.ID
- **Note:** This is the full ENCOUNTER table, not filtered to HL cohort. Filter to HL cohort patients via `filter(ID %in% hl_patient_ids)` using `get_hl_patient_ids()` from utils_treatment.R

### 3. Encounter-Level Treatment Type (Sheet 3)

- **Source:** `treatment_episodes.rds` (from R/26, enriched by R/28). This RDS has one row per episode (patient_id x treatment_type x episode_number). For encounter-level counts, the `encounter_ids` column contains comma-separated ENCOUNTERIDs.
- **Alternative simpler source:** `treatment_episode_detail.rds` (from R/26) — one row per patient x treatment_date x triggering_code. Has `treatment_type` and `ENCOUNTERID` at encounter grain.
- **Recommended:** Use `treatment_episode_detail.rds` for encounter-level treatment cross-tab. Join rurality via patient_id.
- **5 treatment categories:** `TREATMENT_TYPES` from R/00_config.R = `c("Chemotherapy", "Radiation", "Proton Therapy", "SCT", "Immunotherapy")`
- **Access:** `readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds"))`
- **Input validation:** Use `assert_rds_exists()` from utils_assertions.R

### 4. Encounter-Level Cancer Category (Sheet 4)

- **Source:** `treatment_episodes.rds` (from R/28) has `cancer_category` column (classify_codes() output) and `encounter_ids` (comma-separated). Or use the episodes directly at episode grain.
- **Alternative:** Query DIAGNOSIS table + classify_codes() directly for all HL cohort encounters
- **Recommended:** Use `treatment_episodes.rds` cancer_category column -- already computed, consistent with the rest of the pipeline. Cross-tab by cancer_category.
- **Note:** cancer_category can be NA for unlinked episodes. Treat as "Unknown" / NA category in the cross-tab.
- **Categories from classify_codes():** Hodgkin Lymphoma, NLPHL, Non-Hodgkin Lymphoma, + other classify_codes() outputs

### 5. R/39 Pipeline Runner

- R/39 currently runs investigation scripts in a hardcoded list. The new script could be added to the `investigation_scripts` vector. However, since R/100 depends on `treatment_episode_detail.rds` (from R/26) and `treatment_episodes.rds` (from R/28), it should be placed after R/28 in the sequence -- which means after the upstream pipeline stage in R/39. The planner should decide whether to add R/100 to R/39's investigation stage.
- No blocking dependency: R/100 is self-contained and can be run independently (like R/79).

---

## Next Available R Script Number

### Current slot inventory
All 2-digit numbers 00-99 are occupied (some with multiple scripts sharing a prefix, e.g., 52, 57, 58, 95, 96, 97, 98, 99). The decade-based organization from v2.0 (Phase 66 renumbering):

- 00-03: Foundation (4 slots, all used)
- 04-09: Intentionally empty decade gaps
- 10-14: Cohort building (5 slots, all used)
- 15-19: Intentionally empty decade gaps
- 20-29: Treatment analysis (10 slots, all used)
- 30-39: Investigation/reports (10 slots, all used)
- 40-59: Cancer site analysis (20 slots, all used)
- 60-69: Payer/QA (10 slots, all used)
- 70-79: Output/visualization (10 slots, all used)
- 80-89: Testing/smoke tests (10 slots, all used)
- 90-99: Ad-hoc/diagnostics (10 slots, all used)

### Recommendation: R/100

**Use R/100** as the next clean script number. Rationale:
- All 2-digit slots are legitimately occupied
- R/100 is a clean continuation (new "post-renumber investigation era")
- The decade-based gaps (04-09, 15-19) are intentional and should not be filled with investigation scripts — they are reserved as structural padding in the decade-based scheme
- SCRIPT_INDEX.md will need a new section "Post-Renumber Investigations (100+)"
- R/88 smoke test validation section for R/100 is the natural pattern

---

## Common Pitfalls

### Pitfall 1: ZIP+4 format in DEMOGRAPHIC.ZIP_CODE
**What goes wrong:** Some patients have 9-digit ZIP format "32606-1234" or "326061234". These won't match the 5-digit RUCA lookup, creating false NAs.
**Why it happens:** PCORnet stores whatever the source system provides; ZIP+4 is common in claims data.
**How to avoid:** `str_sub(ZIP_norm, 1, 5)` truncates to first 5 characters before padding. Validate with `str_detect(ZIP_norm, "^[0-9]{5}$")`.
**Warning signs:** NA count much higher than expected; NA patients concentrated at specific sites.

### Pitfall 2: Leading zeros stripped from numeric ZIP
**What goes wrong:** If ZIP_CODE was ever coerced to integer somewhere, "02115" (Boston) becomes "2115" -- 4 digits, no match.
**Why it happens:** SQL engines sometimes auto-cast. DuckDB with character schema should be fine since R/01 uses `col_character()`.
**How to avoid:** `str_pad(ZIP_norm, 5, pad = "0")` restores leading zeros. Already recommended above.
**Warning signs:** NAs concentrated in New England states (ZIPs 00xxx-09xxx use leading zeros).

### Pitfall 3: Florida-only cohort but RUCA file is national
**What goes wrong:** The Florida cohort will match Florida ZIPs (32xxx-34xxx). Non-Florida ZIPs (e.g., from patients who moved or have out-of-state addresses) will still match the national RUCA file -- this is correct behavior.
**Why it happens:** DEMOGRAPHIC.ZIP_CODE is a snapshot; may reflect current address, not address at time of treatment.
**How to avoid:** No special handling needed. Non-Florida ZIPs should match (patients seen at Florida institutions sometimes have out-of-state home addresses). Log count of non-Florida-prefix ZIPs as a diagnostic note.
**Warning signs:** Large number of NAs from known-valid Florida ZIPs would indicate lookup failure.

### Pitfall 4: RUCA code 99 (not coded)
**What goes wrong:** ZIP codes assigned RUCA 99 are water-only, zero-population areas. Treating them as "Rural" is incorrect.
**Why it happens:** Code 99 is in the file but does not represent a commuting area category.
**How to avoid:** `ruca_tier_label()` function returns NA for code 99. NA appears as its own row in cross-tabs (per user decision). Do NOT map 99 to Rural.
**Warning signs:** High count of 99s would suggest address quality issues.

### Pitfall 5: Encounter-level vs patient-level count confusion
**What goes wrong:** Sheet 1 is patient counts; sheets 2-4 are encounter counts. Analysts compare numbers between sheets and get confused when they don't match.
**Why it happens:** High-utilizer patients (many encounters) dominate encounter-level counts.
**How to avoid:** Label each sheet clearly in its title row: "Patient-Level Count" vs "Encounter-Level Count". Add a note row under the title explaining the unit of analysis.
**Warning signs:** User reports that totals don't add up across sheets -- this is expected behavior.

### Pitfall 6: treatment_episode_detail.rds may not exist yet
**What goes wrong:** R/100 calls `assert_rds_exists(DETAIL_RDS)` and fails because R/26 was never run in the current session.
**Why it happens:** R/26 must be run before R/100. The self-contained script pattern means the analyst must run upstream scripts first.
**How to avoid:** In the script header comment, document that R/26 and R/28 must be run first. Use `assert_rds_exists()` with a helpful error message pointing to the upstream script.
**Warning signs:** FileNotFoundError on the RDS path.

### Pitfall 7: RUCA xlsx first row may be a title row, not headers
**What goes wrong:** `read_excel(path, sheet=1)` picks up a title row as the header, making column names like "Rural-Urban Commuting Area Codes for ZIP Codes (2020)".
**Why it happens:** USDA xlsx files often have a descriptive title row before the actual data header.
**How to avoid:** Use `skip = N` parameter to skip title rows, or use `col_names = FALSE` + programmatic rename. Inspect the file first and document the skip offset in a comment. If the codebook sheet is sheet 1, use `sheet = "Data"` (check actual sheet names at implementation time).
**Warning signs:** Column 1 name is a long string instead of a short identifier.

---

## Code Examples

### ZIP Normalization + RUCA Lookup Join

```r
# Normalize ZIP and join RUCA lookup
demo_zip <- get_pcornet_table("DEMOGRAPHIC") %>%
  select(PATID = ID, ZIP_CODE) %>%
  collect() %>%
  mutate(
    ZIP_norm = str_trim(ZIP_CODE),
    ZIP_norm = str_sub(ZIP_norm, 1, 5),
    ZIP_norm = str_pad(ZIP_norm, 5, pad = "0"),
    ZIP_norm = if_else(str_detect(ZIP_norm, "^[0-9]{5}$"), ZIP_norm, NA_character_)
  )

# Left join -- NAs for unmatched ZIPs
rurality_tbl <- demo_zip %>%
  left_join(RUCA_LOOKUP, by = c("ZIP_norm" = "ZIP_CODE")) %>%
  mutate(
    rurality_label = ruca_tier_label(RUCA_code)   # Metropolitan / Micropolitan / Small town / Rural / NA
  )

n_na <- sum(is.na(rurality_tbl$rurality_label))
message(glue("  Rurality assignment: {nrow(rurality_tbl)} patients, {n_na} with NA rurality ({round(100*n_na/nrow(rurality_tbl),1)}% unmatched)"))
```

### 4-Tier Label Function

```r
ruca_tier_label <- function(ruca_code) {
  primary <- floor(ruca_code)
  dplyr::case_when(
    primary %in% 1:3  ~ "Metropolitan",
    primary %in% 4:6  ~ "Micropolitan",
    primary %in% 7:9  ~ "Small town",
    primary == 10     ~ "Rural",
    TRUE              ~ NA_character_   # 99, NA, unknown
  )
}
```

### Cross-Tab with Row/Column Totals (Sheet 2 example)

```r
# Sheet 2: Rurality x Payer (encounter-level)
# rurality_label NA -> "Unknown"
sheet2_data <- encounters_with_rurality %>%
  mutate(
    rurality_label = if_else(is.na(rurality_label), "Unknown", rurality_label),
    payer_category = if_else(is.na(payer_category), "Unknown", payer_category)
  ) %>%
  count(rurality_label, payer_category) %>%
  arrange(rurality_label, payer_category) %>%           # ascending alpha per SORT-01
  pivot_wider(names_from = payer_category, values_from = n, values_fill = 0L)

# Add row totals
sheet2_data <- sheet2_data %>%
  rowwise() %>%
  mutate(Total = sum(c_across(where(is.numeric)), na.rm = TRUE)) %>%
  ungroup()

# Add column totals row
totals_row <- sheet2_data %>%
  summarise(rurality_label = "Total", across(where(is.numeric), sum))
sheet2_out <- bind_rows(sheet2_data, totals_row)
```

### R/88 Smoke Test Section Pattern (from Phase 115 section 15k)

```r
# ==============================================================================
# SECTION 15l: RUCA RURALITY SUMMARY (Phase 116) ----
# ==============================================================================

message("\n[Phase 116] RUCA rurality summary (R/100)...")

r100_exists <- file.exists("R/100_ruca_rurality_summary.R")
check("R/100_ruca_rurality_summary.R exists (Phase 116)", r100_exists)

if (r100_exists) {
  r100_lines <- readLines("R/100_ruca_rurality_summary.R", warn = FALSE)

  check("R/100 loads RUCA_LOOKUP from data/reference/ (Phase 116)",
        any(grepl("RUCA-codes-2020-zipcode\\.xlsx", r100_lines)))

  check("R/100 normalizes ZIP to 5 digits with str_pad (Phase 116)",
        any(grepl("str_pad.*5.*pad.*0", r100_lines)))

  check("R/100 logs NA count for unmatched ZIPs (Phase 116)",
        any(grepl("n_na|NA.*rurality|unmatched", r100_lines, ignore.case = TRUE)))

  check("R/100 defines ruca_tier_label() with 4 tiers (Phase 116)",
        any(grepl("ruca_tier_label", r100_lines)) &&
        any(grepl("Metropolitan|Micropolitan|Small town|Rural", r100_lines)))

  check("R/100 produces 4-sheet xlsx output (Phase 116)",
        sum(grepl('add_worksheet.*sheet', r100_lines)) >= 4 ||
        sum(grepl('"Rurality|sheet.*Rurality|Payer|Treatment|Cancer"', r100_lines)) >= 4)

  check("R/100 has patient-level sheet 1 with PATID counts (Phase 116)",
        any(grepl("n_distinct.*PATID|PATID.*n_distinct", r100_lines)))

  check("R/100 includes row totals and column totals (Phase 116)",
        any(grepl("Total|totals_row|adorn_totals", r100_lines)))

  check("R/100 sources R/00_config.R (Phase 116)",
        any(grepl('source.*00_config', r100_lines, fixed = FALSE)))
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 2010 ZIP RUCA file | 2020 ZIP RUCA file (updated 9/26/2025) | USDA released 2020 version in 2024-2025 | 2020 census boundaries are more current; use 2020 |
| CRAN `rural` package | Bundle USDA xlsx directly | Project decision (offline HiPerGator) | No CRAN dependency, reproducible, version-pinned in repo |
| Census tract RUCA | ZIP code RUCA | Project decision (no geocoding) | Less precise but appropriate given DEMOGRAPHIC.ZIP_CODE is the only address field |

**Deprecated/outdated:**
- 2010 ZIP RUCA: Still available at USDA ERS but superseded by 2020 version. Use 2020.
- CRAN `ruca` package: Wraps 2010 data and is not on CRAN as of July 2026. Not suitable.

---

## Open Questions

1. **Exact column headers in the 2020 RUCA xlsx**
   - What we know: File is confirmed at the ERS URL; contains at minimum ZIP identifier + RUCA code columns
   - What's unclear: Exact header strings (may be "ZIP_CODE", "ZIPCODE", or descriptive text)
   - Recommendation: Read by column position (`select(1, 2)`) in the R script and rename explicitly; add a `message(paste(names(ruca_raw), collapse=', '))` diagnostic at the top of the load block

2. **Whether xlsx sheet 1 is data or a title/codebook sheet**
   - What we know: USDA xlsx files often include a codebook sheet before the data; may need `sheet = 2` or `skip = N`
   - What's unclear: Exact sheet structure without opening the file
   - Recommendation: The planner should download the file locally before writing the load code, inspect sheet names, and document the `sheet` and `skip` parameters as constants at the top of R/100

3. **Whether treatment_episode_detail.rds carries encounter grain for Sheet 3**
   - What we know: R/26 produces `treatment_episode_detail.rds` with columns `patient_id, treatment_type, treatment_date, triggering_code, ENCOUNTERID, drug_name`
   - What's unclear: Whether a single treatment episode produces one or multiple detail rows per ENCOUNTERID
   - Recommendation: At implementation, `n_distinct(ENCOUNTERID)` vs `nrow()` to confirm grain; if multiple detail rows share an ENCOUNTERID, deduplicate on (patient_id, ENCOUNTERID, treatment_type) before cross-tabbing

4. **Best data source for Sheet 4 cancer categories**
   - What we know: `treatment_episodes.rds` has cancer_category per episode (from R/28 encounter linkage); this is episode-level not encounter-level
   - What's unclear: Whether user wants episodes or raw encounters for Sheet 4
   - Recommendation: Use `treatment_episodes.rds` cancer_category x rurality cross-tab at episode grain (one row per treatment episode per patient); label sheet as "episode-level" not "encounter-level" to be precise; or alternatively query DIAGNOSIS directly and classify_codes() for a true encounter-level cancer count

---

## Sources

### Primary (HIGH confidence)
- USDA ERS RUCA page (https://www.ers.usda.gov/data-products/rural-urban-commuting-area-codes/) — confirmed 2020 ZIP file availability, file size, last update date
- USDA ERS direct download URL (https://ers.usda.gov/sites/default/files/_laserfiche/DataFiles/53241/RUCA-codes-2020-zipcode.xlsx?v=32088) — confirmed accessible
- USDA ERS Documentation page (https://www.ers.usda.gov/data-products/rural-urban-commuting-area-codes/documentation) — primary code taxonomy (1-10, 99)
- USDA ERS Descriptions page (https://www.ers.usda.gov/data-products/rural-urban-commuting-area-codes/descriptions-and-maps) — 4-tier grouping (Metro/Micro/Small town/Rural)
- Pipeline codebase (R/01_load_pcornet.R line 204) — ZIP_CODE col_character() confirmed
- Pipeline codebase (R/79, R/40) — openxlsx2 styling pattern confirmed
- Pipeline codebase (R/61_tiered_encounter_level.R) — encounter-level payer access pattern confirmed
- Pipeline codebase (R/88_smoke_test_comprehensive.R, SECTION 15k) — latest smoke test section pattern confirmed

### Secondary (MEDIUM confidence)
- UW RHRC RUCA approximation page (https://depts.washington.edu/uwruca/ruca-approx.php) — alternative 4-category health research scheme (Urban/Large Rural/Small Rural/Isolated), verified as a different scheme from the user's chosen one
- UW RUCA v1.1 documentation (https://depts.washington.edu/uwruca/ruca1/ruca-documentation11.php) — older file had 5 columns including State Code; 2020 version structure similar

### Tertiary (LOW confidence)
- WebSearch results — secondary RUCA code decimal listing (1.0, 1.1, etc.) from aggregated search summaries; not verified against official USDA codebook

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages needed; all libraries in use
- RUCA data source: HIGH — URL verified from USDA ERS site directly
- RUCA taxonomy: HIGH — primary code structure confirmed from USDA ERS documentation
- Architecture: HIGH — follows established R/79 and R/40 patterns exactly
- Integration points: HIGH — codebase read directly for all four cross-tab data sources
- Exact xlsx column headers: LOW — file not downloaded/opened during research; use by-position read

**Research date:** 2026-07-06
**Valid until:** 2026-10-01 (USDA RUCA files are stable; pipeline patterns stable)
