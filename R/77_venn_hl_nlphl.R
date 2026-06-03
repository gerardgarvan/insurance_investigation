# ==============================================================================
# 77_venn_hl_nlphl.R -- Venn diagram: Classical HL vs NLPHL patient overlap
# ==============================================================================
#
# Purpose:
#   Creates a Venn diagram showing how patients with Hodgkin Lymphoma (non-NLPHL)
#   and NLPHL diagnoses overlap. Some patients have both C81.0x (NLPHL) and
#   C81.1-C81.9 (classical HL) codes in their diagnosis records.
#
# Inputs:
#   - output/confirmed_hl_cohort.rds (confirmed HL patient IDs)
#   - DIAGNOSIS DuckDB table (C81 ICD-10 codes)
#
# Outputs:
#   - output/figures/venn_hl_nlphl.png
#
# Dependencies:
#   - R/00_config.R (CONFIG paths)
#   - R/01_load_pcornet.R (DuckDB connection, get_pcornet_table)
#
# ==============================================================================

# ==============================================================================
# SECTION 1: SETUP ----
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(ggplot2)
  library(glue)
  library(scales)
})

source("R/00_config.R")
source("R/01_load_pcornet.R")

message("\n", strrep("=", 60))
message("Venn Diagram: Classical HL vs NLPHL")
message(strrep("=", 60))

# ==============================================================================
# SECTION 2: LOAD CONFIRMED HL COHORT ----
# ==============================================================================

INPUT_RDS <- file.path(CONFIG$output_dir, "confirmed_hl_cohort.rds")
assert_rds_exists(INPUT_RDS, script_name = "R/77_venn")

confirmed_hl_cohort <- readRDS(INPUT_RDS)
message(glue("Loaded {format(nrow(confirmed_hl_cohort), big.mark=',')} confirmed HL patients"))

# ==============================================================================
# SECTION 3: EXTRACT C81 DIAGNOSES ----
# ==============================================================================

message("\nQuerying DIAGNOSIS for C81 codes...")

hl_c81_dx <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%
  select(ID, DX) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C81")) %>%
  filter(ID %in% confirmed_hl_cohort$ID)

message(glue("  Total C81 diagnosis rows: {format(nrow(hl_c81_dx), big.mark=',')}"))
message(glue("  Unique patients with C81: {format(n_distinct(hl_c81_dx$ID), big.mark=',')}"))

# ==============================================================================
# SECTION 4: CLASSIFY NLPHL vs CLASSICAL HL ----
# ==============================================================================

nlphl_ids <- hl_c81_dx %>%
  filter(str_detect(DX_norm, "^C810")) %>%
  pull(ID) %>%
  unique()

classical_ids <- hl_c81_dx %>%
  filter(!str_detect(DX_norm, "^C810")) %>%
  pull(ID) %>%
  unique()

both_ids <- intersect(nlphl_ids, classical_ids)
nlphl_only_ids <- setdiff(nlphl_ids, classical_ids)
classical_only_ids <- setdiff(classical_ids, nlphl_ids)

n_nlphl_only <- length(nlphl_only_ids)
n_classical_only <- length(classical_only_ids)
n_both <- length(both_ids)
n_total <- n_nlphl_only + n_classical_only + n_both

message(glue("\n  NLPHL only:      {format(n_nlphl_only, big.mark=',')} patients"))
message(glue("  Classical only:  {format(n_classical_only, big.mark=',')} patients"))
message(glue("  Both:            {format(n_both, big.mark=',')} patients"))
message(glue("  Total:           {format(n_total, big.mark=',')} patients"))

# ==============================================================================
# SECTION 5: BUILD VENN DIAGRAM ----
# ==============================================================================

# Venn geometry: two overlapping circles
# Left circle = NLPHL (C81.0x), Right circle = Classical HL (C81.1-C81.9)

