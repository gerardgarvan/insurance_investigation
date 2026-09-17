---
phase: quick-260917-lvy
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - R/utils/utils_zip_calendar.R
  - R/122_encounter_distance.R
autonomous: true
requirements: [DIST-02, DIST-03]
must_haves:
  truths:
    - "Both files parse without error (Rscript parse check exits 0)"
    - "utils_zip_calendar.R: lag() default no longer passes -Inf (type-safe new_run logic)"
    - "utils_zip_calendar.R: address dates use parse_pcornet_date(), not as.Date()"
    - "utils_zip_calendar.R: zip5 prefers ZIP9 prefix; disagreements are messaged and zip5_col is dropped"
    - "utils_zip_calendar.R: bad periods (NA start, reversed) are dropped with counts"
    - "utils_zip_calendar.R: compute_encounter_distance() output has no ADMIT_DATE column"
    - "utils_zip_calendar.R: zip_distance() alignment is asserted before use"
    - "utils_zip_calendar.R: ID coerced to character at every calendar boundary"
    - "utils_zip_calendar.R: D-04/D-05 labels corrected to D-07/D-03; D-02 corrected to D-04"
    - "R/122_encounter_distance.R: ID coerced to character before calendar path; filter uses as.character"
    - "R/122_encounter_distance.R: join-key uniqueness asserted; ADMIT_DATE absence in dist_result asserted"
    - "R/122_encounter_distance.R: six stopifnot guards on get_zip_centroid() row counts"
    - "R/122_encounter_distance.R: distance_km_haversine retained in enc_distance select()"
    - "R/122_encounter_distance.R: unmatched_zip9 zip3 derived correctly from centroid_source"
    - "R/122_encounter_distance.R: glue objects in qc_tbl coerced to character"
    - "R/122_encounter_distance.R: %||% replaced with portable if/is.null pattern"
    - "R/122_encounter_distance.R: stale text and decision labels updated (B8 items)"
    - "R/122_encounter_distance.R: Section 4 comment updated (B9)"
  artifacts:
    - path: R/utils/utils_zip_calendar.R
      provides: "Patient ZIP calendar helpers with all A-series fixes applied"
    - path: R/122_encounter_distance.R
      provides: "Encounter distance script with all B-series fixes applied"
  key_links:
    - from: R/122_encounter_distance.R
      to: R/utils/utils_zip_calendar.R
      via: "source() call; compute_encounter_distance() used in SECTION 4"
---

<objective>
Apply every edit described in FIX_122_and_zip_calendar.md (items A1–A8 in utils_zip_calendar.R,
items B1–B9 in R/122_encounter_distance.R) exactly as specified.

Purpose: Harden the Phase 153 encounter-distance pipeline against runtime type errors,
wrong date parsers, silent ZIP5 disagreements, unbounded period rows, unsafe join patterns,
misaligned centroid vectors, and stale decision labels.

Output: Two edited R files that parse cleanly and satisfy the C-Verification block.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
</execution_context>

<context>
@.planning/PROJECT.md
@FIX_122_and_zip_calendar.md
@R/utils/utils_zip_calendar.R
@R/122_encounter_distance.R
</context>

<tasks>

<task type="auto">
  <name>Task 1: Apply A-series fixes to R/utils/utils_zip_calendar.R (A1–A8)</name>
  <files>R/utils/utils_zip_calendar.R</files>
  <action>
Apply the following eight edits IN ORDER to R/utils/utils_zip_calendar.R. Do not refactor,
reorder sections, or change any behavior beyond what each item states.

**A1 — Fix lag() default type error (lines 109–112)**
Replace:
```r
    mutate(
      new_run = start > lag(cummax(as.integer(end)), default = -Inf) + 1,
      run     = cumsum(new_run)
    ) |>
```
with:
```r
    mutate(
      prev_max_end = lag(cummax(as.integer(end))),
      new_run      = is.na(prev_max_end) | as.integer(start) > prev_max_end + 1L,
      run          = cumsum(new_run)
    ) |>
```

