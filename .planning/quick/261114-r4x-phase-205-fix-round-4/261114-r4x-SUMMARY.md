# Quick 261114-r4x: Phase 205 fix round 4

## Assumptions (headless run)
- Ran inline (no planner/executor subagents) to keep the change small; verified locally with parse checks and testthat only.
- CHOP/BEACOPP were already in REGIMEN_DICT and resolve locally; added tests, token normalization and an R/28 unrecognized-drug-set diagnostic instead of new entries.
- BV+AVD span rule follows the committed Phase 201 code (chemo date span +/-7), pooling any systemic treatment_type per the request.
- Bendamustine first-line exclusion left unimplemented (proposed decision only).

## Changes
- R/00_config.R: immunotherapy entries, SUPPORTIVE_AGENTS.
- R/utils/utils_regimen.R: normalize_regimen_drug, detail_agents, REGIMEN_NON_HL_LABELS, classify_abvd_set, adjust_abvd_family.
- R/205_lot_output.R: drug-set breakdown per 204->205 change (n >= 11), BV+AVD / Nivo+AVD residual.
- R/28_episode_classification.R: top unrecognized drug sets.
- tests/testthat/test-205-regimen-round4.R (new); one assertion in test-205-regimen-revision.R updated (rule c).
- REGL-06-decisions.md: round 4 section, open decisions.

## Verification
- tools/rcheck.sh parse: 6 files OK. tools/rcheck.sh test 205: 0 failures.

## PENDING HIPERGATOR
See REGL-06-decisions.md "Fix round 4" for console steps and lines to paste back.
