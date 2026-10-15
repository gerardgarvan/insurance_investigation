---
phase: 184-survivorship-modality-rates-and-distance-modality-interaction
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - R/184_modality_rate_model.R
  - output/modality_rate_model_<YYYYMMDD>.xlsx
  - output/184-MEMO.md
autonomous: false
requirements:
  - MODR-01
  - MODR-02

must_haves:
  truths:
    - "CBC reproduction gate passes: CBC-only Poisson GEE on pinned Phase 179 cohort matches Phase 179 workbook 'Primary: years 2+' OR within 0.005, with exact row count and far/near patient split"
    - "Rate table exists for every modality (restricted to eligible patients), by far × year-period, with suppression applied (counts 1-10 shown as '<11'; rates suppressed when n < 11)"
    - "Annual (primary) and 6-month (sensitivity) period rates both appear in the workbook Rates tab"
    - "Poisson GEE with far + modality + far:modality + year_index_cat + offset(log(person_years)) is fitted; modality-specific RRs and 95% CIs for far vs not-far are reported"
    - "Global Wald test of all far:modality interaction terms is reported (test stat + p-value)"
    - "Pearson chi-sq/df overdispersion diagnostic is computed per modality and appears in Diagnostics tab"
    - "NB sensitivity results appear alongside Poisson in Diagnostics tab"
    - "Adjusted sensitivity (add age_at_anchor + sex) is fitted and results reported"
    - "Workbook output/modality_rate_model_<YYYYMMDD>.xlsx exists with tabs KEY, Rates, Model_Results, Interaction, Diagnostics, QC — in that order, KEY leftmost"
    - "184-MEMO.md is written summarising key findings, cohort pin, and model spec"
    - "Script runs end-to-end without error; QC checks pass"
  artifacts:
    - path: "R/184_modality_rate_model.R"
      provides: "Complete analysis script — all sections 0-10"
      min_lines: 400
    - path: "output/modality_rate_model_<YYYYMMDD>.xlsx"
      provides: "Workbook with all required tabs"
      contains: "KEY, Rates, Model_Results, Interaction, Diagnostics, QC"
    - path: "output/184-MEMO.md"
      provides: "Script-generated narrative memo"
  key_links:
    - from: "R/184_modality_rate_model.R §SECTION 0"
      to: "output/internal/cbc_patient_year_20261015.rds"
      via: "readRDS with env-var override R184_P179_RDS"
      pattern: "R184_P179_RDS|cbc_patient_year_20261015\\.rds"
    - from: "R/184_modality_rate_model.R §SECTION 0"
      to: "R/147 surveillance_modality_patient RDS"
      via: "output/logs/147_verify_last_pass.txt pointer"
      pattern: "147_verify_last_pass\\.txt"
    - from: "R/184_modality_rate_model.R §Task 0"
      to: "Phase 179 workbook"
      via: "exact-label reader, label 'Primary: years 2+'"
      pattern: "Primary: years 2\\+"
    - from: "long-format patient × modality × year frame"
      to: "geepack::geeglm()"
      via: "data arranged by ID + year_index, id = as.integer(ID)"
      pattern: "geeglm.*family.*poisson|geepack"
---

<objective>
Build `R/184_modality_rate_model.R` from scratch as a single self-contained script that:
1. Reproduces the Phase 179 "Primary: years 2+" CBC result as a hard gate (stops on mismatch).
2. Expands the pinned Phase 179 cohort to a long-format patient × modality × follow-up-year frame, restricted per modality eligibility rules from R/147.
3. Produces per-modality surveillance rate tables (MODR-01): events, person-years, rate per patient-year by modality × far × year-period, with HIPAA suppression.
4. Fits a Poisson GEE with a `far × modality` interaction (MODR-02) and reports modality-specific rate ratios, a global Wald test, overdispersion diagnostics, NB sensitivity, and adjusted sensitivity.
5. Writes a single workbook (`output/modality_rate_model_<YYYYMMDD>.xlsx`) and a script-generated memo (`output/184-MEMO.md`).

Purpose: Deliver MODR-01 and MODR-02 requirements for the v3.11 milestone team deliverable.
Output: `R/184_modality_rate_model.R`, workbook, memo.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/STATE.md

<!-- Phase context — locked decisions D-01 through D-22 -->
@.planning/phases/184-survivorship-modality-rates-and-distance-modality-interaction/184-CONTEXT.md

<!-- Prior phase pattern references -->
@R/179_cbc_patient_year.R
@R/183_mice_sensitivity_distance.R
@R/166_survivorship_modality_rates.R
@R/00_config.R

<interfaces>
<!-- Patterns the executor MUST reuse. Extracted from R/179 and R/183 to prevent codebase exploration. -->

From R/179_cbc_patient_year.R:

```r
# Suppression helpers (copy into R/184 §SECTION 0 helpers)
sup <- function(x) {
  x <- as.numeric(x)
  ifelse(is.na(x), NA_character_,
         ifelse(x >= 1 & x <= 10, "<11", format(x, big.mark = ",", trim = TRUE)))
}
show_rate <- function(num, den) {
  if (is.na(num) || is.na(den) || num < 11 || den < 11) return("—")
  round(num / den, 4)   # adapt: return rate per patient-year, not percentage
}

# R/147 pin pointer pattern (§SECTION 1a):
ptr_path <- file.path(CONFIG$output_dir, "logs", "147_verify_last_pass.txt")
ptr_lines <- readLines(ptr_path, warn = FALSE)
ptr_get <- function(key) {
  hit <- grep(paste0("^", key, "\\s*="), ptr_lines, value = TRUE)
  if (length(hit) == 0L) return(NA_character_)
  trimws(sub("^[^=]*=", "", hit[1]))
}
r147_rds <- ptr_get("rds_path")

# GEE helper pattern (§SECTION 5 equivalent in R/179):
# data MUST be arranged by ID then year_index before calling geeglm
data <- dplyr::arrange(data, ID, year_index)
fit <- geepack::geeglm(
  formula  = count ~ far + modality + far:modality + year_index_cat + offset(log(person_years)),
  family   = poisson(link = "log"),
  id       = as.integer(factor(ID)),
  corstr   = CONFIG$distance_gee_corstr,   # "independence" per D-04
  std.err  = "san.se",
  data     = data
)

# Pearson chi-sq/df overdispersion:
phi <- sum(residuals(fit, "pearson")^2) / fit$df.residual

# year_index_cat construction (same as R/179):
data <- data |>
  dplyr::mutate(year_index_cat = factor(year_index))
```

