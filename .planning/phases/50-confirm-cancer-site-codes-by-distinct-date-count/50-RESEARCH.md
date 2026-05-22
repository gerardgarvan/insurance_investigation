# Phase 3: Confirm Cancer Site Codes by Distinct Date Count - Research

**Researched:** 2026-05-19
**Domain:** R data manipulation, epidemiological validation, ICD-10 cancer site classification
**Confidence:** HIGH

## Summary

Phase 3 implements a standard epidemiological validation pattern — requiring at least 2 distinct dates with the same diagnosis code before counting it as "confirmed." This filters out potential rule-out diagnoses or data entry errors. The implementation extends R/47's cancer site frequency analysis with a date-based confirmation filter applied at two levels: exact ICD-10 code matching and 3-character prefix matching.

The technical foundation is solid: dplyr's `n_distinct()` combined with `group_by()` provides efficient distinct-date counting, R/47 already has the 53-category PREFIX_MAP and classification logic, and openxlsx2 patterns are established in R/47. The confirmation logic is a straightforward filter: count distinct DX_DATE values per patient per code, keep only those with count >= 2.

**Primary recommendation:** Reuse R/47's PREFIX_MAP, classify_codes(), and xlsx styling patterns. Add DX_DATE to the DIAGNOSIS query, compute confirmation at both exact-code and prefix levels using nested group_by + filter operations, output a two-sheet xlsx comparing total vs confirmed counts.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Code Matching Level:**
- **D-01:** Run confirmation at TWO levels: (1) exact ICD-10 code (e.g., C81.10 must appear on 2+ distinct dates), and (2) 3-character prefix (e.g., any C81.* code on 2+ distinct dates confirms C81). Both levels are computed and reported.
- **D-02:** Output is one xlsx workbook with two sheets — Sheet 1 for exact code confirmation, Sheet 2 for prefix-level confirmation. Easy side-by-side comparison.

**Data Sources:**
- **D-03:** DIAGNOSIS table only. Use DX_DATE as the date for distinct-date counting. TUMOR_REGISTRY entries are already registrar-confirmed and do not need date-based validation.
- **D-04:** Only ICD-10 codes (DX_TYPE == "10") — consistent with R/47's DIAGNOSIS query.

**Output Format:**
- **D-05:** Per cancer site category: total_patients, confirmed_patients, unconfirmed_patients, confirmation_rate. Shows the impact of the confirmation filter at a glance.
- **D-06:** Only show populated categories (those with at least one patient). No zero-count rows.
- **D-07:** Styled xlsx output following established openxlsx2 patterns from prior phases.

**Script Structure:**
- **D-08:** New script (R/50_*.R or next available number). R/47 stays as the unfiltered baseline. New script reuses R/47's PREFIX_MAP and classify_codes() logic but adds the confirmation filter.

### Claude's Discretion

- Exact script numbering (next available R/NN_*.R)
- Whether to source PREFIX_MAP from R/47 directly or duplicate/extract to a shared location
- Column ordering and xlsx styling details
- Whether to include a summary row at the bottom of each sheet

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | `n_distinct()` + `group_by()` is the standard pattern for distinct-date counting; readable syntax for nested filtering |
| tidyverse | 2.0.0+ | Ecosystem | Includes dplyr, stringr, lubridate; already loaded in all project scripts |
| openxlsx2 | 1.18.2+ | Styled xlsx output | Project standard for multi-sheet xlsx with header styling, frozen panes, auto column widths |
| glue | 1.8.0 | String formatting | Readable logging messages with embedded expressions; project standard |
| DuckDB | via utils_duckdb.R | Data access | `get_pcornet_table("DIAGNOSIS")` accessor pattern established in R/47 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | 1.5.1+ | String operations | `str_remove_all()` for ICD code normalization (remove dots) — already in R/47 |
| lubridate | 1.9.3+ | Date operations | If date validation/filtering needed (DX_DATE parsing, NA handling) |
| scales | 1.3.0+ | Number formatting | Format percentages for confirmation_rate column; format large numbers with commas |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| dplyr | data.table | 10-50x faster but opaque syntax conflicts with project's "named predicate" requirement |
| openxlsx2 | writexl | Simpler but no styling support — project requires styled output per D-07 |
| Separate script | Modify R/47 | Would lose unfiltered baseline — D-08 explicitly requires new script |

**Installation:**

All libraries already installed in project renv environment. No new dependencies required.

**Version verification:** Project uses renv with locked versions in renv.lock. All core libraries already present and version-verified during Phase 45-47 work.

## Architecture Patterns

