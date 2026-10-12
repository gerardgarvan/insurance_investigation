# Phase 177: NEEDS_TEMPORAL_MATCH Sizing Memo — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-12
**Phase:** 177-needs-temporal-match-sizing-memo
**Areas discussed:** Encounter join strategy, Deliverable form, Recommendation framework, R/122 cross-check

---

## Encounter join strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Patient-level only | Use R/121 `$patients` triage counts as-is — no encounter join | |
| Context row only | All encounters for NEEDS_TEMPORAL_MATCH patients | |
| Two-row approach | Context row (all encounters) + decision row (encounters a temporal match would actually change, within Phase 165 analytic universe) | ✓ |

**User's choice:** Two-row approach.

**Notes:** The decision row must use the Phase 165 per-encounter distance set as the analytic universe (that's where a fix would move a result). Show whole-record and post-anchor counts to mirror the two Phase 165 flags. An encounter-level join requires a script — R/121 alone cannot answer this.

---

## Deliverable form

| Option | Description | Selected |
|--------|-------------|----------|
| Ad-hoc one-off | Inline query, markdown memo only — not re-runnable | |
| Script + memo | `R/177_temporal_match_sizing.R` (re-runnable, read-only) + markdown memo | ✓ |
| Full pipeline script | New R/88 section, full production integration | |

**User's choice:** Script + memo.

**Notes:** Script writes a counts-only workbook to `output/` (suppress_small applied, KEY sheet leftmost); patient-level to `output/internal/`. Register in R/39 and SCRIPT_INDEX as one-off investigation. Do NOT add R/88 section. Memo in phase dir cites numbers from the script.

---

## Recommendation framework

| Option | Description | Selected |
|--------|-------------|----------|
| Post-hoc judgment | Look at counts and decide | |
| Pre-set thresholds | Lock thresholds before seeing counts, apply mechanically | ✓ |
| External benchmark | Compare to published imputation literature thresholds | |

**User's choice:** Pre-set thresholds, locked in CONTEXT.md before the numbers arrive.

**Notes:**
- Primary: share of Phase 165 analytic-universe encounters filled; also count those landing >100 mi (drives CBC test).
- Secondary: share of patients affected + rough implementation cost estimate (utils_address.R temporal lookup from Phase 139 likely reusable).
- Thresholds: <1% → document only; 1–5% → inline fix; >5% or could change >100 mi result → new phase.
- Recommendation table must appear in memo *before* the count rows so the logic is transparent.

---

## R/122 cross-check

| Option | Description | Selected |
|--------|-------------|----------|
| Skip | R/121 only — no cross-reference | |
| Reconciliation required | Compare R/121 NEEDS_TEMPORAL_MATCH patient count to R/122 patient_zip_missing waterfall; explain any gap | ✓ |

**User's choice:** Reconciliation required.

**Notes:** Expected R/121 NEEDS_TEMPORAL_MATCH count is ~410. Must agree with or explain the difference vs. R/122's `patient_zip_missing` waterfall step (definitional difference: patient-level triage vs. encounter-level status). If unexplained disagreement, memo must flag it before making any recommendation.

---

## Claude's Discretion

- Exact join keys and column names (read from actual RDS before coding)
- Script sourcing pattern (follow adjacent scripts)
- Workbook sheet layout (follow Phase 121/122 conventions)

## Deferred Ideas

None.