From R/183_mice_sensitivity_distance.R:

```r
# Pinned RDS loading pattern with env-var override:
p179_rds_path <- Sys.getenv("R184_P179_RDS",
  unset = file.path(CONFIG$output_dir, "internal", "cbc_patient_year_20261015.rds"))
stopifnot("Phase 179 pinned RDS not found" = file.exists(p179_rds_path))
py <- readRDS(p179_rds_path)

# Exact-label reader for Phase 179 workbook (memo/workbook tab approach):
p179_xlsx <- list.files(CONFIG$output_dir, "^cbc_patient_year_.*\\.xlsx$", full.names = TRUE)
p179_xlsx <- p179_xlsx[which.max(file.mtime(p179_xlsx))]
wb_data   <- readxl::read_excel(p179_xlsx, sheet = "Model_Results")
# Read OR by matching exact "Primary: years 2+" label in a Label/Window column
gate_row  <- wb_data[wb_data$Label == "Primary: years 2+", ]
stopifnot("Exact label 'Primary: years 2+' not found in Phase 179 workbook" = nrow(gate_row) == 1L)
gate_or   <- gate_row$OR
# Script MUST stop (not warn) if OR mismatch exceeds 0.005

# Memo generation pattern (writeLines to file):
memo_path <- file.path(CONFIG$output_dir, "184-MEMO.md")
memo_lines <- c(
  "# Phase 184 Memo: Survivorship Modality Rates and Distance × Modality Interaction",
  glue::glue("Run date: {RUN_DATE}"),
  ...
)
writeLines(memo_lines, memo_path)
message(glue::glue("Memo written: {memo_path}"))

# KEY tab builder (openxlsx):
wb <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb, "KEY")
# KEY is added FIRST so it appears leftmost
```

From R/166_survivorship_modality_rates.R:

```r
# Modality eligibility: R/147 patient-modality RDS contains per-patient eligibility flags.
# load it, then for each modality restrict to patients where eligible == TRUE (or equiv).
# The column naming follows R/147 output conventions — check names(r147_raw) at runtime.
# Key columns expected: ID, modality (or modality_label), hl_anchor_date,
#   person_years (or follow_up_years), n_dates_post_primary, eligible (logical or 0/1).
```

CONFIG values used in R/184:
```r
CONFIG$far_from_care_cutoff_mi    # 100 (mi) — far threshold
CONFIG$distance_gee_corstr        # "independence" — corstr for GEE (D-04)
CONFIG$output_dir                 # output/
CONFIG$cache$outputs_dir          # output/internal/
```
</interfaces>
</context>

<tasks>

<!-- ============================================================ -->
<!-- TASK 0 — Reproduction gate (hard stop)                       -->
<!-- ============================================================ -->
<task type="auto" tdd="false">
  <name>Task 0: Reproduction gate — CBC-only Poisson GEE vs Phase 179 workbook</name>
  <files>R/184_modality_rate_model.R</files>
  <action>
Create `R/184_modality_rate_model.R` with SECTIONS 0 and 1 (setup + pinned inputs) and implement the Task 0 reproduction gate as the FIRST thing that runs after loading packages and config. The script must stop with a clear error message if the gate fails. Per D-16 (locked).

**SECTION 0 — Setup:**
```r
# ==============================================================================
# 184_modality_rate_model.R -- Survivorship Modality Rates and Distance × Modality Interaction
# ==============================================================================
# Inputs (pinned):
#   R184_P179_RDS  env-var override; default output/internal/cbc_patient_year_20261015.rds
#   R/147 patient-modality RDS via output/logs/147_verify_last_pass.txt
#   Phase 179 workbook (most recent output/cbc_patient_year_*.xlsx)
# Outputs:
#   output/modality_rate_model_<YYYYMMDD>.xlsx
#   output/184-MEMO.md
# Requirements: MODR-01, MODR-02   Decisions: 184-CONTEXT D-01..D-22
# ==============================================================================

source("R/00_config.R")
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(geepack)
  library(MASS); library(openxlsx); library(readxl); library(glue)
})
RUN_DATE <- format(Sys.Date(), "%Y%m%d")
message(glue("==== R/184 modality_rate_model -- RUN DATE {RUN_DATE} ===="))
CUTOFF     <- CONFIG$far_from_care_cutoff_mi
GEE_CORSTR <- CONFIG$distance_gee_corstr   # "independence" per D-04
as_id      <- function(x) as.character(x)
sup <- function(x) {
  x <- as.numeric(x)
  ifelse(is.na(x), NA_character_,
         ifelse(x >= 1 & x <= 10, "<11", format(x, big.mark = ",", trim = TRUE)))
}
rate_if_visible <- function(num, den) {
  ifelse(is.na(num) | is.na(den) | num < 11 | den < 11, NA_real_, num / den)
}
```

**SECTION 1 — Pinned inputs:**
- Load Phase 179 pinned RDS using env-var override `R184_P179_RDS`; default path `output/internal/cbc_patient_year_20261015.rds`. Stop if not found.
- Verify required columns: `ID`, `year_index`, `year_start`, `year_end`, `cbc_year`, `far`, `exposure_missing`, `person_years` (or equivalent). Stop on missing.
- Exclude 614 missing-exposure patients (`exposure_missing == TRUE` or `is.na(far)`). Assert `far` is non-missing after exclusion. Log N excluded.
- Load R/147 patient-modality RDS via `output/logs/147_verify_last_pass.txt` pointer (same pattern as R/179 §1a). Stop if pointer or RDS not found.
- Find most recent Phase 179 workbook: `list.files(CONFIG$output_dir, "^cbc_patient_year_.*\\.xlsx$", full.names=TRUE)`.

**SECTION 2 — Task 0 reproduction gate (D-16):**
- Filter Phase 179 RDS to `year_index >= 2` and `!exposure_missing`.
- Construct `year_index_cat <- factor(year_index)`.
- Arrange by `ID, year_index`.
- Fit Poisson GEE (binary outcome `cbc_year`; family = `binomial(link="logit")` — this is the Phase 179 spec matching D-16, NOT count/Poisson yet):
  ```r
  gate_fit <- geepack::geeglm(
    cbc_year ~ far + year_index_cat,
    family = binomial(link = "logit"),
    id     = as.integer(factor(ID)),
    corstr = GEE_CORSTR,
    std.err = "san.se",
    data   = gate_data
  )
  gate_or_calc <- exp(coef(gate_fit)["farTRUE"])
  ```
