# Phase 212: cohort rule helpers. Synthetic IDs only.
d <- function(x) as.Date(x)

dx <- dplyr::tibble(
  ID = c("same_enc", "same_enc",
         "same_date", "same_date",
         "close_pass", "close_pass",
         "na_two", "na_two",
         "na_one_real", "na_one_real"),
  ENCOUNTERID = c("e1", "e1",
                  "e2", "e3",
                  "e4", "e5",
                  NA, NA,
                  "e6", NA),
  DX_DATE = d(c("2020-01-01", "2020-02-01",
                "2020-03-01", "2020-03-01",
                "2020-04-01", "2020-04-03",
                "2020-05-01", "2020-05-09",
                "2020-06-01", "2020-06-10")),
  ADMIT_DATE = d(NA)
)

test_that("rule A: same encounter fails; same date fails; 2-day gap passes (7-day gone)", {
  ids <- hl_confirmed_two_encounters(dx)$ID
  expect_false("same_enc" %in% ids)
  expect_false("same_date" %in% ids)
  expect_true("close_pass" %in% ids)
})

test_that("missing ENCOUNTERID rows count as own encounter keyed by date", {
  res <- hl_confirmed_two_encounters(dx)
  expect_true(all(c("na_two", "na_one_real") %in% res$ID))
  fb <- attr(res, "fallback_rows")
  expect_equal(sum(fb$n_rows), 3)
  expect_equal(nrow(fb), 2)
  expect_setequal(attr(res, "fallback_only_ids"), c("na_two", "na_one_real"))
})

test_that("two NA-encounter rows on the same date are one encounter", {
  x <- dplyr::tibble(ID = c("p", "p"), ENCOUNTERID = c(NA, NA),
                     DX_DATE = d(c("2020-01-01", "2020-01-01")))
  expect_equal(nrow(hl_confirmed_two_encounters(x)), 0)
})

test_that("DISTINCT_ENC_REQUIRE_DIFF_DATES = FALSE: distinct ENCOUNTERIDs suffice", {
  ids_t <- hl_confirmed_two_encounters(dx, require_diff_dates = TRUE)$ID
  ids_f <- hl_confirmed_two_encounters(dx, require_diff_dates = FALSE)$ID
  expect_false("same_date" %in% ids_t)
  expect_true("same_date" %in% ids_f)
  expect_false("same_enc" %in% ids_f)
})

test_that("fallback date column used when DX_DATE is NA; rows with no key dropped", {
  x <- dplyr::tibble(ID = c("p", "p", "p"), ENCOUNTERID = c(NA, NA, NA),
                     DX_DATE = d(c(NA, NA, NA)),
                     ADMIT_DATE = d(c("2020-01-01", "2020-02-01", NA)))
  res <- hl_confirmed_two_encounters(x, fallback_date_col = "ADMIT_DATE")
  expect_equal(res$ID, "p")
  expect_equal(attr(res, "n_rows_no_key"), 1)
})

test_that("v315 sets: TR-HL gain, TR-NHL loss, both kept, absent-from-DEMOGRAPHIC excluded, old loss", {
  demog <- c("old_keep", "old_lose", "dx2_new", "trhl_only", "nhl_dx2", "both", "old_trhl")
  s <- apply_cohort_rule_v315(
    ids_dx2   = c("old_keep", "dx2_new", "nhl_dx2", "both"),
    ids_tr_hl = c("trhl_only", "both", "trhl_absent", "old_trhl"),
    ids_tr_nhl = c("nhl_dx2", "both"),
    ids_old   = c("old_keep", "old_lose", "old_trhl"),
    ids_demog = demog
  )
  expect_setequal(s$lost_2enc, "old_lose")
  expect_setequal(s$gained_drop7, c("dx2_new", "nhl_dx2", "both"))
  expect_setequal(s$gained_trhl, "trhl_only")
  expect_setequal(s$lost_trnhl, "nhl_dx2")
  expect_false("trhl_absent" %in% s$new)
  expect_true("both" %in% s$new)
  expect_setequal(s$new, c("old_keep", "old_trhl", "dx2_new", "both", "trhl_only"))
  expect_equal(length(s$old) - length(s$lost_2enc) + length(s$gained_drop7) +
                 length(s$gained_trhl) - length(s$lost_trnhl), length(s$new))
})

test_that("waterfall by site reconciles and suppresses 1-10", {
  ids <- paste0("p", 1:30)
  s <- apply_cohort_rule_v315(ids_dx2 = ids[1:25], ids_tr_hl = ids[26:28],
                              ids_tr_nhl = character(0), ids_old = ids[1:20],
                              ids_demog = ids)
  sm <- dplyr::tibble(ID = ids, site = rep(c("UFH", "ORL"), length.out = 30))
  w <- cohort_waterfall_by_site(s, sm)
  all_n <- function(st) w$n[w$step == st & w$site == "ALL"]
  expect_equal(all_n("old") - all_n("lost_2enc") + all_n("gained_drop7") +
                 all_n("gained_trhl") - all_n("lost_trnhl"), all_n("new"))
  expect_equal(w$n_display[w$step == "gained_trhl" & w$site == "ALL"], "<11")
  expect_equal(w$n_display[w$step == "lost_2enc" & w$site == "ALL"], "0")
  expect_equal(w$n_display[w$step == "new" & w$site == "ALL"], "28")
})

test_that("fallback summary by site suppresses small cells", {
  fb <- dplyr::tibble(ID = c("a", "b", "c"), n_rows = c(2L, 1L, 3L))
  sm <- dplyr::tibble(ID = c("a", "b", "c"), site = c("UFH", "UFH", "ORL"))
  r <- fallback_summary_by_site(fb, sm)
  expect_equal(r$rows_display[r$site == "ALL"], "<11")
  expect_equal(r$patients_display[r$site == "UFH"], "<11")
})
