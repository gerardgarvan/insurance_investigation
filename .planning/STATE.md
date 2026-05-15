---
gsd_state_version: 1.0
milestone: v1.6
milestone_name: Phases
status: completed
last_updated: "2026-05-15T16:47:31.924Z"
last_activity: 2026-05-15 — Phase 45 Plan 02 complete (audit executed on HiPerGator, 42 new codes added, xlsx generated)
progress:
  total_phases: 42
  completed_phases: 36
  total_plans: 70
  completed_plans: 67
---

# Project State: PCORnet Payer Variable Investigation (R Pipeline)

**Last updated:** 2026-05-15
**Project status:** Milestone v1.6 in progress — Phase 45 complete, Phase 46 next

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-01)

**Core value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

**Current focus:** Phase 46 — Treatment Code Cross-Reference & Triggering Codes

## Current Position

Phase: 45 (complete)
Plan: 02 of 02 complete
Status: Phase 45 complete — radiation CPT audit executed, config expanded to 63 codes, xlsx delivered
Last activity: 2026-05-15 — Phase 45 Plan 02 complete (audit executed on HiPerGator, 42 new codes added, xlsx generated)

## Accumulated Context

### Key Decisions

- AMC 8-category payer mapping centralized in R/00_config.R (Phase 36)
- 8-tier hierarchical same-day payer resolution with distinct Other govt tier (Phase 37)
- PayerVariable.xlsx runtime dependency eliminated (Phase 36)
- Parse/source validation with rollback ensures config remains valid R after programmatic modification (Phase 39)
- Supportive Care classification handled via new supportive_care_hcpcs vector (Phase 39)
- httr2 (modern) with req_retry() for RxNorm API robustness over httr (legacy) (Phase 40)
- Supportive Care classification prioritized first to prevent G-CSF/antiemetic misclassification as chemo (Phase 40)
- NDC lookup requires 2-step RxNorm API pattern (NDC->RxCUI->Name) (Phase 40)
- Dual code-type mapping (NDC + RXNORM) with category-specific vector routing enables same classification to route to different vectors (Phase 40)
- Unified SCT classification (SCT-related remapped to SCT) for consistent cross-source view (Phase 41)
- Cross-source RDS harmonization pattern: load separate artifacts, mutate to common schema, bind_rows (Phase 41)
- 90-day gap threshold for episode splitting in treatment duration analysis (Phase 43)
- All chemo codes pooled — no regimen distinction between ABVD/BV+AVD/salvage (Phase 43)
- Pre-2000 dates retained as real tumor registry historical data, not sentinels (Phase 43)
- Pull ALL drugs for HL patients from PRESCRIBING/DISPENSING/MED_ADMIN instead of curated RXNORM list (Phase 38)
- SCT ICD-10-PCS uses exact %in% matching (full 7-char codes), chemo/radiation/immuno use str_detect prefixes (Phase 38)
- write_resolved_xlsx() reusable function pattern for styled 2-sheet xlsx generation per treatment category (Phase 42)
- Treatment constants centralized once in R/00_config.R (TREATMENT_TYPES, TREATMENT_TYPE_COLORS, GAP_THRESHOLD, immunotherapy_drg) (Quick 260508-n87)
- Shared treatment helper functions centralized in R/utils_treatment.R (safe_table, get_hl_patient_ids, empty_result, nrow_or_0) (Quick 260508-n87)
- Hardcoded descriptions required for retired CPT codes (77404-77421 series) — NLM API only covers active codes (Phase 45)
- Active proton codes are exactly 77520, 77522, 77523, 77525 (77521 was deleted before 2024 — do not add) (Phase 45)
- classify_code_str() helper pattern avoids if_else type issues when classifying mixed code formats in purrr::map_chr (Phase 45)
- Audit-driven config expansion: run audit, auto-add confirmed codes, re-audit for 100% coverage (Phase 45)
- glue format spec `:,` is Python syntax; R requires format(x, big.mark=',') (Phase 45)
- openxlsx2 uses int2col() not int_to_col() (Phase 45)

### Pending Todos

None.

### Roadmap Evolution

- Milestone v1.5 completed and archived 2026-05-01
- Phase 42 added: Treatment Codes Resolved XLSX (All Types) — extend resolved xlsx to radiation/SCT/immunotherapy and verify chemo accuracy
- Phases 24, 26, 27, 28 dropped (no longer relevant) — 2026-05-05
- Active requirements: VIZ-01, VIZ-02, VIZ-03 (attrition waterfall, Sankey, HIPAA suppression)
- Phase 38 added: Chemo Treatment Inventory by Source Table
- Phase 39 added: Investigate Unmatched Codes
- Phase 40 added: Investigate Unmatched NDC Codes
- Phase 41 added: Combine NDC+HCPCS Reports
- Phase 43 added: Establish Treatment Lengths for SCT, Chemo, and Radiation
- Phase 44 added: Treatment Episode Start/Stop Dates — per-episode start/stop dates with episode length, special handling for historical dates outside 2012-2025 window
- Milestone v1.6 roadmap created 2026-05-15: Phases 45-47 (radiation CPT audit, treatment code cross-reference + triggering codes, cancer site frequency)

### Blockers/Concerns

None.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260501-gkl | Cleanup code health issues — root clutter, dead scripts, template fix, duplicate numbering, gitignore updates | 2026-05-01 | 68acd08 | [260501-gkl-cleanup-code-health-issues-root-clutter-](./quick/260501-gkl-cleanup-code-health-issues-root-clutter-/) |
| 260508-n87 | Centralize treatment constants and shared helpers — eliminated duplicate definitions across 9 scripts | 2026-05-08 | 1552211 | [260508-n87-look-for-improvements-in-existing-code-a](./quick/260508-n87-look-for-improvements-in-existing-code-a/) |