- Read Phase 179 workbook Model_Results sheet; find row where label/window column matches EXACTLY "Primary: years 2+". Extract OR. Stop if label not found.
- Assert `abs(gate_or_calc - gate_or_p179) < 0.005`. Stop with informative error if not.
- Assert row count of gate_data matches Phase 179 reported patient-year row count (read from Phase 179 workbook KEY or QC tab; use best available). Log comparison even if assertion is approximate.
- Assert far/near patient split matches Phase 179 counts (report difference; stop only if >5 patients discrepant).
- Log: "REPRODUCTION GATE PASSED: OR={gate_or_calc:.4f} vs P179={gate_or_p179:.4f}, diff={abs(diff):.5f}"
  </action>
  <verify>
    <automated>
      # In R session at repo root:
      # source("R/184_modality_rate_model.R", local=new.env(parent=globalenv()))
      # Must reach "REPRODUCTION GATE PASSED" message without stopping.
      # Check: script file exists and has a "REPRODUCTION GATE PASSED" log statement.
      grep -n "REPRODUCTION GATE PASSED" R/184_modality_rate_model.R
    </automated>
  </verify>
  <done>
    `R/184_modality_rate_model.R` exists. SECTION 0 (setup/helpers), SECTION 1 (pinned inputs), and SECTION 2 (reproduction gate) are fully implemented. When sourced, the script loads inputs and either prints "REPRODUCTION GATE PASSED" or stops with a clear error. No silent pass.
  </done>
</task>

<!-- ============================================================ -->
<!-- TASK 1 — Data preparation: long format patient × modality × year -->
<!-- ============================================================ -->
<task type="auto" tdd="false">
  <name>Task 1: Data preparation — expand to patient × modality × year with eligibility and person-years</name>
  <files>R/184_modality_rate_model.R</files>
  <action>
Add SECTION 3 to `R/184_modality_rate_model.R` immediately after the reproduction gate (SECTION 2). This section builds the analytic long-format frame used by all subsequent sections.

**SECTION 3 — Long-format data construction (D-05, D-06, D-07):**

Step 3a — Build the patient × year base frame from the Phase 179 pinned RDS:
- Start from the Phase 179 RDS after excluding missing-exposure patients.
- Primary: restrict to `year_index >= 2`. Keep `ID`, `year_index`, `year_start`, `year_end`, `far`, `person_years`.
- One row per patient × year (this is already the structure of the Phase 179 RDS).

Step 3b — Load dated modality events from R/166 output:
- Load the most recent `output/internal/survivorship_dated_events_<date>.rds` (ID × modality × event_date, produced by R/166). Use `list.files` + `which.max(file.mtime(...))`.
- If not found, stop with: "R/166 dated events RDS not found — run R/166_survivorship_modality_rates.R first."
- Verify columns: `ID`, `modality` (or `modality_label`), `event_date`. Coerce types.

Step 3c — Load modality eligibility from R/147 patient-modality RDS (already loaded in SECTION 1):
- Extract eligibility per patient per modality. Expect columns `ID`, `modality`, and an eligibility flag (e.g., `eligible`, `modality_eligible`, or similar — check `names(r147_raw)` at runtime and use whichever is present).
- Build a two-column lookup: `ID` × `modality` → `eligible` (logical). Log modality names found.

Step 3d — Cross join patient × year × modality, then restrict by eligibility:
```r
modalities <- unique(eligibility$modality)
# cross: expand each patient-year to all modalities, then inner join eligibility
long_base <- patient_years |>
  tidyr::crossing(modality = modalities) |>
  dplyr::inner_join(eligibility |> dplyr::filter(eligible), by = c("ID", "modality"))
# Result: one row per patient × year × modality, restricted to eligible combinations (D-07)
```

Step 3e — Count distinct modality event dates within each patient-year interval:
```r
# Assign each dated event to its year_index (left-closed, right-open: [year_start, year_end))
dated_events_in_year <- dated_events |>
  dplyr::inner_join(long_base |> dplyr::select(ID, modality, year_index, year_start, year_end),
                    by = c("ID", "modality")) |>
  dplyr::filter(event_date >= year_start, event_date < year_end) |>
  dplyr::distinct(ID, modality, year_index, event_date) |>
  dplyr::count(ID, modality, year_index, name = "count")

long_df <- long_base |>
  dplyr::left_join(dated_events_in_year, by = c("ID", "modality", "year_index")) |>
  dplyr::mutate(
    count        = tidyr::replace_na(count, 0L),
    year_index_cat = factor(year_index),
    modality     = factor(modality, levels = sort(unique(modality))),   # CBC = reference (D-08)
    modality     = relevel(modality, ref = "CBC")
  )
```

Step 3f — Assert no missing values in `count`, `far`, `person_years`, `modality`, `year_index_cat`. Log dimensions of `long_df`.

Step 3g — Log: eligible N per modality (for QC tab later), far/near counts in the expanded frame, total rows.
  </action>
  <verify>
    <automated>
      grep -n "SECTION 3\|long_df\|crossing.*modality\|inner_join.*eligib" R/184_modality_rate_model.R
    </automated>
  </verify>
  <done>
    SECTION 3 exists in `R/184_modality_rate_model.R`. The section produces `long_df` with columns: `ID`, `modality` (factor, CBC reference), `year_index`, `year_index_cat`, `far` (logical), `person_years`, `count` (integer ≥ 0). Eligibility restriction applied per modality per D-07. Missing-exposure patients excluded. Log statements confirm dimensions and N-per-modality.
  </done>
</task>

<!-- ============================================================ -->
<!-- TASK 2 — Rate table (MODR-01)                               -->
<!-- ============================================================ -->
<task type="auto" tdd="false">
  <name>Task 2: Rate table (MODR-01) — events, person-years, rate per patient-year by modality × far × period</name>
  <files>R/184_modality_rate_model.R</files>
  <action>
Add SECTION 4 to `R/184_modality_rate_model.R` to produce the rate table that satisfies MODR-01.

**SECTION 4 — Rate table construction (D-17):**

Step 4a — Annual primary rate table (from `long_df`, years 2+):
```r
rate_annual <- long_df |>
  dplyr::group_by(modality, far) |>
  dplyr::summarise(
    n_eligible   = dplyr::n_distinct(ID),
    n_events     = sum(count),
    person_years = sum(person_years),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    period         = "Annual (primary, years 2+)",
    n_events_disp  = sup(n_events),
    rate_per_py    = rate_if_visible(n_events, person_years),
    rate_disp      = ifelse(is.na(rate_per_py), "—", sprintf("%.4f", rate_per_py))
  )
```

