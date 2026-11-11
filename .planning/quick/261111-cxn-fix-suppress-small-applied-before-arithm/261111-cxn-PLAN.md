---
phase: quick
plan: 261111-cxn
type: execute
wave: 1
depends_on: []
files_modified:
  - R/107_med_admin_dispensing_gap_diagnostic.R
  - R/109_med_admin_dispensing_fix_impact_audit.R
  - R/110_output_level_before_after_report.R
autonomous: true
requirements: [quick-261111-cxn]
must_haves:
  truths:
    - "suppress_small() is never called on a value that participates in arithmetic afterwards"
    - "All delta/percentage columns are computed from raw integer columns"
    - "suppress_small() is called only immediately before writing (xlsx/csv) or in a glue() message"
    - "Percentages and deltas derived from a suppressed count are blanked (NA_character_) in the display table"
    - "No sorting or filtering uses a character column produced by suppress_small()"
  artifacts:
    - path: R/107_med_admin_dispensing_gap_diagnostic.R
      provides: "suppress_small applied only at write/message step"
    - path: R/109_med_admin_dispensing_fix_impact_audit.R
      provides: "suppress_small applied only at write/message step; arithmetic uses raw integers"
    - path: R/110_output_level_before_after_report.R
      provides: "suppress_small applied only at write/message step; delta computed from raw integers"
  key_links:
    - from: "R/109 Section 6 (line 240-251)"
      to: "df_before_after_summary delta column"
      via: "must use raw integer columns, not suppress_small output"
    - from: "R/109 Section 8 (line 331)"
      to: "arrange(desc(delta_pts))"
      via: "suppress_small must be deferred until after sort"
    - from: "R/110 compute_episode_summary"
      to: "df_summary delta = after - before"
      via: "suppress_small must not be applied before the join and mutate"
---

<objective>
Fix suppress_small() applied before arithmetic in R/107, R/109, and R/110.

Purpose: Commit 338ba5f introduced suppress_small() calls inside summarise/tibble constructors, so derived columns (delta, percentages, sort) operate on character "<11" values, causing crashes like "non-numeric argument to binary operator".

Output: Three patched scripts where all arithmetic uses raw numeric columns; suppress_small() is applied only at the final display/write step.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
</execution_context>

<context>
@.planning/STATE.md
@R/107_med_admin_dispensing_gap_diagnostic.R
@R/109_med_admin_dispensing_fix_impact_audit.R
@R/110_output_level_before_after_report.R
</context>

<tasks>

<task type="auto">
  <name>Task 1: Audit and catalogue all suppress_small call sites in R/107, R/109, R/110</name>
  <files>R/107_med_admin_dispensing_gap_diagnostic.R, R/109_med_admin_dispensing_fix_impact_audit.R, R/110_output_level_before_after_report.R</files>
  <action>
Classify every suppress_small() call in each file as SAFE or UNSAFE before touching any code.

SAFE = called on a scalar/column that is never used in arithmetic, comparison, sort, or filter afterwards.
UNSAFE = called on a value that feeds into arithmetic (delta, sum, percentage, sort key) in the same or a later pipeline step.

**R/107 audit findings (read before editing):**
- Lines 212, 218: `n_patients = suppress_small(...)` in list objects → written directly to CSV via bind_rows. No arithmetic on n_patients after. SAFE.
- Lines 335, 341, 347, 353, 395, 401: same pattern — SAFE.
- Line 415: `headline_new_patients <- suppress_small(n_new_ma_patients)` → used only in glue() message. SAFE.
- Line 417: `headline_earlier <- suppress_small(n_earlier_dates)` → used only in glue() message. SAFE.
- **R/107 verdict: no changes required.** All suppress_small calls are safe.

**R/109 unsafe call sites:**
- Line 234: `n_patients = suppress_small(n_distinct(ID))` inside `group_by/summarise` → stored in `df_source_counts`. No arithmetic follows on this column. SAFE.
- Lines 243, 247: `before = c(suppress_small(n_distinct(before$ID)), ...)` and `after = c(suppress_small(...), ...)` in `df_before_after_summary` tibble → line 251 `mutate(delta = after - before)` crashes. **UNSAFE.**
- Line 287: `n_patients_earlier = suppress_small(n_distinct(shift_df$ID))` → line 293 `glue("... {df_timing_shift$n_patients_earlier} ...")` — only display, but check for numeric arithmetic. SAFE (glue only).
- Line 331: `mutate(across(c(n_pts_before, n_pts_after, delta_pts), suppress_small))` then `arrange(desc(delta_pts))` — sort on character column. **UNSAFE.**
- Line 572: `n_patients = suppress_small(n_distinct(ID))` in NDC frequency table → used in `arrange(desc(n_rows))` (n_rows not suppressed) and `mutate(rank = row_number())`. n_patients not used in arithmetic after. SAFE.

