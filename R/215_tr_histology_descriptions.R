# ==============================================================================
# 215_tr_histology_descriptions.R -- Phase 215: tumor-registry histology code descriptions
# ==============================================================================
# Gives every distinct histology code in TUMOR_REGISTRY_ALL a description from the
# ICD-O-3 term list (data/reference), with ICD-O-2 conversion and an extract fallback.
# Read-only; does not touch ICD_CODES$hl_histology / nhl_histology or any cohort rule.
#
# Outputs (counts 1-10 shown as "<11"; no patient IDs):
#   output/tr_histology_code_descriptions.csv  one row per distinct raw_code
#   output/tr_histology_unmatched.csv          codes with no description
#
# Input names: HISTOLOGICAL_TYPE (TR1), MORPH (TR2/TR3) are from
# build_tr_lymphoma_flags(). Site columns SITE_CODE (TR1) / SITE (TR2/TR3) and
# HISTOLOGICAL_TYPE_DESCRIPTION / SITE_CODE_DESCRIPTION (TR1) are UNVERIFIED -- taken
# from the Phase 84 fixture plans; no .planning/schemas probe lists them. Each is
# optional here: the script logs which are present and continues without the absent ones.
#
# Pinned inputs: reference files from CONFIG (icdo3_histology_terms_path,
# icdo2_to_icdo3_path); script stops if either is missing.
#
# Run interactively on HiPerGator:
#   module load R/4.5; R --no-save
#   source("R/215_tr_histology_descriptions.R", local = new.env(parent = globalenv()))
# ==============================================================================

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(glue) })
source("R/00_config.R")
message("=== R/215: Tumor registry histology descriptions ===\n")

# --- column-name constants (UNVERIFIED except code columns; see header) --------------
COL_ID <- "ID"; COL_SRC <- "SOURCE"
COL_CODES <- c("HISTOLOGICAL_TYPE", "MORPH")
COL_SITES <- c("SITE_CODE", "SITE")
COL_HDESC <- "HISTOLOGICAL_TYPE_DESCRIPTION"
COL_SDESC <- "SITE_CODE_DESCRIPTION"
TRUNC_LEN <- 74L                       # extract descriptions at/above this length are truncated
OUT_DESC  <- file.path(CONFIG$output_dir, "tr_histology_code_descriptions.csv")
OUT_UNM   <- file.path(CONFIG$output_dir, "tr_histology_unmatched.csv")

suppress <- function(n) ifelse(is.na(n), NA_character_,
                               ifelse(n >= 1L & n <= 10L, "<11", as.character(n)))

lk <- load_histology_lookup()          # stops if a reference file is missing

# --- load registry columns (one connection, closed immediately) -----------------------
open_pcornet_con()
tr_tbl <- get_pcornet_table("TUMOR_REGISTRY_ALL")
tr_names <- colnames(tr_tbl)
present <- function(x) x[x %in% tr_names]
message(glue("[R215] columns present: codes={paste(present(COL_CODES), collapse='/')} ",
             "sites={paste(present(COL_SITES), collapse='/')} ",
             "hist_desc={COL_HDESC %in% tr_names} site_desc={COL_SDESC %in% tr_names}"))
if (length(present(COL_CODES)) == 0L) {
  close_pcornet_con()
  stop("[R215] TUMOR_REGISTRY_ALL has neither HISTOLOGICAL_TYPE nor MORPH.")
}
sel <- c(present(c(COL_ID, COL_SRC)), present(COL_CODES), present(COL_SITES),
         present(c(COL_HDESC, COL_SDESC)))
tr <- tr_tbl |> select(all_of(sel)) |> collect()
close_pcornet_con()
message(glue("[R215] TUMOR_REGISTRY_ALL rows: {nrow(tr)}; distinct IDs: {n_distinct(tr[[COL_ID]])}"))

if (COL_SDESC %in% names(tr)) {
  mx <- max(nchar(tr[[COL_SDESC]]), na.rm = TRUE)
  message(glue("[R215] max length of {COL_SDESC}: {mx} (rows at max: {sum(nchar(tr[[COL_SDESC]]) == mx, na.rm = TRUE)})"))
}

# --- stack the code columns into raw_code (as build_tr_lymphoma_flags does) ------------
tr$.site <- if (length(present(COL_SITES)) > 0L) {
  do.call(dplyr::coalesce, lapply(present(COL_SITES), function(s) as.character(tr[[s]])))
} else NA_character_
if (!(COL_HDESC %in% names(tr))) tr[[COL_HDESC]] <- NA_character_
if (!(COL_SRC %in% names(tr))) tr[[COL_SRC]] <- NA_character_
tr <- tr |> mutate(hdesc = as.character(.data[[COL_HDESC]]))

stacked <- tr |>
  select(all_of(c(COL_ID, COL_SRC)), .site, hdesc, all_of(present(COL_CODES))) |>
  mutate(across(all_of(present(COL_CODES)), as.character)) |>
  pivot_longer(cols = all_of(present(COL_CODES)), names_to = "code_col", values_to = "raw_code") |>
  filter(!is.na(raw_code) & nzchar(trimws(raw_code))) |>
  # the extract description belongs to HISTOLOGICAL_TYPE only
  mutate(hdesc = if_else(code_col == "HISTOLOGICAL_TYPE", hdesc, NA_character_))
