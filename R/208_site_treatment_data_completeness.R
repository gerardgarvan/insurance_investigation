# ==============================================================================
# 208_site_treatment_data_completeness.R -- W-NOTX: per-site treatment-data
#                                           completeness (analysis only)
# ==============================================================================
# Unit: each SOURCE (site) present in ENCOUNTER.
# Per site:
#   - patients and encounters (ENCOUNTER)
#   - for PROCEDURES, PRESCRIBING, MED_ADMIN, DISPENSING, DIAGNOSIS: any rows from
#     that SOURCE (table SOURCE column; fall back to ENCOUNTERID -> ENCOUNTER.SOURCE
#     when a table has no SOURCE), rows per 100 encounters, patients with >= 1 row,
#     min / max date (dates before 1990-01-01 ignored)
#   - share of confirmed-cohort patients whose R/169 primary_source is the site and
#     who have any chemotherapy-type record: get_chemo_hits() on PRESCRIBING /
#     MED_ADMIN / DISPENSING; CPT/HCPCS J9xxx / Q5xxx in PROCEDURES; Z51.11 / Z51.12
#     in DIAGNOSIS
#   - R/203 no-treatment % among observable patients by primary source, alongside
# Flags: a treatment table (PROCEDURES, PRESCRIBING, MED_ADMIN, DISPENSING) that is
# empty for the site, or whose rows per 100 encounters is < 10% of the median rate
# (median over sites with a non-zero rate in that table).
#
# Input names: R/01_load_pcornet.R column specs (ENCOUNTER: ID, ENCOUNTERID, SOURCE;
# PROCEDURES: PX, PX_TYPE, PX_DATE; PRESCRIBING: RX_ORDER_DATE; MED_ADMIN:
# MEDADMIN_START_DATE; DISPENSING: DISPENSE_DATE; DIAGNOSIS: DX, DX_DATE; every
# table SOURCE), .planning/schemas/203_schema_inputs_20261114.md (confirmed cohort,
# single_source_care_20261008.rds: ID, primary_source). Checked at run time; the
# 261114-uzz SUMMARY requests a probe of the CDM tables.
#
# Pinned inputs (env var, dated default; KEY records pinned TRUE/FALSE):
#   R208_COHORT_RDS  output/confirmed_hl_cohort.rds
#   R208_SSC_RDS     output/internal/single_source_care_20261008.rds   (NOT *_parts_*)
#   R208_203_RDS     newest output/internal/203_no_treatment_characterization_<YYYYMMDD>[_vN].rds
#                    by FILE NAME (user-specified "newest"; never file.mtime). Set the
#                    env var to pin; the chosen file is printed and recorded in KEY.
#
# Outputs:
#   output/208_site_treatment_data_completeness_YYYYMMDD.xlsx
#     (KEY, A_site_table_presence, A2_site_table_detail, B_site_treatment_capture,
#      C_vs_203_no_tx, QC); no patient IDs
#   output/internal/208_site_treatment_capture_patients_YYYYMMDD.rds (IDs: internal)
#
# Run interactively on HiPerGator:
#   module load R/4.5; R --no-save
#   source("R/208_site_treatment_data_completeness.R", local = new.env(parent = globalenv()))
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(openxlsx)
})

source("R/00_config.R")
source("R/utils/utils_duckdb.R")
source("R/utils/utils_treatment.R")
message("=== R/208: Site treatment-data completeness (W-NOTX) ===\n")

if (IS_LOCAL) {
  stop("R/208 reads the PCORnet CDM tables (DuckDB) and cohort outputs, which exist only on ",
       "HiPerGator. Run interactively after `module load R/4.5`.")
}

