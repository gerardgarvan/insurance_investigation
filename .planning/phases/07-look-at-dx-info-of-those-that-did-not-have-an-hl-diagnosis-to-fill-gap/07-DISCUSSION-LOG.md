# Phase 7: Dx Info of Non-HL Patients - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 07-look-at-dx-info-of-those-that-did-not-have-an-hl-diagnosis-to-fill-gap
**Areas discussed:** Diagnosis exploration scope, Gap-filling strategy, Output and reporting, Pipeline impact

---

## Diagnosis exploration scope

### Q1: How broadly should we look at diagnoses?

| Option | Description | Selected |
|--------|-------------|----------|
| All diagnoses | Pull every DX code for these 19 patients from the DIAGNOSIS table | |
| Lymphoma-adjacent only | Focus on C81-C96 and 200-208 hematologic malignancy codes | |
| Both (Recommended) | Full dx dump PLUS focused lymphoma/cancer summary | ✓ |

**User's choice:** Both (Recommended)
**Notes:** Full picture for context plus focused summary for actionable findings.

### Q2: Check other tables beyond DIAGNOSIS?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, full profile | Encounter counts, procedures, prescriptions, enrollment | |
| DIAGNOSIS + ENROLLMENT only | Dx codes plus enrollment info | |
| Just DIAGNOSIS | Keep it focused on dx info | |

**User's choice:** Other — "diagnosis enrollment and the tumor tables"
**Notes:** User wants DIAGNOSIS, ENROLLMENT, and TUMOR_REGISTRY tables specifically (not PROCEDURES or PRESCRIBING).

### Q3: Stratify by site?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, by site (Recommended) | Show which sites the 19 come from, dx patterns by partner | ✓ |
| No, aggregate only | Combined picture across all sites | |

**User's choice:** Yes, by site (Recommended)

---

## Gap-filling strategy

### Q1: What to do if lymphoma-adjacent codes found?

| Option | Description | Selected |
|--------|-------------|----------|
| Document only | Report but don't change identification logic | |
| Expand if clinically justified | Flag for review, optionally expand identification | |
| You decide (Recommended) | Claude reviews actual codes and recommends | ✓ |

**User's choice:** You decide (Recommended)
**Notes:** Claude has discretion to recommend expansion based on clinical coding conventions.

### Q2: Patients with zero diagnosis records?

| Option | Description | Selected |
|--------|-------------|----------|
| Data quality flag | Mark as 'No DIAGNOSIS records' | |
| Investigate further | Cross-reference with ENCOUNTER table | |
| Both (Recommended) | Flag AND cross-reference with enrollment/encounters | ✓ |

**User's choice:** Both (Recommended)

---

## Output and reporting

### Q1: Where should analysis live?

| Option | Description | Selected |
|--------|-------------|----------|
| New script 09_dx_gap_analysis.R | Standalone focused investigation | |
| Add section to 07_diagnostics.R | Extend existing diagnostics | |
| New script (Recommended) | 09_dx_gap_analysis.R standalone — 07 already large | ✓ |

**User's choice:** New script (Recommended)

### Q2: What CSVs to produce?

| Option | Description | Selected |
|--------|-------------|----------|
| Single comprehensive CSV | One file with everything | |
| Multiple focused CSVs (Recommended) | Separate: all dx, lymphoma codes, patient summary | ✓ |
| Console summary only | No CSV files | |

**User's choice:** Multiple focused CSVs (Recommended)

---

## Pipeline impact

### Q1: Update pipeline and rebuild if findings justify it?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, update and rebuild | Always update and rebuild if justified | |
| Report only, rebuild later | Defer all pipeline changes | |
| Conditional (Recommended) | Clear-cut findings → update; ambiguous → report only | ✓ |

**User's choice:** Conditional (Recommended)

### Q2: Script dependency model?

| Option | Description | Selected |
|--------|-------------|----------|
| Depend on pipeline output (Recommended) | Read excluded_no_hl_evidence.csv | ✓ |
| Independent identification | Re-derive Neither patients from scratch | |

**User's choice:** Depend on pipeline output (Recommended)

---

## Claude's Discretion

- Whether discovered codes justify expanding HL identification
- Gap classification categories
- Exact lymphoma/cancer ICD code ranges for focused filter
- Console summary format
- Whether pipeline rebuild is warranted

## Deferred Ideas

None — discussion stayed within phase scope
