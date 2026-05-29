# Project Research Summary

**Project:** v1.8 Episode-Level Cancer Linkage & First-Line Therapy Identification
**Domain:** Clinical observational research in PCORnet Common Data Model
**Researched:** 2026-05-29
**Confidence:** HIGH

## Executive Summary

This milestone adds encounter-level cancer diagnosis linkage (replacing patient-level joins) and first-line therapy regimen identification (ABVD, BV+AVD, Nivo+AVD) to the existing R-based Hodgkin Lymphoma treatment analysis pipeline. The research confirms **minimal new dependencies**: all features use validated stack components (dplyr rolling joins for encounter linkage, lubridate for 28-day cycle detection, httr2 for drug name resolution via RxNorm API). The existing DuckDB-backed architecture accommodates all changes through script extensions and new numbered components (R/60-R/65).

The recommended approach leverages **hybrid encounter-diagnosis linkage**: direct ENCOUNTERID match (highest precision) with temporal proximity fallback for NULL/missing encounter links. Regimen detection requires **cycle-window grouping** (+/- 3 days) rather than same-encounter matching because infusion centers create separate encounters per drug. Critical to success: validate ENCOUNTERID population rates per table (90% in PROCEDURES vs 40% in DISPENSING at claims-heavy sites) before designing linkage strategy.

Key risks center on **PCORnet data model assumptions**: NULL ENCOUNTERID in 10-60% of medication records (site-dependent), many-to-many explosion on diagnosis joins (1 encounter = 15 diagnoses), and orphan diagnoses without encounter links (15-30% at claims sites). Mitigation requires multi-tier linkage strategies, explicit diagnosis ranking (PDX/ORIGDX/DX_SOURCE), and classification-not-deletion for post-death encounters. The existing pipeline architecture (numbered scripts, RDS caching, centralized config) minimizes integration risk — extend, don't replace.

## Key Findings

### Recommended Stack

**Zero critical new dependencies.** All v1.8 features use existing validated stack components. The pipeline already has dplyr 1.2.1 (rolling joins with `join_by(closest())`), lubridate 1.9.5 (interval testing with `%within%`), httr2 1.2.2 (RxNorm API validated in Phase 40), and DuckDB 1.3+ (encounter indexing). Only optional addition: rxnorm GitHub package (nt-williams/rxnorm) for simplified drug name resolution, but httr2 direct API calls work fine for the limited drug set (~20 HL therapy drugs).

**Core technologies:**
- **dplyr 1.2.1** (rolling joins): `join_by(closest())` handles encounter-level linkage with fallback to nearest diagnosis date — mature feature since dplyr 1.1.0 (Feb 2023)
- **lubridate 1.9.5** (interval operations): `%within%` detects 28-day cycle co-administration for regimen classification — validated in Phase 1 for enrollment windows
- **httr2 1.2.2** (RxNorm API): Drug name resolution with retry/throttle — already working in R/40 for NDC lookup
- **DuckDB 1.3+** (backend): ENCOUNTERID indexing for join performance — validated in Phase 29-32
- **openxlsx2 1.0.0+** (output): New Gantt output files — validated in Phase 54 for styled xlsx tables

**Integration points already validated:** httr2 RxNorm API pattern exists in R/40_investigate_unmatched_ndc.R (copy request builder, adapt for drug names). DuckDB ENCOUNTERID indexing confirmed in Phase 29 (verify coverage in PROCEDURES/PRESCRIBING/DISPENSING). openxlsx2 multi-sheet workbooks working in Phase 54 (reuse for death date analysis table).

### Expected Features

**Must have (table stakes):**
- **Encounter-specific cancer diagnosis linkage** — Episode-level context prevents conflating unrelated diagnoses across time; patient-level joins create false associations (HL 2015 + breast cancer 2022 flagging all encounters for both)
- **Death date validation** — EHR death dates incomplete/inaccurate (89% of post-death encounters due to missing death status); impossible dates corrupt survival analysis
- **First-line therapy identification** — Standard requirement for observational oncology studies; 60-day clean period with no prior chemotherapy (claims research standard)
- **Regimen-level classification** — Clinical interpretability requires regimen names (ABVD, BV+AVD, Nivo+AVD), not drug lists; multi-agent temporal windowing essential

