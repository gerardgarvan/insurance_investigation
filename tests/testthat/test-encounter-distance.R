# ==============================================================================
# test-encounter-distance.R -- Integration test for encounter distance outputs
# Phase 154
# ==============================================================================
# Skipped locally; passes on HiPerGator after a full R/122 run.
# Run with: testthat::test_file("tests/testthat/test-encounter-distance.R")

library(testthat)
library(dplyr)

source("R/00_config.R")

test_that("zipcodeR distance agrees with haversine cross-check within 1 mile (500-pair sample)", {
  rds_files <- list.files(file.path(CONFIG$output_dir), pattern = "^encounter_distance_\\d{8}\\.rds$",
                          full.names = TRUE)
  skip_if(length(rds_files) == 0, "encounter_distance rds not present (run on HiPerGator)")
  d <- readRDS(sort(rds_files, decreasing = TRUE)[1]) |>
    dplyr::filter(distance_status == "computed", !is.na(distance_km_haversine))
  skip_if(nrow(d) == 0, "no computed rows with haversine cross-check")
  set.seed(15202)
  s <- d[sample.int(nrow(d), min(500L, nrow(d))), ]
  diff_mi <- abs(s$distance_mi - s$distance_km_haversine / 1.609344)
  expect_lte(stats::median(diff_mi), 1)
  expect_lte(mean(diff_mi > 1), 0.05)   # allow <=5% of pairs to differ by >1 mi (centroid-source differences)
})
