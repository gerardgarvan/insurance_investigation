# ==============================================================================
# Script:  212_cohort_rule_waterfall.R
# Phase:   212 (COHORT-04) -- v3.15 cohort rule, READ-ONLY dry run + waterfall
# Purpose: Compute new-rule membership in memory, compare with the existing
#          confirmed_hl_cohort.rds, write a waterfall workbook. Does NOT write the rds.
#
# Rule (see .planning/phases/212-*/212-CONTEXT.md):
#   A  >= 2 HL dx (C81 / 201.x) on distinct encounters; with
#      DISTINCT_ENC_REQUIRE_DIFF_DATES (R/00_config.R, default TRUE) the encounters
#      must also fall on different dates.
#      A dx row with missing ENCOUNTERID counts as its own encounter keyed by its
#      diagnosis date (DX_DATE, else ADMIT_DATE) -- user decision 2026-11-17.
#   B  plus every TR-HL patient (any TUMOR_REGISTRY_ALL SOURCE) present in DEMOGRAPHIC
#   C  minus TR-NHL patients who are not also TR-HL
#
# Inputs:  env R212_COHORT_RDS (default output/confirmed_hl_cohort.rds; set to the
#            pre212 backup after R/47 is applied)
#          DuckDB: DIAGNOSIS, ENCOUNTER, DEMOGRAPHIC, TUMOR_REGISTRY_ALL
#          Column names: constants below; they come from the Phase 212 schema probe
#            (.planning/schemas/212_schema_*.md, plan 01). Script stops if no probe file.
# Outputs: output/212_cohort_waterfall_<RUN_DATE>.xlsx (aggregate counts only; counts
#          1-10 shown "<11"; no patient IDs, dates or ZIPs anywhere).
# Run:     module load R/4.5; R --no-save
#          source("R/212_cohort_rule_waterfall.R", local = new.env(parent = globalenv()))
# Caveat:  ICD_CODES$nhl_histology is UNVERIFIED (D-201-03).
# ==============================================================================

source(here::here("R", "00_config.R"), local = FALSE)
suppressPackageStartupMessages({
  library(dplyr); library(glue); library(here); library(openxlsx); library(stringr)
})

RUN_DATE <- Sys.getenv("RUN_DATE", format(Sys.Date(), "%Y%m%d"))
message(glue("==== R/212 cohort_rule_waterfall (dry run) -- RUN DATE {RUN_DATE} ===="))

# ---- Task 0: probe file gate ---------------------------------------------------
probe_files <- Sys.glob(here::here(".planning", "schemas", "212_schema_*.md"))
if (length(probe_files) == 0L)
  stop("[R212] no .planning/schemas/212_schema_*.md probe file. Run plan 01 probe on HiPerGator first.")
PROBE_FILE <- basename(sort(probe_files, decreasing = TRUE)[1])  # file name only, for KEY
message(glue("  probe file: {PROBE_FILE}"))

# Column-name constants (confirm against the probe file)
C_ID <- "ID"; C_ENC <- "ENCOUNTERID"; C_DXDATE <- "DX_DATE"; C_DX <- "DX"
C_ADMIT <- "ADMIT_DATE"      # fallback date on DIAGNOSIS, used only if the column exists
C_SRC <- "SOURCE"            # DEMOGRAPHIC SOURCE: reference only (includes LNK); ENCOUNTER SOURCE
# Site attribution = R/169 primary_source (D-212-06), as in R/208.

