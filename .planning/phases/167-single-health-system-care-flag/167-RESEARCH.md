# Phase 167: Single-Health-System Care Flag — Research

**Researched:** 2026-10-08
**Domain:** DuckDB SQL aggregation + R openxlsx workbook assembly
**Confidence:** HIGH (all findings verified from live source files in this repo)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-167-01 (closed):** SOURCE from ENCOUNTER only. No other CDM tables unioned.
- **D-167-02 (closed):** Deliver both windows as separate columns: whole-record and post-HL-anchor.
- **D-167-03:** Whole-record window = encounters with `ADMIT_DATE` within pipeline's existing analysis date range (`CONFIG$date_range_max = 2025-03-31`); encounters with missing `ADMIT_DATE` excluded from both windows and counted in QC.
- **D-167-04:** Read `hl_anchor_date` from R/147's anchor source (`get_hl_any_dx_ids()` in `utils_treatment.R`) directly — not from Phase 165/166 output files. Post-anchor: `ADMIT_DATE > hl_anchor_date`. No anchor → whole-record flag still computed; post-anchor = NA. Anchor exists but zero post-anchor encounters → `n_sources_post = 0`, `single_source_care_post = NA`.
- **D-167-05:** Compute `single_source_care` / `n_sources` over non-blank SOURCE values only. Patients with any blank/NA SOURCE get `any_blank_source = TRUE`. QC counts them. QC also includes a sensitivity row treating blank as its own site.
- **D-167-06:** Workbook tab detail: single- vs multi-source cross-tabulated by encounter count bands (1 | 2–4 | 5–9 | 10+); `n_sources` distribution capped at "4+"; 2×2 table comparing whole-record vs post-anchor single-source status. `suppress_small()` throughout including by-SOURCE breakdown.
- **D-167-07:** Export dated CSV + internal RDS. Columns: `ID`, `n_encounters`, `n_sources`, `single_source_care`, `primary_source`, `n_encounters_post`, `n_sources_post`, `single_source_care_post`, `any_blank_source`. `primary_source` for multi-source = most common site (alphabetical tiebreak).
- **Script numbering:** R/169 is the next available slot (R/166, R/167, R/168 are Phase 166 plans 01–03).
- **Plan-end requirements:** Every plan must end with a HiPerGator run step (`module load R/4.5`) and a workbook review step.

### Claude's Discretion

- Column ordering within the RDS beyond the required columns.
- Exact tie-breaking logic for `primary_source` (alphabetical is sufficient).
- DuckDB query structure (CTE vs subquery) — follow R/116 pattern.
- Workbook UF styling — match Phase 166 convention (header `#0021A5` white bold Arial; flag style `#FA4616`).

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SRC-01 | Patient-level binary `single_source_care` (1 = `n_distinct(ENCOUNTER.SOURCE) == 1`) and `n_sources` for every cohort patient with ≥1 encounter; computed in DuckDB, not by loading ENCOUNTER into R; SOURCE from ENCOUNTER only | DuckDB SQL pattern verified from R/116; `open_pcornet_con()` + `DBI::dbGetQuery()` is the correct approach |
| SRC-02 | Delivered in two windows as separate columns: whole-record and post-HL-anchor; flag joinable onto Phase 165/166 patient tables on `ID` | Two-window `_post` suffix pattern established in Phase 165/166; join-on-ID is the project convention |
| SRC-03 | Patients with NA/blank SOURCE on any encounter are flagged and counted in QC, not coerced to a site; NA-SOURCE patient count in QC sheet | D-167-05 gives the precise rule; `suppress_small()` already handles suppression |
</phase_requirements>

---

## Summary

Phase 167 delivers `R/169_single_source_care.R` — a read-only investigation script that queries `ENCOUNTER.SOURCE` in DuckDB and produces a patient-level flag (`single_source_care`) plus its post-anchor counterpart. The DuckDB query pattern is already established by `R/116_encounter_ses_index.R` (cohort PATID filter, `DBI::dbGetQuery()`, collect into R). The workbook assembly pattern is established by `R/168_survivorship_workbook.R` (openxlsx, UF colors, KEY sheet first). Both patterns need only adaptation, not invention.

The anchor date source is `get_hl_any_dx_ids()` from `R/utils/utils_treatment.R`, which returns `tibble(ID, hl_anchor_date, in_confirmed_cohort)`. This is the exact same function called by R/147 and R/165 — Phase 167 is explicitly not to read it from any Phase 165/166 output file (D-167-04).

