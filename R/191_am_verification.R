# R/191_am_verification.R
# =============================================================================
# Purpose:  Read-only verification script for the analytic manual (Phase 191).
#           Runs six query-backed checks (V1_SOURCE through V6_DEATH) against the
#           CDM tables in DuckDB and writes results to
#           output/am_verification_<YYYYMMDD>.xlsx.
#
#           Each check implements the manual's rule directly from CDM tables
#           (independent re-derivation, per D-01a) and compares with the pipeline's
#           own result. A failing check is recorded as FAILED/SKIPPED in the QC
#           sheet and does not stop the others.
#
# Inputs:   DuckDB (open via CONFIG$cache$duckdb_path)
#           get_hl_any_dx_ids() from utils_treatment.R (V3 pipeline side, live call)
#           R/60 output payer_resolved_detail_all.csv (V2 pipeline side; pinned via R191_R60_CSV)
#           R/116 output encounter_ses_index_<date>.rds  (V5 pipeline side; pinned via R191_R116_RDS)
#           cancer_summary_table_pre_post_v2_7day.rds    (V4 pipeline side; pinned via R191_R49_RDS)
#
# Outputs:  output/am_verification_<YYYYMMDD>.xlsx           (KEY, V1–V6, QC)
#           output/internal/am_v2_discordant_<date>.rds      (V2 discordant patient-days with IDs)
#           output/internal/am_v3_anchor_diff_<date>.rds     (V3 per-patient anchor comparison)
#
# Requirements: AM-VER-01, AM-VER-02, AM-VER-04
# Phase: 191 — verify-existing-entries
# Plan:  191-01
# =============================================================================

# =============================================================================
# SECTION 1 — Setup
# =============================================================================

# Source config in the global environment so pcornet_con and CONFIG are global,
# matching the pattern used by R/169_single_source_care.R.
source(here::here("R/00_config.R"))

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(openxlsx)
})

# Run date (override via R191_DATE env var for reproducibility)
run_date <- Sys.getenv("R191_DATE", unset = format(Sys.Date(), "%Y%m%d"))
if (!grepl("^[0-9]{8}$", run_date)) {
  stop("R191_DATE must be an 8-digit date (YYYYMMDD), got: ", run_date)
}

message(glue("R/191 am_verification — run_date = {run_date}"))

# =============================================================================
# SECTION 2 — Column-name constants (file:line citations in comments)
# =============================================================================

# --- Patient key ---
COL_ID                   <- "ID"           # utils_duckdb.R:128

# --- ENCOUNTER ---
COL_ENC_ENCOUNTERID      <- "ENCOUNTERID"  # 60_tiered_same_day_payer.R:84
COL_ENC_ADMIT_DATE       <- "ADMIT_DATE"   # 60_tiered_same_day_payer.R:84
COL_ENC_ENC_TYPE         <- "ENC_TYPE"     # 60_tiered_same_day_payer.R:85
COL_ENC_SOURCE           <- "SOURCE"       # 169_single_source_care.R:125
COL_ENC_PAYER_PRI        <- "PAYER_TYPE_PRIMARY"   # 60_tiered_same_day_payer.R:85
COL_ENC_PAYER_SEC        <- "PAYER_TYPE_SECONDARY" # 60_tiered_same_day_payer.R:143

# --- DIAGNOSIS ---
COL_DX_ID                <- "ID"           # utils_treatment.R:72
COL_DX_DX                <- "DX"           # utils_treatment.R:74
COL_DX_TYPE              <- "DX_TYPE"      # utils_treatment.R:74
COL_DX_DX_DATE           <- "DX_DATE"      # utils_treatment.R:318
COL_DX_ADMIT_DATE        <- "ADMIT_DATE"   # utils_treatment.R:318 (fallback)

# --- TUMOR_REGISTRY (TUMOR_REGISTRY_ALL view) ---
# TR1 histology: HISTOLOGICAL_TYPE; TR2/TR3 histology: MORPH  (00_config.R:457)
COL_TR_DX_DATE           <- "DATE_OF_DIAGNOSIS"    # 02_harmonize_payer.R:244
COL_TR_HIST_TR1          <- "HISTOLOGICAL_TYPE"    # 00_config.R:457
COL_TR_MORPH_TR23        <- "MORPH"                # 00_config.R:457

# HL histology codes (ICD-O-3) — 00_config.R:473-476
HL_HIST_CODES <- ICD_CODES$hl_histology  # 00_config.R:473

# --- DEATH ---
COL_DEATH_ID             <- "ID"           # utils_death.R:54
COL_DEATH_DATE           <- "DEATH_DATE"   # utils_death.R:54
COL_DEATH_SOURCE         <- "DEATH_SOURCE" # utils_death.R:55

# --- AMC payer lookup (00_config.R:783) ---
AMC_LOOKUP               <- AMC_PAYER_LOOKUP  # 00_config.R:783

# =============================================================================
# SECTION 3 — DuckDB connection (opened_here pattern from R/169)
# =============================================================================

opened_here <- FALSE
if (!exists("pcornet_con", envir = .GlobalEnv) ||
    !DBI::dbIsValid(get("pcornet_con", envir = .GlobalEnv))) {
  opened_here <- tryCatch(
    { open_pcornet_con(); TRUE },
    error = function(e) {
      message("R/191: DuckDB unavailable — skipping (", conditionMessage(e), ")")
      NA
    }
  )
}
duckdb_ok <- !is.na(opened_here)

# Record DuckDB metadata for QC provenance
duckdb_path  <- CONFIG$cache$duckdb_path
duckdb_mtime <- if (file.exists(duckdb_path)) format(file.mtime(duckdb_path)) else "unknown"

# =============================================================================
# SECTION 4 — Suppression helpers
# =============================================================================

# Use the project's existing suppress_small() (defined in utils_surveillance.R,
# auto-sourced via 00_config.R).

#' Apply suppress_small() to every count column in a data frame.
#' @param df     data.frame
#' @param cols   character vector of column names to suppress
#' @param pct_cols named list: list(count_col = "pct_col") — blank pct when count suppressed
sup_df <- function(df, cols, pct_cols = list()) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  for (col in cols) {
    if (col %in% names(df)) df[[col]] <- suppress_small(df[[col]])
  }
  for (cnt_col in names(pct_cols)) {
    pct_col <- pct_cols[[cnt_col]]
    if (cnt_col %in% names(df) && pct_col %in% names(df)) {
      suppressed <- !is.na(df[[cnt_col]]) & df[[cnt_col]] == "<11"
      if (any(suppressed, na.rm = TRUE)) df[[pct_col]][suppressed] <- NA_character_
    }
  }
  df
}

#' Complementary-suppression table.
#' @param tab data.frame: first col = row label; last col = row total; last row = col totals.
#' @param count_cols column indices (not first or last) that hold raw integer counts.
#' Returns character data.frame with suppression applied.
sup_table <- function(tab) {
  tab <- as.data.frame(tab, stringsAsFactors = FALSE)
  nr <- nrow(tab)
  nc <- ncol(tab)
  if (nr < 2L || nc < 3L) {
    # Apply basic suppression on all numeric columns and return
    for (j in seq_len(nc)) {
      v <- suppressWarnings(as.integer(tab[[j]]))
      if (!all(is.na(v))) tab[[j]] <- suppress_small(v)
    }
    return(tab)
  }

  interior_rows <- seq_len(nr - 1L)
  interior_cols <- seq(2L, nc - 1L)

  # Record raw values
  raw <- tab
  for (i in seq_len(nr)) for (j in seq_len(nc)) {
    v <- suppressWarnings(as.integer(tab[i, j]))
    raw[i, j] <- if (is.na(v)) NA_integer_ else v
  }

  # Suppress interior cells 1-10
  supp_mask <- matrix(FALSE, nrow = nr, ncol = nc)
  for (i in interior_rows) for (j in interior_cols) {
    v <- suppressWarnings(as.integer(raw[i, j]))
    if (!is.na(v) && v >= 1L && v <= 10L) supp_mask[i, j] <- TRUE
  }

  # Complementary suppression on totals
  # Row totals (last column) suppressed if exactly one interior cell in that row is suppressed
  for (i in interior_rows) {
    if (sum(supp_mask[i, interior_cols]) == 1L) supp_mask[i, nc] <- TRUE
  }
  # Column totals (last row) suppressed if exactly one interior cell in that column is suppressed
  for (j in interior_cols) {
    if (sum(supp_mask[interior_rows, j]) == 1L) supp_mask[nr, j] <- TRUE
  }

  # Format output
  out <- tab
  for (i in seq_len(nr)) for (j in seq_len(nc)) {
    v <- suppressWarnings(as.integer(raw[i, j]))
    out[i, j] <- if (supp_mask[i, j]) "<11"
                 else if (is.na(v)) ""
                 else as.character(v)
  }
  out
}

