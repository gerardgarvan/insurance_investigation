# Architecture Research

**Domain:** PCORnet CDM R Analysis Pipeline — v1.6 Treatment Code Validation & Cancer Site Analysis
**Researched:** 2026-04-21
**Confidence:** HIGH (based on direct inspection of all existing R scripts and reference files)

## Standard Architecture

### System Overview

The existing pipeline follows a **standalone diagnostic script** pattern on top of a DuckDB backend with a centralized config layer. Each numbered script is independently runnable: it sources config, opens a DuckDB connection via `get_pcornet_table()`, does its work, and writes output to `output/` or RDS cache. There is no shared in-memory state between scripts — scripts are not chained at runtime.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CONFIG LAYER                                 │
│  R/00_config.R: TREATMENT_CODES, AMC_PAYER_LOOKUP, CONFIG, GAP_*    │
│  R/utils_treatment.R: safe_table(), get_hl_patient_ids(), etc.       │
├─────────────────────────────────────────────────────────────────────┤
│                      BACKEND ABSTRACTION                             │
│  R/01_load_pcornet.R: get_pcornet_table(name) → tbl_dbi or tibble   │
│  USE_DUCKDB flag (default TRUE) → DuckDB lazy SQL queries            │
│  materialize() helper for in-memory regex ops on DuckDB result sets  │
├──────────────┬──────────────────────────────────┬───────────────────┤
│  TREATMENT   │  TREATMENT CODES / EPISODES       │  PAYER ANALYSIS  │
│  INVENTORY   │  R/43_treatment_durations.R        │  R/35_*, R/36_*  │
│  R/38_*.R    │  R/44_treatment_episodes.R         │  R/45_*, R/46_*  │
│  (4-type     │  (per-patient, per-episode dates,  │  (frequency,     │
│  inventory   │   RDS + xlsx + per-type CSVs)      │   hierarchy)     │
│  xlsx)       │                                    │                  │
├──────────────┴──────────────────────────────────┴───────────────────┤
│  RESOLVED CODE REPORTS: R/42_treatment_codes_resolved.R             │
│  write_resolved_xlsx() → 2-sheet styled workbook per treatment type  │
├─────────────────────────────────────────────────────────────────────┤
│                     REFERENCE FILE INPUTS                            │
│  VariableDetails.xlsx  (Treatment sheet: 123 rows, modality+codes)   │
│  TreatmentVariables_2024.07.17.docx  (CPT ranges, source tables)     │
│  CancerSiteCategories.xlsx  (Groups sheet: 43 rows, ICD10/ICDO3)     │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Status |
|-----------|---------------|--------|
| `R/00_config.R` | TREATMENT_CODES (named list), AMC_PAYER_LOOKUP, CONFIG paths, GAP_THRESHOLD, TREATMENT_TYPES, TREATMENT_TYPE_COLORS | Existing — may receive additions |
| `R/01_load_pcornet.R` | `get_pcornet_table(name)` dispatcher — returns DuckDB tbl or tibble depending on USE_DUCKDB | Existing — unchanged |
| `R/utils_treatment.R` | `safe_table()`, `empty_result()`, `get_hl_patient_ids()`, `nrow_or_0()` | Existing — unchanged |
| `R/38_treatment_inventory.R` | Scans all 7 PCORnet tables for 4 treatment types, produces styled multi-sheet xlsx | Existing — unchanged |
| `R/42_treatment_codes_resolved.R` | `write_resolved_xlsx()` reusable function; produces per-type 2-sheet xlsx | Existing — unchanged |
| `R/43_treatment_durations.R` | `extract_all_dates()` + `assign_episode_ids()` + per-patient summary | Existing — unchanged |
| `R/44_treatment_episodes.R` | Per-episode detail from Phase 43 functions; per-type CSVs | Existing — **modified**: add triggering code column |
| **R/45_cancer_site_frequency.R** | Read CancerSiteCategories.xlsx, expand ICD10 ranges, query TUMOR_REGISTRY + DIAGNOSIS, produce frequency table | **New** |
| **R/46_treatment_code_crossref.R** | Parse VariableDetails.xlsx Treatment sheet + TreatmentVariables docx; diff against TREATMENT_CODES in config; produce gap report | **New** |
| **R/47_radiation_cpt_audit.R** | Audit 70010-79999 CPT range in PROCEDURES; classify imaging vs treatment; verify proton codes 77520-77525 present | **New** |

## Recommended Project Structure

No structural changes to directories. New scripts follow the existing numbered pattern in `R/`:

