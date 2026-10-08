# ==============================================================================
# scratch/166_data_check.R -- Phase 166 HiPerGator data check
# READ-ONLY: prints only, writes nothing.
#
# Usage:
#   module load R/4.4.2
#   cd /blue/erin.mobley-hl.bcu/insurance_investigation
#   Rscript scratch/166_data_check.R 2>&1 | tee logs/166_data_check.log
#
# Purpose: Confirm data facts that 166-AUDIT.md marks PENDING-HPG so that
#   Plans 02-04 can proceed with confirmed column names, file paths, and
#   anthracycline presence counts.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
})

source("R/00_config.R")
if (!exists("load_surveillance_codeset")) source("R/utils/utils_surveillance.R")
if (!exists("get_hl_patient_ids"))         source("R/utils/utils_treatment.R")
if (!exists("compute_followup"))           source("R/utils/utils_surveillance.R")

cat("=== 166 Data Check ===\n")
cat(format(Sys.time()), "\n\n")

out_dir <- CONFIG$cache$outputs_dir
cat("outputs_dir:", out_dir, "\n\n")

# ==============================================================================
# 1. Locate treatment episode RDS files
# ==============================================================================

cat("--- 1. Treatment episode files ---\n")
ep_files <- list.files(out_dir, pattern = "\\.(rds|RDS)$", full.names = TRUE,
                       ignore.case = TRUE)
ep_180 <- ep_files[grepl("180|gantt_180|treatment_180|episodes_180", ep_files,
                          ignore.case = TRUE)]
ep_90  <- ep_files[grepl("90|episodes_90|treatment_90", ep_files, ignore.case = TRUE)]

cat("180-day episode files found:\n")
cat(if (length(ep_180) > 0) paste(" ", sort(ep_180), collapse = "\n") else "  (none)", "\n\n")

cat("90-day episode files found:\n")
cat(if (length(ep_90) > 0) paste(" ", sort(ep_90), collapse = "\n") else "  (none)", "\n\n")

# Select most recent of each
pick_latest <- function(paths) {
  if (length(paths) == 0) return(NULL)
  paths[order(file.info(paths)$mtime, decreasing = TRUE)[1]]
}

ep_180_latest <- pick_latest(ep_180)
ep_90_latest  <- pick_latest(ep_90)

# ==============================================================================
# 2. Inspect 180-day file (primary; fall back to 90 if absent)
# ==============================================================================

inspect_episode_file <- function(path, label) {
  cat(sprintf("--- Inspecting %s: %s ---\n", label, basename(path)))
  ep <- tryCatch(readRDS(path), error = function(e) {
    cat("  ERROR reading:", conditionMessage(e), "\n"); return(NULL)
  })
  if (is.null(ep)) return(invisible(NULL))
  cat("  nrow:", nrow(ep), "\n")
  cat("  names:", paste(names(ep), collapse = ", "), "\n\n")

  # Date-level drug rows: check if there are multiple rows per ID x episode x drug
  id_col  <- intersect(c("ID", "PATID", "id"), names(ep))[1]
  drug_col <- intersect(c("drug_name", "DRUG_NAME", "drug", "generic_name"), names(ep))[1]
  date_col <- intersect(c("treatment_date", "admin_date", "ADMIN_DATE",
                           "drug_date", "date"), names(ep))[1]
  ep_col   <- intersect(c("episode_id", "episode_num", "EPISODE_ID",
                           "episode", "ep_id"), names(ep))[1]
  fl_col   <- intersect(c("first_line", "FIRST_LINE", "firstline"), names(ep))[1]

  cat("  Detected columns:\n")
  cat("    id_col   :", ifelse(is.na(id_col),   "(not found)", id_col),   "\n")
  cat("    drug_col :", ifelse(is.na(drug_col), "(not found)", drug_col), "\n")
  cat("    date_col :", ifelse(is.na(date_col), "(not found)", date_col), "\n")
  cat("    ep_col   :", ifelse(is.na(ep_col),   "(not found)", ep_col),   "\n")
  cat("    fl_col   :", ifelse(is.na(fl_col),   "(not found)", fl_col),   "\n\n")

  if (!is.na(id_col) && !is.na(date_col) && !is.na(drug_col)) {
    # Check rows per ID x date x drug
    grain <- ep |>
      count(.data[[id_col]], .data[[date_col]], .data[[drug_col]],
            name = "n_rows") |>
      count(n_rows, name = "n_id_date_drug_combos")
    cat("  Rows per ID x date x drug grain (has_date_level_drug_rows check):\n")
    print(grain)
    cat("  => has_date_level_drug_rows:",
        if (nrow(ep) > n_distinct(ep[[id_col]])) "yes (rows > distinct IDs)" else "UNCLEAR",
        "\n\n")
  }

  # first_line population
  if (!is.na(fl_col)) {
    cat("  first_line flag:\n")
    print(table(ep[[fl_col]], useNA = "ifany"))
    cat("  => first_line_flag_populated:",
        if (any(!is.na(ep[[fl_col]]))) "yes" else "no (all NA)", "\n\n")
  } else {
    cat("  first_line column NOT FOUND in", label, "\n\n")
  }

  # Anthracycline drug counts
  if (!is.na(drug_col) && !is.na(id_col)) {
    # Apply DRUG_NAME_ALIASES if available
    drug_vals <- as.character(ep[[drug_col]])
    if (exists("DRUG_NAME_ALIASES", envir = .GlobalEnv)) {
      key <- tolower(trimws(drug_vals))
      aliased <- DRUG_NAME_ALIASES[key]
      drug_vals <- ifelse(!is.na(aliased), aliased, drug_vals)
    }
    ep_dn <- mutate(ep, drug_normalized = drug_vals)
    anthra_pattern <- "doxo|dauno|epiru|idaru|mitox"
    anthra <- ep_dn |>
      filter(grepl(anthra_pattern, drug_normalized, ignore.case = TRUE) |
             grepl(anthra_pattern, .data[[drug_col]], ignore.case = TRUE)) |>
      group_by(drug_normalized) |>
      summarise(n_patients = n_distinct(.data[[id_col]]), .groups = "drop") |>
      arrange(desc(n_patients))
    cat("  Anthracyclines present (after DRUG_NAME_ALIASES):\n")
    if (nrow(anthra) > 0) print(anthra) else cat("  (none matched pattern)\n")
    cat("\n")
  }

  invisible(ep)
}

