# Phase 105: Code & Overlap Verification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-15
**Phase:** 105-code-overlap-verification
**Areas discussed:** Script organization, HL+NHL overlap depth, Action outcomes, Output structure

---

## Script Organization

| Option | Description | Selected |
|--------|-------------|----------|
| One combined + one overlap | Single R script for CODE-01/02/03 (all code verification, one xlsx with 3 tabs). Separate script for OVERLAP-01. Fewer scripts, grouped by investigation type. | ✓ |
| Four separate scripts | R/33 for CODE-01, R/34 for CODE-02, R/35 for CODE-03, R/36 for OVERLAP-01. Maximum modularity, each runs independently. | |
| Two combined scripts | Same as recommended — R/33 for CODE-01+02+03 combined, R/34 for OVERLAP-01. | |

**User's choice:** One combined + one overlap (Recommended)
**Notes:** CODE-01/02/03 are small related code verification tasks that share the same investigation pattern. Combining reduces script proliferation while keeping OVERLAP-01 (a larger analytical task) separate.

---

## HL+NHL Overlap Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Temporal + same-day focus | For each dual-code patient: first HL date, first NHL date, days between, same-day flag, encounter counts per type. Summary table of patterns (same-day, <30 days, >30 days). Most directly answers 'are these real?' | ✓ |
| Full clinical context | All of temporal analysis PLUS treatment linkage (which treatments map to HL vs NHL encounters) and orphan code flagging (NHL codes with zero treatment records). Deeper but more complex. | |
| You decide | Claude picks the analysis depth that best answers the meeting note concern about dual-code data quality. | |

**User's choice:** Temporal + same-day focus (Recommended)
**Notes:** Directly addresses meeting note G4 concern — Erin's skepticism about ~4,000/8,000 dual-code patients being real. Same-day flagging and temporal pattern analysis are the most direct test of data quality.

---

## Action Outcomes

| Option | Description | Selected |
|--------|-------------|----------|
| Report only | Scripts produce xlsx findings + console recommendations. No modifications to R/00_config.R or DRUG_GROUPINGS. Changes happen in a follow-up if needed. Consistent with v3.1/3.2 investigation pattern. | ✓ |
| Report + auto-fix | Scripts report findings AND make recommended changes to R/00_config.R. More efficient but mixes investigation with implementation. | |
| Report + proposed patch | Scripts report findings and generate a 'proposed_changes.R' file with recommended config changes as commented-out code. User reviews and applies manually. | |

**User's choice:** Report only (Recommended)
**Notes:** Consistent with v3.1/v3.2 investigation pattern. Keeps investigation cleanly separated from implementation. Any config changes would be a follow-up.

---

## Output Structure

| Option | Description | Selected |
|--------|-------------|----------|
| One xlsx per script | Code verification script -> code_verification.xlsx (3 tabs: Ethna, Transplant, SCT_Codes, plus Summary). Overlap script -> hl_nhl_overlap_validation.xlsx (Summary + Patient Detail + Pattern Analysis). Two files total. | ✓ |
| One xlsx per requirement | 4 separate xlsx files. Maximum separation but more files to manage. | |
| Single combined workbook | All 4 investigations in one phase_105_verification.xlsx with 6+ tabs. Everything in one place but large and complex. | |

**User's choice:** One xlsx per script (Recommended)
**Notes:** Aligns with script organization decision — one output file per script. Two files total, each self-contained with investigation-specific tabs.

---

## Claude's Discretion

- Exact script numbers in investigation decade
- Console logging structure and verbosity
- Tab ordering and column layout within xlsx files
- Percentage columns alongside raw counts in summaries
- R/88 smoke test section structure and check count
- Specific temporal buckets for overlap pattern analysis

## Deferred Ideas

None — discussion stayed within phase scope
