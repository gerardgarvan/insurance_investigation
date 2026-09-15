# Phase 152: Encounter-ZIP to Residence Distance — Context

**Gathered:** 2026-09-15
**Status:** Ready for planning
**Source:** PRD Express Path (phase142.txt)

<domain>
## Phase Boundary

Standalone investigation script (`R/122_encounter_distance.R`) that computes
great-circle distance between each cohort encounter's ZIP and the patient's
residential address in effect on the encounter date. Produces an encounter-level
distance table plus patient-level and distributional summaries. Does NOT impute
ZIPs, does NOT wire into the main pipeline, and does NOT compute road-network
distance. Output pattern mirrors R/115 (standalone counts deliverable, xlsx +
rds).

**Script number:** R/122 — R/116 is already taken by `116_encounter_ses_index.R`
(Phase 144). The phase spec references "R/116" but that slot is occupied; use
R/122 as the next available investigation slot.

</domain>

<decisions>
## Implementation Decisions

### New Script
- `R/122_encounter_distance.R` — mirrors R/115 structural conventions: header
  block, SECTION 1 setup, SECTION 1B pure/testable core functions defined before
  the HiPerGator probe gate, SECTION 2 probe gate, etc.
- Cohort scope: HL cohort (N = 9,282), IDs sourced from DuckDB via CONFIG.
- Output files: `output/encounter_distance_YYYYMMDD.xlsx` + `output/encounter_distance_YYYYMMDD.rds`
- KEY sheet leftmost (D-02 pattern from Phase 141/Phase 116).

### New Helpers in `R/utils/utils_address.R`
Two new exported functions appended to the existing file:

1. **`get_zip_centroid(zip, level = c("zip5", "zip9"))`**
   - ZIP5 path: join ZIP5 → ZCTA5 → Census ZCTA gazetteer internal-point lat/lon.
     Reference file: `data/reference/zcta_gazetteer_centroids.csv`
     (Census ZCTA INTPTLAT/INTPTLON; must be staged on HiPerGator before run).
   - ZIP9 path: join ZIP9 (first 5 digits = ZIP5; full 9 = block-group GEOID
     from Neighborhood Atlas crosswalk) → block-group internal-point centroid.
     Reference file: `data/reference/zip9_bg_centroid_crosswalk.csv`
     (ZIP9, GEOID, INTPTLAT, INTPTLON; 51/52 states already acquired per spec).
     Falls back to ZIP5 centroid when ZIP9 is unmatched.
   - Returns tibble: `zip, level, lat, lon, centroid_source`
     where `centroid_source` ∈ `{"zip5_gazetteer", "zip9_bg", "zip5_fallback"}`.

2. **`haversine_km(lat1, lon1, lat2, lon2)`**
   - Vectorized great-circle distance in km using the haversine formula.
   - Earth radius = 6371 km (WGS-84 mean).
   - Returns numeric vector; NA when any input is NA.
   - Defined in SECTION 1B (pure, no I/O) so tests can source the file without
     HiPerGator data.

### Encounter-Side ZIP Resolution
- Pull ENCOUNTER rows from DuckDB scoped to HL cohort IDs + ADMIT_DATE.
- Normalize encounter ZIP with existing `normalize_zip9()` / `normalize_zip5()`.
- Resolve to ZIP9 centroid when available (`get_zip_centroid(zip, "zip9")`);
  fall back to ZIP5 centroid.

### Residence-Side ZIP Resolution
- Call `get_zip9_at_date(ID, ADMIT_DATE)` (backward-only, most-recent-before
  fallback as in Phase 139). Match type recorded (`match_type` from the function).
- Fallback indicator: whether match was interval-exact or most-recent-before.
- Resolve residence ZIP to finest level available.

### Distance Computation
- Finest level available on both sides; e.g., if encounter has ZIP9 centroid and
  residence has ZIP5 centroid, use both but record `distance_basis = "zip9–zip5"`.
- `distance_basis` values: `"zip9–zip9"`, `"zip9–zip5"`, `"zip5–zip9"`, `"zip5–zip5"`.
- Distance = `haversine_km(enc_lat, enc_lon, res_lat, res_lon)`.
- NA distance when either centroid is unresolvable.

### Distance Thresholds (D-01)
- Far-distance flag threshold: **200 km** (primary), **50 km** (secondary).
- Both thresholds recorded in D_flags sheet.

### Fallback Encounters in Summaries (D-02)
- Encounters whose residence match is a most-recent-before fallback are
  **included** in B_patient_summary and C_distribution.
- A `res_match_fallback` boolean column distinguishes them.
- QC sheet has a sensitivity row isolating fallback-only distances.

### ENCOUNTER ZIP Interpretation (D-03)
- Treat as an open question to be documented in the KEY sheet.
- The KEY text states: "Whether encounter ZIP is patient- or facility-sourced in
  this OneFlorida+ extract is unknown; column description reflects travel
  distance if facility-sourced, proxy validation if patient-sourced."
