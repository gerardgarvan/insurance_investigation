# Phase 102: Single-Agent Co-Administration Analysis - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-12
**Phase:** 102-single-agent-co-administration-analysis
**Areas discussed:** Single-agent definition, Window & scope, Output structure, Script placement

---

## Single-agent Definition

### Q1: What defines 'single-agent' for this analysis?

| Option | Description | Selected |
|--------|-------------|----------|
| One code per patient-date | Group by (patient_id, treatment_date) — if only 1 chemo triggering_code appears on that date, it's single-agent. Captures fragmented billing where ABVD components are given on different days. | ✓ |
| One code per encounter | Group by ENCOUNTERID — if only 1 chemo code per encounter. More granular but encounters may split same-day visits. | |
| One drug per episode | Use R/28's n_unique_drugs at episode level — episodes with drug_count=1. Misses date-level fragmentation. | |

**User's choice:** One code per patient-date (Recommended)
**Notes:** None

### Q2: Should encounters with no resolved drug name be included?

| Option | Description | Selected |
|--------|-------------|----------|
| Include with code only | Use triggering_code as identifier when drug_name is NA — some chemo is billed via J-codes without RxNorm resolution | ✓ |
| Exclude | Only include encounters with resolved drug_names — cleaner but may miss billing-only patterns | |
| Include and flag | Include all but add a 'drug_resolved' TRUE/FALSE column so user can filter | |

**User's choice:** Include with code only (Recommended)
**Notes:** None

---

## Window & Scope

### Q3: Should encounters already classified as multi-agent regimens be included?

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude regimen-classified | Only analyze encounters NOT already assigned a regimen_label by R/28 — these are the truly 'unclassified single-agent' encounters that might be fragmented | ✓ |
| Include all | Include everything — even encounters R/28 already classified as ABVD etc. | |
| Separate sections | Analyze both with separate output sheets | |

**User's choice:** Exclude regimen-classified (Recommended)
**Notes:** None

### Q4: What treatment types should be in scope?

| Option | Description | Selected |
|--------|-------------|----------|
| Chemo-to-chemo only | Look for other Chemotherapy encounters within ±30 days — most relevant for fragmented regimen detection | ✓ |
| Chemo + Immunotherapy | Include Immunotherapy in the co-admin window — captures Nivo+AVD-like patterns | |
| All treatment types | Include Radiation, SCT, Proton too — broader but noisier | |

**User's choice:** Chemo-to-chemo only (Recommended)
**Notes:** None

---

## Output Structure

### Q5: How should the detail table identify drugs?

| Option | Description | Selected |
|--------|-------------|----------|
| Sub-category name + code | Show both human-readable sub_category_name AND triggering_code — readable for clinical review, traceable for code verification | ✓ |
| Drug name when available, code otherwise | Use drug_name from RxNorm resolution when available, fall back to triggering_code | |
| Triggering code only | Just the code — consistent but requires separate lookup | |

**User's choice:** Sub-category name + code (Recommended)
**Notes:** None

### Q6: How should co-administered drugs be represented in the detail table?

| Option | Description | Selected |
|--------|-------------|----------|
| One row per pair | Each row = (single-agent encounter, co-administered drug, days_apart). Multiple rows if multiple co-admin drugs found. | ✓ |
| Collapsed column | One row per encounter with semicolon-separated list of co-admin drugs + dates. | |
| Both sheets | Expanded pair detail on Sheet 1, collapsed summary per encounter on Sheet 2 | |

**User's choice:** One row per pair (Recommended)
**Notes:** None

### Q7: How many sheets for the output xlsx?

| Option | Description | Selected |
|--------|-------------|----------|
| 2 sheets | Sheet 1 = Co-Administration Detail, Sheet 2 = Pattern Summary. Matches COADMIN-01/02 directly. | ✓ |
| 3 sheets | Detail + Pattern Summary + Single-Agent Inventory | |
| 3 sheets with regimen cross-ref | Detail + Pattern Summary + Regimen Component Matching | |

**User's choice:** 2 sheets (Recommended)
**Notes:** None

---

## Script Placement

### Q8: Where should the co-administration analysis script go?

| Option | Description | Selected |
|--------|-------------|----------|
| R/58 new standalone | R/58_co_administration_analysis.R — follows R/57 in the drug grouping decade. | ✓ |
| R/31 new investigation | R/31_co_administration_analysis.R — follows R/30 in investigation scripts decade. | |
| Extend R/57 | Add co-administration sections to R/57 — keeps all drug grouping logic together but makes it larger. | |

**User's choice:** R/58 new standalone (Recommended)
**Notes:** None

---

## Claude's Discretion

- Column ordering in detail and summary tables
- Whether to include cancer_linked flag from Phase 101
- Sub-category name resolution approach
- Console summary messages and attrition logging
- R/88 smoke test validation section structure

## Deferred Ideas

None — discussion stayed within phase scope.
