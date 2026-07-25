# Phase 137: read-zip9-temporal-assignment - Research

**Researched:** 2026-07-25
**Domain:** R temporal interval lookup, LDS_ADDRESS_HISTORY, openxlsx2 append pattern
**Confidence:** HIGH (all findings drawn from canonical project code; no external library research required)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** ZIP9 assignment is per-query-date, not static per patient. The utility accepts any vector of (ID, date) pairs and returns the ZIP9/ZIP5 active at each date.
- **D-02:** Primary rule — interval overlap: `ADDRESS_PERIOD_START <= date < ADDRESS_PERIOD_END`.
- **D-03:** Fallback when no interval covers the query date: most-recent `ADDRESS_PERIOD_START` on or before date. If no address record precedes the date, return `NA` for both ZIP9 and ZIP5.
- **D-04:** When multiple records cover the same date (overlapping periods), select the one with the most recent `ADDRESS_PERIOD_START` (tie-break by recency).
- **D-05:** Delivered as `get_zip9_at_date(ids, dates)` in `R/utils/utils_address.R`. Returns a tibble with columns `ID`, `query_date`, `ZIP9`, `ZIP5`, `match_type` (`"interval"`, `"most_recent_before"`, `"none"`).
- **D-06:** Reads `LDS_ADDRESS_HISTORY` from `CONFIG$data_dir` directly (not via `get_pcornet_table()`). NOT precomputed/cached; callers load on demand.
- **D-07:** New investigation script `R/NN_zip9_temporal_lookup.R` (next available after 106). Validates `get_zip9_at_date()` with a sample call, logs diagnostics to console. Registered in R/39, R/88 (new section), and R/SCRIPT_INDEX.md.
- **D-08:** New script uses the same probe-first gate as R/106: if `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` absent, log clear message and exit gracefully (no crash, no `stop()`). When sourced non-globally, raise a condition so R/39's tryCatch logs it as skipped.
- **D-09:** Per-patient timeline diagnostics: % with gaps, % with overlapping periods, % missing `ADDRESS_PERIOD_END`, summary of period count distribution.
- **D-10:** Output appended as new sheet ("Address Timeline Diagnostics") to the **existing** `output/zip_change_frequency.xlsx` (produced by R/106). Follows `add_styled_sheet()` look-and-feel.
- **D-11:** Diagnostics also logged to console (headline stats) before writing the sheet.

### Claude's Discretion

- Exact function signature (parameter names, whether to accept a data frame vs separate vectors)
- How to handle `ADDRESS_PERIOD_END = NA` (treat as open-ended: period extends indefinitely)
- Whether per-patient timeline diagnostics are computed by utils function or investigation script
- The exact `R/NN` number (check `R/SCRIPT_INDEX.md`)
- Column layout and ordering in the new xlsx sheet

### Deferred Ideas (OUT OF SCOPE)

- Computing and attaching ADI/SVI/SDI scores to the cohort
- Adding `LDS_ADDRESS_HISTORY` to `PCORNET_TABLES` / DuckDB permanent load set
- Adding ZIP9 columns (ZIP9_AT_DX, ZIP9_AT_TX) to the cohort RDS
- Building a local fixture for `LDS_ADDRESS_HISTORY` for end-to-end local testing
</user_constraints>

---

## Summary

Phase 137 builds a date-keyed ZIP9/ZIP5 lookup utility on top of the address-history work from Phase 121 (R/106). The core deliverable is `R/utils/utils_address.R` containing `get_zip9_at_date()`, which performs interval-overlap matching with a most-recent-before fallback. All patterns (probe gate, xlsx append, styled sheets, console diagnostics, registration) have exact precedents in the existing codebase.

The canonical reference for everything in this phase is `R/106_zip_change_frequency.R`. The script number for the new investigation script is **114** (next available after 113). The next R/88 smoke-test section is **15ab** (the last existing section is 15aa, added for Phase 135).

**Primary recommendation:** Model `utils_address.R` directly on `utils_format.R` (module structure) and copy the probe gate verbatim from R/106 lines 95–114. Use `openxlsx2::wb_load()` to open the existing xlsx, call `add_styled_sheet()`, then `wb_save()`.