# Copied verbatim from R/211_abvd_impact_table.R:25-30 (prefix changed to R212)
pin_input <- function(env_var, default_rel) {
  v <- Sys.getenv(env_var, "")
  p <- if (nzchar(v)) v else here::here(default_rel)
  if (!file.exists(p)) stop("[R212] input missing: ", p)
  list(path = p, pinned = nzchar(v))
}
pin_old <- pin_input("R212_COHORT_RDS", file.path("output", "confirmed_hl_cohort.rds"))
pin_ssc <- pin_input("R212_SSC_RDS", file.path("output", "internal", "single_source_care_20261008.rds"))
ssc <- readRDS(pin_ssc$path)
if (!all(c("ID", "primary_source") %in% names(ssc))) stop("[R212] R/169 rds lacks ID / primary_source")
old_cohort <- readRDS(pin_old$path)
if (!"ID" %in% names(old_cohort)) stop("[R212] cohort rds has no ID column")
ids_old <- unique(as.character(old_cohort$ID))
message(glue("  old cohort: {format(length(ids_old), big.mark=',')} patients ({basename(pin_old$path)}, pinned = {pin_old$pinned})"))
message(glue("  DISTINCT_ENC_REQUIRE_DIFF_DATES = {DISTINCT_ENC_REQUIRE_DIFF_DATES}"))

# ---- DuckDB pulls (one open/close block; no IN lists) ----------------------------
open_pcornet_con()
dx_tbl <- get_pcornet_table("DIAGNOSIS")
has_admit <- C_ADMIT %in% colnames(dx_tbl)
dx_cols <- c(C_ID, C_ENC, C_DX, C_DXDATE, if (has_admit) C_ADMIT)
dx_hl <- dx_tbl |> select(all_of(dx_cols)) |> collect() |>
  mutate(DX_norm = toupper(str_remove_all(.data[[C_DX]], "\\."))) |>
  filter(str_detect(DX_norm, "^C81") | str_detect(DX_norm, "^201")) |>
  select(-DX_norm, -all_of(C_DX))
demog <- get_pcornet_table("DEMOGRAPHIC") |> select(all_of(c(C_ID, C_SRC))) |> collect()
# ENCOUNTER SOURCE counts per patient (aggregated in DuckDB; joined in R, no IN list).
# Used only for patients without an R/169 primary_source row (R/169 logic; date window not applied).
source_counts <- get_pcornet_table("ENCOUNTER") |>
  filter(!is.na(.data[[C_SRC]])) |>
  count(.data[[C_ID]], .data[[C_SRC]], name = "n_enc_at_source") |> collect()
names(source_counts)[1:2] <- c("ID", "SOURCE")
enc_ids <- get_pcornet_table("ENCOUNTER") |> distinct(.data[[C_ID]]) |> collect() |> pull(1)
tr_ids <- get_pcornet_table("TUMOR_REGISTRY_ALL") |> distinct(.data[[C_ID]]) |> collect() |> pull(1)
close_pcornet_con()

ids_demog <- unique(as.character(demog[[C_ID]]))
demog_src_map <- tibble(ID = as.character(demog[[C_ID]]), site = as.character(demog[[C_SRC]]))
ps <- assign_primary_source(ids_demog, ssc, source_counts)
site_map <- ps |> select(ID, site)
message(glue("  site = R/169 primary_source: from R/169 {fmt_sup(sum(ps$origin == 'r169'))}; computed {fmt_sup(sum(ps$origin == 'computed'))}; unassigned {fmt_sup(sum(ps$origin == 'unassigned'))}"))
message(glue("  HL dx rows: {format(nrow(dx_hl), big.mark=',')}; DEMOGRAPHIC: {format(length(ids_demog), big.mark=',')}; fallback date col present: {has_admit}"))

# ---- Rule A -----------------------------------------------------------------------
dx2 <- hl_confirmed_two_encounters(
  dx_hl, id_col = C_ID, enc_col = C_ENC, date_col = C_DXDATE,
  require_diff_dates = DISTINCT_ENC_REQUIRE_DIFF_DATES,
  fallback_date_col = if (has_admit) C_ADMIT else NULL
)
dx2_loose <- hl_confirmed_two_encounters(
  dx_hl, id_col = C_ID, enc_col = C_ENC, date_col = C_DXDATE,
  require_diff_dates = FALSE, fallback_date_col = if (has_admit) C_ADMIT else NULL
)
fb_rows <- attr(dx2, "fallback_rows")
fb_only <- attr(dx2, "fallback_only_ids")
message(glue("  rule A patients: {format(nrow(dx2), big.mark=',')}; fallback rows: {fmt_sup(sum(fb_rows$n_rows))} in {fmt_sup(nrow(fb_rows))} patients; qualify only via fallback: {fmt_sup(length(fb_only))}; rows with no key: {fmt_sup(attr(dx2, 'n_rows_no_key'))}"))

