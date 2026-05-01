---
phase: quick
plan: 260501-gkl
type: execute
wave: 1
depends_on: []
files_modified:
  - .gitignore
  - 22_multi_source_overlap_detection_TEMPLATE.R
  - R/26_generate_speedup_report.R
autonomous: true
must_haves:
  truths:
    - "git status shows no untracked __pycache__, pptx, xlsx, or txt clutter"
    - "No dead one-off R or SAS scripts remain in root"
    - "No stale PLAN.md duplicates remain in root"
    - "R/ directory has no duplicate script numbers"
    - "Template file references existing predicate source"
  artifacts:
    - path: ".gitignore"
      provides: "Updated ignore patterns for root-level output artifacts"
      contains: "__pycache__"
    - path: "R/29_generate_speedup_report.R"
      provides: "Renamed speedup report script (was R/26_)"
  key_links:
    - from: "22_multi_source_overlap_detection_TEMPLATE.R"
      to: "R/03_cohort_predicates.R"
      via: "source() call"
      pattern: 'source.*03_cohort_predicates'
    - from: "R/29_generate_speedup_report.R"
      to: "output/logs/duckdb_benchmark.csv"
      via: "read_csv()"
      pattern: "29_generate_speedup_report"
---

<objective>
Clean up accumulated code health issues: root-level clutter, dead scripts, stale plan duplicates, a broken template reference, a duplicate script number, and gitignore gaps.

Purpose: Reduce noise in git status, prevent confusion from dead/duplicate files, ensure template and numbered scripts are correct.
Output: Clean root directory, updated .gitignore, renamed R/29_generate_speedup_report.R, fixed template source() call.
</objective>

<execution_context>
@C:\Users\Owner\Documents\insurance_investigation\.claude\get-shit-done\workflows\execute-plan.md
@C:\Users\Owner\Documents\insurance_investigation\.claude\get-shit-done\templates\summary.md
</execution_context>

<context>
@.planning/STATE.md
@.gitignore
</context>

<tasks>

<task type="auto">
  <name>Task 1: Update .gitignore, delete dead scripts and stale plans, remove empty directory</name>
  <files>.gitignore, check_enr_dates.R, check_lowercase_dx.R, check_orl_enr_dates.R, debug_columns.R, payer_missingness_html.R, SAS_CODE_FOR_V5_MODELS4.sas, ins_presinvesting.sas, 29-01-PLAN.md, 29-02-PLAN.md, 30-01-PLAN.md, 30-02-PLAN.md, 31-01-PLAN.md, 31-02-PLAN.md, 32-01-PLAN.md, 32-02-PLAN.md, .planning/New folder</files>
  <action>
1. **Update .gitignore** -- append these patterns after the existing "Root-level diagnostic/output artifacts" section:

```
# Python bytecode
__pycache__/

# Office temp files
~$*

# Root-level output artifacts (not tracked)
/*.pptx
/*.xlsx
/*.txt
```

These are safe to add because NO root-level .pptx, .xlsx, or .txt files are currently tracked in git. The patterns only affect `git status` display for untracked files.

2. **Delete dead one-off R scripts from root** (all superseded by pipeline scripts in R/):
   - `check_enr_dates.R` (superseded by R/utils_dates.R + R/07_diagnostics.R)
   - `check_lowercase_dx.R` (one-off fix, Phase 18 era)
   - `check_orl_enr_dates.R` (Orlando-specific one-off)
   - `debug_columns.R` (11-line debugging stub)
   - `payer_missingness_html.R` (hardcoded HiPerGator paths, superseded by Phase 18-20 scripts)

3. **Delete abandoned SAS files from root** (legacy, never integrated into R pipeline):
   - `SAS_CODE_FOR_V5_MODELS4.sas`
   - `ins_presinvesting.sas`

4. **Delete stale root-level PLAN.md duplicates** (copies already exist in .planning/phases/):
   - `29-01-PLAN.md`, `29-02-PLAN.md`
   - `30-01-PLAN.md`, `30-02-PLAN.md`
   - `31-01-PLAN.md`, `31-02-PLAN.md`
   - `32-01-PLAN.md`, `32-02-PLAN.md`

5. **Remove accidental empty directory**: `.planning/New folder`