---

## Standard Stack

### Core (already in renv — no new installs)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | project standard | interval filter, group_by, arrange, slice | named-predicate requirement |
| vroom | project standard | load LDS_ADDRESS_HISTORY CSV | existing pattern in R/106 |
| openxlsx2 | project standard | append new sheet to existing xlsx | R/106 already uses it |
| glue | project standard | console message formatting | project standard |
| lubridate / utils_dates | project standard | date parsing | `parse_pcornet_date()` in utils_dates |
| stringr | project standard | ZIP normalization | R/106 already uses it |

No new packages needed. All are already in renv.

### Reuse Inventory

| Asset | Location | What to Reuse |
|-------|----------|---------------|
| `normalize_zip9()` | R/106 lines 171-174 | Copy verbatim into utils_address.R |
| `normalize_zip5()` | R/106 lines 177-179 | Copy verbatim into utils_address.R |
| `normalize_zip5_raw()` | R/106 lines 182-186 | Copy verbatim into utils_address.R |
| `suppress_small()` | R/106 lines 190-192 | Copy into utils_address.R (or keep inline in R/114) |
| `add_styled_sheet()` | R/106 lines 750-797 | Do NOT duplicate; R/114 sources R/106 or redefines locally |
| Probe gate | R/106 lines 95-114 | Copy verbatim into R/114 |
| `parse_pcornet_date()` | R/utils/utils_dates.R | Available automatically via R/00_config.R |

**Note on `add_styled_sheet()`:** R/106 defines this function locally, copied from R/100. R/114 will source `R/00_config.R` (which does NOT auto-load `add_styled_sheet()`). The cleanest path: R/114 opens the existing xlsx with `wb_load()`, calls a locally-defined `add_styled_sheet()` that matches R/106's signature exactly. Do NOT re-source R/106 (side effects: loads the whole address table, writes the xlsx from scratch).

---

## Architecture Patterns

### Module Structure: utils_address.R

Model on `R/utils/utils_format.R`. Header with Purpose/Inputs/Outputs/Dependencies/Requirements. Define functions only — no side effects, no `source()` calls, no global assignments. Auto-loaded by `R/00_config.R` via `list.files("R/utils/", full.names = TRUE)`.

```
R/utils/utils_address.R
  normalize_zip9(zip)          — strip hyphen, validate 8-9 digit numeric, pad to 9
  normalize_zip5(zip9_clean)   — first 5 chars of clean ZIP9
  normalize_zip5_raw(zip)      — normalize a raw ZIP5 column
  get_zip9_at_date(ids, dates) — main temporal lookup function
```

### Script Number

The next available number after R/113 is **R/114**. The new script is `R/114_zip9_temporal_lookup.R`.

### Temporal Lookup Algorithm (get_zip9_at_date)

The function must handle three cases per (ID, date) pair:

1. **Interval match** (`ADDRESS_PERIOD_START <= date < ADDRESS_PERIOD_END`, or `ADDRESS_PERIOD_END is NA` treated as open-ended): select the record with the most recent `ADDRESS_PERIOD_START` among all covering records.
2. **Most-recent-before fallback** (no interval covers the date): select the record with the largest `ADDRESS_PERIOD_START` that is still <= date.
3. **None** (no record with `ADDRESS_PERIOD_START <= date`): return `NA` for both ZIP9 and ZIP5.

Implementation sketch using dplyr:

