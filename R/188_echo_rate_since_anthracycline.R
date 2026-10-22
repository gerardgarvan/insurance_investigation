# R/188_echo_rate_since_anthracycline.R
# Phase 188 — Echo rate per patient-year after last anthracycline dose
#
# Schema probes used (Task 0):
#   .planning/schemas/187out_schema_20261022.md
#     Path: output/internal/anthracycline_exposure_patient_20261022.rds
#     Cols: ID, any_chemo, any_anthracycline, last_anthracycline_date,
#           years_since_last_anthracycline, follow_end, drugs_received
#     any_anthracycline TRUE = 2,379
#   .planning/schemas/188_dated_events_schema_20261022.md
#     Path: CONFIG$cache$outputs_dir / survivorship_dated_events_20261012.rds
#     Cols: ID, modality, event_date (3 cols, 1,054,151 rows, 8,623 IDs)
#     Echo label: "Echocardiogram" (12,026 rows)
#     D-02a: no window/tier/year_index column — file is NOT windowed
#   .planning/schemas/188_166parts_schema_20261022.md
#     Path: CONFIG$cache$outputs_dir / survivorship_echo_parts_20261012.rds
#     Phase 166 per-patient echo rates: element echo_rate_patient (2,387 x 5)
#     Cols: ID, modality, n_dates_post, person_years, rate_per_py
#     modality distinct value: "echo_post_anthracycline" (no variant column)
#
# Source from repo root:
#   source("R/188_echo_rate_since_anthracycline.R", local = new.env(parent = globalenv()))

source(here::here("R", "00_config.R"))

# ── HELPERS ───────────────────────────────────────────────────────────────────
# Counts 1-10 -> "<11"; 0 shown as "0". R/184's sup() is local to R/184,
# so R/188 defines its own.
sup <- function(n) {
  # Counts only: whole, nonnegative numbers. Person-years are handled separately.
  if (any(!is.na(n) & (n < 0 | n != round(n)))) stop("[188] sup() given a negative or fractional value.")
  dplyr::case_when(
    is.na(n)          ~ NA_character_,
    n == 0            ~ "0",
    n >= 1 & n <= 10  ~ "<11",
    TRUE              ~ as.character(n)
  )
}

# Complementary pair: if either cell is "<11", suppress both
# (their sum is a visible total).
sup_pair <- function(a, b) {
  s <- c(sup(a), sup(b))
  if (any(s == "<11", na.rm = TRUE)) s <- c("<11", "<11")
  s
}

# ── build_echo_out() — THE implementation; fixtures AND real data use this ───
build_echo_out <- function(anthra_df, echo_df) {
  # Start from REAL echo rows, attach patient dates (inner join) so no phantom
  # rows are created for patients without echoes, and a genuine source echo with
  # a missing date is kept and labelled "unclassifiable" instead of being dropped.
  stopifnot(!anyDuplicated(anthra_df$ID))
  joined <- echo_df |>
    dplyr::inner_join(anthra_df, by = "ID", relationship = "many-to-one")

  deduped <- joined |>
    dplyr::distinct(ID, echo_date, .keep_all = TRUE)   # D-02b (NA dates collapse to one per patient)

  enc <- deduped |>
    dplyr::mutate(
      days_since_last_anthracycline_dose = as.numeric(echo_date - last_anthracycline_date),
      window_label = dplyr::case_when(
        is.na(echo_date) | is.na(last_anthracycline_date) | is.na(follow_end) ~ "unclassifiable",
        echo_date > follow_end                                                  ~ "after_follow_end",
        echo_date <= last_anthracycline_date                                    ~ "on_or_before_last_dose",
        TRUE                                                                    ~ "after_last_dose"
      )
    ) |>
    dplyr::select(ID, echo_date, days_since_last_anthracycline_dose, window_label)
  # No NA-date filter: every row here is a real echo. Patients with no echo get
  # zero counts through the patient-table left join below.

  # Pivot counts per patient per window label
  counts_wide <- enc |>
    dplyr::count(ID, window_label) |>
    tidyr::pivot_wider(names_from = window_label, values_from = n, values_fill = 0L) |>
    dplyr::rename_with(
      ~ dplyr::case_when(
        .x == "after_last_dose"        ~ "n_echoes_post",
        .x == "on_or_before_last_dose" ~ "n_echoes_before_or_on_last_dose",
        .x == "after_follow_end"       ~ "n_echoes_after_follow_end",
        .x == "unclassifiable"         ~ "n_echoes_unclassifiable",
        TRUE                           ~ .x
      )
    )

  needed_cols <- c(
    "n_echoes_post", "n_echoes_before_or_on_last_dose",
    "n_echoes_after_follow_end", "n_echoes_unclassifiable"
  )
  for (col in needed_cols) {
    if (!col %in% names(counts_wide)) counts_wide[[col]] <- 0L
  }

  pat <- anthra_df |>
    dplyr::left_join(counts_wide, by = "ID") |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(needed_cols), ~ dplyr::coalesce(as.integer(.x), 0L))
    ) |>
    dplyr::mutate(
      person_years       = years_since_last_anthracycline,
      # Eligibility from the dates (valid interval), not from person_years alone;
      # D-07a checks the two agree.
      in_rate_population = !is.na(last_anthracycline_date) & !is.na(follow_end) &
                           follow_end > last_anthracycline_date,
      rate_per_py        = dplyr::if_else(
        in_rate_population,
        n_echoes_post / person_years,
        NA_real_
      )
    ) |>
    dplyr::select(
      ID, n_echoes_post, person_years, rate_per_py,
      n_echoes_before_or_on_last_dose, n_echoes_after_follow_end,
      n_echoes_unclassifiable, in_rate_population
    )

  list(encounter_grain = enc, patient_grain = pat)
}