```
R/
├── 00_config.R                  # TREATMENT_CODES — may add proton codes, correct descriptions
├── ...
├── 42_treatment_codes_resolved.R  # write_resolved_xlsx() — unchanged
├── 43_treatment_durations.R       # extract_all_dates() — unchanged
├── 44_treatment_episodes.R        # MODIFIED: add triggering_codes column to CSV output
├── 45_cancer_site_frequency.R     # NEW: CancerSiteCategories.xlsx → TUMOR_REGISTRY/DIAGNOSIS freq
├── 46_treatment_code_crossref.R   # NEW: VariableDetails.xlsx + docx diff vs TREATMENT_CODES
├── 47_radiation_cpt_audit.R       # NEW: 70010-79999 CPT audit in PROCEDURES
output/
├── cancer_site_frequency.xlsx     # Output from R/45
├── treatment_code_crossref.xlsx   # Output from R/46
├── radiation_cpt_audit.xlsx       # Output from R/47
└── (per-type episode CSVs updated with triggering_codes column)
```

## Architectural Patterns

### Pattern 1: Standalone Diagnostic Script

**What:** Every v1.3+ script follows this template — `source("R/00_config.R")`, `source("R/01_load_pcornet.R")`, call `get_pcornet_table()` for lazy DuckDB access, do work, write output. No runtime coupling to other scripts.

**When to use:** All new scripts in this milestone follow this pattern.

**Example structure:**
```r
source("R/00_config.R")
source("R/01_load_pcornet.R")

OUTPUT_PATH <- file.path(CONFIG$output_dir, "cancer_site_frequency.xlsx")

# ... load reference file, query tables, write xlsx
wb <- wb_workbook()
# ... style and write
wb$save(OUTPUT_PATH)
```

### Pattern 2: readxl for Spreadsheet Input, openxlsx2 for Output

**What:** Reference xlsx files (VariableDetails.xlsx, CancerSiteCategories.xlsx) are read with `readxl::read_excel()`. All output xlsx workbooks are built with `openxlsx2`, matching the styling established in R/38 and R/42 (dark header fills, color-coded first column, freeze panes, column widths).

**When to use:** Any script reading reference spreadsheets or writing styled output.

**Trade-offs:** readxl and openxlsx2 are already installed project-wide. No new dependencies needed.

### Pattern 3: ICD10 Range Expansion

**What:** CancerSiteCategories.xlsx stores code ranges as strings (e.g., `"C810-C814, C817, C819"`). These must be parsed and expanded into individual ICD-10-CM codes before matching against TUMOR_REGISTRY or DIAGNOSIS tables. The expansion logic lives in the script that uses the file, not in a shared utility, because this is the first use of range-format ICD codes in the pipeline.

**Key detail from CancerSiteCategories.xlsx inspection:**
- Sheet: "Groups", 43 rows (42 cancer site entries + header)
- Columns: Site, Detailed site, Primary disease site, ICD10, ICDO3
- ICD10 column holds comma-separated ranges like `"C810-C814, C817, C819"` — requires range expansion
- ICDO3 column holds similar ranges — optional for TUMOR_REGISTRY histology matching
- Hodgkin Lymphoma row: ICD10 = `"C810-C814, C817, C819"`, ICDO3 = `"9650-9655, 9659, 9663-9665, 9667"`

**When to use:** R/45_cancer_site_frequency.R — parse ranges once on load, then use `%in%` or `filter(DX %in% expanded_codes)`.

### Pattern 4: Docx Text Extraction for Cross-Reference

**What:** TreatmentVariables_2024.07.17.docx is not machine-readable as a table — it is a Word document with prose and bulleted lists. The relevant content for cross-reference is:
- Radiation CPT range: "From PROCEDURES: 70010-79999" (broad range, not individual codes)
- Chemo CPT: "PX = 96401-96549, J8501-J9999"
- SCT CPT: "38240, 38241, 38242, 38243"
- SCT ICD-10-PCS: explicit full codes (30230C0, 30230G0, etc.)
- Immunotherapy: XW0xx CAR T-cell codes
- DRG codes per treatment type

VariableDetails.xlsx Treatment sheet (123 rows) is the more structured source and covers SCT + immunotherapy codes explicitly. The docx provides the broader "from PROCEDURES: 70010-79999" range specification for radiation.

**Approach for R/46:** Parse VariableDetails.xlsx with readxl (clean tabular source), use the docx text content (accessible via unzip + XML parse in R with `xml2` package, or simpler: the docx text was confirmed extractable) to confirm the radiation range definition. The cross-reference compares codes listed in VariableDetails.xlsx Treatment sheet against codes in TREATMENT_CODES from config.

