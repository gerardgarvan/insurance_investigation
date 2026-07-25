# Phase 137: read-zip9-temporal-assignment - Context

**Gathered:** 2026-07-25
**Status:** Ready for planning

<domain>
## Phase Boundary

A **date-keyed ZIP9/ZIP5 lookup utility** built on `LDS_ADDRESS_HISTORY`. Given any
`(patient_ID, date)` pair, the utility returns the ZIP9 (and ZIP5) that was active for
that patient at that date, using interval overlap (`ADDRESS_PERIOD_START ≤ date <
ADDRESS_PERIOD_END`) with a most-recent-before-date fallback.

**In scope:**
- A shared R utility function `get_zip9_at_date(ids, dates)` in a new module
  `R/utils/utils_address.R`
- A new investigation script `R/NN` (next available number) that validates the function
  and adds a diagnostic sheet to the existing `R/106` xlsx
- Address timeline diagnostics per patient (gaps, overlaps, missing period-ends) appended
  as a new sheet to `output/zip_change_frequency.xlsx`
- Probe-first gate (graceful exit if `LDS_ADDRESS_HISTORY` absent)
- Registration in `R/39`, `R/88`, and `R/SCRIPT_INDEX.md`

**Out of scope:**
- Computing any SES index (ADI/SVI/SDI) — that is a future phase
- Adding `LDS_ADDRESS_HISTORY` to the permanent `PCORNET_TABLES` / DuckDB load set
- Adding ZIP9 columns to the cohort RDS (that belongs to the SES index phase)

</domain>

<decisions>
## Implementation Decisions

### Temporal anchor
- **D-01:** ZIP9 assignment is **per-query-date, not static per patient**. The utility
  accepts any vector of `(ID, date)` pairs and returns the ZIP9/ZIP5 active at each
  date. No single clinical anchor is baked in — callers supply the date.

### Assignment logic
- **D-02:** Primary rule — **interval overlap**: `ADDRESS_PERIOD_START ≤ date <
  ADDRESS_PERIOD_END`. The address record whose period spans the query date is selected.
- **D-03:** Fallback when no interval covers the query date: **most-recent
  `ADDRESS_PERIOD_START` on or before date**. If no address record precedes the date,
  return `NA` for both ZIP9 and ZIP5.
- **D-04:** When multiple records cover the same date (overlapping periods), select the
  one with the most recent `ADDRESS_PERIOD_START` (tie-break by recency).

### Output form
- **D-05:** Delivered as an **R utility function** `get_zip9_at_date(ids, dates)` in
  `R/utils/utils_address.R`. Returns a tibble with columns `ID`, `query_date`, `ZIP9`,
  `ZIP5`, `match_type` (one of: `"interval"`, `"most_recent_before"`, `"none"`).
- **D-06:** The function reads `LDS_ADDRESS_HISTORY` from `CONFIG$data_dir` directly
  (not via `get_pcornet_table()`, consistent with R/106). It is NOT precomputed/cached;
  callers load on demand.

### Script & registration
- **D-07:** New investigation script `R/NN_zip9_temporal_lookup.R` (next available
  number after 106). Validates `get_zip9_at_date()` with a sample call, logs diagnostics
  to console. Registered in `R/39`, `R/88` (new section), and `R/SCRIPT_INDEX.md`.
- **D-08:** The new script uses the same **probe-first gate** as R/106: if
  `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` is absent, log a clear message and exit
  gracefully (no crash, no `stop()`).

### Address pattern summary
- **D-09:** Per-patient timeline diagnostics characterizing how address records connect:
  - % of patients with gaps between periods (no record covers some dates)
  - % of patients with overlapping periods
  - % of records missing `ADDRESS_PERIOD_END`
  - Summary of period count distribution per patient
- **D-10:** Output appended as a **new sheet** (e.g., "Address Timeline Diagnostics")
  to the **existing `output/zip_change_frequency.xlsx`** produced by R/106. Follows
  `add_styled_sheet()` look-and-feel.
- **D-11:** Diagnostics also logged to console (headline stats) before writing the sheet.

### Claude's Discretion
- Exact function signature (parameter names, whether to accept a data frame vs
  separate vectors)
