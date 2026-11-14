---
phase: quick-261114-mch
plan: 01
subsystem: gantt-episodes-180
tags: [abvd, bv-avd, nivo-avd, date-level-relabel, phase-201b]
key-files:
  modified:
    - R/00_config.R
    - R/142_gantt_180_export.R
    - R/88_smoke_test_comprehensive.R
decisions: []
metrics:
  completed: 2026-11-14
  tasks: 3
  files: 3
---

# Quick Task 261114-mch: Fix Detection of BV+AVD and Nivo+AVD

**One-liner:** Date-level admin-date concurrency relabel in R/142 Section 4C4 reclassifies AVD episodes concurrent with brentuximab or nivolumab administration as BV+AVD or Nivo+AVD using a +/-7-day window.

## What Was Done

### Task 1 — R/00_config.R: ABVD_CONCURRENT_WINDOW_DAYS constant (commit ba0da39)

Added after `ABVD_EXCLUDING_DRUGS`:

```r
ABVD_CONCURRENT_WINDOW_DAYS <- 7L
```

Comment cites Phase 201b and explains the +/- window semantics. No other ABVD_* constants changed.

### Task 2 — R/142 Section 4C4: date-level relabel block (commit e191bc6)

Inserted between the `classify_abvd_episode()` call (drug-name pass) and the `episodes_export |> dplyr::mutate(abvd_class = ...)` block.

**Logic:**

1. `immuno_admin`: filter `detail` to Immunotherapy rows with `^brentuximab` or `^nivolumab` drug_name prefix; keep `patient_id`, `treatment_date`, `bv`, `nivo`.
2. `chemo_span`: min/max `treatment_date` per `(patient_id, episode_number)` from Chemotherapy detail rows.
3. `conc`: inner-join `chemo_span` to `immuno_admin` on `patient_id`; filter admin date within `[chemo_first - 7, chemo_last + 7]`; summarise `conc_bv`/`conc_nivo` per episode.
4. `n_bv_span_not_admin`: span-overlap count — Immunotherapy episode spans from `episodes` that overlap the chemo episode's start/stop but have no admin-date concurrency (sequential use, not same regimen).
5. Relabel precedence (applied to the pre-mutate `abvd_class` vector):
   - AVD + conc_bv → `"BV+AVD"` (brentuximab wins over nivolumab)
   - AVD + conc_nivo (and not conc_bv) → `"Nivo+AVD"`
   - ABVD or ABVD_PLUS + conc_bv or conc_nivo → `"ABVD_PLUS"`
6. `abvd_episode` definition unchanged: `abvd_class %in% c("ABVD", "AVD", "JCODE_ABVD")` — BV+AVD and Nivo+AVD are excluded.
7. `ever_abvd` and `ever_abvd_plus` recomputed post-relabel from the updated `abvd_class` (no logic change needed).

**D-08 QC block extended:**

- Pre-relabel counts: ABVD / AVD / ABVD_PLUS episode counts (from `abvd_class_pre` snapshot).
- Post-relabel counts: all 6 classes including BV+AVD and Nivo+AVD (episodes + distinct patients).
- `n_relabel_bv`, `n_relabel_nivo`, `n_relabel_plus`: per-drug relabel episode counts.
- `n_bv_span_not_admin`: sequential-use BV episodes (span overlap, no admin-date concurrency).

**Expected output from HiPerGator run (not yet executed — awaiting checkpoint):**

Per the plan note, approximately 252 AVD episodes / 230 patients overlap brentuximab and ~46 / 43 overlap nivolumab at the span level; the admin-date window relabels a subset of these.

### Task 3 — R/88 Section 15bd updates (commit a63dc33)

- **[d3] valid_cls** updated to `c("ABVD", "AVD", "JCODE_ABVD", "ABVD_PLUS", "BV+AVD", "Nivo+AVD", "")`.
- **[a4] and [a5c] comments** clarified: `classify_abvd_episode()` correctly returns NA for BV+AVD drug_name tokens (excluding-drug guard); BV+AVD/Nivo+AVD relabelling is a date-level R/142 step, not a function output. Test expectations unchanged.
- **[d5]** new check: BV+AVD rows have `abvd_episode == "FALSE"`.
- **[d6]** new check: Nivo+AVD rows have `abvd_episode == "FALSE"`.
- **[PRE201B]** regression: asserts the first 26 column names of `gantt_episodes_180.csv` match the pre-Phase-201b schema. Skips (via `p201_skip_fn`) when the file is absent. The 26-name vector is hard-coded from the known Phase 201 schema.
- Skip entries for [d5], [d6], [PRE201B] added to the file-absent branch.
- **15bb [c2] and 15bc [c1]** already assert 32 columns (updated in prior quick task 261114-m8m); confirmed unchanged.

## Parse Status

| File | Status |
|------|--------|
| R/00_config.R | PASS |
| R/142_gantt_180_export.R | PASS |
| R/88_smoke_test_comprehensive.R | PASS |

## Deviations from Plan

None — plan executed exactly as written. Task 4 (HiPerGator checkpoint) is excluded per execution constraints and remains for the user to run interactively.

## Known Stubs

None. The relabel logic is complete; before/after QC counts in D-08 will populate when R/142 is run on HiPerGator.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | ba0da39 | feat: add ABVD_CONCURRENT_WINDOW_DAYS = 7L to R/00_config.R |
| 2 | e191bc6 | feat: R/142 Section 4C4 date-level BV+AVD / Nivo+AVD relabel |
| 3 | a63dc33 | feat: R/88 15bd — BV+AVD/Nivo+AVD value set, [d5]/[d6], PRE201B regression |
