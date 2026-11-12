# 197-UCI-DISTANCE — UCI Facility ZIP Investigation

Generated 2026-11-12. Read-only analysis (no R/183 changes made).

## Patients affected

| Group | n | Current handling |
|---|---|---|
| UCI main_source | 211 | 100% missing dist_to_source_facility_mi; MICE imputes |
| NA main_source | 48 | 100% missing; MICE imputes |
| **Total imputed** | **259** | — |

Complete-case analysis (OR 0.834) already excludes all 259. MICE analysis (OR 0.846)
imputes them. The two estimates agree (95% CIs overlap), so the current imputation
strategy is acceptable pending data confirmation.

## Why NA main_source?

`main_source` is assigned in R/183 (line 279–282) as the modal SOURCE among
post-anchor encounters per patient:

```r
main_source = { tbl <- sort(table(SOURCE), decreasing = TRUE); names(tbl)[1] }
```

`table()` excludes NAs by default, so patients whose post-anchor encounters ALL have
`SOURCE = NA` get `main_source = NA` (empty table → `names(tbl)[1]` = NA). This is a
data-quality gap (blank SOURCE in ENCOUNTER), not a pipeline bug.

## Root cause for UCI: (a) no FACILITY_LOCATION data

R/183 builds facility ZIPs at lines 294–301:

```r
src_fac_zip <- enc |>
  dplyr::filter(distance_status == "computed",
                !is.na(zip5_facility)) |>
  dplyr::count(SOURCE, zip5_facility) |>
  dplyr::group_by(SOURCE) |>
  dplyr::slice_max(n, n = 1L, with_ties = FALSE) |>
  dplyr::ungroup()
```

For UCI to be absent from `src_fac_zip` (R/183 log: "14 SOURCEs with modal facility
ZIP"), at least one of the two filter conditions must exclude all UCI rows:

- `distance_status == "computed"`: requires that the encounter had a valid patient
  ZIP AND a valid facility ZIP at the time R/122 ran.
- `!is.na(zip5_facility)`: requires that FACILITY_LOCATION was non-blank and a valid
  US ZIP5 after normalization.

Since UCI has 100% missing `dist_to_source_facility_mi` (all 211 patients), no UCI
encounter passed through the facility-ZIP path in R/122. The most likely root cause is
**(a): UCI ENCOUNTER rows have blank or null FACILITY_LOCATION** in the PCORnet CDM
extract. With `enc_zip_raw = NA`, `normalize_zip5_raw()` returns NA → `distance_status`
is not "computed" → UCI encounters are filtered out of both conditions above → no entry
in `src_fac_zip` → all 211 UCI patients get NA distance.

Possible alternative: UCI has FACILITY_LOCATION values that are present but fail
normalization (all-alpha, placeholder, PO Box, etc.). The DuckDB query below
distinguishes (a) from this alternative.

### DuckDB query to confirm (run on HiPerGator)

```r
module load R/4.5; R --no-save

con <- DBI::dbConnect(duckdb::duckdb(), dbdir = CONFIG$duckdb_path, read_only = TRUE)

# 1. Columns in ENCOUNTER matching FACILITY or ZIP
DBI::dbGetQuery(con, "
  SELECT column_name
  FROM information_schema.columns
  WHERE table_name = 'ENCOUNTER'
    AND (UPPER(column_name) LIKE '%FACILITY%'
      OR UPPER(column_name) LIKE '%ZIP%')
  ORDER BY column_name
")

# 2. Per-SOURCE: n encounters, n NULL FACILITY_LOCATION, n distinct FACILITY_LOCATION
DBI::dbGetQuery(con, "
  SELECT
    SOURCE,
    COUNT(*) AS n_enc,
    SUM(CASE WHEN FACILITY_LOCATION IS NULL OR TRIM(FACILITY_LOCATION) = '' THEN 1 ELSE 0 END) AS n_null_facility,
    COUNT(DISTINCT FACILITY_LOCATION) AS n_distinct_facility
  FROM ENCOUNTER
  GROUP BY SOURCE
  ORDER BY n_enc DESC
")

DBI::dbDisconnect(con)
```

**Paste back:** the two result tables. Expected: UCI row has n_null_facility ≈ n_enc
(confirming root cause a).

## Why ORL has 25.4% missing (127/500)

ORL appears in the 14 SOURCEs with a modal facility ZIP, so the ORL facility centroid
is computed. The 127 missing distances for ORL patients come from the patient side:
those patients have no valid `pat_zip5` (modal patient address ZIP across post-anchor
encounters is NA), so `haversine_km()` cannot be called. This is a data-quality gap in
LDS_ADDRESS_HISTORY for those 127 ORL patients, not a facility-ZIP issue.

Verification query:

```r
# After loading mice_input (R/183 pat_mice object or mice_input RDS):
mice_input |>
  filter(main_source == "ORL") |>
  summarise(n = n(), n_miss_pat_zip = sum(is.na(pat_zip5)),
            n_miss_dist = sum(is.na(dist_to_source_facility_mi)))
```

Expected: n_miss_pat_zip ≈ n_miss_dist ≈ 127.

## Proposal: source_facility_zip_override.csv

If Amy/Erin can confirm an institutional ZIP for UCI (and any other source with blank
FACILITY_LOCATION), create:

```
data/reference/source_facility_zip_override.csv
```

Columns: `SOURCE`, `ZIP5`, `notes`

```csv
SOURCE,ZIP5,notes
UCI,,needs confirmation from Amy/Erin — UCI institutional ZIP unknown
```

R/183 would read this file at the start of section 2e, coalesce it into `src_fac_zip`
after the encounter-based modal computation:

```r
zip_override <- read.csv("data/reference/source_facility_zip_override.csv",
                          stringsAsFactors = FALSE) |>
  dplyr::filter(!is.na(ZIP5) & nzchar(ZIP5))
src_fac_zip <- dplyr::bind_rows(
  src_fac_zip,
  zip_override |> dplyr::anti_join(src_fac_zip, by = "SOURCE") |>
    dplyr::transmute(SOURCE, zip5_facility = ZIP5)
)
```

**Do NOT implement until Amy/Erin confirm the UCI ZIP.** Leave UCI row blank in the CSV.
The override file should be committed even if UCI is blank, so Amy/Erin can fill it in.

## Decisions pending

| ID | Question | Who | Default if no answer |
|---|---|---|---|
| D-197-10 | What is UCI's institutional/campus ZIP5 for distance imputation? | Amy/Erin | Keep UCI distance as NA (imputed by MICE) |
| D-197-11 | Should we implement the override file for future SOURCEs? | Gerard | Implement when D-197-10 is resolved |

## Impact on current results

MICE imputes `dist_to_source_facility_mi` for all 259 patients (211 UCI + 48 NA source)
using the other covariates (age, sex, ADI, payer, etc.). The pooled OR from d01 (primary
model, complete-case excluded) is 0.846 [0.727–0.986], virtually identical to the
complete-case estimate of 0.834. The 259 imputed patients do not materially change the
estimate, so the current approach is defensible pending data confirmation.
