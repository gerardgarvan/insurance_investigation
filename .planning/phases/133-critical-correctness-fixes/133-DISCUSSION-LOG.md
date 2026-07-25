# Phase 133: Critical Correctness Fixes - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-25
**Phase:** 133-critical-correctness-fixes
**Areas discussed:** Plan decomposition, R/67/68 + R/95/96 swap approach, R/47 sentinel constant, R/46 aggregation restructure

---

## Plan Decomposition

| Option | Description | Selected |
|--------|-------------|----------|
| 1 omnibus plan | All 8 fixes in a single plan — simpler to coordinate, one commit | ✓ |
| 3 plans by risk cluster | R/28+R/89+R/101 / R/47→48→49 / R/67/68+R/95/96 | |
| 6 plans, one per script group | Maximum isolation, most overhead | |

**User's choice:** 1 omnibus plan
**Notes:** Fixes are independent so rollback risk is low; the phase is atomic by design.

---

## R/67/68 + R/95/96 Swap Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Swap dates alongside sources (minimal surgery) | Add admit_date swap in the same mutate as source swap | ✓ |
| Restructure to (date, source) tuple pairs | Refactor to nested/grouped representation | |

**User's choice:** Minimal surgery — swap dates alongside sources
**Notes:** Keeps existing structure intact.

---

### R/95/96 Pattern

| Option | Description | Selected |
|--------|-------------|----------|
| Identical fix — same pattern | R/95 = AV+TH analogue of R/67; same change | ✓ |
| Verify individually before fixing | Check structural differences first | |

**User's choice:** Identical fix — same pattern

---

## R/47 Sentinel Constant

| Option | Description | Selected |
|--------|-------------|----------|
| Define inline in R/47 (matching R/48/R/49) | SENTINEL_CUTOFF at top of R/47, same as existing pattern | ✓ |
| Centralize to R/00_config.R | Move constant to config, update all three scripts | |

**User's choice:** Define inline in R/47
**Notes:** Consistent with existing R/48/R/49 pattern; avoids broader config change.

---

## R/46 Aggregation Restructure

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal — fix the aggregation path only | Aggregate before join; leave summary rows as-is | ✓ |
| Verify TOTAL row logic too | Also verify TOTAL row derives from corrected totals | |

**User's choice:** Minimal — fix the aggregation path only
**Notes:** Narrowest change that fixes the stated bug.

---

## Claude's Discretion

- Ordering of fixes within the omnibus plan (dependency-first suggested)
- Exact dplyr idiom for R/49 patient-intersection fix

## Deferred Ideas

None.
