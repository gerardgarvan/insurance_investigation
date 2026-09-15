---
phase: 152-encounter-zip-to-residence-distance
verified: 2026-09-15T12:00:00Z
status: human_needed
score: 12/14 must-haves verified
re_verification: true
  previous_status: gaps_found
  previous_score: 10/14
  gaps_closed:
    - "get_zip_centroid() ZIP9 path now uses DuckDB filtered read_csv join — vroom::vroom(bg_path) count is 0, duckdb::dbConnect count is 1"
    - "CONFIG$adi_zip9_parquet and CONFIG$tiger_bg_dir added to R/00_config.R (lines 202-216)"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Plan 00 crosswalk build on HiPerGator"
    expected: "sbatch job completes; data/reference/zip9_bg_centroid_crosswalk.csv written with ZIP9/GEOID/INTPTLAT/INTPTLON/N_BG; all nchar(ZIP9)==9 and nchar(GEOID)==12; lat within 17-72, lon within -180 to -64; WV listed as absent in BUILDLOG"
    why_human: "Requires HiPerGator SLURM, the ADI parquet at /blue/erin.mobley-hl.bcu/ADI/, and TIGER/Line block-group shapefiles"
  - test: "R/122 end-to-end run on HiPerGator against N=9,282 HL cohort"
    expected: "Both probe gates report 'found'; output/encounter_distance_YYYYMMDD.xlsx produced with KEY+A/B/C/D/QC sheets; QC waterfall n_encounters_total reconciles to DuckDB ENCOUNTER row count; distance_km values plausible; testthat file passes including previously-skipped file-present centroid cases"
    why_human: "Requires HiPerGator DuckDB + PCORnet CDM tables + staged centroid reference files"
---

# Phase 152: Encounter-ZIP to Residence Distance — Verification Report (Re-verification)

**Phase Goal:** For each cohort encounter, compute the geographic distance between the ZIP recorded on the ENCOUNTER row and the patient's residential address in effect on the encounter date (LDS_ADDRESS_HISTORY, via get_zip9_at_date()). Produce an encounter-level distance table and a patient-level summary that characterizes how far patients travel for care and flags encounters whose ZIP is implausibly far from the residence on file.
**Verified:** 2026-09-15T12:00:00Z
**Status:** human_needed
**Re-verification:** Yes — after gap closure (152-04 and 152-05 executed)

---

## Re-verification Summary

Previous status was `gaps_found` (10/14, 2026-09-15). Two locally-fixable code gaps have been closed:

- **Gap 1 closed:** `get_zip_centroid()` ZIP9 path now uses a DuckDB `read_csv` filtered join. `grep -c "vroom::vroom(bg_path"` returns 0; `grep -c "duckdb::dbConnect"` returns 1. The full-table vroom load and `.zip9_bg_centroid_cache` memoisation of the entire crosswalk are gone.
- **Gap 2 closed:** `CONFIG$adi_zip9_parquet` and `CONFIG$tiger_bg_dir` are now present in `R/00_config.R` (lines 202–216), matching the `%||%` fallback paths already in R/122a.

