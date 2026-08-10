# Deferred Items -- Phase 139

Out-of-scope discoveries found during 139-04 execution. Not fixed (per SCOPE BOUNDARY: only
auto-fix issues directly caused by the current task's changes). Confirmed pre-existing --
`git diff --stat R/88_smoke_test_comprehensive.R` for the 139-04 session shows only additive
changes (74 insertions, 0 deletions) to this file, so these two failures are unrelated to
Phase 139 and existed before this session's edits.

## 1. `R/88_smoke_test_comprehensive.R` line ~197: "Coverage analysis output exists: output/source_coverage_analysis.csv" -- FAIL

Pre-existing check, unrelated to Phase 139 (R/115). Not investigated or fixed here.

## 2. `R/88_smoke_test_comprehensive.R` line ~581: "get_chemo_hits('MED_ADMIN') returns >=1 row against local fixture (Phase 122, IS_LOCAL)" -- FAIL

Pre-existing check (Phase 122, MED_ADMIN chemo-detection fixture), unrelated to Phase 139.
Not investigated or fixed here.

## Net effect on Phase 139's own verification

Section 15ad (Phase 139 structural checks, added by this plan) shows 14 PASS, 0 FAIL --
satisfying this plan's own success criterion ("Rscript R/88_smoke_test_comprehensive.R exits
0 with Section 15ad showing 0 FAIL"). The overall script exit code is 1 (728 checks total, 2
failed) solely because of the two pre-existing, out-of-scope failures above -- not because of
anything introduced by Phase 139.
