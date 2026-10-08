# Phase 168: NHL-Only and HL+NHL Gantt Episode Subsets — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-08
**Phase:** 168-nhl-only-and-hl-nhl-gantt-episode-subsets
**Areas discussed:** CSV output, "x" matching, drug_names QC format

---

## CSV Output for Tableau

| Option | Description | Selected |
|--------|-------------|----------|
| Workbook only | Tableau can connect to xlsx | |
| Workbook + CSVs | Same data frames, cheap to add, no risk of disagreement | ✓ |

**User's choice:** Yes to CSVs. Named `nhl_only_episodes_<date>.csv` and `hl_nhl_episodes_<date>.csv`. Written from the same data frames as the workbook tabs so they cannot disagree.

---

## "x" Value Matching

| Option | Description | Selected |
|--------|-------------|----------|
| Exact lowercase only | Sheet says "x", match only "x" | |
| Case-insensitive + trim + log unexpected | Tolerates "X", " x "; logs non-blank non-x values in QC | ✓ |

**User's choice:** Already settled at milestone level — case-insensitive, whitespace-trimmed. Non-blank non-"x" values in columns E, F, J are logged in QC (not silently dropped).

**Notes:** Closed as a pre-existing decision; not a new choice made in this session.

---

## drug_names QC Mismatch Format

| Option | Description | Selected |
|--------|-------------|----------|
| Count + ID list only | Compact; requires opening both files to see what differs | |
| Side-by-side (mismatched rows only) | One row per mismatch: patient_id, episode_number, sheet value, Gantt value | ✓ |

**User's choice:** Side-by-side mismatched rows. Normalize both sides first (lowercase → trim → split on separator → sort → rejoin) so order-only differences don't count. QC shows three counts: exact matches, matches-after-normalizing, real mismatches. Only real mismatches get the detail rows.

**Notes:** "Since the Gantt file is the August snapshot the sheet was marked from, real mismatches should be rare, and each one points to a join or version problem."

---

## Additional Constraints Flagged (not gray areas, but plan-time reminders)

- Outputs contain patient IDs → `output/internal/`, marked INTERNAL. Only QC aggregate counts are non-internal.
- Plan must confirm from the August gantt CSV: ID column name, episode-number column name, chemo-row filter column/value, episode numbering scope. Do not assume.
- Plans end with HiPerGator run step + team review step (chemo-combos file only exists there).

## Claude's Discretion

None — all decisions were user-specified.

## Deferred Ideas

None.
