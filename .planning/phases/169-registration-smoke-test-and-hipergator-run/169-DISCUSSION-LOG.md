# Phase 169: Registration, Smoke Test, and HiPerGator Run — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-08
**Phase:** 169-registration-smoke-test-and-hipergator-run
**Areas discussed:** R/165 placement in R/39, SMOKE-165-01 check design, test-165 scope, HiPerGator run coordination

---

## R/165 Placement in R/39

| Option | Description | Selected |
|--------|-------------|----------|
| Between R/122 and R/147 | Natural dependency order on distance + rurality | |
| Immediately before R/166 (after R/162) | After R/147 (CBC events/anchors also required) | ✓ |

**User's choice:** After R/162, immediately before R/166.
**Notes:** R/165 re-derives CBC from LAB_RESULT_CM directly but requires R/147 to have run first so DuckDB state is stable. R/163 prototype: SCRIPT_INDEX only, not R/39 (one-off, requires survey/geepack, slow).

---

## SMOKE-165-01 Check Design

| Option | Description | Selected |
|--------|-------------|----------|
| Standard structural pattern | File exists, sheet names, KEY leftmost, registered in R/39, test file | partial |
| Standard + config + code-pattern + output-gated | All of the above plus CONFIG checks, no-literal-100, no-quit, binary column, fan-out, suppression | ✓ |

**User's choice:** Extended check set.
**Notes:** CONFIG checks (cutoff == 100, method in allowed set), code-pattern checks (no literal 100, no quit(), no R/4.4.2), output-gated (sheet order, B_test windows, far_from_care_100mi 0/1, one-row-per-ENCOUNTERID, no 1–10 in A_crosstab). 15 checks total.

---

## test-165 File Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Empty placeholder | Always passes; smoke check reports something untrue | |
| Minimal real tests on utils_distance_cbc.R helpers | Tests the actual helpers with meaningful fixtures | ✓ |

**User's choice:** Real minimal tests.
**Notes:** Four specific fixtures: (1) naive_or_se() overflow regression with large integers, (2) suppress_display() boundary behavior, (3) CBC two-day inpatient deduplication, (4) build_pat_analysis() anchor-day exclusion.

---

## HiPerGator Run Coordination

| Option | Description | Selected |
|--------|-------------|----------|
| Acceptance criteria only | State what passes, let runner figure out commands | |
| Exact sbatch commands with dependency chaining | Spell out --parsable, --dependency=afterok, verification steps, paste-back | ✓ |

**User's choice:** Exact commands.
**Notes:** JOB165 → JOB166 → JOB167 → JOB168 → JOB88 with afterok chains. Verification: four dated workbooks + SMOKE footers all PASS + R/88 exit 0. Paste back footer lines and output paths.

---

## Claude's Discretion

- Exact KEY pending-confirmation note wording
- R/88 section helper naming (chk_165, p165_pass, p165_fail)
- Whether CONFIG checks use source() or readLines() (follow adjacent section pattern)

## Deferred Ideas

- 165-CONTEXT.md D-165-01 doc fix (pending Amy/Erin confirmation)
- utils_distance_hist.R SCRIPT_INDEX entry (not in roadmap scope for Phase 169)
