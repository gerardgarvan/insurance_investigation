---
phase: quick-261114-mch
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - R/00_config.R
  - R/142_gantt_180_export.R
  - R/88_smoke_test_comprehensive.R
autonomous: false
requirements: [ABVD-FLAG-201B]
must_haves:
  truths:
    - "abvd_class value set includes BV+AVD and Nivo+AVD; AVD episodes concurrent with a brentuximab admin date are relabelled BV+AVD and with nivolumab are relabelled Nivo+AVD"
    - "ABVD/ABVD_PLUS episodes concurrent with brentuximab or nivolumab admin dates become ABVD_PLUS with the drug recorded among added agents"
    - "Concurrency is date-level using the 180-day detail rows (admin dates), not episode spans: within [first chemo admin date - 7, last chemo admin date + 7]"
    - "ABVD_CONCURRENT_WINDOW_DAYS = 7 is a config constant"
    - "abvd_episode = abvd_class %in% c('ABVD','AVD') plus the JCODE path, AFTER the relabel; ever_abvd and ever_abvd_plus recomputed from abvd_class post-relabel"
    - "R/88 15bd [d3] value set includes BV+AVD and Nivo+AVD; [a4]/[a5c] expectations updated; 15bb [c2] and 15bc [c1] assert 32 columns; PRE201B regression on columns 1-26 confirmed"
  artifacts:
    - path: "R/142_gantt_180_export.R"
      provides: "Section 4C4 date-level BV/Nivo relabel step before abvd_episode/ever_abvd/ever_abvd_plus derivation"
      contains: "ABVD_CONCURRENT_WINDOW_DAYS"
    - path: "R/00_config.R"
      provides: "ABVD_CONCURRENT_WINDOW_DAYS constant"
    - path: "R/88_smoke_test_comprehensive.R"
      provides: "Updated 15bd value-set / [a4]/[a5c], 15bb/15bc 32-col, PRE201B regression"
---

<objective>
BV+AVD and Nivo+AVD are currently mislabelled as plain AVD because brentuximab and nivolumab are classified as Immunotherapy and never appear in Chemotherapy `drug_names`. Detect them by cross-referencing immunotherapy administration dates against the concurrent chemo episode's administration-date span, and relabel `abvd_class` accordingly.

Purpose: `abvd_class` must distinguish BV+AVD / Nivo+AVD regimens from true AVD so downstream treatment analyses are correct.
Output: Updated Section 4C4 in R/142 (date-level relabel), a config window constant, and updated R/88 checks.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
</execution_context>

<context>
@CLAUDE.md
@R/142_gantt_180_export.R  (Section 2 loads `detail`; Section 4C4 at line ~887 does drug-name classification; detail has patient_id, treatment_type, treatment_date, drug_name, episode_number, episode_start, episode_stop)
@R/00_config.R  (ABVD_* constants at line ~895; BRENTUXIMAB_DRUG at 854)
@R/utils/utils_cancer.R  (classify_abvd_episode at line 160 — drug-name only; keep as-is, relabel happens in R/142 with date detail)
@R/88_smoke_test_comprehensive.R  (15bb [c2] line ~7528; 15bc [c1] line ~7678; 15bd [a4] 7921, [a5c] 7938, [d3] 7011/8011)

<interfaces>
From R/142 Section 2, the `detail` data frame (the 180-day detail rows, NOT episode spans) has, before any pseudo-rows are added:
  patient_id, treatment_type, treatment_date (Date), triggering_code, ENCOUNTERID,
  drug_name, episode_number, episode_start, episode_stop

`episodes_export` (Chemotherapy rows) carries: patient_id, treatment_type, episode_number,
  episode_start, episode_stop, drug_names (semicolon canonical), regimen_label, and after 4C4:
  abvd_class, abvd_episode, ever_abvd, ever_abvd_plus.

Immunotherapy admin dates for a drug: filter `detail` to treatment_type == "Immunotherapy"
and drug family prefix (^brentuximab / ^nivolumab) on `drug_name` (canonical), take `treatment_date`.

A chemo episode's admin-date span: for the (patient_id, episode_number) of each Chemotherapy
row, the min/max `treatment_date` of its `detail` rows where treatment_type == "Chemotherapy".
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add ABVD_CONCURRENT_WINDOW_DAYS config constant</name>
  <files>R/00_config.R</files>
  <action>
In R/00_config.R, next to the ABVD_* constants (after line ~897, after `ABVD_EXCLUDING_DRUGS`), add with a `# Phase 201b` comment:

