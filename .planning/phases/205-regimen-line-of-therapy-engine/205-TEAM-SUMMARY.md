# Phase 205 Team Summary: Regimen and Line-of-Therapy Engine

**Status:** Candidate built; not shipped. Delivered files are unchanged (Phase 204 versions). Candidate outputs are in `output/internal/p205_candidate_v4`.

## What the candidate does

- Labels systemic-therapy episodes with a regimen using a dictionary, and assigns a line of therapy per patient.
- Quality checks all passed: no unlabelled systemic episodes, no labels on non-systemic episodes, no BV / PD-1-only label without those agents.
- About 19% of systemic episodes remain "Unrecognized" (mostly single agents or fragments, methotrexate alone, bevacizumab, obinutuzumab).

## Change relative to Phase 204

- ABVD 1108 of 1109 episodes unchanged; AVD 236/236; Nivo+AVD 42/42.
- BV+AVD 242 of 251 episodes unchanged; 13 differ (supportive leuprolide / goserelin and edge cases).
- ABVD_PLUS 166 of 186 unchanged; 16 become ABVD after excluding supportive agents.
- Patients with ever-ABVD: 1230 to 1250. First chemotherapy ABVD: 1176 to 1195.
- Previously blank episodes now labelled, for example Salvage 661, Rituximab_mono 474, Bendamustine mono 172, CHOP 152, R-CHOP 139, ABVD/AVD partial 145.

## Line of therapy

- Rule: a new line starts on a change of regimen family, or on a same-family restart after at least 365 days.
- 2940 patients have a recognized line: 1 line 2313; 2 lines 339; 3 lines 150; 4 lines 79; more than 4 lines 59.
- First line (1959 patients): ABVD 956, BV+AVD 194, AVD 169, partial 118, R-CHOP 115, CHOP 108, ABVD_PLUS 95, Bendamustine mono 85, BR 48, CHOEP 27, Nivo+AVD 27, BEACOPP 17.

## Limitation

Concurrent BV + bendamustine and similar chemotherapy + immunotherapy combinations are recorded as separate episodes, alternate families, and may raise the line count for about 2% of patients. Recognizing cross-type combinations before line assignment is a possible later change.

## Decisions requested

1. D-201-01: exclude supportive agents (GnRH agonists) from ABVD_PLUS (proposed: yes).
2. ABVD/AVD partial excluded from `ever_abvd` (proposed: yes).
3. NHL-family first-line regimens (R-CHOP, CHOP, CHOEP, Bendamustine mono, BR; 383 patients) may reflect non-HL or composite cases; review against the D-203-02 cohort definition.
4. Same-family restart threshold of 365 days: confirm.
5. Replace the delivered `gantt_episodes_180.csv` with the 205 version?

Detail: `REGL-06-decisions.md`, `205-VERIFICATION.md`.

## Decisions received 2026-11-14

- D-201-01 = NO (GnRH agonists do not make ABVD_PLUS) and 205-2 = NO (partial not in `ever_abvd`) are applied to the delivered `gantt_episodes_180.csv` by `R/206_apply_decisions_gantt180.R` (pre-decisions copy: `output/internal/gantt_episodes_180_pre_decisions_20261114.csv`). The full 205 replacement is not shipped.
- All other items above are deferred to 2026-12-07.
