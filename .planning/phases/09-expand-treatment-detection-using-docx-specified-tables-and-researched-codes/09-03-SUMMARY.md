---
phase: 09-expand-treatment-detection-using-docx-specified-tables-and-researched-codes
plan: 03
subsystem: treatment-payer
tags:
  - treatment-detection
  - payer-anchoring
  - multi-source-dates
  - pcornet-expansion
dependency_graph:
  requires:
    - 09-01-SUMMARY (TREATMENT_CODES expanded with DRG/revenue/diagnosis codes)
  provides:
    - Multi-source first treatment date extraction for payer anchoring
    - Chemo payer anchoring from 7 date sources (PROCEDURES, PRESCRIBING, DIAGNOSIS, ENCOUNTER, DISPENSING, MED_ADMIN, revenue)
    - Radiation payer anchoring from 4 date sources (PROCEDURES, DIAGNOSIS, ENCOUNTER, revenue)
    - SCT payer anchoring from 4 date sources (PROCEDURES, DIAGNOSIS, ENCOUNTER, revenue)
  affects:
    - 04_build_cohort.R (Section 6.5 treatment-anchored payer uses expanded date sources)
tech_stack:
  added: []
  patterns:
    - Stacked bind_rows + group_by + min(src_date) for multi-source date combination
    - nrow_or_0() helper for NULL-safe logging
    - purrr::compact() to filter NULL date sources
key_files:
  created: []
  modified:
    - R/10_treatment_payer.R
decisions:
  - Use stacked bind_rows pattern instead of nested full_join chains for cleaner multi-source date combination
  - Add per-source patient count logging for transparency without per-patient overhead
  - DISPENSING/MED_ADMIN only used for chemo (radiation/SCT are procedures, no drug RXNORM matching)
metrics:
  duration_minutes: 3
  completed_date: "2026-03-26"
  tasks_completed: 2
  files_modified: 1
  lines_added: 260
  lines_removed: 60
---

# Phase 09 Plan 03: Expand Treatment-Anchored Payer Date Extraction Summary

**Multi-source treatment date extraction for improved payer match coverage**

## One-liner

Expanded compute_payer_at_chemo/radiation/sct() to extract first treatment dates from DIAGNOSIS, ENCOUNTER DRG, DISPENSING, MED_ADMIN, and PROCEDURES revenue sources, using stacked minimum-date pattern to combine 4-7 sources per treatment type.

## What Was Done

### Task 1: Expand compute_payer_at_chemo() with 5 new date sources

**Objective:** Add DIAGNOSIS (Z51.11/Z51.12/V58.11/V58.12), ENCOUNTER DRG (837-839, 846-848), DISPENSING (RXNORM_CUI), MED_ADMIN (RXNORM_CUI), and PROCEDURES revenue (0331/0332/0335) date extraction to chemo payer anchoring.

**Implementation:**
- Added `nrow_or_0()` helper function for NULL-safe logging of tibble row counts
- Added `library(purrr)` for `compact()` function
- Expanded compute_payer_at_chemo() from 2 date sources (PROCEDURES, PRESCRIBING) to 7 sources
- Replaced nested if/else if/else date combination logic with generic stacked combiner:
  1. Collect all date sources in named list
  2. Filter NULLs with `compact()`
  3. Stack via `bind_rows()` after renaming date columns to `src_date`
  4. `group_by(ID) + min(src_date)` to get per-patient minimum
- Added per-source logging: `"Chemo date sources: PX=450, RX=23, DX=8, DRG=5, DISP=0, MA=0, REV=12"`
- Updated function docstring to list all 7 date sources

**Date columns used:**
- DIAGNOSIS: DX_DATE
- ENCOUNTER: ADMIT_DATE
- DISPENSING: DISPENSE_DATE
- MED_ADMIN: MEDADMIN_START_DATE
- PROCEDURES revenue: PX_DATE (same column as existing PROCEDURES queries)

