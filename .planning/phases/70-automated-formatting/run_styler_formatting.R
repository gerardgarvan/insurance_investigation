# ==============================================================================
# run_styler_formatting.R - Phase 70 styler execution script
# ==============================================================================
#
# Purpose:
#   Automated styler formatting workflow for Phase 70-01 Task 2.
#   Runs dry-run safety check, applies formatting if safe, and reports results.
#   This script should be run on HiPerGator where R and styler are available.
#
# Usage:
#   Rscript .planning/phases/70-automated-formatting/run_styler_formatting.R
#
# ==============================================================================

library(styler)

message(strrep("=", 60))
message("Phase 70: Styler Formatting Workflow")
message(strrep("=", 60))

# Set working directory to project root if needed
if (basename(getwd()) != "insurance_investigation") {
  if (file.exists("R/00_config.R")) {
    message("Already in project root")
  } else {
    stop("Must run from project root directory")
  }
}

# ==============================================================================
# STEP 1: Verify styler installation ----
# ==============================================================================

message("\n[Step 1] Verifying styler installation...")
if (!requireNamespace("styler", quietly = TRUE)) {
  stop("styler package not installed. Run: install.packages('styler')")
}
message("styler version: ", as.character(packageVersion("styler")))

# ==============================================================================
# STEP 2: Count header elements BEFORE formatting (baseline) ----
# ==============================================================================

message("\n[Step 2] Counting header elements (baseline)...")

# Count header borders (# ==============)
header_border_cmd <- 'grep -rc "^# ==============" R/ --include="*.R" 2>/dev/null | grep -v ":0$" | wc -l'
header_border_before <- as.integer(system(header_border_cmd, intern = TRUE))
message("Header borders (# ===...): ", header_border_before)

# Count section headers (SECTION.*----)
section_header_cmd <- 'grep -rc "SECTION.*----" R/ --include="*.R" 2>/dev/null | grep -v ":0$" | wc -l'
section_header_before <- as.integer(system(section_header_cmd, intern = TRUE))
message("Section headers (SECTION N: TITLE ----): ", section_header_before)

# ==============================================================================
# STEP 3: Run styler dry-run ----
# ==============================================================================

message("\n[Step 3] Running styler dry-run (preview only)...")

dry_results <- style_dir(
  path = "R",
  exclude_dirs = c("archive", "renv"),
  dry = "on"
)

n_changed <- sum(dry_results[["changed"]])
n_total <- nrow(dry_results)
changed_files <- dry_results[["file"]][dry_results[["changed"]]]

message("Files that would change: ", n_changed, " of ", n_total)
if (n_changed > 0) {
  message("\nChanged files:")
  for (f in changed_files) {
    message("  - ", f)
  }
}

# ==============================================================================
# STEP 4: Manual inspection prompt ----
# ==============================================================================

message("\n[Step 4] Safety check required...")
message("Before applying formatting, inspect the proposed changes:")
message("  1. Run: git diff R/00_config.R (or any changed file)")
message("  2. Look for changes to:")
message("     - Lines starting with # ===")
message("     - Lines ending with ----")
message("     - Box-style comment headers")
message("  3. If headers are damaged, add # styler: off / # styler: on markers")
message("  4. If changes are cosmetic (spacing only), proceed")

response <- readline(prompt = "\nProceed with formatting? (yes/no): ")

if (tolower(trimws(response)) != "yes") {
  message("\nFormatting aborted by user.")
  message("Re-run this script after fixing any issues.")
  quit(status = 0)
}

# ==============================================================================
# STEP 5: Apply formatting ----
# ==============================================================================

message("\n[Step 5] Applying styler formatting...")

apply_results <- style_dir(
  path = "R",
  exclude_dirs = c("archive", "renv"),
  dry = "off"
)

n_changed_applied <- sum(apply_results[["changed"]])
message("Files changed: ", n_changed_applied, " of ", nrow(apply_results))

# ==============================================================================
# STEP 6: Verify header preservation ----
# ==============================================================================

message("\n[Step 6] Verifying header preservation...")

header_border_after <- as.integer(system(header_border_cmd, intern = TRUE))
section_header_after <- as.integer(system(section_header_cmd, intern = TRUE))

message("Header borders: ", header_border_before, " -> ", header_border_after)
message("Section headers: ", section_header_before, " -> ", section_header_after)

if (header_border_after != header_border_before) {
  warning("Header border count CHANGED! (", header_border_before, " -> ", header_border_after, ")")
  warning("Phase 69 headers may be damaged. Review changes carefully.")
}

if (section_header_after != section_header_before) {
  warning("Section header count CHANGED! (", section_header_before, " -> ", section_header_after, ")")
  warning("RStudio section markers may be damaged. Review changes carefully.")
}

# ==============================================================================
# STEP 7: Verify archive exclusion ----
# ==============================================================================

message("\n[Step 7] Verifying R/archive/ exclusion...")

archive_changes_cmd <- 'git diff --name-only R/archive/ 2>/dev/null | wc -l'
archive_changes <- as.integer(system(archive_changes_cmd, intern = TRUE))

if (archive_changes > 0) {
  warning("R/archive/ files were modified! (", archive_changes, " files)")
  warning("Archive should be excluded. Check exclude_dirs parameter.")
} else {
  message("R/archive/ correctly excluded (no changes)")
}

# ==============================================================================
# STEP 8: Git commit instructions ----
# ==============================================================================

message("\n[Step 8] Next steps:")
message("  1. Review changes: git diff R/")
message("  2. If satisfied, stage and commit:")
message('     git add R/*.R R/utils/*.R')
message('     git commit --no-verify -m "style(70-01): apply styler auto-formatting to 75 R scripts"')
message("  3. Get commit hash and update .git-blame-ignore-revs:")
message('     HASH=$(git rev-parse HEAD)')
message('     echo "$HASH" >> .git-blame-ignore-revs')
message("  4. Commit the updated .git-blame-ignore-revs:")
message('     git add .git-blame-ignore-revs')
message('     git commit --no-verify -m "docs(70-01): add styler commit hash to .git-blame-ignore-revs"')

message("\n", strrep("=", 60))
message("Styler formatting complete!")
message(strrep("=", 60))
