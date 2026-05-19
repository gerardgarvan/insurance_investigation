# Phase 3: Confirm Cancer Site Codes by Distinct Date Count - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-19
**Phase:** 03-confirm-cancer-site-codes-by-distinct-date-count
**Areas discussed:** Code matching level, Data sources & dates, Output format, Relationship to R/47

---

## Code Matching Level

| Option | Description | Selected |
|--------|-------------|----------|
| Exact ICD-10 code | C81.10 must appear on 2+ dates. Strictest — same disease + anatomic site. | |
| 3-char prefix | Any C81.* code on 2+ dates confirms C81 (Hodgkin Lymphoma). Matches R/47's PREFIX_MAP. | |
| Category level | Any code in the same cancer site category on 2+ dates. Loosest matching. | |

**User's choice:** "do 1 and 2" — Both exact code AND 3-char prefix levels. Run confirmation at both levels for comparison.
**Notes:** User wants exploratory comparison of both confirmation levels.

### Follow-up: Multi-level output format

| Option | Description | Selected |
|--------|-------------|----------|
| One xlsx, two sheets | Sheet 1: exact code confirmation. Sheet 2: prefix-level confirmation. | ✓ |
| Separate xlsx files | Two separate files, one per level. | |

**User's choice:** One xlsx, two sheets
**Notes:** None

---

## Data Sources & Dates

| Option | Description | Selected |
|--------|-------------|----------|
| DIAGNOSIS only | Encounter-based DX_DATE for distinct-date counting. TUMOR_REGISTRY already registrar-confirmed. | ✓ |
| DIAGNOSIS + TUMOR_REGISTRY | Pool dates from both sources. | |
| You decide | Claude picks based on data availability. | |

**User's choice:** DIAGNOSIS only
**Notes:** TUMOR_REGISTRY is inherently registrar-confirmed and doesn't need date-based validation.

### Follow-up: Category inclusion

| Option | Description | Selected |
|--------|-------------|----------|
| Only populated categories | Show only categories with at least one patient. | ✓ |
| Full 53-category grid | Show all 53 categories including zeros. | |

**User's choice:** Only populated categories
**Notes:** None

---

## Output Format

| Option | Description | Selected |
|--------|-------------|----------|
| Counts comparison | Per category: total, confirmed, unconfirmed, confirmation_rate. | ✓ |
| Confirmed only | Per category: confirmed count only. | |
| Patient-level detail | One row per patient per code with n_distinct_dates. | |

**User's choice:** Counts comparison
**Notes:** Shows the impact of the confirmation filter at a glance.

---

## Relationship to R/47

| Option | Description | Selected |
|--------|-------------|----------|
| New script | New R/50_*.R script. R/47 stays as unfiltered baseline. Reuses PREFIX_MAP and classify_codes(). | ✓ |
| Modify R/47 | Add confirmation logic directly to R/47. | |

**User's choice:** New script
**Notes:** Keeps R/47 clean as the baseline frequency. New script reuses existing classification logic.

---

## Claude's Discretion

- Script numbering and naming
- PREFIX_MAP sourcing strategy (import from R/47 vs duplicate)
- Column ordering and xlsx styling
- Summary row inclusion

## Deferred Ideas

None — discussion stayed within phase scope