# ---- TR flags (all TR SOURCEs; DEMOGRAPHIC IDs plus TR-only IDs) ------------------
all_ids <- unique(c(ids_demog, as.character(tr_ids)))
trf <- build_tr_lymphoma_flags(all_ids)
ids_tr_hl  <- trf$patient_id[trf$tr_hl_dx  %in% TRUE]
ids_tr_nhl <- trf$patient_id[trf$tr_nhl_dx %in% TRUE]
unlisted   <- attr(trf, "unlisted_lymphoid")
message(glue("  TR-HL: {format(length(ids_tr_hl), big.mark=',')}; TR-NHL: {format(length(ids_tr_nhl), big.mark=',')}; both: {fmt_sup(length(intersect(ids_tr_hl, ids_tr_nhl)))}"))

# ---- Waterfall ---------------------------------------------------------------------
sets <- apply_cohort_rule_v315(dx2$ID, ids_tr_hl, ids_tr_nhl, ids_old, ids_demog)
wf <- cohort_waterfall_by_site(sets, site_map)
for (s in names(COHORT_WATERFALL_STEPS)) {
  message(glue("  {s}: {fmt_sup(length(sets[[s]]))}"))
}

# Reference only: gained patients by DEMOGRAPHIC SOURCE (includes LNK, not a site).
gained_ids <- union(sets$gained_drop7, sets$gained_trhl)
gained_demog_src <- tibble(ID = gained_ids) |>
  left_join(demog_src_map, by = "ID") |>
  mutate(site = coalesce(site, "Not in DEMOGRAPHIC")) |>
  count(site, name = "n") |> arrange(desc(n)) |>
  mutate(n_patients = fmt_sup(n)) |> select(`DEMOGRAPHIC SOURCE` = site, n_patients)
# Origin of the site label for patients in the new cohort.
site_origin <- ps |> filter(ID %in% sets$new) |> count(origin, name = "n") |>
  mutate(n_patients = fmt_sup(n)) |> select(origin, n_patients)

wf_all <- wf |> filter(site == "ALL") |> select(step, label, n_patients = n_display)
wf_site <- wf |> filter(site != "ALL") |>
  select(step, label, site, n_patients = n_display)
wf_site <- tidyr::pivot_wider(wf_site, names_from = site, values_from = n_patients, values_fill = "0")

# ---- Sheets ---------------------------------------------------------------------------
tr_hl_incl <- intersect(ids_tr_hl, ids_demog)
tr_hl_absent <- setdiff(ids_tr_hl, ids_demog)
tr_hl_no_enc <- setdiff(tr_hl_incl, as.character(enc_ids))
tr_hl_site <- tibble(ID = tr_hl_incl) |>
  left_join(site_map, by = "ID") |> count(site, name = "n") |>
  mutate(n_patients = fmt_sup(n)) |> select(site, n_patients)
# D-201-04 reconciliation: "121 TR-HL not in current cohort" -- measured here, not typed.
tr_hl_not_old <- setdiff(tr_hl_incl, ids_old)
tr_hl_checks <- tibble(
  measure = c("TR-HL patients (all TR SOURCEs)",
              "TR-HL included (present in DEMOGRAPHIC)",
              "TR-HL absent from DEMOGRAPHIC (not included)",
              "TR-HL included with 0 ENCOUNTER rows",
              "TR-HL included, not in old cohort (D-201-04 gap)",
              "  of those, in new cohort",
              "  of those, in new cohort via rule A (also have 2 encounters)"),
  n = c(length(ids_tr_hl), length(tr_hl_incl), length(tr_hl_absent), length(tr_hl_no_enc),
        length(tr_hl_not_old), length(intersect(tr_hl_not_old, sets$new)),
        length(intersect(tr_hl_not_old, dx2$ID)))
) |> mutate(n_patients = fmt_sup(n)) |> select(measure, n_patients)

