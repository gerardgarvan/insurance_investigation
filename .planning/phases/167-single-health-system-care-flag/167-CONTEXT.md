# Phase 167: Single-Health-System Care Flag — Context

**Gathered:** 2026-10-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce a patient-level binary `single_source_care` flag — and its post-HL-anchor counterpart — by querying `ENCOUNTER.SOURCE` in DuckDB. Deliver an Excel workbook (`single_source_care_<date>.xlsx`) plus a joinable CSV and internal RDS. Phase 167 does not modify any upstream output.

</domain>

<decisions>
## Implementation Decisions

### D-167-01 (closed): SOURCE table
- ENCOUNTER only. No other CDM tables unioned.

### D-167-02 (closed): Two windows
- Whole-record and post-HL-anchor delivered as separate columns on every output row.

### Encounter filter scope (D-167-03)
- **D-167-03:** Whole-record window covers all cohort encounters whose `ADMIT_DATE` falls within the pipeline's existing analysis date range — the same bounds `R/01` applies, as reconciled in Phase 136 (`CONFIG$date_range_max`). Do not introduce a new date range.
- Encounters with a missing `ADMIT_DATE` cannot be placed in either window. Exclude them from both window computations and count them in the QC sheet.

### Anchor date source (D-167-04)
- **D-167-04:** Read `hl_anchor_date` from **R/147's anchor source** directly (same source Phase 165 and 166 use). Do **not** read it from Phase 165 or 166 output files — that would create a run-order dependency.
- Post-anchor window: `ADMIT_DATE > hl_anchor_date` (anchor day counted as before-anchor, matching Phase 165/166 convention).
- Patient has no anchor date: whole-record flag still computed; post-anchor flag = `NA` (not 0); counted in QC.
- Patient has anchor date but zero post-anchor encounters: `n_sources_post = 0`, post-anchor flag = `NA`. Zero encounters must not be reported as single-source.

### Blank SOURCE handling (D-167-05)
- **D-167-05:** Compute `single_source_care` and `n_sources` over **non-blank SOURCE values only**. Patients with any blank/NA SOURCE on any encounter get `any_blank_source = TRUE`.
- QC sheet counts patients with `any_blank_source = TRUE`.
- QC also includes a **sensitivity row** treating blank as its own site, so the team can see whether blanks change the single-source classification.
- "Flagged, not coerced" means: the primary classification ignores blanks; the sensitivity shows the worst case.

### Workbook tab detail (D-167-06)
- Base spec from roadmap: n/% single-source, distribution of n_sources, breakdown by SOURCE for single-source patients. **Add:**
  - Single- vs multi-source cross-tabulated by encounter count bands: **1 | 2–4 | 5–9 | 10+** (per-band n and % single-source). Motivation: patients with 1–2 encounters are almost always single-source by default; without this breakdown the headline % conflates care continuity with encounter volume.
  - `n_sources` distribution with a **"4+" top category** (prevents rare high values from being small cells).
  - A **2×2 table** comparing whole-record vs post-anchor single-source status: how many whole-record single-source patients become multi-source post-anchor, and vice versa.
- Apply `suppress_small()` (counts 1–10 → "<11") throughout, including the by-SOURCE breakdown (small sites will produce small cells).
- Both A_summary (whole-record) and B_post_anchor tabs get the same structure.

### Joinable output (D-167-07)
- Export: dated **CSV** (shareable) + internal **RDS** (contains patient IDs, gitignored pattern).
- Columns:
  - `ID`
  - `n_encounters`, `n_sources`, `single_source_care`, `primary_source`
  - `n_encounters_post`, `n_sources_post`, `single_source_care_post`
  - `any_blank_source`
- `primary_source`: for single-source patients = that source; for multi-source = most common site (ties broken by alphabetical SOURCE value). Phase 165 patient-level sensitivity model can consume this file directly instead of recomputing it.