### Pattern 5: Triggering Code Column via Back-Join

**What:** R/44_treatment_episodes.R currently produces per-episode rows with no code traceability. Adding a `triggering_codes` column requires joining the episode output back to the raw date-extraction results from R/43's `extract_all_dates()`, which already knows which codes produced each date. The pattern is: extract dates with their source codes, aggregate dates into episodes as before, then for each episode collect the distinct triggering codes that fall within the episode window.

**When to use:** The triggering code column in R/44 is the only case where a new column must trace back to raw code evidence.

**Implementation note:** `extract_all_dates()` in R/43 currently returns only `ID` and `treatment_date` columns. Modifying it to also return `triggering_code` and `code_type` columns (without changing its episode logic) enables the join. R/44 sources R/43 directly, so the change propagates automatically.

## Data Flow

### v1.6 New Data Flows

```
[CancerSiteCategories.xlsx]
    ↓  (readxl, range expansion)
[expanded ICD10 code list by site group]
    ↓
[TUMOR_REGISTRY_ALL via get_pcornet_table()]   [DIAGNOSIS via get_pcornet_table()]
    ↓                                               ↓
[count patients by cancer site + source table]
    ↓
[cancer_site_frequency.xlsx]  ← R/45_cancer_site_frequency.R
```

```
[VariableDetails.xlsx Treatment sheet]     [TreatmentVariables_2024.07.17.docx text]
    ↓  (readxl, forward-fill Modality col)     ↓  (xml2 or zip+read approach)
[reference code set per modality]          [CPT range definitions per type]
    ↓
[diff vs TREATMENT_CODES in R/00_config.R]
    ↓
[in_config_not_in_reference | in_reference_not_in_config | common]
    ↓
[treatment_code_crossref.xlsx]  ← R/46_treatment_code_crossref.R
```

```
[PROCEDURES via get_pcornet_table()]
    ↓  (filter PX_TYPE == "CH", 70010 <= as.numeric(PX) <= 79999)
[CPT codes in range]
    ↓  (classify: imaging vs treatment vs unknown using CPT category logic)
[radiation_cpt_audit.xlsx]  ← R/47_radiation_cpt_audit.R
    includes: proton codes 77520-77525 presence/absence, imaging exclusion rationale
```

```
[R/43_treatment_durations.R: extract_all_dates() — MODIFIED]
    ↓  (now returns ID + treatment_date + triggering_code + code_type)
[R/44_treatment_episodes.R: calculate_episodes_detailed() — MODIFIED]
    ↓  (group triggering codes within episode window, collapse to comma-sep string)
[per-type CSV output with new triggering_codes column]
```

### Key Integration Points

1. **R/00_config.R → R/45, R/46, R/47:** All three new scripts source config. R/46 reads `TREATMENT_CODES` directly to perform the diff. R/47 reads `TREATMENT_CODES$radiation_cpt` to distinguish already-captured vs newly-found codes. R/45 uses `CONFIG$output_dir` for output path.

2. **R/43 → R/44 (triggering codes change):** R/44 sources R/43 with `source("R/43_treatment_durations.R")`. If `extract_all_dates()` in R/43 is extended to return a `triggering_code` column, R/44 picks it up automatically. This is the only inter-script dependency change in this milestone.

3. **CancerSiteCategories.xlsx → R/45:** The file lives in the project root. ICD10 column requires range expansion (e.g., "C810-C814" → c("C810","C811","C812","C813","C814")). ICDO3 column is optional — use for TUMOR_REGISTRY histology cross-check only.

4. **VariableDetails.xlsx → R/46:** The Treatment sheet uses a merged-cell pattern (Modality column has None/NA for rows below the first in each group). readxl reads these as NA. A `fill()` forward-fill on the Modality column is required before use.

5. **PROCEDURES table → R/47:** The 70010-79999 CPT range includes both imaging codes (diagnostic radiology, nuclear medicine) and therapeutic radiation delivery codes. The audit must classify each code found in data. Imaging subranges: 70010-76999 (diagnostic radiology + nuclear medicine), 77000-77299 (mostly planning/simulation codes), 77300-77399 (treatment planning), 77400-77499 (treatment delivery — these are the therapeutic ones), 77500-77999 (management + brachytherapy). Proton codes 77520-77525 fall within 77500-77599.

## New vs Modified Components

### New (3 scripts)

