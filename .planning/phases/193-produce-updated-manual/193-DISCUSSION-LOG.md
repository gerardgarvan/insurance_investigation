# Phase 193: Produce Updated Manual - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-28
**Phase:** 193-produce-updated-manual
**Areas discussed:** Tracked-change insertion method, Evidence workbook scope, Comment replies, Scope boundary

---

## Tracked-Change Insertion Method

| Option | Description | Selected |
|--------|-------------|----------|
| OOXML revision XML | Unpack .docx, inject w:ins/w:del into document.xml, repack | ✓ |
| .docx with inserted text, no TC markup | Insert text normally; no tracked-change XML | |
| Side-by-side diff document | Separate .docx showing original vs new | |

**User's choice:** OOXML direct XML editing. Unpack the .docx, edit `word/document.xml`, repack. `w:ins` for insertions, `w:del` for deletions; `w:author="Gerard Garvan"` with timestamp. Comments via `comments.xml` and range markers.

**Notes:**
- Read the "docx skill" (OOXML tracked-change spec) before building the script.
- Three-way verification: python-docx reopen, pandoc `--track-changes=all` count match, human Word checkpoint.
- Do not produce a separate diff document — Amy needs to accept/reject changes in Word.
- Original .docx hash must not change.

---

## Evidence Workbook Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Run cmd_export → am_evidence_<date>.xlsx | Extend existing export for Changes + Open Items sheets | ✓ |
| Merge verdicts into evidence workbook | Pull D-191-NN rows from am_verdicts into one file | |
| Verdicts workbook satisfies AM-DOC-03 | No new workbook needed | |

**User's choice:** Build a separate `am_evidence_<date>.xlsx`. The verdicts workbook covers Phase 191 (checks of existing text); AM-DOC-03 needs a map of what changed in the new manual.

**Notes:**
- One row per tracked change: change ID, section, map ID, action, inserted/replaced text, citation, verdict, decision ID.
- Add an Open Items sheet listing §8 parking-lot rows.
- Integrity check: every tracked change in the .docx maps to exactly one workbook row.
- KEY sheet references `am_verdicts_20261027.xlsx` as the Phase 191 record.

---

## Comment Replies

| Option | Description | Selected |
|--------|-------------|----------|
| Threaded replies via commentsExtended.xml | w:paraIdParent linking under Amy's comments | ✓ |
| New standalone comments at same location | Separate comments, not threaded | |
| Cover-note only | Replies in Phase 194 email, no .docx changes | |

**User's choice:** Threaded replies. Use `commentsExtended.xml` with parent links. Fallback: new comment at same anchor starting "Re: Amy's comment —" if threading proves unreliable.

**Notes:**
- **c0 reply:** "OneFLquestions document not received; listed as open in §8 (D-190-01)."
- **c1 reply:** Phase 191 verdict, 1–2 sentences (Tumor Registry default + first HL code date); add "see §8" if mismatch.
- Both replies also appear in the evidence workbook and Phase 194 cover email.

---

## Scope Boundary

| Option | Description | Selected |
|--------|-------------|----------|
| DRAFTED + CORRECTION only | TEAM-INPUT-NEEDED skipped | |
| Full boundary as discussed | DRAFTED / CORRECTION / OPEN-QUESTION / TEAM-INPUT-NEEDED all handled with distinct treatments | ✓ |

**User's choice (detailed):**
- **DRAFTED** → tracked insertions (w:ins).
- **CORRECTION** → w:del anchor text + w:ins replacement, comment citing decision ID/evidence.
- **OPEN-QUESTION-SEE-§8** → no change to existing text; add comment pointing to §8 row. If field is empty, insert current-code description as tracked text with the comment.
- **TEAM-INPUT-NEEDED** → insert `[TEAM INPUT NEEDED]` placeholder as a tracked insertion. Do not skip — hiding the gap is worse than showing it.
- **§8 rows** → tracked insertions into the existing Parking Lot table; existing rows untouched.
- **Front matter** → "Date last updated" and "Document version" updated as tracked changes.
- **Strip draft helper columns** from Word text; they go to the workbook keyed by change ID.
- **Comment volume:** only on CORRECTIONs, OPEN-QUESTION flags, and c0/c1 replies.

---

## Claude's Discretion

- Change ID scheme (e.g., TC-NNN).
- Whether insertion script is a new subcommand in `am_evidence_map.py` or standalone.
- Exact timestamp in w:ins/w:del attributes.

## Deferred Ideas

None.
