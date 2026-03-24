# Project Research Summary

**Project:** PCORnet CDM Payer Analysis Pipeline (R)
**Domain:** Healthcare Data Analysis — Multi-site Clinical Research Network
**Researched:** 2026-03-24
**Confidence:** MEDIUM-HIGH

## Executive Summary

This project is a **PCORnet Common Data Model (CDM) cohort-building and payer analysis pipeline** implemented in R for the University of Florida HiPerGator HPC environment. Expert practitioners in this domain build pipelines using tidyverse-based sequential numbered scripts with explicit attrition logging, named filter predicates, and multi-site data harmonization. The analysis focuses on Hodgkin Lymphoma patients within the OneFlorida+ network, investigating insurance disparities across 4 partner sites with heterogeneous data models (claims-only, EHR-mapped, and death-only sources).

The recommended approach prioritizes **readability over raw performance** using tidyverse/dplyr over data.table to ensure "human-readable named predicates" that read like clinical protocols. The core technical challenge is **payer harmonization with temporal dual-eligible detection** — identifying patients simultaneously enrolled in Medicare and Medicaid via overlapping date ranges — combined with robust ICD code matching that handles both dotted (C81.10) and undotted (C8110) formats across ICD-9 and ICD-10 codes. Visualization centers on attrition waterfall charts and payer-stratified Sankey diagrams showing patient flow from enrollment through diagnosis to treatment.

Key risks include (1) **dual-eligible detection failures** from naive payer assignment without temporal overlap logic, undercounting this critical population by 50-80%, (2) **ICD code format mismatches** causing 30-50% diagnostic cohort loss, (3) **date parsing failures** from multi-format SAS exports, and (4) **HIPAA violations** from incomplete small-cell suppression. Mitigation requires explicit temporal logic with lubridate date intervals, normalized ICD code matching with both formats, multi-order date parsing, and secondary suppression to prevent back-calculation of suppressed cells.

## Key Findings

### Recommended Stack

**Core approach:** tidyverse-based pipeline for readability (dplyr 1.2.0+, ggplot2 4.0.1+, vroom 1.7.0+ for CSV loading) with automatic attrition logging via tidylog 1.1.0. Use renv 1.1.4+ for reproducible package management on HiPerGator's SLURM environment. Reject data.table despite 10-50x performance advantage due to opaque syntax conflicting with "named predicate" requirement.

**Core technologies:**
- **R 4.4.2 + tidyverse 2.0.0+**: Base framework — HiPerGator standard, prioritizes code readability for clinical protocol documentation
- **vroom 1.7.0+**: Fast CSV loading — 1.23 GB/sec lazy loading, 10-100x faster than base R while maintaining tidyverse syntax compatibility
- **tidylog 1.1.0**: Automatic attrition logging — wraps dplyr to print N rows added/removed at each step, zero manual logging code needed
- **ggalluvial 0.12.5**: Sankey/alluvial diagrams — standard R package for payer-stratified patient flow visualization
- **lubridate 1.9.3+**: Date/time operations — critical for enrollment overlap detection, diagnosis timing, dual-eligible identification
- **here 1.0.2**: Path management — project-relative paths that work in both RStudio and SLURM jobs, avoids hard-coded paths

**Rejected alternatives:**
- **data.table**: 10-50x faster but `DT[i, j, by]` syntax conflicts with readability requirement
- **arrow/parquet**: 5-10x faster than CSV but input format is CSV; conversion overhead not justified for v1

### Expected Features

