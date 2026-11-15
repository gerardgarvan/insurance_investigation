# ==============================================================================
# 207_radiation_gap_probe.R -- W-RAD: radiation evidence for registry-radiation
#                              patients with no pipeline Radiation / Proton episode
# ==============================================================================
# Findings report only. Does NOT change TREATMENT_CODES / DRUG_GROUPINGS, the
# delivered gantt_episodes_180.csv, or any pipeline script.
#
# Population: Phase 202 denominator patients (in gantt_episodes_180 AND tr_hl_dx
# TRUE) whose tumor registry says radiation was given (build_tr_treatment_flags(),
# trtype "radiation", tr_given TRUE), split into
#   (i)  has a pipeline Radiation or Proton Therapy episode (any date)
#   (ii) none (expected ~105 overall; ~84 inside the EHR coverage window)
# Coverage window = R/202 E_coverage_window logic: tr_coverage_filter() against the
# first ENCOUNTER.ADMIT_DATE >= ENC_DATE_SENTINEL_BEFORE (1990-01-01).
#
# Searches (DuckDB, filtered by code, never an IN() list of patient IDs):
#   PROCEDURES: PX_TYPE CH CPT 77xxx + HCPCS G6001-G6017, G0339, G0340, Q3001;
#               PX_TYPE 10 ICD-10-PCS "D*"; PX_TYPE 09 ICD-9 92.2x; PX_TYPE RE 033x
#   DIAGNOSIS : Z51.0, V58.0 (encounter for radiotherapy); Z92.3, V15.3 (history)
#   ENCOUNTER : radiation-oncology provider (PROVIDER_SPECIALTY_PRIMARY, NUCC
#               2085R0001X from PROVIDER_SPECIALTIES). ENC_TYPE has no radiation
#               value in PCORnet CDM, so it is not used.
#
# Input names: R/01_load_pcornet.R column specs (PROCEDURES: ID, PX, PX_TYPE,
# PX_DATE, SOURCE; DIAGNOSIS: ID, DX, DX_DATE, SOURCE; ENCOUNTER: ID, ADMIT_DATE,
# PROVIDERID, SOURCE; PROVIDER: PROVIDERID, PROVIDER_SPECIALTY_PRIMARY) and
# 202_schema_tr_treatment_cols_20261114.md / 203_schema_inputs_20261114.md. They
# are checked at run time (stop with available columns if absent). A probe of
# PROCEDURES / DIAGNOSIS / PROVIDER is requested in the 261114-uzz SUMMARY.
#
# Inputs (pinned; env var, dated default; KEY sheet records pinned TRUE/FALSE):
#   R207_GANTT_180  output/gantt_episodes_180.csv                       (read only)
#   R207_TR_FLAGS   output/internal/tr_lymphoma_flags_all_patients_20261113.rds
#
# Outputs:
#   output/207_radiation_gap_probe_YYYYMMDD.xlsx
#     (KEY, A_summary, B_codes_not_in_pipeline, C_codes_in_pipeline_but_missed,
#      D_by_source, QC); no patient IDs.
#   output/internal/207_radiation_gap_probe_patients_YYYYMMDD.rds  (IDs: internal)
#
# Run interactively on HiPerGator:
#   module load R/4.5; R --no-save
#   source("R/207_radiation_gap_probe.R", local = new.env(parent = globalenv()))
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(vroom)
  library(openxlsx)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_tr_sensitivity.R")
message("=== R/207: Radiation gap probe (W-RAD) ===\n")

if (IS_LOCAL) {
  stop("R/207 reads TUMOR_REGISTRY_ALL, PROCEDURES, DIAGNOSIS, ENCOUNTER and gantt_episodes_180, ",
       "which exist only on HiPerGator. Run interactively after `module load R/4.5`.")
}

# --- SUPPRESSION HELPERS ------------------------------------------------------
fmt_sup <- function(n) {
  n <- as.integer(n)
  ifelse(is.na(n), NA_character_,
         ifelse(n >= 1L & n <= 10L, "<11", format(n, big.mark = ",", trim = TRUE)))
}
pct_sup <- function(num, den) {
  ifelse(!is.na(num) & !is.na(den) & num >= 11L & den >= 11L, round(100 * num / den, 1), NA_real_)
}

# --- PINNED INPUTS ------------------------------------------------------------
pin <- function(env, default) {
  v <- Sys.getenv(env, unset = "")
  list(path = if (nzchar(v)) v else default, pinned = nzchar(v))
}
p_gantt <- pin("R207_GANTT_180", file.path(CONFIG$output_dir, "gantt_episodes_180.csv"))
p_flags <- pin("R207_TR_FLAGS",
               file.path(CONFIG$output_dir, "internal", "tr_lymphoma_flags_all_patients_20261113.rds"))
for (p in list(p_gantt, p_flags)) {
  if (!file.exists(p$path)) stop("[R207] input not found: ", p$path)
}
out_dir  <- file.path(CONFIG$output_dir)
int_dir  <- file.path(CONFIG$output_dir, "internal")
dir.create(int_dir, showWarnings = FALSE, recursive = TRUE)
run_date <- format(Sys.Date(), "%Y%m%d")

