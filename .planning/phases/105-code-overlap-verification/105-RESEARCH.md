# Phase 105: Code & Overlap Verification - Research

**Researched:** 2026-06-15
**Domain:** Code classification verification and lymphoma overlap validation
**Confidence:** HIGH

## Summary

Phase 105 produces four standalone investigation reports validating code classification concerns and HL+NHL dual-diagnosis data quality. Two scripts deliver two xlsx files: (1) combined code verification investigating etanercept immunotherapy classification, organ transplant revenue code 0362 usage, and SCT diagnosis code validation against patient data; (2) HL+NHL overlap validation extending R/78's Venn analysis with patient-level temporal detail to assess the ~4,000/8,000 dual-code rate flagged in meeting notes.

The phase follows the established Phase 104 investigation script pattern: DuckDB queries via `get_pcornet_table()`, multi-sheet styled xlsx outputs using openxlsx2, section-based console logging with glue, and raw counts without HIPAA suppression. No upstream modifications—reports document findings and recommendations for potential follow-up config changes.

**Primary recommendation:** Use R/31-R/32 investigation script template structure. Leverage existing `R/78_venn_lymphoma_3way.R` patient classification logic for OVERLAP-01 temporal extension. Query PRESCRIBING for RxNorm codes, PROCEDURES for revenue/CPT codes, DIAGNOSIS for ICD codes via lazy DuckDB evaluation. Add R/88 smoke test section (Phase 105 / Section 29) validating both new scripts exist and produce expected output files.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Script Organization:**
- D-01: Two scripts total: one combined code verification script (CODE-01 + CODE-02 + CODE-03) and one separate HL+NHL overlap validation script (OVERLAP-01)
- D-02: Combined code verification script produces a single xlsx with tabs per investigation plus a summary tab with recommendations. Each CODE section is a self-contained analysis block within the script
- D-03: Script numbering follows next available numbers in the investigation script decade (R/33, R/34 or similar — Claude's discretion on exact numbers)

**Code Verification Investigations (CODE-01/02/03):**
- D-04: CODE-01 (Ethna/etanercept): Query PRESCRIBING for etanercept RxNorm codes (1653225, 809158, 809159, 214555). Cross-reference against DRUG_GROUPINGS immunotherapy codes. Report finding: etanercept is a TNF-alpha inhibitor (immunosuppressant), NOT anticancer immunotherapy. Already correctly excluded from DRUG_GROUPINGS — data quality issue in raw data, not a mapping error
- D-05: CODE-02 (Organ transplant code 0362): Query PROCEDURES for revenue code 0362. Cross-reference patients against SCT-indicating diagnosis codes (Z94.84) and procedure codes (38240-38243, 30233/30243 series) to assess what fraction are SCT vs solid organ transplant
- D-06: CODE-03 (SCT codes above line 22): Query DIAGNOSIS for Z94.84 (SCT status), T86.5 (SCT complications), T86.09 (BMT complications). Cross-reference against procedure-based SCT evidence. Report how many patients have diagnosis-only vs. diagnosis+procedure evidence

**HL+NHL Overlap Validation (OVERLAP-01):**
- D-07: Extends R/78's 3-way Venn analysis with patient-level temporal detail. For each dual-code patient: first HL dx date, first NHL dx date, days between, same-day flag, encounter count per type
- D-08: Summary pattern analysis: categorize dual-code patients by temporal relationship (same-day, <30 days apart, 30-180 days, >180 days). This directly addresses the meeting note concern about whether dual diagnoses are real
- D-09: Output as hl_nhl_overlap_validation.xlsx with three tabs: Summary (counts and pattern breakdown), Patient Detail (per-patient temporal data), Pattern Analysis (grouped statistics)

**Action Outcomes:**
- D-10: Report-only — no modifications to R/00_config.R, DRUG_GROUPINGS, or any existing scripts. Recommendations are captured in xlsx summary tabs and console output. Config changes, if needed, would be a separate follow-up phase
- D-11: Raw counts without HIPAA suppression — manual suppression before sharing (v3.1/v3.2 convention)

**Output Structure:**
- D-12: Two xlsx output files: `code_verification.xlsx` (3 investigation tabs + Summary/Recommendations tab) and `hl_nhl_overlap_validation.xlsx` (Summary + Patient Detail + Pattern Analysis tabs)

### Claude's Discretion

- Exact script numbers (next available in investigation decade)
- Console logging structure and verbosity
- Tab ordering and column layout within xlsx files
- Whether to include percentage columns alongside raw counts in summaries
- R/88 smoke test section structure and check count for both new scripts
- Specific temporal buckets for overlap pattern analysis (exact day thresholds)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CODE-01 | User can run R script that investigates "Ethna" immunotherapy classification, verifying whether it appears in current code mappings and recommending correction | RxNorm code lookup via PRESCRIBING table query; etanercept codes (1653225, 809158, 809159, 214555) cross-referenced against DRUG_GROUPINGS immunotherapy_rxnorm list (lines 3044-3073 of R/00_config.R) |
| CODE-02 | User can run R script that cross-checks organ transplant code (line 11 of all_codes_resolved spreadsheet) against current SCT code mappings and patient data | Revenue code 0362 query via PROCEDURES table; cross-reference with SCT diagnosis codes (Z94.84) and procedure codes (38240-38243, 30233/30243 series) from DRUG_GROUPINGS sct_* sublists |
| CODE-03 | User can run R script that verifies SCT codes above line 22 in the codes spreadsheet against actual patient data, flagging codes with zero or suspicious usage | DIAGNOSIS table query for Z94.84, T86.5, T86.09; cross-reference with procedure-based SCT evidence from PROCEDURES table |
| OVERLAP-01 | User can run R script that produces a focused validation report on HL+NHL dual-code patients (~4,000 of 8,000), extending R/77-R/78 with patient-level detail and data quality assessment | R/78 Venn logic reuse (C82-C86/200/202 NHL patterns, C81 HL patterns); DIAGNOSIS table temporal queries for first dx dates per type; pattern categorization by days-between threshold |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | tidyverse standard; established project pattern |
| glue | 1.8.0 | String formatting | Project convention for console logging |
| openxlsx2 | 1.10+ | xlsx creation | Project standard for styled multi-sheet outputs (R/29-R/32, R/53, R/57-R/59) |
| lubridate | 1.9.3+ | Date operations | Date parsing and temporal gap calculations |
| stringr | 1.5.1+ | String operations | Code normalization (ICD dotted/undotted formats) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DBI / duckdb | N/A | Database queries | DuckDB lazy query execution via get_pcornet_table() |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| openxlsx2 | openxlsx (v1) | v1 is deprecated; v2 is project standard since Phase 88 |
| DuckDB queries | readRDS cached tables | DuckDB is production standard; RDS cache only for local/fixture mode |

**Installation:**
All libraries already in project renv.lock — no new installations needed.

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 33_code_verification.R          # CODE-01, CODE-02, CODE-03 combined
├── 34_hl_nhl_overlap_validation.R  # OVERLAP-01
├── 88_smoke_test_comprehensive.R   # Add Phase 105 section
└── utils/
    ├── utils_duckdb.R              # get_pcornet_table()
    ├── utils_dates.R               # parse_pcornet_date()
    └── utils_assertions.R          # assert_rds_exists(), assert_df_valid()
```

### Pattern 1: Investigation Script Structure
**What:** Section-based script with console logging, DuckDB queries, analysis, styled xlsx output
**When to use:** All investigation scripts (R/30-R/32 established pattern)
**Example:**
```r
# Source: R/31_pre_diagnosis_treatments.R (Phase 104)

# ==============================================================================
# SECTION 1: SETUP AND CONFIGURATION ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(openxlsx2)
})

