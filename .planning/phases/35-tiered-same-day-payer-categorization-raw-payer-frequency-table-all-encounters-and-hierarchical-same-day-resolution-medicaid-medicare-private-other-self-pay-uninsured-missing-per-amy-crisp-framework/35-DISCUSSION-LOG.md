# Phase 35: Tiered Same-Day Payer Categorization - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-27
**Phase:** 35-tiered-same-day-payer-categorization
**Areas discussed:** Category mapping, Raw frequency table, Output structure, Pipeline integration

---

## Category Mapping

### Q1: How should raw codes map to Amy's 6 tiers?

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse + collapse (Recommended) | Apply existing map_payer_category() first, then collapse: Dual eligible→Medicaid, Other govt→Other, No payment/Self-pay→Self-pay, Unavailable+Unknown→Missing. Then apply FLM source override. Reuses tested code. | |
| Fresh mapping from xlsx | Use PayerVariable.xlsx 'New Value' column as the base mapping, then collapse its 7 categories to Amy's 6 tiers. Independent of R pipeline mapping. | |
| Direct raw-code mapping | Build a new case_when from scratch mapping raw codes directly to Amy's 6 tiers, using her explicit rules (93→Medicaid, 14→Medicaid, prefix 1→Medicare, etc.). No dependency on existing functions. | |

**User's choice:** "I want to be able to change mapping later just in case PIs change minds about mappings"
**Notes:** User prioritized configurability over code reuse. Led to D-01: tier mapping as configurable lookup at top of script.

### Q2: Where should the configurable tier mapping live?

| Option | Description | Selected |
|--------|-------------|----------|
| Top of script (Recommended) | Define TIER_MAPPING as a named list at the top of the standalone script. Easy to find and edit. Self-contained. | ✓ |
| In 00_config.R | Add TIER_MAPPING next to existing PAYER_MAPPING in the shared config. Available to all scripts but adds coupling. | |

**User's choice:** Top of script (Recommended)

### Q3: How should the 'FLM is a source' Medicaid override work?

| Option | Description | Selected |
|--------|-------------|----------|
| ENCOUNTER.SOURCE (Recommended) | If any encounter on that patient-date has ENCOUNTER.SOURCE = 'FLM', the resolved payer for that date is Medicaid. | ✓ |
| DEMOGRAPHIC.SOURCE | If the patient's home site (DEMOGRAPHIC.SOURCE) is FLM, then ALL their dates resolve to Medicaid. Broader interpretation. | |

**User's choice:** ENCOUNTER.SOURCE (Recommended)

---

## Raw Frequency Table

### Q1: What should the 'all encounters' raw frequency table look like?

| Option | Description | Selected |
|--------|-------------|----------|
| Extend Phase 34 to all ENC_TYPEs (Recommended) | Same xlsx cross-reference approach as Phase 34, but remove AV+TH filter. | |
| Simpler format per Amy's request | Just raw code + count + percentage. No xlsx cross-reference. | |
| Skip — Phase 34 is sufficient | Don't produce a separate all-encounter version. | |

**User's choice:** "give option of all encounters and just AV+TH"
**Notes:** User wants both scopes produced in the same script run. Led to D-05.

### Q2: Should this replace Phase 34's script or be a new script?

| Option | Description | Selected |
|--------|-------------|----------|
| New script does both (Recommended) | Phase 35 script produces all-encounter AND AV+TH frequency tables in one run. Phase 34's script stays untouched. | ✓ |
| Consolidate into Phase 34 script | Modify R/35_payer_code_frequency_av_th.R to also produce all-encounter output. | |

**User's choice:** New script does both (Recommended)

---

## Output Structure

### Q1: What outputs should the same-day resolution produce?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-date detail + summary (Recommended) | CSV 1: per-patient-per-date detail. CSV 2: patient-level summary. CSV 3: aggregate before vs after distribution. | ✓ |
| Patient-level only | One row per patient with modal resolved payer. | |
| Date-level detail only | One row per patient-date with resolved payer. | |

**User's choice:** Per-date detail + summary (Recommended)

### Q2: Should the same-day resolution apply to all encounters or just AV+TH?

| Option | Description | Selected |
|--------|-------------|----------|
| Both scopes (Recommended) | Run resolution on all encounters AND separately on AV+TH. | ✓ |
| All encounters only | Run on all encounter types only. | |
| AV+TH only | Restrict to ambulatory/telehealth only. | |

**User's choice:** Both scopes (Recommended)

---

## Pipeline Integration

### Q1: Standalone or pipeline modification?

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone script (Recommended) | New standalone diagnostic script. Does NOT modify R/02_harmonize_payer.R. Can be promoted later. | ✓ |
| Modify pipeline | Integrate same-day resolution directly into R/02_harmonize_payer.R. | |

**User's choice:** Standalone script (Recommended)

---

## Claude's Discretion

- Script numbering and naming
- Console summary format
- CSV naming convention
- Whether frequency + resolution are one script or two
- Sort order of detail output
- Handling of single-encounter dates

## Deferred Ideas

None — discussion stayed within phase scope.
