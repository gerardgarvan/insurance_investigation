# ==============================================================================
# 06_visualize_sankey.R -- Payer-stratified Sankey/alluvial diagram
# ==============================================================================
# Produces two-axis alluvial diagram: Payer Category -> Treatment Type
# Flows colored by payer category using colorblind-safe viridis palette.
# Requirements: VIZ-02
# NOTE: HIPAA small-cell suppression deferred to v2 (D-11). Outputs are exploratory, remain on HiPerGator.
# ==============================================================================

source("R/04_build_cohort.R")  # Loads hl_cohort, all upstream

library(ggplot2)
library(ggalluvial)
library(dplyr)
library(forcats)
library(glue)
library(scales)

message("\n", strrep("=", 60))
message("Payer-Stratified Sankey Diagram")
message(strrep("=", 60))

# ==============================================================================
# SECTION 1: DERIVE MUTUALLY EXCLUSIVE TREATMENT CATEGORIES
# ==============================================================================

message("\n--- Deriving Treatment Categories ---")

# Use hierarchical case_when() -- SCT most intensive, checked first (D-06)
sankey_data <- hl_cohort %>%
  mutate(
    TREATMENT_CATEGORY = case_when(
      HAD_SCT == 1                           ~ "SCT (any combination)",
      HAD_CHEMO == 1 & HAD_RADIATION == 1    ~ "Chemo + Radiation",
      HAD_CHEMO == 1                         ~ "Chemo only",
      HAD_RADIATION == 1                     ~ "Radiation only",
      TRUE                                   ~ "No treatment evidence"
    )
  )

# Show treatment category distribution before collapsing
tx_dist <- sankey_data %>%
  count(TREATMENT_CATEGORY, name = "n") %>%
  arrange(desc(n))

message("Treatment category distribution (before collapsing):")
for (i in seq_len(nrow(tx_dist))) {
  message(glue("  {tx_dist$TREATMENT_CATEGORY[i]}: {tx_dist$n[i]}"))
}

# ==============================================================================
# SECTION 2: COLLAPSE RARE TREATMENT COMBINATIONS (D-10)
# ==============================================================================

message("\n--- Collapsing Rare Treatment Combinations ---")

# Use mutate + if_else to RECODE (not filter -- never drop rows)
sankey_data <- sankey_data %>%
  group_by(TREATMENT_CATEGORY) %>%
  mutate(
    n_in_category = n(),
    TREATMENT_CATEGORY = if_else(
      n_in_category <= 10 & TREATMENT_CATEGORY != "No treatment evidence",
      "Multiple treatments",
      TREATMENT_CATEGORY
    )
  ) %>%
  ungroup() %>%
  select(-n_in_category)

# Show treatment category distribution after collapsing
tx_dist_collapsed <- sankey_data %>%
  count(TREATMENT_CATEGORY, name = "n") %>%
  arrange(desc(n))

message("Treatment category distribution (after collapsing <=10):")
for (i in seq_len(nrow(tx_dist_collapsed))) {
  message(glue("  {tx_dist_collapsed$TREATMENT_CATEGORY[i]}: {tx_dist_collapsed$n[i]}"))
}

# Verify no patients dropped
stopifnot(nrow(sankey_data) == nrow(hl_cohort))
message(glue("Verified: Row count unchanged ({nrow(sankey_data)} patients)"))

# ==============================================================================
# SECTION 3: COLLAPSE SMALL PAYER CATEGORIES (D-08)
# ==============================================================================

message("\n--- Collapsing Small Payer Categories ---")

# Show payer distribution before collapsing
payer_dist_before <- sankey_data %>%
  count(PAYER_CATEGORY_PRIMARY, name = "n") %>%
  arrange(desc(n))

message("Payer category distribution (before collapsing):")
for (i in seq_len(nrow(payer_dist_before))) {
  message(glue("  {payer_dist_before$PAYER_CATEGORY_PRIMARY[i]}: {payer_dist_before$n[i]}"))
}

# Collapse small payer categories into "Other" (D-08)
sankey_data <- sankey_data %>%
  mutate(
    PAYER_CATEGORY_PRIMARY = fct_lump_n(
      fct_infreq(PAYER_CATEGORY_PRIMARY),
      n = 7,
      other_level = "Other"
    )
  )

# Show payer distribution after collapsing
payer_dist_after <- sankey_data %>%
  count(PAYER_CATEGORY_PRIMARY, name = "n") %>%
  arrange(desc(n))

