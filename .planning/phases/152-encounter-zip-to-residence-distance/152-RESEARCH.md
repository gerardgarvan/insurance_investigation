# Phase 152: Encounter-ZIP to Residence Distance — Research

**Researched:** 2026-09-15
**Domain:** Geospatial distance computation in R; Census ZCTA Gazetteer; PCORnet ENCOUNTER table ZIP fields; utils_address.R memoization; haversine formula
**Confidence:** HIGH (all key questions answered from direct code inspection, official Census docs, and CRAN docs)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Script number: `R/122_encounter_distance.R` (R/116 is taken by encounter_ses_index.R)
- Output files: `output/encounter_distance_YYYYMMDD.xlsx` + `output/encounter_distance_YYYYMMDD.rds`
- KEY sheet leftmost (D-02 pattern from Phase 141/Phase 116)
- Cohort scope: HL cohort (N = 9,282), IDs from DuckDB via CONFIG
- Script structure mirrors R/115: header block, SECTION 1B pure functions before probe gate, SECTION 2 probe gate
- Two new helpers appended to `R/utils/utils_address.R`:
  1. `get_zip_centroid(zip, level = c("zip5", "zip9"))` — returns tibble: `zip, level, lat, lon, centroid_source`; centroid_source in `{"zip5_gazetteer", "zip9_bg", "zip5_fallback"}`
  2. `haversine_km(lat1, lon1, lat2, lon2)` — vectorized great-circle in km; Earth radius 6371 km; NA when any input NA; defined in SECTION 1B
- ZIP5 path: join ZIP5 → ZCTA5 → `data/reference/zcta_gazetteer_centroids.csv` (INTPTLAT, INTPTLONG)
- ZIP9 path: `data/reference/zip9_bg_centroid_crosswalk.csv` (ZIP9, GEOID, INTPTLAT, INTPTLON); fallback to ZIP5 centroid when unmatched
- Residence side: `get_zip9_at_date(ID, ADMIT_DATE)` backward-only, most-recent-before fallback (Phase 139 convention)
- distance_basis values: `"zip9–zip9"`, `"zip9–zip5"`, `"zip5–zip9"`, `"zip5–zip5"`
- Far-distance thresholds: 200 km primary, 50 km secondary; both in D_flags sheet
- Fallback encounters (res_match_fallback) included in B_patient_summary and C_distribution; distinguished by boolean `res_match_fallback`
- QC sheet has sensitivity row isolating fallback-only distances
- Encounter ZIP interpretation treated as open question; documented in KEY sheet as D-03
- Block-group centroid probe gate: check `CONFIG$zip9_bg_centroid_path`; stop with actionable message if absent
- Output sheets: KEY, A_encounter_distance, B_patient_summary, C_distribution, D_flags, QC
- A_encounter_distance columns: ID, ENCOUNTERID, ADMIT_DATE, enc_zip_norm, res_zip9, res_zip5, res_match_type, res_match_fallback, distance_km, distance_basis, enc_centroid_source, res_centroid_source
- B_patient_summary columns: n_encounters, n_with_distance, median_km, iqr_km, max_km, pct_gt50km, pct_gt200km
- C_distribution: bins (0–5, 5–25, 25–50, 50–200, >200 km) × distance_basis
- WV gap: explicitly note in QC that WV ZIP9 centroid coverage may be lower
- Tests: `tests/testthat/test-122-distance.R`
- Register R/122 in `R/39_run_all_investigations.R`, `R/88_smoke_test_comprehensive.R`, and `R/SCRIPT_INDEX.md`
- Deferred: road-network distance, ZIP9 imputation, SDI/ADI linkage, main-pipeline wiring

### Claude's Discretion

- Internal variable naming and pipe style (consistent with R/115/R/116)
- Whether `get_zip_centroid()` memoizes reference file reads (recommended; follow `.centroid_zip9_lookup_cache` pattern)
- Exact column widths in xlsx output
- Whether RDS output is the full encounter-level tibble or a list with both A and B tables

