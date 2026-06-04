# Phase 84: Test Fixture Design & Creation - Research

**Researched:** 2026-06-04
**Domain:** R test fixture design, synthetic clinical data generation, PCORnet CDM compliance
**Confidence:** HIGH

## Summary

Phase 84 creates hand-crafted test fixture CSVs covering 11 clinical edge cases in ~20 synthetic patients distributed across 15 PCORnet CDM table CSVs. The fixtures support local testing by providing realistic-but-synthetic data that exercises cohort filter predicates, payer harmonization logic, and treatment detection without HIPAA concerns.

The recommended approach uses an R generation script (`tests/generate_fixtures.R`) as the single source of truth, with tribble() for small inline datasets and write_csv() to produce version-controlled CSVs. The script iterates over PCORNET_TABLES (already defined in R/00_config.R), respects existing column type specifications from R/01_load_pcornet.R, and uses configuration constants (AMC_PAYER_LOOKUP, ICD_CODES, TREATMENT_CODES, DRUG_GROUPINGS) to ensure fixture codes match production logic.

**Primary recommendation:** Write an R script that generates all 15 fixture CSVs programmatically using tribble() definitions, then commit both the script and the generated CSVs to git. This approach ensures reproducibility (script is source of truth), debuggability (human-readable tribble syntax), and version control visibility (CSVs diffable, script changes drive CSV changes).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** One edge case per patient (~20 patients). Each patient targets 1-2 specific edge cases for clear traceability. FIXTURE_DESIGN.md reads like a test matrix linking patient IDs to the exact case they exercise.
- **D-02:** Patient IDs follow PT001-PT020 pattern (zero-padded sequential). Matches ROADMAP success criteria references (PT001, PT002, etc.).
- **D-03:** Encounter IDs follow ENC{patient}_{seq} pattern (e.g., ENC001_01, ENC001_02). Links encounters to patients visually for easy debugging.
- **D-04:** Diagnosis dates centered on 2012-2014 range, spanning the ICD-9-to-ICD-10 transition (Oct 2015). Allows testing both DX_TYPE="09" and DX_TYPE="10" patients realistically.
- **D-05:** Include 1-2 baseline "happy path" patients with no edge cases — straightforward HL diagnosis, private insurance, standard chemo. Establishes a reference for what normal pipeline output looks like.
- **D-06:** R generation script is the single source of truth. Lives at `tests/generate_fixtures.R` with tribble() definitions. CSVs are committed to git for convenience but are regenerable by running the script.
- **D-07:** To update fixtures: edit `tests/generate_fixtures.R`, re-run it, commit both the script and regenerated CSVs. Script changes drive CSV changes.
- **D-08:** All 15 PCORnet CDM tables get fixture CSVs. Low-traffic tables (CONDITION, LAB_RESULT_CM, PROVIDER) get header + 1-2 minimal rows so DuckDB ingest succeeds and pipeline scripts don't choke on empty tables.
- **D-09:** TUMOR_REGISTRY tables (140-314 columns each) include only pipeline-used columns (~15-20 per table). Missing columns default to NA during vroom read. Keeps fixtures small and readable.
- **D-10:** 11 edge cases covered:
  1. Dual-eligible — Medicare + Medicaid payer codes
  2. NLPHL — C81.0x or 201.4x diagnosis
  3. SCT — Stem cell transplant procedure codes (38240/38241 or Z94.84)
  4. Multiple cancers — HL + another cancer site on same patient
  5. Death dates — DEATH table records for timeline truncation
  6. Orphan dx codes — Z51.11/Z51.12 without paired procedure in same encounter
  7. Same-day multi-payer — 2+ encounters same ADMIT_DATE, different payers
  8. 1900 sentinel dates — SAS/Excel epoch artifacts to filter
  9. ICD-9/ICD-10 cross-system — Patient with both 201.x and C81.x diagnoses (Phase 87 confirmation logic)
  10. Missing payer — Patient with payer code "NI" or NA (exclude_missing_payer predicate)
  11. ABVD regimen detection — Patient with doxorubicin + vinblastine + dacarbazine + bleomycin RXNORM_CUIs (first-line therapy identification)

### Claude's Discretion
- Exact RXNORM_CUI values for ABVD drugs (research authoritative codes)
- Which specific columns to include for TUMOR_REGISTRY1/2/3 (scan pipeline code for used columns)
- Enrollment date ranges per patient (ensure coverage of diagnosis dates)
- Whether DISPENSING vs PRESCRIBING vs MED_ADMIN is used for each drug-related edge case
- Site/SOURCE values for test patients (use realistic OneFlorida+ partner site codes: AMS, UMI, FLM, VRT, UFH)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FIX-01 | Hand-crafted fixture CSVs (~20 patients) covering all 13 PCORnet CDM tables in tests/fixtures/ | Section: Standard Stack (tribble + write_csv), Architecture Patterns (generation script structure) |
| FIX-02 | Fixtures include all clinical edge cases: dual-eligible, NLPHL, SCT, multiple cancers, death dates, orphan dx, same-day multi-payer, 1900 sentinel dates | Section: Code Examples (edge case patient definitions), Don't Hand-Roll (leverage existing code constants) |
| FIX-03 | Fixture design documented in FIXTURE_DESIGN.md with patient-to-edge-case mapping | Section: Architecture Patterns (design doc template), Code Examples (patient matrix table) |
| FIX-04 | Fixture generation R script creates CSVs reproducibly from documented design | Section: Standard Stack (tribble approach), Code Examples (script skeleton) |
| FIX-05 | Fixture CSVs git-tracked for version control and diff visibility | Section: Architecture Patterns (commit strategy), Common Pitfalls (CSV diffability) |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| tibble | 3.2.1+ | In-memory data construction | tribble() provides formula-based row-by-row syntax ideal for hand-crafted test data; included in tidyverse |
| readr | 2.2.0+ | CSV writing | write_csv() produces clean, portable CSVs with consistent quoting; version-control friendly; included in tidyverse |
| dplyr | 1.2.0+ | Data manipulation | mutate(), case_when() for computed columns; filter() for subsetting; included in tidyverse |
| glue | 1.8.0 | String interpolation | Dynamic patient/encounter ID generation with readable syntax |
| here | 1.0.2 | Path management | Project-relative paths work in interactive and batch modes |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| purrr | 1.0.2+ | Iteration | map2() to generate multiple tables from templates |
| lubridate | 1.9.3+ | Date construction | ymd() for clean date literals in tribble() |
| stringr | 1.5.1+ | String operations | str_pad() for zero-padded IDs if needed |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| tribble() | data.frame() with rbind() | tribble() is more readable for row-oriented construction; data.frame() syntax is column-oriented and verbose |
| R script generation | CSV templates edited manually | Manual editing is error-prone and not reproducible; script ensures consistency |
| Minimal columns | Full 314-column TUMOR_REGISTRY schema | Minimal columns keep fixtures readable and git-diffable; vroom .default = col_character() handles missing columns gracefully |
| Committed CSVs | .gitignore CSVs, generate on demand | Committed CSVs provide fast local setup; users don't need to run generator first; trade-off is repo size (~1MB acceptable) |

