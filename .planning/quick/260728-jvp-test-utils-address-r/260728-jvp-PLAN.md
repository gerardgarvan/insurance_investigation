---
phase: quick
plan: 260728-jvp
type: execute
wave: 1
depends_on: []
files_modified:
  - tests/test_utils_address.R
  - tests/fixtures/LDS_ADDRESS_HISTORY_Mailhot_V1.csv
autonomous: true
requirements: []
must_haves:
  truths:
    - "All three match_type branches (interval, most_recent_before, none) are exercised and verified locally without HiPerGator"
    - "normalize_zip9/normalize_zip5/normalize_zip5_raw edge cases are covered (8-digit, 9-digit, hyphenated, zip5-only, empty)"
    - "Open-ended period (NA ADDRESS_PERIOD_END) is confirmed to produce match_type = 'interval', not 'none'"
    - "Rscript tests/test_utils_address.R exits 0 (all assertions pass)"
  artifacts:
    - path: "tests/test_utils_address.R"
      provides: "Self-contained unit test script for utils_address.R"
    - path: "tests/fixtures/LDS_ADDRESS_HISTORY_Mailhot_V1.csv"
      provides: "Minimal fixture for get_zip9_at_date() local testing"
  key_links:
    - from: "tests/test_utils_address.R"
      to: "R/utils/utils_address.R"
      via: "source() after sourcing R/00_config.R with overridden CONFIG$data_dir"
      pattern: "CONFIG\\$data_dir"
---

<objective>
Write a self-contained unit test script for `R/utils/utils_address.R` that can run locally (Windows / RStudio) without HiPerGator.

Purpose: UAT tests 2 and 3 are blocked because `get_zip9_at_date()` loads its CSV from `CONFIG$data_dir` with no injection point. The fix is a test script that writes a minimal fixture CSV, temporarily points `CONFIG$data_dir` at the fixture directory, and then calls the function — unblocking local verification of all three `match_type` branches and the open-ended-period guard.

Output: `tests/test_utils_address.R` (runnable via `Rscript tests/test_utils_address.R`) + `tests/fixtures/LDS_ADDRESS_HISTORY_Mailhot_V1.csv`.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@R/utils/utils_address.R
@tests/run_local_test.R
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create LDS_ADDRESS_HISTORY fixture CSV</name>
  <files>tests/fixtures/LDS_ADDRESS_HISTORY_Mailhot_V1.csv</files>
  <action>
Create `tests/fixtures/LDS_ADDRESS_HISTORY_Mailhot_V1.csv` with the minimum columns required by `get_zip9_at_date()`:
`ID, ADDRESS_ZIP9, ADDRESS_PERIOD_START, ADDRESS_PERIOD_END`

Include these rows (cover all branch scenarios):

| ID    | ADDRESS_ZIP9  | ADDRESS_PERIOD_START | ADDRESS_PERIOD_END | Test scenario                          |
|-------|---------------|----------------------|--------------------|----------------------------------------|
| PT001 | 323601234     | 2018-01-01           | 2023-12-31         | interval match — query inside range    |
| PT002 | 10001-5678    | 2015-06-01           |                    | open-ended (NA end) interval match     |
| PT003 | 900011234     | 2010-03-01           | 2019-06-30         | most_recent_before — query after end   |
| PT004 |               | 2020-01-01           | 2022-12-31         | interval but ZIP9 is empty → ZIP9=NA  |

Notes:
- `ADDRESS_PERIOD_END` for PT002 must be blank (empty string), not the literal text "NA"
- `ADDRESS_ZIP9` for PT001 uses 9 digits (clean), for PT002 uses hyphenated format (normalize strips hyphen), for PT004 is empty (normalize → NA)
- Column order must match the header exactly
- Use comma-separated, no extra spaces

The file content:
```
ID,ADDRESS_ZIP9,ADDRESS_PERIOD_START,ADDRESS_PERIOD_END
PT001,323601234,2018-01-01,2023-12-31
PT002,10001-5678,2015-06-01,
PT003,900011234,2010-03-01,2019-06-30
PT004,,2020-01-01,2022-12-31
```
  </action>
  <verify>
    <automated>Rscript -e "x <- read.csv('tests/fixtures/LDS_ADDRESS_HISTORY_Mailhot_V1.csv', colClasses='character', na.strings=c('')); cat('rows:', nrow(x), '\n'); cat('cols:', paste(names(x), collapse=','), '\n'); stopifnot(nrow(x)==4); cat('OK\n')"</automated>
  </verify>
  <done>Fixture CSV exists with 4 data rows and correct column headers. PT002 ADDRESS_PERIOD_END reads as NA/empty. Rscript check exits 0.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Write tests/test_utils_address.R</name>
  <files>tests/test_utils_address.R</files>
  <behavior>
    - normalize_zip9("323601234") == "323601234"  (9-digit clean)
    - normalize_zip9("10001-5678") == "100015678"  (hyphen stripped, 9 digits)
    - normalize_zip9("32360") is NA  (bare ZIP5 → NA, not mangled)
    - normalize_zip9("") is NA
    - normalize_zip9("1234567890") is NA  (10 digits → NA)
    - normalize_zip5_raw("32360") == "32360"
    - normalize_zip5_raw("3236") == "03236"  (padded to 5)
    - normalize_zip5_raw("ABC") is NA
    - get_zip9_at_date("PT001", as.Date("2020-06-15")) → match_type == "interval", ZIP9 == "323601234"
    - get_zip9_at_date("PT002", as.Date("2024-01-01")) → match_type == "interval"  (open-ended NA end treated as 9999-12-31)
    - get_zip9_at_date("PT003", as.Date("2022-05-01")) → match_type == "most_recent_before"  (query after period end)
    - get_zip9_at_date("PTXXX", as.Date("2022-01-01")) → match_type == "none"  (unknown patient)
    - get_zip9_at_date returns exactly one row per distinct (ID, query_date) pair when duplicates passed
    - get_zip9_at_date result has columns: ID, query_date, ZIP9, ZIP5, match_type
  </behavior>
  <action>