as_date_safe <- function(x) suppressWarnings(as.Date(substr(as.character(x), 1, 10)))
guard_date <- function(d) {
  d <- as_date_safe(d)
  d[!is.na(d) & d < ENC_DATE_SENTINEL_BEFORE] <- as.Date(NA)   # sentinel guard (< 1990)
  d
}

# --- CODE SETS ------------------------------------------------------------------
HCPCS_RAD <- c(sprintf("G60%02d", 1:17), "G0339", "G0340", "Q3001")
CPT_PLAN_DELIVERY_RANGE <- as.character(77261:77799)
RAD_ONC_TAXONOMY <- "2085R0001X"
stopifnot(RAD_ONC_TAXONOMY %in% PROVIDER_SPECIALTIES$cancer_oncology)

HIST_DX   <- c("Z92.3", "V15.3")
PROBE_DX  <- c(TREATMENT_CODES$radiation_dx_icd10, TREATMENT_CODES$radiation_dx_icd9, HIST_DX)
norm_dot <- function(x) toupper(gsub("\\s", "", as.character(x)))
# Undotted ICD codes -> dotted (dx: after 3 chars; ICD-9 procedure: after 2 chars)
dot_dx <- function(x) {
  x <- norm_dot(x)
  ifelse(grepl("\\.", x) | nchar(x) <= 3L, x, paste0(substr(x, 1, 3), ".", substr(x, 4, nchar(x))))
}
dot_px9 <- function(x) {
  x <- norm_dot(x)
  ifelse(grepl("\\.", x) | nchar(x) <= 2L, x, paste0(substr(x, 1, 2), ".", substr(x, 3, nchar(x))))
}

# Pipeline lists (radiation / proton), by code type.
PIPE_CH   <- unique(c(TREATMENT_CODES$radiation_cpt, TREATMENT_CODES$proton_cpt,
                      names(DRUG_GROUPINGS)[DRUG_GROUPINGS %in% "Radiation"]))
PIPE_PX09 <- TREATMENT_CODES$radiation_icd9
PIPE_PX10 <- TREATMENT_CODES$radiation_icd10pcs_prefixes
PIPE_DX   <- c(TREATMENT_CODES$radiation_dx_icd10, TREATMENT_CODES$radiation_dx_icd9)

code_type_label <- function(src_table, px_type) {
  dplyr::case_when(
    src_table == "PROCEDURES" & px_type == "CH" ~ "CPT/HCPCS (PX_TYPE CH)",
    src_table == "PROCEDURES" & px_type == "10" ~ "ICD-10-PCS (PX_TYPE 10)",
    src_table == "PROCEDURES" & px_type == "09" ~ "ICD-9 procedure (PX_TYPE 09)",
    src_table == "PROCEDURES" & px_type == "RE" ~ "Revenue code (PX_TYPE RE)",
    src_table == "DIAGNOSIS" ~ "ICD diagnosis",
    src_table == "ENCOUNTER" ~ "Provider specialty",
    TRUE ~ paste0("PX_TYPE ", px_type))
}
in_pipeline <- function(code, ctype) {
  dplyr::case_when(
    ctype == "CPT/HCPCS (PX_TYPE CH)"      ~ code %in% PIPE_CH,
    ctype == "ICD-9 procedure (PX_TYPE 09)" ~ dot_px9(code) %in% PIPE_PX09,
    ctype == "ICD-10-PCS (PX_TYPE 10)"     ~ vapply(code, function(cd)
      any(startsWith(cd, PIPE_PX10)), logical(1L), USE.NAMES = FALSE),
    ctype == "ICD diagnosis"               ~ dot_dx(code) %in% PIPE_DX,
    TRUE ~ FALSE)
}
code_family <- function(code, ctype) {
  dplyr::case_when(
    ctype == "CPT/HCPCS (PX_TYPE CH)" & code %in% c("G0339", "G0340") ~ "HCPCS image-guided robotic SRS (G0339/G0340)",
    ctype == "CPT/HCPCS (PX_TYPE CH)" & grepl("^G60", code) ~ "HCPCS radiation treatment delivery (G6001-G6017)",
    ctype == "CPT/HCPCS (PX_TYPE CH)" & code == "Q3001" ~ "HCPCS radioelements for brachytherapy (Q3001)",
    ctype == "CPT/HCPCS (PX_TYPE CH)" & code %in% CPT_PLAN_DELIVERY_RANGE ~ "CPT 77261-77799 radiation oncology chapter",
    ctype == "CPT/HCPCS (PX_TYPE CH)" ~ "CPT 77xxx outside 77261-77799 (imaging / other)",
    ctype == "ICD-10-PCS (PX_TYPE 10)" & startsWith(code, "D7") ~ "ICD-10-PCS radiation, lymphatic / hematologic (D7*)",
    ctype == "ICD-10-PCS (PX_TYPE 10)" ~ "ICD-10-PCS radiation therapy section (D*), other body system",
    ctype == "ICD-9 procedure (PX_TYPE 09)" ~ "ICD-9 procedure 92.2x radiotherapy",
    ctype == "Revenue code (PX_TYPE RE)" ~ "Revenue code 033x radiation therapy",
    ctype == "ICD diagnosis" & dot_dx(code) %in% c("Z51.0", "V58.0") ~ "Encounter for radiotherapy",
    ctype == "ICD diagnosis" & dot_dx(code) %in% HIST_DX ~ "Personal history of irradiation",
    ctype == "Provider specialty" ~ "Encounter with radiation-oncology provider (NUCC 2085R0001X)",
    TRUE ~ NA_character_)
}
# TREATMENT = codes that record radiation planned / delivered (CPT 77261-77799, HCPCS
# G6001-G6017 / G0339 / G0340, revenue 033x, ICD-10-PCS D*, ICD-9 92.2x, Z51.0 / V58.0).
# SURVIVORSHIP/OTHER = history of irradiation, rad-onc provider visit, 77xxx imaging /
# guidance / DXA / breast imaging outside 77261-77799. Q3001 (brachytherapy radioelements)
# is classed TREATMENT (assumption; it is a brachytherapy supply code).
OTHER_FAMILIES <- c("Personal history of irradiation",
                    "Encounter with radiation-oncology provider (NUCC 2085R0001X)",
                    "CPT 77xxx outside 77261-77799 (imaging / other)")