**Must have (table stakes):**
- **PCORnet CDM table loading** — 22 CSV tables with correct data types (dates, IDs, coded values); foundation for all analysis
- **ICD code matching (ICD-9 + ICD-10)** — both historical (ICD-9 201.xx) and current (ICD-10 C81.xx) for 149 HL codes; handles dotted/undotted formats
- **Named filter predicates** — `has_diagnosis()`, `with_enrollment()`, `exclude_missing_values()` functions that read like clinical protocol
- **Attrition logging** — N before/after for every filter operation; CONSORT diagram requirement
- **Attrition waterfall visualization** — vertical bar chart showing progressive cohort reduction through exclusion criteria
- **HIPAA small-cell suppression** — counts 1-10 must be suppressed with secondary suppression to prevent back-calculation
- **Multi-site data handling** — preserve site ID through pipeline to identify partner-specific data quality patterns
- **Payer harmonization (9-category)** — Medicare, Medicaid, Dual-eligible, Private, Other government, No payment/Self-pay, Other, Unavailable, Unknown
- **Dual-eligible detection** — time-aware logic identifying overlapping Medicare + Medicaid enrollment periods

**Should have (competitive differentiators):**
- **Sankey/alluvial visualization stratified by payer** — patient flow (enrollment → diagnosis → treatment) colored by payer category reveals insurance-driven pathway differences
- **Filter chain provenance tracking** — records which predicates applied in which order for reproducible audit trail
- **Site-level data quality reporting** — per-site completeness summary identifies bias sources in multi-site data
- **ICD code version metadata** — track which codes are ICD-9 vs ICD-10 to enable sensitivity analysis of temporal bias
- **Configuration-driven paths** — `00_config.R` with environment variables enables replication across institutions

**Defer (v2+):**
- **Statistical modeling/regression** — build validated cohort and exploratory visualizations first
- **Treatment timing windows** — days from diagnosis to first treatment; requires additional temporal logic
- **RMarkdown reports** — automate after analysis stabilizes; raw R scripts sufficient for v1
- **Site × year missing data audit** — comprehensive QA heatmap deferred until baseline findings established

### Architecture Approach

PCORnet CDM analysis pipelines follow a **layered sequential pipeline architecture** where data flows through numbered stages (00_config.R → 01_load → 02_harmonize → 03_predicates → 04_build_cohort → 05_waterfall → 06_sankey). Each layer transforms or filters the dataset with automatic logging. The architecture prioritizes transparency (every operation logged), reproducibility (same input → same output), and regulatory compliance (HIPAA suppression layer wraps all outputs). Named predicate functions encapsulate filtering logic into reusable, testable components that compose into documented cohort definitions.

**Major components:**
1. **Config** (`00_config.R`) — defines file paths, ICD code lists (149 HL codes), payer mapping rules, HIPAA thresholds; sourced by all other scripts
2. **Loader** (`01_load_pcornet.R`) — reads 22 PCORnet CSV tables with explicit col_types specification to prevent date parsing failures; applies multi-format date parsing with lubridate
3. **Harmonizer** (`02_harmonize_payer.R`) — maps raw PAYER_TYPE codes to 9 standard categories; implements temporal overlap detection for dual-eligible (Medicare + Medicaid simultaneous enrollment)
4. **Cohort Constructor** (`03_predicates.R` + `04_build_cohort.R`) — defines named predicate functions (`has_hodgkin_diagnosis()`, `with_enrollment_period()`) and applies filter chain with attrition logging at each step
5. **Attrition Logger** (`utils_attrition.R`) — captures N before/after each filter step; accumulates into data frame consumed by waterfall visualization
6. **Visualizers** (`05_waterfall.R`, `06_sankey.R`) — ggplot2-based charts with small-cell suppression applied before plotting
7. **Suppression Layer** (`utils_suppression.R`) — wraps all output generation to replace counts 1-10 with "<11"; implements secondary suppression to prevent back-calculation

### Critical Pitfalls

1. **Naive payer assignment without temporal overlap detection** — Dual-eligible patients (Medicare + Medicaid simultaneously) miscategorized as single-payer, undercounting this vulnerable population by 50-80%. **Prevention:** Implement lubridate interval-based overlap detection; validate dual-eligible count is 10-20% of Medicare + Medicaid combined; prioritize dual-eligible category in 9-way hierarchy.

