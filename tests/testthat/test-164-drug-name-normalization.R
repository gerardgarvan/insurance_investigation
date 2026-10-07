# ==============================================================================
# test-164-drug-name-normalization.R -- Tests for doxorubicin generic-name
#   normalization (Phase 164, Task 4)
# ==============================================================================
# Coverage:
#   1. Every variant listed in the plan maps to "Doxorubicin".
#   2. Liposomal variants (Doxil, Caelyx, doxorubicin liposomal) map to
#      "Doxorubicin".
#   3. ABVD and other regimen labels pass through unchanged.
#   4. The mapping is idempotent (normalizing twice gives the same result).
#   5. Duplicate rows collapse after mapping (via sort(unique())).
#   6. NA passes through as NA.
#
# Sourcing: canonicalize_drug_name() is defined in R/00_config.R, which is
# auto-loaded by the test infrastructure. If not already loaded, source it here.
# ==============================================================================

# Ensure canonicalize_drug_name is available ──────────────────────────────────
if (!exists("canonicalize_drug_name")) {
  # Source config silently; suppress expected file-not-found warnings about
  # reference Excel / data files that are absent in the local test environment.
  suppressWarnings(tryCatch(
    source("R/00_config.R", local = FALSE),
    error = function(e) NULL
  ))
}

if (!exists("canonicalize_drug_name")) {
  skip("canonicalize_drug_name not available (R/00_config.R could not be sourced)")
}

# ── 1. Brand names → "Doxorubicin" ──────────────────────────────────────────
test_that("adriamycin brand names map to Doxorubicin", {
  expect_equal(canonicalize_drug_name("adriamycin"),     "Doxorubicin")
  expect_equal(canonicalize_drug_name("Adriamycin"),     "Doxorubicin")
  expect_equal(canonicalize_drug_name("ADRIAMYCIN"),     "Doxorubicin")
  expect_equal(canonicalize_drug_name("adriamycin pfs"), "Doxorubicin")
  expect_equal(canonicalize_drug_name("Adriamycin PFS"), "Doxorubicin")
  expect_equal(canonicalize_drug_name("adriamycin rdf"), "Doxorubicin")
  expect_equal(canonicalize_drug_name("Adriamycin RDF"), "Doxorubicin")
})

# ── 2. Generic salt forms → "Doxorubicin" ───────────────────────────────────
test_that("doxorubicin generic/salt forms map to Doxorubicin", {
  expect_equal(canonicalize_drug_name("doxorubicin"),             "Doxorubicin")
  expect_equal(canonicalize_drug_name("Doxorubicin"),             "Doxorubicin")
  expect_equal(canonicalize_drug_name("DOXORUBICIN"),             "Doxorubicin")
  expect_equal(canonicalize_drug_name("doxorubicin hcl"),         "Doxorubicin")
  expect_equal(canonicalize_drug_name("Doxorubicin HCl"),         "Doxorubicin")
  expect_equal(canonicalize_drug_name("doxorubicin hydrochloride"), "Doxorubicin")
  expect_equal(canonicalize_drug_name("Doxorubicin Hydrochloride"), "Doxorubicin")
})

# ── 3. Liposomal variants → "Doxorubicin" (D-3) ─────────────────────────────
test_that("liposomal doxorubicin variants map to Doxorubicin", {
  expect_equal(canonicalize_drug_name("doxil"),                      "Doxorubicin")
  expect_equal(canonicalize_drug_name("Doxil"),                      "Doxorubicin")
  expect_equal(canonicalize_drug_name("DOXIL"),                      "Doxorubicin")
  expect_equal(canonicalize_drug_name("caelyx"),                     "Doxorubicin")
  expect_equal(canonicalize_drug_name("Caelyx"),                     "Doxorubicin")
  expect_equal(canonicalize_drug_name("liposomal doxorubicin"),      "Doxorubicin")
  expect_equal(canonicalize_drug_name("Liposomal Doxorubicin"),      "Doxorubicin")
  expect_equal(canonicalize_drug_name("doxorubicin liposomal"),      "Doxorubicin")
  expect_equal(canonicalize_drug_name("Doxorubicin Liposomal"),      "Doxorubicin")
  expect_equal(canonicalize_drug_name("doxorubicin hcl liposome"),   "Doxorubicin")
  expect_equal(canonicalize_drug_name("doxorubicin (liposomal)",   ), "Doxorubicin")
  expect_equal(canonicalize_drug_name("Doxorubicin (Liposomal)"),    "Doxorubicin")
})

# ── 4. Regimen labels and other drugs pass through unchanged ─────────────────
test_that("ABVD and other non-aliased names pass through unchanged", {
  expect_equal(canonicalize_drug_name("ABVD"),               "ABVD")
  expect_equal(canonicalize_drug_name("Bleomycin"),           "Bleomycin")
  expect_equal(canonicalize_drug_name("Vinblastine"),         "Vinblastine")
  expect_equal(canonicalize_drug_name("Dacarbazine"),         "Dacarbazine")
  expect_equal(canonicalize_drug_name("Brentuximab Vedotin"), "Brentuximab Vedotin")
  expect_equal(canonicalize_drug_name("Nivolumab"),           "Nivolumab")
  expect_equal(canonicalize_drug_name("Cyclophosphamide"),    "Cyclophosphamide")
})

# ── 5. Idempotency: normalizing twice gives the same result ──────────────────
test_that("canonicalize_drug_name is idempotent", {
  variants <- c(
    "adriamycin", "Adriamycin PFS", "doxorubicin hcl", "Doxorubicin Hydrochloride",
    "Doxil", "Caelyx", "liposomal doxorubicin", "doxorubicin liposomal",
    "Doxorubicin", "Bleomycin", "ABVD"
  )
  once  <- canonicalize_drug_name(variants)
  twice <- canonicalize_drug_name(once)
  expect_equal(once, twice)
})

# ── 6. NA passes through as NA ───────────────────────────────────────────────
test_that("NA input returns NA", {
  expect_true(is.na(canonicalize_drug_name(NA_character_)))
  result <- canonicalize_drug_name(c("doxorubicin", NA_character_, "ABVD"))
  expect_equal(result, c("Doxorubicin", NA_character_, "ABVD"))
})

# ── 7. Duplicate collapse after mapping ──────────────────────────────────────
test_that("duplicate drug tokens collapse via sort(unique()) after mapping", {
  # Simulate two episode detail rows that previously had distinct names
  # for the same drug, now both map to "Doxorubicin".
  raw_names <- c("adriamycin", "Doxorubicin Hydrochloride", "Liposomal Doxorubicin",
                 "Bleomycin", "Vinblastine", "Dacarbazine")
  normalized <- canonicalize_drug_name(raw_names)
  collapsed  <- paste(sort(unique(normalized)), collapse = ",")
  # All dox variants → "Doxorubicin"; no duplicates remain.
  expect_equal(collapsed, "Bleomycin,Dacarbazine,Doxorubicin,Vinblastine")
})

# ── 8. Vectorized behavior ───────────────────────────────────────────────────
test_that("canonicalize_drug_name handles mixed vectors correctly", {
  input  <- c("adriamycin", "Bleomycin", "doxil", "ABVD", NA_character_)
  expect_equal(
    canonicalize_drug_name(input),
    c("Doxorubicin", "Bleomycin", "Doxorubicin", "ABVD", NA_character_)
  )
})
