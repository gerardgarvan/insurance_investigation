---
phase: quick-260918-his
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - R/utils/utils_distance_hist.R
  - R/122_encounter_distance.R
  - tests/testthat/test-utils-distance-hist.R
  - .planning/phases/154-distribution-and-histogram-deliverable/154-CONTEXT.md
autonomous: true
requirements: []

must_haves:
  truths:
    - "bin_distance(log) first bin is [0,1) mi with lower = -0.25, upper = 0, lower_mi = 0, upper_mi = 1"
    - "Decade values (1, 10, 100 mi) land exactly on log bin edges (lower %in% c(0, 1, 2))"
    - "Log plot x-axis has a '<1' tick and decade ticks that coincide with bar edges"
    - "Histogram subtitle names the same-ZIP zero count as '... N same-ZIP encounters at 0 mi.'"
    - "make_distance_histograms() accepts linear_width and linear_cap; passes them to bin_distance()"
    - "Linear defaults are 10-mile bins, 350-mile cap ('350+' open top bin)"
    - "QC sheet extra_tbl contains three sub-tables identified by a 'table' column"
    - "All four tests in sections C1–C4 pass without failures"
    - "154-CONTEXT.md records decision 154-D7 under Implementation Decisions"
  artifacts:
    - path: "R/utils/utils_distance_hist.R"
      provides: "bin_distance(), plot_distance_hist(), make_distance_histograms() with A1-A4 edits"
    - path: "R/122_encounter_distance.R"
      provides: "Updated SECTION 12.5b call, B_histogram_bins KEY row, 12.5b-ii tail block"
    - path: "tests/testthat/test-utils-distance-hist.R"
      provides: "Updated/replaced tests C1-C4"
    - path: ".planning/phases/154-distribution-and-histogram-deliverable/154-CONTEXT.md"
      provides: "154-D7 decision entry"
  key_links:
    - from: "R/122_encounter_distance.R SECTION 12.5b"
      to: "make_distance_histograms()"
      via: "linear_width = 10, linear_cap = 350 arguments"
    - from: "plot_distance_hist()"
      to: "bin_distance() first bin lower = -0.25"
      via: "xf = ifelse(v < 1, -0.125, log10(v)) mapping"
    - from: "R/122_encounter_distance.R add_styled_sheet QC"
      to: "tail_by_state / tail_by_patient_zip"
      via: "dplyr::bind_rows() with 'table' column"
---

<objective>
Apply all edits from FIX_histograms.md to fix histogram binning and labelling after the
2026-09-18 first HiPerGator run. Fixes: log-bin edges now coincide with decade tick marks,
the same-ZIP zero spike is named in the subtitle, the 5-mile/300-mile linear defaults are
replaced with 10-mile/350-mile, and a long-distance tail QC table is appended to the QC sheet.

Purpose: The 2026-09-18 PNGs showed misaligned axis ticks and an unlabelled zero spike.
Output: Corrected utils_distance_hist.R, updated R/122 SECTION 12.5b, corrected tests, and
154-D7 decision log entry.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/phases/154-distribution-and-histogram-deliverable/154-CONTEXT.md
@FIX_histograms.md
@R/utils/utils_distance_hist.R
@R/122_encounter_distance.R
@tests/testthat/test-utils-distance-hist.R
</context>

<tasks>

<task type="auto">
  <name>Task 1: Apply A1-A4 to utils_distance_hist.R</name>
  <files>R/utils/utils_distance_hist.R</files>
  <action>
Apply exactly the four subsections from FIX_histograms.md section A. Anchor on the
code text shown below (not line numbers); replace only the indicated blocks.

**A1 — Replace the entire bin_distance() function.**

Current function starts with:
```
bin_distance <- function(mi, scale = c("linear", "log"), width = 5, cap = 300) {
```
and ends just before the `# ---` separator before `plot_distance_hist`.

Replace the whole function (including its roxygen block starting `#' Cut distance_mi`)
with the new function from FIX_histograms.md A1. Key design changes:
- signature: `width = 10, cap = 350` (new defaults)
- log path: `x <- ifelse(mi < 1, -0.125, log10(mi))` (not `log10(1 + mi)`)
- log edges start at `-0.25`: `edges <- c(-0.25, seq(0, top, by = 0.25))`
- `top` computed as `(floor(max(x) / 0.25) + 1) * 0.25`
- empty tibble is returned via a named `empty` object with `if (length(mi) == 0L) return(empty)`
- `stopifnot` guard: `"bin_distance(): negative distances" = all(mi >= 0)`
- `lower_mi` / `upper_mi` for log: `ifelse(lower < 0, 0, 10^lower)` / `10^upper`
- Use `dplyr::if_else()` for lower_mi and upper_mi (NOT base `ifelse()`)

