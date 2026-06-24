# Phase 113: Investigate encounters after death date - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-06-24
**Phase:** 113-investigate-encounters-after-death-date-quantify-how-far-after-death-the-200-patients-encounters-occur
**Areas discussed:** Output detail level, Time bucketing, Clinical scope

---

## Output Detail Level

| Option | Description | Selected |
|--------|-------------|----------|
| Both (Recommended) | Sheet 1: per-patient summary (one row per patient with count, min/max/median gap in days). Sheet 2: per-encounter detail (every post-death encounter with exact date and gap from death). | Y |
| Per-patient summary only | One row per patient with aggregate stats (count of post-death encounters, days between death and last encounter). Compact overview. | |
| Per-encounter detail only | Every individual post-death encounter listed with date and gap from death. Full granularity but no summary view. | |

**User's choice:** Both (Recommended)
**Notes:** Two-sheet xlsx providing both a summary overview and full granular detail.

---

## Time Bucketing

| Option | Description | Selected |
|--------|-------------|----------|
| Bucketed ranges (Recommended) | Group gaps into clinically meaningful ranges: 0-30 days, 31-90 days, 91-365 days, >1 year. Summary sheet shows count per bucket. Detail sheet still has raw days. | Y |
| Raw days only | Show exact days_after_death for each encounter. No pre-defined buckets. | |
| Both buckets + raw | Detail sheet has raw days_after_death column AND a bucket column. Summary sheet has a bucket distribution table alongside patient-level stats. | |

**User's choice:** Bucketed ranges (Recommended)
**Notes:** Clinically meaningful bucket ranges on summary; raw days on detail sheet for flexibility.

---

## Clinical Scope

| Option | Description | Selected |
|--------|-------------|----------|
| All clinical activity (Recommended) | ENCOUNTER admits, DIAGNOSIS records, and treatment episodes -- mirrors what R/53 already flags. | Y |
| ENCOUNTER admits only | Focus strictly on ENCOUNTER table ADMIT_DATE after death. | |
| Encounters + Diagnoses | ENCOUNTER admits and DIAGNOSIS records, skip treatment episodes. | |

**User's choice:** All clinical activity (Recommended)
**Notes:** Full scope matching R/53's existing detection. Each event tagged with source table.

---

## Claude's Discretion

- Styled xlsx headers (existing meeting-presentable pattern)
- Optional third summary sheet with bucket distribution cross-tabbed by activity type
- R/88 smoke test section additions

## Deferred Ideas

None -- discussion stayed within phase scope.
