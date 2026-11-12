# ==============================================================================
# R/tools/check_199_full_history.R -- Phase 199 full-history check (READ-ONLY)
# ==============================================================================
# Purpose:
#   Confirm that immune_flag / ever_brentuximab in output/gantt_episodes_180.csv
#   reflect each patient's ENTIRE record, not only what the treatment-episode
#   pipeline picked up.
#
#   Diagnosis side: build_autoimmune_dx_flags() reads every DIAGNOSIS row for the
#   cohort with no date window (only the 1910 sentinel), so it already covers the
#   full history. This script re-derives it as a control.
#
#   Drug side: the flags read drug_names from the Gantt episodes, which only
#   contain codes in the treatment code lists. Known gaps checked here:
#     - Rituximab biosimilar HCPCS Q5115 (Truxima), Q5119 (Ruxience), Q5123 (Riabni)
#     - Rituximab RxNorm codes (RITUXIMAB_CODES$rxnorm is not in chemo_rxnorm)
#     - Oral methotrexate HCPCS J8610
#     - Any record found only by medication NAME (brand or generic)
#   This script searches PROCEDURES, PRESCRIBING, MED_ADMIN and DISPENSING over
#   all dates, by code AND by name, and compares the patient sets with the CSV.
#
# Inputs:  output/gantt_episodes_180.csv; DuckDB PCORnet tables
# Outputs: console only (counts 1-10 shown as "<11"; no IDs printed)
# Run:     source("R/tools/check_199_full_history.R", local = new.env(parent = globalenv()))
# ==============================================================================

suppressPackageStartupMessages({ library(dplyr); library(glue) })
if (!exists("CONFIG")) source("R/00_config.R")

fmt_sup <- function(n) if (n >= 1L && n <= 10L) "<11" else format(n, big.mark = ",")

# --- 1. Flags as written by R/142 -------------------------------------------
g <- readr::read_csv(file.path(CONFIG$output_dir, "gantt_episodes_180.csv"),
                     col_types = readr::cols(.default = readr::col_character()),
                     show_col_types = FALSE)
stopifnot(all(c("immune_flag", "ever_brentuximab", "drug_names") %in% names(g)))
cohort <- unique(g$patient_id)

tok_pts <- function(pattern) {
  hit <- grepl(pattern, g$drug_names, ignore.case = TRUE)
  unique(g$patient_id[hit])
}
ep <- list(
  Rituximab    = tok_pts("(^|;)\\s*rituximab"),
  Methotrexate = tok_pts("(^|;)\\s*methotrexate"),
  Brentuximab  = tok_pts("(^|;)\\s*brentuximab")
)
flag_imm  <- unique(g$patient_id[g$immune_flag == "TRUE"])
flag_brx  <- unique(g$patient_id[g$ever_brentuximab == "TRUE"])

# --- 2. Raw CDM search over all dates ---------------------------------------
drug_defs <- list(
  Rituximab = list(
    hcpcs  = c("J9310", "J9311", "J9312", "Q5115", "Q5119", "Q5123"),
    rxnorm = RITUXIMAB_CODES$rxnorm,
    names  = c("rituximab", "rituxan", "truxima", "ruxience", "riabni")
  ),
  Methotrexate = list(
    hcpcs  = c(MTX_CODES$hcpcs, "J8610"),
    rxnorm = MTX_CODES$rxnorm,
    names  = c("methotrexate", "trexall", "otrexup", "rasuvo", "xatmep", "jylamvo", "rheumatrex")
  ),
  Brentuximab = list(
    hcpcs  = c("J9042"),
    rxnorm = c("1147320", "1147323", "1147324", "1147327"),
    names  = c("brentuximab", "adcetris")
  )
)

opened_here <- FALSE
if (!exists("pcornet_con", envir = .GlobalEnv) || !DBI::dbIsValid(pcornet_con)) {
  open_pcornet_con(); opened_here <- TRUE
}
duckdb::duckdb_register(pcornet_con, "chk199_cohort", tibble::tibble(ID = cohort))
on.exit({
  try(duckdb::duckdb_unregister(pcornet_con, "chk199_cohort"), silent = TRUE)
  if (opened_here) try(close_pcornet_con(), silent = TRUE)
}, add = TRUE)

flds <- function(tbl) toupper(DBI::dbListFields(pcornet_con, tbl))
sql_in   <- function(x) paste0("'", gsub("'", "''", x), "'", collapse = ", ")
sql_like <- function(col, words) paste0("lower(CAST(t.", col, " AS VARCHAR)) LIKE '%", words, "%'", collapse = " OR ")