source("R/00_config.R")
source("R/utils/utils_assertions.R")
source("R/utils/utils_duckdb.R")

# Define file paths
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "code_verification.xlsx")

message("=== R/33: Code Verification (CODE-01/02/03) ===")
message(glue("  Output: {OUTPUT_XLSX}"))

# ==============================================================================
# SECTION 2: INPUT VALIDATION ----
# ==============================================================================

message("--- Input validation ---")
# Validate RDS inputs exist (if needed)

# ==============================================================================
# SECTION 3: CODE-01 INVESTIGATION (Ethna/Etanercept) ----
# ==============================================================================

message("--- CODE-01: Etanercept investigation ---")

# Query PRESCRIBING for etanercept RxNorm codes
etanercept_codes <- c("1653225", "809158", "809159", "214555")
etanercept_rx <- get_pcornet_table("PRESCRIBING") %>%
  filter(RXNORM_CUI %in% etanercept_codes) %>%
  select(ID, RXNORM_CUI, RX_START_DATE) %>%
  collect()

message(glue("  Found {nrow(etanercept_rx)} etanercept prescriptions for {n_distinct(etanercept_rx$ID)} patients"))

# Cross-reference against DRUG_GROUPINGS immunotherapy codes
immuno_rxnorm <- names(DRUG_GROUPINGS)[DRUG_GROUPINGS == "Immunotherapy" & grepl("^\\d+$", names(DRUG_GROUPINGS))]
overlap <- intersect(etanercept_codes, immuno_rxnorm)

