# ==============================================================================
# 99_claude_diagnostics.R -- Generate comprehensive data profile for Claude
# ==============================================================================
#
# Produces a single text file (output/claude_diagnostics.txt) containing all
# the metadata Claude needs to write correct, performant R code:
#
#   1. Row counts and memory footprint per table
#   2. Distinct patient counts and fan-out ratios per table
#   3. Column types as actually loaded (post-parsing)
#   4. glimpse() of key tables (ENCOUNTER, DIAGNOSIS, TUMOR_REGISTRY_ALL)
#   5. Key column cardinality (join planning)
#   6. Payer code distribution (ENCOUNTER)
#   7. Date parsing success summary
#   8. Full pipeline console output capture (load + harmonize + cohort build)
#
# HIPAA: All patient counts 1-10 are suppressed as "<11"
#
# Usage (on HiPerGator):
#   source("R/99_claude_diagnostics.R")
#   # Then download output/claude_diagnostics.txt and paste to Claude
#
# ==============================================================================

# ==============================================================================
# SETUP: Redirect all output to text file
# ==============================================================================

output_dir <- "output"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_file <- file.path(output_dir, "claude_diagnostics.txt")

# Open sink for both stdout and messages
sink_con <- file(output_file, open = "wt")
sink(sink_con, type = "output")
sink(sink_con, type = "message")

# Helper: HIPAA-safe count (suppresses 1-10)
safe_count <- function(n) {
  if (is.na(n)) return("NA")
  if (n >= 1 & n <= 10) return("<11")
  format(n, big.mark = ",")
}

# Helper: section header
section <- function(title) {
  cat("\n", strrep("=", 70), "\n", sep = "")
  cat(title, "\n")
  cat(strrep("=", 70), "\n\n")
}

# Helper: subsection header
subsection <- function(title) {
  cat("\n--- ", title, " ", strrep("-", max(1, 60 - nchar(title))), "\n\n", sep = "")
}