# --- HELPERS ------------------------------------------------------------------
fmt_sup <- function(n) {
  n <- as.integer(n)
  ifelse(is.na(n), NA_character_,
         ifelse(n >= 1L & n <= 10L, "<11", format(n, big.mark = ",", trim = TRUE)))
}
pct_sup <- function(num, den) {
  ifelse(!is.na(num) & !is.na(den) & num >= 11L & den >= 11L, round(100 * num / den, 1), NA_real_)
}
# Rate cell: "0" when no rows, "<11" when 1-10 rows, else rows per 100 encounters.
rate_cell <- function(rows, enc) {
  ifelse(is.na(rows) | rows == 0L, "0",
         ifelse(rows < 11L, "<11",
                ifelse(enc < 11L, "NA (<11 enc)", format(round(100 * rows / enc, 1), nsmall = 1, trim = TRUE))))
}
need_cols <- function(df, cols, what) {
  miss <- setdiff(cols, names(df))
  if (length(miss) > 0L)
    stop("[R208] ", what, ": missing columns ", paste(miss, collapse = ", "),
         ". Available: ", paste(sort(names(df)), collapse = ", "))
  invisible(df)
}
check_tbl_cols <- function(tbl, need, nm) {
  miss <- setdiff(need, colnames(tbl))
  if (length(miss) > 0L) {
    close_pcornet_con()
    stop("[R208] ", nm, " missing columns: ", paste(miss, collapse = ", "),
         "\n  available: ", paste(colnames(tbl), collapse = ", "))
  }
}
SENTINEL_ISO <- format(ENC_DATE_SENTINEL_BEFORE)   # "1990-01-01"; dates before are ignored