# One query per (table, rule); returns ID, raw date string, source label
run_q <- function(tbl, where, date_col, label) {
  f <- flds(tbl)
  dsel <- if (!is.null(date_col) && toupper(date_col) %in% f) paste0("CAST(t.", date_col, " AS VARCHAR)") else "NULL"
  sql <- glue("SELECT DISTINCT t.ID, {dsel} AS rec_date FROM {tbl} t
               JOIN chk199_cohort c ON c.ID = t.ID WHERE {where}")
  out <- tryCatch(DBI::dbGetQuery(pcornet_con, sql), error = function(e) {
    message(glue("    [skip] {label}: {conditionMessage(e)}")); NULL })
  if (is.null(out) || nrow(out) == 0) return(NULL)
  out$source <- label
  out
}

raw_hits <- function(def) {
  parts <- list()
  # PROCEDURES by HCPCS code
  if ("PX" %in% flds("PROCEDURES"))
    parts$px <- run_q("PROCEDURES", glue("upper(trim(CAST(t.PX AS VARCHAR))) IN ({sql_in(def$hcpcs)})"),
                      "PX_DATE", "PROCEDURES code")
  # PRESCRIBING by RxNorm + by name
  f <- flds("PRESCRIBING")
  if ("RXNORM_CUI" %in% f && length(def$rxnorm))
    parts$rx_code <- run_q("PRESCRIBING", glue("CAST(t.RXNORM_CUI AS VARCHAR) IN ({sql_in(def$rxnorm)})"),
                           "RX_ORDER_DATE", "PRESCRIBING code")
  for (nc in intersect(c("RAW_RX_MED_NAME", "RX_MED_NAME"), f))
    parts[[paste0("rx_", nc)]] <- run_q("PRESCRIBING", sql_like(nc, def$names), "RX_ORDER_DATE", "PRESCRIBING name")
  # MED_ADMIN by code + by name
  f <- flds("MED_ADMIN")
  if ("MEDADMIN_CODE" %in% f)
    parts$ma_code <- run_q("MED_ADMIN", glue("upper(trim(CAST(t.MEDADMIN_CODE AS VARCHAR))) IN ({sql_in(c(def$rxnorm, def$hcpcs))})"),
                           "MEDADMIN_START_DATE", "MED_ADMIN code")
  for (nc in intersect(c("RAW_MEDADMIN_MED_NAME", "MEDADMIN_MED_NAME"), f))
    parts[[paste0("ma_", nc)]] <- run_q("MED_ADMIN", sql_like(nc, def$names), "MEDADMIN_START_DATE", "MED_ADMIN name")
  # DISPENSING by name (NDC lists are not maintained here)
  f <- flds("DISPENSING")
  for (nc in intersect(c("RAW_DISPENSE_MED_NAME", "DISPENSE_MED_NAME"), f))
    parts[[paste0("di_", nc)]] <- run_q("DISPENSING", sql_like(nc, def$names), "DISPENSE_DATE", "DISPENSING name")
  dplyr::bind_rows(parts)
}

# --- 3. Compare ---------------------------------------------------------------
message("\n=== Phase 199 full-history check (all dates, all CDM medication sources) ===")
raw_sets <- list()
for (drug in names(drug_defs)) {
  h <- raw_hits(drug_defs[[drug]])
  raw_ids <- if (is.null(h) || nrow(h) == 0) character(0) else unique(h$ID)
  raw_sets[[drug]] <- raw_ids
  ep_ids  <- ep[[drug]]
  only_raw <- setdiff(raw_ids, ep_ids)

  message(glue("\n--- {drug} ---"))
  message(glue("  Patients in Gantt drug_names (what the flag uses): {fmt_sup(length(ep_ids))}"))
  message(glue("  Patients in raw CDM, any date, code or name:      {fmt_sup(length(raw_ids))}"))
  message(glue("  In raw CDM but NOT in Gantt drug_names:           {fmt_sup(length(only_raw))}"))
  message(glue("  In Gantt but not found in raw search:             {fmt_sup(length(setdiff(ep_ids, raw_ids)))}"))
  if (length(only_raw) && !is.null(h)) {
    by_src <- h |> dplyr::filter(ID %in% only_raw) |> dplyr::distinct(ID, source) |>
      dplyr::count(source, name = "n_pts")
    for (i in seq_len(nrow(by_src)))
      message(glue("    raw-only via {by_src$source[i]}: {fmt_sup(by_src$n_pts[i])}"))
  }
  # Year span of raw records vs Gantt episodes (shows whether any date window applies)
  if (!is.null(h) && nrow(h)) {
    yrs <- suppressWarnings(as.integer(format(parse_pcornet_date(h$rec_date), "%Y")))
    yrs <- yrs[!is.na(yrs)]
    if (length(yrs)) message(glue("  Raw record years: {min(yrs)}-{max(yrs)}"))
  }
  ep_rows <- grepl(paste0("(^|;)\\s*", tolower(drug)), g$drug_names, ignore.case = TRUE)
  ep_yrs <- suppressWarnings(as.integer(substr(g$episode_start[ep_rows], 1, 4)))
  ep_yrs <- ep_yrs[!is.na(ep_yrs)]
  if (length(ep_yrs)) message(glue("  Gantt episode years: {min(ep_yrs)}-{max(ep_yrs)}"))
}

# --- 4. What immune_flag / ever_brentuximab would be with raw-history drugs ----
dx <- build_autoimmune_dx_flags(cohort, sentinel = SENTINEL_CUTOFF, codes = IMMUNE_FLAG_DX_CODES)
dx_ids <- dx$ID[dx$has_autoimmune_dx]
imm_raw <- intersect(union(raw_sets$Rituximab, raw_sets$Methotrexate), dx_ids)

message("\n=== Flag comparison ===")
message(glue("  Patients with IMMUNE_FLAG dx (full DIAGNOSIS history): {fmt_sup(length(dx_ids))}"))
message(glue("  immune_flag TRUE in CSV:                          {fmt_sup(length(flag_imm))}"))
message(glue("  immune_flag if drugs taken from raw full history: {fmt_sup(length(imm_raw))}"))
message(glue("    would be added:   {fmt_sup(length(setdiff(imm_raw, flag_imm)))}"))
message(glue("    would be dropped: {fmt_sup(length(setdiff(flag_imm, imm_raw)))}"))
message(glue("  ever_brentuximab TRUE in CSV:                     {fmt_sup(length(flag_brx))}"))
message(glue("  ever_brentuximab from raw full history:           {fmt_sup(length(raw_sets$Brentuximab))}"))
message(glue("    would be added:   {fmt_sup(length(setdiff(raw_sets$Brentuximab, flag_brx)))}"))
message("\nIf 'would be added' is 0 for all three, the episode-based flags already cover each patient's full history.")
