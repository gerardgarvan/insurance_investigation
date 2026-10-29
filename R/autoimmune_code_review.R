# autoimmune_code_review.R
# =============================================================================
# Purpose:  List every candidate autoimmune diagnosis code actually present for
#           the HL cohort, so colleagues can mark which codes are appropriate
#           before AUTOIMMUNE_DX_CODES is written (Phase 192.1).
#
#           ICD-10 candidates: codes matching the requested prefixes
#             M05*, M06*, M31.3*, M31.7, L10.0, M08.3, M08.09, M08.00, L40*
#           ICD-9 candidates: every ICD-9 code the CMS 2018 GEMs link to any of
#             those ICD-10 codes (either direction). Each ICD-9 code is labelled
#             STRICT (all its GEM targets are in the requested list) or BROADER
#             (some targets fall outside), with the targets listed.
#
# Inputs:   DuckDB DIAGNOSIS; get_hl_any_dx_ids()
#           docs/reference/2018_I10gem.txt, docs/reference/2018_I9gem.txt
#
# Output:   CONFIG$output_dir/autoimmune_code_review_<YYYYMMDD>.xlsx
#           Sheets: KEY, Codes_found, ICD9_candidates_not_found
#           Patient/record counts 1-10 shown as "<11". No patient IDs.
#
# Usage (HiPerGator, interactive):
#   cd /blue/erin.mobley-hl.bcu/insurance_investigation
#   module load R/4.5 ; R
#   here::i_am("R/00_config.R"); source("autoimmune_code_review.R")
# =============================================================================

source(here::here("R/00_config.R"))
suppressPackageStartupMessages({ library(dplyr); library(openxlsx); library(glue) })

run_date <- format(Sys.Date(), "%Y%m%d")

REQ_ICD10 <- c(
  "M05"   = "Rheumatoid arthritis with rheumatoid factor (family)",
  "M06"   = "Other rheumatoid arthritis (family)",
  "M313"  = "Granulomatosis with polyangiitis (M31.3, M31.30, M31.31)",
  "M317"  = "Microscopic polyangiitis",
  "L100"  = "Pemphigus vulgaris",
  "M083"  = "Juvenile rheumatoid polyarthritis (seronegative)",
  "M0809" = "Unspecified juvenile rheumatoid arthritis, multiple sites",
  "M0800" = "Unspecified juvenile rheumatoid arthritis of unspecified site",
  "L40"   = "Psoriasis (family)"
)
req_prefixes <- names(REQ_ICD10)

sup <- function(n) ifelse(is.na(n), NA_character_,
                          ifelse(n >= 1 & n <= 10, "<11", format(n, big.mark = ",", trim = TRUE)))
starts_any <- function(x, prefixes) Reduce(`|`, lapply(prefixes, function(p) startsWith(x, p)))
norm <- function(x) toupper(gsub("[.[:space:]]", "", x))

# -----------------------------------------------------------------------------
# 1. GEM candidates
# -----------------------------------------------------------------------------
read_gem <- function(path) {
  stopifnot(file.exists(path))
  g <- read.table(path, header = FALSE, colClasses = "character",
                  col.names = c("source", "target", "flags"))
  g$source <- norm(g$source); g$target <- norm(g$target)
  g
}
gem10 <- read_gem(here::here("docs/reference/2018_I10gem.txt"))  # ICD-10 -> ICD-9
gem9  <- read_gem(here::here("docs/reference/2018_I9gem.txt"))   # ICD-9  -> ICD-10

icd9_fwd <- gem10 |> filter(starts_any(source, req_prefixes), target != "NODX") |> pull(target)
icd9_bwd <- gem9  |> filter(starts_any(target, req_prefixes)) |> pull(source)
icd9_cand <- sort(unique(c(icd9_fwd, icd9_bwd)))