**A2 — In plot_distance_hist(), make four targeted replacements:**

(a) Replace:
```r
  xf   <- if (is_log) function(v) log10(1 + v) else identity
```
with:
```r
  xf   <- if (is_log) function(v) ifelse(v < 1, -0.125, log10(v)) else identity
```

(b) Replace the subtitle sprintf line:
```r
      subtitle = sprintf("n = %s; median %.1f mi (solid), 90th percentile %.1f mi (dashed)",
                         format(stats$n, big.mark = ","), stats$median, stats$p90),
```
with:
```r
      subtitle = sprintf("n = %s. Median %.1f mi (solid line); 90th percentile %.1f mi (dashed line). %s same-ZIP %s at 0 mi.",
                         format(stats$n, big.mark = ","), stats$median, stats$p90,
                         format(stats$n_zero, big.mark = ","), unit),
```
Note: `unit` is already computed earlier in the function as
`if (level == "encounter") "encounters" else "patients"` — confirm it exists; add
`unit <- if (level == "encounter") "encounters" else "patients"` near the top of the
function if it does not already exist.

(c) Replace:
```r
      x = if (is_log) "Distance, miles (log10(1 + mi) scale)" else "Distance, miles",
```
with:
```r
      x = if (is_log) "Distance, miles (log scale; first bar = under 1 mile)" else "Distance, miles",
```

(d) Replace the entire axis block. Currently it is:
```r
  if (is_log) {
    ticks <- c(0, 1, 5, 10, 25, 50, 100, 250, 500, 1000)
    p <- p + ggplot2::scale_x_continuous(breaks = log10(1 + ticks), labels = ticks)
  }
```
Replace with the full if/else block from FIX_histograms.md A2(d):
```r
  if (is_log) {
    ticks <- c(1, 3, 10, 30, 100, 300, 1000, 3000)
    ticks <- ticks[log10(ticks) <= max(bins$upper)]
    p <- p + ggplot2::scale_x_continuous(
      breaks = c(-0.125, log10(ticks)),
      labels = c("<1", scales::label_comma()(ticks)),
      expand = ggplot2::expansion(mult = c(0.01, 0.02)))
  } else {
    step   <- if (cap >= 200) 50 else if (cap >= 100) 25 else 10
    brks   <- seq(0, cap, by = step)
    top    <- cap + bw / 2
    p <- p + ggplot2::scale_x_continuous(
      breaks = c(brks, top),
      labels = c(as.character(brks), paste0(cap, "+")),
      expand = ggplot2::expansion(mult = c(0.01, 0.02)))
  }
```
Note: `bw` and `cap` must be accessible here. They are computed at the top of
`plot_distance_hist()` from `bins`. Confirm `bw <- diff(bins$lower)[1]` and
`cap <- max(bins$lower[!is.infinite(bins$upper)])` are present (or add them).

(e) In the theme() call, set `plot.subtitle` size to 9.5:
```r
    ggplot2::theme(
      plot.caption  = ggplot2::element_text(hjust = 0, colour = "grey30"),
      plot.subtitle = ggplot2::element_text(size = 9.5)
    )
```

**A3 — In make_distance_histograms(), two replacements:**

Replace the signature:
```r
make_distance_histograms <- function(dist, out_dir, run_date = format(Sys.Date(), "%Y%m%d"),
                                     cutoffs = NULL) {
```
with:
```r
make_distance_histograms <- function(dist, out_dir, run_date = format(Sys.Date(), "%Y%m%d"),
                                     cutoffs = NULL, linear_width = 10, linear_cap = 350) {
```

Replace:
```r
      b <- bin_distance(levels[[lv]]$d$distance_mi, scale = sc)
```
with:
```r
      b <- if (sc == "linear") {
        bin_distance(levels[[lv]]$d$distance_mi, scale = "linear", width = linear_width, cap = linear_cap)
      } else {
        bin_distance(levels[[lv]]$d$distance_mi, scale = "log")
      }
```

**A4 — Append two lines to the header comment block** (after the existing `# Called from:` line):
```r
# Log bins (A1, 2026-09-18): [0,1) mi first bin, then quarter-decade bins on log10(mi).
# Linear defaults: 10-mile bins, 350-mile cap (set from R/122; see 154-D7).
```

