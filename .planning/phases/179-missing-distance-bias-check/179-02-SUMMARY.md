---
phase: 179-cbc-patient-year
plan: "02"
subsystem: analysis
tags: [patient-year, cbc, distance, gee, workbook, phase-165-companion]
dependency_graph:
  requires: [R/179 plan-01 RDS, R/122 enc_distance, R/147 anchors, utils_distance_cbc.R]
  provides: [output/cbc_patient_year_<date>.xlsx, Sections 4-7 of R/179_cbc_patient_year.R]
  affects: [Phase 180 missing-exposure bias check, R/165 KEY relabel, R/39 orchestration]
tech_stack:
  added: []
  patterns: [geepack GEE logistic, withCallingHandlers warning capture, openxlsx UF-branded workbook]
key_files:
  created: []
  modified:
    - R/179_cbc_patient_year.R
    - R/165_distance_cbc_association.R
    - R/39_run_all_investigations.R
    - R/SCRIPT_INDEX.md
decisions:
  - "naive_or_se() returns list(log_or, se, haldane); fallback matrix constructed with as.numeric(table(...))"
  - "geepack robust SE column is Std.err (verified against utils_distance_cbc.R docs)"
  - "Phase 165 OR read from distance_cbc_association_20261008.xlsx at runtime; fallback text if absent"
  - "suppress_2x2() local helper mirrors R/165 complementary-suppression logic"
metrics:
  duration: "~20 min"
  completed: "2026-10-13"
  tasks: 3
  files: 4
---

# Phase 179 Plan 02: GEE Models, Workbook, Downstream Edits — Summary

**One-liner:** Sections 4-7 appended to R/179 adding exposure descriptives, four GEE fits with
geepack robust SE and labelled fallback, a four-sheet UF-branded workbook, and Phase 165 companion
framing; D-14 relabel added to R/165 KEY; R/179 registered in R/39 and SCRIPT_INDEX.

---

## What Was Implemented

### Task 1 — Sections 4-5 (R/179_cbc_patient_year.R)

**Section 4 — Subsets and descriptives:**
- `py_all`, `py_primary` (years 2+), `py_yr1` built from `py_final` with `year_index_cat` factor
- **4a** Patient-level exposure distribution: `quantile()` at P5/P10/P25/P50/P75/P90/P95;
  n far / not far / missing via `suppress_display()` (D-10)
- **4b** Per-year index table: patient-years far/not-far, CBC counts, rates (shown only when
  numerator AND denominator ≥ 11 else "—"), crude OR via `naive_or_se()`
- **4c** Year 1 2×2 (far × cbc_year) with `suppress_2x2()` local helper; interior cells and
  margins suppressed per complementary-suppression logic; labeled "descriptive only, not in model"

**Section 5 — GEE models (D-11, D-12):**
- `run_gee()` function: `dplyr::arrange(ID, year_index)` before fit; `droplevels(year_index_cat)`;
  `withCallingHandlers()` captures warnings; geepack robust SE via `ct_coef["x", "Std.err"]`
- Fallback: on GEE error only, crude OR via `naive_or_se(matrix(as.numeric(table(...)), 2))`;
  labelled "CRUDE FALLBACK (GEE error)" — not silent
- Four fits: Primary (years 2+), Secondary (all years), Sensitivity per-year exposure (D-09),
  Sensitivity broad outcome (D-06)
- Per-year sensitivity: patient-years and patients dropped vs primary are logged

### Task 2 — Sections 6-7 (R/179_cbc_patient_year.R)

**Section 6 — Workbook** (`output/cbc_patient_year_<RUN_DATE>.xlsx`):
- Sheets in order: KEY, Descriptives, Per_Year, Model_Results
- UF styles: header `#0021A5` white bold; section/fallback rows `#FA4616`
- **KEY**: companion framing ("Companion to Phase 165 (encounter-level: CBC drawn during the
  encounter). Which analysis is primary is pending team decision (D-15, with D-165-01)");
  all inputs pinned; primary/secondary/sensitivity ORs; Phase 165 ORs read at runtime from
  `distance_cbc_association_20261008.xlsx`; fallback text "see Phase 165 workbook" if absent
- **Descriptives**: 4a exposure quantiles then 4c Year 1 2×2 with section headers
- **Per_Year**: 4b per-year table
- **Model_Results**: one row per fit; orange fill on fallback rows

**Section 7 — Console summary**: paths, primary OR/CI/method, all four results, Phase 165 text.

### Task 3 — Downstream edits

**R/165 KEY (D-14):** After the existing "Analysis" row, added:
```r
c("Analysis level", "Encounter-level: CBC drawn during the encounter"),
c("Patient-year analysis", "Phase 179 (R/179_cbc_patient_year.R): CBC within each follow-up year; primary choice pending (D-15)"),
```
Takes effect on the next R/165 run; no existing workbook edited by hand.

