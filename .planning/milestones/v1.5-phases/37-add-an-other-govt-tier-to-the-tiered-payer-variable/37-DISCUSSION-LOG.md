# Phase 37: Add an Other Govt Tier to the Tiered Payer Variable - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-01
**Phase:** 37-add-an-other-govt-tier-to-the-tiered-payer-variable
**Areas discussed:** Tier priority position, Output impact, Scope of change

---

## Tier Priority Position

| Option | Description | Selected |
|--------|-------------|----------|
| Medicaid > Medicare > Other Govt > Private > Other > Self-pay > Uninsured > Missing | Government programs (VA, state/federal) rank above private insurance, alongside Medicare/Medicaid as public payers | |
| Medicaid > Medicare > Private > Other Govt > Other > Self-pay > Uninsured > Missing | Government programs rank below private insurance but above generic 'Other' — the most conservative insertion point | ✓ |

**User's choice:** Medicaid > Medicare > Private > Other Govt > Other > Self-pay > Uninsured > Missing
**Notes:** Conservative insertion — Other Govt below Private but above generic Other.

---

## Output Impact

| Option | Description | Selected |
|--------|-------------|----------|
| Transparent update (Recommended) | Same 12 filenames, same column structure. 'Other govt' simply appears as its own resolved_payer value and its own row in category summaries. No new files. | ✓ |
| Add comparison output | Add a 13th CSV showing what changed — encounters that were 'Other' under 7-tier but now resolve to 'Other govt' under 8-tier. Useful for validating the impact. | |

**User's choice:** Transparent update
**Notes:** No structural changes to outputs.

---

## Scope of Change

| Option | Description | Selected |
|--------|-------------|----------|
| Full update in R/36 (Recommended) | Update CODE_TO_TIER, TIER_PRIORITY ordering, console summaries, and any hardcoded tier lists within R/36. Keep it self-contained to one script. | ✓ |
| R/36 + config.R | Also add a TIER_PRIORITY constant to R/00_config.R alongside the existing PAYER_MAPPING, centralizing the hierarchy definition for future scripts. | |
| Minimal CODE_TO_TIER only | Just change the one case_when line in CODE_TO_TIER. Smallest possible diff. | |

**User's choice:** Full update in R/36
**Notes:** Self-contained to R/36. No changes to config.R or other scripts.

---

## Claude's Discretion

- Console summary formatting for the additional tier row
- TIER_PRIORITY vector format (named vs character)
- Minor formatting adjustments for wider tier set

## Deferred Ideas

None — discussion stayed within phase scope.
