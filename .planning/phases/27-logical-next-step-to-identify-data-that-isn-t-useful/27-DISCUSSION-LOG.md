# Phase 27: Cross-Table Data Quality Assessment - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-22
**Phase:** 27-logical-next-step-to-identify-data-that-isn-t-useful
**Areas discussed:** Definition of 'not useful', Output and deliverables, Scope of analysis, Criteria priority

---

## Definition of 'not useful'

| Option | Description | Selected |
|--------|-------------|----------|
| Duplicate encounters (Recommended) | Focus on encounters identified as Identical in Phase 26 overlap classification | |
| Missing payer data | Encounters where payer fields are systematically empty/sentinel-coded | |
| All quality issues combined | Unified pass across duplicates + missingness + sentinel dates + anomalies | |

**User's choice:** "there are no duplicates. but that's just for encounter data set. let's run QA for all of the other tables"
**Notes:** User clarified that Phase 25-26 confirmed no encounter duplicates. The real gap is QA on all other PCORnet CDM tables beyond ENCOUNTER.

### Follow-up: QA type

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-source overlap detection | Same approach as Phase 25-26 applied to other tables | |
| Completeness and missingness | Profile key fields for missingness rates across tables | |
| Both overlap + completeness | Multi-source duplicate detection + field completeness profiling | |

**User's choice:** "both but do research into other areas to explore"
**Notes:** User wants both core QA types plus researcher investigation of additional QA dimensions.

### Follow-up: Which tables

| Option | Description | Selected |
|--------|-------------|----------|
| All loaded tables (Recommended) | Run QA across all 22 PCORnet CDM tables loaded by R/01_load_pcornet.R | ✓ |
| Just analysis-critical tables | Focus on tables feeding cohort pipeline | |
| Tables not yet investigated | Skip ENCOUNTER, focus on uninvestigated tables | |

**User's choice:** All loaded tables (Recommended)

---

## Output and deliverables

| Option | Description | Selected |
|--------|-------------|----------|
| Per-table CSV reports (Recommended) | One CSV per table with QA findings | ✓ |
| Single consolidated CSV | One summary CSV with one row per table | |
| Both per-table + summary | Detailed per-table + cross-table summary | |

**User's choice:** Per-table CSV reports (Recommended)

### Follow-up: Console output

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, full console summary (Recommended) | Console summary per table with key findings | ✓ |
| Minimal console output | Just progress messages and file paths | |
| You decide | Claude's discretion | |

**User's choice:** Yes, full console summary (Recommended)

---

## Scope of analysis

| Option | Description | Selected |
|--------|-------------|----------|
| All records (Recommended) | QA full table contents as loaded | ✓ |
| HL cohort patients only | Filter to cohort patients first | |
| Both, compared | Run QA on all + cohort-only, compare rates | |

**User's choice:** All records (Recommended)

### Follow-up: Integration

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone script (Recommended) | New R/24_cross_table_qa.R | ✓ |
| Integrated into pipeline | Add QA checks into main pipeline sequence | |

**User's choice:** Standalone script (Recommended)

---

## Criteria priority

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-source overlap | Same-ID, same-date records from different SOURCE values | ✓ |
| Field completeness | Percentage of non-NA values per column | ✓ |
| Value validity | Check values against PCORnet CDM value sets | ✓ |
| Exact row duplicates | Identical rows that may be loading artifacts | ✓ |

**User's choice:** All four selected
**Notes:** User wants comprehensive QA across all four dimensions.

### Follow-up: Tables without date fields

| Option | Description | Selected |
|--------|-------------|----------|
| Skip if no date field (Recommended) | Only run overlap detection on tables with date fields | ✓ |
| Adapt per table | Use different key fields per table | |
| You decide | Claude's discretion | |

**User's choice:** Skip if no date field (Recommended)

---

## Claude's Discretion

- Researcher should investigate additional QA dimensions beyond the four specified
- CSV naming and column structure per table
- PCORnet CDM valid value set definitions
- TUMOR_REGISTRY subtable handling
- Console summary formatting

## Deferred Ideas

None — discussion stayed within phase scope
