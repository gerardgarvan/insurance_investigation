# Phase 153: Patient ZIP Calendar and Best-ZIP Selection — Context

**Gathered:** 2026-09-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Add `R/utils/utils_zip_calendar.R` with three exported functions:
`build_patient_zip_calendar()`, `pick_best_zip()`, and
`compute_encounter_distance()`. Wire `compute_encounter_distance()` into
`R/122_encounter_distance.R`, replacing the existing `get_zip9_at_date()` call
in SECTION 4. Implements AM rules 2–3 with full provenance tracking.

Does NOT touch `get_zip9_at_date()` itself — Phase 139/141 consumers keep their
current behavior unchanged.

</domain>

<decisions>
## Implementation Decisions

### D-02 — Which patient ZIP
- **D-01:** Patient ZIP is **time-varying**: `build_patient_zip_calendar()` reads
  `LDS_ADDRESS_HISTORY` and each encounter receives the ZIP active on its
  `ADMIT_DATE` (or the nearest one if no period covers it). A single static
  per-patient ZIP (e.g., at index date) is explicitly rejected.

### D-04 — Scope of rule 3 (nearest-ZIP fill)
- **D-02:** Rule 3 applies to the **patient side only**. When
  `ENCOUNTER.FACILITY_LOCATION` is blank, the script counts and reports it as
  `facility_zip_missing` in `distance_status` — it does not impute a facility
  location from any other source. A missing facility ZIP is a separate data
  quality problem, not addressable by `LDS_ADDRESS_HISTORY`.

### Calendar source
- **D-03:** `build_patient_zip_calendar()` reads **address history only**
  (`LDS_ADDRESS_HISTORY`). `ENCOUNTER.FACILITY_LOCATION` is never added to the
  patient calendar — mixing a facility ZIP into the patient residence calendar
  would corrupt the distance calculation for encounters at the patient's own
  facility ZIP.

### ZIP9 vs ZIP5 ranking in `pick_best_zip()`
- **D-04:** Two-zone ranking (departs from Appendix A reference code):
  - **In-range candidates** (period covers `ADMIT_DATE`): rank by
    `zip_len desc` (ZIP9 > ZIP5), then `|days_offset|` (=0 for all
    in-range, so this only matters if there are multiple in-range periods),
    then `desc(days_offset)` (D-03 tie-breaker: prefer earlier period).
  - **Out-of-range candidates** (no period covers `ADMIT_DATE`): rank by
    `|days_offset|` only — ZIP tier is **ignored** when picking the nearest
    address in time. Tie on `|days_offset|`: prefer earlier period
    (`desc(days_offset)`, D-03).
  - An in-range ZIP5 always beats an out-of-range ZIP9.
  - Planner must revise the single `arrange()` in Appendix A to implement this
    two-zone logic (e.g., `arrange(desc(in_range), if_else(in_range, desc(zip_len), 0L), abs(days_offset), desc(days_offset))`
    or equivalent branching).

### D-03 — Tie-breaking (resolved 2026-09-17, carried forward)
- **D-05:** When two address periods have equal `|days_offset|`, prefer the
  **earlier** period (the one that was already in force or ended before the
  encounter). Implemented via `desc(days_offset)`: positive offsets (period
  before encounter) sort ahead of negative offsets (period after encounter).

### Claude's Discretion
- Internal variable naming and pipe style (follow R/115/R/116 conventions).
- Whether `build_patient_zip_calendar()` memoizes the address-history read (recommended for R/122 performance; follow `.centroid_zip9_lookup_cache` pattern in `utils_address.R`).
- Exact column widths in xlsx output.
- Implementation of the two-zone arrange (see D-04 above); any clean equivalent of the branching logic is acceptable as long as the priority is correct.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase spec and design code
- `MILESTONE_encounter_distance.md` — master spec; Appendix A contains the
  reference code for all three functions. **Note:** the `arrange()` in
  `pick_best_zip()` must be revised per D-04 above (two-zone ranking, not a
  single flat arrange).