### Recommended Project Structure

```
R/
├── 47_cancer_site_frequency.R    # Unfiltered baseline (KEEP unchanged)
├── 50_*.R                        # New: Confirmed cancer sites (this phase)
├── utils_icd.R                   # normalize_icd() helper
├── utils_duckdb.R                # get_pcornet_table() accessor
└── 00_config.R                   # Optional: extract PREFIX_MAP here if sharing grows
```

### Pattern 1: Distinct Date Confirmation Filter

**What:** Count distinct dates per patient per code, filter to those with count >= 2

**When to use:** Epidemiological validation requiring temporal persistence (rule out single-encounter diagnoses)

**Example:**

```r
# Source: dplyr documentation + R/44 patterns
# https://dplyr.tidyverse.org/reference/n_distinct.html

# Exact code level: Patient must have same exact code on 2+ distinct dates
dx_exact_confirmed <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  group_by(ID, DX_norm) %>%
  filter(n_distinct(DX_DATE) >= 2) %>%
  ungroup()

# Prefix level: Patient must have same 3-char prefix on 2+ distinct dates
dx_prefix_confirmed <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  mutate(prefix3 = substr(DX_norm, 1, 3)) %>%
  group_by(ID, prefix3) %>%
  filter(n_distinct(DX_DATE) >= 2) %>%
  ungroup()
```

### Pattern 2: Reusing R/47 Classification Logic

**What:** Source PREFIX_MAP and classify_codes() from R/47 without modification

**When to use:** When extending existing analysis without changing baseline logic

**Example:**

```r
# Source: R/47_cancer_site_frequency.R lines 39-382

# Option 1: Duplicate PREFIX_MAP and classify_codes() in new script
# (RECOMMENDED for v1 — keeps scripts independent)

PREFIX_MAP <- c(
  "C00" = "Lip, Oral Cavity and Pharynx",
  "C15" = "Esophagus",
  # ... (full 308-line map from R/47)
)

classify_codes <- function(codes) {
  prefix3 <- substr(codes, 1, 3)
  categories <- unname(PREFIX_MAP[prefix3])
  categories
}

# Option 2: Source from R/47 (creates dependency)
# source("R/47_cancer_site_frequency.R")
# (NOT RECOMMENDED — would execute full R/47 script)

# Option 3: Extract to shared utility (future refactoring)
# source("R/utils_cancer_classification.R")
# (OUT OF SCOPE for v1 — consider if 3+ scripts need this)
```

### Pattern 3: Two-Sheet Comparison XLSX

**What:** One workbook with Sheet 1 (exact code confirmation) and Sheet 2 (prefix confirmation)

**When to use:** Comparing multiple aggregation levels of the same validation logic

**Example:**

```r
# Source: R/47_cancer_site_frequency.R lines 597-694

wb <- wb_workbook()

# Sheet 1: Exact Code Confirmation
wb$add_worksheet("Exact Code")
headers1 <- c("Cancer Site Category", "Total Patients", "Confirmed Patients",
              "Unconfirmed Patients", "Confirmation Rate")
# ... add data, styling, freeze panes

# Sheet 2: Prefix Confirmation
wb$add_worksheet("Prefix Level")
headers2 <- c("Cancer Site Category", "Total Patients", "Confirmed Patients",
              "Unconfirmed Patients", "Confirmation Rate")
# ... add data, styling, freeze panes

wb$save("output/tables/cancer_site_confirmation.xlsx")
```

### Anti-Patterns to Avoid

- **Don't count records — count patients:** `n_distinct(ID)` not `n()` when computing total_patients and confirmed_patients
- **Don't forget NA date handling:** `filter(!is.na(DX_DATE))` before `n_distinct(DX_DATE)` or you'll count NA as a "date"
- **Don't mix confirmation levels:** Exact-code confirmation and prefix confirmation are separate analyses — don't try to combine them in one step
- **Don't modify R/47:** D-08 requires new script; R/47 is the unfiltered baseline reference

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Distinct date counting | Manual loop through patients, track dates in list | `group_by(ID, code) %>% filter(n_distinct(date) >= 2)` | dplyr handles all edge cases (NA, grouping, memory efficiency); loop would be 100+ lines and slower |
| ICD prefix extraction | Regex patterns, str_match, if_else chains | `substr(code, 1, 3)` | 3-char prefix is fixed-width; substr is fastest and clearest |
| XLSX styling | Write CSV, manually format in Excel | openxlsx2 wb_add_fill, wb_add_font, freeze_pane | Project standard; reproducible; R/47 already has working pattern |
| Confirmation rate calculation | Custom percentage function | `mutate(confirmation_rate = confirmed_patients / total_patients)` with scales::percent() | Built-in division handles NA/divide-by-zero gracefully; scales formats for output |

