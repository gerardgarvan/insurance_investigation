# Phase 115: Add 7-Day Confirmed Column + Age at Episode to Gantt Data - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-06-26
**Phase:** 115-add-7-day-confirmed-column-to-gantt-data
**Areas discussed:** Column format, Match logic, Output scope, Age at episode (folded)

---

## Column Format

| Option | Description | Selected |
|--------|-------------|----------|
| Per-category list (Recommended) | Comma-separated list of only the confirmed categories. Empty string if none confirmed. | ✓ |
| Boolean flag | Single TRUE/FALSE -- TRUE if ALL episode_dx_categories are 7-day confirmed. Simpler but loses detail. | |
| You decide | Claude picks the most useful format. | |

**User's choice:** Per-category list
**Notes:** User selected the recommended option. This preserves granularity -- downstream consumers can see exactly which categories are confirmed vs not.

---

## Match Logic

| Option | Description | Selected |
|--------|-------------|----------|
| Intersect categories (Recommended) | Intersect episode_dx_categories with patient's 7-day confirmed categories at category level. Empty if no overlap or no dx categories. | ✓ |
| Intersect at code level | Match at raw ICD code level, then map back to category names. More granular but adds complexity. | |

**User's choice:** Intersect categories
**Notes:** Category-level matching is sufficient. Code-level would add complexity without meaningful benefit since categories are the analysis unit.

---

## Output Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Episodes only (Recommended) | Add to gantt_episodes.csv only, consistent with Phase 112 pattern. | ✓ |
| Both CSVs | Add to both gantt_episodes.csv and gantt_detail.csv. | |

**User's choice:** Episodes only
**Notes:** Consistent with Phase 112 which added episode_dx_categories to episodes only.

---

## Age at Episode (Folded Scope)

User requested adding an "age at episode" column during discussion. Evaluated as scope addition:

| Option | Description | Selected |
|--------|-------------|----------|
| Fold it in | Add age_at_episode to this phase alongside 7-day confirmed column. Both are simple additive columns. | ✓ |
| Separate phase | Note as deferred idea, create separate phase. | |

**User's choice:** Fold it in

| Option | Description | Selected |
|--------|-------------|----------|
| Integer years (Recommended) | Floor of (episode_start - birth_date) in years. Standard clinical format. | ✓ |
| Decimal years | Precise age with decimal. More granular but less conventional. | |

**User's choice:** Integer years
**Notes:** Integer years is standard for clinical reporting. Birth date from DEMOGRAPHIC table.

---

## Claude's Discretion

- Column naming for both new fields
- Pipeline placement (R/28 vs R/52)
- DEMOGRAPHIC birth date sourcing method
- Schema count updates

## Deferred Ideas

None -- age at episode was folded into phase scope rather than deferred.
