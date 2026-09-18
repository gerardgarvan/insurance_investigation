# Phase 155: Binary Indicator and Cutoff Memo — Context

**Gathered:** 2026-09-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Add `CONFIG$distance_cutoff_mi` (default `NA`) as a config gate. When set, R/122 emits
`far_from_care` (0/1) and `far_from_care_cutoff_mi` in every output row, the workbook
gains `E_binary_by_cutoff` (live cutoff) and `F_sensitivity_cutoffs` (candidate sweep,
always present). Deliver `docs/distance_cutoff_memo.md` — a neutral, one-page evidence
document for Amy/Erin to choose the cutoff value. Wire candidate-cutoff dotted lines into
the Phase 154 PNG histograms.

Does NOT decide the cutoff value. That decision (D-06) remains pending the team.

</domain>

<decisions>
## Implementation Decisions

### 155-01: CONFIG gate and far_from_care indicator
- **D-01:** Add `distance_cutoff_mi = NA` to `R/00_config.R` alongside
  `distance_candidate_cutoffs_mi`. When `NA`, pipeline output is byte-identical to
  Phase 154 (no new columns, no E sheet written).
- **D-02:** When `distance_cutoff_mi` is numeric, R/122 adds `far_from_care` (integer 0/1)
  and `far_from_care_cutoff_mi` (the config value) to every row of `enc_distance` before
  the workbook writer runs.