# ── Fixture constructors ──────────────────────────────────────────────────────
.mk_anthra <- function(id, last_dose, follow_end, py) {
  tibble::tibble(
    ID                             = id,
    last_anthracycline_date        = as.Date(last_dose),
    follow_end                     = as.Date(follow_end),
    years_since_last_anthracycline = py
  )
}
.mk_echo <- function(id, dates) {
  tibble::tibble(ID = id, echo_date = as.Date(dates))
}

# ── FIXTURES (D-22) ───────────────────────────────────────────────────────────
# All 13 fixtures run before SECTION 0 pins (and therefore before any data file
# is loaded), so they pass even when the HiPerGator data files are absent.

# Fixture 1: no-echo patient, person_years > 0 → all counts 0; rate = 0 (not NA);
#            encounter file has zero rows for this patient.
{
  a <- .mk_anthra("P1", "2020-01-01", "2022-01-01", 2.0)
  e <- tibble::tibble(ID = character(0), echo_date = as.Date(character(0)))
  r <- build_echo_out(a, e)
  p <- r$patient_grain
  stopifnot(p$n_echoes_post              == 0L)
  stopifnot(p$n_echoes_before_or_on_last_dose == 0L)
  stopifnot(p$n_echoes_after_follow_end  == 0L)
  stopifnot(p$n_echoes_unclassifiable   == 0L)
  stopifnot(!is.na(p$rate_per_py) && p$rate_per_py == 0)
  stopifnot(nrow(r$encounter_grain) == 0L)
}

# Fixture 2: pre-dose-only echoes → n_echoes_post = 0, before_or_on count = 2
{
  a <- .mk_anthra("P2", "2020-06-01", "2022-01-01", 1.5)
  e <- .mk_echo("P2", c("2019-01-01", "2020-06-01"))
  r <- build_echo_out(a, e)
  p <- r$patient_grain
  stopifnot(p$n_echoes_post == 0L)
  stopifnot(p$n_echoes_before_or_on_last_dose == 2L)
}

# Fixture 3: post-dose echoes within follow_end → rate = n / py
{
  a <- .mk_anthra("P3", "2020-01-01", "2022-01-01", 2.0)
  e <- .mk_echo("P3", c("2020-06-01", "2021-06-01"))
  r <- build_echo_out(a, e)
  p <- r$patient_grain
  stopifnot(p$n_echoes_post == 2L)
  stopifnot(abs(p$rate_per_py - 1.0) < 1e-9)
}

# Fixture 4: echo after follow_end → n_echoes_after_follow_end incremented; excluded from numerator
{
  a <- .mk_anthra("P4", "2020-01-01", "2021-01-01", 1.0)
  e <- .mk_echo("P4", "2021-06-01")
  r <- build_echo_out(a, e)
  p <- r$patient_grain
  stopifnot(p$n_echoes_after_follow_end == 1L)
  stopifnot(p$n_echoes_post == 0L)
}

# Fixture 5: duplicate echo date → counted once (dedup via distinct)
{
  a <- .mk_anthra("P5", "2020-01-01", "2022-01-01", 2.0)
  e <- tibble::tibble(ID = c("P5", "P5"), echo_date = as.Date(c("2020-06-01", "2020-06-01")))
  r <- build_echo_out(a, e)
  p <- r$patient_grain
  stopifnot(p$n_echoes_post == 1L)
}

# Fixture 6: echo on last-dose date → window_label = "on_or_before_last_dose"
{
  a <- .mk_anthra("P6", "2020-06-01", "2022-01-01", 1.5)
  e <- .mk_echo("P6", "2020-06-01")
  r <- build_echo_out(a, e)
  enc <- r$encounter_grain
  stopifnot(enc$window_label == "on_or_before_last_dose")
}

# Fixture 7: echo on follow_end date → window_label = "after_last_dose" (counts in numerator)
{
  a <- .mk_anthra("P7", "2020-01-01", "2022-01-01", 2.0)
  e <- .mk_echo("P7", "2022-01-01")
  r <- build_echo_out(a, e)
  enc <- r$encounter_grain
  stopifnot(enc$window_label == "after_last_dose")
  p <- r$patient_grain
  stopifnot(p$n_echoes_post == 1L)
}

# Fixture 8: NA follow_end → all echoes unclassifiable; in_rate_population = FALSE
{
  a <- .mk_anthra("P8", "2020-01-01", NA, NA)
  e <- .mk_echo("P8", "2020-06-01")
  r <- build_echo_out(a, e)
  enc <- r$encounter_grain
  stopifnot(all(enc$window_label == "unclassifiable"))
  p <- r$patient_grain
  stopifnot(!p$in_rate_population)
}