**Installation:**
All packages already listed in project STACK.md and installed via renv. No new dependencies needed.

**Version verification:** Already satisfied by existing renv.lock from Phase 83.

## Architecture Patterns

### Recommended Project Structure
```
tests/
├── fixtures/                      # CSV output directory (already exists from Phase 83)
│   ├── ENROLLMENT_Mailhot_V1.csv
│   ├── DIAGNOSIS_Mailhot_V1.csv
│   ├── CONDITION_Mailhot_V1.csv
│   ├── PROCEDURES_Mailhot_V1.csv
│   ├── PRESCRIBING_Mailhot_V1.csv
│   ├── ENCOUNTER_Mailhot_V1.csv
│   ├── DEMOGRAPHIC_Mailhot_V1.csv
│   ├── TUMOR_REGISTRY1_Mailhot_V1.csv
│   ├── TUMOR_REGISTRY2_Mailhot_V1.csv
│   ├── TUMOR_REGISTRY3_Mailhot_V1.csv
│   ├── DISPENSING_Mailhot_V1.csv
│   ├── MED_ADMIN_Mailhot_V1.csv
│   ├── LAB_RESULT_CM_Mailhot_V1.csv  # Note: filename override in 00_config.R
│   ├── PROVIDER_Mailhot_V1.csv
│   ├── DEATH_Mailhot_V1.csv
│   └── FIXTURE_DESIGN.md          # Patient-to-edge-case mapping documentation
├── generate_fixtures.R            # Single source of truth for fixture data
└── .gitkeep                       # Already present
```

### Pattern 1: tribble() for Inline Patient Definitions
**What:** tibble::tribble() constructs data frames row-by-row with column headers prefixed by ~. Ideal for hand-crafted test data where you want to see "patients as rows."

**When to use:** Any table with < 50 rows where readability matters more than performance.

**Example:**
```r
# Source: testthat best practices
library(tibble)
library(lubridate)

enrollment_data <- tribble(
  ~ID,      ~ENR_START_DATE, ~ENR_END_DATE, ~CHART, ~ENR_BASIS, ~SOURCE,
  # Patient 1: Baseline happy path (private insurance, standard HL)
  "PT001",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UFH",

  # Patient 2: Dual-eligible (Medicare + Medicaid)
  "PT002",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "AMS",

  # Patient 3: NLPHL diagnosis
  "PT003",  "2011-06-01",    "2015-12-31",  "Y",    "I",        "FLM"
) %>%
  mutate(
    ENR_START_DATE = ymd(ENR_START_DATE),
    ENR_END_DATE = ymd(ENR_END_DATE)
  )
```

### Pattern 2: Iteration Over PCORNET_TABLES with Named List Output
**What:** Generate all 15 fixture CSVs in a single script using a named list and iteration.

**When to use:** When you need to produce multiple related files with consistent structure.

**Example:**
```r
source("R/00_config.R")  # Loads PCORNET_TABLES, PCORNET_PATHS

library(dplyr)
library(readr)
library(purrr)
library(glue)

# Define all fixture data as named list
fixture_tables <- list(
  ENROLLMENT = generate_enrollment(),
  DIAGNOSIS = generate_diagnosis(),
  ENCOUNTER = generate_encounter(),
  DEMOGRAPHIC = generate_demographic(),
  # ... etc for all 15 tables
)

# Write all CSVs using PCORNET_PATHS for consistent naming
walk2(names(fixture_tables), fixture_tables, function(table_name, table_data) {
  output_path <- PCORNET_PATHS[[table_name]]
  write_csv(table_data, output_path)
  message(glue("Wrote {nrow(table_data)} rows to {output_path}"))
})
```

### Pattern 3: Minimal Columns for Low-Traffic Tables
**What:** For tables like CONDITION, LAB_RESULT_CM, PROVIDER that are rarely used by the pipeline, include only ID, SOURCE, and one domain-specific column.

**When to use:** When the pipeline loads the table but doesn't actively filter/join on it (avoids "table not found" errors without bloating fixtures).

**Example:**
```r
# CONDITION: Pipeline doesn't use this table, but DuckDB ingest expects it
condition_data <- tribble(
  ~CONDITIONID, ~ID,     ~CONDITION, ~CONDITION_TYPE, ~SOURCE,
  "COND001",    "PT001", "E11.9",    "10",            "UFH"
)

# PROVIDER: Pipeline checks existence but doesn't join
provider_data <- tribble(
  ~PROVIDERID, ~PROVIDER_SPECIALTY_PRIMARY, ~SOURCE,
  "PROV001",   "207RH0003X",                 "UFH"  # Hematology/Oncology NPI code
)
```

### Pattern 4: Edge Case Patient Design with Inline Comments
**What:** Use tribble() comments to document which edge case each patient targets.

**When to use:** Always — makes the script self-documenting and ensures FIXTURE_DESIGN.md stays in sync.

**Example:**
```r
diagnosis_data <- tribble(
  ~DIAGNOSISID, ~ID,     ~ENCOUNTERID, ~DX,      ~DX_TYPE, ~DX_DATE,     ~SOURCE,
  # PT001: Baseline happy path — standard ICD-10 HL
  "DX001",      "PT001", "ENC001_01",  "C81.10", "10",     "2013-03-15", "UFH",

  # PT002: Dual-eligible (diagnosis in DIAGNOSIS, payer in ENCOUNTER)
  "DX002",      "PT002", "ENC002_01",  "C81.20", "10",     "2013-06-20", "AMS",

  # PT003: NLPHL — uses C81.0x subtype
  "DX003",      "PT003", "ENC003_01",  "C81.00", "10",     "2013-09-10", "FLM",

  # PT009: ICD-9/ICD-10 cross-system — has BOTH 201.x and C81.x diagnoses
  "DX009A",     "PT009", "ENC009_01",  "201.90", "09",     "2012-11-05", "VRT",
  "DX009B",     "PT009", "ENC009_02",  "C81.90", "10",     "2012-11-15", "VRT"
)
```