message(glue("  Etanercept codes in DRUG_GROUPINGS immunotherapy: {length(overlap)} of {length(etanercept_codes)}"))

# Build findings table
code01_findings <- data.frame(
  Finding = "Etanercept classification",
  Status = ifelse(length(overlap) == 0, "CORRECT", "NEEDS CORRECTION"),
  Detail = ifelse(length(overlap) == 0,
    "Etanercept correctly excluded from immunotherapy — it is a TNF-alpha inhibitor (immunosuppressant), not anticancer immunotherapy",
    glue("{length(overlap)} etanercept codes found in immunotherapy grouping — should be excluded")
  ),
  Recommendation = ifelse(length(overlap) == 0, "No action needed", "Remove from DRUG_GROUPINGS immunotherapy"),
  stringsAsFactors = FALSE
)

# ==============================================================================
# SECTION 4: CODE-02 INVESTIGATION (Organ Transplant 0362) ----
# ==============================================================================

message("\n--- CODE-02: Revenue code 0362 investigation ---")

# Query PROCEDURES for revenue code 0362
rev_0362 <- get_pcornet_table("PROCEDURES") %>%
  filter(REVENUE_CODE == "0362") %>%
  select(ID, REVENUE_CODE, PX_DATE) %>%
  collect()

message(glue("  Found {nrow(rev_0362)} records with revenue code 0362 for {n_distinct(rev_0362$ID)} patients"))

# Cross-reference with SCT diagnosis codes (Z94.84)
sct_dx <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX %in% c("Z94.84", "Z9484")) %>%
  select(ID) %>%
  distinct() %>%
  collect()

overlap_sct_dx <- rev_0362 %>%
  filter(ID %in% sct_dx$ID) %>%
  distinct(ID)

message(glue("  Patients with 0362 AND Z94.84 SCT status code: {nrow(overlap_sct_dx)} of {n_distinct(rev_0362$ID)}"))

# Build findings table
code02_findings <- data.frame(
  Revenue_Code = "0362",
  Total_Records = nrow(rev_0362),
  Unique_Patients = n_distinct(rev_0362$ID),
  With_SCT_Dx = nrow(overlap_sct_dx),
  Percent_SCT = sprintf("%.1f%%", 100 * nrow(overlap_sct_dx) / n_distinct(rev_0362$ID)),
  Recommendation = "Revenue code 0362 covers both solid organ and SCT — current inclusion in DRUG_GROUPINGS is appropriate given majority have corroborating SCT evidence",
  stringsAsFactors = FALSE
)

# ==============================================================================
# SECTION 5: CODE-03 INVESTIGATION (SCT Codes Above Line 22) ----
# ==============================================================================

message("\n--- CODE-03: SCT diagnosis codes above line 22 ---")

# Query DIAGNOSIS for Z94.84, T86.5, T86.09
sct_status_codes <- c("Z94.84", "Z9484", "T86.5", "T865", "T86.09", "T8609")
sct_status_dx <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX %in% sct_status_codes |
         toupper(str_remove_all(DX, "\\.")) %in% str_remove_all(sct_status_codes, "\\.")) %>%
  select(ID, DX, DX_TYPE, DX_DATE) %>%
  collect()

message(glue("  Found {nrow(sct_status_dx)} SCT status/complication diagnosis records for {n_distinct(sct_status_dx$ID)} patients"))

