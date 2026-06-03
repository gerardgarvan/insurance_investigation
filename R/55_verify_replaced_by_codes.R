# ==============================================================================
# 55_verify_replaced_by_codes.R -- Replaced-by Code Verification
# ==============================================================================
#
# Purpose:
#   Verify replaced-by code mappings from all_codes_resolved_next_tables_v2.1.xlsx
#   with pairwise validation and graph-based cycle detection. Validates that old->new
#   code pairs both exist in code lists, remain in same category, and form a valid
#   directed acyclic graph (DAG) without cycles or excessively long chains.
#
# Inputs:
#   - data/reference/all_codes_resolved_next_tables_v2.1.xlsx (replaced-by mappings)
#   - R/00_config.R (DRUG_GROUPINGS named vector, TREATMENT_CODES lists)
#
# Outputs:
#   - output/replaced_by_verification.xlsx (3-sheet workbook)
#     - Sheet 1: Pairwise Verification (PASS/FAIL per code pair)
#     - Sheet 2: Chain Analysis (long chains, cycles)
#     - Sheet 3: Summary Statistics (overall verdict)
#
# Dependencies:
#   - R/00_config.R (DRUG_GROUPINGS, TREATMENT_CODES, CONFIG paths)
#   - igraph (graph construction, cycle detection, path analysis)
#   - openxlsx2 (multi-sheet workbook output)
#   - checkmate (input validation)
#
# Requirements:
#   - CODE-01: Verify replaced-by code mappings
#   - QUAL-01: Quality gates for code verification
#
# Decision Traceability:
#   - D-08: Inspect xlsx sheets for replaced-by column structure
#   - D-09: Pairwise verification against DRUG_GROUPINGS + TREATMENT_CODES
#   - D-10: Graph-based cycle detection using igraph::is_dag()
#   - D-11: Three-sheet output format with actionable PASS/FAIL statuses
#
# ==============================================================================

# --- SECTION 1: SETUP AND CONFIGURATION ----

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(stringr)
  library(openxlsx2)
  library(checkmate)
  library(igraph)
})

source("R/00_config.R")

XLSX_PATH <- "data/reference/all_codes_resolved_next_tables_v2.1.xlsx"
OUTPUT_XLSX <- file.path(CONFIG$output_dir, "replaced_by_verification.xlsx")

message("=== Phase 79: Replaced-by Code Verification ===\n")
message(glue("  Source: {XLSX_PATH}"))
message(glue("  Output: {OUTPUT_XLSX}\n"))


# --- SECTION 2: LOAD AND INSPECT XLSX ----

message("--- Loading and inspecting XLSX structure ---")

# Validate input file exists
assert_file_exists(XLSX_PATH, .var.name = "[R/55 ERROR] Input XLSX")

# Load workbook and inspect sheets
wb <- wb_load(XLSX_PATH)
sheet_names <- wb_get_sheet_names(wb)

message(glue("  Sheets found: {paste(sheet_names, collapse=', ')}"))

# Read each sheet to find replaced-by mappings
# Common column names: "code", "old_code", "replaced_by", "next_code", "new_code"
replaced_by_pairs <- NULL

for (sheet_name in sheet_names) {
  sheet_data <- wb_to_df(wb, sheet = sheet_name)

  # Check for replaced-by pattern columns (drop NAs from unnamed columns)
  cols <- tolower(names(sheet_data))
  cols <- cols[!is.na(cols)]

  # Look for old->new code pair patterns
  has_replaced_by <- any(str_detect(cols, "replaced|next"), na.rm = TRUE)
  has_code_col <- any(str_detect(cols, "^code$|old_code"), na.rm = TRUE)

  if (has_replaced_by && has_code_col) {
    message(glue("  Found replaced-by mappings in sheet: {sheet_name}"))

    # Identify old_code and new_code columns
    old_col <- names(sheet_data)[str_detect(tolower(names(sheet_data)), "^code$|old_code")][1]
    new_col <- names(sheet_data)[str_detect(tolower(names(sheet_data)), "replaced|next")][1]

    if (!is.na(old_col) && !is.na(new_col)) {
      message(glue("    Old code column: {old_col}"))
      message(glue("    New code column: {new_col}"))

      pairs <- sheet_data %>%
        select(old_code = all_of(old_col), new_code = all_of(new_col)) %>%
        filter(!is.na(old_code), !is.na(new_code), old_code != "", new_code != "") %>%
        mutate(
          old_code = as.character(old_code),
          new_code = as.character(new_code),
          sheet_source = sheet_name
        )

      if (is.null(replaced_by_pairs)) {
        replaced_by_pairs <- pairs
      } else {
        replaced_by_pairs <- bind_rows(replaced_by_pairs, pairs)
      }

      message(glue("    Found {nrow(pairs)} code pairs"))
    }
  }
}

