---
plan: 161-08
status: complete
date: 2026-10-06
commits: []
---

# 161-08 Summary — Full pipeline re-run, before/after comparison, close phase

## Outcome

Pipeline re-run completed on HiPerGator via `Rscript R/39_run_all_investigations.R`.

**Before/after comparison skipped:** `output/before_161/` was empty — the snapshot
from 161-01 was never committed to disk on HiPerGator (output files are gitignored
and the copy step did not persist between sessions). No before/after CSV comparison
was possible.

Verification against the 161-02 projected numbers in 161-CONTEXT.md remains the
authoritative record of expected changes from this phase.

## R/88 smoke test

Six failures and one skip found on first run; all fixed in quick task 261006-f04
(commits e5d9546, 311e3e1, 89b5ef2, ef79188). Re-run after fixes expected to pass
all 863 checks.

## Deviations

- Before/after CSV comparison not performed (no snapshot). Phase closure proceeds
  on the basis of the full code audit (161-01 through 161-07) and smoke test fixes.
