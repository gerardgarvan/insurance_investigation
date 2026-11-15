---
phase: 205-regimen-line-of-therapy-engine
status: candidate-built-not-shipped
verified: 2026-11-14
---

# Phase 205 Verification

**Status:** CANDIDATE BUILT, NOT SHIPPED. Delivered files remain Phase 204 versions (`output/internal/pre205_run_backup`). Candidate outputs: `output/internal/p205_candidate_v4` (`gantt_episodes_180.csv`, `regimen_reconciliation_p205.csv`, `lot_summary_p205.rds`, RDS). HiPerGator run 5, commit 466b0f9.

## QC (R/205)

| Check | Result |
|-------|--------|
| Unlabelled systemic episodes | 0 (pass) |
| Non-systemic episodes with a regimen label | 0 (pass) |
| Chemotherapy episodes labelled BV / PD-1-only without those agents | 0 (pass) |
| Unrecognized systemic share | about 19% of systemic episodes (single agents / fragments, MTX alone, bevacizumab, obinutuzumab); informational |

## Reconciliation vs Phase 204 (180d)

- ABVD 1108/1109 kept; AVD 236/236; Nivo+AVD 42/42.
- BV+AVD 242/251 (13 differ: supportive leuprolide / goserelin, edge cases).
- ABVD_PLUS 166/186 (16 -> ABVD via supportive-agent exclusion).
- `ever_abvd` 1230 -> 1250 (1229 in both). First-chemo ABVD 1176 -> 1195.
- New labels on previously blank episodes: BEACOPP 104, CHOP 152, R-CHOP 139, CHOEP 58, BEAM 93, Salvage 661, BR 60, Bendamustine mono 172, Rituximab_mono 474, ABVD/AVD partial 145.

## LOT

- Rule: new line on family change or same-family restart >= 365 d.
- 2940 patients with a recognized line; n_lines 1 = 2313, 2 = 339, 3 = 150, 4 = 79, > 4 = 59.
- First line (recognized regimens), 1959 patients: ABVD 956, BV+AVD 194, AVD 169, partial 118, R-CHOP 115, CHOP 108, ABVD_PLUS 95, Bendamustine mono 85, BR 48, CHOEP 27, Nivo+AVD 27, BEACOPP 17.

## Known limitation

Concurrent BV + bendamustine and similar chemo + immunotherapy combos are separate Chemotherapy and Immunotherapy episodes, alternate families and inflate LOT for about 2% of patients. Future fix: recognize cross-type combos before LOT.

## Not verified / open

- Plan 205-03 (R/88 SMOKE-205-01 section) not executed; ship gate not met.
- Open decisions: see `REGL-06-decisions.md` (D-201-01, REGL-06-J, REGL-06-K2, D-205-LOT-RESTART, D-205-SHIP, D-205-XTYPE).
- Cohort membership, 7-day confirmation and D-201-04 unchanged.