### Deferred Ideas (OUT OF SCOPE)

- Road-network / drive-time distance
- ZIP9 imputation for encounters lacking a ZIP
- SDI/ADI linkage to distance output
- Main-pipeline wiring of R/122 outputs
</user_constraints>

---

## Summary

Phase 152 adds a standalone investigation script (`R/122_encounter_distance.R`) that computes the haversine (great-circle) distance between each cohort encounter's recorded ZIP and the patient's residential address on that encounter date. Two new helpers go into `utils_address.R`: a centroid resolver (`get_zip_centroid`) and a vectorized haversine calculator (`haversine_km`).

All key technical questions are answerable from direct inspection of the existing codebase and official documentation. The ENCOUNTER table carries a `FACILITY_LOCATION` column (confirmed in `R/01_load_pcornet.R` line 176); that is the only ZIP-like field in the ENCOUNTER schema — no `ZIP` or `ZIPCODE` column exists. The Census ZCTA Gazetteer file uses column names `GEOID` (ZCTA5 identifier), `INTPTLAT`, and `INTPTLONG` (with a trailing G). The haversine formula should be implemented inline in SECTION 1B rather than importing `geosphere`, keeping the file sourceable in a no-package test environment and avoiding a new dependency.

The memoization pattern for `get_zip_centroid()` must follow the existing `<<-` pattern used by `.centroid_zip9_lookup_cache` and `.zip5_lookup_cache` in `utils_address.R`, keyed by `(path, mtime, size)` to force rebuild when files change. The probe gate for both centroid files must be SECTION 1B-safe (no I/O) when running in a test context, with actual file probes in SECTION 2 following the R/115 dual-gate pattern.

**Primary recommendation:** implement `haversine_km` as a pure inline function (no `geosphere` dependency), implement `get_zip_centroid` with memoized reference-file reads using the established `<<-` cache pattern, and structure the encounter pull identically to R/116's SECTION 4 (`get_pcornet_table("ENCOUNTER") %>% dplyr::rename_with(toupper)`) scoped to HL cohort IDs.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | project std | Data manipulation | Named-predicate convention; all analysis scripts use it |
| openxlsx2 | project std | xlsx output | Used by R/115, R/116 for all workbook output |
| glue | project std | Message formatting | Used throughout pipeline |
| stringr | project std | ZIP normalization | Used by normalize_zip9/zip5 in utils_address.R |
| vroom | project std | Reference CSV loading | Used by utils_address.R for all reference file loads |
| tibble | project std | Typed data frames | Used by all helpers in utils_address.R |

### No New Dependencies Required

`haversine_km` is a 5-line inline formula. The `geosphere::distHaversine` CRAN function exists (MEDIUM confidence from CRAN docs) but introduces a new dependency for a function simpler to implement inline. Project convention (no installs inside SLURM, renv::snapshot required) makes avoiding unnecessary new packages the right default.

**Installation:** No new packages required.

---

## Architecture Patterns

### Script Section Structure (mirrors R/115 exactly)

```
SECTION 1:   SETUP AND LIBRARIES (suppressPackageStartupMessages, source("R/00_config.R"))
SECTION 1B:  TESTABLE CORE FUNCTIONS (haversine_km, get_zip_centroid — pure, no I/O)
SECTION 2:   CONSTANTS AND PROBE GATES (output paths, centroid file checks, DuckDB check)
SECTION 3:   ENCOUNTER PULL (DuckDB, HL cohort scope, ADMIT_DATE parsing)
SECTION 4:   RESIDENCE ZIP RESOLUTION (get_zip9_at_date)
SECTION 5:   ENCOUNTER ZIP NORMALIZATION (normalize_zip9/normalize_zip5 on FACILITY_LOCATION)
SECTION 6:   CENTROID RESOLUTION (get_zip_centroid for both sides)
SECTION 7:   DISTANCE COMPUTATION (haversine_km, distance_basis assignment)
SECTION 8:   PATIENT SUMMARY (B_patient_summary)
SECTION 9:   DISTRIBUTION TABLE (C_distribution)
SECTION 10:  FLAGS (D_flags: encounters > 200 km and > 50 km)
SECTION 11:  QC WATERFALL
SECTION 12:  XLSX ASSEMBLY AND WRITE
```

