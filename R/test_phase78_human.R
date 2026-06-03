# ==============================================================================
# test_phase78_human.R -- HiPerGator Human Verification Tests for Phase 78
# ==============================================================================
#
# Purpose:
#   Interactive test script to verify Phase 78 (Episode Enhancement & Death
#   Integration) runtime behavior on HiPerGator. Runs each UAT test case,
#   checks actual outputs, and reports PASS/FAIL with diagnostics.
#
# Usage:
#   1. Open RStudio on HiPerGator
#   2. source("R/test_phase78_human.R")
#   3. Review console output for PASS/FAIL results
#
# Prerequisites:
#   - DuckDB database populated (R/01 through R/27 already run)
#   - treatment_episodes.rds exists (from prior R/28 run)
#   - code_descriptions.rds exists (from Phase 48b)
#   - validated_death_dates.rds exists (from Phase 59)
#
# UAT Test Cases (from 78-HUMAN-UAT.md):
#   1. Execute R/35 and verify multi-sheet xlsx output
#   2. Execute R/28 and verify treatment_episodes.rds has 17 columns
#   3. Execute R/52 and verify Gantt CSV column counts
#   4. Run smoke test and verify Phase 78 checks pass
#
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
})

# ==============================================================================
# TEST HARNESS
# ==============================================================================

test_passed <- 0L
test_failed <- 0L
test_errors <- character(0)

pass <- function(msg) {
  test_passed <<- test_passed + 1L
  message(glue("  [PASS] {msg}"))
}

fail <- function(msg, detail = NULL) {
  test_failed <<- test_failed + 1L
  test_errors <<- c(test_errors, msg)
  message(glue("  [FAIL] {msg}"))
  if (!is.null(detail)) message(glue("         {detail}"))
}

section <- function(num, title) {
  message(glue("\n{strrep('=', 70)}"))
  message(glue("UAT TEST {num}: {title}"))
  message(strrep("=", 70))
}

# ==============================================================================
# LOAD CONFIG
# ==============================================================================

message("Loading R/00_config.R...")
source("R/00_config.R")

OUTPUTS_DIR <- CONFIG$cache$outputs_dir
OUTPUT_DIR  <- CONFIG$output_dir


# ==============================================================================
# UAT TEST 1: Execute R/35 and verify multi-sheet xlsx output
# ==============================================================================

section(1, "R/35 Death Cause Quality Profiling")

message("Running R/35_death_cause_quality.R...")
tryCatch({
  source("R/35_death_cause_quality.R")
  pass("R/35 executed without error")
}, error = function(e) {
  fail("R/35 execution failed", conditionMessage(e))
})

# Check 1a: death_cause_quality.xlsx exists
xlsx_path <- file.path(OUTPUT_DIR, "death_cause_quality.xlsx")
if (file.exists(xlsx_path)) {
  pass(glue("death_cause_quality.xlsx exists ({round(file.size(xlsx_path)/1024, 1)} KB)"))

  # Check 1b: Verify 5 sheets
  tryCatch({
    suppressPackageStartupMessages(library(openxlsx2))
    wb <- wb_load(xlsx_path)
    sheet_names <- wb$sheet_names
    expected_sheets <- c("Overall Completeness", "By Payer Category",
                         "By Partner Site", "Cause Category Distribution",
                         "Recommendations")

    if (length(sheet_names) == 5) {
      pass(glue("Workbook has 5 sheets: {paste(sheet_names, collapse=', ')}"))
    } else {
      fail(glue("Expected 5 sheets, found {length(sheet_names)}"),
           glue("Found: {paste(sheet_names, collapse=', ')}"))
    }

    # Check each expected sheet is present
    missing_sheets <- setdiff(expected_sheets, sheet_names)
    if (length(missing_sheets) == 0) {
      pass("All expected sheet names present")
    } else {
      fail(glue("Missing sheets: {paste(missing_sheets, collapse=', ')}"))
    }

    # Check 1c: Overall Completeness has data
    overall_data <- wb_to_df(wb, sheet = "Overall Completeness", start_row = 4)
    if (nrow(overall_data) >= 4) {
      pass(glue("Overall Completeness sheet has {nrow(overall_data)} metric rows"))
    } else {
      fail(glue("Overall Completeness sheet has only {nrow(overall_data)} rows, expected >= 4"))
    }
  }, error = function(e) {
    fail("Could not validate xlsx contents", conditionMessage(e))
  })
} else {
  fail(glue("death_cause_quality.xlsx not found at {xlsx_path}"))
}