### Anti-Patterns to Avoid
- **Hardcoding patient counts:** Don't hardcode n=20 in multiple places; use length(unique(enrollment$ID)) for dynamic counts.
- **Mixing tribble() and data.frame():** Stick to tribble() for consistency across all tables; mixing syntaxes reduces readability.
- **CSV editing after generation:** Never manually edit generated CSVs; always edit the script and regenerate (D-07).
- **Omitting SOURCE column:** Every PCORnet table has a SOURCE column for partner site; fixtures must include it or vroom will fail.
- **Ignoring column type specs:** ENROLLMENT_SPEC defines ENR_START_DATE as col_character(); tribble() should construct it as character (or Date then convert) to match production data shape.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Patient ID generation | Custom counter logic | glue("PT{str_pad(1:20, 3, pad='0')}") or seq_along with sprintf | One-liner handles zero-padding and uniqueness |
| Payer code validity | Manual lookup of valid codes | Copy from AMC_PAYER_LOOKUP keys in R/00_config.R | Production codes are already defined; ensures fixtures match production logic |
| ICD code validity | Manual code lookup | Copy from ICD_CODES$hl_icd10, ICD_CODES$hl_icd9 in R/00_config.R | HL codes are already defined and vetted (150+ codes); reuse prevents typos |
| RXNORM_CUI codes | Web search for drug codes | Copy from TREATMENT_CODES$chemo_rxnorm in R/00_config.R | ABVD codes already documented (3639, 11213, 67228, 3946); reuse ensures fixtures match treatment detection logic |
| Table column lists | Manually typing 314 TUMOR_REGISTRY columns | Use .default = col_character() strategy from R/01_load_pcornet.R | vroom handles missing columns gracefully; fixtures only need pipeline-used columns |
| CSV filename patterns | Hardcoded paths | Use PCORNET_PATHS from R/00_config.R | Filename override for LAB_RESULT_CM already handled; consistency with production |
| Date parsing | strptime() or as.Date() with format strings | lubridate::ymd() for unambiguous YYYY-MM-DD literals | ymd() is self-documenting and handles ISO 8601 without format strings |
| Encounter ID uniqueness | Manual tracking of used IDs | Pattern ENC{patient}_{seq} with str_pad | Visual linkage to patient + auto-uniqueness |

**Key insight:** R/00_config.R already contains all the production codes, lookup tables, and constants needed for fixtures. The generation script should source("R/00_config.R") and reuse these definitions rather than duplicating them.

## Common Pitfalls

### Pitfall 1: Forgetting Filename Override for LAB_RESULT_CM
**What goes wrong:** Script generates `LAB_RESULT_CM_Mailhot_V1.csv` but R/00_config.R expects `LAB_RESULT_Mailhot_V1.csv` (no "_CM" suffix).

**Why it happens:** PCORNET_PATHS has a special override: `PCORNET_PATHS[["LAB_RESULT_CM"]] <- file.path(CONFIG$data_dir, "LAB_RESULT_Mailhot_V1.csv")` (line 251 in R/00_config.R).

**How to avoid:** Use PCORNET_PATHS[[table_name]] for all output paths, not paste0(table_name, "_Mailhot_V1.csv").

**Warning signs:** DuckDB ingest fails with "file not found: LAB_RESULT_Mailhot_V1.csv" even though LAB_RESULT_CM_Mailhot_V1.csv exists.

### Pitfall 2: Date Columns as Date Type Instead of Character
**What goes wrong:** tribble() creates ENR_START_DATE as Date, but vroom reads it as character per ENROLLMENT_SPEC. Type mismatch causes downstream parse_pcornet_date() to fail.

**Why it happens:** Natural instinct is to use ymd() in tribble(), which produces Date objects. But production CSVs have dates as character strings, and R/01_load_pcornet.R specifies col_character() for all date columns to enable multi-format parsing.

**How to avoid:** Either (1) keep dates as strings in tribble() and skip ymd(), or (2) use ymd() then mutate all date columns to character before write_csv(): `mutate(across(ends_with("_DATE"), as.character))`.

**Warning signs:** Local testing works (Date columns parse fine) but production fails, or parse_pcornet_date() logs warnings about unexpected input types.

### Pitfall 3: Missing Required Columns per Table Spec
**What goes wrong:** Generated CSV omits a required column (e.g., DIAGNOSIS without DX_TYPE), causing vroom to error or pipeline filters to produce NA results.

**Why it happens:** Easy to forget which columns are required vs optional when working from memory.

**How to avoid:** Cross-reference each generated tribble() against the {TABLE}_SPEC in R/01_load_pcornet.R (lines 55-340). Required columns are those without .default fallback and not marked as "optional" in comments.

**Warning signs:** vroom error "column X not found in file" or nrow(filter(dx, DX_TYPE == "10")) returns 0 when you expect 15.

### Pitfall 4: Forgetting SOURCE Column
**What goes wrong:** Generated table omits SOURCE column (partner site identifier), causing joins or DuckDB ingest to fail.

**Why it happens:** SOURCE is present in every PCORnet table spec but easy to overlook when focusing on clinical columns.

**How to avoid:** Add SOURCE as last column in every tribble() definition. Use realistic OneFlorida+ partner codes: UFH, AMS, FLM, VRT, UMI.

**Warning signs:** vroom error about missing column SOURCE, or DuckDB schema mismatch.

### Pitfall 5: Dual-Eligible Patient Design Error
**What goes wrong:** Dual-eligible patient (PT002) has Medicare primary + Medicaid secondary in ENCOUNTER, but R/02_harmonize_payer.R doesn't detect dual-eligible flag.

**Why it happens:** Dual-eligible detection requires payer codes "14", "141", or "142" (AMC_PAYER_LOOKUP$dual_eligible_codes), not just "Medicare + Medicaid combination."

**How to avoid:** For dual-eligible patient, use PAYER_TYPE_PRIMARY = "14" (Dual Eligibility Medicare/Medicaid Organization) in at least one encounter. Code "14" maps to "Medicaid" category per AMC_PAYER_LOOKUP and triggers dual-eligible flag.

**Warning signs:** Dual-eligible patient shows DUAL_ELIGIBLE = FALSE in payer_summary output.

