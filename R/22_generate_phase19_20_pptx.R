# ==============================================================================
# 22_generate_phase19_20_pptx.R -- Focused PPTX for phases 19 and 20
# ==============================================================================
#
# Phase 24: Make Presentation of Just Phases 19 and 20
# Requirements: PPTX4-01, PPTX4-02, PPTX4-03, PPTX4-04
#
# Purpose:
#   Build a standalone PowerPoint deck containing only:
#   - Phase 19 (UF payer missingness), and
#   - Phase 20 (FLM duplicate encounter dates)
#
# Inputs (output/tables):
#   - uf_payer_raw_value_distribution.csv
#   - uf_payer_missingness_by_year.csv
#   - uf_payer_missingness_by_enc_type.csv
#   - uf_payer_missingness_year_x_enc_type.csv
#   - uf_payer_raw_vs_harmonized.csv
#   - flm_patient_duplicate_summary.csv
#   - flm_date_level_duplicate_detail.csv
#   - flm_duplicate_aggregate_summary.csv
#   - flm_source_payer_completeness.csv
#
# Output:
#   - insurance_tables_phase19_20_YYYY-MM-DD.pptx
#
# Usage:
#   source("R/22_generate_phase19_20_pptx.R")
#
# ==============================================================================

library(officer)
library(flextable)
library(dplyr)
library(readr)
library(ggplot2)
library(scales)
library(glue)
library(stringr)
library(tidyr)

message("\n", strrep("=", 70))
message("Generating focused Phase 19/20 PowerPoint")
message(strrep("=", 70))

# ------------------------------------------------------------------------------
# Styling constants (aligned with existing deck)
# ------------------------------------------------------------------------------
UF_BLUE <- "#003087"
UF_ORANGE <- "#FA4616"
LIGHT_BLUE <- "#CCD5EA"
LIGHT_ORANGE <- "#FDD9CC"
DARK_TEXT <- "#333333"
FOOTNOTE_TEXT <- "#666666"

# ------------------------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------------------------
style_table <- function(ft, total_row = integer(0), body_font_size = 11) {
  n_rows <- nrow_part(ft, "body")
  odd_rows <- seq(1, n_rows, by = 2)
  even_rows <- seq(2, n_rows, by = 2)

  ft <- ft %>%
    fontsize(size = body_font_size, part = "body") %>%
    fontsize(size = 12, part = "header") %>%
    font(fontname = "Calibri", part = "all") %>%
    bold(part = "header") %>%
    bg(bg = UF_BLUE, part = "header") %>%
    color(color = "white", part = "header") %>%
    color(color = DARK_TEXT, part = "body") %>%
    align(align = "center", part = "header") %>%
    align(j = 1, align = "left", part = "body") %>%
    align(j = -1, align = "center", part = "body") %>%
    border_remove() %>%
    padding(padding.left = 5, padding.right = 5, padding.top = 2, padding.bottom = 2, part = "all")

  if (length(odd_rows) > 0) ft <- ft %>% bg(i = odd_rows, bg = LIGHT_BLUE, part = "body")
  if (length(even_rows) > 0) ft <- ft %>% bg(i = even_rows, bg = LIGHT_ORANGE, part = "body")

  if (length(total_row) > 0 && total_row[1] > 0) {
    ft <- ft %>%
      bold(i = total_row[1], part = "body") %>%
      bg(i = total_row[1], bg = UF_BLUE, part = "body") %>%
      color(i = total_row[1], color = "white", part = "body")
  }

  ft %>% autofit()
}

