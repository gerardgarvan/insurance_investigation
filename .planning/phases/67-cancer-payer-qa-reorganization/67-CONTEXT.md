# Phase 67: Post-Renumbering Inventory Cleanup - Context

**Gathered:** 2026-06-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix post-renumbering issues left by Phase 66: resolve the 66-prefix script collision, move the full-pipeline smoke test to the test decade, archive all unnumbered scripts to R/archive/ with a README, and regenerate SCRIPT_INDEX.md from the filesystem to guarantee accuracy.

**Repurposed from:** Original Phase 67 scope (cancer/payer renumbering) was fully absorbed by Phase 66's expanded scope. This phase addresses cleanup items that fell through during the comprehensive renumbering.

</domain>

<decisions>
## Implementation Decisions

### Phase Repurposing
- **D-01:** Phase 67 is repurposed to "Post-Renumbering Inventory Cleanup" — a combined pass that fixes the 66 collision, syncs the index, archives unnumbered scripts, and creates R/archive/. All post-renumbering cleanup in one phase.

### Smoke Test Placement (66-Prefix Collision)
- **D-02:** Move `66_smoke_test_full_pipeline.R` to `87_smoke_test_full_pipeline.R` in the test decade (80-89). It IS a test script and belongs alongside `86_smoke_test_foundation.R`. This frees position 66 for `66_all_site_duplicate_dates.R` with no collision. The payer/QA decade stays at 10 scripts (60-69).
- **D-03:** After moving the smoke test, no renumbering is needed in the payer/QA decade — `66_all_site_duplicate_dates.R` through `69_per_patient_source_detection.R` keep their current numbers.

### Unnumbered Script Archival
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

### SCRIPT_INDEX Regeneration
- **D-06:** SCRIPT_INDEX.md is regenerated from the filesystem AFTER all moves/renames are complete. Use the same regeneration approach from Phase 66 (read R/*.R, extract header comments, rebuild the entire index). Guaranteed accurate — no manual patching.

### Claude's Discretion
- Archive README format and level of detail per script
- Whether to update source() references inside archived scripts (they won't be run from R/ anymore)
- Smoke test internal reference updates (if 87_smoke_test_full_pipeline.R references its own filename internally)
- Order of operations: move smoke test first, then archive, then regenerate index (or different sequence)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 66 Outcomes (predecessor)
- `.planning/phases/66-cohort-treatment-reorganization/66-CONTEXT.md` — Decade allocation decisions (D-01 through D-08), identifies Phases 67/68 as needing repurposing
- `R/SCRIPT_INDEX.md` — Current (partially desynchronized) script inventory; will be regenerated

### Script Inventory (current state)
- `R/66_all_site_duplicate_dates.R` — collides with 66_smoke_test_full_pipeline.R
- `R/66_smoke_test_full_pipeline.R` — Phase 66 validation test; target: move to 87
- `R/86_smoke_test_foundation.R` — Phase 65 foundation test; reference for naming pattern in test decade

### Requirements
- `.planning/REQUIREMENTS.md` — REORG-04 (deprecated scripts archival), REORG-05 (smoke test validation)
- `.planning/ROADMAP.md` — Phase 67 success criteria (will need updating to reflect repurposed scope)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 66's SCRIPT_INDEX regeneration approach — same pattern can be reused for the final regeneration
- `R/86_smoke_test_foundation.R` — naming convention and structure pattern for `87_smoke_test_full_pipeline.R`

### Established Patterns
- Test scripts in 80-89 decade: 80 (backends), 81 (parity), 82 (benchmark), 83 (speedup report), 84 (durations), 85 (episodes), 86 (foundation smoke test). Next slot: 87.
- Unnumbered scripts have no source() callers — they are standalone one-off tools. Safe to move without updating cross-references.

### Integration Points
- `66_smoke_test_full_pipeline.R` may reference its own path or the `66` prefix internally — needs checking after rename to 87
- No scripts source() any of the 8 unnumbered scripts — archival has zero cross-reference impact
- SCRIPT_INDEX.md is documentation only (not sourced by any R script) — regeneration is safe

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

- Phase 68 was also marked "to be repurposed" — could become script documentation prep or additional cleanup if needed after Phase 67
- Cancer decade (40-53) SCRIPT_INDEX entries may have description inaccuracies beyond the position mismatches — full regeneration from filesystem will catch these

</deferred>

---

*Phase: 67-cancer-payer-qa-reorganization*
*Context gathered: 2026-06-01*