2. **ICD code format mismatches** — PCORnet sites use inconsistent formats (dotted "C81.10", undotted "C8110", trailing zeros "C81.1"), causing 30-50% diagnostic cohort loss with naive string matching. **Prevention:** Normalize ALL DX codes to undotted uppercase format (`str_remove_all(DX, "\\.")`) during data load; normalize 149-code reference list identically; test with both formats.

3. **Date parsing failures from multi-format SAS exports** — ENR_START_DATE, DX_DATE arrive in DATE9 ("01JAN2020"), DATETIME ("01JAN2020:00:00:00"), YYYYMMDD (20200101), Excel serial (43831) formats; readr auto-detection fails 20% of time. **Prevention:** Never rely on auto-detection — use `col_character()` initially, then `parse_date_time(orders = c("dmy", "ymd", "mdy", "dmy HMS"))` with NA rate validation < 5%.

4. **HIPAA small-cell suppression without secondary suppression** — Primary suppression (hide 1-10 counts) but no secondary suppression enables back-calculation from marginal totals, direct HIPAA violation. **Prevention:** For every suppressed cell, suppress 2-3 additional cells in same row/column; validate that no suppressed value is recoverable by subtraction from visible totals.

5. **Enrollment gaps misinterpreted as "uninsured"** — PCORnet ENROLLMENT represents "periods where care is observable," not insurance coverage; gaps can mean out-of-network care, partner doesn't capture uninsured, or data quality issue. **Prevention:** Create separate "Unknown/Missing enrollment" category distinct from "No payment/Self-pay"; profile gap rates by partner (FLM claims-only has expected gaps, VRT death-only has all gaps).

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Foundation & Data Loading
**Rationale:** Configuration and data loading with correct data types must precede all analysis. Date parsing failures and ICD format mismatches are show-stoppers that require early detection. Utilities for attrition logging and suppression are foundational infrastructure used by all downstream phases.

**Delivers:**
- `00_config.R` with paths, ICD code lists, payer mappings
- `01_load_pcornet.R` loading 22 CSV tables with explicit col_types
- Multi-format date parser handling SAS DATE9/DATETIME/YYYYMMDD/Excel formats
- `utils_attrition.R` with `init_attrition_log()` and `log_attrition()` functions
- `utils_suppression.R` with primary and secondary suppression functions

**Addresses (from FEATURES.md):**
- PCORnet CDM table loading (table stakes)
- Data type enforcement (table stakes)
- Configuration-driven paths (differentiator)

**Avoids (from PITFALLS.md):**
- Pitfall 3: Date parsing failures from multi-format SAS exports
- Hardcoded paths breaking on HiPerGator vs local environments

**Research flag:** Standard patterns — CSV loading with readr/vroom and config management are well-documented. No phase research needed.

---

### Phase 2: Payer Harmonization & Dual-Eligible Detection
**Rationale:** Payer harmonization is the critical path item and core research question. Dual-eligible detection requires complex temporal overlap logic that's easy to get wrong. Must validate against Python pipeline reference implementation before proceeding to cohort building. This phase has highest technical risk and needs early validation.

**Delivers:**
- `02_harmonize_payer.R` implementing 9-category payer mapping
- Temporal overlap detection: identify patients with overlapping Medicare + Medicaid enrollment periods using lubridate intervals
- Dual-eligible flag with date range documentation
- Validation report comparing R output to Python pipeline payer counts

**Addresses (from FEATURES.md):**
- Payer harmonization (9-category with dual-eligible) — table stakes
- Dual-eligible detection — differentiator
- Multi-site data handling — table stakes

**Avoids (from PITFALLS.md):**
- Pitfall 1: Naive payer assignment without temporal overlap detection (CRITICAL)
- Pitfall 4: Enrollment gaps misinterpreted as "uninsured"
- Pitfall 8: Partner-specific data quirks treated as errors

**Research flag:** NEEDS DEEP RESEARCH — temporal overlap detection with lubridate intervals is complex; dual-eligible validation logic needs explicit design; partner-specific enrollment patterns (FLM claims-only, VRT death-only) need profiling. Consider `/gsd:research-phase` for temporal logic patterns.