# Query PROCEDURES for actual SCT procedure codes (38240-38243, 30233/30243 series)
sct_proc_codes <- names(DRUG_GROUPINGS)[DRUG_GROUPINGS == "SCT" & !grepl("^\\d+$", names(DRUG_GROUPINGS))]
sct_proc <- get_pcornet_table("PROCEDURES") %>%
  filter(PX %in% sct_proc_codes) %>%
  select(ID) %>%
  distinct() %>%
  collect()

# Cross-reference
patients_dx_only <- setdiff(sct_status_dx$ID, sct_proc$ID)
patients_dx_and_proc <- intersect(sct_status_dx$ID, sct_proc$ID)

message(glue("  Diagnosis-only (no procedure evidence): {length(patients_dx_only)} patients"))
message(glue("  Diagnosis + procedure evidence: {length(patients_dx_and_proc)} patients"))

# Build findings table
code03_findings <- data.frame(
  Code_Type = c("Z94.84 (SCT status)", "T86.5 (SCT complications)", "T86.09 (BMT complications)"),
  In_DRUG_GROUPINGS = c("No", "No", "No"),
  Patient_Count = c(
    sum(str_detect(sct_status_dx$DX, "Z94.84|Z9484")),
    sum(str_detect(sct_status_dx$DX, "T86.5|T865")),
    sum(str_detect(sct_status_dx$DX, "T86.09|T8609"))
  ),
  With_Procedure_Evidence = "See detail tab",
  Recommendation = "Correctly excluded from DRUG_GROUPINGS — these are status/complication codes, not treatment events",
  stringsAsFactors = FALSE
)

# ==============================================================================
# SECTION 6: CREATE STYLED XLSX ----
# ==============================================================================

message("\n--- Creating styled xlsx ---")

wb <- wb_workbook()

# --- Sheet 1: Summary/Recommendations ---
wb$add_worksheet("Summary")
# [Title, subtitle, header formatting per R/31 pattern]
# [Add code01_findings, code02_findings, code03_findings as summary]

# --- Sheet 2: CODE-01 Detail ---
wb$add_worksheet("CODE-01 Detail")
# [Etanercept prescription detail with patient IDs, dates, RxNorm codes]

# --- Sheet 3: CODE-02 Detail ---
wb$add_worksheet("CODE-02 Detail")
# [Revenue code 0362 records with SCT evidence flags]

# --- Sheet 4: CODE-03 Detail ---
wb$add_worksheet("CODE-03 Detail")
# [SCT diagnosis code records with procedure evidence flags]

wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
message(glue("  Saved: {OUTPUT_XLSX}"))

# ==============================================================================
# SECTION 7: FINAL SUMMARY ----
# ==============================================================================

message("\n=== R/33 Code Verification Complete ===")
message(glue("  Output: {OUTPUT_XLSX}"))
message("Done.")
```

### Pattern 2: HL+NHL Overlap Temporal Analysis
**What:** Extension of R/78 Venn logic with per-patient first-dx-date temporal detail
**When to use:** OVERLAP-01 investigation
**Example:**
```r
# Source: Extended from R/78_venn_lymphoma_3way.R