6. **Stage the 5 already-deleted PPTX files** that show as "D" (deleted but unstaged) in git status:
   - `insurance_tables_2026-03-24.pptx`
   - `insurance_tables_2026-03-26.pptx`
   - `insurance_tables_2026-03-30.pptx`
   - `insurance_tables_2026-03-31.pptx`
   - `insurance_tables_2026-04-01.pptx`

   Stage these deletions with `git add` so they are recorded. The new `/*.pptx` gitignore pattern will prevent future pptx files from appearing in status.
  </action>
  <verify>
    <automated>git status -s | grep -E "^\?\? (check_|debug_|payer_missingness_html|SAS_|ins_pre|[0-9]+-0[12]-PLAN)" && echo "FAIL: dead files still present" || echo "PASS: dead files removed"</automated>
  </verify>
  <done>Root directory has no dead R/SAS scripts, no stale PLAN.md duplicates, no empty "New folder". Gitignore covers __pycache__, Office temp files, root pptx/xlsx/txt. Deleted PPTX files are staged.</done>
</task>

<task type="auto">
  <name>Task 2: Fix template source reference and rename duplicate R/26_ script</name>
  <files>22_multi_source_overlap_detection_TEMPLATE.R, R/26_generate_speedup_report.R</files>
  <action>
1. **Fix template source() reference** in `22_multi_source_overlap_detection_TEMPLATE.R`:
   - Line 21: change `source("R/utils_predicates.R")` to `source("R/03_cohort_predicates.R")`
   - The file `R/utils_predicates.R` does not exist; predicates live in `R/03_cohort_predicates.R`

2. **Rename duplicate-numbered script** `R/26_generate_speedup_report.R` to `R/29_generate_speedup_report.R`:
   - Number 26 is already used by `R/26_smoke_test_backends.R` (Phase 30, created first)
   - Numbers 29-32 are free; 29 is the natural next after 28
   - Use `git mv R/26_generate_speedup_report.R R/29_generate_speedup_report.R` to preserve history

3. **Update 3 self-references inside the renamed file** (`R/29_generate_speedup_report.R`):
   - Line 2: header comment `26_generate_speedup_report.R` -> `29_generate_speedup_report.R`
   - Line 30: usage comment `source("R/26_generate_speedup_report.R")` -> `source("R/29_generate_speedup_report.R")`
   - Line 287: glue string `R/26_generate_speedup_report.R` -> `R/29_generate_speedup_report.R`

   NOTE: References in `.planning/phases/32-*/` files are historical records and should NOT be updated.
  </action>
  <verify>
    <automated>grep -c "utils_predicates" 22_multi_source_overlap_detection_TEMPLATE.R && echo "FAIL: stale reference" || echo "PASS: template fixed" && grep -c "26_generate" R/29_generate_speedup_report.R && echo "FAIL: old name in file" || echo "PASS: rename complete"</automated>
  </verify>
  <done>Template references R/03_cohort_predicates.R (which exists). R/26_generate_speedup_report.R renamed to R/29_generate_speedup_report.R with all 3 internal self-references updated. No duplicate script numbers in R/ directory.</done>
</task>

</tasks>

<verification>
After both tasks complete:
1. `git status` shows no untracked dead scripts, stale plans, or __pycache__
2. `ls R/26_*.R` returns only `R/26_smoke_test_backends.R`
3. `ls R/29_*.R` returns `R/29_generate_speedup_report.R`
4. `grep "utils_predicates" 22_multi_source_overlap_detection_TEMPLATE.R` returns no matches
5. `grep "03_cohort_predicates" 22_multi_source_overlap_detection_TEMPLATE.R` returns a match
6. Root directory has no files matching: check_*.R, debug_columns.R, payer_missingness_html.R, *.sas, NN-0N-PLAN.md
</verification>

<success_criteria>
- .gitignore updated with 5 new patterns (__pycache__/, ~$*, /*.pptx, /*.xlsx, /*.txt)
- 5 dead R scripts deleted from root
- 2 abandoned SAS files deleted from root
- 8 stale PLAN.md files deleted from root
- .planning/New folder removed
- 5 previously-deleted PPTX files staged in git
- Template file source() call points to R/03_cohort_predicates.R
- R/26_generate_speedup_report.R renamed to R/29_generate_speedup_report.R with internal refs updated
</success_criteria>

<output>
After completion, create `.planning/quick/260501-gkl-cleanup-code-health-issues-root-clutter-/260501-gkl-SUMMARY.md`
</output>
