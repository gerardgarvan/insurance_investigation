---
gsd_state_version: 1.0
milestone: v3.12
milestone_name: Team To-Do Close-out (Survivorship Rates, Anthracycline Exposure, NHL Follow-up)
status: defining_requirements
stopped_at: —
last_updated: "2026-10-22T00:00:00.000Z"
last_activity: 2026-10-22
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-14, v3.11 started)

**Core value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

**Current focus:** Phase 184 — survivorship-modality-rates-and-distance-modality-interaction

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-10-22 — Milestone v3.12 started

**Phase 177 close-out (2026-10-12):** Outcome = Document only. R/177_temporal_match_sizing.R built and run on HiPerGator; output workbook: output/temporal_match_sizing_20261012.xlsx. NEEDS_TEMPORAL_MATCH patients (410) generate **zero** patient_zip_missing encounters in R/122 — R/122's address-history calendar already resolves their ZIPs from LDS_ADDRESS_HISTORY. share_whole=0%, share_post=0%, far_ratio=0%. No new imputation tier warranted. All D-04 cross-tab cells explained. 177-SIZING-MEMO.md written. R/.planning/ duplication resolved in this session (planning artifacts archived to root; R/.planning/ retired and gitignored). Quick task (operator): add note to R/122 workbook KEY — temporal match would fill 0 encounters (Phase 177); the 3,731 patient_zip_missing encounters are UNREACHABLE_NO_ZIP9 or not in R/121 — no dated ZIP exists to fill them.

**Quick task — R/147_verify_vs_1006.R fixes (2026-10-13):** Guard final `quit()` with `!interactive()` (line 554); exact-match 'Confirmed-cohort N' and QC label lookups use `fixed = TRUE` / `==` rather than partial regex. Quit audit found no other unguarded `quit()` calls in `R/`. Follow-up (post-phase-178): QC row lookups at `QC:total_person_years` and `QC:matched_rows_drop` tightened to `trimws(df[[1]]) == label` with exact single-match enforcement (FAIL if != 1 match, naming label and count).

**Phase 180 close-out (2026-10-13):** D-05 same side confirmed — limitation row added to R/179 KEY builder; bounded ORs: far=1 OR 0.776 (0.693–0.867), far=0 OR 0.872 (0.751–1.012), both below 1 alongside primary 0.845. D-09 result (primary restriction, any_lab_year=1): moves toward 1 (37.4% shrinkage >= 25%) — consistent with out-of-system care; report to Amy/Erin alongside D-165-01. MISS-01 top groups: (b) facility ZIP missing 581 pts / 2,421 py, (a) patient ZIP missing 164 pts / 1,260 py. Outputs: cbc_missing_capture_20261013.xlsx + internal RDS (58,595 rows).

**Study hypothesis (added 2026-10-13, MISS-04):** Far patients may obtain CBCs outside the UFHealth system, so "no CBC in the record" can mean "not captured" rather than "not received." MISS-04 tests this via: (a) in-system encounter rate in the same one-year window (far vs not-far), (b) Phase 165 association restricted to patients with ≥1 in-system encounter, (c) Phase 165 association stratified by Phase 167 single-health-system flag. OR movement toward 1 under restriction/stratification → consistent with out-of-system care (non-capture); OR stays → consistent with true difference in CBC receipt. Report only; goes to Amy/Erin with D-165-01.

**Phase 176 close-out (2026-10-12):** 2026-10-09 HiPerGator run confirmed as the close-out run (both inputs predate run; 547/135 constants confirmed). All 8 reconciliation quantities PASS. 151-01-SUMMARY.md written with Verdict: PASS. All 12 record-level mismatches documented (10 same-ZIP3, 2 different-ZIP3) — all accepted as expected data quirks. Phase 151 ticked [x] in root ROADMAP. HYGIENE-03 marked Complete. R/.planning/ is a full parallel planning tree created when GSD was launched from inside R/ subdirectory; deferred to Phase 177 for resolution (not a pure stale subset — has diverged content). Note: always launch GSD from the repo root, not from R/.

**Phase 175 close-out (2026-10-12):** Three-way exit guard added to R/88 (testthat no-op / interactive stop() / batch quit(status=1)). skip_check() helper added; 13 runtime-skip fake-TRUEs and 2 fake-assertions converted. p163_skip_note now bumps global skipped counter. R88_FORCE_FAIL sentinel added. HiPerGator confirmed all 4 paths: ec0=0 (ALL 960 CHECKS PASSED, 3 skipped), ec1=1 (FAILED: 1/961, 3 skipped), stop() fires in interactive with session alive. New R/88 baseline: 960 CHECKS PASSED, 3 skipped. Downstream phases cite "PASS == total, FAIL == 0" not a fixed number.

**Phase 174 close-out (2026-10-12):** Counter bugs fixed in R/88. .p135_check and check_137 (28+14 checks) now update global passed/failed. check_138/139/144 unconditional passed<<- moved into pass branch only. Production cache_dir check added. HiPerGator confirmed: ALL 963 CHECKS PASSED, FAIL == 0. R/88 baseline was 963 (was 920) — superseded by Phase 175 baseline of 960 CHECKS PASSED (3 skipped).

**Phase 173 close-out (2026-10-12):** Path B taken (fresh HiPerGator re-run, R/4.5 interactive, ~0.2 min, host c0700a-s28.ufhpc). Encounter-grain DoI counts exactly match Phase 130 baseline (2026-07-16) — DuckDB pcornet.duckdb confirmed unchanged. ALL 920 R/88 CHECKS PASSED. SMOKE-130-01 footer confirmed in R/88 validated requirements list. doi_attribution_report.xlsx produced with 4 sheets (Patient Prevalence, Encounter Co-occurrence, Drug x DoI Summary, Metadata). Mutual-exclusivity: 0 codes classify as both DoI and cancer. DOI-REG-01/02/03 closed.

