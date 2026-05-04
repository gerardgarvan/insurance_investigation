# Phase 40: Investigate Unmatched NDC Codes - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-04
**Phase:** 40-investigate-unmatched-ndc-codes
**Areas discussed:** Code lookup method, Tables & code types in scope, Classification strategy, Config integration

---

## Code Lookup Method

| Option | Description | Selected |
|--------|-------------|----------|
| RxNorm API | NLM's RxNorm API maps NDC->RxNorm->drug name. Free, no auth, same NLM infrastructure as Phase 39 | ✓ |
| FDA NDC Directory | Downloadable flat file from FDA with NDC-to-product mapping. Offline lookup, no API calls | |
| OpenFDA drug API | openFDA API has NDC lookup. Free, no auth, but more complex JSON and rate-limited | |
| You decide | Let Claude choose based on existing patterns | |

**User's choice:** RxNorm API (Recommended)
**Notes:** Consistent with Phase 39's NLM infrastructure. rxnav.nlm.nih.gov endpoints.

---

## Tables & Code Types in Scope

| Option | Description | Selected |
|--------|-------------|----------|
| NDC + RXNORM | Investigate both NDC codes from DISPENSING.NDC AND unmatched RXNORM CUIs from all 3 drug tables | ✓ |
| NDC only | Strictly DISPENSING.NDC codes. RXNORM gap analysis would be separate | |
| You decide | Let Claude assess volume and decide | |

**User's choice:** NDC + RXNORM (Recommended)
**Notes:** Current chemo_rxnorm only has 4 CUIs (ABVD regimen) — significant gap expected in RXNORM coverage.

---

## Classification Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Drug name keyword matching | Map NDC/RXNORM to drug name via API, then classify by keyword patterns for known drugs | ✓ |
| RxNorm therapeutic class | Use RxNorm API for ATC/NDF-RT drug classes, then map to treatment category | |
| You decide | Let Claude determine approach based on data | |

**User's choice:** Drug name keyword matching (Recommended)
**Notes:** Same fully-automated approach as Phase 39. Keyword patterns for known HL drugs.

---

## Config Integration

| Option | Description | Selected |
|--------|-------------|----------|
| New NDC vectors + expand RXNORM | Add chemo_ndc, supportive_care_ndc vectors AND expand chemo_rxnorm with new CUIs | ✓ |
| RXNORM only, skip NDC | Map NDC back to RXNORM and only enrich chemo_rxnorm | |
| You decide | Let Claude assess which fits existing matching infrastructure | |

**User's choice:** New NDC vectors + expand RXNORM (Recommended)
**Notes:** Keeps code types separate in TREATMENT_CODES (existing naming pattern). Both NDC vectors and expanded RXNORM vectors.

---

## Claude's Discretion

- RxNorm API endpoint selection and batching strategy
- Keyword classification rules for drug name patterns
- xlsx report layout and styling
- Handling of unresolvable NDC codes
- MED_ADMIN NDC scope determination

## Deferred Ideas

- Downstream script updates (R/03, R/10) to match on new NDC vectors
- ICD-10-PCS broader range detection for drug admin codes
- Drug interaction or polypharmacy analysis
