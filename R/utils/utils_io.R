# ==============================================================================
# utils_io.R -- Shared I/O helpers for the PCORnet pipeline
# ==============================================================================
# Auto-sourced by R/00_config.R (D-04 glob).
#
# Functions
#   resolve_input()          Resolve a dated input file with optional env-var pin.
#   versioned_output_path()  Return a dated output path, versioning if file exists.
#
# ==============================================================================

#' Resolve a dated input file path with optional env-var pin.
#'
#' Checks the env var \code{env_var} first. If set, that path is used and
#' \code{(pinned=TRUE)} is logged. If unset, all files in \code{dir} matching
#' \code{pattern} are sorted: files with a \code{_vN} version suffix are ranked
#' by numeric N (so \code{_v10} > \code{_v2}); remaining files are ranked
#' alphabetically (descending), which correctly orders YYYYMMDD date suffixes.
#' The first candidate is used and \code{(pinned=FALSE)} is logged.
#'
#' @param dir       Directory to search (passed to \code{list.files()}).
#' @param pattern   Regex pattern matching the dated files.
#' @param env_var   Name of the env var that overrides the path
#'                  (e.g. \code{"R183_R122_RDS"}).
#' @param label     Short label for messages (defaults to \code{env_var}).
#' @return          Absolute file path character(1). Stops if not found.
#'
#' @examples
#' \dontrun{
#' enc_dist_path <- resolve_input(
#'   dir     = CONFIG$output_dir,
#'   pattern = "^encounter_distance.*\\.rds$",
#'   env_var = "R163_R122_RDS",
#'   label   = "enc_distance"
#' )
#' }
resolve_input <- function(dir, pattern, env_var, label = env_var) {
  override <- Sys.getenv(env_var, unset = "")
  if (nchar(override) > 0) {
    path <- override
    if (!file.exists(path))
      stop("[resolve_input] ", label, ": pinned path not found: ", path)
    message("[resolve_input] ", label, " (pinned=TRUE): ", path)
    return(invisible(path))
  }

  candidates <- list.files(dir, pattern = pattern, full.names = TRUE)

  if (length(candidates) == 0L)
    stop("[resolve_input] ", label, ": no file matching '", pattern,
         "' in ", dir)

  # Version-aware sort: _v10 > _v2 (numeric); fall back to alphabetical desc
  # for YYYYMMDD-suffixed files.
  ver_key <- function(f) {
    m <- regmatches(f, regexpr("_v(\\d+)(\\.\\w+)?$", f))
    if (length(m) == 0L || identical(m, character(0)) || m == "")
      return(0L)
    as.integer(sub("_v(\\d+).*", "\\1", m))
  }

  if (length(candidates) > 1L) {
    has_ver <- vapply(candidates, ver_key, integer(1L))
    if (any(has_ver > 0L)) {
      # Mixed: sort versioned files by numeric version desc, rest alphabetically
      candidates <- candidates[order(has_ver, candidates, decreasing = TRUE)]
    } else {
      # Date-stamped files: alphabetical descending gives most recent
      candidates <- sort(candidates, decreasing = TRUE)
    }
  }

  path <- candidates[[1L]]
  message("[resolve_input] ", label, " (pinned=FALSE): ", path)
  invisible(path)
}

#' Return a dated output path, incrementing _v2/_v3... if the base path exists.
#'
#' Controlled by env var VERSIONED_OUTPUT (default "TRUE").
#' Set VERSIONED_OUTPUT=FALSE to disable versioning (stop() if file exists instead).
#'
#' @param dir       Output directory.
#' @param stem      File stem WITHOUT date suffix (e.g. "distance_cbc_association").
#' @param ext       Extension including dot (e.g. ".xlsx").
#' @param run_date  Date string (default: today in YYYYMMDD).
#' @return          Full path string.
versioned_output_path <- function(dir, stem, ext,
                                  run_date = format(Sys.Date(), "%Y%m%d")) {
  versioning <- !identical(Sys.getenv("VERSIONED_OUTPUT", unset = "TRUE"), "FALSE")
  base <- file.path(dir, paste0(stem, "_", run_date, ext))
  if (!file.exists(base)) return(base)

  if (!versioning)
    stop("[versioned_output_path] '", basename(base), "' already exists. ",
         "Set VERSIONED_OUTPUT=TRUE (or unset) to enable auto-versioning.")

  v <- 2L
  repeat {
    candidate <- file.path(dir, paste0(stem, "_", run_date, "_v", v, ext))
    if (!file.exists(candidate)) return(candidate)
    v <- v + 1L
  }
}

#' Compute a reproducible fingerprint of a cohort data frame.
#'
#' Canonical method: sort unique IDs as character, write to a tempfile,
#' compute md5sum with tools::md5sum(). This matches the baseline stored in
#' output/baselines/pre_phaseA_*/cohort_final_fingerprint.rds.
#'
#' @param cohort Data frame with an ID column.
#' @return Named list: rows (int), ids (int), cols (chr), id_md5 (chr).
cohort_fingerprint <- function(cohort) {
  ids    <- sort(unique(as.character(cohort$ID)))
  f      <- tempfile()
  on.exit(unlink(f), add = TRUE)
  writeLines(ids, f)
  id_md5 <- unname(tools::md5sum(f))
  cols   <- paste(sort(names(cohort)), collapse = ",")
  list(rows = nrow(cohort), ids = length(ids), cols = cols, id_md5 = id_md5)
}
