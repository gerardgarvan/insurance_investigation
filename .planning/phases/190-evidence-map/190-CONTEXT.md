# Phase 190: Evidence Map - Context

**Gathered:** 2026-10-27
**Revised:** 2026-10-27 (comment locations, extraction method, phase labels, read-in-full list, mining scope, VariableDetails location, D-190-01 interim handling)
**Status:** Ready for planning

<domain>
## Phase Boundary

Read-only crosswalk from every item in the analytic manual to a repo source reference, with each item assigned a status ({FILLED-NEEDS-CHECK, EMPTY-REPO-CAN-ANSWER, EMPTY-NEEDS-TEAM, OUT-OF-SCOPE}). Also catalogs repo domains not yet in the manual and mines named team decisions from meeting notes and prior planning files. Phase 191 uses this map as its starting point — no manual text and no code changes in this phase.

</domain>

<decisions>
## Implementation Decisions

### Prerequisite: docs/analytic_manual/ setup (before Phase 190 executes)

- **D-01:** `docs/analytic_manual/` holds the original files unchanged as the source of record: `AnalyticManual_2026.01.30.docx`, `TeamMtgNotes2026.docx`, `VariableDetails.xlsx`. Phase 193 builds the new versioned copy from `docs/analytic_manual/AnalyticManual_2026.01.30.docx`.
- **D-02:** Alongside each `.docx`, add a markdown extraction (`AnalyticManual_2026.01.30.md`, `TeamMtgNotes2026.md`) as the readable working copy. `VariableDetails.xlsx` is read as-is (no extraction); its "Surveillance Strategy" sheet is the source for the Survivorship encounters domain (lead L9).
- **D-03:** Extraction is done on Windows with pandoc (not R — no local Rscript):
  ```
  pandoc AnalyticManual_2026.01.30.docx --track-changes=all -t gfm -o AnalyticManual_2026.01.30.md
  pandoc TeamMtgNotes2026.docx --track-changes=all -t gfm -o TeamMtgNotes2026.md
  ```
  `--track-changes=all` keeps Word comments as spans anchored to the text they annotate. **Verification gate:** both of Amy's comment texts must appear in `AnalyticManual_2026.01.30.md` next to their anchor text (see Specifics for the exact anchors). If they do not, read `word/comments.xml` and the `w:commentRangeStart`/`w:commentRangeEnd` anchors directly from the `.docx` zip (Python `zipfile` + `xml.etree`). Do not use mammoth (drops comments by default).

### Evidence Map Format

- **D-04:** `AM-EVIDENCE-MAP.md` is the primary working document — edited by script or by hand during Phase 190. The `am_evidence_<date>.xlsx` workbook is script-generated from it and never hand-edited. In Phase 190 the workbook is a draft export; the final export is built in Phase 193.
- **D-05:** Each map row carries a **stable ID** (e.g., `S4-INS-03`, where S4 = manual section 4, INS = insurance/payer domain, 03 = item sequence). This ID threads through the Phase 191 verdict workbook and Phase 193 tracked-change comments. IDs must be assigned during Phase 190 and never renumbered; retired rows keep their ID with status noted, and new rows take the next free sequence number.

### Team Decisions Mining (AM-MAP-03)

- **D-06:** Keyword grep across **all** `.planning/phases/*/` files named `*CONTEXT.md`, `*DISCUSSION-LOG.md` and `*SUMMARY.md`, plus `.planning/MILESTONES.md` and `.planning/STATE.md`.
  - Decision markers: `D-\d`, "team decided", "confirmed with", "per Amy|Erin|Ray|Sharon", "locked", "agreed"
  - AM domain terms: payer, insurance, Medicaid, FLM, Tricare, LNK, SOURCE, tumor registry, anchor, 7-day, death, cause of death, ADI, SDI, ZIP9, RUCA, RUCC, distance, cutoff, zipcodeR, episode, regimen, anthracycline, survivorship, CBC, rituximab
- **D-07:** Always read in full regardless of grep hits: phases 34–37, 61, 62, 87, 104–105, 110, 116, 118–119, 122–124, 133, 137–151, 152–155, 158–160, 165, 166, 167, 179–188.
- **D-08:** Read `TeamMtgNotes2026.md` (the extracted markdown) in full.
- **D-09:** Count only decisions attributed to a named person (Amy, Erin, Ray, Sharon, Gerard) or explicitly to "the team" — not unilateral planning choices made during implementation. Each mined decision records: decision text, who, date, source file, and the map row ID(s) it informs.

### D-190-01: OneFLquestions Document Location

- **D-10:** D-190-01 status = **OPEN, team decision pending**. Record the decision row with no default resolution; Phase 194 follows up with the team. Interim handling so downstream phases do not stall: until the document is received, Amy's comment c0 is marked `BLOCKED (OneFLquestions document not received)` in the map, and Phases 191–192 proceed without it. If the document arrives before Phase 192, it is added to the map as an additional source; no completed work is redone.
- **ROADMAP alignment:** the Phase 190 success criterion that reads "recorded with its default resolution" is to be reworded to "recorded as an open decision with interim handling (c0 BLOCKED)".

### Claude's Discretion

