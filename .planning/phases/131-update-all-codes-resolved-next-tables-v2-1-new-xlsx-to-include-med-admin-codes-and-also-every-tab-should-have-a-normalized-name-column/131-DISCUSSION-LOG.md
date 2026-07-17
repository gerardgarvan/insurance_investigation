# Phase 131: Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-17
**Phase:** 131 — update all_codes_resolved_next_tables_v2.1_new.xlsx
**Areas discussed:** MED_ADMIN representation, Normalized name scope & meaning, File versioning & script updates

---

## MED_ADMIN representation

| Option | Description | Selected |
|--------|-------------|----------|
| New rows for MED_ADMIN-only codes | Add rows only for CUIs in MED_ADMIN but NOT PRESCRIBING | ✓ |
| Annotate existing rows | Add 'MED_ADMIN' to Source Table for shared rows | |
| Both: annotate + new rows | Mark shared rows AND add exclusive rows | |

**User's choice:** New rows for MED_ADMIN-only codes

---

| Option | Description | Selected |
|--------|-------------|----------|
| Query from DuckDB at runtime | Anti-join MED_ADMIN vs PRESCRIBING in live DuckDB | ✓ |
| Use Phase 122/123 diagnostic output | Extract from R/107 or R/109 pre-computed results | |

**User's choice:** Query from DuckDB at runtime

---

| Option | Description | Selected |
|--------|-------------|----------|
| Chemotherapy only | Phase 122 fix was chemo-specific | |
| All applicable tabs | Query MED_ADMIN for all treatment types | ✓ |

**User's choice:** All applicable tabs

---

## Normalized name scope & meaning

| Option | Description | Selected |
|--------|-------------|----------|
| Same RxNav lookup for RxNorm, existing Meaning for others | RxNorm CUIs → RxNav IN concept; CPT/HCPCS/ICD → Meaning column value | ✓ |
| Human-curated per tab | Manually defined grouping logic per treatment type | |

**User's choice:** Same RxNav lookup for RxNorm, existing Meaning for others

---

| Option | Description | Selected |
|--------|-------------|----------|
| Normalized Meaning (match Supportive Care) | Keep existing column name | |
| normalized_name (snake_case) | Machine-friendly, consistent | ✓ |

**User's choice:** normalized_name (snake_case)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, rename Supportive Care to normalized_name | All 8 tabs uniform; minor breaking change to col-name references | ✓ |
| No, leave Supportive Care as-is | Avoid touching working code | |

**User's choice:** Yes, rename to normalized_name — accepted the R/105 and R/88 update cost for consistency

---

## File versioning & script updates

| Option | Description | Selected |
|--------|-------------|----------|
| v2.1_new.xlsx becomes canonical | Update all script REFERENCE_XLSX paths | |
| Keep v2.1.xlsx as filename, copy changes back | No script path changes | ✓ |

**User's choice:** Keep v2.1.xlsx as canonical filename — overwrite it from the _new working copy

---

## Claude's Discretion

- Column position for `normalized_name` (last column on each tab)
- Whether Index and Sheet1 tabs receive the column
- Exact R/88 smoke test assertion update

## Deferred Ideas

None.
