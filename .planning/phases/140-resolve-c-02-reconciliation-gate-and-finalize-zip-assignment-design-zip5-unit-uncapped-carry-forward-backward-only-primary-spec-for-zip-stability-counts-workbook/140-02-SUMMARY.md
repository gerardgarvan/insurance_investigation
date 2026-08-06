---
phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook
plan: 02
subsystem: data-pipeline
tags: [r, duckdb, geocoding, crosswalk, zip-assignment, data-quality-gate]

# Dependency graph
requires:
  - phase: 139-zip-stability-imputation-occurrence-counts
    provides: R/115_zip_stability_counts.R's block-group probe/join scaffold (SECTION 8), gracefully degraded to has_block_group_crosswalk = FALSE absent a staged file
provides:
  - "Documented staging contract (path/columns/source/vintage) for the Neighborhood Atlas ZIP9-to-block-group crosswalk in data/reference/README.md, requiring no further code changes once the file lands"
  - "Coverage-aware activation gate on the block-group tier (BLOCK_GROUP_MATCH_THRESHOLD, default 90% pending confirmation) so P-03a's acceptance is file-existence AND adequate match rate, not presence alone"
  - "Recorded outcome of the crosswalk acquisition human-action: not available, explicitly deferred (not a regression from Phase 139's shipped state)"
  - "Recorded D-2 team decision: ZIP5 accepted as the primary analysis unit now (option-a), unblocking Plans 140-04 through 140-07"
affects: [140-04-PLAN, 140-05-PLAN, 140-06-PLAN, 140-07-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Coverage-aware crosswalk activation: file.exists() alone is insufficient evidence a geographic crosswalk is usable -- gate on match-rate-against-observed-universe (n_zip9_matched_to_block_group / n_zip9_distinct_observed), not join success alone"
    - "Decision-recording checkpoint tasks (no <files> tag) resolved by recording the team's answer in SUMMARY.md/STATE.md rather than by code changes"

key-files:
  created: []
  modified:
    - data/reference/README.md
    - R/115_zip_stability_counts.R

key-decisions:
  - "D-2: ZIP5 accepted as the primary analysis unit now (option-a), not deferred pending the block-group crosswalk re-run -- the block-group confirmation stays confirmatory, not gating, per 140-CONTEXT.md's own design"
  - "P-03a crosswalk acquisition: not available -- explicitly deferred. Block-group tier remains gracefully degraded (not a regression from Phase 139's shipped state); P-03b (A-06 re-run with block-group tier populated) and full P-03c confirmation stay deferred as follow-up work outside this plan's scope"

patterns-established:
  - "Geographic crosswalk staging: document the exact contract (path/columns/vintage/threshold) before the file exists, so acquisition is a pure human-action with zero follow-on code risk"

requirements-completed: [P-03a, P-03b, P-03c, D-2]

# Metrics
duration: 25min (Task 1, prior session) + this session (Task 2/3 resolution)
completed: 2026-08-06
---

# Phase 140 Plan 02: Crosswalk Staging Contract + D-2 ZIP5 Decision Summary

**Neighborhood Atlas block-group crosswalk staging contract documented with a 90%-match-rate coverage gate wired into R/115; crosswalk acquisition itself deferred by team decision; D-2 resolved as ZIP5-primary-now, unblocking Plans 140-04 through 140-07.**

## Performance

- **Duration:** Task 1 executed and committed in a prior session (~25 min, 2 tasks-worth of code); this session resolves the two remaining checkpoint tasks (Task 2 human-action, Task 3 decision) via user-provided resolutions -- no additional code changes required.
- **Started:** 2026-08-06 (prior session, Task 1) / resumed 2026-08-06T23:13:22Z (this session)
- **Completed:** 2026-08-06T23:13:22Z
- **Tasks:** 3 (1 auto, 1 checkpoint:human-action, 1 checkpoint:decision) -- all 3 resolved
- **Files modified:** 2 (data/reference/README.md, R/115_zip_stability_counts.R) -- both from Task 1, already committed

## Accomplishments
- Task 1 (already committed, verified intact this session): `data/reference/README.md` documents the exact expected path, filename, column-name contract, required vintage (2021 Neighborhood Atlas release, pending confirmation), and source for the ZIP9-to-block-group crosswalk; R/115 SECTION 8 gained a match-rate coverage gate (`BLOCK_GROUP_MATCH_THRESHOLD = 0.90`, `n_zip9_matched_to_block_group`, `pct_zip9_matched_to_block_group`) that downgrades `block_group_tier_status` to `"found but coverage insufficient"` if a staged crosswalk covers fewer than 90% of distinct observed ZIP9s, plus two new QC rows (SECTION 13) reporting the coverage figure whenever a crosswalk is found.
- Task 2 (human-action, resolved this session): the team has not obtained the Neighborhood Atlas crosswalk file. Recorded as "not available -- defer" per the plan's own resume-signal handling. No code changes required beyond Task 1 -- the auto-probe/gate already handles file-absence gracefully (block_group_tier_status reads "not available (crosswalk file not found)"). P-03b (A-06 re-run with block-group tier) and full P-03c confirmation remain deferred as follow-up work, outside this plan's scope.
- Task 3 (decision, resolved this session): D-2 answered as **option-a -- accept ZIP5 as the primary analysis unit now.** This unblocks Plans 140-04 through 140-07, which treat ZIP5 as the working assumption. In particular, 140-04's S1-fold-in design (per 140-08-PATCH FIX-03, folding S1 into S3 in the ordered scenario assignment) is confirmed applicable and should proceed under this decision when that plan executes. The block-group re-run remains confirmatory evidence (not a gating precondition) per 140-CONTEXT.md's own design -- this decision is not contingent on Task 2's outcome.

## Task Commits

Each task was committed atomically:

1. **Task 1: Document crosswalk staging contract + wire match-rate coverage gate** - `5d4309b` (docs) + `6862a64` (content landed via a concurrent 140-01 commit due to a `git add -p` race across parallel Wave-1 agents; verified present and correct in the current file state)
2. **Task 2: Obtain/stage crosswalk file (checkpoint:human-action)** - No code commit; resolved via decision recording only (see below). Outcome: "not available -- defer."
3. **Task 3: D-2 ZIP5-vs-ZIP9 decision (checkpoint:decision)** - No code commit; resolved via decision recording only. Outcome: option-a (ZIP5 accepted now).

**Plan metadata:** this SUMMARY.md + STATE.md/ROADMAP.md updates (docs commit, see below)

_Note: Tasks 2 and 3 have no `<files>` tag in the plan -- they are decision-recording tasks by design, resolved entirely through documentation (this SUMMARY.md, STATE.md), not code._

## Files Created/Modified
- `data/reference/README.md` - Documents the Neighborhood Atlas crosswalk's expected path (`data/reference/neighborhood_atlas_block_group_crosswalk.csv`), source, required vintage (2021 release, pending confirmation against LDS_ADDRESS_HISTORY's 2012-01-01 to 2025-03-31 study period), expected column-name candidates, and the 90%-match-rate coverage threshold -- all pending final team confirmation but fully specified so staging requires zero further code changes.
- `R/115_zip_stability_counts.R` - SECTION 8 gains the match-rate coverage gate (`BLOCK_GROUP_MATCH_THRESHOLD`, `n_zip9_matched_to_block_group`, `pct_zip9_matched_to_block_group`) inside the existing `has_block_group_crosswalk` branch, additive only, no change to default (crosswalk-absent) behavior; SECTION 13 gains two new QC rows reporting the coverage figures when a crosswalk is found.