message("Payer category distribution (after collapsing to top 7):")
for (i in seq_len(nrow(payer_dist_after))) {
  message(glue("  {payer_dist_after$PAYER_CATEGORY_PRIMARY[i]}: {payer_dist_after$n[i]}"))
}

# ==============================================================================
# SECTION 4: CREATE STRATUM LABELS WITH N COUNTS (D-09)
# ==============================================================================

message("\n--- Creating Stratum Labels ---")

# Encode N into factor levels for payer axis
payer_counts <- sankey_data %>% count(PAYER_CATEGORY_PRIMARY, name = "n_patients")
sankey_data <- sankey_data %>%
  left_join(payer_counts, by = "PAYER_CATEGORY_PRIMARY") %>%
  mutate(
    PAYER_LABEL = glue("{PAYER_CATEGORY_PRIMARY}\n(N={comma(n_patients)})"),
    PAYER_LABEL = fct_reorder(PAYER_LABEL, n_patients, .desc = TRUE)
  ) %>%
  select(-n_patients)

# Same for treatment axis
tx_counts <- sankey_data %>% count(TREATMENT_CATEGORY, name = "n_patients")
sankey_data <- sankey_data %>%
  left_join(tx_counts, by = "TREATMENT_CATEGORY") %>%
  mutate(
    TREATMENT_LABEL = glue("{TREATMENT_CATEGORY}\n(N={comma(n_patients)})"),
    TREATMENT_LABEL = fct_reorder(TREATMENT_LABEL, n_patients, .desc = TRUE)
  ) %>%
  select(-n_patients)

message(glue("Created stratum labels with N counts for {n_distinct(sankey_data$PAYER_LABEL)} payer categories"))
message(glue("Created stratum labels with N counts for {n_distinct(sankey_data$TREATMENT_LABEL)} treatment categories"))

# Snapshot: figure backing data (per SNAP-03)
save_output_data(sankey_data, "sankey_patient_flow_data")

# ==============================================================================
# SECTION 5: BUILD GGALLUVIAL PLOT (D-05, D-07)
# ==============================================================================

message("\n--- Building Sankey Diagram ---")

p_sankey <- ggplot(
  sankey_data,
  aes(axis1 = PAYER_LABEL, axis2 = TREATMENT_LABEL)
) +
  geom_alluvium(
    aes(fill = PAYER_LABEL),
    curve_type = "xspline",
    alpha = 0.7,
    width = 1/12
  ) +
  geom_stratum(width = 1/12, fill = "gray90", color = "gray50") +
  geom_text(
    stat = "stratum",
    aes(label = after_stat(stratum)),
    size = 3
  ) +
  scale_x_discrete(
    limits = c("Payer Category", "Treatment Type"),
    expand = c(0.15, 0.15)
  ) +
  scale_fill_viridis_d(
    option = "mako",
    name = "Payer Category",
    begin = 0.1,
    end = 0.9
  ) +
  labs(
    title = "Patient Flow: Payer Category to Treatment Type",
    subtitle = glue("Hodgkin Lymphoma cohort (N = {comma(nrow(sankey_data))})"),
    caption = "Flow width proportional to patient count; rare categories collapsed"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    legend.position = "bottom",
    legend.title = element_text(face = "bold"),
    axis.text.x = element_text(face = "bold", size = 11),
    axis.text.y = element_blank(),
    axis.title = element_blank(),
    panel.grid = element_blank(),
    plot.title = element_text(face = "bold", size = 14),
    plot.caption = element_text(hjust = 0, face = "italic", color = "gray40")
  )

# ==============================================================================
# SECTION 6: OUTPUT
# ==============================================================================

# Display in RStudio viewer
print(p_sankey)
message("Sankey diagram displayed in RStudio viewer")

# Create output directory
dir.create(file.path(CONFIG$output_dir, "figures"), showWarnings = FALSE, recursive = TRUE)

# Save PNG
ggsave(
  filename = file.path(CONFIG$output_dir, "figures", "sankey_patient_flow.png"),
  plot = p_sankey,
  width = 10,
  height = 7,
  units = "in",
  dpi = 300,
  bg = "white"
)

message(glue("Sankey diagram saved to {file.path(CONFIG$output_dir, 'figures', 'sankey_patient_flow.png')}"))

message("\n", strrep("=", 60))
message("Sankey diagram complete")
message(strrep("=", 60))

# ==============================================================================
# End of 06_visualize_sankey.R
# ==============================================================================