### ENCOUNTER ZIP Column: FACILITY_LOCATION

**CRITICAL finding (HIGH confidence — directly observed in `R/01_load_pcornet.R` line 176):**

The ENCOUNTER table in this project's PCORnet CDM has no column named `ZIP`, `ZIPCODE`, or `FACILITY_ZIP`. The ZIP-like field is `FACILITY_LOCATION` (character type). This is the column to normalize with `normalize_zip9()` / `normalize_zip5_raw()` for the encounter side.

PCORnet CDM v6.x specifies `FACILITY_LOCATION` as the ZIP field on encounter records (it is free-text in the spec, typically populated with a ZIP or ZIP+4). Confirmed in `01_load_pcornet.R:176`:
```r
FACILITY_LOCATION = col_character(),
```

Plan tasks should reference `FACILITY_LOCATION` explicitly; do not search for `ZIP` or `ZIPCODE`.

### get_zip_centroid() — Design Pattern

Follow the `.centroid_zip9_lookup_cache` memoization pattern from `utils_address.R` lines 563–613 precisely:

```r
# Cache declared at file scope (before any function):
.zcta_gazetteer_cache    <- list(key = NULL, value = NULL)
.zip9_bg_centroid_cache  <- list(key = NULL, value = NULL)

get_zip_centroid <- function(zip, level = c("zip5", "zip9")) {
  level <- match.arg(level)
  # SECTION 1B: pure logic only — no file I/O here; file probing is in SECTION 2
  # Reference files loaded lazily on first call using CONFIG$reference_dir path
  # Cache key: paste0(normalizePath(path), "|", mtime, "|", size)
  # <<- writes to file-scope cache
  # Returns tibble: zip, level, lat, lon, centroid_source
  # centroid_source: "zip5_gazetteer" | "zip9_bg" | "zip5_fallback"
}
```

### Census ZCTA Gazetteer Column Names (HIGH confidence — official Census docs)

The 2020 ZCTA Gazetteer file is tab-delimited with these columns relevant to Phase 152:
- `GEOID` — 5-digit ZCTA identifier (join key; matches ZIP5 directly)
- `INTPTLAT` — latitude of internal point
- `INTPTLONG` — longitude of internal point (note trailing G, not `INTPTLON`)

The join key for the ZIP5 path is `ZIP5 == GEOID`. The CONTEXT.md spec refers to the column as `INTPTLON` but the actual Census file uses `INTPTLONG`. The `zcta_gazetteer_centroids.csv` staged on HiPerGator may have been pre-renamed; the probe gate should check for both names and message if `INTPTLONG` (not `INTPTLON`) is found, to avoid a silent NA join.

### haversine_km() — Inline Implementation

Defined in SECTION 1B. No package dependency:

```r
haversine_km <- function(lat1, lon1, lat2, lon2) {
  # Vectorized; returns NA when any argument is NA
  R <- 6371  # WGS-84 mean radius, km
  to_rad <- function(x) x * pi / 180
  lat1r <- to_rad(lat1); lat2r <- to_rad(lat2)
  dlat  <- to_rad(lat2 - lat1)
  dlon  <- to_rad(lon2 - lon1)
  a  <- sin(dlat / 2)^2 + cos(lat1r) * cos(lat2r) * sin(dlon / 2)^2
  2 * R * asin(pmin(1, sqrt(a)))  # pmin guards against floating-point > 1
}
```