cat("CLAUDE DIAGNOSTICS REPORT\n")
cat("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "\n")
cat("R version:", R.version.string, "\n")
cat("Platform:", R.version$platform, "\n")
cat("Working directory:", getwd(), "\n")
cat(strrep("=", 70), "\n")

# ==============================================================================
# SECTION 1: Load data (captures all load messages)
# ==============================================================================

section("1. DATA LOADING (console output captured)")

# Force fresh load to capture all messages
if (exists("pcornet", envir = .GlobalEnv)) rm(pcornet, envir = .GlobalEnv)
source("R/00_config.R")

# Time the full load
load_start <- Sys.time()
source("R/01_load_pcornet.R")
load_end <- Sys.time()

cat("\nTotal load time:", format(load_end - load_start, digits = 3), "\n")

# ==============================================================================
# SECTION 2: Table dimensions and memory
# ==============================================================================

section("2. TABLE DIMENSIONS AND MEMORY")

cat(sprintf("%-25s %12s %8s %12s %15s\n",
            "Table", "Rows", "Cols", "Patients", "Memory (MB)"))
cat(strrep("-", 75), "\n")

total_rows <- 0
total_mem <- 0

for (tbl_name in names(pcornet)) {
  df <- pcornet[[tbl_name]]
  if (is.null(df)) {
    cat(sprintf("%-25s %12s\n", tbl_name, "NULL (missing)"))
    next
  }

  n_rows <- nrow(df)
  n_cols <- ncol(df)
  mem_mb <- as.numeric(object.size(df)) / 1024^2

  # Patient count (all tables have ID column)
  if ("ID" %in% names(df)) {
    n_patients <- dplyr::n_distinct(df$ID)
    patients_str <- safe_count(n_patients)
  } else {
    patients_str <- "no ID col"
  }

  cat(sprintf("%-25s %12s %8d %12s %12.1f MB\n",
              tbl_name,
              format(n_rows, big.mark = ","),
              n_cols,
              patients_str,
              mem_mb))

  total_rows <- total_rows + n_rows
  total_mem <- total_mem + mem_mb
}

cat(strrep("-", 75), "\n")
cat(sprintf("%-25s %12s %8s %12s %12.1f MB\n",
            "TOTAL", format(total_rows, big.mark = ","), "", "", total_mem))

# ==============================================================================
# SECTION 3: Fan-out ratios (rows per patient)
# ==============================================================================

section("3. FAN-OUT RATIOS (rows per patient)")

cat("How many rows per patient in each table (affects join strategy):\n\n")
cat(sprintf("%-25s %12s %12s %12s %12s\n",
            "Table", "Patients", "Rows", "Mean", "Max"))
cat(strrep("-", 75), "\n")

for (tbl_name in names(pcornet)) {
  df <- pcornet[[tbl_name]]
  if (is.null(df) || !"ID" %in% names(df)) next

  n_patients <- dplyr::n_distinct(df$ID)
  n_rows <- nrow(df)
  rows_per_patient <- df %>%
    dplyr::count(ID) %>%
    dplyr::pull(n)

  cat(sprintf("%-25s %12s %12s %12.1f %12s\n",
              tbl_name,
              safe_count(n_patients),
              format(n_rows, big.mark = ","),
              mean(rows_per_patient),
              format(max(rows_per_patient), big.mark = ",")))
}

# ==============================================================================
# SECTION 4: Column types as loaded
# ==============================================================================

section("4. COLUMN TYPES (as loaded, post-parsing)")

for (tbl_name in names(pcornet)) {
  df <- pcornet[[tbl_name]]
  if (is.null(df)) next

  subsection(paste0(tbl_name, " (", ncol(df), " cols)"))

  col_classes <- sapply(df, function(x) paste(class(x), collapse = "/"))
  for (i in seq_along(col_classes)) {
    cat(sprintf("  %-40s %s\n", names(col_classes)[i], col_classes[i]))
  }
}

# ==============================================================================
# SECTION 5: glimpse() of key tables
# ==============================================================================

section("5. GLIMPSE OF KEY TABLES")

key_tables <- c("ENCOUNTER", "DIAGNOSIS", "ENROLLMENT", "DEMOGRAPHIC",
                "PROCEDURES", "TUMOR_REGISTRY_ALL")

for (tbl_name in key_tables) {
  df <- pcornet[[tbl_name]]
  if (is.null(df)) next

  subsection(tbl_name)
  # Use str() which works better in sink context than glimpse()
  str(df, give.attr = FALSE)
  cat("\n")
}

# ==============================================================================
# SECTION 6: Key column cardinality (join planning)
# ==============================================================================

section("6. KEY COLUMN CARDINALITY (for join planning)")

cat("Distinct values in columns commonly used for joins/filters:\n\n")

cardinality_checks <- list(
  list(tbl = "ENCOUNTER",  cols = c("ID", "ENCOUNTERID", "ENC_TYPE", "PAYER_TYPE_PRIMARY",
                                     "PAYER_TYPE_SECONDARY", "SOURCE")),
  list(tbl = "DIAGNOSIS",  cols = c("ID", "ENCOUNTERID", "DX_TYPE", "ENC_TYPE", "SOURCE")),
  list(tbl = "ENROLLMENT", cols = c("ID", "ENR_BASIS", "SOURCE")),
  list(tbl = "PROCEDURES", cols = c("ID", "ENCOUNTERID", "PX_TYPE", "SOURCE")),
  list(tbl = "PRESCRIBING", cols = c("ID", "ENCOUNTERID", "SOURCE")),
  list(tbl = "DEMOGRAPHIC", cols = c("ID", "SEX", "RACE", "HISPANIC", "SOURCE")),
  list(tbl = "TUMOR_REGISTRY_ALL", cols = c("ID", "SOURCE"))
)

for (check in cardinality_checks) {
  df <- pcornet[[check$tbl]]
  if (is.null(df)) next

  subsection(check$tbl)
  for (col in check$cols) {
    if (!col %in% names(df)) next
    n_distinct_val <- dplyr::n_distinct(df[[col]], na.rm = FALSE)
    n_na <- sum(is.na(df[[col]]))
    cat(sprintf("  %-30s %10s distinct  (%s NA)\n",
                col,
                safe_count(n_distinct_val),
                safe_count(n_na)))
  }
}

# ==============================================================================
# SECTION 7: Patient ID overlap across tables
# ==============================================================================

section("7. PATIENT ID OVERLAP ACROSS TABLES")

cat("Which patients appear in which tables (Venn-style):\n\n")

# Collect patient ID sets
id_sets <- list()
for (tbl_name in names(pcornet)) {
  df <- pcornet[[tbl_name]]
  if (is.null(df) || !"ID" %in% names(df)) next
  id_sets[[tbl_name]] <- unique(df$ID)
}

# All unique patients across all tables
all_patients <- unique(unlist(id_sets))
cat("Total unique patients across all tables:", safe_count(length(all_patients)), "\n\n")

# Pairwise overlap with key tables
ref_tables <- c("DEMOGRAPHIC", "ENROLLMENT", "ENCOUNTER", "DIAGNOSIS")
for (ref in ref_tables) {
  if (!ref %in% names(id_sets)) next
  ref_ids <- id_sets[[ref]]
  cat(sprintf("Patients in %-20s: %s\n", ref, safe_count(length(ref_ids))))
  for (tbl_name in names(id_sets)) {
    if (tbl_name == ref) next
    overlap <- length(intersect(ref_ids, id_sets[[tbl_name]]))
    only_ref <- length(setdiff(ref_ids, id_sets[[tbl_name]]))
    cat(sprintf("  + %-24s overlap: %10s  |  in %s only: %s\n",
                tbl_name,
                safe_count(overlap),
                ref,
                safe_count(only_ref)))
  }
  cat("\n")
}

# ==============================================================================
# SECTION 8: Payer code distribution (raw encounter-level)
# ==============================================================================

section("8. PAYER CODE DISTRIBUTION (raw, encounter-level)")

if (!is.null(pcornet$ENCOUNTER)) {
  enc <- pcornet$ENCOUNTER

  subsection("PAYER_TYPE_PRIMARY (top 30)")
  primary_freq <- enc %>%
    dplyr::count(PAYER_TYPE_PRIMARY, sort = TRUE) %>%
    head(30)
  for (i in seq_len(nrow(primary_freq))) {
    val <- ifelse(is.na(primary_freq$PAYER_TYPE_PRIMARY[i]), "[NA]",
                  primary_freq$PAYER_TYPE_PRIMARY[i])
    cat(sprintf("  %-15s %s (%4.1f%%)\n",
                val,
                safe_count(primary_freq$n[i]),
                100 * primary_freq$n[i] / nrow(enc)))
  }

  subsection("PAYER_TYPE_SECONDARY (top 30)")
  secondary_freq <- enc %>%
    dplyr::count(PAYER_TYPE_SECONDARY, sort = TRUE) %>%
    head(30)
  for (i in seq_len(nrow(secondary_freq))) {
    val <- ifelse(is.na(secondary_freq$PAYER_TYPE_SECONDARY[i]), "[NA]",
                  secondary_freq$PAYER_TYPE_SECONDARY[i])
    cat(sprintf("  %-15s %s (%4.1f%%)\n",
                val,
                safe_count(secondary_freq$n[i]),
                100 * secondary_freq$n[i] / nrow(enc)))
  }
}

# ==============================================================================
# SECTION 9: Date parsing success summary
# ==============================================================================

section("9. DATE PARSING SUCCESS RATES")

cat("For each date column: how many parsed as Date vs remained NA:\n\n")
cat(sprintf("%-25s %-30s %10s %10s %8s\n",
            "Table", "Column", "Parsed", "NA", "NA%"))
cat(strrep("-", 85), "\n")

for (tbl_name in names(pcornet)) {
  df <- pcornet[[tbl_name]]
  if (is.null(df)) next

  date_cols <- names(df)[sapply(df, inherits, "Date")]
  if (length(date_cols) == 0) next

  for (col in date_cols) {
    # Skip _VALID flag columns
    if (grepl("_VALID$", col)) next
    n_total <- length(df[[col]])
    n_na <- sum(is.na(df[[col]]))
    n_parsed <- n_total - n_na
    pct_na <- round(100 * n_na / n_total, 1)
    cat(sprintf("%-25s %-30s %10s %10s %7.1f%%\n",
                tbl_name, col,
                safe_count(n_parsed),
                safe_count(n_na),
                pct_na))
  }
}

# ==============================================================================
# SECTION 10: Pipeline execution (harmonize + cohort build)
# ==============================================================================

section("10. PIPELINE EXECUTION (payer harmonization + cohort build)")

cat("Running 02_harmonize_payer.R...\n\n")
tryCatch({
  source("R/02_harmonize_payer.R")
  cat("\nPayer harmonization complete.\n")
}, error = function(e) {
  cat("\nERROR in 02_harmonize_payer.R:", conditionMessage(e), "\n")
})

cat("\n\nRunning 04_build_cohort.R...\n\n")
tryCatch({
  source("R/04_build_cohort.R")
  cat("\nCohort build complete.\n")
}, error = function(e) {
  cat("\nERROR in 04_build_cohort.R:", conditionMessage(e), "\n")
})

# ==============================================================================
# SECTION 11: Cohort summary (if built)
# ==============================================================================

section("11. COHORT SUMMARY (post-build)")

if (exists("hl_cohort", envir = .GlobalEnv)) {
  cat("hl_cohort dimensions:", nrow(hl_cohort), "rows x", ncol(hl_cohort), "cols\n\n")

  subsection("Column types")
  col_classes <- sapply(hl_cohort, function(x) paste(class(x), collapse = "/"))
  for (i in seq_along(col_classes)) {
    cat(sprintf("  %-40s %s\n", names(col_classes)[i], col_classes[i]))
  }

  # Treatment flag distribution
  treatment_cols <- c("HAD_CHEMO", "HAD_RADIATION", "HAD_SCT")
  available_tx <- intersect(treatment_cols, names(hl_cohort))
  if (length(available_tx) > 0) {
    subsection("Treatment flags")
    for (col in available_tx) {
      freq <- table(hl_cohort[[col]], useNA = "ifany")
      cat(sprintf("  %s:\n", col))
      for (val in names(freq)) {
        display_val <- ifelse(is.na(val), "[NA]", val)
        cat(sprintf("    %-10s %s\n", display_val, safe_count(freq[val])))
      }
    }
  }

  # Payer distribution
  payer_cols <- c("PAYER_CATEGORY_PRIMARY", "PAYER_AT_FIRST_DX",
                  "PAYER_AT_CHEMO", "PAYER_AT_RADIATION", "PAYER_AT_SCT")
  available_payer <- intersect(payer_cols, names(hl_cohort))
  if (length(available_payer) > 0) {
    subsection("Payer category distribution")
    for (col in available_payer) {
      freq <- sort(table(hl_cohort[[col]], useNA = "ifany"), decreasing = TRUE)
      cat(sprintf("  %s:\n", col))
      for (val in names(freq)) {
        display_val <- ifelse(is.na(val), "[NA]", val)
        cat(sprintf("    %-25s %s\n", display_val, safe_count(freq[val])))
      }
      cat("\n")
    }
  }
} else {
  cat("hl_cohort not found in environment (cohort build may have failed).\n")
}

# ==============================================================================
# SECTION 12: Attrition log (if available)
# ==============================================================================

section("12. ATTRITION LOG")

if (exists("attrition_log", envir = .GlobalEnv) && nrow(attrition_log) > 0) {
  cat(sprintf("%-45s %10s %10s %10s %8s\n",
              "Step", "Before", "After", "Excluded", "Excl%"))
  cat(strrep("-", 85), "\n")
  for (i in seq_len(nrow(attrition_log))) {
    row <- attrition_log[i, ]
    cat(sprintf("%-45s %10s %10s %10s %7.1f%%\n",
                row$step,
                safe_count(row$n_before),
                safe_count(row$n_after),
                safe_count(row$n_excluded),
                row$pct_excluded))
  }
} else {
  cat("No attrition log found.\n")
}

# ==============================================================================
# SECTION 13: Warnings and session info
# ==============================================================================

section("13. WARNINGS AND SESSION INFO")

subsection("Accumulated warnings")
w <- warnings()
if (length(w) > 0) {
  # Limit to first 50 to keep file manageable
  for (i in seq_len(min(length(w), 50))) {
    cat(sprintf("  [%d] %s\n", i, names(w)[i]))
  }
  if (length(w) > 50) {
    cat(sprintf("  ... and %d more warnings\n", length(w) - 50))
  }
} else {
  cat("  No warnings.\n")
}

subsection("Loaded packages")
pkgs <- sessionInfo()$otherPkgs
if (!is.null(pkgs)) {
  for (pkg in pkgs) {
    cat(sprintf("  %-20s %s\n", pkg$Package, pkg$Version))
  }
}

subsection("Total memory usage")
cat("  R process memory:", format(object.size(as.environment(.GlobalEnv)), units = "MB"), "\n")
cat("  gc() output:\n")
print(gc())

# ==============================================================================
# CLOSE SINK
# ==============================================================================

sink(type = "message")
sink(type = "output")
close(sink_con)

message("Done! Diagnostics written to: ", output_file)
message("File size: ", format(file.size(output_file), big.mark = ","), " bytes")
message("\nCopy this file and paste its contents to Claude.")