icd9_info <- gem9 |>
  filter(source %in% icd9_cand, target != "NODX") |>
  group_by(icd9 = source) |>
  summarise(
    gem_icd10_targets = paste(sort(unique(target)), collapse = "; "),
    targets_outside   = paste(sort(unique(target[!starts_any(target, req_prefixes)])), collapse = "; "),
    .groups = "drop") |>
  mutate(scope = ifelse(targets_outside == "", "STRICT", "BROADER"))
# ICD-9 codes reached only via the forward map (no backward rows) get BROADER-UNKNOWN
icd9_info <- full_join(tibble(icd9 = icd9_cand), icd9_info, by = "icd9") |>
  mutate(scope = coalesce(scope, "CHECK (no backward GEM row)"))

# -----------------------------------------------------------------------------
# 2. Codes present in DIAGNOSIS for the cohort
# -----------------------------------------------------------------------------
opened_here <- FALSE
if (!exists("pcornet_con", envir = .GlobalEnv) || !DBI::dbIsValid(pcornet_con)) {
  open_pcornet_con(); opened_here <- TRUE
}
cohort <- get_hl_any_dx_ids() |> distinct(ID)
duckdb::duckdb_register(pcornet_con, "rev_cohort", cohort)

found <- DBI::dbGetQuery(pcornet_con, "
  SELECT UPPER(REPLACE(REPLACE(TRIM(d.DX), '.', ''), ' ', '')) AS code,
         TRIM(CAST(d.DX_TYPE AS VARCHAR))                      AS dx_type,
         COUNT(*)                                              AS n_records,
         COUNT(DISTINCT d.ID)                                  AS n_patients,
         MIN(YEAR(CAST(COALESCE(d.DX_DATE, d.ADMIT_DATE) AS DATE))) AS first_year,
         MAX(YEAR(CAST(COALESCE(d.DX_DATE, d.ADMIT_DATE) AS DATE))) AS last_year
  FROM DIAGNOSIS d
  JOIN rev_cohort c ON c.ID = d.ID
  WHERE UPPER(LEFT(TRIM(d.DX), 1)) IN ('M', 'L')
     OR regexp_matches(TRIM(d.DX), '^[0-9]')
  GROUP BY 1, 2")

duckdb::duckdb_unregister(pcornet_con, "rev_cohort")
if (opened_here) close_pcornet_con()

is10 <- startsWith(found$dx_type, "10")
is09 <- startsWith(found$dx_type, "09") | found$dx_type == "9"

f10 <- found[is10 & starts_any(found$code, req_prefixes), ] |>
  mutate(system = "ICD-10",
         requested_family = vapply(code, function(cd) {
           hit <- req_prefixes[startsWith(cd, req_prefixes)]
           paste(REQ_ICD10[hit], collapse = "; ") }, character(1)),
         scope = "REQUESTED", gem_icd10_targets = NA_character_, targets_outside = NA_character_)

f09 <- found[is09 & found$code %in% icd9_cand, ] |>
  left_join(icd9_info, by = c("code" = "icd9")) |>
  mutate(system = "ICD-9", requested_family = NA_character_)

codes_found <- bind_rows(f10, f09) |>
  group_by(system, code, requested_family, scope, gem_icd10_targets, targets_outside) |>
  summarise(n_patients = sum(n_patients), n_records = sum(n_records),
            first_year = min(first_year, na.rm = TRUE), last_year = max(last_year, na.rm = TRUE),
            dx_type_values = paste(sort(unique(dx_type)), collapse = ", "),
            .groups = "drop") |>
  arrange(system == "ICD-9", code) |>
  transmute(
    System = system, Code = code,
    `Requested family (ICD-10)` = requested_family,
    `Scope (ICD-9)` = scope,
    `GEM ICD-10 targets (ICD-9)` = gem_icd10_targets,
    `Targets outside request` = targets_outside,
    `Patients` = sup(n_patients), `Records` = sup(n_records),
    `First year` = first_year, `Last year` = last_year,
    `DX_TYPE values` = dx_type_values,
    `Include? (Y/N)` = "", `Reviewer comment` = "")

not_found <- icd9_info |>
  filter(!icd9 %in% f09$code) |>
  transmute(`ICD-9 code` = icd9, Scope = scope,
            `GEM ICD-10 targets` = gem_icd10_targets, `Targets outside request` = targets_outside)

# Unrecognised DX_TYPE values among M/L/numeric codes (for the record)
other_types <- sort(unique(found$dx_type[!is10 & !is09]))

# -----------------------------------------------------------------------------
# 3. Workbook
# -----------------------------------------------------------------------------
hdr  <- createStyle(fgFill = "#0021A5", fontColour = "#FFFFFF", textDecoration = "bold", wrapText = TRUE)
flag <- createStyle(fgFill = "#FA4616", fontColour = "#FFFFFF")
wrap <- createStyle(wrapText = TRUE, valign = "top")

key <- data.frame(
  Field = c("Purpose", "Run date", "Cohort", "ICD-10 requested", "ICD-9 candidates",
            "STRICT", "BROADER", "Counts", "How to review", "Other DX_TYPE values seen"),
  Value = c(
    "Candidate autoimmune codes found for HL cohort patients, for team review before the Gantt flag is finalised (Phase 192.1)",
    run_date,
    "HL cohort from get_hl_any_dx_ids(); all dates in DIAGNOSIS",
    paste(sprintf("%s (%s)", names(REQ_ICD10), REQ_ICD10), collapse = "; "),
    "ICD-9 codes linked by the CMS 2018 GEMs (either direction) to any requested ICD-10 code",
    "All of the ICD-9 code's GEM ICD-10 targets are within the requested list",
    "Some GEM targets fall outside the requested list (listed in 'Targets outside request')",
    "Patients and records 1-10 shown as '<11'; no patient IDs",
    "Mark 'Include? (Y/N)' for every row on Codes_found; add a comment for any N or uncertain code",
    if (length(other_types)) paste(other_types, collapse = ", ") else "(none)"),
  stringsAsFactors = FALSE)

wb <- createWorkbook()
addWorksheet(wb, "KEY")
writeData(wb, "KEY", key, headerStyle = hdr)
setColWidths(wb, "KEY", 1:2, widths = c(28, 110)); addStyle(wb, "KEY", wrap, rows = 2:(nrow(key) + 1), cols = 2)

addWorksheet(wb, "Codes_found")
writeData(wb, "Codes_found", codes_found, headerStyle = hdr)
freezePane(wb, "Codes_found", firstRow = TRUE)
setColWidths(wb, "Codes_found", 1:ncol(codes_found),
             widths = c(9, 10, 40, 14, 30, 24, 10, 10, 10, 10, 12, 14, 40))
broader_rows <- which(codes_found$`Scope (ICD-9)` %in% c("BROADER", "CHECK (no backward GEM row)")) + 1
if (length(broader_rows)) addStyle(wb, "Codes_found", flag, rows = broader_rows, cols = 4, gridExpand = TRUE)

addWorksheet(wb, "ICD9_candidates_not_found")
writeData(wb, "ICD9_candidates_not_found", not_found, headerStyle = hdr)
setColWidths(wb, "ICD9_candidates_not_found", 1:4, widths = c(12, 14, 40, 30))

out <- file.path(CONFIG$output_dir, glue("autoimmune_code_review_{run_date}.xlsx"))
saveWorkbook(wb, out, overwrite = TRUE)

message(glue("Codes found: {nrow(codes_found)} ",
             "(ICD-10: {sum(codes_found$System == 'ICD-10')}, ICD-9: {sum(codes_found$System == 'ICD-9')}; ",
             "ICD-9 BROADER: {sum(codes_found$`Scope (ICD-9)` == 'BROADER', na.rm = TRUE)})"))
message("Saved: ", out)
