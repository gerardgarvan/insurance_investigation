# Phase 98: R/28 + Remaining Lookup Optimization - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-10
**Phase:** 98-r-28-remaining-lookup-optimization
**Areas discussed:** Migration scope, Comma-separated lookup pattern, Validation approach

---

## Migration Scope

| Option | Description | Selected |
|--------|-------------|----------|
| R/28 only (Recommended) | Focus on R/28 where performance impact matters. Update success criterion #2 to scope to R/28 only. | |
| R/28 + sweep all files | Replace DRUG_GROUPINGS[ everywhere for consistency. Touches 7 additional files with no performance benefit. | ✓ |
| R/28 + hot paths only | R/28 plus scripts processing >10K rows. Skip small-data scripts. | |

**User's choice:** R/28 + sweep all files
**Notes:** User wants full consistency — all named vector lookups replaced across the entire codebase, even in small-data scripts.

---

## Comma-Separated Lookup Pattern

| Option | Description | Selected |
|--------|-------------|----------|
| Explode-join-collapse (Recommended) | Unnest triggering_codes to one-row-per-code, vectorized keyed join, re-aggregate. Eliminates R-level loop. | ✓ |
| Replace inner lookup only | Keep sapply/str_split structure but swap named vector for keyed join. Minimal code change, small speedup. | |
| You decide | Claude picks the approach per section of R/28. | |

**User's choice:** Explode-join-collapse (Recommended)
**Notes:** Full data.table approach — unnest, vectorized keyed join, re-aggregate. Follows the data.table philosophy of the milestone.

---

## Validation Approach

| Option | Description | Selected |
|--------|-------------|----------|
| R/98 parity + full R/88 (Recommended) | Dedicated R/98 script for R/28 output parity. Full R/88 smoke test as final v3.0 gate. No benchmark needed. | ✓ |
| R/98 parity + benchmark | Same plus benchmark comparison. R/28's data volume is small so speedup modest. | |
| R/88 smoke test only | Skip dedicated R/98. Rely on R/88 existing checks. Simpler but less targeted. | |

**User's choice:** R/98 parity + full R/88 (Recommended)
**Notes:** Parity validation for R/28 output, then full smoke test as v3.0 gate. No benchmark since R/28 processes ~1K episodes.

---

## Additional Context

- User asked about vroom parsing warnings in log3.txt. These are pre-existing benign warnings from raw PCORnet CSV loading during R/97 validation run on HiPerGator. All 36/36 validation checks passed with 5.4x speedup. No action needed.

## Claude's Discretion

- Internal data.table patterns for explode-join-collapse implementation
- Whether helper functions are rewritten or replaced with inline operations
- xlsx_lookups handling (currently named character vectors, not in LOOKUP_TABLES_DT)
- code_descriptions.rds lookup treatment
- R/98 validation script structure

## Deferred Ideas

None — discussion stayed within phase scope.
