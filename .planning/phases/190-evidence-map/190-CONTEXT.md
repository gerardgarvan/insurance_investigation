# Phase 190: Evidence Map - Context

**Gathered:** 2026-10-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Read-only crosswalk from every item in the analytic manual to a repo source reference, with each item assigned a status ({FILLED-NEEDS-CHECK, EMPTY-REPO-CAN-ANSWER, EMPTY-NEEDS-TEAM, OUT-OF-SCOPE}). Also catalogs repo domains not yet in the manual and mines named team decisions from meeting notes and prior CONTEXT.md files. Phase 191 uses this map as its starting point — no manual text and no code changes in this phase.

</domain>

<decisions>
## Implementation Decisions

### Prerequisite: docs/analytic_manual/ setup (before Phase 190 executes)

- **D-01:** `docs/analytic_manual/` holds the original `.docx` files unchanged as the source of record (`AnalyticManual_2026.01.30.docx`, `TeamMtgNotes2026.docx`). Phase 193 builds the new versioned copy from `docs/analytic_manual/AnalyticManual_2026.01.30.docx`.
- **D-02:** Alongside each `.docx`, add a markdown extraction (`AnalyticManual_2026.01.30.md`, `TeamMtgNotes2026.md`) as the R-readable working copy. `VariableDetails` stays as `.xlsx`.
- **D-03:** Extraction is done on Windows with Python or pandoc (not R — no local Rscript). Critical requirement: **Word comments (including Amy's c0 and c1) must survive extraction with their attachment text**. Many converters drop comments silently; verify before proceeding.

### Evidence Map Format

- **D-04:** `AM-EVIDENCE-MAP.md` is the primary working document — edited by script or by hand during Phase 190. The `am_evidence_<date>.xlsx` workbook is script-generated from it and never hand-edited.
- **D-05:** Each map row carries a **stable ID** (e.g., `S4-INS-03`, where S4 = manual section 4, INS = insurance/payer domain, 03 = item sequence). This ID threads through the Phase 191 verdict workbook and Phase 193 tracked-change comments. IDs must be assigned during Phase 190 and never renumbered.

### Team Decisions Mining (AM-MAP-03)

- **D-06:** Use a keyword grep across **all** prior CONTEXT.md files, plus MILESTONES.md and STATE.md.
  - Decision markers: `D-\d`, "team decided", "confirmed with", "per Amy|Erin|Ray|Sharon", "locked", "agreed"
  - AM domain terms: payer, insurance, Medicaid, FLM, Tricare, LNK, SOURCE, tumor registry, anchor, 7-day, death, cause of death, ADI, SDI, ZIP9, RUCA, RUCC, distance, cutoff, zipcodeR, episode, regimen, anthracycline, survivorship, CBC, rituximab
- **D-07:** Always read in full regardless of grep hits: phases 34–37, 62, 87, 104–105, 110, 118–119, 122–124, 137–151, 152–155, 165, 167, 179–188.
- **D-08:** Read `TeamMtgNotes2026.md` (the extracted markdown) in full.
- **D-09:** Count only decisions attributed to a named person (Amy, Erin, Ray, Sharon, Gerard) or explicitly to "the team" — not unilateral planning choices made during implementation.

### D-190-01: OneFLquestions Document Location

- **D-10:** D-190-01 status = **OPEN, team decision pending**. Record the decision row with no default resolution. Phase 194 will follow up with the team.

### Claude's Discretion

- Row ID format within each section is Claude's to decide (e.g., S4-INS-03 or another stable scheme), as long as it is human-readable, section-scoped, and documented in the CONTEXT.md for Phase 191 to reference.
- Section ordering and grouping in AM-EVIDENCE-MAP.md follows the manual's section structure.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Manual source files (must exist before Phase 190 executes)
- `docs/analytic_manual/AnalyticManual_2026.01.30.docx` — source of record; untouched throughout v3.13
- `docs/analytic_manual/AnalyticManual_2026.01.30.md` — R-readable extraction; used by evidence map script
- `docs/analytic_manual/TeamMtgNotes2026.md` — R-readable extraction; mined for team decisions

### Requirements and roadmap
- `.planning/REQUIREMENTS.md` — AM-MAP-01, AM-MAP-02, AM-MAP-03 acceptance criteria
- `.planning/ROADMAP.md` §Phase 190 — success criteria including AM-MAP-03 decision list and D-190-01

### Prior phases to read in full
- `.planning/phases/34-*/` through `37-*/` — payer hierarchy decisions
- `.planning/phases/62-*/` — regimen labeling and cause of death
- `.planning/phases/87-*/` — drug grouping tables
- `.planning/phases/104-*/` through `105-*/`
- `.planning/phases/110-*/`
- `.planning/phases/118-*/` through `119-*/`
- `.planning/phases/122-*/` through `124-*/` — MED_ADMIN/DISPENSING chemo detection
- `.planning/phases/137-*/` through `151-*/`
- `.planning/phases/152-*/` through `155-*/` — ZIP/distance/rurality
- `.planning/phases/165-*/`, `.planning/phases/167-*/`
- `.planning/phases/179-*/` through `188-*/`

### Output privacy rules (CLAUDE.md)
- `CLAUDE.md` §Outputs and privacy — counts 1–10 as `"<11"`, no patient IDs in workbooks or memos

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/SCRIPT_INDEX.md` — exists; verification script must be registered here (Phase 191 concern, but planner should be aware)
- `.planning/STATE.md` — contains D-IDs for parking lot; mine for AM-MAP-03

### Established Patterns
- Output workbooks use UF colours `#0021A5` / `#FA4616`, KEY sheet leftmost — evidence workbook must follow the same pattern
- Stable IDs already used for decision rows (D-NNN-NN); Phase 190 extends this to map row IDs (S-section-domain-seq)

### Integration Points
- `am_evidence_<date>.xlsx` → consumed by Phase 191 verification script as input (read-only)
- `AM-EVIDENCE-MAP.md` → consumed by Phase 191 planner as the authoritative item list

</code_context>

<specifics>
## Specific Ideas

- Word comment extraction is a known risk: verify that Amy's comments (c0 on the insurance variable, c1 on survivorship or similar) survive conversion with their attachment text visible. Use `python-docx` or `mammoth` on Windows; pandoc often drops comment annotations. Check before proceeding.
- The stable row ID (D-05) is the connective tissue across all four phases — get it right in Phase 190; renaming later breaks the chain.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 190-evidence-map*
*Context gathered: 2026-10-27*