```r
get_zip9_at_date <- function(ids, dates) {
  # ids and dates are parallel vectors; combine into query tibble
  queries <- tibble(ID = ids, query_date = as.Date(dates))

  # Load address table (caller's responsibility — function reads on demand per D-06)
  addr_path <- file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv")
  addr_raw  <- vroom::vroom(addr_path, col_types = vroom::cols(.default = "c"),
                            progress = FALSE)

  addr <- addr_raw %>%
    mutate(
      zip9_norm        = normalize_zip9(ADDRESS_ZIP9),
      zip5_norm        = normalize_zip5(zip9_norm),
      period_start_dt  = parse_pcornet_date(ADDRESS_PERIOD_START),
      # NA ADDRESS_PERIOD_END treated as open-ended (D: Claude's Discretion)
      period_end_dt    = if_else(
        is.na(ADDRESS_PERIOD_END) | trimws(ADDRESS_PERIOD_END) == "",
        as.Date("9999-12-31"),
        parse_pcornet_date(ADDRESS_PERIOD_END)
      )
    ) %>%
    filter(!is.na(period_start_dt))

  # Cross join queries to address records, then classify each candidate
  candidates <- queries %>%
    inner_join(addr %>% select(ID, zip9_norm, zip5_norm,
                               period_start_dt, period_end_dt),
               by = "ID") %>%
    mutate(
      is_interval = period_start_dt <= query_date & query_date < period_end_dt,
      is_before   = period_start_dt <= query_date
    )

  # Interval matches (D-02, D-04)
  interval_hits <- candidates %>%
    filter(is_interval) %>%
    group_by(ID, query_date) %>%
    arrange(desc(period_start_dt), .by_group = TRUE) %>%
    slice(1) %>%
    ungroup() %>%
    mutate(match_type = "interval") %>%
    select(ID, query_date, ZIP9 = zip9_norm, ZIP5 = zip5_norm, match_type)

  # Queries not covered by any interval — apply most-recent-before fallback (D-03)
  covered <- interval_hits %>% select(ID, query_date)
  uncovered <- queries %>% anti_join(covered, by = c("ID", "query_date"))

  fallback_hits <- candidates %>%
    semi_join(uncovered, by = c("ID", "query_date")) %>%
    filter(is_before) %>%
    group_by(ID, query_date) %>%
    arrange(desc(period_start_dt), .by_group = TRUE) %>%
    slice(1) %>%
    ungroup() %>%
    mutate(match_type = "most_recent_before") %>%
    select(ID, query_date, ZIP9 = zip9_norm, ZIP5 = zip5_norm, match_type)

  # Queries with no match at all
  still_uncovered <- uncovered %>%
    anti_join(fallback_hits, by = c("ID", "query_date"))

  none_rows <- still_uncovered %>%
    mutate(ZIP9 = NA_character_, ZIP5 = NA_character_, match_type = "none")

  bind_rows(interval_hits, fallback_hits, none_rows) %>%
    arrange(ID, query_date)
}
```

**Note on performance:** This approach joins ALL address records for matching IDs, then filters. For a large cohort this is memory-efficient enough (LDS_ADDRESS_HISTORY is one-file-per-patient CDM; R/106 loads it entirely). If the CSV is large, the inner_join on ID means only rows for queried patients are retained early. This is acceptable per D-06 (no caching).

### xlsx Append Pattern (D-10)

R/114 must NOT recreate `zip_change_frequency.xlsx` from scratch — it must append a new sheet to the existing workbook created by R/106.

```r
# Correct pattern — open existing, add sheet, save
wb <- openxlsx2::wb_load(OUTPUT_XLSX)

add_styled_sheet(
  wb, "Address Timeline Diagnostics",
  title_text    = "Address Timeline Diagnostics -- Per-Patient Period Structure",
  subtitle_text = "...",
  data_tbl      = diagnostics_tbl
)

openxlsx2::wb_save(wb, OUTPUT_XLSX)
```

**Anti-pattern to avoid:** `wb_workbook()` creates a new blank workbook — this would overwrite R/106's existing sheets. Always use `wb_load()` when appending.

### Probe-First Gate (D-08)

Copy verbatim from R/106 lines 95-114:

```r
if (!file.exists(addr_path)) {
  message("[R/114] LDS_ADDRESS_HISTORY not found -- skipped (not a real failure)")
  if (identical(environment(), globalenv())) {
    quit(status = 0)
  } else {
    stop("[R/114] LDS_ADDRESS_HISTORY not found -- skipped", call. = FALSE)
  }
}
```

**Critical:** The gate must ALSO check that `OUTPUT_XLSX` exists before trying to `wb_load()` it. If R/106 has never been run, the xlsx won't exist. Decision: if xlsx absent, log a clear message and exit gracefully (same pattern).

### R/39 Registration

The investigation_scripts vector in R/39 Section 3 currently ends with `"R/112_doi_attribution_report.R"` (no trailing comma on the last entry, then closing paren). The new entry goes before the closing paren:

