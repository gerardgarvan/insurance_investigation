# ==============================================================================
# 161_death_sensitivity.R -- Grace-period sensitivity table and D1 reproduction check
# ==============================================================================
# [161-07 audit] Compliant: calls resolve_death_date() and death_sensitivity_table() directly.
# This script IS the canonical verification of the grace-period choice.
#
# Purpose:
#   Runs resolve_death_date() at N = 0, 30, 60, 90, 365 days to document the D1
#   choice (30-day grace period). Prints a reproduction check: the number of
#   decedents with post-death activity > 30 days must equal 261 (the diagnostic
#   count from R/161_diag_anchor_followup.R, run 2026-10-01, same cohort + cutoff).
#   Writes two CSVs to output/ for archival.
#
# Inputs:
#   - pcornet.duckdb: DEATH (ID, DEATH_DATE, DEATH_SOURCE), DIAGNOSIS, ENCOUNTER,
#     and all ACTIVITY_SOURCES tables
#
# Outputs:
#   - output/161_death_sensitivity.csv   (flag counts at N = 0, 30, 60, 90, 365)
#   - output/161_death_flags_n30.csv     (flag counts at N = 30 only)
#
# Dependencies:
#   - R/00_config.R (sources utils_activity.R, utils_death.R, utils_treatment.R)
#   - DBI, duckdb, dplyr, readr
#
# Usage (HiPerGator):
#   module load R/4.4.2
#   Rscript R/161_death_sensitivity.R
#
# ==============================================================================

source(here::here("R/00_config.R"))
library(DBI)
library(duckdb)
library(dplyr)
library(readr)

# ---------------------------------------------------------------------------
# 1. Open DuckDB via the shared helper so safe_table() / get_pcornet_table()
#    pick up pcornet_con and USE_DUCKDB = TRUE (raw dbConnect bypasses both)
# ---------------------------------------------------------------------------
con <- open_pcornet_con(read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

CUTOFF_DATE <- as.Date(Sys.getenv("HL_CUTOFF_DATE", "2025-12-31"))

# ---------------------------------------------------------------------------
# 2. Build HL cohort IDs using the same denominator as R/147
# ---------------------------------------------------------------------------
cohort_ids <- get_hl_any_dx_ids()
message(sprintf("HL cohort: %d patients", nrow(cohort_ids)))

# ---------------------------------------------------------------------------
# 3. Compute last observed activity using the shared definition (D4)
# ---------------------------------------------------------------------------
activity <- get_last_activity(con, cohort_ids, CUTOFF_DATE)
message(sprintf("Activity computed for %d patients", nrow(activity)))

# ---------------------------------------------------------------------------
# 4. Read DEATH rows for cohort patients
# ---------------------------------------------------------------------------
duckdb::duckdb_register(con, "cohort_ids_reg", cohort_ids)
on.exit(duckdb::duckdb_unregister(con, "cohort_ids_reg"), add = TRUE)

tbls      <- DBI::dbListTables(con)
death_tbl <- DBI::dbGetQuery(con, sprintf(
  "SELECT d.ID, d.DEATH_DATE, d.DEATH_SOURCE
     FROM %s d
     JOIN cohort_ids_reg c ON d.ID = c.ID",
  tbls[toupper(tbls) == "DEATH"][1]
)) |>
  dplyr::mutate(DEATH_DATE = as.Date(DEATH_DATE)) |>
  tibble::as_tibble()

message(sprintf("DEATH rows fetched: %d", nrow(death_tbl)))

# ---------------------------------------------------------------------------
# 5. Sensitivity table across grace periods (documents D1 choice)
# ---------------------------------------------------------------------------
sensitivity <- death_sensitivity_table(death_tbl, activity,
                                       grace_values = c(0L, 30L, 60L, 90L, 365L))
print(sensitivity)

readr::write_csv(sensitivity, here::here("output", "161_death_sensitivity.csv"))
message("Written: output/161_death_sensitivity.csv")

# ---------------------------------------------------------------------------
# 6. Reproduction check: must equal 261 (diagnostic count, 2026-10-01)
# ---------------------------------------------------------------------------
resolved_n30 <- resolve_death_date(death_tbl, activity, grace_days = 30L)
repro_count  <- sum(resolved_n30$post_death_activity_days > 30L)
message(sprintf(
  "Reproduction check (post_death_activity_days > 30): %d  [expected: 261]",
  repro_count))
if (repro_count != 261L) {
  warning(sprintf(
    "Reproduction check FAILED: got %d, expected 261. Trace definition mismatch before proceeding.",
    repro_count))
}

# ---------------------------------------------------------------------------
# 7. Flag counts at N = 30 to output (aggregate only; no patient-level data)
# ---------------------------------------------------------------------------
flags_n30 <- dplyr::count(resolved_n30, death_flag) |>
  dplyr::arrange(death_flag)
readr::write_csv(flags_n30, here::here("output", "161_death_flags_n30.csv"))
message("Written: output/161_death_flags_n30.csv")