# Fixture 9: last dose > follow_end → echo between follow_end and dose → after_follow_end
# echo_date (2021-03-01) > follow_end (2020-12-31), so rule 2 fires first
{
  a <- .mk_anthra("P9", "2021-06-01", "2020-12-31", NA)
  e <- .mk_echo("P9", "2021-03-01")
  r <- build_echo_out(a, e)
  enc <- r$encounter_grain
  stopifnot(enc$window_label == "after_follow_end")
}

# Fixture 10: D-06 sum checks pass across a two-patient fixture dataset
{
  a <- dplyr::bind_rows(
    .mk_anthra("PA", "2020-01-01", "2022-01-01", 2.0),
    .mk_anthra("PB", "2020-06-01", "2022-01-01", 1.5)
  )
  e <- dplyr::bind_rows(
    .mk_echo("PA", c("2020-06-01", "2021-01-01")),
    .mk_echo("PB", c("2019-01-01", "2020-06-01"))
  )
  r <- build_echo_out(a, e)
  p <- r$patient_grain
  enc_nrow <- nrow(dplyr::filter(r$encounter_grain, !is.na(echo_date)))
  per_patient_ok <- all(
    (p$n_echoes_post + p$n_echoes_before_or_on_last_dose +
       p$n_echoes_after_follow_end + p$n_echoes_unclassifiable) ==
      dplyr::left_join(
        p |> dplyr::select(ID),
        dplyr::filter(r$encounter_grain, !is.na(echo_date)) |> dplyr::count(ID),
        by = "ID"
      ) |> dplyr::pull(n) |> tidyr::replace_na(0L)
  )
  dataset_ok <- sum(p$n_echoes_post + p$n_echoes_before_or_on_last_dose +
                      p$n_echoes_after_follow_end + p$n_echoes_unclassifiable) == enc_nrow
  stopifnot(per_patient_ok)
  stopifnot(dataset_ok)
}

# Fixture 11: suppression helper
stopifnot(sup(5)  == "<11")
stopifnot(sup(11) == "11")
stopifnot(sup(0)  == "0")

# Fixture 12: complementary pair
stopifnot(identical(sup_pair(5, 400), c("<11", "<11")))
stopifnot(identical(sup_pair(40, 400), c("40", "400")))

# Fixture 13: genuine source echo row with a missing date is kept and labelled
# "unclassifiable", not dropped
{
  a <- .mk_anthra("P13", "2020-01-01", "2022-01-01", 2.0)
  e <- tibble::tibble(ID = c("P13", "P13"), echo_date = as.Date(c(NA, "2020-06-01")))
  r <- build_echo_out(a, e)
  stopifnot(nrow(r$encounter_grain) == 2L)
  stopifnot(r$patient_grain$n_echoes_unclassifiable == 1L,
            r$patient_grain$n_echoes_post == 1L)
}

message("Phase 188: all 13 fixture cases passed.")

# ── SECTION 0: Pins ───────────────────────────────────────────────────────────
R188_DATED_EVENTS <- Sys.getenv(
  "R188_DATED_EVENTS",
  unset = file.path(CONFIG$cache$outputs_dir, "survivorship_dated_events_20261012.rds")
)
R188_ANTHRA_EXPOSURE <- Sys.getenv(
  "R188_ANTHRA_EXPOSURE",
  unset = file.path(CONFIG$output_dir, "internal", "anthracycline_exposure_patient_20261022.rds")
)
R188_ANTHRA_166_PARTS <- Sys.getenv(
  "R188_ANTHRA_166_PARTS",
  unset = file.path(CONFIG$cache$outputs_dir, "survivorship_echo_parts_20261012.rds")
)

stopifnot(file.exists(R188_DATED_EVENTS))
stopifnot(file.exists(R188_ANTHRA_EXPOSURE))
stopifnot(file.exists(R188_ANTHRA_166_PARTS))

pins_188 <- tibble::tibble(
  pin_var = c("R188_DATED_EVENTS", "R188_ANTHRA_EXPOSURE", "R188_ANTHRA_166_PARTS"),
  path    = c(R188_DATED_EVENTS,   R188_ANTHRA_EXPOSURE,   R188_ANTHRA_166_PARTS),
  pinned  = c(
    nchar(Sys.getenv("R188_DATED_EVENTS"))     > 0,
    nchar(Sys.getenv("R188_ANTHRA_EXPOSURE"))  > 0,
    nchar(Sys.getenv("R188_ANTHRA_166_PARTS")) > 0
  )
)

# ── SECTION 1: Load inputs ────────────────────────────────────────────────────
anthra_raw <- readRDS(R188_ANTHRA_EXPOSURE)
anthra <- anthra_raw |>
  dplyr::filter(any_anthracycline == TRUE) |>
  dplyr::mutate(ID = as.character(ID)) |>
  dplyr::select(ID, last_anthracycline_date, follow_end, years_since_last_anthracycline)
stopifnot(!anyDuplicated(anthra$ID))
n_exposed <- nrow(anthra)    # read at run time (2,379 at planning) — never typed into code
message("[188] Exposed patients from Phase 187: ", n_exposed)

events_raw <- readRDS(R188_DATED_EVENTS)
ECHO_LABEL <- "Echocardiogram"   # from 188_dated_events_schema_20261022.md
echo_raw <- events_raw |>
  dplyr::filter(modality == ECHO_LABEL) |>
  dplyr::transmute(ID = as.character(ID), echo_date = event_date) |>
  dplyr::filter(ID %in% anthra$ID)