**Key insight:** Confirmation logic is fundamentally a filter-after-count operation — dplyr's `group_by() + filter(n_distinct(...) >= threshold)` pattern is the idiomatic solution. Manual date tracking in loops is a 10x complexity increase with no benefit.

## Common Pitfalls

### Pitfall 1: Counting NA as a Distinct Date

**What goes wrong:** `n_distinct(DX_DATE)` counts NA as a unique value, so a patient with one real date and one NA date gets count=2 and passes confirmation

**Why it happens:** R's `unique()` and `n_distinct()` treat NA as a distinct value by default

**How to avoid:** Filter out NA dates BEFORE the group_by + n_distinct operation:

```r
# WRONG: NA counted as distinct date
dx_confirmed <- dx_cancer %>%
  group_by(ID, DX_norm) %>%
  filter(n_distinct(DX_DATE) >= 2)  # Includes NA!

# CORRECT: Remove NA before counting
dx_confirmed <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  group_by(ID, DX_norm) %>%
  filter(n_distinct(DX_DATE) >= 2)
```

**Warning signs:** Confirmation rate suspiciously high (>95%); manual inspection shows patients with only 1 real date being confirmed

### Pitfall 2: Prefix Confirmation Logic Confusion

**What goes wrong:** Counting "2+ distinct dates with any C81.* code" is not the same as "2+ distinct dates with C81.10 plus 2+ distinct dates with C81.20" — patient needs 2+ dates with ANY code in the prefix family, not 2+ dates per specific code

**Why it happens:** Misunderstanding the epidemiological logic — prefix confirmation is about "this cancer site appeared multiple times" not "each specific code appeared multiple times"

**How to avoid:** Group by (ID, prefix) not (ID, DX_norm) for prefix-level confirmation:

```r
# WRONG: Requires 2+ dates per exact code, then aggregates to prefix
dx_prefix <- dx_cancer %>%
  group_by(ID, DX_norm) %>%
  filter(n_distinct(DX_DATE) >= 2) %>%
  mutate(prefix3 = substr(DX_norm, 1, 3))

# CORRECT: Group by prefix first, then count distinct dates across all codes in prefix
dx_prefix <- dx_cancer %>%
  mutate(prefix3 = substr(DX_norm, 1, 3)) %>%
  group_by(ID, prefix3) %>%
  filter(n_distinct(DX_DATE) >= 2)
```

**Warning signs:** Prefix confirmation counts much lower than expected; patient with C81.10 on day 1 and C81.20 on day 2 marked unconfirmed

### Pitfall 3: Forgetting to Remove Duplicates Before Confirmation

**What goes wrong:** If a patient has multiple DIAGNOSIS records with same ID, same DX_norm, same DX_DATE (from different encounters or table structure), they get counted as 1 distinct date. But if you don't deduplicate, you'll incorrectly compute statistics later.

**Why it happens:** DIAGNOSIS table may have duplicate (ID, DX, DX_DATE) tuples from different encounters with same diagnosis

**How to avoid:** Use `distinct(ID, DX_norm, DX_DATE)` BEFORE counting distinct dates:

```r
# RECOMMENDED: Explicit distinct() for clarity
dx_clean <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  distinct(ID, DX_norm, DX_DATE) %>%  # Remove duplicate (ID, code, date) rows
  group_by(ID, DX_norm) %>%
  filter(n_distinct(DX_DATE) >= 2)

# NOTE: In practice, n_distinct() handles duplicates automatically,
# but explicit distinct() makes the deduplication visible and prevents
# downstream issues when joining or aggregating
```

**Warning signs:** Record counts don't match patient counts in unexpected ways; manual inspection shows multiple identical (ID, code, date) rows

### Pitfall 4: Divide-by-Zero in Confirmation Rate

