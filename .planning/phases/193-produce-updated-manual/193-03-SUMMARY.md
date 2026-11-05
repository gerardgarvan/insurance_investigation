---
phase: 193-produce-updated-manual
plan: 03
subsystem: analytic-manual
tags: [ooxml, tracked-changes, comments, docx, python]
dependency_graph:
  requires: [193-02]
  provides: [AM-DOC-01, AM-DOC-02]
  affects: [193-04]
tech_stack:
  added: []
  patterns: [lxml OOXML editing, zipfile unpack/repack, tracked-change builders, comment threading]
key_files:
  created:
    - tools/am_evidence/am_manual_lib.py (tracked-change builders + apply_operations, Plan 03 additions)
    - tools/am_evidence/tests/test_am_manual_lib.py
    - tools/am_evidence/run_apply.py
    - docs/analytic_manual/AnalyticManual_2026.10.28.docx
  modified:
    - .planning/phases/193-produce-updated-manual/193-OPERATIONS.json (anchor fixes + recorded IDs)
decisions:
  - "make_tracked_row must replace ALL cell paragraphs to avoid copying pre-existing w14:paraId values into every deep copy of the template row"
  - "commentRangeStart, commentRangeEnd, and commentReference all use the same w:id as the comment (verified from live DOCX)"
  - "header row of §8 table is also a tracked insertion so reject-all removes the entire table"
  - "w:tr elements can carry w14:paraId; must be stripped from deep-copied template rows"
metrics:
  duration_minutes: ~90
  tasks_completed: 2
  files_modified: 4
  completed_date: "2026-11-05"
---

# Phase 193 Plan 03: OOXML Insertion Engine and Versioned DOCX Summary

Produced `AnalyticManual_2026.10.28.docx` with all 183 manifest operations applied as Gerard Garvan tracked changes; reject-all integrity proof and accept-all content proof both pass; original byte-for-byte unchanged.

## Pre-task: Anchor Fix Results

8 ANCHOR-FAILED ops in 193-OPERATIONS.json had anchor_text set to new draft content (not yet in DOCX). Fixed by substituting the actual DOCX text from the target paragraph for each op:

| Op | Map ID | Old anchor (draft) | New anchor (DOCX) | para_index |
|----|--------|-------------------|-------------------|-----------|
| OP-004 | S0-FM-04 | "Data sources: EHR (primary)..." | "Data sources: EHR (primary), Claims (secondary)" | 4 |
| OP-022 | S2-COH-03 | "Index Date Definition: The earliest HL..." | "Index Date Definition: " | 49 |
| OP-038 | S4-DXDT-03 | "Cleaning Rules Applied: The pipeline..." | "Use diagnosis date from Tumor Registry as default." | 123 |
| OP-046 | S4-DX-03 | "Cleaning Rules Applied: Two separate..." | " Only counting cancer diagnoses with at least..." | 143 |
| OP-068 | S4-DTH-03 | "Cleaning Rule — grace window: If a death..." | "If death date is 14 days prior to last treatment encounter, ignore death" | 200 |
| OP-078 | S4-DIST-03 | "Cleaning Rule — distance method: Distance..." | "Using the zipcodeR package to calculate distance..." | 223 |
| OP-142 | S5-REC-02 | "Record provenance: Whether claims-derived..." | "Variables where Claims is authoritative: " | 232 |
| OP-154 | S11-LIM-02 | "Claims and LNK source status: Whether..." | "Limitations related to claims completeness or lag: " | 308 |

All 8 anchors verified unique (exactly 1 match each). `expected_counts.n_anchor_failed` set to 0.

## Pytest Results

```
21 passed in 0.09s
```

Tests cover: IdAllocator next_w_id/next_para_id, make_tracked_paragraph structure (pPr/rPr/ins mark + ins run), xml:space=preserve for leading/trailing space, reject_all removes inserted paragraph, accept_all keeps inserted text, apply_correction round-trip (reject→"foo BAR baz", accept→"foo QUX baz"), enable_track_revisions idempotency.

## run_apply.py Output