### Pitfall 6: ICD-9/ICD-10 Cross-System Patient Without 7-Day Gap
**What goes wrong:** Patient PT009 has both ICD-9 201.x and ICD-10 C81.x diagnoses on same date, but Phase 87 logic requires 7-day unique day gap for cancer confirmation.

**Why it happens:** Misunderstanding the "cross-system" requirement — it's not just "both code systems present" but "both contribute to 7-day gap rule."

**How to avoid:** Ensure PT009 has ICD-9 diagnosis on date X and ICD-10 diagnosis on date X+7 or later. Use DX_DATE values at least 7 days apart.

**Warning signs:** Patient excluded from cohort despite having HL diagnoses in both ICD-9 and ICD-10.

### Pitfall 7: ABVD Regimen Patient Without All Four Drugs
**What goes wrong:** Patient PT011 (ABVD regimen detection) only has doxorubicin and bleomycin in PRESCRIBING, missing vinblastine and dacarbazine. Regimen detection fails.

**Why it happens:** ABVD is a 4-drug combination; partial regimens don't count as "ABVD detection" in treatment logic.

**How to avoid:** Ensure ABVD patient has all four RXNORM_CUIs in PRESCRIBING or DISPENSING within a 28-day window: 3639 (doxorubicin), 11213 (bleomycin), 67228 (vinblastine), 3946 (dacarbazine).

**Warning signs:** ABVD patient flagged as has_chemo = TRUE but not identified as "ABVD regimen" in treatment summaries.

### Pitfall 8: Git Diff Noise from Unstable Column Ordering
**What goes wrong:** Regenerating fixtures reorders columns (tribble column order changes), causing large git diffs even when data is unchanged.

**Why it happens:** tribble() column order is defined by formula order (~ID, ~DX, ~DX_TYPE), but if you reorder these during edits, write_csv() produces CSVs with different column sequences.

**How to avoid:** Lock column order by listing columns in tribble() in the same order as {TABLE}_SPEC in R/01_load_pcornet.R. Use select() to enforce order if needed.

**Warning signs:** git diff shows every column shifted even though values are identical.

## Code Examples

Verified patterns from project codebase and R best practices:

