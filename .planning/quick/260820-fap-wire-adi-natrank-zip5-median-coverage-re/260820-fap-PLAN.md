---
phase: quick
plan: 260820-fap
type: execute
wave: 1
depends_on: []
files_modified:
  - R/116_encounter_ses_index.R
autonomous: true
requirements: []
must_haves:
  truths:
    - "vroom reads zip5_adi_summary.csv without col_types warnings about adi_coverage"
    - "SECTION 7 console prints adi_natrank_zip5_median coverage percentage"
    - "SECTION 9 index_coverage tibble has a fifth row for ADI ZIP5 median"
    - "SECTION 9 coverage_ceilings tibble has a row for ADI ZIP5 median"
  artifacts:
    - path: "R/116_encounter_ses_index.R"
      provides: "all three edits applied"
---

<objective>
Wire adi_natrank_zip5_median coverage reporting into R/116.

Purpose: R/118 now writes an adi_coverage column to zip5_adi_summary.csv; R/116 must
declare it in col_types to avoid vroom warnings. The index_coverage and coverage_ceilings
tables need a new row so the output xlsx reflects this ZIP5-median tier's actual coverage.

Output: Three targeted edits to R/116_encounter_ses_index.R only.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
</execution_context>

<context>
@.planning/STATE.md
@R/116_encounter_ses_index.R
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add adi_coverage to vroom col_types spec (SECTION 5, ~line 163)</name>
  <files>R/116_encounter_ses_index.R</files>
  <action>
    In the vroom::cols() block for ADI_SUMMARY_PATH (inside the `if (has_adi_summary)` block,
    SECTION 5), add one line after `source = vroom::col_character()`:

      adi_coverage   = vroom::col_double()

    Preserve the existing indentation style (two-space inside vroom::cols, column name
    left-aligned with the others, `=` aligned). The col_types block currently ends with
    `source = vroom::col_character()` — append the new column after that line, before the
    closing parenthesis of vroom::cols().
  </action>
  <verify>grep -n "adi_coverage" R/116_encounter_ses_index.R</verify>
  <done>Line present: `adi_coverage   = vroom::col_double()` inside the vroom::cols() block</done>
</task>

<task type="auto">
  <name>Task 2: Add SECTION 7 coverage message for adi_natrank_zip5_median (~line 370)</name>
  <files>R/116_encounter_ses_index.R</files>
  <action>
    After the existing line:
      message(glue("  ruca_code coverage:   {round(100 * mean(!is.na(encounter_ses$ruca_code)),  1)}%"))

    Insert this new line (same indentation, same glue pattern):
      message(glue("  adi_natrank_zip5_median coverage: {round(100 * mean(!is.na(encounter_ses$adi_natrank_zip5_median)), 1)}%"))

    No trailing spaces needed — alignment padding is not required for this longer label.
  </action>
  <verify>grep -n "adi_natrank_zip5_median coverage" R/116_encounter_ses_index.R</verify>
  <done>Line present immediately after the ruca_code coverage message</done>
</task>

<task type="auto">
  <name>Task 3: Add ADI ZIP5 median rows to index_coverage and coverage_ceilings (SECTION 9, ~lines 393-480)</name>
  <files>R/116_encounter_ses_index.R</files>
  <action>
    **Edit A — index_coverage tibble (~line 393):**
    The tibble currently has four rows: SDI, ADI, SVI, RUCA. Change the four-element
    vectors to five-element vectors by inserting the new ADI ZIP5 median values between
    the ADI and SVI positions (i.e., as the third element in each vector):

      index        = c("SDI", "ADI", "ADI ZIP5 median", "SVI", "RUCA")

      n_non_na     = c(sum(!is.na(encounter_ses$sdi_score)),
                       sum(!is.na(encounter_ses$adi_natrank)),
                       sum(!is.na(encounter_ses$adi_natrank_zip5_median)),
                       sum(!is.na(encounter_ses$svi_score)),
                       sum(!is.na(encounter_ses$ruca_code)))

      n_total      = nrow(encounter_ses)        # scalar, unchanged

      pct_coverage = round(100 * n_non_na / n_total, 1)   # derived, unchanged

      join_key     = c("ZIP5","ZIP9","ZIP5","ZIP5","ZIP5")

      file_present = c(has_sdi, has_adi, has_adi_summary, has_svi, has_ruca)

    **Edit B — coverage_ceilings tibble (~line 452):**
    The tibble currently has six rows. Insert a new row for "ADI ZIP5 median" between
    the "SVI" row and the "ADI" row (i.e., as the fourth element of each vector, pushing
    the existing "ADI" to fifth and the two NOTE rows to sixth and seventh):

      index = c("RUCA", "SDI", "SVI", "ADI ZIP5 median", "ADI",
                "NOTE: no-index encounters", "NOTE: SVI ranking caveat")

      geography = c("ZIP5", "ZCTA via ZIP5 (D-01)", "ZCTA via ZIP5 derived (D-02a-i)",
                    "ZIP5 (beneficiary-based denominator)", "ZIP9 (D-05)",
                    NA_character_, NA_character_)

      best_achievable_pct = c(
        "77.7% (achieved)",
        paste0("<=77.7%, minus ZIP5s with no ZCTA (count PENDING HiPerGator run)"),
        paste0("<=77.7%, minus ZCTA match (PENDING HiPerGator run of R/117_build_svi_zcta.R)"),
        "<=77.7%, limited to ZIP5s with >=50% ADI coverage (floor = 0.50)",
        "<=77.7%",
        NA_character_, NA_character_
      )

      limited_by = c(
        "ZIP availability",
        "ZIP availability, then ZCTA match (PO-box-only/single-building ZIPs unmatched)",
        "ZIP availability, then ZCTA match, then derivation (findSVI Census API)",
        "ZIP5 availability, then coverage floor (ADI_COVERAGE_FLOOR=0.50 in R/118); denominator is beneficiary-based ZIP+4 segments, not all USPS delivery segments",
        "ZIP9 availability only (23-state collation; 478MB file; transfer via scp)",
        NA_character_, NA_character_
      )

      note = c(NA_character_, NA_character_, NA_character_, NA_character_, NA_character_,
               <existing NOTE: no-index note string unchanged>,
               <existing NOTE: SVI ranking caveat string unchanged>)

    Keep the existing note strings for the two NOTE rows byte-for-byte unchanged.
    Match indentation style of the existing coverage_ceilings tibble.
  </action>
  <verify>grep -n "ADI ZIP5 median" R/116_encounter_ses_index.R</verify>
  <done>Two matches found: one in index_coverage, one in coverage_ceilings</done>
</task>

</tasks>

<verification>
grep -n "adi_coverage\|adi_natrank_zip5_median" R/116_encounter_ses_index.R
Expected: adi_coverage in col_types block; adi_natrank_zip5_median in coverage message + index_coverage + coverage_ceilings
</verification>

<success_criteria>
- adi_coverage = vroom::col_double() present in the ADI_SUMMARY_PATH vroom::cols() block
- SECTION 7 has a fifth coverage message line for adi_natrank_zip5_median
- index_coverage tibble has 5 data rows (SDI, ADI, ADI ZIP5 median, SVI, RUCA) + existing Phase-145 appended rows
- coverage_ceilings tibble has 7 rows including "ADI ZIP5 median" between "SVI" and "ADI"
- No other files modified
</success_criteria>

<output>
After completion, create `.planning/quick/260820-fap-wire-adi-natrank-zip5-median-coverage-re/260820-fap-SUMMARY.md`
</output>