---

### Phase 3: Cohort Definition & ICD Matching
**Rationale:** With clean payer data, cohort construction applies clinical inclusion/exclusion criteria. ICD code matching for 149 HL codes is high-risk due to format variation. Named predicate functions enable reusable, testable filter logic. Attrition logging at each step provides transparency for CONSORT reporting.

**Delivers:**
- `03_cohort_predicates.R` with named filter functions:
  - `has_hodgkin_diagnosis()` — ICD-9 (201.xx) + ICD-10 (C81.xx) with format normalization
  - `with_enrollment_period()` — minimum enrollment duration check
  - `exclude_missing_payer()` — filter patients with known payer categories
- `04_build_cohort.R` — applies filter chain with attrition logging
- Final cohort data frame + attrition log data frame

**Addresses (from FEATURES.md):**
- ICD code matching (ICD-9 + ICD-10) — table stakes
- Named filter predicates — table stakes
- Attrition logging — table stakes
- Encounter-based enrollment — table stakes

**Avoids (from PITFALLS.md):**
- Pitfall 2: ICD code format mismatches (CRITICAL)
- Pitfall 6: Incidence-prevalence bias from cohort definition
- Pitfall 7: Immortal time bias from misaligned index date

**Research flag:** NEEDS MODERATE RESEARCH — ICD code normalization patterns (dotted vs undotted) and regex for 149 codes need validation; incident vs prevalent case definition needs epidemiologic review. Standard attrition logging patterns are well-documented (dtrackr, tidylog examples).

---

### Phase 4: Attrition Waterfall Visualization
**Rationale:** Waterfall chart demonstrates that attrition logging works correctly and provides early validation of cohort size. Simpler than Sankey diagram (no multi-axis flow logic). Enables validation of small-cell suppression implementation before more complex visualizations.

**Delivers:**
- `05_visualize_waterfall.R` — ggplot2 bar chart from attrition log
- Vertical bars showing N patients excluded at each filter step
- Small-cell suppression applied to steps with N ∈ [1, 10]
- Secondary suppression for adjacent steps to prevent back-calculation
- PNG output: `output/figures/waterfall_attrition.png`

**Addresses (from FEATURES.md):**
- Attrition waterfall visualization — table stakes
- HIPAA small-cell suppression — table stakes

**Avoids (from PITFALLS.md):**
- Pitfall 5: HIPAA small-cell suppression without secondary suppression (CRITICAL)

**Research flag:** Standard patterns — waterfall charts in pharmacoepidemiology are well-documented (CONSORT diagrams, dtrackr vignettes). No phase research needed.

---

### Phase 5: Payer-Stratified Sankey Diagram
**Rationale:** Sankey diagram is the key differentiator visualization showing patient flow from enrollment → diagnosis → treatment stratified by payer. Requires ggalluvial with flow-level suppression logic. More complex than waterfall due to multi-axis data reshaping and flow aggregation.

**Delivers:**
- `06_visualize_sankey.R` — ggalluvial flow diagram
- Three axes: enrollment period, diagnosis date category, treatment type
- Flow thickness proportional to N patients, colored by payer category
- Small-cell suppression at flow level (suppress flows with N ∈ [1, 10])
- Aggregation of rare payer categories into "Other" if < 20 patients
- PNG output: `output/figures/sankey_patient_flow.png`

**Addresses (from FEATURES.md):**
- Sankey/alluvial visualization stratified by payer — differentiator (core deliverable)
- Human-readable filter predicate names — differentiator

**Avoids (from PITFALLS.md):**
- Pitfall 5: Small-cell suppression without secondary suppression
- Visual clutter from 9 categories where several have < 20 patients

**Research flag:** NEEDS MODERATE RESEARCH — ggalluvial data reshaping for 3-axis flows with payer stratification; small-cell suppression at flow level (not just axis labels) needs design. Consider `/gsd:research-phase` for ggalluvial patterns if stuck during implementation.

---

### Phase Ordering Rationale

