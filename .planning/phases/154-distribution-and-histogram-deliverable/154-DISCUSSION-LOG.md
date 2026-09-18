# Phase 154: Distribution and Histogram Deliverable — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-18
**Phase:** 154-distribution-and-histogram-deliverable
**Areas discussed:** Histogram code placement, Xlsx sheet fate, A_distribution_summary breakouts, D_fill_offsets format

---

## Histogram Code Placement

| Option | Description | Selected |
|--------|-------------|----------|
| New R/utils/utils_distance_hist.R | Separate file sourced into R/122; follows utils_address.R / utils_zip_calendar.R pattern; matches "sourced by R/122" in milestone spec | ✓ |
| Inline in R/122 SECTION 1B | No new file; adds ~100 lines to already-1115-line script | |

**User's choice:** New R/utils/utils_distance_hist.R
**Notes:** Milestone spec language "sourced by R/122" was the deciding signal.

---

## Xlsx Sheet Fate

| Option | Description | Selected |
|--------|-------------|----------|
| Drop old sheets — rds keeps raw data | Clean 6-sheet deliverable matching spec; raw encounter rows stay in .rds | ✓ |
| Keep A_encounter_distance and B_patient_summary | Xlsx grows to 8+ sheets; unwieldy for team review | |

**User's choice:** Drop from xlsx — rds keeps the raw data

**Follow-up: km bins**

| Option | Description | Selected |
|--------|-------------|----------|
| Drop km bins — miles only | B_histogram_bins in miles is canonical; km bins were Phase 152 interim | ✓ |
| Keep km summary as QC row | Cross-check for haversine vs zipcodeR discrepancy | |

**User's choice:** Drop it — miles only going forward

---

## A_distribution_summary Breakouts

| Option | Description | Selected |
|--------|-------------|----------|
| ENC_TYPE + state via zip3_state.csv | Full spec; zip3_state.csv already present and used in QC | |
| Skip breakouts — overall only | Simpler; doesn't deliver what milestone asked | |
| ENC_TYPE only, omit by-state | ZIP3 → state too imprecise for published distribution table | ✓ |

**User's choice:** Pull ENC_TYPE but omit by-state (too imprecise via ZIP3)

**Follow-up: statistics per row**

| Option | Description | Selected |
|--------|-------------|----------|
| n, median, IQR, p90, p95, p99, max | Robust stats for right-skewed distribution; what team needs for Phase 155 cutoff | ✓ |
| n, mean, SD, median, IQR, p90, p95, p99, max | Full milestone spec; includes mean/SD even for skewed data | |

**User's choice:** n, median, IQR, p90, p95, p99, max (omit mean/SD)

---

## D_fill_offsets Format

| Option | Description | Selected |
|--------|-------------|----------|
| Signed integer bins | Preserves asymmetry (past vs future fills); team can see direction | ✓ |
| Absolute-value bins with direction indicator | Easier to read but loses asymmetry at a glance | |
| Summary table only | Minimal; loses distribution shape | |

**User's choice:** Signed integer bins (e.g., [−365,−180], [−180,−90], etc.)
**Notes:** Exact bin edges left to Claude's discretion (see D-05 in CONTEXT.md).

---

## Claude's Discretion

- Exact `D_fill_offsets` bin edges
- Variable naming and pipe style
- Whether `utils_distance_hist.R` gets SECTION 1B header comment
- Exact xlsx column widths
- Ordering of `make_distance_histograms()` call relative to xlsx writer

## Deferred Ideas

None.

---

## Review Pass Addendum (2026-09-18)

Changes made to CONTEXT.md after a review against the milestone, FIX doc, and Appendix B.
Decisions were renumbered to phase-local `154-D1`..`154-D6`.

| Item | Change | Reason |
|------|--------|--------|
| By-state breakout | Reinstated as "by facility state" via `zipcodeR::zip_code_db$state` on `zip5_facility` | Original omission was reasoned from ZIP3 imprecision; ZIP5→state is exact and needs no ZIP3 |
| A_distribution_summary source | New `summarise_distance()` helper, not `make_distance_histograms()$stats` | `stats` lacks IQR/p95/p99/max and has no breakouts |
| ENC_TYPE plumbing | Three insertion points (SECTION 3, SECTION 7 select, SECTION 12) | Adding to the pull alone does not reach `enc_distance` |
| 154-03 patient rds | Added as 154-D6 | Was absent from the phase boundary; Phase 155 depends on it |
| D_fill_offsets | Sign convention stated; `[0]` bin removed; summary rows redefined | Avoid inverted past/future labels; `[0]` is empty by construction |
| Haversine cross-check | Moved to testthat, not dropped | Milestone 152-02 success criterion still applies |
| Bin width / cap | Function arguments with Appendix B defaults | Milestone says revisit after first run |