- How to handle `ADDRESS_PERIOD_END = NA` (treat as open-ended: period extends
  indefinitely)
- Whether the per-patient timeline diagnostics are computed by the utils function or
  by the investigation script
- The exact `R/NN` number (next available after 106; check `R/SCRIPT_INDEX.md`)
- Column layout and ordering in the new xlsx sheet

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### ZIP / address data source (Phase 121 precedent)
- `R/106_zip_change_frequency.R` — existing ZIP9 investigation; defines the
  `LDS_ADDRESS_HISTORY` file path pattern, probe gate, xlsx output style, and
  address-data loading. The new script must append a sheet to its xlsx output.
- `.planning/phases/121-investigate-how-often-the-9-digit-zip-code-changes-at-the-individual-level-to-inform-the-decision-on-handling-zip-code-data-for-socioeconomic-indices/121-CONTEXT.md`
  — Phase 121 decisions: D-01 (LDS_ADDRESS_HISTORY as source), D-02 (probe-first gate),
  D-03 (DEMOGRAPHIC is NOT a valid source), D-04/D-05 (ZIP9 vs ZIP5 granularity).

### Existing utils modules (for naming and pattern consistency)
- `R/utils/utils_format.R` — canonical pattern for a new utils module (created Phase 135/136)
- `R/utils/utils_payer.R`, `R/utils/utils_cancer.R` — naming and structure conventions

### Probe-first gate pattern
- `R/106_zip_change_frequency.R` lines 77–113 — probe-before-use gate to mirror exactly

### Investigation script registration
- `R/39_run_all_investigations.R` — register new script (mind the single comma-less
  final-entry vector convention)
- `R/88_smoke_test_comprehensive.R` — add new structural smoke-test section
- `R/SCRIPT_INDEX.md` — add new script row to Post-Renumber Investigations (100+) table

### Config / data access
- `R/00_config.R` §3 — PCORNET_TABLES / PCORNET_PATHS; `LDS_ADDRESS_HISTORY` is NOT
  listed — read directly by path from `CONFIG$data_dir`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/106_zip_change_frequency.R`: probe gate, `LDS_ADDRESS_HISTORY` loading, xlsx output
  via `add_styled_sheet()`, ZIP normalization, console headline-stats pattern
- `R/utils/utils_format.R`: model for a new `utils_address.R` module
- `R/utils/utils_treatment.R`: `get_hl_patient_ids()`, `safe_table()`
- `R/utils/utils_assertions.R`: input-validation helpers

### Established Patterns
- **Probe-first gate**: check file exists → quit(status=0) if absent; no crash
- **Styled xlsx**: `openxlsx2` + `add_styled_sheet()`, dark-gray headers, frozen panes
- **Investigation scripts**: read-only, self-bootstrapping (source `R/00_config.R`),
  registered in R/39 + R/88 + R/SCRIPT_INDEX.md
- **HIPAA**: patient counts 1–10 suppressed in shareable output
- **Patient ID column**: `ID` (not `PATID`)

### Integration Points
- Output xlsx: `output/zip_change_frequency.xlsx` — new sheet appended, not a new file
- `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` read directly from `CONFIG$data_dir`
- `utils_address.R` sourced by the new investigation script; downstream SES scripts
  will also source it

</code_context>

<specifics>
## Specific Ideas

- `get_zip9_at_date()` should return a `match_type` column so callers can distinguish
  interval matches from most-recent-before fallbacks from NAs — useful for quality
  assessment in downstream SES scripts.
- Address timeline diagnostic sheet mirrors the styled look of R/106's existing sheets.
- `ADDRESS_PERIOD_END = NA` should be treated as open-ended (the period is still active).

</specifics>

<deferred>
## Deferred Ideas

- Computing and attaching ADI/SVI/SDI scores to the cohort — future SES index phase
- Adding `LDS_ADDRESS_HISTORY` to `PCORNET_TABLES` / DuckDB permanent load set
- Adding ZIP9 columns (ZIP9_AT_DX, ZIP9_AT_TX) to the cohort RDS
- Building a local fixture for `LDS_ADDRESS_HISTORY` for end-to-end local testing

</deferred>

---

*Phase: 137-read-zip9-temporal-assignment*
*Context gathered: 2026-07-25*