**What goes wrong:** Category has 0 total_patients (shouldn't happen per D-06, but could happen if logic is wrong) → confirmation_rate becomes NaN

**Why it happens:** `confirmed / 0 = NaN` in R

**How to avoid:** Filter out zero-count categories BEFORE computing rate, per D-06:

```r
# Filter populated categories first (D-06)
summary_exact <- dx_exact_summary %>%
  filter(total_patients > 0) %>%
  mutate(
    unconfirmed_patients = total_patients - confirmed_patients,
    confirmation_rate = confirmed_patients / total_patients
  )
```

**Warning signs:** NA or NaN in confirmation_rate column; categories with 0 total_patients appearing in output

### Pitfall 5: Confirmation Filter Removes All Categories from Classification

**What goes wrong:** After confirmation filter, `classify_codes()` is called on the filtered data, but categories with 0 confirmed patients still appear in the output with NA counts

**Why it happens:** `classify_codes()` returns category names for all codes, but if no patients remain after confirmation, the category still appears in the output with NA or 0

**How to avoid:** Classify BEFORE confirmation, then aggregate separately for total and confirmed:

```r
# CORRECT: Classify once on full data, then compute two aggregations
dx_cancer <- dx_cancer %>%
  mutate(
    DX_norm = normalize_icd(DX),
    category = classify_codes(DX_norm)
  )

# Total patients per category (before confirmation)
total_by_cat <- dx_cancer %>%
  group_by(category) %>%
  summarise(total_patients = n_distinct(ID), .groups = "drop")

# Confirmed patients per category (after confirmation filter)
confirmed_by_cat <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  group_by(ID, DX_norm) %>%
  filter(n_distinct(DX_DATE) >= 2) %>%
  ungroup() %>%
  group_by(category) %>%
  summarise(confirmed_patients = n_distinct(ID), .groups = "drop")

# Join and compute rates
summary <- total_by_cat %>%
  left_join(confirmed_by_cat, by = "category") %>%
  mutate(
    confirmed_patients = replace_na(confirmed_patients, 0),
    unconfirmed_patients = total_patients - confirmed_patients,
    confirmation_rate = confirmed_patients / total_patients
  ) %>%
  filter(total_patients > 0)  # D-06: Only populated categories
```

## Code Examples

Verified patterns from official sources and project codebase:

### Distinct Date Counting with dplyr

```r
# Source: dplyr official documentation
# https://dplyr.tidyverse.org/reference/n_distinct.html

# Count distinct dates per patient per code
dx_date_counts <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  group_by(ID, DX_norm) %>%
  summarise(
    n_dates = n_distinct(DX_DATE),
    .groups = "drop"
  )

# Filter to confirmed (2+ dates)
dx_confirmed <- dx_date_counts %>%
  filter(n_dates >= 2)
```

### ICD Code Normalization and Classification

```r
# Source: R/47_cancer_site_frequency.R lines 398-409, R/utils_icd.R lines 36-44

# Normalize ICD codes (remove dots, uppercase)
normalize_icd <- function(icd_code) {
  toupper(str_remove_all(icd_code, "\\."))
}

# Classify codes by 3-char prefix
classify_codes <- function(codes) {
  prefix3 <- substr(codes, 1, 3)
  categories <- unname(PREFIX_MAP[prefix3])
  categories
}

# Usage
dx_cancer <- dx_icd10 %>%
  mutate(
    DX_norm = normalize_icd(DX),
    category = classify_codes(DX_norm)
  )
```

### Styled XLSX with openxlsx2

```r
# Source: R/47_cancer_site_frequency.R lines 597-694

DARK_HEADER_FILL <- "FF374151"
WHITE_FONT       <- "FFFFFFFF"

wb <- wb_workbook()
wb$add_worksheet("Exact Code")

# Headers
headers <- c("Cancer Site Category", "Total Patients", "Confirmed Patients",
             "Unconfirmed Patients", "Confirmation Rate")
for (i in seq_along(headers)) {
  wb$add_data(sheet = "Exact Code", x = headers[i], start_row = 1, start_col = i)
}

# Header styling
wb$add_fill(sheet = "Exact Code", dims = "A1:E1", color = wb_color(DARK_HEADER_FILL))
wb$add_font(sheet = "Exact Code", dims = "A1:E1",
            name = "Calibri", size = 11, bold = TRUE,
            color = wb_color(WHITE_FONT))

# Freeze header row
wb$freeze_pane(sheet = "Exact Code", first_active_row = 2, first_active_col = 1)

# Data (starting row 2)
wb$add_data(sheet = "Exact Code", x = as.data.frame(summary_data),
            start_row = 2, col_names = FALSE)

# Number formatting
wb$add_numfmt(sheet = "Exact Code", dims = "B2:D100", numfmt = "#,##0")
wb$add_numfmt(sheet = "Exact Code", dims = "E2:E100", numfmt = "0.0%")

# Auto column widths
wb$set_col_widths(sheet = "Exact Code", cols = 1:5, widths = c(42, 14, 16, 18, 16))

wb$save("output/tables/cancer_site_confirmation.xlsx")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual date counting in loops | `n_distinct()` in dplyr | dplyr 1.0+ (2020) | 10x less code, handles NA/edge cases automatically |
| openxlsx (original package) | openxlsx2 | openxlsx2 stable 2025 | Faster, better memory handling, active maintenance |
| Base R substr() for prefix | stringr::str_sub() | N/A | substr() is still fastest for fixed-width extraction; stringr adds no value here |
| Percentage as numeric | scales::percent() for formatting | scales 1.0+ | Readable output formatting; automatic handling of NA |

**Deprecated/outdated:**

- openxlsx (original): Maintenance transferred to openxlsx2 in 2025; project already uses openxlsx2
- Manual `n_distinct()` implementation with `length(unique())`: dplyr's `n_distinct()` is optimized and handles edge cases better

## Open Questions

1. **Should PREFIX_MAP be extracted to a shared utility?**
   - What we know: R/47 has 308 lines of PREFIX_MAP definition; duplicate in new script adds 308 lines; only 2 scripts currently use it
   - What's unclear: Will Phase 4 (7-day separation) also use it? Will future analyses need it?
   - Recommendation: Duplicate in v1 for script independence. If 3+ scripts need it, refactor to R/utils_cancer_classification.R in future quick task

2. **Should confirmation_rate be formatted as percentage or decimal?**
   - What we know: R/47 uses numeric counts only (no rates); scales::percent() formats as "45.2%"; raw decimal is 0.452
   - What's unclear: User preference not specified in CONTEXT.md
   - Recommendation: Use percentage format (scales::percent()) for readability — matches typical epidemiological reporting. If user wants decimal, it's a one-line change to number format string

3. **Should summary totals row be included at bottom of each sheet?**
   - What we know: R/47 includes "TOTAL" rows (lines 647-661); marked as Claude's Discretion in CONTEXT.md
   - What's unclear: Whether totals make sense for confirmation analysis (confirmation rate across all categories is not meaningful)
   - Recommendation: Include totals for patient counts (total_patients, confirmed_patients, unconfirmed_patients) but omit confirmation_rate for totals row (label as "N/A" or leave blank)

## Sources

### Primary (HIGH confidence)

- [dplyr n_distinct() documentation](https://dplyr.tidyverse.org/reference/n_distinct.html) - Distinct value counting
- [dplyr count() documentation](https://dplyr.tidyverse.org/reference/count.html) - Group counting patterns
- [openxlsx2 CRAN manual](https://cran.r-project.org/web/packages/openxlsx2/openxlsx2.pdf) - April 2026 reference
- [openxlsx2 official site](https://janmarvin.github.io/openxlsx2/) - Package documentation
- R/47_cancer_site_frequency.R (project codebase) - PREFIX_MAP, classify_codes(), xlsx patterns
- R/utils_icd.R (project codebase) - normalize_icd() pattern
- R/44_treatment_episodes.R (project codebase) - distinct() deduplication pattern (lines 94-97)

### Secondary (MEDIUM confidence)

- [ICD-10-CM FY 2026 Coding Guidelines](https://www.cms.gov/files/document/fy-2026-icd-10-cm-coding-guidelines.pdf) - 3-character category structure
- [2026 ICD-10-CM Codes C00-D49: Neoplasms](https://www.icd10data.com/ICD10CM/Codes/C00-D49) - Cancer code structure verification
- [SEER ICD-O-3 Coding Materials](https://seer.cancer.gov/icd-o-3/) - Cancer site classification source
- [CMS Small Cell Policy (HIPAA)](https://www.doh.wa.gov/portals/1/documents/1500/smallnumbers.pdf) - Cell suppression guidance (not directly applicable to this phase but context for D-06)

### Tertiary (LOW confidence)

- [Validation studies in epidemiologic research](https://www.sciencedirect.com/science/article/pii/S0895435621001529) - General epidemiological validation concepts (2+ dates logic is standard but not explicitly documented in single canonical source)

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH - All libraries already in project renv; dplyr patterns well-documented; openxlsx2 patterns established in R/47
- Architecture: HIGH - Clear reuse of R/47 logic; distinct-date filtering is standard dplyr pattern; two-level confirmation logic straightforward
- Pitfalls: HIGH - NA date handling, prefix logic confusion, and divide-by-zero are well-known gotchas with documented solutions
- Confirmation rate formatting: MEDIUM - User preference for percentage vs decimal not explicitly stated; percentage is standard but needs confirmation

**Research date:** 2026-05-19
**Valid until:** 2026-06-19 (30 days - stable domain, dplyr/openxlsx2 patterns unlikely to change)