unlisted_sheet <- if (is.null(unlisted) || nrow(unlisted) == 0L) {
  tibble(code = character(), n_patients = character())
} else {
  unlisted |> mutate(n_patients = fmt_sup(n_patients)) |> select(code, n_patients)
}

fb_site <- fallback_summary_by_site(fb_rows, site_map) |>
  select(site, rows_needing_fallback = rows_display, patients_needing_fallback = patients_display)
na_effect <- bind_rows(
  tibble(measure = "Rule A patients (with missing-ENCOUNTERID fallback)", n = nrow(dx2)),
  tibble(measure = "Qualify only via fallback", n = length(fb_only)),
  tibble(measure = "Rule A patients if distinct ENCOUNTERIDs only (no date requirement)", n = nrow(dx2_loose)),
  tibble(measure = "Rule A patients under the other DISTINCT_ENC_REQUIRE_DIFF_DATES setting",
         n = nrow(hl_confirmed_two_encounters(
           dx_hl, id_col = C_ID, enc_col = C_ENC, date_col = C_DXDATE,
           require_diff_dates = !DISTINCT_ENC_REQUIRE_DIFF_DATES,
           fallback_date_col = if (has_admit) C_ADMIT else NULL)))
) |> mutate(n_patients = fmt_sup(n)) |> select(measure, n_patients)

decisions <- tibble(
  id = c("D-212-01", "D-212-02", "D-212-03", "D-212-04", "D-212-05 (replaced)", "D-212-05b",
         "D-212-06", "D-212-07", "D-212-08", "D-212-09"),
  decision = c(
    "TR-HL forced includes need only to appear in DEMOGRAPHIC; 0-ENCOUNTER and absent-from-DEMOGRAPHIC counts reported (tr_hl_checks).",
    "TR-NHL = existing tr_nhl_dx (ICD_CODES$nhl_histology, UNVERIFIED D-201-03). Unlisted lymphoid codes neither include nor exclude; listed in unlisted_lymphoid.",
    "Both TR-HL and TR-NHL -> included.",
    "TR-NHL exclusion also removes patients meeting rule A if TR-NHL and not TR-HL.",
    "USER (2026-11-17): HL dx row with missing ENCOUNTERID counts as its own encounter keyed by DX_DATE, else ADMIT_DATE. Rows/patients needing this fallback reported by site (fallback_by_site).",
    "USER (2026-11-17): config DISTINCT_ENC_REQUIRE_DIFF_DATES (default TRUE): >= 2 HL dx on distinct encounters on different dates; FALSE = distinct ENCOUNTERIDs only.",
    "UPDATED 2026-11-17: site = R/169 primary_source (as R/208), NOT DEMOGRAPHIC SOURCE (includes LNK, linked multi-site records). Patients without an R/169 row get the R/169 logic from ENCOUNTER SOURCE counts; none -> 'unassigned'. DEMOGRAPHIC SOURCE kept as a reference sheet only.",
    "Sequential waterfall, each patient counted once; reconciles to new total (checked, script stops otherwise).",
    "first_hl_dx_date for TR-HL-only patients from existing TR DATE_OF_DIAGNOSIS logic in R/47 Section 5 (applied in R/47, not here).",
    "Rule applied in R/47 only after this dry run is reviewed; R/212 does not write the rds."
  ),
  status = c(rep("FLAG FOR USER REVIEW", 6), "APPROVED 2026-11-17 (revised)", rep("FLAG FOR USER REVIEW", 3))
)

