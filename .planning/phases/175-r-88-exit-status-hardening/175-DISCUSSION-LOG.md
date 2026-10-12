# Phase 175: R/88 Exit-Status Hardening - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-12
**Phase:** 175-r-88-exit-status-hardening
**Areas discussed:** Interactive vs non-interactive guard, Skip-as-pass audit, Failure path testing

---

## Interactive vs non-interactive guard

| Option | Description | Selected |
|--------|-------------|----------|
| Replace TESTTHAT with !interactive() | Single condition, simpler | |
| Combine !interactive() + TESTTHAT check | Three-way: stop() / no-op / quit(status=1) | ✓ |
| Keep TESTTHAT only | No change from current | |

**User's choice:** Three-way strategy — interactive: `stop()`, testthat: no-op, non-interactive: `quit(status=1)`. Also add `quit(status=0)` on clean non-interactive run.

**Notes:** The key constraint is that `quit()` in an interactive `source()` call kills the entire R session on HiPerGator. Using `stop()` instead gives a loud, visible failure without ending the session. testthat keeps current no-op so the harness can read FAIL lines directly.

---

## Skip-as-pass audit

| Option | Description | Selected |
|--------|-------------|----------|
| Leave check("…", TRUE) as-is | No change, document the design | |
| Add skip_check(), convert all check("…", TRUE) | Skips excluded from total, reported separately | ✓ |
| Add skip_check(), convert only IS_LOCAL-gated ones | Partial conversion | |

**User's choice:** Add `skip_check(label, reason)` and audit every `check("…", TRUE)` — convert runtime-conditional skips, keep genuine structural assertions as `check()`. Footer becomes `passed / failed / skipped` with total = passed + failed only.

**Notes:** User framed this as finishing what Phase 174 started — counting a skip as a pass has the same problem as counting a fail as a pass. The baseline PASS total will shift downward (~12 fewer); SUMMARY must record new number after HiPerGator run.

---

## Failure path testing

| Option | Description | Selected |
|--------|-------------|----------|
| Temporary check added/removed by hand | Simple, but error-prone | |
| --test-fail CLI flag | Rscript only, doesn't test interactive path | |
| R88_FORCE_FAIL env var + system2() from interactive R | Tests both paths, no cleanup needed | ✓ |

**User's choice:** `R88_FORCE_FAIL=1` env var triggers a sentinel check (always FALSE when set). Test non-interactive via `system2("Rscript", ...)` capturing exit code; test interactive via `Sys.setenv()` + `try(source(...))` with `local = new.env(parent = globalenv())`. Confirm session alive after `stop()`. Run on compute node from Open OnDemand RStudio.

**Notes:** `system2()` return value is the exit code directly — no output parsing needed.

---

## Claude's Discretion

- Exact placement of `skip_check()` definition (adjacent to `check()`)
- Whether `skip_check()` unifies with existing `p163_skip_note()` pattern
- Order of test procedure steps in SUMMARY

## Deferred Ideas

None.
