# Phase 179: Missing-Distance Bias Check and CBC Capture Check — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-13
**Phase:** 179-missing-distance-bias-check
**Areas discussed:** MISS-04 in-system restriction operationalization

---

## MISS-04 In-System Restriction

| Option | Description | Selected |
|--------|-------------|----------|
| Any encounter in CDM (post-anchor) | In-system = any CDM encounter; trivially satisfied for Phase 165 patients | |
| ≥1 not-far encounter specifically | In-system = encounter at facility <100 mi from patient | |
| Non-CBC lab in LAB_RESULT_CM | ≥1 non-CBC lab in same window = evidence of in-system lab care | ✓ (primary) |
| Any other CDM encounter | ≥1 encounter (any type) in window excluding index | ✓ (secondary) |

**User's choice:** Two-level restriction. Primary = ≥1 non-CBC lab in `LAB_RESULT_CM` (any `LAB_LOINC` not in CBC code set {6690-2, 718-7, 777-3}) in the same window as the CBC outcome (post-anchor; per-encounter if encounter-level unit). Secondary = ≥1 other encounter in CDM in same window. Descriptive proportions (far vs not-far meeting each definition) reported first; then Phase 165 OR rerun within each restricted set.

**Notes:** Rationale = CBC is a lab; a patient with other in-system labs but no CBC that year is unlikely to be capturing CBC elsewhere, while zero in-system labs fits out-of-system lab care. The window for the restriction mirrors exactly how Phase 165 defines the outcome window; for encounter-level unit, restriction is per-encounter. Apply MISS-04 locked interpretation rule to primary restriction only; secondary reported alongside.

---

## Claude's Discretion

- Workbook sheet layout and tab naming (within spec constraints)
- Whether to use single combined workbook vs separate workbooks (recommend single)
- R/177 RDS loading pattern for candidates

## Deferred Ideas

None.