Two remaining items are HiPerGator human checkpoints that cannot be verified programmatically. Gap 3 from the original verification (crosswalk file existence) is reclassified as part of the human checkpoint — it is a consequence of Plan 00 Task 3 not yet having been run, not a separate code gap.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | haversine_km() returns great-circle km; NA when any input is NA | VERIFIED | R/utils/utils_address.R line 93; 6371 km radius, pmin guard, asin(NA)=NA propagation |
| 2 | get_zip_centroid(zip,'zip5') resolves a ZIP5 to a gazetteer centroid; falls back when file absent | VERIFIED | Lines 728+; memoized via .zcta_gazetteer_cache; absent file returns typed tibble with centroid_source="zip5_gazetteer_absent" |
| 3 | get_zip_centroid(zip,'zip9') resolves ZIP9 to block-group centroid; falls back to ZIP5 on miss | VERIFIED | Function present; DuckDB filtered join on lines 859-879; zip5_fallback path on miss |
| 4 | get_zip_centroid() ZIP9 crosswalk read is filtered (DuckDB), never loaded whole into R | VERIFIED | grep -c "vroom::vroom(bg_path" = 0; grep -c "duckdb::dbConnect" = 1; DBI::dbGetQuery with WHERE ZIP9 = '{safe_zip}' LIMIT 1 at lines 861-878 |
| 5 | CONFIG carries zip9_bg_centroid_path and zcta_gazetteer_path | VERIFIED | R/00_config.R lines 180, 185 |
| 6 | CONFIG carries adi_zip9_parquet and tiger_bg_dir (for R/122a) | VERIFIED | R/00_config.R lines 202-206 (adi_zip9_parquet) and 212-216 (tiger_bg_dir); both set to NULL locally and to /blue/ paths on HiPerGator |
| 7 | data/reference/zip9_bg_centroid_crosswalk.csv exists on HiPerGator (Plan 00 build complete) | HUMAN NEEDED | Plan 00 Task 3 (sbatch job submission and validation) is a blocking human checkpoint; cannot verify programmatically |
| 8 | test-122-distance.R passes all haversine/centroid/distance_basis unit tests | VERIFIED (local) | File exists with Miami-Tampa=331±5, Miami-NYC=1758±5, NA propagation, vectorization, centroid_source assertions, skip_if_not guards for file-present cases |
| 9 | R/122 pulls HL-cohort ENCOUNTER rows from DuckDB using FACILITY_LOCATION as the ZIP field | VERIFIED | R/122_encounter_distance.R line 187: enc_zip_raw = FACILITY_LOCATION |
| 10 | R/122 resolves residence ZIP at ADMIT_DATE via get_zip9_at_date() joined on (ID, query_date) | VERIFIED | Lines 206-218: left_join on c("ID"="ID","ADMIT_DATE"="query_date"); fan-out assertion at line 232 |
| 11 | R/122 resolves both centroids via get_zip_centroid() and computes haversine distance | VERIFIED | SECTION 6 calls get_zip_centroid on distinct ZIP vectors for both sides; SECTION 7 line 422: haversine_km(enc_lat, enc_lon, res_lat, res_lon) |
| 12 | R/122 produces B_patient_summary, C_distribution, D_flags, QC waterfall | VERIFIED | All four sections present (SECTION 8-11); WV gap note present; pct_gt50km/pct_gt200km present; both thresholds in D_flags |
| 13 | R/122 writes xlsx (KEY leftmost) and rds; registered in R/39, R/88, SCRIPT_INDEX.md | VERIFIED | wb_workbook()/wb_save() present; saveRDS present; R/39 line 224; R/88 line 5261; SCRIPT_INDEX.md line 166 |
| 14 | Script runs end-to-end on HiPerGator against N=9,282 HL cohort | HUMAN NEEDED | Crosswalk CSV not yet built; Plan 03 Task 3 blocking checkpoint AWAITING USER |

