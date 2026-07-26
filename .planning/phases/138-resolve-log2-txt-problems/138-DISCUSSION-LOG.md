# Phase 138: resolve-log2-txt-problems - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-26
**Phase:** 138-resolve-log2-txt-problems
**Areas discussed:** Scope (all 4 failure groups), DuckDB gsub fix, R/03 scoping fix, cascade attribution, smoke test coverage

---

## Scope

| Option | Description | Selected |
|--------|-------------|----------|
| DuckDB gsub error (4 scripts) | R/13 gsub in lazy filter | ✓ |
| R/03 ingest failure | <<- scoping bug | ✓ |
| R/53 PATID column missing | Wrong column name | ✓ |
| R/52 / R/101 / R/104 connection failures | Cascades from R/53 | ✓ |

**User's choice:** All four groups
**Notes:** R/52, R/101, R/104 identified as cascades from R/53 — resolving R/53 resolves all three.

---

## DuckDB gsub fix approach

| Option | Description | Selected |
|--------|-------------|----------|
| Pre-compute combined IN-list | unique(c(dotted, undotted)) before filter | ✓ |
| Use DuckDB regexp_replace | DuckDB-native string replacement in SQL | |
| collect() before filter | Pull 5M rows to R first | |

**User's choice:** Pre-compute combined IN-list (recommended)
**Notes:** Consistent with R/14's existing pattern at lines 140-141.

---

## R/03 scoping fix

| Option | Description | Selected |
|--------|-------------|----------|
| local() block / return-value pattern | Restructure to avoid <<- in callbacks | ✓ |
| Environment reference object | e$tables_ingested = reference type | |
| Change R/39 to use globalenv() | Simpler but pollutes global namespace | |

**User's choice:** local() block with return-value pattern (recommended)

---

## gsub fix scope (R/13 only vs check R/70/R/71 independently)

| Option | Description | Selected |
|--------|-------------|----------|
| Fix R/13 only — R/70/R/71 inherit | Cascades resolve from R/13 fix | ✓ |
| Verify each script independently | Direct grep check on R/70, R/71 | |

**User's choice:** R/70 and R/71 inherit — fix only R/13

---

## R/88 Smoke Tests

| Option | Description | Selected |
|--------|-------------|----------|
| Add R/88 assertions for each fix | New section with 3 checks | ✓ |
| No new smoke tests | Pipeline exit 0 is sufficient | |

**User's choice:** Add R/88 assertions (recommended)

---

## Deferred Ideas

None.