| Script | Purpose | Primary Input | Output |
|--------|---------|--------------|--------|
| `R/45_cancer_site_frequency.R` | Cancer site frequency from ICD codes | CancerSiteCategories.xlsx, TUMOR_REGISTRY, DIAGNOSIS | `output/cancer_site_frequency.xlsx` |
| `R/46_treatment_code_crossref.R` | Diff TREATMENT_CODES vs reference docs | VariableDetails.xlsx, TreatmentVariables docx, TREATMENT_CODES | `output/treatment_code_crossref.xlsx` |
| `R/47_radiation_cpt_audit.R` | Classify radiation CPT 70010-79999 range | PROCEDURES table, TREATMENT_CODES$radiation_cpt | `output/radiation_cpt_audit.xlsx` |

### Modified (1 script, 1 config)

| Component | Change | Risk |
|-----------|--------|------|
| `R/43_treatment_durations.R` | `extract_all_dates()` extended to also return `triggering_code` + `code_type` columns | LOW — R/44 is the only consumer; adding columns is additive |
| `R/44_treatment_episodes.R` | `calculate_episodes_detailed()` collects triggering codes per episode; per-type CSV output gains `triggering_codes` column | LOW — new column is additive; existing consumers of RDS/xlsx unaffected |
| `R/00_config.R` | Correct descriptions for Phase 39 radiation_cpt codes (currently "no description"); optionally add proton codes 77520-77525 if confirmed absent | VERY LOW — string edits only |

### Unchanged (all others)

R/38, R/42, R/01, R/02-R/36 — no modifications. The standalone script pattern means new scripts do not require changes to existing scripts that have no dependency on them.

## Build Order

The four features have one internal dependency (triggering codes requires modifying R/43 before R/44). The other three features are fully independent of each other and of the triggering codes work.

```
Phase A (independent — can start anytime):
  45_cancer_site_frequency.R   — no dependency on other new scripts
  46_treatment_code_crossref.R — no dependency on other new scripts
  47_radiation_cpt_audit.R     — no dependency on other new scripts

Phase B (sequential — R/43 must be modified first):
  Step 1: Modify R/43_treatment_durations.R (add triggering_code to extract_all_dates())
  Step 2: Modify R/44_treatment_episodes.R (add triggering_codes column using R/43 output)
```

**Recommended build order (minimizes risk):**

1. **R/47_radiation_cpt_audit.R** — Purely reads from PROCEDURES + config. No R script changes. Fastest to validate and provides immediate answer on proton code coverage question. Also informs any potential R/00_config.R corrections.

2. **R/46_treatment_code_crossref.R** — Reads reference files + config. No R script changes. Produces gap list that may motivate adding codes to TREATMENT_CODES. Run before triggering codes work so any config updates are in place.

3. **(Optional) R/00_config.R corrections** — Based on R/47 and R/46 findings: add proton codes 77520-77525 if missing; correct "Phase 39: no description" comments on radiation_cpt codes.

4. **R/43_treatment_durations.R modification** — Add triggering_code to extract_all_dates() return value. Verify R/43 still produces identical duration outputs (regression check: run R/43 before and after, compare RDS/xlsx output).

5. **R/44_treatment_episodes.R modification** — Add triggering_codes column. Verify per-type CSVs gain the column and episode logic is unchanged.

6. **R/45_cancer_site_frequency.R** — Independent of all other changes. Can run after R/47 and R/46 are done, or in parallel. Placed last because the ICD range expansion logic has the most implementation complexity (range parsing).

## Scaling Considerations

| Concern | Current Approach | At v1.6 |
|---------|-----------------|---------|
| Reference file parsing | readxl one-time load | Same — files are small (43 and 123 rows) |
| ICD range expansion | Not previously needed | Range expansion is in-memory R; 42 site rows → hundreds of codes, trivial |
| CPT range audit (70010-79999) | Not previously done | ~990 possible CPT codes; filter on PROCEDURES with materialize() pattern |
| Triggering codes | Not tracked | Stored as comma-separated string in CSV; no performance concern |

## Anti-Patterns to Avoid

### Anti-Pattern 1: Treating TreatmentVariables Docx as Authoritative Code List

**What people do:** Assume the docx CPT range "70010-79999" means all codes in that range should be in TREATMENT_CODES.

**Why it's wrong:** The docx defines the search range for radiation, not the inclusion list. Imaging codes (70010-76999, diagnostic radiology) are explicitly not radiation treatment. The audit (R/47) exists to classify what's in that range, not to wholesale-add all 990 codes.

