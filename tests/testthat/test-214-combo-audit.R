# Phase 214: combination audit helpers. Synthetic fixtures always run; the three-file
# tests read docs/combo_audit/*.csv and skip when those files are absent.
# R/utils helpers are sourced by helper-utils.R. canonicalize_drug_name lives in
# R/00_config.R, so only its two definitions are evaluated here (config itself is not sourced).
canon_env <- new.env()
local({
  src <- parse(here::here("R", "00_config.R"))
  keep <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) &&
                   as.character(e[[2]])[1] %in% c("DRUG_NAME_ALIASES", "canonicalize_drug_name"), src)
  for (e in keep) eval(e, canon_env)
  assign("str_trim", stringr::str_trim, canon_env)
  environment(canon_env$canonicalize_drug_name) <- canon_env
})
canon <- canon_env$canonicalize_drug_name

test_that("normalise_combo collapses aliases, order, whitespace and duplicates", {
  expect_equal(normalise_combo("Adriamycin;Bleomycin;Dacarbazine;Vinblastine", canon),
               "Bleomycin;Dacarbazine;Doxorubicin;Vinblastine")
  expect_equal(normalise_combo("Doxorubicin Hydrochloride;Adriamycin", canon), "Doxorubicin")
  expect_equal(normalise_combo(" Vinblastine ;Bleomycin;; Bleomycin", canon), "Bleomycin;Vinblastine")
  expect_equal(normalise_combo(c("B;A", "A;B"), canon), c("A;B", "A;B"))
})

test_that("blank and NA drug_names map to (blank)", {
  expect_equal(normalise_combo(c("", NA, "  ", ";"), canon), rep("(blank)", 4))
})

test_that("classify_combos assigns each class", {
  old <- c("A;B", "C;D", "Adriamycin;E", "F")
  new <- c("A;B", "D;C", "Doxorubicin;E", "G")
  cl <- classify_combos(old, new, canon)
  st <- setNames(cl$status, cl$combination_normalized)
  expect_equal(st[["A;B"]], "unchanged")
  expect_equal(st[["C;D"]], "label_only")
  expect_equal(st[["Doxorubicin;E"]], "label_only")
  expect_equal(st[["F"]], "dropped")
  expect_equal(st[["G"]], "new")
})

ep <- function(pid, s, e, key) data.frame(patient_id = pid, episode_start = as.Date(s),
                                          episode_stop = as.Date(e), drug_key = key,
                                          stringsAsFactors = FALSE)

test_that("match_episodes labels pair types", {
  old <- rbind(ep("p1", "2020-01-01", "2020-03-01", "A"), ep("p2", "2020-01-01", "2020-06-01", "A"),
               ep("p3", "2020-01-01", "2020-02-01", "A"), ep("p3", "2020-03-01", "2020-04-01", "A"))
  new <- rbind(ep("p1", "2020-02-01", "2020-04-01", "A;B"),
               ep("p2", "2020-01-01", "2020-02-01", "A"), ep("p2", "2020-03-01", "2020-06-01", "A"),
               ep("p3", "2020-01-15", "2020-03-15", "A"))
  m <- match_episodes(old, new)
  expect_equal(m$pair_type[m$old_row == 1L], "1:1")
  expect_equal(unique(m$pair_type[m$old_row == 2L]), "1:n")
  expect_equal(unique(m$pair_type[m$old_row %in% 3:4]), "n:1")
  expect_equal(nrow(match_episodes(old[0, ], new)), 0L)
})

test_that("attribute_cause covers causes a-g with precedence", {
  expect_equal(attribute_cause("A", "A", TRUE, FALSE, "1:1"), "e")
  expect_equal(attribute_cause(NA, "A", FALSE, TRUE), "d")
  expect_equal(attribute_cause("A", "A;B", TRUE, TRUE, "1:n"), "f")
  expect_equal(attribute_cause("A;B", "A;B", TRUE, TRUE, "1:1"), "a")
  expect_equal(attribute_cause("A", "A;B", TRUE, TRUE, "1:1"), "b")
  expect_equal(attribute_cause("A;B", "A", TRUE, TRUE, "1:1"), "c")
  expect_equal(attribute_cause("A;B", "A;C", TRUE, TRUE, "1:1"), "g")
  expect_equal(attribute_cause(NA, NA, TRUE, TRUE), "g")
  expect_equal(combo_added_drugs("A", "A;B;C"), "B;C")
})

test_that("rollup_cause: most frequent wins, ties go alphabetical", {
  df <- data.frame(combination_normalized = c("X", "X", "X", "Y", "Y"),
                   cause = c("b", "b", "a", "c", "a"), stringsAsFactors = FALSE)
  r <- rollup_cause(df)
  expect_equal(r$primary_cause[r$combination_normalized == "X"], "b")
  expect_equal(r$primary_cause[r$combination_normalized == "Y"], "a")
  expect_equal(r$n_b[r$combination_normalized == "X"], 2L)
})

test_that("suppress_combo_counts masks 1-10 and keeps 0 and 11", {
  d <- data.frame(n_episodes = c(0L, 1L, 10L, 11L, 50L))
  expect_equal(suppress_combo_counts(d, "n_episodes")$n_episodes, c("0", "<11", "<11", "11", "50"))
})

# ---- three-file tests (docs/combo_audit) --------------------------------------
f_old <- here::here("docs", "combo_audit", "chemo_combo_check.csv")
f_new <- here::here("docs", "combo_audit", "unique_chemo_drugs.csv")
f_chg <- here::here("docs", "combo_audit", "combo_change_list_2026-11-19.csv")

test_that("reference files classify 314 / 161 / 29 / 21 and match the change list", {
  skip_if_not(all(file.exists(f_old, f_new, f_chg)), "reference CSVs absent: verify on HiPerGator")
  rd <- function(f) {
    x <- readLines(f, warn = FALSE, encoding = "UTF-8")
    x <- sub("^﻿", "", x)[-1]
    x <- gsub('^"|"$', "", x)
    x[nzchar(trimws(x))]  # blank row is handled separately (Q-214-02)
  }
  cl <- classify_combos(rd(f_old), rd(f_new), canon)
  tab <- table(cl$status)
  expect_equal(as.integer(tab[c("unchanged", "label_only", "new", "dropped")]), c(314L, 161L, 29L, 21L))
  chg <- read.csv(f_chg, stringsAsFactors = FALSE)
  expect_named(chg, c("status", "combination_normalized", "old_file_string", "new_file_string",
                      "related_combination", "hypothesized_cause_UNCONFIRMED"))
  m <- merge(cl[, c("combination_normalized", "status")], chg[, c("combination_normalized", "status")],
             by = "combination_normalized")
  expect_equal(nrow(m), nrow(cl))
  expect_true(all(m$status.x == m$status.y))
})