### Generation Script Skeleton
```r
# tests/generate_fixtures.R
# ==============================================================================
# Generate PCORnet CDM test fixture CSVs for local testing
# ==============================================================================
#
# Purpose:
#   Single source of truth for fixture data. Defines ~20 synthetic patients
#   covering 11 clinical edge cases, then writes 15 PCORnet CDM table CSVs to
#   tests/fixtures/ directory.
#
# Usage:
#   source("tests/generate_fixtures.R")
#   # Writes 15 CSVs to tests/fixtures/
#
# To update fixtures:
#   1. Edit this script
#   2. Re-run: source("tests/generate_fixtures.R")
#   3. Git commit both this script and regenerated CSVs
#
# Edge cases covered (D-10):
#   1. Dual-eligible (PT002)
#   2. NLPHL (PT003)
#   3. SCT (PT004)
#   4. Multiple cancers (PT005)
#   5. Death dates (PT006)
#   6. Orphan dx codes (PT007)
#   7. Same-day multi-payer (PT008)
#   8. 1900 sentinel dates (PT009)
#   9. ICD-9/ICD-10 cross-system (PT010)
#   10. Missing payer (PT011)
#   11. ABVD regimen (PT012)
#   Baseline happy path (PT001, PT020)
#
# ==============================================================================

source("R/00_config.R")  # Loads PCORNET_TABLES, PCORNET_PATHS, ICD_CODES, AMC_PAYER_LOOKUP, TREATMENT_CODES

library(tibble)
library(dplyr)
library(readr)
library(lubridate)
library(glue)
library(purrr)

message("\n", strrep("=", 60))
message("PCORnet Test Fixture Generator")
message(strrep("=", 60))

# ==============================================================================
# SECTION 1: PATIENT ROSTER ----
# ==============================================================================
# 20 patients: 2 baseline, 11 edge cases (some patients = 2 cases), rest = variations

PATIENT_IDS <- sprintf("PT%03d", 1:20)

# ==============================================================================
# SECTION 2: TABLE GENERATORS ----
# ==============================================================================

generate_enrollment <- function() {
  tribble(
    ~ID,      ~ENR_START_DATE, ~ENR_END_DATE, ~CHART, ~ENR_BASIS, ~SOURCE,
    # PT001: Baseline happy path
    "PT001",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UFH",
    # PT002: Dual-eligible (will have payer code 14 in ENCOUNTER)
    "PT002",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "AMS",
    # PT003: NLPHL
    "PT003",  "2011-06-01",    "2015-12-31",  "Y",    "I",        "FLM",
    # PT004: SCT
    "PT004",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "VRT",
    # PT005: Multiple cancers
    "PT005",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UMI",
    # PT006: Death date
    "PT006",  "2010-01-01",    "2014-06-30",  "Y",    "I",        "UFH",
    # PT007: Orphan dx codes
    "PT007",  "2011-01-01",    "2015-12-31",  "Y",    "I",        "AMS",
    # PT008: Same-day multi-payer
    "PT008",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "FLM",
    # PT009: 1900 sentinel dates (bad enrollment dates to filter)
    "PT009",  "1900-01-01",    "2015-12-31",  "Y",    "I",        "VRT",
    # PT010: ICD-9/ICD-10 cross-system
    "PT010",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UMI",
    # PT011: Missing payer (will have NI in ENCOUNTER)
    "PT011",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UFH",
    # PT012: ABVD regimen (will have 4 drugs in PRESCRIBING)
    "PT012",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "AMS",
    # PT013-PT019: Additional variation patients
    "PT013",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "FLM",
    "PT014",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "VRT",
    "PT015",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UMI",
    "PT016",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UFH",
    "PT017",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "AMS",
    "PT018",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "FLM",
    "PT019",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "VRT",
    # PT020: Baseline happy path #2
    "PT020",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UMI"
  )
}

generate_diagnosis <- function() {
  tribble(
    ~DIAGNOSISID, ~ID,     ~ENCOUNTERID, ~ENC_TYPE, ~ADMIT_DATE,  ~PROVIDERID, ~DX,      ~DX_TYPE, ~DX_DATE,     ~DX_SOURCE, ~DX_ORIGIN, ~PDX, ~DX_POA, ~SOURCE,
    # PT001: Baseline — standard ICD-10 HL
    "DX001",      "PT001", "ENC001_01",  "IP",      "2013-03-15", "PROV001",   "C81.10", "10",     "2013-03-15", "AD",       "OD",       "P",  "Y",     "UFH",
    # PT002: Dual-eligible
    "DX002",      "PT002", "ENC002_01",  "IP",      "2013-06-20", "PROV001",   "C81.20", "10",     "2013-06-20", "AD",       "OD",       "P",  "Y",     "AMS",
    # PT003: NLPHL — C81.0x
    "DX003",      "PT003", "ENC003_01",  "IP",      "2013-09-10", "PROV001",   "C81.00", "10",     "2013-09-10", "AD",       "OD",       "P",  "Y",     "FLM",
    # PT004: SCT (diagnosis, procedure in PROCEDURES)
    "DX004",      "PT004", "ENC004_01",  "IP",      "2012-05-12", "PROV001",   "C81.30", "10",     "2012-05-12", "AD",       "OD",       "P",  "Y",     "VRT",
    # PT005: Multiple cancers — HL + breast cancer
    "DX005A",     "PT005", "ENC005_01",  "IP",      "2013-01-20", "PROV001",   "C81.40", "10",     "2013-01-20", "AD",       "OD",       "P",  "Y",     "UMI",
    "DX005B",     "PT005", "ENC005_02",  "AV",      "2013-02-10", "PROV001",   "C50.911","10",     "2013-02-10", "AD",       "OD",       "S",  NA,      "UMI",
    # PT006: Death date (diagnosis, death in DEATH)
    "DX006",      "PT006", "ENC006_01",  "IP",      "2013-11-05", "PROV001",   "C81.70", "10",     "2013-11-05", "AD",       "OD",       "P",  "Y",     "UFH",
    # PT007: Orphan dx codes — Z51.11 without paired chemo procedure
    "DX007A",     "PT007", "ENC007_01",  "AV",      "2013-04-15", "PROV001",   "C81.90", "10",     "2013-04-15", "AD",       "OD",       "P",  "Y",     "AMS",
    "DX007B",     "PT007", "ENC007_02",  "AV",      "2013-05-20", "PROV001",   "Z51.11", "10",     "2013-05-20", "AD",       "OD",       "S",  NA,      "AMS",
    # PT008: Same-day multi-payer (two encounters same date, different payers in ENCOUNTER)
    "DX008",      "PT008", "ENC008_01",  "AV",      "2013-07-10", "PROV001",   "C81.90", "10",     "2013-07-10", "AD",       "OD",       "P",  "Y",     "FLM",
    # PT009: 1900 sentinel dates (enrollment table has bad date, DX is normal)
    "DX009",      "PT009", "ENC009_01",  "IP",      "2012-12-01", "PROV001",   "C81.90", "10",     "2012-12-01", "AD",       "OD",       "P",  "Y",     "VRT",
    # PT010: ICD-9/ICD-10 cross-system — diagnoses 7+ days apart
    "DX010A",     "PT010", "ENC010_01",  "IP",      "2012-11-05", "PROV001",   "201.90", "09",     "2012-11-05", "AD",       "OD",       "P",  "Y",     "UMI",
    "DX010B",     "PT010", "ENC010_02",  "AV",      "2012-11-15", "PROV001",   "C81.90", "10",     "2012-11-15", "AD",       "OD",       "P",  "Y",     "UMI",
    # PT011: Missing payer (diagnosis, payer NI in ENCOUNTER)
    "DX011",      "PT011", "ENC011_01",  "IP",      "2013-08-22", "PROV001",   "C81.90", "10",     "2013-08-22", "AD",       "OD",       "P",  "Y",     "UFH",
    # PT012: ABVD regimen (diagnosis, drugs in PRESCRIBING)
    "DX012",      "PT012", "ENC012_01",  "IP",      "2013-02-14", "PROV001",   "C81.90", "10",     "2013-02-14", "AD",       "OD",       "P",  "Y",     "AMS",
    # PT020: Baseline #2
    "DX020",      "PT020", "ENC020_01",  "IP",      "2013-10-05", "PROV001",   "C81.90", "10",     "2013-10-05", "AD",       "OD",       "P",  "Y",     "UMI"
  )
}

generate_encounter <- function() {
  tribble(
    ~ENCOUNTERID, ~ID,     ~ADMIT_DATE,  ~ADMIT_TIME, ~DISCHARGE_DATE, ~DISCHARGE_TIME, ~PROVIDERID, ~FACILITY_LOCATION, ~ENC_TYPE, ~FACILITYID, ~DISCHARGE_DISPOSITION, ~DISCHARGE_STATUS, ~DRG, ~DRG_TYPE, ~ADMITTING_SOURCE, ~PAYER_TYPE_PRIMARY, ~PAYER_TYPE_SECONDARY, ~FACILITY_TYPE, ~SOURCE,
    # PT001: Baseline — private insurance
    "ENC001_01",  "PT001", "2013-03-15", "08:00",     "2013-03-20",    "14:00",         "PROV001",   "FL",               "IP",      "FAC001",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "UFH",
    # PT002: Dual-eligible — payer code 14
    "ENC002_01",  "PT002", "2013-06-20", "09:30",     "2013-06-25",    "11:00",         "PROV001",   "FL",               "IP",      "FAC002",    "A",                    "01",               "840","MS",      "1",               "14",                NA,                    "HOSPITAL",     "AMS",
    # PT003: NLPHL
    "ENC003_01",  "PT003", "2013-09-10", "10:00",     "2013-09-15",    "12:00",         "PROV001",   "FL",               "IP",      "FAC003",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "FLM",
    # PT004: SCT
    "ENC004_01",  "PT004", "2012-05-12", "07:00",     "2012-05-22",    "16:00",         "PROV001",   "FL",               "IP",      "FAC004",    "A",                    "01",               "840","MS",      "1",               "111",               NA,                    "HOSPITAL",     "VRT",
    # PT005: Multiple cancers — two encounters
    "ENC005_01",  "PT005", "2013-01-20", "08:00",     "2013-01-25",    "14:00",         "PROV001",   "FL",               "IP",      "FAC005",    "A",                    "01",               "840","MS",      "1",               "211",               NA,                    "HOSPITAL",     "UMI",
    "ENC005_02",  "PT005", "2013-02-10", "09:00",     NA,              NA,              "PROV001",   "FL",               "AV",      "FAC005",    NA,                     NA,                 NA,   NA,        NA,                "211",               NA,                    "CLINIC",       "UMI",
    # PT006: Death date
    "ENC006_01",  "PT006", "2013-11-05", "08:00",     "2013-11-10",    "14:00",         "PROV001",   "FL",               "IP",      "FAC001",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "UFH",
    # PT007: Orphan dx codes — two encounters, Z51.11 in second
    "ENC007_01",  "PT007", "2013-04-15", "08:00",     NA,              NA,              "PROV001",   "FL",               "AV",      "FAC002",    NA,                     NA,                 NA,   NA,        NA,                "512",               NA,                    "CLINIC",       "AMS",
    "ENC007_02",  "PT007", "2013-05-20", "09:00",     NA,              NA,              "PROV001",   "FL",               "AV",      "FAC002",    NA,                     NA,                 NA,   NA,        NA,                "512",               NA,                    "CLINIC",       "AMS",
    # PT008: Same-day multi-payer — two encounters same ADMIT_DATE, different payers
    "ENC008_01",  "PT008", "2013-07-10", "08:00",     NA,              NA,              "PROV001",   "FL",               "AV",      "FAC003",    NA,                     NA,                 NA,   NA,        NA,                "1",                 NA,                    "CLINIC",       "FLM",
    "ENC008_02",  "PT008", "2013-07-10", "14:00",     NA,              NA,              "PROV002",   "FL",               "AV",      "FAC003",    NA,                     NA,                 NA,   NA,        NA,                "512",               NA,                    "CLINIC",       "FLM",
    # PT009: 1900 sentinel dates
    "ENC009_01",  "PT009", "2012-12-01", "08:00",     "2012-12-06",    "14:00",         "PROV001",   "FL",               "IP",      "FAC004",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "VRT",
    # PT010: ICD-9/ICD-10 cross-system — two encounters 10 days apart
    "ENC010_01",  "PT010", "2012-11-05", "08:00",     "2012-11-10",    "14:00",         "PROV001",   "FL",               "IP",      "FAC005",    "A",                    "01",               "840","MS",      "1",               "111",               NA,                    "HOSPITAL",     "UMI",
    "ENC010_02",  "PT010", "2012-11-15", "09:00",     NA,              NA,              "PROV001",   "FL",               "AV",      "FAC005",    NA,                     NA,                 NA,   NA,        NA,                "111",               NA,                    "CLINIC",       "UMI",
    # PT011: Missing payer — PAYER_TYPE_PRIMARY = "NI"
    "ENC011_01",  "PT011", "2013-08-22", "08:00",     "2013-08-27",    "14:00",         "PROV001",   "FL",               "IP",      "FAC001",    "A",                    "01",               "840","MS",      "1",               "NI",                NA,                    "HOSPITAL",     "UFH",
    # PT012: ABVD regimen
    "ENC012_01",  "PT012", "2013-02-14", "08:00",     "2013-02-19",    "14:00",         "PROV001",   "FL",               "IP",      "FAC002",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "AMS",
    # PT020: Baseline #2
    "ENC020_01",  "PT020", "2013-10-05", "08:00",     "2013-10-10",    "14:00",         "PROV001",   "FL",               "IP",      "FAC005",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "UMI"
  )
}

generate_demographic <- function() {
  tribble(
    ~ID,      ~BIRTH_DATE,  ~BIRTH_TIME, ~SEX, ~SEXUAL_ORIENTATION, ~GENDER_IDENTITY, ~HISPANIC, ~RACE, ~BIOBANK_FLAG, ~PAT_PREF_LANGUAGE_SPOKEN, ~ZIP_CODE, ~SOURCE,
    "PT001",  "1975-06-15", "12:00",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "32611",   "UFH",
    "PT002",  "1940-03-20", "08:00",     "F",  NA,                  NA,               "N",       "03",  NA,            "eng",                     "33101",   "AMS",
    "PT003",  "1982-11-10", "14:30",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "32301",   "FLM",
    "PT004",  "1968-07-22", "10:00",     "F",  NA,                  NA,               "Y",       "04",  NA,            "spa",                     "32801",   "VRT",
    "PT005",  "1955-01-15", "11:00",     "F",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "33140",   "UMI",
    "PT006",  "1950-08-30", "09:00",     "M",  NA,                  NA,               "N",       "03",  NA,            "eng",                     "32611",   "UFH",
    "PT007",  "1978-04-12", "13:00",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "33101",   "AMS",
    "PT008",  "1985-09-05", "15:00",     "F",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "32301",   "FLM",
    "PT009",  "1972-12-20", "08:30",     "M",  NA,                  NA,               "N",       "03",  NA,            "eng",                     "32801",   "VRT",
    "PT010",  "1960-05-18", "10:30",     "F",  NA,                  NA,               "Y",       "04",  NA,            "spa",                     "33140",   "UMI",
    "PT011",  "1980-02-28", "12:30",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "32611",   "UFH",
    "PT012",  "1970-11-11", "14:00",     "F",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "33101",   "AMS",
    "PT013",  "1988-03-03", "11:30",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "32301",   "FLM",
    "PT014",  "1965-07-07", "09:30",     "F",  NA,                  NA,               "N",       "03",  NA,            "eng",                     "32801",   "VRT",
    "PT015",  "1992-10-10", "13:30",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "33140",   "UMI",
    "PT016",  "1958-12-25", "10:00",     "F",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "32611",   "UFH",
    "PT017",  "1974-06-06", "14:30",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "33101",   "AMS",
    "PT018",  "1983-08-08", "12:00",     "F",  NA,                  NA,               "Y",       "04",  NA,            "spa",                     "32301",   "FLM",
    "PT019",  "1966-02-14", "09:00",     "M",  NA,                  NA,               "N",       "03",  NA,            "eng",                     "32801",   "VRT",
    "PT020",  "1979-09-09", "11:00",     "F",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "33140",   "UMI"
  )
}

# ... (similar generate_* functions for remaining 11 tables)

# ==============================================================================
# SECTION 3: WRITE CSVS ----
# ==============================================================================

fixture_tables <- list(
  ENROLLMENT = generate_enrollment(),
  DIAGNOSIS = generate_diagnosis(),
  ENCOUNTER = generate_encounter(),
  DEMOGRAPHIC = generate_demographic()
  # ... add remaining tables
)

# Write all CSVs using PCORNET_PATHS for consistent naming
walk2(names(fixture_tables), fixture_tables, function(table_name, table_data) {
  output_path <- PCORNET_PATHS[[table_name]]
  write_csv(table_data, output_path, na = "")
  message(glue("✓ Wrote {nrow(table_data)} rows to {basename(output_path)}"))
})

message("\n", strrep("=", 60))
message("Fixture generation complete!")
message("Next: commit tests/generate_fixtures.R and tests/fixtures/*.csv")
message(strrep("=", 60))
```