**Known-distance test:** Miami (25.7617° N, 80.1918° W) to Tampa (27.9506° N, 82.4572° W) ≈ 331 km great-circle (verified numerically 2026-09-15; an earlier draft of this document gave 279 km, which was an arithmetic error). The spec's ~330 km is correct. Use 331 ± 5 km as the test expectation. Miami → New York (40.7128° N, 74.0060° W) ≈ 1758 km is a second safe pair.

### ENCOUNTER Pull (mirrors R/116 SECTION 4)

```r
enc_tbl <- get_pcornet_table("ENCOUNTER") %>% dplyr::rename_with(toupper)

encounters_raw <- enc_tbl %>%
  dplyr::filter(ID %in% !!COHORT_IDS, !is.na(ADMIT_DATE)) %>%
  dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, enc_zip_raw = FACILITY_LOCATION) %>%
  dplyr::collect()
```

Note: R/116 uses `PATID = ID` rename; R/122 should keep `ID` to match the `get_zip9_at_date()` contract (which expects column named `ID`).

### Probe Gate Structure (mirrors R/115 SECTION 2)

Two sequential probe gates:
1. Check ZCTA gazetteer CSV at `CONFIG$reference_dir` (or `here::here("data","reference",...)`)
2. Check ZIP9 block-group centroid CSV at `CONFIG$zip9_bg_centroid_path` (or sibling path)
3. Check DuckDB ENCOUNTER table via `get_pcornet_table("ENCOUNTER")`

Each gate should: message the path being checked, message found/NOT FOUND, and `stop()` with an actionable message if a blocking dependency is absent (same pattern as R/115 lines 454–468). Gates do NOT fire when the script is sourced with no HiPerGator data — SECTION 1B functions are all pure and defined before any gate.

### distance_basis Assignment

```r
distance_basis = case_when(
  !is.na(enc_lat_zip9) & !is.na(res_lat_zip9) ~ "zip9-zip9",
  !is.na(enc_lat_zip9) & !is.na(res_lat_zip5) ~ "zip9-zip5",
  !is.na(enc_lat_zip5) & !is.na(res_lat_zip9) ~ "zip5-zip9",
  !is.na(enc_lat_zip5) & !is.na(res_lat_zip5) ~ "zip5-zip5",
  TRUE                                          ~ NA_character_
)
```

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Residence ZIP at encounter date | Custom temporal join | `get_zip9_at_date(ids, dates)` in utils_address.R | Already handles interval matching, most-recent-before fallback, fan-out prevention, open-ended periods |
| ZIP normalization | New string manipulation | `normalize_zip9()`, `normalize_zip5_raw()`, `normalize_zip5()` | Already tested, handles 4-digit left-pad question, sentinel rejection |
| Reference file memoization | New caching mechanism | `<<-` list cache keyed by (path, mtime, size) | Pattern established by `.centroid_zip9_lookup_cache` in utils_address.R; consistent with existing code |
| xlsx assembly | openxlsx or writexl | `openxlsx2` with `wb_add_worksheet` / `wb_add_data` | Already in use by R/115, R/116; renv already has it |
| Cohort IDs | Re-derive HL cohort | `get_hl_patient_ids()` from utils_treatment.R | Same pattern used by R/115 line 1089 |

---

## Common Pitfalls

### Pitfall 1: INTPTLONG vs INTPTLON Column Name

**What goes wrong:** The Census ZCTA Gazetteer file uses `INTPTLONG` (with trailing G), not `INTPTLON`. The CONTEXT.md spec abbreviates it as `INTPTLON`. A silent column mismatch produces all-NA lat/lon.

**How to avoid:** The probe gate or `get_zip_centroid()` should `stopifnot` or `stop()` if neither `INTPTLAT` nor `INTPTLONG` appear in the loaded file, with a message showing the actual column names.

### Pitfall 2: Fan-Out from get_zip9_at_date()

