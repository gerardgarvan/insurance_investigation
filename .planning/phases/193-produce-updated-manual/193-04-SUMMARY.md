---
phase: 193-produce-updated-manual
plan: "04"
subsystem: analytic-manual
tags: [docx-build, evidence-workbook, d15-qa, reconciliation, manual-export]
dependency_graph:
  requires: [193-03-PLAN.md, 193-OPERATIONS.json]
  provides: [output/am_evidence_20261028.xlsx, tools/am_evidence/am_evidence_map.py:cmd_manual_export]
  affects: [.planning/STATE.md]
tech_stack:
  added: []
  patterns: [openpyxl UF-colour workbook, D-15 QA suite, reconciliation by alloc counter]
key_files:
  created:
    - output/am_evidence_20261028.xlsx
  modified:
    - tools/am_evidence/am_evidence_map.py
    - tools/am_evidence/am_manual_lib.py
    - docs/analytic_manual/AnalyticManual_2026.10.28.docx
    - .planning/phases/193-produce-updated-manual/193-OPERATIONS.json
    - .planning/STATE.md
decisions:
  - "D-193-01 resolved: new versioned copy used (default)"
  - "Export regression uses existing Phase 190 xlsx SHA-256 (not re-run) — openpyxl is non-deterministic"
  - "Reconciliation extended to cover make_tracked_row sub-IDs (rev_id+1, rev_id+2 by default arithmetic)"
metrics:
  duration: "~45 min"
  completed: "2026-11-05"
  tasks: 2
  files: 5
---

# Phase 193 Plan 04: manual-export Subcommand + D-15 QA + Evidence Workbook Summary

**One-liner:** `cmd_manual_export` builds AnalyticManual_2026.10.28.docx via apply_operations, runs the full D-15 suite (package checks, reconciliation, pandoc, LibreOffice), verifies the Phase 190 export is unchanged, and writes a 4-sheet UF-coloured evidence workbook with KEY leftmost.

## Tasks Completed

### Task 0: cmd_manual_export subcommand + D-15 QA suite + export regression

Added `cmd_manual_export(args)` and `_get_export_sha()` to `tools/am_evidence/am_evidence_map.py`.
Added `manual-export` parser and `elif` branch to `main()`.

Steps executed by the subcommand:
1. Export regression (pre): SHA-256 of `am_evidence_20261027.xlsx` recorded.
2. DOCX build: `am_manual_lib.apply_operations()` called; AnalyticManual_2026.10.28.docx written.
3. D-15 suite: package checks, reconciliation, pandoc cross-check, LibreOffice (SKIP).
4. Export regression (post): same file SHA-256 confirmed unchanged.
5. Workbook written: `output/am_evidence_20261028.xlsx` (KEY, Operations, Open Items, Reconciliation).
6. Summary printed.

**D-15 results:**
| Check | Result |
|-------|--------|
| Package checks (XML well-formedness, _rels, uniqueness, comment parity) | PASS |
| Reconciliation (every build ID → one op; every APPLIED op ID in XML) | PASS |
| pandoc cross-check | PASS: pandoc ran OK; output 112,255 chars |
| LibreOffice PDF render | SKIP: soffice not found on PATH |
| Export regression (Phase 190 xlsx) | PASS: unchanged (9d8b7eaf...) |

**Build outputs:**
- Output DOCX SHA-256: `74ebe4e05ec5d805cd850bf5fc3f4cc922adca12ae36810e5158fe4761f663e1`
- Revisions issued: 324; Comments added: 12
- c0 reply: THREADED-REPLY; c1 reply: THREADED-REPLY
- Workbook sheets: `['KEY', 'Operations', 'Open Items', 'Reconciliation']`

**Workbook content:**
- KEY: build ID, original SHA-256, output SHA-256, column definitions, reply outcomes, Phase 191 record reference, all D-15 QA results, privacy note, sheet guide.
- Operations: 183 rows — op_id, section, map_ids, action, inserted_text (truncated 500 chars), anchor_text, revision_ids, comment_ids, citations, verdict, decision_id, status (APPLIED/ANCHOR-FAILED).
- Open Items: 41 §8 table rows as inserted (Item | Notes | Date added).
- Reconciliation: per-ID pass/fail rows; failures shown in red; PASS rows in green.

### Task 1: Advance STATE.md to AUTOMATED-QA-PASSED

Updated `.planning/STATE.md`:
- Phase 193 position set to AUTOMATED-QA-PASSED.
- Recorded: output DOCX filename and SHA-256, evidence workbook filename, reply outcomes (c0/c1=THREADED-REPLY), D-15 QA results, D-193-01 resolution.
- Explicitly stated: WORD-REVIEW-APPROVED is the remaining gate; Phase 193 NOT complete until Plan 05 passes.
- Phase Map updated to `AUTOMATED-QA-PASSED (awaiting WORD-REVIEW-APPROVED)`.
- All prior STATE.md content preserved (milestone v3.13, Phase Map, Accumulated Context, Open Decisions).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed ID accumulation across --overwrite re-runs in apply_operations**
- **Found during:** Task 0, reconciliation step
- **Issue:** `apply_operations` used `setdefault("revision_ids", []).extend(...)` without clearing first; on a second run, IDs from the first run remained, and new IDs were appended, creating duplicates and an inflated manifest.
- **Fix:** Reset `op["revision_ids"] = []` and `op["comment_ids"] = []` for all ops before the main application loop.
- **Files modified:** `tools/am_evidence/am_manual_lib.py`
- **Commit:** 9d0d720

**2. [Rule 1 - Bug] Fixed untracked IDs from make_tracked_row default arithmetic**
- **Found during:** Task 0, reconciliation step
- **Issue:** `make_tracked_row` uses `run_rev_id = rev_id + 1` (default arithmetic, not alloc counter) for paragraph marks and cell runs. Those IDs appeared in the XML but were not in any op's `revision_ids`.
- **Fix:** In apply_operations, after each op, capture any alloc-issued IDs not yet in `revision_ids` or `comment_ids` and append them (by comparing counter before/after `_apply_single_op`).
- **Additional fix:** In `_reconcile`, extend the `rev_id_to_op` lookup to cover `rid+1` and `rid+2` for each INSERT-TABLE/INSERT-ROW op's row IDs (covering the implicit sub-ID pattern).
- **Files modified:** `tools/am_evidence/am_manual_lib.py`, `tools/am_evidence/am_evidence_map.py`
- **Commit:** 9d0d720

**3. [Rule 1 - Bug] Fixed export regression to use existing file SHA-256**
- **Found during:** Task 0, Step 4
- **Issue:** Original plan called `_run_export_to_temp()` before and after to compare output. openpyxl workbooks are not byte-deterministic (ZIP timestamps differ between runs), so pre ≠ post even with identical content.
- **Fix:** Replaced two-run comparison with a single SHA-256 of the existing Phase 190 export xlsx (`am_evidence_20261027.xlsx`), confirming `manual-export` did not modify that file.
- **Files modified:** `tools/am_evidence/am_evidence_map.py`
- **Commit:** 9d0d720

## Known Stubs

None. The workbook is fully wired from the manifest and the DOCX build output.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| `output/am_evidence_20261028.xlsx` exists | FOUND |
| `docs/analytic_manual/AnalyticManual_2026.10.28.docx` exists | FOUND |
| commit 9d0d720 exists | FOUND |
| STATE.md contains AUTOMATED-QA-PASSED | PASS |
| STATE.md names AnalyticManual_2026.10.28.docx | PASS |
| STATE.md contains WORD-REVIEW-APPROVED | PASS |