**v3.9 Roadmap (2026-10-12):**

- Phase 174: Smoke-Check Discrepancy (HYGIENE-01) — find and fix/document the 920/921 gap
- Phase 175: R/88 Exit-Status Hardening (HYGIENE-02) — quit(status=1) + interactive FAILED message; depends on 174
- Phase 176: Phase 151 Close-Out (HYGIENE-03) — R/121 HiPerGator run + 151-01-SUMMARY.md; may run with 177
- Phase 177: NEEDS_TEMPORAL_MATCH Sizing Memo (HYGIENE-04) — unfilled-ZIP encounter counts + imputation-tier recommendation; may run with 176

Progress: [██████████] 100% (4/4 phases complete)

## Performance Metrics

**Milestone velocity:**

- v3.8: 4 phases (170-173) completed (2026-10-09 to 2026-10-12)
- v3.7: 5 phases (165-169) completed (2026-10-09)
- v3.2: 23 phases (104-126) completed (2026-06-15 to 2026-07-15)

**Planning efficiency:**

- Average plans per phase: 1.0 (recent milestones)
- Average tasks per plan: 3.0

## Accumulated Context

### Roadmap Evolution

- Phase 182.1 inserted after Phase 182: ZIP Centroid Mapping for Unique/PO-Box and Placeholder ZIPs (URGENT) — 134,949 zip_not_in_db encounters; 32610 alone accounts for 106,423 (UF Health Shands campus); placeholder ZIPs treated as missing; full re-run chain R/122→R/165→R/179→R/180→R/181 required before Phase 183

### v3.9 Roadmap Decisions

- Phase numbering continues from Phase 173 (v3.8 last phase) — v3.9 starts at Phase 174
- Granularity: coarse (4 phases, fixed scope per instructions)
- Phase 174 is a strict prerequisite for Phase 175: exit-status hardening must be tested against a known-clean baseline count that Phase 174 establishes
- Phases 176 and 177 may run in any order after Phase 175; they are independent of each other
- All phases require an interactive HiPerGator run step (module load R/4.5; source() with local = new.env(parent = globalenv()))
- ROADMAP ticks are gated on real HiPerGator confirmation passes, not local structural checks alone

### HiPerGator Run Pattern (v3.9 standard)

All phases in v3.9 use the same confirmation pattern:

```r
module load R/4.5
R --no-save
source("R/88_smoke_test_comprehensive.R", local = new.env(parent = globalenv()))
```

### Known Context

- R/88 baseline (Phase 175): ALL 960 CHECKS PASSED (3 skipped); exit code 0 clean, exit code 1 with R88_FORCE_FAIL=1
- Phase 151 (Per-Patient ZIP Problem Inventory) had a HiPerGator run confirmed 2026-10-09 per the ROADMAP detail note, but no 151-01-SUMMARY.md was written and the phase is not ticked — Phase 176 closes this out
- R/121 groups from Phase 151: NEEDS_TEMPORAL_MATCH (~410 patients), UNREACHABLE_NO_ZIP9 (~427 patients)
- Phase 150 concordance baseline: 547 concordant / 135 discordant (~80%) — used as expected error rate in Phase 177 memo

## Session Continuity

**Phase 183 close-out (2026-10-15):** MICE sensitivity for distance complete. D-01 (log_dist PMM) and D-02 (far logreg), m=20 each, 614 patients imputed. Pooled primary (years 2+): D-01 OR=0.842 (0.725–0.977) FMI=0.049, D-02 OR=0.834 (0.713–0.976) FMI=0.160 — both within Phase 180 bounds and within 0.01 of each other. loggedEvents: main_sourceUCI dropped (D-01 PMM only, non-mandatory, not a D-09 stop). payer dropped (payer_summary RDS not found, optional per D-07b). R/88: ALL 982 CHECKS PASSED (3 skipped). Outputs: mice_sensitivity_distance_20261015.xlsx, mice_trace_20261015.png, mice_density_20261015.png, 183-MEMO.md.

**Last command:** Phase 182.1 complete — ZIP→ZCTA crosswalk fallback (HRSA 2022 vintage) added to R/122; 13,652 encounters resolved via zipcodeR_crosswalk, 14 via haversine_gazetteer; 2,647 encounters with missing patient ZIP + placeholder facility ZIP now classified as facility_zip_missing; 107,624 encounters remain zip_not_in_db. Phase 182.1 gained 48 patients (vs 185 in Phase 182); far switches: 50 total. D-09 % shrinkage: 30.4% → 19.7% (no material change, near 25% threshold). Phase 183 target: 614 patients. R/88 ALL 982 CHECKS PASSED (3 skipped); SMOKE-182.1-01 9/9 PASS (fixed [2d] to strip comment lines before is_sentinel_zip5 check; renumbered all labels [x/7]→[x/9]).
**Stopped at:** Phase 184 Plan 01 complete — awaiting HiPerGator checkpoint

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 261022-hg3 | Add caveman lite as the project default | 2026-10-22 | d568ea3 | [261022-hg3-add-caveman-lite-as-the-project-default](./quick/261022-hg3-add-caveman-lite-as-the-project-default/) |

Last activity: 2026-10-22 - Completed quick task 261022-hg3: Add caveman lite as the project default
