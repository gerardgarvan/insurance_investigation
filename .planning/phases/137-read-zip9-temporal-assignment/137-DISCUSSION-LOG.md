# Phase 137: read-zip9-temporal-assignment - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-25
**Phase:** 137-read-zip9-temporal-assignment
**Areas discussed:** Temporal anchor, Assignment logic, Output form, Script & registration, Address pattern summary

---

## Temporal anchor

| Option | Description | Selected |
|--------|-------------|----------|
| First HL diagnosis date | Static per-patient anchor at first_hl_dx_date | |
| First treatment date | Static per-patient anchor at first treatment | |
| Multiple anchors | Separate columns per anchor type | |
| Per-encounter / any date | Lookup accepts any date — not static | ✓ |

**User's choice:** "zip 9 look up should be based on a given encounter, i.e., it's not static"
**Notes:** The utility accepts any `(ID, date)` pair — callers supply the date. No single anchor is baked in.

---

## Encounter scope

| Option | Description | Selected |
|--------|-------------|----------|
| All HL cohort encounters — standalone lookup | Lookup table keyed on ID × date | |
| All HL cohort encounters — enrich encounter frame | Add ZIP columns to existing RDS | |
| Treatment encounters only | Narrow scope | |
| Any date in the database | General-purpose function usable by any script | ✓ |

**User's choice:** "it should be possible to attach a zip 9 to any date in the database"
**Notes:** Delivered as a utility function, not a pre-computed encounter-scoped table.

---

## Assignment logic

| Option | Description | Selected |
|--------|-------------|----------|
| ADDRESS_PERIOD_START ≤ date < ADDRESS_PERIOD_END (interval overlap) | Semantically correct; falls back when periods don't cover | ✓ |
| Most-recent ADDRESS_PERIOD_START on or before date | Simpler, no period-end logic | |
| Claude decides based on data quality | Inspect fill rate first | |

**User's choice:** Interval overlap (`ADDRESS_PERIOD_START ≤ date < ADDRESS_PERIOD_END`)

---

## Fallback when no interval covers

| Option | Description | Selected |
|--------|-------------|----------|
| Fall back to most-recent-before-date, then NA | Practical, recovers most cases | ✓ |
| Return NA always when no interval covers | Strict | |
| Modal ZIP9 for the patient | Last resort | |

**User's choice:** Fall back to most-recent-before-date, then NA

---

## Output form

| Option | Description | Selected |
|--------|-------------|----------|
| R function: get_zip9_at_date(ids, dates) | Utility function in utils module | ✓ |
| Precomputed lookup RDS | Cached file downstream scripts load | |
| Both: function + cached RDS | Flexible but more complex | |
| Claude decides | Match existing utils conventions | |

**User's choice:** R function `get_zip9_at_date(ids, dates)`

---

## Script & registration

| Option | Description | Selected |
|--------|-------------|----------|
| New utils module only — no standalone script | Function only, no R/NN script | |
| New investigation script R/NN + utils module | Standalone script + utils module | ✓ |
| Inline in existing utils module | Add to existing module | |

**User's choice:** New investigation script R/NN + utils module, registered in R/39, R/88, R/SCRIPT_INDEX.md

---

## Address pattern summary

| Option | Description | Selected |
|--------|-------------|----------|
| Per-patient timeline diagnostics: gaps, overlaps, missing period-ends | Characterize how records connect per patient | ✓ |
| Population-level only | Aggregate stats only | |
| Both: population + per-patient flags | Summary + HAS_GAP / HAS_OVERLAP columns | |

**User's choice:** Per-patient timeline diagnostics (gaps, overlaps, missing period-ends)

---

## Summary output location

| Option | Description | Selected |
|--------|-------------|----------|
| Console log only | No xlsx for this phase | |
| New xlsx report for this phase | Separate styled xlsx | |
| Appended to existing R/106 xlsx | New sheet in zip_change_frequency.xlsx | ✓ |

**User's choice:** Append new "Address Timeline Diagnostics" sheet to existing `output/zip_change_frequency.xlsx`

---

## Claude's Discretion

- Exact function signature and parameter names
- Handling of `ADDRESS_PERIOD_END = NA` (treat as open-ended)
- Whether diagnostics are computed in utils function or investigation script
- The exact R/NN script number (next after 106)
- Column layout in the new xlsx sheet

## Deferred Ideas

- Computing ADI/SVI/SDI scores — future SES index phase
- Adding LDS_ADDRESS_HISTORY to permanent PCORNET_TABLES / DuckDB
- ZIP9 columns in cohort RDS (ZIP9_AT_DX, ZIP9_AT_TX)
- Local fixture for LDS_ADDRESS_HISTORY for end-to-end local testing
