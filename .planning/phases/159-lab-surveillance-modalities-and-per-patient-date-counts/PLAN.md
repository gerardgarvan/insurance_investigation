# Phase 159: Lab Surveillance Modalities and Per-Patient Date Counts

**Goal:** Add BMP, CMP, LIPID, LFT, and KIDNEY as five surveillance modalities to R/147,
using `lab_code_crosswalk.xlsx` as the LOINC dictionary. Produce a wide per-patient
table (LAB-06): one row per HL any-dx denominator patient, one column per modality
(all 14), holding the count of unique post-anchor calendar dates the modality occurred
within follow-up.

**Requirements covered:** LAB-01, LAB-02, LAB-03, LAB-04, LAB-05, LAB-06, LAB-07

**Depends on:** Phase 158 (R/147, `utils_surveillance.R`, `surveillance_codeset.xlsx`)

**Inherited decisions (non-negotiable, from 158-CONTEXT.md D-01..D-30):**
- Denominator = HL any-dx patients; anchor = first HL dx date; follow_end = min(death, last encounter) capped at 2025-09-15 (D-01..D-03, D-09, D-10)
- Event grain = distinct ID × modality × date (D-05)
- Person-years formula: pooled denominator (D-26)
- DuckDB push-down: `DISTINCT ID, code, raw_date` inside DuckDB; HL IDs via temp table semi-join (D-29; L-6)
- Codeset-driven design: analyte lists and thresholds in the file, not in code (L-4)
- Two-workbook pattern: INTERNAL (unsuppressed) + release (suppressed ≤10 → `"<11"`) (D-27)
- Code normalization: trim + uppercase + strip dots (D-15)
- `codeset_row_id` on every matched event (D-23)

---

## Key Decisions from 159-CONTEXT.md

| ID | Decision |
|----|----------|
| D-01 | Counting is **nested**: a CMP day also counts as BMP, LFT, and KIDNEY. Answers "were these analytes checked?" not "which panel was ordered." |
| D-02 | Nesting is implemented as extra codeset rows (same code under multiple modalities), identical to stress echo in 158 D-20. No script logic. |
| D-08 | Sensitivity = partial-panel threshold, not any-single-analyte (prevents glucose = BMP = CMP collapse). |
| D-09 | Thresholds: BMP ≥4/8; CMP ≥7/14; LFT ≥2/4; LIPID ≥2/3; KIDNEY: creatinine alone (primary), OR eGFR/cystatin-C/urine kidney marker (sensitivity). |
| D-10 | New match type `analyte_min_same_day` (replaces `analyte_any_same_day`). Rule rows carry `min_analyte_count` (integer). Loader validates it is < the panel total. `analyte_all_same_day` is the full-panel (primary) match. |
| D-12 | Specimen allowlist: Ser/Plas, Ser, Plas, Ser/Plas/Bld, Bld, BldV. Excluded: BldA (blood gases), BldC (fingerstick glucose). Urine excluded from primary; allowed for KIDNEY sensitivity per D-11. |
| D-13 | Panel codes (CPT + LOINC) are primary-tier `exact` rows. All-analyte rule row is a separate primary-tier row. Both live in the codeset. |
| D-14 | LAB-06 columns: `n_dates_<modality>` (primary, post-anchor) and `n_dates_<modality>_any` (primary-or-sensitivity, post-anchor). No pre-anchor columns here. |
| D-15 | Every denominator ID has a row; patients with no events get zeros, not NA. |
| D-16..D-18 | Inherited Phase 158 denominator/workbook mechanics unchanged. |

---

## Codeset Row Numbering (continuing from Phase 158's SC108)

Phase 158 ended at SC108. New rows start at SC109.

### `Lab_Analytes` Sheet (new) — `analyte_row_id` LA001..

One row per code. Columns:

| Column | Description |
|--------|-------------|
| `analyte_row_id` | `LA001`, `LA002`, … |
| `analyte` | Normalized analyte name (see canonical names below) |
| `code_system` | `LOINC` or `CPT` |
| `code` | As-issued (may have dots for LOINC) |
| `code_norm` | Result of `normalize_surv_code(code)` |
| `cdm_table` | `LAB_RESULT_CM` (LOINC) or `PROCEDURES` (CPT) |
| `type_filter` | `""` for LAB_RESULT_CM; `"CH"` for PROCEDURES CPT |
| `specimen` | Verbatim from crosswalk MASTER (e.g., `"Ser/Plas"`) |
| `loinc_status` | `"ACTIVE"` or `"DEPRECATED"` (carried for A2 review; D-6) |
| `source` | `"crosswalk_LOINC"` or `"crosswalk_CPT"` |