**A2 — Use parse_pcornet_date() for address dates (lines 90–91)**
Replace:
```r
      start = as.Date(ADDRESS_PERIOD_START),
      end   = coalesce(as.Date(ADDRESS_PERIOD_END), study_end)
```
with:
```r
      start = parse_pcornet_date(ADDRESS_PERIOD_START),
      end   = coalesce(parse_pcornet_date(ADDRESS_PERIOD_END), study_end)
```
Also add `parse_pcornet_date()` to the Dependencies comment block (the block at lines 55–57).
If parse_pcornet_date() is not defined in a file auto-sourced by R/00_config.R, STOP and
report which file defines it; do not reimplement it here.

**A3 — Prefer ZIP9 prefix for zip5; add helper and pipe steps (line 89 + new helpers)**
Replace line 89:
```r
      zip5  = coalesce(normalize_zip5(ADDRESS_ZIP5), substr(zip9, 1, 5)),
```
with:
```r
      zip5_col = normalize_zip5(ADDRESS_ZIP5),
      zip5     = if_else(!is.na(zip9), substr(zip9, 1, 5), zip5_col),
```

Above `build_patient_zip_calendar()`, define:
```r
.report_zip5_disagreement <- function(d) {
  n_disagree <- sum(!is.na(d$zip9) & !is.na(d$zip5_col) &
                    substr(d$zip9, 1, 5) != d$zip5_col)
  if (n_disagree > 0) {
    message(sprintf("  [zip_calendar] %d rows where ADDRESS_ZIP5 != first 5 of ADDRESS_ZIP9; ZIP9 prefix used",
                    n_disagree))
  }
  d
}
```

Immediately after the transmute() closes (after current line 92, i.e. after the `end = ...` line),
insert these two pipe steps before the first `filter(!is.na(zip5))`:
```r
    .report_zip5_disagreement() |>
    select(-zip5_col) |>
```

