# Phase 108: Fix warnings that are in warnings.txt - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-16
**Phase:** 108-fix-warnings-that-are-in-warnings-txt
**Areas discussed:** Warning triage, Connection cleanup, Data quality gates

---

## Warning Triage - Noise Warnings

| Option | Description | Selected |
|--------|-------------|----------|
| Suppress at source | Change open_pcornet_con to silently close/reopen, and to_tibble_safe to silently return empty tibble | ✓ |
| Suppress at call site | Wrap calls in suppressWarnings() | |
| Keep as-is | Leave them alone, they're not causing harm | |

**User's choice:** Suppress at source
**Notes:** None

## Warning Triage - min() Warnings (815 instances)

| Option | Description | Selected |
|--------|-------------|----------|
| Fix at source | Replace min(col, na.rm=TRUE) with safe min_or_na() wrapper that returns NA instead of Inf+warning | ✓ |
| suppressWarnings() wrap | Wrap summarise() calls in suppressWarnings() | |
| Pre-filter groups | Filter out groups with all-NA values before summarise() | |

**User's choice:** Fix at source
**Notes:** None

## Warning Triage - Date < 1900-01-01

| Option | Description | Selected |
|--------|-------------|----------|
| Coerce to NA | Replace pre-1900 dates with NA during ingest or harmonization | ✓ |
| Suppress the warning | Keep dates as-is but suppress conversion warning | |
| Keep warning | Leave visible as data quality flags | |

**User's choice:** Coerce to NA
**Notes:** SAS epoch sentinels (1899-12-30), not real dates

## Warning Triage - Date Range (1990-2030)

| Option | Description | Selected |
|--------|-------------|----------|
| Widen the range | Change valid range to ~1960-2030 to accommodate tumor registry dates | ✓ |
| Remove the check | Remove range validation entirely for this field | |
| Keep as-is | Leave the warning as informative | |

**User's choice:** Widen the range
**Notes:** None

---

## Connection Cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Silent close/reopen | Just remove warning() call, keep existing close-and-reopen behavior | ✓ |
| Add connection reuse | Check if existing connection is valid and reuse it | |
| Refactor to with_connection() | Create with_pcornet_con() wrapper for auto-open/close | |

**User's choice:** Silent close/reopen
**Notes:** None

---

## Data Quality Gates - LAB_RESULT_CM

| Option | Description | Selected |
|--------|-------------|----------|
| Improve error message | Keep skip behavior with more actionable warning | |
| Add encoding fallback | Try re-ingesting with latin1/windows-1252 if UTF-8 fails | |
| Keep as-is | Current skip-and-warn is acceptable | |

**User's choice:** Other — "try encoding but I think it's another issue and I'd like to fix it"
**Notes:** User suspects filename mismatch rather than actual unicode error. Wants root cause investigation.

## Data Quality Gates - TABLE-2 >= TABLE-1

| Option | Description | Selected |
|--------|-------------|----------|
| Investigate and fix logic | Check if TABLE-2 filter is too broad or TABLE-1 too narrow | ✓ |
| Adjust the validation | Update the check since TABLE-2 < TABLE-1 may not always hold | |
| Keep the warning | Leave as useful data quality flag | |

**User's choice:** Investigate and fix logic
**Notes:** None

## Data Quality Gates - PROVIDER Table

| Option | Description | Selected |
|--------|-------------|----------|
| Expected missing | Suppress since Level 3/4 classification isn't needed | |
| Should be present | PROVIDER.csv should exist — real issue | ✓ |
| Not sure | Need to check HiPerGator | |

**User's choice:** Should be present — "should be present maybe program is using the wrong filename like i suspect with lab file"
**Notes:** User suspects filename mismatch in code, similar to LAB_RESULT_CM issue. Both may be looking for wrong filenames.

---

## Claude's Discretion

- Exact placement of min_or_na() utility function
- Where pre-1900 date coercion happens (ingest vs harmonization)
- Exact widened range for warn_date_range()

## Deferred Ideas

None — discussion stayed within phase scope
