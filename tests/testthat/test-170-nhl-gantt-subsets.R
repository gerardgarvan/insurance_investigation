# tests/testthat/test-170-nhl-gantt-subsets.R
# =============================================================================
# Unit tests for R/170_nhl_gantt_subsets.R pure helpers.
# Covers:
#   (a) norm_key
#   (b) classify_x, flag_unexpected_x
#   (c) classify_groups
#   (d) join_ej_chemo_only
#   (e) normalize_drug_names
# =============================================================================

# Load helpers from R/170 (stops before any I/O at the probe gate).
# Requires here package to be available.
skip_if_not_installed("here")
tryCatch(
  sys.source(here::here("R/170_nhl_gantt_subsets.R"), envir = globalenv()),
  error = function(e) {
    if (!grepl("skipping", conditionMessage(e), ignore.case = TRUE)) stop(e)
  }
)

# Confirm helpers are defined before proceeding
skip_if(!exists("norm_key"),             "norm_key not defined — R/170 did not load")
skip_if(!exists("classify_x"),           "classify_x not defined — R/170 did not load")
skip_if(!exists("flag_unexpected_x"),    "flag_unexpected_x not defined — R/170 did not load")
skip_if(!exists("classify_groups"),      "classify_groups not defined — R/170 did not load")
skip_if(!exists("join_ej_chemo_only"),   "join_ej_chemo_only not defined — R/170 did not load")
skip_if(!exists("normalize_drug_names"), "normalize_drug_names not defined — R/170 did not load")

# =============================================================================
# (a) norm_key
# =============================================================================
test_that("norm_key: integer and string forms normalise to same value", {
  expect_equal(norm_key(1),     "1")
  expect_equal(norm_key("1"),   "1")
  expect_equal(norm_key("1.0"), "1")
  expect_equal(norm_key(" 1 "), "1")
})

test_that("norm_key: empty string becomes NA", {
  expect_true(is.na(norm_key("")))
})

test_that("norm_key: NA stays NA", {
  expect_true(is.na(norm_key(NA)))
})

# =============================================================================
# (b) classify_x and flag_unexpected_x
# =============================================================================
test_that("classify_x: recognises x in various forms", {
  expect_true(classify_x("x"))
  expect_true(classify_x("X"))
  expect_true(classify_x(" x "))
})

test_that("classify_x: rejects blank, NA, and non-x values", {
  expect_false(classify_x(""))
  expect_false(classify_x(NA_character_))
  expect_false(classify_x("x?"))
  expect_false(classify_x("yes"))
})

test_that("flag_unexpected_x: TRUE only for non-blank, non-x, non-0 values", {
  expect_true(flag_unexpected_x("x?"))
  expect_true(flag_unexpected_x("yes"))
  expect_false(flag_unexpected_x("x"))
  expect_false(flag_unexpected_x("X"))
  expect_false(flag_unexpected_x("0"))   # 0 = false/no in this sheet
  expect_false(flag_unexpected_x(""))
  expect_false(flag_unexpected_x(NA_character_))
})

# =============================================================================
# (c) classify_groups
# =============================================================================
test_that("classify_groups: all-NHL patient is strict and loose", {
  sheet <- data.frame(
    patient_id = c("A", "A"),
    hl    = c(FALSE, FALSE),
    nhl   = c(TRUE,  TRUE),
    hlnhl = c(FALSE, FALSE),
    stringsAsFactors = FALSE
  )
  g <- classify_groups(sheet)
  row <- g[g$patient_id == "A", ]
  expect_true(row$group1_strict)
  expect_true(row$group1_loose)
  expect_false(row$group2)
})

test_that("classify_groups: NHL + one HL episode -> loose only, not strict", {
  sheet <- data.frame(
    patient_id = c("B", "B"),
    hl    = c(FALSE, TRUE),
    nhl   = c(TRUE,  FALSE),
    hlnhl = c(FALSE, FALSE),
    stringsAsFactors = FALSE
  )
  g <- classify_groups(sheet)
  row <- g[g$patient_id == "B", ]
  expect_false(row$group1_strict)
  expect_true(row$group1_loose)
  expect_false(row$group2)
})

test_that("classify_groups: HL+NHL episode -> group2, not strict", {
  sheet <- data.frame(
    patient_id = c("C"),
    hl    = c(FALSE),
    nhl   = c(FALSE),
    hlnhl = c(TRUE),
    stringsAsFactors = FALSE
  )
  g <- classify_groups(sheet)
  row <- g[g$patient_id == "C", ]
  expect_false(row$group1_strict)
  expect_true(row$group2)
})

# =============================================================================
# (d) join_ej_chemo_only
# =============================================================================
test_that("join_ej_chemo_only: E-J only on chemo row; row count and order preserved", {
  gantt_rows <- data.frame(
    patient_id     = c("P1", "P1", "P1"),
    episode_number = c("1",  "1",  "2"),
    treatment_type = c("Chemotherapy", "Radiation", "Death"),
    drug_names     = c("DrugA", NA, NA),
    stringsAsFactors = FALSE
  )
  ej <- data.frame(
    patient_id     = "P1",
    episode_number = "1",
    `Definitely HL`  = NA_character_,
    `Definitely NHL` = "x",
    Initial          = "x",
    Relapse          = NA_character_,
    Notes            = NA_character_,
    `HL and NHL`     = NA_character_,
    stringsAsFactors = FALSE,
    check.names      = FALSE
  )

  result <- join_ej_chemo_only(gantt_rows, ej, "Chemotherapy")

  # Row count unchanged
  expect_equal(nrow(result), 3L)

  # Order preserved: first row is chemo (P1 ep 1)
  expect_equal(result$treatment_type[1], "Chemotherapy")
  expect_equal(result$treatment_type[2], "Radiation")
  expect_equal(result$treatment_type[3], "Death")

  # E-J populated on chemo row
  expect_equal(result$`Definitely NHL`[1], "x")

  # E-J empty (NA) on non-chemo rows
  expect_true(is.na(result$`Definitely NHL`[2]))
  expect_true(is.na(result$`Definitely NHL`[3]))
  expect_true(is.na(result$`HL and NHL`[2]))
})

# =============================================================================
# (e) normalize_drug_names
# =============================================================================
test_that("normalize_drug_names: order, case, and separator variants match", {
  expect_equal(
    normalize_drug_names("Doxorubicin; Bleomycin"),
    normalize_drug_names("bleomycin,doxorubicin")
  )
})

test_that("normalize_drug_names: NA input stays NA", {
  expect_true(is.na(normalize_drug_names(NA_character_)))
})

test_that("normalize_drug_names: vectorised over multiple values", {
  result <- normalize_drug_names(c("A; B", "B,A", NA))
  expect_equal(result[1], result[2])
  expect_true(is.na(result[3]))
})