Create `tests/test_utils_address.R` — a self-contained test script runnable via `Rscript tests/test_utils_address.R` from the project root.

Structure:

```r
# ==============================================================================
# tests/test_utils_address.R -- Unit tests for R/utils/utils_address.R
# ==============================================================================
# Usage: Rscript tests/test_utils_address.R   (from project root)
# ==============================================================================

cat(strrep("=", 60), "\n")
cat("TEST: utils_address.R\n")
cat(strrep("=", 60), "\n\n")

# --- Setup ---
# Source config (loads utils modules including utils_address.R)
source("R/00_config.R")
# Override CONFIG$data_dir to point at local fixtures
CONFIG$data_dir <- here::here("tests", "fixtures")

# --- Helpers ---
pass_count <- 0L
fail_count <- 0L
check <- function(label, expr) {
  result <- tryCatch(expr, error = function(e) FALSE)
  if (isTRUE(result)) {
    cat(sprintf("  PASS: %s\n", label))
    pass_count <<- pass_count + 1L
  } else {
    cat(sprintf("  FAIL: %s\n", label))
    fail_count <<- fail_count + 1L
  }
}

# --- normalize_zip9 ---
cat("\n[normalize_zip9]\n")
check("9-digit clean",         normalize_zip9("323601234") == "323601234")
check("hyphenated 9-digit",    normalize_zip9("10001-5678") == "100015678")
check("bare ZIP5 -> NA",       is.na(normalize_zip9("32360")))
check("empty -> NA",           is.na(normalize_zip9("")))
check("10-digit -> NA",        is.na(normalize_zip9("1234567890")))
check("8-digit left-padded",   normalize_zip9("32360123") == "032360123")

# --- normalize_zip5_raw ---
cat("\n[normalize_zip5_raw]\n")
check("5-digit clean",         normalize_zip5_raw("32360") == "32360")
check("4-digit padded",        normalize_zip5_raw("3236")  == "03236")
check("alpha -> NA",           is.na(normalize_zip5_raw("ABC")))

# --- get_zip9_at_date ---
cat("\n[get_zip9_at_date]\n")

res_interval <- get_zip9_at_date("PT001", as.Date("2020-06-15"))
check("interval match returns 1 row",        nrow(res_interval) == 1L)
check("interval match_type",                 res_interval$match_type == "interval")
check("interval ZIP9 correct",               res_interval$ZIP9 == "323601234")
check("interval ZIP5 correct",               res_interval$ZIP5 == "32360")
check("result columns correct",              all(c("ID","query_date","ZIP9","ZIP5","match_type") %in% names(res_interval)))

res_open <- get_zip9_at_date("PT002", as.Date("2024-01-01"))
check("open-ended period match_type=interval", res_open$match_type == "interval")
check("open-ended ZIP9 normalized",            res_open$ZIP9 == "100015678")

res_fallback <- get_zip9_at_date("PT003", as.Date("2022-05-01"))
check("fallback match_type=most_recent_before", res_fallback$match_type == "most_recent_before")

res_none <- get_zip9_at_date("PTXXX", as.Date("2022-01-01"))
check("unknown patient match_type=none",     res_none$match_type == "none")
check("none ZIP9 is NA",                     is.na(res_none$ZIP9))

# Deduplicate: passing same (ID, date) twice should return 1 row
res_dedup <- get_zip9_at_date(c("PT001","PT001"), c(as.Date("2020-06-15"), as.Date("2020-06-15")))
check("dedup: 1 row per distinct (ID, date)", nrow(res_dedup) == 1L)

# --- Summary ---
cat(strrep("=", 60), "\n")
cat(sprintf("RESULT: %d passed, %d failed\n", pass_count, fail_count))
cat(strrep("=", 60), "\n")
if (fail_count > 0L) quit(status = 1L)
```

Key implementation notes:
- `CONFIG$data_dir` override MUST happen after `source("R/00_config.R")` and BEFORE any call to `get_zip9_at_date()` — the function reads `CONFIG$data_dir` at call time, not at source time
- Use `here::here("tests", "fixtures")` not a relative path for `CONFIG$data_dir`, so the script works from any working directory
- The `check()` helper uses `tryCatch` to catch assertion errors without aborting the whole run
- Exit code 1 if any failures (Rscript-compatible)
  </action>
  <verify>
    <automated>Rscript tests/test_utils_address.R</automated>
  </verify>
  <done>Rscript tests/test_utils_address.R exits 0 with all assertions passing. Output shows "RESULT: N passed, 0 failed".</done>
</task>

</tasks>

<verification>
After both tasks complete:
1. `Rscript tests/test_utils_address.R` exits 0
2. All three match_type branches confirmed locally: "interval" (PT001 and PT002 open-ended), "most_recent_before" (PT003), "none" (PTXXX)
3. normalize_zip9 edge cases verified: hyphen-strip, 8-digit padding, bare ZIP5 → NA
</verification>

<success_criteria>
- tests/fixtures/LDS_ADDRESS_HISTORY_Mailhot_V1.csv exists with 4 fixture rows
- tests/test_utils_address.R exists and exits 0 via Rscript
- UAT tests 2 and 3 (previously blocked) are unblocked and confirmed passing locally
</success_criteria>

<output>
After completion, report results directly in the conversation. No SUMMARY.md needed for quick tasks.
</output>