The blank-SOURCE handling (D-167-05) is the only novel logic: two pass computation — primary classification ignores blanks, sensitivity row in QC treats blank as a distinct site. Everything else is straightforward COUNT DISTINCT aggregation in DuckDB followed by openxlsx workbook construction.

**Primary recommendation:** One plan. Structure the script in the same 3-block pattern as R/166/R/167/R/168: (1) DuckDB query → R tibble, (2) R aggregation and flag construction, (3) openxlsx workbook + CSV/RDS export. Register R/169 at the end of `investigation_scripts` in R/39.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| DBI | project renv | DuckDB connection + `dbGetQuery()` | Used by all DuckDB scripts via utils_duckdb.R |
| duckdb | project renv | DuckDB driver | Same |
| dplyr | project renv | In-R aggregation, joins, mutate | Project standard — no data.table |
| openxlsx | project renv | Workbook creation | R/168 uses this; `openxlsx2` used in R/116 — R/168 is the canonical workbook pattern for Phase 166/167 |
| glue | project renv | String interpolation | Project-wide |
| readr | project renv | `write_csv()` for dated CSV export | Used in R/168 |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| here | project renv | `here::here()` for paths | `source(here::here("R/00_config.R"))` pattern |
| tidyr | project renv | `pivot_wider` if needed for 2×2 tables | Optional; dplyr may suffice |

**Installation:** No new packages — all are already in renv.lock.

---

## Architecture Patterns

### Recommended Project Structure

```
R/169_single_source_care.R   # New script (Phase 167)
```

No new utility modules needed. All helpers already exist.

### Pattern 1: DuckDB Query for Cohort-Scoped Aggregation

This is the canonical pattern from `R/116_encounter_ses_index.R` (SECTION 4 + SECTION 2). For Phase 167, the DuckDB query is pure aggregation — never load the ENCOUNTER table into R.

**Approach:** Use `DBI::dbGetQuery()` with a parameterized SQL string. Register cohort IDs as a DuckDB temp table (via `duckdb::duckdb_register()`) then join inside SQL — this is safer than SQL `IN (…)` for large cohort vectors.

```r
# Source: R/116_encounter_ses_index.R (SECTION 4 adaptation) and R/161_diag_anchor_followup.R
source(here::here("R/00_config.R"))
if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()

# Load anchor dates from the canonical source (D-167-04)
anchors <- get_hl_any_dx_ids()   # tibble(ID, hl_anchor_date, in_confirmed_cohort)

# Register cohort IDs as a temp table so DuckDB can join
cohort_ids_tbl <- dplyr::distinct(anchors, ID)
duckdb::duckdb_register(pcornet_con, "cohort_ids", cohort_ids_tbl)

# DuckDB query: whole-record aggregation, non-blank SOURCE only
# Matches D-167-03: ADMIT_DATE within [date_range_min, date_range_max]
# Matches D-167-05: filter out blank/NULL SOURCE before n_distinct()
sql_whole <- "
WITH cohort_enc AS (
  SELECT e.ID, e.SOURCE, e.ADMIT_DATE
  FROM   ENCOUNTER e
  INNER JOIN cohort_ids c ON c.ID = e.ID
  WHERE  e.ADMIT_DATE BETWEEN DATE '1901-01-01' AND DATE '2025-03-31'
    AND  e.ADMIT_DATE IS NOT NULL
),
blank_flag AS (
  SELECT ID,
         MAX(CASE WHEN SOURCE IS NULL OR TRIM(SOURCE) = '' THEN 1 ELSE 0 END) AS any_blank_source
  FROM   cohort_enc
  GROUP BY ID
),
nonblank_agg AS (
  SELECT ID,
         COUNT(*)              AS n_encounters,
         COUNT(DISTINCT SOURCE) AS n_sources
  FROM   cohort_enc
  WHERE  SOURCE IS NOT NULL AND TRIM(SOURCE) <> ''
  GROUP BY ID
)
SELECT n.ID,
       n.n_encounters,
       n.n_sources,
       b.any_blank_source,
       CASE WHEN n.n_sources = 1 THEN 1 ELSE 0 END AS single_source_care
FROM   nonblank_agg n
LEFT JOIN blank_flag b ON b.ID = n.ID
"
whole_raw <- DBI::dbGetQuery(pcornet_con, sql_whole)
```