```r
# Phase 201b: date-level concurrency window for detecting BV+AVD / Nivo+AVD.
# A brentuximab/nivolumab administration date within +/- this many days of a chemo
# episode's administration-date span counts as concurrent (same regimen, not sequential).
ABVD_CONCURRENT_WINDOW_DAYS <- 7L
```

Do not change the existing ABVD_COMPONENTS / AVD_COMPONENTS / ABVD_EXCLUDING_DRUGS lines.
  </action>
  <verify>
    <automated>tools/rcheck.sh parse R/00_config.R</automated>
  </verify>
  <done>ABVD_CONCURRENT_WINDOW_DAYS = 7L defined; R/00_config.R parses.</done>
</task>

<task type="auto">
  <name>Task 2: R/142 Section 4C4 — date-level BV/Nivo relabel before flag derivation</name>
  <files>R/142_gantt_180_export.R</files>
  <action>
Keep the existing `classify_abvd_episode()` call (line ~892) that produces the initial drug-name-based `abvd_class` and the NA-on-non-Chemotherapy line (line ~893). The initial `abvd_class` already yields NA for BV+AVD / Nivo+AVD when the excluding drug happens to appear in `drug_names` — but the real cases have the excluding drug on a separate Immunotherapy episode, so these stay "AVD" / "ABVD" / "ABVD_PLUS" after the drug-name pass. Insert the date-level relabel AFTER line ~893 and BEFORE the `episodes_export <- episodes_export |> dplyr::mutate(abvd_class = abvd_class, ...)` block at line ~894.

Build the relabel using the `detail` data frame loaded in Section 2 (date-level, admin dates). Reference ABVD_CONCURRENT_WINDOW_DAYS from config and the ^brentuximab / ^nivolumab prefixes.

Steps (write as a clearly commented block):

1. Immunotherapy admin dates per patient per drug family from `detail`:
```r
immuno_admin <- detail |>
  dplyr::filter(treatment_type == "Immunotherapy", !is.na(treatment_date)) |>
  dplyr::mutate(
    bv   = grepl("^brentuximab", drug_name, ignore.case = TRUE),
    nivo = grepl("^nivolumab",   drug_name, ignore.case = TRUE)
  ) |>
  dplyr::filter(bv | nivo) |>
  dplyr::select(patient_id, treatment_date, bv, nivo)
```

2. Chemo episode admin-date span per (patient_id, episode_number) from `detail` Chemotherapy rows:
```r
chemo_span <- detail |>
  dplyr::filter(treatment_type == "Chemotherapy", !is.na(treatment_date)) |>
  dplyr::group_by(patient_id, episode_number) |>
  dplyr::summarise(
    chemo_first = min(treatment_date),
    chemo_last  = max(treatment_date),
    .groups = "drop"
  )
```

3. For each chemo episode, detect concurrency by joining immuno_admin to chemo_span on patient_id and testing the window (this is an interval membership, so join by patient then filter):
```r
win <- ABVD_CONCURRENT_WINDOW_DAYS
conc <- chemo_span |>
  dplyr::inner_join(immuno_admin, by = "patient_id", relationship = "many-to-many") |>
  dplyr::filter(treatment_date >= chemo_first - win,
                treatment_date <= chemo_last  + win) |>
  dplyr::group_by(patient_id, episode_number) |>
  dplyr::summarise(
    conc_bv   = any(bv),
    conc_nivo = any(nivo),
    .groups = "drop"
  )
```

4. Also compute a span-overlap (NOT admin-date) flag for the QC comparison requested — brentuximab Immunotherapy episode overlapping the chemo episode span but with no admin date in the window (sequential use). Build it from the Immunotherapy episode spans in `episodes_export` (or `episodes`) joined to chemo episode spans on patient, overlap test `imm_start <= chemo_stop & imm_stop >= chemo_start`, then anti-join the `conc` admin-date matches. Hold the count in `n_bv_span_not_admin` for the QC block (step 7 below). Use `episodes` (Immunotherapy rows have episode_start/episode_stop) for the immuno spans.

