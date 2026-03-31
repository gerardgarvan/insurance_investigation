# ==============================================================================
# 16_encounter_analysis.R -- Encounter analysis by payor, DX year, age group
# ==============================================================================
#
# Produces:
#   1. Histogram of encounters per person by payor category
#   2. Post-treatment encounters per person by year of diagnosis
#   3. Total encounters per person by year of diagnosis
#   4. Summary table with column sums
#   5. Post-treatment encounter breakdown by age group
#
# Usage:
#   source("R/16_encounter_analysis.R")
#
# ==============================================================================

source("R/04_build_cohort.R")

library(ggplot2)
library(dplyr)
library(tidyr)
library(glue)
library(scales)
library(readr)

message("\n", strrep("=", 60))
message("Encounter Analysis")
message(strrep("=", 60))

# ==============================================================================
# SECTION 1: HISTOGRAM -- Encounters per person by payor category
# ==============================================================================

message("\n--- Histogram: Encounters per person by payor ---")

hist_data <- hl_cohort %>%
  filter(!is.na(PAYER_CATEGORY_PRIMARY), !is.na(N_ENCOUNTERS))

p1 <- ggplot(hist_data, aes(x = N_ENCOUNTERS, fill = PAYER_CATEGORY_PRIMARY)) +
  geom_histogram(binwidth = 5, color = "white", linewidth = 0.2) +
  facet_wrap(~ PAYER_CATEGORY_PRIMARY, scales = "free_y") +
  labs(
    title = "Number of Encounters per Person by Payor Category",
    x = "Number of Encounters",
    y = "Number of Patients"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none",
        strip.text = element_text(face = "bold")) +
  scale_fill_viridis_d()

ggsave("output/figures/encounters_per_person_by_payor.png", p1,
       width = 12, height = 8, dpi = 300)
message("  Saved: output/figures/encounters_per_person_by_payor.png")

# ==============================================================================
# SECTION 2: POST-TREATMENT ENCOUNTERS per person by year of diagnosis
# ==============================================================================

message("\n--- Post-treatment encounters by DX year ---")

enc_by_year <- hl_cohort %>%
  filter(!is.na(DX_YEAR), !is.na(N_ENC_NONACUTE_CARE)) %>%
  group_by(DX_YEAR) %>%
  summarise(
    n_patients = n(),
    mean_post_tx_enc = mean(N_ENC_NONACUTE_CARE, na.rm = TRUE),
    median_post_tx_enc = median(N_ENC_NONACUTE_CARE, na.rm = TRUE),
    mean_total_enc = mean(N_ENCOUNTERS, na.rm = TRUE),
    median_total_enc = median(N_ENCOUNTERS, na.rm = TRUE),
    .groups = "drop"
  )

p2 <- ggplot(enc_by_year, aes(x = DX_YEAR, y = mean_post_tx_enc)) +
  geom_col(fill = "#2c7fb8", alpha = 0.8) +
  geom_text(aes(label = round(mean_post_tx_enc, 1)), vjust = -0.3, size = 3) +
  labs(
    title = "Mean Post-Treatment Encounters per Person by Year of Diagnosis",
    x = "Year of Diagnosis",
    y = "Mean Post-Treatment Encounters"
  ) +
  theme_minimal(base_size = 11) +
  scale_x_continuous(breaks = pretty_breaks())

ggsave("output/figures/post_tx_encounters_by_dx_year.png", p2,
       width = 10, height = 6, dpi = 300)
message("  Saved: output/figures/post_tx_encounters_by_dx_year.png")

# ==============================================================================
# SECTION 3: TOTAL ENCOUNTERS per person by year of diagnosis
# ==============================================================================

message("\n--- Total encounters by DX year ---")

p3 <- ggplot(enc_by_year, aes(x = DX_YEAR, y = mean_total_enc)) +
  geom_col(fill = "#41ae76", alpha = 0.8) +
  geom_text(aes(label = round(mean_total_enc, 1)), vjust = -0.3, size = 3) +
  labs(
    title = "Mean Total Encounters per Person by Year of Diagnosis",
    x = "Year of Diagnosis",
    y = "Mean Total Encounters"
  ) +
  theme_minimal(base_size = 11) +
  scale_x_continuous(breaks = pretty_breaks())

