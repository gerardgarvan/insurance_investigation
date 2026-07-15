# Phase 128: DoI Classification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-15
**Phase:** 128-doi-classification
**Areas discussed:** Cohort scope, Diagnosis position, L10.81 rollup, Script organization

---

## Cohort scope

| Option | Description | Selected |
|--------|-------------|----------|
| HL cohort only | Restrict to `get_hl_patient_ids()`, push `PATID IN (...)` alongside the prefix filter into DuckDB SQL. Smallest/safest pull; every DoI co-occurs with the HL cohort. (Recommended) | |
| Full extract | Classify DoI across the entire DIAGNOSIS table (all patients), join to cohort later. | ✓ |

**User's choice:** Full extract
**Notes:** Still OOM-safe because the `LEFT(DX,3) IN (...)` prefix filter runs before `collect()` — only DoI-prefixed rows are materialized, just across all patients. Follow-up added an `in_hl_cohort` tag so Phase 129 can restrict/compare cheaply.

---

## Diagnosis position

| Option | Description | Selected |
|--------|-------------|----------|
| All positions | Classify DoI on every DIAGNOSIS row (principal P + secondary S). Captures comorbid DoI. (Recommended) | ✓ |
| Principal only | Only classify PDX-principal diagnoses; would miss most secondary DoI comorbidities. | |

**User's choice:** All positions
**Notes:** DoI conditions (RA/SLE/IBD) usually appear as secondary/comorbid codes.

---

## L10.81 rollup

| Option | Description | Selected |
|--------|-------------|----------|
| Count as DoI, flagged | L10.81 sets has_any_doi=TRUE, appears in doi_categories, carries paraneoplastic_flag=TRUE as a caveat. Preserves HL+paraneoplastic co-occurrence. (Recommended) | ✓ |
| Segregate from counts | Track L10.81 separately, exclude from primary rollups. Cleaner pure-autoimmune counts, loses co-occurrence signal. | |

**User's choice:** Count as DoI, flagged
**Notes:** The flag is the disambiguator (DOI-CLASS-05); Phase 129 can filter on it for a pure-autoimmune view.

---

## Script organization

| Option | Description | Selected |
|--------|-------------|----------|
| R/111 classification-only | R/111 produces the two .rds artifacts only; Phase 129 attribution/output is a separate R/112 reading them. (Recommended) | ✓ |
| R/111 shared/extended | R/111 classifies now and Phase 129 extends it in place with attribution + output. | |

**User's choice:** R/111 classification-only
**Notes:** One-investigation-per-script convention; cached .rds files are the explicit hand-off to Phase 129; keeps the read-only guarantee clean.

---

## Follow-up: Cohort tag (raised by the full-extract choice)

| Option | Description | Selected |
|--------|-------------|----------|
| Add in_hl_cohort flag | Boolean column on doi_encounters/doi_patients via get_hl_patient_ids(); Phase 129 splits HL vs full-extract cheaply. (Recommended) | ✓ |
| No cohort tag | Pure full-extract artifacts; Phase 129 re-derives cohort membership itself. | |

**User's choice:** Add in_hl_cohort flag

---

## Claude's Discretion

- Prefix-filter SQL construction from DOI_CODE_MAP keys (3-char pushdown + R-side refinement for 4-char disambiguation keys)
- DX_DATE null / 1900-sentinel handling (per utils_dates.R conventions)
- Multi-code-per-encounter representation (long-format grain already permits it)
- doi_categories ascending-collapse mechanics at patient grain
- Logging / tabyl(doi_category) review format
- stopifnot() vs checkmate for the mutual-exclusivity assertion (must halt before writing artifacts)

## Deferred Ideas

- Attribution linkage (rituximab/MTX ↔ DoI) → Phase 129 (R/112)
- 4-sheet Tableau-ready output + three-state likely_non_lymphoma_directed flag → Phase 129
- R/39 registration, SCRIPT_INDEX, R/88 smoke section, HiPerGator runtime gate → Phase 130
- Automated HIPAA suppression — explicitly NOT applied (Phase 127 D-07)