**Key details:**
- Date bounds are hardcoded from `CONFIG$date_range_max` — substitute via `glue()` in actual code so if the config changes the query stays consistent.
- Patients with zero non-blank encounters (all blanks) will not appear in `nonblank_agg`; they appear only in `blank_flag`. Handle with a full cohort left-join in R after collecting.

### Pattern 2: Post-Anchor Window Computation

Run a second DuckDB query filtered to `ADMIT_DATE > hl_anchor_date`. Because `hl_anchor_date` is patient-specific, register the anchors table as a DuckDB temp table and join inside SQL.

```r
# Source: R/161_diag_anchor_followup.R line 176-177 and R/165 line 222
duckdb::duckdb_register(pcornet_con, "hl_anchors",
                        anchors |> dplyr::select(ID, hl_anchor_date))

sql_post <- "
WITH post_enc AS (
  SELECT e.ID, e.SOURCE, e.ADMIT_DATE
  FROM   ENCOUNTER e
  INNER JOIN cohort_ids  c ON c.ID = e.ID
  INNER JOIN hl_anchors  a ON a.ID = e.ID
  WHERE  e.ADMIT_DATE > a.hl_anchor_date     -- anchor day = pre (D-167-04 + R/147 D-25)
    AND  e.ADMIT_DATE IS NOT NULL
),
nonblank_post AS (
  SELECT ID,
         COUNT(*)              AS n_encounters_post,
         COUNT(DISTINCT SOURCE) AS n_sources_post
  FROM   post_enc
  WHERE  SOURCE IS NOT NULL AND TRIM(SOURCE) <> ''
  GROUP BY ID
)
SELECT * FROM nonblank_post
"
post_raw <- DBI::dbGetQuery(pcornet_con, sql_post)
```

### Pattern 3: Full Cohort Left-Join and Flag Construction

After collecting both DuckDB results into R, left-join onto the full cohort to ensure every patient appears (including those with zero encounters).

```r
# All cohort patients as base — left join window results
result <- anchors |>
  dplyr::select(ID, hl_anchor_date) |>
  dplyr::left_join(whole_raw,  by = "ID") |>
  dplyr::left_join(post_raw,   by = "ID") |>
  dplyr::mutate(
    # Patients with zero encounters: n_encounters = 0, single_source_care = NA
    # D-167-04: zero post-anchor encounters -> n_sources_post = 0, single_source_care_post = NA
    single_source_care_post = dplyr::case_when(
      is.na(hl_anchor_date)   ~ NA_integer_,   # no anchor -> NA (not 0)
      is.na(n_encounters_post) ~ NA_integer_,   # zero post-anchor encounters -> NA
      n_sources_post == 1      ~ 1L,
      TRUE                     ~ 0L
    ),
    n_sources_post = dplyr::coalesce(n_sources_post, 0L),  # only after flag computed
    any_blank_source = dplyr::coalesce(any_blank_source, FALSE)
  )
```

### Pattern 4: primary_source Computation

For single-source patients = that source. For multi-source = most common site, alphabetical tiebreak (D-167-07). This requires a separate query or R-side computation.

```r
# Collect SOURCE-level encounter counts per patient (non-blank only, whole record)
# Then in R:
primary_source_tbl <- source_counts |>   # ID, SOURCE, n_enc_at_source
  dplyr::group_by(ID) |>
  dplyr::arrange(dplyr::desc(n_enc_at_source), SOURCE) |>  # ties: alphabetical SOURCE
  dplyr::slice_head(n = 1) |>
  dplyr::ungroup() |>
  dplyr::select(ID, primary_source = SOURCE)
```

### Pattern 5: Workbook Assembly (from R/168)

```r
# Source: R/168_survivorship_workbook.R SECTION 4
library(openxlsx)

UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"

hdr_style <- openxlsx::createStyle(
  fgFill         = UF_BLUE,
  fontColour     = "white",
  textDecoration = "bold",
  fontName       = "Arial",
  fontSize       = 11,
  halign         = "left",
  border         = "Bottom",
  borderColour   = "white"
)

wb <- openxlsx::createWorkbook()
# Sheet order: KEY (leftmost), A_summary, B_post_anchor, QC
```

### Workbook Tab Structure (D-167-06)

```
KEY          — metadata (run date, decisions, date bounds, SOURCE count)
A_summary    — whole-record window: headline %, encounter-band cross-tab,
               n_sources distribution (capped "4+"), by-SOURCE for single-source
B_post_anchor — same structure for post-anchor window
QC           — NA-ADMIT_DATE count, any_blank_source patient count,
               sensitivity row (blank = own site), 2×2 whole vs post-anchor
```