CLASS_TREAT <- "TREATMENT"
CLASS_OTHER <- "SURVIVORSHIP/OTHER"
code_class_of <- function(family) {
  dplyr::if_else(is.na(family) | family %in% OTHER_FAMILIES, CLASS_OTHER, CLASS_TREAT)
}
WINDOW_D <- 180L
DX_WINDOW_MAX <- 365L   # fallback window: 0 to +365 d from TR HL diagnosis date

# --- SECTION 1: POPULATION ------------------------------------------------------
message("=== Section 1: Population (Phase 202 denominator, TR radiation given) ===")
gantt <- vroom(p_gantt$path, col_types = cols(
  patient_id = col_character(), treatment_type = col_character(),
  tr_hl_dx = col_logical(), episode_start = col_date(format = ""),
  .default = col_character()), show_col_types = FALSE)
gantt_pts <- gantt |>
  distinct(patient_id, tr_hl_dx) |> group_by(patient_id) |> slice(1L) |> ungroup()
pipe_rad_ids <- unique(gantt$patient_id[gantt$treatment_type %in% c("Radiation", "Proton Therapy")])
pipe_rad_first <- gantt |>
  filter(treatment_type %in% c("Radiation", "Proton Therapy"), !is.na(episode_start)) |>
  group_by(patient_id) |> summarise(pipe_first_rad = min(episode_start), .groups = "drop") |>
  rename(ID = patient_id)

tr_flags <- readRDS(p_flags$path)
stopifnot(all(c("ID", "tr_hl_dx") %in% names(tr_flags)))
tr_hl_ids <- as.character(tr_flags$ID[tr_flag_to_logical(tr_flags$tr_hl_dx) %in% TRUE])
denom_ids <- intersect(gantt_pts$patient_id[gantt_pts$tr_hl_dx %in% TRUE], tr_hl_ids)
message(glue("  denominator (Gantt & tr_hl_dx TRUE): {length(denom_ids)} patients"))

tr_rad <- build_tr_treatment_flags(ids = denom_ids, sources = c("UFH", "ORL")) |>
  filter(trtype == "radiation", tr_given %in% TRUE)
pop <- tr_rad |>
  transmute(ID = as.character(ID), tr_rad_date = as.Date(tr_first_date)) |>
  group_by(ID) |> summarise(tr_rad_date = suppressWarnings(min(tr_rad_date, na.rm = TRUE)), .groups = "drop") |>
  mutate(tr_rad_date = if_else(is.finite(tr_rad_date), tr_rad_date, as.Date(NA)),
         group = if_else(ID %in% pipe_rad_ids, "i_pipeline_radiation", "ii_no_pipeline_radiation"))
message(glue("  TR radiation given: {nrow(pop)} patients; group (i) {sum(pop$group == 'i_pipeline_radiation')}; ",
             "group (ii) {sum(pop$group == 'ii_no_pipeline_radiation')}"))

# Coverage window (R/202 E_coverage_window): drop patients whose dated TR radiation precedes
# the first usable encounter or who have a TR date but no ENCOUNTER record.
open_pcornet_con()
first_enc <- get_pcornet_table("ENCOUNTER") |>
  filter(ADMIT_DATE >= !!ENC_DATE_SENTINEL_BEFORE) |>
  group_by(ID) |> summarise(first_enc_date = min(ADMIT_DATE, na.rm = TRUE)) |> collect()
