# Phase 188: Echo Rate Since Anthracycline - Context

**Gathered:** 2026-10-22
**Status:** Planned — 188-01-PLAN.md ready for execution

<domain>
## Phase Boundary

Among `any_anthracycline == TRUE` patients (n=2,379 from Phase 187), compute the echo rate per patient-year since last dose, add reconciliation columns for excluded echoes, and produce a four-sheet workbook. Phase 188 also produces an encounter-grain internal RDS of all echo events for exposed patients. Script registration (R/39, R/88, SCRIPT_INDEX) is Phase 189 (REG-01).

</domain>

<decisions>
## Implementation Decisions

### D-188-01: Echo Event Source

- **D-01:** Echo events = `survivorship_dated_events_<date>.rds` produced by R/166, filtered to the echo modality. This is the same source R/167 uses, so the Phase 166 row in the Anchor Comparison sheet is drawn from the same event population — comparison is like-for-like.
- **D-02:** The path is pinned as `R188_DATED_EVENTS` (env var with a dated default), taken from a schema probe on HiPerGator before planning begins — not picked by `sort(..., decreasing=TRUE)[1L]` as R/167 currently does (that is the anti-pattern to avoid per CLAUDE.md). Task 0 must cite the probe file. The dated default is the same dated file the pinned Phase 166 workbook was built from, as recorded on that workbook's KEY sheet, so the Anchor Comparison is like-for-like. If the Phase 166 KEY does not record it, use the file the Phase 171-verified survivorship run used and state on KEY that the event file may differ from Phase 166's.
- **D-02a:** Window check (must hold before planning). The probe or a one-line HiPerGator check must show whether `survivorship_dated_events` keeps every echo date per patient or only echoes inside a survivorship window (e.g. year_index ≥ 2 or post-primary tier). If it is windowed, echoes before the window are missing, so `n_echoes_before_or_on_last_dose` would be undercounted by construction. In that case KEY says the on-or-before count covers only in-window echoes, and the plan does not present it as a full count. Record which applies in CONTEXT before planning.
- **D-02b:** Echoes are counted as unique ID × echo_date. Multiple echo codes or rows on the same day for the same patient count once (same unique-date convention as Phase 159 and `echo_rate_post_dose()`'s `n_dates_post`). The encounter-grain RDS is deduplicated to one row per ID × echo_date before any counting.
- **D-03:** Patient set = rows in the Phase 187 patient-grain RDS (`any_anthracycline == TRUE` filter applied in R/188, not assumed pre-filtered). Path pinned as `R188_ANTHRA_EXPOSURE` from the path recorded in `187-01-SUMMARY.md`.
- **D-04:** Echoes after `follow_end` are outside person-time and do not count toward the rate numerator. They are counted in a reconciliation column and reported on the QC sheet.

### D-188-02: Encounter-Grain Internal RDS

- **D-05:** R/188 writes one encounter-grain RDS to `output/internal/` containing **all echo events for anthracycline-exposed patients** (pre-dose, on-dose, and post-dose):
  - `ID` — character, no values in probe
  - `echo_date` — Date
  - `days_since_last_anthracycline_dose` — numeric; negative or zero for echoes on or before last dose; computed as `echo_date - last_anthracycline_date`
  - `window_label` — character factor: `"on_or_before_last_dose"` / `"after_last_dose"` / `"after_follow_end"` / `"unclassifiable"`
- **D-05a:** Labels are assigned in this order, first match wins, so every echo gets exactly one label:
  1. `"unclassifiable"` — `echo_date`, `last_anthracycline_date` or `follow_end` is NA. (Phase 187 stops if an exposed patient has NA last date, so in practice this means NA `follow_end` or NA `echo_date`.)
  2. `"after_follow_end"` — `echo_date > follow_end`. Takes precedence over the dose comparison, so for a patient whose last dose falls after `follow_end`, an echo between `follow_end` and the dose is outside observation, not "on or before".
  3. `"on_or_before_last_dose"` — `echo_date <= last_anthracycline_date`.
  4. `"after_last_dose"` — otherwise, i.e. `last_anthracycline_date < echo_date <= follow_end`. This is the numerator interval `(last dose, follow_end]`.
  Endpoint conventions (stated on KEY): an echo on the last-dose date is "on or before"; an echo on the `follow_end` date counts in the numerator. Events are never dropped before labelling.
- **D-06:** The patient-grain counts (`n_echoes_before_or_on_last_dose`, `n_echoes_after_follow_end`, `n_echoes_post`, `n_echoes_unclassifiable`) are derived from this file. Two sum checks, both stop on failure: per patient, the four window counts add to that patient's total unique echo dates; and at dataset level, the four column totals add to the row count of the deduplicated encounter-grain file.

### D-188-03: Patient-Grain Output Columns (Internal RDS)

- **D-07:** R/188 also writes a patient-grain RDS to `output/internal/` with columns:
  - `ID` — character
  - `n_echoes_post` — integer; echoes strictly after `last_anthracycline_date` and on or before `follow_end`
  - `person_years` — numeric; `years_since_last_anthracycline` from Phase 187
  - `rate_per_py` — numeric; `n_echoes_post / person_years`; NA when `person_years` is NA or zero
  - `n_echoes_before_or_on_last_dose` — integer; echoes labelled `"on_or_before_last_dose"` (D-05a)
  - `n_echoes_after_follow_end` — integer; echoes labelled `"after_follow_end"`
  - `n_echoes_unclassifiable` — integer; echoes labelled `"unclassifiable"`
  - `in_rate_population` — logical; TRUE when `person_years` is non-NA and > 0 (D-11)
- **D-07a:** Denominator check. R/188 recomputes `(follow_end - last_anthracycline_date) / 365.25` for every patient with both dates and last dose ≤ `follow_end`, and stops if it differs from Phase 187's `years_since_last_anthracycline` by more than 1e-9. This confirms the person-time covers exactly the numerator interval `(last dose, follow_end]` without reimplementing anything Phase 187 owns.
- **D-08:** Both internal RDS files written before the workbook; workbook is derived from aggregates of the patient-grain file. Patient IDs and dates never appear in the workbook.

### D-188-04: Workbook Layout

- **D-09:** Four sheets in order: **KEY**, **Rates**, **Anchor Comparison**, **QC**.
- **D-10:** KEY leftmost; UF blue (`#0021A5`) for header rows; UF orange (`#FA4616`) for accent rows. Standard convention per CLAUDE.md and R/184/186.
- **D-11:** **Rates sheet** — one aggregate row: `n_patients`, `total_echoes_post`, `total_person_years`, `rate_per_py`. `rate_per_py` is the pooled rate, `total_echoes_post / total_person_years` — not the mean of patient-level rates. `n_patients` = exposed patients with `in_rate_population == TRUE`, and `total_echoes_post` and `total_person_years` are both summed over exactly that population, so a patient's echoes never enter the numerator while their person-time is left out; exposed patients excluded from the rate (NA or zero person-years, e.g. last dose after or on `follow_end`) are counted on QC. Counts 1–10 suppressed as `"<11"`; the rate is shown only when `total_echoes_post` and `total_person_years` are both ≥ 11, otherwise a dash. Because exposed total, included, and excluded patients add up, if either the included or the excluded count is `"<11"`, both are suppressed.
- **D-12:** **QC sheet** — four panels:
  - Panel A: `n_echoes_before_or_on_last_dose` aggregate (total excluded echoes, n patients with any excluded echo, pct of exposed patients)
  - Panel B: `n_echoes_after_follow_end` aggregate (same structure)
  - Panel C: patient reconciliation — total exposed = in rate population + excluded, with excluded broken down by reason (NA `follow_end`; last dose after `follow_end`; last dose on `follow_end`, zero person-years). The identity is checked in code before writing.
  - Panel D: `n_echoes_unclassifiable` aggregate (expected 0; nonzero values are reported, not hidden)
  - Suppression applies to all cell values, including percentages and any derived cell: a percentage is shown only when its numerator and denominator are both ≥ 11, and complementary suppression applies within each panel where cells add to a visible total.
- **D-13:** **Anchor Comparison sheet** (ECHO-02) — see D-188-05 below.

### D-188-05: Anchor Comparison Sheet (ECHO-02)

- **D-14:** Sheet name exactly: `"Anchor Comparison"`.
- **D-15:** Table columns: `anchor`, `n_patients`, `n_echoes_post`, `person_years`, `rate_per_py`. Three rows: Phase 166 row, Phase 188 row, delta row.
  - Phase 166 row label = Phase 166's actual anchor as documented in `166-03-SUMMARY.md`: `"last_dose_firstline_dt (D-08a: equals last_dose_ever_dt in this extract)"`.
  - Phase 188 row label = `"last_dose_ever_dt (Phase 188)"`.
  - Delta row = Phase 188 values minus Phase 166 values (numeric; suppressed if any input cell is `"<11"`). The row is labelled "Difference (Phase 188 − Phase 166), cross-phase descriptive" — it is not presented as an isolated anchoring effect.
  - The anchor-difference row sits below the delta row with its own label and denominator: "Patients with a different anchor date / patients present in both Phase 166 and Phase 188" (overlap population).
- **D-15a:** Below the numeric table, a methodology table with one row per dimension and columns `dimension`, `phase_166`, `phase_188`, `same`: anchor definition, drug set, patient eligibility, follow-up end rule, echo source file (dated), echo counting unit (unique dates vs events), person-time definition, window filter. Phase 166 entries are taken from 166-CONTEXT / 166-03-SUMMARY with the line cited; entries that cannot be confirmed read "not documented". KEY's D-17 sentence points to this table rather than listing the differences itself.
  - One additional row: count of patients whose anchor date differs between the two definitions. This needs Phase 166's **per-patient** anchor dates, which the workbook (aggregates only) does not hold. The planner looks for Phase 166's internal patient-grain anchor file (`output/internal/`, named in 166-03-SUMMARY). If it exists, pin it as `R188_ANTHRA_166_PATIENT`, compare per patient, and report the count (suppressed). If it does not exist, omit this row and say on KEY that per-patient anchor comparison was not possible because Phase 166 kept no per-patient anchor file. Never assume the count.
- **D-16:** **Phase 166 values are read by exact label from Phase 166's pinned workbook output** — R/188 does not rerun R/167 or recompute Phase 166 values. The planner identifies the exact sheet and label strings from a schema probe of the Phase 166 workbook (D-21) before writing code. If Phase 166 did not report one of the comparison quantities (e.g. it reported time-to-echo but no person-years or rate), that cell reads "not reported in Phase 166" and its delta cell is blank; nothing is derived to fill it. The reader stops with the available labels printed if a required sheet or label is missing or duplicated; a Phase 166 cell that is suppressed (`"<11"` or dash) is carried as-is and its delta cell is blank; a cell that is otherwise nonnumeric stops the script.
- **D-17:** KEY narrative explanation (neutral wording): Phase 166 clock = `last_dose_firstline_dt`; Phase 188 clock = `last_dose_ever_dt`. D-08a applies to both: the `first_line` column was absent from the 180-day episode file, so all episodes were treated equivalently — the two anchor dates are numerically identical in this extract (cite `166-03-SUMMARY.md` line confirming this; if no such line exists, KEY states the expectation and points to the per-patient row, or to its absence per D-15, instead of asserting it). The D-08a parenthetical in the Phase 166 row label is used only when that SUMMARY line exists. Any nonzero delta in the Anchor Comparison table therefore reflects window, eligibility, echo-source, or drug-set differences rather than anchoring — KEY names which of these differ between Phase 166 and Phase 188.

### D-188-06: Script Architecture

- **D-18:** One new script: `R/188_echo_rate_since_anthracycline.R`. R/166, R/167, and R/187 are read-only inputs; do not edit them.
- **D-19:** `echo_rate_post_dose()` from `R/utils/utils_anthracycline_echo.R` (lines 258–306) is reusable for computing `n_dates_post` and `rate_per_py`. Phase 188 passes `dose_col = "last_anthracycline_date"` (the column name from the Phase 187 output). The planner confirms the helper's filter logic matches D-05 (strict `>` for post, `<=` follow_end) before using it; if not, the plan describes the delta and adjusts.
- **D-20:** Pins: `R188_DATED_EVENTS` (survivorship_dated_events path), `R188_ANTHRA_EXPOSURE` (Phase 187 output path), and `R188_ANTHRA_166_WB` (Phase 166 workbook path for reading anchor comparison values). All three recorded on KEY with pinned TRUE/FALSE. Script stops with an informative error if any pinned file is missing.
- **D-21:** Probes required before planning: (1) the `survivorship_dated_events` RDS, to confirm (a) modality values (exact string for echo filter), (b) column names (`ID`, `modality`, `event_date` or variants), (c) row count and patient count, (d) the D-02a window question; (2) the pinned Phase 166 workbook, to get exact sheet names and labels for D-16 (`166wb_schema_<date>.md`). Task 0 cites the 187out probe, the dated_events probe and the Phase 166 workbook probe. If D-15's per-patient file is used, it is probed too.
- **D-22:** Script ends with a blocking HiPerGator checkpoint before the SUMMARY is written. Checkpoint output: workbook path, row counts for both internal RDS files, Rates sheet aggregate values, QC totals. Fixtures run through the same function as the real data (as in R/187): no-echo patient with positive person-years (all counts zero, rate 0 — not NA; rate is NA only when person_years is NA or 0), pre-dose-only echoes (n_echoes_post = 0, n_echoes_before_or_on = N), post-dose echoes (rate computed correctly), after-follow_end echo (counted in n_after, excluded from numerator), two echo rows on the same day (counted once, D-02b), an echo on the last-dose date (counted as on_or_before), an echo on the follow_end date (counted in the numerator), a patient with NA follow_end (echoes labelled unclassifiable, patient excluded from the rate and counted in Panel C), a patient whose last dose is after follow_end (echo between follow_end and dose labelled after_follow_end), and a suppression fixture where one cell of a TRUE/FALSE-style pair is "<11" (both suppressed).

### Claude's Discretion

- Section structure within R/188 (SECTION 0 pins, SECTION 1 load, SECTION 2 encounter-grain, SECTION 3 patient-grain, SECTION 4 workbook)
- Whether to write a probe call on the output workbook for downstream phases

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Schema Probes (required before planning)
- `.planning/schemas/187out_schema_20261022.md` — Phase 187 output RDS column names and types. Task 0 must cite this. Key columns: `ID`, `any_anthracycline`, `last_anthracycline_date`, `years_since_last_anthracycline`, `follow_end`, `drugs_received`.
- Schema probe of `survivorship_dated_events_<date>.rds` — **must be run on HiPerGator before planning begins** and copied to `.planning/schemas/188_dated_events_schema_<date>.md`. Confirms modality string for echo filter and column names. Task 0 must cite this probe file.

### Phase 187 Output
- `187-01-SUMMARY.md` (in `.planning/phases/187-anthracycline-exposure-variables/`) — Contains the exact dated path of the anthracycline_exposure_patient RDS for `R188_ANTHRA_EXPOSURE` default.
- `.planning/phases/187-anthracycline-exposure-variables/187-CONTEXT.md` — D-04 through D-09: output columns, pin pattern, consumer-owns-pin rule, probe requirement.

### Phase 166 Output (for Anchor Comparison)
- `.planning/phases/166-survivorship-modality-rates-and-anthracycline-to-echo-timing/166-03-SUMMARY.md` — Confirms D-08a fallback: `last_dose_firstline_dt == last_dose_ever_dt` in this extract; line to cite in KEY. Also confirms the Phase 166 workbook path and exact sheet/label strings for reading Phase 166 aggregate values.
- `.planning/phases/166-survivorship-modality-rates-and-anthracycline-to-echo-timing/166-AUDIT.md` §D-08a — Documents the `first_line_flag_absent: TRUE` fallback.

### Echo Rate Helper
- `R/utils/utils_anthracycline_echo.R` lines 258–306 — `echo_rate_post_dose()`: `dose_col` parameter accepts `"last_anthracycline_date"`. Planner verifies filter logic (strict `>`, `<= follow_end`) matches Phase 188 requirements before relying on it.

### Phase 185 Pin Convention
- `.planning/phases/185-phase184-closeout-and-modality-rates/185-CONTEXT.md` D-01 — Consumer-owns-the-pin rule. R/188 pins its own inputs; R/187 does not set an env var for downstream use.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `echo_rate_post_dose()` (`R/utils/utils_anthracycline_echo.R` lines 258–306): returns ID × modality × n_dates_post × person_years × rate_per_py. Accepts `dose_col` arg — pass `"last_anthracycline_date"`. Planner must verify its window logic matches ECHO-01 before using it.
- `last_anthracycline_dose()` (`R/utils/utils_anthracycline_echo.R` lines 58–90): already used by Phase 187; Phase 188 reads Phase 187's output directly rather than calling this helper again.
- Exact-label reader pattern (`R/184_modality_rate_model.R` lines 266–288 / `R/186_survivorship_rate_granularity.R`): copy verbatim for reading Phase 166 workbook values.

### Established Patterns
- Pin block (SECTION 0): env var with dated default, `file.exists()` stop, `TRUE/FALSE` recorded on KEY — same as R/185, R/186, R/187.
- Counts 1–10 suppressed as `"<11"`; complementary suppression within each rate block.
- KEY sheet leftmost; UF colours applied to header and accent rows.

### Integration Points
- R/188 reads: `survivorship_dated_events_<date>.rds` (R/166 output) + `anthracycline_exposure_patient_<date>.rds` (R/187 output) + Phase 166 workbook (for Anchor Comparison Phase 166 row).
- R/188 writes to `output/internal/` (two RDS files) and `output/` (workbook, dated).
- Phase 189 reads R/188 output for REG-01 registration and TRACK-01 tracking.

</code_context>

<specifics>
## Specific Ideas

- Window label values exactly: `"on_or_before_last_dose"`, `"after_last_dose"`, `"after_follow_end"` — use these strings in the encounter-grain RDS.
- Anchor Comparison sheet name exactly: `"Anchor Comparison"` (no abbreviation).
- Phase 166 row label in Anchor Comparison: `"last_dose_firstline_dt (D-08a: equals last_dose_ever_dt in this extract)"` — this exact phrasing or close equivalent; taken from `166-03-SUMMARY.md`.
- KEY wording for D-08a note must be neutral and cite the SUMMARY line — no causal language, no characterization of the finding as surprising.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 188-echo-rate-since-anthracycline*
*Context gathered: 2026-10-22*