**Verification:** `grep -c "chemo_dx_icd10|chemo_drg|chemo_revenue|DISPENSE_DATE|MEDADMIN_START_DATE|nrow_or_0"` returned 11 matches (threshold: >= 6).

**Commit:** c72fcff

---

### Task 2: Expand compute_payer_at_radiation() and compute_payer_at_sct() with new date sources

**Objective:** Apply same multi-source date extraction pattern to radiation (4 sources) and SCT (4 sources), excluding DISPENSING/MED_ADMIN (no drug RXNORM matching for procedures).

**Implementation:**

**compute_payer_at_radiation()** -- 4 date sources:
- PROCEDURES CPT/ICD (existing)
- DIAGNOSIS Z51.0 (ICD-10), V58.0 (ICD-9)
- ENCOUNTER DRG 849
- PROCEDURES revenue codes 0330/0333

**compute_payer_at_sct()** -- 4 date sources:
- PROCEDURES CPT/ICD (existing)
- DIAGNOSIS Z94.84/T86.5/T86.09/Z48.290/T86.0 (ICD-10 only, no ICD-9 equivalent)
- ENCOUNTER DRGs 014, 016, 017
- PROCEDURES revenue codes 0362/0815

Both functions use the same stacked combiner pattern as chemo:
1. Extract dates from each source (NULL if table missing)
2. Collect in named list, filter NULLs with `compact()`
3. Stack via `bind_rows()` with generic `src_date` column
4. `group_by(ID) + min(src_date)` for per-patient minimum
5. Log per-source counts: `"Radiation date sources: PX=120, DX=15, DRG=8, REV=3"`

**Rationale for excluding DISPENSING/MED_ADMIN from radiation/SCT:**
- Radiation and SCT are procedural treatments (energy/transplant), not pharmaceutical
- No drug RXNORM matching applies (TREATMENT_CODES$radiation_rxnorm does not exist)
- Consistent with Plan 02's decision to exclude PRESCRIBING from radiation/SCT

**Updated function docstrings** to list all date sources.

**Updated file header comment** to mention expanded date extraction from DIAGNOSIS, ENCOUNTER, DISPENSING, MED_ADMIN, and PROCEDURES revenue sources.

**Verification:** `grep -c "radiation_dx_icd10|radiation_drg|radiation_revenue|sct_dx_icd10|sct_drg|sct_revenue|date sources"` returned 8 matches (threshold: >= 8).

**Commit:** c72fcff (same commit as Task 1, single atomic change)

---

## Deviations from Plan

None. Plan executed exactly as written.

## Verification Results

All automated verifications passed:

1. ✅ `grep "TREATMENT_CODES$chemo_drg"` → 1 match (chemo DRG filter)
2. ✅ `grep "TREATMENT_CODES$radiation_drg"` → 1 match (radiation DRG filter)
3. ✅ `grep "TREATMENT_CODES$sct_drg"` → 1 match (SCT DRG filter)
4. ✅ `grep "nrow_or_0"` → 4 matches (helper function + 3 usages in logging)
5. ✅ `grep "date sources:"` → 3 matches (one per treatment type logging)
6. ✅ `grep "pcornet$DISPENSING"` → 2 matches (only in chemo function)
7. ✅ Task 1 grep count: 11 matches (>= 6 required)
8. ✅ Task 2 grep count: 8 matches (>= 8 required)

## Known Stubs

None. All date extraction logic is fully implemented. No placeholder values or hardcoded empty data.

## Key Technical Decisions

### Decision 1: Stacked bind_rows pattern instead of nested full_join
**Context:** Original chemo function used nested `if/else if/else` with `full_join()` for 2 date sources. Expanding to 7 sources would create deeply nested logic.

**Options:**
1. Nested if/else if/else chains with conditional full_join (existing pattern)
2. Stacked bind_rows with generic src_date column + group_by min

**Choice:** Option 2 (stacked pattern)

