# Phase 154: Distribution and Histogram Deliverable — Context

**Gathered:** 2026-09-18
**Revised:** 2026-09-18 (review pass)
**Status:** Ready for planning

> Decision IDs in this file are phase-local (`154-D1`..`154-D6`). Bare `D-nn` IDs refer to the
> milestone-level log in `MILESTONE_encounter_distance.md` and are reserved for AM §3.

<domain>
## Phase Boundary

Add `bin_distance()` / `plot_distance_hist()` / `make_distance_histograms()` helpers
(complete reference code in `MILESTONE_encounter_distance.md` Appendix B) as a new
`R/utils/utils_distance_hist.R` file sourced into `R/122_encounter_distance.R`.
Restructure the xlsx from the current 7-sheet Phase 152 layout to the 6-sheet Phase 154 spec.
Produce 4 histogram PNGs per run. Write the per-patient summary rds
(`distance_patient_<date>.rds`, milestone 154-03) that Phase 155 consumes.

Does NOT change `bin_distance()` logic, color constants, or file-naming conventions.
Bin width (5 mi) and cap (300 mi) keep the Appendix B defaults but remain function
arguments so Phase 155 can revisit them without editing the helper.

</domain>

<decisions>
## Implementation Decisions

### Histogram Helper File (154-D1)
- **154-D1:** Histogram helpers live in **`R/utils/utils_distance_hist.R`** — a new
  separate file sourced into `R/122` near the top alongside `utils_address.R` and
  `utils_zip_calendar.R`.
- Reason: matches "sourced by R/122" language in the milestone spec; follows the
  `utils_address.R` / `utils_zip_calendar.R` pattern; keeps R/122 below ~1200 lines;
  functions are independently testable without HiPerGator data.
- Functions in this file: `bin_distance()`, `plot_distance_hist()`,
  `make_distance_histograms()` — taken verbatim from Appendix B unless trivial fixes
  are needed for compatibility.

### Xlsx Sheet Restructuring (154-D2)
- **154-D2:** The xlsx is fully replaced with the 6-sheet Phase 154 spec:
  `KEY`, `A_distribution_summary`, `B_histogram_bins`, `C_completeness`,
  `D_fill_offsets`, `QC`.
- Old Phase 152 sheets (`A_encounter_distance`, `B_patient_summary`, `C_distribution`
  in km, `D_flags`, `E_completeness`) are **dropped from the xlsx**.
- Raw encounter-level rows are retained in the `.rds` file (already written in
  SECTION 12A of R/122) — no data is lost, just not in the workbook.
- Dropping `B_patient_summary` from the xlsx does NOT drop the patient-level
  deliverable: `distance_patient_<date>.rds` (milestone 154-03) is still written,
  with per-patient median/min/max `distance_mi`, n encounters, and share of
  encounters at each candidate cutoff (see 154-D6).

### Miles Only; km Bins Dropped (154-D3)
- **154-D3:** The old km-based distribution table (`C_distribution`, 0–5 / 5–25 / 50–200 /
  >200 km bins) is removed entirely. `B_histogram_bins` provides the canonical
  distribution in miles (matching the PNG figures). Going forward, miles is the
  reporting unit throughout the workbook.
- The milestone 152-02 cross-check (zipcodeR vs `haversine_km()` agree within 1 mile
  on a 500-pair sample) is NOT a workbook row; it lives in
  `tests/testthat/test-encounter-distance.R`, using `distance_km_haversine` retained
  in the rds (FIX B4).

### A_distribution_summary Breakouts (154-D4)
- **154-D4:** Breakouts delivered: **overall**, **by year** (year of `ADMIT_DATE`),
  **by `ENC_TYPE`**, **by facility state**.
- `ENC_TYPE` must be added in three places: the SECTION 3 ENCOUNTER pull (currently
  only `ID, ENCOUNTERID, ADMIT_DATE, FACILITY_LOCATION`), carried through the
  SECTION 4 join (automatic from `encounters_raw`), and added to the final
  `dplyr::select()` that builds `enc_distance` (R/122 lines 508–525). Without the
  third, it never reaches the workbook.
- **Facility state comes from `zipcodeR::zip_code_db$state` joined on
  `zip5_facility`** — exact, no ZIP3 derivation. `zip3_state.csv` stays confined to
  the QC section's unmatched-ZIP9 accounting. The same join yields the
  out-of-state-facility count needed for AM §4 Observed Issues (milestone 156-01).