5. Join `conc` onto `episodes_export` by (patient_id, episode_number); `conc_bv`/`conc_nivo` default FALSE where no match. Then relabel the vector `abvd_class` (still the plain vector from step line ~892, before the mutate) using row-aligned `conc_bv`/`conc_nivo` restricted to Chemotherapy rows and to abvd_class currently in c("ABVD","AVD","ABVD_PLUS"):
   - AVD + conc_bv -> "BV+AVD"
   - AVD + conc_nivo (and not conc_bv) -> "Nivo+AVD"
   - ABVD or ABVD_PLUS + (conc_bv or conc_nivo) -> "ABVD_PLUS"
   Precedence: brentuximab before nivolumab when both concurrent on an AVD episode (BV+AVD wins). Count relabels into `n_relabel_bv`, `n_relabel_nivo` for QC.
   Record "Brentuximab Vedotin" / "Nivolumab" as added agents for the ABVD_PLUS-from-concurrency rows (append to a side vector used only by the added-agents QC; do not mutate drug_names).

   Implementation note: align `conc` to `episodes_export` row order with a left_join into a temp tibble keyed by row, or build `conc_bv_vec <- episodes_export |> left_join(conc) |> pull(conc_bv) |> tidyr::replace_na(FALSE)`. Keep the plain `abvd_class` vector edits index-aligned to `episodes_export`.

6. THEN run the existing `episodes_export <- episodes_export |> dplyr::mutate(abvd_class = abvd_class, abvd_episode = abvd_class %in% c("ABVD","AVD","JCODE_ABVD"), ...)` block (line ~894). abvd_episode stays `abvd_class %in% c("ABVD","AVD","JCODE_ABVD")` so BV+AVD / Nivo+AVD are NOT abvd_episode (they are not plain ABVD/AVD). ever_abvd and ever_abvd_plus are already recomputed from the post-relabel abvd_class in that block — confirm no change needed there beyond operating on the relabelled vector.

   NOTE: the task spec says "abvd_episode = abvd_class in c('ABVD','AVD') (plus JCODE path) AFTER this relabel" — the existing derivation already matches that. Do not broaden abvd_episode to include BV+AVD/Nivo+AVD.

7. Extend the D-08 ABVD QC block (starts line ~916) to print, all with `fmt_sup()`:
   - Before/after counts by abvd_class: capture pre-relabel counts (episodes + distinct patients) for ABVD/AVD/ABVD_PLUS from the plain vector before step 5, and after-relabel counts for ABVD/AVD/ABVD_PLUS/BV+AVD/Nivo+AVD; print both.
   - `n_relabel_bv` and `n_relabel_nivo` (episodes relabelled per drug).
   - `n_bv_span_not_admin`: AVD episodes overlapping a brentuximab Immunotherapy episode by span but NOT concurrent by admin date (sequential use).
   Keep the existing per-class episode/patient counts (lines ~920-951) but extend them to include BV+AVD and Nivo+AVD classes.

Section 4D (across(where(is.character)) NA->blank) still runs after 4C4; abvd_class remains a character column exported at col 31. No schema change (still 32 columns).
  </action>
  <verify>
    <automated>tools/rcheck.sh parse R/142_gantt_180_export.R</automated>
  </verify>
  <acceptance_criteria>
    - Date-level relabel block sits between the classify_abvd_episode call and the episodes_export mutate
    - Uses ABVD_CONCURRENT_WINDOW_DAYS and the 180-day `detail` admin dates (not episode spans) for concurrency
    - AVD+BV -> BV+AVD; AVD+Nivo -> Nivo+AVD; ABVD/ABVD_PLUS+either -> ABVD_PLUS
    - abvd_episode unchanged definition (excludes BV+AVD / Nivo+AVD)
    - QC prints before/after by class, per-drug relabel counts, and span-not-admin count
    - R/142 parses
  </acceptance_criteria>
  <done>R/142 Section 4C4 relabels BV+AVD / Nivo+AVD from admin dates; QC extended; file parses.</done>
</task>

<task type="auto">
  <name>Task 3: R/88 test updates — 15bd value set / [a4]/[a5c], 15bb/15bc 32-col, PRE201B regression</name>
  <files>R/88_smoke_test_comprehensive.R</files>
  <action>
15bd ([d3], line ~8011): add "BV+AVD" and "Nivo+AVD" to `valid_cls`:
```r
valid_cls <- c("ABVD", "AVD", "JCODE_ABVD", "ABVD_PLUS", "BV+AVD", "Nivo+AVD", "")
```

15bd [a4] (line ~7921) and [a5c] (line ~7938): these test `classify_abvd_episode()` directly with a `Brentuximab Vedotin;...` token in drug_names, which still returns NA (the function is unchanged — BV+AVD detection is date-level in R/142, not drug-name-level in the helper). Confirm these expectations still hold with the helper unchanged; adjust the test comments to note that BV+AVD/Nivo+AVD relabelling is a date-level R/142 step, not a classify_abvd_episode output. If the task intends [a4]/[a5c] to reflect the new value set, add a data-level check in the 15bd file-present branch instead: assert that any abvd_class == "BV+AVD" rows have abvd_episode == "FALSE" (BV+AVD is not an abvd_episode), and same for Nivo+AVD.

