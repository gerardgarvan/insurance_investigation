# Phase 119: Fix death_cause_nhl_flag - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-09
**Phase:** 119-fix-death-cause-nhl-flag
**Areas discussed:** Signal source, Fallback behavior

**Diagnosis established during discussion:** Inspected `output/death_cause_nhl_flag.csv` —
1,344 deceased rows, `cause_of_death_is_nhl` blank on 100% of rows. Confirmed the pipeline
loads a `DEATH` table but no PCORnet `DEATH_CAUSE` table; R/102 reads `DEATH.DEATH_CAUSE` which
is unpopulated → all NA. Not a logic bug; wrong/empty source field.

---

## Signal source (where 'died of NHL' should come from)

| Option | Description | Selected |
|--------|-------------|----------|
| Investigate first | Check DEATH columns, a delivered DEATH_CAUSE table CSV, and TUMOR_REGISTRY vital/cause fields on HiPerGator, then implement | ✓ |
| Load PCORnet DEATH_CAUSE table | Add DEATH_CAUSE.csv to the pipeline and read real cause codes | (candidate within investigation) |
| Use TUMOR_REGISTRY | Derive from cancer-registry cause/vital-status fields | (candidate within investigation) |
| Proxy: NHL in diagnosis history | Deceased + NHL in confirmed cancer history (different meaning) | (backstop only) |

**User's choice:** Investigate first
**Notes:** Exhaustively locate the populated source before rewriting R/102.

---

## Fallback if no cause-of-death field found anywhere

| Option | Description | Selected |
|--------|-------------|----------|
| Diagnosis-history proxy | Flag deceased patients with NHL in cancer history, labeled as proxy | (last resort) |
| Report infeasible, leave blank | Document unavailable, no proxy | |
| Pause and ask | Stop after investigation, decide then | |
| Other (free text) | — | ✓ |

**User's choice (free text):** "it should find something"
**Notes:** Do NOT accept all-blank / "unavailable." The investigation must be thorough and is
expected to surface a real cause-of-death / NHL-death signal. Proxy is only a last resort if
truly nothing cause-specific exists.

## Deferred Ideas

- Broadening NHL beyond classify_codes()=="Non-Hodgkin Lymphoma"
- Adding raw cause code / category as extra columns