### Anti-Patterns to Avoid

- **Do not load ENCOUNTER into R** — it will OOM on HiPerGator. Use DuckDB SQL only (SRC-01 requirement).
- **Do not use `dplyr::filter(ID %in% cohort_ids)` on a tbl_lazy** — for large cohort vectors, register as a DuckDB temp table and JOIN. (REVIEW-FUT-02 notes the lazy-tbl local-join gap.)
- **Do not set `single_source_care_post = 0` when patient has no anchor** — must be NA per D-167-04.
- **Do not set `single_source_care_post = 0` when patient has anchor but zero post-anchor encounters** — must be NA per D-167-04 (zero encounters is not single-source).
- **Do not suppress the count used for statistics** — compute statistics on unsuppressed counts, then apply `suppress_small()` for display tables only (pattern from R/168 `display_counts()`).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| DuckDB connection | Custom connection code | `open_pcornet_con()` / `close_pcornet_con()` from `utils_duckdb.R` | Already handles read-only mode, global state, TUMOR_REGISTRY view |
| Anchor date fetch | Re-query DIAGNOSIS | `get_hl_any_dx_ids()` from `utils_treatment.R` | Canonical source; Phase 165/166 already use it; D-167-04 requires it |
| Small-cell suppression | Custom threshold logic | `suppress_small()` from `utils_surveillance.R` | Project standard; threshold=10; auto-sourced by `R/00_config.R` |
| Workbook styling | Custom style creation | Copy UF_BLUE/UF_ORANGE + `hdr_style` from R/168 | Exact style match required; already debugged |
| Cohort ID filter in DuckDB | SQL `IN (…)` string | `duckdb::duckdb_register()` + SQL JOIN | IN-list fails for large vectors; register-and-join is the R/161 established pattern |

**Key insight:** The hard parts of this phase (DuckDB connection management, anchor date derivation, workbook UF styling, suppression) are already solved. This phase is assembly, not invention.

---

## Common Pitfalls

### Pitfall 1: Patients With All-Blank SOURCE Disappear From Aggregation

**What goes wrong:** If the DuckDB query filters to non-blank SOURCE before aggregating, patients whose every encounter has a blank SOURCE produce zero rows in `nonblank_agg`. They do not appear in the result. These patients silently have `n_sources = NA` instead of being counted and flagged.

**Why it happens:** SQL `WHERE SOURCE IS NOT NULL AND TRIM(SOURCE) <> ''` removes them from the GROUP BY.

**How to avoid:** Run the blank-flag CTE separately (before the SOURCE filter) to capture `any_blank_source = TRUE` for these patients. Then left-join the blank flag back. After the full cohort left-join in R, patients with zero non-blank encounters have `n_encounters = NA` — distinguish them from patients-with-no-encounters by also tracking whether they appear in `blank_flag`.

**Warning signs:** `n_distinct(result$ID)` < `n_distinct(anchors$ID)` after the left-join.

### Pitfall 2: Zero Post-Anchor Encounters Incorrectly Set to 0 or Single-Source

**What goes wrong:** `left_join` on `post_raw` produces `n_encounters_post = NA` for patients with no post-anchor encounters. If the plan coalesces this to 0 and then sets `single_source_care_post = (n_sources_post == 1)`, a patient with 0 post-anchor encounters gets `single_source_care_post = FALSE` (0), not NA.

**How to avoid:** Compute `single_source_care_post` flag BEFORE coalescing `n_sources_post` to 0. The case_when must check `is.na(n_encounters_post)` → NA. Then coalesce `n_sources_post` to 0L for reporting.

**Warning signs:** QC check: count patients where `single_source_care_post == 0 AND n_encounters_post == 0` — should be zero.

### Pitfall 3: Sensitivity Row Conflates With Primary Classification

**What goes wrong:** The QC sensitivity row (blank treated as own site) is built from the same aggregated data as the primary flag, causing confusion about which figure is primary and which is sensitivity.

**How to avoid:** Compute a separate aggregation in DuckDB (or R) that includes blank SOURCE as a distinct value. Label this column clearly (e.g., `n_sources_with_blank`, `single_source_care_sensitivity`). Only report it in the QC sheet, never in A_summary or B_post_anchor.

### Pitfall 4: `primary_source` Is NA for Multi-Source Patients With Ties