key <- tibble(
  item = c("run_date", "script", "mode", "cohort_rds", "cohort_rds_pinned", "probe_file",
           "DISTINCT_ENC_REQUIRE_DIFF_DATES", "r169_ssc_rds", "r169_ssc_pinned", "site_attribution",
           "review_2026_11_17_dry_run", "review_2026_11_17_rule", "review_2026_11_17_gained_check",
           "review_2026_11_17_site_note", "suppression", "caveat", "sheets"),
  value = c(RUN_DATE, "R/212_cohort_rule_waterfall.R", "READ-ONLY dry run (no rds written)",
            pin_old$path, as.character(pin_old$pinned), PROBE_FILE,
            as.character(DISTINCT_ENC_REQUIRE_DIFF_DATES),
            pin_ssc$path, as.character(pin_ssc$pinned),
            "R/169 primary_source (not DEMOGRAPHIC SOURCE, which includes LNK); patients without an R/169 row: R/169 logic from ENCOUNTER SOURCE, else 'unassigned'.",
            "User review of the HiPerGator dry run (2026-11-17), approved: old 7,696; lost_2enc 0; gained_drop7 1,635; gained_trhl 0 (all 174 TR-HL not in old cohort already gained by drop7); lost_trnhl 152; new 9,179.",
            "Rules (a) and (b) give identical results: all 9,331 DEMOGRAPHIC patients have >= 2 active HL dx dates. DISTINCT_ENC_REQUIRE_DIFF_DATES stays TRUE. The extract was pulled on HL dx, so the 2-encounter rule is non-binding; the TR-NHL exclusion is the only rule that removes patients.",
            "All 1,635 gained patients have active C81/201 codes. Distinct active-HL dx dates among gained: 2 = 554; 3-4 = 341; 5-9 = 273; 10+ = 467.",
            "Gains are concentrated at UAB and ORL, consistent with the 7-day rule being more restrictive at those sites (see waterfall_by_site, R/169 primary_source).",
            "Counts 1-10 shown as <11; no patient-level data in this workbook.",
            "nhl_histology list is UNVERIFIED (D-201-03).",
            "waterfall_all, waterfall_by_site (R/169 primary_source), tr_hl_checks, tr_hl_by_site, unlisted_lymphoid, fallback_by_site, na_encounter_effect, gained_by_demog_source (reference), site_label_origin, decisions")
)

sheets <- list(KEY = key, waterfall_all = wf_all, waterfall_by_site = wf_site,
               tr_hl_checks = tr_hl_checks, tr_hl_by_site = tr_hl_site,
               unlisted_lymphoid = unlisted_sheet, fallback_by_site = fb_site,
               na_encounter_effect = na_effect, gained_by_demog_source = gained_demog_src,
               site_label_origin = site_origin, decisions = decisions)

wb <- createWorkbook()
modifyBaseFont(wb, fontSize = 10, fontName = "Arial")
hdr <- createStyle(fontName = "Arial", fontSize = 10, fontColour = "#FFFFFF",
                   fgFill = "#0021A5", textDecoration = "bold")
accent <- createStyle(fontName = "Arial", fontSize = 10, fontColour = "#FFFFFF",
                      fgFill = "#FA4616", textDecoration = "bold")
for (nm in names(sheets)) {
  addWorksheet(wb, nm)
  writeData(wb, nm, as.data.frame(sheets[[nm]]), headerStyle = hdr)
  setColWidths(wb, nm, cols = seq_len(ncol(sheets[[nm]])), widths = "auto")
}
addStyle(wb, "KEY", accent, rows = 1, cols = 1)

out_path <- here::here("output", glue("212_cohort_waterfall_{RUN_DATE}.xlsx"))
saveWorkbook(wb, out_path, overwrite = TRUE)

message(glue("  TR-HL included {fmt_sup(length(tr_hl_incl))}; absent from DEMOGRAPHIC {fmt_sup(length(tr_hl_absent))}; 0 ENCOUNTER rows {fmt_sup(length(tr_hl_no_enc))}; not in old cohort {fmt_sup(length(tr_hl_not_old))}"))
message(glue("  output: {out_path}"))
message("==== R/212 complete (no rds written) ====")