### Script numbering
- Next available: **R/169** (R/166, R/167, R/168 are Phase 166 plans 01–03).

### Plan-end requirements
- Every plan must end with a **HiPerGator run step** (`module load R/4.5`) and a **workbook review step**, consistent with Phase 165 and 166 corrected plans.

### Claude's Discretion
- Column ordering within the RDS beyond the required columns above.
- Exact tie-breaking logic for `primary_source` (alphabetical is sufficient).
- DuckDB query structure (CTE vs subquery) — follow R/116 pattern.
- Workbook UF styling — match Phase 166 convention (header `#0021A5` white bold Arial; flag style `#FA4616`).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase design and requirements
- `.planning/ROADMAP.md` §Phase 167 — closed design constraints D-167-01, D-167-02, success criteria
- `.planning/REQUIREMENTS.md` §SRC-01, SRC-02, SRC-03

### Date range / encounter scope
- `R/00_config.R` — `CONFIG$date_range_max` and date range parameters set here
- `R/01_load_pcornet.R` — how date range is applied to ENCOUNTER on load (Phase 167 must match)

### Anchor date source
- The same anchor-date join R/147 introduced (and R/166/R/167 reuse via `dplyr::select(ID, hl_anchor_date, follow_end)` from the cohort parts file) — verify the exact source path in `R/00_config.R` or the R/147 script before planning.

### DuckDB pattern
- `R/utils/utils_duckdb.R` — DuckDB connection utilities
- `R/116_encounter_ses_index.R` — canonical example of DuckDB + R query pattern (ENCOUNTER table, cohort PATID filter, DBI)
- `R/03_duckdb_ingest.R` — ENCOUNTER table is in DuckDB at `CONFIG$cache$duckdb_path`

### Suppression
- `R/utils/utils_surveillance.R` §`suppress_small()` — the project's canonical suppression function (threshold = 10)

### Workbook styling
- `R/168_survivorship_workbook.R` — canonical workbook assembly pattern (openxlsx, UF colors, sheet order, KEY sheet content, suppress_small wiring)

### Registration
- `R/39_run_all_investigations.R` — R/169 must be registered here in dependency order after R/168
- `R/88_smoke_test_comprehensive.R` — new SMOKE-167-01 section required
- `R/SCRIPT_INDEX.md` — add row for R/169

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `suppress_small()` in `utils_surveillance.R` — already sourced via `R/00_config.R`; use as-is
- `R/utils/utils_duckdb.R` — DuckDB connection helpers; follow R/116 pattern
- Workbook assembly pattern from `R/168_survivorship_workbook.R` — reuse openxlsx structure, KEY sheet layout, UF color constants, dated filename convention

### Established Patterns
- DuckDB queries filter to cohort PATIDs before pulling data into R (R/116 §SECTION 3)
- Two-window (whole-record / post-anchor) column pattern: Phase 165 and 166 use `_post` suffix convention — match it
- Dated output filenames: `output/single_source_care_{RUN_DATE}.xlsx`
- Internal RDS: `output/internal/single_source_care_{RUN_DATE}.rds` (or follow CONFIG$output_dir pattern)

### Integration Points
- Phase 165 patient-level sensitivity model can join on `ID` from the CSV output to get `primary_source` and `single_source_care`
- R/39 registration: insert R/169 after R/168 in the dependency list

</code_context>

<specifics>
## Specific Requirements

- Encounter count bands: **1 | 2–4 | 5–9 | 10+** (exactly these bands, not others)
- n_sources distribution: cap at **"4+"** top category in display tables
- Blank SOURCE sensitivity: a dedicated row in QC treating blank as a distinct site
- `primary_source` for multi-source patients: most common site (alphabetical tiebreak)
- `n_sources_post = 0` with `single_source_care_post = NA` when patient has anchor date but zero post-anchor encounters
- `single_source_care_post = NA` (not 0) when patient has no anchor date

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 167-single-health-system-care-flag*
*Context gathered: 2026-10-08*