**Canonical analyte names** (exact strings used in rule rows' `code_norm` field):
`SODIUM`, `POTASSIUM`, `CHLORIDE`, `CO2`, `BUN`, `CREATININE`, `GLUCOSE`,
`CALCIUM`, `ALBUMIN`, `TOTAL_PROTEIN`, `ALP`, `ALT`, `AST`, `TOTAL_BILIRUBIN`,
`TOTAL_CHOLESTEROL`, `HDL`, `TRIGLYCERIDES`, `EGFR`, `CYSTATIN_C`,
`URINE_ALBUMIN_CREATININE_RATIO`, `URINE_PROTEIN`

**Selection from crosswalk MASTER:** Exact match on the crosswalk's `component` field
(case-insensitive) plus D-12 specimen allowlist. Do NOT use grouping flags.
KIDNEY sensitivity analytes (EGFR, CYSTATIN_C, URINE_ALBUMIN_CREATININE_RATIO,
URINE_PROTEIN) allow urine specimen for urine-based codes only; their `specimen`
column retains the verbatim crosswalk value.

Example approximate code counts (before review): sodium ≈7 LOINCs, creatinine ≈11,
glucose ≈23, HDL ≈9. Check glucose A2 rows first for challenge/tolerance variants.

### `Analysis_Codeset` New Rows (SC109 onward)

New columns added to `Analysis_Codeset` sheet for these rows only (blank for existing SC001..SC108 rows):
- `min_analyte_count` (integer, blank = NA for non-rule rows)
- The `match` column gains two new allowed values: `analyte_all_same_day` and `analyte_min_same_day`

#### BMP rows (SC109..SC11x)

| SC# | modality | code_system | code | match | tier | notes |
|-----|----------|-------------|------|-------|------|-------|
| SC109 | BMP | CPT | 80048 | exact | primary | BMP panel CPT |
| SC110 | BMP | LOINC | 24320-4 | exact | primary | BMP panel LOINC |
| SC111 | BMP | LOINC | 24321-2 | exact | primary | BMP panel LOINC |
| SC112 | BMP | LOINC | 51990-0 | exact | primary | BMP panel LOINC |
| SC113 | BMP | LOINC | 70219-1 | exact | primary | BMP panel LOINC |
| SC114 | BMP | LOINC | 45064-3 | exact | primary | BMP panel LOINC (deprecated, D-6) |
| SC115 | BMP | LOINC | 101655-9 | exact | primary | BMP panel LOINC |
| SC116 | BMP | LOINC | 104076-5 | exact | primary | BMP panel LOINC |
| SC117 | BMP | — | SODIUM;POTASSIUM;CHLORIDE;CO2;BUN;CREATININE;GLUCOSE;CALCIUM | analyte_all_same_day | primary | All 8 analytes same day |
| SC118 | BMP | — | SODIUM;POTASSIUM;CHLORIDE;CO2;BUN;CREATININE;GLUCOSE;CALCIUM | analyte_min_same_day | sensitivity | min_analyte_count=4 |

**D-01 nesting — CMP panel codes also satisfy BMP.** Add CMP panel CPT 80053 and its
panel LOINCs as duplicate rows under BMP modality (same code_norm; different
codeset_row_id). Same for LFT and KIDNEY where the analyte overlap applies
(BUN and creatinine under CMP make CMP days also KIDNEY primary events, per D-13).
Assign consecutive SC numbers.

#### CMP rows

Panel CPT 80053 + LOINCs 24322-0, 24323-8, 45065-0 (exact, primary).
All-analyte row: `SODIUM;POTASSIUM;CHLORIDE;CO2;BUN;CREATININE;GLUCOSE;CALCIUM;ALBUMIN;TOTAL_PROTEIN;ALP;ALT;AST;TOTAL_BILIRUBIN` (`analyte_all_same_day`, primary).
Sensitivity: same analytes, `analyte_min_same_day`, `min_analyte_count=7`.

#### LIPID rows

Panel CPT 80061 + LOINCs 24331-1, 57698-3, 100898-6 (exact, primary).
All-analyte: `TOTAL_CHOLESTEROL;HDL;TRIGLYCERIDES` (`analyte_all_same_day`, primary).
Sensitivity: same, `analyte_min_same_day`, `min_analyte_count=2`.

#### LFT rows

Panel CPT 80076 + LOINCs 24324-6, 24325-3 (exact, primary).
All-analyte: `ALT;AST;ALP;TOTAL_BILIRUBIN` (`analyte_all_same_day`, primary).
Sensitivity: same, `analyte_min_same_day`, `min_analyte_count=2`.
CMP panel code rows duplicated here (D-01 nesting: CMP days satisfy LFT because CMP
includes all four LFT analytes).

#### KIDNEY rows

Panel CPT 80069 + LOINC 24362-6 (exact, primary).
Primary analyte: `CREATININE` (`analyte_all_same_day`, primary — single analyte; rule is met when any CREATININE code is present that day).
Sensitivity: `CREATININE;EGFR;CYSTATIN_C;URINE_ALBUMIN_CREATININE_RATIO;URINE_PROTEIN`, `analyte_min_same_day`, `min_analyte_count=1` (i.e., creatinine OR one of the others; creatinine itself already counts as primary so any sensitivity event not covered by primary must be one of the alternates).
CMP and BMP panel code rows duplicated here (both contain creatinine).

---

## LAB-06 Column Name Fixed Lookup

Wide table column names use this exact lookup (modality → snake_case prefix):

```r
MODALITY_COL_LOOKUP <- c(
  "Echocardiogram"                  = "echo",
  "Stress test"                     = "stress",
  "Cardiac MRI"                     = "cmri",
  "Multiple gated acquisition (MUGA)" = "muga",
  "PET scan"                        = "pet",
  "CT scan"                         = "ct",
  "Pulmonary function test"         = "pft",
  "Thyroid function"                = "thyroid",
  "CBC"                             = "cbc",
  "BMP"                             = "bmp",
  "CMP"                             = "cmp",
  "LIPID"                           = "lipid",
  "LFT"                             = "lft",
  "KIDNEY"                          = "kidney"
)
```

Resulting columns (per modality): `n_dates_<prefix>` and `n_dates_<prefix>_any`.
Total 28 count columns + `ID`, `hl_anchor_date`, `follow_end`, `person_years`,
`in_confirmed_cohort` = 33 columns.

---

## QC Near-Miss Reporting Format

For each `analyte_min_same_day` or `analyte_all_same_day` rule row, compute the
"near-miss" distribution: ID × dates where ≥1 but < required analytes were present.
Report as a named list / tibble added to the QC sheet:

```
QC_NEAR_MISS: codeset_row_id | modality | rule | n_analytes_required |
              n_days_0_analytes | n_days_1 | n_days_2 | ... | n_days_qualifying
```

One row per rule row. Column `n_days_k` = number of ID × dates where exactly k
distinct analytes were present on that day. `n_days_qualifying` = ID × dates that
became events. This allows the team to see if the threshold is too strict or too loose.

---

## Plan 159-01 — Analyte Table and Codeset Rows (Wave 1)

**Wave:** 1 (no dependencies)
**Files modified:**
- `data/reference/surveillance_codeset.xlsx` (new `Lab_Analytes` sheet; new SC109+ rows in `Analysis_Codeset`)
- `R/utils/utils_surveillance.R` (extend loader and add new match-type constants)
- `tests/testthat/test-159-codeset-loader.R` (new)

### Task 1.1: Build `Lab_Analytes` Sheet

**Files:** `data/reference/surveillance_codeset.xlsx`

**Action:**

Open `lab_code_crosswalk.xlsx` MASTER sheet. For each canonical analyte (see list in
Codeset section above), filter rows by:
1. Exact `component` match (case-insensitive) to the analyte's crosswalk search term.
2. Specimen in D-12 allowlist: `Ser/Plas`, `Ser`, `Plas`, `Ser/Plas/Bld`, `Bld`, `BldV`.
   Exception: EGFR, CYSTATIN_C, URINE_ALBUMIN_CREATININE_RATIO, URINE_PROTEIN —
   include urine specimen codes too (KIDNEY sensitivity per D-11).

Assign `analyte_row_id` as `LA001`, `LA002`, … (sequential, ordered by analyte then
code_system then code). Fill all columns per the `Lab_Analytes` schema above.

Also include single-analyte CPT codes from the crosswalk's CPT rows for the same
analytes (e.g., CPT 82565 = creatinine, 84295 = sodium). These have `cdm_table =
PROCEDURES`, `type_filter = "CH"`.

Flag glucose rows: review for challenge/tolerance variants. Exact-component match
(`component = "Glucose"` not `"Glucose^2H post..."`) should already exclude them, but
confirm in A2 during the HiPerGator run (Section 4 pitfall from brief).

After building the sheet, add it to `surveillance_codeset.xlsx` as sheet `Lab_Analytes`
(last sheet, before Analysis_Codeset is re-written). Do not remove existing sheets.

**Verify:**
- `nrow(Lab_Analytes)` is reported; no duplicate `analyte_row_id` or duplicate `(analyte, code_norm)` pairs
- Every canonical analyte name appears at least once
- No row has a blank `analyte_row_id`, `analyte`, `code`, or `code_norm`

**Acceptance criteria:** Sheet `Lab_Analytes` exists in the workbook, loads without
error via `readxl::read_excel()`, and every canonical analyte name has ≥1 row.

### Task 1.2: Add SC109+ Rows to `Analysis_Codeset`

**Files:** `data/reference/surveillance_codeset.xlsx`

**Action:**

Append rows to `Analysis_Codeset` sheet starting at SC109 for BMP, then CMP, LIPID,
LFT, KIDNEY, following the codeset row numbering table in this plan. For each modality:
1. Panel code rows (exact, primary) — one row per code (CPT + each LOINC).
2. All-analyte rule row (analyte_all_same_day, primary) — `code_norm` = semicolon-joined
   canonical analyte names; `cdm_table` = blank (applies across both tables); `min_analyte_count` = blank.
3. Sensitivity rule row (analyte_min_same_day, sensitivity) — same `code_norm`; fill `min_analyte_count`.

For D-01 nesting: duplicate CMP panel rows (CPT 80053, LOINCs 24322-0/24323-8/45065-0)
under BMP, LFT, and KIDNEY with new SC IDs. Duplicate BMP/CMP panel rows under
KIDNEY. Each duplicate row has the same `code_norm` but a different `codeset_row_id`
and `modality`.

Add two new columns to the sheet if not present: `min_analyte_count` (integer, blank
for non-rule rows) and ensure `match` column allows new values by updating the header
comment on the KEY sheet.

**Verify:**
- `nrow(Analysis_Codeset)` increases by the expected count (count all rows added above)
- No duplicate `codeset_row_id` values in the full sheet
- All new rows have non-blank `codeset_row_id`, `modality`, `code_norm`, `match`, `tier`

**Acceptance criteria:** Loading the updated codeset via the current `load_surveillance_codeset()` does NOT crash on the new rows (even before the loader is extended) — i.e., existing validations pass. Confirmed by running `load_surveillance_codeset()` with the existing code and inspecting the error message for match-value failures (expected; handled in 1.3).

### Task 1.3: Extend `load_surveillance_codeset()` and Add Loader Tests

**Files:** `R/utils/utils_surveillance.R`, `tests/testthat/test-159-codeset-loader.R`

**Action:**

In `R/utils/utils_surveillance.R`:

1. Add `"analyte_all_same_day"` and `"analyte_min_same_day"` to `SURV_MATCH_VALUES`.

2. Add `"Lab_Analytes"` loading to `load_surveillance_codeset()`. The function returns
   a named list instead of a bare tibble: `list(codeset = <tibble>, analytes = <tibble>)`.
   Callers that previously received `codeset` directly are updated in R/147 (Task 3.1).

   ```r
   load_surveillance_codeset <- function(
       path = file.path("data", "reference", "surveillance_codeset.xlsx")) {
     # ... existing Analysis_Codeset load ...
     analytes <- readxl::read_excel(path, sheet = "Lab_Analytes", col_types = "text")
     # validate Lab_Analytes:
     #   required cols: analyte_row_id, analyte, code_system, code, code_norm, cdm_table
     #   no duplicate analyte_row_id
     #   no duplicate (analyte, code_norm)
     #   all analyte names in known set (SURV_KNOWN_ANALYTES constant)
     #   cdm_table in c("LAB_RESULT_CM", "PROCEDURES")
     #   min_analyte_count on analyte_min_same_day rows: integer, < analyte count for that row
     #   every analyte name in analyte_min/all_same_day rule rows exists in Lab_Analytes
     list(codeset = cs, analytes = analytes)
   }
   ```

3. Add constant:
   ```r
   SURV_KNOWN_ANALYTES <- c(
     "SODIUM", "POTASSIUM", "CHLORIDE", "CO2", "BUN", "CREATININE", "GLUCOSE",
     "CALCIUM", "ALBUMIN", "TOTAL_PROTEIN", "ALP", "ALT", "AST", "TOTAL_BILIRUBIN",
     "TOTAL_CHOLESTEROL", "HDL", "TRIGLYCERIDES", "EGFR", "CYSTATIN_C",
     "URINE_ALBUMIN_CREATININE_RATIO", "URINE_PROTEIN"
   )
   ```

4. Validation rules to add:
   - `min_analyte_count` on `analyte_min_same_day` rows: must parse as a positive
     integer that is strictly less than the number of `;`-separated analytes in `code_norm`.
   - Every analyte name in `analyte_all_same_day` / `analyte_min_same_day` rule rows
     (split on `;`) must exist in `Lab_Analytes$analyte`. Stop with: `"Rule row <id>
     references analyte <name> not found in Lab_Analytes"`.
   - No duplicate `analyte_row_id` in `Lab_Analytes`.
   - No duplicate `(analyte, code_norm)` in `Lab_Analytes`.

Create `tests/testthat/test-159-codeset-loader.R` with a synthetic codeset fixture
(in-memory via `writexl::write_xlsx` to a temp file) covering:

- **Test A:** A CPT code stored as a number in Excel (e.g., `80048` not `"80048"`)
  reads back as text `"80048"` after `col_types = "text"`. Confirm `code_norm = "80048"`.
- **Test B:** An unknown analyte name in an `analyte_all_same_day` rule row causes the
  loader to stop with an error mentioning the analyte name.
- **Test C:** A duplicate `code_norm` within the same analyte in `Lab_Analytes` causes
  the loader to stop.
- **Test D:** A valid `Lab_Analytes` sheet with 2 analytes and a valid rule row loads
  without error and returns a list with `$codeset` and `$analytes`.
- **Test E:** A rule row with `min_analyte_count` ≥ the number of analytes in `code_norm`
  (e.g., `min_analyte_count = 8` with 8 analytes) causes the loader to stop (must be
  strictly less than).

**Verify:**
```
Rscript -e "testthat::test_file('tests/testthat/test-159-codeset-loader.R')"
```
All 5 tests pass (no SKIP, no FAIL).

**Acceptance criteria:** Loader returns `list(codeset, analytes)` and all 5 tests pass.

---

## Plan 159-02 — Rule Matching and Per-Patient Table (Wave 2)

**Wave:** 2 (depends on 159-01)
**Files modified:**
- `R/utils/utils_surveillance.R` (new functions)
- `tests/testthat/test-159-surveillance-analytes.R` (new)

### Task 2.1: Implement `build_analyte_events()`

**Files:** `R/utils/utils_surveillance.R`

**Action:**

Add the following function beside `build_component_events()`:

```r
#' Match analyte rule rows (analyte_all_same_day / analyte_min_same_day).
#'
#' @param analyte_long  Tibble with columns: ID, analyte (canonical name),
#'                      event_date (Date). One row per ID x analyte x date.
#'                      Both LAB_RESULT_CM and PROCEDURES rows, already mapped
#'                      from code to analyte via Lab_Analytes.
#' @param rule_rows     Subset of codeset where match %in%
#'                      c("analyte_all_same_day", "analyte_min_same_day").
#'                      Must have: codeset_row_id, modality, tier, match,
#'                      code_norm (semicolon-sep analyte names),
#'                      min_analyte_count (NA for all_same_day rows).
#' @return Named list:
#'   $events     Tibble: codeset_row_id, ID, event_date, modality, tier.
#'               One row per qualifying ID x codeset_row_id x date.
#'   $near_miss  Tibble: codeset_row_id, modality, n_analytes_required,
#'               n_days_0, n_days_1, ..., n_days_<max_k>, n_days_qualifying.
#'               One row per rule_row. Column count varies with max observed k;
#'               use pivot_wider internally.
build_analyte_events <- function(analyte_long, rule_rows) { ... }
```

Implementation notes:
- For each rule row, split `code_norm` on `;` to get the required analyte names.
- For `analyte_all_same_day`: threshold = number of required analytes (all must be present).
- For `analyte_min_same_day`: threshold = `min_analyte_count` (integer from codeset row).
- Count distinct analytes present per ID × date (from `analyte_long`, filtered to the required analytes for that row).
- Days with count ≥ threshold → event. Days with 0 < count < threshold → near-miss.
- Near-miss tibble uses `pivot_wider(names_from = n_analytes, values_from = n_days, names_prefix = "n_days_")`.
- Output `$events` must carry `codeset_row_id` so per-row presence in sheet A is preserved.
- A patient with no analyte results on any date produces no rows in `$events` (not NA rows).

**Verify:** Covered by test suite in Task 2.3.

**Acceptance criteria:** Function exists, is exported, and is called with valid inputs without error on the synthetic fixture.

### Task 2.2: Implement `build_patient_modality_dates()`

**Files:** `R/utils/utils_surveillance.R`

**Action:**

```r
#' Produce the LAB-06 wide per-patient table (D-14, D-15, LAB-06).
#'
#' @param events_long  Tibble: ID, modality, tier, event_date, (event_window).
#'                     From match_coded_events() + build_analyte_events() combined.
#'                     Only post-anchor events (event_window == "post") are counted.
#' @param denom        Tibble: ID, hl_anchor_date, follow_end, person_years,
#'                     in_confirmed_cohort. All denominator patients.
#' @param col_lookup   Named character vector: modality → column prefix.
#'                     Default: MODALITY_COL_LOOKUP (defined in this file).
#' @return Tibble: one row per denom ID (including patients with zero events).
#'         Columns: ID, hl_anchor_date, follow_end, person_years,
#'         in_confirmed_cohort, then for each modality in col_lookup:
#'         n_dates_<prefix> (primary-tier post-anchor distinct dates),
#'         n_dates_<prefix>_any (primary-or-sensitivity post-anchor distinct dates).
#'         Count columns are integer; NA never appears (zeros for missing).
build_patient_modality_dates <- function(events_long, denom,
                                         col_lookup = MODALITY_COL_LOOKUP) { ... }
```

Implementation notes:
- Filter `events_long` to `event_window == "post"` only (D-25, D-14).
- Count distinct `event_date` per ID × modality for primary tier → `n_dates_<prefix>`.
- Count distinct `event_date` per ID × modality where tier %in% c("primary", "sensitivity") → `n_dates_<prefix>_any`.
- Left join denom as the driving table → all denom IDs appear; missing counts → 0L (not NA), via `replace(is.na(.), 0L)` after pivot.
- Column order: ID, hl_anchor_date, follow_end, person_years, in_confirmed_cohort, then modalities in the order they appear in `col_lookup`.
- Use `MODALITY_COL_LOOKUP` constant (defined at file top in this plan).

**Verify:** Covered by test suite in Task 2.3.

**Acceptance criteria:** Function exists. Running it on the synthetic fixture returns the correct number of columns (33) and correct zero-filling.

### Task 2.3: Tests for New Matching Functions

**Files:** `tests/testthat/test-159-surveillance-analytes.R`

**Action:**

Create synthetic in-memory fixture (no file I/O):

```r
# Analytes present on specific dates for two patients
analyte_long <- tibble::tribble(
  ~ID,    ~analyte,    ~event_date,
  "P01",  "SODIUM",    as.Date("2021-03-01"),
  "P01",  "POTASSIUM", as.Date("2021-03-01"),
  "P01",  "CHLORIDE",  as.Date("2021-03-01"),
  "P01",  "CO2",       as.Date("2021-03-01"),
  "P01",  "BUN",       as.Date("2021-03-01"),
  "P01",  "CREATININE",as.Date("2021-03-01"),
  "P01",  "GLUCOSE",   as.Date("2021-03-01"),
  "P01",  "CALCIUM",   as.Date("2021-03-01"),
  # CMP analytes (all BMP + LFT analytes also here → nesting)
  "P01",  "ALBUMIN",   as.Date("2021-03-01"),
  "P01",  "TOTAL_PROTEIN", as.Date("2021-03-01"),
  "P01",  "ALP",       as.Date("2021-03-01"),
  "P01",  "ALT",       as.Date("2021-03-01"),
  "P01",  "AST",       as.Date("2021-03-01"),
  "P01",  "TOTAL_BILIRUBIN", as.Date("2021-03-01"),
  # P02: only 7 BMP analytes (near-miss for BMP primary; sensitivity tier)
  "P02",  "SODIUM",    as.Date("2021-06-15"),
  "P02",  "POTASSIUM", as.Date("2021-06-15"),
  "P02",  "CHLORIDE",  as.Date("2021-06-15"),
  "P02",  "CO2",       as.Date("2021-06-15"),
  "P02",  "BUN",       as.Date("2021-06-15"),
  "P02",  "CREATININE",as.Date("2021-06-15"),
  "P02",  "GLUCOSE",   as.Date("2021-06-15"),
  # P03: no analyte results at all
)
```

Tests:

- **Test 1 — CMP day counts as BMP under nesting:** P01 on 2021-03-01 qualifies for both
  the CMP all-analyte row and the BMP all-analyte row. `$events` has at least one row for
  P01 under BMP and one under CMP on that date.
- **Test 2 — Partial BMP is sensitivity, not primary:** P02 has 7 of 8 BMP analytes on
  2021-06-15. The BMP `analyte_all_same_day` row does NOT generate a P02 event. The BMP
  `analyte_min_same_day` row (min=4) DOES generate a P02 event.
- **Test 3 — Dual-table deduplication:** Construct a second `analyte_long` where P01 on
  2021-03-01 also has CREATININE from a PROCEDURES row. After mapping to analyte name,
  CREATININE appears twice for P01 on that date. `build_analyte_events()` counts it once
  (distinct analyte, not distinct source row).
- **Test 4 — Patient with no events has zeros:** P03 has no rows in `analyte_long`. After
  `build_patient_modality_dates()` with a denom that includes P03, P03 has a row with
  `n_dates_bmp = 0L` and `n_dates_bmp_any = 0L` (integer zeros, not NA).
- **Test 5 — Column names follow fixed lookup:** Output of `build_patient_modality_dates()`
  contains columns named `n_dates_bmp`, `n_dates_bmp_any`, `n_dates_cmp`, `n_dates_cmp_any`,
  etc., based on `MODALITY_COL_LOOKUP`. Column `n_dates_muga` exists (from Phase 158 modality).
- **Test 6 — Near-miss reporting:** P02 (7 of 8 BMP analytes) appears in `$near_miss` for the
  BMP primary row under `n_days_7 = 1`. `n_days_qualifying` for BMP primary row is 0 (P02
  not a primary event). `n_days_qualifying` for BMP sensitivity row is 1.
- **Test 7 — Primary dates ≤ any-tier dates:** `stopifnot(all(out$n_dates_bmp <= out$n_dates_bmp_any))`.

**Verify:**
```
Rscript -e "testthat::test_file('tests/testthat/test-159-surveillance-analytes.R')"
```
All 7 tests pass.

**Acceptance criteria:** All 7 tests pass; no SKIP; execution time < 30 seconds.

---

## Plan 159-03 — R/147 Changes (Wave 3)

**Wave:** 3 (depends on 159-01, 159-02)
**Files modified:**
- `R/147_surveillance_modality_frequency.R`

### Task 3.1: Analyte Pull (DuckDB Push-Down, L-6)

**Files:** `R/147_surveillance_modality_frequency.R`

**Action:**

Add a new section (SECTION 4B, after the existing LAB_RESULT_CM pull) to pull analyte
data for the five new modalities. This is the highest-volume query in the script.

```r
# SECTION 4B: ANALYTE PULL (LAB-01..LAB-03; L-6 push-down) ----
# Collect DISTINCT ID x code x raw_date from LAB_RESULT_CM and PROCEDURES,
# restricted to HL-denominator IDs and the analyte codes in Lab_Analytes.

analyte_codes <- surv_codeset$analytes  # from updated loader (list return)

# Lab LOINC analyte codes
lab_analyte_codes <- analyte_codes |>
  dplyr::filter(cdm_table == "LAB_RESULT_CM") |>
  dplyr::pull(code_norm) |>
  unique()

# CPT analyte codes (single-analyte CPTs, e.g. 82565, 84295)
proc_analyte_codes <- analyte_codes |>
  dplyr::filter(cdm_table == "PROCEDURES") |>
  dplyr::pull(code_norm) |>
  unique()
```

Push `DISTINCT ID, code, raw_date` to DuckDB before `collect()`, using
`surv_code_where()` for the IN clause and the existing HL-ID temp table semi-join
(D-29). Parse dates after `collect()` with `parse_pcornet_date()` (D-28).

After collect, join `analyte_codes` (by `code_norm`) to map each result row to its
canonical `analyte` name. Then bind LAB_RESULT_CM rows and PROCEDURES rows into a
single `analyte_long` tibble: `ID, analyte, event_date`.

Call `compute_followup()` + `classify_event_window()` on the analyte pull before
passing to `build_analyte_events()`. Filter to `event_window == "post"` for counting.

Update the existing `surv_codeset` variable to use the new list return:
```r
surv_codeset_all <- load_surveillance_codeset()
codeset   <- surv_codeset_all$codeset   # was: codeset <- load_surveillance_codeset()
analytes  <- surv_codeset_all$analytes
```

Update the D-18 check:
```r
stopifnot("A rows must equal codeset rows (D-18)" =
            nrow(A_code_presence) == nrow(codeset))
```

**Verify:** Script sources without error on a dry run with an empty-result stub.
The analyte pull section executes and returns a zero-row `analyte_long` when no HL IDs
match (guard against crashing on empty pull).

**Acceptance criteria:** `source("R/147_surveillance_modality_frequency.R")` up to
end of SECTION 4B without error. `analyte_long` tibble exists with correct columns.

### Task 3.2: Wire Analyte Events into Output Sheets (A, A2, E)

**Files:** `R/147_surveillance_modality_frequency.R`

**Action:**

After SECTION 4B, add SECTION 7B:

```r
# SECTION 7B: ANALYTE EVENTS AND WIDE TABLE (LAB-03..LAB-06) ----

# Identify analyte rule rows from the codeset
analyte_rule_rows <- codeset |>
  dplyr::filter(match %in% c("analyte_all_same_day", "analyte_min_same_day"))

# Build analyte events (returns list: $events, $near_miss)
analyte_result <- build_analyte_events(
  analyte_long    = analyte_long,
  rule_rows       = analyte_rule_rows
)

# Combine with coded events for A_code_presence and frequency sheets
# coded_events already exists from SECTION 7 (match_coded_events output)
all_events <- dplyr::bind_rows(
  coded_events,
  analyte_result$events
)
```

Extend `build_code_presence()` call (sheet A) to include analyte rule rows. Confirm
`nrow(A_code_presence) == nrow(codeset)` includes the new rows.

**A2_analyte_presence sheet:** one row per `Lab_Analytes` row. Compute from
`analyte_long` (all windows, not just post-anchor, so the team sees total data coverage):

```r
A2_analyte_presence <- analytes |>
  dplyr::left_join(
    analyte_long |>
      dplyr::group_by(analyte) |>
      dplyr::summarise(
        n_results  = dplyr::n(),
        n_patients = dplyr::n_distinct(ID),
        first_date = min(event_date, na.rm = TRUE),
        last_date  = max(event_date, na.rm = TRUE),
        .groups = "drop"),
    by = "analyte"
  ) |>
  dplyr::mutate(
    n_results  = dplyr::coalesce(n_results,  0L),
    n_patients = dplyr::coalesce(n_patients, 0L),
    present    = n_results > 0
  )
```

Note: `n_results` and `n_patients` are per `analyte` (grouped), not per
`analyte_row_id`, because the Lab_Analytes table can have multiple codes per analyte.

**E_patient_modality_dates sheet (INTERNAL only):**

```r
patient_wide <- build_patient_modality_dates(
  events_long = all_events |>
    dplyr::filter(event_window == "post"),
  denom       = denom_all
)
```

Write `patient_wide` as:
- `surveillance_patient_modality_dates_<run_date>.rds` (HiPerGator only)
- `surveillance_patient_modality_dates_<run_date>.csv`
- Sheet `E_patient_modality_dates` in INTERNAL workbook only (do NOT add to release workbook)

**Workbook sheet order** (D-18 from 159-CONTEXT):
- INTERNAL: KEY, A_code_presence, A2_analyte_presence, B_modality_primary, C_modality_with_sensitivity, D_pre_vs_post_anchor, E_patient_modality_dates, QC
- Release: KEY, A_code_presence, A2_analyte_presence, B_modality_primary, C_modality_with_sensitivity, D_pre_vs_post_anchor, QC

**QC sheet additions:** Append the near-miss table from `analyte_result$near_miss` as
a second block in the QC sheet, after the existing QC content. Label it
`"=== LAB Analyte Near-Miss (D-09 thresholds) ==="`.

**Five success criterion `stopifnot`s** (from brief, add after all events are computed):
```r
# SC-4: B n_patients matches patient_wide positive count, per modality
# SC-5: primary dates <= any-tier dates, per ID x modality
stopifnot(all(
  purrr::map_lgl(names(MODALITY_COL_LOOKUP), function(m) {
    pfx <- MODALITY_COL_LOOKUP[[m]]
    all(patient_wide[[paste0("n_dates_", pfx)]] <=
        patient_wide[[paste0("n_dates_", pfx, "_any")]])
  })
))
# SC-6: CMP primary dates <= BMP primary dates, per ID (nesting check)
stopifnot(all(patient_wide$n_dates_cmp <= patient_wide$n_dates_bmp))
```

**Verify:**
```
Rscript -e "source('R/00_config.R'); source('R/utils/utils_surveillance.R');
  source('R/utils/utils_treatment.R'); message('Sections 7B source OK')"
```

**Acceptance criteria:** Script runs to completion on HiPerGator without error. Three
output files are produced. INTERNAL workbook contains sheets A2 and E. Release workbook
does not contain sheet E. All `stopifnot` checks pass.

---

## Plan 159-04 — Registration and HiPerGator Run (Wave 4)

**Wave:** 4 (depends on 159-03)
**Files modified:**
- `R/88_run_validation_checks.R`
- `SCRIPT_INDEX` (or `SCRIPT_INDEX.md` — confirm filename by checking `ls R/ | grep -i script`)
- `data/reference/README.md`

### Task 4.1: Extend R/88 Validation Section

**Files:** `R/88_run_validation_checks.R`

**Action:**

Find the existing Phase 158 section in R/88. Add immediately after it:

```r
# ---- Phase 159: Lab modalities (LAB-01..LAB-07) ----
message("  [159] Lab_Analytes sheet exists and loads")
surv_all_159 <- load_surveillance_codeset()
stopifnot(
  "Lab_Analytes sheet missing" = !is.null(surv_all_159$analytes),
  "Lab_Analytes has zero rows" = nrow(surv_all_159$analytes) > 0,
  "Lab_Analytes: duplicate analyte_row_id" =
    !anyDuplicated(surv_all_159$analytes$analyte_row_id)
)

message("  [159] Five new modalities present in codeset")
new_modalities <- c("BMP", "CMP", "LIPID", "LFT", "KIDNEY")
present <- unique(surv_all_159$codeset$modality)
missing_mod <- setdiff(new_modalities, present)
if (length(missing_mod) > 0)
  stop("Missing modalities in codeset: ", paste(missing_mod, collapse = ", "))

message("  [159] Each new modality has panel, all-analyte, and any-analyte rows")
for (m in new_modalities) {
  rows <- surv_all_159$codeset |> dplyr::filter(modality == m)
  has_exact   <- any(rows$match == "exact")
  has_all     <- any(rows$match == "analyte_all_same_day")
  has_min     <- any(rows$match == "analyte_min_same_day")
  if (!has_exact || !has_all || !has_min)
    stop(glue::glue("Modality {m} missing panel/all-analyte/any-analyte rows"))
}

message("  [159] build_analyte_events and build_patient_modality_dates exist")
stopifnot(
  exists("build_analyte_events",       where = "package:base",  inherits = TRUE) ||
  exists("build_analyte_events",       envir = globalenv(),     inherits = TRUE),
  exists("build_patient_modality_dates", envir = globalenv(),   inherits = TRUE)
)
```

Note: because `utils_surveillance.R` is sourced before R/88 checks run, use
`exists("build_analyte_events", inherits = TRUE)` rather than a package check.
Adjust the pattern to match how R/88 sources utils files.

**Verify:** `Rscript R/88_run_validation_checks.R` passes the Phase 159 section
without SKIP or FAIL. Confirm by running on HiPerGator after SLURM job completes.

**Acceptance criteria:** R/88 Phase 159 section exits cleanly (no `stop()` triggered).

### Task 4.2: Update SCRIPT_INDEX and README

**Files:** `SCRIPT_INDEX` (confirm exact filename), `data/reference/README.md`

**Action:**

In SCRIPT_INDEX, find the R/147 entry and update Outputs to include:
- `surveillance_patient_modality_dates_<date>.rds`
- `surveillance_patient_modality_dates_<date>.csv`

And update Requirements to include `LAB-01..LAB-07` alongside existing `SURV-01..SURV-06`.

In `data/reference/README.md`, add entries for:
- `surveillance_codeset.xlsx` — note that `Lab_Analytes` sheet is new in Phase 159
- `lab_code_crosswalk.xlsx` — note that it is the LOINC dictionary source for Phase 159

If README already mentions `lab_code_crosswalk.xlsx`, update its entry; do not add a
duplicate.

**Verify:**
```
grep -i "LAB-01" SCRIPT_INDEX
grep -i "Lab_Analytes" data/reference/README.md
```
Both commands return at least one match.

**Acceptance criteria:** Both files updated. R/147 entry reflects new outputs and requirements.

### Task 4.3: HiPerGator Checkpoint — Run and Review

**Type:** `checkpoint:human-verify`

**What was built (automated in plans 01-03):**
- `Lab_Analytes` sheet in `surveillance_codeset.xlsx`
- SC109+ rows in `Analysis_Codeset`
- New matching functions in `utils_surveillance.R`
- Extended R/147 producing A2, E, and patient-wide table
- Extended R/88 validation

**How to verify:**

1. On HiPerGator, run the test suite:
   ```bash
   module load R/4.4.2
   Rscript -e "testthat::test_dir('tests/testthat/', filter = '159')"
   ```
   All tests pass.

2. Run R/88:
   ```bash
   Rscript R/88_run_validation_checks.R 2>&1 | grep -E "\[159\]|FAIL|stop"
   ```
   Phase 159 section shows 4 `[159]` message lines, no FAIL.

3. Run R/147 (SLURM or interactive):
   ```bash
   Rscript R/147_surveillance_modality_frequency.R
   ```

4. Open the INTERNAL workbook:
   - Sheet order: KEY, A_code_presence, A2_analyte_presence, B, C, D, E_patient_modality_dates, QC
   - A2 has one row per `Lab_Analytes` row; check `present` column. Review glucose rows first.
   - E has one row per denominator patient; no NA in count columns.
   - QC has a near-miss block for BMP, CMP, LFT, LIPID, KIDNEY rule rows.

5. Open the release workbook:
   - No sheet E (patient-level data absent).
   - Cells 1-10 are suppressed to `"<11"` in B/C/D.

6. Check KEY sheet note: "BMP, CMP, LFT, and KIDNEY modality counts are not additive
   (nested). A CMP day also counts as a BMP, LFT, and KIDNEY day. KIDNEY primary
   counts will be at least as high as BMP primary counts."

7. Confirm SC-6: for all patients, CMP primary date count ≤ BMP primary date count
   (nesting sanity; should have been caught by `stopifnot` but eyeball the range in sheet E).

**Resume signal:** Type "approved" or describe any issues found.

---

## Success Criteria

All seven LAB requirements are met when:

1. **LAB-01:** `Lab_Analytes` sheet loads without error. Every canonical analyte has ≥1 code row. No duplicate `analyte_row_id` or `(analyte, code_norm)`.
2. **LAB-02:** `nrow(A_code_presence) == nrow(codeset)` — one A row per codeset row, including all new SC109+ rows. Each of the five modalities has panel (exact), all-analyte, and any-analyte rows.
3. **LAB-03:** All 7 analyte-matching tests pass. QC near-miss block present in INTERNAL workbook. Events carry `codeset_row_id`.
4. **LAB-04:** A2_analyte_presence has one row per `Lab_Analytes` row. `present` column reflects actual extract coverage.
5. **LAB-05:** BMP, CMP, LIPID, LFT, KIDNEY appear in B and C sheets with non-zero `n_patients` (assuming any qualifying lab results in extract).
6. **LAB-06:** Per-patient wide table has exactly one row per denominator ID, no NA counts, 33 columns. `stopifnot` checks SC-5 and SC-6 pass.
7. **LAB-07:** R/88 Phase 159 section passes. SCRIPT_INDEX and README updated. Outputs issued from HiPerGator run.