**R/39 `investigation_scripts` (D-19):** `"R/179_cbc_patient_year.R"` added after R/177 entry;
trailing comma added to R/177 line to keep vector valid.

**SCRIPT_INDEX (D-19):** One-off row added after R/177; post-renumber count updated 27 → 28;
total updated 115 → 116.

---

## Deviations from Plan

None. Plan executed exactly as written.

**Notes on implementation choices:**
- `naive_or_se()` returns `list(log_or, se, haldane)` — the `se` field name was confirmed
  from `utils_distance_cbc.R` line 82. The fallback matrix uses `as.numeric(table(...))` with
  `nrow = 2` exactly as specified in the plan pseudocode.
- `suppress_2x2()` is a local helper (not in utils) because it combines interior and margin
  suppression logic that is specific to the 2×2 Year 1 display — consistent with how R/165
  handles its own per-window 2×2 tables.
- `readxl::read_excel()` is used to pull Phase 165 ORs; it is already in the project renv.

---

## Verification Grep Output

```
grep -n "Std.err|arrange(ID|droplevels|withCallingHandlers|naive_or_se" R/179_cbc_patient_year.R | head -20

55:# build_cbc_events(), suppress_small_vec(), suppress_display(), naive_or_se() available.
635:# Patient-years far / not far, CBC rate in each, crude OR (naive_or_se).
657:  nb <- tryCatch(naive_or_se(ct), error = function(e) list(log_or = NA_real_, se = NA_real_, haldane = NA))
720:    dplyr::arrange(ID, year_index) |>
722:      year_index_cat = droplevels(year_index_cat),
729:    withCallingHandlers(
753:    # Fallback: crude OR via naive_or_se (labelled, not silent; D-13)
758:    nb <- naive_or_se(ct_fb)
771:  se <- ct_coef["x", "Std.err"]    # geepack robust SE column (D-11)
```

```
grep -n "Companion to Phase 165|Patient-year analysis|primary choice pending" \
  R/165_distance_cbc_association.R R/179_cbc_patient_year.R | head -10

R/165_distance_cbc_association.R:614: c("Patient-year analysis", "Phase 179 (...): primary choice pending (D-15)"),
R/179_cbc_patient_year.R:872: c("Companion to Phase 165",
R/179_cbc_patient_year.R:873:   paste0("Companion to Phase 165 (encounter-level: CBC drawn during the encounter). ",
```

```
grep -n "R/179_cbc_patient_year" R/39_run_all_investigations.R R/SCRIPT_INDEX.md | head -10

R/39_run_all_investigations.R:245: "R/179_cbc_patient_year.R"  # CBC within each follow-up year ...
R/SCRIPT_INDEX.md:176: | `R/179_cbc_patient_year.R` | Patient-year re-specification ... | 179 |
```

---

## Must-Haves Sign-Off

| Must-have | Status |
|-----------|--------|
| GEE uses geepack's robust SE column `Std.err`; data sorted by ID (then year_index) before fit; unused factor levels dropped | SATISFIED — line 771 `ct_coef["x", "Std.err"]`; `dplyr::arrange(ID, year_index)` at line 720; `droplevels(year_index_cat)` at line 722 |
| Fallback to crude OR happens only on a real fitting error and is labelled; warnings captured and reported | SATISFIED — fallback inside `if (inherits(fit, "error"))` only; label "CRUDE FALLBACK (GEE error)"; `withCallingHandlers()` captures all warnings into `warns` |
| KEY calls Phase 179 a companion to Phase 165 (primary choice pending, D-15) and shows Phase 165's ORs beside Phase 179's | SATISFIED — "Companion to Phase 165" row in KEY; Phase 165 ORs read at runtime from workbook; fallback to "see Phase 165 workbook" if not found |
| Counts 1-10 shown as `<11`; percentages only when numerator and denominator ≥ 11; distance quantiles 5th-95th only | SATISFIED — `suppress_display()` throughout; `show_rate()` helper gates on num AND denom ≥ 11; quantiles at `c(0.05,0.10,0.25,0.50,0.75,0.90,0.95)` only |
| Phase closes only after an interactive HiPerGator run and review | PENDING — Task 4 checkpoint not yet completed |

---

## Known Stubs

None. All columns come from real data sources loaded in Sections 0-3.

## Open Item

Task 4 (HiPerGator interactive run) is a `checkpoint:human-action` gate. Phase close-out
(Task 5: SUMMARY update with actual ORs, STATE.md D-15 item) is deferred until the run output
is reviewed.

## Self-Check

- `R/179_cbc_patient_year.R` modified, committed at `59d9a96`
- `R/165_distance_cbc_association.R`, `R/39_run_all_investigations.R`, `R/SCRIPT_INDEX.md`
  modified, committed at `8333261`
- All verification greps confirmed above
- No `Std. Error` (with space) found in R/179; only `Std.err` (geepack column)
- "Supersedes" not present in R/179 KEY rows
