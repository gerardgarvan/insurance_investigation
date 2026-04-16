# Phase 25: Close Gaps Between Code and OneFLQuestions/QuantAnalysisMtgNotes - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-04-15
**Phase:** 25-close-gaps-between-existing-code-and-oneflquestions-docx-and-quantanalysismtgnotes-zoomai-docx-lowest-hanging-fruit-first
**Areas discussed:** Missing insurance breakdown, DX date QA & sourcing, FLM overlap & Medicaid QA, Data quality flags

---

## Missing Insurance Breakdown

### Q1: How should the 'Missing' post-treatment insurance be broken down?

| Option | Description | Selected |
|--------|-------------|----------|
| 3-way split (Recommended) | Split into: (A) 'No Post-Treatment Encounters', (B) 'Payer Data Missing', (C) keep existing valid categories. Add as new columns to cohort CSV + update PPTX tables. | ✓ |
| 2-way split | Simpler: just 'No Post-Treatment Encounters' vs 'Missing Payer on Encounters'. | |
| Analysis-only CSV | Don't change existing PPTX/cohort. Produce standalone diagnostic CSV showing the breakdown. | |

**User's choice:** 3-way split (Recommended)
**Notes:** None

### Q2: Should the 3-way split apply to all treatment-anchored payer columns, or just post-treatment?

| Option | Description | Selected |
|--------|-------------|----------|
| All payer columns (Recommended) | Apply to POST_TREATMENT_PAYER, POST_CHEMO_PAYER, POST_RAD_PAYER, POST_SCT_PAYER, and also PAYER_AT_CHEMO, PAYER_AT_RADIATION, PAYER_AT_SCT. | ✓ |
| Post-treatment only | Only POST_TREATMENT_PAYER and the 3 post-treatment-specific columns. | |

**User's choice:** All payer columns (Recommended)
**Notes:** None

---

## DX Date QA & Sourcing

### Q3: How should DX_DATE sourcing and QA work?

| Option | Description | Selected |
|--------|-------------|----------|
| QA comparison + source switch (Recommended) | Produce QA CSV comparing DX_DATE across sources, then implement TR as primary for TR-available sites. | ✓ |
| QA comparison only | Just produce the comparison CSV, don't change DX date logic. | |
| Source switch only | Implement TR-first logic without QA comparison. | |

**User's choice:** QA comparison + source switch (Recommended)
**Notes:** None

### Q4: When tumor registry DX_DATE differs from DIAGNOSIS table DX_DATE, what should the cohort output show?

| Option | Description | Selected |
|--------|-------------|----------|
| Both + source flag (Recommended) | Add DX_DATE_TR, DX_DATE_DIAG, DX_DATE_SOURCE columns. FIRST_DX_DATE uses TR when available, DIAG as fallback. | ✓ |
| Just the resolved date | Replace FIRST_DX_DATE with resolved date, no separate source columns. | |
| You decide | Claude's discretion on column structure. | |

**User's choice:** Both + source flag (Recommended)
**Notes:** None

---

## FLM Overlap & Medicaid QA

### Q5: How should the FLM claims vs EHR overlap analysis work?

| Option | Description | Selected |
|--------|-------------|----------|
| Overlap diagnostic script (Recommended) | New standalone script: for patients with BOTH FLM + site EHR encounters, compare payer completeness, encounter volume, and date coverage. | ✓ |
| Extend Phase 20/22 scripts | Add overlap analysis as new section in existing R/21_all_site_duplicate_dates.R. | |
| You decide | Claude's discretion on placement. | |

**User's choice:** Overlap diagnostic script (Recommended)
**Notes:** None

### Q6: For the Medicaid QA check, what should it produce?

| Option | Description | Selected |
|--------|-------------|----------|
| Diagnostic CSV (Recommended) | For Medicaid-payer patients without treatment, classify FIRST_DX_DATE vs enrollment window. | ✓ |
| Add to FLM overlap script | Combine into the FLM overlap script as a separate section. | |
| You decide | Claude's discretion. | |

**User's choice:** Diagnostic CSV (Recommended)
**Notes:** None

---

## Data Quality Flags

### Q7: How should impossible enrollment dates be handled?

| Option | Description | Selected |
|--------|-------------|----------|
| Flag + filter (Recommended) | Enrollment dates > today + 1 year flagged ENR_DATE_VALID = FALSE, logged, written to diagnostic CSV, set to NA. | ✓ |
| Just document | Note the issue in diagnostic output but don't filter. | |
| You decide | Claude's discretion on approach. | |

**User's choice:** Flag + filter (Recommended)
**Notes:** None

### Q8: What kind of sensitivity analysis for missing payer data?

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude-FLM-claims run (Recommended) | Key summary tables with all data vs FLM-claims excluded, side-by-side CSVs. | ✓ |
| Multiple restriction scenarios | 3-4 scenarios: all data, exclude FLM, exclude high-missing sites, EHR-only. | |
| Skip for now | Defer to separate phase. | |

**User's choice:** Exclude-FLM-claims run (Recommended)
**Notes:** None

---

## Claude's Discretion

- Script numbering and naming for new diagnostic scripts
- Internal implementation details for 3-way payer split logic
- Column ordering in CSV outputs
- Whether to combine smaller analyses into fewer scripts

## Deferred Ideas

None -- discussion stayed within phase scope
