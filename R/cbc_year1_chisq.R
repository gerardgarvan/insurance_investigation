# ==============================================================================
# cbc_year1_chisq.R -- CBC in the first surveillance year vs distance (chi-square)
# ==============================================================================
# Question: among patients with a fully observed first surveillance year, is
#           having >= 1 CBC in year 1 associated with living far (> 100 mi)?
#
# Data:     Phase 179 patient-year RDS (pinned). Year 1 = (anchor, anchor + 365].
#           The RDS holds only fully observed years (year_end <= EXTRACT_DATE and
#           alive through year_end), so every year_index == 1 row is a full first year.
#           Outcome  = cbc_year (Phase 165 CBC: WBC + Hgb + PLT same date).
#           Exposure = far (patient median post-anchor distance > 100 mi).
#           Patients missing exposure are excluded (complete case).
#
# Check:    2x2 counts must equal the Phase 179 workbook Per_Year row "1"
#           (CBC_years_far / PY_far / CBC_years_not_far / PY_not_far).
#
# Output:   console + output/cbc_year1_chisq_<YYYYMMDD>.xlsx (KEY leftmost).
#           Counts 1-10 shown as "<11"; percentages only when num and den >= 11.
#
# Usage (interactive R on HiPerGator, repo root):
#   source("R/tools/cbc_year1_chisq.R", local = new.env(parent = globalenv()))
#   Optional pins: Sys.setenv(CBCY1_P179_RDS = ..., CBCY1_P179_XLSX = ...)
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
  library(openxlsx)
})

RUN_DATE <- format(Sys.Date(), "%Y%m%d")
DATA_END <- as.Date("2025-03-31")   # event data in this extract end ~March 2025 (Phase 184)

pin <- function(var, default) {
  v <- Sys.getenv(var, unset = "")
  p <- if (nzchar(v)) v else default
  if (!file.exists(p)) stop(glue("[cbc_year1] {var}: file not found: {p}"), call. = FALSE)
  list(var = var, path = p, pinned = nzchar(v))
}
PINS <- list(
  rds  = pin("CBCY1_P179_RDS",  "output/internal/cbc_patient_year_20261015.rds"),
  xlsx = pin("CBCY1_P179_XLSX", "output/cbc_patient_year_20261015.xlsx")
)

sup <- function(x) ifelse(is.na(x), NA_character_,
                          ifelse(x >= 1 & x <= 10, "<11", format(x, big.mark = ",", trim = TRUE)))
pct <- function(num, den) if (is.na(num) || is.na(den) || num < 11 || den < 11) "—" else
  sprintf("%.1f%%", 100 * num / den)

# ---- 1. Year-1 analytic set ---------------------------------------------------
py <- readRDS(PINS$rds$path)
need <- c("ID", "year_index", "year_start", "year_end", "cbc_year", "far", "exposure_missing")
miss <- setdiff(need, names(py))
if (length(miss)) stop("[cbc_year1] Phase 179 RDS missing columns: ", paste(miss, collapse = ", "),
                       ". Available: ", paste(names(py), collapse = ", "), call. = FALSE)

y1_all <- py |> filter(year_index == 1L)
stopifnot("one year-1 row per patient" = !anyDuplicated(y1_all$ID))
y1 <- y1_all |> filter(!exposure_missing, !is.na(far))

message(glue("==== CBC year 1 vs distance -- RUN DATE {RUN_DATE} ===="))
message(glue("  Input: {basename(PINS$rds$path)} (pinned={PINS$rds$pinned})"))
message(glue("  Patients with a full first year: {sup(nrow(y1_all))}; ",
             "missing exposure (excluded): {sup(sum(y1_all$exposure_missing))}; ",
             "analysed: {sup(nrow(y1))}"))

# ---- 2. 2x2 table and tests ---------------------------------------------------
two_by_two <- function(d) {
  tab <- table(far = factor(d$far, levels = c(1, 0), labels = c("far (>100 mi)", "not far")),
               cbc = factor(d$cbc_year, levels = c(1, 0), labels = c("CBC in year 1", "no CBC")))
  a <- tab[1, 1]; b <- tab[1, 2]; c <- tab[2, 1]; dd <- tab[2, 2]
  chi   <- suppressWarnings(chisq.test(tab, correct = FALSE))
  chi_y <- suppressWarnings(chisq.test(tab, correct = TRUE))
  fish  <- fisher.test(tab)
  or    <- (a * dd) / (b * c)
  se    <- sqrt(1 / a + 1 / b + 1 / c + 1 / dd)
  list(tab = tab, a = a, b = b, c = c, d = dd,
       or = or, lo = exp(log(or) - 1.96 * se), hi = exp(log(or) + 1.96 * se),
       chi2 = unname(chi$statistic), p = chi$p.value,
       chi2_yates = unname(chi_y$statistic), p_yates = chi_y$p.value,
       p_fisher = fish$p.value, min_expected = min(chi$expected))
}

res <- two_by_two(y1)
y1_de <- y1 |> filter(year_end <= DATA_END)
res_de <- two_by_two(y1_de)