**What goes wrong:** `get_zip9_at_date()` returns ONE row per DISTINCT `(ID, query_date)` pair, not one row per input element. Callers MUST join on `c("ID", "query_date")`; do NOT cbind the result. Phase 145 documented this fan-out causing 1,950,696 → 2,210,904 rows in R/116.

**How to avoid:** After calling `get_zip9_at_date(encounters$ID, encounters$ADMIT_DATE)`, join the result back to the encounters frame: `encounters %>% left_join(res_zip, by = c("ID", "query_date" = "query_date"))`. Use `rename(query_date = ADMIT_DATE)` on encounters before the join or rename in the join.

### Pitfall 3: FACILITY_LOCATION Contains Non-ZIP Values

**What goes wrong:** `FACILITY_LOCATION` is free-text in PCORnet CDM. It may contain postal codes in varied formats, facility identifiers, or blank. `normalize_zip9()` and `normalize_zip5_raw()` will return NA for non-numeric values — this is correct behavior, not a bug. The QC waterfall should count how many FACILITY_LOCATION values yielded a normalized ZIP vs NA.

**How to avoid:** After normalization, log: `n_enc_with_norm_zip5`, `n_enc_with_norm_zip9`, `n_enc_zip_na`. Report these as the first QC waterfall rows.

### Pitfall 4: get_zip_centroid() Sourced Before Reference Files Exist (Test Context)

**What goes wrong:** If file-loading is inside `get_zip_centroid()` (not just in SECTION 2 gate), sourcing the script in a test environment (no HiPerGator data) will error on `vroom()`. SECTION 1B must be pure — no file I/O — so testthat can source the file.

**How to avoid:** Mirror the `approximate_zip9()` pattern: file-loading inside `get_zip_centroid()` is fine for lazy-load, but the function must return a typed-empty tibble (not error) when the reference file is absent. Add a file-existence check at the top of the function body.

### Pitfall 5: haversine_km with All-NA Input Row

**What goes wrong:** When encounter ZIP is unknown AND residence ZIP is unknown, both lat/lon are NA. Arithmetic on NA propagates NA through the haversine formula correctly — but only if `pmin(1, sqrt(a))` guards against NaN from sqrt(NA) → NaN → asin(NaN) → NaN (not NA). In R, `sqrt(NA_real_)` returns `NA_real_` (safe), but `sqrt(-0.0)` edge cases should be guarded.

**How to avoid:** The `pmin(1, sqrt(a))` guard and the NA propagation through `*` and `+` of doubles is sufficient in base R. Add a unit test with all-NA inputs confirming the return is `NA_real_` not `NaN`.

### Pitfall 6: Miami–Tampa Distance Test Value

**What goes wrong:** An earlier draft of this research claimed the great-circle Miami–Tampa distance was 279 km and that the spec's 330 km was a driving figure. That was wrong: the haversine distance for Miami (25.7617°N, 80.1918°W) to Tampa (27.9506°N, 82.4572°W) is ≈ 331 km. A test expecting 279 km will fail against a correct implementation.

**How to avoid:** Use 331 ± 5 km as the test expectation (matches the spec). Optionally add Miami → NYC ≈ 1758 ± 5 km as a second assertion.

### Pitfall 7: WV ZIP9 Coverage Gap in QC Sheet

**What goes wrong:** West Virginia ZIP9s are known to have lower coverage in the Neighborhood Atlas block-group crosswalk. Failing to note this on the QC sheet may lead the team to investigate a data problem that is a documented limitation.

**How to avoid:** The QC sheet must include a row explicitly noting: "WV ZIP9 centroid coverage may be lower; unmatched ZIP9 count by state in QC table flags this."

---

## Registration Pattern

### R/39_run_all_investigations.R

Current last entry in the investigation_scripts vector (line 223):
```r
"R/121_zip_problem_inventory.R"   # Per-patient ZIP problem flags (Phase 151)
```

Add immediately after, with trailing comma on the prior line:
```r
"R/122_encounter_distance.R"      # Encounter-ZIP to residence distance (Phase 152); haversine distance, outputs encounter_distance_YYYYMMDD.xlsx + .rds
```