add_table_slide <- function(pptx, title, subtitle, tbl_data, footnote = NULL, body_font_size = 11) {
  total_row_idx <- which(tbl_data[[1]] == "Total")
  ft <- flextable(tbl_data) %>% style_table(total_row = total_row_idx, body_font_size = body_font_size)

  n_cols <- ncol(tbl_data)
  if (n_cols > 1) {
    first_col_width <- 2.4
    data_col_width <- (9.0 - first_col_width) / (n_cols - 1)
    ft <- ft %>%
      width(j = 1, width = first_col_width) %>%
      width(j = 2:n_cols, width = data_col_width)
  }

  pptx <- pptx %>%
    add_slide(layout = "Blank") %>%
    ph_with(
      value = fpar(ftext(title, prop = fp_text(font.size = 26, bold = TRUE, font.family = "Calibri", color = UF_BLUE))),
      location = ph_location(left = 0.5, top = 0.2, width = 9, height = 0.6)
    ) %>%
    ph_with(
      value = fpar(ftext(subtitle, prop = fp_text(font.size = 13, italic = TRUE, font.family = "Calibri", color = DARK_TEXT))),
      location = ph_location(left = 0.5, top = 0.85, width = 9, height = 0.4)
    ) %>%
    ph_with(value = ft, location = ph_location(left = 0.5, top = 1.35, width = 9, height = 5.3))

  if (!is.null(footnote)) {
    pptx <- pptx %>%
      ph_with(
        value = fpar(ftext(footnote, prop = fp_text(font.size = 10, italic = TRUE, font.family = "Calibri", color = FOOTNOTE_TEXT))),
        location = ph_location(left = 0.5, top = 6.85, width = 9, height = 0.5)
      )
  }

  pptx
}

add_image_slide <- function(pptx, title, subtitle, img_path, footnote = NULL, img_width = 8.8, img_height = 5.1) {
  if (!file.exists(img_path)) {
    stop(glue("Expected image not found: {img_path}"), call. = FALSE)
  }

  pptx <- pptx %>%
    add_slide(layout = "Blank") %>%
    ph_with(
      value = fpar(ftext(title, prop = fp_text(font.size = 26, bold = TRUE, font.family = "Calibri", color = UF_BLUE))),
      location = ph_location(left = 0.5, top = 0.2, width = 9, height = 0.6)
    ) %>%
    ph_with(
      value = fpar(ftext(subtitle, prop = fp_text(font.size = 13, italic = TRUE, font.family = "Calibri", color = DARK_TEXT))),
      location = ph_location(left = 0.5, top = 0.85, width = 9, height = 0.4)
    ) %>%
    ph_with(
      value = external_img(img_path, width = img_width, height = img_height),
      location = ph_location(left = (10 - img_width) / 2, top = 1.35, width = img_width, height = img_height)
    )

  if (!is.null(footnote)) {
    pptx <- pptx %>%
      ph_with(
        value = fpar(ftext(footnote, prop = fp_text(font.size = 10, italic = TRUE, font.family = "Calibri", color = FOOTNOTE_TEXT))),
        location = ph_location(left = 0.5, top = 6.85, width = 9, height = 0.5)
      )
  }

  pptx
}

add_section_slide <- function(pptx, section_title, section_subtitle) {
  pptx %>%
    add_slide(layout = "Blank") %>%
    ph_with(
      value = fpar(ftext(section_title, prop = fp_text(font.size = 34, bold = TRUE, font.family = "Calibri", color = UF_BLUE))),
      location = ph_location(left = 0.7, top = 2.0, width = 8.6, height = 1.0)
    ) %>%
    ph_with(
      value = fpar(ftext(section_subtitle, prop = fp_text(font.size = 18, italic = TRUE, font.family = "Calibri", color = DARK_TEXT))),
      location = ph_location(left = 0.7, top = 3.1, width = 8.6, height = 0.9)
    )
}

split_df <- function(df, chunk_size) {
  split(df, ceiling(seq_len(nrow(df)) / chunk_size))
}

assert_required_files <- function(paths) {
  missing <- paths[!file.exists(paths)]
  if (length(missing) > 0) {
    stop(
      glue(
        "Missing required input files:\n- {paste(missing, collapse = '\n- ')}\n\nRun Phase 19 and 20 scripts first."
      ),
      call. = FALSE
    )
  }
}

fmt_pct <- function(x) paste0(x, "%")

# ------------------------------------------------------------------------------
# Input files
# ------------------------------------------------------------------------------
input_files <- list(
  uf_raw_values = "output/tables/uf_payer_raw_value_distribution.csv",
  uf_by_year = "output/tables/uf_payer_missingness_by_year.csv",
  uf_by_enc = "output/tables/uf_payer_missingness_by_enc_type.csv",
  uf_year_x_enc = "output/tables/uf_payer_missingness_year_x_enc_type.csv",
  uf_raw_vs_harm = "output/tables/uf_payer_raw_vs_harmonized.csv",
  flm_patient = "output/tables/flm_patient_duplicate_summary.csv",
  flm_date_detail = "output/tables/flm_date_level_duplicate_detail.csv",
  flm_agg = "output/tables/flm_duplicate_aggregate_summary.csv",
  flm_source = "output/tables/flm_source_payer_completeness.csv"
)

