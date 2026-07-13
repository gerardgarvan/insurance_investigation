# Phase 121: Investigate 9-Digit ZIP Change Frequency - Research

**Researched:** 2026-07-13
**Domain:** PCORnet CDM LDS_ADDRESS_HISTORY / ZIP stability analysis / R investigation script
**Confidence:** HIGH (project conventions); MEDIUM (LDS_ADDRESS_HISTORY CDM spec — PDFs unreadable; spec assembled from web search + CHOP data-models service)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Source of truth is PCORnet `LDS_ADDRESS_HISTORY` (the only CDM table with time-varying 9-digit ZIP: `ADDRESS_ZIP9` + `ADDRESS_PERIOD_START` / `ADDRESS_PERIOD_END`, plus `ADDRESS_PREFERRED` / `ADDRESS_USE`).
- **D-02:** Probe-first pattern (mirror Phase 119's R/103 diagnostic gate): the script FIRST checks whether `LDS_ADDRESS_HISTORY` (or an equivalent raw address CSV) exists in the HiPerGator extract directory before attempting analysis. If absent, it reports that clearly and exits gracefully (no crash) rather than assuming.
- **D-03:** The loaded `DEMOGRAPHIC` table is NOT a valid source for this question — it holds exactly one 5-digit `ZIP_CODE` per patient with no time dimension (confirmed: `DEMOGRAPHIC_values.csv` shows 5-digit values, 25.1% NA). Phase 116 (R/100 RUCA) used `DEMOGRAPHIC.ZIP_CODE` truncated to 5 digits — that is the carried-forward precedent, and precisely the limitation this phase investigates.
- **D-04:** Measure change frequency at BOTH granularities: ZIP9 (distinct full 9-digit values per patient) and ZIP5 (distinct 5-digit values per patient).
- **D-05:** Report both side-by-side so the SES-index decision can be made with full information. A ZIP9->ZIP9 move within the same ZIP5 is a ZIP9 change but NOT a ZIP5 change — surface that distinction.
- **D-06:** Produce a styled multi-sheet xlsx + console summary (match R/100 RUCA output style using `openxlsx2` + the `add_styled_sheet()` helper pattern).
- **D-07:** Suggested sheets: (1) per-patient distinct-ZIP-count distribution at ZIP9 and ZIP5; (2) % of patients who ever changed + change-count histogram; (3) time-between-changes (derived from `ADDRESS_PERIOD_START`); (4) tie-break comparison (most-recent vs modal disagreement rate); (5) a Recommendation / Metadata sheet.
- **D-08:** Follow the project's investigation-script convention: new `R/NN` script, registered in `R/39_run_all_investigations.R`, with a new `R/88` smoke-test section (continuing the section-suffix sequence, e.g., 15s).
- **D-09:** Console logs headline stats (cohort size, % ever-changed at ZIP9/ZIP5, median distinct ZIPs) before writing the xlsx.
- **D-10:** Scope to all patients with address history in `LDS_ADDRESS_HISTORY` (broadest denominator), not just the HL cohort.
- **D-11:** For the single-ZIP tie-break, the report presents options without committing: quantify how often most-recent (via `ADDRESS_PERIOD_START` / `ADDRESS_PREFERRED`) vs modal (most-frequently-recorded) would select a different ZIP. The decision is left to the downstream SES-index phase.

### Claude's Discretion

- Exact sheet layout, column ordering, and styling details (follow R/100 conventions)
- HIPAA suppression of small ZIP cells (1-10) in any patient-count output
- Handling of NA / malformed ZIP values (define and log an explicit rule)
- The `R/NN` number and `R/88` section suffix (next available in sequence)

### Deferred Ideas (OUT OF SCOPE)

- Actually computing and attaching a socioeconomic index (ADI/SVI/SDI) to the cohort
- Permanently adding `LDS_ADDRESS_HISTORY` to `PCORNET_TABLES` / DuckDB ingest
- Time-varying ZIP (and time-varying SES index) in the production cohort pipeline
- Building a local fixture for `LDS_ADDRESS_HISTORY` so R/88 can run this section end-to-end locally
</user_constraints>

---

## Summary

Phase 121 is a read-only investigation script (`R/106_zip_change_frequency.R`) that probes for `LDS_ADDRESS_HISTORY`, loads it if present, and quantifies per-patient ZIP stability at both ZIP9 and ZIP5 granularity. The outputs are a 5-sheet styled xlsx + console headline stats, following the R/100 RUCA investigation pattern exactly.

The script is NOT part of the permanent PCORNET_TABLES load set. It reads the CSV directly by path using a `file.exists()` probe (the D-02 / R/103 pattern). Because `LDS_ADDRESS_HISTORY` is a PCORnet CDM v6/v7 table that was NOT in the original extract order but may exist in the same HiPerGator directory, the probe-and-report-gracefully pattern is essential. Locally, the probe returns FALSE and the script exits with a clear message — all R/88 checks are therefore structural (grep-based), not runtime.

The next available R/NN number is **R/106** (R/100-R/105 are occupied). The next available R/88 section suffix is **15s** (15r = Phase 120, 15q = quick-i1e, 15p = Phase 119; 15s is the next in the alphabetic sequence).

**Primary recommendation:** Build R/106 as a near-clone of R/103 (probe gate) + R/100 (styled xlsx output), loading the address CSV directly, computing per-patient distinct-ZIP counts and change metrics, and writing a 5-sheet openxlsx2 workbook.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation, group_by/summarise | Established project pattern; named predicate style |
| stringr | 1.5.1+ | ZIP normalization (str_sub, str_pad, str_trim, str_detect) | Used identically in R/100 for ZIP_CODE normalization |
| glue | 1.8.0 | Console logging messages | Used in every investigation script |
| openxlsx2 | latest | Styled xlsx output | R/100 `add_styled_sheet()` pattern; already installed |
| lubridate | 1.9.3+ | Date arithmetic (time-between-changes from ADDRESS_PERIOD_START) | Parse date strings, compute interval in days |
| vroom / read.csv | 1.7.0+ / base | CSV loading for LDS_ADDRESS_HISTORY | vroom preferred for large tables; base read.csv fallback if vroom unavailable |
| tidyr | latest | pivot_wider for distribution tables | Used in R/100 `build_crosstab()` |
| tibble | 3.2.1+ | Data frame construction | Included in tidyverse |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| forcats | 1.0.0+ | Reorder factor levels for histogram output | If change-count histogram needs ordered x-axis |

### Already Available (from R/00_config.R auto-source chain)

These are available via `source("R/00_config.R")` — no explicit library() call needed:
- `get_pcornet_table()` from `utils_duckdb.R` — NOT used for `LDS_ADDRESS_HISTORY` (not in PCORNET_TABLES); referenced only for the DEMOGRAPHIC fallback mention
- `parse_pcornet_date()` from `utils_dates.R` — available for parsing ADDRESS_PERIOD_START/END

**Installation:** No new packages required. All dependencies are already installed in the project renv.

---

## Architecture Patterns

### Script Structure (mirror R/103 probe gate + R/100 xlsx output)

```
R/106_zip_change_frequency.R
  SECTION 1: SETUP AND LIBRARIES
  SECTION 2: CONSTANTS AND PROBE
    - probe file.exists() for LDS_ADDRESS_HISTORY CSV
    - if absent: message + quit(status=0) gracefully
  SECTION 3: LOAD ADDRESS TABLE
    - vroom/read.csv with explicit col_types
    - validate: ID column present, ADDRESS_ZIP9 present
  SECTION 4: HELPER FUNCTIONS
    - normalize_zip9(): trim, remove hyphen, pad to 9 digits
    - normalize_zip5(): str_sub(zip9_clean, 1, 5)
    - NA rules: blank / "00000" / non-numeric -> NA
  SECTION 5: PER-PATIENT ZIP METRICS
    - group_by(ID), summarise distinct ZIP9/ZIP5 counts
    - n_zip9_distinct, n_zip5_distinct, zip9_ever_changed, zip5_ever_changed
    - n_address_records (total rows per patient)
  SECTION 6: CHANGE-COUNT DISTRIBUTIONS (Sheet 1)
    - distribution table: n_distinct_zip9 x n_patients, n_distinct_zip5 x n_patients
  SECTION 7: CHANGE RATES + HISTOGRAM (Sheet 2)
    - % ever changed at ZIP9, at ZIP5, at ZIP9-only (not ZIP5)
    - change-count histogram (0 changes / 1 / 2 / 3+ changes)
  SECTION 8: TIME-BETWEEN-CHANGES (Sheet 3)
    - parse ADDRESS_PERIOD_START, arrange by ID + date
    - lead() to compute gap in days to next start
    - distribution: median, p25/p75, max, histogram buckets
    - guard: patients with only 1 address record -> NA gap
  SECTION 9: TIE-BREAK COMPARISON (Sheet 4)
    - for patients with 2+ ZIP9 values:
      most_recent = ZIP9 where ADDRESS_PERIOD_START == max(ADDRESS_PERIOD_START)
                    OR ADDRESS_PREFERRED == "Y"
      modal       = ZIP9 appearing most frequently
    - n_agree, n_disagree, pct_disagree
    - note: if ADDRESS_PREFERRED is all NA/blank, fall back to recency only
  SECTION 10: WRITE STYLED XLSX (5 sheets via add_styled_sheet())
    - Sheet 1: ZIP Change Distribution (patient-level counts)
    - Sheet 2: Change Rates & Histogram
    - Sheet 3: Time Between Changes
    - Sheet 4: Tie-Break Comparison
    - Sheet 5: Recommendation & Metadata
  SECTION 11: CONSOLE SUMMARY (D-09)
    - n_patients_total, pct_ever_changed_zip9, pct_ever_changed_zip5,
      median_distinct_zip9, n_with_na_zip
```

### Pattern 1: Probe-First Gate (from R/103)

```r
# Source: R/103_death_cause_diagnostic.R lines 137-150 (adapted)
addr_path <- file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv")
message(glue("  CSV probe: {addr_path}"))
message(glue("  File exists? {file.exists(addr_path)}"))

if (!file.exists(addr_path)) {
  message(glue(
    "\n[R/106] LDS_ADDRESS_HISTORY not found at expected path.\n",
    "  Expected: {addr_path}\n",
    "  This table is NOT in the permanent PCORNET_TABLES load set.\n",
    "  Confirm the exact filename with the data custodian and re-run.\n",
    "  Phase 121 investigation requires HiPerGator with this file present.\n"
  ))
  quit(status = 0)
}
```

**Key detail:** Use `quit(status = 0)` not `stop()` — graceful exit, not crash, consistent with D-02.

### Pattern 2: add_styled_sheet() (from R/100, reuse verbatim)

```r
# Source: R/100_ruca_rurality_summary.R lines 343-367
# Copy the DARK_GRAY/WHITE/DARK_TEXT constants and the add_styled_sheet()
# helper definition VERBATIM into R/106. Do not import from R/100 via source()
# (investigation scripts are self-contained).
DARK_GRAY <- wb_color("FF374151")
WHITE     <- wb_color("FFFFFFFF")
DARK_TEXT <- wb_color("FF1F2937")

add_styled_sheet <- function(wb, sheet_name, title_text, subtitle_text, data_tbl) {
  # ... (verbatim from R/100 lines 343-367)
}
```

### Pattern 3: ZIP Normalization (from R/100 Section 5, adapted for ZIP9)

```r
# Source: R/100_ruca_rurality_summary.R lines 196-201 (ZIP5 path)
# For ZIP9: same logic but handle the hyphen format (NNNNN-NNNN) before sub()
normalize_zip9 <- function(zip) {
  zip %>%
    str_trim() %>%
    str_remove_all("-") %>%    # remove hyphen if present (98765-4321 -> 987654321)
    str_pad(9, pad = "0") %>%  # left-pad to 9 digits
    if_else(str_detect(., "^[0-9]{9}$"), ., NA_character_)
}

normalize_zip5 <- function(zip9_clean) {
  str_sub(zip9_clean, 1, 5)
}
```

### Pattern 4: R/39 Registration (from R/39 lines 176-196)

The `investigation_scripts` vector currently ends with `"R/105_normalize_supportive_care_meaning.R"` as the comma-less final entry (line 195-196). Adding R/106 means:
- R/105 gains a trailing comma
- R/106 becomes the new comma-less final entry

```r
# R/39 investigation_scripts vector tail — EXACT addition pattern:
  "R/105_normalize_supportive_care_meaning.R",  # add comma to this line
  "R/106_zip_change_frequency.R"                # new final entry (no trailing comma)
```

### Pattern 5: R/88 Section 15s Structure (from Section 15r, 14-check pattern)

```r
# SECTION 15s: ZIP CHANGE FREQUENCY (Phase 121) ----
message("\n[Phase 121] ZIP change frequency (R/106)...")

# Check 1: R/106 script exists
r106_exists <- file.exists("R/106_zip_change_frequency.R")
check("R/106_zip_change_frequency.R exists (Phase 121)", r106_exists)

if (r106_exists) {
  r106_lines <- readLines("R/106_zip_change_frequency.R", warn = FALSE)
  r106_text  <- paste(r106_lines, collapse = "\n")

  # Check 2:  >= 150 lines
  # Check 3:  sources R/00_config.R
  # Check 4:  file.exists() probe for LDS_ADDRESS_HISTORY CSV
  # Check 5:  quit(status = 0) graceful exit when file absent (not stop())
  # Check 6:  reads ADDRESS_ZIP9 column
  # Check 7:  reads ADDRESS_PERIOD_START column
  # Check 8:  normalize_zip9 function present (hyphen removal)
  # Check 9:  normalize_zip5 function (str_sub 1,5)
  # Check 10: NA ZIP rule logged (str_detect "^[0-9]{9}$" or equivalent)
  # Check 11: group_by(ID) ... n_distinct for per-patient counts
  # Check 12: writes xlsx via wb_save (add_styled_sheet present)
  # Check 13: HIPAA suppression pattern present (small cell suppression)
  # Check 14: no ggplot/ggsave (data output only)
} else {
  for (i in 2:14) check(paste0("R/106 dependent check #", i,
                               " -- SKIPPED (script missing)"), FALSE)
}
```

### Anti-Patterns to Avoid

- **Do not call `get_pcornet_table("LDS_ADDRESS_HISTORY")`** — this table is NOT in PCORNET_TABLES. Read the CSV directly by path.
- **Do not `stop()` on missing file** — use `quit(status = 0)` per D-02 / R/103 precedent.
- **Do not use PATID** — patient ID column is `ID` across this extract (confirmed in R/00_config.R comment and R/103 usage).
- **Do not assume ADDRESS_ZIP9 has no hyphen** — some implementations store "NNNNN-NNNN"; strip the hyphen before analysis.
- **Do not assume ADDRESS_PERIOD_END is always populated** — current addresses may have NULL/NA period end (open-ended). Guard with `is.na()`.
- **Do not hard-code the filename** — store as a constant `ADDR_FILENAME <- "LDS_ADDRESS_HISTORY_Mailhot_V1.csv"` with a comment that the actual filename is a runtime unknown (same note pattern as DEATH_CAUSE in R/00_config.R line 257).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Styled xlsx with frozen panes + dark headers | Custom openxlsx2 from scratch | `add_styled_sheet()` verbatim from R/100 | Already tested, consistent look |
| ZIP5 from ZIP9 | Custom substring logic | `str_sub(zip9_clean, 1, 5)` (R/100 pattern) | One-liner, no edge cases |
| Console logging | `print()` or `cat()` | `message(glue(...))` | Consistent with all investigation scripts |
| Date parsing of period columns | `as.Date()` directly | `parse_pcornet_date()` (available via R/00 auto-source) | Handles PCORnet multi-format date strings |

---

## LDS_ADDRESS_HISTORY Table Specification

**Source:** PCORnet CDM v6.0/v7.0; verified via CHOP data-models service and web search (MEDIUM confidence — official PDFs are binary-compressed and unreadable by WebFetch).

### Columns

| Column | Type | Max Length | Nullable | Description |
|--------|------|-----------|----------|-------------|
| ADDRESSID | Char | — | N | Arbitrary unique identifier per address record |
| PATID | Char | — | N | Links to DEMOGRAPHIC.PATID; this extract uses `ID` |
| ADDRESS_ZIP9 | Char | 9 | Y | Full 9-digit postal code. May be stored as "NNNNN-NNNN" or "NNNNNNNNN". |
| ADDRESS_ZIP5 | Char | 5 | Y | 5-digit postal code. Separate column; may differ from first-5 of ZIP9 if data entry varies. |
| ADDRESS_PERIOD_START | Date | — | Y | Initial date when this address was known to be in use |
| ADDRESS_PERIOD_END | Date | — | Y | Date address was no longer in use. **NULL/NA for current/open-ended addresses.** |
| ADDRESS_PREFERRED | Char | 2 | Y | Whether this is the preferred address. Expected values: `Y` / `N`. May be blank. |
| ADDRESS_USE | Char | 2 | Y | Classification of address use (home, work, temporary, etc.). Updated valueset in CDM v7. |
| ADDRESS_STATE | Char | 2 | Y | 2-letter postal state abbreviation |
| ADDRESS_CITY | Char | — | Y | City name |
| ADDRESS_TYPE | Char | 2 | Y | Address type |
| ADDRESS_COUNTY | Char | — | Y | County (added in CDM v7) |

**CDM v7 additions to this table:** STATE_FIPS, COUNTY_FIPS, RUCA_ZIP, CURRENT_ADDRESS_FLAG (MEDIUM confidence, from web search summary).

### Multi-Address Semantics

- **One row per address period per patient.** A patient with 3 distinct addresses over time has 3+ rows with different ADDRESSID values and different ADDRESS_PERIOD_START dates.
- **Ordering:** Sort by `ID`, then `ADDRESS_PERIOD_START` ascending to get chronological sequence.
- **Open-ended current address:** ADDRESS_PERIOD_END = NA means the address is presumed current.
- **Multiple records same start date:** Possible if ADDRESS_USE differs (e.g., home vs work). Filter or prioritize by ADDRESS_PREFERRED = "Y" / ADDRESS_USE = home equivalent.

### Patient ID Column

Per R/00_config.R (confirmed): **`ID`** (not PATID) across this extract. The CDM spec uses `PATID`; this extract uses `ID`. R/106 must use `ID` throughout.

### Expected HiPerGator Filename

`LDS_ADDRESS_HISTORY_Mailhot_V1.csv` — follows the `{TABLE}_Mailhot_V1.csv` naming convention established in PCORNET_PATHS. This is a runtime unknown: the actual filename must be confirmed at execution time (identical caveat to DEATH_CAUSE in Phase 119). R/106 should probe this default path and note the override pattern in a comment.

---

## ADI / SVI Granularity Context (why both ZIP9 and ZIP5 matter)

This section exists only to frame why D-04 (measure BOTH granularities) is the right decision. The planner does not need to implement anything about ADI/SVI in this phase.

| Index | Geographic Unit | Typical Key | Implication for ZIP data |
|-------|----------------|-------------|--------------------------|
| ADI (Area Deprivation Index) | Census block group | ZIP+4 (9-digit) maps to block group | ZIP9 is the relevant granularity; ZIP5-only loses block-group precision |
| SVI (CDC Social Vulnerability Index) | Census tract (~4,000 people) | ZIP5 maps to tract | ZIP5 is sufficient for SVI linkage |
| SDI (Social Deprivation Index) | Census tract | ZIP5 adequate | ZIP5 sufficient |

**Key insight:** If the downstream SES phase chooses ADI (block-group precision), the report must show how stable ZIP9 is — even patients who never change ZIP5 may change ZIP9 (moving within the same ZIP code area). D-04 / D-05 directly serve this decision. A patient whose ZIP9 changes but ZIP5 does not is a ZIP9-change-only case — surface that count.

Confidence: HIGH for ADI/SVI geographic units (multiple verified web sources).

---

## Suggested Metrics and Sheet Design

### Sheet 1: ZIP Change Distribution (patient-level)

| n_distinct_zip9 | n_patients | pct_patients | n_distinct_zip5 | ... |
|---|---|---|---|---|
| 1 (never changed) | X | Y% | ... | ... |
| 2 | X | Y% | ... | ... |
| 3+ | X | Y% | ... | ... |
| Total | X | 100% | ... | ... |

Report ZIP9 and ZIP5 side-by-side in the same table (D-05).

### Sheet 2: Change Rate Summary

Headline statistics table:
- Total patients in LDS_ADDRESS_HISTORY
- % with any ZIP9 change (n_distinct_zip9 > 1)
- % with any ZIP5 change (n_distinct_zip5 > 1)
- % with ZIP9-change-only (n_distinct_zip9 > 1 AND n_distinct_zip5 == 1)
- Median, p25, p75 of n_distinct_zip9
- Median, p25, p75 of n_distinct_zip5

Change-count histogram table (n_changes = n_distinct - 1):

| n_zip9_changes | n_patients |
|---|---|
| 0 | ... |
| 1 | ... |
| 2 | ... |
| 3+ | ... |

HIPAA: suppress rows where n_patients <= 10 per project convention.

### Sheet 3: Time Between Changes

Derived from ADDRESS_PERIOD_START. For each patient with 2+ records ordered by start date, compute `lead(ADDRESS_PERIOD_START) - ADDRESS_PERIOD_START` in days.

- Patients with 1 address record: gap = NA (document count)
- Patients with ADDRESS_PERIOD_START all NA: gap = NA (document count)
- Distribution table: median gap days, p25, p75, min, max, n_gaps

Histogram buckets: <30 days, 30-180 days, 181-365 days, 1-2 years, >2 years.

### Sheet 4: Tie-Break Comparison

For patients with 2+ distinct ZIP9 values:
- most_recent_zip9: the ZIP9 on the record with the latest ADDRESS_PERIOD_START (break ties by ADDRESS_PREFERRED = "Y" if available)
- modal_zip9: the ZIP9 appearing most often (ties broken by recency)
- agree: most_recent == modal
- disagree: most_recent != modal (quantify; these are the patients where tie-break rule matters)

Report: n_patients_evaluated, n_agree, n_disagree, pct_disagree.

Note: if ADDRESS_PREFERRED is uniformly NA/blank in the extract, document that and fall back to ADDRESS_PERIOD_START recency alone.

### Sheet 5: Recommendation & Metadata

Table of run metadata (mirroring R/100 Sheet 5):
- Source file path
- Row count in LDS_ADDRESS_HISTORY
- Distinct patient count
- Run date
- NA ZIP9 count
- NA ZIP5 count
- Script version / phase

Written recommendation text (2-3 sentences): based on the % ever-changed and the tie-break disagreement rate, state whether a single ZIP per patient is defensible for SVI (ZIP5 stable) and/or whether ZIP9 change frequency warrants time-varying handling for ADI.

---

## Registration Mechanics

### R/NN Number

**R/106** is the next available number. Confirmed: R/100 through R/105 are all occupied (R/SCRIPT_INDEX.md Post-Renumber Investigations count: 6, scripts R/100-R/105). R/106 is the next slot.

### R/88 Section Suffix

**15s** is the next available suffix. Confirmed sequence from R/88:
- 15m = Phase 116 (RUCA)
- 15n = Phase 117 (Gantt lifespan)
- 15o = Phase 118 (death cause NHL flag)
- 15p = Phase 119 (death cause fix)
- 15q = quick-i1e (Gantt entire history)
- 15r = Phase 120 (Supportive Care Normalized Meaning)
- **15s = Phase 121 (ZIP change frequency)** — next in sequence

### R/88 Section Placement

Insert Section 15s AFTER Section 15r (line 2499 in current R/88, which is the blank line after the `else` block closes for Section 15r) and BEFORE Section 15g (line 2500). Follow the exact same 14-check structure as Section 15r.

### R/39 Vector Update

Current final entry (comma-less): `"R/105_normalize_supportive_care_meaning.R"` at line 195.
- Line 195 gains a trailing comma
- Line 196 (new): `"R/106_zip_change_frequency.R"` (no trailing comma)
- Vector length: 20 entries (was 19)

### SCRIPT_INDEX.md Update

Add row to Post-Renumber Investigations (100+) table:
- Script: `R/106_zip_change_frequency.R`
- Purpose: ZIP change frequency investigation — probes LDS_ADDRESS_HISTORY, measures per-patient distinct ZIP9/ZIP5 counts, time-between-changes, and tie-break disagreement rate. Produces 5-sheet styled xlsx + console summary to inform downstream SES-index ZIP handling decision.
- Phase: 121

Update counts: 100+ count 6 -> 7, Total 92 -> 93.

---

## Common Pitfalls

### Pitfall 1: ZIP9 stored with hyphen

**What goes wrong:** ADDRESS_ZIP9 in some PCORnet implementations stores "98765-4321" (9 chars including hyphen) or "987654321" (9 numeric chars). If you do `str_sub(zip9, 1, 9)` without stripping the hyphen first, you keep the hyphen and break 9-digit numeric validation.

**How to avoid:** `str_remove_all("-")` BEFORE `str_pad(9, pad="0")`. The regex `^[0-9]{9}$` then catches only valid 9-digit values.

**Warning signs:** ZIP9 values that pass length-9 check but contain "-" will fail the `^[0-9]{9}$` check if you don't pre-strip.

### Pitfall 2: ADDRESS_PERIOD_END is NA for current addresses

**What goes wrong:** A patient's current (most recent) address has no end date. Code that tries to use PERIOD_END to compute duration will produce NA gaps for current records, which is correct behavior — but if you filter to `!is.na(ADDRESS_PERIOD_END)` you silently drop the most recent record.

**How to avoid:** Do NOT filter on ADDRESS_PERIOD_END. Use ADDRESS_PERIOD_START only for chronological ordering and gap computation. Document in console output: "N patients have at least one open-ended record (PERIOD_END = NA)."

### Pitfall 3: ADDRESS_ZIP5 vs first-5 of ADDRESS_ZIP9

**What goes wrong:** ADDRESS_ZIP5 is a separate column and may not always equal `str_sub(ADDRESS_ZIP9, 1, 5)` due to data entry. The CDM spec lists both as distinct fields. Using one as a proxy for the other will produce silent mismatches.

**How to avoid:** For ZIP5 analysis, use the ADDRESS_ZIP5 column if it is non-NA. If ADDRESS_ZIP5 is predominantly NA, fall back to deriving from ADDRESS_ZIP9. Log a count of records where ADDRESS_ZIP5 != str_sub(ADDRESS_ZIP9, 1, 5) to surface data quality.

**Decision to document:** R/106 should explicitly state which source it uses for ZIP5 in the Recommendation sheet: "ZIP5 sourced from ADDRESS_ZIP5 column (N records); derived from ADDRESS_ZIP9 for M records where ZIP5 was blank."

### Pitfall 4: ID vs PATID

**What goes wrong:** The PCORnet CDM spec uses `PATID` as the patient identifier. This extract uses `ID`. Joining LDS_ADDRESS_HISTORY to any other table using `PATID` will fail silently (no rows matched).

**How to avoid:** Use `ID` throughout R/106. Confirmed in R/00_config.R comment ("NOTE: Patient ID column is 'ID' (not 'PATID') across all tables") and in every 100+ series script.

### Pitfall 5: NA ZIP handling and HIPAA suppression

**What goes wrong:** (a) NA ZIP9 values are counted as a "distinct ZIP value" if not removed before `n_distinct()`. (b) ZIP-level patient counts (e.g., how many patients have a given ZIP9) may expose cells with 1-10 patients — HIPAA risk.

**How to avoid:**
- (a) Filter `!is.na(zip9_norm)` BEFORE computing per-patient distinct counts. Log the NA count.
- (b) In any output that includes ZIP codes themselves (not just counts), suppress rows where n_patients <= 10. The Sheet 1/2 distribution tables don't expose individual ZIPs (they show counts of patients with N distinct ZIPs), so suppression only applies to the tie-break sheet if individual ZIPs are shown — avoid showing individual ZIPs altogether in the output.

### Pitfall 6: Local fixture has no LDS_ADDRESS_HISTORY

**What goes wrong:** R/88 Section 15s structural checks may attempt to verify things that require runtime data. The local test fixture (`tests/fixtures/`) does NOT have a `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` file.

**How to avoid:** All 14 Section 15s checks must be structural-only (grep-based against R/106 file text), plus one runtime check gated with `!IS_LOCAL && file.exists(OUTPUT_XLSX)` — matching the R/88 Section 15p Check 14 IS_LOCAL-gate pattern.

### Pitfall 7: Multiple address records per patient on the same date

**What goes wrong:** A patient may have two address records with the same ADDRESS_PERIOD_START (e.g., a home address and a work address both starting on the same date). If you use `lead(ADDRESS_PERIOD_START)` to compute gaps, duplicate dates will produce 0-day gaps.

**How to avoid:** When computing time-between-changes, operate on the distinct set of ADDRESS_PERIOD_START values per patient (after deduplication), not on all rows. Or note this in the output.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 121 produces a new R script that uses only already-installed packages (dplyr, stringr, glue, openxlsx2, lubridate, vroom, tidyr). No new external tools or services required. LDS_ADDRESS_HISTORY is a runtime dependency that the probe-first pattern handles gracefully.

---

## Validation Architecture

Nyquist validation is enabled (no explicit `false` in `.planning/config.json` — key absent, treated as enabled per spec). However, this is a read-only investigation phase with no HiPerGator data locally. The validation approach follows the established pattern for post-renumber investigation scripts:

### Test Framework

| Property | Value |
|----------|-------|
| Framework | R/88_smoke_test_comprehensive.R (structural grep-based) |
| Config file | none (standalone Rscript) |
| Quick run command | `Rscript R/88_smoke_test_comprehensive.R` |
| Full suite command | `Rscript R/88_smoke_test_comprehensive.R` |

### Phase Requirements -> Test Map

| Behavior | Test Type | Command | Notes |
|----------|-----------|---------|-------|
| R/106 exists | structural | R/88 Check 1 (file.exists) | Locally runnable |
| Probe gate present (file.exists + quit) | structural | R/88 Check 4-5 (grep) | Locally runnable |
| ZIP normalization (hyphen strip + pad) | structural | R/88 Check 8-10 (grep) | Locally runnable |
| xlsx written via add_styled_sheet | structural | R/88 Check 12 (grep) | Locally runnable |
| HIPAA suppression pattern | structural | R/88 Check 13 (grep) | Locally runnable |
| Output xlsx non-zero rows | runtime | R/88 Check 14 (IS_LOCAL gated) | HiPerGator only |

### Wave 0 Gaps

- [ ] R/106_zip_change_frequency.R — primary deliverable; does not exist yet
- [ ] R/88 Section 15s — 14 structural checks; does not exist yet
- [ ] R/39 investigation_scripts update — R/105 gains comma, R/106 added
- [ ] R/SCRIPT_INDEX.md row for R/106 (count 6->7, Total 92->93)

---

## Open Questions

1. **Exact filename of LDS_ADDRESS_HISTORY on HiPerGator**
   - What we know: default naming convention is `LDS_ADDRESS_HISTORY_Mailhot_V1.csv`; this may or may not match the actual HiPerGator filename
   - What's unclear: whether the data custodian named it differently (same situation as DEATH_CAUSE in Phase 119)
   - Recommendation: R/106 probes the default path, exits gracefully if absent, and comments the override pattern. The user runs it on HiPerGator to confirm.

2. **Whether ADDRESS_ZIP5 column is populated or all-blank in the extract**
   - What we know: CDM spec defines ADDRESS_ZIP5 as a separate 5-char column
   - What's unclear: this particular OneFlorida+ extract may have ADDRESS_ZIP5 blank/NA and rely on ADDRESS_ZIP9 alone
   - Recommendation: R/106 should log counts of non-NA ADDRESS_ZIP5 vs non-NA ADDRESS_ZIP9 after loading, and derive ZIP5 from ZIP9 for any records where ADDRESS_ZIP5 is blank.

3. **Whether ADDRESS_PREFERRED is populated**
   - What we know: CDM spec has ADDRESS_PREFERRED with expected values Y/N; in practice many extracts leave this blank
   - What's unclear: the OneFlorida+ implementation's actual fill rate
   - Recommendation: R/106 logs `n_preferred_Y <- sum(addr$ADDRESS_PREFERRED == "Y", na.rm=TRUE)` and falls back to pure recency (ADDRESS_PERIOD_START) if ADDRESS_PREFERRED is <5% populated.

4. **Whether the scope (all patients in LDS_ADDRESS_HISTORY) is really broader than the PCORNET_TABLES cohort**
   - What we know: D-10 specifies all patients with address history, not just HL cohort
   - What's unclear: whether LDS_ADDRESS_HISTORY is limited to the same cohort as the rest of the extract or truly all patients
   - Recommendation: The script reports both total patient count AND the overlap with HL cohort patient IDs (if `get_hl_patient_ids()` is available) as a footnote in the Metadata sheet.

---

## Sources

### Primary (HIGH confidence)

- R/100_ruca_rurality_summary.R (read directly) — `add_styled_sheet()` signature, ZIP normalization pattern, `build_crosstab()`, console logging convention
- R/103_death_cause_diagnostic.R (read directly) — probe-first `file.exists()` gate, `quit(status=0)` graceful exit pattern, self-bootstrap DuckDB pattern
- R/39_run_all_investigations.R (read directly) — `investigation_scripts` vector, comma-less final entry convention, 19 current entries -> 20 with R/106
- R/88_smoke_test_comprehensive.R Sections 15r, 15q, 15p (read directly) — 14-check structural section template, IS_LOCAL runtime gate pattern, else-branch for missing script
- R/SCRIPT_INDEX.md (read directly) — R/100-R/105 occupied, R/106 is next; count 6, Total 92
- R/00_config.R lines 211-258 (read directly) — `{TABLE}_Mailhot_V1.csv` naming convention, `ID` not PATID, PCORNET_TABLES list, override pattern for non-standard filenames
- .planning/phases/121-CONTEXT.md (read directly) — all 11 decisions D-01..D-11

### Secondary (MEDIUM confidence)

- CHOP data-models-service.research.chop.edu PCORnet v6.0.0 — LDS_ADDRESS_HISTORY column definitions (ADDRESSID, PATID, ADDRESS_ZIP9, ADDRESS_ZIP5, ADDRESS_PERIOD_START, ADDRESS_PERIOD_END, ADDRESS_PREFERRED, ADDRESS_USE, ADDRESS_STATE, ADDRESS_CITY, ADDRESS_TYPE) and multi-address semantics
- PCORnet CDM v7.0 web search summary — LDS_ADDRESS_HISTORY introduced in v7.0; ADDRESS_COUNTY, CURRENT_ADDRESS_FLAG, STATE_FIPS, COUNTY_FIPS, RUCA_ZIP added; ADDRESS_USE valueset updated
- ADI/SVI geographic unit sources — multiple PubMed/IHPI sources confirming ADI at block group (ZIP+4 resolution) and SVI at census tract (ZIP5 adequate)

### Tertiary (LOW confidence)

- PCORnet v7.0 PDF specification (official source but unreadable by WebFetch — binary PDF) — column-level details for ADDRESS_PREFERRED and ADDRESS_USE allowable values not independently confirmed

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages already in project renv; patterns copied from existing scripts
- Architecture: HIGH — directly derived from R/103 (probe pattern) and R/100 (xlsx pattern)
- LDS_ADDRESS_HISTORY spec: MEDIUM — CDM data-models service verified column names and semantics; exact value sets for ADDRESS_PREFERRED/ADDRESS_USE not confirmed from PDFs
- ADI/SVI granularity: HIGH — multiple independent sources agree
- Registration mechanics (R/106, Section 15s): HIGH — derived from direct reading of R/88, R/39, SCRIPT_INDEX

**Research date:** 2026-07-13
**Valid until:** 2026-08-13 (stable ecosystem; R/88 section numbering is project-internal and changes only when new phases add sections)