Step 4b — Also compute a by-year breakdown (modality × far × year_index):
```r
rate_by_year <- long_df |>
  dplyr::group_by(modality, far, year_index) |>
  dplyr::summarise(
    n_events     = sum(count),
    person_years = sum(person_years),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    n_events_disp = sup(n_events),
    rate_per_py   = rate_if_visible(n_events, person_years),
    rate_disp     = ifelse(is.na(rate_per_py), "—", sprintf("%.4f", rate_per_py))
  )
```

Step 4c — 6-month sensitivity rate table: Build a parallel long frame restricted to 6-month sub-windows within each annual year_index (first 6 months of the follow-up year, i.e., event_date < year_start + 182 days). Use dated_events already in memory — no re-derivation. Produce `rate_6mo` with same structure as `rate_annual` but `period = "6-month (sensitivity)"`.

Step 4d — Combine annual and 6-month into `rate_table_combined` for the workbook Rates tab.

Step 4e — Suppression audit: compute, per modality, what fraction of cells are suppressed in `rate_annual`. Log a warning for any modality where >50% of cells are suppressed (will also appear in QC tab — D-18).

Store objects: `rate_annual`, `rate_by_year`, `rate_6mo`, `rate_table_combined`, `suppression_audit`.
  </action>
  <verify>
    <automated>
      grep -n "SECTION 4\|rate_annual\|rate_6mo\|rate_table_combined\|suppression_audit" R/184_modality_rate_model.R
    </automated>
  </verify>
  <done>
    SECTION 4 exists. `rate_annual`, `rate_by_year`, `rate_6mo`, and `rate_table_combined` are defined. Suppression (counts 1-10 → "<11"; rates suppressed when n < 11) applied per D-17. 6-month sensitivity uses 182-day sub-window of dated events. Suppression audit computed and logged.
  </done>
</task>

<!-- ============================================================ -->
<!-- TASK 3 — Poisson GEE primary model (MODR-02)               -->
<!-- ============================================================ -->
<task type="auto" tdd="false">
  <name>Task 3: Poisson GEE model (MODR-02) — fit and extract modality-specific RRs</name>
  <files>R/184_modality_rate_model.R</files>
  <action>
Add SECTION 5 to `R/184_modality_rate_model.R` to fit the primary Poisson GEE and extract modality-specific rate ratios for far vs not-far.

**SECTION 5 — Primary Poisson GEE (D-01, D-04, D-05, D-08, D-09, D-10, D-14):**

Step 5a — Fit the primary model:
```r
# MUST arrange by ID then year_index before geeglm (geepack requirement)
gee_data <- dplyr::arrange(long_df, ID, year_index)

fit_primary <- geepack::geeglm(
  count ~ far + modality + far:modality + year_index_cat + offset(log(person_years)),
  family  = poisson(link = "log"),
  id      = as.integer(factor(gee_data$ID)),
  corstr  = GEE_CORSTR,          # "independence" per D-04
  std.err = "san.se",
  data    = gee_data
)
message("Primary Poisson GEE fitted. Convergence: ", fit_primary$geese$error)
stopifnot("Primary GEE did not converge" = fit_primary$geese$error == 0L)
```

Step 5b — Extract modality-specific rate ratios for `far` vs not-far:
- Reference modality = CBC (D-08). For CBC: the `far` main effect gives log-RR for far vs not-far.
- For each non-CBC modality M: log-RR_M = coef["farTRUE"] + coef["farTRUE:modalityM"].
- Compute log-RR, SE (from sandwich variance-covariance matrix), and 95% CI (Wald) for each modality.
- Use `vcov(fit_primary)` to get the sandwich VCov; delta method for linear combinations:
  ```r
  # For CBC: log_rr = coef["farTRUE"], var = vcov["farTRUE","farTRUE"]
  # For modality M: log_rr = coef["farTRUE"] + coef["farTRUE:modalityM"]
  #   var = vcov["farTRUE","farTRUE"] + vcov["farTRUE:modalityM","farTRUE:modalityM"]
  #         + 2*vcov["farTRUE","farTRUE:modalityM"]
  ```
- Build `model_results` data frame: modality, log_RR, SE, RR (exp(log_RR)), CI_lo (exp(log_RR - 1.96*SE)), CI_hi (exp(log_RR + 1.96*SE)), p_value (Wald z-test).

Step 5c — Store `fit_primary` and `model_results`.
  </action>
  <verify>
    <automated>
      grep -n "SECTION 5\|fit_primary\|geeglm.*poisson\|model_results\|farTRUE" R/184_modality_rate_model.R
    </automated>
  </verify>
  <done>
    SECTION 5 exists. `fit_primary` is a fitted `geeglm` Poisson model with the formula per D-10. `model_results` data frame has one row per modality with columns: modality, log_RR, SE, RR, CI_lo, CI_hi, p_value. Delta-method SEs used for non-CBC modalities. Convergence asserted.
  </done>
</task>

<!-- ============================================================ -->
<!-- TASK 4 — Interaction: global Wald test and individual terms -->
<!-- ============================================================ -->
<task type="auto" tdd="false">
  <name>Task 4: Interaction — global Wald test of far:modality terms and individual term table</name>
  <files>R/184_modality_rate_model.R</files>
  <action>
Add SECTION 6 to `R/184_modality_rate_model.R` to compute the global Wald test of the interaction and tabulate individual interaction terms.

**SECTION 6 — Interaction testing (D-15):**

Step 6a — Global Wald test of all `far:modality` interaction terms (D-15):
```r
# Identify all interaction term names
int_terms <- grep("^farTRUE:modality", names(coef(fit_primary)), value = TRUE)
message("Interaction terms (", length(int_terms), "): ", paste(int_terms, collapse = ", "))

# Build contrast matrix for joint Wald test
int_idx   <- which(names(coef(fit_primary)) %in% int_terms)
beta_int  <- coef(fit_primary)[int_idx]
vcov_int  <- vcov(fit_primary)[int_idx, int_idx]
# Wald chi-squared = beta' * solve(vcov) * beta
wald_chi2 <- as.numeric(t(beta_int) %*% solve(vcov_int) %*% beta_int)
wald_df   <- length(int_terms)
wald_p    <- pchisq(wald_chi2, df = wald_df, lower.tail = FALSE)
message(glue("Global Wald test: chi2({wald_df}) = {round(wald_chi2,3)}, p = {formatC(wald_p, digits=4)}"))

global_wald <- data.frame(
  test = "Global Wald: all far:modality terms",
  chi2 = round(wald_chi2, 4),
  df   = wald_df,
  p    = wald_p
)
```