### R/88_smoke_test_comprehensive.R

Current last section is `# Section 15ag: per-patient ZIP problem inventory (Phase 151)` ending around line 5258. Add:
```r
# Section 15ah: encounter-ZIP to residence distance (Phase 152) ----
```

Checks should mirror the Section 15af/15ag pattern: grep for SECTION 1B function definitions, assert output file naming convention, assert sheet names in workbook, assert probe gate presence.

### R/SCRIPT_INDEX.md

R/122 belongs in the **Investigations (100-122)** group (the index currently ends at R/121). Add a new row:
```
| 122_encounter_distance.R | Encounter-ZIP to residence haversine distance; get_zip_centroid() + haversine_km() helpers; encounter-level and patient-level summaries (Phase 152) | 00_config, utils/utils_address |
```

---

## Wave Structure Recommendation

This phase has clear serialization requirements (helpers must exist before the main script) and an internal parallelism opportunity (encounter-side and residence-side ZIP resolution are independent computations that can be planned together but executed after setup).

**Recommended 4-plan wave structure:**

| Plan | Content | Depends On |
|------|---------|-----------|
| 152-00-PLAN.md | `R/122a_build_zip9_centroid_crosswalk.R` + sbatch: derive `zip9_bg_centroid_crosswalk.csv` from the Neighborhood Atlas ZIP+4 files and block-group internal points on HiPerGator (blocking checkpoint) | Nothing (runs in parallel with 01) |
| 152-01-PLAN.md | SECTION 1B helpers in utils_address.R: `haversine_km()` + `get_zip_centroid()` (both functions, memoization caches, `.validate_zcta_centroid()` guard) + test file `test-122-distance.R` | Nothing |
| 152-02-PLAN.md | `R/122_encounter_distance.R` scaffold: SECTION 1 through SECTION 7 (encounter pull, residence resolution, centroid resolution, distance computation, distance_basis column) | Plan 01 (helpers must exist) |
| 152-03-PLAN.md | SECTION 8–12 (patient summary, distribution table, flags, QC waterfall, xlsx assembly + RDS write) + registration in R/39, R/88, R/SCRIPT_INDEX.md | Plan 02 |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| DuckDB ENCOUNTER table | Encounter pull (SECTION 3) | HiPerGator only | — | Probe gate stops with message |
| `data/reference/zcta_gazetteer_centroids.csv` | ZIP5 centroids | NOT YET STAGED | — | Probe gate stops with actionable message |
| `data/reference/zip9_bg_centroid_crosswalk.csv` | ZIP9 centroids | NOT YET BUILT — must be derived on HiPerGator from the 51 Neighborhood Atlas ZIP+4→block-group files under `/blue/erin.mobley.precision/` joined to block-group internal points (TIGER/NHGIS); see Plan 00 | — | Probe gate warns and degrades to all-ZIP5 (`zip5_fallback`) so a ZIP5-only run is possible before the crosswalk exists |
| `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` | `get_zip9_at_date()` | HiPerGator only | — | Existing probe in utils_address.R |
| openxlsx2 | xlsx output | In renv | project std | — |
| vroom | CSV loading | In renv | project std | read.csv fallback (existing pattern) |

**Missing dependencies with no fallback blocking a full run:**
- Both centroid reference files must be staged on HiPerGator before the script can compute any distances. The probe gate should stop with: `"Stage data/reference/zcta_gazetteer_centroids.csv from Census ZCTA Gazetteer Files (https://www.census.gov/geographies/reference-files/2020/geo/gazetter-file.html) before running."` and similarly for `zip9_bg_centroid_crosswalk.csv`.

