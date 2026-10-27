# Phase 186: Survivorship Rate Granularity - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-22
**Phase:** 186-survivorship-rate-granularity
**Areas discussed:** D-186-01 (Biannual definition), Implementation path

---

## D-186-01: Biannual Definition

| Option | Description | Selected |
|--------|-------------|----------|
| Every 6 months | Reuse R/184 half-year output blocks; no new patient-year calculation | ✓ |
| Every 2 years | New follow-up window; new patient-year calculation | |

**User's choice:** Every 6 months — "biannual" strictly means twice yearly; every 2 years would be "biennial." R/184 already writes "Half-year rates (years 2+)" and "Half-year rates (all years)" blocks to the Rates sheet, so no new computation is needed.

**Notes:** Decision recorded as provisional pending team confirmation at the next meeting. If team intends "every 2 years," that becomes a new phase — not a revision of Phase 186.

---

## Implementation Path

| Option | Description | Selected |
|--------|-------------|----------|
| New standalone R/186 | R/184 untouched; reads both windows from pinned workbook and stacks | ✓ |
| Extend R/184 | Modify R/184 to output a combined table | |

**User's choice:** New standalone R/186. R/184 is executed v3.11 code and must not be edited (CLAUDE.md anti-pattern 7). R/186 pins `R184_OUTPUT` to the dated workbook named in 185-01-SUMMARY, reads annual (years 2+) and half-year (years 2+) blocks by exact label from the 185 schema probe, and stacks into one long table. Suppressed values carried as-is.

**Notes:**
- All-years blocks go on a secondary sheet.
- Rate unit (per patient-year vs per patient-half-year) must be confirmed from the 185 schema probe before code is written; state unit in KEY or column header. Do not rescale unless units differ; record any conversion formula in a CONTEXT revision.
- R/186 output workbook should be pinned as `R186_OUTPUT` at close-out for Phase 188 consumption.

---

## Claude's Discretion

- Script section structure within R/186
- Whether to run `probe_inputs()` on the output workbook for downstream phases

## Deferred Ideas

- Biennial (every 2 years) window — new phase if team redirects
- Anthracycline as a covariate in modality rate models (v3.13 candidate)
