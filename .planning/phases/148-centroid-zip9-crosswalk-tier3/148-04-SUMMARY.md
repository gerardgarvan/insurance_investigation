---
plan: 148-04
phase: 148-centroid-zip9-crosswalk-tier3
status: complete
tasks-completed: 2/2
self-check: PASSED
---

## What Was Built

- `data/reference/README.md`: zip9_source final breakdown table updated to 2026-08-19 figures;
  new "ZIP5-Level ADI Summary (Phase 148)" section added with D-04(a/b/c) figures, columns,
  R/116 integration notes, and rural degradation note.
- `.planning/phases/148-centroid-zip9-crosswalk-tier3/148-DISCOVERY.md`: §5 placeholders
  replaced with actual D-04 figures and bug note (isTRUE fix).

## D-04 Final Figures

- **(a) ZIP5s in zip5_adi_summary.csv:** 20,950
- **(b) Records resolved of 36,953 needing Tier 3:** 30,725 (83.2%) — lead figure
- **(c) Encounters with zip5_representative:** 47,036

## Phase 148 Acceptance Criteria — All Met

- [x] `zip5_representative` fires in `.classify_zip9_source()` (both arms)
- [x] `adi_natrank_zip5_median` column distinct from `adi_natrank` — never coalesced
- [x] D-04(a): 20,950 ZIP5s in summary
- [x] D-04(b): 30,725 / 36,953 = 83.2% of Tier 3 records resolved (lead figure)
- [x] D-04(c): 47,036 encounters classified `zip5_representative`
- [x] `data/reference/README.md` documents `zip5_adi_summary.csv`
- [x] 148-DISCOVERY.md §5 has no [TBD] placeholders
- [x] Rural degradation note written (Route B: IQR width, not distance_m)
- [x] isTRUE vectorization bug documented in DISCOVERY.md §5 and 148-03-SUMMARY.md
- [x] All changes committed to git

## Tasks

1. **Task 1:** DISCOVERY.md §5 filled; README.md zip5_adi_summary section written.
2. **Task 2:** Committed — see commit below.

## Commit

`fix(148) + docs(148-04)` — see git log for exact hash after commit.