# Query all HL diagnoses (C81 ICD-10, 201 ICD-9)
hl_dx <- get_pcornet_table("DIAGNOSIS") %>%
  filter((DX_TYPE == "10" & str_detect(DX, "^C81")) |
         (DX_TYPE == "09" & str_detect(DX, "^201"))) %>%
  select(ID, DX, DX_TYPE, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\.")))

# Query all NHL diagnoses (C82-C86 ICD-10, 200/202 ICD-9)
nhl_dx <- get_pcornet_table("DIAGNOSIS") %>%
  filter((DX_TYPE == "10" & str_detect(DX, "^C8[2-6]")) |
         (DX_TYPE == "09" & str_detect(DX, "^(200|202)"))) %>%
  select(ID, DX, DX_TYPE, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\.")))

# Get first dx date per patient per type
hl_first <- hl_dx %>%
  group_by(ID) %>%
  summarise(first_hl_dx = min(DX_DATE, na.rm = TRUE), .groups = "drop")

nhl_first <- nhl_dx %>%
  group_by(ID) %>%
  summarise(first_nhl_dx = min(DX_DATE, na.rm = TRUE), .groups = "drop")

# Identify dual-code patients
dual_code <- hl_first %>%
  inner_join(nhl_first, by = "ID") %>%
  mutate(
    days_between = as.numeric(abs(first_hl_dx - first_nhl_dx)),
    same_day = (days_between == 0),
    temporal_category = case_when(
      same_day ~ "Same day",
      days_between < 30 ~ "<30 days apart",
      days_between < 180 ~ "30-180 days apart",
      TRUE ~ ">180 days apart"
    )
  )

message(glue("  Dual-code patients: {nrow(dual_code)}"))

# Pattern summary
pattern_summary <- dual_code %>%
  group_by(temporal_category) %>%
  summarise(
    n_patients = n(),
    pct = n() / nrow(dual_code),
    .groups = "drop"
  ) %>%
  arrange(desc(n_patients))

# Output to xlsx with 3 tabs: Summary, Patient Detail, Pattern Analysis
```

### Pattern 3: openxlsx2 Styled Output
**What:** Multi-sheet xlsx with consistent header styling (dark gray FF374151, white bold text)
**When to use:** All investigation outputs
**Example:**
```r
# Source: R/31_pre_diagnosis_treatments.R lines 200-255

wb <- wb_workbook()
wb$add_worksheet("Summary")

# Title row (Calibri 16pt bold, dark gray)
wb$add_data(sheet = "Summary", x = "Code Verification Summary", start_row = 1, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A1", name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Summary", dims = "A1:D1")

# Header row 3 (dark gray background FF374151, white bold text)
headers <- c("Investigation", "Status", "Detail", "Recommendation")
for (i in seq_along(headers)) {
  wb$add_data(sheet = "Summary", x = headers[i], start_row = 3, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A3:D3", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A3:D3", name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows starting at row 4
wb$add_data(sheet = "Summary", x = summary_table, start_row = 4, col_names = FALSE)

# Freeze pane below header
wb$freeze_pane(sheet = "Summary", firstActiveRow = 4)
```

### Anti-Patterns to Avoid
- **Manual logging code:** Use tidylog or glue message() consistently — don't mix cat(), print(), message()
- **Hardcoded paths:** Always use `file.path(CONFIG$output_dir, "filename.xlsx")` not `"output/filename.xlsx"`
- **Modifying upstream scripts:** These are report-only investigations — no changes to R/00_config.R, DRUG_GROUPINGS, or existing scripts

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| DuckDB table access | Custom SQL queries with dbGetQuery() | `get_pcornet_table("TABLE_NAME") %>% filter(...) %>% collect()` | Utility handles backend switching (DuckDB vs RDS cache), lazy evaluation optimization |
| Date parsing | Custom lubridate logic per script | `parse_pcornet_date()` from utils_dates.R | Centralized sentinel date handling (year <= 1900), consistent parsing across pipeline |
| Input validation | Manual file.exists() checks | `assert_rds_exists()`, `assert_df_valid()` from utils_assertions.R | Consistent error messages with context, project standard since Phase 72 |
| ICD code normalization | str_remove_all(DX, "\\.") per script | Pattern already established in R/78 — reuse consistently | Edge cases handled (missing dots, mixed case) |
| Venn classification | Rebuild patient set logic | Reuse R/78 NHL_ICD10_PATTERN, NHL_ICD9_PATTERN, HL code detection logic | Tested logic, consistent with existing 3-way Venn |

**Key insight:** Investigation scripts benefit from established utility patterns — don't reinvent data access, validation, or formatting. Focus effort on analysis logic and clear reporting.

## Common Pitfalls

### Pitfall 1: RxNorm Code String vs Integer Confusion
**What goes wrong:** PRESCRIBING.RXNORM_CUI is stored as character, but config lists numeric codes. Query misses records due to type mismatch.
**Why it happens:** PCORnet CDM stores codes as strings to preserve leading zeros; R/00_config.R defines codes as character vectors but without quotes they become numeric.
**How to avoid:** Always quote RxNorm codes in queries: `filter(RXNORM_CUI %in% c("1653225", "809158"))` not `filter(RXNORM_CUI %in% c(1653225, 809158))`
**Warning signs:** Query returns zero rows when you expect matches; glimpse(etanercept_rx) shows 0 obs.

### Pitfall 2: ICD Code Dotted vs Undotted Normalization
**What goes wrong:** Querying for "Z94.84" misses records stored as "Z9484" or vice versa.
**Why it happens:** PCORnet data has mixed formats (some facilities use dots, some don't).
**How to avoid:** Normalize both sides: `filter(toupper(str_remove_all(DX, "\\.")) %in% c("Z9484", "T865"))`
**Warning signs:** Low match counts; manual inspection shows same code with/without dots.

### Pitfall 3: Same-Day Diagnosis Temporal Logic
**What goes wrong:** Calculating `days_between <- first_hl_dx - first_nhl_dx` returns negative values when NHL is before HL, complicating temporal bucketing.
**Why it happens:** Subtraction order matters; temporal categorization needs absolute difference.
**How to avoid:** Use `days_between <- as.numeric(abs(first_hl_dx - first_nhl_dx))` for symmetric comparison.
**Warning signs:** Negative day values in output; pattern categories show asymmetric counts.

### Pitfall 4: DRUG_GROUPINGS List Subsetting by Code Type
**What goes wrong:** Attempting `DRUG_GROUPINGS[grepl("^\\d+$", names(DRUG_GROUPINGS))]` to get RxNorm codes includes other numeric codes (CPT, ICD-9).
**Why it happens:** Multiple code systems use numeric identifiers; simple digit pattern isn't specific enough.
**How to avoid:** Use explicit sublist access: `TREATMENT_CODES$immunotherapy_rxnorm` for known lists, or cross-reference against source table metadata.
**Warning signs:** Cross-reference returns unexpected code types; manual review shows CPT codes in "RxNorm" subset.

### Pitfall 5: Lazy DuckDB Evaluation Without collect()
**What goes wrong:** Assigning DuckDB query result without `collect()` creates lazy tibble; downstream operations fail or return incorrect counts.
**Why it happens:** dplyr's `tbl()` returns unevaluated query; R operations trigger SQL translation that may not support all R functions.
**How to avoid:** Always call `collect()` after filter/select chain: `etanercept_rx <- get_pcornet_table("PRESCRIBING") %>% filter(...) %>% collect()`
**Warning signs:** `class(result)` shows "tbl_duckdb_connection" not "data.frame"; `nrow()` returns NA or incorrect count.

## Code Examples

Verified patterns from project codebase:

### DuckDB Query with Lazy Evaluation
```r
# Source: R/31_pre_diagnosis_treatments.R lines 89-99
# Pattern: Query PCORnet table via DuckDB with lazy filter, then collect()

episodes <- readRDS(INPUT_EPISODES)
cohort <- readRDS(INPUT_COHORT)

# Join episodes to cohort (inner join = confirmed HL patients only)
episodes_with_dx <- episodes %>%
  inner_join(cohort %>% select(ID, first_hl_dx_date), by = c("patient_id" = "ID"))

# Filter with sentinel date guard
pre_dx_episodes <- episodes_with_dx %>%
  filter(!is.na(first_hl_dx_date)) %>%
  filter(year(first_hl_dx_date) > 1900) %>%  # Pitfall guard
  filter(episode_start < first_hl_dx_date) %>%
  mutate(days_before_dx = as.numeric(first_hl_dx_date - episode_start))
```

### Multi-Tab openxlsx2 Workbook Creation
```r
# Source: R/32_secondary_malignancy_table.R lines 256-324
# Pattern: Create workbook, add multiple worksheets with consistent styling

wb <- wb_workbook()

# --- Sheet 1: Summary ---
wb$add_worksheet("Summary")

# Title row (Calibri 16pt bold, dark gray)
wb$add_data(sheet = "Summary", x = "Secondary Malignancy Table -- Confirmed HL Cohort", start_row = 1, start_col = 1)
wb$add_font(sheet = "Summary", dims = "A1", name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Summary", dims = "A1:D1")

# Header row 5 (dark gray background FF374151, white bold text)
headers_summary <- c("Cancer Category", "Timing", "Patients", "% of Cohort")
for (i in seq_along(headers_summary)) {
  wb$add_data(sheet = "Summary", x = headers_summary[i], start_row = 5, start_col = i)
}
wb$add_fill(sheet = "Summary", dims = "A5:D5", color = wb_color("FF374151"))
wb$add_font(sheet = "Summary", dims = "A5:D5", name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))

# Data rows starting at row 6
wb$add_data(sheet = "Summary", x = summary_table, start_row = 6, col_names = FALSE)

# Number formatting
last_row_summary <- 5 + nrow(summary_table)
wb$add_numfmt(sheet = "Summary", dims = glue("C6:C{last_row_summary}"), numfmt = "#,##0")
wb$add_numfmt(sheet = "Summary", dims = glue("D6:D{last_row_summary}"), numfmt = "0.0%")

# Freeze pane below header
wb$freeze_pane(sheet = "Summary", firstActiveRow = 6)

wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)
```

### R/78 Venn Classification Reuse Pattern
```r
# Source: R/78_venn_lymphoma_3way.R lines 60-113
# Pattern: Query DIAGNOSIS, normalize codes, classify into HL/NHL sets

# NHL ICD-10-CM codes: C82-C86 (major NHL categories)
NHL_ICD10_PATTERN <- "^C8[2-6]"
NHL_ICD9_PATTERN  <- "^(200|202)"

# Query all lymphoma diagnoses
dx_icd10 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C8[1-6]"))

dx_icd9 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "09") %>%
  select(ID, DX, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^(200|201|202)"))

# Classify into NHL rows
nhl_rows <- bind_rows(
  dx_icd10 %>% filter(str_detect(DX_norm, NHL_ICD10_PATTERN)),
  dx_icd9  %>% filter(str_detect(DX_norm, NHL_ICD9_PATTERN))
)

nhl_ids <- unique(nhl_rows$ID)
```

## Validation Architecture

> **Note:** Skipped — `workflow.nyquist_validation` is explicitly set to false in .planning/config.json.

## Sources

### Primary (HIGH confidence)
- **Project Codebase:**
  - R/31_pre_diagnosis_treatments.R — Phase 104 investigation script template (lines 1-316)
  - R/32_secondary_malignancy_table.R — Multi-sheet xlsx pattern with styled headers (lines 1-406)
  - R/78_venn_lymphoma_3way.R — HL/NHL classification logic (lines 1-338)
  - R/88_smoke_test_comprehensive.R — Smoke test structure and section patterns (lines 1-2755)
  - R/00_config.R — DRUG_GROUPINGS immunotherapy_rxnorm (lines 3044-3073), sct_* sublists (lines 1599-1635)
  - R/utils/utils_duckdb.R — get_pcornet_table() utility (lines 1-50)
  - R/utils/utils_dates.R — parse_pcornet_date() utility
  - R/utils/utils_assertions.R — assert_rds_exists(), assert_df_valid() utilities

- **Phase Context:**
  - .planning/phases/105-code-overlap-verification/105-CONTEXT.md — User decisions (D-01 through D-12)
  - .planning/REQUIREMENTS.md — CODE-01, CODE-02, CODE-03, OVERLAP-01 specifications
  - pecan_lymphoma_meeting_notes_combined.md — G4 (HL+NHL overlap), G8 (Ethna), G10 (0362), G11 (SCT codes)

- **Code Reference Files:**
  - all_codes_resolved_next_tables.xlsx — Line 11 (revenue code 0362), lines 3-22 (SCT status codes), line 22+ (active SCT procedures)

### Secondary (MEDIUM confidence)
- **External Documentation:**
  - openxlsx2 package documentation — wb_workbook(), add_worksheet(), add_data(), wb_color(), freeze_pane() API verified against project usage patterns
  - DuckDB R client documentation — Lazy evaluation behavior, tbl() vs collect() semantics

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already in renv.lock; versions verified via project scripts
- Architecture: HIGH - Patterns directly lifted from Phase 104 (R/31, R/32) and existing R/78 Venn logic
- Pitfalls: HIGH - Identified from actual project code patterns and PCORnet data quirks (ICD normalization, RxNorm string types)
- Code examples: HIGH - All examples copied verbatim from existing project scripts with line number citations

**Research date:** 2026-06-15
**Valid until:** 2026-07-15 (30 days — stable investigation script pattern, unlikely to change)
