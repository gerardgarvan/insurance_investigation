# Phase 79: Code Investigations & New Tables - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-03
**Phase:** 79-code-investigations-new-tables
**Areas discussed:** Script numbering, New tables structure, SCT 0362 investigation, Replaced-by verification

---

## Script Numbering

| Option | Description | Selected |
|--------|-------------|----------|
| 54-56 range | R/54 = SCT 0362 investigation, R/55 = replaced-by verification, R/56 = new tables. Groups them in the cancer/codes decade near R/50-R/53. | ✓ |
| 36-38 range | R/36 = SCT 0362, R/37 = replaced-by, R/38 = new tables. Uses the sparse 30s decade. Slightly less logical grouping. | |
| 77-79 range | R/77 = SCT 0362, R/78 = replaced-by, R/79 = new tables. Uses the 70s gap. Mixes investigation scripts with visualization/output scripts. | |
| You decide | Claude picks the best numbering based on codebase patterns. | |

**User's choice:** 54-56 range (Recommended)
**Notes:** None

### Script Names

| Option | Description | Selected |
|--------|-------------|----------|
| Use these names | R/54_investigate_sct_0362.R, R/55_verify_replaced_by_codes.R, R/56_new_tables_from_groupings.R | ✓ |
| Shorter names | R/54_sct_0362.R, R/55_replaced_by_codes.R, R/56_drug_grouping_tables.R | |

**User's choice:** Use these names (Recommended)
**Notes:** None

---

## New Tables Structure

### Cancer Code Representation

| Option | Description | Selected |
|--------|-------------|----------|
| Cancer category label | Use cancer_category from treatment_episodes.rds (e.g., 'Hodgkin Lymphoma', 'NLPHL', 'Breast'). Human-readable, already computed in R/28. | |
| Raw ICD codes | Use the actual ICD-10/ICD-9 diagnosis codes linked to the encounter. More granular but harder to read. | ✓ |
| Both | Show cancer_category label AND the raw triggering diagnosis code(s) in separate columns. | |

**User's choice:** Raw ICD codes
**Notes:** None

### Cancer Code Aggregation

| Option | Description | Selected |
|--------|-------------|----------|
| One row per unique combination | E.g., 'Chemo \| C81.10;C81.12 \| 45 encounters'. Groups by treatment type + cancer code set. | ✓ |
| One row per treatment-code pair | Separate rows per cancer code. An encounter appears in multiple rows if it has multiple cancer codes. | |
| Pivoted (codes as columns) | Cancer codes become column headers, encounter counts fill the cells. Wide format. | |

**User's choice:** One row per unique combination (Recommended)
**Notes:** None

### Drug-Level Row Granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Individual treatment code | One row per unique treatment code (CPT/HCPCS/NDC). Most granular. | ✓ |
| Drug name from code_descriptions.rds | Group by resolved drug name. Multiple codes for same drug collapse into one row. | |
| Treatment code + drug name | Show both code and name per row. Keeps code-level granularity with readable labels. | |

**User's choice:** Individual treatment code (Recommended)
**Notes:** None

### Output Format

| Option | Description | Selected |
|--------|-------------|----------|
| Single xlsx with 2 sheets | One xlsx file with Sheet 1 = treatment-type summary, Sheet 2 = drug-level summary. | ✓ |
| Separate xlsx files | Two separate xlsx files, one per table. | |
| xlsx + csv | Both xlsx (for review) and csv (for downstream consumption). | |

**User's choice:** Single xlsx with 2 sheets (Recommended)
**Notes:** None

---

## SCT 0362 Investigation

### Core Clinical Question

| Option | Description | Selected |
|--------|-------------|----------|
| Co-occurring SCT codes | Check if 0362 encounters also have standard SCT CPT codes (38204-38241) or other SCT revenue codes (0815). | |
| Full encounter profile | Pull complete encounter details (all procedures, diagnoses, prescriptions) for 0362 encounters. | ✓ |
| Both | Co-occurring SCT codes as primary analysis, plus full encounter details as supplementary sheet. | |

**User's choice:** Full encounter profile
**Notes:** None

### Output Format

| Option | Description | Selected |
|--------|-------------|----------|
| xlsx with multiple sheets | Sheet 1: patient summary. Sheet 2: encounter-level detail. Sheet 3: summary statistics. | ✓ |
| Console + csv | Console diagnostics with summary stats, plus a single CSV. | |
| xlsx only (single sheet) | One flat table with encounter-level detail. | |

**User's choice:** xlsx with multiple sheets (Recommended)
**Notes:** None

### Automated Recommendation

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, automated recommendation | Script computes overlap rate and recommends: >80% = confirmed, <30% = artifact, 30-80% = manual review. | ✓ |
| No, data only | Script produces data tables only. Human interprets results. | |
| Flag in console | Print recommendation to console but don't embed in xlsx. | |

**User's choice:** Yes, automated recommendation (Recommended)
**Notes:** None

---

## Replaced-by Verification

### Source of Replaced-by Mappings

| Option | Description | Selected |
|--------|-------------|----------|
| In the xlsx | all_codes_resolved_next_tables.xlsx contains replaced-by code mappings. | ✓ |
| External source | Replaced-by mappings come from SEER tables or CMS crosswalks. | |
| Need to check | Script should first inspect xlsx structure and identify replaced-by columns/sheets. | |

**User's choice:** In the xlsx
**Notes:** None

### Verification Methodology

| Option | Description | Selected |
|--------|-------------|----------|
| Check both old and new codes exist | Pairwise: verify old code IS in code lists, new code IS also in code lists, both map to same treatment category. Flag mismatches. | ✓ |
| Chain detection only | Focus on finding replacement chains >3 steps and cycles. | |
| Cross-reference against SEER/CMS | Verify our mappings match official ICD-9 to ICD-10 crosswalk. | |

**User's choice:** Check both old and new codes exist (Recommended)
**Notes:** None

### Chain Detection

| Option | Description | Selected |
|--------|-------------|----------|
| Pairwise + chain detection | Primary: pairwise verification. Secondary: chain detection >3 steps and cycles via igraph. | ✓ |
| Pairwise only | Just verify each pair. No igraph dependency needed. | |
| You decide | Claude determines based on data. | |

**User's choice:** Pairwise + chain detection (Recommended)
**Notes:** None

### Output Format

| Option | Description | Selected |
|--------|-------------|----------|
| xlsx with verification report | Sheet 1: pairs with PASS/FAIL/MISSING. Sheet 2: chain analysis. Sheet 3: summary stats. Plus console. | ✓ |
| Console only | Print results to console. No file output. | |
| csv + console | CSV of results plus console summary. | |

**User's choice:** xlsx with verification report (Recommended)
**Notes:** None

---

## Additional Instructions

User requested: "Once you write the scripts for this phase please take a pass or two through them to make sure all of the columns, joins, functions, sources of other scripts work." Captured as D-17 in CONTEXT.md — explicit validation passes during execution.

## Claude's Discretion

- igraph installation approach (renv pattern)
- Script header comment depth (v2.0 standards)

## Deferred Ideas

None — discussion stayed within phase scope
