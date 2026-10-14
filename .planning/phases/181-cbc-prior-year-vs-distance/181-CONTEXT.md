# Phase 181: CBC Prior-Year vs Distance — Context

**Gathered:** 2026-10-14
**Status:** Ready for planning
**Depends on:** Phase 179 RDS (`output/internal/cbc_patient_year_20261013.rds`); Phase 180 workbook (`output/cbc_missing_capture_<date>.xlsx`)

<domain>
## Phase Boundary

Build `R/181_cbc_prior_year.R`: patient-level 2×2 chi-squared of CBC receipt in each patient's
"prior year" (working definition: most recent fully observed follow-up year) vs far-from-care,
plus a one-page team summary memo. Read-only: no new cohort building, no new exposure derivation.
</domain>

<decisions>
## Implementation Decisions

### Prior-Year Definition
- **D-01 (working definition — pending Erin/Ray confirmation):** "Prior year" = each patient's most
  recent fully observed follow-up year = `max(year_index)` per patient in the Phase 179 RDS.
  - Primary analytic set: patients whose most recent full year is year_index ≥ 2 (survivorship cohort).
  - Secondary analytic set: all patients (year_index ≥ 1).
- **D-02:** KEY sheet and memo must label the definition as "working definition — confirm with
  Erin/Ray" until confirmed.
- **D-03 (sensitivity):** Also report, as a sensitivity analysis (not primary), the year immediately
  before the CDM cutoff for patients followed to the cutoff (a common fixed-calendar-window
  definition). Report N and CBC rate side-by-side with the primary definition so the team can
  compare if they meant a different window.

### Statistical Test
- **D-04:** Pearson chi-squared for the 2×2. Fisher's exact if any expected cell count < 5. Report
  which test was used and why in the QC sheet and the A_2x2 sheet. Also report OR with 95% CI.
- **D-05:** Missing `far` exposure → excluded from the 2×2; N missing reported in KEY and QC, not
  included in the analytic 2×2.
- **D-06:** CBC rates by group (far vs not-far) reported in B_rates sheet.

### Workbook Structure
- **D-07:** Sheet order: KEY (leftmost), A_2x2, B_rates, C_year_distribution, QC.
  - **KEY:** input file names + run date, working definition caveat, branch taken (chi-sq vs Fisher
    with expected cell counts), N in each analytic set, missing-exposure N, primary and secondary
    OR + CI + p-value, prior-year sensitivity comparison.
  - **A_2x2:** The 2×2 table for primary and secondary sets (far × CBC, observed counts, row %).
  - **B_rates:** CBC rate (%) by far / not-far for primary and secondary sets.
  - **C_year_distribution:** Distribution of max year_index across patients (how many patients have
    their "prior year" at year 1, 2, 3, …). Helps team assess whether the cohort is late-stage.
  - **QC:** See D-08 below.
- **D-08 QC sheet rows:**
  - Input files: Phase 179 RDS name, Phase 180 workbook name, run date.
  - Patient counts: N in Phase 179 RDS; N with exposure; N missing exposure (excluded); N in
    primary set (most recent year ≥ 2); N in secondary set.
  - Reconciliation: 2×2 cells sum to analytic N — TRUE/FALSE for primary and secondary.
  - Expected cell counts for each set, and which test was used (chi-sq vs Fisher) and why.
  - Check: "prior year" chosen equals each patient's `max(year_index)` — TRUE/FALSE.
  - Count of cells suppressed (<11) per sheet.
  - Sensitivity N (CDM-cutoff definition) vs primary N.
- **D-09:** Counts 1–10 → `"<11"`; percentages only when both counts ≥ 11. UF color palette.

### Phase 180 Memo Numbers — Source and Interpretation
- **D-10:** Do NOT hard-code Phase 180 numbers in the script. The memo reads every Phase 179/180
  number from those workbooks (or their SUMMARY files) by exact label at runtime.
- **D-11:** For the single-source split (0.754 vs 1.068), take group assignment from the Phase 180
  MISS-04 sheet. Expected mapping: `single_source_care_post = 1` (all care within one OneFlorida+
  system) vs `= 0` (care across multiple systems). If the actual assignment is reversed, state it
  plainly in the memo, because the interpretation changes.
- **D-12:** "Out of system" in the memo means outside the OneFlorida+ network.

### Team Memo Structure (CBCP-02)
- **D-13:** One-page markdown file in the phase directory. Five headed sections with bullet lists
  under each. Neutral language throughout. No patient-level data; counts 1–10 as `<11`.
