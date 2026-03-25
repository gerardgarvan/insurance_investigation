# Phase 8: Insurance Mode Around Treatment Types - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 08-add-insurance-mode-around-three-treatment-types-chemo-radiation-stem-cell-from-procedures-tables-with-plus-minus-30-days-window
**Areas discussed:** Treatment date source, Window anchor point, Output structure, No-match handling

---

## Treatment Date Source

### Q1: Which treatment date sources for anchoring the ±30 day window?

| Option | Description | Selected |
|--------|-------------|----------|
| PROCEDURES only | Use PX_DATE from PROCEDURES table only (chemo HCPCS, radiation CPT, SCT CPT codes). Matches user's request — "from procedures tables". | ✓ |
| PROCEDURES + TUMOR_REGISTRY | Also include TR dates (DT_CHEMO, DT_RAD, DT_HTE, CHEMO_START_DATE_SUMMARY). More anchor points but mixes sources. | |
| TUMOR_REGISTRY only | Use only TR treatment dates. Simpler but limited — not all patients have TR records. | |

**User's choice:** PROCEDURES only
**Notes:** Matches user's original request to use "procedures tables"

### Q2: Should we also check ICD-9 and ICD-10-PCS procedure codes?

| Option | Description | Selected |
|--------|-------------|----------|
| HCPCS/CPT only | Stick with PX_TYPE == "CH" matching existing TREATMENT_CODES config | |
| All procedure code types | Also check ICD-9-CM and ICD-10-PCS procedure codes. Would need to add ICD procedure code lists to config. | ✓ |

**User's choice:** All procedure code types
**Notes:** Will need new ICD-9-CM and ICD-10-PCS procedure code lists for chemo, radiation, SCT in 00_config.R

### Q3: Should PRESCRIBING table dates also anchor the chemo window?

| Option | Description | Selected |
|--------|-------------|----------|
| PROCEDURES only | Only use PX_DATE from PROCEDURES for the window anchor | |
| Include PRESCRIBING dates for chemo | Also anchor on RX_ORDER_DATE when RXNORM_CUI matches chemo codes. More anchor points for chemo. | ✓ |

**User's choice:** Include PRESCRIBING dates for chemo
**Notes:** Chemo gets additional date source from prescribing; radiation and SCT stay PROCEDURES-only

---

## Window Anchor Point

### Q1: First procedure date or all procedure dates?

| Option | Description | Selected |
|--------|-------------|----------|
| First procedure date | Find earliest PX_DATE per patient per treatment type. Compute payer mode within ±30 days of that date. Mirrors PAYER_CATEGORY_AT_FIRST_DX pattern. | ✓ |
| All procedure dates | Pool encounters within ±30 days of ANY treatment procedure for that type. More data but noisier. | |
| Each procedure separately | Compute payer at each individual procedure date, then take mode across all results. Most granular but complex. | |

**User's choice:** First procedure date
**Notes:** Consistent with existing PAYER_CATEGORY_AT_FIRST_DX approach

### Q2: Should first treatment dates be captured as output columns?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, include dates | Add FIRST_CHEMO_DATE, FIRST_RADIATION_DATE, FIRST_SCT_DATE columns alongside payer columns | ✓ |
| No, payer only | Only output the payer mode columns | |

**User's choice:** Yes, include dates
**Notes:** Useful for time-to-treatment analysis later

---

## Output Structure

### Q1: How to integrate treatment payer results?

| Option | Description | Selected |
|--------|-------------|----------|
| New columns on hl_cohort | Add columns directly to existing hl_cohort in 04_build_cohort.R. Single output file. | ✓ |
| Separate analysis script + CSV | New standalone script writing separate CSV. Doesn't modify existing pipeline. | |
| Both — columns + detail CSV | Add summary columns to hl_cohort AND write separate detail CSV. | |

**User's choice:** New columns on hl_cohort
**Notes:** Keeps all patient-level data in one place

### Q2: Script organization?

| Option | Description | Selected |
|--------|-------------|----------|
| New script sourced by build_cohort | Create 10_treatment_payer.R with functions, source in 04_build_cohort.R. Clean separation. | ✓ |
| Inline in 04_build_cohort.R | Add logic directly into Section 6 of 04_build_cohort.R | |

**User's choice:** New script sourced by build_cohort
**Notes:** Clean separation, consistent with how other utility scripts are organized

### Q3: Column naming convention?

| Option | Description | Selected |
|--------|-------------|----------|
| PAYER_AT_CHEMO / PAYER_AT_RADIATION / PAYER_AT_SCT | Matches existing PAYER_CATEGORY_AT_FIRST_DX naming pattern | ✓ |
| PAYER_MODE_CHEMO / PAYER_MODE_RADIATION / PAYER_MODE_SCT | Emphasizes statistical mode. More precise but different naming. | |

**User's choice:** PAYER_AT_* pattern
**Notes:** Consistency with existing column naming

---

## No-Match Handling

### Q1: What to do when no encounters found in ±30 day window?

| Option | Description | Selected |
|--------|-------------|----------|
| NA | Leave as NA — honest about missing data. Consistent with PAYER_CATEGORY_AT_FIRST_DX. | ✓ |
| Fall back to overall mode | Use PAYER_CATEGORY_PRIMARY as fallback. Fills gaps but may not reflect insurance at treatment time. | |
| Widen window | Try ±60, then ±90 days. Adaptive but complex. | |

**User's choice:** NA
**Notes:** Consistent with existing pipeline approach

### Q2: Should the script log match/no-match counts?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, log counts | Print summary with matched vs NA counts per treatment type | ✓ |
| No extra logging | Standard NA handling without special reporting | |

**User's choice:** Yes, log counts
**Notes:** Consistent with existing pipeline logging style

---

## Claude's Discretion

- ICD-9-CM and ICD-10-PCS procedure code selection
- Internal function structure within 10_treatment_payer.R
- Exact placement of source() call and column joins in 04_build_cohort.R
- Whether to reuse existing encounters object or re-query

## Deferred Ideas

None — discussion stayed within phase scope