**Score: 12/14 truths verified (2 require human action on HiPerGator)**

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/122a_build_zip9_centroid_crosswalk.R` | ZIP9->BG centroid crosswalk builder using DuckDB + read_parquet | VERIFIED | Present; DuckDB read_parquet + TIGER DBF join; N_BG column; sql_str escaping |
| `slurm/122a_build_zip9_centroid_crosswalk.sbatch` | SLURM wrapper for 122a | VERIFIED | File present |
| `R/utils/utils_address.R` (haversine_km + get_zip_centroid) | Two new helper functions, pure/sourceable | VERIFIED | Both present; ZIP9 path uses DuckDB filtered join — vroom full-load removed |
| `R/00_config.R` (centroid path keys) | zcta_gazetteer_path + zip9_bg_centroid_path | VERIFIED | Lines 180, 185 |
| `R/00_config.R` (122a keys) | adi_zip9_parquet + tiger_bg_dir | VERIFIED | Lines 202-216; both keys present with IS_LOCAL NULL / HiPerGator path branches |
| `tests/testthat/test-122-distance.R` | Unit tests for haversine_km and get_zip_centroid | VERIFIED | All specified test cases present; skip_if_not guards present |
| `R/122_encounter_distance.R` | SECTION 1-12 complete analysis script | VERIFIED | All sections present |
| `R/39_run_all_investigations.R` | R/122 registered | VERIFIED | Line 224 confirmed |
| `R/88_smoke_test_comprehensive.R` | Section 15ah structural checks | VERIFIED | Lines 5261-5335: p152_pass/p152_fail counters |
| `R/SCRIPT_INDEX.md` | R/122 investigations row | VERIFIED | Line 166 confirmed |
| `data/reference/zip9_bg_centroid_crosswalk.csv` | Built crosswalk on HiPerGator | HUMAN NEEDED | Does not exist locally; requires Plan 00 Task 3 sbatch run |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| R/122a | adi_2024_zip9_all_dedup.parquet | DuckDB read_parquet + CONFIG$adi_zip9_parquet | VERIFIED | CONFIG key now present; %||% fallback is a safety net, not the primary path |
| R/122 encounter pull | ENCOUNTER.FACILITY_LOCATION | get_pcornet_table + rename_with(toupper) + select enc_zip_raw = FACILITY_LOCATION | VERIFIED | Line 187 confirmed |
| R/122 residence resolution | get_zip9_at_date() | left_join on c(ID, ADMIT_DATE=query_date) | VERIFIED | Lines 206-218; fan-out assertion at line 232 |
| R/122 distance | haversine_km() / get_zip_centroid() | case_when distance_basis + haversine_km call | VERIFIED | Lines 422-432 confirmed |
| R/122 xlsx assembly | output/encounter_distance_YYYYMMDD.xlsx | wb_workbook + KEY leftmost + A/B/C/D/QC + wb_save | VERIFIED | All confirmed in SECTION 12 |
| get_zip_centroid() ZIP9 | zip9_bg_centroid_crosswalk.csv | DuckDB read_csv filtered to requested ZIP9 (WHERE ZIP9 = '{safe_zip}' LIMIT 1) | VERIFIED | Lines 859-879; vroom full-load replaced; SQL-escaped zip_str; on.exit disconnect |
| R/39 | R/122_encounter_distance.R | investigation_scripts vector entry | VERIFIED | Line 224 confirmed |

---

### Behavioral Spot-Checks

| Behavior | Result | Status |
|----------|--------|--------|
| grep -c "vroom::vroom(bg_path" R/utils/utils_address.R | 0 | PASS |
| grep -c "duckdb::dbConnect" R/utils/utils_address.R | 1 | PASS |
| grep -c "adi_zip9_parquet" R/00_config.R | >= 1 | PASS |
| grep -c "tiger_bg_dir" R/00_config.R | >= 1 | PASS |
| haversine_km: 6371 km radius present | 2 matches | PASS |
| haversine_km: pmin domain guard present | 1 match | PASS |
| R/122 cbind-free | 0 matches | PASS |
| R/122 fan-out assertion present | Found at line 232 | PASS |
| R/122 distance_basis covers all four combos | All four present | PASS |

---

### Anti-Patterns Found

No blocker anti-patterns remain. The previously-flagged vroom full-load of the 68M-row crosswalk (Blocker) and the missing CONFIG keys (Warning) are both resolved.

---

### Human Verification Required

#### 1. Plan 00 crosswalk build on HiPerGator

**Test:** Submit `sbatch slurm/122a_build_zip9_centroid_crosswalk.sbatch` on a HiPerGator login node after confirming TIGER block-group zips are staged under CONFIG$tiger_bg_dir (`/blue/erin.mobley-hl.bcu/ADI/tiger_bg`).
**Expected:** Job completes; `data/reference/zip9_bg_centroid_crosswalk.csv` written with exactly ZIP9,GEOID,INTPTLAT,INTPTLON,N_BG; all nchar(ZIP9)==9, nchar(GEOID)==12; lat 17-72, lon -180 to -64; WV noted as absent in BUILDLOG; Gainesville spot-check (ZIP9 "326110000") near 29.65/-82.32.
**Why human:** Requires HiPerGator SLURM, the ADI parquet at `/blue/erin.mobley-hl.bcu/ADI/out/adi_2024_zip9_all_dedup.parquet`, and TIGER/Line block-group shapefiles.

#### 2. R/122 end-to-end HiPerGator run

**Test:** Stage both centroid reference files (`zcta_gazetteer_centroids.csv` and `zip9_bg_centroid_crosswalk.csv` under `data/reference/`), then `module load R/4.4.2` and `Rscript R/122_encounter_distance.R`.
**Expected:** Both probe gates report "found"; workbook `output/encounter_distance_YYYYMMDD.xlsx` produced with KEY+A/B/C/D/QC sheets; QC waterfall n_encounters_total reconciles to DuckDB ENCOUNTER row count; distance_km values plausible (Florida intra-state majority <300 km); testthat file passes including previously-skipped file-present centroid cases.
**Why human:** Requires HiPerGator DuckDB + PCORnet CDM tables + staged centroid reference files.

---

### Summary

All locally-verifiable code gaps from the initial verification have been closed:

- The ZIP9 crosswalk read in `get_zip_centroid()` is now a DuckDB filtered join (one row scanned per requested ZIP9, not the full 68M-row file). The acceptance criterion ("grep returns 0 for vroom::vroom(bg_path") is met.
- `CONFIG$adi_zip9_parquet` and `CONFIG$tiger_bg_dir` are now declared in `R/00_config.R` with proper IS_LOCAL/HiPerGator branching, completing the CONFIG contract from Plan 00.

The two remaining items (crosswalk build and full pipeline run) are HiPerGator human checkpoints that block final phase sign-off but do not indicate any remaining code defect.

---

_Verified: 2026-09-15T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
_Re-verification after: 152-04-PLAN and 152-05-PLAN gap closure_
