# Phase 114: Investigate blank drug names and make drug_names/triggering_code_descriptions consistent with treatment reference excel - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-24
**Phase:** 114-investigate-blank-drug-names-and-make-drug-names-triggering-code-descriptions-consistent-with-treatment-reference-excel
**Areas discussed:** Blank drug names scope, Consistency target, Output structure, Pipeline modification vs report-only

---

## Blank Drug Names Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Investigate and report only | Quantify how many episodes have blank drug_names, which treatment types are affected, and characterize the gaps. Produce an audit xlsx. | |
| Investigate and fill where possible | Quantify blanks, then attempt to resolve them using RxNorm, the reference excel, or triggering code mappings. Update the pipeline. | |
| You decide | Claude determines the right approach based on what's found in the data. | |

**User's choice:** Investigate and fill where possible
**Notes:** None

### Follow-up: Fill Source

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, map from reference excel (Recommended) | Use all_codes_resolved_next_tables_v2.1.xlsx as authoritative source to fill drug_names from triggering_codes. | |
| Only use RxNorm API | Re-query RxNorm for unresolved codes. | |
| Both sources | Try reference excel first (for billing codes), then RxNorm for remaining gaps. | |

**User's choice:** "yes, and use the medication name only. don't worry about route or dosage in the description i.e., use Medication column for the chemo"
**Notes:** User specified Medication column only — no route, dosage, or full description.

---

## Consistency Target

| Option | Description | Selected |
|--------|-------------|----------|
| Treatment reference excel is authoritative (Recommended) | all_codes_resolved_next_tables_v2.1.xlsx is the canonical source. Pipeline should match it. Discrepancies = pipeline bugs to fix. | ✓ |
| Pipeline values are authoritative | RxNorm API resolutions and code_descriptions.rds are correct. Flag differences but don't change pipeline. | |
| Case-by-case review | Produce discrepancy report. User decides per-item which source to keep. | |

**User's choice:** Treatment reference excel is authoritative (Recommended)
**Notes:** None

### Follow-up: Normalization

| Option | Description | Selected |
|--------|-------------|----------|
| Exact match to Medication column | Pipeline descriptions must match the reference excel character-for-character (case-insensitive). | |
| Normalized form OK | Pipeline can use a cleaned-up version as long as the drug name is the same. | |
| You decide | Claude determines the right normalization level. | ✓ |

**User's choice:** You decide
**Notes:** None

---

## Output Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Before/after audit xlsx (Recommended) | Two-sheet xlsx: Sheet 1 = summary of blanks filled and discrepancies fixed with counts. Sheet 2 = per-code detail showing old vs new drug_name/description values. | ✓ |
| Discrepancy report only | Single xlsx listing every code where pipeline and reference excel disagree, without fixing. | |
| No separate output | Just fix the pipeline directly. No dedicated investigation file needed. | |

**User's choice:** Before/after audit xlsx (Recommended)
**Notes:** None

---

## Pipeline Modification vs Report-Only

| Option | Description | Selected |
|--------|-------------|----------|
| Modify pipeline scripts (Recommended) | Update R/27, R/42, R/26, or R/28 so drug_names and triggering_code_descriptions use the treatment reference excel as source of truth. | ✓ |
| New standalone script only | Create a new investigation script that produces the audit xlsx but doesn't touch existing pipeline scripts. | |
| Both: fix pipeline + investigation script | Modify pipeline for consistency AND produce a standalone audit xlsx documenting what changed. | |

**User's choice:** Modify pipeline scripts (Recommended)
**Notes:** None

### Follow-up: Audit Script Separation

| Option | Description | Selected |
|--------|-------------|----------|
| Separate audit script (Recommended) | A standalone script reads old and new outputs, compares them, produces the before/after xlsx. | ✓ |
| Built into modified scripts | The modified pipeline scripts log their own changes and produce the audit output as a side effect. | |

**User's choice:** Separate audit script (Recommended)
**Notes:** None

---

## Claude's Discretion

- Normalization level for drug name matching (exact vs cleaned form)
- Which specific pipeline scripts need modification
- Styled xlsx headers for audit output
- New script number assignment
- R/88 smoke test additions
- Whether to add audit script to R/39

## Deferred Ideas

None — discussion stayed within phase scope