# If no replaced-by pairs found, create empty structure
if (is.null(replaced_by_pairs) || nrow(replaced_by_pairs) == 0) {
  warning("No replaced-by code mappings found in any sheet. Creating minimal verification report.")

  # Create empty verification outputs
  verification <- tibble(
    old_code = character(),
    new_code = character(),
    old_in_codes = logical(),
    new_in_codes = logical(),
    old_group = character(),
    new_group = character(),
    category_match = logical(),
    status = character()
  )

  chain_results <- tibble(
    message = "No replaced-by mappings found in input file"
  )

  summary_stats <- tibble(
    metric = c("total_pairs", "n_pass", "n_fail", "n_missing", "pass_rate_pct",
               "is_dag", "n_long_chains", "max_chain_length", "overall_verdict"),
    value = c("0", "0", "0", "0", "N/A", "N/A", "0", "0",
              "NO DATA: No replaced-by mappings found in input file")
  )

  # Skip to output section
  skip_graph_analysis <- TRUE

} else {
  message(glue("\nTotal replaced-by mappings found: {nrow(replaced_by_pairs)} pairs"))
  skip_graph_analysis <- FALSE
}


# --- SECTION 3: PAIRWISE VERIFICATION ----

if (!skip_graph_analysis) {
  message("\n--- Performing pairwise verification ---")

  # Build all_known_codes from TREATMENT_CODES and DRUG_GROUPINGS
  all_treatment_codes <- unlist(TREATMENT_CODES, use.names = FALSE)
  all_known_codes <- unique(c(all_treatment_codes, names(DRUG_GROUPINGS)))

  message(glue("  All known codes: {length(all_known_codes)} unique codes"))

  # Verify each old->new pair
  verification <- replaced_by_pairs %>%
    mutate(
      old_in_codes = old_code %in% all_known_codes,
      new_in_codes = new_code %in% all_known_codes,
      old_group = DRUG_GROUPINGS[old_code],
      new_group = DRUG_GROUPINGS[new_code],
      category_match = case_when(
        is.na(old_group) | is.na(new_group) ~ NA,
        TRUE ~ old_group == new_group
      ),
      status = case_when(
        !old_in_codes & !new_in_codes ~ "MISSING: both codes not in code lists",
        !old_in_codes ~ "MISSING: old code not in code lists",
        !new_in_codes ~ "MISSING: new code not in code lists",
        !is.na(category_match) & !category_match ~ "FAIL: category mismatch",
        TRUE ~ "PASS"
      )
    )

  # Console summary
  status_counts <- verification %>%
    count(status) %>%
    arrange(desc(n))

  message("\n  Status counts:")
  for (i in seq_len(nrow(status_counts))) {
    message(glue("    {status_counts$status[i]}: {status_counts$n[i]}"))
  }
}


# --- SECTION 4: CHAIN ANALYSIS WITH IGRAPH ----

if (!skip_graph_analysis) {
  message("\n--- Performing graph analysis for cycles and long chains ---")

  # Build directed graph from old->new edges
  edge_list <- verification %>%
    select(from = old_code, to = new_code) %>%
    filter(!is.na(from), !is.na(to))

  g <- graph_from_data_frame(edge_list, directed = TRUE)

  message(glue("  Graph built: {vcount(g)} vertices, {ecount(g)} edges"))

  # Cycle detection
  dag_check <- is_dag(g)

  if (!dag_check) {
    message("  WARNING: Replacement graph contains cycles!")
    cycle_info <- "Cycles detected in replacement graph"
  } else {
    message("  PASS: No cycles in replacement graph (valid DAG)")
    cycle_info <- "No cycles detected (valid DAG)"
  }

  # Long chain detection (>3 steps)
  # Calculate shortest path lengths between all pairs
  dist_matrix <- distances(g, mode = "out")

  # Find long chains (distance > 3)
  long_chains <- which(dist_matrix > 3 & is.finite(dist_matrix), arr.ind = TRUE)

  if (nrow(long_chains) > 0) {
    message(glue("  Found {nrow(long_chains)} long chains (>3 steps)"))

    chain_results <- tibble(
      start_code = rownames(dist_matrix)[long_chains[, 1]],
      end_code = colnames(dist_matrix)[long_chains[, 2]],
      chain_length = dist_matrix[long_chains]
    )

    # Get paths for each long chain
    chain_results <- chain_results %>%
      rowwise() %>%
      mutate(
        path = {
          sp <- shortest_paths(g, from = start_code, to = end_code, mode = "out", output = "vpath")
          if (length(sp$vpath[[1]]) > 0) {
            paste(names(sp$vpath[[1]]), collapse = " -> ")
          } else {
            NA_character_
          }
        }
      ) %>%
      ungroup() %>%
      arrange(desc(chain_length))

    max_chain_length <- max(chain_results$chain_length)
  } else {
    message("  No chains >3 steps detected")
    chain_results <- tibble(message = "No chains >3 steps detected")
    max_chain_length <- 0
  }

  # Add cycle information to chain results
  if (!dag_check && exists("chain_results")) {
    chain_results <- bind_rows(
      tibble(message = cycle_info),
      chain_results
    )
  } else if (!dag_check) {
    chain_results <- tibble(message = cycle_info)
  }
}


