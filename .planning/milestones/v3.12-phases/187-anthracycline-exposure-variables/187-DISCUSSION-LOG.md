# Phase 187: Anthracycline Exposure Variables - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-22
**Phase:** 187-anthracycline-exposure-variables
**Areas discussed:** Drug source + schema probe, Survivorship set join design, any_anthracycline NA logic, data_cutoff_date source

---

## Drug Source + Schema Probe

| Option | Description | Selected |
|--------|-------------|----------|
| 180-day episode detail RDS (same as R/167) | Probe this file; one row per ID × drug × admin_date after alias collapse | ✓ |
| Also probe MED_ADMIN / DISPENSING directly | More thorough but risks double-counting; Phase 124 already folded these in | |
| You decide | Claude resolves from codebase | |

**User's choice:** 180-day episode detail RDS. Phase 124 already folded MED_ADMIN and DISPENSING; going back to raw tables risks double-counting.

**Notes:** Probe must confirm (a) which of {Doxorubicin, Daunorubicin, Epirubicin, Idarubicin} appear after alias collapse, and (b) whether admin_date has any window filter. If either check fails, stop and decide before writing code. Absent drugs recorded on KEY, not hunted.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Task 0 = run probe, checkpoint before planning | User confirms probe before planner writes code | |
| Task 0 = run probe, continue (no checkpoint) | Probe runs, planner proceeds | |
| Probe before planning (user runs it manually) | User runs probe_inputs() on HiPerGator, commits schema file, then /gsd:plan-phase | ✓ |

**User's choice:** Probe runs on HiPerGator before `/gsd:plan-phase 187`. User copies `.planning/schemas/187_schema_<date>.md` to repo unedited and pastes drug labels and admin_date min/max. Task 0 of the plan cites the existing probe file.

---

## Survivorship Set Join Design

| Option | Description | Selected |
|--------|-------------|----------|
| R/187 writes patient-grain only; Phase 188 joins to encounters | Simpler; Phase 188 computes days_since at echo level | ✓ |
| R/187 writes patient-grain + echo-encounter-grain RDS | Two files to keep in sync | |
| You decide | Claude picks approach | |

**User's choice:** Patient-grain only. Echo dates belong to Phase 188; R/187 shouldn't reach into survivorship events.

**Notes:**
- Extra columns in patient-grain RDS: `any_chemo`, `drugs_received`, `follow_end` — Phase 188 needs follow_end for rate denominator
- ROADMAP and REQUIREMENTS updated (quick task) to move `days_since_last_anthracycline_dose` from Phase 187 to Phase 188 / ECHO-01

---

## any_anthracycline NA Logic

| Option | Description | Selected |
|--------|-------------|----------|
| Episode detail presence = has chemo; absent = NA | any_anthracycline = NA for no chemo | |
| Separate any_chemo flag; any_anthracycline never NA | TRUE/FALSE for all patients; any_chemo separates no-chemo from chemo-no-anthracycline | ✓ |

**User's choice:** `any_anthracycline` is TRUE/FALSE, never NA. Add `any_chemo` TRUE/FALSE column. Downstream NA handling in Phase 188 would silently drop patients.

**Notes:** ANTH-01 REQUIREMENTS wording corrected — the "NA for unexposed" language applied to the time variables, not the flag. `last_anthracycline_date` and `years_since_last_anthracycline` are NA when `any_anthracycline == FALSE`.

---

## data_cutoff_date Source

| Option | Description | Selected |
|--------|-------------|----------|
| Use compute_followup() follow_end per patient | Reuses Phase 161 definition; accounts for death | ✓ |
| Pin scalar cutoff date constant in CONFIG | Explicit but CONFIG lacks this field; doesn't account for death | |
| You decide | | |

**User's choice:** Use `follow_end` from `compute_followup()` — not reimplemented in R/187, read from its pinned output or called with same arguments as R/184.

**Notes:**
- Last dose after `follow_end`: set `years_since_last_anthracycline = NA`, keep row, count on KEY. Never pass negative.
- ROADMAP and ANTH-02 updated to say "last dose → follow_end (Phase 161 definition)" replacing "min(last_encounter, data_cutoff)"
- ANTH-02 update is part of the same quick task as the days_since move

---

## Claude's Discretion

- Section structure within R/187
- Whether to run probe_inputs() on R/187 output RDS for Phase 188 reference
- Exact column order in output RDS

## Deferred Ideas

- Mitoxantrone sensitivity row → Phase 188 scope
- Cumulative dose / cardiotoxicity dose-equivalence → out of scope
