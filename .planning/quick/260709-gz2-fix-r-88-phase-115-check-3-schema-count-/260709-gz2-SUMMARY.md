---
phase: quick-260709-gz2
plan: 01
subsystem: smoke-test
tags: [r88, smoke-test, schema-count, regex, phase-115]
key-files:
  modified:
    - R/88_smoke_test_comprehensive.R
decisions:
  - "Use ^\\s*\\)\\s*$ (anchored standalone-paren regex) instead of \\)\\s*$ + trimws() to safely scan multi-line c() blocks that contain comment lines ending in ')'"
metrics:
  duration: ~5 minutes
  completed: 2026-07-09
  tasks: 1
  files: 1
---

# Quick Task 260709-gz2: Fix R/88 Phase 115 Check 3 Schema Count

One-liner: anchored standalone-paren regex `^\s*\)\s*$` replaces `\)\s*$`+`trimws()` in Check 3's while-loop so R/52's EPISODES_SCHEMA scan counts all 20 entries instead of stopping prematurely on a comment line.

## What Was Done

Fixed a false-negative in R/88 Phase 115 "Check 3" (Section 15k, ~line 1841) where the while-loop that scans R/52's `EPISODES_SCHEMA <- c(...)` block was stopping prematurely on a comment line that happened to end in `)` — specifically `# Phase 115: 7-day confirmed subset + age (+2 columns, now 20 total)`. This caused the scan to count only 18 entries and fail the `== 20` assertion, even though R/52 is correct and genuinely defines 20 schema columns.

## Change Made

**File:** `R/88_smoke_test_comprehensive.R`, line ~1841

**Before (buggy):**
```r
while (r52_schema_end <= length(r52_lines) && !grepl("\\)\\s*$", trimws(r52_lines[r52_schema_end]))) {
```

**After (fixed):**
```r
# WHY: match ONLY a standalone ")" line as the terminator. R/52's EPISODES_SCHEMA
# block has a comment line ending in ")" ("...now 20 total)") one line above the real
# closing ")". The old "\\)\\s*$" terminator stopped on that comment and undercounted
# entries (18 instead of 20). "^\\s*\\)\\s*$" only matches the true closing paren line.
while (r52_schema_end <= length(r52_lines) && !grepl("^\\s*\\)\\s*$", r52_lines[r52_schema_end])) {
```

Key differences:
- `^\s*` and `\s*$` anchors ensure only a line that is ENTIRELY a closing paren (with optional whitespace) terminates the scan
- `trimws()` wrapper dropped — redundant given the anchored regex handles leading/trailing whitespace directly
- WHY comment added explaining the comment-line-ending-in-paren pitfall

## Verification (Structural — Windows-local)

All structural checks passed:

1. New terminator present: `grep -n '^\\s*\\)\\s*$'` matches at line 1845 in the Check 3 while-loop.
2. Old buggy terminator absent: `grepl("\\)\\s*$", trimws(r52_lines[r52_schema_end]))` no longer present in the file for this loop.
3. Assertion unchanged: `schema_entries_115 == 20` still at line 1851.
4. Token regex unchanged: `'"[a-z0-9_]+"'` still at line 1849.
5. WHY comment present: lines 1841-1844 reference "now 20 total" and standalone-paren behavior.
6. R/52 untouched: `git status --short R/52_gantt_v2_export.R` returned empty.
7. Rscript parse: not available locally (Windows-local, no R in PATH) — structural verification accepted per Phase 116/117 precedent.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- Commit `ea5bae6` exists: confirmed via `git log`.
- File `R/88_smoke_test_comprehensive.R` modified: confirmed.
- File `R/52_gantt_v2_export.R` unmodified: confirmed.
