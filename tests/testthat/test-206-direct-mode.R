root <- testthat::test_path("..", "..")
load_206 <- function() {
  e <- new.env()
  for (f in c("utils_abvd_flags.R", "utils_regimen.R")) {
    p <- file.path(root, "R", "utils", f); skip_if_not(file.exists(p))
    try(sys.source(p, envir = e), silent = TRUE)
  }
  skip_if_not(exists("classify_abvd_set", envir = e) && exists("split_drug_names", envir = e))
  sys.source(file.path(root, "R", "utils", "utils_206_direct.R"), envir = e)
  e
}
mk <- function(drugs, cls) data.frame(
  patient_id = c("a", "a", "b", "b", "c"),
  treatment_type = c("HL Diagnosis", "Chemotherapy", "HL Diagnosis", "Chemotherapy", "HL Diagnosis"),
  drug_names = c(NA, drugs[1], NA, drugs[2], NA),
  abvd_class = c(NA, cls[1], NA, cls[2], NA), stringsAsFactors = FALSE)

test_that("supportive-only plus row is flagged; clean rows pass", {
  e <- load_206()
  core <- "Doxorubicin; Bleomycin; Vinblastine; Dacarbazine"
  d <- mk(c(paste0(core, "; Leuprolide"), core), c("ABVD_PLUS", "ABVD"))
  expect_equal(e$direct_supportive_plus_rows(d$abvd_class, d$drug_names, d$treatment_type), 2L)
  d2 <- mk(c(paste0(core, "; Leuprolide"), core), c("ABVD", "ABVD"))
  expect_length(e$direct_supportive_plus_rows(d2$abvd_class, d2$drug_names, d2$treatment_type), 0L)
  d3 <- mk(c(paste0(core, "; Cisplatin"), core), c("ABVD_PLUS", "ABVD"))
  expect_length(e$direct_supportive_plus_rows(d3$abvd_class, d3$drug_names, d3$treatment_type), 0L)
})

test_that("direct_mode_checks passes a clean file and fails a supportive-only plus", {
  e <- load_206()
  core <- "Doxorubicin; Bleomycin; Vinblastine; Dacarbazine"
  base <- data.frame(
    patient_id = c("a", "a", "b", "b", "c"),
    treatment_type = c("HL Diagnosis", "Chemotherapy", "HL Diagnosis", "Chemotherapy", "HL Diagnosis"),
    drug_names = c(NA, core, NA, "Doxorubicin; Vinblastine; Dacarbazine", NA),
    triggering_codes = NA_character_,
    abvd_class = c(NA, "ABVD", NA, "AVD", NA),
    abvd_episode = c("FALSE", "TRUE", "FALSE", "FALSE", "FALSE"),
    avd_episode  = c("FALSE", "FALSE", "FALSE", "TRUE", "FALSE"),
    ever_abvd = c("TRUE", "TRUE", "FALSE", "FALSE", "FALSE"),
    ever_avd  = c("FALSE", "FALSE", "TRUE", "TRUE", "FALSE"),
    stringsAsFactors = FALSE)
  ok <- e$direct_mode_checks(base, names(base), expected_hl = 3L)
  expect_true(all(unlist(ok)))
  bad <- base
  bad$drug_names[2] <- paste0(core, "; Leuprolide"); bad$abvd_class[2] <- "ABVD_PLUS"
  r <- e$direct_mode_checks(bad, names(bad), expected_hl = 3L)
  expect_false(r$no_supportive_only_plus)
  expect_false(e$direct_mode_checks(base, names(base), expected_hl = 4L)$hl_diagnosis_rows)
})