assert_required_files(unlist(input_files, use.names = FALSE))

# ------------------------------------------------------------------------------
# Read data
# ------------------------------------------------------------------------------
uf_raw_values <- read_csv(input_files$uf_raw_values, show_col_types = FALSE)
uf_by_year <- read_csv(input_files$uf_by_year, show_col_types = FALSE)
uf_by_enc <- read_csv(input_files$uf_by_enc, show_col_types = FALSE)
uf_year_x_enc <- read_csv(input_files$uf_year_x_enc, show_col_types = FALSE)
uf_raw_vs_harm <- read_csv(input_files$uf_raw_vs_harm, show_col_types = FALSE)

flm_patient <- read_csv(input_files$flm_patient, show_col_types = FALSE)
flm_date_detail <- read_csv(input_files$flm_date_detail, show_col_types = FALSE)
flm_agg <- read_csv(input_files$flm_agg, show_col_types = FALSE)
flm_source <- read_csv(input_files$flm_source, show_col_types = FALSE)

message("Loaded Phase 19/20 input files.")

# ------------------------------------------------------------------------------
# Create derived tables
# ------------------------------------------------------------------------------
uf_cross_summary <- uf_by_year %>%
  summarise(
    encounters = sum(n_encounters, na.rm = TRUE),
    primary_missing = sum(n_primary_missing, na.rm = TRUE),
    secondary_missing = sum(n_secondary_missing, na.rm = TRUE),
    both_missing = sum(n_both_missing, na.rm = TRUE),
    primary_pct = round(100 * primary_missing / encounters, 1),
    secondary_pct = round(100 * secondary_missing / encounters, 1),
    both_pct = round(100 * both_missing / encounters, 1)
  ) %>%
  transmute(
    `Group` = "UFH",
    `Encounters` = format(encounters, big.mark = ","),
    `Primary Missing` = format(primary_missing, big.mark = ","),
    `% Primary Missing` = fmt_pct(primary_pct),
    `Secondary Missing` = format(secondary_missing, big.mark = ","),
    `% Secondary Missing` = fmt_pct(secondary_pct),
    `% Both Missing` = fmt_pct(both_pct)
  )

flm_total_patient_dates <- sum(flm_patient$n_unique_dates, na.rm = TRUE)
flm_dupe_patient_dates <- sum(flm_patient$n_duplicate_dates, na.rm = TRUE)
flm_multi_source_dates <- sum(flm_patient$n_multi_source_dates, na.rm = TRUE)

flm_summary_tbl <- tibble(
  `Metric` = c(
    "Total FLM patients",
    "Total FLM patient-dates",
    "Patient-dates with duplicates",
    "Duplicate-date rate",
    "Patient-dates with multiple sources",
    "Multi-source share of duplicates"
  ),
  `Value` = c(
    format(nrow(flm_patient), big.mark = ","),
    format(flm_total_patient_dates, big.mark = ","),
    format(flm_dupe_patient_dates, big.mark = ","),
    fmt_pct(round(100 * flm_dupe_patient_dates / flm_total_patient_dates, 2)),
    format(flm_multi_source_dates, big.mark = ","),
    ifelse(
      flm_dupe_patient_dates > 0,
      fmt_pct(round(100 * flm_multi_source_dates / flm_dupe_patient_dates, 2)),
      "0%"
    )
  )
)

recommendation_tbl <- if (nrow(flm_source) > 0) {
  ordered <- flm_source %>% arrange(desc(pct_primary_present))
  top <- ordered[1, , drop = FALSE]
  tibble(
    `Recommendation` = glue("Prefer SOURCE '{top$SOURCE}' when resolving duplicate-date encounters"),
    `Primary Completeness` = fmt_pct(top$pct_primary_present),
    `Secondary Completeness` = fmt_pct(top$pct_secondary_present),
    `Either Field Completeness` = fmt_pct(top$pct_either_present)
  )
} else {
  tibble(
    `Recommendation` = "No multi-source encounters available; source recommendation not applicable.",
    `Primary Completeness` = "N/A",
    `Secondary Completeness` = "N/A",
    `Either Field Completeness` = "N/A"
  )
}

