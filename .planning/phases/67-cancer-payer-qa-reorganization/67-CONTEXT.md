# Phase 67: Post-Renumbering Inventory Cleanup - Context

**Gathered:** 2026-06-01
**Updated:** 2026-06-01 (gap-fix pass)
**Status:** Ready for planning (gap-fix plan)

<domain>
## Phase Boundary

Fix post-renumbering issues left by Phase 66: resolve the 66-prefix script collision, move the full-pipeline smoke test to the test decade, archive all unnumbered scripts to R/archive/ with a README, and regenerate SCRIPT_INDEX.md from the filesystem to guarantee accuracy.

**Repurposed from:** Original Phase 67 scope (cancer/payer renumbering) was fully absorbed by Phase 66's expanded scope. This phase addresses cleanup items that fell through during the comprehensive renumbering.

**Gap-fix scope:** Plan 67-01 completed but verification found 3 gaps (5/7 truths verified). This context update captures decisions for a gap-fix plan (67-02) to address the remaining documentation/reference mismatches.

</domain>

<decisions>
## Implementation Decisions

### Phase Repurposing (Plan 01 - Complete)
- **D-01:** Phase 67 is repurposed to "Post-Renumbering Inventory Cleanup" — a combined pass that fixes the 66 collision, syncs the index, archives unnumbered scripts, and creates R/archive/. All post-renumbering cleanup in one phase.

### Smoke Test Placement (Plan 01 - Complete)
- **D-02:** Move `66_smoke_test_full_pipeline.R` to `87_smoke_test_full_pipeline.R` in the test decade (80-89). It IS a test script and belongs alongside `86_smoke_test_foundation.R`. This frees position 66 for `66_all_site_duplicate_dates.R` with no collision. The payer/QA decade stays at 10 scripts (60-69).
- **D-03:** After moving the smoke test, no renumbering is needed in the payer/QA decade — `66_all_site_duplicate_dates.R` through `69_per_patient_source_detection.R` keep their current numbers.

### Unnumbered Script Archival (Plan 01 - Complete)
- **D-04:** All 8 unnumbered scripts in R/ move to `R/archive/` with a README explaining each script's purpose and why it was archived. This satisfies REORG-04 (deprecated/superseded scripts archived).
- **D-05:** Scripts to archive:
  - `check_deleted_proton_code.R` — one-off CPT 77521 check
  - `date_range_check.R` — quick date range diagnostic
  - `payer_frequency_from_resolved.R` — payer frequency from CSV output
  - `run_phase12_outputs.R` — HiPerGator orchestration helper
  - `sct_code_inventory.R` — SCT evidence inventory
  - `search_C8190.R` — one-off ICD code search
  - `tiered_payer_summary.R` — styled xlsx from payer CSV
  - `treatment_cross_reference.R` — gap report: reference docs vs config

### SCRIPT_INDEX Regeneration (Plan 01 - FAILED, redo in Plan 02)
- **D-06:** SCRIPT_INDEX.md is regenerated from the filesystem AFTER all moves/renames are complete. Use the same regeneration approach from Phase 66 (read R/*.R, extract header comments, rebuild the entire index). Guaranteed accurate — no manual patching.
- **D-07 (gap-fix):** Plan 01's regeneration produced wrong script numbers in the payer/QA section (listed 67, 68 instead of 66, 67; missed 68_overlap_classification.R entirely). **Full regeneration from filesystem required** — scan R/*.R, extract headers, rebuild the entire SCRIPT_INDEX.md. Do NOT patch individual lines.

### Smoke Test Array Fix (Plan 02 - NEW)
- **D-08 (gap-fix):** `R/87_smoke_test_full_pipeline.R` payer_expected array (lines 108-112) lists 9 scripts with 2 wrong names. Fix to list all 10 correct payer scripts (60-69) with correct filenames. Update the count assertion on line 117 from 9 to 10. **Only fix the payer array and count** — do not rebuild other decade arrays.

### ROADMAP Success Criteria Fix (Plan 02 - NEW)
- **D-09 (gap-fix):** ROADMAP.md Phase 67 success criteria #2 says "Payer/QA decade has 9 scripts (60-65, 67-69)" — update to "10 scripts (60-69)" to match the actual filesystem state. The payer decade has always had 10 scripts; the original count was wrong.

### Claude's Discretion
- Archive README format and level of detail per script
- Whether to update source() references inside archived scripts (they won't be run from R/ anymore)
- Smoke test internal reference updates (if 87_smoke_test_full_pipeline.R references its own filename internally)
- Order of operations: move smoke test first, then archive, then regenerate index (or different sequence)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Verification Report (gap source)
- `.planning/phases/67-cancer-payer-qa-reorganization/67-01-VERIFICATION.md` — Identifies 3 gaps: SCRIPT_INDEX wrong numbers, smoke test stale array, ROADMAP wrong count

### Filesystem Truth (authoritative)
- `R/66_all_site_duplicate_dates.R` — EXISTS at position 66 (not 67)
- `R/67_multi_source_overlap_detection.R` — EXISTS at position 67 (not 68)
- `R/68_overlap_classification.R` — EXISTS at position 68 (missing from SCRIPT_INDEX entirely)
- `R/69_per_patient_source_detection.R` — EXISTS at position 69 (correct in current docs)

### Files to Fix
- `R/SCRIPT_INDEX.md` — Lines 81-83: wrong payer script numbers, missing 68_overlap_classification.R. Full regen needed.
- `R/87_smoke_test_full_pipeline.R` — Lines 108-112: payer_expected has wrong names; line 117: count says 9, should be 10
- `.planning/ROADMAP.md` — Phase 67 success criteria #2: says 9 scripts, should say 10

### Phase 66 Outcomes (predecessor)
- `.planning/phases/66-cohort-treatment-reorganization/66-CONTEXT.md` — Decade allocation decisions (D-01 through D-08)

### Requirements
- `.planning/REQUIREMENTS.md` — REORG-01, REORG-02 (cross-references and script inventory accuracy)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 66's SCRIPT_INDEX regeneration approach — same pattern to be reused (but must scan filesystem correctly this time)
- `R/86_smoke_test_foundation.R` — naming convention and structure pattern for test decade

### Established Patterns
- Payer/QA decade: 10 scripts at positions 60-69 (NOT 9 as plan 01 assumed)
- Test decade: 8 scripts at positions 80-87
- SCRIPT_INDEX regeneration: scan R/*.R, extract header comments per script, rebuild full table

### Integration Points
- Smoke test payer_expected array must match filesystem exactly for test to pass
- SCRIPT_INDEX.md is documentation only — regeneration has zero cross-reference impact
- ROADMAP.md success criteria is planning documentation — update is bookkeeping only

</code_context>

<specifics>
## Specific Ideas

No specific requirements — straightforward mechanical fixes matching documentation to filesystem reality.

</specifics>

<deferred>
## Deferred Ideas

- Phase 68 was also marked "to be repurposed" — could become script documentation prep or additional cleanup if needed after Phase 67
- Cancer decade (40-53) SCRIPT_INDEX entries may have description inaccuracies beyond the position mismatches — full regeneration from filesystem will catch these
- Consider rebuilding ALL smoke test decade arrays (not just payer) in a future phase to catch any other drift

</deferred>

---

*Phase: 67-cancer-payer-qa-reorganization*
*Context gathered: 2026-06-01*
*Context updated: 2026-06-01 (gap-fix)*
