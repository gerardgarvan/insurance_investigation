# Phase 169: Registration, Smoke Test, and HiPerGator Run — Context

**Gathered:** 2026-10-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Close the registration gaps left by Phase 165 (R/165 was never wired into R/39 or
SCRIPT_INDEX.md, R/163 prototype never documented), add SMOKE-165-01 structural checks
to R/88, create a real test file for R/165's helpers, and execute a HiPerGator run that
produces all four phase-specific workbooks (Phases 165–168) with today's date.

Phases 166–168 are already registered (R/39, SCRIPT_INDEX, R/88 sections). The only
registration gap is Phase 165 and its companion prototype (R/163).

</domain>

<decisions>
## Implementation Decisions

### D-01: R/165 position in R/39
R/165 (`distance_cbc_association.R`) depends on:
- R/122 output (`enc_distance`) for `distance_mi`
- R/116 output (`encounter_ses_index`) for rurality in the sensitivity model
- R/147 CBC events and anchor dates (re-derived from LAB_RESULT_CM, but R/147 must
  have already run so the DuckDB ENCOUNTER data is stable)

**Decision:** Insert R/165 immediately before R/166 (i.e., after R/162, which is the
current last entry before the Phase 166 block). Do NOT insert between R/122 and R/147.

### D-02: R/163 prototype — SCRIPT_INDEX only, not R/39
R/163 (`distance_cbc_methods_prototype.R`) is a one-off evidence script requiring
`survey` and `geepack`; it is slow and not suitable for routine pipeline runs.

**Decision:** Add a SCRIPT_INDEX.md row for R/163 marked **"one-off, not in pipeline"**
so it is documented without executing every time R/39 runs. Do NOT add it to R/39's
`investigation_scripts` vector.

### D-03: R/88 SMOKE-165-01 checks
New section `15ar` (after `15aq` = Phase 168). Checks fall into two tiers:

**Always-on (code-level, offline-safe):**
1. `R/165_distance_cbc_association.R` exists
2. `R/utils/utils_distance_cbc.R` exists
3. `CONFIG$far_from_care_cutoff_mi == 100` (read from 00_config.R or source()d)
4. `CONFIG$distance_assoc_method %in% c("gee", "rao_scott", "patient_fisher")`
5. R/165 source contains no literal `100` cutoff (uses `CUTOFF` / `CONFIG$`)
6. R/165 contains no `quit(` call
7. R/165 contains no `R/4.4.2` literal (must use the canonical module load path)
8. `utils_distance_cbc.R` defines the key helpers (check for function definitions)
9. R/165 registered in R/39 `investigation_scripts`
10. `tests/testthat/test-165-distance-cbc-association.R` exists

**Output-gated (offline: skip with NOTE PASS):**
11. Workbook sheet order is exactly KEY, A_crosstab, B_test, C_sensitivity, QC;
    KEY is first
12. B_test contains both windows (whole-record and post-anchor rows present)
13. `far_from_care_100mi` column in output RDS is only `{0, 1}` (no other values)
14. `enc_far_from_care.rds` (or equivalent encounter-level RDS) has one row per
    `ENCOUNTERID` — satisfies the "no fan-out" row-count requirement
15. A_crosstab contains no displayed values in 1–10 range (suppression applied)

### D-04: test-165 — real minimal tests, not placeholder
File: `tests/testthat/test-165-distance-cbc-association.R`
Source: helpers from `R/utils/utils_distance_cbc.R`.

**Required test cases:**
1. **`naive_or_se()` integer overflow regression:** pass a 2×2 table with cell counts
   in the hundreds of thousands (matching the prototype run scale). Expect a finite,
   positive odds ratio. This is the specific overflow that broke candidate 1 in the
   prototype run.
2. **`suppress_display()`:** 1–10 → `"<11"`; 0 and 11 are unchanged; boundary values
   10 and 11 tested explicitly.
3. **CBC encounter matching:** a two-day inpatient stay (ADMIT_DATE ≠ DISCHARGE_DATE)
   with CBC events on both days collapses to one row with `cbc_in_encounter = 1`
   (not two rows, and not duplicated).