- Statistics per row: `n`, `median_mi`, `IQR_mi`, `p90_mi`, `p95_mi`, `p99_mi`,
  `max_mi`. Mean and SD are omitted (less meaningful for right-skewed distance data).
- These statistics are computed by a dedicated `summarise_distance()` helper in
  `utils_distance_hist.R` (grouped `summarise()` over `enc_distance`), NOT taken
  from the `stats` element returned by `make_distance_histograms()` — that element
  only carries n, n_excluded, median, p90, n_zero and is for figure captions.

### D_fill_offsets Format (154-D5)
- **154-D5:** `D_fill_offsets` shows the `days_offset` distribution for encounters
  where `zip5_patient_source` ∈ {nearest_zip9, nearest_zip5} (i.e., the patient ZIP
  was filled from the nearest period rather than an in-range period).
- **Sign convention (from `pick_best_zip()`): positive `days_offset` = address
  period ended BEFORE the encounter (patient's past); negative = period started
  AFTER the encounter (patient's future).** State this on the sheet header and in
  the KEY; do not relabel.
- Format: **signed integer bins** (e.g., [-∞,−365], [−365,−180], [−180,−90],
  [−90,−30], [−30,−7], [−7,−1], [1,7], [7,30], [30,90], [90,180],
  [180,365], [365,+∞]) — preserves asymmetry. No `[0]` bin: in-range rows are
  excluded by definition, so nearest fills always have nonzero offset.
- Include `n`, `pct` per bin, plus summary rows: median of signed `days_offset`,
  median and p90 of `abs(days_offset)`, and share of fills from the past
  (offset > 0) vs future (offset < 0).

### Per-patient rds and candidate cutoffs (154-D6)
- **154-D6:** `distance_patient_<date>.rds` — one row per patient with any
  `computed` encounter: `ID`, `n_enc_computed`, `median_mi`, `min_mi`, `max_mi`,
  and `share_ge_<c>` for each `c` in `CONFIG$distance_candidate_cutoffs_mi`
  (default `c(30, 50)`; a config vector, not a decision — D-06 remains pending).
- Also written as the `stats` input to Phase 155; not included in the xlsx.

### Claude's Discretion
- Exact bin edges for `D_fill_offsets` (the sketch above is illustrative; planner
  may choose cleaner breakpoints that span the observed data range).
- Variable naming, pipe style (follow R/115/R/116/R/122 conventions).
- Whether `utils_distance_hist.R` gets a SECTION 1B header comment block.
- Exact column widths in xlsx output.
- Whether `make_distance_histograms()` is called before or after the xlsx writer
  in R/122 (bins list must be available to pass to `B_histogram_bins` writer, so
  it must run before wb_save).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Master spec and reference code
- `MILESTONE_encounter_distance.md` — Phase 154 section (lines 82–97) defines the
  plan breakdown (154-01, 154-02, 154-03) and success criteria. **Appendix B**
  (lines 245–354) is the complete reference implementation of the three histogram
  helper functions — use verbatim unless compatibility fixes are needed.
  `summarise_distance()` (154-D4) and the per-patient rds builder (154-D6) are NOT
  in Appendix B and must be written in this phase.
- `FIX_122_and_zip_calendar.md` — must be fully applied before this phase starts;
  in particular A5 (no `ADMIT_DATE` in `compute_encounter_distance()` output) and
  B4 (`distance_km_haversine` retained).

### Script to modify
- `R/122_encounter_distance.R` — SECTION 3 (add `ENC_TYPE` to ENCOUNTER pull),
  SECTION 7 final `select()` (add `ENC_TYPE`), SECTION 12 (replace xlsx writer
  with 6-sheet structure, call `make_distance_histograms()` and
  `summarise_distance()` before `wb_save()`, write `distance_patient_<date>.rds`).

### New file to create
- `R/utils/utils_distance_hist.R` — new file; sourced into R/122 alongside
  `utils_address.R` and `utils_zip_calendar.R`. Register in `R/SCRIPT_INDEX.md`
  (milestone 156-05 covers `utils_zip_calendar.R`; add this file to that line).
- `tests/testthat/test-utils-distance-hist.R` — `bin_distance()` edge cases
  (empty input, all zeros, single value above cap) and the zipcodeR-vs-haversine
  agreement test noted under 154-D3.

### Existing utils to reuse (do not duplicate)
- `R/utils/utils_address.R` — `haversine_km()`, `normalize_zip5_raw()`,
  `get_zip_centroid()` (for reference; distance computation stays in R/122 via
  zipcodeR).
- `R/utils/utils_zip_calendar.R` — `compute_encounter_distance()` output columns
  (`distance_mi`, `distance_status`, `zip5_patient_source`, `days_offset`) that
  feed the histogram and distribution table.

### Phase 153 output columns (available in R/122 after SECTION 4)
- `distance_mi` — zipcodeR distance in miles (canonical); NA when status ≠ computed
- `distance_status` ∈ {computed, facility_zip_missing, patient_zip_missing, zip_not_in_db}
- `zip5_patient_source` ∈ {in_range_zip9, in_range_zip5, nearest_zip9, nearest_zip5}
- `days_offset` — signed integer; 0 for in-range fills; nonzero for nearest fills

### Prior phase contexts
- `.planning/phases/152-encounter-zip-to-residence-distance/152-CONTEXT.md`
- `.planning/phases/153-patient-zip-calendar-and-best-zip-selection/153-CONTEXT.md`
- `.planning/ROADMAP.md` §Phase 154

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `add_styled_sheet()` in R/122 SECTION 12 — existing xlsx styling helper;
  the new 6-sheet writer should reuse it for all new sheets.
- `zip3_state.csv` lookup (already loaded in SECTION 11) — QC only; facility
  state for A_distribution_summary comes from `zip_code_db` per 154-D4.
- `unmatched_zip9_by_state` table (SECTION 11) — stays in QC sheet as-is.

### Established Patterns
- Pure functions in SECTION 1B before probe gates (R/115/R/116/R/122).
- KEY sheet leftmost; `wb_workbook()` → `add_styled_sheet()` → `wb_save()` pattern
  in R/122 SECTION 12.
- `figures/` subdirectory under `CONFIG$output_dir` for PNGs (`dir.create()` with
  `showWarnings = FALSE, recursive = TRUE` as in Appendix B).
- 300 dpi, `bg = "white"`, `width = 8, height = 5` per `ggsave()` call.

### Integration Points
- Source `utils_distance_hist.R` in R/122 SECTION 1 (library block), after
  sourcing `utils_zip_calendar.R`.
- `make_distance_histograms()` call goes in SECTION 12 before `wb_save()`:
  returns `list(bins, stats)` — `bins` feeds `B_histogram_bins`; `stats` is used
  only for PNG captions and a QC cross-check that its `n` equals the
  `A_distribution_summary` overall `n`.
- `summarise_distance(enc_distance, by = NULL / "year" / "ENC_TYPE" / "facility_state")`
  builds `A_distribution_summary`; rows stacked with a `breakout` column.
- Facility state: `left_join(zipcodeR::zip_code_db[, c("zipcode", "state")],
  by = c("zip5_facility" = "zipcode"))` once in SECTION 12; result reused by the
  out-of-state count in QC.
- `ENC_TYPE` added to `dplyr::select()` in SECTION 3, to the final `select()` in
  SECTION 7, and carried through to SECTION 12's distribution-summary grouping.

</code_context>

<specifics>
## Specific Design Notes

- **4 PNGs per run:** `figures/encounter_distance_hist_{encounter|patient}_{linear|log}_{YYYYMMDD}.png`
- **B_histogram_bins** contains `level` (encounter/patient), `scale` (linear/log),
  `bin`, `lower`, `upper`, `lower_mi`, `upper_mi`, `n`, `pct` — the exact columns
  returned by `bin_distance()` plus the `level` column added by `make_distance_histograms()`.
- **C_completeness** carries forward the Phase 153 completeness waterfall
  (encounters → with facility ZIP → with in-range patient ZIP → with nearest patient
  ZIP → distance computed). This replaces the old `E_completeness` sheet.
- **Reference lines in PNGs:** median solid UF Orange, p90 dashed UF Orange.
  Phase 155 candidate cutoffs (dotted) are NOT added until Phase 155 — `cutoffs`
  arg to `plot_distance_hist()` should default to NULL.
- **Success criterion (row-count reconciliation):** `n` in the
  `A_distribution_summary` overall row must equal the `computed` count from
  Phase 152/153 (i.e., `nrow(filter(enc_distance, distance_status == "computed"))`),
  and must equal `stats$n` for the encounter level from `make_distance_histograms()`.
  Patient-level `n` equals `n_distinct(ID)` among computed rows and equals
  `nrow(distance_patient_<date>.rds)`.

</specifics>

<deferred>
## Deferred Ideas

- Revisiting the 5-mile bin width and 300-mile cap after the first real run
  (milestone note) — deferred to Phase 155, which owns the cutoff discussion.

</deferred>

---

*Phase: 154-distribution-and-histogram-deliverable*
*Context gathered: 2026-09-18*