**Should have (competitive):**
- **Hybrid encounter-diagnosis linkage** — Direct ENCOUNTERID match preferred, temporal fallback ensures coverage when encounter link missing; most pipelines do one or the other
- **Second cancer confirmation with temporal separation** — 7-day-apart rule (Phase 51 pattern) extends to encounter-level HL flag; prevents duplicate diagnoses from administrative re-coding
- **Granular treatment source validation** — Drop ICD diagnosis codes from SCT detection (diagnosis = history/status, not procedure); restrict to PROCEDURES/PRESCRIBING/DISPENSING
- **Regimen-specific timing rules** — BV+AVD post-2019 (FDA approval 3/20/2018), Nivo+AVD post-2024 (FDA PDUFA 4/8/2026) prevent anachronistic identification

**Defer (v2+):**
- **Treatment episode boundary formalization** — Explicit start/stop dates with 45-day gap threshold; currently implicit in first-line logic
- **Multi-line therapy sequencing** — First → second → third line progression tracking; requires episode boundaries + regimen change detection
- **Regimen expansion** — Stanford V, BEACOPP protocols (ABVD/BV+AVD/Nivo+AVD cover most advanced HL)
- **Pediatric protocol regimen ID** — Age <21 cohort with dose-reduced protocols; requires separate validation
- **Payer x regimen interaction** — Does payer correlate with specific regimens? Deferred per PROJECT.md out of scope

### Architecture Approach

The existing linear numbered-script pattern (R/00 through R/59) accommodates v1.8 through **extension, not replacement**. ENCOUNTERID propagation modifies R/44a (treatment episode detection) to add one column. New scripts follow clone-and-enhance pattern: R/60 (encounter-cancer linkage), R/61 (regimen labeling), R/62 (enhanced Gantt v2), preserving R/49 (original Gantt) for backward compatibility. RDS artifacts (treatment_episodes.rds, regimen_labeled_episodes.rds) enable downstream consumption without re-running entire pipeline. Centralized configuration (R/00_config.R) gains REGIMEN_DEFINITIONS for drug matching logic.

**Major components:**
1. **R/44a (modified)** — Add `encounter_ids` column to episode detection; drop ICD diagnosis codes from SCT detection (Z94.84 status codes remain, only C81.* removed)
2. **R/60 (new)** — Encounter-level cancer linkage via ENCOUNTERID match + closest date fallback; produces `cancer_category`, `cancer_link_method`, `is_hodgkin` per episode
3. **R/61 (new)** — First-line regimen labeling for adults 21+ at treatment; 28-day cycle window matching with dropped-agent tolerance (ABVD→AVD allowed); temporal availability rules
4. **R/62 (new)** — Enhanced Gantt CSV export (v2 suffix) with encounter-level cancer + regimen labels; preserves v1 outputs
5. **R/64 (optional)** — Death date analysis table (counts: patients with death dates, death as last encounter, post-death encounters); separate from Gantt integration

### Critical Pitfalls

1. **NULL/missing ENCOUNTERID varies by table (10-60% site-dependent)** — DISPENSING from external pharmacies often lacks encounter link (CVS, Walgreens). **Prevent:** Pre-validate ENCOUNTERID population rate per table and source; implement multi-tier linkage (exact match → PATID+date window ±3 days → ±14 days for orphan prescriptions); document linkage tier per medication. **Phase 1 (data validation) prevents cascade failures.**

2. **Many-to-many explosion on diagnosis-to-encounter join (1 encounter = 15 diagnoses)** — Cancer patients have multiple active diagnoses (HL + solid tumor history, HL + second malignancy) plus status codes (Z94.84 SCT status). Naive join produces 100-400 rows per treatment event. **Prevent:** Pre-filter DIAGNOSIS to malignant C-codes (C00-C96), exclude Z85.* (history), T86.5 (complications); rank diagnoses by PDX='P', DX_SOURCE='Primary', DX_DATE; select top 1 per encounter; assert 1:1 cardinality. **Phase 2 (encounter linkage) requires explicit disambiguation.**

3. **Chemotherapy regimen fragmentation across encounters** — ABVD requires 4 drugs (day 1 + day 15 of 28-day cycle); infusion centers create separate encounters per drug. Naive "all 4 drugs on same ENCOUNTERID" finds zero regimens despite 200+ patients receiving it. **Prevent:** Define cycle window (+/- 3 days from anchor date); detect regimen across encounters grouped by PATID + cycle_window; allow different ENCOUNTERIDs per drug. **Phase 4 (regimen detection) fails without cycle-window grouping.**

