#!/usr/bin/env Rscript
# =============================================================================
# R/161_diag_anchor_followup.R
# Phase 161 (diagnostic) — Why does hl_anchor_date >= follow_end occur?
#
# Read-only against the DuckDB CDM. Re-derives hl_anchor_date and follow_end
# independently of utils_surveillance.R, attributes every zero_or_negative
# patient to a root cause, and quantifies follow-up under-count for ALL HL
# patients under a broader "last observed activity" definition.
#
# Usage:
#   source("/blue/erin.mobley-hl.bcu/insurance_investigation/R/161_diag_anchor_followup.R")
#
# Optional env overrides (set with Sys.setenv() before sourcing):
#   HL_PROJECT_ROOT  project root (default: /blue/erin.mobley-hl.bcu/insurance_investigation)
#   HL_DUCKDB_PATH   DuckDB file (default: /blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb)
#   HL_CUTOFF_DATE   study cutoff used by R/147 (default: 2025-12-31)
#   HL_E_TABLE_PATH  R/147 E_patient_modality_dates output (.rds/.csv) for replication check
#   HL_DIAG_OUT      output directory (default: <root>/output/diagnostics/161_anchor_followup)
# =============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(purrr)
})

# ---- Config ------------------------------------------------------------------
PROJECT_ROOT <- Sys.getenv("HL_PROJECT_ROOT", "/blue/erin.mobley-hl.bcu/insurance_investigation")
CUTOFF_DATE  <- as.Date(Sys.getenv("HL_CUTOFF_DATE", "2025-12-31"))
E_TABLE_PATH <- Sys.getenv("HL_E_TABLE_PATH", "")
OUT_DIR      <- Sys.getenv("HL_DIAG_OUT",
                           file.path(PROJECT_ROOT, "output", "diagnostics", "161_anchor_followup"))
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

KNOWN_DB_PATHS <- c(
  "/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb",
  file.path(dirname(PROJECT_ROOT), "clean", "duckdb", "pcornet.duckdb")
)

# ---- Resolve DuckDB path -----------------------------------------------------
resolve_duckdb_path <- function(project_root, known = KNOWN_DB_PATHS) {
  env_path <- Sys.getenv("HL_DUCKDB_PATH", "")
  if (nzchar(env_path)) {
    if (!file.exists(env_path)) stop("HL_DUCKDB_PATH does not exist: ", env_path)
    return(normalizePath(env_path))
  }

  # 1. Known persisted location(s)
  hit <- known[file.exists(known)]
  if (length(hit)) return(normalizePath(hit[1]))

  # 2. Quoted *.duckdb path in R/00_config.R or R/03_duckdb_ingest.R
  for (f in file.path(project_root, "R", c("00_config.R", "03_duckdb_ingest.R"))) {
    if (!file.exists(f)) next
    src  <- readLines(f, warn = FALSE)
    hits <- unlist(regmatches(src, gregexpr("[\"'][^\"']*\\.duckdb[\"']", src)))
    hits <- unique(gsub("^[\"']|[\"']$", "", hits))
    cand <- unique(c(hits, file.path(project_root, hits)))
    cand <- cand[file.exists(cand)]
    if (length(cand)) return(normalizePath(cand[1]))
  }

  # 3. Search project tree and sibling clean/ folder
  roots <- unique(c(project_root, file.path(dirname(project_root), "clean")))
  roots <- roots[dir.exists(roots)]
  found <- unlist(lapply(roots, list.files, pattern = "\\.duckdb$",
                         recursive = TRUE, full.names = TRUE))
  found <- found[!grepl("renv/|\\.Rproj\\.user|/tmp/", found)]
  if (length(found) == 1) return(normalizePath(found))
  if (length(found) == 0) {
    stop("No .duckdb file found under: ", paste(roots, collapse = ", "),
         ". Set HL_DUCKDB_PATH explicitly.")
  }
  stop("Multiple .duckdb files found; set HL_DUCKDB_PATH to one of:\n  ",
       paste(found, collapse = "\n  "))
}