**Do this instead:** R/47 classifies each code found in actual PROCEDURES data as imaging vs treatment. Only confirmed treatment delivery codes (77401-77470 series, proton codes 77520-77525, brachytherapy codes) belong in TREATMENT_CODES.

### Anti-Pattern 2: Modifying extract_all_dates() Return Schema Destructively

**What people do:** Change the column names or drop existing columns while adding `triggering_code`.

**Why it's wrong:** R/44 directly consumes R/43's `extract_all_dates()` return value. Any breaking column rename would silently fail at runtime on HiPerGator.

**Do this instead:** Add `triggering_code` and `code_type` as new columns. Never rename or remove `ID` or `treatment_date` which are the existing columns R/44 depends on.

### Anti-Pattern 3: Embedding ICD Range Expansion Logic Inline

**What people do:** Write a one-off paste/seq loop inside R/45 without a named function.

**Why it's wrong:** ICD range expansion (parsing "C810-C814" → vector of 4 codes) is non-trivial for alphanumeric codes (the suffix is numeric, the prefix is alpha+numeric). Inline code is untestable and will be repeated if cancer site analysis is ever extended.

**Do this instead:** Define `expand_icd_range(range_str)` as a named function at the top of R/45. Test it on the Hodgkin row before running against all 42 rows.

### Anti-Pattern 4: Forward-Fill Failure on VariableDetails.xlsx Treatment Sheet

**What people do:** Read the Treatment sheet and use the raw Modality column with NA gaps without forward-filling.

**Why it's wrong:** The Treatment sheet uses merged cells for Modality (e.g., "Stem cell transplant" is only in the first row of that group; subsequent rows have NA). Without `tidyr::fill(Modality, .direction = "down")`, code-level rows lose their modality assignment.

**Do this instead:** After `read_excel(..., sheet = "Treatment")`, immediately apply `fill(Modality, .direction = "down")` before any filtering or joining.

## Integration Points

### External References

| Reference File | Location | How Used |
|----------------|----------|----------|
| CancerSiteCategories.xlsx | Project root | R/45 reads "Groups" sheet; ICD10 ranges expanded to code vectors for DIAGNOSIS/TUMOR_REGISTRY queries |
| VariableDetails.xlsx | Project root | R/46 reads "Treatment" sheet (123 rows); Modality forward-filled; codes diffed vs TREATMENT_CODES |
| TreatmentVariables_2024.07.17.docx | Project root | R/46 uses text content to confirm CPT range definitions (70010-79999 for radiation, etc.); parse via `xml2` or zip extraction |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| R/00_config.R ↔ R/45, R/46, R/47 | `source()` + global TREATMENT_CODES | R/46 reads TREATMENT_CODES directly for diff |
| R/43 ↔ R/44 | `source("R/43_treatment_durations.R")` in R/44 | R/44 uses R/43's functions; adding a column to extract_all_dates() return is the only change |
| R/01_load_pcornet.R ↔ R/45, R/47 | `get_pcornet_table()` dispatcher | Standard pattern; R/45 queries TUMOR_REGISTRY_ALL + DIAGNOSIS; R/47 queries PROCEDURES |
| New scripts ↔ output/ | `file.path(CONFIG$output_dir, ...)` | Follows existing output path convention |

## Sources

All findings in this document are derived from direct code inspection. No external sources required — architecture is entirely captured in the existing R scripts.

- `R/00_config.R` (lines 412-760): TREATMENT_CODES structure, radiation_cpt codes, proton code presence check
- `R/38_treatment_inventory.R`: Standalone diagnostic script pattern, safe_table(), CPT_HCPCS_RANGES
- `R/42_treatment_codes_resolved.R`: write_resolved_xlsx() reusable function signature
- `R/43_treatment_durations.R`: extract_all_dates() return schema (ID, treatment_date)
- `R/44_treatment_episodes.R`: calculate_episodes_detailed() and per-type CSV outputs
- `CancerSiteCategories.xlsx` (Groups sheet, 43 rows): ICD10 range format confirmed
- `VariableDetails.xlsx` (Treatment sheet, 123 rows): Modality/Code/Description structure confirmed; note at row 63 refers to TreatmentVariables docx
- `TreatmentVariables_2024.07.17.docx` (text extraction): "From PROCEDURES: 70010-79999" for radiation confirmed

---
*Architecture research for: PCORnet CDM R Analysis Pipeline — v1.6 Treatment Code Validation & Cancer Site Analysis*
*Researched: 2026-04-21*
