# ==============================================================================
# 05_visualize_waterfall.R -- Attrition waterfall chart
# ==============================================================================
# Produces vertical bar chart showing cohort reduction through filter steps.
# Each bar shows patients remaining, annotated with N and % excluded.
# Requirements: VIZ-01
# ==============================================================================

source("R/04_build_cohort.R")  # Loads attrition_log, hl_cohort, all upstream

library(ggplot2)
library(dplyr)
library(glue)
library(scales)

message("\n", strrep("=", 60))
message("Attrition Waterfall Chart")
message(strrep("=", 60))

# ==============================================================================
# SECTION 1: DATA PREPARATION
# ==============================================================================

# Prepare data for visualization
attrition_plot_data <- attrition_log %>%
  mutate(
    # Preserve filter step order (as executed)
    step = factor(step, levels = unique(step)),
    # Create annotation: For first row (Initial population), show N only
    # For subsequent rows, show "N\n(-X.X%)"
    label = if_else(
      pct_excluded == 0,
      glue("{comma(n_after)}"),
      glue("{comma(n_after)}\n(-{round(pct_excluded, 1)}%)")
    )
  )

message(glue("Prepared {nrow(attrition_plot_data)} attrition steps for visualization"))
message(glue("Range: {comma(max(attrition_plot_data$n_before))} -> {comma(min(attrition_plot_data$n_after))} patients"))

# ==============================================================================
# SECTION 2: BUILD WATERFALL CHART
# ==============================================================================

p_waterfall <- ggplot(attrition_plot_data, aes(x = step, y = n_after)) +
  geom_col(fill = "steelblue3", width = 0.7, alpha = 0.9) +
  geom_text(
    aes(label = label),
    vjust = -0.5,
    size = 3.5,
    fontface = "bold"
  ) +
  scale_y_continuous(
    labels = comma,
    expand = expansion(mult = c(0, 0.15))  # Extra space above for labels
  ) +
  labs(
    title = "Cohort Attrition Through Filter Steps",
    subtitle = glue("Hodgkin Lymphoma cohort: {comma(max(attrition_plot_data$n_before))} -> {comma(min(attrition_plot_data$n_after))} patients"),
    x = "Filter Step",
    y = "Patients Remaining",
    caption = "Annotations show N remaining and % excluded from previous step"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold", size = 14),
    plot.caption = element_text(hjust = 0, face = "italic", color = "gray40")
  )

# ==============================================================================
# SECTION 3: OUTPUT
# ==============================================================================

# Display in RStudio viewer
print(p_waterfall)
message("Waterfall chart displayed in RStudio viewer")

# Create output directory
dir.create(file.path(CONFIG$output_dir, "figures"), showWarnings = FALSE, recursive = TRUE)

# Save PNG
ggsave(
  filename = file.path(CONFIG$output_dir, "figures", "waterfall_attrition.png"),
  plot = p_waterfall,
  width = 10,
  height = 7,
  units = "in",
  dpi = 300,
  bg = "white"
)

message(glue("Waterfall chart saved to {file.path(CONFIG$output_dir, 'figures', 'waterfall_attrition.png')}"))

message("\n", strrep("=", 60))
message("Waterfall chart complete")
message(strrep("=", 60))

# ==============================================================================
# End of 05_visualize_waterfall.R
# ==============================================================================