# =============================================================================
# SECTION 5 — Check runner
# =============================================================================

QC_ROWS <- list()  # accumulated check-level provenance rows

#' Run a single check function, catching all errors.
#' fn must return list(status, reason, map_ids, provenance, tables, internal).
#' status ∈ {COMPLETE, PARTIAL, SKIPPED, FAILED}
run_check <- function(check_id, fn) {
  message(glue("\n--- {check_id} ---"))
  result <- tryCatch(
    fn(),
    error = function(e) {
      msg <- conditionMessage(e)
      message(glue("  {check_id} FAILED: {msg}"))
      list(
        status     = "FAILED",
        reason     = glue("Uncaught error: {msg}"),
        map_ids    = check_id,
        provenance = "N/A",
        tables     = list(),
        internal   = list(),
        rows_written = 0L,
        supp_events  = 0L
      )
    }
  )
  # Ensure required fields
  for (fld in c("rows_written", "supp_events")) {
    if (is.null(result[[fld]])) result[[fld]] <- 0L
  }
  message(glue("  {check_id} -> {result$status}"))
  QC_ROWS[[check_id]] <<- result
  result
}

# =============================================================================
# SECTION 6 — V1_SOURCE
# =============================================================================

check_v1 <- function() {
  if (!duckdb_ok) return(list(
    status = "SKIPPED", reason = "DuckDB unavailable",
    map_ids = "L1", provenance = "N/A", tables = list(), internal = list()
  ))

  con <- get("pcornet_con", envir = .GlobalEnv)

  # Find all CDM tables with a SOURCE column via information_schema
  schema_q <- "SELECT LOWER(table_name) AS tbl FROM information_schema.columns
               WHERE LOWER(column_name) = 'source'
               ORDER BY tbl"
  source_tables <- DBI::dbGetQuery(con, schema_q)$tbl

  # HL cohort IDs from get_hl_any_dx_ids()
  hl_ids <- get_hl_any_dx_ids()$ID

  results <- list()
  supp_events <- 0L

  for (tbl in source_tables) {
    # Normalize SOURCE: UPPER(TRIM(SOURCE)); blank -> NULL treated as NULL by GROUP BY
    q <- glue(
      "SELECT UPPER(TRIM(NULLIF(TRIM({COL_ENC_SOURCE}),''))) AS source_val,
              COUNT(*) AS n_rows,
              COUNT(DISTINCT {COL_ID}) AS n_patients
       FROM \"{tbl}\"
       GROUP BY 1
       ORDER BY n_rows DESC"
    )
    tbl_counts <- tryCatch(
      DBI::dbGetQuery(con, q),
      error = function(e) NULL
    )
    if (is.null(tbl_counts)) next

    # HL cohort subset
    # Register HL IDs as a temp table for semi-join
    hl_tbl_name <- paste0("hl_ids_v1_", gsub("[^a-z0-9]", "_", tbl))
    tryCatch({
      DBI::dbExecute(con, glue("DROP TABLE IF EXISTS {hl_tbl_name}"))
      DBI::dbWriteTable(con, hl_tbl_name, data.frame(ID = hl_ids), temporary = TRUE)
    }, error = function(e) NULL)

    q_hl <- glue(
      "SELECT UPPER(TRIM(NULLIF(TRIM({COL_ENC_SOURCE}),''))) AS source_val,
              COUNT(*) AS n_rows_hl,
              COUNT(DISTINCT t.{COL_ID}) AS n_patients_hl
       FROM \"{tbl}\" t
       JOIN {hl_tbl_name} h ON t.{COL_ID} = h.ID
       GROUP BY 1
       ORDER BY n_rows_hl DESC"
    )
    hl_counts <- tryCatch(
      DBI::dbGetQuery(con, q_hl),
      error = function(e) data.frame(source_val = character(), n_rows_hl = integer(), n_patients_hl = integer())
    )

    combined <- merge(tbl_counts, hl_counts, by = "source_val", all.x = TRUE)
    combined$table_name <- tbl

    # LNK rows/patients
    lnk_rows <- combined[!is.na(combined$source_val) & combined$source_val == "LNK", , drop = FALSE]

    # Patients with >1 distinct SOURCE per table
    q_multi <- glue(
      "SELECT COUNT(DISTINCT {COL_ID}) AS n_multi_source
       FROM (
         SELECT {COL_ID}, COUNT(DISTINCT UPPER(TRIM(NULLIF(TRIM({COL_ENC_SOURCE}),''))))
           AS n_src
         FROM \"{tbl}\"
         GROUP BY {COL_ID}
       ) sub WHERE n_src > 1"
    )
    multi_count <- tryCatch(
      DBI::dbGetQuery(con, q_multi)$n_multi_source,
      error = function(e) NA_integer_
    )

    # Count suppression events
    raw_n_rows <- combined$n_rows
    combined$n_rows     <- suppress_small(combined$n_rows)
    combined$n_patients <- suppress_small(combined$n_patients)
    supp_events <- supp_events + sum(combined$n_rows == "<11", na.rm = TRUE)

    combined$n_rows_hl     <- suppress_small(combined$n_rows_hl)
    combined$n_patients_hl <- suppress_small(combined$n_patients_hl)

    results[[tbl]] <- list(
      source_by_table = combined,
      lnk_rows        = lnk_rows,
      n_multi_source  = multi_count
    )
  }

  # Build display table
  all_rows <- dplyr::bind_rows(lapply(names(results), function(t) {
    d <- results[[t]]$source_by_table
    d$n_multi_source_patients <- results[[t]]$n_multi_source
    d
  }))

  list(
    status       = "COMPLETE",
    reason       = glue("SOURCE profiled in {length(source_tables)} tables"),
    map_ids      = "L1",
    provenance   = "DuckDB information_schema + ENCOUNTER/DEMOGRAPHIC tables; R/169 reads SOURCE from ENCOUNTER only",
    tables       = list(v1_source = all_rows),
    internal     = list(),
    rows_written = nrow(all_rows),
    supp_events  = supp_events
  )
}

# =============================================================================
# SECTION 7 — V2_INSURANCE
# =============================================================================