# Summarize date-level detail instead of showing raw rows
flm_date_summary <- flm_date_detail %>%
  mutate(admit_date_parsed = as.Date(admit_date_parsed)) %>%
  group_by(admit_date_parsed) %>%
  summarise(
    n_encounters = n(),
    n_distinct_patients = n_distinct(ID),
    n_sources = n_distinct(SOURCE, na.rm = TRUE),
    pct_primary_missing = round(100 * mean(primary_missing), 1),
    pct_secondary_missing = round(100 * mean(secondary_missing), 1),
    .groups = "drop"
  ) %>%
  arrange(desc(n_encounters)) %>%
  head(40) %>%
  mutate(
    admit_date_parsed = as.character(admit_date_parsed),
    n_encounters = format(n_encounters, big.mark = ","),
    n_distinct_patients = format(n_distinct_patients, big.mark = ","),
    pct_primary_missing = fmt_pct(pct_primary_missing),
    pct_secondary_missing = fmt_pct(pct_secondary_missing)
  ) %>%
  rename(
    `Date` = admit_date_parsed,
    `Encounters` = n_encounters,
    `Patients` = n_distinct_patients,
    `Distinct Sources` = n_sources,
    `% Primary Missing` = pct_primary_missing,
    `% Secondary Missing` = pct_secondary_missing
  )

# ------------------------------------------------------------------------------
# Charts
# ------------------------------------------------------------------------------
dir.create("output/figures", showWarnings = FALSE, recursive = TRUE)

chart_uf_year <- ggplot(
  uf_by_year %>% mutate(admit_year = as.integer(admit_year)),
  aes(x = admit_year, y = pct_primary_missing)
) +
  geom_line(color = UF_BLUE, linewidth = 1) +
  geom_point(color = UF_BLUE, size = 2.2) +
  scale_y_continuous(labels = scales::percent_format(scale = 1), expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "UF Primary Payer Missingness by Year",
    x = "Admission Year",
    y = "% Primary Missing"
  ) +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold", color = UF_BLUE))

chart_uf_enc <- uf_by_enc %>%
  select(ENC_TYPE_LABEL, pct_primary_missing, pct_secondary_missing) %>%
  pivot_longer(cols = starts_with("pct_"), names_to = "field", values_to = "pct") %>%
  mutate(field = recode(field, pct_primary_missing = "Primary", pct_secondary_missing = "Secondary")) %>%
  ggplot(aes(x = ENC_TYPE_LABEL, y = pct, fill = field)) +
  geom_col(position = "dodge", width = 0.7) +
  scale_fill_manual(values = c("Primary" = UF_BLUE, "Secondary" = UF_ORANGE)) +
  scale_y_continuous(labels = scales::percent_format(scale = 1), expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "UF Missingness by Encounter Type",
    x = "Encounter Type",
    y = "% Missing",
    fill = "Payer Field"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    axis.text.x = element_text(angle = 35, hjust = 1),
    plot.title = element_text(face = "bold", color = UF_BLUE),
    legend.position = "bottom"
  )

chart_flm_source <- flm_source %>%
  select(SOURCE, pct_primary_present, pct_secondary_present) %>%
  pivot_longer(cols = starts_with("pct_"), names_to = "field", values_to = "pct_present") %>%
  mutate(field = recode(field, pct_primary_present = "Primary", pct_secondary_present = "Secondary")) %>%
  ggplot(aes(x = reorder(SOURCE, pct_present), y = pct_present, fill = field)) +
  geom_col(position = "dodge", width = 0.7) +
  coord_flip() +
  scale_fill_manual(values = c("Primary" = UF_BLUE, "Secondary" = UF_ORANGE)) +
  scale_y_continuous(labels = scales::percent_format(scale = 1), expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "FLM Payer Completeness by Encounter Source",
    x = "Encounter Source",
    y = "% Present",
    fill = "Payer Field"
  ) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold", color = UF_BLUE), legend.position = "bottom")

chart_flm_top_patients <- flm_patient %>%
  arrange(desc(n_duplicate_dates)) %>%
  head(20) %>%
  mutate(ID = factor(ID, levels = rev(ID))) %>%
  ggplot(aes(x = ID, y = n_duplicate_dates)) +
  geom_col(fill = UF_ORANGE) +
  coord_flip() +
  labs(
    title = "Top 20 FLM Patients by Duplicate-Date Count",
    x = "Patient ID",
    y = "Duplicate Dates"
  ) +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold", color = UF_BLUE))