# --- SECTION 5: BUILD OUTPUT TABLES ----

if (!skip_graph_analysis) {
  message("\n--- Building output tables ---")

  # Sheet 1: Pairwise Verification
  pairwise_output <- verification %>%
    select(old_code, new_code, old_in_codes, new_in_codes, old_group, new_group,
           category_match, status, sheet_source)

  # Sheet 3: Summary Statistics
  n_total <- nrow(verification)
  n_pass <- sum(verification$status == "PASS")
  n_fail <- sum(str_detect(verification$status, "^FAIL"))
  n_missing <- sum(str_detect(verification$status, "^MISSING"))
  pass_rate_pct <- round(100 * n_pass / n_total, 1)

  n_long_chains <- if (exists("max_chain_length")) {
    if (max_chain_length > 0) nrow(chain_results) - if (exists("cycle_info")) 1 else 0 else 0
  } else {
    0
  }

  overall_verdict <- case_when(
    dag_check && n_fail == 0 ~ "PASS",
    !dag_check ~ "NEEDS REVIEW: Cycles detected",
    n_fail > 0 ~ "NEEDS REVIEW: Category mismatches detected",
    TRUE ~ "NEEDS REVIEW"
  )

  summary_stats <- tibble(
    metric = c(
      "total_pairs",
      "n_pass",
      "n_fail",
      "n_missing",
      "pass_rate_pct",
      "is_dag",
      "n_long_chains",
      "max_chain_length",
      "overall_verdict"
    ),
    value = c(
      as.character(n_total),
      as.character(n_pass),
      as.character(n_fail),
      as.character(n_missing),
      as.character(pass_rate_pct),
      as.character(dag_check),
      as.character(n_long_chains),
      as.character(if (exists("max_chain_length")) max_chain_length else 0),
      overall_verdict
    )
  )
}


# --- SECTION 6: WRITE XLSX OUTPUT ----

message("\n--- Writing multi-sheet workbook ---")

wb_out <- wb_workbook()

# Sheet 1: Pairwise Verification
wb_out$add_worksheet("Pairwise Verification")
if (exists("pairwise_output") && nrow(pairwise_output) > 0) {
  wb_out$add_data("Pairwise Verification", pairwise_output, start_row = 1, col_names = TRUE)
} else {
  wb_out$add_data("Pairwise Verification", verification, start_row = 1, col_names = TRUE)
}

# Sheet 2: Chain Analysis
wb_out$add_worksheet("Chain Analysis")
wb_out$add_data("Chain Analysis", chain_results, start_row = 1, col_names = TRUE)

# Sheet 3: Summary Statistics
wb_out$add_worksheet("Summary Statistics")
wb_out$add_data("Summary Statistics", summary_stats, start_row = 1, col_names = TRUE)

wb_out$save(OUTPUT_XLSX)

message(glue("  Wrote: {OUTPUT_XLSX}"))


# --- SECTION 7: CONSOLE SUMMARY ----

message("\n=== VERIFICATION COMPLETE ===\n")

if (!skip_graph_analysis) {
  message(glue("Total code pairs: {n_total}"))
  message(glue("  PASS: {n_pass} ({pass_rate_pct}%)"))
  message(glue("  FAIL: {n_fail}"))
  message(glue("  MISSING: {n_missing}"))
  message(glue("\nDAG check: {if (dag_check) 'PASS (no cycles)' else 'FAIL (cycles detected)'}"))
  message(glue("Long chains (>3 steps): {n_long_chains}"))
  if (exists("max_chain_length") && max_chain_length > 0) {
    message(glue("Max chain length: {max_chain_length}"))
  }
  message(glue("\nOverall verdict: {overall_verdict}\n"))
} else {
  message("No replaced-by mappings found in input file.")
  message("Verification report created with minimal structure.\n")
}