Do NOT change summarise_distance() or any other function.
  </action>
  <verify>
    <automated>Rscript -e 'invisible(parse("R/utils/utils_distance_hist.R")); cat("parse OK\n")'</automated>
  </verify>
  <done>
    - bin_distance() signature shows `width = 10, cap = 350`
    - log path uses `ifelse(mi < 1, -0.125, log10(mi))` not `log10(1 + mi)`
    - log edges array starts with `-0.25`
    - lower_mi for log uses `dplyr::if_else(lower < 0, 0, 10^lower)`
    - plot_distance_hist() subtitle format string contains "same-ZIP"
    - axis block has `labels = c("<1", scales::label_comma()(ticks))`
    - make_distance_histograms() signature includes `linear_width = 10, linear_cap = 350`
    - Header block contains "Log bins (A1, 2026-09-18)"
    - R parse reports no errors
  </done>
</task>

<task type="auto">
  <name>Task 2: Apply B1-B3 to R/122_encounter_distance.R and D to 154-CONTEXT.md</name>
  <files>R/122_encounter_distance.R, .planning/phases/154-distribution-and-histogram-deliverable/154-CONTEXT.md</files>
  <action>
Apply exactly sections B1, B2, B3 from FIX_histograms.md, then section D.

**B1 — Update the make_distance_histograms() call in SECTION 12.5b.**

Find the block (currently starting at the `# ---- 12.5b` comment):
```r
hist_result <- make_distance_histograms(
  dist     = enc_distance,
  out_dir  = CONFIG$output_dir,
  run_date = RUN_DATE,
  cutoffs  = NULL   # dotted candidate-cutoff lines are a Phase 155 addition (154-CONTEXT)
)
```
Replace with:
```r
hist_result <- make_distance_histograms(
  dist         = enc_distance,
  out_dir      = CONFIG$output_dir,
  run_date     = RUN_DATE,
  cutoffs      = NULL,  # dotted candidate-cutoff lines are a Phase 155 addition (154-CONTEXT)
  linear_width = 10,    # 154-D7: chosen after the 2026-09-18 first run (median 15 mi, p90 196 mi)
  linear_cap   = 350    # 154-D7: keeps the Florida body readable; out-of-state mass goes to "350+"
)
```

**B2 — Update the B_histogram_bins KEY sheet value string.**

Find the string (it is the 4th element of the `key_values` character vector, after
"A_distribution_summary statistics"):
```r
    "level, scale, bin, lower, upper, lower_mi, upper_mi, n, pct — from make_distance_histograms() bind_rows(bins_out)",
```
Replace with:
```r
    "level, scale, bin, lower, upper, lower_mi, upper_mi, n, pct. Linear: 10-mile bins to 350, then [350, Inf). Log: first bin [0,1) mi (includes same-ZIP zeros), then quarter-decade bins on log10(mi); lower/upper are in log10(mi) units for log rows (first bin lower = -0.25), lower_mi/upper_mi are in miles for all rows.",
```

**B3 — Insert long-distance tail tabulation block and update the QC add_styled_sheet() call.**

Immediately BEFORE the line:
```r
# ---- 12.5c Per-patient rds write ----
```
insert the following block verbatim:
```r
# ---- 12.5b-ii Long-distance tail tabulation (>= linear_cap) for AM §4 Observed Issues ----
zip_state_pat <- zipcodeR::zip_code_db %>%
  dplyr::transmute(zipcode = as.character(zipcode), patient_state = state) %>%
  dplyr::distinct(zipcode, .keep_all = TRUE)

tail_rows <- computed_rows %>%
  dplyr::filter(distance_mi >= 350) %>%
  dplyr::left_join(zip_state_pat, by = c("zip5_patient" = "zipcode"))

tail_by_state <- tail_rows %>%
  dplyr::count(patient_state, facility_state, name = "N") %>%
  dplyr::arrange(dplyr::desc(N)) %>%
  dplyr::mutate(Pct_of_tail = round(100 * N / sum(N), 2)) %>%
  dplyr::slice_head(n = 25)

tail_by_patient_zip <- tail_rows %>%
  dplyr::count(zip5_patient, patient_state, name = "N") %>%
  dplyr::arrange(dplyr::desc(N)) %>%
  dplyr::slice_head(n = 20)

message(glue("  tail >= 350 mi: {nrow(tail_rows)} encounters ({round(100 * nrow(tail_rows) / nrow(computed_rows), 2)}% of computed)"))
```

