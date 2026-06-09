# Phase 94: Make Proton Therapy a Distinct Category from Radiation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-09
**Phase:** 94-make-proton-therapy-a-distinct-category-from-radiation
**Areas discussed:** Category naming, Detection code scope, Downstream output handling, Aggregation behavior

---

## Category Naming

| Option | Description | Selected |
|--------|-------------|----------|
| Proton | Short and parallel with existing names (Chemotherapy, Radiation, SCT, Immunotherapy). Matches the concise naming convention. | |
| Proton Therapy | More descriptive, distinguishes from the physics concept. Slightly longer in tables and labels. | ✓ |
| Proton Beam | Most specific — matches the CODE_DESCRIPTIONS entries ('Proton Beam (Simple)' etc). May be redundant in clinical context. | |

**User's choice:** Proton Therapy
**Notes:** None

---

## Detection Code Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Full split (Recommended) | Create TREATMENT_CODES$proton_cpt, add has_proton() predicate in R/10, detect proton episodes separately in R/26. Complete separation at all pipeline layers. | ✓ |
| DRUG_GROUPINGS only | Remap 4 codes in DRUG_GROUPINGS but leave TREATMENT_CODES$radiation_cpt unchanged. Proton episodes get categorized post-detection. Simpler change but cohort flag still says 'has_radiation' for proton patients. | |
| You decide | Claude picks the approach that best fits the pipeline architecture. | |

**User's choice:** Full split (Recommended)
**Notes:** None

---

## Downstream Output Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Full treatment (Recommended) | Own xlsx sheet in treatment reports, own Gantt color, own smoke test section, own row in summary tables. Treated identically to the other 4 categories. | ✓ |
| Minimal — just the label | Let TREATMENT_TYPES loops handle it automatically. No new xlsx sheet, no custom color (use a default), skip dedicated smoke test. Fastest to implement. | |
| You decide | Claude picks based on how many proton episodes exist in the data. | |

**User's choice:** Full treatment (Recommended)
**Notes:** None

---

## Aggregation Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone only | Proton Therapy appears as its own row, Radiation appears as its own row (now excluding proton). Clean and simple. No combined row. | ✓ |
| Standalone + combined | Both individual rows (Radiation, Proton Therapy) plus a 'Radiation (All)' combined row. Useful for comparing against prior outputs that lumped them together. | |
| You decide | Claude picks based on whether combined rows add confusion vs value. | |

**User's choice:** Standalone only
**Notes:** None

---

## Claude's Discretion

- Exact Gantt color choice for Proton Therapy
- Order within TREATMENT_TYPES
- CODE_SUBCATEGORY_MAP handling
- ICD-10-PCS proton modality qualifier handling
- Gap threshold inheritance for proton episodes

## Deferred Ideas

None
