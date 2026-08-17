---
phase: 146-acquire-and-stage-the-ses-reference-files-sdi-svi-adi
plan: 06
status: complete
completed: "2026-08-17"
key-files:
  created:
    - .planning/phases/146-acquire-and-stage-the-ses-reference-files-sdi-svi-adi/146-DISCOVERY.md
---

# Phase 146 Plan 06: HiPerGator Real-Run Verification — Summary

**One-liner:** R/116 ran on HiPerGator with all four staged indices; RUCA 77.7%, SDI 77.5%, SVI 77.5%, ADI 75.0% — all non-zero and within the 77.7% ceiling. R/88 passes.

## Task Results

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | Re-run R/116 + R/88 on HiPerGator | ✓ COMPLETE | All acceptance criteria met |

## Key Findings

**R/116 coverage per index (1,950,696 encounter rows, 8,953 patients):**

| Index | Coverage | Within ceiling? |
|-------|----------|-----------------|
| RUCA  | 77.7%    | ✓               |
| SDI   | 77.5%    | ✓               |
| SVI   | 77.5%    | ✓               |
| ADI   | 75.0%    | ✓               |

- SVI derived file (`svi_2020_zcta_derived.csv`) loaded successfully — R/117 findSVI run confirmed working
- ADI 2.7pp below ceiling: Tier 3 centroid crosswalk not staged (zip5_modal = 0, Branch C confirmed)
- Fan-out `stopifnot()` guards did not trip; row count preserved
- "Coverage Ceilings" sheet present in summary workbook

**R/88:** PASS — probe gates degrade absent indices to NA without crashing.

## Deferred (Non-Blocking)

- Sentinel-ZIP top-20 frequency table (D-04 systematic-vs-scattered verdict)
- SDI distinct unmatched ZIP5 count (encounter-weighted gap derivable: 0.2pp ≈ 3,901 rows)

Both deferred items are diagnostic, not blocking. Phase acceptance criteria are satisfied.

## Self-Check: PASSED