Step 6b — Individual interaction term table:
```r
int_se <- sqrt(diag(vcov(fit_primary))[int_idx])
interaction_terms <- data.frame(
  term      = int_terms,
  log_RR_diff = beta_int,
  SE          = int_se,
  z           = beta_int / int_se,
  p           = 2 * pnorm(-abs(beta_int / int_se)),
  RR_ratio    = exp(beta_int),   # multiplicative difference from CBC far-effect
  CI_lo       = exp(beta_int - 1.96 * int_se),
  CI_hi       = exp(beta_int + 1.96 * int_se)
)
```

Store `global_wald`, `interaction_terms`.
  </action>
  <verify>
    <automated>
      grep -n "SECTION 6\|global_wald\|wald_chi2\|interaction_terms\|far:modality\|farTRUE:modality" R/184_modality_rate_model.R
    </automated>
  </verify>
  <done>
    SECTION 6 exists. `global_wald` data frame has chi2, df, p. `interaction_terms` data frame has one row per non-CBC modality interaction term with log-scale and exponentiated estimates and CIs. Logged to console.
  </done>
</task>

<!-- ============================================================ -->
<!-- TASK 5 — Diagnostics: overdispersion + NB sensitivity       -->
<!-- ============================================================ -->
<task type="auto" tdd="false">
  <name>Task 5: Diagnostics — Pearson chi-sq/df per modality and NB GEE sensitivity</name>
  <files>R/184_modality_rate_model.R</files>
  <action>
Add SECTION 7 to `R/184_modality_rate_model.R` for overdispersion diagnostics and negative-binomial sensitivity.

**SECTION 7 — Diagnostics (D-02, D-03):**

Step 7a — Pearson chi-sq/df per modality (D-02):
Fit a separate Poisson GEE per modality (on the modality-restricted eligible subset from `long_df`) and compute Pearson chi-sq/df for each:
```r
modality_levels <- levels(long_df$modality)
diag_list <- lapply(modality_levels, function(m) {
  sub_df <- dplyr::filter(long_df, modality == m) |>
    dplyr::arrange(ID, year_index)
  tryCatch({
    fit_m <- geepack::geeglm(
      count ~ far + year_index_cat + offset(log(person_years)),
      family  = poisson(link = "log"),
      id      = as.integer(factor(sub_df$ID)),
      corstr  = GEE_CORSTR,
      std.err = "san.se",
      data    = sub_df
    )
    phi <- sum(residuals(fit_m, "pearson")^2) / fit_m$df.residual
    data.frame(modality = m, pearson_phi = round(phi, 3), n_rows = nrow(sub_df),
               converged = fit_m$geese$error == 0L)
  }, error = function(e) {
    message("  Modality ", m, " per-modality GEE failed: ", conditionMessage(e))
    data.frame(modality = m, pearson_phi = NA_real_, n_rows = nrow(sub_df),
               converged = FALSE)
  })
})
overdispersion_diag <- dplyr::bind_rows(diag_list)
message("Overdispersion Pearson phi by modality:")
print(overdispersion_diag)
```

Step 7b — NB sensitivity (D-03):
Fit `MASS::glm.nb()` per modality (patient-level counts pooled, not GEE; note this as a simplification in comments). Collect theta (dispersion), key `far` coefficient and CI.
```r
nb_list <- lapply(modality_levels, function(m) {
  sub_df <- dplyr::filter(long_df, modality == m) |>
    dplyr::arrange(ID, year_index)
  tryCatch({
    fit_nb <- MASS::glm.nb(
      count ~ far + year_index_cat + offset(log(person_years)),
      data = sub_df
    )
    cf <- summary(fit_nb)$coefficients
    ci <- confint(fit_nb, "farTRUE", level = 0.95)
    data.frame(
      modality  = m,
      theta     = fit_nb$theta,
      log_RR_nb = cf["farTRUE", "Estimate"],
      RR_nb     = exp(cf["farTRUE", "Estimate"]),
      CI_lo_nb  = exp(ci[1]),
      CI_hi_nb  = exp(ci[2]),
      p_nb      = cf["farTRUE", "Pr(>|z|)"]
    )
  }, error = function(e) {
    message("  NB failed for modality ", m, ": ", conditionMessage(e))
    data.frame(modality = m, theta = NA_real_, log_RR_nb = NA_real_,
               RR_nb = NA_real_, CI_lo_nb = NA_real_, CI_hi_nb = NA_real_, p_nb = NA_real_)
  })
})
nb_sensitivity <- dplyr::bind_rows(nb_list)
```

Store `overdispersion_diag`, `nb_sensitivity`.
  </action>
  <verify>
    <automated>
      grep -n "SECTION 7\|overdispersion_diag\|nb_sensitivity\|pearson_phi\|glm\.nb\|MASS" R/184_modality_rate_model.R
    </automated>
  </verify>
  <done>
    SECTION 7 exists. `overdispersion_diag` has one row per modality with Pearson phi. `nb_sensitivity` has one row per modality with NB far-effect RR and CI. Both computed with tryCatch so individual modality failures do not stop the script.
  </done>
</task>

<!-- ============================================================ -->
<!-- TASK 6 — Adjusted sensitivity (age + sex)                   -->
<!-- ============================================================ -->
<task type="auto" tdd="false">
  <name>Task 6: Adjusted sensitivity — add age_at_anchor + sex to the Poisson GEE</name>
  <files>R/184_modality_rate_model.R</files>
  <action>
Add SECTION 8 to `R/184_modality_rate_model.R` for the adjusted sensitivity analysis per D-11.

**SECTION 8 — Adjusted sensitivity (D-11):**

