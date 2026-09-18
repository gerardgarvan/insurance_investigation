# Phase 154: Distribution and Histogram Deliverable — Context

**Gathered:** 2026-09-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Add `bin_distance()` / `plot_distance_hist()` / `make_distance_histograms()` helpers
(complete reference code in `MILESTONE_encounter_distance.md` Appendix B) as a new
`R/utils/utils_distance_hist.R` file sourced into `R/122_encounter_distance.R`.
Restructure the xlsx from the current 7-sheet Phase 152 layout to the 6-sheet Phase 154 spec.
Produce 4 histogram PNGs per run.

Does NOT change `bin_distance()` logic, color constants, bin widths, or file-naming
conventions — all locked in Appendix B.

</domain>

<decisions>
## Implementation Decisions

### Histogram Helper File (D-01)
- **D-01:** Histogram helpers live in **`R/utils/utils_distance_hist.R`** — a new
  separate file sourced into `R/122` near the top alongside `utils_address.R` and
  `utils_zip_calendar.R`.
- Reason: matches "sourced by R/122" language in the milestone spec; follows the
  `utils_address.R` / `utils_zip_calendar.R` pattern; keeps R/122 below ~1200 lines;
  functions are independently testable without HiPerGator data.
- Functions in this file: `bin_distance()`, `plot_distance_hist()`,
  `make_distance_histograms()` — taken verbatim from Appendix B unless trivial fixes
  are needed for compatibility.

### Xlsx Sheet Restructuring (D-02)
- **D-02:** The xlsx is fully replaced with the 6-sheet Phase 154 spec:
  `KEY`, `A_distribution_summary`, `B_histogram_bins`, `C_completeness`,
  `D_fill_offsets`, `QC`.
- Old Phase 152 sheets (`A_encounter_distance`, `B_patient_summary`, `C_distribution`
  in km, `D_flags`, `E_completeness`) are **dropped from the xlsx**.
- Raw encounter-level rows are retained in the `.rds` file (already written in
  SECTION 12A of R/122) — no data is lost, just not in the workbook.

### Miles Only; km Bins Dropped (D-03)
- **D-03:** The old km-based distribution table (`C_distribution`, 0–5 / 5–25 / 50–200 /
  >200 km bins) is removed entirely. `B_histogram_bins` provides the canonical
  distribution in miles (matching the PNG figures). Going forward, miles is the
  reporting unit throughout the workbook.

### A_distribution_summary Breakouts (D-04)
- **D-04:** Breakouts delivered: **overall**, **by year** (year of `ADMIT_DATE`),
  **by `ENC_TYPE`**.
- `ENC_TYPE` must be added to the SECTION 3 ENCOUNTER pull (currently only
  `ID, ENCOUNTERID, ADMIT_DATE, FACILITY_LOCATION`).
- **By-state breakout is omitted** — ZIP3→state derivation is too imprecise for a
  published distribution table (even though zip3_state.csv is present and used in
  the QC section for unmatched-ZIP9 accounting).
- Statistics per row: `n`, `median_mi`, `IQR_mi`, `p90_mi`, `p95_mi`, `p99_mi`,
  `max_mi`. Mean and SD are omitted (less meaningful for right-skewed distance data).

### D_fill_offsets Format (D-05)
- **D-05:** `D_fill_offsets` shows the `days_offset` distribution for encounters
  where `zip5_patient_source` ∈ {nearest_zip9, nearest_zip5} (i.e., the patient ZIP
  was filled from the nearest period rather than an in-range period).
- Format: **signed integer bins** (e.g., [-∞,−365], [−365,−180], [−180,−90],
  [−90,−30], [−30,−7], [−7,−1], [0], [1,7], [7,30], [30,90], [90,180],
  [180,365], [365,+∞]) — preserves asymmetry so the team can see whether fills
  come predominantly from the patient's past (most-recent-before) or future.
- Include `n`, `pct` per bin, plus a summary row with median and p90 of
  signed `days_offset`.

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
  (lines 245–354) is the complete reference implementation of all three histogram
  helper functions — use verbatim unless compatibility fixes are needed.

### Script to modify
- `R/122_encounter_distance.R` — SECTION 3 (add `ENC_TYPE` to ENCOUNTER pull),
  SECTION 12 (replace xlsx writer with 6-sheet structure, call
  `make_distance_histograms()` before `wb_save()`).

### New file to create
- `R/utils/utils_distance_hist.R` — new file; sourced into R/122 alongside
  `utils_address.R` and `utils_zip_calendar.R`.

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
- `zip3_state.csv` lookup (already loaded in SECTION 11) — available for QC but
  NOT used for A_distribution_summary per D-04.
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
  returns `list(bins, stats)` — `bins` feeds `B_histogram_bins`, `stats` feeds
  `A_distribution_summary` overall row.
- `ENC_TYPE` added to `dplyr::select()` in SECTION 3 and carried through to
  SECTION 12's distribution-summary grouping.

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
- **Success criterion (row-count reconciliation):** row count in
  `A_distribution_summary` overall row must equal the `computed` count from
  Phase 152/153 (i.e., `nrow(filter(enc_distance, distance_status == "computed"))`).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 154-distribution-and-histogram-deliverable*
*Context gathered: 2026-09-18*
