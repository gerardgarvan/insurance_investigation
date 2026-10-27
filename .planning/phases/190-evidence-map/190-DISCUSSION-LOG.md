# Phase 190: Evidence Map - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-27
**Phase:** 190-evidence-map
**Areas discussed:** Manual copy location, Evidence map format, Team decisions mining scope, D-190-01 default resolution

---

## Manual Copy Location

| Option | Description | Selected |
|--------|-------------|----------|
| Plain-text / markdown copy only | Convert .docx to markdown; original stays at root | |
| Original .docx only | Copy .docx into docs/analytic_manual/; parse with docx reader | |
| Both .docx and markdown | .docx for reference + markdown extraction | ✓ |

**User's choice:** Both — original `.docx` files in `docs/analytic_manual/` unchanged as source of record; markdown extractions alongside for R reading.

**Notes:** `VariableDetails` stays as `.xlsx`. Extraction done on Windows with Python or pandoc (not R). Critical: Word comments including Amy's c0/c1 must survive extraction with their attachment text. Many converters drop comments silently — verify before proceeding.

---

## Evidence Map Format

| Option | Description | Selected |
|--------|-------------|----------|
| Markdown primary, xlsx exported | AM-EVIDENCE-MAP.md edited; xlsx script-generated | ✓ |
| xlsx primary, markdown summary | Workbook edited; markdown generated from it | |
| Both maintained independently | Parallel artifacts; risk of drift | |

**User's choice:** Markdown is primary; xlsx is script-generated and never hand-edited.

**Notes:** Each row gets a stable ID (e.g., S4-INS-03) that carries through Phase 191 verdicts and Phase 193 tracked-change comments. IDs must not be renumbered — they are the connective tissue across all four phases.

---

## Team Decisions Mining Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Targeted scan — known AM-relevant phases | Curated list of AM-touching phases | |
| Full scan — all CONTEXT.md files | Read every CONTEXT.md across ~189 phases | |
| Keyword grep first, then read hits | Grep all files, read matching ones | ✓ |

**User's choice:** Keyword grep across all CONTEXT.md files plus MILESTONES.md and STATE.md.

**Notes:**
- Decision markers: `D-\d`, "team decided", "confirmed with", "per Amy|Erin|Ray|Sharon", "locked", "agreed"
- AM domain terms: payer, insurance, Medicaid, FLM, Tricare, LNK, SOURCE, tumor registry, anchor, 7-day, death, cause of death, ADI, SDI, ZIP9, RUCA, RUCC, distance, cutoff, zipcodeR, episode, regimen, anthracycline, survivorship, CBC, rituximab
- Always-read phases (regardless of grep): 34–37, 62, 87, 104–105, 110, 118–119, 122–124, 137–151, 152–155, 165, 167, 179–188
- Read TeamMtgNotes2026 in full
- Count only named-person or team-attributed decisions — not unilateral planning choices

---

## D-190-01 Default Resolution

| Option | Description | Selected |
|--------|-------------|----------|
| Leave blank — team decision pending | Record as OPEN, no default | ✓ |
| Known location — record it now | Known path/URL recorded as default | |
| Presumed location with caveat | Best-guess location, marked unverified | |

**User's choice:** Leave blank — OPEN, team decision pending. Phase 194 follows up.

---

## Claude's Discretion

- Row ID format within sections (the exact schema for stable IDs)

## Deferred Ideas

None.