**Dependency-driven sequencing:**
- Config → Loader (paths defined before loading)
- Loader → Harmonizer (raw data loaded before payer mapping)
- Harmonizer → Cohort Builder (payer categories assigned before filtering on payer)
- Cohort Builder → Visualizers (cohort and attrition log created before charting)

**Risk-driven prioritization:**
- Phase 2 (Payer Harmonization) tackles highest technical risk early — dual-eligible detection is complex and easy to get wrong; early validation against Python pipeline prevents late-stage rework
- Phase 3 (ICD Matching) is second-highest risk due to format variation; gets validation through cohort size comparison to Python pipeline
- Phases 4-5 (Visualizations) are lower risk — standard ggplot2 patterns with suppression wrapper

**Architecture-driven grouping:**
- Phase 1 groups all "foundation infrastructure" (config, utilities, loading) — enables parallel work on later phases once foundation is solid
- Phases 4-5 (Waterfall, Sankey) can be developed in parallel once Phase 3 completes — both read from same cohort + attrition log objects

**Pitfall avoidance:**
- Early focus on date parsing (Phase 1) prevents cascading failures in temporal logic (Phases 2-3)
- Payer harmonization isolated in Phase 2 enables focused validation before downstream dependencies
- Small-cell suppression utilities built in Phase 1, applied in Phases 4-5 — consistent implementation

### Research Flags

**Phases likely needing deeper research during planning:**
- **Phase 2 (Payer Harmonization):** Complex temporal overlap detection with lubridate — sparse examples for "simultaneous enrollment in two insurance types." Dual-eligible validation rules need explicit design. Partner-specific enrollment patterns need profiling. **Recommendation:** Consider `/gsd:research-phase` for temporal interval overlap patterns and dual-eligible detection algorithms.
- **Phase 3 (Cohort Definition):** ICD code format normalization across 149 codes — need validation that regex patterns capture all variants. Incident vs prevalent case definition needs epidemiologic review if not already specified. **Recommendation:** Spot-check ICD normalization with test queries before full implementation.
- **Phase 5 (Sankey Diagram):** ggalluvial data reshaping for multi-axis flow with payer stratification — examples exist but project-specific data structure may need experimentation. **Recommendation:** If stuck on data reshaping, use `/gsd:research-phase` for ggalluvial patterns with 3+ axes.

**Phases with standard patterns (skip phase research):**
- **Phase 1 (Foundation):** CSV loading with readr/vroom, config management, basic utilities — thoroughly documented in tidyverse guides.
- **Phase 4 (Waterfall):** Attrition bar charts — CONSORT diagram patterns well-documented in dtrackr, consort packages.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Core tidyverse stack (dplyr, ggplot2, vroom) verified from official CRAN releases and benchmarks. HiPerGator R module loading confirmed from UF documentation. tidylog is MEDIUM confidence (less widespread adoption) but stable 1.1.0 release. |
| Features | MEDIUM-HIGH | Table stakes features (loading, ICD matching, attrition logging) are well-established in PCORnet literature. Dual-eligible detection and Sankey visualization are domain-standard but implementation details need validation. 9-category payer mapping matches Python reference. |
| Architecture | MEDIUM | Sequential numbered scripts pattern is standard for R pipelines. Named predicate functions are best practice in clinical research. Small-cell suppression layer architecture is inferred from HIPAA requirements rather than documented PCORnet pattern. |
| Pitfalls | MEDIUM-HIGH | Dual-eligible detection failure, ICD format mismatch, date parsing failures are documented in multi-site PCORnet studies. HIPAA suppression violations are well-documented in CMS policy. Immortal time bias and incidence-prevalence bias are standard epidemiologic concepts. Partner-specific quirks based on PROJECT.md context. |

**Overall confidence:** MEDIUM-HIGH

Research provides strong foundation for roadmap with clear phase structure. Highest risk areas (payer harmonization, ICD matching) are identified with mitigation strategies. Stack recommendations are solid. Main uncertainty is implementation details for temporal overlap detection and ggalluvial data reshaping — both solvable during execution with targeted research if needed.