Step 8a — Source age_at_anchor and sex:
These variables come from the same source used in R/183 (the R/147 patient-modality RDS typically contains demographics). Check `names(r147_raw)` for `age_at_anchor` and `sex` (or `age`, `gender`). Adapt column names based on what is present, logging which column was used.
```r
demo_cols <- intersect(c("age_at_anchor", "age"), names(r147_raw))
sex_cols  <- intersect(c("sex", "gender"), names(r147_raw))
if (length(demo_cols) == 0 || length(sex_cols) == 0) {
  warning("age or sex not found in R/147 RDS; adjusted sensitivity will not be run")
  adj_skipped <- TRUE
} else {
  adj_skipped <- FALSE
  demo <- r147_raw |>
    dplyr::transmute(
      ID  = as_id(ID),
      age = as.numeric(.data[[demo_cols[1]]]),
      sex = as.character(.data[[sex_cols[1]]])
    ) |>
    dplyr::distinct(ID, .keep_all = TRUE)
  gee_data_adj <- dplyr::left_join(gee_data, demo, by = "ID")
  n_missing_demo <- sum(is.na(gee_data_adj$age) | is.na(gee_data_adj$sex))
  message(glue("  Adjusted sensitivity: {n_missing_demo} rows with missing age or sex (excluded)"))
  gee_data_adj <- dplyr::filter(gee_data_adj, !is.na(age), !is.na(sex))
}
```

Step 8b — Fit adjusted Poisson GEE (only if not skipped):
```r
if (!adj_skipped) {
  fit_adjusted <- geepack::geeglm(
    count ~ far + modality + far:modality + year_index_cat + age + sex +
      offset(log(person_years)),
    family  = poisson(link = "log"),
    id      = as.integer(factor(gee_data_adj$ID)),
    corstr  = GEE_CORSTR,
    std.err = "san.se",
    data    = gee_data_adj
  )
  message("Adjusted GEE convergence: ", fit_adjusted$geese$error)
  # Extract same model_results structure as SECTION 5, store as adj_model_results
  # (reuse the same delta-method block as Task 3, parameterised as a helper function)
}
```

Step 8c — Build `adj_model_results` with same columns as `model_results`. If `adj_skipped`, set `adj_model_results <- NULL` and log a note.
  </action>
  <verify>
    <automated>
      grep -n "SECTION 8\|fit_adjusted\|adj_model_results\|adj_skipped\|age_at_anchor\|age.*sex" R/184_modality_rate_model.R
    </automated>
  </verify>
  <done>
    SECTION 8 exists. Adjusted Poisson GEE fitted with `age + sex` added per D-11. Column-name discovery handles both `age_at_anchor`/`age` and `sex`/`gender`. Graceful skip (with warning) if covariates unavailable. `adj_model_results` is either a data frame matching `model_results` structure or NULL.
  </done>
</task>

<!-- ============================================================ -->
<!-- TASK 7 — 6-month period sensitivity model                   -->
<!-- ============================================================ -->
<task type="auto" tdd="false">
  <name>Task 7: 6-month period sensitivity — refit GEE on 6-month sub-window frame</name>
  <files>R/184_modality_rate_model.R</files>
  <action>
Add SECTION 9 to `R/184_modality_rate_model.R` for the 6-month period sensitivity model.

**SECTION 9 — 6-month sensitivity model:**

Step 9a — The 6-month event counts are already derived in SECTION 4 (Task 2, Step 4c), producing a `long_df_6mo` with count restricted to the first 182 days of each year_index interval. If not already a separate frame, build it here:
```r
# Events in first 182 days of each year-interval
events_6mo <- dated_events |>
  dplyr::inner_join(long_base |> dplyr::select(ID, modality, year_index, year_start, year_end),
                    by = c("ID", "modality")) |>
  dplyr::filter(event_date >= year_start,
                event_date <  year_start + 182) |>
  dplyr::distinct(ID, modality, year_index, event_date) |>
  dplyr::count(ID, modality, year_index, name = "count_6mo")

long_df_6mo <- long_base |>
  dplyr::left_join(events_6mo, by = c("ID", "modality", "year_index")) |>
  dplyr::mutate(
    count_6mo    = tidyr::replace_na(count_6mo, 0L),
    person_years_6mo = pmin(person_years, 0.5),   # cap at 0.5 person-years
    year_index_cat   = factor(year_index),
    modality         = relevel(factor(modality), ref = "CBC")
  ) |>
  dplyr::arrange(ID, year_index)
```

Step 9b — Fit 6-month Poisson GEE (same formula, count_6mo outcome, person_years_6mo offset):
```r
fit_6mo <- geepack::geeglm(
  count_6mo ~ far + modality + far:modality + year_index_cat + offset(log(person_years_6mo)),
  family  = poisson(link = "log"),
  id      = as.integer(factor(long_df_6mo$ID)),
  corstr  = GEE_CORSTR,
  std.err = "san.se",
  data    = long_df_6mo
)
message("6-month sensitivity GEE convergence: ", fit_6mo$geese$error)
```

Step 9c — Extract `model_results_6mo` (same structure as `model_results`). Store alongside primary results.
  </action>
  <verify>
    <automated>
      grep -n "SECTION 9\|fit_6mo\|model_results_6mo\|long_df_6mo\|person_years_6mo\|count_6mo" R/184_modality_rate_model.R
    </automated>
  </verify>
  <done>
    SECTION 9 exists. `long_df_6mo` built using first 182 days of each year-interval; person-years capped at 0.5. `fit_6mo` is a fitted `geeglm` Poisson model. `model_results_6mo` data frame has same columns as `model_results`.
  </done>
</task>

<!-- ============================================================ -->
<!-- TASK 8 — Workbook (all tabs, UF colours, suppression, KEY)  -->
<!-- ============================================================ -->
<task type="auto" tdd="false">
  <name>Task 8: Workbook — assemble all tabs with UF colours, suppression, KEY leftmost</name>
  <files>R/184_modality_rate_model.R</files>
  <action>
Add SECTION 10 to `R/184_modality_rate_model.R` to produce the workbook per D-18 and D-20.

**SECTION 10 — Workbook construction (D-18, D-20):**

Filename: `output/modality_rate_model_<YYYYMMDD>.xlsx`.
Tab order: KEY (leftmost), Rates, Model_Results, Interaction, Diagnostics, QC.

UF colours (from CONFIG or hardcoded as fallback):
```r
uf_blue  <- "#003087"
uf_orange <- "#FA4616"
# Use CONFIG$uf_colours if available, else use above
```

