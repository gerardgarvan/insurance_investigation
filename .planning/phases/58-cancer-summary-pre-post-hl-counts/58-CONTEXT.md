# Phase 58: Cancer Summary Pre/Post HL Counts - Context

**Gathered:** 2026-05-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Update cancer_summary_table.xlsx to show per-cancer-code patient counts split by timing relative to first HL diagnosis date (pre-HL, post-HL, both). Population is the confirmed 7-day HL cohort. Counts only, no percentages. C81 (Hodgkin Lymphoma) row excluded since it's the reference anchor. New standalone script and output file — does not modify R/55 or R/56 outputs.

</domain>

<decisions>
## Implementation Decisions

### Column Structure
- **D-01:** Keep existing count columns from R/55: Total Patients, Confirmed (2+ Dates), Confirmed (7-Day Gap), Total Records
- **D-02:** Drop all percentage and date-stat columns: Rate (2+ Dates), Rate (7-Day Gap), Mean/Median Unique Dates, Mean/Median Dates (7-Day Sep)
- **D-03:** Add three new count columns: Pre-HL Count, Post-HL Count, Both Count
- **D-04:** "Both" = intersection — patient had that cancer code at least once before AND at least once after first_hl_dx_date. Pre and Post are non-exclusive (Pre + Post - Both = unique patients with temporal data)
- **D-05:** Counts only — no percentages anywhere in the table

### Column Ordering
- **D-06:** Category Summary: Cancer Site Category | Total Patients | Confirmed (2+ Dates) | Confirmed (7-Day Gap) | Pre-HL | Post-HL | Both | Total Records
- **D-07:** Code Summary: ICD-10 Code | Cancer Site Category | Total Patients | Confirmed (2+ Dates) | Confirmed (7-Day Gap) | Pre-HL | Post-HL | Both | Total Records

### Same-Day Handling
- **D-08:** Same-day = pre-HL. Pre uses DX_DATE <= first_hl_dx_date, Post uses DX_DATE > first_hl_dx_date. Consistent with R/56's strict > convention.

### HL Row Handling
- **D-09:** Exclude C81 (Hodgkin Lymphoma) rows entirely from the pre/post table. C81 is the anchor diagnosis — pre/post split is self-referential for this code. Table focuses on OTHER cancers relative to HL diagnosis.

### Patients with No Dates
- **D-10:** Patients with a cancer code but all NA DX_DATEs are excluded from Pre/Post/Both columns but still appear in Total Patients (carried forward from baseline patient-code summary).

### Sentinel Dates
- **D-11:** DX_DATEs before 1910-01-01 are excluded from pre/post counting, consistent with R/56's sentinel handling.

### Data Sources
- **D-12:** Load confirmed_hl_cohort.rds from R/55 for first_hl_dx_date — do not recompute. The pmin(DIAGNOSIS, TUMOR_REGISTRY) approach is established.
- **D-13:** Pre/post counting uses DIAGNOSIS table only (via DuckDB). TUMOR_REGISTRY is not queried for cancer codes — consistent with R/55 and R/56 pattern.

### Output Strategy
- **D-14:** New standalone script (R/58_cancer_summary_pre_post.R) producing a new file (cancer_summary_table_pre_post.xlsx). Does not modify R/55 or R/56 outputs.
- **D-15:** Two-sheet xlsx: Category Summary and Code Summary, matching R/55's two-sheet pattern.

### Styling
- **D-16:** Same styling as R/55: dark gray headers (#374151), white font, totals row with light gray fill (#E5E7EB), comma-formatted counts (#,##0), frozen header row, Calibri font.

### Claude's Discretion
- Whether to also produce a companion CSV file
- Whether to include population denominator note in the xlsx
- PREFIX_MAP handling (copy from R/55 or factor out)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Cancer summary pipeline
- `R/55_cancer_summary_refined.R` — Source of truth for cancer_summary_table.xlsx, confirmed_hl_cohort.rds, PREFIX_MAP, classify_codes(), D-code removal, cohort confirmation logic, xlsx styling pattern
- `R/56_cancer_summary_post_hl.R` — Temporal filtering pattern (DX_DATE > first_hl_dx_date), sentinel date exclusion (< 1910-01-01), post-HL re-aggregation from raw DIAGNOSIS rows

### Inputs
- `output/confirmed_hl_cohort.rds` — confirmed 7-day HL cohort with first_hl_dx_date and first_hl_dx_source (produced by R/55)
- `output/tables/cancer_summary.csv` — baseline patient-code level data (produced by R/55, for description lookup)

### Infrastructure
- `R/00_config.R` — CONFIG paths, DuckDB connection setup
- `R/01_load_pcornet.R` — get_pcornet_table(), close_pcornet_con()

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `confirmed_hl_cohort.rds`: Pre-computed artifact with ID, first_hl_dx_date, first_hl_dx_source — one row per confirmed patient
- `PREFIX_MAP` + `classify_codes()`: Cancer site category classification (duplicated in R/55 and R/56) — copy into R/58 for script independence
- `cancer_summary.csv`: Baseline patient-code level data with descriptions — can be used for description lookup
- xlsx styling pattern: DARK_HEADER_FILL, WHITE_FONT, TITLE_FONT_COLOR, TOTALS_FILL constants and openxlsx2 styling code established in R/55

### Established Patterns
- DuckDB query pattern: `get_pcornet_table("DIAGNOSIS") %>% filter(DX_TYPE == "10") %>% mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>% filter(str_detect(DX_norm, "^C"))` — standard C-code extraction
- Sentinel exclusion: `filter(DX_DATE >= as.Date("1910-01-01"))` after collecting raw rows
- D-code exclusion: `filter(!str_detect(code, "^D"))` applied at data load time
- Totals row: Computed as sums of data columns with NA for non-summable fields

### Integration Points
- Reads: confirmed_hl_cohort.rds (R/55 output), cancer_summary.csv (R/55 output), DIAGNOSIS DuckDB table
- Writes: output/tables/cancer_summary_table_pre_post.xlsx (new file)
- No upstream script modifications needed

</code_context>

<specifics>
## Specific Ideas

- The pre/post analysis tells the clinical story: what other cancers did HL patients have before vs after their HL diagnosis?
- "Both" column identifies codes that persist across the temporal boundary — potentially indicating chronic/recurring conditions
- C81 exclusion keeps the table focused on comorbid/secondary cancers relative to the HL anchor

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 58-cancer-summary-pre-post-hl-counts*
*Context gathered: 2026-05-26*