**What goes wrong:** `slice_head(n=1)` after `arrange(desc(n), SOURCE)` works correctly in R but can produce unexpected results if `n_enc_at_source` is tied across all sources (e.g., all sites = 1 encounter). In this case alphabetical is correct by D-167-07 — but the plan must document the tiebreak explicitly.

**How to avoid:** Always sort by `dplyr::desc(n_enc_at_source), SOURCE` (ascending SOURCE for alphabetical). Verify: `primary_source` should be non-NA for every patient with ≥1 encounter.

### Pitfall 5: openxlsx vs openxlsx2 Mismatch

**What goes wrong:** R/116 uses `openxlsx2` (`wb_workbook()`, `wb_add_worksheet()`) while R/168 uses `openxlsx` (`createWorkbook()`, `addWorksheet()`). These are NOT compatible APIs.

**How to avoid:** R/169 must follow R/168's pattern exactly — `library(openxlsx)`, not `library(openxlsx2)`. Verify: `openxlsx::createWorkbook()` is the entry point.

---

## Code Examples

### Canonical DuckDB Cohort-Scoped Query (from R/161)

```r
# Source: R/161_diag_anchor_followup.R lines 176-177
duckdb::duckdb_register(con, "hl_ids",
                        anchor |> select(ID, hl_anchor_date, anchor_encounterid))
```

### Canonical openxlsx KEY Sheet Pattern (from R/168)

```r
# Source: R/168_survivorship_workbook.R SECTION 5
key_df <- tibble::tibble(
  Field = c("Run date", "Script", "Decisions", "Date range", "Anchor source"),
  Value = c(run_date, "R/169_single_source_care.R",
            "167-CONTEXT.md D-167-01..D-167-07",
            paste0(CONFIG$analysis$date_range_min, " to ", CONFIG$analysis$date_range_max),
            "get_hl_any_dx_ids() (utils_treatment.R)")
)
openxlsx::addWorksheet(wb, "KEY")
openxlsx::writeData(wb, "KEY", key_df, headerStyle = hdr_style)
```

### Encounter Count Band Cross-Tab (D-167-06)

```r
# In R, after collecting whole-record result
band_breaks <- c(0, 1, 4, 9, Inf)
band_labels <- c("1", "2-4", "5-9", "10+")
result |>
  dplyr::filter(!is.na(n_encounters)) |>
  dplyr::mutate(enc_band = cut(n_encounters, breaks = band_breaks,
                               labels = band_labels, right = TRUE)) |>
  dplyr::group_by(enc_band) |>
  dplyr::summarise(
    n_patients        = dplyr::n(),
    n_single_source   = sum(single_source_care == 1L, na.rm = TRUE),
    pct_single_source = round(100 * n_single_source / n_patients, 1)
  )
```

### suppress_small() Usage Pattern (from R/168)