**R/110 unsafe call sites:**
- Lines 221, 229, 237: `suppress_small(n_distinct(...))` assigned to `pts_any_chemo`, `pts_dispensing`, `pts_med_admin` scalars → returned in `tibble()` as the column value → joined in `df_summary` → line 266 `delta = after - before` crashes. **UNSAFE.**
- Lines 393, 435, 500, 545: suppress_small in other summarise blocks — check whether downstream arithmetic exists (read surrounding 20 lines for each before deciding).

Do not edit yet. Confirm the full unsafe list before proceeding to Task 2.
  </action>
  <verify>No verify step — this is a read-and-classify task. Output is a confirmed unsafe list used by Task 2.</verify>
  <done>Every suppress_small call site in the three files classified SAFE or UNSAFE with line numbers.</done>
</task>

<task type="auto">
  <name>Task 2: Restructure R/109 and R/110 to defer suppression to display/write step</name>
  <files>R/109_med_admin_dispensing_fix_impact_audit.R, R/110_output_level_before_after_report.R</files>
  <action>
Apply targeted edits only to the UNSAFE call sites identified in Task 1. Do not alter SAFE sites.

**R/109 — Fix 1: df_before_after_summary (lines ~240–253)**

Replace the tibble constructor and mutate so raw integers are used for delta:

```r
# BEFORE (broken):
df_before_after_summary <- tibble(
  metric = c("n_patients_any_chemo", "n_distinct_id_date_pairs"),
  before = c(
    suppress_small(n_distinct(before$ID)),
    nrow(before)
  ),
  after = c(
    suppress_small(n_distinct(after$ID)),
    nrow(after)
  )
) %>%
  mutate(delta = after - before)
```

```r
# AFTER (fixed):
df_before_after_summary_raw <- tibble(
  metric  = c("n_patients_any_chemo", "n_distinct_id_date_pairs"),
  before  = c(n_distinct(before$ID), nrow(before)),
  after   = c(n_distinct(after$ID),  nrow(after)),
  delta   = c(n_distinct(after$ID)  - n_distinct(before$ID),
              nrow(after)           - nrow(before))
)

# Display table: suppress patient counts; blank delta when either end is suppressed.
df_before_after_summary <- df_before_after_summary_raw %>%
  mutate(
    before_disp = suppress_small(before),
    after_disp  = suppress_small(after),
    delta_disp  = dplyr::case_when(
      before < 11L | after < 11L ~ NA_character_,   # complementary suppression
      TRUE                       ~ as.character(delta)
    )
  ) %>%
  select(metric, before = before_disp, after = after_disp, delta = delta_disp)
```

Update the glue() message on the lines after to reference `df_before_after_summary_raw` for the numeric values used in the message (or use the raw scalars directly):

```r
message(glue(
  "  Headline: {suppress_small(df_before_after_summary_raw$before[1])} patients before -> ",
  "{suppress_small(df_before_after_summary_raw$after[1])} patients after ",
  "(delta = {df_before_after_summary_raw$delta[1]})"
))
message(glue(
  "  (ID,date) pairs: {df_before_after_summary_raw$before[2]} before -> ",
  "{df_before_after_summary_raw$after[2]} after ",
  "(delta = {df_before_after_summary_raw$delta[2]})\n"
))
```

**R/109 — Fix 2: df_ingredient_delta sort on character (line ~331)**

Move `suppress_small` after `arrange()`:

```r
# BEFORE (broken):
df_ingredient_delta <- full_join(...) %>%
  mutate(
    ...
    delta_pts   = ...,
    delta_dates = ...
  ) %>%
  mutate(across(c(n_pts_before, n_pts_after, delta_pts), suppress_small)) %>%
  arrange(desc(delta_pts))
```