- Code is identical either way.

### Block-Group Centroid Source (D-04)
- Use whichever centroid file is already staged under `/blue/erin.mobley.precision/`
  on HiPerGator. The plan should include a probe gate that checks for the file
  at `CONFIG$data_dir` (or a sibling path from CONFIG) and stops with an
  actionable message if absent. Default path key: `CONFIG$zip9_bg_centroid_path`.

### Output Sheets (xlsx)
| Sheet | Content |
|-------|---------|
| KEY | Sheet index + column dictionary |
| A_encounter_distance | One row per encounter: ID, ENCOUNTERID, ADMIT_DATE, enc_zip_norm, res_zip9, res_zip5, res_match_type, res_match_fallback, distance_km, distance_basis, enc_centroid_source, res_centroid_source |
| B_patient_summary | Per patient: n_encounters, n_with_distance, median_km, iqr_km, max_km, pct_gt50km, pct_gt200km |
| C_distribution | Distance bins (0–5, 5–25, 25–50, 50–200, >200 km) × distance_basis, encounter and patient counts |
| D_flags | Encounters > 200 km (and > 50 km secondary), with residence interval matched, for team review |
| QC | Coverage waterfall (encounters total → normalized ZIP → residence resolved → centroid resolved → distance computed); unmatched ZIP9 count by state; WV gap noted; fallback sensitivity row |

### Tests (`tests/testthat/test-122-distance.R`)
- `haversine_km` against known city pairs (e.g., Miami–Tampa ≈ 330 km).
- `get_zip_centroid` for a ZIP5 with and without a ZIP9 match.
- Fallback `distance_basis` assignment when ZIP9 centroid is absent.
- An all-missing-ZIP encounter yields `NA` distance without error.

### Claude's Discretion
- Internal variable naming, pipe style (consistent with R/115/R/116).
- Whether `get_zip_centroid()` memoizes the reference file reads (recommended
  for performance; follow pattern of `.centroid_zip9_lookup_cache` in utils_address.R).
- Exact column widths in xlsx output.
- Whether the rds output is the full encounter-level tibble or a list with both A and B tables.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing patterns this phase must follow
- `R/utils/utils_address.R` — `get_zip9_at_date()`, `normalize_zip9()`, `normalize_zip5()`, `approximate_zip9()`, `.centroid_zip9_lookup_cache` memoization pattern
- `R/115_zip_stability_counts.R` — script structure conventions (header block, SECTION 1B pure functions, probe gate, HiPerGator checkpoint pattern)
- `R/116_encounter_ses_index.R` — D-02 xlsx output pattern (KEY leftmost, encounter-level + summary sheets), how ENCOUNTER is pulled from DuckDB

### Reference data already present
- `data/reference/neighborhood_atlas_zip9_adi.csv` — ZIP9 ADI (columns: ZIP9, ADI_NATRANK)
- `data/reference/zip5_sdi_reference.csv` — ZIP5 SDI (columns: ZIP5, SDI_score)
- `data/reference/svi_2020_zcta_derived.csv` — ZCTA SVI (columns: ZCTA, RPL_THEMES)

### Reference data NOT YET STAGED (must be obtained before HiPerGator run)
- `data/reference/zcta_gazetteer_centroids.csv` — Census ZCTA internal-point centroids (ZCTA5, INTPTLAT, INTPTLON); source: Census ZCTA Gazetteer Files
- `data/reference/zip9_bg_centroid_crosswalk.csv` — ZIP9 → block-group GEOID → INTPTLAT/INTPTLON crosswalk (51/52 states acquired per spec); source: `/blue/erin.mobley.precision/`

### Planning / state context
- `.planning/ROADMAP.md` Phase 152 entry
- `.planning/STATE.md` — accumulated project decisions

</canonical_refs>

<specifics>
## Specific Ideas from Spec

- **Exit criteria (from spec):** Script runs end-to-end on HiPerGator against
  N=9,282 HL cohort and re-issues workbook; testthat coverage as above; QC
  waterfall reconciles to ENCOUNTER row count in DuckDB.
- **West Virginia gap:** explicitly note in QC sheet that WV ZIP9 centroid
  coverage may be lower due to crosswalk gap.
- **D-flags threshold:** 200 km primary / 50 km secondary — both recorded.
- **Script registration:** register R/122 in `R/39_register_scripts.R`,
  `R/88_section15af...R` (if applicable), and `R/SCRIPT_INDEX.md`.

</specifics>

<deferred>
## Deferred Items

- Road-network / drive-time distance (great-circle only in this phase).
- ZIP9 imputation for encounters lacking a ZIP (Phase 141 / centroid-imputation phase consumes whatever ZIP the encounter carries).
- SDI/ADI linkage to the distance output (separate phase).
- Main-pipeline wiring of R/122 outputs.

</deferred>

---

*Phase: 152-encounter-zip-to-residence-distance*
*Context gathered: 2026-09-15 via PRD Express Path (phase142.txt)*
