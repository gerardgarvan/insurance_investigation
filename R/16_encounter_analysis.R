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
# PPTX2-04: Verified -- 6+Missing payer, >500 overflow bin with per-facet annotation (Phase 12)

message("\n--- Histogram: Encounters per person by payor ---")

hist_data <- hl_cohort %>%
  filter(!is.na(PAYER_CATEGORY_PRIMARY), !is.na(N_ENCOUNTERS)) %>%
  mutate(
    PAYER_CATEGORY_PRIMARY = case_when(
      PAYER_CATEGORY_PRIMARY %in% c("Other", "Unavailable", "Unknown") ~ "Missing",
      TRUE ~ PAYER_CATEGORY_PRIMARY
    ),
    PAYER_CATEGORY_PRIMARY = factor(PAYER_CATEGORY_PRIMARY,
      levels = c("Medicare", "Medicaid", "Dual eligible", "Private",
                 "Other government", "No payment / Self-pay", "Missing"))
  )

# Cap x-axis at 500 to show bulk of distribution (median ~93, Q3 ~243)
x_cap <- 500

# Compute per-facet overflow counts for annotation
overflow_counts <- hist_data %>%
  filter(N_ENCOUNTERS > x_cap) %>%
  count(PAYER_CATEGORY_PRIMARY, name = "n_overflow", .drop = FALSE)

# Cap encounter values for binning (create overflow bin)
hist_data <- hist_data %>%
  mutate(N_ENC_CAPPED = if_else(N_ENCOUNTERS > x_cap, as.numeric(x_cap + 1), as.numeric(N_ENCOUNTERS)))

# Snapshot: figure backing data (per SNAP-03)
save_output_data(hist_data, "encounters_per_person_by_payor_data")

n_beyond <- sum(hist_data$N_ENCOUNTERS > x_cap)