### E_binary_by_cutoff sheet (155-01 output)
- **D-03:** `E_binary_by_cutoff` is written only when `CONFIG$distance_cutoff_mi` is set
  (non-NA). It shows **both encounter-level and patient-level** flagging statistics,
  stacked as two row-groups (matching `A_distribution_summary`'s two-level structure).
- **D-04:** Columns: `grain` (encounter/patient), `payer_category_9`, `n_total`,
  `n_flagged`, `pct_flagged`. Cross-tabs by `payer_category_9` — the 9-category canonical
  payer variable. One row per category per grain, plus an "Overall" row.
- **D-05:** Sheet shows the **live CONFIG cutoff only** — it is regenerated when the config
  is updated. The multi-cutoff comparison belongs in `F_sensitivity_cutoffs`.

### F_sensitivity_cutoffs sheet (155-03)
- **D-06:** `F_sensitivity_cutoffs` is written **always** (regardless of whether
  `distance_cutoff_mi` is set). It sweeps every value in `CONFIG$distance_candidate_cutoffs_mi`
  (default `c(30, 50)`).
- **D-07:** Format: one row per candidate cutoff. Columns: `cutoff_mi`, `n_enc_flagged`,
  `pct_enc_flagged`, `n_pat_flagged`, `pct_pat_flagged`, plus per-`payer_category_9`
  sub-columns (or stacked rows — planner's choice for readability). Lives in the same
  workbook as the other sheets; no separate xlsx file.
- **D-08:** Sheet lives **in the existing workbook** (`encounter_distance_<date>.xlsx`),
  not in a standalone script or separate file.

### Sensitivity harness (155-03) — implementation
- **D-09:** The harness is implemented as a code block within R/122 SECTION 12, not as
  a separate R script. It reads `computed_rows` (already in memory) and applies
  `far_from_care` logic for each cutoff in `cutoffs_mi`. No additional script file needed.

### Cutoff memo (155-02)
- **D-10:** File: `docs/distance_cutoff_memo.md`. One page, neutral register.
- **D-11:** Three candidate families presented:
  1. Distribution-based: median and 75th percentile of the observed encounter distribution
     (values from `A_distribution_summary` overall row).
  2. Literature-based: 30 mi and 50 mi thresholds — **placeholders** `[CITE: HL access
     literature]` inserted; Amy/Erin supply the specific papers from their prior work.
  3. Drive-time proxy: note that drive-time proxies are a later-phase option (not computed
     in this pipeline); this family is described in qualitative terms only.
- **D-12:** For each candidate, the memo reports: % of encounters flagged, % of patients
  flagged, and how the flag distributes across `payer_category_9`. Numbers drawn from
  `F_sensitivity_cutoffs` sheet values.
- **D-13:** Memo recommends the **shape** of the decision only (single cutoff vs.
  categorical bands) — does NOT recommend a specific value. The team (Amy/Erin) decides.
- **D-14:** A D-06 row is opened in AM §3 with `"Decision made: pending team"` — the memo
  is the deliverable that triggers this state.

### PNG histograms — dotted cutoff lines (Phase 154 deferred item)
- **D-15:** Phase 155 wires the dotted cutoff lines into the existing `plot_distance_hist()`
  call. Pass `CONFIG$distance_candidate_cutoffs_mi` (not `distance_cutoff_mi`) as the
  `cutoffs` arg so lines appear at **all candidates** (30 and 50 mi by default). This
  matches the comment at R/122:1146 and Appendix B's `cutoffs` parameter.
- Lines appear on all four PNGs (encounter/patient × linear/log) as dotted UF Orange.

### Claude's Discretion
- Exact layout of `F_sensitivity_cutoffs` rows vs columns for the payer breakdown
  (stacked rows vs sub-columns) — choose for readability given the 9-category count.
- Whether `far_from_care` is computed inline in SECTION 12 or as a helper function.
- Exact bin wording and section headers in `docs/distance_cutoff_memo.md`.
- Whether `E_binary_by_cutoff` uses a `grain` column or two separate row sections with
  a blank separator.
- AM §3 D-06 row format (consistent with existing D-01..D-05 rows in the AM).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Master spec
- `MILESTONE_encounter_distance.md` §Phase 155 (lines ~99–113) — 155-01/02/03 plan
  breakdown, success criteria, and dependency on Phase 154.
- `MILESTONE_encounter_distance.md` §D-06 (line ~35) — the pending D-06 decision record
  that Phase 155 opens in AM §3 as "pending team."
- `MILESTONE_encounter_distance.md` Appendix B — `plot_distance_hist()` signature including
  `cutoffs` arg (lines ~289–345); the `cutoffs` default is `NULL`, Phase 155 passes
  `CONFIG$distance_candidate_cutoffs_mi`.

### Script to modify
- `R/122_encounter_distance.R` — SECTION 12 (add `E_binary_by_cutoff` and
  `F_sensitivity_cutoffs` writers; add `far_from_care` / `far_from_care_cutoff_mi`
  columns when cutoff is set; pass `cutoffs_mi` to `make_distance_histograms()`).
- `R/00_config.R` — add `distance_cutoff_mi = NA` alongside `distance_candidate_cutoffs_mi`.

### New file to create
- `docs/distance_cutoff_memo.md` — cutoff evidence memo for Amy/Erin.

### Phase 154 context (lock decisions that carry forward)
- `.planning/phases/154-distribution-and-histogram-deliverable/154-CONTEXT.md` —
  D-06: `distance_patient_<date>.rds` includes `share_ge_<c>` columns feeding 155's
  patient-level flagging counts. `cutoffs_mi` variable already validated in SECTION 12.
  `payer_category_9` confirmed as the canonical payer variable.

### Prior phase contexts
- `.planning/phases/152-encounter-zip-to-residence-distance/152-CONTEXT.md`
- `.planning/phases/153-patient-zip-calendar-and-best-zip-selection/153-CONTEXT.md`
- `.planning/ROADMAP.md` §Phase 155

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `cutoffs_mi` vector — already validated in R/122 SECTION 12 (lines 1004–1013); reuse
  this variable directly for both `F_sensitivity_cutoffs` and the PNG cutoff arg.
- `computed_rows` — already defined as `filter(enc_distance, distance_status == "computed")`
  in SECTION 12; the harness iterates over this.
- `add_styled_sheet()` — existing xlsx helper in R/122; reuse for `E_binary_by_cutoff`
  and `F_sensitivity_cutoffs`.
- `distance_patient_<date>.rds` — written by Phase 154 SECTION 12; contains
  `share_ge_30` / `share_ge_50` per patient. Load to compute patient-level flagging counts
  for `F_sensitivity_cutoffs` without re-computing from enc_distance.
- `plot_distance_hist()` — in `R/utils/utils_distance_hist.R`; `cutoffs` arg already
  present (default `NULL`); Phase 155 passes `cutoffs_mi`.

### Established Patterns
- Config gate pattern: `if (!is.null(CONFIG$x) && !is.na(CONFIG$x))` — use consistently
  for both the E sheet and the `far_from_care` column emission.
- Sheet order: KEY, A_distribution_summary, B_histogram_bins, C_completeness,
  D_fill_offsets, [E_binary_by_cutoff when cutoff set], F_sensitivity_cutoffs.
- Column types in enc_distance: `far_from_care` should be integer (0L/1L), not logical,
  to match PCORnet convention for binary indicators.

### Integration Points
- `far_from_care` and `far_from_care_cutoff_mi` are added to `enc_distance` in SECTION 12
  before the workbook writer so the xlsx can reference them if needed — but they are not
  written to any current sheet other than `E_binary_by_cutoff`.
- `make_distance_histograms()` call in SECTION 12 already receives `cutoffs_mi` via the
  existing `cutoffs_mi` variable — just pass it as the `cutoffs` argument.

</code_context>

<specifics>
## Specific Design Notes

- **Byte-identical check (success criterion 1):** The planner must include a testthat
  fixture or manual check that with `distance_cutoff_mi = NA`, no new columns appear in
  `enc_distance` and `E_binary_by_cutoff` is absent from the workbook.
- **AM §3 D-06 row:** Should follow the format of existing D-01..D-05 rows in
  `MILESTONE_encounter_distance.md` AM §3 section (date, description, affected analyses).
  The status value is `"Decision made: pending team"` — not `"Resolved"`.
- **`docs/` directory:** Must be created if it doesn't exist (`dir.create()` with
  `showWarnings = FALSE` or R Markdown output path). The memo is a Markdown file, not
  a PDF or docx, so no pandoc dependency.
- **`payer_category_9`** must be present in `enc_distance` (carried from ENCOUNTER join
  in Phase 154). Confirm in SECTION 3/SECTION 7 that it's included; if not, it must be
  added in Phase 155 SECTION 3 alongside `ENC_TYPE`.

</specifics>

<deferred>
## Deferred Ideas

- Setting the actual `distance_cutoff_mi` value — this is D-06, pending Amy/Erin's
  decision after reviewing the memo.
- Drive-time proxy computation — noted in the memo as a future-phase option; not
  implemented in Phase 155.
- Wiring `far_from_care` into the main modeling pipeline — awaits the team's cutoff
  decision (same pattern as the SES-linkage deferral in Phase 141).

</deferred>

---

*Phase: 155-binary-indicator-and-cutoff-memo*
*Context gathered: 2026-09-18*