check_v2 <- function() {
  if (!duckdb_ok) return(list(
    status = "SKIPPED", reason = "DuckDB unavailable",
    map_ids = "L2", provenance = "N/A", tables = list(), internal = list()
  ))

  con <- get("pcornet_con", envir = .GlobalEnv)

  # --- Pipeline side: pinned R/60 output ---
  r60_path <- Sys.getenv("R191_R60_CSV",
    unset = file.path(CONFIG$output_dir, "tables", "payer_resolved_detail_all.csv"))
  if (!file.exists(r60_path)) {
    return(list(
      status = "SKIPPED",
      reason = glue("R/60 output not found at {r60_path}; set R191_R60_CSV"),
      map_ids = "L2", provenance = "N/A", tables = list(), internal = list()
    ))
  }
  pipe_side <- tryCatch(
    readr::read_csv(r60_path, col_types = readr::cols(.default = readr::col_character()),
                    show_col_types = FALSE) |>
      dplyr::select(ID, ADMIT_DATE, resolved_payer) |>
      dplyr::mutate(ADMIT_DATE = as.Date(ADMIT_DATE)),
    error = function(e) NULL
  )
  if (is.null(pipe_side)) return(list(
    status = "FAILED", reason = "Could not read R/60 CSV",
    map_ids = "L2", provenance = r60_path, tables = list(), internal = list()
  ))
  r60_mtime <- format(file.mtime(r60_path))

  # --- Manual side: SQL re-derivation of 6-level hierarchy (one per patient-day) ---
  # Hierarchy: Medicaid (codes 93/14 or FLM source) > Medicare > Private > Other > Uninsured > missing
  # Note: code 93 maps to Medicaid via FLM override; code 14 maps to Medicaid directly.
  # Pipeline categories Other and Other govt have no clean manual equivalent -> UNMAPPED.
  manual_q <- glue("
    WITH enc_day AS (
      SELECT
        {COL_ID}               AS ID,
        CAST({COL_ENC_ADMIT_DATE} AS DATE) AS admit_date,
        UPPER(TRIM(NULLIF(TRIM({COL_ENC_SOURCE}),''))) AS source_val,
        UPPER(TRIM({COL_ENC_PAYER_PRI}))  AS payer_pri,
        UPPER(TRIM({COL_ENC_PAYER_SEC}))  AS payer_sec
      FROM ENCOUNTER
      WHERE {COL_ENC_ADMIT_DATE} IS NOT NULL
    ),
    classified AS (
      SELECT
        ID,
        admit_date,
        CASE
          WHEN source_val = 'FLM'                     THEN 'Medicaid'
          WHEN payer_pri IN ('14','141','142','93')
            OR payer_sec IN ('14','141','142','93')    THEN 'Medicaid'
          WHEN payer_pri IN ('2','21','211','213','219','23','25','29') THEN 'Medicaid'
          WHEN payer_pri IN ('1','11','111','19')      THEN 'Medicare'
          WHEN payer_pri IN ('5','51','511','512','513','52','521','529',
                              '6','623','7','71','311') THEN 'Private'
          WHEN payer_pri IN ('8','821')                THEN 'Uninsured'
          WHEN payer_pri IN ('81')                     THEN 'Self-pay'
          WHEN payer_pri IN ('NI','UN','99','9999','UNKNOWN') THEN 'missing'
          ELSE 'unmapped'
        END AS manual_level,
        CASE
          WHEN source_val = 'FLM'                     THEN 1
          WHEN payer_pri IN ('14','141','142','93')
            OR payer_sec IN ('14','141','142','93')    THEN 2
          WHEN payer_pri IN ('2','21','211','213','219','23','25','29') THEN 3
          WHEN payer_pri IN ('1','11','111','19')      THEN 4
          WHEN payer_pri IN ('5','51','511','512','513','52','521','529',
                              '6','623','7','71','311') THEN 5
          WHEN payer_pri IN ('8','821')                THEN 6
          WHEN payer_pri IN ('81')                     THEN 7
          WHEN payer_pri IN ('NI','UN','99','9999','UNKNOWN') THEN 8
          ELSE 9
        END AS manual_rank
      FROM enc_day
    ),
    resolved AS (
      SELECT ID, admit_date,
        FIRST(manual_level ORDER BY manual_rank ASC) AS manual_resolved
      FROM classified
      GROUP BY ID, admit_date
    )
    SELECT * FROM resolved
  ")
  manual_side <- tryCatch(
    DBI::dbGetQuery(con, manual_q),
    error = function(e) NULL
  )
  if (is.null(manual_side)) return(list(
    status = "FAILED", reason = "Manual-side SQL failed",
    map_ids = "L2", provenance = r60_path, tables = list(), internal = list()
  ))
  manual_side$admit_date <- as.Date(manual_side$admit_date)

  # V2 crosswalk: pipeline -> manual 6-level
  # Other and Other govt = UNMAPPED (no clean manual equivalent)
  crosswalk <- c(
    "Medicaid"   = "Medicaid",
    "Medicare"   = "Medicare",
    "Private"    = "Private",
    "Uninsured"  = "Uninsured",
    "Self-pay"   = "UNMAPPED",   # manual merges with Uninsured; pipeline separates
    "Missing"    = "missing",
    "Other"      = "UNMAPPED",
    "Other govt" = "UNMAPPED"
  )

  # Join manual and pipeline sides
  compared <- pipe_side |>
    dplyr::inner_join(manual_side, by = c("ID", "ADMIT_DATE" = "admit_date")) |>
    dplyr::mutate(
      pipe_mapped = dplyr::recode(resolved_payer, !!!crosswalk, .default = "UNMAPPED"),
      is_unmapped = pipe_mapped == "UNMAPPED",
      agree       = !is_unmapped & pipe_mapped == manual_resolved
    )

  n_total   <- nrow(compared)
  n_unmapped<- sum(compared$is_unmapped, na.rm = TRUE)
  n_mapped  <- n_total - n_unmapped
  n_agree   <- sum(compared$agree, na.rm = TRUE)

  # Agreement table (excluding UNMAPPED)
  agree_tbl <- data.frame(
    metric          = c("Patient-days compared", "UNMAPPED (excluded)",
                        "Mapped patient-days", "Agreeing (mapped)"),
    count           = c(n_total, n_unmapped, n_mapped, n_agree),
    stringsAsFactors = FALSE
  )
  agree_tbl$count <- suppress_small(agree_tbl$count)

  # Cross-tab: manual level x pipeline category
  xtab_raw <- compared |>
    dplyr::group_by(manual_resolved, resolved_payer) |>
    dplyr::summarise(n = dplyr::n(), .groups = "drop") |>
    tidyr::pivot_wider(names_from = resolved_payer, values_from = n, values_fill = 0L)
  xtab_raw$row_total <- rowSums(dplyr::select(xtab_raw, -manual_resolved), na.rm = TRUE)
  col_totals <- c(manual_resolved = "Total", colSums(dplyr::select(xtab_raw, -manual_resolved), na.rm = TRUE))
  xtab_disp  <- sup_table(rbind(as.data.frame(xtab_raw), as.list(col_totals)))

  # UNMAPPED categories
  unmapped_tbl <- compared |>
    dplyr::filter(is_unmapped) |>
    dplyr::group_by(resolved_payer) |>
    dplyr::summarise(n_patient_days = dplyr::n(), .groups = "drop")
  unmapped_tbl$n_patient_days <- suppress_small(unmapped_tbl$n_patient_days)

  # Discordant patient-days -> internal/ RDS (IDs included)
  discordant <- compared |> dplyr::filter(!is_unmapped & !agree)
  supp_events <- sum(agree_tbl$count == "<11", na.rm = TRUE)

  internal_path <- file.path(CONFIG$output_dir, "internal",
                              glue("am_v2_discordant_{run_date}.rds"))
  dir.create(dirname(internal_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(discordant, internal_path)

  prov <- glue(
    "Pipeline: {r60_path} (mtime {r60_mtime}); ",
    "Manual: SQL re-derivation on DuckDB ENCOUNTER (DuckDB mtime {duckdb_mtime})"
  )

  list(
    status       = "COMPLETE",
    reason       = glue("{n_mapped} mapped patient-days; {n_unmapped} UNMAPPED"),
    map_ids      = "L2",
    provenance   = prov,
    tables       = list(
      v2_agreement   = agree_tbl,
      v2_crosstab    = xtab_disp,
      v2_unmapped    = unmapped_tbl
    ),
    internal     = list(discordant_path = internal_path),
    rows_written = nrow(xtab_disp),
    supp_events  = supp_events
  )
}

# =============================================================================
# SECTION 8 — V3_DXDATE
# =============================================================================

check_v3 <- function() {
  if (!duckdb_ok) return(list(
    status = "SKIPPED", reason = "DuckDB unavailable",
    map_ids = "L3", provenance = "N/A", tables = list(), internal = list()
  ))

  con <- get("pcornet_con", envir = .GlobalEnv)

  # --- Pipeline side: call get_hl_any_dx_ids() live ---
  pipe_anchors <- tryCatch(
    get_hl_any_dx_ids() |> dplyr::select(ID, pipe_anchor = hl_anchor_date),
    error = function(e) NULL
  )
  if (is.null(pipe_anchors)) return(list(
    status = "FAILED", reason = "get_hl_any_dx_ids() failed",
    map_ids = "L3", provenance = "get_hl_any_dx_ids() (utils_treatment.R:310)", tables = list(), internal = list()
  ))

  # --- Manual side step 1: TR HL date ---
  # Use TUMOR_REGISTRY_ALL view (created by open_pcornet_con, utils_duckdb.R:140)
  # HL histology codes in ICD_CODES$hl_histology (00_config.R:473-476)
  # TR1: HISTOLOGICAL_TYPE; TR2/TR3: MORPH (00_config.R:457)
  hl_codes_sql <- paste0("'", paste(HL_HIST_CODES, collapse = "','"), "'")

  tr_q <- glue("
    SELECT ID,
           MIN(CAST(DATE_OF_DIAGNOSIS AS DATE)) AS tr_anchor
    FROM TUMOR_REGISTRY_ALL
    WHERE (
      (HISTOLOGICAL_TYPE IS NOT NULL AND SUBSTR(HISTOLOGICAL_TYPE,1,4) IN ({hl_codes_sql}))
      OR
      (MORPH IS NOT NULL AND SUBSTR(MORPH,1,4) IN ({hl_codes_sql}))
    )
    AND DATE_OF_DIAGNOSIS IS NOT NULL
    GROUP BY ID
  ")
  tr_side <- tryCatch(
    DBI::dbGetQuery(con, tr_q),
    error = function(e) NULL
  )
  if (is.null(tr_side)) {
    tr_side <- data.frame(ID = character(), tr_anchor = as.Date(character()))
    tr_note  <- "TUMOR_REGISTRY_ALL query failed or table absent; TR step skipped"
  } else {
    tr_side$tr_anchor <- as.Date(tr_side$tr_anchor)
    tr_note <- glue("{nrow(tr_side)} patients with TR HL histology date")
  }

  # --- Manual side step 2: first C81/201 code date from DIAGNOSIS ---
  dx_q <- glue("
    SELECT ID,
           MIN(COALESCE(CAST(DX_DATE AS DATE), CAST(ADMIT_DATE AS DATE))) AS dx_anchor
    FROM DIAGNOSIS
    WHERE (
      (TRIM(DX_TYPE) = '10' AND REPLACE(UPPER(TRIM(DX)),'.','') LIKE 'C81%')
      OR
      (TRIM(DX_TYPE) = '09' AND REPLACE(UPPER(TRIM(DX)),'.','') LIKE '201%')
    )
    GROUP BY ID
  ")
  dx_side <- tryCatch(
    DBI::dbGetQuery(con, dx_q),
    error = function(e) NULL
  )
  if (is.null(dx_side)) return(list(
    status = "FAILED", reason = "DIAGNOSIS HL code date query failed",
    map_ids = "L3", provenance = "SQL on DIAGNOSIS", tables = list(), internal = list()
  ))
  dx_side$dx_anchor <- as.Date(dx_side$dx_anchor)

  # Manual anchor: TR date if available, else first code date
  manual_anchors <- dx_side |>
    dplyr::left_join(tr_side, by = "ID") |>
    dplyr::mutate(
      manual_anchor = dplyr::coalesce(tr_anchor, dx_anchor),
      manual_source = dplyr::case_when(
        !is.na(tr_anchor) ~ "tumor_registry",
        !is.na(dx_anchor) ~ "diagnosis_code",
        TRUE               ~ "none"
      )
    ) |>
    dplyr::select(ID, manual_anchor, manual_source, tr_anchor, dx_anchor)

  # Compare with pipeline
  compared <- pipe_anchors |>
    dplyr::full_join(manual_anchors, by = "ID") |>
    dplyr::mutate(
      day_diff = as.integer(pipe_anchor - manual_anchor),
      diff_band = dplyr::case_when(
        is.na(day_diff)        ~ "one_side_only",
        day_diff == 0          ~ "0",
        day_diff > 0 & day_diff <= 7   ~ "pipe_later_1_7",
        day_diff > 7 & day_diff <= 30  ~ "pipe_later_8_30",
        day_diff > 30 & day_diff <= 365 ~ "pipe_later_31_365",
        day_diff > 365         ~ "pipe_later_gt365",
        day_diff < 0 & day_diff >= -7  ~ "pipe_earlier_1_7",
        day_diff < -7 & day_diff >= -30 ~ "pipe_earlier_8_30",
        day_diff < -30 & day_diff >= -365 ~ "pipe_earlier_31_365",
        day_diff < -365        ~ "pipe_earlier_gt365",
        TRUE                   ~ "other"
      )
    )

  # Anchor source breakdown
  pipe_src <- pipe_anchors |>
    dplyr::mutate(pipe_has = !is.na(pipe_anchor)) |>
    dplyr::count(pipe_has)

  manual_src <- manual_anchors |>
    dplyr::count(manual_source)

  # Band table
  band_tbl <- compared |> dplyr::count(diff_band) |>
    dplyr::rename(n_patients = n)
  band_tbl$n_patients <- suppress_small(band_tbl$n_patients)

  # Internal: full per-patient comparison (includes IDs)
  internal_path <- file.path(CONFIG$output_dir, "internal",
                              glue("am_v3_anchor_diff_{run_date}.rds"))
  dir.create(dirname(internal_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(compared, internal_path)

  prov <- glue(
    "Pipeline: get_hl_any_dx_ids() live call (utils_treatment.R:310); ",
    "Manual: SQL on DIAGNOSIS + TUMOR_REGISTRY_ALL ({tr_note})"
  )

  list(
    status       = "COMPLETE",
    reason       = glue("{nrow(pipe_anchors)} pipeline anchors, {sum(!is.na(manual_anchors$manual_anchor))} manual anchors"),
    map_ids      = "L3",
    provenance   = prov,
    tables       = list(
      v3_manual_source = manual_src,
      v3_day_diff_bands = band_tbl
    ),
    internal     = list(anchor_diff_path = internal_path),
    rows_written = nrow(band_tbl),
    supp_events  = sum(band_tbl$n_patients == "<11", na.rm = TRUE)
  )
}

# =============================================================================
# SECTION 9 — V4_DXSCOPE
# =============================================================================

check_v4 <- function() {
  if (!duckdb_ok) return(list(
    status = "SKIPPED", reason = "DuckDB unavailable",
    map_ids = "L4", provenance = "N/A", tables = list(), internal = list()
  ))

  con <- get("pcornet_con", envir = .GlobalEnv)

  # Pipeline artifact: cancer_summary_table_pre_post_v2_7day.rds (R/49 output)
  # Pinned via R191_R49_RDS env var
  r49_path <- Sys.getenv("R191_R49_RDS",
    unset = file.path(CONFIG$output_dir, "tables", "cancer_summary_table_pre_post_v2_7day.rds"))

  if (!file.exists(r49_path)) {
    return(list(
      status = "SKIPPED",
      reason = glue("R/49 7-day artifact not found at {r49_path}; set R191_R49_RDS"),
      map_ids = "L4", provenance = "N/A", tables = list(), internal = list()
    ))
  }
  r49_mtime <- format(file.mtime(r49_path))

  # Load pipeline artifact — contains per-patient-per-code rows with two_or_more_unique_dates_gt_7
  pipeline_art <- tryCatch(
    readRDS(r49_path),
    error = function(e) NULL
  )
  if (is.null(pipeline_art)) return(list(
    status = "FAILED", reason = "Could not read R/49 RDS artifact",
    map_ids = "L4", provenance = r49_path, tables = list(), internal = list()
  ))

  # Detect cancer_category column — artifact may be a summary list, not a per-patient frame.
  # If missing, record the artifact shape as a note and continue with the independent re-derivation.
  cat_col <- intersect(c("cancer_category", "category", "cancer_site"), names(pipeline_art))[1]
  artifact_note <- if (is.na(cat_col)) {
    glue("R/49 artifact does not contain a per-patient cancer_category column (found: {paste(names(pipeline_art), collapse=', ')}). Pipeline comparison skipped; independent re-derivation from DIAGNOSIS used.")
  } else {
    glue("R/49 artifact column used: {cat_col}")
  }

  # Independent re-check: for each cancer type, count per (ID, cancer_category) pairs
  # that have >= 2 encounter dates >= 7 days apart in DIAGNOSIS
  # Re-derive 7-day rule from DIAGNOSIS directly (independent of R/49)

  # Get HL cohort IDs
  hl_ids <- get_hl_any_dx_ids()$ID

  # Re-derive: pull DIAGNOSIS dates for all cancer codes (ICD-10 prefix-based)
  # Classify cancer type using classify_codes() from utils_cancer.R
  dx_q <- "
    SELECT ID, DX, DX_TYPE, CAST(DX_DATE AS DATE) AS dx_date
    FROM DIAGNOSIS
    WHERE DX_DATE IS NOT NULL AND DX_TYPE = '10'
  "
  dx_raw <- tryCatch(
    DBI::dbGetQuery(con, dx_q) |>
      dplyr::filter(ID %in% hl_ids) |>
      dplyr::mutate(
        category = classify_codes(DX)
      ) |>
      dplyr::filter(!is.na(category), category != "Benign/Uncertain"),
    error = function(e) NULL
  )

  if (is.null(dx_raw)) return(list(
    status = "PARTIAL",
    reason = "Independent re-derivation from DIAGNOSIS failed; only pipeline summary reported",
    map_ids = "L4", provenance = r49_path, tables = list(), internal = list()
  ))

  # 7-day rule: per (ID, category), need >= 2 distinct dates spanning >= 7 days
  seven_day_tbl <- dx_raw |>
    dplyr::group_by(ID, category) |>
    dplyr::summarise(
      n_dates    = dplyr::n_distinct(dx_date),
      span_days  = as.integer(max(dx_date, na.rm = TRUE) - min(dx_date, na.rm = TRUE)),
      meets_rule = n_dates >= 2L & span_days >= 7L,
      .groups    = "drop"
    )

  recheck_by_cat <- seven_day_tbl |>
    dplyr::group_by(category) |>
    dplyr::summarise(
      n_patient_category_pairs = dplyr::n(),
      n_meets_7day             = sum(meets_rule),
      n_fails_7day             = sum(!meets_rule),
      .groups = "drop"
    )

  # Apply suppression
  recheck_by_cat$n_patient_category_pairs <- suppress_small(recheck_by_cat$n_patient_category_pairs)
  recheck_by_cat$n_meets_7day             <- suppress_small(recheck_by_cat$n_meets_7day)
  recheck_by_cat$n_fails_7day             <- suppress_small(recheck_by_cat$n_fails_7day)

  supp <- sum(recheck_by_cat$n_meets_7day == "<11", na.rm = TRUE) +
          sum(recheck_by_cat$n_fails_7day == "<11", na.rm = TRUE)

  code_path_note <- paste(
    "Code-path finding (Task 0): In R/49_cancer_summary_pre_post.R lines 182-184,",
    "filter(two_or_more_unique_dates_gt_7 == 1) IS applied to all cancer categories,",
    "not only to HL. The 7-day rule therefore applies to non-HL types in the pipeline."
  )

  prov <- glue(
    "Pipeline: {r49_path} (mtime {r49_mtime}); {artifact_note}; ",
    "Re-check: SQL on DuckDB DIAGNOSIS + classify_codes() (utils_cancer.R)"
  )

  list(
    status       = "COMPLETE",
    reason       = glue("{nrow(recheck_by_cat)} cancer categories assessed"),
    map_ids      = "L4",
    provenance   = prov,
    tables       = list(
      v4_7day_by_category = recheck_by_cat,
      v4_code_path_note   = data.frame(finding = code_path_note, stringsAsFactors = FALSE)
    ),
    internal     = list(),
    rows_written = nrow(recheck_by_cat),
    supp_events  = supp
  )
}

# =============================================================================
# SECTION 10 — V5_ZIPCOVER
# =============================================================================

check_v5 <- function() {
  if (!duckdb_ok) return(list(
    status = "SKIPPED", reason = "DuckDB unavailable",
    map_ids = "L5", provenance = "N/A", tables = list(), internal = list()
  ))

  con <- get("pcornet_con", envir = .GlobalEnv)

  # --- Patient-level: LDS_ADDRESS_HISTORY ZIP availability ---
  # Probe for ZIP column names via information_schema (column names unconfirmed in probe)
  addr_cols_q <- "SELECT LOWER(column_name) AS col
                  FROM information_schema.columns
                  WHERE LOWER(table_name) = 'lds_address_history'"
  addr_cols <- tryCatch(
    DBI::dbGetQuery(con, addr_cols_q)$col,
    error = function(e) character(0)
  )

  addr_result <- NULL
  addr_note   <- "LDS_ADDRESS_HISTORY not available in DuckDB or column names differ"

  if (length(addr_cols) > 0) {
    # Identify ZIP9 and ZIP5 columns by pattern
    zip9_col <- addr_cols[grepl("zip.?9|zip9", addr_cols)][1]
    zip5_col <- addr_cols[grepl("zip.?5|zip5", addr_cols)][1]
    id_col   <- if ("id" %in% addr_cols) "ID" else if ("patid" %in% addr_cols) "PATID" else NA_character_

    if (!is.na(id_col) && !is.na(zip9_col)) {
      # Sentinel ZIP5 detection (same rule as is_sentinel_zip5 in utils_address.R):
      # 00000, 99999, single-repeated-digit 5-char string
      zip5_col_expr <- if (!is.na(zip5_col)) glue("SUBSTR({zip9_col},1,5)") else "''"
      addr_q <- glue("
        SELECT
          {id_col} AS ID,
          {zip9_col} AS zip9_raw,
          {zip5_col_expr} AS zip5_raw
        FROM LDS_ADDRESS_HISTORY
      ")
      addr_raw <- tryCatch(DBI::dbGetQuery(con, addr_q), error = function(e) NULL)
      if (!is.null(addr_raw)) {
        addr_raw <- addr_raw |>
          dplyr::mutate(
            has_zip9 = !is.na(zip9_raw) & nchar(trimws(zip9_raw)) >= 8,
            has_zip5 = !is.na(zip5_raw) & nchar(trimws(zip5_raw)) == 5 &
                       !grepl("^(00000|99999|11111|22222|33333|44444|55555|66666|77777|88888)$",
                               trimws(zip5_raw))
          )
        pat_summary <- addr_raw |>
          dplyr::group_by(ID) |>
          dplyr::summarise(
            any_zip9 = any(has_zip9),
            any_zip5 = any(has_zip5),
            .groups  = "drop"
          ) |>
          dplyr::mutate(
            zip_tier = dplyr::case_when(
              any_zip9 ~ "zip9",
              any_zip5 ~ "zip5_only",
              TRUE      ~ "none"
            )
          )
        addr_result <- pat_summary |>
          dplyr::count(zip_tier) |>
          dplyr::rename(n_patients = n)
        addr_result$n_patients <- suppress_small(addr_result$n_patients)
        addr_note <- glue("ZIP9 col: {zip9_col}; ZIP5 col: {zip5_col_expr}")
      }
    }
  }

  # --- Encounter-level: R/116 output ---
  r116_path <- Sys.getenv("R191_R116_RDS", unset = "")
  if (r116_path == "") {
    # Try most-recent file in output/
    candidates <- list.files(CONFIG$output_dir,
                             pattern = "encounter_ses_index_.*\\.rds$",
                             full.names = TRUE)
    if (length(candidates) > 0) {
      r116_path <- candidates[which.max(file.mtime(candidates))]
    }
  }

  enc_result <- NULL
  enc_note   <- "R/116 encounter_ses_index RDS not found; set R191_R116_RDS"

  if (nchar(r116_path) > 0 && file.exists(r116_path)) {
    r116_mtime <- format(file.mtime(r116_path))
    ses_raw <- tryCatch(readRDS(r116_path), error = function(e) NULL)
    if (!is.null(ses_raw)) {
      # match_type values: "interval" | "most_recent_before" | "none" (utils_address.R:17)
      mt_tbl <- ses_raw |>
        dplyr::count(match_type) |>
        dplyr::rename(n_encounters = n)
      mt_tbl$n_encounters <- suppress_small(mt_tbl$n_encounters)

      # SES score availability
      ses_avail <- ses_raw |>
        dplyr::summarise(
          n_with_adi   = sum(!is.na(adi_natrank)),
          n_with_sdi   = sum(!is.na(sdi_score)),
          n_total_enc  = dplyr::n()
        )
      ses_avail$n_with_adi  <- suppress_small(ses_avail$n_with_adi)
      ses_avail$n_with_sdi  <- suppress_small(ses_avail$n_with_sdi)
      ses_avail$n_total_enc <- suppress_small(ses_avail$n_total_enc)

      enc_result <- list(match_type = mt_tbl, ses_avail = ses_avail)
      enc_note   <- glue("R/116 RDS: {r116_path} (mtime {r116_mtime})")
    }
  }

  all_tables <- list()
  if (!is.null(addr_result)) all_tables$v5_patient_zip <- addr_result
  if (!is.null(enc_result)) {
    all_tables$v5_enc_match_type <- enc_result$match_type
    all_tables$v5_ses_avail      <- enc_result$ses_avail
  }

  status <- if (!is.null(addr_result) && !is.null(enc_result)) "COMPLETE"
            else if (!is.null(addr_result) || !is.null(enc_result)) "PARTIAL"
            else "SKIPPED"

  reason <- paste(addr_note, "|", enc_note)

  list(
    status       = status,
    reason       = reason,
    map_ids      = "L5",
    provenance   = glue("Patient: LDS_ADDRESS_HISTORY ({addr_note}); Encounter: {enc_note}"),
    tables       = all_tables,
    internal     = list(),
    rows_written = sum(sapply(all_tables, nrow)),
    supp_events  = 0L
  )
}

# =============================================================================
# SECTION 11 — V6_DEATH
# =============================================================================

check_v6 <- function() {
  if (!duckdb_ok) return(list(
    status = "SKIPPED", reason = "DuckDB unavailable",
    map_ids = "L6", provenance = "N/A", tables = list(), internal = list()
  ))

  con <- get("pcornet_con", envir = .GlobalEnv)

  # HL cohort IDs + anchors
  anchors  <- get_hl_any_dx_ids()
  hl_ids   <- anchors$ID

  # Register HL ID table for SQL joins
  DBI::dbExecute(con, "DROP TABLE IF EXISTS hl_ids_v6")
  DBI::dbWriteTable(con, "hl_ids_v6", data.frame(ID = hl_ids), temporary = TRUE)

  # --- Death dates from DEATH table ---
  death_q <- "
    SELECT d.ID, CAST(d.DEATH_DATE AS DATE) AS death_date, d.DEATH_SOURCE
    FROM DEATH d
    JOIN hl_ids_v6 h ON d.ID = h.ID
    WHERE d.DEATH_DATE IS NOT NULL
  "
  death_raw <- tryCatch(DBI::dbGetQuery(con, death_q), error = function(e) NULL)
  if (is.null(death_raw)) return(list(
    status = "FAILED", reason = "DEATH table query failed",
    map_ids = "L6", provenance = "DEATH table", tables = list(), internal = list()
  ))
  death_raw$death_date <- as.Date(death_raw$death_date)

  # One death date per patient (earliest, mirroring pipeline D3 logic for simplicity;
  # note pipeline uses resolve_death_date() with grace_days=30 and source-priority)
  death_per_patient <- death_raw |>
    dplyr::group_by(ID) |>
    dplyr::summarise(death_date = min(death_date, na.rm = TRUE), .groups = "drop")

  # --- Last treatment date from ENCOUNTER ---
  # Treat any ENCOUNTER row in the HL cohort as a treatment-context encounter.
  # We use ADMIT_DATE as the encounter date, consistent with the pipeline.
  last_tx_q <- "
    SELECT e.ID, MAX(CAST(e.ADMIT_DATE AS DATE)) AS last_tx_date
    FROM ENCOUNTER e
    JOIN hl_ids_v6 h ON e.ID = h.ID
    WHERE e.ADMIT_DATE IS NOT NULL
    GROUP BY e.ID
  "
  last_tx <- tryCatch(DBI::dbGetQuery(con, last_tx_q), error = function(e) NULL)
  if (is.null(last_tx)) return(list(
    status = "FAILED", reason = "ENCOUNTER last-date query failed",
    map_ids = "L6", provenance = "ENCOUNTER table", tables = list(), internal = list()
  ))
  last_tx$last_tx_date <- as.Date(last_tx$last_tx_date)

  # Join death and last treatment
  death_tx <- death_per_patient |>
    dplyr::full_join(last_tx, by = "ID") |>
    dplyr::mutate(
      gap_days = as.integer(death_date - last_tx_date),
      gap_band = dplyr::case_when(
        is.na(death_date)     ~ "no_death_record",
        is.na(last_tx_date)   ~ "no_treatment_date",
        gap_days >= 0         ~ "death_on_after_last_tx",
        gap_days >= -14       ~ "before_1_14",
        gap_days >= -30       ~ "before_15_30",
        gap_days >= -90       ~ "before_31_90",
        TRUE                  ~ "before_gt90"
      ),
      # 14-day rule (as in manual): removed if death < last_tx by <= 14 days
      removed_14day = !is.na(gap_days) & gap_days < 0 & gap_days >= -14L,
      # grace_days=30 rule (production): removed if activity > 30 days after death
      # For this comparison: death removed if gap_days < -30
      removed_30day = !is.na(gap_days) & gap_days < -30L
    )

  # Gap band counts
  gap_tbl <- death_tx |>
    dplyr::count(gap_band) |>
    dplyr::rename(n_patients = n)
  gap_tbl$n_patients <- suppress_small(gap_tbl$n_patients)

  # 14-day vs 30-day rule comparison
  rule_tbl <- data.frame(
    rule             = c("14-day (manual)", "30-day grace (pipeline production)"),
    n_patients_removed = c(sum(death_tx$removed_14day), sum(death_tx$removed_30day)),
    stringsAsFactors = FALSE
  )
  rule_tbl$n_patients_removed <- suppress_small(rule_tbl$n_patients_removed)

  # --- DEATH_CAUSE: cohort patients with any record ---
  # Probe for DEATH_CAUSE table existence
  dc_exists_q <- "SELECT COUNT(*) AS n FROM information_schema.tables
                  WHERE LOWER(table_name) = 'death_cause'"
  dc_exists <- tryCatch(
    DBI::dbGetQuery(con, dc_exists_q)$n > 0,
    error = function(e) FALSE
  )

  dc_cohort_n <- NA_integer_
  dc_note     <- "DEATH_CAUSE table not found in DuckDB"

  if (isTRUE(dc_exists)) {
    dc_q <- "
      SELECT COUNT(DISTINCT dc.ID) AS n_with_cause
      FROM DEATH_CAUSE dc
      JOIN hl_ids_v6 h ON dc.ID = h.ID
    "
    dc_result <- tryCatch(DBI::dbGetQuery(con, dc_q), error = function(e) NULL)
    if (!is.null(dc_result)) {
      dc_cohort_n <- dc_result$n_with_cause
      dc_note     <- glue("DEATH_CAUSE present; {suppress_small(dc_cohort_n)} cohort patients with a record")
    } else {
      dc_note <- "DEATH_CAUSE query failed"
    }
  }

  # Code-path finding (from Task 0 code reading):
  code_path_note <- paste(
    "Code-path finding (Task 0): No cohort inclusion/exclusion predicate in",
    "R/10_cohort_predicates.R uses DEATH_CAUSE. R/102 and R/103 are diagnostic-only.",
    "Expected count of patients excluded by DEATH_CAUSE = 0."
  )

  # Production call sites for resolve_death_date() grace_days=30:
  call_sites_note <- paste(
    "grace_days=30L used at all 5 production call sites:",
    "R/142_gantt_180_export.R:340,",
    "R/147_surveillance_modality_frequency.R:263,",
    "R/52_gantt_v2_export.R:514,",
    "R/161_death_sensitivity.R:90,",
    "R/166_survivorship_modality_rates.R:172.",
    "Manual uses 14-day rule. grace_days default = 30 (utils_death.R:51)."
  )

  dc_tbl <- data.frame(
    item  = c("DEATH_CAUSE table exists", "Cohort patients with any DEATH_CAUSE record",
              "Cohort exclusions using DEATH_CAUSE"),
    value = c(as.character(isTRUE(dc_exists)), suppress_small(dc_cohort_n), "0 (code-path finding)"),
    note  = c("", dc_note, code_path_note),
    stringsAsFactors = FALSE
  )

  supp <- sum(gap_tbl$n_patients == "<11", na.rm = TRUE) +
          sum(rule_tbl$n_patients_removed == "<11", na.rm = TRUE)

  prov <- glue(
    "Manual: SQL on DuckDB DEATH + ENCOUNTER for cohort IDs; ",
    "Pipeline: resolve_death_date() (utils_death.R:51), grace_days=30L"
  )

  list(
    status       = "COMPLETE",
    reason       = glue("{nrow(death_per_patient)} patients with a death record"),
    map_ids      = "L6",
    provenance   = prov,
    tables       = list(
      v6_gap_bands   = gap_tbl,
      v6_rule_compare = rule_tbl,
      v6_death_cause  = dc_tbl,
      v6_call_sites   = data.frame(note = call_sites_note, stringsAsFactors = FALSE)
    ),
    internal     = list(),
    rows_written = nrow(gap_tbl),
    supp_events  = supp
  )
}

# =============================================================================
# SECTION 12 — Run all checks
# =============================================================================

message("\n=== Running checks ===")

r_v1 <- run_check("V1_SOURCE",    check_v1)
r_v2 <- run_check("V2_INSURANCE", check_v2)
r_v3 <- run_check("V3_DXDATE",    check_v3)
r_v4 <- run_check("V4_DXSCOPE",   check_v4)
r_v5 <- run_check("V5_ZIPCOVER",  check_v5)
r_v6 <- run_check("V6_DEATH",     check_v6)

# =============================================================================
# SECTION 13 — Build workbook
# =============================================================================

UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"

wb <- createWorkbook()
modifyBaseFont(wb, fontName = "Arial", fontSize = 11)

# Header style for V-sheet header block rows
hdr_style <- createStyle(
  fgFill = UF_BLUE, fontColour = "white", textDecoration = "bold", wrapText = TRUE
)
sub_style <- createStyle(
  fgFill = UF_ORANGE, fontColour = "white", textDecoration = "bold"
)
bold_style <- createStyle(textDecoration = "bold")

write_sheet_header <- function(wb, sheet, check_id, lead, map_ids, purpose, supports) {
  hdr <- data.frame(
    Field = c("Check ID", "Lead", "Map IDs", "Purpose", "Run date", "Supports"),
    Value = c(check_id, lead, map_ids, purpose, run_date, supports),
    stringsAsFactors = FALSE
  )
  writeData(wb, sheet, hdr, startRow = 1)
  addStyle(wb, sheet, hdr_style, rows = 1, cols = 1:2, gridExpand = TRUE)
  setColWidths(wb, sheet, cols = 1:2, widths = c(18, 80))
}

# Helper: write a data.frame to a sheet starting at a given row
write_tbl <- function(wb, sheet, df, start_row, title = NULL) {
  if (!is.null(title)) {
    writeData(wb, sheet, data.frame(X = title), startRow = start_row, colNames = FALSE)
    addStyle(wb, sheet, bold_style, rows = start_row, cols = 1)
    start_row <- start_row + 1L
  }
  writeData(wb, sheet, df, startRow = start_row)
  start_row + nrow(df) + 2L
}

# ---- KEY ----
addWorksheet(wb, "KEY")
key_data <- data.frame(
  Field = c("Run date", "DuckDB path", "DuckDB mtime", "Script",
            "Suppression rule", "Results note"),
  Value = c(
    run_date, duckdb_path, duckdb_mtime,
    "R/191_am_verification.R",
    "Counts 1-10 displayed as '<11'. Complementary suppression on totals. Percentages blanked when derived from suppressed count.",
    "Results only. Verdicts are in AM-VERDICTS.md."
  ),
  stringsAsFactors = FALSE
)
key_sheet_guide <- data.frame(
  Sheet = c("V1_SOURCE","V2_INSURANCE","V3_DXDATE","V4_DXSCOPE","V5_ZIPCOVER","V6_DEATH","QC"),
  Description = c(
    "SOURCE values by CDM table — rows, patients, LNK counts, multi-source patients",
    "Manual 6-level hierarchy vs pipeline same-day resolved payer: agreement, cross-tab, UNMAPPED",
    "Manual two-step HL anchor (TR date -> first code date) vs get_hl_any_dx_ids(): day-diff bands",
    "7-day rule re-check by cancer category from DIAGNOSIS; code-path finding on non-HL scope",
    "Patient-level ZIP availability; encounter-level match_type and SES index coverage from R/116",
    "Death-before-last-treatment gaps; 14-day vs grace_days=30 comparison; DEATH_CAUSE scope",
    "One row per check: Check ID, Status, Reason, Map IDs, Provenance, Rows written, Suppression events"
  ),
  stringsAsFactors = FALSE
)
writeData(wb, "KEY", key_data, startRow = 1)
writeData(wb, "KEY", key_sheet_guide, startRow = nrow(key_data) + 3L)
addStyle(wb, "KEY", hdr_style, rows = 1, cols = 1:2, gridExpand = TRUE)
setColWidths(wb, "KEY", cols = 1:2, widths = c(20, 90))

# ---- V1_SOURCE ----
addWorksheet(wb, "V1_SOURCE")
write_sheet_header(wb, "V1_SOURCE",
  check_id = "V1_SOURCE",
  lead     = "L1",
  map_ids  = "L1",
  purpose  = "SOURCE values (normalized UPPER(TRIM())) by CDM table — rows, patients, LNK counts, patients with >1 distinct SOURCE",
  supports = "OBSERVED"
)
note_row <- 7L
writeData(wb, "V1_SOURCE",
  data.frame(Note = "Observed in this extract. R/169_single_source_care.R reads SOURCE from ENCOUNTER only."),
  startRow = note_row, colNames = FALSE)
if (r_v1$status == "COMPLETE" && length(r_v1$tables) > 0) {
  writeData(wb, "V1_SOURCE", r_v1$tables$v1_source, startRow = note_row + 2L)
}

# ---- V2_INSURANCE ----
addWorksheet(wb, "V2_INSURANCE")
write_sheet_header(wb, "V2_INSURANCE",
  check_id = "V2_INSURANCE",
  lead     = "L2",
  map_ids  = "L2",
  purpose  = "Manual 6-level same-day hierarchy re-derived from ENCOUNTER vs pipeline R/60 output. Agreement, cross-tab, UNMAPPED categories. Discordant IDs -> output/internal/.",
  supports = "OBSERVED"
)
next_row <- 8L
if (r_v2$status %in% c("COMPLETE","PARTIAL") && length(r_v2$tables) > 0) {
  next_row <- write_tbl(wb, "V2_INSURANCE", r_v2$tables$v2_agreement, next_row, "Agreement summary")
  next_row <- write_tbl(wb, "V2_INSURANCE", r_v2$tables$v2_crosstab,  next_row, "Cross-tab: manual level x pipeline category")
  next_row <- write_tbl(wb, "V2_INSURANCE", r_v2$tables$v2_unmapped,  next_row, "UNMAPPED pipeline categories (no clean manual equivalent)")
}
writeData(wb, "V2_INSURANCE",
  data.frame(Note = glue("V2 crosswalk: Self-pay, Other, Other govt are UNMAPPED (no clean manual equivalent). Discordant patient-days with IDs saved to output/internal/am_v2_discordant_{run_date}.rds.")),
  startRow = next_row, colNames = FALSE)

# ---- V3_DXDATE ----
addWorksheet(wb, "V3_DXDATE")
write_sheet_header(wb, "V3_DXDATE",
  check_id = "V3_DXDATE",
  lead     = "L3 / c1",
  map_ids  = "L3",
  purpose  = "Manual two-step rule (TR HL date, else first C81/201 code date) vs get_hl_any_dx_ids() live call. Anchor-source breakdown and day-difference bands.",
  supports = "OBSERVED"
)
next_row <- 8L
if (r_v3$status %in% c("COMPLETE","PARTIAL") && length(r_v3$tables) > 0) {
  next_row <- write_tbl(wb, "V3_DXDATE", r_v3$tables$v3_manual_source,  next_row, "Manual anchor source breakdown")
  next_row <- write_tbl(wb, "V3_DXDATE", r_v3$tables$v3_day_diff_bands, next_row, "Day difference bands (pipe - manual)")
}
writeData(wb, "V3_DXDATE",
  data.frame(Note = "c1 scope: see AM-VERDICTS.md. Note: get_hl_any_dx_ids() reads DIAGNOSIS only; it does not consult TUMOR_REGISTRY. Manual step 1 uses TUMOR_REGISTRY_ALL view (utils_duckdb.R:140)."),
  startRow = next_row, colNames = FALSE)

# ---- V4_DXSCOPE ----
addWorksheet(wb, "V4_DXSCOPE")
write_sheet_header(wb, "V4_DXSCOPE",
  check_id = "V4_DXSCOPE",
  lead     = "L4",
  map_ids  = "L4",
  purpose  = "7-day rule (>=2 encounters >=7 days apart) re-checked per cancer category from DIAGNOSIS. Code-path finding on whether rule applies to non-HL types.",
  supports = "OBSERVED"
)
next_row <- 8L
if (r_v4$status %in% c("COMPLETE","PARTIAL") && length(r_v4$tables) > 0) {
  next_row <- write_tbl(wb, "V4_DXSCOPE", r_v4$tables$v4_7day_by_category, next_row, "7-day rule by cancer category (independent re-check)")
  if (!is.null(r_v4$tables$v4_code_path_note)) {
    next_row <- write_tbl(wb, "V4_DXSCOPE", r_v4$tables$v4_code_path_note, next_row, "Code-path finding")
  }
}
writeData(wb, "V4_DXSCOPE",
  data.frame(Note = "Observed agreement does not show that the code applies the rule to non-HL types; see code-path finding above from Task 0 code reading."),
  startRow = next_row, colNames = FALSE)

# ---- V5_ZIPCOVER ----
addWorksheet(wb, "V5_ZIPCOVER")
write_sheet_header(wb, "V5_ZIPCOVER",
  check_id = "V5_ZIPCOVER",
  lead     = "L5 (data side)",
  map_ids  = "L5",
  purpose  = "Patient-level ZIP availability from LDS_ADDRESS_HISTORY. Encounter-level match_type and SES index (ADI, SDI) coverage from R/116 output.",
  supports = "OBSERVED"
)
next_row <- 8L
if (r_v5$status %in% c("COMPLETE","PARTIAL") && length(r_v5$tables) > 0) {
  if (!is.null(r_v5$tables$v5_patient_zip))
    next_row <- write_tbl(wb, "V5_ZIPCOVER", r_v5$tables$v5_patient_zip, next_row, "Patient ZIP availability (LDS_ADDRESS_HISTORY)")
  if (!is.null(r_v5$tables$v5_enc_match_type))
    next_row <- write_tbl(wb, "V5_ZIPCOVER", r_v5$tables$v5_enc_match_type, next_row, "Encounter match_type distribution (R/116)")
  if (!is.null(r_v5$tables$v5_ses_avail))
    next_row <- write_tbl(wb, "V5_ZIPCOVER", r_v5$tables$v5_ses_avail, next_row, "SES index availability (R/116)")
}
writeData(wb, "V5_ZIPCOVER",
  data.frame(Note = "Encounter-level coverage reflects the pipeline's temporal assignment; it describes coverage, it does not verify the assignment rule. Method verdict is code-reading only (L5 method, AM-VERDICTS.md)."),
  startRow = next_row, colNames = FALSE)

# ---- V6_DEATH ----
addWorksheet(wb, "V6_DEATH")
write_sheet_header(wb, "V6_DEATH",
  check_id = "V6_DEATH",
  lead     = "L6",
  map_ids  = "L6",
  purpose  = "Death-before-last-treatment gap bands. 14-day (manual) vs grace_days=30 (pipeline) removal comparison. DEATH_CAUSE scope: cohort record count and code-path finding.",
  supports = "OBSERVED"
)
next_row <- 8L
if (r_v6$status %in% c("COMPLETE","PARTIAL") && length(r_v6$tables) > 0) {
  next_row <- write_tbl(wb, "V6_DEATH", r_v6$tables$v6_gap_bands,    next_row, "Death-before-last-treatment gap bands")
  next_row <- write_tbl(wb, "V6_DEATH", r_v6$tables$v6_rule_compare, next_row, "14-day (manual) vs grace_days=30 (pipeline) removal")
  next_row <- write_tbl(wb, "V6_DEATH", r_v6$tables$v6_death_cause,  next_row, "DEATH_CAUSE scope")
  next_row <- write_tbl(wb, "V6_DEATH", r_v6$tables$v6_call_sites,   next_row, "Production call sites for resolve_death_date()")
}

# ---- QC ----
addWorksheet(wb, "QC")
qc_rows <- lapply(names(QC_ROWS), function(cid) {
  r <- QC_ROWS[[cid]]
  data.frame(
    Check_ID     = cid,
    Check_Status = r$status,
    Reason       = r$reason,
    Map_IDs      = r$map_ids,
    Provenance   = r$provenance,
    Rows_written = r$rows_written,
    Supp_events  = r$supp_events,
    stringsAsFactors = FALSE
  )
})
qc_df <- dplyr::bind_rows(qc_rows)
writeData(wb, "QC", qc_df)
addStyle(wb, "QC", hdr_style, rows = 1, cols = seq_len(ncol(qc_df)), gridExpand = TRUE)
setColWidths(wb, "QC", cols = seq_len(ncol(qc_df)),
  widths = c(14, 14, 60, 12, 80, 12, 12))

# Move KEY to first position
worksheetOrder(wb) <- c(
  which(names(wb) == "KEY"),
  which(names(wb) == "V1_SOURCE"),
  which(names(wb) == "V2_INSURANCE"),
  which(names(wb) == "V3_DXDATE"),
  which(names(wb) == "V4_DXSCOPE"),
  which(names(wb) == "V5_ZIPCOVER"),
  which(names(wb) == "V6_DEATH"),
  which(names(wb) == "QC")
)

# =============================================================================
# SECTION 14 — Save workbook
# =============================================================================

out_path <- file.path(CONFIG$output_dir, glue("am_verification_{run_date}.xlsx"))
saveWorkbook(wb, out_path, overwrite = TRUE)
message(glue("\nSaved: {out_path}"))

# =============================================================================
# SECTION 15 — Console QC summary
# =============================================================================

message("\n=== QC Summary ===")
for (i in seq_len(nrow(qc_df))) {
  message(glue("  {qc_df$Check_ID[i]}: {qc_df$Check_Status[i]} — {qc_df$Reason[i]}"))
}
message(glue("\nWorkbook: {out_path}"))

# Close connection only if this script opened it
if (isTRUE(opened_here)) close_pcornet_con()
message("\nR/191 done.")