**Local (Windows) structural verification:** SECTION 1B functions are pure; the test file can be run locally without HiPerGator data, covering haversine_km, get_zip_centroid fallback logic, and distance_basis assignment.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | testthat (project standard; used by all existing test-*.R files) |
| Config file | `tests/testthat.R` (existing) |
| Quick run command | `testthat::test_file("tests/testthat/test-122-distance.R")` |
| Full suite command | `testthat::test_dir("tests/testthat/")` |

### Phase Requirements → Test Map

| Behavior | Test Type | Automated Command | File Exists? |
|----------|-----------|-------------------|-------------|
| `haversine_km` correct for known city pair | unit | `test_file("tests/testthat/test-122-distance.R")` | ❌ Wave 0 (Plan 01) |
| `haversine_km` returns NA when any input NA | unit | same | ❌ Wave 0 |
| `get_zip_centroid` returns zip5_gazetteer source for ZIP5 with match | unit | same | ❌ Wave 0 |
| `get_zip_centroid` returns zip5_fallback when ZIP9 unmatched | unit | same | ❌ Wave 0 |
| distance_basis assigned correctly across 4 combinations | unit | same | ❌ Wave 0 |
| all-missing-ZIP encounter yields NA distance without error | unit | same | ❌ Wave 0 |

### Wave 0 Gaps

- [ ] `tests/testthat/test-122-distance.R` — all 6 test cases above; created in Plan 01

---

## Code Examples

### Memoized Reference File Load (adapting existing `.centroid_zip9_lookup_cache` pattern)

```r
# File-scope cache (defined before get_zip_centroid):
.zcta_gazetteer_cache <- list(key = NULL, value = NULL)

# Inside get_zip_centroid, ZIP5 path:
gaz_path  <- file.path(CONFIG$reference_dir %||% here::here("data","reference"),
                        "zcta_gazetteer_centroids.csv")
if (!file.exists(gaz_path)) {
  return(tibble(zip = zip, level = "zip5", lat = NA_real_, lon = NA_real_,
                centroid_source = "zip5_gazetteer_absent"))
}
cache_key <- paste0(normalizePath(gaz_path, mustWork = FALSE), "|",
                    as.numeric(file.mtime(gaz_path)), "|", file.size(gaz_path))
if (!is.null(.zcta_gazetteer_cache$key) &&
    identical(.zcta_gazetteer_cache$key, cache_key)) {
  gaz <- .zcta_gazetteer_cache$value
} else {
  gaz <- vroom::vroom(gaz_path,
                      col_types = vroom::cols(GEOID = "c", INTPTLAT = "d", INTPTLONG = "d"),
                      progress = FALSE, delim = "\t")
  .zcta_gazetteer_cache$key   <<- cache_key
  .zcta_gazetteer_cache$value <<- gaz
}
```

Note on delimiter: the raw Census Gazetteer download is tab-delimited, but the staged file is named `.csv` and may have been re-saved as comma-delimited. Do NOT hard-code `delim = "\t"`; let `vroom::vroom()` infer the delimiter (omit `delim`) and validate the resulting column names afterward (Pitfall 1).

### haversine_km Inline (SECTION 1B, pure):

```r
haversine_km <- function(lat1, lon1, lat2, lon2) {
  R     <- 6371
  d2r   <- pi / 180
  lat1r <- lat1 * d2r; lat2r <- lat2 * d2r
  dlat  <- (lat2 - lat1) * d2r
  dlon  <- (lon2 - lon1) * d2r
  a     <- sin(dlat / 2)^2 + cos(lat1r) * cos(lat2r) * sin(dlon / 2)^2
  2 * R * asin(pmin(1, sqrt(a)))
}
```

### Encounter Pull (R/122 adaptation of R/116 SECTION 4):

```r
COHORT_IDS <- get_hl_patient_ids()
enc_tbl    <- get_pcornet_table("ENCOUNTER") %>% dplyr::rename_with(toupper)

encounters_raw <- enc_tbl %>%
  dplyr::filter(ID %in% !!COHORT_IDS, !is.na(ADMIT_DATE)) %>%
  dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, enc_zip_raw = FACILITY_LOCATION) %>%
  dplyr::collect() %>%
  dplyr::mutate(ADMIT_DATE = parse_pcornet_date(ADMIT_DATE)) %>%
  dplyr::filter(!is.na(ADMIT_DATE))
```

