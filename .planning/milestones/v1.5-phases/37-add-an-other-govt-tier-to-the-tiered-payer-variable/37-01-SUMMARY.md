---
phase: 37-add-an-other-govt-tier-to-the-tiered-payer-variable
plan: 01
subsystem: payer-categorization
tags:
  - payer-resolution
  - hierarchical-categorization
  - amc-framework
dependency_graph:
  requires: []
  provides:
    - 8-tier payer resolution hierarchy
    - distinct Other govt category in same-day resolution
  affects:
    - R/36_tiered_same_day_payer.R
tech_stack:
  added: []
  patterns:
    - 8-tier hierarchical resolution with distinct Other govt tier
key_files:
  created: []
  modified:
    - R/36_tiered_same_day_payer.R
decisions:
  - key: Other govt tier position
    decision: Position 4 (between Private and Other)
    rationale: Maintains AMC 8-category framework alignment with government programs resolving above generic other but below private insurance
    alternatives:
      - "Position 5 (after Other): Would reverse the intended priority hierarchy"
      - "Collapse into Other: Was the prior behavior, loses government payer distinction"
  - key: Safety net rank value
    decision: Updated to 8L (from 7L)
    rationale: Missing tier now has rank 8 as the new maximum, ensuring NA tier_rank values map to lowest priority
metrics:
  duration: 81 seconds
  tasks_completed: 1
  tasks_total: 1
  commits: 1
  files_modified: 1
  completed_date: "2026-05-01"
---

# Phase 37 Plan 01: Add Other Govt Tier to Tiered Payer Variable Summary

Expanded the same-day payer resolution hierarchy from 7 to 8 tiers by promoting "Other govt" from a collapsed category into its own distinct tier at position 4, aligning resolution logic with the AMC 8-category payer system.

## What Was Done

### Task 1: Expand tier hierarchy from 7 to 8 tiers with Other Govt at position 4

**Objective:** Promote "Other govt" from collapsed "Other" category to distinct tier 4

**Changes Made:**

1. **TIER_MAPPING expanded from 7 to 8 entries** (lines 75-83)
   - Added `"Other govt" = 4L` as distinct tier
   - Shifted ranks: Other → 5L, Self-pay → 6L, Uninsured → 7L, Missing → 8L
   - Added inline comments: "VA, TRICARE, state agencies, corrections" for Other govt

2. **CODE_TO_TIER function updated** (line 93)
   - Changed `payer_category == "Other govt" ~ "Other"` to `~ "Other govt"`
   - Now preserves "Other govt" as distinct category instead of collapsing

3. **Safety net updated** (line 169)
   - Changed `if_else(is.na(tier_rank), 7L, tier_rank)` to `8L`
   - NA tier_rank values now default to 8 (new maximum for Missing tier)

4. **Documentation updates**
   - Header comment (line 13): Added "Other govt" to hierarchy chain
   - Comment above CODE_TO_TIER (line 86): "8 resolution tiers" with "1:1 alignment"

**Verification:**
- All 5 changes confirmed via grep pattern matching
- Script structure unchanged (no new functions, same output files)
- R parsing not verified (Rscript unavailable on Windows), will be tested on HiPerGator

**Commit:** `8af61f3`

**Files Modified:**
- `R/36_tiered_same_day_payer.R` (1 file, 13 insertions, 12 deletions)

## Deviations from Plan

None - plan executed exactly as written.

## Impact

**Before:** 7-tier system collapsed "Other govt" into generic "Other" at rank 4
**After:** 8-tier system with distinct "Other govt" at rank 4, generic "Other" at rank 5

**Resolution Priority Order (highest to lowest):**
1. Medicaid (includes dual-eligible, FLM source, codes 93/14)
2. Medicare
3. Private
4. **Other govt** (VA, TRICARE, state agencies, corrections) ← NEW DISTINCT TIER
5. Other (worker's comp, auto insurance)
6. Self-pay
7. Uninsured
8. Missing

**Expected Behavioral Change:**

For same-day encounters with mixed payer categories:
- **Before:** Patient with Private + Other govt on same date → resolves to "Other" (rank 4)
- **After:** Patient with Private + Other govt on same date → resolves to "Other govt" (rank 4)
- **Before:** Patient with Other govt + Other on same date → resolves to "Other" (rank 4, tie)
- **After:** Patient with Other govt + Other on same date → resolves to "Other govt" (rank 4 beats rank 5)

**CSV Output Changes:**

All 12 CSV files (`payer_resolved_detail_*.csv`, `payer_resolved_patient_summary_*.csv`, `payer_resolved_impact_*.csv`) will now contain "Other govt" as a distinct `resolved_payer` value instead of collapsed into "Other".

**Data Quality Improvement:**

VA, TRICARE, and other government program patients are now explicitly identified in resolution outputs, enabling government vs commercial payer analysis without requiring raw code lookups.

## Known Stubs

None. This plan modifies only the resolution hierarchy; data wiring and CSV generation logic are unchanged.

## Next Steps

1. **UAT Validation:** Run `source("R/36_tiered_same_day_payer.R")` on HiPerGator with full data access
2. **Output Verification:** Confirm 12 CSV files contain "Other govt" as distinct category in resolved_payer column
3. **Before/After Comparison:** Run payer_resolved_impact_*.csv queries to quantify how many patient-dates shifted from collapsed "Other" to distinct "Other govt"
4. **Presentation Update:** Update any existing PowerPoint slides showing 7-tier hierarchy to reflect 8-tier system

## Self-Check: PASSED

**Files created:** None (all expected)

**Files modified:**
```
R/36_tiered_same_day_payer.R exists: FOUND
```

**Commits:**
```
8af61f3 exists: FOUND
```

All claimed artifacts verified.