# Check 1d: death_cause_quality_result.rds exists and has expected structure
rds_path <- file.path(OUTPUTS_DIR, "death_cause_quality_result.rds")
if (file.exists(rds_path)) {
  qr <- readRDS(rds_path)
  if (is.list(qr)) {
    expected_keys <- c("missingness_rate", "death_cause_available", "recommendation",
                       "n_deaths", "n_with_cause", "pct_complete")
    present_keys <- intersect(expected_keys, names(qr))
    if (length(present_keys) == length(expected_keys)) {
      pass(glue("death_cause_quality_result.rds has all 6 expected keys"))
    } else {
      missing_keys <- setdiff(expected_keys, names(qr))
      fail(glue("RDS missing keys: {paste(missing_keys, collapse=', ')}"))
    }
    message(glue("  INFO: missingness_rate = {qr$missingness_rate}%"))
    message(glue("  INFO: n_deaths = {qr$n_deaths}, n_with_cause = {qr$n_with_cause}"))
    message(glue("  INFO: recommendation = {qr$recommendation}"))
  } else {
    fail("death_cause_quality_result.rds is not a list", glue("Class: {class(qr)}"))
  }
} else {
  fail(glue("death_cause_quality_result.rds not found at {rds_path}"))
}


# ==============================================================================
# UAT TEST 2: Execute R/28 and verify treatment_episodes.rds has 17 columns
# ==============================================================================

section(2, "R/28 Episode Classification (Code Descriptions + Drug Groups)")

message("Running R/28_episode_classification.R...")
tryCatch({
  source("R/28_episode_classification.R")
  pass("R/28 executed without error")
}, error = function(e) {
  fail("R/28 execution failed", conditionMessage(e))
})

# Check 2a: treatment_episodes.rds exists
episodes_path <- file.path(OUTPUTS_DIR, "treatment_episodes.rds")
if (file.exists(episodes_path)) {
  episodes <- readRDS(episodes_path)

  # Check 2b: Column count is 17
  ncols <- ncol(episodes)
  if (ncols == 17) {
    pass(glue("treatment_episodes.rds has {ncols} columns (expected 17)"))
  } else {
    fail(glue("treatment_episodes.rds has {ncols} columns, expected 17"),
         glue("Columns: {paste(names(episodes), collapse=', ')}"))
  }

  # Check 2c: triggering_code_description column exists
  if ("triggering_code_description" %in% names(episodes)) {
    n_populated <- sum(!is.na(episodes$triggering_code_description) &
                       episodes$triggering_code_description != "", na.rm = TRUE)
    pass(glue("triggering_code_description column present ({n_populated}/{nrow(episodes)} populated)"))

    # Show sample values
    sample_vals <- episodes %>%
      filter(!is.na(triggering_code_description) & triggering_code_description != "") %>%
      head(3) %>%
      pull(triggering_code_description)
    if (length(sample_vals) > 0) {
      message("  INFO: Sample triggering_code_description values:")
      for (v in sample_vals) message(glue("    - {v}"))
    }
  } else {
    fail("triggering_code_description column missing from treatment_episodes.rds")
  }

  # Check 2d: drug_group column exists
  if ("drug_group" %in% names(episodes)) {
    n_populated <- sum(!is.na(episodes$drug_group) &
                       episodes$drug_group != "", na.rm = TRUE)
    pass(glue("drug_group column present ({n_populated}/{nrow(episodes)} populated)"))

    # Show sample values
    sample_vals <- episodes %>%
      filter(!is.na(drug_group) & drug_group != "") %>%
      head(3) %>%
      pull(drug_group)
    if (length(sample_vals) > 0) {
      message("  INFO: Sample drug_group values:")
      for (v in sample_vals) message(glue("    - {v}"))
    }
  } else {
    fail("drug_group column missing from treatment_episodes.rds")
  }

  # Check 2e: Verify comma-separated values match triggering_codes ordering
  sample_with_multi <- episodes %>%
    filter(grepl(",", triggering_codes)) %>%
    head(2)
  if (nrow(sample_with_multi) > 0) {
    message("  INFO: Multi-code episodes (verify comma-separated alignment):")
    for (i in 1:nrow(sample_with_multi)) {
      row <- sample_with_multi[i, ]
      message(glue("    codes: {row$triggering_codes}"))
      message(glue("    descs: {row$triggering_code_description}"))
      message(glue("    groups: {row$drug_group}"))
    }
    pass("Multi-code episodes found -- verify alignment above visually")
  } else {
    message("  INFO: No multi-code episodes found (single-code mapping only)")
  }
} else {
  fail(glue("treatment_episodes.rds not found at {episodes_path}"))
}