Then update the `add_styled_sheet(wb, "QC", ...)` call. Find:
```r
  extra_tbl   = unmatched_zip9_by_state,
  extra_label = "Unmatched ZIP9 encounters by state (centroid_source == zip5_fallback)"
```
Replace with:
```r
  extra_tbl   = dplyr::bind_rows(
    dplyr::mutate(unmatched_zip9_by_state, table = "unmatched_zip9_by_state", .before = 1),
    dplyr::mutate(tail_by_state,           table = "tail_ge_350mi_by_patient_x_facility_state", .before = 1),
    dplyr::mutate(tail_by_patient_zip,     table = "tail_ge_350mi_top20_patient_zip5", .before = 1)
  ),
  extra_label = "Supplementary tables (see 'table' column): unmatched ZIP9 by state; long-distance tail by state pair; top patient ZIP5s in the tail"
```
If needed, add `dplyr::across(-table, as.character)` inside each mutate to prevent
bind_rows type-mismatch failures. Only add this if the three tables genuinely have
conflicting column types (unmatched_zip9_by_state has STATE/n_unmatched_zip9_encounters;
tail_by_state has patient_state/facility_state/N/Pct_of_tail; tail_by_patient_zip has
zip5_patient/patient_state/N — different schemas, so bind_rows fills missing cols with NA,
no type mismatch expected; do not add across() unless there is a real conflict).

**D — Add 154-D7 entry to 154-CONTEXT.md.**

Open `.planning/phases/154-distribution-and-histogram-deliverable/154-CONTEXT.md`.
Find the `## Implementation Decisions` section. After the last existing decision entry
(154-D6 is the last), append:

```
### Histogram bins after first run (154-D7)
- **154-D7:** Linear: 10-mile bins, 350-mile cap. Log: first bin [0,1) mi, then
  quarter-decade bins on log10(mi) so decade values are bin edges. Chosen 2026-09-18
  after the first HiPerGator run (n = 1,725,592; median 15.1 mi; p90 196.4 mi;
  ~7% of encounters beyond 300 mi). Same-ZIP zero count is stated in the subtitle.
```
  </action>
  <verify>
    <automated>Rscript -e 'invisible(parse("R/122_encounter_distance.R")); cat("parse OK\n")'</automated>
  </verify>
  <done>
    - SECTION 12.5b call includes `linear_width = 10` and `linear_cap = 350`
    - KEY row for B_histogram_bins contains "quarter-decade bins on log10(mi)"
    - `# ---- 12.5b-ii` comment block exists immediately before `# ---- 12.5c`
    - `tail_by_state` and `tail_by_patient_zip` are defined before the QC add_styled_sheet call
    - QC add_styled_sheet extra_tbl uses `dplyr::bind_rows(...)` with three mutated sub-tables
    - extra_label contains "Supplementary tables (see 'table' column)"
    - 154-CONTEXT.md contains "154-D7:" entry under Implementation Decisions
    - R parse reports no errors
  </done>
</task>

<task type="auto">
  <name>Task 3: Apply C1-C4 to test-utils-distance-hist.R and run tests</name>
  <files>tests/testthat/test-utils-distance-hist.R</files>
  <action>
Apply exactly the four test edits from FIX_histograms.md section C.

**C1 — Replace the boundary test.**

Find and replace the entire test block that starts with:
```r
test_that("bin_distance log: value exactly on a 0.25 boundary is counted", {
  b <- bin_distance(c(0, 9, 99), scale = "log")   # log10(10) = 1, log10(100) = 2
  expect_equal(sum(b$n), 3L)
  expect_true(max(b$upper) > 2)
})
```
with:
```r
test_that("bin_distance log: decade values sit on bin edges and are counted", {
  b <- bin_distance(c(0, 0.5, 1, 10, 100), scale = "log")
  expect_equal(sum(b$n), 5L)
  expect_true(all(c(0, 1, 2) %in% b$lower))          # 1, 10, 100 mi are edges
  expect_equal(b$n[b$lower == -0.25], 2L)             # 0 and 0.5 -> first bin
  expect_equal(b$n[b$lower == 0], 1L)                 # 1 mi -> [1, 1.78)
  expect_equal(b$lower_mi[b$lower == -0.25], 0)
  expect_equal(b$upper_mi[b$lower == -0.25], 1)
})
```

**C2 — Update the all-zero test.**

Find within the `"bin_distance: all-zero input lands entirely in the first bin"` test:
```r
  b_log <- bin_distance(rep(0, 7), scale = "log")
  expect_equal(sum(b_log$n), 7L)
```
Replace with:
```r
  b_log <- bin_distance(rep(0, 7), scale = "log")
  expect_equal(sum(b_log$n), 7L)
  expect_equal(b_log$n[1], 7L)                        # all in the [0,1) first bin
  expect_gte(nrow(b_log), 2L)
```
(Keep the two lines above it for the linear case — only the log portion changes.)

**C3 — Replace the negative-input test body.**