close_pcornet_con()
first_enc <- first_enc |> mutate(ID = as.character(ID), first_enc_date = as.Date(first_enc_date))
cov <- tr_coverage_filter(rename(pop, tr_first_date = tr_rad_date), first_enc)
pop$in_window <- pop$ID %in% cov$in_window$ID
message(glue("  in EHR coverage window: {sum(pop$in_window)} (group ii: ",
             "{sum(pop$in_window & pop$group == 'ii_no_pipeline_radiation')})"))

# TR HL diagnosis date (fallback anchor): earliest non-missing date across HL-histology rows.
# Columns as in R/202 TR_DX_DATE_COLS (UFH DATE_OF_DIAGNOSIS, ORL DXDATE); used only if present.
message("=== Section 1b: TR HL diagnosis date ===")
TR_DX_DATE_COLS_207 <- c(UFH = "DATE_OF_DIAGNOSIS", ORL = "DXDATE")
open_pcornet_con()
tr_tbl <- get_pcornet_table("TUMOR_REGISTRY_ALL")
tr_cols <- colnames(tr_tbl)
hist_present <- intersect(TR_HIST_COLS, tr_cols)
dx_present <- intersect(unique(TR_DX_DATE_COLS_207), tr_cols)
tr_dx_note <- NULL
if (!all(c("ID", "SOURCE") %in% tr_cols) || length(hist_present) == 0L || length(dx_present) == 0L) {
  close_pcornet_con()
  tr_dx_note <- paste0("TR dx-date fallback unavailable (missing ID/SOURCE, histology or dx-date columns; ",
                       "dx cols present: ", paste(dx_present, collapse = ", "), ")")
  tr_dx <- tibble(ID = character(), tr_dx_date = as.Date(character()))
} else {
  tr_dx_raw <- tr_tbl |> select(all_of(unique(c("ID", "SOURCE", hist_present, dx_present)))) |> collect()
  close_pcornet_con()
  tr_dx_hl <- tr_dx_raw |>
    mutate(ID = as.character(ID)) |>
    filter(if_any(all_of(hist_present),
                  ~ substr(as.character(.x), 1, 4) %in% ICD_CODES$hl_histology),
           ID %in% pop$ID)
  tr_dx <- bind_rows(lapply(names(TR_DX_DATE_COLS_207), function(src) {
    col <- TR_DX_DATE_COLS_207[[src]]
    if (!col %in% names(tr_dx_hl)) return(tibble(ID = character(), tr_dx_date = as.Date(character())))
    d <- tr_dx_hl[tr_dx_hl$SOURCE == src, , drop = FALSE]
    tibble(ID = d$ID, tr_dx_date = guard_date(d[[col]]))
  })) |>
    filter(!is.na(tr_dx_date)) |>
    group_by(ID) |> summarise(tr_dx_date = min(tr_dx_date), .groups = "drop")
  rm(tr_dx_raw, tr_dx_hl)
}
pop <- pop |> left_join(tr_dx, by = "ID") |> left_join(pipe_rad_first, by = "ID")
message(glue("  TR radiation date available: {sum(!is.na(pop$tr_rad_date))} of {nrow(pop)}; ",
             "TR dx date available: {sum(!is.na(pop$tr_dx_date))}"))

# --- SECTION 2: EVIDENCE QUERIES (own open/close per table) ---------------------
check_cols <- function(tbl, need, nm) {
  miss <- setdiff(need, colnames(tbl))
  if (length(miss) > 0L) {
    close_pcornet_con()
    stop("[R207] ", nm, " missing columns: ", paste(miss, collapse = ", "),
         "\n  available: ", paste(colnames(tbl), collapse = ", "))
  }
}

message("=== Section 2a: PROCEDURES ===")
open_pcornet_con()
px_tbl <- get_pcornet_table("PROCEDURES")
check_cols(px_tbl, c("ID", "PX", "PX_TYPE", "PX_DATE", "SOURCE"), "PROCEDURES")
px_raw <- px_tbl |>
  filter(
    (PX_TYPE == "CH" & (PX %like% "77%" | PX %in% !!HCPCS_RAD)) |
    (PX_TYPE == "10" & PX %like% "D%") |
    (PX_TYPE == "09" & (PX %like% "92.2%" | PX %like% "922%")) |
    (PX_TYPE == "RE" & PX %like% "033%")) |>
  select(ID, PX, PX_TYPE, PX_DATE, SOURCE) |>
  collect()
close_pcornet_con()
px_ev <- px_raw |>
  transmute(ID = as.character(ID), source_table = "PROCEDURES",
            code = norm_dot(PX), code_type = code_type_label("PROCEDURES", as.character(PX_TYPE)),
            ev_date = guard_date(PX_DATE), site = coalesce(as.character(SOURCE), "(blank)"))
message(glue("  PROCEDURES radiation-like rows (all patients): {nrow(px_ev)}"))
rm(px_raw)

