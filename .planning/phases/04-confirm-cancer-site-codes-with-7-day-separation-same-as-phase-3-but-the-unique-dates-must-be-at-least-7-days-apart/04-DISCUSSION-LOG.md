# Phase 4: Confirm Cancer Site Codes with 7-Day Separation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-05-19
**Phase:** 04-confirm-cancer-site-codes-with-7-day-separation
**Areas discussed:** Script structure, Comparison columns, Gap calculation

---

## Script Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Separate R/51 script | Clone R/50 with the 7-day filter added. Two independent scripts, each producing its own xlsx. Simple, no risk of breaking Phase 3. | Yes |
| Parameterize R/50 | Add a GAP_DAYS parameter (default 0 for Phase 3, 7 for Phase 4). One script produces both reports when called with different args. DRYer but couples the phases. | |
| You decide | Claude picks the approach based on codebase patterns | |

**User's choice:** Separate R/51 script
**Notes:** Clean separation preferred -- no coupling between Phase 3 and Phase 4 scripts.

---

## Comparison Columns

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone report | Same columns as Phase 3 (total, confirmed, unconfirmed, rate) but confirmed = 7-day-separated. User compares by opening both xlsx files side by side. | Yes |
| Include Phase 3 columns | Add columns like confirmed_any_2date and confirmed_7day_gap so each row shows both strictness levels. One file tells the whole story. | |
| You decide | Claude picks based on what's most useful | |

**User's choice:** Standalone report
**Notes:** Same column structure as Phase 3. Side-by-side comparison via separate files.

---

## Gap Calculation

| Option | Description | Selected |
|--------|-------------|----------|
| Any pair >= 7 days (Recommended) | Confirmed if max(date) - min(date) >= 7 days. Standard epidemiological approach -- if the earliest and latest dates are 7+ days apart, it's confirmed. | Yes |
| All consecutive >= 7 days | Every pair of consecutive dates must be 7+ days apart. Stricter -- filters out clusters of dates that are close together even if the span is wide. | |
| You decide | Claude picks the epidemiologically standard approach | |

**User's choice:** Any pair >= 7 days (Recommended)
**Notes:** Standard epidemiological approach. max(date) - min(date) >= 7.

---

## Claude's Discretion

- Exact output filename convention
- Whether to add a subtitle noting the 7-day requirement in xlsx title rows
- Column ordering and styling details beyond R/50 patterns

## Deferred Ideas

None -- discussion stayed within phase scope.