```r
# AFTER (fixed):
df_ingredient_delta_raw <- full_join(...) %>%
  mutate(
    drug_name   = ...,
    delta_pts   = coalesce(n_pts_after, 0L) - coalesce(n_pts_before, 0L),
    delta_dates = coalesce(n_dates_after, 0L) - coalesce(n_dates_before, 0L)
  ) %>%
  arrange(desc(delta_pts))

# Display table: suppress and apply complementary suppression to delta.
df_ingredient_delta <- df_ingredient_delta_raw %>%
  mutate(
    n_pts_before_disp = suppress_small(n_pts_before),
    n_pts_after_disp  = suppress_small(n_pts_after),
    # Blank delta if either endpoint is suppressed (complementary suppression).
    delta_pts_disp = dplyr::case_when(
      coalesce(n_pts_before, 0L) < 11L | coalesce(n_pts_after, 0L) < 11L ~ NA_character_,
      TRUE ~ as.character(delta_pts)
    )
  ) %>%
  select(-n_pts_before, -n_pts_after, -delta_pts,
         n_pts_before = n_pts_before_disp,
         n_pts_after  = n_pts_after_disp,
         delta_pts    = delta_pts_disp)
```

The write step downstream already uses `df_ingredient_delta` — no further changes needed there, but verify no subsequent arithmetic uses `df_ingredient_delta$delta_pts` after this rename.

**R/110 — Fix: compute_episode_summary returns raw integers; suppression at display join**

```r
# BEFORE (broken): suppress_small applied inside the helper, before the join and delta mutate.
compute_episode_summary <- function(df, label) {
  ...
  pts_any_chemo <- suppress_small(dplyr::n_distinct(chemo_df[[pid_col]]))
  pts_dispensing <- suppress_small(...)
  pts_med_admin  <- suppress_small(...)
  tibble::tibble(metric = ..., !!label := c(total_episodes, total_chemo_episodes,
                                             pts_any_chemo, pts_dispensing, pts_med_admin))
}
```

```r
# AFTER (fixed): helper returns raw integers; callers suppress at display time.
compute_episode_summary <- function(df, label) {
  ...
  pts_any_chemo  <- if (!is.null(pid_col)) dplyr::n_distinct(chemo_df[[pid_col]]) else NA_integer_
  pts_dispensing <- if (!is.null(pid_col) && !is.null(src_col)) {
    d_chemo <- chemo_df |> dplyr::filter(stringr::str_detect(.data[[src_col]], "DISPENSING"))
    dplyr::n_distinct(d_chemo[[pid_col]])
  } else { NA_integer_ }
  pts_med_admin  <- if (!is.null(pid_col) && !is.null(src_col)) {
    m_chemo <- chemo_df |> dplyr::filter(stringr::str_detect(.data[[src_col]], "MED_ADMIN"))
    dplyr::n_distinct(m_chemo[[pid_col]])
  } else { NA_integer_ }
  tibble::tibble(metric = ..., !!label := c(total_episodes, total_chemo_episodes,
                                             pts_any_chemo, pts_dispensing, pts_med_admin))
}
```

Then update `df_summary` construction (lines ~263–269):

```r
df_summary_raw <- dplyr::left_join(summary_before, summary_after, by = "metric") |>
  dplyr::mutate(
    delta = dplyr::case_when(
      !is.na(before) & !is.na(after) ~ after - before,
      TRUE ~ NA_integer_
    )
  )

# Which metrics are patient counts (require suppression)?
patient_count_metrics <- c(
  "Patients with any chemo episode",
  "Patients with DISPENSING-sourced chemo episode",
  "Patients with MED_ADMIN-sourced chemo episode"
)

df_summary <- df_summary_raw |>
  dplyr::mutate(
    before = dplyr::if_else(metric %in% patient_count_metrics,
                            suppress_small(before), as.character(before)),
    after  = dplyr::if_else(metric %in% patient_count_metrics,
                            suppress_small(after),  as.character(after)),
    # Blank delta for patient-count rows where either endpoint is suppressed.
    delta  = dplyr::case_when(
      metric %in% patient_count_metrics &
        (dplyr::coalesce(dplyr::if_else(metric %in% patient_count_metrics,
                                        dplyr::if_else(
                                          as.integer(dplyr::na_if(before, "<11")) < 11L,
                                          TRUE, FALSE), FALSE), FALSE)) ~ NA_character_,
      TRUE ~ as.character(delta)
    )
  )
```

Simpler approach for the display step (preferred — avoids nested if_else complexity):

```r
df_summary <- df_summary_raw |>
  dplyr::mutate(
    # Suppress raw patient counts; leave episode/date row counts as-is.
    before_disp = dplyr::if_else(metric %in% patient_count_metrics,
                                 suppress_small(before), as.character(before)),
    after_disp  = dplyr::if_else(metric %in% patient_count_metrics,
                                 suppress_small(after),  as.character(after)),
    delta_disp  = dplyr::case_when(
      metric %in% patient_count_metrics &
        (coalesce(before, 0L) < 11L | coalesce(after, 0L) < 11L) ~ NA_character_,
      TRUE ~ as.character(delta)
    )
  ) |>
  dplyr::select(metric,
                before = before_disp,
                after  = after_disp,
                delta  = delta_disp)
```

