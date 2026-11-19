# ==============================================================================
# utils_combo_audit.R -- pure helpers for Phase 214 (chemo combination change audit)
# ==============================================================================
# No I/O. Used by R/214_combo_change_audit.R and tests/testthat/test-214-combo-audit.R.
# Decision Q-214-01: the combination unit is the episode-level drug_names string,
# compared after normalisation (split ';', trim, alias map, dedupe, sort, rejoin).
# Decision Q-214-02: a blank drug_names row is kept as key "(blank)".
# Suppression reuses suppress_display() from utils_distance_cbc.R (1-10 -> "<11").
# ==============================================================================

COMBO_BLANK_KEY <- "(blank)"
COMBO_CAUSES <- c("a", "b", "c", "d", "e", "f", "g")

# Normalise a vector of raw drug_names strings to combination keys.
# canon_fn: alias map function (canonicalize_drug_name from R/00_config.R by default).
normalise_combo <- function(x, canon_fn = NULL) {
  if (is.null(canon_fn)) canon_fn <- get("canonicalize_drug_name", mode = "function")
  vapply(as.character(x), function(s) {
    if (is.na(s) || !nzchar(trimws(s))) return(COMBO_BLANK_KEY)
    tok <- trimws(strsplit(s, ";", fixed = TRUE)[[1]])
    tok <- tok[nzchar(tok)]
    if (length(tok) == 0L) return(COMBO_BLANK_KEY)
    tok <- unique(as.character(canon_fn(tok)))
    paste(sort(tok, method = "radix"), collapse = ";")
  }, character(1), USE.NAMES = FALSE)
}

# Split a normalised key into its drug set.
combo_drugs <- function(key) {
  if (is.na(key) || key == COMBO_BLANK_KEY) return(character())
  strsplit(key, ";", fixed = TRUE)[[1]]
}

# Classify combinations between an old and a new set of raw strings (A-214-06).
# Returns one row per distinct normalised key present on either side.
#   unchanged: some raw string is identical on both sides
#   label_only: key on both sides but no identical raw string
#   new / dropped: key on one side only
classify_combos <- function(old_raw, new_raw, canon_fn = NULL) {
  old_raw <- unique(as.character(old_raw)); new_raw <- unique(as.character(new_raw))
  old_key <- normalise_combo(old_raw, canon_fn); new_key <- normalise_combo(new_raw, canon_fn)
  keys <- sort(unique(c(old_key, new_key)), method = "radix")
  one <- function(k) {
    o <- old_raw[old_key == k]; n <- new_raw[new_key == k]
    status <- if (length(o) == 0L) "new" else if (length(n) == 0L) "dropped"
              else if (length(intersect(o, n)) > 0L) "unchanged" else "label_only"
    data.frame(status = status, combination_normalized = k,
               old_file_string = paste(o, collapse = " | "),
               new_file_string = paste(n, collapse = " | "),
               stringsAsFactors = FALSE)
  }
  do.call(rbind, lapply(keys, one))
}

# Match old and new episodes (A-214-07). Both inputs: patient_id, episode_start,
# episode_stop, drug_key (normalised). Returns pairs plus pair_type:
# "1:1", "1:n" (one old, several new), "n:1" (several old, one new), "n:n".
# Old episodes with no overlapping new episode, and vice versa, are returned by
# attribute_cause() via the patient-level checks, not here.
match_episodes <- function(old, new) {
  if (nrow(old) == 0L || nrow(new) == 0L) {
    return(data.frame(old_row = integer(), new_row = integer(), pair_type = character(),
                      stringsAsFactors = FALSE))
  }
  old$old_row <- seq_len(nrow(old)); new$new_row <- seq_len(nrow(new))
  j <- merge(old[, c("patient_id", "old_row", "episode_start", "episode_stop")],
             new[, c("patient_id", "new_row", "episode_start", "episode_stop")],
             by = "patient_id", suffixes = c("_old", "_new"))
  j <- j[j$episode_start_old <= j$episode_stop_new & j$episode_start_new <= j$episode_stop_old, ,
         drop = FALSE]
  if (nrow(j) == 0L) {
    return(data.frame(old_row = integer(), new_row = integer(), pair_type = character(),
                      stringsAsFactors = FALSE))
  }
  n_new_per_old <- table(j$old_row); n_old_per_new <- table(j$new_row)
  multi_new <- as.integer(n_new_per_old[as.character(j$old_row)]) > 1L
  multi_old <- as.integer(n_old_per_new[as.character(j$new_row)]) > 1L
  j$pair_type <- ifelse(multi_new & multi_old, "n:n",
                 ifelse(multi_new, "1:n", ifelse(multi_old, "n:1", "1:1")))
  j[, c("old_row", "new_row", "pair_type")]
}

# Cause for one matched/unmatched episode (A-214-07 precedence e, d, f, a, b, c, g).
#   old_key / new_key: normalised keys of the paired episodes (NA when unpaired)
#   patient_in_old / patient_in_new: patient present in each Gantt file
#   pair_type: from match_episodes(); NA when unpaired
attribute_cause <- function(old_key, new_key, patient_in_old, patient_in_new, pair_type = NA_character_) {
  if (!patient_in_new) return("e")
  if (!patient_in_old) return("d")
  if (!is.na(pair_type) && pair_type != "1:1") return("f")
  if (is.na(old_key) || is.na(new_key)) return("g")
  od <- combo_drugs(old_key); nd <- combo_drugs(new_key)
  if (setequal(od, nd)) return("a")
  if (all(od %in% nd) && length(nd) > length(od)) return("b")
  if (all(nd %in% od) && length(od) > length(nd)) return("c")
  "g"
}

# Drug-difference fields for cause (b): added drugs, as a ";"-joined string.
combo_added_drugs <- function(old_key, new_key) {
  paste(setdiff(combo_drugs(new_key), combo_drugs(old_key)), collapse = ";")
}

# Roll up cause per combination (A-214-09). df: combination_normalized, cause (one
# row per affected episode). Returns primary_cause (most frequent; tie -> alphabetical)
# and one n_<cause> column per cause a..g.
rollup_cause <- function(df) {
  keys <- sort(unique(df$combination_normalized), method = "radix")
  rows <- lapply(keys, function(k) {
    cs <- df$cause[df$combination_normalized == k]
    tab <- table(factor(cs, levels = COMBO_CAUSES))
    out <- data.frame(combination_normalized = k,
                      primary_cause = names(tab)[which.max(as.integer(tab))],
                      stringsAsFactors = FALSE)
    for (cz in COMBO_CAUSES) out[[paste0("n_", cz)]] <- as.integer(tab[[cz]])
    out
  })
  if (length(rows) == 0L) return(data.frame())
  do.call(rbind, rows)
}

# Team-copy suppression: 1-10 -> "<11" on every named count column (reuses suppress_display).
suppress_combo_counts <- function(df, count_cols) {
  for (cc in intersect(count_cols, names(df))) df[[cc]] <- suppress_display(as.integer(df[[cc]]))
  df
}
