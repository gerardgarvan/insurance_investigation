# ==============================================================================
# test-166-echo.R -- Tests for utils_anthracycline_echo.R (Phase 166 Plan 03)
# ==============================================================================
# Fixtures cover:
#   (a) first-line max dose chosen over later non-first-line dose;
#       last_dose_ever_dt picks the later one
#   (b) echo on the dose day not counted; next-day echo counted (strict-after)
#   (c) follow_end <= dose -> excluded, counted in n_no_time_after_last_dose
#   (d) event_factor levels exactly c("censored","echo","death")
#   (e) ID alignment: different row orders produce correct per-ID results
#   (f) echo_rate_post_dose NA when follow_end == dose
#   (g) echo_cif_km returns NA for a horizon beyond the maximum observed time
# ==============================================================================

# Load functions under test — sourced directly to avoid CONFIG / DuckDB deps
local_utils_path <- here::here("R", "utils", "utils_anthracycline_echo.R")
if (file.exists(local_utils_path)) source(local_utils_path)

library(dplyr)
library(tibble)

# ---------- shared fixture builders -------------------------------------------

make_episodes <- function(rows) {
  # rows: list of named vectors with ID, drug_name, admin_date, first_line, episode_id
  tibble::tibble(
    ID         = sapply(rows, `[[`, "ID"),
    drug_name  = sapply(rows, `[[`, "drug_name"),
    admin_date = as.Date(sapply(rows, `[[`, "admin_date")),
    first_line = as.logical(sapply(rows, `[[`, "first_line")),
    episode_id = sapply(rows, `[[`, "episode_id")
  )
}

make_echo_events <- function(rows) {
  tibble::tibble(
    ID         = sapply(rows, `[[`, "ID"),
    modality   = "Echocardiogram",
    event_date = as.Date(sapply(rows, `[[`, "event_date"))
  )
}

make_followup <- function(rows) {
  tibble::tibble(
    ID             = sapply(rows, `[[`, "ID"),
    hl_anchor_date = as.Date(sapply(rows, `[[`, "hl_anchor_date")),
    follow_end     = as.Date(sapply(rows, `[[`, "follow_end"))
  )
}

make_deaths <- function(rows = list()) {
  if (length(rows) == 0) {
    return(tibble::tibble(
      ID                   = character(0),
      death_date_resolved  = as.Date(character(0))
    ))
  }
  tibble::tibble(
    ID                  = sapply(rows, `[[`, "ID"),
    death_date_resolved = as.Date(sapply(rows, `[[`, "death_date_resolved"))
  )
}

# ==============================================================================
# (a) first-line dose selection: last_dose_firstline_dt uses only first_line==TRUE
#     rows; last_dose_ever_dt uses all rows including the later non-first-line dose
# ==============================================================================
test_that("(a) last_dose_firstline_dt uses first_line rows; last_dose_ever_dt uses all", {
  episodes <- make_episodes(list(
    list(ID = "P1", drug_name = "Doxorubicin", admin_date = "2018-01-01",
         first_line = TRUE,  episode_id = "E1"),
    list(ID = "P1", drug_name = "Doxorubicin", admin_date = "2018-03-01",
         first_line = TRUE,  episode_id = "E1"),
    # Later dose, but NOT first-line
    list(ID = "P1", drug_name = "Doxorubicin", admin_date = "2019-06-01",
         first_line = FALSE, episode_id = "E2")
  ))

  result <- last_anthracycline_dose(episodes, drugs = "Doxorubicin")

  expect_equal(nrow(result), 1L)
  expect_equal(result$ID, "P1")
  # First-line max = 2018-03-01 (the later FIRST-LINE date)
  expect_equal(result$last_dose_firstline_dt, as.Date("2018-03-01"))
  # Ever max = 2019-06-01 (the non-first-line date is later)
  expect_equal(result$last_dose_ever_dt, as.Date("2019-06-01"))
})

# ==============================================================================
# (b) echo on dose day not counted; next-day echo IS counted
# ==============================================================================
test_that("(b) same-day echo not counted (strict after); next-day echo counted", {
  dose_date <- as.Date("2018-06-01")

  episodes <- tibble::tibble(
    ID         = "P2",
    drug_name  = "Doxorubicin",
    admin_date = dose_date,
    first_line = TRUE,
    episode_id = "E1"
  )

  # Two echoes: one on the dose day, one the next day
  echo_events <- tibble::tibble(
    ID         = c("P2", "P2"),
    modality   = "Echocardiogram",
    event_date = c(dose_date, dose_date + 1L)
  )

  followup <- tibble::tibble(
    ID             = "P2",
    hl_anchor_date = as.Date("2017-01-01"),
    follow_end     = as.Date("2022-01-01")
  )

  deaths <- make_deaths()

  doses   <- last_anthracycline_dose(episodes, drugs = "Doxorubicin")
  tte_res <- echo_time_to_event(doses, echo_events, followup, deaths,
                                dose_col = "last_dose_firstline_dt")

  expect_equal(nrow(tte_res$data), 1L)
  # echo event at dose+1 day -> time = 1
  expect_equal(tte_res$data$event_status, "echo")
  expect_equal(as.numeric(tte_res$data$time_days), 1)
})