show_res <- function(r, label) {
  message(glue("\n  [{label}]"))
  message(glue("    far:     CBC {sup(r$a)} of {sup(r$a + r$b)} ({pct(r$a, r$a + r$b)})"))
  message(glue("    not far: CBC {sup(r$c)} of {sup(r$c + r$d)} ({pct(r$c, r$c + r$d)})"))
  message(glue("    OR (far vs not far) = {sprintf('%.3f', r$or)} ",
               "(95% CI {sprintf('%.3f', r$lo)}-{sprintf('%.3f', r$hi)})"))
  message(glue("    Pearson chi-square = {sprintf('%.2f', r$chi2)}, df = 1, p = {signif(r$p, 3)} ",
               "(min expected cell = {sprintf('%.1f', r$min_expected)})"))
  message(glue("    Yates-corrected p = {signif(r$p_yates, 3)}; Fisher exact p = {signif(r$p_fisher, 3)}"))
}
show_res(res, "Primary: all full first years")
show_res(res_de, glue("Sensitivity: first year ends by {DATA_END}"))

# ---- 3. Check against Phase 179 Per_Year row "1" --------------------------------
per_year <- openxlsx::read.xlsx(PINS$xlsx$path, sheet = "Per_Year")
need_py <- c("Year_index", "PY_far", "PY_not_far", "CBC_years_far", "CBC_years_not_far")
if (length(setdiff(need_py, names(per_year))))
  stop("[cbc_year1] Per_Year sheet columns: ", paste(names(per_year), collapse = ", "), call. = FALSE)
r1 <- per_year[trimws(as.character(per_year$Year_index)) == "1", ]
if (nrow(r1) != 1L) stop("[cbc_year1] Per_Year row '1' not found exactly once", call. = FALSE)
as_n <- function(x) suppressWarnings(as.numeric(gsub(",", "", as.character(x))))
ref <- c(far_cbc = as_n(r1$CBC_years_far), far_n = as_n(r1$PY_far),
         nf_cbc = as_n(r1$CBC_years_not_far), nf_n = as_n(r1$PY_not_far))
mine <- c(far_cbc = res$a, far_n = res$a + res$b, nf_cbc = res$c, nf_n = res$c + res$d)
comparable <- !is.na(ref)   # cells shown as "<11" in the workbook cannot be compared
check_ok <- all(ref[comparable] == mine[comparable]) && any(comparable)
message(glue("\n  Check vs Phase 179 Per_Year year 1: {if (check_ok) 'MATCH' else 'MISMATCH'} ",
             "({sum(comparable)} of 4 cells comparable)"))
if (!check_ok) stop("[cbc_year1] counts do not match Phase 179 Per_Year year 1 -- check pins", call. = FALSE)

# ---- 4. Workbook ----------------------------------------------------------------
res_row <- function(r, label) data.frame(
  Analysis = label,
  Far_CBC = sup(r$a), Far_total = sup(r$a + r$b), Far_pct = pct(r$a, r$a + r$b),
  NotFar_CBC = sup(r$c), NotFar_total = sup(r$c + r$d), NotFar_pct = pct(r$c, r$c + r$d),
  OR = sprintf("%.3f", r$or), CI_low = sprintf("%.3f", r$lo), CI_high = sprintf("%.3f", r$hi),
  Chi2 = sprintf("%.2f", r$chi2), p_Pearson = signif(r$p, 3),
  p_Yates = signif(r$p_yates, 3), p_Fisher = signif(r$p_fisher, 3),
  Min_expected = sprintf("%.1f", r$min_expected), stringsAsFactors = FALSE)

results <- rbind(res_row(res, "Primary: all full first years"),
                 res_row(res_de, glue("Sensitivity: first year ends by {DATA_END}")))

key <- data.frame(Field = c(
  "Analysis", "Run date", "Input RDS", "Check workbook", "Unit", "Full first year",
  "Outcome", "Exposure", "Excluded", "Test", "Sensitivity", "Phase 179 check", "Suppression"),
  Value = c(
  "CBC in the first surveillance year vs distance (2x2 chi-square)",
  RUN_DATE,
  glue("{basename(PINS$rds$path)} (pinned={PINS$rds$pinned})"),
  glue("{basename(PINS$xlsx$path)} (pinned={PINS$xlsx$pinned})"),
  "Patient (one row per patient: year_index == 1)",
  "Year 1 = (anchor, anchor + 365 days]; included only if fully observed (ends by EXTRACT_DATE, alive through year end) -- Phase 179 rule",
  "cbc_year: >= 1 CBC (WBC 6690-2 + Hgb 718-7 + PLT 777-3 same date) in year 1",
  "far: patient median post-anchor distance > 100 mi",
  glue("Patients missing exposure: {sup(sum(y1_all$exposure_missing))}"),
  "Pearson chi-square without continuity correction (primary); Yates and Fisher exact reported",
  glue("First year ending by {DATA_END} (event data in this extract end ~March 2025)"),
  glue("Counts match Phase 179 Per_Year year 1 ({sum(comparable)} of 4 cells comparable)"),
  "Counts 1-10 shown as <11; percentages only when numerator and denominator >= 11"),
  stringsAsFactors = FALSE)

hdr <- createStyle(fgFill = "#0021A5", fontColour = "#FFFFFF", textDecoration = "bold")
wb  <- createWorkbook()
addWorksheet(wb, "KEY");     writeData(wb, "KEY", key, headerStyle = hdr)
setColWidths(wb, "KEY", 1:2, c(22, 110)); freezePane(wb, "KEY", firstRow = TRUE)
addWorksheet(wb, "Results"); writeData(wb, "Results", results, headerStyle = hdr)
setColWidths(wb, "Results", 1:ncol(results), "auto"); freezePane(wb, "Results", firstRow = TRUE)
out_path <- file.path("output", glue("cbc_year1_chisq_{RUN_DATE}.xlsx"))
saveWorkbook(wb, out_path, overwrite = TRUE)
message(glue("\n  Workbook saved: {out_path}"))