DUCKDB_PATH <- resolve_duckdb_path(PROJECT_ROOT)
cat("Using DuckDB:", DUCKDB_PATH, "\n")
cat("Cutoff date :", format(CUTOFF_DATE), "\n")
cat("Output dir  :", normalizePath(OUT_DIR), "\n")

con <- tryCatch(
  dbConnect(duckdb::duckdb(), dbdir = DUCKDB_PATH, read_only = TRUE),
  error = function(e) stop("Could not open DuckDB read-only (another session may hold a ",
                           "write lock, e.g. a running R/03):\n", conditionMessage(e)))

all_tables <- dbListTables(con)
has_table  <- function(t) toupper(t) %in% toupper(all_tables)
real_name  <- function(t) all_tables[match(toupper(t), toupper(all_tables))]
fields_up  <- function(t) toupper(dbListFields(con, real_name(t)))
has_col    <- function(t, col) has_table(t) && toupper(col) %in% fields_up(t)
banner     <- function(x) cat("\n", strrep("=", 78), "\n", x, "\n", strrep("=", 78), "\n", sep = "")
save_csv   <- function(df, name) write_csv(df, file.path(OUT_DIR, paste0(name, ".csv")))

# Patient key may be ID (renamed) or PATID (raw CDM) inside DuckDB
pk_col <- function(t) {
  f <- fields_up(t)
  if ("ID" %in% f) return("ID")
  if ("PATID" %in% f) return("PATID")
  stop("Table ", t, " has neither ID nor PATID column.")
}
fill_pk <- function(sql, pk) gsub("{PK}", pk, sql, fixed = TRUE)

required <- c("DIAGNOSIS", "ENCOUNTER")
missing_req <- required[!vapply(required, has_table, logical(1))]
if (length(missing_req)) {
  dbDisconnect(con, shutdown = TRUE)
  stop("Required table(s) missing from DuckDB: ", paste(missing_req, collapse = ", "),
       "\nTables present: ", paste(all_tables, collapse = ", "))
}
cat("Patient key — DIAGNOSIS:", pk_col("DIAGNOSIS"), "| ENCOUNTER:", pk_col("ENCOUNTER"),
    if (has_table("DEATH")) paste("| DEATH:", pk_col("DEATH")) else "", "\n")

# ---- 1. Date column type audit ----------------------------------------------
banner("1. Date column types (VARCHAR = parse risk; TIMESTAMPTZ = day-shift risk)")
date_cols <- c("DX_DATE", "ADMIT_DATE", "DISCHARGE_DATE", "DEATH_DATE")
type_audit <- dbGetQuery(con, sprintf(
  "SELECT table_name, column_name, data_type
     FROM information_schema.columns
    WHERE upper(column_name) IN (%s)
      AND upper(table_name) IN ('DIAGNOSIS','ENCOUNTER','DEATH')
    ORDER BY table_name, column_name",
  paste0("'", date_cols, "'", collapse = ","))) |>
  as_tibble() |>
  mutate(string_dates = grepl("VARCHAR|TEXT|STRING", toupper(data_type)),
         tz_risk      = grepl("TIME ZONE|TIMESTAMPTZ", toupper(data_type)))
print(type_audit, n = Inf)
save_csv(type_audit, "01_date_type_audit")

