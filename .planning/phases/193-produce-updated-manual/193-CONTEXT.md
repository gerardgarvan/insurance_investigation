# Phase 193: Produce Updated Manual - Context

**Gathered:** 2026-10-28
**Revised:** 2026-10-28 (preflight inventory, run-aware anchors, operation manifest, table-row revisions, accept-all/reject-all integrity test, comment-reply outcomes, completion states, suppression scope, export separation)
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce `AnalyticManual_<YYYY.MM.DD>.docx` as a new versioned copy — original byte-for-byte unchanged — with AM-DRAFT.md content applied as real Word tracked changes, replies to Amy's comments c0 and c1, and a new `am_evidence_<date>.xlsx` reconciling every edit operation to its source. No pipeline code changes. Phase 193 is complete only after a human Word review is recorded (D-16).

</domain>

<decisions>
## Implementation Decisions

### Method

- **D-01:** Unpack the `.docx`, edit the package XML with lxml, repack. python-docx is used only for reading. Read the docx skill's tracked-changes and comments guidance before building.
- **D-04:** Write only to the new versioned copy in `docs/analytic_manual/`. If the target filename exists, stop unless run with an explicit `--overwrite`; record a build ID (timestamp + git commit) in the manifest and the workbook KEY. Verify the original's SHA-256 at start and end.

### Preflight inventory (before any edit)

- **D-11:** Write `193-PREFLIGHT.md` recording:
  - original SHA-256
  - package parts and relationships present (`comments.xml`, `commentsExtended.xml`, `commentsIds.xml`, `commentsExtensible.xml`, `people.xml`, `settings.xml`, headers/footers)
  - existing tracked changes, comments (ID, author, initials, text, anchor, `w14:paraId` of the comment paragraph), bookmarks, content controls, fields
  - the paragraph/table location of every target: each section heading, each existing domain field, the §8 table, the front-matter "Date last updated" and "Document version" fields (including whether they sit in body, table, header or footer), and the heading/paragraph/table styles in use
  - c0 and c1 identified by author and comment text, not by assumed numeric ID
  Existing revisions and comments are left untouched unless an operation explicitly targets them.

### Operation manifest

- **D-13:** Build `193-OPERATIONS.json` deterministically from `_parse_draft()` before writing XML. One operation per logical edit:
  `op_id` (OP-NNN), source unit(s) and map ID, status, target (section, paragraph/table/cell locator from the preflight), action (`INSERT-PARA`, `INSERT-ROW`, `REPLACE`, `COMMENT-ONLY`, `REPLY`, `PLACEHOLDER`), text to insert, anchor text (for REPLACE/COMMENT), citation(s), decision ID, verdict.
  After writing, each operation records the physical IDs created (`w:ins`/`w:del` revision IDs, comment IDs). The source-unit count (e.g., 138) is an inventory, not the expected revision count; expected counts come from the manifest.
- **M1/M2:** Classify every unit by destination before insertion: empty field (fill), populated field (insert after the last existing paragraph of that field — never duplicate existing text), new subsection (repo-only domains, using existing heading styles from the preflight; no new styles), table row, front-matter field.

### Anchors

- **D-12a:** Corrections and comment anchors are matched against the DOCX structure, not the markdown: concatenate the run text of each candidate paragraph or cell, find the quoted anchor, and map it back to the runs it spans (splitting runs at the boundaries while copying their `w:rPr`). Require exactly one match within one paragraph or cell. Zero matches, multiple matches, or a span across paragraphs/cells/fields/hyperlinks → that operation is not applied and is reported as `ANCHOR-FAILED` in the manifest and workbook; the build fails unless every failure is resolved.

### Tracked-change construction

- **D-12:**
  - Insertions: `w:ins` wrapping `w:r` elements with `w:t` (`xml:space="preserve"` where needed); new paragraphs carry a paragraph-mark insertion (`w:pPr/w:rPr/w:ins`) so the whole paragraph is accepted or rejected together.
  - Deletions: `w:del` wrapping runs whose text is in `w:delText`, preserving the original `w:rPr`.
  - Inserted table rows: `w:trPr/w:ins` on the row plus `w:ins` runs in each cell; cell properties copied from an existing row of the same table.
  - Every revision has a unique `w:id` (not colliding with existing revision, comment or bookmark IDs), `w:author="Gerard Garvan"`, and one build timestamp.
  - Inserted text uses the formatting of the surrounding paragraph (copied `w:pPr`/`w:rPr`).
  - Set `w:trackRevisions` in `settings.xml` so further edits by reviewers are tracked.
- **What gets inserted** (unchanged from discussion):
  - DRAFTED → tracked insertion.
  - CORRECTION → tracked deletion of the anchor text + tracked insertion of the replacement + one comment citing decision ID and evidence.
  - OPEN-QUESTION-SEE-§8 → existing text unchanged plus a comment pointing to the §8 row; where it fills an empty field, current-code description inserted as tracked text with that comment.
  - TEAM-INPUT-NEEDED → visible `[TEAM INPUT NEEDED]` placeholder as a tracked insertion.
  - §8 rows → tracked row insertions; existing rows untouched.
  - Front matter → "Date last updated" and "Document version" as tracked changes, in whatever part the preflight located them.
- **D-34 (what is stripped):** draft-control metadata only — `[S4-…]` tags, `STATUS:`, `CITE:` lines and the trailing Map ID/Status/Cite table columns. These go to the workbook keyed by `op_id`. Substantive references that belong in the manual (decision dates, team decision wording, the §8 Notes IDs) stay in the text. Code paths and line ranges go to comments (CORRECTION/OPEN only) and the workbook, not the body text.
- **Comment volume:** comments only on CORRECTIONs, OPEN-QUESTION units and the two replies.