### ABVD Regimen Patient (PT012)
```r
# Source: R/00_config.R lines 2389-2392
# ABVD RXNORM_CUI codes from TREATMENT_CODES$chemo_rxnorm

generate_prescribing <- function() {
  tribble(
    ~PRESCRIBINGID, ~ID,     ~ENCOUNTERID, ~RX_PROVIDERID, ~RX_ORDER_DATE, ~RX_ORDER_TIME, ~RX_START_DATE, ~RX_END_DATE, ~RX_DOSE_ORDERED, ~RX_DOSE_ORDERED_UNIT, ~RX_QUANTITY, ~RX_DOSE_FORM, ~RX_REFILLS, ~RX_DAYS_SUPPLY, ~RX_FREQUENCY, ~RX_PRN_FLAG, ~RX_ROUTE, ~RX_BASIS, ~RXNORM_CUI, ~RX_SOURCE, ~RX_DISPENSE_AS_WRITTEN, ~RAW_RX_MED_NAME,           ~RAW_RXNORM_CUI, ~SOURCE,
    # PT012: ABVD regimen — all 4 drugs within 28-day window
    "RX012_01",     "PT012", "ENC012_01",  "PROV001",      "2013-02-15",   "08:00",        "2013-02-15",   "2013-02-15", 50,               "mg",                  NA,           "INJ",         0,           1,               "Q1D",         "N",         "IV",      "P",       "3639",      "OD",       NA,                         "Doxorubicin 50mg IV",      "3639",          "AMS",
    "RX012_02",     "PT012", "ENC012_01",  "PROV001",      "2013-02-15",   "08:15",        "2013-02-15",   "2013-02-15", 10,               "units",               NA,           "INJ",         0,           1,               "Q1D",         "N",         "IV",      "P",       "11213",     "OD",       NA,                         "Bleomycin 10 units IV",    "11213",         "AMS",
    "RX012_03",     "PT012", "ENC012_01",  "PROV001",      "2013-02-15",   "08:30",        "2013-02-15",   "2013-02-15", 6,                "mg",                  NA,           "INJ",         0,           1,               "Q1D",         "N",         "IV",      "P",       "67228",     "OD",       NA,                         "Vinblastine 6mg IV",       "67228",         "AMS",
    "RX012_04",     "PT012", "ENC012_01",  "PROV001",      "2013-02-15",   "08:45",        "2013-02-15",   "2013-02-15", 375,              "mg",                  NA,           "INJ",         0,           1,               "Q1D",         "N",         "IV",      "P",       "3946",      "OD",       NA,                         "Dacarbazine 375mg IV",     "3946",          "AMS"
  )
}
```