# --- PINNED INPUTS ------------------------------------------------------------
pin <- function(env, default) {
  v <- Sys.getenv(env, unset = "")
  list(path = if (nzchar(v)) v else default, pinned = nzchar(v))
}
int_dir <- file.path(CONFIG$output_dir, "internal")
dir.create(int_dir, showWarnings = FALSE, recursive = TRUE)
p_cohort <- pin("R208_COHORT_RDS", file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds"))
p_ssc    <- pin("R208_SSC_RDS", file.path(int_dir, "single_source_care_20261008.rds"))
p_203 <- {
  v <- Sys.getenv("R208_203_RDS", unset = "")
  if (nzchar(v)) list(path = v, pinned = TRUE) else {
    f <- list.files(int_dir, pattern = "^203_no_treatment_characterization_[0-9]{8}(_v[0-9]+)?[.]rds$",
                    full.names = TRUE)
    list(path = if (length(f) == 0L) "" else sort(f, decreasing = TRUE)[1L], pinned = FALSE)  # by name
  }
}
for (p in list(p_cohort, p_ssc, p_203)) {
  if (!nzchar(p$path) || !file.exists(p$path)) stop("[R208] input not found: '", p$path, "'")
}
message(glue("  cohort: {p_cohort$path}\n  ssc:    {p_ssc$path}\n  r203:   {p_203$path} (pinned: {p_203$pinned})"))
run_date <- format(Sys.Date(), "%Y%m%d")

# --- SECTION 1: SITES FROM ENCOUNTER -------------------------------------------
message("=== Section 1: ENCOUNTER by SOURCE ===")
open_pcornet_con()
enc_tbl <- get_pcornet_table("ENCOUNTER")
check_tbl_cols(enc_tbl, c("ID", "ENCOUNTERID", "SOURCE"), "ENCOUNTER")
site_enc <- enc_tbl |>
  group_by(SOURCE) |>
  summarise(n_encounters = n(), n_patients = n_distinct(ID)) |>
  collect() |>
  mutate(site = coalesce(as.character(SOURCE), "(blank)"),
         n_encounters = as.integer(n_encounters), n_patients = as.integer(n_patients)) |>
  select(site, n_encounters, n_patients)
close_pcornet_con()
sites <- site_enc$site
message(glue("  sites in ENCOUNTER: {length(sites)}: {paste(sort(sites), collapse = ', ')}"))

# --- SECTION 2: TABLE PRESENCE BY SITE ------------------------------------------
message("=== Section 2: Table presence by SOURCE ===")
TABLES <- tibble(
  table = c("PROCEDURES", "PRESCRIBING", "MED_ADMIN", "DISPENSING", "DIAGNOSIS"),
  date_col = c("PX_DATE", "RX_ORDER_DATE", "MEDADMIN_START_DATE", "DISPENSE_DATE", "DX_DATE"),
  treatment_table = c(TRUE, TRUE, TRUE, TRUE, FALSE))

table_by_site <- function(tbl_name, date_col) {
  open_pcornet_con()
  tb <- tryCatch(get_pcornet_table(tbl_name), error = function(e) NULL)
  if (is.null(tb)) {
    close_pcornet_con()
    return(tibble(table = tbl_name, site = character(), n_rows = integer(), n_patients = integer(),
                  min_date = character(), max_date = character(), link = "table not found"))
  }
  cols <- colnames(tb)
  check_tbl_cols(tb, c("ID", if (!is.na(date_col) && nzchar(date_col)) date_col), tbl_name)
  if ("SOURCE" %in% cols) {
    base <- tb |> mutate(.site = SOURCE); link <- "table SOURCE"
  } else if ("ENCOUNTERID" %in% cols) {
    e <- get_pcornet_table("ENCOUNTER") |> select(ENCOUNTERID, .site = SOURCE) |> distinct()
    base <- tb |> left_join(e, by = "ENCOUNTERID"); link <- "ENCOUNTERID -> ENCOUNTER.SOURCE"
  } else {
    close_pcornet_con()
    return(tibble(table = tbl_name, site = character(), n_rows = integer(), n_patients = integer(),
                  min_date = character(), max_date = character(),
                  link = "no SOURCE or ENCOUNTERID: not attributable"))
  }
  has_date <- !is.na(date_col) && nzchar(date_col)
  if (has_date) {
    # rename() + all_of() avoids !! / .data inside the lazy (dbplyr) mutate
    res <- base |>
      rename(.d_raw = all_of(date_col)) |>
      mutate(.d = as.character(.d_raw)) |>
      mutate(.d_ok = if_else(!is.na(.d) & .d >= SENTINEL_ISO, .d, NA_character_)) |>
      group_by(.site) |>
      summarise(n_rows = n(), n_patients = n_distinct(ID),
                min_date = min(.d_ok, na.rm = TRUE), max_date = max(.d_ok, na.rm = TRUE)) |>
      collect()
  } else {
    res <- base |>
      group_by(.site) |>
      summarise(n_rows = n(), n_patients = n_distinct(ID)) |>
      collect() |>
      mutate(min_date = NA_character_, max_date = NA_character_)
  }
  close_pcornet_con()
  res |>
    transmute(table = tbl_name, site = coalesce(as.character(.site), "(blank)"),
              n_rows = as.integer(n_rows), n_patients = as.integer(n_patients),
              min_date = substr(as.character(min_date), 1, 10),
              max_date = substr(as.character(max_date), 1, 10), link = link)
}
presence <- bind_rows(lapply(seq_len(nrow(TABLES)), function(i) {
  r <- table_by_site(TABLES$table[i], TABLES$date_col[i])
  message(glue("  {TABLES$table[i]}: {nrow(r)} site rows ({unique(r$link)[1]})"))
  r
}))
grid <- tidyr::expand_grid(site = sites, table = TABLES$table) |>
  left_join(select(presence, table, site, n_rows, n_patients, min_date, max_date, link),
            by = c("table", "site")) |>
  left_join(site_enc, by = "site") |>
  left_join(select(TABLES, table, treatment_table), by = "table") |>
  mutate(n_rows = coalesce(n_rows, 0L), n_patients = coalesce(n_patients, 0L),
         has_rows = n_rows > 0L,
         rate_per_100 = 100 * n_rows / n_encounters)
# Flags (treatment tables): empty, or < 10% of the median non-zero rate for that table.
med_rate <- grid |> filter(treatment_table, rate_per_100 > 0) |>
  group_by(table) |> summarise(median_rate = median(rate_per_100), .groups = "drop")
grid <- grid |>
  left_join(med_rate, by = "table") |>
  mutate(flag = case_when(
    !treatment_table ~ "",
    !has_rows ~ "EMPTY",
    !is.na(median_rate) & rate_per_100 < 0.1 * median_rate ~ "< 10% of median rate",
    TRUE ~ ""))
message(glue("  flagged site x treatment-table cells: {sum(grid$flag != '')}"))

sheet_A <- grid |>
  select(site, table, n_encounters, rows = n_rows, rate_per_100 = rate_per_100, flag) |>
  mutate(cell = paste0(rate_cell(rows, n_encounters),
                       ifelse(flag != "", paste0(" [", flag, "]"), ""))) |>
  select(site, table, cell) |>
  tidyr::pivot_wider(names_from = table, values_from = cell) |>
  left_join(site_enc, by = "site") |>
  transmute(Site = site, `Patients (ENCOUNTER)` = fmt_sup(n_patients),
            `Encounters` = fmt_sup(n_encounters),
            `PROCEDURES rows/100 enc` = PROCEDURES, `PRESCRIBING rows/100 enc` = PRESCRIBING,
            `MED_ADMIN rows/100 enc` = MED_ADMIN, `DISPENSING rows/100 enc` = DISPENSING,
            `DIAGNOSIS rows/100 enc` = DIAGNOSIS) |>
  arrange(Site)
sheet_A2 <- grid |>
  transmute(Site = site, Table = table, `Attribution` = coalesce(link, "no rows"),
            `Any rows from this SOURCE` = has_rows, `Rows` = fmt_sup(n_rows),
            `Rows per 100 encounters` = ifelse(n_rows >= 11L & n_encounters >= 11L,
                                               round(rate_per_100, 1), NA_real_),
            `Patients with >= 1 row` = fmt_sup(n_patients),
            `Min date (>= 1990)` = ifelse(n_rows >= 11L, min_date, NA_character_),
            `Max date` = ifelse(n_rows >= 11L, max_date, NA_character_),
            Flag = flag) |>
  arrange(Site, Table)

# --- SECTION 3: TREATMENT CAPTURE BY PRIMARY SOURCE ------------------------------
message("=== Section 3: Cohort chemotherapy-type records by primary source ===")
cohort <- readRDS(p_cohort$path); need_cols(cohort, "ID", "confirmed_hl_cohort")
cohort_ids <- as.character(unique(cohort$ID))
ssc <- readRDS(p_ssc$path); need_cols(ssc, c("ID", "primary_source"), "R/169 single_source_care")
pt <- tibble(ID = cohort_ids) |>
  left_join(transmute(ssc, ID = as.character(ID), primary_source), by = "ID") |>
  mutate(primary_source = coalesce(as.character(primary_source), "(none)"))
message(glue("  cohort {nrow(pt)} patients; no primary_source: {sum(pt$primary_source == '(none)')}"))

ndc_crosswalk <- load_ndc_crosswalk()
open_pcornet_con()
CHEMO_RXNORM_208 <- TREATMENT_CODES$chemo_rxnorm
hits_rx <- get_chemo_hits("PRESCRIBING", CHEMO_RXNORM_208)
hits_ma <- get_chemo_hits("MED_ADMIN",   CHEMO_RXNORM_208, ndc_crosswalk)
hits_dp <- get_chemo_hits("DISPENSING",  CHEMO_RXNORM_208, ndc_crosswalk)
px_tbl <- get_pcornet_table("PROCEDURES")
check_tbl_cols(px_tbl, c("ID", "PX", "PX_TYPE"), "PROCEDURES")
hits_px <- px_tbl |>
  filter(PX_TYPE == "CH", PX %like% "J9%" | PX %like% "Q5%") |>
  select(ID) |> distinct() |> collect()
dx_tbl <- get_pcornet_table("DIAGNOSIS")
check_tbl_cols(dx_tbl, c("ID", "DX"), "DIAGNOSIS")
hits_dx <- dx_tbl |>
  filter(DX %like% "Z51.11%" | DX %like% "Z5111%" | DX %like% "Z51.12%" | DX %like% "Z5112%") |>
  select(ID, DX) |> collect() |>
  filter(gsub("\\.", "", toupper(DX)) %in% c("Z5111", "Z5112")) |>
  select(ID) |> distinct()
close_pcornet_con()

ids_of <- function(h) if (is.null(h)) character(0) else unique(as.character(h$ID))
ev_sets <- list(`CPT/HCPCS J9/Q5 (PROCEDURES)` = as.character(hits_px$ID),
                `Antineoplastic RxNorm (PRESCRIBING)` = ids_of(hits_rx),
                `Antineoplastic RxNorm/NDC (MED_ADMIN)` = ids_of(hits_ma),
                `Antineoplastic NDC (DISPENSING)` = ids_of(hits_dp),
                `Z51.11 / Z51.12 (DIAGNOSIS)` = as.character(hits_dx$ID))
for (nm in names(ev_sets)) pt[[nm]] <- pt$ID %in% ev_sets[[nm]]
pt$any_chemo <- Reduce(`|`, lapply(names(ev_sets), function(nm) pt[[nm]]))
message(glue("  cohort patients with any chemotherapy-type record: {sum(pt$any_chemo)}"))

sheet_B_raw <- pt |>
  group_by(primary_source) |>
  summarise(n_cohort = n(), n_any = sum(any_chemo),
            across(all_of(names(ev_sets)), sum), .groups = "drop") |>
  arrange(desc(n_cohort))
sheet_B <- sheet_B_raw |>
  transmute(`Primary source (R/169)` = primary_source,
            `Cohort patients n` = fmt_sup(n_cohort),
            `Any chemotherapy-type record n` = fmt_sup(n_any),
            `Any chemotherapy-type record %` = pct_sup(n_any, n_cohort),
            across(all_of(names(ev_sets)), ~ fmt_sup(.x)))
for (nm in names(ev_sets)) {
  sheet_B[[paste0(nm, " %")]] <- pct_sup(sheet_B_raw[[nm]], sheet_B_raw$n_cohort)
}

# --- SECTION 4: R/203 COMPARISON ------------------------------------------------
message("=== Section 4: Compare with R/203 (no-treatment % among observable) ===")
r203 <- readRDS(p_203$path)
need_cols(r203, c("ID", "group", "primary_source", "treatment_observable"), "R/203 char_pt")
c203 <- r203 |>
  mutate(primary_source = coalesce(as.character(primary_source), "(none)")) |>
  group_by(primary_source) |>
  summarise(n_total = n(),
            n_notx = sum(group == "no_treatment"),
            n_observable = sum(treatment_observable %in% TRUE),
            n_notx_observable = sum(group == "no_treatment" & treatment_observable %in% TRUE),
            .groups = "drop")
sheet_C_raw <- full_join(sheet_B_raw |> select(primary_source, n_cohort, n_any), c203,
                         by = "primary_source") |>
  arrange(desc(coalesce(n_total, n_cohort)))
cmp_rate <- grid |> filter(table %in% c("PROCEDURES", "PRESCRIBING", "MED_ADMIN", "DISPENSING")) |>
  group_by(site) |>
  summarise(n_flagged_tables = sum(flag != ""), .groups = "drop")
sheet_C <- sheet_C_raw |>
  left_join(cmp_rate, by = c("primary_source" = "site")) |>
  transmute(`Primary source` = primary_source,
            `R/203 patients n` = fmt_sup(n_total),
            `R/203 no_tx n` = fmt_sup(n_notx),
            `R/203 no_tx %` = pct_sup(n_notx, n_total),
            `R/203 observable n` = fmt_sup(n_observable),
            `R/203 no_tx among observable n` = fmt_sup(n_notx_observable),
            `R/203 no_tx % among observable` = pct_sup(n_notx_observable, n_observable),
            `208 cohort n` = fmt_sup(n_cohort),
            `208 any chemotherapy-type record %` = pct_sup(n_any, n_cohort),
            `208 flagged treatment tables at site (0-4)` = n_flagged_tables)

# --- SECTION 5: QC + KEY -----------------------------------------------------------
sheet_QC <- tibble(
  check = c("sites in ENCOUNTER", "ENCOUNTER encounters (sum over sites)",
            "confirmed cohort patients", "cohort patients with an R/169 primary_source",
            "cohort patients with any chemotherapy-type record",
            "R/203 patients", "R/203 no_treatment patients",
            "site x treatment-table cells flagged (EMPTY or < 10% of median)",
            "cohort patients not in R/203 table (should be 0)",
            "R/203 cohort patients not in the 208 cohort file (should be 0)"),
  value = c(as.character(length(sites)), fmt_sup(sum(site_enc$n_encounters)),
            fmt_sup(nrow(pt)), fmt_sup(sum(pt$primary_source != "(none)")),
            fmt_sup(sum(pt$any_chemo)), fmt_sup(nrow(r203)),
            fmt_sup(sum(r203$group == "no_treatment")), as.character(sum(grid$flag != "")),
            fmt_sup(length(setdiff(pt$ID, as.character(r203$ID)))),
            fmt_sup(length(setdiff(as.character(r203$ID), pt$ID)))))

sheet_KEY <- tibble(
  item = c("Purpose", "Unit", "Sheet: A_site_table_presence", "Sheet: A2_site_table_detail",
           "Sheet: B_site_treatment_capture", "Sheet: C_vs_203_no_tx", "Sheet: QC",
           "Flag rule", "Attribution", "Dates", "Chemotherapy-type record",
           "Pinned input: confirmed cohort", "Pinned input: R/169 single_source_care",
           "Pinned input: R/203 characterization", "Suppression", "Status"),
  value = c(
    "W-NOTX: is the low treatment capture at some sites a data-completeness problem? Descriptive only.",
    "Each SOURCE value (site) present in ENCOUNTER.",
    "Matrix site x table: rows per 100 encounters; '0' = no rows; '<11' = 1-10 rows; [EMPTY] / [< 10% of median rate] flags on treatment tables.",
    "Long form: any rows, rows, rows per 100 encounters, patients with >= 1 row, min / max date, attribution method.",
    "Confirmed-cohort patients by R/169 primary_source with any chemotherapy-type record, split by evidence type.",
    "R/169 primary_source: R/203 no_tx % (all and among observable, D rule, not applied) next to the 208 chemotherapy-type record share.",
    "Counts and join checks.",
    "Treatment tables = PROCEDURES, PRESCRIBING, MED_ADMIN, DISPENSING. EMPTY = no rows for the site. Median = median non-zero rows per 100 encounters across sites for that table.",
    "Table SOURCE column; ENCOUNTERID -> ENCOUNTER.SOURCE if the table has no SOURCE (column 'Attribution' on A2).",
    "Dates before 1990-01-01 (sentinels, e.g. 1901-01-01) ignored in min / max.",
    "get_chemo_hits() on PRESCRIBING / MED_ADMIN / DISPENSING (RxNorm; NDC via crosswalk); CPT/HCPCS J9xxx and Q5xxx (PX_TYPE CH) in PROCEDURES; Z51.11 / Z51.12 in DIAGNOSIS. Records anywhere in the CDM, not only at the primary source.",
    glue("{p_cohort$path} (pinned: {p_cohort$pinned})"),
    glue("{p_ssc$path} (pinned: {p_ssc$pinned})"),
    glue("{p_203$path} (pinned: {p_203$pinned}; unpinned = newest by file name)"),
    "Counts 1-10 shown as '<11'; percentages only when numerator and denominator >= 11. Rates per 100 encounters shown only when rows >= 11 and encounters >= 11. No patient IDs.",
    "Descriptive only; no causal interpretation."))

# --- SECTION 6: WRITE --------------------------------------------------------------
uf_blue <- "#0021A5"; uf_orange <- "#FA4616"
wb <- createWorkbook()
hdr <- createStyle(fontColour = "#FFFFFF", fgFill = uf_blue, textDecoration = "bold", halign = "left")
write_sheet <- function(wb, name, df) {
  addWorksheet(wb, name)
  writeData(wb, name, as.data.frame(df), headerStyle = hdr)
  setColWidths(wb, name, cols = seq_len(ncol(df)), widths = "auto")
}
write_sheet(wb, "KEY", sheet_KEY)
write_sheet(wb, "A_site_table_presence", sheet_A)
write_sheet(wb, "A2_site_table_detail", sheet_A2)
write_sheet(wb, "B_site_treatment_capture", sheet_B)
write_sheet(wb, "C_vs_203_no_tx", sheet_C)
write_sheet(wb, "QC", sheet_QC)
addStyle(wb, "KEY", createStyle(fgFill = uf_orange, fontColour = "#FFFFFF", textDecoration = "bold"),
         rows = 1, cols = seq_len(ncol(sheet_KEY)), stack = FALSE)
flag_style <- createStyle(fontColour = uf_orange, textDecoration = "bold")
conditionalFormatting(wb, "A_site_table_presence", cols = 4:8, rows = seq_len(nrow(sheet_A) + 1L),
                      rule = "[", type = "contains", style = flag_style)

out_xlsx <- versioned_output_path(CONFIG$output_dir, "208_site_treatment_data_completeness",
                                  ".xlsx", run_date = run_date)
saveWorkbook(wb, out_xlsx, overwrite = TRUE)
out_rds <- file.path(int_dir, glue("208_site_treatment_capture_patients_{run_date}.rds"))
saveRDS(pt, out_rds)

message(glue("\n  Output written: {out_xlsx}"))
message(glue("  Internal patient-level: {out_rds}"))
message("  Console checkpoint (paste back): A_site_table_presence and QC rows")
print(as.data.frame(sheet_A), row.names = FALSE)
print(as.data.frame(sheet_QC), row.names = FALSE)
message("\n=== R/208 complete ===")
