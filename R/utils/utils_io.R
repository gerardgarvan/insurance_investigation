# ==============================================================================
# utils_io.R -- Shared I/O helpers for the PCORnet pipeline
# ==============================================================================
# Auto-sourced by R/00_config.R (D-04 glob).
#
# Functions
#   resolve_input()   Resolve a dated input file with optional env-var pin.
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