fig_uf_year <- "output/figures/phase24_uf_missingness_by_year.png"
fig_uf_enc <- "output/figures/phase24_uf_missingness_by_enc_type.png"
fig_flm_source <- "output/figures/phase24_flm_source_completeness.png"
fig_flm_patients <- "output/figures/phase24_flm_top_duplicate_patients.png"

ggsave(fig_uf_year, chart_uf_year, width = 10, height = 6, dpi = 300)
ggsave(fig_uf_enc, chart_uf_enc, width = 10, height = 6, dpi = 300)
ggsave(fig_flm_source, chart_flm_source, width = 10, height = 6, dpi = 300)
ggsave(fig_flm_patients, chart_flm_top_patients, width = 10, height = 6, dpi = 300)

message("Generated Phase 24 chart PNGs.")

# ------------------------------------------------------------------------------
# Build deck
# ------------------------------------------------------------------------------
pptx <- read_pptx()

# Title slide
pptx <- pptx %>%
  add_slide(layout = "Blank") %>%
  ph_with(
    value = fpar(ftext("Focused Diagnostic Presentation", prop = fp_text(font.size = 32, bold = TRUE, font.family = "Calibri", color = UF_BLUE))),
    location = ph_location(left = 0.7, top = 0.9, width = 8.6, height = 0.9)
  ) %>%
  ph_with(
    value = fpar(ftext("Phase 19 (UF Missingness) + Phase 20 (FLM Duplicate Dates)", prop = fp_text(font.size = 18, italic = TRUE, font.family = "Calibri", color = DARK_TEXT))),
    location = ph_location(left = 0.7, top = 1.9, width = 8.8, height = 0.8)
  ) %>%
  ph_with(
    value = block_list(
      fpar(ftext("- Standalone deck excluding generalized Phase 21/22 content", prop = fp_text(font.size = 14, font.family = "Calibri", color = DARK_TEXT))),
      fpar(ftext("- Includes both formatted tables and charts", prop = fp_text(font.size = 14, font.family = "Calibri", color = DARK_TEXT))),
      fpar(ftext("- Large/detail outputs are split or summarized for readability", prop = fp_text(font.size = 14, font.family = "Calibri", color = DARK_TEXT)))
    ),
    location = ph_location(left = 1.0, top = 3.0, width = 8.2, height = 2.2)
  ) %>%
  ph_with(
    value = fpar(ftext(glue("Generated: {Sys.Date()}"), prop = fp_text(font.size = 11, italic = TRUE, font.family = "Calibri", color = FOOTNOTE_TEXT))),
    location = ph_location(left = 0.7, top = 6.8, width = 8.5, height = 0.4)
  )

# Phase 19 section
pptx <- add_section_slide(pptx, "Phase 19", "UF Insurance Missingness")

pptx <- add_table_slide(
  pptx,
  "UF Missingness: Cross Summary",
  "Overall UF primary/secondary missingness across valid encounters",
  uf_cross_summary,
  footnote = "Derived from uf_payer_missingness_by_year.csv aggregates."
)

pptx <- add_image_slide(
  pptx,
  "UF Missingness by Year",
  "Primary missingness trend by admission year",
  fig_uf_year,
  footnote = "Source: uf_payer_missingness_by_year.csv"
)

uf_year_tbl <- uf_by_year %>%
  mutate(
    n_encounters = format(n_encounters, big.mark = ","),
    pct_primary_missing = fmt_pct(pct_primary_missing),
    pct_secondary_missing = fmt_pct(pct_secondary_missing),
    pct_both_missing = fmt_pct(pct_both_missing)
  ) %>%
  select(
    `Year` = admit_year,
    `Encounters` = n_encounters,
    `% Primary Missing` = pct_primary_missing,
    `% Secondary Missing` = pct_secondary_missing,
    `% Both Missing` = pct_both_missing
  )

pptx <- add_table_slide(
  pptx,
  "UF Missingness by Year",
  "Tabular yearly breakdown",
  uf_year_tbl,
  footnote = "1900 sentinel dates excluded in source diagnostic script."
)

pptx <- add_image_slide(
  pptx,
  "UF Missingness by Encounter Type",
  "Primary vs secondary missingness by encounter type",
  fig_uf_enc,
  footnote = "Source: uf_payer_missingness_by_enc_type.csv"
)