- **D-14:** Section structure:
  1. **Question and definitions** — "prior year" = working definition; distance = patient median
     post-anchor encounter distance, > 100 mi.
  2. **Prior-year result** — 2×2 rates, OR, 95% CI, test used; primary and secondary.
  3. **Relationship to earlier analyses** — Phase 165 encounter-level OR vs Phase 179 patient-year
     OR (side-by-side comparison from Phase 179 KEY).
  4. **Robustness** — missing-distance bounds (Phase 180 MISS-02/03); note the not-far bound's CI
     crosses 1.
  5. **Capture check** — log-OR shrinks ~37.4% under the lab restriction (Phase 180 MISS-04);
     single-system split with groups named; "consistent with out-of-system care" language, not causal
     proof.
  6. **Decisions needed** — D-15 (which analysis is primary: 165 vs 179), confirm "prior year"
     definition with Erin/Ray.

### Execution Convention
- **D-15:** Interactive R on HiPerGator from repo root. `module load R/4.5` (not 4.4.2 per recent
  convention). `source("R/181_cbc_prior_year.R", local = new.env(parent = globalenv()))`.
- **D-16:** Register in `R/39` (one-off section) and `SCRIPT_INDEX`. No `R/88` section unless team
  requests.
- **D-17:** Script name: `R/181_cbc_prior_year.R`. Output workbook:
  `output/cbc_prior_year_<YYYYMMDD>.xlsx`. Memo: `.planning/phases/181-cbc-prior-year-vs-distance/181-MEMO.md`.

### Claude's Discretion
- Minor formatting within sheets (column widths, freeze panes) — follow Phase 179/180 precedent.
- Exact wording of neutral-language sentences in the memo — as long as the five section structure
  and bullet format (D-13/D-14) are respected.
- Whether to use `chisq.test()` or `fisher.test()` is determined by expected cell counts at runtime
  (D-04) — no user decision needed.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 179 — Patient-Year Analysis (primary input)
- `R/179_cbc_patient_year.R` — RDS schema, `far` exposure definition, `cbc_year` outcome definition,
  `year_index` structure, build_cbc_events() LOINC set
- `.planning/phases/179-missing-distance-bias-check/179-CONTEXT.md` — D-15 note (primary-analysis
  choice still pending), GEE specification

### Phase 180 — Capture Check (memo input)
- `R/180_cbc_missing_capture.R` — MISS-04 sheet label for single-source split, D-09 log-OR change
  rule, D-05 bounding logic
- `.planning/phases/180-cbc-per-patient-year/180-CONTEXT.md` — D-01 through D-12, output
  file naming convention

### Phase 165 — Encounter-Level OR (memo comparison)
- `.planning/phases/165-*/165-CONTEXT.md` — D-165-01 (rao_scott decided 2026-10-08), window
  conventions

### Config and Conventions
- `R/00_config.R` — `CONFIG$far_from_care_cutoff_mi` (100 mi), `CONFIG$distance_gee_corstr`,
  `EXTRACT_DATE`, UF color palette
- `SCRIPT_INDEX` and `R/39` — registration convention for new scripts

### No External Specs
- Requirements CBCP-01 and CBCP-02 are fully captured in the roadmap and decisions above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/179_cbc_patient_year.R` — `build_cbc_events()` helper, `far` derivation, broad LOINC list,
  GEE model call, xlsx workbook builder with UF colors; Phase 181 workbook follows the same pattern.
- `R/180_cbc_missing_capture.R` — suppression helper (`suppress_small()`), QC sheet builder,
  KEY sheet builder; reuse directly.
- `R/00_config.R` — UF color palette, `far_from_care_cutoff_mi`, `EXTRACT_DATE`.

### Established Patterns
- Workbook sheets built with `openxlsx` + UF colors; KEY leftmost; counts suppressed via helper.
- `chisq.test()` / `fisher.test()` branch on expected cell counts — same pattern used in Phase 165.
- `source(f, local = new.env(parent = globalenv()))` execution convention across all recent phases.

### Integration Points
- Reads: `output/internal/cbc_patient_year_20261013.rds` (Phase 179), Phase 180 workbook.
- Reads Phase 169 RDS indirectly via Phase 180 (for `single_source_care_post` already in Phase 180
  output — do not re-join).
- Writes: `output/cbc_prior_year_<YYYYMMDD>.xlsx`, `.planning/phases/181-.../181-MEMO.md`.
- No DuckDB queries needed — all data in Phase 179 RDS.

</code_context>

<specifics>
## Specific Requirements

- Sensitivity analysis: CDM-cutoff year window, reported alongside primary in KEY and A_2x2.
- Memo Phase 180 numbers read from workbook at runtime, not hard-coded.
- Group labeling for single_source_care_post must be taken from the MISS-04 sheet and stated
  explicitly in the memo (do not assume which OR maps to which group).
- "Prior year" definition labeled as working definition in both KEY and memo until Erin/Ray confirm.

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope.

</deferred>

---

*Phase: 181-cbc-prior-year-vs-distance*
*Context gathered: 2026-10-14*
