test_that("fmt_sup suppresses 1-10, keeps 0 and 11+, NA-safe", {
  expect_equal(fmt_sup(c(0, 1, 10, 11, 1234, NA)), c("0", "<11", "<11", "11", "1,234", NA))
})

test_that("episode_crosstab sums to row count and ABVD_PLUS no-bleo counts as avd", {
  old <- tibble::tibble(abvd_episode = c(TRUE, FALSE, FALSE, TRUE))
  new <- tibble::tibble(
    patient_id = c("a", "b", "c", "d"),
    abvd_class = c("ABVD", "ABVD_PLUS", "OTHER", "ABVD"),
    abvd_episode = c(TRUE, FALSE, FALSE, TRUE),
    avd_episode  = c(FALSE, TRUE, FALSE, FALSE)
  )
  ct <- episode_crosstab(old, new)
  expect_equal(sum(ct$n_episodes), nrow(new))
  row <- ct[ct$abvd_class == "ABVD_PLUS", ]
  expect_true(row$new_avd)
  expect_false(row$new_abvd)
  tr <- episode_transitions(old, new)
  expect_equal(nrow(tr), 0L)
  new$abvd_episode[3] <- TRUE
  tr <- episode_transitions(old, new)
  expect_equal(tr$transition, "FALSE->TRUE")
  expect_error(episode_crosstab(old[1:2, ], new))
})

test_that("patient_flag_compare and ever_cross count patients", {
  old <- tibble::tibble(abvd_episode = c(FALSE, FALSE, TRUE))
  new <- tibble::tibble(patient_id = c("a", "a", "b"),
                        abvd_class = "X",
                        abvd_episode = c(TRUE, FALSE, TRUE),
                        avd_episode = c(FALSE, TRUE, FALSE))
  pc <- patient_flag_compare(old, new)
  expect_equal(sum(pc$n_patients), 2L)
  expect_equal(sum(ever_cross(c(TRUE, TRUE, FALSE), c(FALSE, TRUE, FALSE))$n_patients), 3L)
})

test_that("beacopp_extra_components detects non-ABVD components only", {
  x <- c("Doxorubicin, Bleomycin, Etoposide, Vinblastine",
         "Doxorubicin, Bleomycin, Vinblastine, Dacarbazine",
         "Doxorubicin, Bleomycin, Vinblastine, Dacarbazine, Leuprolide")
  expect_equal(beacopp_extra_components(x), c(TRUE, FALSE, FALSE))
})

test_that("drug_set_patterns has no patient_id and drops supportive agents", {
  p <- drug_set_patterns(c("Vinblastine, Doxorubicin, Leuprolide", "Doxorubicin; Vinblastine", NA))
  expect_false("patient_id" %in% names(p))
  expect_true("Doxorubicin + Vinblastine" %in% p$pattern)
  expect_equal(p$n_episodes[p$pattern == "Doxorubicin + Vinblastine"], 2L)
})

test_that("suppress_impact_table hides totals when a component is small", {
  df <- data.frame(a = c(5, 20, 0), b = c(30, 40, 0), total = c(35, 60, 0))
  out <- suppress_impact_table(df, c("a", "b", "total"), total_col = "total")
  expect_equal(out$a, c("<11", "20", "0"))
  expect_equal(out$total, c("<11", "60", "0"))
})