message("=== Section 2b: DIAGNOSIS ===")
open_pcornet_con()
dx_tbl <- get_pcornet_table("DIAGNOSIS")
check_cols(dx_tbl, c("ID", "DX", "DX_DATE", "SOURCE"), "DIAGNOSIS")
dx_raw <- dx_tbl |>
  filter(DX %like% "Z51.0%" | DX %like% "Z510%" | DX %like% "V58.0%" | DX %like% "V580%" |
         DX %like% "Z92.3%" | DX %like% "Z923%" | DX %like% "V15.3%" | DX %like% "V153%") |>
  select(ID, DX, DX_DATE, SOURCE) |>
  collect()
close_pcornet_con()
dx_ev <- dx_raw |>
  mutate(code = dot_dx(DX)) |>
  filter(code %in% PROBE_DX) |>
  transmute(ID = as.character(ID), source_table = "DIAGNOSIS", code,
            code_type = code_type_label("DIAGNOSIS", NA_character_),
            ev_date = guard_date(DX_DATE), site = coalesce(as.character(SOURCE), "(blank)"))
message(glue("  DIAGNOSIS radiation-like rows (all patients): {nrow(dx_ev)}"))
rm(dx_raw)

message("=== Section 2c: ENCOUNTER x PROVIDER (radiation-oncology specialty) ===")
enc_note <- NULL
enc_ev <- px_ev[0, ]
open_pcornet_con()
prov_tbl <- tryCatch(get_pcornet_table("PROVIDER"), error = function(e) NULL)
if (is.null(prov_tbl) || !all(c("PROVIDERID", "PROVIDER_SPECIALTY_PRIMARY") %in% colnames(prov_tbl))) {
  close_pcornet_con()
  enc_note <- "PROVIDER table or PROVIDER_SPECIALTY_PRIMARY absent: encounter-specialty search skipped"
} else {
  rad_prov <- prov_tbl |>
    filter(PROVIDER_SPECIALTY_PRIMARY == !!RAD_ONC_TAXONOMY) |>
    select(PROVIDERID) |> distinct() |> collect()
  if (nrow(rad_prov) == 0L) {
    close_pcornet_con()
    enc_note <- glue("PROVIDER has no rows with PROVIDER_SPECIALTY_PRIMARY = {RAD_ONC_TAXONOMY}: encounter-specialty search found nothing")
  } else {
    enc_tbl <- get_pcornet_table("ENCOUNTER")
    check_cols(enc_tbl, c("ID", "ADMIT_DATE", "PROVIDERID", "SOURCE"), "ENCOUNTER")
    enc_raw <- enc_tbl |>
      filter(PROVIDERID %in% !!rad_prov$PROVIDERID) |>
      select(ID, ADMIT_DATE, SOURCE) |> collect()
    close_pcornet_con()
    enc_ev <- enc_raw |>
      transmute(ID = as.character(ID), source_table = "ENCOUNTER", code = RAD_ONC_TAXONOMY,
                code_type = code_type_label("ENCOUNTER", NA_character_),
                ev_date = guard_date(ADMIT_DATE), site = coalesce(as.character(SOURCE), "(blank)"))
    rm(enc_raw)
  }
}
message(glue("  ENCOUNTER radiation-oncology provider rows (all patients): {nrow(enc_ev)}",
             "{if (!is.null(enc_note)) paste0('  [', enc_note, ']') else ''}"))

# --- SECTION 3: EVIDENCE FOR THE POPULATION (join in R) -------------------------
ev <- bind_rows(px_ev, dx_ev, enc_ev) |>
  inner_join(select(pop, ID, group, in_window, tr_rad_date, tr_dx_date), by = "ID") |>
  mutate(in_pipe   = in_pipeline(code, code_type),
         family    = code_family(code, code_type),
         code_class = code_class_of(family),
         days_from_tr = as.integer(ev_date - tr_rad_date),
         days_from_dx = as.integer(ev_date - tr_dx_date))
message(glue("  evidence rows for the TR-radiation population: {nrow(ev)}"))