```
[1/14] Original SHA-256 verified: 2e119764b63cf9e4...
[2/14] No ANCHOR-FAILED ops. Total ops: 183
[4/14] Copied and unpacked DOCX: 20 parts
[5/14] IdAllocator ready. w:id starts at 2, paraId starts at 7FF8A73F
[6/14] Collected 473 original paragraph texts
[7/14] Operations applied. reply_outcomes: {'c0': 'THREADED-REPLY', 'c1': 'THREADED-REPLY'}
[8/14] w:trackChanges enabled in settings.xml
[9/14] Well-formedness checks passed
[10/14] Reject-all proof PASSED (473 paragraphs)
[11/14] Accept-all proof PASSED
[12/14] Untouched-content verified via reject-all equality in step 10
[13/14] DOCX repacked to AnalyticManual_2026.10.28.docx
[14/14] Original re-verified unchanged: 2e119764b63cf9e4...

n_revisions:    324
n_comments:     12
reply_outcomes: {'c0': 'THREADED-REPLY', 'c1': 'THREADED-REPLY'}
```

## Reject-all and Accept-all Proof Outcomes

- **Reject-all:** PASSED — 473 paragraphs; text equals original exactly.
- **Accept-all:** PASSED — all inserted texts found in result.
- Both proofs run inside `apply_operations()` on deep copies; a successful run is itself the proof.

## Output DOCX

- **Path:** `docs/analytic_manual/AnalyticManual_2026.10.28.docx`
- **SHA-256:** `c55dc51cf5f8df22594cb1e2f9f29e8c400af7f8b31e7acf4d5c78caa1c97504`
- **Contains:** `w:trackChanges` in settings.xml, `w:author="Gerard Garvan"` in document.xml.
- **Original SHA-256:** `2e119764b63cf9e491decc1177ff38ea49335cd2f15673b9e92b68a127a1517d` (unchanged, verified twice).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] commentRangeStart/End/Reference incorrect placement**
- **Found during:** Task 1 (well-formedness / paraId uniqueness failure)
- **Issue:** `_add_comment_to_doc` was inserting `commentRangeStart` and `commentRangeEnd` as siblings of the anchor paragraph in the body, and creating a new `w:p` for the `commentReference`. The correct OOXML pattern (verified from live DOCX) puts all three as children of the anchor paragraph itself, all sharing one w:id.
- **Fix:** Revised to append commentRangeStart, commentRangeEnd, and a commentReference run as direct children of the anchor paragraph; allocated only one w:id (the comment id) for all three.
- **Files modified:** `tools/am_evidence/am_manual_lib.py` (`_add_comment_to_doc`)
- **Commit:** a5eec20

**2. [Rule 1 - Bug] make_tracked_row copies pre-existing w14:paraId into each row copy**
- **Found during:** Task 1 (paraId uniqueness failure — 5 paraIds each appearing 43 times)
- **Issue:** `zip(tcs, cells_text)` stopped at the shorter list (cells_text had 1 item; template had 5 cells), leaving 4 cells per row with the copied pre-existing paraIds. Additionally, `w:tr` elements carry their own `w14:paraId` which was duplicated into every deep copy of the template row.
- **Fix:** (a) Replace ALL cells in every deep-copied row, using `""` for extra cells. (b) Strip `w14:paraId` from the copied `w:tr` before use.
- **Files modified:** `tools/am_evidence/am_manual_lib.py` (`make_tracked_row`)
- **Commit:** a5eec20

**3. [Rule 1 - Bug] §8 table header row not tracked — rejected document had different paragraph count**
- **Found during:** Task 1 (reject-all proof failure — para 273 showed "Item" instead of original text)
- **Issue:** The §8 table header row was inserted as permanent (untracked) content. After reject-all removed the tracked data rows, the untracked header row remained, shifting all subsequent paragraphs.
- **Fix:** Made the header row also a tracked insertion via `make_tracked_row`.
- **Files modified:** `tools/am_evidence/am_manual_lib.py` (`_insert_s8_table`)
- **Commit:** a5eec20

## Known Stubs

None. All 183 ops applied. INSERT-PARA, INSERT-ROW, INSERT-TABLE, REPLACE, PLACEHOLDER, COMMENT-ONLY, and REPLY actions all functional. The `[TEAM INPUT NEEDED]` placeholders in the output DOCX are intentional (they represent TEAM-INPUT-NEEDED units from the draft) and are themselves tracked insertions.

## Self-Check

All 5 key files exist. All commits exist: 9c074bd (Task 0), a5eec20 (Task 1). Self-Check: PASSED
