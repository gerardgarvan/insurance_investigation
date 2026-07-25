# Phase 134: Ingest Integrity and Honest Tests - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-25
**Phase:** 134-ingest-integrity-and-honest-tests
**Areas discussed:** R/82–83 benchmark scripts, R/98 independent baseline, R/88 skip counter

---

## R/82–83: Which 5 Scripts to Benchmark

| Option | Description | Selected |
|--------|-------------|----------|
| R/20, R/21, R/22, R/23, R/24 | Original Phase 32 intent — DBDIAG-01 explicitly names these as the 5 diagnostic scripts | ✓ |
| R/14 + R/20–R/23 | Keep cohort build, add 4 diagnostics | |
| You decide | Claude picks | |

**User's choice:** R/20, R/21, R/22, R/23, R/24
**Notes:** DBDIAG-01 in v1.4 requirements is the authoritative source.

---

## R/98: How to Build an Independent Baseline

| Option | Description | Selected |
|--------|-------------|----------|
| Commit a static fixture from a known-good pre-Phase-98 run | Commit treatment_episodes_pre98_baseline.rds to repo | ✓ |
| Re-run old R/28 code path each time | Dynamic but adds runtime cost | |
| You decide | Claude picks | |

**User's choice:** Commit a static fixture
**Notes:** User didn't know whether a pre-Phase-98 file exists on HiPerGator. Executor decision rule captured in D-12: check existence first, fall back to current-output snapshot with documented caveat.

---

## R/88: Skip Counter Summary Format

| Option | Description | Selected |
|--------|-------------|----------|
| N passed / N failed / N skipped | Three-way breakdown in summary line | ✓ |
| N passed / N failed (skips in body only) | Headline unchanged, skip details in per-check output | |
| You decide | Claude picks | |

**User's choice:** Three-way breakdown — `N passed / N failed / N skipped`
**Notes:** Makes runs with many skips visibly incomplete.

---

## Claude's Discretion

- Per-table pass/fail tracking mechanism in R/03
- Whether `coerce_types()` is removed or bypassed in R/81

## Deferred Ideas

None.