# Independent source counts for reconciliation (computed before build_echo_out)
n_src_rows   <- nrow(echo_raw)
n_src_na_date <- sum(is.na(echo_raw$echo_date))
n_src_unique  <- nrow(dplyr::distinct(echo_raw, ID, echo_date))
message("[188] Source echo rows for exposed patients: ", n_src_rows,
        " | NA dates: ", n_src_na_date, " | unique ID x date: ", n_src_unique,
        " | duplicates removed: ", n_src_rows - n_src_unique)

echo_parts_166 <- readRDS(R188_ANTHRA_166_PARTS)
# Element name, column names, echo label from 188_166parts_schema_20261022.md
P166_ELEMENT    <- "echo_rate_patient"        # from 188_166parts_schema_20261022.md
P166_ECHO_LABEL <- "echo_post_anthracycline"  # from 188_166parts_schema_20261022.md
p166_all <- echo_parts_166[[P166_ELEMENT]]
if (is.null(p166_all)) stop("[188] Element '", P166_ELEMENT, "' not in parts RDS. Available: ",
                             paste(names(echo_parts_166), collapse = ", "))
# No variant column in echo_rate_patient (probe confirms primary variant only).
p166 <- p166_all |>
  dplyr::filter(modality == P166_ECHO_LABEL) |>
  dplyr::mutate(ID = as.character(ID))
stopifnot(!anyDuplicated(p166$ID))

# ── SECTION 2-3: same build_echo_out() the fixtures tested ───────────────────
out_188  <- build_echo_out(anthra, echo_raw)
echo_enc <- out_188$encounter_grain   # real echoes only, deduped, labelled (D-02b, D-05a)
pat      <- out_188$patient_grain

stopifnot(nrow(pat) == n_exposed)
# Source-to-output reconciliation: unique source ID x date reaches the encounter file
if (nrow(echo_enc) != n_src_unique)
  stop("[188] Encounter rows (", nrow(echo_enc), ") != unique source ID x date pairs (",
       n_src_unique, ").")
message("[188] window_label counts:")
print(table(echo_enc$window_label, useNA = "ifany"))

enc_path <- file.path(CONFIG$output_dir, "internal",
                      glue::glue("echo_enc_anthracycline_{format(Sys.Date(), '%Y%m%d')}.rds"))
saveRDS(echo_enc, enc_path)
message("[188] Encounter-grain RDS: ", enc_path, " (", nrow(echo_enc), " rows)")

# D-07a: denominator and eligibility check over the WHOLE exposed population
validation <- anthra |>
  dplyr::mutate(
    valid_dates = !is.na(last_anthracycline_date) & !is.na(follow_end) &
                  follow_end > last_anthracycline_date,
    py_expected = dplyr::if_else(
      valid_dates,
      as.numeric(follow_end - last_anthracycline_date) / 365.25,
      NA_real_
    )
  ) |>
  dplyr::left_join(dplyr::select(pat, ID, person_years, in_rate_population), by = "ID")
if (!identical(validation$valid_dates, validation$in_rate_population))
  stop("[188] D-07a: rate eligibility does not match the date-based definition.")
eligible <- dplyr::filter(validation, valid_dates)
if (nrow(eligible) == 0L) stop("[188] D-07a: no eligible patients.")
if (anyNA(eligible$person_years)) stop("[188] D-07a: Phase 187 person_years NA for an eligible patient.")
d07a <- max(abs(eligible$py_expected - eligible$person_years))
if (d07a >= 1e-9) stop("[188] D-07a FAILED: max person-year difference ", d07a)
# Ineligible patients must not carry positive person-years
if (any(!validation$valid_dates & !is.na(validation$person_years) & validation$person_years > 0))
  stop("[188] D-07a: an ineligible patient has positive person_years.")
message("[188] D-07a check passed: max person-year diff = ", format(d07a, scientific = TRUE))

# D-06 sum checks (per patient and dataset level)
per_patient_totals <- dplyr::count(echo_enc, ID)
chk <- pat |>
  dplyr::left_join(per_patient_totals, by = "ID") |>
  dplyr::mutate(
    n    = dplyr::coalesce(n, 0L),
    sum4 = n_echoes_post + n_echoes_before_or_on_last_dose +
           n_echoes_after_follow_end + n_echoes_unclassifiable
  )
if (any(chk$sum4 != chk$n))
  stop("[188] D-06 per-patient sum check failed for ", sum(chk$sum4 != chk$n), " patients.")
if (sum(chk$sum4) != nrow(echo_enc))
  stop("[188] D-06 dataset sum check failed.")
message("[188] D-06 sum checks passed (per-patient and dataset-level).")

pat_path <- file.path(CONFIG$output_dir, "internal",
                      glue::glue("echo_rate_anthracycline_patient_{format(Sys.Date(), '%Y%m%d')}.rds"))
saveRDS(pat, pat_path)
message("[188] Patient-grain RDS: ", pat_path, " (", nrow(pat), " rows)")

# ── SECTION 4: Workbook ───────────────────────────────────────────────────────
wb <- openxlsx::createWorkbook()

UF_BLUE   <- "#0021A5"
UF_ORANGE <- "#FA4616"