# Circle parameters
circle_resolution <- 200
theta <- seq(0, 2 * pi, length.out = circle_resolution)
r <- 1.5  # radius
offset <- 0.9  # horizontal offset from center (controls overlap)

# Left circle (NLPHL)
left_circle <- data.frame(
  x = -offset + r * cos(theta),
  y = r * sin(theta),
  group = "NLPHL"
)

# Right circle (Classical HL)
right_circle <- data.frame(
  x = offset + r * cos(theta),
  y = r * sin(theta),
  group = "Classical HL"
)

circles <- bind_rows(left_circle, right_circle)

# Label positions
pct_nlphl_only <- n_nlphl_only / n_total * 100
pct_both <- n_both / n_total * 100
pct_classical_only <- n_classical_only / n_total * 100

labels_df <- data.frame(
  x = c(-offset - 0.5, 0, offset + 0.5),
  y = c(0, 0, 0),
  label = c(
    glue("{comma(n_nlphl_only)}\n({round(pct_nlphl_only, 1)}%)"),
    glue("{comma(n_both)}\n({round(pct_both, 1)}%)"),
    glue("{comma(n_classical_only)}\n({round(pct_classical_only, 1)}%)")
  )
)

# Group title positions (above circles)
titles_df <- data.frame(
  x = c(-offset, offset),
  y = c(r + 0.35, r + 0.35),
  label = c(
    glue("NLPHL\n(C81.0x)\nn = {comma(length(nlphl_ids))}"),
    glue("Classical HL\n(C81.1\u2013C81.9)\nn = {comma(length(classical_ids))}")
  )
)

# Color palette
fill_nlphl <- "#4BACC6"      # teal
fill_classical <- "#F79646"   # orange

p_venn <- ggplot() +
  # Draw filled circles with transparency
  geom_polygon(
    data = left_circle,
    aes(x = x, y = y),
    fill = fill_nlphl, alpha = 0.35, color = fill_nlphl, linewidth = 1
  ) +
  geom_polygon(
    data = right_circle,
    aes(x = x, y = y),
    fill = fill_classical, alpha = 0.35, color = fill_classical, linewidth = 1
  ) +
  # Count labels inside regions
  geom_text(
    data = labels_df,
    aes(x = x, y = y, label = label),
    size = 5, fontface = "bold", lineheight = 0.9
  ) +
  # Group titles above circles
  geom_text(
    data = titles_df,
    aes(x = x, y = y, label = label),
    size = 4, fontface = "bold", lineheight = 0.9
  ) +
  # Plot labels
  labs(
    title = "Patient Overlap: NLPHL vs Classical Hodgkin Lymphoma",
    subtitle = glue("Confirmed HL cohort | {comma(n_total)} patients with C81 diagnosis codes"),
    caption = glue(
      "NLPHL = Nodular Lymphocyte-Predominant HL (C81.0x) | ",
      "Classical HL = C81.1\u2013C81.9\n",
      "Overlap = patients with both NLPHL and Classical HL codes in their records"
    )
  ) +
  coord_equal() +
  theme_void(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14, hjust = 0.5),
    plot.subtitle = element_text(size = 11, hjust = 0.5, color = "gray30"),
    plot.caption = element_text(hjust = 0.5, face = "italic", color = "gray40", size = 9),
    plot.margin = margin(15, 15, 15, 15)
  )

# ==============================================================================
# SECTION 6: OUTPUT ----
# ==============================================================================

print(p_venn)
message("Venn diagram displayed in RStudio viewer")

ggsave(
  filename = build_output_path("figures", "venn_hl_nlphl.png"),
  plot = p_venn,
  width = 10,
  height = 7,
  units = "in",
  dpi = 300,
  bg = "white"
)

message(glue("Venn diagram saved to {file.path(CONFIG$output_dir, 'figures', 'venn_hl_nlphl.png')}"))

message("\n", strrep("=", 60))
message("Venn diagram complete")
message(strrep("=", 60))
