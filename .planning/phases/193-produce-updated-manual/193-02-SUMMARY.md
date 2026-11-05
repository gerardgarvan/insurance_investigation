---
phase: 193-produce-updated-manual
plan: "02"
subsystem: am-manual-tooling
tags: [operation-manifest, anchor-resolution, d13, build-operations]
dependency_graph:
  requires: [193-01-PREFLIGHT]
  provides: [193-OPERATIONS.json, build_operations()]
  affects: [193-03-engine]
tech_stack:
  added: []
  patterns: [lxml-anchor-matching, _parse_draft-enumeration, d34-metadata-stripping]
key_files:
  created:
    - tools/am_evidence/build_operations_json.py
    - .planning/phases/193-produce-updated-manual/193-OPERATIONS.json
  modified:
    - tools/am_evidence/am_manual_lib.py
key_decisions:
  - "COMMENT-ONLY ops for OPEN-QUESTION-SEE-§8 use draft text as anchor_text; all 8 fail anchor resolution because that text does not exist in the original DOCX — Plan 03 engine must supply the existing-DOCX anchor for each"
  - "§8 INSERT-TABLE carries all 41 rows with columns Item|Notes|Date added (Map ID/Status/Cite stripped per D-34)"
  - "REPLY ops resolve OK: c0 anchors to para '4. Data Cleaning and Harmonization Rules', c1 anchors to 'Use diagnosis date from Tumor Registry as default.'"
metrics:
  duration: "~45 minutes"
  completed: "2026-11-05"
  tasks_completed: 2
  files_modified: 3
---

# Phase 193 Plan 02: Operation Manifest Classifier Summary

Implements `build_operations()` in `tools/am_evidence/am_manual_lib.py` and produces `193-OPERATIONS.json` with 183 classified operations and anchor resolution results.

## What Was Done

### Task 0: build_operations() classifier

Added `build_operations(draft_path, preflight) -> list[dict]` to `am_manual_lib.py`. The function:

- Imports and calls `_parse_draft()` from `am_evidence_map.py` for unit enumeration.
- Classifies every unit per the RESEARCH "Operation Classification Logic" table into one of: INSERT-PARA, INSERT-ROW, INSERT-TABLE, REPLACE, COMMENT-ONLY, REPLY, PLACEHOLDER.
- §8: emits exactly one INSERT-TABLE op carrying all 41 §8 rows with columns Item | Notes | Date added (Map ID/Status/Cite stripped per D-34).
- REPLY ops: two ops with parent_para_id from preflight (c0: `4AFA1B64`, c1: `0EC496CC`).
- D-34 stripping: removes `[S4-…]` tags, STATUS: lines, CITE: lines from insert_text.
- op_ids assigned OP-001…OP-183 by deterministic line_num sort.

### Task 1: Anchor resolution and 193-OPERATIONS.json

Script `build_operations_json.py` runs dry-run anchor matching via `find_anchor_para()` against the original DOCX (read-only). Writes `193-OPERATIONS.json` with `build_meta`, `expected_counts`, and `operations`.

## Action Histogram

| Action | Count |
|--------|-------|
| INSERT-PARA | 95 |
| INSERT-ROW | 42 |
| PLACEHOLDER | 31 |
| COMMENT-ONLY | 8 |
| REPLACE | 4 |
| INSERT-TABLE | 1 |
| REPLY | 2 |
| **Total** | **183** |

## Anchor Resolution Summary

| Resolution | Count |
|-----------|-------|
| OK | 175 |
| ANCHOR-FAILED | 8 |

**ANCHOR-FAILED ops:** OP-004, OP-022, OP-038, OP-046, OP-068, OP-078, OP-142, OP-154 — all are COMMENT-ONLY ops for OPEN-QUESTION-SEE-§8 units. These ops use the draft content as anchor_text; that text is new content not present in the original DOCX. The anchor_text for these ops needs to reference existing DOCX paragraph text. Resolution: Plan 03 engine must map each OPEN-QUESTION unit to the existing DOCX field paragraph and update the anchor_text before applying.

The 2 CORRECTION REPLACE ops (S4-INS-03, S4-DIST-06) resolved OK. Both front-matter REPLACE ops resolved OK. Both REPLY ops resolved OK.

## Deviations from Plan

### Auto-identified Issues

**1. [Rule 2 - Missing functionality] COMMENT-ONLY anchor_text uses draft content, not existing DOCX text**

- **Found during:** Task 1 anchor dry-run
- **Issue:** 8 COMMENT-ONLY ops for OPEN-QUESTION-SEE-§8 have anchor_text derived from the draft bullet content. The existing DOCX does not contain that text; the anchor match correctly returns 0 matches (ANCHOR-FAILED).
- **Impact:** These ops cannot be applied by the Plan 03 engine until their anchor_text values are updated to match the actual existing DOCX paragraph text for each §4 field.
- **Not fixed here:** Fixing requires mapping each OPEN-QUESTION map ID to its DOCX field paragraph — this requires preflight data linking map IDs to para_index values, which is out of scope for Plan 02. The failures are surfaced correctly per D-12a.
- **Recommendation for Plan 03:** For each ANCHOR-FAILED COMMENT-ONLY op, look up the §4 domain label paragraph by section heading + field label pattern, and replace anchor_text with the existing DOCX paragraph text.

## Known Stubs

None. All ops have complete classification data. Anchor failures are documented and expected.

## Self-Check: PASSED

- `193-OPERATIONS.json` exists: YES
- `am_manual_lib.py` contains `build_operations`: YES
- Commit `5e09955` (Task 0): FOUND
- Commit `59a1d25` (Task 1): FOUND