**A4 — Drop bad periods with counts (after line 98's sentinel filter)**
Immediately after the `filter(!is_sentinel_zip5(zip5)) |>` line, insert:
```r
    .drop_bad_periods() |>
```

Above `build_patient_zip_calendar()`, define:
```r
.drop_bad_periods <- function(d) {
  n_na_start <- sum(is.na(d$start))
  n_reversed <- sum(!is.na(d$start) & d$start > d$end)
  if (n_na_start > 0) message(sprintf("  [zip_calendar] dropping %d rows with NA ADDRESS_PERIOD_START", n_na_start))
  if (n_reversed > 0) message(sprintf("  [zip_calendar] dropping %d rows with start > end", n_reversed))
  d |> filter(!is.na(start), start <= end)
}
```

**A5 — Do not return ADMIT_DATE from compute_encounter_distance() (lines 221–223 + roxygen)**
Replace:
```r
  out <- enc |>
    select(ID, ENCOUNTERID, zip5_facility) |>
    left_join(best, by = c("ID", "ENCOUNTERID"))
```
with:
```r
  out <- enc |>
    select(ID, ENCOUNTERID, zip5_facility) |>
    left_join(best |> select(-ADMIT_DATE), by = c("ID", "ENCOUNTERID"))
```

In the roxygen `@return` block (lines 199–202) and the header Outputs block (lines 47–48),
remove `ADMIT_DATE` from the compute_encounter_distance() output column list.
Do NOT change pick_best_zip()'s output description.

**A6 — Assert zip_distance() alignment (lines 232–234)**
Replace:
```r
  pairs$distance_mi <- zip_distance(
    pairs$zip5_patient, pairs$zip5_facility, units = "miles"
  )$distance
```
with:
```r
  zd <- zip_distance(pairs$zip5_patient, pairs$zip5_facility, units = "miles")
  stopifnot(
    "zip_distance() returned a different number of rows than input pairs" =
      nrow(zd) == nrow(pairs),
    "zip_distance() output order does not match input pairs" =
      identical(as.character(zd$zipcode_a), pairs$zip5_patient)
  )
  pairs$distance_mi <- zd$distance
```

**A7 — Coerce ID to character at every calendar boundary**
1. At the start of `build_patient_zip_calendar()`, before the `transmute`, change `addr |>` to:
```r
  addr |>
    mutate(ID = as.character(ID)) |>
```

2. At the start of `pick_best_zip()`, replace:
```r
  enc |>
    mutate(ADMIT_DATE = as.Date(ADMIT_DATE)) |>
```
with:
```r
  enc |>
    mutate(ID = as.character(ID), ADMIT_DATE = as.Date(ADMIT_DATE)) |>
```

3. At the start of `compute_encounter_distance()`, insert as the first statement:
```r
  enc <- enc |> mutate(ID = as.character(ID))
```

**A8 — Relabel decision references in comments only (no code change)**
- In lines 13–14, 123, 127, 132–133, 146, 160, 165: replace every "D-04" with "D-07"
  and every "D-05" with "D-03". Verify these are comment-only occurrences.
- In lines 196 and 207: replace "(D-02)" with "(D-04)" in those two lines only
  (these describe facility-ZIP-never-imputed).
  </action>
  <verify>
    <automated>cd "C:/Users/Owner/Documents/insurance_investigation" && Rscript -e 'invisible(parse("R/utils/utils_zip_calendar.R")); cat("parse OK\n")'</automated>
  </verify>
  <done>
- File parses without error.
- All eight A-items are applied as specified.
- .report_zip5_disagreement() and .drop_bad_periods() helpers exist above build_patient_zip_calendar().
- compute_encounter_distance() drops ADMIT_DATE from the best join.
- zip_distance() result is validated with stopifnot before use.
- ID coerced to character in all three functions.
- Decision label comments updated (D-04→D-07, D-05→D-03, D-02→D-04 on lines 196/207).
  </done>
</task>

<task type="auto">
  <name>Task 2: Apply B-series fixes to R/122_encounter_distance.R (B1–B9)</name>
  <files>R/122_encounter_distance.R</files>
  <action>
Apply the following nine edits IN ORDER to R/122_encounter_distance.R. Do not refactor,
reorder sections, or change behavior beyond what each item states.

**B1 — Coerce ID before the calendar path (lines 252–253 + line 240)**
Replace lines 252–253:
```r
enc_for_dist <- encounters_raw %>%
  dplyr::mutate(zip5_facility = normalize_zip5_raw(enc_zip_raw))
```
with:
```r
encounters_raw <- encounters_raw %>%
  dplyr::mutate(ID = as.character(ID))
COHORT_IDS <- as.character(COHORT_IDS)

enc_for_dist <- encounters_raw %>%
  dplyr::mutate(zip5_facility = normalize_zip5_raw(enc_zip_raw))
```

Also change line 240 from:
```r
  dplyr::filter(ID %in% COHORT_IDS)
```
to:
```r
  dplyr::filter(as.character(ID) %in% as.character(COHORT_IDS))
```
Do NOT change line 203 or 212 (DuckDB side).

**B2 — Assert join-key uniqueness and ADMIT_DATE absence (lines 277–281)**
Replace:
```r
encounters <- encounters_raw %>%
  dplyr::left_join(
    dist_result,
    by = c("ID", "ENCOUNTERID")
  )
```
with:
```r
stopifnot(
  "encounters_raw has duplicate (ID, ENCOUNTERID)" =
    !anyDuplicated(encounters_raw[c("ID", "ENCOUNTERID")]),
  "dist_result has duplicate (ID, ENCOUNTERID)" =
    !anyDuplicated(dist_result[c("ID", "ENCOUNTERID")]),
  "dist_result still carries ADMIT_DATE -- apply utils_zip_calendar.R fix A5" =
    !"ADMIT_DATE" %in% names(dist_result)
)
encounters <- encounters_raw %>%
  dplyr::left_join(dist_result, by = c("ID", "ENCOUNTERID"))
```

**B3 — Guard positional centroid assignments with six stopifnot calls**
After line 345 (end of `enc_zip9_lookup` assignment), insert:
```r
  stopifnot("get_zip_centroid(zip9) row count != input length (enc side)" =
              nrow(enc_zip9_lookup) == sum(enc_has_zip9))
```
After line 354 (end of `enc_zip5_lookup` assignment), insert:
```r
  stopifnot("get_zip_centroid(zip5) row count != input length (enc side)" =
              nrow(enc_zip5_lookup) == sum(enc_has_zip5_only))
```
After line 381 (end of `res_zip9_lookup` assignment), insert:
```r
  stopifnot("get_zip_centroid(zip9) row count != input length (res side)" =
              nrow(res_zip9_lookup) == sum(res_has_zip9))
```
After line 389 (end of `res_zip5_lookup` assignment), insert:
```r
  stopifnot("get_zip_centroid(zip5) row count != input length (res side)" =
              nrow(res_zip5_lookup) == sum(res_has_zip5_only))
```
After line 419 (end of `enc_zip5_lookup` assignment in the ZIP5-only else branch), insert:
```r
  stopifnot("get_zip_centroid(zip5) row count != input length (enc side, ZIP5-only path)" =
              nrow(enc_zip5_lookup) == sum(enc_has_zip5))
```
After line 427 (end of `res_zip5_lookup` assignment in the ZIP5-only else branch), insert:
```r
  stopifnot("get_zip_centroid(zip5) row count != input length (res side, ZIP5-only path)" =
              nrow(res_zip5_lookup) == sum(res_has_zip5))
```
NOTE: line numbers shift after each insertion; locate insertions by the content of the
surrounding assignments, not by absolute line number.

**B4 — Retain distance_km_haversine in enc_distance select() (lines 508–525)**
In the `dplyr::select()` that builds `enc_distance`, insert `distance_km_haversine,`
immediately after `distance_km,`. Also add `distance_km_haversine` to the KEY sheet's
`A_encounter_distance columns` string (line 1012 area) immediately after `distance_km`.

**B5 — Fix unmatched-ZIP9 state attribution (lines 764–766)**
Replace:
```r
  dplyr::mutate(
    zip3 = substr(coalesce(enc_zip_norm, zip9_patient, zip5_patient), 1, 3)
  )
```
with:
```r
  dplyr::mutate(
    unmatched_zip = dplyr::case_when(
      enc_centroid_source == "zip5_fallback" ~ enc_zip_norm,
      res_centroid_source == "zip5_fallback" ~ dplyr::coalesce(zip9_patient, zip5_patient),
      TRUE                                   ~ NA_character_
    ),
    zip3 = substr(unmatched_zip, 1, 3)
  )
```

**B6 — Coerce glue objects in qc_tbl**
- Line 855: change `Note   = nearest_offset_summary` to `Note   = as.character(nearest_offset_summary)`.
- Line 860 (the tibble row with `glue::glue(...)`): wrap the entire `glue::glue(...)` call in `as.character(...)`.

**B7 — Replace %||% for portability (lines 949–950)**
Replace:
```r
  wb$set_col_widths(sheet = sheet_name, cols = 1:max(n_cols, ncol(extra_tbl %||% data_tbl)),
                    widths = "auto")
```
with:
```r
  width_tbl <- if (is.null(extra_tbl)) data_tbl else extra_tbl
  wb$set_col_widths(sheet = sheet_name, cols = seq_len(max(n_cols, ncol(width_tbl))),
                    widths = "auto")
```

**B8 — Stale text and labels (no logic change)**
Apply each replacement exactly. Locate lines by their current string content:

1. Line 891: change `"6 sheets"` to `"7 sheets"`.
2. Line 998: replace `"HL cohort (N = 9,282), IDs from DuckDB via CONFIG"` with
   `glue("HL cohort (N = {length(COHORT_IDS)}), IDs from DuckDB via CONFIG")`.
3. Line 1027 (subtitle of KEY sheet): replace `Cohort: HL (N=9,282)` with
   `Cohort: HL (N={length(COHORT_IDS)})` inside the existing glue string.
4. Line 1042 (subtitle of B_patient_summary sheet): replace
   `"One row per patient; fallback (most_recent_before) encounters included per D-02."` with
   `"One row per patient; nearest-fill (nearest_zip9 / nearest_zip5) encounters included."`.
5. Line 978: replace `"D-03: Encounter ZIP interpretation (OPEN QUESTION)"` with
   `"Encounter ZIP interpretation (OPEN QUESTION, not a numbered decision)"`.
6. Line 983: replace `"D-02: Nearest-fill encounters in summaries"` with
   `"Nearest-fill encounters in summaries (D-03)"`.
7. Line 849: replace `"pick_best_zip() selects ZIP9 > ZIP5 within Zone 1."` with
   `"pick_best_zip() selects ZIP9 > ZIP5 within Zone 1 (D-07)."`.
8. Line 547: replace `# Per D-02:` with `# Per D-03:`.
9. Line 619: replace `per D-01` with
   `(reference thresholds; the reportable cutoff is D-06, pending)`.
10. Line 1007: append ` -- reference thresholds only; reportable binary cutoff is D-06 (pending team decision)`
    to the end of that string.
11. Line 1021: replace `(D-02 pattern)` with `(project convention)`.

**B9 — Section 4 comment accuracy (line 245)**
Line 245 has the comment `# Sentinel and NA ZIP5 rows excluded` — leave it unchanged.
Immediately after that comment line, add a new comment line:
```r
# NA-start and reversed periods are dropped with a message (see .drop_bad_periods()).
```
  </action>
  <verify>
    <automated>cd "C:/Users/Owner/Documents/insurance_investigation" && Rscript -e 'invisible(parse("R/utils/utils_zip_calendar.R")); invisible(parse("R/122_encounter_distance.R")); cat("parse OK\n")'</automated>
  </verify>
  <done>
- Both files parse without error.
- All nine B-items applied exactly as specified.
- enc_distance select() includes distance_km_haversine after distance_km.
- %||% is gone; portable width_tbl pattern in place.
- qc_tbl glue objects wrapped in as.character().
- All B8 string replacements applied; B9 comment added after line 245.
  </done>
</task>

<task type="auto">
  <name>Task 3: Run C-Verification checks and create test scaffold if absent</name>
  <files>tests/testthat/test-utils-zip-calendar.R</files>
  <action>
Run the verification commands from FIX_122_and_zip_calendar.md section C.

**Step 1 — Parse check (both files):**
```bash
module load R/4.5
Rscript -e 'invisible(parse("R/utils/utils_zip_calendar.R")); invisible(parse("R/122_encounter_distance.R")); cat("parse OK\n")'
```
If either parse fails, fix the syntax error before proceeding.

**Step 2 — Helper existence check:**
```bash
Rscript -e 'source("R/00_config.R"); stopifnot(all(sapply(c("normalize_zip9","normalize_zip5","normalize_zip5_raw","is_sentinel_zip5","parse_pcornet_date","get_zip_centroid","haversine_km"), exists))); cat("helpers OK\n")'
```
If parse_pcornet_date is missing, report which file it is defined in and stop; do not reimplement.

**Step 3 — zipcodeR smoke test:**
```bash
Rscript -e 'library(zipcodeR); d <- zip_distance("32610","32601"); stopifnot(nrow(d)==1, d$distance > 1, d$distance < 10); cat("zipcodeR OK\n")'
```

**Step 4 — CSV header check:**
```bash
head -1 data/LDS_ADDRESS_HISTORY_Mailhot_V1.csv
```
Confirm the header contains: ID, ADDRESS_ZIP9, ADDRESS_ZIP5, ADDRESS_PERIOD_START, ADDRESS_PERIOD_END.
If any name differs, report the actual names and stop; do not rename columns in the helper.

**Step 5 — Create test file if absent:**
If `tests/testthat/test-utils-zip-calendar.R` does not exist, create it with the nine test cases
described in FIX_122_and_zip_calendar.md section C:

1. Two identical (ID, ZIP9, start, end) rows collapse to one.
2. Same ZIP, adjacent periods (2020-01-01..2020-06-30 and 2020-07-01..2020-12-31) merge into one run.
3. Same ZIP, gap periods (2020-01-01..2020-03-31 and 2020-06-01..2020-12-31) stay as two runs.
4. Two ZIPs both covering 2020-05-01: n_candidates_in_range == 2, ZIP9 row chosen over ZIP5.
5. Nearest-win test: encounter 2021-01-15, ZIP5 period ends 2021-01-05 (offset=10), ZIP9 period starts 2021-01-25 (offset=10). Adjust to offsets 10 vs 12 for nearest-wins case; second case with equal offsets tests earlier-wins.
6. Patient with no address history: distance_status == "patient_zip_missing".
7. Row with NA ADDRESS_PERIOD_END: end == study_end.
8. Row with NA start is dropped and a message is emitted.
9. compute_encounter_distance() output has no ADMIT_DATE column.

Each test must use `testthat::test_that()` with `expect_*` assertions. Use minimal in-memory
tibbles as input (no file I/O). Tests must be runnable from the project root via:
```bash
Rscript -e 'testthat::test_file("tests/testthat/test-utils-zip-calendar.R")'
```

Run the tests. All nine must pass before declaring done.

**Step 6 — Report results:**
Print the results of each verification step. If any step fails, report the failure message
and the specific fix needed before stopping.

NOTE: Do NOT submit `sbatch slurm/122_encounter_distance.sbatch` — that requires HiPerGator.
Only the local parse/helper/zipcodeR/header checks and unit tests are in scope here.
  </action>
  <verify>
    <automated>cd "C:/Users/Owner/Documents/insurance_investigation" && Rscript -e 'invisible(parse("R/utils/utils_zip_calendar.R")); invisible(parse("R/122_encounter_distance.R")); cat("parse OK\n")' && Rscript -e 'testthat::test_file("tests/testthat/test-utils-zip-calendar.R")'</automated>
  </verify>
  <done>
- Both files parse cleanly.
- helpers OK check passes (parse_pcornet_date and all six other helpers exist).
- zipcodeR smoke test passes.
- CSV header confirmed (or discrepancy reported and stopped).
- test-utils-zip-calendar.R exists with all nine test cases.
- All nine tests pass.
  </done>
</task>

</tasks>

<verification>
After all three tasks:
- `Rscript -e 'invisible(parse("R/utils/utils_zip_calendar.R")); invisible(parse("R/122_encounter_distance.R")); cat("parse OK\n")'` exits 0.
- `Rscript -e 'testthat::test_file("tests/testthat/test-utils-zip-calendar.R")'` shows 9/9 pass.
- No ADMIT_DATE column in compute_encounter_distance() output (test 9 confirms).
- distance_km_haversine present in enc_distance select() (grep confirms).
- %||% is absent from R/122_encounter_distance.R (grep confirms).
</verification>

<success_criteria>
- All A1–A8 edits applied to utils_zip_calendar.R with no behavior changes beyond the specified fixes.
- All B1–B9 edits applied to R/122_encounter_distance.R with no behavior changes beyond the specified fixes.
- Both files parse cleanly under R/4.5.
- Nine unit tests in test-utils-zip-calendar.R all pass.
- No regression in existing behavior (the parse check and unit tests are the gate).
</success_criteria>

<output>
No SUMMARY.md required for quick tasks. Report verification output directly in the final message.
</output>
