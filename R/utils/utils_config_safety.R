# utils_config_safety.R
# ---------------------------------------------------------------------------
# Config-backup housekeeping helpers (Phase 197-06).
#
# Auto-sourced by R/00_config.R via the R/utils/*.R glob.
#
# Functions:
#   trim_config_bak(config_path, keep = 5L)
#     Deletes all but the most recent `keep` timestamped .bak files for
#     the given config path.  Call once after every successful config write
#     so the directory does not accumulate unbounded backups.
#
# Pattern expected by list.files():
#   <basename(config_path)>.<YYYYMMDD_HHMMSS>.bak
# ---------------------------------------------------------------------------

#' Keep the last N timestamped .bak files; delete older ones.
#'
#' @param config_path  Full path to the config file (e.g. here::here("R","00_config.R")).
#' @param keep         Number of most-recent .bak files to retain. Default 5.
#' @return invisible(NULL)
trim_config_bak <- function(config_path, keep = 5L) {
  dir  <- dirname(config_path)
  base <- basename(config_path)

  # Match only timestamped backups, not plain ".bak" files.
  pattern <- paste0("^", base, "\\.\\d{8}_\\d{6}\\.bak$")
  baks <- sort(
    list.files(dir, pattern = pattern, full.names = TRUE),
    decreasing = TRUE   # newest (lexicographically largest timestamp) first
  )

  if (length(baks) > keep) {
    old <- baks[(keep + 1L):length(baks)]
    removed <- file.remove(old)
    message(
      "[config_safety] Removed ", sum(removed), " old .bak file(s) for ", base
    )
  }

  invisible(NULL)
}
