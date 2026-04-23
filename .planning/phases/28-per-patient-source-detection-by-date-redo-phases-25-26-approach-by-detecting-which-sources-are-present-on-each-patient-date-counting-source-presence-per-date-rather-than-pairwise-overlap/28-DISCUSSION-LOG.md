# Phase 28: Per-Patient Source Detection by Date - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-04-23
**Phase:** 28-per-patient-source-detection-by-date
**Areas discussed:** Output granularity, Fields beyond source, Same-week scope

---

## Output Granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Patient-date detail + summaries (Recommended) | One row per patient-date showing n_sources and source_combo, plus aggregate CSVs: source combo frequencies, per-source summary counts. Mirrors Phase 25 structure. | ✓ |
| Patient-date detail only | Just the core detection table: patient ID, date, how many sources, which sources. No aggregation CSVs. | |
| Patient-level rollup | Collapse to one row per patient: max sources on any date, typical source pattern, etc. Skip date-level detail. | |

**User's choice:** Patient-date detail + summaries (Recommended)
**Notes:** None

### Follow-up: Include single-source dates?

| Option | Description | Selected |
|--------|-------------|----------|
| All dates (1+ sources) | Every patient-date row gets a source count. Gives full picture -- you can filter to multi-source later. Larger CSV but more complete. | ✓ |
| Multi-source only (2+) | Only rows where the patient has encounters from 2+ distinct sources on the same date. Keeps output focused on overlap. Same filtering as Phase 25. | |

**User's choice:** All dates (1+ sources)
**Notes:** None

---

## Fields Beyond Source

| Option | Description | Selected |
|--------|-------------|----------|
| Source detection only (Recommended) | Each patient-date gets: n_sources, source_combo, n_encounters per source. No field comparison -- that was Phase 26's job and you're replacing that approach. | ✓ |
| Include key fields per source | For each source on a date, also capture ENC_TYPE(s), PAYER_TYPE_PRIMARY completeness. Gives a quick glance at what each source contributes without full pairwise comparison. | |
| Full field summary per source | For each source on a date, summarize all key fields (ENC_TYPE, payer primary/secondary, provider, discharge). Essentially Phase 26's comparison but grouped by source not pairs. | |

**User's choice:** Source detection only (Recommended)
**Notes:** None

---

## Same-Week Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Same-date only (Recommended) | One grouping: patient + ADMIT_DATE. Much simpler and directly answers 'which sources were on each date.' Phase 25's same-week detection was a separate concern. | ✓ |
| Same-date + same-week | Also group by patient + ISO week (or rolling 7-day window) to detect source presence in the same week. Adds complexity but captures near-miss overlaps. | |
| You decide | Let Claude choose based on what makes the cleanest output. | |

**User's choice:** Same-date only (Recommended)
**Notes:** None

---

## Additional Input (unprompted)

**User's input:** "I want you to use whatever data manipulation is fastest you don't need to use dplyr you can use data.table"
**Decision captured:** D-05 in CONTEXT.md -- data.table allowed for speed, overriding project-wide dplyr convention for this script.

---

## Claude's Discretion

- Script naming/numbering
- Console output formatting
- HIPAA suppression approach
- n_encounters_per_source breakdown column design

## Deferred Ideas

None
