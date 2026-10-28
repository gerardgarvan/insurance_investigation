# Phase 193: Produce Updated Manual - Context

**Gathered:** 2026-10-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce `AnalyticManual_<YYYY.MM.DD>.docx` as a new versioned copy — original byte-for-byte unchanged — with all AM-DRAFT.md content inserted as real Word tracked changes (w:ins / w:del markup), Amy's existing comments c0 and c1 replied to, and a new `am_evidence_<date>.xlsx` workbook recording every tracked change. No pipeline code changes in this phase.

</domain>

<decisions>
## Implementation Decisions

### Tracked-change insertion method

- **D-01:** Unpack the `.docx` zip, edit `word/document.xml` directly to inject `w:ins` and `w:del` elements (`w:author="Gerard Garvan"`, timestamp = build time), then repack. Do not use python-docx's high-level API for this — it does not produce tracked-change XML. python-docx is fine for reading the original structure.
- **D-02:** Read the OOXML tracked-change spec (the "docx skill") before building the insertion script.
- **D-03:** Three-way verification gate before the phase is complete:
  1. Reopen the output with python-docx and confirm it parses without error.
  2. Run `pandoc --track-changes=all` on the output; confirm insertion, deletion, and comment counts match the plan.
  3. Human checkpoint: open in Word, confirm tracked changes are visible and the file is clean.
- **D-04:** Write only to the new versioned copy. Verify the original's SHA-256 hash has not changed.

### What gets inserted

- **DRAFTED units** → `w:ins` tracked insertions into the corresponding empty section.
- **CORRECTION units** → tracked deletion (`w:del`) of the anchor text + `w:ins` of the replacement text, plus a comment citing the decision ID and evidence (per D-24 from Phase 192 context). Comment appears on the CORRECTION only.
- **OPEN-QUESTION-SEE-§8 units** → existing text is not changed; add a comment pointing to the §8 row. Where the unit fills an empty field, insert current-code description as tracked text with that comment.
- **TEAM-INPUT-NEEDED units** → insert a visible `[TEAM INPUT NEEDED]` placeholder as a tracked insertion so reviewers see the gap. Do not skip.
- **§8 rows** → tracked insertions into the existing Parking Lot table. Existing rows are not moved or deleted.
- **Front matter** → "Date last updated" and "Document version" fields updated as tracked changes.
- **Strip draft helper columns:** Map ID tags (`[S4-…]`), STATUS, and CITE lines do not appear in the Word text — they go to the evidence workbook, keyed by change ID.
- **Comment volume:** comments only on CORRECTIONs, OPEN-QUESTION flags, and the c0/c1 replies. No comment on every DRAFTED line — that would bury reviewers.

### Comment replies (AM-DOC-02)

- **D-05:** Reply to Amy's c0 and c1 in `comments.xml` / `commentsExtended.xml` using `w:paraIdParent` threading. Author: "Gerard Garvan".
  - **c0 reply:** "OneFLquestions document not received; listed as open in §8 (D-190-01)."
  - **c1 reply:** Phase 191 verdict in 1–2 sentences covering both steps (Tumor Registry default, then first HL code date). If a mismatch, add "see §8."
- **D-06:** If `commentsExtended.xml` threading proves unreliable, fallback is a new comment on the same anchor paragraph starting "Re: Amy's comment —".
- **D-07:** Both replies also appear in the evidence workbook and are noted in the Phase 194 cover email.

### Evidence workbook (AM-DOC-03)

- **D-08:** Produce a new `am_evidence_<date>.xlsx` by extending the existing `cmd_export` in `tools/am_evidence/am_evidence_map.py`. This is distinct from the Phase 191 verdicts workbook (`am_verdicts_20261027.xlsx`), which remains the Phase 191 record.
- **D-09:** Workbook structure:
  - **KEY** sheet (leftmost): column index + reference to `am_verdicts_20261027.xlsx` as the Phase 191 record.
  - **Changes** sheet: one row per tracked change — columns: change ID, section, map ID, action (insert / replace / comment), inserted or replaced text, citation, verdict, decision ID (where applicable).
  - **Open Items** sheet: all §8 parking-lot rows.
  - Integrity check: every tracked change in the .docx has exactly one workbook row, and vice versa. Export fails if the counts diverge.
