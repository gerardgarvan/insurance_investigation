# Phase 18: One Enrolled Person Does Not Have an HL Diagnosis Caught - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-07
**Phase:** 18-one-enrolled-person-does-not-have-an-hl-diagnosis-caught
**Areas discussed:** Root cause identification, Fix scope, Validation approach

---

## Root Cause Identification

### Q1: Patient identification method

| Option | Description | Selected |
|--------|-------------|----------|
| I have the patient ID | You know which specific patient is missing from the cohort and can share details | |
| I have pipeline output | You have console output or CSV files showing the gap but need help interpreting which patient | |
| I noticed a count mismatch | You see N patients expected vs N-1 in cohort output — need the pipeline to find who's missing | ✓ |

**User's choice:** I noticed a count mismatch
**Notes:** User sees everyone has enrollment but one person drops at the HL identification step.

### Q2: Where is the mismatch

| Option | Description | Selected |
|--------|-------------|----------|
| DEMOGRAPHIC vs cohort final | Total patients in DEMOGRAPHIC minus expected HL patients doesn't match cohort output count | |
| Enrollment vs HL-flagged | Everyone has enrollment but one person drops at the HL identification step | ✓ |
| PPTX slide vs pipeline | A PPTX slide or table shows a different count than the cohort CSV | |

**User's choice:** Enrollment vs HL-flagged

### Q3: Gap type

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, one Neither patient | The gap analysis or HL_SOURCE breakdown shows one patient as Neither who should have HL | ✓ |
| Not sure yet | You see the count discrepancy but haven't checked the HL_SOURCE breakdown or gap analysis output | |
| Different issue | The patient has enrollment but isn't showing up at all in the HL identification step for a different reason | |

**User's choice:** Yes, one Neither patient

### Q4: Gap analysis results

| Option | Description | Selected |
|--------|-------------|----------|
| Haven't run it yet | Haven't run the gap analysis script — will run it as part of this phase | |
| Has lymphoma/cancer codes | Patient has lymphoma/cancer ICD codes but not the specific HL codes in the code list | ✓ |
| Phantom or coding gap | Patient has zero diagnosis records or enrollment without any dx codes | |

**User's choice:** Has lymphoma/cancer codes

### Q5: Specific code knowledge

| Option | Description | Selected |
|--------|-------------|----------|
| C81 codes not matching | The patient has C81.xx codes that SHOULD match but don't — possibly a format or normalization issue | |
| Not sure of exact codes | You know they have lymphoma codes from the gap analysis but haven't looked at the specific codes yet | ✓ |
| Non-C81 lymphoma codes | The patient has other lymphoma codes (C82-C96, 200-208 non-201) that you believe should count as HL evidence for this cohort | |

**User's choice:** Not sure of exact codes

---

## Fix Scope

### Q6: Fix breadth

| Option | Description | Selected |
|--------|-------------|----------|
| Add the missing code(s) only (Recommended) | Add just the specific code(s) this patient has to ICD_CODES. Minimal change, targeted fix. | ✓ |
| Audit all C81 variants | Cross-reference the full ICD-10-CM C81 code tree against the code list to find any other missing variants | |
| Depends on root cause | Decide after seeing the specific codes — if it's a normalization bug, fix that; if it's a missing code, add it | |

**User's choice:** Add the missing code(s) only

### Q7: If correctly excluded

| Option | Description | Selected |
|--------|-------------|----------|
| Document and close | Confirm the exclusion is correct, update the gap analysis output/notes, no code changes needed | ✓ |
| Ask me first | Show me the specific codes and let me decide whether this patient should be included based on clinical judgment | |

**User's choice:** Document and close

---

## Validation Approach

### Q8: Verification method

| Option | Description | Selected |
|--------|-------------|----------|
| Full pipeline rerun (Recommended) | Rerun from 04_build_cohort.R to see updated HL_SOURCE breakdown and cohort count. Confirms fix + no regressions. | ✓ |
| Targeted check only | Run just the HL identification logic on this patient's data to confirm the fix, skip full pipeline | |
| Rerun + update PPTX | Full pipeline rerun AND regenerate the PPTX to reflect the updated cohort count | |

**User's choice:** Full pipeline rerun

---

## Claude's Discretion

- How to structure diagnostic script changes if a code needs to be added
- Whether to update 09_dx_gap_analysis.R with the findings
- Exact format of documentation if the exclusion is confirmed correct

## Deferred Ideas

None — discussion stayed within phase scope
