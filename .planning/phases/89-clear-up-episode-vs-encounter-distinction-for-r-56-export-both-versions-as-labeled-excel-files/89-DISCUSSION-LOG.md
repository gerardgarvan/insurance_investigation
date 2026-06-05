# Phase 89: Clear Up Episode vs Encounter Distinction - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-05
**Phase:** 89-clear-up-episode-vs-encounter-distinction-for-r-56-export-both-versions-as-labeled-excel-files
**Areas discussed:** Output naming, Column labeling, Script scope

---

## Output Naming

### Question 1: How should the Excel files be named to make the grain obvious?

| Option | Description | Selected |
|--------|-------------|----------|
| Prefix with grain (Recommended) | e.g., episode_level_drug_grouping_tables.xlsx and encounter_level_drug_grouping_instances.xlsx | ✓ |
| Rename to match grain | e.g., drug_grouping_by_episode.xlsx and drug_grouping_by_encounter.xlsx | |
| Keep current names | Keep current names but clarify inside the files only | |

**User's choice:** Prefix with grain
**Notes:** None

### Question 2: Should old filenames be kept alongside new ones?

| Option | Description | Selected |
|--------|-------------|----------|
| Replace entirely | Only produce new grain-prefixed filenames | |
| Keep both | Produce both old and new filenames | ✓ |

**User's choice:** Keep both
**Notes:** Backward compatibility — both old and new names produced

---

## Column Labeling

### Question 1: How should the grain be documented inside each Excel file?

| Option | Description | Selected |
|--------|-------------|----------|
| Sheet name includes grain (Recommended) | e.g., 'Episode-Level Sub-Category Summary' — grain visible when switching tabs | ✓ |
| Add a metadata sheet | Add a README/About sheet with documentation | |
| Both sheet names + metadata | Rename sheets AND add metadata sheet | |

**User's choice:** Sheet name includes grain
**Notes:** None

---

## Script Scope

### Question 1: How should the code changes be structured?

| Option | Description | Selected |
|--------|-------------|----------|
| Modify R/56 and R/57 in-place (Recommended) | Update output filenames and sheet names directly in existing scripts | ✓ |
| New wrapper script | Create R/89 that sources R/56 and R/57, then copies/renames | |
| Config-driven naming | Add output filename configs to R/00_config.R | |

**User's choice:** Modify in-place
**Notes:** Minimal change, no new files

---

## Claude's Discretion

- Dual-save mechanism (wb$save() twice vs file.copy())
- Log message wording for dual-output

## Deferred Ideas

None — discussion stayed within phase scope