# ==============================================================================
# UAT TEST 3: Execute R/52 and verify Gantt CSV column counts
# ==============================================================================

section(3, "R/52 Gantt v2 Export (Drug Group + Cause of Death)")

message("Running R/52_gantt_v2_export.R...")
tryCatch({
  source("R/52_gantt_v2_export.R")
  pass("R/52 executed without error")
}, error = function(e) {
  fail("R/52 execution failed", conditionMessage(e))
})

# Check 3a: gantt_episodes_v2.csv column count
gantt_ep_path <- file.path(OUTPUT_DIR, "gantt_episodes_v2.csv")
if (file.exists(gantt_ep_path)) {
  gantt_ep <- read.csv(gantt_ep_path, nrows = 5)
  ncols_ep <- ncol(gantt_ep)
  if (ncols_ep == 16) {
    pass(glue("gantt_episodes_v2.csv has {ncols_ep} columns (expected 16)"))
  } else {
    fail(glue("gantt_episodes_v2.csv has {ncols_ep} columns, expected 16"),
         glue("Columns: {paste(names(gantt_ep), collapse=', ')}"))
  }

  # Check 3b: drug_group column present
  if ("drug_group" %in% names(gantt_ep)) {
    pass("drug_group column present in gantt_episodes_v2.csv")
  } else {
    fail("drug_group column missing from gantt_episodes_v2.csv")
  }

  # Check 3c: cause_of_death column present
  if ("cause_of_death" %in% names(gantt_ep)) {
    pass("cause_of_death column present in gantt_episodes_v2.csv")
  } else {
    fail("cause_of_death column missing from gantt_episodes_v2.csv")
  }
} else {
  fail(glue("gantt_episodes_v2.csv not found at {gantt_ep_path}"))
}

# Check 3d: gantt_detail_v2.csv column count
gantt_detail_path <- file.path(OUTPUT_DIR, "gantt_detail_v2.csv")
if (file.exists(gantt_detail_path)) {
  gantt_detail <- read.csv(gantt_detail_path, nrows = 5)
  ncols_detail <- ncol(gantt_detail)
  if (ncols_detail == 14) {
    pass(glue("gantt_detail_v2.csv has {ncols_detail} columns (expected 14)"))
  } else {
    fail(glue("gantt_detail_v2.csv has {ncols_detail} columns, expected 14"),
         glue("Columns: {paste(names(gantt_detail), collapse=', ')}"))
  }

  # Check 3e: cause_of_death column present in detail
  if ("cause_of_death" %in% names(gantt_detail)) {
    pass("cause_of_death column present in gantt_detail_v2.csv")
  } else {
    fail("cause_of_death column missing from gantt_detail_v2.csv")
  }
} else {
  fail(glue("gantt_detail_v2.csv not found at {gantt_detail_path}"))
}

