# PCORnet Payer Variable Investigation (R Pipeline)

## What This Is

A standalone R-based exploration pipeline that loads raw PCORnet CDM CSV files for a Hodgkin Lymphoma cohort (OneFlorida+), builds a filtered cohort using human-readable named predicates, and produces attrition waterfall and Sankey/alluvial visualizations stratified by payer type. Runs on RStudio on HiPerGator.

## Core Value

A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Load 22 PCORnet CDM CSV tables from HiPerGator with correct data types
- [ ] Harmonize payer variables into 9 categories matching the Python pipeline (Medicare, Medicaid, Dual eligible, Private, Other government, No payment/Self-pay, Other, Unavailable, Unknown)
- [ ] Implement dual-eligible detection (Medicare+Medicaid combinations)
- [ ] Build cohort filter chain using named predicates (has_*, with_*, exclude_*)
- [ ] Log N patients before and after every filter step automatically
- [ ] Identify HL patients using 149 ICD codes (77 ICD-10 C81.xx, 72 ICD-9 201.xx)
- [ ] Produce attrition waterfall chart from filter log
- [ ] Produce Sankey/alluvial showing enrollment → diagnosis date → treatment type, stratified by payer
- [ ] Handle multi-site data (OneFlorida+ partner institutions: AMS, UMI, FLM, VRT)
- [ ] Apply HIPAA small-cell suppression (counts 1-10) in outputs

### Out of Scope

- Statistical modeling / regression — exploration only for v1
- Payer × treatment initiation timing analysis — v2
- Payer × diagnosis timing analysis — v2
- Missing data audit by site and year — v2
- RMarkdown / Shiny rendering — v1 produces raw R scripts and PNG figures
- Replicating the Python pipeline's data cleaning (deduplication, consistency flags) — R pipeline loads raw CSVs and applies its own filter chain
- Publication-ready figure formatting — exploratory quality is fine

## Context

- **Existing Python pipeline** at `C:\cygwin64\home\Owner\Data loading and cleaing\` handles production-grade data loading, cleaning, and payer analysis using Python/Polars. This R project is a parallel exploration tool, not a replacement.
- **Data source**: OneFlorida+ PCORnet CDM extract (Mailhot HL cohort, extracted 2025-09-15), 22 CSV tables on HiPerGator
- **Study**: UFPTI 2405-HLX17A — investigating insurance disparities in Hodgkin Lymphoma treatment
- **PCORnet CDM tables in scope**: ENROLLMENT, DIAGNOSIS, PROCEDURES, PRESCRIBING, ENCOUNTER, DEMOGRAPHIC (primary), plus reference to DEATH, HARVEST for metadata
- **Payer logic reference**: `docs/PAYER_VARIABLES_AND_CATEGORIES.md` in the Python pipeline defines the exact 9-category mapping and dual-eligible rules to replicate
- **ICD codes**: 149 HL diagnosis codes — ICD-10 C81.00–C81.9A (77 codes) and ICD-9 201.00–201.98 (72 codes), format-adaptive (dotted and undotted)
- **Partner provenance**: Some partners are claims-only (FLM), some have mapped ICD codes (AMS, UMI), one is death-only (VRT)

## Constraints

- **Runtime environment**: RStudio on UF HiPerGator — scripts must work in that environment
- **R packages**: tidyverse ecosystem (dplyr, ggplot2, stringr, lubridate), ggalluvial for Sankey, scales, janitor, glue
- **Data access**: Raw CSVs on HiPerGator filesystem — paths configured in `R/00_config.R`
- **HIPAA compliance**: All patient counts 1-10 must be suppressed in any output
- **Code style**: Filtering logic uses named predicate functions (`has_*`, `with_*`, `exclude_*`) — no opaque one-liners
- **Payer fidelity**: Must match the Python pipeline's 9-category payer mapping exactly, including dual-eligible detection

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Standalone R (not consuming Python output) | Enables independent exploration without Python pipeline dependency | — Pending |
| Replicate exact payer logic from Python pipeline | Ensures results are comparable across both pipelines | — Pending |
| Cohort + viz only for v1 | Focus on getting the filter chain and visualizations working before adding analysis tables | — Pending |
| Named predicate functions for filtering | Readability — code should read like a clinical protocol | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-24 after initialization*
