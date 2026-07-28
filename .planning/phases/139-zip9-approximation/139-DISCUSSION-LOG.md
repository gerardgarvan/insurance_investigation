# Phase 139: ZIP9 Approximation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-28
**Phase:** 139-zip9-approximation
**Areas discussed:** Trigger condition, Approximation method, Output shape and location, Reference data source

---

## Trigger condition

| Option | Description | Selected |
|--------|-------------|----------|
| ZIP9 is NA | Approximate whenever get_zip9_at_date() returns ZIP9 = NA, regardless of match_type | ✓ |
| ZIP5 exists but ZIP9 is NA | Only approximate when ZIP5 is not NA but ZIP9 is NA | |
| All rows — extend unconditionally | Run approximation pass over all rows | |

**User's choice:** ZIP9 is NA (regardless of match_type)
**Notes:** Covers both ZIP5-only address records and any other case where ZIP9 normalizes to NA.

| Option | Description | Selected |
|--------|-------------|----------|
| Leave match_type='none' as NA unconditionally | No address data = nothing to approximate from | ✓ |
| Allow match_type='none' into approximation | Use secondary source if ZIP5 available | |

**User's choice:** Leave match_type='none' as NA unconditionally
**Notes:** No ZIP5 anchor = no approximation possible.

---

## Approximation method

| Option | Description | Selected |
|--------|-------------|----------|
| Modal ZIP9 from cohort | Most frequent ZIP9 for that ZIP5 across all LDS_ADDRESS_HISTORY | ✓ |
| Crosswalk from external reference | USPS, HUD, or Census ZIP5→ZIP9 crosswalk | |
| Flag as unapproximatable | Return ZIP9 = NA with match_type = 'zip5_only' for all | |

**User's choice:** Modal ZIP9 from cohort
**Notes:** Stays within HiPerGator data, no external dependency.

| Option | Description | Selected |
|--------|-------------|----------|
| Most recent ADDRESS_PERIOD_START | Tie-break by recency — consistent with get_zip9_at_date() | ✓ |
| Lexicographic (lowest ZIP9 first) | Deterministic but arbitrary | |
| Claude's discretion | Let planner choose | |

**User's choice:** Most recent ADDRESS_PERIOD_START
**Notes:** Consistent with Phase 137 D-04 tie-break.

---

## Output shape and location

| Option | Description | Selected |
|--------|-------------|----------|
| Extend utils_address.R with new function | Add approximate_zip9() to existing utils file | ✓ |
| New R/115 investigation script | Standalone script with diagnostic output | |
| Both: utility function + validation script | Function in utils + R/115 for validation | |

**User's choice:** Extend utils_address.R with new function (approximate_zip9)
**Notes:** No new script in this phase; diagnostics deferred.

| Option | Description | Selected |
|--------|-------------|----------|
| "zip5_modal" | Clear, self-documenting match_type for approximated rows | ✓ |
| "approximated" | Generic label | |
| "modal_zip9" | Describes source but not that it was a fallback | |

**User's choice:** "zip5_modal"

| Option | Description | Selected |
|--------|-------------|----------|
| Full LDS_ADDRESS_HISTORY | Larger sample, more stable modal estimate | ✓ |
| Input subset only | Only patients in input tibble | |

**User's choice:** Full LDS_ADDRESS_HISTORY
**Notes:** Consistent with how R/106 operated.

---

## Reference data source

| Option | Description | Selected |
|--------|-------------|----------|
| ZIP9 = NA, match_type = "zip5_only" | Signal ZIP5 exists but no ZIP9 approximable | ✓ |
| ZIP9 = NA, match_type unchanged | Downstream detects by ZIP9 = NA check | |
| ZIP5 padded to 9 digits | Convention-based signal | |

**User's choice:** ZIP9 = NA, match_type = "zip5_only"
**Notes:** Allows downstream SES phases to distinguish "no address" (none) from "ZIP5 only, no ZIP9 possible" (zip5_only).

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — same probe-first gate | Exit gracefully if LDS file absent | ✓ |
| No — hard stop if file absent | Strict contract | |

**User's choice:** Yes — same probe-first gate

---

## Claude's Discretion

- Exact internal variable names within `approximate_zip9()`
- Whether to cache the lookup table within the function or recompute each call
- Whether to log diagnostic counts to console as a side effect

## Deferred Ideas

- R/115 validation script — considered, not scoped in this phase
- External ZIP5→ZIP9 crosswalk — deferred in favor of cohort-internal modal
- ADI/SVI/SDI SES index computation — explicitly future phase