n_stacked <- nrow(stacked)
message(glue("[R215] stacked non-missing code values: {n_stacked}; distinct raw_code: {n_distinct(stacked$raw_code)}"))

# --- describe distinct (raw_code, site) pairs, join back (row count must not change) ---
pairs <- stacked |> distinct(raw_code, .site)
desc <- describe_histology(pairs$raw_code, pairs$.site, lookup = lk)
stopifnot(nrow(desc) == nrow(pairs))
pairs <- bind_cols(pairs, desc |> select(-raw_code))
st2 <- stacked |> left_join(pairs, by = c("raw_code", ".site"), relationship = "many-to-one")
stopifnot(nrow(st2) == n_stacked)

# --- one row per raw_code: modal site-resolved description -----------------------------
site_dep <- unique(lk$conv$icdo2_code5[duplicated(lk$conv$icdo2_code5) |
                                         duplicated(lk$conv$icdo2_code5, fromLast = TRUE)])
modal <- st2 |>
  count(raw_code, hist4, behavior, icdo3_code, description, desc_source, match_level, name = "n") |>
  arrange(raw_code, desc(n)) |>
  group_by(raw_code) |>
  mutate(n_variants = n()) |>
  slice(1L) |>
  ungroup() |>
  select(-n)

# --- extract fallback for unmatched codes (D-02, D-08) ---------------------------------
fb <- st2 |>
  filter(!is.na(hdesc), nchar(hdesc) < TRUNC_LEN, nzchar(trimws(hdesc))) |>
  count(raw_code, hdesc, name = "n") |>
  arrange(raw_code, desc(n)) |>
  group_by(raw_code) |> slice(1L) |> ungroup() |>
  select(raw_code, fb_desc = hdesc)
res <- modal |>
  left_join(fb, by = "raw_code", relationship = "one-to-one") |>
  mutate(
    use_fb      = desc_source == "unmatched" & !is.na(fb_desc),
    description = if_else(use_fb, fb_desc, description),
    desc_source = if_else(use_fb, "extract_fallback", desc_source)
  ) |>
  select(-fb_desc, -use_fb)

# --- counts per code: rows, patients, by SOURCE ----------------------------------------
cnt <- st2 |>
  group_by(raw_code) |>
  summarise(rows_n = n(), patients_n = n_distinct(.data[[COL_ID]]), .groups = "drop")
by_src <- st2 |>
  mutate(.src = coalesce(as.character(.data[[COL_SRC]]), "(none)")) |>
  group_by(raw_code, .src) |>
  summarise(n = n(), .groups = "drop") |>
  mutate(n = suppress(n)) |>
  pivot_wider(names_from = .src, values_from = n, names_prefix = "rows_")

out <- res |>
  mutate(converted_code = if_else(desc_source == "icdo3_via_icdo2_conversion", icdo3_code, NA_character_),
         site_dependent = raw_code %in% site_dep) |>
  left_join(cnt, by = "raw_code", relationship = "one-to-one") |>
  left_join(by_src, by = "raw_code", relationship = "one-to-one") |>
  arrange(desc(rows_n))
out <- out |>
  mutate(rows_all_sources = suppress(rows_n), patients = suppress(patients_n)) |>
  select(raw_code, hist4, behavior, converted_code, icdo3_code, description, desc_source,
         match_level, site_dependent, n_variants, rows_all_sources, patients,
         starts_with("rows_"), -rows_n)

# --- checks and log --------------------------------------------------------------------
stopifnot(!anyDuplicated(out$raw_code))
stopifnot(sum(cnt$rows_n) == n_stacked)
n75 <- sum(nchar(out$description) == 75L & out$desc_source == "extract_fallback", na.rm = TRUE)  # truncation check (term-list labels may legitimately be long)
shares <- out |> count(desc_source) |> mutate(pct = round(100 * n / sum(n), 1))
for (i in seq_len(nrow(shares)))
  message(glue("[R215] desc_source {shares$desc_source[i]}: {shares$n[i]} codes ({shares$pct[i]}%)"))
unm <- out |> filter(desc_source == "unmatched") |> select(raw_code, rows_all_sources, patients)
message(glue("[R215] distinct codes: {nrow(out)}; unmatched: {nrow(unm)}; ",
             "extract_fallback descriptions at 75 chars: {n75}; stacked rows reconcile: {sum(cnt$rows_n) == n_stacked}"))

dir.create(CONFIG$output_dir, showWarnings = FALSE, recursive = TRUE)
write.csv(out, OUT_DESC, row.names = FALSE, na = "")
write.csv(unm, OUT_UNM, row.names = FALSE, na = "")
message(glue("[R215] wrote {OUT_DESC} ({nrow(out)} rows) and {OUT_UNM} ({nrow(unm)} rows)"))