# ==============================================================================
# (c) follow_end <= dose -> patient excluded, n_no_time_after_last_dose incremented
# ==============================================================================
test_that("(c) follow_end <= dose excludes patient; counted in n_no_time_after_last_dose", {
  dose_date <- as.Date("2018-06-01")

  episodes <- tibble::tibble(
    ID = "P3", drug_name = "Doxorubicin",
    admin_date = dose_date, first_line = TRUE, episode_id = "E1"
  )

  followup <- tibble::tibble(
    ID = "P3", hl_anchor_date = as.Date("2017-01-01"),
    follow_end = dose_date   # exactly equal -> excluded
  )

  echo_events <- tibble::tibble(
    ID = character(0), modality = character(0), event_date = as.Date(character(0))
  )
  deaths <- make_deaths()

  doses   <- last_anthracycline_dose(episodes, drugs = "Doxorubicin")
  tte_res <- echo_time_to_event(doses, echo_events, followup, deaths,
                                dose_col = "last_dose_firstline_dt")

  expect_equal(nrow(tte_res$data), 0L)
  expect_equal(tte_res$n_no_time_after_last_dose, 1L)
})

# ==============================================================================
# (d) event_factor levels exactly c("censored","echo","death")
# ==============================================================================
test_that("(d) event_factor levels are exactly c('censored','echo','death')", {
  episodes <- tibble::tibble(
    ID = "P4", drug_name = "Doxorubicin",
    admin_date = as.Date("2018-01-01"), first_line = TRUE, episode_id = "E1"
  )
  followup <- tibble::tibble(
    ID = "P4", hl_anchor_date = as.Date("2017-01-01"),
    follow_end = as.Date("2025-01-01")
  )
  echo_events <- tibble::tibble(
    ID = character(0), modality = character(0), event_date = as.Date(character(0))
  )
  deaths <- make_deaths()

  doses   <- last_anthracycline_dose(episodes, drugs = "Doxorubicin")
  tte_res <- echo_time_to_event(doses, echo_events, followup, deaths,
                                dose_col = "last_dose_firstline_dt")

  expect_equal(levels(tte_res$data$event_factor),
               c("censored", "echo", "death"))
})

# ==============================================================================
# (e) ID alignment: 3 patients supplied in different row orders produce correct
#     per-ID results
# ==============================================================================
test_that("(e) correct per-ID results despite shuffled row order", {
  # P5: echo after last dose -> event = "echo"
  # P6: death after last dose (no echo) -> event = "death"
  # P7: censored (no echo, no death) -> event = "censored"
  episodes <- tibble::tibble(
    ID         = c("P7", "P5", "P6"),   # shuffled
    drug_name  = "Doxorubicin",
    admin_date = as.Date(c("2018-01-01", "2018-01-01", "2018-01-01")),
    first_line = TRUE,
    episode_id = "E1"
  )

  echo_events <- tibble::tibble(
    ID         = "P5",
    modality   = "Echocardiogram",
    event_date = as.Date("2019-06-01")
  )

  followup <- tibble::tibble(
    ID             = c("P6", "P7", "P5"),  # shuffled
    hl_anchor_date = as.Date("2017-01-01"),
    follow_end     = as.Date("2025-01-01")
  )

  deaths <- make_deaths(list(
    list(ID = "P6", death_date_resolved = "2020-01-01")
  ))

  doses   <- last_anthracycline_dose(episodes, drugs = "Doxorubicin")
  tte_res <- echo_time_to_event(doses, echo_events, followup, deaths,
                                dose_col = "last_dose_firstline_dt")

  df <- tte_res$data |> dplyr::arrange(ID)

  expect_equal(df$ID,           c("P5", "P6", "P7"))
  expect_equal(df$event_status, c("echo", "death", "censored"))
})

# ==============================================================================
# (f) echo_rate_post_dose: NA when follow_end == dose (zero person-time)
# ==============================================================================
test_that("(f) echo_rate_post_dose is NA when follow_end == dose", {
  dose_date <- as.Date("2018-06-01")

  episodes <- tibble::tibble(
    ID = "P8", drug_name = "Doxorubicin",
    admin_date = dose_date, first_line = TRUE, episode_id = "E1"
  )
  followup <- tibble::tibble(
    ID = "P8", hl_anchor_date = as.Date("2017-01-01"),
    follow_end = dose_date
  )
  echo_events <- tibble::tibble(
    ID = character(0), modality = character(0), event_date = as.Date(character(0))
  )

  doses  <- last_anthracycline_dose(episodes, drugs = "Doxorubicin")
  result <- echo_rate_post_dose(doses, echo_events, followup,
                                dose_col = "last_dose_firstline_dt")

  expect_equal(nrow(result), 1L)
  expect_true(is.na(result$rate_per_py))
})

# ==============================================================================
# (g) echo_cif_km: NA for horizon beyond max observed time
# ==============================================================================
test_that("(g) echo_cif_km returns NA for horizon beyond max observed time", {
  # Build a minimal TTE dataset: one echo event at 100 days
  tte_data <- tibble::tibble(
    ID           = "P9",
    time_days    = 100,
    event_status = "echo",
    event_factor = factor("echo", levels = c("censored", "echo", "death"))
  )

  # Horizon of 1825 days (5 years) is beyond the 100-day max observed time
  cif_res <- echo_cif_km(tte_data, horizons = c(365, 730, 1825))

  row_1825 <- cif_res |> dplyr::filter(horizon_days == 1825)
  expect_equal(nrow(row_1825), 1L)
  expect_true(is.na(row_1825$cif_aj))
  expect_true(is.na(row_1825$one_minus_km))
})