4. **BV+AVD misinterpreted as additive (5 drugs) instead of replacement** — Naming convention "BV+AVD" reads like "add BV to ABVD," but brentuximab replaces bleomycin (not added). Coding as 5-drug regimen finds zero cases. **Prevent:** Clinical validation before coding; BV+AVD = brentuximab + doxorubicin + vinblastine + dacarbazine (4 drugs, bleomycin ABSENT); detect in priority order (check brentuximab → BV+AVD, check nivolumab → Nivo+AVD, check bleomycin → ABVD). **Phase 4 (regimen definitions) must be clinically validated.**

5. **"Encounters after death" auto-deleted instead of classified** — Death date is often REPORTED date (when facility learned of death), not ACTUAL date; post-death encounters include legitimate hospice admissions, lab results from pre-death specimens, administrative processing. Deleting removes 10-20% of end-of-life care data. **Prevent:** Classify by encounter type (impossible: active treatment >7 days after death + no subsequent; administrative: revenue code 0001, ENC_TYPE='OT'; specimen: LAB result date > death but specimen date < death; hospice: palliative care DX); flag impossible deaths but preserve legitimate encounters. **Phase 5 (death date analysis) analyzes, doesn't delete.**

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 60: ENCOUNTERID Propagation + SCT Code Tightening
**Rationale:** Foundation for all encounter-level features; SCT cleanup is independent low-risk change bundled here.
**Delivers:** Enhanced treatment_episodes.rds with `encounter_ids` column; SCT episodes exclude diagnosis codes (Z94.84, T86.5 retained for status, only C81.* removed).
**Addresses:** ENCOUNTERID infrastructure from ARCHITECTURE.md; treatment source validation from FEATURES.md.
**Avoids:** Pitfall v1.8-5 (dropping all ICD codes loses legitimate SCT cases) — clarify requirement during scope.
**Research flag:** **Skip research-phase** — extends existing R/44a pattern; DuckDB ENCOUNTERID indexing validated Phase 29.

### Phase 61: Drug Name Resolution via RxNorm API
**Rationale:** Independent of Phase 60; enables Phase 62 regimen detection; reuses httr2 pattern from Phase 40.
**Delivers:** Drug name mapping for RXNORM_CUI codes in treatment_episode_detail.rds; foundation for regimen classification.
**Uses:** httr2 1.2.2 (RxNorm API with retry/throttle from Phase 40); jsonlite 1.9.3+ (JSON parsing).
**Implements:** REGIMEN_DEFINITIONS in R/00_config.R (RxNorm CUI → drug name keyword mappings).
**Avoids:** Pitfall v1.8-4 (regimen fragmentation) partially — establishes drug detection before cycle logic.
**Research flag:** **Skip research-phase** — httr2 RxNorm API pattern already validated in R/40_investigate_unmatched_ndc.R; copy request builder, adapt for drug names.

### Phase 62: 28-Day Cycle Regimen Detection
**Rationale:** Requires Phase 61 (drug names); core feature for first-line therapy analysis.
**Delivers:** Regimen classification (ABVD, BV+AVD, Nivo+AVD) using cycle-window grouping (+/- 3 days); dropped-agent tolerance (ABVD→AVD allowed).
**Uses:** lubridate 1.9.5 (`%within%` for 28-day cycle detection); dplyr 1.2.1 (group_by + summarise for cycle aggregation).
**Implements:** Cycle-window grouping pattern from ARCHITECTURE.md; regimen definitions from FEATURES.md.
**Avoids:** Pitfall v1.8-4 (regimen fragmentation — naive same-encounter matching finds zero cases); Pitfall v1.8-7 (BV+AVD as additive instead of replacement).
**Research flag:** **Research-phase needed** — Clinical validation required for regimen definitions (brentuximab replaces bleomycin, not additive); dropped-agent tolerance thresholds (3 of 4 drugs? 2 of 4?); temporal availability rules (BV+AVD post-2019, Nivo+AVD post-2024). **Use `/gsd:research-phase` before implementation.**

