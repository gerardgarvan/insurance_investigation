---
phase: quick-261114-mpi
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - R/142_gantt_180_export.R
autonomous: true
requirements: [QUICK-261114-MPI]
must_haves:
  truths:
    - "R/142 no longer contains any RUN_PRE201B_REGRESSION block"
    - "R/142 parses cleanly"
  artifacts:
    - path: R/142_gantt_180_export.R
      provides: "gantt 180 export with PRE201B blocks removed"
  key_links: []
---

<objective>
Remove the two RUN_PRE201B_REGRESSION-gated blocks from R/142_gantt_180_export.R.
The PRE201B baseline is copied from the current output file, which already has 32
columns, so the `stopifnot("PRE201B baseline must have 30 columns" = ...)` guard
always fails. The existing PRE201 block (which saves a 26-column baseline, cols 1-26)
is correct and sufficient.

Purpose: Eliminate a permanently-failing regression block so R/142 can run without error.
Output: R/142 with PRE201B save block (lines ~1322-1337) and PRE201B check block
        (lines ~1343-1362) removed.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
</execution_context>

<context>
@.planning/STATE.md
@R/SCRIPT_INDEX.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Remove both RUN_PRE201B_REGRESSION blocks from R/142</name>
  <files>R/142_gantt_180_export.R</files>
  <action>
Delete the two `if (Sys.getenv("RUN_PRE201B_REGRESSION") == "TRUE") { ... }` blocks.

Block 1 — PRE201B baseline save (around line 1322):
  Remove from: `if (Sys.getenv("RUN_PRE201B_REGRESSION") == "TRUE") {`
           to: the matching closing `}` after `message(glue("  PRE201B baseline exists (kept): {pre201b}"))`.
  This block saves a copy of the current OUTPUT_EPISODES, then stopifnots it has 30 columns.
  Leave the blank line between the PRE201 block above and `write.csv(episodes_export, ...)` below intact.

Block 2 — PRE201B regression check (around line 1343):
  Remove from: `if (Sys.getenv("RUN_PRE201B_REGRESSION") == "TRUE") {`
           to: the matching closing `}` before `if (Sys.getenv("RUN_PRE199_REGRESSION") == "TRUE") {`.
  This block reads the saved baseline and runs the row-identity stopifnot.

Do NOT touch: the PRE201 block (which uses `RUN_PRE201_REGRESSION` and saves a 26-col baseline),
the PRE199 block, or any other regression block.
Do NOT modify R/88_smoke_test_comprehensive.R — the [PRE201B] check there only validates
column names 1-26 and is not broken.
  </action>
  <verify>
    <automated>tools/rcheck.sh parse R/142_gantt_180_export.R</automated>
  </verify>
  <done>
`tools/rcheck.sh parse R/142_gantt_180_export.R` exits 0.
`grep -n "RUN_PRE201B_REGRESSION" R/142_gantt_180_export.R` returns no output.
`grep -n "RUN_PRE201_REGRESSION" R/142_gantt_180_export.R` still returns the PRE201 block.
  </done>
</task>

</tasks>

<verification>
grep -n "RUN_PRE201B_REGRESSION" R/142_gantt_180_export.R   # must be empty
grep -c "RUN_PRE201_REGRESSION"  R/142_gantt_180_export.R   # must be >= 1
tools/rcheck.sh parse R/142_gantt_180_export.R              # must exit 0
</verification>

<success_criteria>
No RUN_PRE201B_REGRESSION text remains in R/142. R/142 parses cleanly. The PRE201
(26-column) block is intact.
</success_criteria>

<output>
After completion, create `.planning/quick/261114-mpi-r142-remove-pre201b-regression-block-use/261114-mpi-SUMMARY.md`
</output>