4. **`build_pat_analysis()` post-anchor window exclusion:** a fixture where one patient
   has a CBC on the anchor day — that event must be excluded from the post-anchor
   analysis set (anchor day = pre, consistent with R/147's `ANCHOR_DAY_IS_POST = FALSE`).

### D-05: HiPerGator run task — exact commands
The plan's HiPerGator task must spell out:

**Step 1 — Sync:**
```
git pull                     # on HiPerGator clone
renv::restore()              # if renv.lock changed
```

**Step 2 — Run scripts (sbatch with dependency chaining):**
```bash
JOB165=$(sbatch --parsable slurm/165_distance_cbc_association.sbatch)
JOB166=$(sbatch --parsable --dependency=afterok:$JOB165 slurm/166_survivorship.sbatch)
JOB167=$(sbatch --parsable --dependency=afterok:$JOB166 slurm/167_single_source_care.sbatch)
JOB168=$(sbatch --parsable --dependency=afterok:$JOB167 slurm/168_nhl_gantt_subsets.sbatch)
JOB88=$(sbatch  --parsable --dependency=afterok:$JOB168 slurm/88_smoke_test.sbatch)
echo "Jobs: 165=$JOB165 166=$JOB166 167=$JOB167 168=$JOB168 88=$JOB88"
```

(If running one-at-a-time: R/165 → R/166 → R/167 → R/168 → R/88, in that order.)

**Step 3 — Verify:**
- Four workbooks with today's date present in `output/` and `output/internal/`:
  - `output/distance_cbc_association_<YYYYMMDD>.xlsx`
  - `output/survivorship_modality_rates_<YYYYMMDD>.xlsx`
  - `output/single_source_care_<YYYYMMDD>.xlsx`
  - `output/internal/nhl_gantt_subsets_<YYYYMMDD>.xlsx`
- SMOKE-165-01 through SMOKE-168-01 footer lines all read `N PASS / 0 FAIL`
- R/88 overall exit status = 0 (`echo "R/88 exit: $?"` after the sbatch job)

**Step 4 — Paste back:**
- The four SMOKE footer lines (e.g., `SMOKE-165-01: 15 PASS / 0 FAIL`)
- The four output file paths with their actual dates

### D-06: Pre-run checks before HiPerGator execution
Two items must be confirmed before R/165 is re-run:

1. **Memo fixes applied to R/165:** Confirm the following are implemented in the current
   `R/165_distance_cbc_association.R` and `R/utils/utils_distance_cbc.R`:
   - `naive_or_se()` overflow fix (integer overflow with large count tables)
   - DEFF computation method (how it was handled in rao_scott)
   - `svyglm ≈ GEE` note in B_test or KEY commentary
   - Out-of-network lab caveat in KEY or QC

2. **D-165-01 method confirmation flag:** The 165-CONTEXT.md records `rao_scott` as the
   decided method; the user notes that whatever was entered was done without Amy and
   Erin's input. **The re-issued workbook's KEY sheet must include a note that the
   primary method (`CONFIG$distance_assoc_method`) is pending team confirmation.** Do
   not change the coded method — just add the caveat text to the KEY sheet. The plan
   task should include verifying what `CONFIG$distance_assoc_method` currently contains
   and surfacing it in the SUMMARY.

### Claude's Discretion
- Exact wording of the KEY "pending confirmation" note (match the voice used in other
  KEY sheets — brief, one line)
- R/88 SECTION 15ar helper function name (`chk_165`, `p165_pass`, `p165_fail` following
  the existing naming pattern)
- Whether to use `source()` or `readLines()` for the CONFIG checks in R/88 (follow
  the pattern used in the adjacent SMOKE-167-01 / SMOKE-168-01 sections)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Registration targets
- `R/39_run_all_investigations.R` §`investigation_scripts` — current list; R/165 goes
  immediately before `"R/166_survivorship_modality_rates.R"`
- `R/SCRIPT_INDEX.md` — R/163 and R/165 entries needed; follow table format at lines
  162–173 (see R/162, R/166 rows as templates)

### Smoke test
- `R/88_smoke_test_comprehensive.R` §SECTION 15aq (Phase 168) — new SECTION 15ar for
  Phase 165 follows immediately after; use `p168_*` / `chk_168` pattern as template
- `.planning/ROADMAP.md` §"Phase 169" — canonical success criteria (file existence,
  sheet names, KEY leftmost, binary 0/1, no fan-out)

### Phase 165 implementation
- `R/165_distance_cbc_association.R` — full production script; read for helper names,
  output column names, stopifnot contracts, and sheet structure
- `R/utils/utils_distance_cbc.R` — helper functions to test; read for `naive_or_se()`,
  `suppress_display()`, `build_pat_analysis()`, CBC-matching logic signatures
- `R/163_distance_cbc_methods_prototype.R` — prototype (one-off); planner reads to
  write the SCRIPT_INDEX "one-off" description

### Prior phase contexts (for pattern consistency)
- `.planning/phases/168-nhl-only-and-hl-nhl-gantt-episode-subsets/168-CONTEXT.md`
  §D-10 — openxlsx (not openxlsx2) convention; KEY leftmost
- `.planning/phases/166-survivorship-modality-rates-and-anthracycline-to-echo-timing/166-CONTEXT.md`
  — smoke test pattern, sbatch dependency chain, HiPerGator run task structure

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/88_smoke_test_comprehensive.R` SECTION 15aq (`chk_168`, `p168_pass`, `p168_fail`,
  output-gated `tryCatch(openxlsx::getSheetNames(...))` pattern) — copy-adapt for
  SECTION 15ar
- `slurm/165_distance_cbc_association.sbatch` — already exists; sbatch command in D-05
  uses it as-is

### Established Patterns
- SMOKE sections in R/88 follow: declare counter pair → `chk_N <- function(condition,
  label)` → always-on checks → output-gated block with `if (file.exists(...)) { ... }
  else { message("NOTE ... skipped (offline)"); p_pass <<- p_pass + 1L }`
- SCRIPT_INDEX rows: `| \`R/NNN_script_name.R\` | Description. | deps |` — one-row
  pipe table entry; "one-off" scripts get that label in their description
- SUMMARY message in R/88 tail: one `message("  * SMOKE-NNN-01: ...")` line per section

### Integration Points
- R/39 `investigation_scripts` vector: insert R/165 on the line before `"R/166_..."`
- R/88 SECTION 15ar: placed between SECTION 15aq (end of Phase 168 block) and
  SECTION 16 (SUMMARY)
- testthat: `tests/testthat/test-165-distance-cbc-association.R` — source helpers with
  `source(here::here("R/utils/utils_distance_cbc.R"))` at top; follow pattern from
  `test-169-single-source-care.R` or `test-170-nhl-gantt-subsets.R`

</code_context>

<specifics>
## Specific Ideas

- **Overflow regression test:** the prototype run with rao_scott on hundreds-of-thousands
  cell counts is the exact failure mode to reproduce in the fixture. Use realistic-scale
  integers (e.g., 120000 / 85000 / 95000 / 65000) not small toy numbers.
- **sbatch dependency chain:** `--parsable` flag on each sbatch is required to capture
  the job ID for `--dependency=afterok:$JOBID`; include this in the plan task verbatim.
- **KEY pending-confirmation note:** one-line addition to the KEY sheet data frame —
  something like `"Method (D-165-01): rao_scott — pending confirmation from Amy and Erin"`
  in the notes/caveats row, consistent with how other KEY sheets handle open items.

</specifics>

<deferred>
## Deferred Ideas

- Updating the 165-CONTEXT.md D-165-01 entry to reflect the pending-confirmation status
  vs. the currently recorded `rao_scott` — that's a doc fix, not part of Phase 169
  execution (can be done alongside SUMMARY.md after the HiPerGator run confirms the
  team's final method choice).
- Adding `utils_distance_hist.R` to SCRIPT_INDEX utility libraries section — it exists
  but was not flagged as missing by the roadmap. Can be picked up as a quick task.

</deferred>

---

*Phase: 169-registration-smoke-test-and-hipergator-run*
*Context gathered: 2026-10-08*