# --- SECTION 4: SHEETS ----------------------------------------------------------
code_table <- function(d_ii, d_i) {
  agg <- function(d, sfx) {
    d |>
      group_by(code, code_type, family, code_class, in_pipe) |>
      summarise("patients_{sfx}" := n_distinct(ID), "records_{sfx}" := n(),
                "n_dated_{sfx}" := sum(!is.na(days_from_tr)),
                "n_within90d_{sfx}" := sum(!is.na(days_from_tr) & abs(days_from_tr) <= 90L),
                "n_dx_dated_{sfx}" := sum(!is.na(days_from_dx)),
                "median_days_from_dx_{sfx}" := if (sum(!is.na(days_from_dx)) >= 11L)
                  as.numeric(median(days_from_dx, na.rm = TRUE)) else NA_real_,
                "median_days_from_tr_{sfx}" := if (sum(!is.na(days_from_tr)) >= 11L)
                  as.numeric(median(days_from_tr, na.rm = TRUE)) else NA_real_,
                .groups = "drop")
  }
  full_join(agg(d_ii, "ii"), agg(d_i, "i"), by = c("code", "code_type", "family", "code_class", "in_pipe")) |>
    mutate(across(starts_with(c("patients_", "records_", "n_dated_", "n_within90d_", "n_dx_dated_")),
                  ~ coalesce(.x, 0L))) |>
    arrange(desc(patients_ii), desc(patients_i), code)
}
display_code_table <- function(ct) {
  ct |>
    transmute(code, code_type, code_class, description = family,
              `patients, group ii` = fmt_sup(patients_ii),
              `records, group ii` = fmt_sup(records_ii),
              `ii: evidence dated n` = fmt_sup(n_dated_ii),
              `ii: within 90 d of registry date n` = fmt_sup(n_within90d_ii),
              `ii: within 90 d % of dated` = pct_sup(n_within90d_ii, n_dated_ii),
              `ii: median days from TR radiation date` = median_days_from_tr_ii,
              `ii: evidence dated n (TR dx date)` = fmt_sup(n_dx_dated_ii),
              `ii: median days from TR dx date` = median_days_from_dx_ii,
              `patients, group i (comparison)` = fmt_sup(patients_i),
              `records, group i (comparison)` = fmt_sup(records_i))
}

grp_ii <- "ii_no_pipeline_radiation"
ev_ii  <- filter(ev, group == grp_ii)
ev_i   <- filter(ev, group == "i_pipeline_radiation")
ct_all <- code_table(ev_ii, ev_i)

# A_summary: per population scope, group (ii) and group (i)
summ_one <- function(pp, e, label) {
  n <- nrow(pp)
  e <- e[e$ID %in% pp$ID, ]
  ids_any   <- unique(e$ID)
  tr_e      <- e[e$code_class == CLASS_TREAT, ]
  ids_tr    <- unique(tr_e$ID)
  ids_tr_w  <- unique(tr_e$ID[!is.na(tr_e$days_from_tr) & abs(tr_e$days_from_tr) <= WINDOW_D])
  ids_tr_dx <- unique(tr_e$ID[!is.na(tr_e$days_from_dx) & tr_e$days_from_dx >= 0L &
                                tr_e$days_from_dx <= DX_WINDOW_MAX])
  ids_other <- setdiff(ids_any, ids_tr)
  tibble(scope = label, n_patients = n,
         n_any = length(ids_any),
         n_with_tr_date = sum(!is.na(pp$tr_rad_date)),
         n_with_dx_date = sum(!is.na(pp$tr_dx_date)),
         n_tx_window = length(ids_tr_w),
         n_tx_dx_window = length(ids_tr_dx),
         n_tx_any_time = length(ids_tr),
         n_other_only = length(ids_other),
         n_none = n - length(ids_any))
}
sheet_A_raw <- bind_rows(
  summ_one(filter(pop, group == grp_ii), ev_ii, "Group ii, all"),
  summ_one(filter(pop, group == grp_ii, in_window), ev_ii, "Group ii, inside EHR coverage window"),
  summ_one(filter(pop, group == "i_pipeline_radiation"), ev_i, "Group i, all (comparison)"),
  summ_one(filter(pop, group == "i_pipeline_radiation", in_window), ev_i, "Group i, inside window (comparison)"))
sheet_A <- sheet_A_raw |>
  transmute(
    Scope = scope,
    `Patients (TR radiation given)` = fmt_sup(n_patients),
    `Any radiation-like evidence n` = fmt_sup(n_any),
    `Any evidence, % of patients` = pct_sup(n_any, n_patients),
    `TREATMENT codes at any time n (primary evidence)` = fmt_sup(n_tx_any_time),
    `TREATMENT codes at any time, % of patients` = pct_sup(n_tx_any_time, n_patients),
    `n with TR radiation date available` = fmt_sup(n_with_tr_date),
    `TREATMENT codes within +/-180 d of TR radiation date n (secondary; among patients with TR date)` = fmt_sup(n_tx_window),
    `TREATMENT codes within +/-180 d, % of patients with TR date` = pct_sup(n_tx_window, n_with_tr_date),
    `n with TR HL diagnosis date available` = fmt_sup(n_with_dx_date),
    `TREATMENT codes 0 to +365 d of TR dx date n (secondary; all patients)` = fmt_sup(n_tx_dx_window),
    `TREATMENT codes 0 to +365 d of TR dx date, % of patients` = pct_sup(n_tx_dx_window, n_patients),
    `SURVIVORSHIP/OTHER evidence only n (no treatment code)` = fmt_sup(n_other_only),
    `No evidence n (likely outside-network care)` = fmt_sup(n_none),
    `No evidence, % of patients` = pct_sup(n_none, n_patients))

sheet_B <- ct_all |> filter(!in_pipe, patients_ii > 0L) |> display_code_table()
sheet_C <- ct_all |> filter(in_pipe, patients_ii > 0L) |> display_code_table()

sheet_D_raw <- ev |>
  group_by(group, source_table, site) |>
  summarise(patients = n_distinct(ID), records = n(),
            patients_not_in_lists = n_distinct(ID[!in_pipe]), .groups = "drop") |>
  arrange(group, source_table, desc(patients))
