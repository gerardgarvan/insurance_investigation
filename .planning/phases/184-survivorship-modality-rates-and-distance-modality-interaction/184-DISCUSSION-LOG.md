# Phase 184: Survivorship Modality Rates and Distance × Modality Interaction - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-15
**Phase:** 184 — Survivorship Modality Rates and Distance × Modality Interaction
**Areas discussed:** Distribution choice, Covariates, Model structure and estimand, Workbook and output structure

---

## Distribution Choice

| Option | Description | Selected |
|--------|-------------|----------|
| Empirical ratio (var/mean) | If any modality ratio > 3 → NB primary | |
| Formal dispersion test (AER/MASS) | Test stat and p-value in KEY | |
| Always negative-binomial | NB primary, Poisson sensitivity | |
| Poisson GEE + robust SEs (user) | Robust SEs handle overdispersion; matches Phase 179 | ✓ |

**User's choice:** Poisson GEE with robust (sandwich) SEs as primary — decided in advance, not based on results. Overdispersion reported as diagnostic (Pearson χ²/df), not decision rule. NB GEE as sensitivity.

---

## Covariates

*Decision captured in the same response as distribution choice.*

| Aspect | Decision |
|--------|----------|
| Primary model terms | `far + modality + far:modality + year_index_cat` |
| Adjusted sensitivity | Add `age_at_anchor + sex` (same sources as R/183) |
| Payer | Excluded — no usable source (dropped in Phase 183) |
| Mediators | Excluded (encounter counts, single_source_care_post would absorb distance effect) |

---

## Model Structure and Estimand

| Option | Description | Selected |
|--------|-------------|----------|
| Patient × modality × year (long) | Count per year, offset = log(person_years) per year | ✓ |
| Patient × modality (collapsed) | Total count across all years | |
| Patient (wide, modality as column) | Multivariate model | |

**User's choice:** One row per patient × modality × year. Phase 179 cohort pin (20261015 RDS), complete-case on exposure (exclude 614 missing). `far` from Phase 179 RDS. Primary: years 2+. Reference modality: CBC. Working correlation: independence with robust SEs.

**Additional notes:**
- Eligibility: restrict each modality to eligible patients per R/147/Phase 158–159 definitions
- Primary estimand: modality-specific RR (far vs not-far) within each modality
- Global test: joint Wald test of all `far:modality` interaction terms

---

## Workbook and Output Structure

| Option | Description | Selected |
|--------|-------------|----------|
| KEY + Rate_Table + Model_Results | 3-tab minimal workbook | |
| KEY + Rate_Table + Model_Results + Descriptives | 4-tab | |
| Separate rate workbook + model workbook | Two files | |
| 6-tab full workbook (user) | KEY, Rates, Model_Results, Interaction, Diagnostics, QC | ✓ |

**User's choice:** Single workbook with tabs: KEY → Rates → Model_Results → Interaction → Diagnostics → QC. Plus a script-generated `184-MEMO.md`.

**QC tab specifics:**
- Reproduction gate: CBC model on Phase 179 pin must reproduce "Primary: years 2+" OR within 0.005 by exact label; stop if fails
- N eligible per modality
- Suppression audit (flag modalities where >50% of cells suppressed)

---

## Claude's Discretion

None — all areas had explicit user decisions.

## Deferred Ideas

None — discussion stayed within phase scope.