hdr_style <- openxlsx::createStyle(
  fontColour = "#FFFFFF", fgFill = UF_BLUE, textDecoration = "bold", halign = "left"
)
acc_style <- openxlsx::createStyle(
  fontColour = "#FFFFFF", fgFill = UF_ORANGE, textDecoration = "bold"
)

# ── Sheet 1: KEY ──────────────────────────────────────────────────────────────
openxlsx::addWorksheet(wb, "KEY")

key_rows <- tibble::tibble(
  item = c(
    # Pins
    "Pin: R188_DATED_EVENTS",
    "Pin: R188_ANTHRA_EXPOSURE",
    "Pin: R188_ANTHRA_166_PARTS",
    "Pin: R188_DATED_EVENTS — pinned (env var set)?",
    "Pin: R188_ANTHRA_EXPOSURE — pinned (env var set)?",
    "Pin: R188_ANTHRA_166_PARTS — pinned (env var set)?",
    # Probe citations
    "Probe: 187out schema file",
    "Probe: 188_dated_events schema file",
    "Probe: 188_166parts schema file",
    # D-02a
    "D-02a: dated_events windowing",
    # D-05a
    "D-05a: echo on last-dose date",
    "D-05a: echo on follow_end date",
    # D-08a
    "D-08a: anchor name note",
    "D-08a: numerical equality note",
    "D-08a: citation",
    # Deviations
    "PD-01: Phase 166 workbook",
    "PD-02: anchor dates in parts RDS"
  ),
  value = c(
    R188_DATED_EVENTS,
    R188_ANTHRA_EXPOSURE,
    R188_ANTHRA_166_PARTS,
    as.character(pins_188$pinned[pins_188$pin_var == "R188_DATED_EVENTS"]),
    as.character(pins_188$pinned[pins_188$pin_var == "R188_ANTHRA_EXPOSURE"]),
    as.character(pins_188$pinned[pins_188$pin_var == "R188_ANTHRA_166_PARTS"]),
    ".planning/schemas/187out_schema_20261022.md",
    ".planning/schemas/188_dated_events_schema_20261022.md",
    ".planning/schemas/188_166parts_schema_20261022.md",
    paste0("survivorship_dated_events_20261012.rds is NOT windowed (D-02a confirmed). ",
           "The on_or_before_last_dose count is the full pre-dose history, ",
           "not limited to a survivorship window."),
    "An echo on the last-dose date is counted as on or before the dose (on_or_before_last_dose).",
    "An echo on the follow_end date is counted in the post-dose numerator (after_last_dose).",
    paste0("Anchor names differ: Phase 166 uses last_dose_firstline_dt; ",
           "Phase 188 uses last_dose_ever_dt (last_anthracycline_date from Phase 187). ",
           "In this extract the dates are numerically equal per Phase 166 D-08a fallback."),
    paste0("D-08a applied in Phase 166: first_line column absent from ",
           "treatment_episode_detail_180.rds; all episodes treated as first-line ",
           "(last_dose_firstline_dt == last_dose_ever_dt). Differences visible in the ",
           "Anchor Comparison sheet are cross-phase descriptive differences; the ",
           "methodology table on that sheet lists which dimensions differ."),
    "166-03-SUMMARY.md decisions block: 'D-08a applied: first_line column absent from treatment_episode_detail_180.rds; all episodes treated as first-line (last_dose_firstline_dt == last_dose_ever_dt).'",
    paste0("PD-01: No Phase 166 workbook exists. The Phase 166 row in the Anchor Comparison ",
           "is aggregated from Phase 166's own per-patient output ",
           "(survivorship_echo_parts_20261012.rds, echo_rate_patient element), ",
           "using the same pooled formula as Phase 188."),
    paste0("PD-02: Anchor dates (last_dose_firstline_dt) are not stored in the parts RDS. ",
           "The per-patient comparison (D-15a) uses person_years as the proxy, ",
           "since both phases derive follow_end from the same source.")
  )
)

openxlsx::writeData(wb, "KEY", key_rows)
openxlsx::addStyle(wb, "KEY", hdr_style, rows = 1, cols = 1:2, gridExpand = TRUE)
openxlsx::setColWidths(wb, "KEY", cols = 1:2, widths = c(45, 100))

# ── Sheet 2: Rates ────────────────────────────────────────────────────────────
openxlsx::addWorksheet(wb, "Rates")

rate_pop  <- dplyr::filter(pat, in_rate_population)
n_pts     <- nrow(rate_pop)
n_excl    <- n_exposed - n_pts
tot_echo  <- sum(rate_pop$n_echoes_post)
tot_py    <- sum(rate_pop$person_years)
show_rate <- tot_echo >= 11 && tot_py >= 11
pts_s     <- sup_pair(n_pts, n_excl)   # included + excluded = exposed total (visible in QC)

rates_df <- tibble::tibble(
  label              = "Echo rate after last anthracycline dose (pooled)",
  n_patients         = pts_s[1],
  n_excluded         = pts_s[2],
  total_echoes_post  = sup(tot_echo),
  total_person_years = if (tot_py >= 1 && tot_py < 11) "<11" else format(round(tot_py, 1), nsmall = 1),
  rate_per_py        = if (show_rate) format(round(tot_echo / tot_py, 4), nsmall = 4) else "-"
)

