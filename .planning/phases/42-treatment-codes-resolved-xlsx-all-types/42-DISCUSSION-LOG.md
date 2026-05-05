# Phase 42: Treatment Codes Resolved XLSX (All Types) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-04
**Phase:** 42-treatment-codes-resolved-xlsx-all-types
**Areas discussed:** Output structure, Description curation, Chemo verification, Supportive Care inclusion

---

## Output Structure

| Option | Description | Selected |
|--------|-------------|----------|
| One file per type | radiation_codes_resolved.xlsx, sct_codes_resolved.xlsx, immunotherapy_codes_resolved.xlsx — mirrors chemotherapy_codes_resolved.xlsx pattern exactly | ✓ |
| Single combined file | all_treatment_codes_resolved.xlsx with one sheet per treatment type plus a Notes sheet | |
| Both | Generate individual per-type files AND a combined all-in-one file | |

**User's choice:** One file per type (Recommended)
**Notes:** Matches existing chemotherapy_codes_resolved.xlsx convention.

---

## Description Curation

| Option | Description | Selected |
|--------|-------------|----------|
| Use API descriptions as-is | Pull 'Description' column from combined_unmatched_report.xlsx. Rename to 'Meaning' for consistency. Fast and reproducible. | ✓ |
| Manual curation needed | Descriptions need human review/editing before writing to resolved files | |
| You decide | Claude picks based on data quality | |

**User's choice:** Use API descriptions as-is (Recommended)
**Notes:** No manual curation step needed.

---

## Chemo Verification

| Option | Description | Selected |
|--------|-------------|----------|
| Cross-check counts | Confirm 203 codes match between files, flag mismatches in Records/Patients counts | ✓ |
| Full audit | Cross-check counts AND verify descriptions against CMS/RxNorm AND flag misclassifications | |
| Code-list match only | Just check code sets are identical (no count comparison) | |

**User's choice:** Cross-check counts (Recommended)
**Notes:** Verify code-list identity and count consistency between chemotherapy_codes_resolved.xlsx and combined_unmatched_report.xlsx.

---

## Supportive Care Inclusion

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, include it | Create supportive_care_codes_resolved.xlsx. Complete picture of all non-Unrelated codes. | ✓ |
| No, active treatments only | Only Radiation (12), SCT (8), Immunotherapy (27). Supportive Care is ancillary. | |
| You decide | Claude decides based on value | |

**User's choice:** Yes, include it
**Notes:** Supportive Care gets its own resolved file for completeness.

---

## Claude's Discretion

- Styling/formatting decisions (colors, fonts, column widths)
- Single script vs one-per-type organization
- Verification output format

## Deferred Ideas

None — discussion stayed within phase scope
