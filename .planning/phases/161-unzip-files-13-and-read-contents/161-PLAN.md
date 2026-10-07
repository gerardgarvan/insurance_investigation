# Phase 161 — Plan

Depends on: decisions in 161-CONTEXT.md. 161-01 and 161-02 can proceed before team
sign-off on D1/D2/D6. 161-03 onward implements the agreed rules.

| Task | Wave | Depends on | Sign-off |
|---|---|---|---|
| 161-01 Snapshot R/147 outputs; locate and fix DEATH_DATE_IMPUTE loss; rebuild | 1 | — | no |
| 161-02 Re-run diagnostic; conflicting-date counts; projected person-years | 2 | 161-01 | no |
| 161-03 `get_last_activity()` + `resolve_death_date()` + sensitivity table | 3 | 161-02 | D1, D2 |
| 161-04 `compute_followup()`: shared activity, resolved death, 3-level status | 4 | 161-03 | D6 |
| 161-05 R/147 reporting, sensitivity exclusion, anchor-day rule | 5 | 161-03, 161-04 | no |
| 161-06 Tests + R/88 assertions | 5 | 161-03, 161-04 | no |
| 161-07 Audit DEATH-reading scripts | 5 | 161-03, 161-04 | no |
| 161-08 Full pipeline re-run, before/after comparison, close phase | 6 | all | no |

## 161-01 Snapshot, locate flag loss, fix ingest
- Copy current R/147 outputs to `output/before_161/` before any code change.
- Trace `DEATH_DATE_IMPUTE` from raw extract → R/01 → RDS cache → R/03 → DuckDB
  to find where B/D/M values become NULL; fix at that point, rebuild cache/DuckDB.
- R/03 guard stops (does not coerce) if the column arrives as Date.
- Audit: no column typed DATE whose name does not end in `_DATE`.

## 161-02 Re-run diagnostic
- Add section 8b (row-level DEATH: conflicting dates, DEATH_SOURCE, imputation,
  projected person-years under D2/D3); record numbers in 161-CONTEXT.md.

## 161-03 Shared utilities (D4)
- `R/utils/utils_activity.R::get_last_activity()` — same sources as the diagnostic.
- `R/utils/utils_death.R::resolve_death_date()`, `death_sensitivity_table()`.
- Driver `R/161_death_sensitivity.R`; reproduces 261 (post_death_activity_days > 30).

## 161-04 compute_followup()
- `obs_end` from `get_last_activity()`; `death_date_resolved` in `pmin()`;
  D6 rule; `fu_status` positive/zero/negative + `fu_reason`; carry `death_flag`.

## 161-05 R/147
- Use shared utilities; flag × status summary; sensitivity excluding flagged
  patients; anchor-day events = pre.

## 161-06 Tests and R/88
- Fixtures for every `death_flag`, grace boundary, source priority, D6,
  inpatient discharge extension; R/88 type/population and no-negative assertions.

## 161-07 Audit
- Every DEATH-reading script updated or exempted with a stated reason; audit CSV.

## 161-08 Re-run and close
- Full pipeline via R/39; before/after vs `output/before_161/`; person-years vs
  161-02 projection; final numbers in 161-CONTEXT.md; commit aggregates only.