- `.planning/ROADMAP.md` §Phase 153 — requirements DIST-02, DIST-03, DIST-07

### Existing utilities to reuse (do not duplicate)
- `R/utils/utils_address.R` — `normalize_zip9()`, `normalize_zip5()`,
  `normalize_zip5_raw()`, `is_sentinel_zip5()`, `haversine_km()`,
  `get_zip9_at_date()` (kept as-is; Phase 153 does not modify it),
  `.centroid_zip9_lookup_cache` memoization pattern
- `R/115_zip_stability_counts.R` — script structure conventions
- `R/116_encounter_ses_index.R` — xlsx output pattern (KEY leftmost)

### Script to wire into
- `R/122_encounter_distance.R` — SECTION 4 (`get_zip9_at_date()` call at line ~229)
  is replaced by `compute_encounter_distance()`; completeness waterfall sheet
  added (encounters → with facility ZIP → with in-range patient ZIP → with
  nearest patient ZIP → distance computed)

### Registration targets (DIST-07)
- `R/39_run_all_investigations.R`
- `R/88_smoke_test_comprehensive.R` (or equivalent)
- `R/SCRIPT_INDEX.md`

### Prior phase context
- `.planning/phases/152-encounter-zip-to-residence-distance/152-CONTEXT.md`
- `.planning/STATE.md`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `normalize_zip9()` / `normalize_zip5()` / `normalize_zip5_raw()` — ZIP
  normalization already in `utils_address.R`; import them, don't redefine.
- `haversine_km()` — already in `utils_address.R` (added Phase 152); use as
  test-only cross-check against `zipcodeR::zip_distance()`.
- `is_sentinel_zip5()` — use to filter placeholder ZIPs from the calendar.
- `get_zip_centroid()` / `.centroid_zip9_lookup_cache` — memoization pattern
  to follow for any reference-file reads inside `build_patient_zip_calendar()`.

### Established Patterns
- Pure functions in SECTION 1B (before probe gate) so testthat can source the
  file without HiPerGator data — same as R/115/R/122.
- `zipcodeR::zip_distance()` is canonical for distance (D-01 from Phase 152);
  compute on distinct `(zip5_patient, zip5_facility)` pairs for performance,
  then join back (Appendix A pattern).
- KEY sheet leftmost in xlsx (D-02 pattern from Phase 116/141).
- `distance_status` ∈ {computed, facility_zip_missing, patient_zip_missing,
  zip_not_in_db} — column already defined in Phase 152 output; Phase 153 must
  produce the same set.

### Integration Points
- `R/122` SECTION 4: replace `get_zip9_at_date()` block (lines ~224–264) with
  a call to `build_patient_zip_calendar()` + `compute_encounter_distance()`.
  The `utils_zip_calendar.R` file should be sourced near the top of R/122
  alongside `utils_address.R`.

</code_context>

<specifics>
## Specific Design Notes

- **`zip5_patient_source` values** ∈ {in_range_zip9, in_range_zip5, nearest_zip9,
  nearest_zip5}; `days_offset` is a signed integer (0 for in-range, negative
  when encounter precedes the period, positive when encounter follows the period).
- **`n_candidates_in_range`** must be computed and reported in the QC sheet so
  the team can see how often a patient had multiple ZIPs active on the same date.
- **Study end date** for closing open `ADDRESS_PERIOD_END` entries: 2025-03-31
  (matches `CONFIG$analysis$date_range_max`).
- **Success criteria from ROADMAP:**
  1. `zip5_patient_source` ∈ {in_range_zip9, in_range_zip5, nearest_zip9,
     nearest_zip5} for every encounter row; `days_offset` is signed integer.
  2. Completeness waterfall reconciles row-for-row with `distance_status` counts.
  3. `n_candidates_in_range > 1` count reported in QC.
  4. Unit tests in `tests/testthat/test-utils-zip-calendar.R` pass.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 153-patient-zip-calendar-and-best-zip-selection*
*Context gathered: 2026-09-17*
