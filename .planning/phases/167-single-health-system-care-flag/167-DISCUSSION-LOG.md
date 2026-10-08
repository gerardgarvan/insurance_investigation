# Phase 167: Single-Health-System Care Flag — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-08
**Phase:** 167-single-health-system-care-flag
**Areas discussed:** Encounter filter scope, Anchor date source, Workbook tab detail, Joinable output, Blank SOURCE handling

---

## Encounter Filter Scope

| Option | Description | Selected |
|--------|-------------|----------|
| All-time cohort encounters | No date filter — any ENCOUNTER row for a cohort PATID | |
| CONFIG date range (pipeline bounds) | Same bounds R/01 applies, as reconciled in Phase 136 (CONFIG$date_range_max) | ✓ |
| Custom Phase 167 date range | Introduce a new date range specific to this phase | |

**User's choice:** Use CONFIG date range — "reuse the pipeline's date range; don't invent one."
**Notes:** Encounters with missing ADMIT_DATE excluded from both windows and counted in QC. This keeps Phase 167 consistent with the rest of the pipeline.

---

## Anchor Date Source

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 165/166 output files | Read hl_anchor_date from most-recent Phase 165 or 166 RDS | |
| R/147's anchor source directly | Same source Phase 165/166 use — no run-order dependency on those phases | ✓ |
| cohort CSV (hl_cohort.csv) | Read from the base cohort file | |

**User's choice:** R/147's anchor source directly.
**Notes:**
- Post-anchor window: ADMIT_DATE > hl_anchor_date (anchor day = before-anchor, matching Phase 165/166)
- No anchor date: whole-record flag computed; post-anchor = NA (not 0); counted in QC
- Anchor date but zero post-anchor encounters: n_sources_post = 0, single_source_care_post = NA. Zero encounters must not be reported as single-source.

---

## Workbook Tab Detail

| Option | Description | Selected |
|--------|-------------|----------|
| Roadmap spec as-is | n/% single-source, n_sources distribution, by-SOURCE breakdown | |
| Roadmap spec + encounter-count breakdown | Add single- vs multi-source by encounter band (1, 2–4, 5–9, 10+); n_sources "4+" cap; whole-record vs post-anchor 2×2 | ✓ |

**User's choice:** Roadmap spec + encounter-count breakdown.
**Notes:** "Patients with only one or two encounters are single-source almost by default. Without accounting for that, the headline percentage mostly measures how few encounters people have." The 2×2 table shows how many patients change classification across windows. suppress_small() applied throughout including by-SOURCE breakdown.

---

## Joinable CSV Output

| Option | Description | Selected |
|--------|-------------|----------|
| xlsx only | No separate flat file | |
| CSV only | Flat file for joins, no internal RDS | |
| CSV + internal RDS | Dated CSV (shareable) + internal RDS (with patient IDs) | ✓ |

**User's choice:** CSV + RDS.
**Notes:** Columns: ID, n_encounters, n_sources, single_source_care, primary_source, n_encounters_post, n_sources_post, single_source_care_post, any_blank_source. primary_source = most common site for multi-source patients (alphabetical tiebreak). Phase 165 sensitivity model can consume this directly.

---

## Blank SOURCE Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude and flag | Compute flags over non-blank SOURCE only; any_blank_source flag; QC count | ✓ |
| Treat blank as own site | Blank SOURCE counted as a distinct site in main computation | |
| Coerce to "Unknown" | Map blank to a sentinel site value | |

**User's choice:** Exclude and flag (non-blank only for primary classification) + sensitivity row in QC treating blank as its own site.
**Notes:** This was raised by the user as needing explicit statement: "flagged, not coerced" leaves the flag's value open without this rule. The sensitivity row lets the team see whether blanks change the result without contaminating the primary classification.

---

## Claude's Discretion

- Column ordering in RDS beyond required columns
- Exact tie-breaking for primary_source (alphabetical sufficient)
- DuckDB query structure (CTE vs subquery) — follow R/116 pattern
- Workbook UF styling — match Phase 166 convention

## Plan-End Requirements (stated explicitly by user)

Every plan must end with a HiPerGator run step (module load R/4.5) and a workbook review step, consistent with Phase 165 and 166 corrected plans.