- Row ID format within each section is Claude's to decide (e.g., S4-INS-03 or another stable scheme), as long as it is human-readable, section-scoped, and documented in AM-EVIDENCE-MAP.md for Phase 191 to reference.
- Section ordering and grouping in AM-EVIDENCE-MAP.md follows the manual's section structure; new domains (AM-MAP-02) are grouped at the end of §4 with their own domain codes.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Manual source files (must exist before Phase 190 executes)
- `docs/analytic_manual/AnalyticManual_2026.01.30.docx` — source of record; untouched throughout v3.13
- `docs/analytic_manual/AnalyticManual_2026.01.30.md` — extraction with comments; used by the evidence map
- `docs/analytic_manual/TeamMtgNotes2026.docx` / `TeamMtgNotes2026.md` — mined for team decisions
- `docs/analytic_manual/VariableDetails.xlsx` — Surveillance Strategy sheet and variable definitions

### Requirements and roadmap
- `.planning/REQUIREMENTS.md` — AM-MAP-01, AM-MAP-02, AM-MAP-03 acceptance criteria
- `.planning/ROADMAP.md` §Phase 190 — success criteria including AM-MAP-03 decision list and D-190-01
- `v3.13-milestone-brief.md` — known leads L1–L9 (each must have a map row)

### Prior phases to read in full
- `.planning/phases/34-*/` through `37-*/` — payer code frequency, same-day payer hierarchy, AMC 8-category mapping, 8-tier resolution with "Other govt" tier
- `.planning/phases/61-*/` — encounter-level cancer linkage; first-line HL regimen detection (ABVD, BV+AVD, Nivo+AVD)
- `.planning/phases/62-*/` — first-line therapy flagging (adults 21+); death date data-quality analysis
- `.planning/phases/87-*/` — unified ICD-9/ICD-10 cancer code handling; HL cohort expanded to C81 + 201.x
- `.planning/phases/104-*/` through `105-*/` — pre-diagnosis treatment, secondary-malignancy 7-day gap; code verification and HL+NHL dual-code overlap
- `.planning/phases/110-*/` — HL-only 7-day-confirmed V2 cancer summary
- `.planning/phases/116-*/` — USDA 2020 RUCA rurality classification
- `.planning/phases/118-*/` through `119-*/` — death-cause NHL flag (DEATH_CAUSE table)
- `.planning/phases/122-*/` through `124-*/` — MED_ADMIN/DISPENSING chemo detection, NDC→RxNorm crosswalk, downstream integration
- `.planning/phases/133-*/` — published-number corrections incl. HL anchor date (evidence for c1)
- `.planning/phases/137-*/` through `151-*/` — ZIP9 temporal assignment, ZIP stability, centroid ZIP9 crosswalk, areal-mean SDI, SES reference files, ADI coverage, ZIP problem inventory
- `.planning/phases/152-*/` through `155-*/` — encounter-to-residence distance (R/122), patient ZIP calendar, histogram, cutoff memo (155 superseded by 165)
- `.planning/phases/158-*/` through `160-*/` — surveillance modality codeset (VariableDetails), lab modalities (BMP/CMP/LIPID/LFT/KIDNEY), diagnostic/eligibility rules
- `.planning/phases/165-*/` — >100 mi indicator and CBC association; team cutoff decision 2026-10-08
- `.planning/phases/166-*/` — survivorship modality rates, anthracycline-to-echo timing
- `.planning/phases/167-*/` — single-health-system care flag (ENCOUNTER.SOURCE; LNK handling)
- `.planning/phases/179-*/` through `188-*/` — CBC deliverables, facility ZIP fill, ZCTA crosswalk, MICE, modality rate model, v3.12 phases

### Output privacy rules (CLAUDE.md)
- `CLAUDE.md` §Outputs and privacy — counts 1–10 as `"<11"`, no patient IDs in workbooks or memos

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/SCRIPT_INDEX.md` — exists; Phase 191's verification script must be listed here
- `.planning/STATE.md` — contains open decisions and parked items; mine for AM-MAP-03 and the §8 parking lot

### Established Patterns
- Output workbooks use UF colours `#0021A5` / `#FA4616`, KEY sheet leftmost — evidence workbook must follow the same pattern
- Stable IDs already used for decision rows (D-NNN-NN); Phase 190 extends this to map row IDs (S-section-domain-seq)

### Integration Points
- `am_evidence_<date>.xlsx` → consumed by Phase 191 verification script as input (read-only)
- `AM-EVIDENCE-MAP.md` → consumed by Phase 191 planner as the authoritative item list

</code_context>

<specifics>
## Specific Ideas

- **Amy's comment anchors** (use these to verify extraction and to create the c0/c1 map rows):
  - **c0** — anchored on the §4 heading "Data Cleaning and Harmonization Rules". Text: reference the OneFLquestions document to ensure everything has made it into the manual. Map status: BLOCKED until the document is received (D-10).
  - **c1** — anchored on the Cancer Diagnosis Date rule "If no diagnosis date: use first date with HL diagnosis code". Text: Gerard to confirm this is what's in the code. Evidence lives in `get_hl_any_dx_ids()` (`R/utils/utils_treatment.R`) and Phase 133.
- **Not a Word comment:** the Insurance domain's Unresolved Issues line "Gerard to confirm code matches this" is in-body text. It gets its own map row (S4-INS-xx) and is answered in Phase 191 alongside c1 (AM-VER-02).
- Every known lead L1–L9 from the milestone brief must appear as at least one map row with status FILLED-NEEDS-CHECK.
- The stable row ID (D-05) is the connective tissue across all four phases — get it right in Phase 190; renaming later breaks the chain.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 190-evidence-map*
*Context gathered: 2026-10-27*