```r
"R/112_doi_attribution_report.R",
"R/113_confirmed_hl_nhl_tumor_registry_counts.R",
"R/114_zip9_temporal_lookup.R"   # <-- add here, no comma (last entry)
```

**Check R/39's actual current last entry** before editing — R/113 may or may not already be registered (git status shows R/113 was added in a quick task). Verify before adding R/114.

### R/88 New Section

The last-added section is `15aa` (Phase 135 pattern regression). The next section is **15ab** for Phase 137.

Structural checks to include (~8-12 checks):

- `R/114_zip9_temporal_lookup.R` exists
- `R/utils/utils_address.R` exists
- `get_zip9_at_date` defined in utils_address.R
- `normalize_zip9` defined in utils_address.R
- `normalize_zip5` defined in utils_address.R
- Probe gate present in R/114 (grep for `file.exists(addr_path)`)
- `wb_load` present in R/114 (not `wb_workbook()` — anti-pattern guard)
- `match_type` column present in return value documentation
- R/114 registered in R/39 `investigation_scripts` vector
- R/114 present in SCRIPT_INDEX.md Post-Renumber table
- utils_address.R present in SCRIPT_INDEX.md Utility Libraries table

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ZIP normalization | Custom regex | Copy `normalize_zip9()` / `normalize_zip5()` from R/106 | Already handles 8-vs-9 digit leading-zero edge case and hyphen stripping |
| Date parsing | `as.Date()` directly | `parse_pcornet_date()` from utils_dates | Handles PCORnet multi-format dates (YYYYMMDD, YYYY-MM-DD, Excel serials) |
| xlsx styling | Custom openxlsx2 code | `add_styled_sheet()` copied from R/106 | Dark-gray header / frozen pane / auto-width established project standard |
| HIPAA suppression | `ifelse(n <= 10, ...)` | `suppress_small()` from R/106 | Consistent `"<11"` threshold across all investigation outputs |

---

## Common Pitfalls

### Pitfall 1: wb_workbook() instead of wb_load()
**What goes wrong:** Creates a blank workbook, silently deleting R/106's existing 5 sheets.
**Why it happens:** Default openxlsx2 pattern for new workbooks.
**How to avoid:** Always `wb_load(OUTPUT_XLSX)` when appending. Gate on xlsx existence first.