```r
# Source: R/168_survivorship_workbook.R lines 162-180
# suppress_small() is auto-sourced via R/00_config.R -> utils_surveillance.R
A_summary_display <- A_summary |>
  dplyr::mutate(
    n_single_source   = suppress_small(n_single_source),
    n_multi_source    = suppress_small(n_multi_source)
  )
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Loading ENCOUNTER into R for analysis | DuckDB SQL aggregation pushed to database layer | Phase 116+ | Avoids OOM; ENCOUNTER is large |
| `filter(ID %in% big_vector)` on tbl_lazy | `duckdb_register()` + SQL JOIN | Phase 161 | Avoids large IN-clause SQL failures |
| openxlsx2 (newer API) | openxlsx (original) for workbooks | R/116 uses wx2; R/168 uses wx | Phase 166 workbooks use openxlsx — must match |

---

## Open Questions

1. **CONFIG key for date_range_min**
   - What we know: `CONFIG$analysis$date_range_max = as.Date("2025-03-31")` confirmed in R/00_config.R line 2918. `date_range_min = as.Date("1901-01-01")` confirmed at line 2917.
   - What's unclear: Whether to embed these as literal dates in DuckDB SQL or pass via `glue()`. R/166 uses `EXTRACT_DATE <- CONFIG` pattern for the cutoff.
   - Recommendation: Pass as `glue()` substitutions in the SQL string so the plan inherits any future CONFIG changes without code edits.

2. **R/88 SMOKE-167-01 section scope**
   - What we know: CONTEXT.md says R/88 gains a "SMOKE-167-01 section" per the canonical refs. REQUIREMENTS.md `SMOKE-37-01` says structural checks: file existence, output sheet names, KEY leftmost, binary columns 0/1 only.
   - What's unclear: Whether SMOKE-167-01 should also check the `any_blank_source` column or the `_post` NA handling.
   - Recommendation: Limit smoke test to structural checks matching Phase 166 pattern (file exists, sheet names match, KEY leftmost, `single_source_care` values in {0, 1, NA}).

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| DuckDB (HiPerGator) | SRC-01 | HiPerGator only | project renv | Script skips via probe gate |
| ENCOUNTER table in DuckDB | SRC-01 | HiPerGator only | — | Script stops with informative message |
| `open_pcornet_con()` | DuckDB access | Available (utils_duckdb.R) | — | — |
| `get_hl_any_dx_ids()` | Anchor dates | Available (utils_treatment.R) | — | — |
| `suppress_small()` | Display suppression | Available (utils_surveillance.R) | — | — |
| openxlsx | Workbook | renv | — | — |

**Missing dependencies with no fallback:**
- DuckDB ENCOUNTER table: requires HiPerGator. Script cannot produce meaningful output locally without it. Use probe gate to skip gracefully.

---

## Validation Architecture

> workflow.nyquist_validation not set to false in .planning/config.json — validation section included.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | testthat (existing in repo under `tests/testthat/`) |
| Config file | none — sourced via `sys.source()` pattern |
| Quick run command | `testthat::test_file("tests/testthat/test-169-single-source-care.R")` |
| Full suite command | `testthat::test_dir("tests/testthat")` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SRC-01 | `single_source_care` derived from `n_distinct(SOURCE) == 1` | unit | `testthat::test_file("tests/testthat/test-169-single-source-care.R")` | Wave 0 |
| SRC-02 | Post-anchor window uses `ADMIT_DATE > hl_anchor_date`; zero post-anchor encounters → flag = NA | unit | same file | Wave 0 |
| SRC-03 | Blank SOURCE → `any_blank_source = TRUE`; not coerced into n_sources | unit | same file | Wave 0 |

### Sampling Rate

- **Per task commit:** `testthat::test_file("tests/testthat/test-169-single-source-care.R")`
- **Per wave merge:** `testthat::test_dir("tests/testthat")`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `tests/testthat/test-169-single-source-care.R` — covers SRC-01, SRC-02, SRC-03 via synthetic tibble fixtures (no DuckDB required for unit tests; test the R-side flag construction logic)

---

## Sources

### Primary (HIGH confidence)

- `R/utils/utils_duckdb.R` — `open_pcornet_con()`, `close_pcornet_con()`, `get_pcornet_table()`, `materialize()` — all verified by direct file read
- `R/utils/utils_treatment.R` — `get_hl_any_dx_ids()` returns `tibble(ID, hl_anchor_date, in_confirmed_cohort)` — verified by direct file read
- `R/utils/utils_surveillance.R` — `suppress_small(x, threshold=10)` signature and logic — verified by direct file read (line 640)
- `R/116_encounter_ses_index.R` — DuckDB + R query pattern (SECTION 4: `dplyr::filter(ID %in% !!addr_ids, !is.na(ADMIT_DATE))` → `collect()`) — verified
- `R/161_diag_anchor_followup.R` — `duckdb::duckdb_register()` + SQL JOIN pattern — verified lines 176-177
- `R/168_survivorship_workbook.R` — openxlsx workbook assembly, UF_BLUE/UF_ORANGE, `display_counts()` pattern — verified SECTIONS 3-4
- `R/147_surveillance_modality_frequency.R` — anchor date source is `get_hl_any_dx_ids()` (line 88), `ANCHOR_DAY_IS_POST = FALSE` (D-25) — verified
- `R/00_config.R` — `date_range_min = as.Date("1901-01-01")`, `date_range_max = as.Date("2025-03-31")` — verified lines 2917-2918
- `R/39_run_all_investigations.R` — `investigation_scripts` vector ends at `R/168_survivorship_workbook.R`; R/169 inserts after — verified lines 229-231
- `167-CONTEXT.md` — all decisions D-167-01 through D-167-07 — verified by full file read

### Secondary (MEDIUM confidence)

- None needed — all findings verified from live source files.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified from renv/existing scripts
- Architecture: HIGH — DuckDB pattern and workbook pattern both verified from R/116, R/161, R/168
- Pitfalls: HIGH — derived from explicit decisions in CONTEXT.md + direct code inspection of blank-handling and NA-flag edge cases

**Research date:** 2026-10-08
**Valid until:** 2026-11-08 (stable codebase; no external dependencies)