openxlsx::writeData(wb, "Rates", rates_df)
openxlsx::addStyle(wb, "Rates", hdr_style, rows = 1, cols = seq_len(ncol(rates_df)), gridExpand = TRUE)
openxlsx::setColWidths(wb, "Rates", cols = seq_len(ncol(rates_df)),
                       widths = c(50, 12, 12, 18, 20, 12))

# ── Sheet 3: Anchor Comparison ────────────────────────────────────────────────
openxlsx::addWorksheet(wb, "Anchor Comparison")

# Phase 166 aggregate row (from per-patient parts RDS, primary variant, person_years > 0)
p166_rate <- dplyr::filter(p166, !is.na(person_years), person_years > 0)
n166      <- nrow(p166_rate)
echo166   <- sum(p166_rate$n_dates_post)
py166     <- sum(p166_rate$person_years)
show166   <- echo166 >= 11 && py166 >= 11

# Rate rows
anc_rows <- tibble::tibble(
  phase        = c(
    "last_dose_firstline_dt (D-08a: equals last_dose_ever_dt in this extract)",
    "last_dose_ever_dt (Phase 188)",
    "Difference (Phase 188 − Phase 166), cross-phase descriptive"
  ),
  n_patients = c(
    sup(n166),
    pts_s[1],
    if (grepl("<11", sup(n166)) || grepl("<11", pts_s[1])) "" else as.character(n_pts - n166)
  ),
  total_echoes_post = c(
    sup(echo166),
    sup(tot_echo),
    if (grepl("<11", sup(echo166)) || grepl("<11", sup(tot_echo))) "" else as.character(tot_echo - echo166)
  ),
  total_person_years = c(
    if (show166) format(round(py166, 1), nsmall = 1) else "-",
    if (show_rate || tot_py >= 11) format(round(tot_py, 1), nsmall = 1) else "-",
    if (!show166 || !(show_rate || tot_py >= 11)) "" else format(round(tot_py - py166, 1), nsmall = 1)
  ),
  rate_per_py = c(
    if (show166) format(round(echo166 / py166, 4), nsmall = 4) else "-",
    if (show_rate) format(round(tot_echo / tot_py, 4), nsmall = 4) else "-",
    if (!show166 || !show_rate) "" else format(round(tot_echo / tot_py - echo166 / py166, 4), nsmall = 4)
  )
)

# Per-patient overlap comparison (D-15a)
# PD-02: n_dates_post is the Phase 166 column name (from 188_166parts_schema_20261022.md)
ov <- dplyr::full_join(
  dplyr::transmute(p166, ID, in166 = TRUE, py166 = person_years, n166 = n_dates_post),
  dplyr::transmute(pat,  ID, in188 = TRUE, py188 = person_years, n188 = n_echoes_post),
  by = "ID"
) |>
  dplyr::mutate(
    in166 = dplyr::coalesce(in166, FALSE),
    in188 = dplyr::coalesce(in188, FALSE)
  )
both    <- dplyr::filter(ov, in166, in188)
both_py <- dplyr::filter(both, !is.na(py166), !is.na(py188))

overlap_rows <- tibble::tibble(
  item = c(
    "Patients in both Phase 166 and Phase 188",
    "Patients only in Phase 166",
    "Patients only in Phase 188",
    paste0("Patients with different person-years / ",
           "patients in both with person-years on both sides"),
    "Patients with different post-dose echo count / patients in both",
    "Patients rate-eligible in both (person-years > 0 on both sides) / patients in both"
  ),
  value = c(
    sup(nrow(both)),
    sup(sum(ov$in166 & !ov$in188)),
    sup(sum(!ov$in166 & ov$in188)),
    paste0(sup(sum(abs(both_py$py166 - both_py$py188) > 1e-9)), " / ", sup(nrow(both_py))),
    paste0(sup(sum(both$n166 != both$n188, na.rm = TRUE)), " / ", sup(nrow(both))),
    paste0(sup(sum(both$py166 > 0 & both$py188 > 0, na.rm = TRUE)), " / ", sup(nrow(both)))
  )
)

