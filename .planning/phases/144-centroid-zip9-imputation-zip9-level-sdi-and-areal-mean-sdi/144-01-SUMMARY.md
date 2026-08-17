---
phase: 144
plan: "01"
subsystem: utils_address
tags: [zip9, imputation, tier3, centroid, approximate_zip9]
dependency_graph:
  requires: [approximate_zip9() from Phase 139, get_zip9_at_date() from Phase 137]
  provides: [zip5_centroid zip9_source value, .classify_zip9_source centroid_lookup param]
  affects: [R/utils/utils_address.R, any caller of approximate_zip9()]
tech_stack:
  added: []
  patterns: [probe-first gate, memoised crosswalk cache, two-phase classification, injection seam]
key_files:
  created:
    - data/reference/README_zip5_centroid_zip9_crosswalk.txt
    - tests/testthat/test-utils-address-tier3.R
  modified:
    - R/utils/utils_address.R
decisions:
  - "Centroid crosswalk is not yet producible (no ZIP+4 centroid source available); probe gate degrades gracefully when absent"
  - ".needs_centroid_check is an internal placeholder; it never appears in returned zip9_source column"
  - "0000 guard rejects synthetic ZIP9s at load time with a clear error message"
metrics:
  duration: "~20 min"
  completed: "2026-08-16"
  tasks: 3
  files: 3
---

# Phase 144 Plan 01: Tier 3 Centroid ZIP9 Imputation in utils_address.R Summary

**One-liner:** Extended `approximate_zip9()` with a probe-first Tier 3 centroid fallback (`zip9_source = "zip5_centroid"`) using a memoised crosswalk cache and a two-phase `.classify_zip9_source()` that degrades gracefully when the crosswalk file is absent.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Document crosswalk derivation methodology | b616fa0 | data/reference/README_zip5_centroid_zip9_crosswalk.txt |
| 2 | Add Tier 3 centroid extension to utils_address.R | 6c71323 | R/utils/utils_address.R |
| 3 | Add unit tests for Tier 3 | e3d56ce | tests/testthat/test-utils-address-tier3.R |

## Decisions Made

1. **Crosswalk not yet producible:** The Census Gazetteer file gives one centroid per ZCTA but no ZIP+4-level coordinates. A licensed ZIP+4 centroid file or USPS Address Validation API call is required for (a) or (b). The README documents this constraint explicitly and forbids appending "0000" to ZIP5 as a synthetic fallback.

2. **Probe-first gate:** When `zip5_centroid_zip9_crosswalk.csv` is absent, `approximate_zip9()` emits a message and passes `.empty_centroid_lookup()` to `.classify_zip9_source()`, which resolves all `.needs_centroid_check` placeholders to `zip5_no_zip9` or `no_zip5` — identical to pre-Tier-3 behavior.

3. **Column isolation:** The `.needs_centroid_check` placeholder is fully consumed inside `.classify_zip9_source()` before `out` is returned. It cannot appear in caller output on any exit path.

## Deviations from Plan

None — plan executed exactly as written. All 5 code changes (cache object, empty lookup, classifier rewrite, crosswalk loader, summary message) applied verbatim from the plan spec.

## Known Stubs

None. The crosswalk file is intentionally absent — the probe gate handles this correctly. The README documents exactly how to produce it when the required data source becomes available.

## Verification Results

All 9 plan verification checks passed:

1. `.centroid_zip9_lookup_cache` defined at line 241
2. `zip5_centroid` present in `.classify_zip9_source()` case_when and summary message
3. `centroid_path` probe gate present in `approximate_zip9()`
4. `zip5_centroid.*get_count` in summary message at line 570
5. `centroid_lookup` parameter in `.classify_zip9_source()` signature
6. 9 `test_that()` calls in test-utils-address-tier3.R (5 core + 4 additional)
7. `get_zip9_at_date` function signature unchanged at line 111
8. `data/reference/README_zip5_centroid_zip9_crosswalk.txt` exists
9. `.needs_centroid_check` does not leak — both usages are guards consuming the placeholder

## Self-Check: PASSED

- `data/reference/README_zip5_centroid_zip9_crosswalk.txt` — FOUND
- `tests/testthat/test-utils-address-tier3.R` — FOUND
- `R/utils/utils_address.R` — FOUND (modified)
- Commits b616fa0, 6c71323, e3d56ce — FOUND in git log