### Phase 63: Encounter-Level Cancer Diagnosis Linkage
**Rationale:** Requires Phase 60 (encounter_ids); foundational for Phase 65 (Gantt v2); high complexity due to many-to-many explosion risk.
**Delivers:** Encounter-level `cancer_category`, `cancer_link_method` (encounter_id/closest_date/none), `is_hodgkin` flags; replaces patient-level join from R/49.
**Uses:** dplyr 1.2.1 (`join_by(closest())` for temporal fallback); DuckDB DIAGNOSIS table access.
**Implements:** Hybrid linkage strategy from ARCHITECTURE.md; diagnosis ranking logic to prevent many-to-many explosion.
**Avoids:** Pitfall v1.8-2 (many-to-many explosion — 1 encounter = 15 diagnoses produces 100-400 rows per treatment); Pitfall v1.8-3 (orphan diagnoses without encounters lose 15-30% at claims sites).
**Research flag:** **Research-phase needed** — Fallback window specification (7/30/60 days for closest date?); diagnosis ranking logic (PDX='P' vs ORIGDX vs DX_SOURCE priority); orphan diagnosis handling (ENCOUNTERID='OT' or NULL). **Use `/gsd:research-phase` for linkage strategy validation.**

### Phase 64: First-Line Therapy Identification (Adults 21+)
**Rationale:** Requires Phase 62 (regimen labels) and Phase 63 (encounter-level HL flag); combines multiple features.
**Delivers:** `is_first_line` flag for chemotherapy episodes; 60-day clean period detection; age filter at treatment date (not enrollment).
**Uses:** dplyr 1.2.1 (lag/lead for prior chemotherapy detection); lubridate 1.9.5 (age calculation, date windows).
**Implements:** First-line definition from FEATURES.md; age-at-treatment pattern from PITFALLS.md.
**Avoids:** Pitfall v1.8-8 (age filter applied before treatment linkage — wrong cohort); age distribution should match HL epidemiology (peak 25-35, bimodal).
**Research flag:** **Skip research-phase** — Standard observational oncology pattern (60-day clean period from claims research); age calculation straightforward.

### Phase 65: Enhanced Gantt Export with Encounter-Level Cancer + Regimen Labels
**Rationale:** Integrates outputs from Phase 63 (encounter-level cancer) and Phase 64 (first-line regimens); final deliverable for milestone.
**Delivers:** gantt_episodes_v2.csv, gantt_detail_v2.csv with new columns (encounter_ids, cancer_category, cancer_link_method, is_hodgkin, regimen_label, is_first_line); preserves v1 outputs.
**Uses:** openxlsx2 1.0.0+ (if xlsx format needed); readr 2.2.0+ (CSV export).
**Implements:** Clone-and-enhance pattern from ARCHITECTURE.md (R/49 → R/62); versioned output files (_v2 suffix).
**Avoids:** Breaking external tools expecting v1 schema — parallel outputs maintain backward compatibility.
**Research flag:** **Skip research-phase** — Extends existing R/49 pattern; new columns at end preserve schema compatibility.

### Phase 66: Death Date Analysis Table
**Rationale:** Independent of other phases; extends Phase 59 validation logic; low complexity.
**Delivers:** Summary table (counts: patients with death dates, death as last encounter, post-death encounters by type); quantifies data quality.
**Uses:** DuckDB DEMOGRAPHIC.DEATH_DATE (validated Phase 59); lubridate 1.9.5 (date comparison); openxlsx2 (xlsx output).
**Implements:** Death date classification from PITFALLS.md; extends Phase 59 impossible death exclusion.
**Avoids:** Pitfall v1.8-6 (auto-deleting post-death encounters loses 10-20% of legitimate end-of-life care).
**Research flag:** **Skip research-phase** — Extends existing Phase 59 validation; simple counts/classification.

### Phase Ordering Rationale

- **Phase 60 first:** ENCOUNTERID propagation is foundation for Phase 63 (encounter-level linkage) and Phase 65 (Gantt v2). SCT code tightening bundled here as independent low-risk cleanup.
- **Phase 61 before 62:** Drug name resolution must precede regimen detection. Independent of ENCOUNTERID work allows parallel development if needed.
- **Phase 62 before 64:** Regimen classification required for first-line therapy identification.
- **Phase 63 after 60:** Encounter-level cancer linkage depends on encounter_ids column from Phase 60.
- **Phase 64 after 62+63:** First-line identification requires both regimen labels (Phase 62) and encounter-level HL flags (Phase 63).
- **Phase 65 last:** Gantt v2 export integrates all previous enhancements (encounter-level cancer + regimen labels + first-line flags).
- **Phase 66 independent:** Death date analysis can happen anytime after Phase 59; placed last as optional deliverable.