# Methodology table (8 rows)
meth <- tibble::tibble(
  dimension = c(
    "anchor definition",
    "drug set",
    "patient eligibility",
    "follow-up end rule",
    "echo source file",
    "echo counting unit",
    "person-time definition",
    "window filter"
  ),
  phase_166 = c(
    "last_dose_firstline_dt (D-08a: equals last_dose_ever_dt in this extract)",
    "Doxorubicin and other anthracyclines (all-episodes primary variant; see D-166-01 / D-06 / D-07 in 166-CONTEXT.md)",
    "2,387 patients with any anthracycline, primary variant (Phase 166/167 episode join)",
    "follow_end from survivorship_modality_rates_parts (Phase 166 compute_followup())",
    "survivorship_dated_events_20261012.rds",
    "unique event_date per ID (echo_rate_post_dose() n_distinct)",
    "(follow_end - last_dose_firstline_dt) / 365.25; NA when follow_end <= dose",
    "strictly after last dose and on or before follow_end (echo_rate_post_dose(): event_date > dose_date & event_date <= follow_end)"
  ),
  phase_188 = c(
    "last_dose_ever_dt (last_anthracycline_date from Phase 187)",
    "any_anthracycline == TRUE from Phase 187 (Doxorubicin, Daunorubicin, Epirubicin)",
    "2,379 patients with any_anthracycline == TRUE from Phase 187",
    "follow_end from Phase 187 (survivorship_modality_rates_parts origin)",
    "survivorship_dated_events_20261012.rds",
    "unique echo_date per ID (D-02b: dplyr::distinct)",
    "(follow_end - last_anthracycline_date) / 365.25; NA when follow_end <= dose or either date NA",
    "after_last_dose label only: echo_date > last_anthracycline_date and echo_date <= follow_end (D-05a)"
  ),
  same = c(
    "No (anchor name differs; dates numerically equal per D-08a)",
    "Yes (same anthracycline class)",
    "No (patient counts differ)",
    "Yes (same source)",
    "Yes",
    "Yes",
    "Yes",
    "Yes"
  ),
  source = c(
    "166-03-SUMMARY.md decisions block; 188-CONTEXT.md D-08a",
    "166-CONTEXT.md D-06, D-07; 187out_schema_20261022.md",
    "188_166parts_schema_20261022.md; 187out_schema_20261022.md",
    "166-CONTEXT.md D-14b; 187-01-SUMMARY.md",
    "188_dated_events_schema_20261022.md",
    "166-03-SUMMARY.md; 188-01-PLAN.md D-02b",
    "utils_anthracycline_echo.R lines 273-277; 188-01-PLAN.md D-07a",
    "utils_anthracycline_echo.R lines 287-289; 188-01-PLAN.md D-05a"
  )
)

# Write Anchor Comparison sheet in three blocks
row_cursor <- 1L

# Block 1: Rate comparison header + rows
openxlsx::writeData(wb, "Anchor Comparison",
                    tibble::tibble(section = "Rate comparison"),
                    startRow = row_cursor)
openxlsx::addStyle(wb, "Anchor Comparison", acc_style,
                   rows = row_cursor, cols = 1, gridExpand = TRUE)
row_cursor <- row_cursor + 1L
openxlsx::writeData(wb, "Anchor Comparison", anc_rows, startRow = row_cursor)
openxlsx::addStyle(wb, "Anchor Comparison", hdr_style,
                   rows = row_cursor, cols = seq_len(ncol(anc_rows)), gridExpand = TRUE)
row_cursor <- row_cursor + nrow(anc_rows) + 2L

# Block 2: Per-patient overlap
openxlsx::writeData(wb, "Anchor Comparison",
                    tibble::tibble(section = "Per-patient overlap (D-15a)"),
                    startRow = row_cursor)
openxlsx::addStyle(wb, "Anchor Comparison", acc_style,
                   rows = row_cursor, cols = 1, gridExpand = TRUE)
row_cursor <- row_cursor + 1L
openxlsx::writeData(wb, "Anchor Comparison", overlap_rows, startRow = row_cursor)
openxlsx::addStyle(wb, "Anchor Comparison", hdr_style,
                   rows = row_cursor, cols = seq_len(ncol(overlap_rows)), gridExpand = TRUE)
row_cursor <- row_cursor + nrow(overlap_rows) + 2L

# Block 3: Methodology table
openxlsx::writeData(wb, "Anchor Comparison",
                    tibble::tibble(section = "Methodology comparison"),
                    startRow = row_cursor)
openxlsx::addStyle(wb, "Anchor Comparison", acc_style,
                   rows = row_cursor, cols = 1, gridExpand = TRUE)
row_cursor <- row_cursor + 1L
openxlsx::writeData(wb, "Anchor Comparison", meth, startRow = row_cursor)
openxlsx::addStyle(wb, "Anchor Comparison", hdr_style,
                   rows = row_cursor, cols = seq_len(ncol(meth)), gridExpand = TRUE)

openxlsx::setColWidths(wb, "Anchor Comparison", cols = 1:5, widths = c(30, 60, 60, 30, 60))

# ── Sheet 4: QC ───────────────────────────────────────────────────────────────
openxlsx::addWorksheet(wb, "QC")

qc_row <- 1L

# Panel A: echoes on or before last dose
n_before <- sum(pat$n_echoes_before_or_on_last_dose)
n_pts_before <- sum(pat$n_echoes_before_or_on_last_dose > 0)
show_pct_a <- n_pts_before >= 11 && n_exposed >= 11
pct_a <- if (show_pct_a) paste0(round(100 * n_pts_before / n_exposed, 1), "%") else "-"

panel_a <- tibble::tibble(
  panel   = "Panel A: echoes on or before last anthracycline dose",
  metric  = c("Total echoes on or before last dose",
               "Patients with any on-or-before echo",
               "Pct of exposed patients (shown when numerator and denominator >= 11)"),
  value   = c(sup(n_before), sup(n_pts_before), pct_a)
)
openxlsx::writeData(wb, "QC", tibble::tibble(section = "Panel A: echoes on or before last dose"),
                    startRow = qc_row)
openxlsx::addStyle(wb, "QC", acc_style, rows = qc_row, cols = 1, gridExpand = TRUE)
qc_row <- qc_row + 1L
openxlsx::writeData(wb, "QC", panel_a[, c("metric", "value")], startRow = qc_row)
openxlsx::addStyle(wb, "QC", hdr_style, rows = qc_row,
                   cols = seq_len(ncol(panel_a[, c("metric", "value")])), gridExpand = TRUE)
