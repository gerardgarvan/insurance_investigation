---
phase: 191-verify-existing-entries
plan: "03"
subsystem: analytic-manual-verification
tags: [verification, verdicts, export, evidence-map, openpyxl]
dependency_graph:
  requires: [AM-VERDICTS.md, AM-EVIDENCE-MAP.md (AM-MAP-03), 191-02-SUMMARY.md]
  provides: [am_verdicts_20261027.xlsx, verdicts-export subcommand]
  affects: [tools/am_evidence/am_evidence_map.py, .planning/STATE.md]
tech_stack:
  added: []
  patterns: [verdicts-export subcommand, count-lint proximity check, round-trip xlsx verification]
key_files:
  created:
    - .planning/phases/191-verify-existing-entries/am_verdicts_20261027.xlsx
    - .planning/phases/191-verify-existing-entries/191-03-SUMMARY.md
  modified:
    - tools/am_evidence/am_evidence_map.py
    - .planning/STATE.md
decisions:
  - "Count-lint excludes hyphenated number compounds (5-digit, 9-digit) and comma-formatted large numbers (1,344) — these are not small-cell violations"
  - "Workbook date suffix taken from today (2026-10-27) per --date default; verdicts-export exits 0 on clean run"
metrics:
  duration_minutes: 40
  completed_date: "2026-10-28"
  tasks_completed: 3
  tasks_total: 3
  files_created: 2
  files_modified: 2
---

# Phase 191 Plan 03: Verdicts Export Summary

**One-liner:** `verdicts-export` subcommand added to `am_evidence_map.py`; `am_verdicts_20261027.xlsx` produced with 24 verdicts, 5 sheets (KEY leftmost), 10 gaps rows, 8 D-191 decisions; STATE.md pointer added.

## Workbook

**Filename:** `am_verdicts_20261027.xlsx`
**Location:** `.planning/phases/191-verify-existing-entries/`

### Verdict Counts

| Verdict | Count |
|---------|-------|
| MATCH | 14 |
| MISMATCH | 6 |
| PARTIAL | 2 |
| CANNOT-VERIFY | 1 |
| BLOCKED | 1 |
| **Total** | **24** |

### D-191 Decisions

| Status | Count |
|--------|-------|
| OPEN | 6 |
| CONFIRMED | 2 |
| **Total** | **8** |

### Gaps (10 rows)

| Source | Rows |
|--------|------|
| BLOCKED verdict (S4-CMNT-01) | 1 |
| CANNOT-VERIFY verdict (S4-DX-01) | 1 |
| Incomplete leads (L2, L3, L4, L5, L6, L7, L8, L9) | 8 |

## Workbook Sheets

1. **KEY** — title, generated date, query workbook, sources, verdict/evidence definitions, decision status meanings, privacy note, sheet guide
2. **Verdicts** — 24 rows; MISMATCH/PARTIAL cells orange; BLOCKED/CANNOT-VERIFY cells grey
3. **Lead Summary** — L1–L9 + Other items; Overall, Rests on, Complete
4. **Decisions** — 8 D-191-NN rows from AM-MAP-03 only
5. **Gaps** — 10 rows combining blocked/unverifiable verdicts and incomplete leads

## STATE.md Pointer

Added to Open Team Decisions table:
```
D-191-01..08 — see AM-EVIDENCE-MAP.md AM-MAP-03 (6 open, 2 manual-update-only)
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Count-lint false positives on hyphenated numbers and comma-formatted counts**

- **Found during:** Task 2 (first verdicts-export run)
- **Issue:** `_count_lint_check()` matched "5" in "5-digit" (hyphenated compound, not a small count) and "1" in "1,344 patients" (a comma-formatted number above 10, not a small-cell count). Three false positive failures blocked export.
- **Fix:** Updated `_count_lint_check()` to exclude tokens containing hyphens and to skip numbers where the adjacent token starts with a comma or digit (indicating a larger comma-formatted number).
- **Files modified:** `tools/am_evidence/am_evidence_map.py`
- **Commit:** `5a8700f`

No upstream fixes to AM-VERDICTS.md or AM-EVIDENCE-MAP.md were required; all 24 verdicts passed integrity checks on the first post-fix run.

## Known Stubs

None. All 24 required IDs have verdicts. The 6 OPEN D-191-NN decisions are open team questions, not stubs in the exported workbook.

## Self-Check

### Files exist

- `.planning/phases/191-verify-existing-entries/am_verdicts_20261027.xlsx` — created
- `tools/am_evidence/am_evidence_map.py` — modified (verdicts-export subcommand)
- `.planning/STATE.md` — modified (D-191-01..08 pointer)

### Commits

- `9ce0905` — Task 0+1: verdicts-export subcommand added
- `5a8700f` — Task 2: export run, count-lint fixed, STATE.md pointer added

## Self-Check: PASSED