Step 10a — Create workbook and add KEY tab first:
```r
wb <- openxlsx::createWorkbook()
openxlsx::addWorksheet(wb, "KEY")

key_content <- data.frame(
  Field = c(
    "Run date", "Script", "Cohort pin",
    "Exclusions", "Model formula",
    "Family", "Corstr", "Offset",
    "Reference modality", "Reference distance",
    "Primary period", "Sensitivity period",
    "Suppression policy",
    "Modality eligibility",
    "R/147 pin", "R/166 dated events"
  ),
  Value = c(
    RUN_DATE,
    "R/184_modality_rate_model.R",
    basename(p179_rds_path),
    glue("{sum(py$exposure_missing, na.rm=TRUE)} missing-exposure patients excluded"),
    "count ~ far + modality + far:modality + year_index_cat + offset(log(person_years))",
    "Poisson GEE (geepack::geeglm)",
    GEE_CORSTR,
    "log(person_years)",
    "CBC",
    glue("not-far (far = distance > {CUTOFF} mi)"),
    "Annual (years 2+)",
    "6-month sub-window (first 182 days of each year-interval)",
    "Counts 1-10 shown as '<11'; rates suppressed when n < 11",
    "Per R/147 patient-modality eligibility flags (D-07)",
    basename(r147_rds),
    basename(events_rds_path)   # store path from SECTION 3 load
  )
)
openxlsx::writeData(wb, "KEY", key_content)
```

Step 10b — Rates tab: write `rate_table_combined` (annual primary + 6-month sensitivity). Apply header style with UF blue fill. Note: suppression already applied in Task 2 (n_events_disp and rate_disp columns use "<11" / "—").

Step 10c — Model_Results tab: write `model_results` (primary annual) and `model_results_6mo` (6-month sensitivity) and `adj_model_results` (adjusted, or a note if skipped). Label each section clearly.

Step 10d — Interaction tab: write `global_wald` then `interaction_terms`.

Step 10e — Diagnostics tab: write `overdispersion_diag` then `nb_sensitivity`. Add column headers clearly distinguishing Poisson vs NB estimates.

Step 10f — QC tab: write reproduction gate result (gate_or_calc, gate_or_p179, diff, PASS/FAIL), N eligible per modality (from suppression_audit), suppression audit (modalities where >50% cells suppressed flagged).

Step 10g — Save workbook:
```r
wb_path <- file.path(CONFIG$output_dir, glue("modality_rate_model_{RUN_DATE}.xlsx"))
openxlsx::saveWorkbook(wb, wb_path, overwrite = TRUE)
stopifnot("Workbook not written" = file.exists(wb_path))
message(glue("Workbook written: {wb_path}"))
```
  </action>
  <verify>
    <automated>
      grep -n "SECTION 10\|addWorksheet.*KEY\|addWorksheet.*Rates\|addWorksheet.*Model_Results\|addWorksheet.*Interaction\|addWorksheet.*Diagnostics\|addWorksheet.*QC\|saveWorkbook" R/184_modality_rate_model.R
    </automated>
  </verify>
  <done>
    SECTION 10 exists. `openxlsx::createWorkbook()` adds tabs in order: KEY, Rates, Model_Results, Interaction, Diagnostics, QC. UF colour applied to headers. Suppression values written as-is from Task 2 (already formatted). Workbook saved to `output/modality_rate_model_<YYYYMMDD>.xlsx`. Script stops if file not written.
  </done>
</task>

<!-- ============================================================ -->
<!-- TASK 9 — Memo                                               -->
<!-- ============================================================ -->
<task type="auto" tdd="false">
  <name>Task 9: Memo — write 184-MEMO.md summarising findings, cohort pin, and model spec</name>
  <files>R/184_modality_rate_model.R</files>
  <action>
Add SECTION 11 to `R/184_modality_rate_model.R` to generate the memo per D-19 and D-21. Follow the R/183 `writeLines` memo pattern exactly.

**SECTION 11 — Memo generation (D-19, D-21):**

```r
memo_path <- file.path(CONFIG$output_dir, "184-MEMO.md")

# Format helpers
fmt_rr <- function(rr, lo, hi) sprintf("RR=%.2f (95%% CI %.2f–%.2f)", rr, lo, hi)

# CBC far-effect from primary model
cbc_row  <- model_results[model_results$modality == "CBC", ]
cbc_line <- fmt_rr(cbc_row$RR, cbc_row$CI_lo, cbc_row$CI_hi)

memo_lines <- c(
  "# Phase 184 Memo: Survivorship Modality Rates and Distance × Modality Interaction",
  "",
  glue("**Run date:** {RUN_DATE}  "),
  glue("**Script:** R/184_modality_rate_model.R  "),
  glue("**Cohort pin:** {basename(p179_rds_path)}  "),
  glue("**Model:** Poisson GEE, corstr={GEE_CORSTR}, robust sandwich SEs  "),
  "",
  "## Reproduction Gate",
  glue("CBC-only Poisson GEE on pinned Phase 179 cohort (years 2+):  "),
  glue("  Calculated OR = {round(gate_or_calc, 4)}, Phase 179 workbook OR = {round(gate_or_p179, 4)}, diff = {round(abs(gate_or_calc - gate_or_p179), 5)}.  "),
  "  Gate: **PASSED**",
  "",
  "## Cohort",
  glue("Phase 179 RDS: {nrow(py)} patient-year rows before exclusion.  "),
  glue("{sum(py$exposure_missing, na.rm=TRUE)} missing-exposure patients excluded.  "),
  glue("Primary analysis (years 2+): {nrow(gee_data)} patient-modality-year rows across {length(modality_levels)} modalities."),
  "",
  "## Model Formula",
  "count ~ far + modality + far:modality + year_index_cat + offset(log(person_years))",
  "",
  "## Key Results",
  glue("**CBC (reference modality):** {cbc_line}"),
  # Add one line per non-CBC modality
  unlist(lapply(modality_levels[modality_levels != "CBC"], function(m) {
    r <- model_results[model_results$modality == m, ]
    if (nrow(r) == 0) return(glue("**{m}:** (not estimated)"))
    glue("**{m}:** {fmt_rr(r$RR, r$CI_lo, r$CI_hi)}")
  })),
  "",
  "## Global Wald Test (far:modality interaction)",
  glue("chi2({global_wald$df}) = {round(global_wald$chi2,3)}, p = {formatC(global_wald$p, digits=4, format='f')}"),
  "",
  "## Overdispersion (Pearson phi, primary Poisson GEE per modality)",
  paste(apply(overdispersion_diag, 1, function(r) glue("  {r['modality']}: phi={r['pearson_phi']}")), collapse="\n"),
  "",
  "## Adjusted Sensitivity (age + sex)",
  if (isTRUE(adj_skipped)) "Not run (age or sex not available in R/147 RDS)." else
    paste(apply(adj_model_results, 1, function(r) glue("  {r['modality']}: RR={round(as.numeric(r['RR']),2)}")), collapse="\n"),
  "",
  glue("**Workbook:** {basename(wb_path)}")
)

writeLines(memo_lines, memo_path)
stopifnot("Memo not written" = file.exists(memo_path))
message(glue("Memo written: {memo_path}"))
```
  </action>
  <verify>
    <automated>
      grep -n "SECTION 11\|writeLines.*memo\|184-MEMO\|memo_path" R/184_modality_rate_model.R
    </automated>
  </verify>
  <done>
    SECTION 11 exists. `writeLines` writes `output/184-MEMO.md`. Memo includes run date, cohort pin, model formula, reproduction gate result, per-modality RRs, global Wald test, overdispersion summary, adjusted sensitivity note, and workbook filename. Script stops if file not written.
  </done>