## Decisions Made
- **D-2 (ZIP5 as primary analysis unit):** option-a selected -- ZIP5 is accepted as the primary analysis unit now, not deferred pending the block-group crosswalk re-run. Rationale: 140-CONTEXT.md's real accuracy-by-gap-bin evidence shows ZIP5 exact-match consistently outperforming ZIP9 exact-match at every horizon past same-day (61.8% vs. 37.1% overall; e.g. 52.0% vs. 29.1% at 181-365 days), and 39.3% of ZIP9 transitions are +4-only (same ZIP5). The countervailing consideration (ZIP9-exact is a conservative proxy that understates ZIP9's true block-group-level utility) is acknowledged but does not block downstream Phase 140 work, per 140-CONTEXT.md's own recommendation that the block-group re-run be confirmatory, not gating. This decision unblocks Plans 140-04 through 140-07 and specifically confirms 140-04's S1-fold-in design (140-08-PATCH FIX-03) is applicable.
- **P-03a crosswalk acquisition:** explicitly deferred -- "not available." The Neighborhood Atlas portal file has not been obtained by the team. This is recorded as a deliberate deferral, not a silent skip: the block-group tier remains gracefully degraded (`block_group_tier_status = "not available (crosswalk file not found)"`), which is the same behavior Phase 139 already shipped -- not a regression. P-03b (A-06 re-run with block-group tier populated) and full P-03c confirmation are follow-up work outside this plan's scope, to be picked up whenever the file is eventually staged (no code changes will be needed at that point, per Task 1's contract).

## Deviations from Plan

None - plan executed exactly as written. Tasks 2 and 3 were checkpoint tasks by design (no `<files>` tag, decision-recording only); their resolutions were supplied by the user in this session and recorded here per the plan's own resume-signal instructions, with no code changes required or attempted.

## Issues Encountered
None. Task 1's code (README + R/115 SECTION 8/13 additions) was verified still intact and correctly landed in commit `6862a64` (a prior-session race between two concurrently-executing Wave-1 agents' commits, already documented in STATE.md and re-confirmed via `grep` in this session).

## User Setup Required

None required by this plan directly. Follow-up (not blocking): if/when the team obtains the Neighborhood Atlas ZIP9-to-block-group crosswalk file, place it at `data/reference/neighborhood_atlas_block_group_crosswalk.csv` per the contract documented in `data/reference/README.md` -- no code changes will be needed to activate the block-group tier or its coverage gate.

## Next Phase Readiness
- Plans 140-04 through 140-07 are unblocked: D-2 (ZIP5-as-analysis-unit) is now a recorded, explicit decision (option-a) rather than a pending blocker. 140-04's S1-fold-in design is confirmed applicable and should proceed under this decision.
- P-03b (A-06 re-run with the block-group tier populated) and full P-03c confirmation remain open follow-up items, not blockers -- they require the Neighborhood Atlas crosswalk file, which the team has deferred obtaining for now. The block-group tier's graceful degradation (shipped in Phase 139) is unchanged; Task 1's coverage gate is additive and activates automatically whenever the file is eventually staged.
- 140-01 (Wave 1, the other in-flight plan) remains separately paused at its own D-1 blocking checkpoint (26-patient C-02 denominator confirmation) -- unrelated to this plan's completion and tracked independently in STATE.md.

---
*Phase: 140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook*
*Completed: 2026-08-06*

## Self-Check: PASSED

- FOUND: 140-02-SUMMARY.md (this file)
- FOUND: commit 5d4309b (Task 1, README)
- FOUND: commit 6862a64 (Task 1, R/115 content, landed via concurrent commit race)
- FOUND: `neighborhood_atlas_block_group_crosswalk.csv`, `Vintage`, `90%` all present in data/reference/README.md
- FOUND: `n_zip9_matched_to_block_group`, `BLOCK_GROUP_MATCH_THRESHOLD` present in R/115_zip_stability_counts.R