### Gaps to Address

**Temporal overlap detection algorithm:** Research identifies the need for dual-eligible detection via overlapping Medicare + Medicaid enrollment periods but doesn't provide explicit lubridate code pattern. **Handling:** Phase 2 should include spike to prototype overlap detection with test data; validate with Python pipeline counts before full implementation. If stuck, use `/gsd:research-phase` for lubridate interval overlap patterns.

**ICD code format variation extent:** Research documents that dotted and undotted formats exist, but doesn't quantify distribution across OneFlorida+ partners (e.g., is AMS 90% dotted, FLM 90% undotted?). **Handling:** Phase 1 should profile DX format distribution during initial load; log counts of dotted vs undotted vs other formats to inform normalization strategy in Phase 3.

**Partner-specific enrollment data models:** PROJECT.md documents that FLM is claims-only, VRT is death-only, AMS/UMI have encounter-based enrollment, but research doesn't provide operational definitions (e.g., how to detect "this is a claims-only partner" programmatically). **Handling:** Phase 2 should create per-partner enrollment completeness report (% patients with ENROLLMENT records, mean enrollment duration, gap patterns) to validate documented partner characteristics.

**Secondary suppression algorithm:** Research emphasizes need for secondary suppression to prevent back-calculation but doesn't specify selection rule (which 2-3 cells to suppress when primary cell is suppressed). **Handling:** Phase 1 utils_suppression.R should implement heuristic: suppress smallest adjacent cell in same row/column; document rule in code comments. Manual validation checklist in Phase 4 before outputs shared.

**Incident vs prevalent case definition:** Research flags incidence-prevalence bias but PROJECT.md doesn't specify whether cohort should be incident (newly diagnosed) or prevalent (all with HL diagnosis). **Handling:** Clarify with project PI before Phase 3; default to incident definition (first DX_DATE in study window) with lookback period to exclude prevalent cases if data supports it.

## Sources

### Primary (HIGH confidence)
- **STACK.md:** CRAN official releases (tidyverse 2.0.0, vroom 1.7.0, ggalluvial 0.12.5), HiPerGator UF documentation, vroom benchmarks, data.table vs tidyverse comparisons
- **FEATURES.md:** PCORnet CDM v7.0 specification (official), PCORnet data quality evaluation studies (PMC), Sankey diagram methodology (PMC publications), CMS cell size suppression policy (ResDAC), dual-eligible identification guidance (CMS/ResDAC)
- **ARCHITECTURE.md:** PCORnet CDM v7.0 specification, R pipeline architecture (bookdown, R4DS), CONSORT diagram packages (dtrackr, consort CRAN), ggalluvial documentation
- **PITFALLS.md:** PCORnet CDM specification, dual-eligible identification methods (ResDAC), immortal time bias literature (PMC), ICD code format regex patterns, CMS suppression policy, multi-site data heterogeneity studies

### Secondary (MEDIUM confidence)
- **STACK.md:** tidylog package (stable but less widespread adoption), consort package (designed for RCTs, may need adaptation for observational cohorts)
- **FEATURES.md:** Treatment timing windows complexity assessment, site-level data quality reporting patterns (inferred from multi-site studies)
- **ARCHITECTURE.md:** Small-cell suppression layer architecture (inferred from HIPAA requirements rather than documented pattern)
- **PITFALLS.md:** Partner-specific data quirks (based on PROJECT.md context rather than OneFlorida+ official documentation)

### Tertiary (LOW confidence — needs validation)
- Partner-specific operational definitions (how to programmatically detect "claims-only" vs "encounter-based" enrollment) — inferred from PROJECT.md, needs validation with project PI or OneFlorida+ documentation
- Exact dual-eligible prevalence in OneFlorida+ HL cohort (research cites 10-20% as typical, but actual may vary) — validate against Python pipeline after Phase 2 implementation

---

*Research completed: 2026-03-24*
*Ready for roadmap: yes*
