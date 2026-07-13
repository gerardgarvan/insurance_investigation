# Phase 121: Investigate 9-Digit ZIP Change Frequency at the Individual Level - Context

**Gathered:** 2026-07-13
**Status:** Ready for planning

<domain>
## Phase Boundary

A **read-only investigation** that quantifies how often an individual patient's
9-digit ZIP code changes over time, and reports the results as a styled xlsx plus
console summary. The purpose is to **inform a downstream decision** on how ZIP-code
data should feed socioeconomic indices (ADI / SVI / deprivation indices) — e.g.,
whether a single ZIP per patient is defensible or whether time-varying handling is
needed.

**In scope:**
- Probing for and (if present) loading the longitudinal 9-digit ZIP source
- Measuring ZIP change frequency per patient at BOTH ZIP9 and ZIP5 granularity
- Summarizing distributions, change rates, and time-between-changes
- Reporting single-ZIP tie-break options (most-recent vs modal) WITHOUT committing to one
- A written recommendation to guide the SES-index handling decision

**Out of scope (future phases):**
- Actually computing/attaching any SES index (ADI/SVI) — this phase only informs that decision
- Adding a time-varying ZIP into the production cohort pipeline
- Adding LDS_ADDRESS_HISTORY to the permanent PCORNET_TABLES load set (unless the
  investigation itself needs it loaded; permanent adoption is a separate decision)

</domain>

<decisions>
## Implementation Decisions

### ZIP Data Source
- **D-01:** Source of truth is PCORnet **`LDS_ADDRESS_HISTORY`** (the only CDM table
  with time-varying 9-digit ZIP: `ADDRESS_ZIP9` + `ADDRESS_PERIOD_START` /
  `ADDRESS_PERIOD_END`, plus `ADDRESS_PREFERRED` / `ADDRESS_USE`).
- **D-02:** **Probe-first pattern** (mirror Phase 119's R/103 diagnostic gate): the
  script FIRST checks whether `LDS_ADDRESS_HISTORY` (or an equivalent raw address CSV)
  exists in the HiPerGator extract directory before attempting analysis. If absent,
  it reports that clearly and exits gracefully (no crash) rather than assuming.
- **D-03:** The loaded `DEMOGRAPHIC` table is NOT a valid source for this question —
  it holds exactly one 5-digit `ZIP_CODE` per patient with no time dimension
  (confirmed: `DEMOGRAPHIC_values.csv` shows 5-digit values, 25.1% NA). Phase 116
  (R/100 RUCA) used `DEMOGRAPHIC.ZIP_CODE` truncated to 5 digits — that is the
  carried-forward precedent, and precisely the limitation this phase investigates.

### Definition of "Change"
- **D-04:** Measure change frequency at **BOTH granularities**:
  - **ZIP9** — distinct full 9-digit values per patient (fine-grained; matters for ADI+4 / block-group indices)
  - **ZIP5** — distinct 5-digit values per patient (matters for SVI / tract-based / most deprivation indices)
- **D-05:** Report both side-by-side so the SES-index decision can be made with full
  information rather than pre-committing to one granularity. (A ZIP9→ZIP9 move within
  the same ZIP5 is a ZIP9 change but NOT a ZIP5 change — surface that distinction.)

### Output & Metrics
- **D-06:** Produce a **styled multi-sheet xlsx + console summary** (match R/100 RUCA
  output style using `openxlsx2` + the `add_styled_sheet()` helper pattern).
- **D-07:** Suggested sheets (planner may refine): (1) per-patient distinct-ZIP-count
  distribution at ZIP9 and ZIP5; (2) % of patients who ever changed + change-count
  histogram; (3) time-between-changes (derived from `ADDRESS_PERIOD_START`);
  (4) tie-break comparison (most-recent vs modal disagreement rate); (5) a
  Recommendation / Metadata sheet.
- **D-08:** Follow the project's investigation-script convention: new `R/NN` script,
  registered in `R/39_run_all_investigations.R`, with a new `R/88` smoke-test section
  (continuing the section-suffix sequence, e.g., 15s).
- **D-09:** Console logs headline stats (cohort size, % ever-changed at ZIP9/ZIP5,
  median distinct ZIPs) before writing the xlsx.

### Cohort Scope & Tie-Break
- **D-10:** Scope to **all patients with address history** in `LDS_ADDRESS_HISTORY`
  (broadest denominator for the stability question), not just the HL cohort.
- **D-11:** For the single-ZIP tie-break, the report presents **options without
  committing**: quantify how often **most-recent** (via `ADDRESS_PERIOD_START` /
  `ADDRESS_PREFERRED`) vs **modal** (most-frequently-recorded) would select a
  different ZIP. The decision is left to the downstream SES-index phase.

### Claude's Discretion
- Exact sheet layout, column ordering, and styling details (follow R/100 conventions)
- HIPAA suppression of small ZIP cells (1–10) in any patient-count output — apply the
  project's standard suppression since it's a hard project constraint
- Handling of NA / malformed ZIP values (define and log an explicit rule)
- The `R/NN` number and `R/88` section suffix (next available in sequence)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### ZIP / address precedent (existing pattern to mirror)
- `R/100_ruca_rurality_summary.R` — existing ZIP-based investigation; source of the
  `add_styled_sheet()` xlsx pattern, `get_hl_patient_ids()` usage, ZIP normalization
  (`str_sub(1,5)` + `str_pad`), and NA-logging convention.

### Probe-first diagnostic-gate pattern
- `R/103_*` (Phase 119 diagnostic gate) — the read-only "probe whether a source
  exists before using it" pattern to replicate for D-02. (Locate exact filename in
  `R/SCRIPT_INDEX.md`.)