**Rationale:**
- Scales cleanly from 2 to 7+ sources without nesting
- Avoids rowwise() + c() min calculation (more efficient with dplyr grouped operations)
- Handles NULL sources gracefully via `compact()` upfront
- Easier to add/remove sources in future (just modify list, no control flow changes)

**Impact:** Cleaner code, easier maintenance, no performance degradation (group_by min is optimized).

---

### Decision 2: Per-source logging without per-patient tracking
**Context:** D-14 specifies aggregate source contribution logging. Could add per-patient source tracking columns (e.g., CHEMO_DATE_SOURCE = "DRG") but not required.

**Options:**
1. Aggregate counts only (D-14 requirement)
2. Aggregate counts + per-patient source column

**Choice:** Option 1 (aggregate only)

**Rationale:**
- Meets D-14 requirement ("no per-patient source tracking columns")
- Reduces output column proliferation (already have 3 FIRST_*_DATE + 3 PAYER_AT_* columns)
- Per-patient source less actionable for analysis (which source matters less than whether date exists)
- Can add per-patient source tracking later if user requests

**Impact:** Logging provides visibility into source contribution without cluttering patient-level data.

---

### Decision 3: DISPENSING/MED_ADMIN excluded from radiation/SCT
**Context:** Radiation and SCT are non-pharmaceutical treatments. DISPENSING/MED_ADMIN track drug administration.

**Options:**
1. Include DISPENSING/MED_ADMIN for all treatment types (symmetry)
2. Exclude from radiation/SCT (clinical appropriateness)

**Choice:** Option 2 (exclude)

**Rationale:**
- Radiation therapy is energy-based (photons, electrons), not drug-based
- SCT is a transplant procedure, not a pharmaceutical administration
- No TREATMENT_CODES$radiation_rxnorm or $sct_rxnorm lists exist (nothing to match on)
- Consistent with Plan 02's decision to exclude PRESCRIBING from radiation/SCT
- Zero clinical rationale for matching RXNORM_CUI in DISPENSING/MED_ADMIN for these treatment types

**Impact:** Chemo has 7 sources (most comprehensive), radiation/SCT have 4 sources each (appropriate for procedure-based treatments).

---

## Next Steps

**Immediate (Plan 09-03 complete):**
1. ✅ Tasks 1-2 completed: compute_payer_at_*() functions expanded
2. ✅ Committed: c72fcff
3. STATE.md updated (via gsd-tools state commands)
4. ROADMAP.md updated (via gsd-tools roadmap update-plan-progress)

**For Next Plan (if Phase 9 continues):**
- Plan 01 added 8 code list vectors to TREATMENT_CODES (chemo_dx_icd10/icd9, radiation_dx_icd10/icd9, sct_dx_icd10, chemo_drg, radiation_drg, sct_drg, chemo_revenue, radiation_revenue, sct_revenue)
- Plan 02 loaded DISPENSING and MED_ADMIN tables with full col_types
- Plan 03 (this plan) consumed new code lists and new tables in 10_treatment_payer.R
- Next step: Expand has_chemo/radiation/sct() in 03_cohort_predicates.R with same 4-7 sources (currently only checks TUMOR_REGISTRY + PROCEDURES + PRESCRIBING)

**For User (HiPerGator verification):**
- Run 04_build_cohort.R Section 6.5 to verify expanded payer anchoring works
- Check logs for per-source counts: expect non-zero for DRG/DIAGNOSIS sources (high prevalence), near-zero for DISPENSING/MED_ADMIN (optional tables)
- Compare PAYER_AT_CHEMO/RADIATION/SCT match rates before/after Phase 9 expansion (expect higher match % with more date sources)

---

## Self-Check: PASSED

### Files Verified
- ✅ R/10_treatment_payer.R exists (modified)

### Commits Verified
- ✅ c72fcff exists in git log

All claimed artifacts present. No discrepancies.

---

**Duration:** 3 minutes
**Completed:** 2026-03-26
**Executor:** Claude Sonnet 4.5 (parallel execution mode)