if (!is.null(ep_180_latest)) {
  ep_180_obj <- inspect_episode_file(ep_180_latest, "180-day")
} else {
  cat("  No 180-day file found; skipping.\n\n")
  ep_180_obj <- NULL
}

if (!is.null(ep_90_latest)) {
  inspect_episode_file(ep_90_latest, "90-day")
}

# ==============================================================================
# 3. List event/dedup/events_win cached files
# ==============================================================================

cat("--- 3. Cached event/dedup/events_win files in outputs_dir ---\n")
event_files <- list.files(out_dir, pattern = "event|dedup|events_win",
                          ignore.case = TRUE, full.names = TRUE)
if (length(event_files) > 0) {
  cat(paste(" ", sort(event_files), collapse = "\n"), "\n")
} else {
  cat("  (none found — option_a (rebuild via function chain) required)\n")
}
cat("\n")

# ==============================================================================
# 4. Option-a dated-events function chain on 200-patient sample
# ==============================================================================

cat("--- 4. Option-a dated-events reconciliation (200-patient sample) ---\n")
cat("  Note: requires open_pcornet_con() and full DuckDB / CDM access.\n")
cat("  Attempting...\n\n")

tryCatch({
  if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()

  # Pull denominator
  if (!exists("get_hl_any_dx_ids")) source("R/utils/utils_treatment.R")
  if (!exists("get_last_activity")) source("R/utils/utils_activity.R")
  if (!exists("resolve_death_date")) source("R/utils/utils_death.R")

  EXTRACT_CUTOFF <- as.Date(EXTRACT_DATE)
  ANCHOR_DAY_IS_POST <- FALSE

  denom_all <- get_hl_any_dx_ids()
  denominator <- denom_all |> filter(!is.na(hl_anchor_date))
  cat("  Full denominator N:", nrow(denominator), "\n")

  # Sample 200 patients
  set.seed(20261008L)
  sample_ids <- sample(denominator$ID, min(200L, nrow(denominator)))
  denom_sample <- filter(denominator, ID %in% sample_ids)
  cat("  Sample N:", nrow(denom_sample), "\n\n")

  # Load codeset and modality lookup
  codeset_full <- load_surveillance_codeset()
  EXCLUDED_CDM_TABLES <- c("DIAGNOSIS")
  codeset <- codeset_full |> filter(!cdm_table %in% EXCLUDED_CDM_TABLES)
  analytes   <- load_lab_analytes(codeset = codeset)
  mod_lookup <- load_modality_lookup(codeset = codeset)

  # DuckDB tables
  lazy_table <- function(name) get_pcornet_table(name)
  proc_tbl <- lazy_table("PROCEDURES")
  lab_tbl  <- lazy_table("LAB_RESULT_CM")
  death_tbl <- lazy_table("DEATH")
  con <- dbplyr::remote_con(proc_tbl)

  hl_ids_tbl <- dplyr::copy_to(con, tibble(ID = denom_sample$ID),
                               name = "tmp_166_sample_ids",
                               temporary = TRUE, overwrite = TRUE)

  pick_date <- function(df, cols) {
    out <- rep(as.Date(NA), nrow(df))
    for (cl in intersect(cols, names(df)))
      out <- dplyr::coalesce(out, parse_pcornet_date(df[[cl]]))
    out
  }
  pull_codes <- function(tbl, cols, where) {
    tbl |> semi_join(hl_ids_tbl, by = "ID") |>
      filter(dplyr::sql(where)) |> select(any_of(cols)) |> collect()
  }
  codes_for <- function(table, match_type) {
    codeset$code_norm[codeset$cdm_table == table & codeset$match == match_type]
  }

  proc_raw <- pull_codes(
    proc_tbl, c("ID", "PX", "PX_TYPE", "PX_DATE", "ADMIT_DATE"),
    surv_code_where("PX", codes_for("PROCEDURES", "exact"),
                    codes_for("PROCEDURES", "prefix")))
  proc_events_in <- tibble(
    ID = proc_raw$ID, code_raw = proc_raw$PX, type_val = proc_raw$PX_TYPE,
    event_date = pick_date(proc_raw, c("PX_DATE", "ADMIT_DATE")),
    source_table = "PROCEDURES")

  lab_exact <- codes_for("LAB_RESULT_CM", "exact")
  lab_comp  <- unlist(lapply(codeset$code_norm[codeset$match == "component_all_same_day"],
                             surv_components))
  lab_codes <- unique(c(lab_exact, lab_comp))
  has_lab_px <- all(c("LAB_PX", "LAB_PX_TYPE") %in% colnames(lab_tbl))
  lab_where <- surv_code_where("LAB_LOINC", lab_codes, codes_for("LAB_RESULT_CM", "prefix"))
  if (has_lab_px)
    lab_where <- paste0("(", lab_where, " OR (TRIM(LAB_PX_TYPE) = 'LC' AND ",
                        surv_code_where("LAB_PX", lab_codes,
                                        codes_for("LAB_RESULT_CM", "prefix")), "))")
  lab_raw <- pull_codes(
    lab_tbl, c("ID", "LAB_LOINC", "LAB_PX", "LAB_PX_TYPE",
               "RESULT_DATE", "SPECIMEN_DATE", "LAB_ORDER_DATE"),
    lab_where)
  loinc_hit <- normalize_surv_code(dplyr::coalesce(lab_raw$LAB_LOINC, "")) %in% lab_codes |
    Reduce(`|`, lapply(codes_for("LAB_RESULT_CM", "prefix"), function(p)
      startsWith(normalize_surv_code(dplyr::coalesce(lab_raw$LAB_LOINC, "")), p)), FALSE)
  lab_code_raw <- as.character(if (has_lab_px) ifelse(loinc_hit, lab_raw$LAB_LOINC, lab_raw$LAB_PX)
                               else lab_raw$LAB_LOINC)
  lab_events_in <- tibble(ID = lab_raw$ID, code_raw = lab_code_raw, type_val = "",
                          event_date = pick_date(lab_raw, c("RESULT_DATE", "SPECIMEN_DATE",
                                                             "LAB_ORDER_DATE")),
                          source_table = "LAB_RESULT_CM")

  la_lab  <- analytes$code_norm[analytes$cdm_table == "LAB_RESULT_CM"]
  la_proc <- analytes$code_norm[analytes$cdm_table == "PROCEDURES"]
  an_lab_where <- surv_code_where("LAB_LOINC", la_lab)
  if (has_lab_px)
    an_lab_where <- paste0("(", an_lab_where, " OR (TRIM(LAB_PX_TYPE) = 'LC' AND ",
                           surv_code_where("LAB_PX", la_lab), "))")
  an_lab_raw <- lab_tbl |> semi_join(hl_ids_tbl, by = "ID") |>
    filter(dplyr::sql(an_lab_where)) |>
    select(any_of(c("ID", "LAB_LOINC", "LAB_PX", "LAB_PX_TYPE",
                    "RESULT_DATE", "SPECIMEN_DATE", "LAB_ORDER_DATE"))) |>
    distinct() |> collect()
  an_loinc <- normalize_surv_code(dplyr::coalesce(an_lab_raw$LAB_LOINC, ""))
  an_lab_code <- as.character(if (has_lab_px) ifelse(an_loinc %in% la_lab,
                                                     an_lab_raw$LAB_LOINC, an_lab_raw$LAB_PX)
                              else an_lab_raw$LAB_LOINC)
  an_proc_raw <- proc_tbl |> semi_join(hl_ids_tbl, by = "ID") |>
    filter(dplyr::sql(surv_code_where("PX", la_proc))) |>
    select(any_of(c("ID", "PX", "PX_TYPE", "PX_DATE", "ADMIT_DATE"))) |>
    distinct() |> collect()
  analyte_hits <- map_analyte_hits(
    bind_rows(
      tibble(ID = an_lab_raw$ID, code_raw = an_lab_code, type_val = "",
             event_date = pick_date(an_lab_raw, c("RESULT_DATE", "SPECIMEN_DATE", "LAB_ORDER_DATE")),
             cdm_table = "LAB_RESULT_CM"),
      tibble(ID = an_proc_raw$ID, code_raw = an_proc_raw$PX, type_val = an_proc_raw$PX_TYPE,
             event_date = pick_date(an_proc_raw, c("PX_DATE", "ADMIT_DATE")),
             cdm_table = "PROCEDURES")) |> filter(!is.na(event_date)),
    analytes)

  # Follow-up for sample
  demo_tbl <- lazy_table("DEMOGRAPHIC")
  activity <- get_last_activity(con, denom_sample, EXTRACT_CUTOFF)
  death_raw <- death_tbl |> semi_join(hl_ids_tbl, by = "ID") |>
    select(any_of(c("ID", "DEATH_DATE", "DEATH_SOURCE"))) |> collect()
  death_rows <- tibble(
    ID           = death_raw$ID,
    DEATH_DATE   = parse_pcornet_date(death_raw$DEATH_DATE),
    DEATH_SOURCE = if ("DEATH_SOURCE" %in% names(death_raw)) death_raw$DEATH_SOURCE else NA_character_)
  death_resolved <- resolve_death_date(death_rows, activity, grace_days = 30L)
  followup_sample <- compute_followup(denom_sample, activity, death_resolved, EXTRACT_CUTOFF)

  # Build events_win for sample
  matched_coded <- match_coded_events(
    bind_rows(proc_events_in, lab_events_in) |> filter(!is.na(event_date)), codeset)
  comp <- build_component_events(lab_events_in |> select(ID, code_raw, event_date), codeset)
  an_rules <- build_analyte_events(analyte_hits, codeset)
  matched_all <- bind_rows(matched_coded, comp$events, an_rules$events)
  events_win <- classify_event_window(matched_all, followup_sample,
                                      anchor_day_is_post = ANCHOR_DAY_IS_POST)

  cat("  events_win names:", paste(names(events_win), collapse = ", "), "\n")
  cat("  events_win nrow:", nrow(events_win), "\n\n")

  # Dated events from option-a function chain
  dated_events <- events_win |>
    filter(type_ok, tier == "primary", window == "post") |>
    distinct(ID, modality, event_date)
  cat("  dated_events (post, primary, deduped) nrow:", nrow(dated_events), "\n")
  cat("  dated_events columns:", paste(names(dated_events), collapse = ", "), "\n\n")

  # Build pt_modality from the full R/147 function (ground truth for reconciliation)
  pt_modality_sample <- build_patient_modality(events_win, followup_sample)
  cat("  pt_modality_sample nrow:", nrow(pt_modality_sample), "\n")

  # Cross-check: count distinct post-anchor primary dates per ID x modality
  # from the option-a dated events, compare to n_dates_post_primary
  dated_counts <- dated_events |>
    count(ID, modality, name = "n_dated")

  recon <- pt_modality_sample |>
    select(ID, modality, n_dates_post_primary) |>
    filter(n_dates_post_primary > 0) |>
    left_join(dated_counts, by = c("ID", "modality")) |>
    mutate(n_dated = coalesce(n_dated, 0L),
           match = n_dates_post_primary == n_dated)

  n_match    <- sum(recon$match, na.rm = TRUE)
  n_mismatch <- sum(!recon$match, na.rm = TRUE)
  cat("  dated_events_reconciliation_sample:\n")
  cat("    ID x modality rows with n_dates_post_primary > 0:", nrow(recon), "\n")
  cat("    Matching (n_dated == n_dates_post_primary):", n_match, "\n")
  cat("    Mismatching:", n_mismatch, "\n")
  if (n_mismatch > 0) {
    cat("  MISMATCH DETAILS (first 20):\n")
    print(filter(recon, !match) |> head(20))
    cat("  ACTION REQUIRED: Investigate which filter differs before Plans 02/03.\n")
  } else {
    cat("  => Reconciliation PASS: option_a function chain reproduces n_dates_post_primary exactly.\n")
  }

}, error = function(e) {
  cat("  Section 4 error:", conditionMessage(e), "\n")
  cat("  (If DuckDB/CDM not available, this is expected in a local-only run.)\n")
})
cat("\n")

# ==============================================================================
# 5. survival package check
# ==============================================================================

cat("--- 5. survival package ---\n")
surv_avail <- requireNamespace("survival", quietly = TRUE)
cat("  requireNamespace('survival'):", surv_avail, "\n")
if (surv_avail) {
  cat("  packageVersion('survival'):", as.character(packageVersion("survival")), "\n")
} else {
  cat("  ACTION: renv::install('survival'); renv::snapshot() required before Plan 03.\n")
}
cat("\n")

cat("=== 166 Data Check Complete ===\n")
cat(format(Sys.time()), "\n")