# ---- 2. HL diagnosis rows and anchor ----------------------------------------
banner("2. HL diagnosis rows and anchor derivation")
hl_dx <- dbGetQuery(con, fill_pk(paste0("
  SELECT {PK} AS ID, ENCOUNTERID, DX, CAST(DX_TYPE AS VARCHAR) AS DX_TYPE,
         (DX_DATE    IS NOT NULL AND TRY_CAST(DX_DATE    AS DATE) IS NULL) AS dx_date_unparsed,
         (ADMIT_DATE IS NOT NULL AND TRY_CAST(ADMIT_DATE AS DATE) IS NULL) AS admit_unparsed,
         TRY_CAST(DX_DATE    AS DATE) AS dx_date,
         TRY_CAST(ADMIT_DATE AS DATE) AS dx_admit_date
    FROM ", real_name("DIAGNOSIS"), "
   WHERE (CAST(DX_TYPE AS VARCHAR) = '10'        AND upper(DX) LIKE 'C81%')
      OR (CAST(DX_TYPE AS VARCHAR) IN ('09','9') AND replace(DX, '.', '') LIKE '201%')"),
  pk_col("DIAGNOSIS"))) |>
  as_tibble() |>
  mutate(dx_date       = as.Date(dx_date),
         dx_admit_date = as.Date(dx_admit_date),
         anchor_cand   = coalesce(dx_date, dx_admit_date))

cat(sprintf("HL dx rows: %d | patients: %d | DX_DATE unparsed: %d | ADMIT_DATE unparsed: %d\n",
            nrow(hl_dx), n_distinct(hl_dx$ID),
            sum(hl_dx$dx_date_unparsed), sum(hl_dx$admit_unparsed)))
if (nrow(hl_dx) == 0) {
  dbDisconnect(con, shutdown = TRUE)
  stop("No HL diagnosis rows found — check DX_TYPE coding (e.g. 'ICD10' vs '10') in DIAGNOSIS.")
}

anchor <- hl_dx |>
  filter(!is.na(anchor_cand)) |>
  group_by(ID) |>
  summarise(
    hl_anchor_date             = min(anchor_cand),
    anchor_from_admit_fallback = any(anchor_cand == hl_anchor_date & is.na(dx_date)),
    anchor_encounterid         = first(ENCOUNTERID[anchor_cand == hl_anchor_date]),
    anchor_dx_type             = first(DX_TYPE[anchor_cand == hl_anchor_date]),
    n_hl_dx_rows               = n(),
    .groups = "drop")

n_na_anchor <- n_distinct(hl_dx$ID) - nrow(anchor)
cat(sprintf("Patients with anchor: %d | NA anchor (dropped in R/147): %d\n",
            nrow(anchor), n_na_anchor))

duckdb::duckdb_register(con, "hl_ids",
                        anchor |> select(ID, hl_anchor_date, anchor_encounterid))

# ---- 3. Encounter-based last contact ----------------------------------------
banner("3. ENCOUNTER summaries")
enc_tbl <- real_name("ENCOUNTER")
enc_pk  <- pk_col("ENCOUNTER")
enc_sum <- dbGetQuery(con, fill_pk(sprintf("
  WITH e AS (
    SELECT e.{PK} AS ID,
           TRY_CAST(e.ADMIT_DATE     AS DATE) AS admit,
           TRY_CAST(e.DISCHARGE_DATE AS DATE) AS disch
      FROM %s e JOIN hl_ids h ON e.{PK} = h.ID
  )
  SELECT ID,
         count(*)                                                       AS n_enc,
         max(admit)                                                     AS last_enc_admit,
         max(greatest(coalesce(admit, disch), coalesce(disch, admit)))
           FILTER (WHERE coalesce(admit, disch) <= DATE '%s')           AS last_enc_any,
         sum(CASE WHEN admit > DATE '%s' THEN 1 ELSE 0 END)             AS n_enc_after_cutoff
    FROM e GROUP BY ID", enc_tbl, CUTOFF_DATE, CUTOFF_DATE), enc_pk)) |>
  as_tibble() |>
  mutate(across(c(last_enc_admit, last_enc_any), as.Date),
         last_enc_any = pmin(last_enc_any, CUTOFF_DATE))

anchor_enc <- dbGetQuery(con, fill_pk(sprintf("
  SELECT h.ID,
         (e.ENCOUNTERID IS NOT NULL)          AS anchor_enc_found,
         CAST(e.ENC_TYPE AS VARCHAR)          AS anchor_enc_type,
         TRY_CAST(e.ADMIT_DATE     AS DATE)   AS anchor_enc_admit,
         TRY_CAST(e.DISCHARGE_DATE AS DATE)   AS anchor_enc_disch
    FROM hl_ids h
    LEFT JOIN %s e
      ON e.{PK} = h.ID AND e.ENCOUNTERID = h.anchor_encounterid", enc_tbl), enc_pk)) |>
  as_tibble() |>
  distinct(ID, .keep_all = TRUE) |>
  mutate(across(c(anchor_enc_admit, anchor_enc_disch), as.Date))

# ---- 4. Death ---------------------------------------------------------------
banner("4. DEATH summaries")
col_type <- function(t, col) {
  out <- dbGetQuery(con, sprintf(
    "SELECT data_type FROM information_schema.columns
      WHERE upper(table_name) = '%s' AND upper(column_name) = '%s'",
    toupper(t), toupper(col)))$data_type
  if (length(out)) toupper(out[1]) else NA_character_
}

IMPUTE_STATUS <- "not_present"
death_sum <- if (has_table("DEATH")) {
  impute_expr <- "CAST(NULL AS BOOLEAN)"
  if (has_col("DEATH", "DEATH_DATE_IMPUTE")) {
    imp_type <- col_type("DEATH", "DEATH_DATE_IMPUTE")
    if (grepl("VARCHAR|TEXT|STRING|CHAR", imp_type)) {
      impute_expr   <- "bool_or(trim(upper(d.DEATH_DATE_IMPUTE)) IN ('B','D','M'))"
      IMPUTE_STATUS <- "ok"
    } else {
      IMPUTE_STATUS <- paste0("mistyped_", imp_type)
      cat("WARNING: DEATH.DEATH_DATE_IMPUTE is typed ", imp_type,
          " in DuckDB (should be VARCHAR flags B/D/M/N). Imputation flags were likely ",
          "lost at ingest (R/03); death_imputed set to NA.\n", sep = "")
      imp_nonnull <- dbGetQuery(con, sprintf(
        "SELECT count(*) AS n_nonnull FROM %s WHERE DEATH_DATE_IMPUTE IS NOT NULL",
        real_name("DEATH")))$n_nonnull
      cat("  Non-null DEATH_DATE_IMPUTE values in DuckDB:", imp_nonnull, "\n")
    }
  }
  dbGetQuery(con, fill_pk(sprintf("
    SELECT d.{PK} AS ID,
           min(TRY_CAST(d.DEATH_DATE AS DATE))            AS death_min,
           max(TRY_CAST(d.DEATH_DATE AS DATE))            AS death_max,
           count(DISTINCT TRY_CAST(d.DEATH_DATE AS DATE)) AS n_death_dates,
           %s                                              AS death_imputed
      FROM %s d JOIN hl_ids h ON d.{PK} = h.ID
     GROUP BY d.{PK}", impute_expr, real_name("DEATH")), pk_col("DEATH"))) |>
    as_tibble() |>
    mutate(across(c(death_min, death_max), as.Date))
} else {
  tibble(ID = anchor$ID[0], death_min = as.Date(character()), death_max = as.Date(character()),
         n_death_dates = integer(), death_imputed = logical())
}
cat(sprintf("HL patients with a death date: %d (imputed: %d, conflicting dates: %d)\n",
            sum(!is.na(death_sum$death_min)), sum(death_sum$death_imputed %in% TRUE),
            sum(death_sum$n_death_dates > 1, na.rm = TRUE)))

# ---- 5. Last observed activity across CDM tables ----------------------------
banner("5. Last observed clinical activity (any CDM table, <= cutoff)")
activity_sources <- list(
  DIAGNOSIS     = c("DX_DATE", "ADMIT_DATE"),
  PROCEDURES    = c("PX_DATE", "ADMIT_DATE"),
  LAB_RESULT_CM = c("SPECIMEN_DATE", "RESULT_DATE"),
  PRESCRIBING   = c("RX_ORDER_DATE", "RX_START_DATE"),
  DISPENSING    = c("DISPENSE_DATE"),
  MED_ADMIN     = c("MEDADMIN_START_DATE"),
  VITAL         = c("MEASURE_DATE"),
  OBS_CLIN      = c("OBSCLIN_START_DATE"),
  IMMUNIZATION  = c("VX_ADMIN_DATE")
)
act_sql <- imap(activity_sources, function(cols, tbl) {
  if (!has_table(tbl)) return(NULL)
  pk <- tryCatch(pk_col(tbl), error = function(e) NULL)
  if (is.null(pk)) return(NULL)
  cols <- cols[map_lgl(cols, ~ has_col(tbl, .x))]
  if (!length(cols)) return(NULL)
  map_chr(cols, ~ fill_pk(sprintf(
    "SELECT t.{PK} AS ID, '%s.%s' AS src,
            max(TRY_CAST(t.%s AS DATE)) FILTER (WHERE TRY_CAST(t.%s AS DATE) <= DATE '%s') AS d
       FROM %s t JOIN hl_ids h ON t.{PK} = h.ID
      GROUP BY t.{PK}",
    tbl, .x, .x, .x, CUTOFF_DATE, real_name(tbl)), pk))
}) |> compact() |> unlist()

cat("Activity sources used:", length(act_sql), "\n")
activity <- dbGetQuery(con, paste(act_sql, collapse = "\nUNION ALL\n")) |>
  as_tibble() |>
  mutate(d = as.Date(d)) |>
  filter(!is.na(d))

act_last <- activity |>
  group_by(ID) |>
  slice_max(d, n = 1, with_ties = FALSE) |>
  ungroup() |>
  transmute(ID, last_activity_any = d, last_activity_src = src)

# ---- 6. Assemble, replicate follow_end, attribute root causes ---------------
banner("6. Replicated follow_end and root-cause attribution")
diag <- anchor |>
  left_join(enc_sum,    by = "ID") |>
  left_join(anchor_enc, by = "ID") |>
  left_join(death_sum,  by = "ID") |>
  left_join(act_last,   by = "ID") |>
  mutate(
    # Current definition (as documented for compute_followup)
    follow_end    = pmin(death_min, last_enc_admit, CUTOFF_DATE, na.rm = TRUE),
    binding       = case_when(
      !is.na(death_min)      & death_min      == follow_end ~ "death",
      !is.na(last_enc_admit) & last_enc_admit == follow_end ~ "last_enc_admit",
      TRUE                                                  ~ "cutoff"),
    fu_status     = if_else(hl_anchor_date >= follow_end, "zero_or_negative", "positive"),
    fu_sign       = case_when(hl_anchor_date >  follow_end ~ "negative",
                              hl_anchor_date == follow_end ~ "zero",
                              TRUE                         ~ "positive"),
    gap_days      = as.integer(hl_anchor_date - follow_end),
    # Candidate definition: observation end = latest evidence of contact
    obs_end_proposed    = pmax(last_enc_any, last_activity_any, na.rm = TRUE),
    follow_end_proposed = pmin(death_min, obs_end_proposed, CUTOFF_DATE, na.rm = TRUE),
    fu_days_current     = pmax(0L, as.integer(follow_end          - hl_anchor_date)),
    fu_days_proposed    = pmax(0L, as.integer(follow_end_proposed - hl_anchor_date)),
    root_cause = case_when(
      fu_status != "zero_or_negative"                       ~ NA_character_,
      hl_anchor_date > CUTOFF_DATE                          ~ "1_anchor_after_cutoff",
      binding == "death" & death_imputed %in% TRUE          ~ "2a_death_before_anchor_imputed",
      binding == "death" & n_death_dates > 1                ~ "2b_death_before_anchor_conflicting",
      binding == "death"                                    ~ "2c_death_before_anchor",
      !is.na(last_enc_any) & last_enc_any > hl_anchor_date  ~ "3a_discharge_date_extends",
      !is.na(last_activity_any) &
        last_activity_any > hl_anchor_date                  ~ "3b_other_cdm_activity_extends",
      !(anchor_enc_found %in% TRUE)                         ~ "4a_last_contact_is_anchor_orphan_enc",
      hl_anchor_date == last_enc_admit                      ~ "4b_last_contact_is_anchor_same_day",
      !is.na(anchor_enc_admit) &
        hl_anchor_date > anchor_enc_admit                   ~ "4c_dx_date_after_own_encounter_admit",
      TRUE                                                  ~ "9_unexplained"))

n_zero <- sum(diag$fu_status == "zero_or_negative")
cat(sprintf("zero_or_negative: %d of %d (%.1f%%) | strictly negative: %d | exactly zero: %d\n",
            n_zero, nrow(diag), 100 * n_zero / nrow(diag),
            sum(diag$fu_sign == "negative"), sum(diag$fu_sign == "zero")))

by_cause <- diag |>
  filter(fu_status == "zero_or_negative") |>
  group_by(root_cause) |>
  summarise(n               = n(),
            n_negative      = sum(fu_sign == "negative"),
            n_zero          = sum(fu_sign == "zero"),
            median_gap_days = median(gap_days),
            max_gap_days    = max(gap_days),
            n_recovered     = sum(fu_days_proposed > 0),
            median_days_recovered = median(fu_days_proposed),
            .groups = "drop") |>
  mutate(pct = round(100 * n / sum(n), 1)) |>
  arrange(root_cause)
cat("\nRoot causes among zero_or_negative:\n"); print(by_cause, n = Inf, width = Inf)

by_binding <- diag |> count(fu_status, binding) |> arrange(fu_status, desc(n))
cat("\nWhich component binds follow_end:\n"); print(by_binding, n = Inf)

by_profile <- diag |>
  group_by(fu_status) |>
  summarise(n                    = n(),
            pct_admit_fallback   = round(100 * mean(anchor_from_admit_fallback), 1),
            pct_icd9_anchor      = round(100 * mean(anchor_dx_type %in% c("09", "9")), 1),
            pct_orphan_anchor    = round(100 * mean(!(anchor_enc_found %in% TRUE)), 1),
            pct_inpatient_anchor = round(100 * mean(anchor_enc_type %in% c("IP", "EI", "IS", "OS")), 1),
            median_n_enc         = median(n_enc, na.rm = TRUE),
            .groups = "drop")
cat("\nAnchor profile, zero_or_negative vs positive:\n"); print(by_profile, width = Inf)

last_src <- diag |>
  filter(root_cause %in% c("3a_discharge_date_extends", "3b_other_cdm_activity_extends")) |>
  count(last_activity_src, sort = TRUE)
cat("\nSource of latest activity for recoverable patients:\n"); print(last_src, n = Inf)

# ---- 7. Whole-cohort impact of a broader follow_end -------------------------
banner("7. Whole-cohort impact (all HL patients, not just zero_or_negative)")
impact <- diag |>
  summarise(n_patients              = n(),
            n_follow_end_extended   = sum(follow_end_proposed > follow_end),
            pct_extended            = round(100 * n_follow_end_extended / n_patients, 1),
            person_years_current    = round(sum(fu_days_current)  / 365.25, 1),
            person_years_proposed   = round(sum(fu_days_proposed) / 365.25, 1),
            pct_py_increase         = round(100 * (person_years_proposed / person_years_current - 1), 1),
            n_zero_current          = sum(fu_days_current  == 0),
            n_zero_proposed         = sum(fu_days_proposed == 0))
print(impact, width = Inf)

# ---- 8. Optional: verify replication against R/147 output -------------------
if (nzchar(E_TABLE_PATH) && file.exists(E_TABLE_PATH)) {
  banner("8. Replication check vs R/147 E_patient_modality_dates")
  e_tbl <- if (grepl("\\.rds$", E_TABLE_PATH, ignore.case = TRUE)) readRDS(E_TABLE_PATH) else
    read_csv(E_TABLE_PATH, show_col_types = FALSE)
  keep  <- intersect(c("ID", "hl_anchor_date", "follow_end", "fu_status", "person_years"), names(e_tbl))
  e_tbl <- e_tbl |>
    as_tibble() |>
    select(all_of(keep)) |>
    mutate(ID = as.character(ID), across(any_of(c("hl_anchor_date", "follow_end")), as.Date)) |>
    distinct(ID, .keep_all = TRUE) |>
    rename_with(~ paste0(.x, "_r147"), -ID)
  cmp <- diag |> mutate(ID = as.character(ID)) |> inner_join(e_tbl, by = "ID")
  rep_check <- tibble(
    n_matched_ids        = nrow(cmp),
    n_only_in_r147       = nrow(anti_join(e_tbl, mutate(diag, ID = as.character(ID)), by = "ID")),
    anchor_mismatch      = if ("hl_anchor_date_r147" %in% names(cmp))
      sum(cmp$hl_anchor_date != cmp$hl_anchor_date_r147, na.rm = TRUE) else NA_integer_,
    follow_end_mismatch  = if ("follow_end_r147" %in% names(cmp))
      sum(cmp$follow_end != cmp$follow_end_r147, na.rm = TRUE) else NA_integer_,
    fu_status_mismatch   = if ("fu_status_r147" %in% names(cmp))
      sum(cmp$fu_status != cmp$fu_status_r147, na.rm = TRUE) else NA_integer_)
  print(rep_check, width = Inf)
  save_csv(rep_check, "08_replication_check")
  if (isTRUE(rep_check$follow_end_mismatch > 0)) {
    save_csv(cmp |> filter(follow_end != follow_end_r147) |>
               select(ID, hl_anchor_date, hl_anchor_date_r147, follow_end, follow_end_r147,
                      death_min, last_enc_admit, last_enc_any, binding),
             "08_follow_end_mismatches")
    cat("follow_end mismatches written; check last_enc_date definition in compute_followup().\n")
  }
} else if (nzchar(E_TABLE_PATH)) {
  cat("\nHL_E_TABLE_PATH set but file not found; skipping replication check:", E_TABLE_PATH, "\n")
}

# ---- 8b. Death-row detail (161-02) ------------------------------------------
banner("8b. Conflicting death dates, DEATH_SOURCE, imputation, projected person-years")
GRACE <- 30L
src_expr <- if (has_col("DEATH", "DEATH_SOURCE")) "CAST(d.DEATH_SOURCE AS VARCHAR)" else "NULL"
imp_expr <- if (IMPUTE_STATUS == "ok") "CAST(d.DEATH_DATE_IMPUTE AS VARCHAR)" else "NULL"
death_rows <- dbGetQuery(con, fill_pk(sprintf("
  SELECT d.{PK} AS ID, TRY_CAST(d.DEATH_DATE AS DATE) AS DEATH_DATE,
         %s AS DEATH_SOURCE, %s AS DEATH_DATE_IMPUTE
    FROM %s d JOIN hl_ids h ON d.{PK} = h.ID",
  src_expr, imp_expr, real_name("DEATH")), pk_col("DEATH"))) |>
  as_tibble() |>
  mutate(DEATH_DATE = as.Date(DEATH_DATE),
         DEATH_SOURCE = toupper(trimws(DEATH_SOURCE)),
         DEATH_DATE_IMPUTE = toupper(trimws(DEATH_DATE_IMPUTE))) |>
  filter(!is.na(DEATH_DATE))

obs <- diag |> transmute(ID, last_observed = pmax(last_enc_any, last_activity_any, na.rm = TRUE))
death_chk <- death_rows |>
  left_join(obs, by = "ID") |>
  mutate(consistent = is.na(last_observed) | DEATH_DATE >= last_observed - GRACE)

per_id <- death_chk |>
  group_by(ID) |>
  summarise(n_dates = n_distinct(DEATH_DATE),
            any_consistent = any(consistent),
            imputed = any(DEATH_DATE_IMPUTE %in% c("B", "D", "M")),
            .groups = "drop")

death_detail <- tibble(
  n_decedents                  = nrow(per_id),
  n_single_plausible           = sum(per_id$n_dates == 1 &  per_id$any_consistent),
  n_single_implausible         = sum(per_id$n_dates == 1 & !per_id$any_consistent),
  n_conflicting                = sum(per_id$n_dates > 1),
  n_conflicting_resolved       = sum(per_id$n_dates > 1 &  per_id$any_consistent),
  n_conflicting_unresolved     = sum(per_id$n_dates > 1 & !per_id$any_consistent),
  n_imputed_bdm                = sum(per_id$imputed),
  n_imputed_and_implausible    = sum(per_id$imputed & !per_id$any_consistent),
  impute_flag_status           = IMPUTE_STATUS)
print(death_detail, width = Inf)

source_tab <- death_rows |>
  count(DEATH_SOURCE = coalesce(DEATH_SOURCE, "<NULL>"), sort = TRUE)
cat("\nDEATH_SOURCE distribution (HL decedent rows):\n"); print(source_tab, n = Inf)

# Projection: D2 (no credible date -> NA) + D3 approximated as earliest consistent
# date (source priority ignored; affects conflicting patients only) + D6.
proj_death <- death_chk |>
  filter(consistent) |>
  group_by(ID) |>
  summarise(death_proj = min(DEATH_DATE), .groups = "drop")
proj <- diag |>
  left_join(proj_death, by = "ID") |>
  mutate(obs_end = pmin(pmax(last_enc_any, last_activity_any, na.rm = TRUE), CUTOFF_DATE),
         fe      = pmin(death_proj, obs_end, CUTOFF_DATE, na.rm = TRUE),
         fe      = if_else(!is.na(death_proj) & death_proj < hl_anchor_date, hl_anchor_date, fe),
         fu_days = pmax(0L, as.integer(fe - hl_anchor_date)))
projection <- tibble(
  person_years_current      = round(sum(diag$fu_days_current) / 365.25, 1),
  person_years_obs_end_only = round(sum(diag$fu_days_proposed) / 365.25, 1),
  person_years_projected_d2 = round(sum(proj$fu_days) / 365.25, 1),
  n_zero_projected          = sum(proj$fu_days == 0),
  n_negative_projected      = sum(proj$fe < proj$hl_anchor_date)) |>
  mutate(pct_increase_d2 = round(100 * (person_years_projected_d2 / person_years_current - 1), 1))
cat("\nProjected person-years under D2/D3/D6:\n"); print(projection, width = Inf)

save_csv(death_detail, "08b_death_detail")
save_csv(source_tab,   "08b_death_source")
save_csv(projection,   "08b_person_years_projection")

# ---- 9. Write outputs --------------------------------------------------------
save_csv(diag,       "09_patient_level_diagnostics")
save_csv(by_cause,   "09_root_cause_summary")
save_csv(by_binding, "09_binding_component")
save_csv(by_profile, "09_anchor_profile")
save_csv(last_src,   "09_last_activity_source")
save_csv(impact,     "09_cohort_impact")
save_csv(tibble(duckdb_path        = DUCKDB_PATH,
                patient_key        = pk_col("DIAGNOSIS"),
                death_impute_flag  = IMPUTE_STATUS,
                n_hl_patients      = n_distinct(hl_dx$ID),
                n_na_anchor        = n_na_anchor,
                n_unparsed_dx_date = sum(hl_dx$dx_date_unparsed),
                n_unparsed_admit   = sum(hl_dx$admit_unparsed),
                cutoff_date        = CUTOFF_DATE), "09_run_meta")

duckdb::duckdb_unregister(con, "hl_ids")
dbDisconnect(con, shutdown = TRUE)
cat("\nDone. Outputs in:", normalizePath(OUT_DIR), "\n")
