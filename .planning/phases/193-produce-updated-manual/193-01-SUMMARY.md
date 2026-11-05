---
phase: 193-produce-updated-manual
plan: 01
subsystem: tools/am_evidence
tags: [ooxml, preflight, docx, lxml, python]
dependency_graph:
  requires: [190-evidence-map/am_source_hashes.txt, docs/analytic_manual/AnalyticManual_2026.01.30.docx]
  provides: [tools/am_evidence/am_manual_lib.py, 193-PREFLIGHT.md]
  affects: [193-02, 193-03]
tech_stack:
  added: [lxml, zipfile, hashlib]
  patterns: [OOXML unpack/repack via zipfile, Clark-notation namespace helpers, ID-space enumeration]
key_files:
  created:
    - tools/am_evidence/am_manual_lib.py
    - .planning/phases/193-produce-updated-manual/193-PREFLIGHT.md
  modified: []
decisions:
  - "Live para_id count is 517 (not 515 as in RESEARCH.md summary) — see note below"
  - "Safe paraId start confirmed as 7FF8A73F (max is 7FF8A73E, matches RESEARCH.md)"
metrics:
  duration: ~8 minutes
  completed: 2026-11-05
  tasks: 2
  files: 2
---

# Phase 193 Plan 01: Preflight Inventory and Helper Library Summary

Shared OOXML helper library created and preflight inventory generated from live DOCX read. Original document is byte-for-byte unchanged (SHA-256 verified).

## Tasks Completed

### Task 0: am_manual_lib.py

- Created `tools/am_evidence/am_manual_lib.py` (207 lines, lxml-only, no python-docx).
- Implements exact interface signatures from the plan: `NS`, `qn()`, `sha256()`, `unpack_docx()`, `repack_docx()`, `AnchorFailed`, `get_para_text()`, `find_anchor_para()`, `scan_id_space()`, `PINNED_ORIGINAL_SHA256`.
- Verification passed: `python -c "import am_manual_lib as m; ..."` printed `[0, 1] 517` and exited 0; SHA-256 assertion passed.

### Task 1: 193-PREFLIGHT.md

- Ran a temporary inspection script (deleted after use) using `am_manual_lib` + python-docx (READ-ONLY).
- All 6 grep acceptance checks passed.
- Preflight written to `.planning/phases/193-produce-updated-manual/193-PREFLIGHT.md` (176 lines).

## Notable Findings from Live DOCX

| Item | RESEARCH.md expected | Live value | Status |
|------|----------------------|------------|--------|
| SHA-256 | `2e119764...` | `2e119764...` | MATCH |
| w_ids | {0, 1} | {0, 1} | MATCH |
| Max w14:paraId | `7FF8A73E` | `7FF8A73E` | MATCH |
| paraId count | 515 | 517 | DISCREPANCY (+2) |
| w:trackChanges in settings.xml | NOT present | NOT present | MATCH |
| c0 body paraId | `4AFA1B64` | `4AFA1B64` | MATCH |
| c1 body paraId | `0EC496CC` | `0EC496CC` | MATCH |
| c0 anchor paraId | `7AA45245` | `7AA45245` | MATCH |
| c1 anchor paraId | `106EBCC1` | `106EBCC1` | MATCH |
| §8 has table | NO table | NO table | MATCH |
| Date last updated para_idx | — | 8 | NEW (live) |
| Document version para_idx | — | 7 | NEW (live) |

**paraId count discrepancy (+2):** RESEARCH.md stated 515 total; live scan reports 517. This likely reflects two paraIds in comments.xml comment body paragraphs being counted by the scanner but not by the original inspection. The max is unchanged at `7FF8A73E`; safe start `7FF8A73F` stands.

## Deviations from Plan

None — plan executed exactly as written. Temporary inspection script was deleted as instructed.

## Artifacts Produced

| Artifact | Path | Lines | Purpose |
|----------|------|-------|---------|
| Helper library | `tools/am_evidence/am_manual_lib.py` | 207 | Shared OOXML helpers for Plans 02 and 03 |
| Preflight inventory | `.planning/phases/193-produce-updated-manual/193-PREFLIGHT.md` | 176 | D-11: ID space, parts, comments, locations |

## Self-Check: PASSED

- `tools/am_evidence/am_manual_lib.py` exists and imports cleanly.
- `.planning/phases/193-produce-updated-manual/193-PREFLIGHT.md` exists with 176 lines.
- Commits: `28e42cd` (am_manual_lib.py), `785e608` (193-PREFLIGHT.md).
- Original DOCX SHA-256 unchanged (verified by `m.sha256(DOCX_PATH) == m.PINNED_ORIGINAL_SHA256`).