- **D-10:** UF colours (`#0021A5` / `#FA4616`); all counts 1–10 suppressed as `"<11"`; no patient IDs.

### Claude's Discretion

- Change ID scheme (e.g., `TC-NNN` prefix) and exact column order within the Changes sheet.
- Whether to build the insertion script as a new subcommand in `am_evidence_map.py` or as a standalone script in `tools/am_evidence/`.
- Exact timestamp value used in `w:ins`/`w:del` attributes (build time is fine).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### AM-DRAFT source
- `.planning/phases/192-draft-new-content/AM-DRAFT.md` — the 95 DRAFTED + 2 CORRECTION + 33 TEAM-INPUT-NEEDED + 8 OPEN-QUESTION units to be inserted

### Prior phase decisions
- `.planning/phases/192-draft-new-content/192-CONTEXT.md` — D-22 through D-27 (evidence precedence, CORRECTION directive format, D-24 comment-on-correction rule)
- `.planning/phases/191-verify-existing-entries/191-CONTEXT.md` — D-191-NN decision row format, c0 / c1 verdict details
- `.planning/phases/190-evidence-map/190-CONTEXT.md` — D-190-01 (OneFLquestions open), map ID scheme

### Evidence map and verdicts
- `.planning/phases/191-verify-existing-entries/AM-VERDICTS.md` — Phase 191 verdicts (c0 BLOCKED, c1 verdict)
- `.planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md` — map IDs, AM-MAP-02 repo-only domain rows, AM-MAP-03 decision rows

### Existing tool
- `tools/am_evidence/am_evidence_map.py` — `cmd_export` (evidence workbook skeleton to extend), `cmd_draft_check`, `_parse_draft`

### Requirements and roadmap
- `.planning/REQUIREMENTS.md` — AM-DOC-01, AM-DOC-02, AM-DOC-03
- `.planning/ROADMAP.md` §Phase 193 — success criteria

### Source document
- `docs/analytic_manual/AnalyticManual_2026.01.30.docx` — original (read-only; hash must not change)
- `docs/analytic_manual/AnalyticManual_2026.01.30.md` — markdown mirror (for anchor lookups)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tools/am_evidence/am_evidence_map.py`: `_parse_draft()` already parses AM-DRAFT.md into structured units with status, cite, and text fields — reuse this to drive the insertion script.
- `tools/am_evidence/am_evidence_map.py`: `cmd_export()` produces `am_evidence_<date>.xlsx` with UF styling from `AM-EVIDENCE-MAP.md` — extend this (new sheet or new command) for the Changes + Open Items sheets.
- `python-docx` v1.2.0 is installed — use for reading .docx structure; use `lxml` (bundled with python-docx) for raw XML manipulation.

### Established Patterns
- All tools run on local Windows; no HiPerGator needed for this phase (no R data reads).
- Output workbooks: KEY leftmost, UF blue/orange, counts suppressed.
- Verification gate: `validate` subcommand must pass after any change to AM-EVIDENCE-MAP.md.

### Integration Points
- Phase 194 consumes the new `.docx` and `am_evidence_<date>.xlsx` to draft the cover email and decision log.
- c0/c1 replies feed directly into the Phase 194 email.

</code_context>

<specifics>
## Specific Ideas

- User explicitly wants the insertion script to read the OOXML tracked-change spec ("the docx skill") before building — check if such a reference exists in the project or web.
- Three-way verification gate is non-negotiable: python-docx reopen + pandoc count match + human Word checkpoint.
- The SHA-256 hash of the original `AnalyticManual_2026.01.30.docx` must be recorded at plan time and re-verified at phase close.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 193-produce-updated-manual*
*Context gathered: 2026-10-28*