**Grouping rationale:**
- Phases 60-61 are infrastructure (ENCOUNTERID + drug names)
- Phases 62-63 are detection logic (regimens + cancer linkage)
- Phases 64-65 are integration (first-line identification + Gantt output)
- Phase 66 is standalone analysis (death date quality)

**Dependency testing:** Each phase produces RDS artifact consumed by downstream phases. Validate artifact schema after each phase before proceeding.

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 62 (regimen detection):** Clinical validation required for regimen definitions, dropped-agent tolerance thresholds, temporal availability rules. Complex logic needs domain expert review.
- **Phase 63 (encounter-level linkage):** Fallback window specification, diagnosis ranking priority, orphan diagnosis handling strategy — multiple design decisions need validation against PCORnet data characteristics.

**Phases with standard patterns (skip research-phase):**
- **Phase 60 (ENCOUNTERID propagation):** Extends existing R/44a extraction pattern; DuckDB indexing validated Phase 29.
- **Phase 61 (drug name resolution):** Reuses httr2 RxNorm API pattern from R/40_investigate_unmatched_ndc.R; copy-paste-adapt.
- **Phase 64 (first-line identification):** Standard observational oncology pattern (60-day clean period, age calculation); well-documented in claims research.
- **Phase 65 (Gantt v2):** Clone-and-enhance R/49; new columns at end preserve compatibility.
- **Phase 66 (death date analysis):** Extends Phase 59 validation; simple counts/classification.

**Pre-implementation validation critical for Phase 1 (data validation):**
- ENCOUNTERID population rate per table/source (prevents Pitfall v1.8-1)
- Diagnosis cardinality per encounter (prevents Pitfall v1.8-2)
- Orphan diagnosis rate per site (prevents Pitfall v1.8-3)

Without Phase 1 data validation, Phases 2-6 inherit site-specific failure modes (regimen detection works at UFH, fails at FLM).

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | **HIGH** | All required packages already in renv.lock from previous phases; dplyr rolling joins stable since 1.1.0 (3+ years); httr2 RxNorm API validated in Phase 40 |
| Features | **MEDIUM** | Table stakes features well-documented in clinical research standards; uncertainty on dropped-agent tolerance thresholds and fallback window specifications (needs Phase 62/63 research) |
| Architecture | **HIGH** | Existing codebase patterns clear; numbered scripts, RDS caching, clone-and-enhance all established; minimal architectural changes required |
| Pitfalls | **MEDIUM** | PCORnet CDM structure confirmed; ENCOUNTERID population variance documented (39-90% site-dependent); clinical logic pitfalls (BV+AVD replacement) validated; needs site-specific validation for NULL rates |

**Overall confidence:** **HIGH**

### Gaps to Address

**ENCOUNTERID population rates are site-dependent (validated range 39-90%):**
- **Gap:** Research confirms variation exists but cannot predict OneFlorida+ specific rates without data inspection.
- **Handle during:** Phase 1 (data validation) — run population queries per table/source before designing linkage strategy.
- **Validation query:** `SELECT SOURCE, COUNT(*) AS total, SUM(CASE WHEN ENCOUNTERID IS NULL OR ENCOUNTERID='OT' THEN 1 ELSE 0 END) AS null_count FROM PRESCRIBING GROUP BY SOURCE`

**Regimen detection dropped-agent tolerance thresholds:**
- **Gap:** Research confirms bleomycin dropped from ABVD is standard practice (RATHL trial, 27.5% of patients), but unclear if 3-of-4 drugs or 2-of-4 should count as regimen match.
- **Handle during:** Phase 62 research-phase — clinical validation with oncology SME; cross-validate detections with TUMOR_REGISTRY chemotherapy flags.
- **Decision point:** ABVD→AVD (missing bleomycin) definitely counts; AVD only from start (never had bleomycin) may need separate category "AVD (modified ABVD)".

