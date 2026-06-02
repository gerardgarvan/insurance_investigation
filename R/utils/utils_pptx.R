# ==============================================================================
# utils/utils_pptx.R -- PowerPoint styling and slide generation helpers using officer package
# ==============================================================================
#
# Purpose:
#   PowerPoint styling and slide generation helpers using officer package. Provides
#   UF brand colors, table styling, and slide layout functions. Used by R/72 and
#   R/73 PPTX generation scripts. style_table() applies UF Health blue/orange brand
#   colors to flextables with parameterized fonts, padding, and alternating row colors.
#   add_title_slide() and add_section_divider() create branded title and section slides.
#
# Inputs:
#   - None (utility function library, not a standalone script)
#
# Outputs:
#   - None (defines functions loaded into calling scripts' environment)
#
# Dependencies:
#   - officer: PowerPoint document creation and slide manipulation
#   - flextable: Table styling and formatting
#
# Requirements: N/A (utility module)
#
# ==============================================================================

# ------------------------------------------------------------------------------
# UF Health brand colors (matches Python pipeline)
# ------------------------------------------------------------------------------
UF_BLUE <- "#003087"
UF_ORANGE <- "#FA4616"
LIGHT_BLUE <- "#CCD5EA" # Alternating row color (odd rows)
LIGHT_ORANGE <- "#FDD9CC" # Alternating row color (even rows)
DARK_TEXT <- "#333333"
FOOTNOTE_TEXT <- "#666666"

#' Apply UF Health brand styling to a flextable
#'
#' Unified styling function with parameterized fonts, padding, and first-column
#' bolding. Defaults preserve R/11 behavior (body=12, header=13, bold first col).
#' R/22 uses body=11, header=12, no bold first col, padding=5.
#'
#' @param ft Flextable object
#' @param total_row Integer. Row index for "Total" row (bold + blue bg)
#' @param body_font_size Numeric. Body text font size (default 12)
#' @param header_font_size Numeric. Header text font size (default 13)
#' @param bold_first_col Logical. Bold first column (default TRUE)
#' @param padding Numeric. Left/right padding in pixels (top/bottom = padding/2)
#' @return Styled flextable object
style_table <- function(ft, total_row = integer(0), body_font_size = 12,
                        header_font_size = 13, bold_first_col = TRUE, padding = 6) {
  n_rows <- nrow_part(ft, "body")
  odd_rows <- if (n_rows >= 1) seq(1, n_rows, by = 2) else integer(0)
  even_rows <- if (n_rows >= 2) seq(2, n_rows, by = 2) else integer(0)

  ft <- ft %>%
    fontsize(size = body_font_size, part = "body") %>%
    fontsize(size = header_font_size, part = "header") %>%
    font(fontname = "Calibri", part = "all") %>%
    bold(part = "header") %>%
    bg(bg = UF_BLUE, part = "header") %>%
    color(color = "white", part = "header") %>%
    color(color = DARK_TEXT, part = "body") %>%
    align(align = "center", part = "header") %>%
    align(j = 1, align = "left", part = "body") %>%
    align(j = -1, align = "center", part = "body") %>%
    border_remove() %>%
    padding(
      padding.left = padding, padding.right = padding,
      padding.top = ceiling(padding / 2), padding.bottom = ceiling(padding / 2), part = "all"
    )

  # Conditionally bold first column (R/11 uses this; R/22 does not)
  if (bold_first_col) {
    ft <- ft %>% bold(j = 1, part = "body")
  }

  # Alternating row colors (light blue / light orange)
  if (length(odd_rows) > 0) ft <- ft %>% bg(i = odd_rows, bg = LIGHT_BLUE, part = "body")
  if (length(even_rows) > 0) ft <- ft %>% bg(i = even_rows, bg = LIGHT_ORANGE, part = "body")

  # Bold the Total row with distinct styling
  if (length(total_row) > 0 && total_row[1] > 0) {
    ft <- ft %>%
      bold(i = total_row[1], part = "body") %>%
      bg(i = total_row[1], bg = UF_BLUE, part = "body") %>%
      color(i = total_row[1], color = "white", part = "body")
  }

  ft %>% autofit()
}

#' Add a table slide with title, subtitle, and optional footnote
#'
#' Creates a blank slide with styled title, subtitle, flextable, and footnote.
#' Used by R/22 for Phase 19/20 pptx generation. Automatically detects "Total"
#' row for special styling.
#'
#' @param pptx officer pptx object
#' @param title Character. Slide title
#' @param subtitle Character. Slide subtitle
#' @param tbl_data Data frame. Table data to display
#' @param footnote Character. Optional footnote text (NULL to omit)
#' @param body_font_size Numeric. Body text font size (default 11 for R/22)
#' @return Updated pptx object
add_table_slide <- function(pptx, title, subtitle, tbl_data, footnote = NULL, body_font_size = 11) {
  total_row_idx <- which(tbl_data[[1]] == "Total")
  # Use R/22 styling: body=11, header=12, no bold first col, padding=5
  ft <- flextable(tbl_data) %>%
    style_table(
      total_row = total_row_idx, body_font_size = body_font_size,
      header_font_size = 12, bold_first_col = FALSE, padding = 5
    )

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
