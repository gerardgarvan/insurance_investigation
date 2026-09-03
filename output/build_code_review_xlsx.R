
# build_code_review_xlsx.R
# Produces output/code_review_signoff.xlsx for co-author review.
# Three sheets:
#   1. DoI Codes       — ICD-9/10 prefixes used to classify diagnoses of interest
#   2. Cancer Codes    — ICD-10 cancer site prefixes (CANCER_SITE_MAP)
#   3. ICD-9 Cancer    — ICD-9 cancer site prefixes (ICD9_CANCER_SITE_MAP)

library(openxlsx2)
library(dplyr)

source("R/00_config.R")

# ── 1. DoI codes ──────────────────────────────────────────────────────────────

doi_df <- tibble(
  prefix    = names(DOI_CODE_MAP),
  category  = unname(DOI_CODE_MAP),
  tier      = unname(DOI_CODE_TIER[names(DOI_CODE_MAP)]),
  code_type = ifelse(grepl("^[0-9]", names(DOI_CODE_MAP)), "ICD-9", "ICD-10"),
  code_version = RITDIS_CODE_VERSION
) %>%
  arrange(category, code_type, prefix)

# ── 2. ICD-10 cancer codes ────────────────────────────────────────────────────

cancer10_df <- tibble(
  prefix    = names(CANCER_SITE_MAP),
  category  = unname(CANCER_SITE_MAP),
  code_type = "ICD-10"
) %>%
  arrange(category, prefix)

# ── 3. ICD-9 cancer codes ─────────────────────────────────────────────────────

cancer9_df <- tibble(
  prefix    = names(ICD9_CANCER_SITE_MAP),
  category  = unname(ICD9_CANCER_SITE_MAP),
  code_type = "ICD-9"
) %>%
  arrange(category, prefix)

# ── Build workbook ────────────────────────────────────────────────────────────

wb <- wb_workbook()

header_style <- wb_style(
  font      = wb_font(bold = TRUE, color = wb_color("FFFFFF"), size = 11),
  fill      = wb_fill(fg_color = wb_color("1F4E79")),
  border    = wb_border(color = wb_color("000000"), style = "thin"),
  alignment = wb_alignment(horizontal = "center", wrap_text = TRUE)
)

add_sheet <- function(wb, sheet_name, df, col_widths) {
  wb <- wb_add_worksheet(wb, sheet_name)
  wb <- wb_add_data(wb, sheet_name, df, start_row = 1)
  wb <- wb_add_cell_style(wb, sheet_name,
    dims = wb_dims(rows = 1, cols = seq_along(df)),
    style = header_style
  )
  wb <- wb_set_col_widths(wb, sheet_name,
    cols = seq_along(df), widths = col_widths
  )
  wb <- wb_freeze_pane(wb, sheet_name, first_row = TRUE)
  wb
}

wb <- add_sheet(wb, "DoI Codes",
  doi_df,
  col_widths = c(12, 32, 14, 10, 16)
)

wb <- add_sheet(wb, "Cancer Codes (ICD-10)",
  cancer10_df,
  col_widths = c(12, 38, 10)
)

wb <- add_sheet(wb, "Cancer Codes (ICD-9)",
  cancer9_df,
  col_widths = c(12, 38, 10)
)

out_path <- "output/code_review_signoff.xlsx"
wb_save(wb, out_path)
message("Wrote: ", out_path)
message("  DoI codes:          ", nrow(doi_df), " rows")
message("  ICD-10 cancer codes:", nrow(cancer10_df), " rows")
message("  ICD-9 cancer codes: ", nrow(cancer9_df), " rows")