---

## Open Questions

1. **INTPTLONG vs INTPTLON column name in the staged CSV**
   - What we know: The official Census Gazetteer uses `INTPTLONG`. The CONTEXT.md spec writes `INTPTLON`.
   - What's unclear: Whether the `zcta_gazetteer_centroids.csv` staged on HiPerGator has been pre-renamed.
   - Recommendation: Probe gate should check for both names; if `INTPTLONG` is found, use it and log a message. If neither is found, stop with the column list.

2. **zip9_bg_centroid_crosswalk.csv exact column names**
   - What we know: CONTEXT.md spec says columns are ZIP9, GEOID, INTPTLAT, INTPTLON.
   - What's unclear: Whether the staged HiPerGator file matches this exactly or uses different names.
   - Recommendation: Plan 02 probe gate should `stopifnot` with an informative message if the required columns are absent, following the `.validate_centroid_lookup()` pattern.

3. **Whether CONFIG has `zip9_bg_centroid_path` already set**
   - What we know: CONTEXT.md D-04 says to use `CONFIG$zip9_bg_centroid_path`. CONFIG is in R/00_config.R which was not read for this research.
   - What's unclear: Whether this key exists or must be added.
   - Recommendation: Plan 01 should check `R/00_config.R` for `zip9_bg_centroid_path`; if absent, add it with the expected default path.

---

## Sources

### Primary (HIGH confidence)

- `R/utils/utils_address.R` — direct inspection: memoization pattern, `.centroid_zip9_lookup_cache`, `get_zip9_at_date()` return contract, `normalize_zip9()`, `normalize_zip5()`, `normalize_zip5_raw()`
- `R/115_zip_stability_counts.R` — direct inspection: script section structure, probe gate pattern, dual-gate pattern, get_pcornet_table ENCOUNTER pull
- `R/116_encounter_ses_index.R` — direct inspection: SECTION 4 ENCOUNTER pull with `rename_with(toupper)`, probe_reference pattern, xlsx output pattern
- `R/01_load_pcornet.R` line 176 — FACILITY_LOCATION confirmed as character column in ENCOUNTER table
- `R/39_run_all_investigations.R` lines 220–224 — confirmed registration pattern and last entry (R/121)
- `R/88_smoke_test_comprehensive.R` — confirmed last section is 15ag (Phase 151); next is 15ah
- Census Bureau Gazetteer File Record Layouts (https://www.census.gov/programs-surveys/geography/technical-documentation/records-layout/gaz-record-layouts.html) — GEOID, INTPTLAT, INTPTLONG column names; tab-delimited format

### Secondary (MEDIUM confidence)

- geosphere CRAN package documentation (https://rdrr.io/cran/geosphere/man/distHaversine.html) — confirms `distHaversine` exists as an alternative; inline implementation preferred for this project

---

## Metadata

**Confidence breakdown:**
- ENCOUNTER ZIP column name: HIGH — directly observed in `R/01_load_pcornet.R`
- Census Gazetteer column names: HIGH — from official Census documentation
- Memoization cache pattern: HIGH — directly read from `utils_address.R`
- Script section structure: HIGH — directly read from `R/115_zip_stability_counts.R`
- ENCOUNTER pull pattern: HIGH — directly read from `R/116_encounter_ses_index.R`
- Registration pattern: HIGH — directly read from `R/39_run_all_investigations.R`
- haversine formula: HIGH — standard mathematical formula, no library uncertainty
- Miami–Tampa distance: HIGH — 331 km, verified numerically; the spec's 330 km is correct

**Research date:** 2026-09-15
**Valid until:** 2026-10-15 (stable codebase; centroid file column names should be verified on first HiPerGator probe run)