### SCT Patient (PT004)
```r
# Source: R/00_config.R TREATMENT_CODES$sct_cpt (lines 2518-2524)

generate_procedures <- function() {
  tribble(
    ~PROCEDURESID, ~ID,     ~ENCOUNTERID, ~ENC_TYPE, ~ADMIT_DATE,  ~PROVIDERID, ~PX_DATE,     ~PX,     ~PX_TYPE, ~PX_SOURCE, ~PPX, ~SOURCE,
    # PT004: SCT — autologous stem cell transplant
    "PX004",       "PT004", "ENC004_01",  "IP",      "2012-05-12", "PROV001",   "2012-05-18", "38241", "CH",     "OD",       NA,   "VRT"
  )
}
```

### FIXTURE_DESIGN.md Template
```markdown
# Test Fixture Design

**Generated:** 2026-06-04
**Version:** 1.0
**Source:** tests/generate_fixtures.R

## Patient Roster and Edge Case Mapping

| Patient ID | Edge Case(s) | Rationale | Expected Filter Behavior |
|------------|--------------|-----------|--------------------------|
| PT001 | Baseline (happy path) | Standard ICD-10 HL diagnosis (C81.10), private insurance (512), no complications | Passes all filters; included in final cohort |
| PT002 | Dual-eligible | Payer code 14 (Dual Eligibility Medicare/Medicaid) | Maps to Medicaid category; DUAL_ELIGIBLE flag = TRUE |
| PT003 | NLPHL | C81.00 diagnosis (nodular lymphocyte predominant HL) | Classified as NLPHL, not classical HL |
| PT004 | SCT | CPT 38241 (autologous stem cell transplant) | has_sct() = TRUE |
| PT005 | Multiple cancers | C81.40 (HL) + C50.911 (breast cancer) | Both cancers appear in cancer summary |
| PT006 | Death date | DEATH_DATE = 2014-06-15 | Timeline truncated at death; excluded from post-death analyses |
| PT007 | Orphan dx codes | Z51.11 (chemo encounter) without paired chemo procedure | Flagged as orphan; not counted as treatment evidence |
| PT008 | Same-day multi-payer | Two encounters on 2013-07-10, payers 1 (Medicare) and 512 (Private) | Tiered payer resolution selects Medicare (rank 2 > 3) |
| PT009 | 1900 sentinel dates | ENR_START_DATE = 1900-01-01 | Filtered by exclude_1900_dates() predicate |
| PT010 | ICD-9/ICD-10 cross-system | 201.90 (ICD-9) on 2012-11-05 + C81.90 (ICD-10) on 2012-11-15 (10-day gap) | Both codes contribute to 7-day unique gap confirmation |
| PT011 | Missing payer | PAYER_TYPE_PRIMARY = "NI" (No Information) | Excluded by exclude_missing_payer() |
| PT012 | ABVD regimen | RXNORM_CUIs 3639, 11213, 67228, 3946 all on 2013-02-15 | Identified as ABVD first-line therapy |
| PT013-PT019 | Variation patients | Additional combinations for robustness | (Define as needed) |
| PT020 | Baseline (happy path) | Second baseline patient for consistency check | Passes all filters; output should match PT001 structure |

## Data Summary

| Table | Row Count | Key Features |
|-------|-----------|--------------|
| ENROLLMENT | 20 | One row per patient; PT009 has sentinel 1900 date |
| DIAGNOSIS | 18 | PT005 has 2 diagnoses (HL + breast); PT007 has 2 (HL + Z51.11); PT010 has 2 (ICD-9 + ICD-10) |
| ENCOUNTER | 17 | PT005, PT007, PT008, PT010 have multiple encounters |
| DEMOGRAPHIC | 20 | One row per patient; ages 30-70 at diagnosis |
| PROCEDURES | 1 | PT004 SCT procedure only |
| PRESCRIBING | 4 | PT012 ABVD regimen (4 drugs) |
| DISPENSING | 0 | Empty (header only) — not used by current pipeline |
| MED_ADMIN | 0 | Empty (header only) — not used by current pipeline |
| CONDITION | 1 | Minimal (header + 1 row) — not actively filtered |
| LAB_RESULT_CM | 0 | Empty (header only) — surveillance lab values not tested in v1 |
| PROVIDER | 1 | Minimal (header + 1 row) — provider specialty not filtered in v1 |
| DEATH | 1 | PT006 only |
| TUMOR_REGISTRY1 | 0 | Empty (header only) — HL diagnosis from DIAGNOSIS table sufficient |
| TUMOR_REGISTRY2 | 0 | Empty (header only) |
| TUMOR_REGISTRY3 | 0 | Empty (header only) |

## Verification Checklist

Before committing fixtures:

- [ ] All 15 CSVs present in tests/fixtures/
- [ ] Filename override correct: LAB_RESULT_Mailhot_V1.csv (not LAB_RESULT_CM_)
- [ ] Every table has SOURCE column
- [ ] Date columns are character strings (not Date objects)
- [ ] Patient IDs are zero-padded: PT001-PT020 (not PT1-PT20)
- [ ] Encounter IDs follow ENC{patient}_{seq} pattern
- [ ] Dual-eligible patient has payer code "14"
- [ ] ABVD patient has all 4 RXNORM_CUIs: 3639, 11213, 67228, 3946
- [ ] ICD-9/ICD-10 patient diagnoses are 7+ days apart
- [ ] Same-day multi-payer patient has 2 encounters with same ADMIT_DATE
- [ ] Total fixture size < 1MB for reasonable git performance
- [ ] CSVs are git-tracked (not in .gitignore)
- [ ] tests/generate_fixtures.R is git-tracked and runnable

## Regeneration Instructions

To update fixtures after editing design:

1. Edit `tests/generate_fixtures.R`
2. Run: `source("tests/generate_fixtures.R")`
3. Review generated CSVs in `tests/fixtures/`
4. Commit both script and CSVs: `git add tests/generate_fixtures.R tests/fixtures/*.csv`
5. Commit message: "fixtures: [description of change]"

## Edge Case Coverage Matrix

| Edge Case | Patient | Table(s) | Verification Query |
|-----------|---------|----------|-------------------|
| Dual-eligible | PT002 | ENCOUNTER | `filter(PAYER_TYPE_PRIMARY == "14")` |
| NLPHL | PT003 | DIAGNOSIS | `filter(DX == "C81.00")` |
| SCT | PT004 | PROCEDURES | `filter(PX == "38241")` |
| Multiple cancers | PT005 | DIAGNOSIS | `filter(ID == "PT005") %>% count()` → 2 rows |
| Death date | PT006 | DEATH | `filter(ID == "PT006")` |
| Orphan dx | PT007 | DIAGNOSIS | `filter(DX == "Z51.11")` |
| Same-day multi-payer | PT008 | ENCOUNTER | `filter(ID == "PT008", ADMIT_DATE == "2013-07-10")` → 2 rows |
| 1900 sentinel | PT009 | ENROLLMENT | `filter(ENR_START_DATE == "1900-01-01")` |
| ICD-9/ICD-10 cross | PT010 | DIAGNOSIS | `filter(ID == "PT010", DX_TYPE %in% c("09", "10"))` → 2 rows |
| Missing payer | PT011 | ENCOUNTER | `filter(PAYER_TYPE_PRIMARY == "NI")` |
| ABVD regimen | PT012 | PRESCRIBING | `filter(ID == "PT012")` → 4 rows with distinct RXNORM_CUIs |
```

## Environment Availability

> Phase has no external dependencies beyond R packages already installed in renv. All generation logic uses base R + tidyverse (already satisfied by Phase 83).

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R | Script execution | ✓ | 4.4.2 | — |
| tidyverse | tribble(), write_csv(), dplyr | ✓ | 2.0.0 | — |
| renv | Package management | ✓ | 1.1.4 | — |

**Missing dependencies with no fallback:** None

**Missing dependencies with fallback:** None

## Sources

### Primary (HIGH confidence)
- Project codebase (R/00_config.R, R/01_load_pcornet.R, R/10_cohort_predicates.R) — extracted ICD codes, payer codes, RXNORM CUIs, column type specifications
- [Test fixtures • testthat](https://testthat.r-lib.org/articles/test-fixtures.html) — official testthat documentation on fixture organization and best practices
- tibble package documentation (CRAN) — tribble() syntax and usage

### Secondary (MEDIUM confidence)
- [R-hub blog: Helper code and files for your testthat tests](https://blog.r-hub.io/2020/11/18/testthat-utility-belt/) — test fixture patterns and organization
- [OneFlorida+ - PCORnet®](https://pcornet.org/news/category/network-partner/oneflorida/) — network partner information (site codes AMS, UMI, FLM, VRT, UFH extracted from R/00_config.R comments, not official OneFlorida documentation)

### Tertiary (LOW confidence)
- [Synthetic Data Generation for Clinical Trials](https://aimultiple.com/synthetic-data-use-cases) — general principles for synthetic clinical data (edge case testing, HIPAA compliance) but no specific R implementation guidance
- RXNORM_CUI codes for ABVD: Verified from R/00_config.R (lines 2389-2392) which cites "ABVD regimen base ingredients (RxNorm concept IDs)" — these codes are production-used, not independently verified against NLM RxNav

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages already installed and tested in Phase 83; tribble() and write_csv() are stable tidyverse APIs
- Architecture: HIGH - Pattern based on established testthat best practices and existing project conventions (PCORNET_TABLES, PCORNET_PATHS reuse)
- Pitfalls: HIGH - Derived from project-specific code (filename overrides, column type specs, dual-eligible logic) and general R testing experience
- Edge case codes: HIGH - All codes (ICD, payer, RXNORM_CUI) extracted from production config (R/00_config.R), not external sources
- OneFlorida site codes: MEDIUM - Codes found in R/00_config.R comments but not independently verified against OneFlorida official documentation

**Research date:** 2026-06-04
**Valid until:** 60 days (stable domain — R testing practices and PCORnet CDM structure change infrequently)
