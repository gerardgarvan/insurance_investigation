# Phase 63: Enhanced Gantt Export - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-31
**Phase:** 63-enhanced-gantt-export
**Areas discussed:** v2 column schema, Script architecture, Schema documentation, Death/HL Dx rows in v2

---

## v2 Column Schema

| Option | Description | Selected |
|--------|-------------|----------|
| All v1 + 3 new | v2 is a superset of v1 — same 14 columns plus cancer_link_method, regimen_label, is_first_line. Easy to diff against v1. | ✓ |
| Only enhanced columns | v2 contains only the new/changed columns plus patient_id + episode keys. Users join to v1 for base data. | |
| Restructured schema | Reorganize column order for v2 (e.g., group clinical columns together). Breaking change from v1 column order. | |

**User's choice:** All v1 + 3 new (Recommended)
**Notes:** None

### Follow-up: cancer_category column naming

| Option | Description | Selected |
|--------|-------------|----------|
| Same name, different source | Keep 'cancer_category' in both. v2 is the upgrade — more precise. Users who compare will see differences at episode level. | ✓ |
| Rename in v2 | Use 'episode_cancer_category' in v2 to make the distinction explicit. Avoids confusion when diffing v1 vs v2. | |

**User's choice:** Same name, different source (Recommended)
**Notes:** cancer_category means different things in v1 (patient-level) vs v2 (encounter-level) but the column name stays the same

---

## Script Architecture

| Option | Description | Selected |
|--------|-------------|----------|
| New R/63 script | Standalone R/63_gantt_v2_export.R. Reads enriched treatment_episodes.rds directly (cancer_category, regimen_label, is_first_line already there). Simpler than R/49. | ✓ |
| Extend R/49 for both | Modify R/49 to output both v1 and v2 files in one run. Avoids duplication but risks breaking v1. | |
| R/49 + shared helpers | Extract Death/HL Diagnosis row logic into a shared utility, then R/49 and R/63 both call it. More refactoring. | |

**User's choice:** New R/63 script (Recommended)
**Notes:** None

### Follow-up: Code duplication

| Option | Description | Selected |
|--------|-------------|----------|
| Accept duplication | Project pattern: scripts are self-contained. R/49 and R/63 both build Death/HL Dx rows independently. Same pattern as PREFIX_MAP duplication. | ✓ |
| You decide | Claude chooses the best approach for maintaining code independence vs DRY. | |

**User's choice:** Accept duplication (Recommended)
**Notes:** ~200 lines of Death/HL Diagnosis row construction duplicated. Consistent with existing project pattern.

---

## Schema Documentation

| Option | Description | Selected |
|--------|-------------|----------|
| Script header comment | Document columns in R/63's header block, same pattern as R/49. Self-contained, no extra files. | ✓ |
| Schema xlsx sheet | Add a 'Schema' sheet to a v2 audit workbook with column name, type, source, and description. | |
| You decide | Claude picks the approach that fits the project pattern best. | |

**User's choice:** Script header comment (Recommended)
**Notes:** None

---

## Death/HL Dx Rows in v2

| Option | Description | Selected |
|--------|-------------|----------|
| Include with NA values | v2 includes Death and HL Diagnosis rows. New columns get NA values. Ensures v2 is a complete superset. | ✓ |
| Exclude pseudo-treatments | v2 only has real treatment episodes. Death and HL Diagnosis only appear in v1. | |
| You decide | Claude determines the best approach for data completeness. | |

**User's choice:** Include with NA values (Recommended)
**Notes:** cancer_link_method="none", regimen_label=NA, is_first_line=FALSE for pseudo-treatment rows

---

## Claude's Discretion

- Column ordering within v2 CSVs
- Summary message at end of R/63
- Guard clauses for missing Phase 61/62 columns

## Deferred Ideas

None