qc_row <- qc_row + nrow(panel_a) + 2L

# Panel B: echoes after follow_end
n_after <- sum(pat$n_echoes_after_follow_end)
n_pts_after <- sum(pat$n_echoes_after_follow_end > 0)
show_pct_b <- n_pts_after >= 11 && n_exposed >= 11
pct_b <- if (show_pct_b) paste0(round(100 * n_pts_after / n_exposed, 1), "%") else "-"

panel_b <- tibble::tibble(
  metric = c("Total echoes after follow_end",
              "Patients with any after-follow_end echo",
              "Pct of exposed patients (shown when numerator and denominator >= 11)"),
  value  = c(sup(n_after), sup(n_pts_after), pct_b)
)
openxlsx::writeData(wb, "QC", tibble::tibble(section = "Panel B: echoes after follow_end"),
                    startRow = qc_row)
openxlsx::addStyle(wb, "QC", acc_style, rows = qc_row, cols = 1, gridExpand = TRUE)
qc_row <- qc_row + 1L
openxlsx::writeData(wb, "QC", panel_b, startRow = qc_row)
openxlsx::addStyle(wb, "QC", hdr_style, rows = qc_row,
                   cols = seq_len(ncol(panel_b)), gridExpand = TRUE)
qc_row <- qc_row + nrow(panel_b) + 2L

# Panel C: patient reconciliation (D-12)
rec <- dplyr::left_join(
  dplyr::select(pat, ID, in_rate_population),
  dplyr::select(anthra, ID, last_anthracycline_date, follow_end),
  by = "ID"
) |>
  dplyr::mutate(reason = dplyr::case_when(
    in_rate_population                        ~ "in rate population",
    is.na(last_anthracycline_date)            ~ "excluded: last dose missing",
    is.na(follow_end)                         ~ "excluded: follow_end missing",
    last_anthracycline_date >  follow_end     ~ "excluded: last dose after follow_end",
    last_anthracycline_date == follow_end     ~ "excluded: last dose on follow_end (zero person-years)",
    TRUE                                      ~ "excluded: other"
  ))
rec_tab <- dplyr::count(rec, reason)
if (sum(rec_tab$n) != n_exposed) stop("[188] Panel C identity failed.")
if (any(rec_tab$reason == "excluded: other")) stop("[188] Panel C: unexpected exclusion reason.")

rec_tab <- rec_tab |>
  dplyr::mutate(shown = sup(n))

# Complementary suppression: one hidden exclusion row is recoverable from the total
excl <- which(startsWith(rec_tab$reason, "excluded"))
small <- excl[rec_tab$shown[excl] == "<11"]
if (length(small) == 1L) {
  others <- setdiff(excl, small)
  if (length(others) > 0L)
    rec_tab$shown[others[which.min(rec_tab$n[others])]] <- "<11"
}
# Align "in rate population" row with sup_pair result from Rates sheet
rec_tab$shown[rec_tab$reason == "in rate population"] <- pts_s[1]

panel_c_out <- dplyr::select(rec_tab, reason, shown)
openxlsx::writeData(wb, "QC", tibble::tibble(section = "Panel C: patient reconciliation"),
                    startRow = qc_row)
openxlsx::addStyle(wb, "QC", acc_style, rows = qc_row, cols = 1, gridExpand = TRUE)
qc_row <- qc_row + 1L
openxlsx::writeData(wb, "QC", panel_c_out, startRow = qc_row)
openxlsx::addStyle(wb, "QC", hdr_style, rows = qc_row,
                   cols = seq_len(ncol(panel_c_out)), gridExpand = TRUE)
qc_row <- qc_row + nrow(panel_c_out) + 2L

# Panel D: unclassifiable echoes
n_unclass <- sum(pat$n_echoes_unclassifiable)
if (n_unclass > 0)
  warning("[188] Panel D: ", n_unclass, " unclassifiable echo events — review source dates.")
panel_d <- tibble::tibble(
  metric = "Total unclassifiable echoes (expected 0)",
  value  = sup(n_unclass)
)
openxlsx::writeData(wb, "QC", tibble::tibble(section = "Panel D: unclassifiable echoes"),
                    startRow = qc_row)
openxlsx::addStyle(wb, "QC", acc_style, rows = qc_row, cols = 1, gridExpand = TRUE)
qc_row <- qc_row + 1L
openxlsx::writeData(wb, "QC", panel_d, startRow = qc_row)
openxlsx::addStyle(wb, "QC", hdr_style, rows = qc_row,
                   cols = seq_len(ncol(panel_d)), gridExpand = TRUE)

openxlsx::setColWidths(wb, "QC", cols = 1:2, widths = c(60, 20))

# ── Write workbook ────────────────────────────────────────────────────────────
wb_path <- file.path(
  CONFIG$output_dir,
  glue::glue("{format(Sys.Date(), '%Y%m%d')}_188_echo_rate_anthracycline.xlsx")
)
openxlsx::saveWorkbook(wb, wb_path, overwrite = TRUE)
message("[188] Workbook written: ", wb_path)
message("[188] Phase 188 complete. Sheets: KEY, Rates, Anchor Comparison, QC")