sheet_D <- sheet_D_raw |>
  transmute(Group = if_else(group == grp_ii, "ii (no pipeline radiation)", "i (pipeline radiation)"),
            `Source table` = source_table, `Record SOURCE (site)` = site,
            `Patients` = fmt_sup(patients), `Records` = fmt_sup(records),
            `Patients with evidence not in lists` = fmt_sup(patients_not_in_lists))

n_ii <- sum(pop$group == grp_ii); n_ii_win <- sum(pop$group == grp_ii & pop$in_window)
sheet_QC <- tibble(
  check = c("TR radiation given, Phase 202 denominator (patients)",
            "group (i) pipeline Radiation / Proton episode",
            "group (ii) none (expected ~105)",
            "group (ii) inside coverage window (expected ~84)",
            "group (ii) TR radiation date missing (patients)",
            "evidence rows, all patients: PROCEDURES / DIAGNOSIS / ENCOUNTER",
            "evidence rows with sentinel or missing date (< 1990 set to NA)",
            "pipeline code list sizes: CH / PX09 / PX10 prefixes / DX",
            "group sums agree (i + ii = TR radiation given)",
            "TR HL diagnosis date available (patients, all groups)",
            "group (i): first pipeline radiation episode date - TR radiation date, days: median (Q1 to Q3), n with both dates",
            "no patient IDs in any workbook sheet (by construction)"),
  value = c(fmt_sup(nrow(pop)), fmt_sup(sum(pop$group == "i_pipeline_radiation")),
            fmt_sup(n_ii), fmt_sup(n_ii_win),
            fmt_sup(sum(pop$group == grp_ii & is.na(pop$tr_rad_date))),
            paste(fmt_sup(nrow(px_ev)), fmt_sup(nrow(dx_ev)), fmt_sup(nrow(enc_ev)), sep = " / "),
            fmt_sup(sum(is.na(ev$ev_date))),
            paste(length(PIPE_CH), length(PIPE_PX09), length(PIPE_PX10), length(PIPE_DX), sep = " / "),
            as.character(sum(pop$group == "i_pipeline_radiation") + n_ii == nrow(pop)),
            paste0(fmt_sup(sum(!is.na(pop$tr_dx_date))),
                   if (!is.null(tr_dx_note)) paste0(" [", tr_dx_note, "]") else ""),
            {
              d_i <- pop |>
                filter(group == "i_pipeline_radiation", !is.na(pipe_first_rad), !is.na(tr_rad_date)) |>
                mutate(dd = as.integer(pipe_first_rad - tr_rad_date)) |> pull(dd)
              if (length(d_i) < 11L) "n < 11 (suppressed)" else {
                q <- stats::quantile(d_i, c(0.25, 0.5, 0.75), names = FALSE)
                sprintf("%.0f (%.0f to %.0f), n = %s", q[2], q[1], q[3], fmt_sup(length(d_i)))
              }
            },
            "TRUE"))