### Config / data access
- `R/00_config.R` §3 (PCORNET_TABLES / PCORNET_PATHS, lines ~211–258) — table load set
  (note: `LDS_ADDRESS_HISTORY` is NOT currently listed), filename-override pattern
  (`LAB_RESULT_CM`, `PROVIDER`), and the `{TABLE}_Mailhot_V1.csv` naming convention.
  Patient ID column is `ID` (not `PATID`).
- `R/01_load_pcornet.R` — loader; `get_pcornet_table()` dispatcher for table access.

### Investigation registration + smoke test
- `R/39_run_all_investigations.R` — investigation runner; new script must be registered
  (mind the single comma-less final-entry vector convention noted in prior phases).
- `R/88_smoke_test_comprehensive.R` — add a new structural smoke-test section.
- `R/SCRIPT_INDEX.md` — add the new script row to the Post-Renumber Investigations (100+) table.

### Data profiling reference
- `DEMOGRAPHIC_values.csv` — confirms `DEMOGRAPHIC.ZIP_CODE` is a single 5-digit
  character column per patient with 25.1% NA (basis for D-03).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/100_ruca_rurality_summary.R`: `add_styled_sheet()` helper, `build_crosstab()`,
  ZIP normalization, `get_hl_patient_ids()`, NA-count logging — directly reusable for
  the xlsx output and ZIP handling.
- `R/utils/utils_treatment.R`: `get_hl_patient_ids()`, `safe_table()`.
- `R/utils/utils_assertions.R`: input-validation helpers (`assert_*`).
- `get_pcornet_table()` dispatcher (R/01) — used to read CDM tables via the DuckDB/CSV backend.

### Established Patterns
- Investigation scripts are read-only, self-bootstrapping (source `R/00_config.R`),
  and registered in `R/39` + `R/88` + `R/SCRIPT_INDEX.md`.
- Probe-before-use diagnostic gate: a source's absence is an EXPECTED, gracefully
  reported state, not an error (Phase 119 R/103 precedent).
- Styled xlsx via `openxlsx2` with dark-gray headers, title/subtitle rows, frozen panes.
- HIPAA: patient counts 1–10 suppressed in shareable output.
- Patient ID column is `ID`; site column is `SOURCE`.

### Integration Points
- `LDS_ADDRESS_HISTORY` is NOT in `PCORNET_TABLES` (R/00_config.R §3). The script must
  read it directly by path (probe `file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv")`
  or the actual filename) rather than assuming `get_pcornet_table()` resolves it —
  unless the plan decides to add it to the load set.
- Output xlsx lands in `CONFIG$output_dir` (alongside `ruca_rurality_summary.xlsx`).

</code_context>

<specifics>
## Specific Ideas

- Mirror R/100's look-and-feel for the xlsx so the team sees a consistent report family.
- Mirror R/103's probe-first gate so a missing address table degrades gracefully.
- Because runtime requires HiPerGator (real extract + possibly a table not in the local
  fixture set), expect structural verification locally and a runtime confirmation step
  the user runs on HiPerGator (consistent with recent phases' local/remote split).

</specifics>

<deferred>
## Deferred Ideas

- Actually computing and attaching a socioeconomic index (ADI/SVI/SDI) to the cohort —
  this phase only informs how ZIP should be handled for that future work.
- Permanently adding `LDS_ADDRESS_HISTORY` to `PCORNET_TABLES` / DuckDB ingest — a
  standing pipeline decision separate from this one-off investigation.
- Time-varying ZIP (and time-varying SES index) in the production cohort pipeline.
- Building a local fixture for `LDS_ADDRESS_HISTORY` so R/88 can run this section
  end-to-end locally (noted as a possible follow-up if desired).

</deferred>

---

*Phase: 121-investigate-how-often-the-9-digit-zip-code-changes-at-the-individual-level*
*Context gathered: 2026-07-13*
