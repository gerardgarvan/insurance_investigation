# Phase 96: classify_payer_tier_dt() Implementation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-10
**Phase:** 96-classify-payer-tier-dt-implementation
**Areas discussed:** Function placement, Caller migration timing, Parity validation scope, Return type & API

---

## Function Placement

| Option | Description | Selected |
|--------|-------------|----------|
| Same utils_payer.R | Add classify_payer_tier_dt() alongside the existing dplyr classify_payer_tier() in R/utils/utils_payer.R. Both versions of the same function in one file — easy to compare side-by-side, and callers already source this file. | ✓ |
| New utils_payer_dt.R | Separate file for data.table payer functions. Keeps dplyr and data.table code isolated, but adds another file to the R/utils/ directory (already has 11 files). | |
| Inside utils_dt.R | Put it in the existing data.table helpers file (R/utils/utils_dt.R). Groups all data.table code together, but mixes generic conversion helpers with domain-specific payer logic. | |

**User's choice:** Same utils_payer.R (Recommended)
**Notes:** None — straightforward selection.

---

## Caller Migration Timing

| Option | Description | Selected |
|--------|-------------|----------|
| Defer to their phases | R/60 switches in Phase 97, R/61/R/62 switch in Phase 98. Phase 96 only creates and validates the function. Callers keep using classify_payer_tier() until their own migration. | ✓ |
| Switch all callers now | Update all 3 callers (R/60, R/61, R/62) to use classify_payer_tier_dt() in Phase 96 after parity is confirmed. Gets migration done early but makes Phase 96 larger. | |
| Switch one caller as proof | Migrate R/60 as proof-of-concept in Phase 96 (it's the next phase target anyway), leave R/61/R/62 for Phase 98. Validates the drop-in works in a real script. | |

**User's choice:** Defer to their phases (Recommended)
**Notes:** None — clean phase separation.

---

## Parity Validation Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone script | Create R/96_validate_payer_dt.R (like R/95 for infrastructure). Runs both functions on ENCOUNTER data, compares all output columns row-by-row, logs pass/fail. Can run on HiPerGator production data. | ✓ |
| Smoke test section only | Add a Section 15h to R/88_smoke_test_comprehensive.R. Runs parity check on fixture data (20 patients). Integrated into existing validation infrastructure. | |
| Both script + smoke test | Standalone R/96 for detailed production validation, PLUS a smoke test section for ongoing regression. Belt and suspenders. | |

**User's choice:** Standalone script (Recommended)
**Notes:** None — follows Phase 95 pattern.

---

## Return Type & API

| Option | Description | Selected |
|--------|-------------|----------|
| Tibble (drop-in compatible) | Converts result back to tibble via to_tibble_safe() before returning. Callers don't need to change anything when they switch — just swap the function name. Matches success criteria wording. | |
| Data.table (caller converts) | Returns raw data.table for maximum speed. Callers that need tibble call to_tibble_safe() themselves. More efficient if caller will do more data.table work after. | |
| You decide | Claude picks based on how the function will actually be used in R/60, R/61, R/62. | ✓ |

**User's choice:** You decide
**Notes:** Deferred to Claude's discretion based on actual caller usage patterns in R/60, R/61, R/62.

---

## Claude's Discretion

- Return type (tibble vs data.table) based on downstream caller patterns
- Internal implementation details (fcase(), join syntax, copy() placement)
- API signature matching
- Validation script structure

## Deferred Ideas

None — discussion stayed within phase scope.
