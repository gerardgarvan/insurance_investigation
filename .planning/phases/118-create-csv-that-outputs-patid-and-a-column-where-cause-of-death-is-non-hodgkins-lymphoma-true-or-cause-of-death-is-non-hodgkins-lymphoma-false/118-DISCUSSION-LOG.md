# Phase 118: Cause-of-Death NHL Flag CSV - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-09
**Phase:** 118-create-csv-that-outputs-patid-and-a-column-where-cause-of-death-is-non-hodgkins-lymphoma...
**Areas discussed:** Row scope, Missing-cause handling, NHL definition

---

## Row scope

| Option | Description | Selected |
|--------|-------------|----------|
| Deceased patients only | One row per patient with a DEATH record (DEATH_DATE present) | ✓ |
| Entire HL cohort | One row per confirmed HL cohort patient; alive → FALSE | |
| All patients with any death record (not restricted to HL cohort) | Every DEATH-table patient | |

**User's choice:** Deceased patients only
**Notes:** Follow R/35 death-data derivation (1900 sentinel → NA, drop NA, one record per patient).

---

## Missing-cause handling

| Option | Description | Selected |
|--------|-------------|----------|
| FALSE (binary) | NHL = TRUE, everything else incl. missing = FALSE | |
| Third value (NA/Unknown) | TRUE = NHL, FALSE = other coded cause, blank/NA = not recorded | ✓ |

**User's choice:** Third value (NA/Unknown)
**Notes:** DEATH_CAUSE is frequently uncoded (per R/35); collapsing missing into FALSE would misrepresent the data.

---

## NHL definition

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse project NHL definition | classify_codes()/CANCER_SITE_MAP == "Non-Hodgkin Lymphoma" (ICD-10 C82-C86, C88; ICD-9 200, 202) | ✓ |
| Broaden to all lymphoma-ish codes | Also C96 (other lymphoid), C91 (lymphoid leukemia) | |

**User's choice:** Reuse project NHL definition
**Notes:** Stay consistent with the rest of the pipeline; Hodgkin (C81) excluded.

## Claude's Discretion

- Output file name (suggested death_cause_nhl_flag.csv) and NHL column name (cause_of_death_is_nhl)
- Script placement (new 100+ standalone script) + self-bootstrap DuckDB connection
- Registration in R/39 and R/88 smoke-test section (Phase 116/117 precedent)
- CSV convention: write.csv(row.names = FALSE, na = "")

## Deferred Ideas

- Broadening NHL to C96/C91/other lymphoid-hematopoietic codes (declined)
- Including alive patients / full cohort with FALSE (declined)
- Adding cause-of-death category label or raw DEATH_CAUSE code as extra columns