**After all edits, add a stopifnot guard before each xlsx/csv write in R/109 and R/110:**

Before the write call for `df_before_after_summary` (R/109) and `df_summary` (R/110):
```r
# Guard: confirm no arithmetic columns are still character.
stopifnot(
  "df_before_after_summary_raw must have integer before/after" =
    is.integer(df_before_after_summary_raw$before),
  "df_before_after_summary_raw must have integer delta" =
    is.integer(df_before_after_summary_raw$delta)
)
```

Before the write call for `df_ingredient_delta_raw` (R/109):
```r
stopifnot(
  "df_ingredient_delta_raw delta_pts must be integer" =
    is.integer(df_ingredient_delta_raw$delta_pts)
)
```

Also add guards that check lines 393, 435, 500, 545 of R/110 for any arithmetic-after-suppress patterns found in Task 1 — fix those in the same edit pass using the same pattern (raw table → display table).

**Also check R/109 lines 572–578:** n_patients = suppress_small(n_distinct(ID)) in combined_freq. It is then used in `arrange(desc(n_rows))` (safe — sorts on n_rows) and `mutate(rank = row_number())` (safe). No arithmetic on n_patients. Leave SAFE; no change needed.
  </action>
  <verify>
    <automated>node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" check-syntax R/109_med_admin_dispensing_fix_impact_audit.R R/110_output_level_before_after_report.R 2>/dev/null || node -e "
const fs = require('fs');
['R/109_med_admin_dispensing_fix_impact_audit.R','R/110_output_level_before_after_report.R'].forEach(f => {
  const src = fs.readFileSync(f,'utf8');
  let d=0;
  for(const ch of src){if(ch==='{')d++;else if(ch==='}')d--;}
  console.log(f, d===0 ? 'BALANCED' : 'UNBALANCED braces: '+d);
});"</automated>
    Also grep that suppress_small is not called before arithmetic on its result:
    <automated>grep -n "suppress_small" R/109_med_admin_dispensing_fix_impact_audit.R R/110_output_level_before_after_report.R</automated>
    Manually scan the grep output: every suppress_small call should appear only in a _disp assignment or a final mutate/select block, never as a direct column in a tibble that feeds into arithmetic.
  </verify>
  <done>
    - df_before_after_summary_raw in R/109 uses raw integers; delta computed numerically.
    - df_ingredient_delta_raw in R/109 is sorted before suppression is applied.
    - compute_episode_summary in R/110 returns raw integers.
    - df_summary in R/110 computes delta from raw integers before any suppression.
    - All display tables apply suppress_small only in the final _disp columns or immediately before write.
    - Complementary suppression blanks deltas/percentages when either endpoint is suppressed.
    - stopifnot guards present before each write call on the raw tables.
    - Brace balance check passes for both files.
  </done>
</task>

<task type="auto">
  <name>Task 3: Commit fix</name>
  <files>R/109_med_admin_dispensing_fix_impact_audit.R, R/110_output_level_before_after_report.R</files>
  <action>
Stage the two modified files and commit with the required message.

```bash
git add R/109_med_admin_dispensing_fix_impact_audit.R R/110_output_level_before_after_report.R
git commit -m "Fix: apply small-cell suppression at display only in R/107/109/110"
```

(R/107 requires no changes per Task 1 audit; do not stage it.)

Then write the quick task summary to `.planning/quick/261111-cxn-fix-suppress-small-applied-before-arithm/261111-cxn-SUMMARY.md`.
  </action>
  <verify>
    <automated>git log --oneline -1</automated>
  </verify>
  <done>Commit exists with message "Fix: apply small-cell suppression at display only in R/107/109/110". Summary file written.</done>
</task>

</tasks>

<verification>
- grep -n "suppress_small" R/109_*.R R/110_*.R — all hits should be in _disp assignments, final select/mutate before write, or glue() message calls only
- No suppress_small hit should appear as a column in a tibble constructor that is later joined and has arithmetic applied
- Brace balance passes for both files
- Commit message matches exactly
</verification>

<success_criteria>
Running R/109 and R/110 on HiPerGator completes Section 6 without "non-numeric argument to binary operator". All delta columns in output workbooks are either a numeric string or NA (complementary-suppressed), never computed from a character "<11".
</success_criteria>

<output>
After completion, create `.planning/quick/261111-cxn-fix-suppress-small-applied-before-arithm/261111-cxn-SUMMARY.md`
</output>
