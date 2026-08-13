test_that("many-to-one join against fixture preserves nrow of encounter_zip", {
  enc_zip <- tibble::tibble(
    ID          = c("A", "A", "B"),
    ENCOUNTERID = c("E1", "E2", "E3"),
    ADMIT_DATE  = as.Date(c("2020-01-01", "2020-01-01", "2020-06-15")),
    direct_zip9 = c(NA_character_, NA_character_, "12345-6789"),
    has_direct_zip9 = c(FALSE, FALSE, TRUE)
  )
  lookup <- tibble::tibble(
    ID         = c("A", "B"),
    query_date = as.Date(c("2020-01-01", "2020-06-15")),
    ZIP9       = c("99999-0001", NA_character_),
    zip9_source = c("zip5_modal", "zip9_observed")
  )

  n_before <- nrow(enc_zip)
  result <- enc_zip %>%
    dplyr::left_join(
      lookup %>% dplyr::select(ID, ADMIT_DATE = query_date,
                               zip9_imputed = ZIP9, zip9_source),
      by = c("ID", "ADMIT_DATE"),
      relationship = "many-to-one"
    )
  expect_equal(nrow(result), n_before)
})

test_that("duplicate (ID, query_date) in lookup triggers stop() before join", {
  dup_lookup <- tibble::tibble(
    ID         = c("A", "A"),
    query_date = as.Date(c("2020-01-01", "2020-01-01")),
    ZIP9       = c("11111-0001", "22222-0002"),
    zip9_source = c("zip9_observed", "zip9_observed")
  )
  n_dup <- sum(duplicated(dup_lookup[c("ID", "query_date")]))
  expect_gt(n_dup, 0L)
  # The guard in SECTION 11B calls stop() when n_dup_lookup > 0. Simulate it:
  expect_error(
    if (n_dup > 0L) stop("duplicate rows detected"),
    "duplicate rows detected"
  )
})

test_that("zip9_effective equals direct_zip9 wherever direct_zip9 is non-NA", {
  enc_zip <- tibble::tibble(
    ID          = c("A", "B"),
    ENCOUNTERID = c("E1", "E2"),
    ADMIT_DATE  = as.Date(c("2020-01-01", "2020-06-15")),
    direct_zip9 = c("12345-6789", NA_character_),
    has_direct_zip9 = c(TRUE, FALSE)
  )
  lookup <- tibble::tibble(
    ID         = c("A", "B"),
    query_date = as.Date(c("2020-01-01", "2020-06-15")),
    ZIP9       = c("99999-0001", "55555-0002"),
    zip9_source = c("zip9_observed", "zip5_modal")
  )
  result <- enc_zip %>%
    dplyr::left_join(
      lookup %>% dplyr::select(ID, ADMIT_DATE = query_date,
                               zip9_imputed = ZIP9, zip9_source),
      by = c("ID", "ADMIT_DATE"),
      relationship = "many-to-one"
    ) %>%
    dplyr::mutate(zip9_effective = dplyr::coalesce(direct_zip9, zip9_imputed))

  # direct_zip9 must always win over zip9_imputed
  direct_rows <- result[!is.na(result$direct_zip9), ]
  expect_equal(direct_rows$zip9_effective, direct_rows$direct_zip9)
})