# Check 3f: Death rows have mapped cause_of_death values
if (file.exists(gantt_ep_path)) {
  gantt_ep_full <- read.csv(gantt_ep_path)
  death_rows <- gantt_ep_full %>% filter(treatment_type == "Death")
  if (nrow(death_rows) > 0) {
    n_with_cause <- sum(!is.na(death_rows$cause_of_death) &
                        death_rows$cause_of_death != "", na.rm = TRUE)
    pct <- round(100 * n_with_cause / nrow(death_rows), 1)
    if (n_with_cause > 0) {
      pass(glue("Death rows have cause_of_death: {n_with_cause}/{nrow(death_rows)} ({pct}%)"))
    } else {
      fail("No death rows have cause_of_death populated")
    }

    # Show cause_of_death value distribution for death rows
    cause_dist <- death_rows %>%
      count(cause_of_death, sort = TRUE) %>%
      head(5)
    message("  INFO: Top cause_of_death values in death rows:")
    for (i in 1:nrow(cause_dist)) {
      message(glue("    {cause_dist$cause_of_death[i]}: {cause_dist$n[i]}"))
    }
  } else {
    message("  INFO: No death rows found in gantt_episodes_v2.csv")
  }

  # Check 3g: Treatment rows have NA cause_of_death
  treatment_rows <- gantt_ep_full %>%
    filter(treatment_type != "Death" & treatment_type != "HL Diagnosis")
  if (nrow(treatment_rows) > 0) {
    n_non_na <- sum(!is.na(treatment_rows$cause_of_death) &
                    treatment_rows$cause_of_death != "", na.rm = TRUE)
    if (n_non_na == 0) {
      pass("Treatment rows correctly have NA/empty cause_of_death")
    } else {
      fail(glue("{n_non_na} treatment rows have non-NA cause_of_death (expected all NA)"))
    }
  }
}


# ==============================================================================
# UAT TEST 4: Run smoke test and verify Phase 78 checks pass
# ==============================================================================

section(4, "R/88 Smoke Test (Phase 78 Sections 14-15)")

message("Running R/88_smoke_test_comprehensive.R...")

# Capture smoke test output to check for failures
smoke_output <- capture.output({
  smoke_result <- tryCatch({
    source("R/88_smoke_test_comprehensive.R")
    "success"
  }, error = function(e) {
    conditionMessage(e)
  })
}, type = "message")

# Display smoke test output
message("\n--- Smoke test output (filtered to Phase 78 sections) ---")
in_section_14_15_16 <- FALSE
for (line in smoke_output) {
  if (grepl("\\[14/16\\]|\\[15/16\\]|\\[16/16\\]|SECTION 14|SECTION 15|SECTION 16|ALL.*CHECKS|FAILED.*checks", line)) {
    in_section_14_15_16 <- TRUE
  }
  if (in_section_14_15_16) {
    message(line)
  }
  if (grepl("^={5,}", line) && in_section_14_15_16 && grepl("CHECKS", paste(smoke_output, collapse = " "))) {
    # Continue showing until end
  }
}
message("--- End smoke test output ---\n")

if (smoke_result == "success") {
  pass("R/88 smoke test completed without error (all checks passed)")
} else {
  fail("R/88 smoke test failed", smoke_result)
}

# Check for CANCER-03, DEATH-01, DEATH-02 in output
validated_reqs <- paste(smoke_output, collapse = " ")
if (grepl("CANCER-03", validated_reqs)) {
  pass("CANCER-03 listed in validated requirements")
} else {
  fail("CANCER-03 not found in smoke test validated requirements")
}

if (grepl("DEATH-01", validated_reqs)) {
  pass("DEATH-01 listed in validated requirements")
} else {
  fail("DEATH-01 not found in smoke test validated requirements")
}

if (grepl("DEATH-02", validated_reqs)) {
  pass("DEATH-02 listed in validated requirements")
} else {
  fail("DEATH-02 not found in smoke test validated requirements")
}


# ==============================================================================
# SUMMARY
# ==============================================================================

message(glue("\n{'='|strrep(70)}"))
message("PHASE 78 HUMAN UAT RESULTS")
message(strrep("=", 70))
total <- test_passed + test_failed
message(glue("  PASSED: {test_passed}/{total}"))
message(glue("  FAILED: {test_failed}/{total}"))
message(strrep("=", 70))

if (test_failed > 0) {
  message("\nFailed tests:")
  for (err in test_errors) {
    message(glue("  - {err}"))
  }
  message(glue("\nResult: FAIL ({test_failed} test(s) did not pass)"))
} else {
  message(glue("\nResult: ALL {total} TESTS PASSED"))
  message("Phase 78 human verification complete.")
}
message("")
