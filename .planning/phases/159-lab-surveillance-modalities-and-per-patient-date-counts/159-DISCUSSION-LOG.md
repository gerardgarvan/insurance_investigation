# Phase 159: Lab Surveillance Modalities and Per-Patient Date Counts - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-24
**Phase:** 159-lab-surveillance-modalities-and-per-patient-date-counts
**Areas discussed:** Nesting (D-1), Sensitivity definition (D-3)

---

## Nesting (D-1)

| Option | Description | Selected |
|--------|-------------|----------|
| Nested (default) | A CMP day also counts as BMP, LFT, and KIDNEY because those analytes were all resulted | ✓ |
| Exclusive | BMP means "BMP drawn without CMP" | |

**User's choice:** Nested
**Notes:** The question the team is asking is "were these labs checked," not "which order set was used." Under nesting, a CMP day also counts as BMP, LFT and KIDNEY because those analytes were all resulted. The per-patient counts read naturally: a patient with 12 CMPs has at least 12 BMP-level checks. The exclusive version would show that patient with 0 BMPs, which misleads anyone reading the BMP column alone.

---

## Sensitivity Definition (D-3)

| Option | Description | Selected |
|--------|-------------|----------|
| Any single analyte (default) | One analyte result on the day = sensitivity event | |
| Partial panel threshold | Minimum analyte count per modality, stored in codeset as `min_analyte_count` | ✓ |

**User's choice:** Partial panel threshold — overriding the brief's default
**Notes:** Under "any single analyte," one glucose result is a BMP event and a CMP event simultaneously. Since almost every lab draw includes glucose or creatinine, the `_any` columns for BMP and CMP would collapse to "any chemistry drawn." The partial-panel thresholds chosen:
- BMP: ≥4 of 8
- CMP: ≥7 of 14
- LFT: ≥2 of 4
- Lipid: ≥2 of 3
- KIDNEY: eGFR, or cystatin C without creatinine, or a urine kidney marker (which also settles D-5)

This requires extending the match type from `analyte_any_same_day` to `analyte_min_same_day` with a `min_analyte_count` column in the codeset.

---

## Claude's Discretion

- QC near-miss reporting format for partial-panel days.
- Whether `min_analyte_count` lives on the rule row or a separate sub-table (rule row preferred for simplicity).

## Deferred Ideas

- Converting Phase 158's CBC rule to `analyte_min_same_day` — natural follow-on.
- Result-value / abnormal-lab flags.
- Guideline adherence analysis.

## Defaults Accepted (not discussed)

- **D-2:** Core analytes per modality as specified in the brief.
- **D-4:** Specimen allowlist (Ser/Plas/Bld variants; exclude BldA, BldC, Urine for primary).
- **D-5:** Urine kidney markers sensitivity-tier only (subsumed into D-3 KIDNEY sensitivity rule).
- **D-6:** Deprecated LOINCs included; `loinc_status` carried in A2.
- **D-7:** Per-patient table: post-anchor primary + any only, no pre-anchor columns.