p1 <- ggplot(hist_data, aes(x = N_ENC_CAPPED, fill = PAYER_CATEGORY_PRIMARY)) +
  geom_histogram(binwidth = 20, color = "white", linewidth = 0.2) +
  geom_text(data = overflow_counts %>% filter(n_overflow > 0),
            aes(x = x_cap + 10, y = Inf, label = paste0(">", x_cap, ": ", n_overflow)),
            vjust = 1.5, hjust = 0, size = 2.8, inherit.aes = FALSE) +
  facet_wrap(~ PAYER_CATEGORY_PRIMARY, scales = "free_y") +
  coord_cartesian(xlim = c(0, x_cap + 40)) +
  scale_x_continuous(breaks = seq(0, x_cap, by = 100),
                     labels = c(seq(0, x_cap - 100, by = 100), paste0(x_cap, "+"))) +
  labs(
    title = "Number of Encounters per Person by Payor Category",
    subtitle = glue("{n_beyond} patients with >{x_cap} encounters shown in overflow bin"),
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

# 1900 sentinel dates are already nullified in 04_build_cohort.R Section 4,
# so DX_YEAR is NA for those patients.
n_missing_dx_year <- sum(is.na(hl_cohort$DX_YEAR))
message(glue("  {n_missing_dx_year} patients with missing DX_YEAR (includes nullified 1900 sentinels) excluded from DX year plots"))

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

# Snapshot: figure backing data (per SNAP-03)
save_output_data(enc_by_year, "post_tx_encounters_by_dx_year_data")

p2 <- ggplot(enc_by_year, aes(x = DX_YEAR, y = mean_post_tx_enc)) +
  geom_col(fill = "#2c7fb8", alpha = 0.8) +
  geom_text(aes(label = round(mean_post_tx_enc, 1)), vjust = -0.3, size = 3) +
  labs(
    title = "Mean Post-Treatment Encounters per Person by Year of Diagnosis",
    subtitle = if (n_missing_dx_year > 0) glue("{n_missing_dx_year} patients with missing diagnosis date excluded") else NULL,
    x = "Year of Diagnosis",
    y = "Mean Post-Treatment Encounters"
  ) +
  theme_minimal(base_size = 11) +
  scale_x_continuous(breaks = pretty_breaks()) +
  coord_cartesian(clip = "off", ylim = c(0, max(enc_by_year$mean_post_tx_enc, na.rm = TRUE) * 1.15)) +
  theme(plot.margin = margin(t = 10, r = 5, b = 5, l = 5))

ggsave("output/figures/post_tx_encounters_by_dx_year.png", p2,
       width = 10, height = 6, dpi = 300)
message("  Saved: output/figures/post_tx_encounters_by_dx_year.png")

# ==============================================================================
# SECTION 3: TOTAL ENCOUNTERS per person by year of diagnosis
# ==============================================================================

message("\n--- Total encounters by DX year ---")

# Snapshot: figure backing data (per SNAP-03)
save_output_data(enc_by_year, "total_encounters_by_dx_year_data")

p3 <- ggplot(enc_by_year, aes(x = DX_YEAR, y = mean_total_enc)) +
  geom_col(fill = "#41ae76", alpha = 0.8) +
  geom_text(aes(label = round(mean_total_enc, 1)), vjust = -0.3, size = 3) +
  labs(
    title = "Mean Total Encounters per Person by Year of Diagnosis",
    subtitle = if (n_missing_dx_year > 0) glue("{n_missing_dx_year} patients with missing diagnosis date excluded") else NULL,
    x = "Year of Diagnosis",
    y = "Mean Total Encounters"
  ) +
  theme_minimal(base_size = 11) +
  scale_x_continuous(breaks = pretty_breaks()) +
  coord_cartesian(clip = "off", ylim = c(0, max(enc_by_year$mean_total_enc, na.rm = TRUE) * 1.15)) +
  theme(plot.margin = margin(t = 10, r = 5, b = 5, l = 5))

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

# Snapshot: table backing data (per SNAP-04)
save_output_data(summary_with_sums, "encounter_summary_by_payor_age_data")

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

# Snapshot: figure backing data (per SNAP-03)
save_output_data(age_post_tx, "post_tx_by_age_group_data")

# PPTX2-07: Verified -- clip="off" + ylim expansion prevents label clipping (Phase 12)
max_y_p4 <- max(age_post_tx$n, na.rm = TRUE)

p4 <- ggplot(age_post_tx, aes(x = AGE_GROUP, y = n, fill = HAS_POST_TX_ENCOUNTERS)) +
  geom_col(position = "dodge") +
  geom_text(aes(label = paste0(n, "\n(", pct, "%)")),
            position = position_dodge(width = 0.9), vjust = -0.3, size = 3) +
  coord_cartesian(clip = "off", ylim = c(0, max_y_p4 * 1.2)) +
  labs(
    title = "Post-Treatment Encounters by Age Group (Yes/No)",
    x = "Age Group at Diagnosis",
    y = "Number of Patients",
    fill = "Has Post-Tx\nEncounters"
  ) +
  theme_minimal(base_size = 11) +
  theme(plot.margin = margin(t = 15, r = 5, b = 5, l = 5)) +
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

# ==============================================================================
# SECTION 6: UNIQUE DATES -- Same analyses using distinct encounter dates per ID
# ==============================================================================

message("\n--- Unique Dates Analysis (distinct dates per patient) ---")

# 6a. Compute unique encounter dates per patient (total)
unique_dates_total <- encounters %>%
  filter(!is.na(ADMIT_DATE)) %>%
  group_by(ID) %>%
  summarise(N_UNIQUE_DATES = n_distinct(ADMIT_DATE), .groups = "drop")

# 6b. Compute unique post-treatment dates (AV+TH post-diagnosis, mirrors Level 1)
first_dx_map <- hl_cohort %>%
  select(ID, first_hl_dx_date) %>%
  filter(!is.na(first_hl_dx_date))

unique_dates_post_tx <- pcornet$ENCOUNTER %>%
  filter(ENC_TYPE %in% c("AV", "TH")) %>%
  inner_join(first_dx_map, by = "ID") %>%
  filter(!is.na(ADMIT_DATE), ADMIT_DATE > first_hl_dx_date) %>%
  group_by(ID) %>%
  summarise(N_UNIQUE_DATES_POST_TX = n_distinct(ADMIT_DATE), .groups = "drop")

# Join to cohort for this analysis
cohort_ud <- hl_cohort %>%
  left_join(unique_dates_total, by = "ID") %>%
  left_join(unique_dates_post_tx, by = "ID") %>%
  mutate(
    N_UNIQUE_DATES = coalesce(N_UNIQUE_DATES, 0L),
    N_UNIQUE_DATES_POST_TX = coalesce(N_UNIQUE_DATES_POST_TX, 0L)
  )

message(glue("  Total unique dates: mean={round(mean(cohort_ud$N_UNIQUE_DATES),1)}, median={median(cohort_ud$N_UNIQUE_DATES)}"))
message(glue("  Post-tx unique dates: mean={round(mean(cohort_ud$N_UNIQUE_DATES_POST_TX),1)}, median={median(cohort_ud$N_UNIQUE_DATES_POST_TX)}"))

# 6c. Histogram: unique dates per person by payer category
hist_data_ud <- cohort_ud %>%
  filter(!is.na(PAYER_CATEGORY_PRIMARY), !is.na(N_UNIQUE_DATES)) %>%
  mutate(
    PAYER_CATEGORY_PRIMARY = case_when(
      PAYER_CATEGORY_PRIMARY %in% c("Other", "Unavailable", "Unknown") ~ "Missing",
      TRUE ~ PAYER_CATEGORY_PRIMARY
    ),
    PAYER_CATEGORY_PRIMARY = factor(PAYER_CATEGORY_PRIMARY,
      levels = c("Medicare", "Medicaid", "Dual eligible", "Private",
                 "Other government", "No payment / Self-pay", "Missing"))
  )

x_cap_ud <- 300

overflow_counts_ud <- hist_data_ud %>%
  filter(N_UNIQUE_DATES > x_cap_ud) %>%
  count(PAYER_CATEGORY_PRIMARY, name = "n_overflow", .drop = FALSE)

hist_data_ud <- hist_data_ud %>%
  mutate(N_UD_CAPPED = if_else(N_UNIQUE_DATES > x_cap_ud, as.numeric(x_cap_ud + 1), as.numeric(N_UNIQUE_DATES)))

# Snapshot: figure backing data (per SNAP-03)
save_output_data(hist_data_ud, "unique_dates_per_person_by_payor_data")

n_beyond_ud <- sum(cohort_ud$N_UNIQUE_DATES > x_cap_ud, na.rm = TRUE)

p_ud1 <- ggplot(hist_data_ud, aes(x = N_UD_CAPPED, fill = PAYER_CATEGORY_PRIMARY)) +
  geom_histogram(binwidth = 15, color = "white", linewidth = 0.2) +
  geom_text(data = overflow_counts_ud %>% filter(n_overflow > 0),
            aes(x = x_cap_ud + 10, y = Inf, label = paste0(">", x_cap_ud, ": ", n_overflow)),
            vjust = 1.5, hjust = 0, size = 2.8, inherit.aes = FALSE) +
  facet_wrap(~ PAYER_CATEGORY_PRIMARY, scales = "free_y") +
  coord_cartesian(xlim = c(0, x_cap_ud + 30)) +
  scale_x_continuous(breaks = seq(0, x_cap_ud, by = 50),
                     labels = c(seq(0, x_cap_ud - 50, by = 50), paste0(x_cap_ud, "+"))) +
  labs(
    title = "Unique Encounter Dates per Person by Payer Category",
    subtitle = glue("{n_beyond_ud} patients with >{x_cap_ud} unique dates shown in overflow bin"),
    x = "Number of Unique Encounter Dates",
    y = "Number of Patients"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none",
        strip.text = element_text(face = "bold")) +
  scale_fill_viridis_d()

ggsave("output/figures/unique_dates_per_person_by_payor.png", p_ud1,
       width = 12, height = 8, dpi = 300)
message("  Saved: output/figures/unique_dates_per_person_by_payor.png")

# 6d. Post-treatment unique dates by DX year
enc_ud_by_year <- cohort_ud %>%
  filter(!is.na(DX_YEAR), !is.na(N_UNIQUE_DATES_POST_TX)) %>%
  group_by(DX_YEAR) %>%
  summarise(
    n_patients = n(),
    mean_post_tx_ud = mean(N_UNIQUE_DATES_POST_TX, na.rm = TRUE),
    median_post_tx_ud = median(N_UNIQUE_DATES_POST_TX, na.rm = TRUE),
    mean_total_ud = mean(N_UNIQUE_DATES, na.rm = TRUE),
    median_total_ud = median(N_UNIQUE_DATES, na.rm = TRUE),
    .groups = "drop"
  )

# Snapshot: figure backing data (per SNAP-03)
save_output_data(enc_ud_by_year, "post_tx_unique_dates_by_dx_year_data")

p_ud2 <- ggplot(enc_ud_by_year, aes(x = DX_YEAR, y = mean_post_tx_ud)) +
  geom_col(fill = "#2c7fb8", alpha = 0.8) +
  geom_text(aes(label = round(mean_post_tx_ud, 1)), vjust = -0.3, size = 3) +
  labs(
    title = "Mean Post-Treatment Unique Dates per Person by Year of Diagnosis",
    subtitle = if (n_missing_dx_year > 0) glue("{n_missing_dx_year} patients with missing diagnosis date excluded") else NULL,
    x = "Year of Diagnosis",
    y = "Mean Unique Post-Treatment Dates"
  ) +
  theme_minimal(base_size = 11) +
  scale_x_continuous(breaks = pretty_breaks()) +
  coord_cartesian(clip = "off", ylim = c(0, max(enc_ud_by_year$mean_post_tx_ud, na.rm = TRUE) * 1.15)) +
  theme(plot.margin = margin(t = 10, r = 5, b = 5, l = 5))

ggsave("output/figures/post_tx_unique_dates_by_dx_year.png", p_ud2,
       width = 10, height = 6, dpi = 300)
message("  Saved: output/figures/post_tx_unique_dates_by_dx_year.png")

# 6e. Total unique dates by DX year
# Snapshot: figure backing data (per SNAP-03)
save_output_data(enc_ud_by_year, "total_unique_dates_by_dx_year_data")

p_ud3 <- ggplot(enc_ud_by_year, aes(x = DX_YEAR, y = mean_total_ud)) +
  geom_col(fill = "#41ae76", alpha = 0.8) +
  geom_text(aes(label = round(mean_total_ud, 1)), vjust = -0.3, size = 3) +
  labs(
    title = "Mean Total Unique Dates per Person by Year of Diagnosis",
    subtitle = if (n_missing_dx_year > 0) glue("{n_missing_dx_year} patients with missing diagnosis date excluded") else NULL,
    x = "Year of Diagnosis",
    y = "Mean Unique Encounter Dates"
  ) +
  theme_minimal(base_size = 11) +
  scale_x_continuous(breaks = pretty_breaks()) +
  coord_cartesian(clip = "off", ylim = c(0, max(enc_ud_by_year$mean_total_ud, na.rm = TRUE) * 1.15)) +
  theme(plot.margin = margin(t = 10, r = 5, b = 5, l = 5))

ggsave("output/figures/total_unique_dates_by_dx_year.png", p_ud3,
       width = 10, height = 6, dpi = 300)
message("  Saved: output/figures/total_unique_dates_by_dx_year.png")

# ==============================================================================
# SECTION 7: STACKED HISTOGRAM -- Pre/Post-Treatment Encounters by Payer (VIZP-03)
# ==============================================================================

message("\n--- Stacked Histogram: Pre/Post-Treatment Encounters by Payer ---")

# 7a. Compute LAST_ANY_TREATMENT_DATE per patient
# Reuse the same logic as 11_generate_pptx.R Section 2c

# Helper to compute last dates from treatment sources
compute_last_tx_dates_from_procedures <- function(treatment_type) {
  sources <- list()

  if (treatment_type == "chemo") {
    # Chemo from PROCEDURES
    if (!is.null(pcornet$PROCEDURES)) {
      sources$px <- pcornet$PROCEDURES %>%
        filter(
          (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
          (PX_TYPE == "10" & PX %in% TREATMENT_CODES$chemo_icd10pcs_prefixes) |
          (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue)
        ) %>%
        filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>%
        summarise(tx_date = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }
    # Chemo from PRESCRIBING
    if (!is.null(pcornet$PRESCRIBING)) {
      sources$rx <- pcornet$PRESCRIBING %>%
        filter(!is.na(RX_ORDER_DATE) | !is.na(RX_START_DATE)) %>%
        mutate(d = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
        filter(!is.na(d)) %>%
        group_by(ID) %>%
        summarise(tx_date = max(d, na.rm = TRUE), .groups = "drop")
    }
    # Chemo from DIAGNOSIS
    if (!is.null(pcornet$DIAGNOSIS)) {
      sources$dx <- pcornet$DIAGNOSIS %>%
        filter(
          (DX_TYPE == "10" & DX %in% TREATMENT_CODES$chemo_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$chemo_dx_icd9)
        ) %>%
        filter(!is.na(DX_DATE)) %>%
        group_by(ID) %>%
        summarise(tx_date = max(DX_DATE, na.rm = TRUE), .groups = "drop")
    }
    # Chemo from ENCOUNTER DRG
    if (!is.null(pcornet$ENCOUNTER)) {
      sources$drg <- pcornet$ENCOUNTER %>%
        filter(DRG %in% TREATMENT_CODES$chemo_drg) %>%
        filter(!is.na(ADMIT_DATE)) %>%
        group_by(ID) %>%
        summarise(tx_date = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
    }
    # Chemo from DISPENSING
    if (!is.null(pcornet$DISPENSING) && "RXNORM_CUI" %in% names(pcornet$DISPENSING)) {
      sources$disp <- pcornet$DISPENSING %>%
        filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
        filter(!is.na(DISPENSE_DATE)) %>%
        group_by(ID) %>%
        summarise(tx_date = max(DISPENSE_DATE, na.rm = TRUE), .groups = "drop")
    }
    # Chemo from MED_ADMIN
    if (!is.null(pcornet$MED_ADMIN) && "RXNORM_CUI" %in% names(pcornet$MED_ADMIN)) {
      sources$ma <- pcornet$MED_ADMIN %>%
        filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
        filter(!is.na(MEDADMIN_START_DATE)) %>%
        group_by(ID) %>%
        summarise(tx_date = max(MEDADMIN_START_DATE, na.rm = TRUE), .groups = "drop")
    }
  } else if (treatment_type == "radiation") {
    if (!is.null(pcornet$PROCEDURES)) {
      sources$px <- pcornet$PROCEDURES %>%
        filter(
          (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$radiation_cpt) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$radiation_icd9) |
          (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$radiation_revenue)
        ) %>%
        filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>%
        summarise(tx_date = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$DIAGNOSIS)) {
      sources$dx <- pcornet$DIAGNOSIS %>%
        filter(
          (DX_TYPE == "10" & DX %in% TREATMENT_CODES$radiation_dx_icd10) |
          (DX_TYPE == "09" & DX %in% TREATMENT_CODES$radiation_dx_icd9)
        ) %>%
        filter(!is.na(DX_DATE)) %>%
        group_by(ID) %>%
        summarise(tx_date = max(DX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$ENCOUNTER)) {
      sources$drg <- pcornet$ENCOUNTER %>%
        filter(DRG %in% TREATMENT_CODES$radiation_drg) %>%
        filter(!is.na(ADMIT_DATE)) %>%
        group_by(ID) %>%
        summarise(tx_date = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
    }
  } else if (treatment_type == "sct") {
    if (!is.null(pcornet$PROCEDURES)) {
      sources$px <- pcornet$PROCEDURES %>%
        filter(
          (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$sct_cpt) |
          (PX_TYPE == "09" & PX %in% TREATMENT_CODES$sct_icd9) |
          (PX_TYPE == "10" & PX %in% TREATMENT_CODES$sct_icd10pcs) |
          (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$sct_revenue)
        ) %>%
        filter(!is.na(PX_DATE)) %>%
        group_by(ID) %>%
        summarise(tx_date = max(PX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$DIAGNOSIS)) {
      sources$dx <- pcornet$DIAGNOSIS %>%
        filter(DX_TYPE == "10" & DX %in% TREATMENT_CODES$sct_dx_icd10) %>%
        filter(!is.na(DX_DATE)) %>%
        group_by(ID) %>%
        summarise(tx_date = max(DX_DATE, na.rm = TRUE), .groups = "drop")
    }
    if (!is.null(pcornet$ENCOUNTER)) {
      sources$drg <- pcornet$ENCOUNTER %>%
        filter(DRG %in% TREATMENT_CODES$sct_drg) %>%
        filter(!is.na(ADMIT_DATE)) %>%
        group_by(ID) %>%
        summarise(tx_date = max(ADMIT_DATE, na.rm = TRUE), .groups = "drop")
    }
  }

  non_null <- compact(sources)
  if (length(non_null) == 0) {
    return(tibble(ID = character(0), tx_date = as.Date(character(0))))
  }

  bind_rows(non_null) %>%
    group_by(ID) %>%
    summarise(tx_date = max(tx_date, na.rm = TRUE), .groups = "drop") %>%
    filter(!is.infinite(tx_date))
}

# Compute last treatment dates for each type
last_chemo_for_stacked <- compute_last_tx_dates_from_procedures("chemo")
last_rad_for_stacked <- compute_last_tx_dates_from_procedures("radiation")
last_sct_for_stacked <- compute_last_tx_dates_from_procedures("sct")

# Combine to get LAST_ANY_TREATMENT_DATE
tx_dates_for_stacked <- bind_rows(
  last_chemo_for_stacked,
  last_rad_for_stacked,
  last_sct_for_stacked
) %>%
  # Filter 1900 sentinel dates (per VIZP-01)
  filter(year(tx_date) != 1900L) %>%
  group_by(ID) %>%
  summarise(LAST_ANY_TX_DATE = max(tx_date, na.rm = TRUE), .groups = "drop") %>%
  filter(!is.infinite(LAST_ANY_TX_DATE))

n_treated_for_stacked <- nrow(tx_dates_for_stacked)
message(glue("  {n_treated_for_stacked} patients with treatment dates for stacked histogram"))

# 7b. Split encounters into pre/post treatment (per D-07)
stacked_enc <- encounters %>%
  inner_join(tx_dates_for_stacked, by = "ID") %>%  # Only treated patients (per D-10)
  filter(!is.na(ADMIT_DATE)) %>%
  mutate(
    ENCOUNTER_PERIOD = if_else(
      ADMIT_DATE > LAST_ANY_TX_DATE,
      "Post-treatment",
      "Pre-treatment"
    )
  )

# 7c. Count per patient per period (per D-09: use raw N_ENCOUNTERS count basis)
stacked_counts <- stacked_enc %>%
  count(ID, ENCOUNTER_PERIOD, name = "n_enc") %>%
  complete(ID, ENCOUNTER_PERIOD, fill = list(n_enc = 0))  # Ensure all patients have both periods

# 7d. Compute total encounters per patient for histogram x-axis
patient_totals_stacked <- stacked_counts %>%
  group_by(ID) %>%
  summarise(N_TOTAL = sum(n_enc), .groups = "drop")

# 7e. Join payer category (per D-08: faceted by 6+Missing)
stacked_plot_data <- stacked_counts %>%
  left_join(
    hl_cohort %>% select(ID, PAYER_CATEGORY_PRIMARY),
    by = "ID"
  ) %>%
  left_join(patient_totals_stacked, by = "ID") %>%
  mutate(
    PAYER_CATEGORY_PRIMARY = case_when(
      PAYER_CATEGORY_PRIMARY %in% c("Other", "Unavailable", "Unknown") ~ "Missing",
      is.na(PAYER_CATEGORY_PRIMARY) ~ "Missing",
      TRUE ~ PAYER_CATEGORY_PRIMARY
    ),
    PAYER_CATEGORY_PRIMARY = factor(PAYER_CATEGORY_PRIMARY,
      levels = c("Medicare", "Medicaid", "Dual eligible", "Private",
                 "Other government", "No payment / Self-pay", "Missing")),
    # Post-treatment on bottom (first level = bottom in stacked histogram) per D-07
    ENCOUNTER_PERIOD = factor(ENCOUNTER_PERIOD,
      levels = c("Post-treatment", "Pre-treatment"))
  )

# 7f. Overflow bin at >500 (matching Section 1 pattern)
x_cap_stk <- 500

overflow_stk <- patient_totals_stacked %>%
  left_join(
    stacked_plot_data %>% distinct(ID, PAYER_CATEGORY_PRIMARY),
    by = "ID"
  ) %>%
  filter(N_TOTAL > x_cap_stk) %>%
  count(PAYER_CATEGORY_PRIMARY, name = "n_overflow", .drop = FALSE)

# Cap total encounters for binning
patient_totals_stacked <- patient_totals_stacked %>%
  mutate(N_TOTAL_CAPPED = if_else(N_TOTAL > x_cap_stk, as.numeric(x_cap_stk + 1), as.numeric(N_TOTAL)))

# Join capped totals back to plot data
stacked_plot_data <- stacked_plot_data %>%
  select(-N_TOTAL) %>%
  left_join(patient_totals_stacked %>% select(ID, N_TOTAL_CAPPED), by = "ID")

n_beyond_stk <- sum(patient_totals_stacked$N_TOTAL > x_cap_stk)

# Snapshot: figure backing data (per SNAP-03)
save_output_data(stacked_plot_data, "encounters_stacked_pre_post_data")

# 7g. Create stacked histogram
p_stacked <- ggplot(stacked_plot_data, aes(x = N_TOTAL_CAPPED, weight = n_enc, fill = ENCOUNTER_PERIOD)) +
  geom_histogram(position = "stack", binwidth = 20, color = "white", linewidth = 0.2) +
  geom_text(data = overflow_stk %>% filter(n_overflow > 0),
            aes(x = x_cap_stk + 10, y = Inf, label = paste0(">", x_cap_stk, ": ", n_overflow)),
            vjust = 1.5, hjust = 0, size = 2.8, inherit.aes = FALSE) +
  facet_wrap(~ PAYER_CATEGORY_PRIMARY, scales = "free_y") +
  coord_cartesian(xlim = c(0, x_cap_stk + 40)) +
  scale_x_continuous(breaks = seq(0, x_cap_stk, by = 100),
                     labels = c(seq(0, x_cap_stk - 100, by = 100), paste0(x_cap_stk, "+"))) +
  scale_fill_manual(values = c("Post-treatment" = "#2c7fb8", "Pre-treatment" = "#ff7f0e")) +
  labs(
    title = "Encounters per Person by Payor (Pre/Post-Treatment Split)",
    subtitle = glue("Treated patients only (N = {format(n_treated_for_stacked, big.mark = ',')}) | {n_beyond_stk} with >{x_cap_stk} encounters in overflow bin"),
    x = "Number of Encounters",
    y = "Number of Patients",
    fill = "Period"
  ) +
  theme_minimal(base_size = 11) +
  theme(strip.text = element_text(face = "bold"),
        legend.position = "bottom")

ggsave("output/figures/encounters_stacked_pre_post_by_payor.png", p_stacked,
       width = 12, height = 8, dpi = 300)
message("  Saved: output/figures/encounters_stacked_pre_post_by_payor.png")

message("\n", strrep("=", 60))
message("Encounter analysis complete")
message(strrep("=", 60))
