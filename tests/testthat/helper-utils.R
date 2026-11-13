# Auto-sourced by testthat before any test file runs.
# Sources R/utils/*.R in the same order as 00_config.R (list.files default, no explicit sort).
suppressMessages({
  for (f in list.files(here::here("R", "utils"), pattern = "\\.R$", full.names = TRUE)) {
    source(f)
  }
})