uf_enc_tbl <- uf_by_enc %>%
  mutate(
    n_encounters = format(n_encounters, big.mark = ","),
    pct_primary_missing = fmt_pct(pct_primary_missing),
    pct_secondary_missing = fmt_pct(pct_secondary_missing)
  ) %>%
  select(
    `Encounter Type` = ENC_TYPE_LABEL,
    `Encounters` = n_encounters,
    `% Primary Missing` = pct_primary_missing,
    `% Secondary Missing` = pct_secondary_missing
  )

pptx <- add_table_slide(
  pptx,
  "UF Missingness by Encounter Type",
  "Tabular encounter-type breakdown",
  uf_enc_tbl,
  footnote = "Encounter type labels follow source diagnostic coding."
)

uf_raw_harm_tbl <- uf_raw_vs_harm %>%
  mutate(
    n_encounters = format(n_encounters, big.mark = ","),
    pct_raw_primary = fmt_pct(pct_raw_primary),
    pct_harmonized = fmt_pct(pct_harmonized)
  ) %>%
  select(
    `Year` = year,
    `Encounters` = n_encounters,
    `% Raw Primary Missing` = pct_raw_primary,
    `% Harmonized Missing` = pct_harmonized
  )

pptx <- add_table_slide(
  pptx,
  "UF Raw vs Harmonized Missingness",
  "Comparison of raw primary payer missingness and harmonized missingness",
  uf_raw_harm_tbl,
  footnote = "OVERALL row plus yearly rows."
)

uf_raw_values_tbl <- uf_raw_values %>%
  group_by(field) %>%
  slice_max(order_by = n, n = 10, with_ties = FALSE) %>%
  ungroup() %>%
  mutate(
    n = format(n, big.mark = ","),
    pct = fmt_pct(pct)
  ) %>%
  transmute(
    `Field` = field,
    `Raw Value` = value,
    `Count` = n,
    `%` = pct
  )

pptx <- add_table_slide(
  pptx,
  "UF Raw Payer Values (Top 10 by Field)",
  "Top raw code frequencies for PRIMARY and SECONDARY fields",
  uf_raw_values_tbl,
  footnote = "Full raw distribution remains in uf_payer_raw_value_distribution.csv.",
  body_font_size = 10
)

uf_year_x_tbl <- uf_year_x_enc %>%
  mutate(
    n_encounters = format(n_encounters, big.mark = ","),
    pct_primary_missing = fmt_pct(pct_primary_missing)
  ) %>%
  select(
    `Year` = admit_year,
    `Encounter Type` = ENC_TYPE_LABEL,
    `Encounters` = n_encounters,
    `% Primary Missing` = pct_primary_missing
  )

uf_year_x_parts <- split_df(uf_year_x_tbl, chunk_size = 24)
for (i in seq_along(uf_year_x_parts)) {
  pptx <- add_table_slide(
    pptx,
    glue("UF Year x Encounter Type Missingness ({i}/{length(uf_year_x_parts)})"),
    "Split table for readability",
    uf_year_x_parts[[i]],
    footnote = "Source: uf_payer_missingness_year_x_enc_type.csv",
    body_font_size = 10
  )
}

# Phase 20 section
pptx <- add_section_slide(pptx, "Phase 20", "FLM Duplicate Encounter Dates")

pptx <- add_table_slide(
  pptx,
  "FLM Duplicate-Date Summary",
  "High-level duplicate and multi-source rates",
  flm_summary_tbl,
  footnote = "Computed from flm_patient_duplicate_summary.csv."
)

pptx <- add_image_slide(
  pptx,
  "Top FLM Patients by Duplicate-Date Count",
  "Top 20 patients ranked by number of duplicate dates",
  fig_flm_patients,
  footnote = "Source: flm_patient_duplicate_summary.csv"
)

flm_patient_tbl <- flm_patient %>%
  arrange(desc(n_multi_source_dates), desc(n_duplicate_dates)) %>%
  head(40) %>%
  mutate(
    n_unique_dates = format(n_unique_dates, big.mark = ","),
    n_total_encounters = format(n_total_encounters, big.mark = ","),
    pct_primary_present = fmt_pct(pct_primary_present),
    pct_secondary_present = fmt_pct(pct_secondary_present)
  ) %>%
  select(
    `Patient ID` = ID,
    `Unique Dates` = n_unique_dates,
    `Total Encounters` = n_total_encounters,
    `Duplicate Dates` = n_duplicate_dates,
    `Multi-source Dates` = n_multi_source_dates,
    `% Primary Present` = pct_primary_present,
    `% Secondary Present` = pct_secondary_present
  )