15bb [c2] (line ~7528): already asserts 32 columns — confirm the count literal is 32 and the comment references Phase 201b. No change if already 32.

15bc [c1] (line ~7678): already asserts 32 columns — confirm 32. No change if already 32.

PRE201B regression: add/confirm a check in the 15bd file-present branch that columns 1-26 match the PRE201B baseline (cols 27-32 are expected to change). Follow the existing PRE201 / PRE199 regression-check pattern already in R/88 (search for the PRE201 baseline check and mirror it with a PRE201B baseline name, restricting the compared columns to 1-26). If a PRE201B baseline comparison does not yet exist in R/88, add a check that the first 26 column NAMES equal the known pre-201 schema (cols 1-26 unchanged) — do not read data if the data-level baseline file is absent (skip with p201_skip_fn, matching the existing file-absent pattern).
  </action>
  <verify>
    <automated>tools/rcheck.sh parse R/88_smoke_test_comprehensive.R</automated>
  </verify>
  <acceptance_criteria>
    - 15bd [d3] valid_cls includes "BV+AVD" and "Nivo+AVD"
    - [a4]/[a5c] expectations consistent with unchanged classify_abvd_episode (BV token -> NA), comments clarified; or data-level BV+AVD/Nivo+AVD abvd_episode==FALSE checks added
    - 15bb [c2] and 15bc [c1] assert 32 columns
    - PRE201B cols 1-26 regression present (data-level if baseline exists, else name-level / skip)
    - R/88 parses
  </acceptance_criteria>
  <done>R/88 reflects new value set, 32-col asserts, PRE201B 1-26 regression; file parses.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <what-built>Date-level BV+AVD / Nivo+AVD relabel in R/142 Section 4C4, config window constant, R/88 updates.</what-built>
  <how-to-verify>
On HiPerGator (do NOT run locally), in an interactive session:

```r
module load R/4.5
R --no-save
Sys.setenv(RUN_PRE201_REGRESSION = "TRUE")
source("R/142_gantt_180_export.R", local = new.env(parent = globalenv()))
```

Paste back only:
- the D-08 QC before/after counts by abvd_class (episodes + patients, suppressed <11)
- `n_relabel_bv` and `n_relabel_nivo`
- `n_bv_span_not_admin` (sequential-use count)
- "Phase 201 regression: PASS"

Then optionally run R/88 (`source("R/88_smoke_test_comprehensive.R", ...)`) and paste the 15bd / 15bb / 15bc result lines.

Expected per the task note: ~252 AVD episodes / 230 patients overlap brentuximab and ~46 / 43 overlap nivolumab at the span level; the admin-date window should relabel a subset of these.
  </how-to-verify>
  <resume-signal>Type "approved" or paste the QC counts / any failures.</resume-signal>
</task>

</tasks>

<verification>
- R/00_config.R, R/142, R/88 all pass `tools/rcheck.sh parse`.
- Relabel uses admin dates from the 180-day `detail`, not episode spans.
- abvd_episode definition unchanged (BV+AVD / Nivo+AVD excluded).
- HiPerGator run shows before/after class counts, per-drug relabel counts, span-not-admin count, and regression PASS.
</verification>

<success_criteria>
- `abvd_class` distinguishes BV+AVD and Nivo+AVD from plain AVD via +/-7-day admin-date concurrency.
- ABVD / ABVD_PLUS + concurrent BV or Nivo -> ABVD_PLUS.
- Config constant ABVD_CONCURRENT_WINDOW_DAYS = 7L.
- ever_abvd / ever_abvd_plus recomputed from post-relabel abvd_class.
- R/88 value set, 32-col asserts, and PRE201B 1-26 regression updated.
</success_criteria>

<output>
After completion, create `.planning/quick/261114-mch-phase-201-fix-detect-bv-avd-and-nivo-avd/261114-mch-SUMMARY.md` with:
- the config constant added
- what the Section 4C4 relabel block does (date-level logic, precedence)
- before/after abvd_class counts and per-drug relabel counts (suppressed <11) from the HiPerGator run
- n_bv_span_not_admin (sequential use)
- R/88 changes and parse/test status
</output>