sheet_KEY <- tibble(
  item = c("Purpose", "Population", "Group (i)", "Group (ii)", "Coverage window",
           "Evidence searched", "Pipeline lists compared",
           "ENCOUNTER / PROVIDER", "Dates", "Sheet: A_summary", "Sheet: B_codes_not_in_pipeline",
           "Sheet: C_codes_in_pipeline_but_missed", "Sheet: D_by_source", "Sheet: QC",
           "Pinned input: gantt_episodes_180", "Pinned input: TR flags",
           "Suppression", "Code class", "Interpretation", "Status"),
  value = c(
    "W-RAD: radiation-like evidence for registry-radiation patients with no pipeline Radiation / Proton episode. Findings only; pipeline code lists unchanged.",
    "Phase 202 denominator patients (in gantt_episodes_180 and tr_hl_dx TRUE) with TR radiation given (build_tr_treatment_flags, UFH + ORL).",
    "Has a pipeline Radiation or Proton Therapy episode (any date).",
    "No pipeline Radiation or Proton Therapy episode.",
    "R/202 E_coverage_window logic: TR radiation date on/after first ENCOUNTER.ADMIT_DATE (>= 1990-01-01); undated kept; patients with a TR date and no encounter excluded.",
    "PROCEDURES: CPT 77xxx and HCPCS G6001-G6017, G0339, G0340, Q3001 (PX_TYPE CH); ICD-10-PCS D* (10); ICD-9 92.2x (09); revenue 033x (RE). DIAGNOSIS: Z51.0, V58.0, Z92.3, V15.3. ENCOUNTER: radiation-oncology provider.",
    "TREATMENT_CODES radiation_cpt, proton_cpt, radiation_icd9, radiation_icd10pcs_prefixes, radiation_dx_icd10/icd9 plus DRUG_GROUPINGS Radiation. Revenue codes and Z92.3 / V15.3 / specialty are in no pipeline list.",
    if (is.null(enc_note)) "Radiation-oncology provider = PROVIDER_SPECIALTY_PRIMARY 2085R0001X (PROVIDER_SPECIALTIES). ENC_TYPE has no radiation value in PCORnet CDM, so it is not used." else as.character(enc_note),
    "Evidence dates before 1990-01-01 are treated as missing. Days from TR radiation date = evidence date - TR first radiation date; days from TR dx date = evidence date - earliest TR HL diagnosis date (UFH DATE_OF_DIAGNOSIS, ORL DXDATE). Sheets B and C show both medians (suppressed if n < 11).",
    "Per scope. PRIMARY evidence = patients with TREATMENT codes at any time (incl. undated): group ii <11 vs group i 33/33 (read the counts in the rows). SECONDARY = window rows. Many group ii patients have no TR radiation date (see 'n with TR radiation date available'), so the +/-180 d test is shown only among patients with a TR radiation date, denominator = n with TR radiation date. Fallback window: TREATMENT codes 0 to +365 d of the TR HL diagnosis date, all patients, reported separately for group i and group ii. Also SURVIVORSHIP/OTHER evidence only, and no evidence. TREATMENT evidence counts all searched codes, whether or not in a pipeline list.",
    "Candidate codes to add: codes for group (ii) patients that are in no pipeline list. Counts and median days from the registry date; group (i) shown for comparison.",
    "Codes already in the pipeline lists but present for group (ii) patients. Non-empty = possible extraction or episode-building gap.",
    "Evidence by record SOURCE (site) and table.",
    "Counts and checks.",
    glue("{p_gantt$path} (pinned: {p_gantt$pinned})"),
    glue("{p_flags$path} (pinned: {p_flags$pinned})"),
    "Counts 1-10 shown as '<11'; percentages only when numerator and denominator >= 11. No patient IDs in the workbook.",
    "code_class (sheets B and C): TREATMENT = CPT 77261-77799, HCPCS G6001-G6017 / G0339 / G0340 / Q3001, revenue 033x, ICD-10-PCS D*, ICD-9 92.2x, Z51.0 / V58.0. SURVIVORSHIP/OTHER = history of irradiation (Z92.3 / V15.3), radiation-oncology provider visit (NUCC 2085R0001X), CPT 77xxx outside 77261-77799 (imaging, guidance, DXA, breast imaging).",
    "Working conclusion (pending the A_summary numbers): the gap is consistent with radiation delivered outside the network, not a pipeline code-list gap. Most non-pipeline evidence is survivorship or non-treatment imaging, not treatment.",
    "Findings report; descriptive only."))

# --- SECTION 5: WRITE -----------------------------------------------------------
uf_blue <- "#0021A5"; uf_orange <- "#FA4616"
wb <- createWorkbook()
hdr <- createStyle(fontColour = "#FFFFFF", fgFill = uf_blue, textDecoration = "bold", halign = "left")
write_sheet <- function(wb, name, df) {
  addWorksheet(wb, name)
  writeData(wb, name, as.data.frame(df), headerStyle = hdr)
  setColWidths(wb, name, cols = seq_len(ncol(df)), widths = "auto")
}
write_sheet(wb, "KEY", sheet_KEY)
write_sheet(wb, "A_summary", sheet_A)
write_sheet(wb, "B_codes_not_in_pipeline", sheet_B)
write_sheet(wb, "C_codes_in_pipeline_but_missed", sheet_C)
write_sheet(wb, "D_by_source", sheet_D)
write_sheet(wb, "QC", sheet_QC)
addStyle(wb, "KEY", createStyle(fgFill = uf_orange, fontColour = "#FFFFFF", textDecoration = "bold"),
         rows = 1, cols = seq_len(ncol(sheet_KEY)), stack = FALSE)

out_xlsx <- versioned_output_path(out_dir, "207_radiation_gap_probe", ".xlsx", run_date = run_date)
saveWorkbook(wb, out_xlsx, overwrite = TRUE)

# Patient-level (internal only): group, window flag, evidence summary per patient.
pt_int <- pop |>
  left_join(ev |> group_by(ID) |>
              summarise(n_evidence_rows = n(), any_not_in_lists = any(!in_pipe),
                        codes_not_in_lists = paste(sort(unique(code[!in_pipe])), collapse = ";"),
                        .groups = "drop"), by = "ID") |>
  mutate(n_evidence_rows = coalesce(n_evidence_rows, 0L),
         any_not_in_lists = coalesce(any_not_in_lists, FALSE))
out_rds <- file.path(int_dir, glue("207_radiation_gap_probe_patients_{run_date}.rds"))
saveRDS(pt_int, out_rds)

message(glue("\n  Output written: {out_xlsx}"))
message(glue("  Internal patient-level: {out_rds}"))
message("  Console checkpoint (paste back): A_summary rows and QC rows")
print(as.data.frame(sheet_A), row.names = FALSE)
print(as.data.frame(sheet_QC), row.names = FALSE)
message("\n=== R/207 complete ===")