ggsave("output/figures/total_encounters_by_dx_year.png", p3,
       width = 10, height = 6, dpi = 300)
message("  Saved: output/figures/total_encounters_by_dx_year.png")

# ==============================================================================
# SECTION 4: SUMMARY TABLE with column sums
# ==============================================================================

message("\n--- Summary table: Encounters by payor and age group ---")

summary_tbl <- hl_cohort %>%
  filter(!is.na(PAYER_CATEGORY_PRIMARY), !is.na(AGE_GROUP)) %>%
  group_by(PAYER_CATEGORY_PRIMARY, AGE_GROUP) %>%
  summarise(
    n_patients = n(),
    total_encounters = sum(N_ENCOUNTERS, na.rm = TRUE),
    total_post_tx_enc = sum(N_ENC_NONACUTE_CARE, na.rm = TRUE),
    pct_with_post_tx = round(100 * mean(HAS_POST_TX_ENCOUNTERS == "Yes", na.rm = TRUE), 1),
    .groups = "drop"
  )

# Add column sums (totals row per payor)
payor_totals <- summary_tbl %>%
  group_by(PAYER_CATEGORY_PRIMARY) %>%
  summarise(
    AGE_GROUP = "Total",
    n_patients = sum(n_patients),
    total_encounters = sum(total_encounters),
    total_post_tx_enc = sum(total_post_tx_enc),
    pct_with_post_tx = round(100 * total_post_tx_enc / total_encounters * 100, 1) / 100,
    .groups = "drop"
  )

# Add grand totals row
grand_total <- summary_tbl %>%
  summarise(
    PAYER_CATEGORY_PRIMARY = "TOTAL",
    AGE_GROUP = "Total",
    n_patients = sum(n_patients),
    total_encounters = sum(total_encounters),
    total_post_tx_enc = sum(total_post_tx_enc),
    pct_with_post_tx = round(100 * sum(total_post_tx_enc) / sum(total_encounters) * 100, 1) / 100
  )

summary_with_sums <- bind_rows(summary_tbl, payor_totals, grand_total) %>%
  arrange(PAYER_CATEGORY_PRIMARY, AGE_GROUP)

write_csv(summary_with_sums, "output/tables/encounter_summary_by_payor_age.csv")
message("  Saved: output/tables/encounter_summary_by_payor_age.csv")

# ==============================================================================
# SECTION 5: POST-TREATMENT ENCOUNTERS by age group (Yes/No breakdown)
# ==============================================================================

message("\n--- Post-treatment encounters by age group ---")

age_post_tx <- hl_cohort %>%
  filter(!is.na(AGE_GROUP)) %>%
  count(AGE_GROUP, HAS_POST_TX_ENCOUNTERS, name = "n") %>%
  group_by(AGE_GROUP) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  ungroup()

p4 <- ggplot(age_post_tx, aes(x = AGE_GROUP, y = n, fill = HAS_POST_TX_ENCOUNTERS)) +
  geom_col(position = "dodge") +
  geom_text(aes(label = paste0(n, "\n(", pct, "%)")),
            position = position_dodge(width = 0.9), vjust = -0.3, size = 3) +
  labs(
    title = "Post-Treatment Encounters by Age Group (Yes/No)",
    x = "Age Group at Diagnosis",
    y = "Number of Patients",
    fill = "Has Post-Tx\nEncounters"
  ) +
  theme_minimal(base_size = 11) +
  scale_fill_manual(values = c("Yes" = "#2c7fb8", "No" = "#d95f02"))

ggsave("output/figures/post_tx_by_age_group.png", p4,
       width = 8, height = 6, dpi = 300)
message("  Saved: output/figures/post_tx_by_age_group.png")

# Print summary to console
message("\n--- Age Group Summary ---")
age_summary <- age_post_tx %>%
  pivot_wider(names_from = HAS_POST_TX_ENCOUNTERS, values_from = c(n, pct), values_fill = 0)
print(age_summary)

write_csv(age_post_tx, "output/tables/post_tx_encounters_by_age_group.csv")
message("  Saved: output/tables/post_tx_encounters_by_age_group.csv")

message("\n", strrep("=", 60))
message("Encounter analysis complete")
message(strrep("=", 60))
