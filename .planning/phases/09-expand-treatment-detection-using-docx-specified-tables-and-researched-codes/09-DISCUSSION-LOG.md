# Phase 9: Expand Treatment Detection - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 09-expand-treatment-detection-using-docx-specified-tables-and-researched-codes
**Areas discussed:** Treatment type scope, Data source expansion, External code lists, Output structure

---

## Treatment Type Scope

### Q1: Which treatment categories to implement?

| Option | Description | Selected |
|--------|-------------|----------|
| Expand chemo/radiation/SCT detection | Keep same 3 types, add all missing docx sources | |
| Add surgery as new type | New HAD_SURGERY + PAYER_AT_SURGERY, requires xlsx | |
| Add ancillary therapy | New HAD_ANCILLARY, requires SEER*Rx mapping | |
| Add treatment intensity | Derived ordinal variable from treatment combination | |

**User's choice:** Expand chemo/radiation/SCT detection only
**Notes:** Surgery, ancillary therapy, and treatment intensity deferred to future phases.

### Q2: Should expanded sources feed into payer anchoring?

| Option | Description | Selected |
|--------|-------------|----------|
| Both flags and payer anchoring | Expand has_*() and compute_payer_at_*() | |
| HAD_* flags only | Only expand treatment identification | |

**User's choice:** Both flags and payer anchoring (Recommended)

### Q3: Code range approach?

| Option | Description | Selected |
|--------|-------------|----------|
| Use exact docx ranges | Trust docx as authoritative for CPT ranges | |
| Research appropriate subsets | Docx ranges may be too broad (e.g., 70010-79999) | |
| Docx ranges with logging | Implement exact ranges but log matches | |

**User's choice:** Research appropriate subsets
**Notes:** 70010-79999 for radiation includes diagnostic radiology, too broad for treatment-only detection.

---

## Data Source Expansion

### Q4: New PCORnet tables?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add both | DISPENSING and MED_ADMIN exist on HiPerGator | |
| Not sure | Need to check HiPerGator | |
| Skip new tables | Only expand within already-loaded tables | |

**User's choice:** Yes, add both

### Q5: ENCOUNTER DRG and DIAGNOSIS treatment codes?

| Option | Description | Selected |
|--------|-------------|----------|
| Add both DRG and DIAGNOSIS sources | Maximum coverage per docx | |
| Add DIAGNOSIS only | DRG may be unreliable across sites | |
| Skip both | Stick with procedure and prescription sources | |

**User's choice:** Add both DRG and DIAGNOSIS sources (Recommended)

### Q6: Revenue codes (PX_TYPE=RE)?

| Option | Description | Selected |
|--------|-------------|----------|
| Add revenue codes | Include PX_TYPE='RE' in PROCEDURES | |
| Skip revenue codes | May not be present in extract | |

**User's choice:** Add revenue codes (Recommended)

---

## External Code Lists

### Q7: xlsx file availability?

| Option | Description | Selected |
|--------|-------------|----------|
| Have PCS codes xlsx | PCS Codes Cancer Tx.xlsx available | |
| Have all xlsx files | All referenced xlsx files available | |
| Don't have them | Use researcher to identify codes instead | |
| Use docx text + research | Docx text + research for missing codes | |

**User's choice:** Don't have them

### Q8: How to handle missing xlsx files?

| Option | Description | Selected |
|--------|-------------|----------|
| Research ICD-10-PCS + use docx DRGs | DRGs from docx text, research PCS codes | |
| Research everything | Research all code lists from scratch | |
| Docx text only | Only codes explicitly in docx text | |

**User's choice:** Research ICD-10-PCS + use docx DRGs (Recommended)

### Q9: NDC mapping approach?

| Option | Description | Selected |
|--------|-------------|----------|
| Research NDC codes for HL drugs | Identify specific NDCs for known agents | |
| Skip NDC-based detection | Don't use DISPENSING/MED_ADMIN NDC | |
| Use RXNORM only (no NDC) | Match RXNORM_CUI in MED_ADMIN, skip NDC | |

**User's choice:** Use RXNORM only (no NDC)
**Notes:** Avoids need for SEER*Rx NDC-to-category mapping file.

---

## Output Structure

### Q10: Code organization approach?

| Option | Description | Selected |
|--------|-------------|----------|
| Update existing functions | Modify has_*() and compute_payer_at_*() in place | |
| New expanded functions | has_chemo_expanded() alongside originals | |
| Config-driven toggle | CONFIG flag to switch narrow/broad detection | |

**User's choice:** Update existing functions (Recommended)

### Q11: Source contribution logging?

| Option | Description | Selected |
|--------|-------------|----------|
| Summary counts per source | Log aggregate counts per source type | |
| Per-patient source tracking | Add CHEMO_SOURCE columns per patient | |
| No source logging | Just update counts | |

**User's choice:** Summary counts per source (Recommended)

### Q12: Col_types for new tables?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, full col_types | Match existing table pattern | |
| Minimal load | Only specify types for used columns | |

**User's choice:** Yes, full col_types (Recommended)

---

## Claude's Discretion

- Exact col_types for DISPENSING and MED_ADMIN
- Internal refactoring of treatment functions
- Date column handling in new tables
- Code list organization in TREATMENT_CODES
- Order of source checking

## Deferred Ideas

- Surgery treatment type -- requires ComprehensiveSurgeryCodes.xlsx
- Ancillary therapy -- requires SEER*Rx NDC mapping
- Treatment Intensity variable -- depends on surgery
- NDC-based detection -- pending SEER*Rx file
- Multimodal treatment flag -- future phase
