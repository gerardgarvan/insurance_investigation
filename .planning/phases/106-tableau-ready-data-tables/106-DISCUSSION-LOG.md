# Phase 106: Tableau-Ready Data Tables - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-15
**Phase:** 106-tableau-ready-data-tables
**Areas discussed:** TABLE-1 encounter scope, TABLE-2 drug granularity, Extra columns for Tableau joins

---

## TABLE-1 Encounter Scope

| Option | Description | Selected |
|--------|-------------|----------|
| All cohort encounters with cancer DX | Query DIAGNOSIS table for ALL encounters in the HL cohort that have any cancer code. Broadest view. | |
| Treatment encounters only | Only encounters from treatment_episode_detail.rds. Smaller table but limits Tableau to treatment visits only. | ✓ |
| All cohort encounters (including no-cancer) | Every encounter in cohort, with cancer codes where they exist (NULL otherwise). Largest table. | |

**User's choice:** Treatment encounters only
**Notes:** Simplifies implementation by reusing R/57's encounter ID source. Limits TABLE-1 to treatment visits.

---

## TABLE-2 Drug Granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Individual drug names + class | Each row: encounter, specific medication name (e.g. Doxorubicin), drug class, plus cancer codes. Most Tableau-flexible. | ✓ |
| Drug class/sub-category only | Aggregate to class level. Less granular but simpler. | |
| You decide | Claude picks the structure based on codebase patterns. | |

**User's choice:** Individual drug names + class
**Notes:** Provides maximum drill-down capability in Tableau.

---

## Extra Columns for Tableau Joins

| Option | Description | Selected |
|--------|-------------|----------|
| Core + treatment context | PATID, ENCOUNTERID, treatment_date, treatment_type, cancer codes + category names. Enough for most views. | ✓ |
| Core mapping only | Just ENCOUNTERID and code mappings. Minimal, Amy joins in Tableau. | |
| Kitchen sink | Add payer, episode number, cancer_linked, first_line, drug_group. Maximum flexibility. | |

**User's choice:** Core + treatment context
**Notes:** Balanced approach — enough context for standalone Tableau use without bloating the table.

---

## Claude's Discretion

- Script numbering and whether TABLE-1/TABLE-2 share a single script
- Column ordering within tables
- Whether to reuse R/57 cancer code extraction via shared helper or inline
- Sheet naming within xlsx workbooks

## Deferred Ideas

None — discussion stayed within phase scope
