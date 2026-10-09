---
phase: 170-r147-rerun-and-verification
plan: "02"
subsystem: smoke-test
tags: [smoke-test, r88, diagnosis-exclusion, downstream-gate]
dependency_graph:
  requires: []
  provides: [SMOKE-163-01 section in R/88, 170-DOWNSTREAM-GATE.md]
  affects: [R/88_smoke_test_comprehensive.R]
tech_stack:
  added: []
  patterns: [p163_chk/p163_skip_note pattern matching 15ar, key=value pointer file gate]
key_files:
  created:
    - .planning/phases/170-r147-rerun-and-verification/170-DOWNSTREAM-GATE.md
  modified:
    - R/88_smoke_test_comprehensive.R
decisions:
  - "Skip branches use p163_skip_note() (never p163_pass increment) so local runs without INTERNAL workbooks report honest 2 PASS / 0 FAIL / 2 SKIP"
  - "DOWNSTREAM-GATE.md uses a pointer file (147_verify_last_pass.txt) rather than VERIFY_RUN_DATE env var so Phases 171/172 work across sessions"
metrics:
  duration: 8m
  completed: 2026-10-09
  tasks: 2
  files: 2
requirements_completed: [RFSH-01]
---

# Phase 170 Plan 02: R/88 SMOKE-163-01 + Downstream Gate Summary

**One-liner:** Section 15as with honest skip reporting (2+2 source checks always run, 2 output checks skip without INTERNAL workbook) and a session-independent pointer-file downstream gate for Phases 171/172.

## Tasks Completed

| # | Name | Commit | Key files |
|---|------|--------|-----------|
| 1 | R/88 Section 15as — SMOKE-163-01 | 5ebacca | R/88_smoke_test_comprehensive.R (+106 lines) |
| 2 | 170-DOWNSTREAM-GATE.md | fb0955e | .planning/phases/170-r147-rerun-and-verification/170-DOWNSTREAM-GATE.md |

## What Was Built

### Task 1: R/88 Section 15as

Inserted between the SMOKE-165-01 footer (Section 15ar) and Section 16 SUMMARY.

Pattern mirrors 15ar with the addition of a skip counter:
- `p163_pass`, `p163_fail`, `p163_skip` counters
- `p163_chk(label, ok)` — increments pass/fail and the global passed/failed
- `p163_skip_note(label, why)` — increments only `p163_skip` (never pass)

Four checks:
1. `EXCLUDED_CDM_TABLES\s*<-` present in R/147 source — always runs
2. `any(grepl("stopifnot", src) & grepl("EXCLUDED_CDM_TABLES", src))` — always runs
3. A_code_presence: no cell == "DIAGNOSIS" (case-insensitive) and no SC039/SC047/SC065/SC090 — skips (not passes) if no INTERNAL workbook found
4. Codeset_summary: no cell matches `(^|[;,[:space:]])Z[0-9]` — skips (not passes) if no INTERNAL workbook found

Footer: `SMOKE-163-01: {p163_pass} PASS / {p163_fail} FAIL / {p163_skip} SKIP`

Section 16 requirements list updated with SMOKE-163-01 entry.

On HiPerGator (Plan 03), Section 15as must report 4 PASS / 0 FAIL / 0 SKIP.

### Task 2: 170-DOWNSTREAM-GATE.md

Handoff document for Phases 171 and 172. Explains the pointer-file mechanism:

- `R/147_verify_vs_1006.R` writes `output/logs/147_verify_last_pass.txt` only on `OVERALL: PASS`
- Pointer file contains `run_date=`, `log=`, `rds=` (key=value, no quotes)
- Gate snippet reads the pointer, validates: pointer exists, dated log contains `OVERALL: PASS`, dated RDS exists
- Optional stale-run warning if a newer INTERNAL workbook exists without a passing verify
- No `VERIFY_RUN_DATE` env var required — works across sessions
- No `which.max(file.mtime())` glob

Includes full rationale table and SLURM job chain context.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — no UI rendering or data flow stubs introduced.

## Self-Check: PASSED

- R/88_smoke_test_comprehensive.R exists: FOUND
- 170-DOWNSTREAM-GATE.md exists: FOUND
- Commit 5ebacca exists: FOUND
- Commit fb0955e exists: FOUND
- Grep "SECTION 15as": FOUND (line 6623)
- Grep "p163_skip": FOUND (multiple lines)
- Grep "/ {p163_skip} SKIP": FOUND (line 6725)
- Grep Z-code pattern: FOUND (line 6711)
- Grep "SC039": FOUND (lines 6687, 6695)
- No `p163_pass <- p163_pass + 1L` in skip branches: CONFIRMED
- Grep "147_verify_last_pass.txt" in GATE.md: FOUND (9 occurrences)
- Grep "OVERALL: PASS" in GATE.md: FOUND