Find the test block:
```r
test_that("bin_distance: negative or infinite input is not silently binned", {
  # bin_distance() does not validate; the invariant lives in R/122 SECTION 12.0a.
  # This test documents the contract: NA is dropped, everything else is counted.
  b <- bin_distance(c(-1, 5), scale = "linear")
  expect_equal(sum(b$n), 1L)   # -1 falls outside [0, Inf) and is dropped by cut()
})
```
Replace the entire body (but keep the test_that wrapper and description) with:
```r
test_that("bin_distance: negative or infinite input is not silently binned", {
  expect_error(bin_distance(c(-1, 5), scale = "linear"), "negative")
})
```

**C4 — Append three new tests at the end of the file:**

```r
test_that("bin_distance linear defaults are 10-mile bins to 350", {
  b <- bin_distance(c(5, 355), scale = "linear")
  expect_equal(b$upper[1], 10)
  expect_equal(max(b$lower), 350)
  expect_equal(b$n[is.infinite(b$upper)], 1L)
})

test_that("make_distance_histograms passes linear_width / linear_cap through", {
  tmp <- withr::local_tempdir()
  r <- make_distance_histograms(enc_dist, out_dir = tmp, run_date = "20260918",
                                linear_width = 25, linear_cap = 200)
  lin <- r$bins[r$bins$level == "encounter" & r$bins$scale == "linear", ]
  expect_equal(lin$upper[1], 25)
  expect_equal(max(lin$lower), 200)
})

test_that("plot_distance_hist log axis has a '<1' tick", {
  b <- bin_distance(mi_vec, scale = "log")
  stats <- tibble::tibble(n = length(mi_vec), n_excluded = 0L, median = median(mi_vec),
                          p90 = quantile(mi_vec, 0.9), n_zero = sum(mi_vec == 0))
  p <- plot_distance_hist(b, stats, level = "encounter")
  lbls <- ggplot2::ggplot_build(p)$layout$panel_params[[1]]$x$get_labels()
  expect_true("<1" %in% lbls)
})
```

After all edits, run the test file.
  </action>
  <verify>
    <automated>Rscript -e 'testthat::test_file("tests/testthat/test-utils-distance-hist.R")'</automated>
  </verify>
  <done>
    - Test "bin_distance log: decade values sit on bin edges and are counted" exists and passes
    - Test "bin_distance: all-zero input" now has `expect_equal(b_log$n[1], 7L)` assertion
    - Test "bin_distance: negative or infinite input" body is `expect_error(..., "negative")`
    - Three new tests at end of file (C4) all pass
    - No test failures reported by testthat::test_file()
    - Total test count is the previous count + 3 (from C4 additions)
  </done>
</task>

</tasks>

<verification>
After all three tasks:

1. Parse check both R files:
   ```bash
   Rscript -e 'invisible(parse("R/utils/utils_distance_hist.R")); cat("OK\n")'
   Rscript -e 'invisible(parse("R/122_encounter_distance.R")); cat("OK\n")'
   ```

2. Run full test file — all tests pass:
   ```bash
   Rscript -e 'testthat::test_file("tests/testthat/test-utils-distance-hist.R")'
   ```

3. Spot-check key anchors:
   - `bin_distance` log path: `ifelse(mi < 1, -0.125, log10(mi))` present
   - `edges <- c(-0.25, seq(0, top, by = 0.25))` present
   - `lower_mi = dplyr::if_else(lower < 0, 0, 10^lower)` present (dplyr::if_else not base ifelse)
   - `linear_width = 10, linear_cap = 350` in both make_distance_histograms() signature and R/122 call
   - `tail_by_state` defined before `# ---- 12.5c`
   - `extra_tbl = dplyr::bind_rows(...)` in QC add_styled_sheet call
   - 154-CONTEXT.md contains "154-D7:"
</verification>

<success_criteria>
- `Rscript -e 'invisible(parse("R/utils/utils_distance_hist.R"))'` exits 0
- `Rscript -e 'invisible(parse("R/122_encounter_distance.R"))'` exits 0
- `testthat::test_file("tests/testthat/test-utils-distance-hist.R")` reports 0 failures
- All code changes are strictly within the scope of FIX_histograms.md sections A-D
- No functions outside utils_distance_hist.R were modified
</success_criteria>

<output>
After completion, commit with:
```bash
git add R/utils/utils_distance_hist.R R/122_encounter_distance.R tests/testthat/test-utils-distance-hist.R .planning/phases/154-distribution-and-histogram-deliverable/154-CONTEXT.md
git commit -m "fix(154): apply FIX_histograms.md — log bins, subtitle zero count, linear 10/350 defaults, tail QC table"
```
No SUMMARY.md is needed for a quick task.
</output>
