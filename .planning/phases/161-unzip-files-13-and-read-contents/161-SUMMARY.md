---
plan: 161
status: complete
date: 2026-10-06
---

# Phase 161 Summary — Death-date plausibility, shared activity definition, follow-up end

## Plans completed

| Plan | What was built |
|------|----------------|
| 161-01 | Snapshot baseline; fixed DEATH_DATE_IMPUTE ingest (VARCHAR, not NULL) |
| 161-02 | Person-year projection after D2/D3; death flag diagnostic |
| 161-03 | `resolve_death_date()` + `get_last_activity()` shared utilities |
| 161-04 | `compute_followup()` rewritten: resolved death, shared activity, 3-level fu_status |
| 161-05 | R/147 updated to shared utilities; sensitivity exclusion; anchor-day rule |
| 161-06 | Tests (test-161-death-plausibility.R) + R/88 assertions A and B |
| 161-07 | Audit of all DEATH-reading scripts; 161_death_audit.csv |
| 161-08 | Pipeline re-run; smoke test fixes (261006-f04); before/after skipped (no snapshot) |

## Key outcomes

- All death-date endpoint scripts now use `resolve_death_date(grace=30)` or carry an
  explicit exemption comment (`[161-07 audit]`).
- R/52 and R/142 Gantt exports no longer plot implausible death markers.
- R/120 and R/121 detect PATID vs ID automatically.
- R/88 passes 863/863 checks after 261006-f04 fixes.