flm_patient_parts <- split_df(flm_patient_tbl, chunk_size = 20)
for (i in seq_along(flm_patient_parts)) {
  pptx <- add_table_slide(
    pptx,
    glue("FLM Patient Duplicate Summary ({i}/{length(flm_patient_parts)})"),
    "Top patients by multi-source and duplicate-date burden",
    flm_patient_parts[[i]],
    footnote = "Subset shown for presentation; full table in flm_patient_duplicate_summary.csv.",
    body_font_size = 10
  )
}

flm_date_parts <- split_df(flm_date_summary, chunk_size = 20)
for (i in seq_along(flm_date_parts)) {
  pptx <- add_table_slide(
    pptx,
    glue("FLM Date-level Duplicate Summary ({i}/{length(flm_date_parts)})"),
    "Date-level detail summarized (not raw full encounter table)",
    flm_date_parts[[i]],
    footnote = "Summarized from flm_date_level_duplicate_detail.csv for readability.",
    body_font_size = 10
  )
}

pptx <- add_image_slide(
  pptx,
  "FLM Source Payer Completeness",
  "Primary and secondary completeness by ENCOUNTER source",
  fig_flm_source,
  footnote = "Source: flm_source_payer_completeness.csv"
)

flm_source_tbl <- flm_source %>%
  mutate(
    n_encounters = format(n_encounters, big.mark = ","),
    pct_primary_present = fmt_pct(pct_primary_present),
    pct_secondary_present = fmt_pct(pct_secondary_present),
    pct_either_present = fmt_pct(pct_either_present)
  ) %>%
  select(
    `Source` = SOURCE,
    `Encounters` = n_encounters,
    `% Primary Present` = pct_primary_present,
    `% Secondary Present` = pct_secondary_present,
    `% Either Present` = pct_either_present
  )

pptx <- add_table_slide(
  pptx,
  "FLM Source Completeness Table",
  "Payer completeness among multi-source duplicate-date encounters",
  flm_source_tbl,
  footnote = "Used to derive source-preference recommendation."
)

pptx <- add_table_slide(
  pptx,
  "FLM Source Recommendation",
  "Preferred source for payer retention on duplicate-date conflicts",
  recommendation_tbl,
  footnote = "Recommendation is based on highest primary payer completeness."
)

# Closing slide
pptx <- pptx %>%
  add_slide(layout = "Blank") %>%
  ph_with(
    value = fpar(ftext("Key Takeaways", prop = fp_text(font.size = 30, bold = TRUE, font.family = "Calibri", color = UF_BLUE))),
    location = ph_location(left = 0.8, top = 0.9, width = 8.5, height = 0.8)
  ) %>%
  ph_with(
    value = block_list(
      fpar(ftext("- Phase 19 confirms UF missingness profile across year and encounter type.", prop = fp_text(font.size = 14, font.family = "Calibri", color = DARK_TEXT))),
      fpar(ftext("- Phase 20 quantifies FLM duplicate-date burden and multi-source overlap.", prop = fp_text(font.size = 14, font.family = "Calibri", color = DARK_TEXT))),
      fpar(ftext("- Source completeness evidence supports a concrete source-preference recommendation.", prop = fp_text(font.size = 14, font.family = "Calibri", color = DARK_TEXT))),
      fpar(ftext("- Full-detail CSV outputs remain available for audit-level review.", prop = fp_text(font.size = 14, font.family = "Calibri", color = DARK_TEXT)))
    ),
    location = ph_location(left = 0.9, top = 2.0, width = 8.4, height = 3.5)
  ) %>%
  ph_with(
    value = fpar(ftext("End of focused Phases 19/20 diagnostic presentation", prop = fp_text(font.size = 11, italic = TRUE, font.family = "Calibri", color = FOOTNOTE_TEXT))),
    location = ph_location(left = 0.8, top = 6.8, width = 8.8, height = 0.4)
  )

output_filename <- glue("insurance_tables_phase19_20_{Sys.Date()}.pptx")
print(pptx, target = output_filename)

message("\n", strrep("=", 70))
message(glue("Saved focused deck: {output_filename}"))
message(glue("Total slides: {length(pptx)}"))
message(strrep("=", 70))