### Comment replies

- **D-14:** Using the preflight inventory, reply to c0 and c1 as threaded replies: new comment in `comments.xml` (author "Gerard Garvan", initials), its paragraph given a new unique `w14:paraId`, and a `w15:commentEx` entry in `commentsExtended.xml` with `w15:paraIdParent` = the original comment's paragraph ID; add the reply to `commentsIds.xml` / `people.xml` if those parts exist, and create missing parts with their relationships and content types if needed. The reply carries the same anchor range as the original. Original comments and anchors are unchanged.
  - c0 reply: "OneFLquestions document not received; listed as open in §8 (D-190-01)."
  - c1 reply: the Phase 191 verdict in one or two sentences covering both steps (Tumor Registry default, then first HL code date); if a mismatch, add "see §8."
- **D-06/D-07:** If threading cannot be produced reliably, fall back to a new comment on the same anchor beginning "Re: Amy's comment —". Each reply's outcome is recorded as `THREADED-REPLY` or `FALLBACK-COMMENT` in the manifest and workbook, and the Phase 194 email uses the recorded outcome.

### Evidence workbook

- **D-08:** New subcommand `manual-export` (not a change to `export`), writing `am_evidence_<date>.xlsx`. Existing `export` output is unchanged; a regression check compares `export` output before and after.
- **D-09/D-17:**
  - KEY (leftmost): build ID, original and output SHA-256, column definitions, reference to `am_verdicts_<date>.xlsx` as the Phase 191 record, reply outcomes.
  - Operations: one row per logical operation — op_id, section, map ID, action, inserted/replaced text, anchor text, revision IDs, comment IDs, citation(s), verdict, decision ID, status (`APPLIED` / `ANCHOR-FAILED`).
  - Open Items: §8 rows as inserted.
  - Reconciliation: every `w:ins`/`w:del`/comment created by the build belongs to exactly one operation, and every APPLIED operation's IDs exist in the output XML; any difference fails the export.
- **D-10:** UF colours; KEY leftmost; no patient IDs. Count suppression applies only to patient or result counts (there should be none in the manual); methodological numbers (day windows, mile cutoffs, code lists, dates, version numbers) are never suppressed.

### Verification

- **D-15:**
  1. Package checks: well-formed XML in every edited part; relationships and content types resolve; revision, comment and paraId uniqueness; every `commentRangeStart` has a matching end and reference.
  2. Reject-all test: programmatically reject every revision created by this build (drop `w:ins` content, unwrap `w:del` → `w:t`); the resulting document text must equal the original's text exactly. This proves no untracked changes.
  3. Accept-all test: accept every revision; the resulting text must contain each operation's inserted text once and none of the deleted anchor text.
  4. Untouched content: existing comments, revisions, tables and sections outside targeted locations are byte-identical in XML after the rejection pass.
  5. Reopen with python-docx; run `pandoc --track-changes=all` and confirm its insertion/deletion/comment markers match manifest counts (cross-check only; the XML checks are authoritative).
  6. Render to PDF (LibreOffice headless) and look at the pages with changes for layout defects.
  7. Human checkpoint in Microsoft Word (D-16).

### Completion states

- **D-16:** The phase records its state in STATE.md: `ARTIFACTS-GENERATED` → `AUTOMATED-QA-PASSED` → `WORD-REVIEW-APPROVED`. Only the last allows Phase 193 to be marked complete. The Word review confirms: file opens without a repair prompt; tracked changes visible and attributed to Gerard Garvan; accept/reject works on a sample; c0/c1 replies show under Amy's comments (or the fallback is visible and labelled); no layout damage on changed pages.

### Claude's Discretion

- Insertion code as a standalone script in `tools/am_evidence/` or a subcommand, provided `manual-export` stays separate from `export`.
- Exact column order within the Operations sheet.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Draft and prior decisions
- `.planning/phases/192-draft-new-content/AM-DRAFT.md` — source units (inventory reported by Phase 192: DRAFTED, CORRECTION, TEAM-INPUT-NEEDED, OPEN-QUESTION-SEE-§8)
- `.planning/phases/192-draft-new-content/192-CONTEXT.md`, `192-01-PLAN.md` (draft grammar)
- `.planning/phases/191-verify-existing-entries/AM-VERDICTS.md` — c0/c1 verdicts
- `.planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md`, `am_source_hashes.txt`

### Tool and guidance
- `tools/am_evidence/am_evidence_map.py` — `_parse_draft()`, `export`, `draft-check`
- docx skill guidance on tracked changes and comments (locate in the Claude Code skills available in this environment)

### Requirements
- `.planning/REQUIREMENTS.md` — AM-DOC-01..03; `.planning/ROADMAP.md` §Phase 193

### Source document
- `docs/analytic_manual/AnalyticManual_2026.01.30.docx` (read-only)

</canonical_refs>

<code_context>
## Existing Code Insights

- `_parse_draft()` gives units with status, cite and text — input to the manifest.
- python-docx 1.2.0 and lxml available locally; pandoc 3.13 installed; LibreOffice needed for the render check (install or skip with the reason recorded).
- All work runs on local Windows; no HiPerGator.

</code_context>

<specifics>
## Specific Ideas

- The reject-all = original test is the key integrity proof; build it early and run it after every change to the insertion code.
- c0/c1 outcomes (THREADED-REPLY vs FALLBACK-COMMENT) flow to the Phase 194 email exactly as recorded.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

---

*Phase: 193-produce-updated-manual*
*Context gathered: 2026-10-28*