</task>

<!-- ============================================================ -->
<!-- TASK 10 — Smoke test                                        -->
<!-- ============================================================ -->
<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 10: Smoke test — run end-to-end, verify outputs and QC checks</name>
  <what-built>
    Complete `R/184_modality_rate_model.R` with all 12 sections (SECTIONS 0-11):
    - SECTION 0: Setup, helpers, constants
    - SECTION 1: Pinned input loading (Phase 179 RDS, R/147 RDS, Phase 179 workbook)
    - SECTION 2: Reproduction gate (CBC GEE vs Phase 179 label "Primary: years 2+")
    - SECTION 3: Long-format data construction (patient × modality × year, eligibility-restricted)
    - SECTION 4: Rate table (annual primary + 6-month sensitivity, suppression)
    - SECTION 5: Primary Poisson GEE (far × modality interaction, modality-specific RRs)
    - SECTION 6: Global Wald test + individual interaction terms
    - SECTION 7: Diagnostics (Pearson phi per modality, NB sensitivity)
    - SECTION 8: Adjusted sensitivity (age + sex)
    - SECTION 9: 6-month period sensitivity GEE
    - SECTION 10: Workbook (KEY, Rates, Model_Results, Interaction, Diagnostics, QC)
    - SECTION 11: Memo (184-MEMO.md)
  </what-built>
  <how-to-verify>
    **Run on HiPerGator (interactive R session at repo root):**

    ```r
    module load R/4.4.2
    R
    source("R/184_modality_rate_model.R", local = new.env(parent = globalenv()))
    ```

    **Expected console output (in order):**
    1. `==== R/184 modality_rate_model -- RUN DATE <date> ====`
    2. `R/147 anchor RDS (verified pointer): ...`
    3. `REPRODUCTION GATE PASSED: OR=... vs P179=..., diff=...` (NOT an error stop)
    4. Per-modality eligibility log lines
    5. `Primary Poisson GEE fitted. Convergence: 0`
    6. `Global Wald test: chi2(...) = ..., p = ...`
    7. `Workbook written: output/modality_rate_model_<YYYYMMDD>.xlsx`
    8. `Memo written: output/184-MEMO.md`

    **File checks:**
    ```r
    file.exists("output/modality_rate_model_<YYYYMMDD>.xlsx")  # TRUE
    file.exists("output/184-MEMO.md")               # TRUE
    readxl::excel_sheets("output/modality_rate_model_<YYYYMMDD>.xlsx")
    # Must be: "KEY" "Rates" "Model_Results" "Interaction" "Diagnostics" "QC"
    ```

    **QC checks inside the workbook:**
    - KEY tab: run date, cohort pin file name, model formula visible
    - QC tab: reproduction gate row shows "PASS" (or diff < 0.005)
    - Rates tab: counts in 1-10 range shown as "<11"; rates suppressed (shown as —) for those rows
    - Model_Results tab: one row per modality; RR, CI_lo, CI_hi all numeric and positive
    - Interaction tab: global Wald test row present; individual far:modality rows present
    - Diagnostics tab: Pearson phi column present; NB RR column present

    **If any section errors:** paste the R error and traceback here.
  </how-to-verify>
  <action>Source R/184_modality_rate_model.R in an interactive R session on HiPerGator and verify all console output and output files per the how-to-verify steps below.</action>
  <files>output/modality_rate_model_<YYYYMMDD>.xlsx, output/184-MEMO.md</files>
  <verify><automated>file.exists(list.files("output", "modality_rate_model.*.xlsx", full.names=TRUE)[1])</automated></verify>
  <done>Script runs end-to-end; workbook has 6 tabs in order KEY/Rates/Model_Results/Interaction/Diagnostics/QC; memo written; reproduction gate PASSED; user types "approved".</done>
  <resume-signal>
    Type "approved" if all checks pass. Or describe which checks failed and paste any error output.
  </resume-signal>
</task>

</tasks>

<verification>
After Task 10 smoke-test approval:

1. Script runs end-to-end without stopping on errors.
2. Reproduction gate produces "PASSED" message with diff < 0.005.
3. Workbook exists at `output/modality_rate_model_<YYYYMMDD>.xlsx` with exactly 6 tabs in order: KEY, Rates, Model_Results, Interaction, Diagnostics, QC.
4. Rates tab has annual primary and 6-month sensitivity rows; counts 1-10 suppressed; rates suppressed when n < 11.
5. Model_Results tab has one row per modality with positive numeric RR, CI_lo, CI_hi.
6. Interaction tab has global Wald chi2, df, p — and one row per non-CBC interaction term.
7. Diagnostics tab has Pearson phi per modality and NB sensitivity RRs.
8. Memo file `output/184-MEMO.md` exists and contains model formula, reproduction gate result, per-modality RRs, global Wald test result.
</verification>

<success_criteria>
MODR-01 met: Per-modality surveillance rate table (annual primary + 6-month sensitivity) exists in the workbook Rates tab, restricted to eligible patients per R/147, with HIPAA suppression applied.

MODR-02 met: Fitted Poisson GEE with `far × modality` interaction is reported in Model_Results and Interaction tabs with modality-specific rate ratios, 95% CIs, and global Wald test. Overdispersion check and NB sensitivity in Diagnostics tab.

Reproduction gate passed: CBC-only GEE OR matches Phase 179 workbook "Primary: years 2+" label within 0.005.
</success_criteria>

<output>
After Task 10 is approved, create `.planning/phases/184-survivorship-modality-rates-and-distance-modality-interaction/184-01-SUMMARY.md` with:
- Files written (R/184_modality_rate_model.R, workbook path, memo path)
- Reproduction gate result (OR diff)
- Model convergence status
- Global Wald test result
- Any modalities with convergence failures or heavy suppression
- Decisions implemented (D-01 through D-22) and any deviations
</output>
