# Phase 147: Read ADDRESS_ZIP5 — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-17
**Phase:** 147-read-address-zip5-retract-downstream-artefacts
**Areas discussed:** D-02 precedence strategy, Plan wave structure, Retraction depth

---

## D-02 Precedence Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Discovery-gated | Plan prints 12 disagreement rows, records in 148-DISCOVERY.md, confirms coalesce order after inspection | ✓ |
| Pre-locked: ADDRESS_ZIP5 wins | Treat ADDRESS_ZIP5 as winner regardless of inspection | |
| Pre-locked: ZIP9-prefix wins | Use ZIP9 prefix for the 12 disagreements | |

**User's choice:** Discovery-gated
**Notes:** Print and document the 12 rows before locking. Provisional coalesce order ADDRESS_ZIP5 first, but confirmed by inspection in 148-DISCOVERY.md.

---

## Plan Wave Structure

| Option | Description | Selected |
|--------|-------------|----------|
| 4 plans | discovery / fix / re-run (HiPerGator checkpoint) / retract | ✓ |
| 3 plans | discovery+fix / re-run / retract | |
| 2 plans | fix+re-run / retract | |

**User's choice:** 4 plans
**Notes:** HiPerGator checkpoint is the natural wave break between plan 3 and plan 4. Cleanest separation of concerns.

---

## Retraction Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Dated header note only | Bold dated note at top of affected section, original text preserved | ✓ |
| Strikethrough | ~~wrong conclusion~~ + corrected figure inline | |
| Full section rewrite | Rewrite section, move old text to "Historical note" block | |

**User's choice:** Dated header note only
**Notes:** Format: `**[2026-08-17] Superseded by Phase 147 — see 148-DISCOVERY.md.** [one-line summary]`. Preserve all original text.

---

## Claude's Discretion

- Exact wording of retraction notes (beyond template)
- Whether to add inline comment in get_zip9_at_date() documenting D-02 coalesce precedence
- Exact fixture patient IDs, dates, and address values for the four 2×2 cells

## Deferred Ideas

- Centroid crosswalk implementation — on hold pending zip5_no_zip9 count from Plan 3 re-run