### Pitfall 2: ADDRESS_PERIOD_END = NA treated as missing
**What goes wrong:** All open-ended addresses (no end date) are excluded from interval matching.
**Why it happens:** `filter(date < ADDRESS_PERIOD_END)` with NA evaluates to FALSE.
**How to avoid:** Coerce `NA` end dates to `as.Date("9999-12-31")` before interval comparison (Claude's Discretion — confirmed in CONTEXT.md specifics).

### Pitfall 3: Joining on character PATID vs ID
**What goes wrong:** Address table uses `ID` column (not `PATID`). Joining on `PATID` returns 0 rows silently.
**Why it happens:** PCORnet CDM naming inconsistency; project convention is `ID`.
**How to avoid:** Validate `"ID" %in% names(addr)` after load (as R/106 does, lines 138-144).

### Pitfall 4: NA ZIP9 counting as a distinct value
**What goes wrong:** `n_distinct(zip9_norm)` counts NA as one distinct value, inflating "no-records" patients.
**Why it happens:** R's default `n_distinct()` includes NA.
**How to avoid:** Filter `!is.na(zip9_norm)` before grouping, same pattern as R/106 lines 243-249.

### Pitfall 5: Cross join memory explosion
**What goes wrong:** `queries` × `addr` cross join before filtering is O(n_queries × n_addr_rows).
**Why it happens:** A naive approach without `inner_join(by = "ID")` first.
**How to avoid:** Use `inner_join(addr, by = "ID")` to restrict candidates to queried patients only before any date computation.

### Pitfall 6: R/39 last-entry comma convention
**What goes wrong:** Adding a trailing comma after the new last entry causes a parse error in the c() vector.
**Why it happens:** R/39's investigation_scripts vector must have no comma on the final entry.
**How to avoid:** Check the actual final entry before editing. Add new entry with a comma on the preceding line, not after the new line.

### Pitfall 7: Sourcing R/106 to get add_styled_sheet()
**What goes wrong:** Sourcing R/106 as a side-effect triggers the full ZIP investigation: loads the CSV, computes all metrics, and overwrites `output/zip_change_frequency.xlsx`.
**Why it happens:** R/106 is a script, not a module; all top-level code executes on `source()`.
**How to avoid:** Define `add_styled_sheet()` locally in R/114 with the same signature, or factor it into utils_address.R. Do NOT source R/106.

---

## Code Examples

### Verified from R/106: Probe Gate Pattern
```r
# Source: R/106_zip_change_frequency.R lines 95-114
addr_path <- file.path(CONFIG$data_dir, ADDR_FILENAME)
if (!file.exists(addr_path)) {
  message(glue("[R/114] LDS_ADDRESS_HISTORY not found at expected path.\n  Expected: {addr_path}"))
  if (identical(environment(), globalenv())) {
    quit(status = 0)
  } else {
    stop("[R/114] LDS_ADDRESS_HISTORY not found -- skipped (not a real failure)", call. = FALSE)
  }
}
```

### Verified from R/106: CSV Load with Type Spec
```r
# Source: R/106_zip_change_frequency.R lines 126-132
addr <- tryCatch(
  vroom::vroom(addr_path, col_types = vroom::cols(.default = "c"), progress = FALSE),
  error = function(e) {
    message(glue("  vroom failed ({conditionMessage(e)}); falling back to read.csv"))
    read.csv(addr_path, colClasses = "character", na.strings = c("", "NA"))
  }
)
```

### Verified from R/106: ZIP Normalization
```r
# Source: R/106_zip_change_frequency.R lines 171-186
normalize_zip9 <- function(zip) {
  z <- str_remove_all(str_trim(zip), "-")
  z <- if_else(str_detect(z, "^[0-9]{8,9}$"), str_pad(z, 9, pad = "0"), NA_character_)
  if_else(str_detect(z, "^[0-9]{9}$"), z, NA_character_)
}
normalize_zip5 <- function(zip9_clean) {
  str_sub(zip9_clean, 1, 5)
}
```

### Verified from R/106: add_styled_sheet() Signature
```r
# Source: R/106_zip_change_frequency.R lines 750-797
add_styled_sheet <- function(wb, sheet_name, title_text, subtitle_text, data_tbl,
                              extra_tbl = NULL, extra_label = NULL)
```

### Verified from R/106: Append to Existing Workbook
```r
# Pattern for R/114 — open existing, NOT wb_workbook()
wb <- openxlsx2::wb_load(OUTPUT_XLSX)
add_styled_sheet(wb, "Address Timeline Diagnostics", ...)
openxlsx2::wb_save(wb, OUTPUT_XLSX)
```

---

## Registration Checklist

### R/39_run_all_investigations.R

- Current last entry: `"R/112_doi_attribution_report.R"` (confirmed from file read)
- R/113 was added in a quick task (260716) but verify it appears in the file before R/114
- Add `"R/114_zip9_temporal_lookup.R"` as new last investigation entry (no trailing comma)

### R/SCRIPT_INDEX.md

Add to **Post-Renumber Investigations (100+)** table:

| Script | Purpose | Phase |
|--------|---------|-------|
| `R/114_zip9_temporal_lookup.R` | Date-keyed ZIP9/ZIP5 temporal lookup validation. Validates `get_zip9_at_date()` from `utils_address.R` with a sample call, logs per-patient timeline diagnostics (gaps, overlaps, missing period-ends) to console, and appends an "Address Timeline Diagnostics" sheet to `output/zip_change_frequency.xlsx`. Probe-first gate: exits gracefully if `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` absent. | 137 |

Add to **Utility Libraries** table:

| Script | Purpose | Auto-sourced by |
|--------|---------|-----------------|
| `utils/utils_address.R` | ZIP9/ZIP5 normalization and date-keyed address lookup: `normalize_zip9()`, `normalize_zip5()`, `get_zip9_at_date()` | 00_config |

### R/88_smoke_test_comprehensive.R

Add **Section 15ab: ZIP9 TEMPORAL LOOKUP (Phase 137)** after Section 15aa.

---

## Environment Availability

Step 2.6: SKIPPED for the utility and investigation script code — these are pure R code changes. The actual runtime (loading the CSV, appending to xlsx) requires HiPerGator with `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` present, consistent with Phase 121 precedent. R/88 structural checks are runnable locally.

---

## Validation Architecture

Nyquist validation: code-level structural checks in R/88 (existing framework). No separate test files. Per project pattern, "tests" for investigation scripts are R/88 grep-based structural assertions.

### Phase Requirements → Test Map

| Req (from D-decisions) | Behavior | Test Type | Automated Command |
|------------------------|----------|-----------|-------------------|
| D-05 (function exists) | `get_zip9_at_date` defined in utils_address.R | structural | `Rscript R/88_smoke_test_comprehensive.R` |
| D-07 (registration) | R/114 in R/39 + R/88 + SCRIPT_INDEX | structural | `Rscript R/88_smoke_test_comprehensive.R` |
| D-08 (probe gate) | Probe gate in R/114 | structural grep | `Rscript R/88_smoke_test_comprehensive.R` |
| D-10 (wb_load not wb_workbook) | Anti-pattern absent | structural grep | `Rscript R/88_smoke_test_comprehensive.R` |

### Quick Run
```
Rscript R/88_smoke_test_comprehensive.R
```

### Wave 0 Gaps
- [ ] Section 15ab in `R/88_smoke_test_comprehensive.R` — covers D-05, D-07, D-08, D-10 structural assertions

---

## Open Questions

1. **Is R/113 already registered in R/39?**
   - What we know: R/113 was added by quick task 260716 but R/39 wasn't explicitly shown to be updated in that task log.
   - What's unclear: Whether the plan for R/114's R/39 registration must also add R/113.
   - Recommendation: Read R/39's actual investigation_scripts vector at plan time to confirm current last entry before adding R/114.

2. **add_styled_sheet() duplication strategy**
   - What we know: It's defined locally in R/106 and R/100 — already duplicated twice.
   - What's unclear: Whether Phase 137 should move it to utils_address.R or keep the local copy in R/114.
   - Recommendation: Keep a local copy in R/114 for now (consistent with the existing pattern). A future phase can centralize if needed.

3. **diagnostics computed where?**
   - What we know: CONTEXT.md leaves this to Claude's Discretion.
   - Recommendation: Compute timeline diagnostics in the investigation script (R/114), not in `get_zip9_at_date()`. The utility function should be single-purpose (lookup); diagnostics are a reporting concern.

---

## Sources

### Primary (HIGH confidence)
- `R/106_zip_change_frequency.R` — probe gate, vroom load, normalize_zip*, add_styled_sheet, xlsx pattern, suppress_small
- `R/utils/utils_format.R` — module structure template
- `R/39_run_all_investigations.R` — registration pattern and current last entry
- `R/88_smoke_test_comprehensive.R` — section numbering (last section 15aa)
- `R/SCRIPT_INDEX.md` — confirmed next script number (114) and table format

### Secondary (MEDIUM confidence)
- openxlsx2 `wb_load()` + `wb_save()` pattern: confirmed from R/106's use of `wb_workbook()` + `wb_save()` for the new case; `wb_load()` is the standard openxlsx2 function for opening existing workbooks (consistent with package documentation).

---

## Metadata

**Confidence breakdown:**
- Script number (114): HIGH — confirmed by listing R/ directory; 113 is the last numbered script
- R/88 section (15ab): HIGH — confirmed by grep of all SECTION 15 entries; 15aa is last
- Algorithm (interval + fallback): HIGH — directly from CONTEXT.md locked decisions D-02/D-03/D-04
- add_styled_sheet reuse: HIGH — function signature verified from R/106 source
- wb_load append pattern: HIGH — standard openxlsx2 API, confirmed by project's existing wb_save usage

**Research date:** 2026-07-25
**Valid until:** 2026-08-25 (stable codebase; only invalidated by concurrent edits to R/39, R/88, or SCRIPT_INDEX)