**Encounter-level cancer linkage fallback window:**
- **Gap:** Research suggests 7/30/60 days as common windows, but no PCORnet-specific guidance for "closest diagnosis" temporal cutoff.
- **Handle during:** Phase 63 research-phase — analyze distribution of days between encounter and nearest diagnosis; choose window that captures 90%+ of linkable cases without excessive false matches.
- **Heuristic:** +/- 30 days from episode_start (typical encounter-to-coding lag in EHR systems).

**Orphan diagnosis linkage strategy:**
- **Gap:** Research confirms 15-30% of diagnoses at claims-heavy sites have ENCOUNTERID='OT' or NULL, but optimal fallback strategy (nearest encounter by date vs. pseudo-encounter creation) unclear.
- **Handle during:** Phase 63 research-phase — compare orphan diagnosis handling approaches (nearest encounter within 30 days vs. patient-level flag); validate against HL cohort confirmation (2+ codes, 7-day gap).
- **Likely approach:** 3-tier linkage (exact ENCOUNTERID → nearest encounter within 30 days → patient-level flag for remaining orphans).

**Death date classification logic:**
- **Gap:** Research identifies legitimate post-death encounter types (hospice, administrative, lab results) but doesn't provide classification heuristics.
- **Handle during:** Phase 66 implementation — classify by ENC_TYPE, DRG presence, revenue codes; flag "impossible deaths" (active treatment >7 days after death + no subsequent encounters); preserve administrative/hospice/specimen encounters.
- **Rule:** NULL out death dates flagged as impossible; retain death dates with plausible post-death encounters.

## Sources

### Primary (HIGH confidence)
- **Existing codebase** — R/44a_treatment_episodes.R, R/49_gantt_data_export.R, R/55_cancer_summary_refined.R, R/00_config.R, R/01_load_pcornet.R (architecture patterns, DuckDB backend, episode detection logic)
- **CRAN official documentation** — dplyr 1.2.1 (May 2026), lubridate 1.9.5 (May 2026), httr2 1.2.2 (May 2026), openxlsx2 1.0.0, DuckDB 1.3.2 (Mar 2026) — version verification, feature stability
- **PCORnet CDM v7.0 Specification** (May 2025) — ENCOUNTERID population rules, table cardinality, data model structure
- **ECHELON-1 trial** (PMC5766843, PMC10628810) — BV+AVD regimen definition (brentuximab replaces bleomycin, not additive); 5-year follow-up data
- **SWOG S1826 trial** (official results, ASH 2025) — Nivo+AVD regimen definition, FDA PDUFA date 4/8/2026, superiority over BV+AVD

### Secondary (MEDIUM confidence)
- **PCORnet prescribing/dispensing linkage study** (PMC6460498) — ENCOUNTERID population rates: 90.5% at integrated sites, 39.4% at non-integrated; 60.6% of dispensing without same-day prescriptions
- **EHR death date validation** (PMC11521374, PMC6232402) — 89% of post-death encounters due to missing death status; death registries lag 1-2 years; EHR capture incomplete
- **Chemotherapy regimen identification methodology** (PMC8058693) — Cycle timing analysis; algorithm identified 85 regimens with >98% PPV; temporal windowing for multi-agent detection
- **ABVD real-world experience** (LA County Hospital, 2025) — 27.5% ABVD→AVD transition rate (bleomycin dropped mid-course); dose modification patterns
- **OncoLink chemotherapy cycle calendars** — 28-day cycle standard for HL regimens; day 1 + day 15 administration for ABVD
- **EHR-registry linkage best practices** (PMC8208472, PMC8246795) — Encounter-level diagnosis accuracy vs. problem list; cancer registry linkage methodology

### Tertiary (LOW confidence — needs validation)
- **rxnorm GitHub package** (nt-williams/rxnorm, v0.2.1.9000, Apr 2025) — Optional RxNorm API wrapper; GitHub-only (not CRAN); actively maintained but not production-validated for this project

---
*Research completed: 2026-05-29*
*Supersedes: SUMMARY.md dated 2026-05-22 (v1.7 milestone research; this covers v1.8 additions)*
*Ready for roadmap: yes*
*Next step: Validate ENCOUNTERID population rates in HiPerGator data, clinical validation for regimen definitions, then proceed to phase planning*
