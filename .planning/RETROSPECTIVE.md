# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.5 -- Payer Analysis Expansion

**Shipped:** 2026-05-01
**Phases:** 4 | **Plans:** 4

### What Was Built
- Payer code frequency diagnostic with PayerVariable.xlsx cross-reference (R/35)
- Dual-scope hierarchical same-day payer resolution per Amy Crisp framework (R/36)
- Centralized AMC 8-category payer mapping in R/00_config.R
- 8-tier resolution hierarchy with distinct "Other govt" tier

### What Worked
- Phase 35's script (R/36) was comprehensive enough that Phase 36's refactoring built directly on top of it
- Materialize-early DuckDB pattern (established Phase 32) continued to work cleanly for all diagnostic scripts
- Configurable TIER_MAPPING at script top enabled quick Phase 37 modification (81 seconds execution)
- Amy Crisp framework provided clear, unambiguous hierarchy for same-day payer resolution

### What Was Inefficient
- Phase 36 had no SUMMARY.md despite being completed -- its work was absorbed into Phase 35's script lifecycle, requiring manual reconciliation during milestone completion
- Phase numbering (R/35 script for Phase 34, R/36 script for Phase 35) drifted from phase numbers, causing confusion
- Milestone archival CLI only detected 1 phase (STATE.md milestone mismatch from v1.4 era), requiring manual fix

### Patterns Established
- Dual-scope analysis pattern (all encounters + AV+TH subset) with consistent suffix strategy (_all vs _av_th_v2)
- Configurable tier mapping as named list at script top for PI editability
- Centralized payer lookup tables in R/00_config.R rather than runtime xlsx dependencies
- FLM source override at patient-date granularity (ENCOUNTER.SOURCE, not DEMOGRAPHIC.SOURCE)

### Key Lessons
1. When Phase N's refactoring is absorbed into Phase N-1's script, create at minimum a SUMMARY.md for Phase N to keep the archival pipeline clean
2. AMC_PAYER_LOOKUP centralization in R/00_config.R eliminates a class of runtime dependency issues -- prefer config-level lookups over file-based lookups
3. Small hierarchical changes (7 to 8 tiers) are trivial when the tier mapping is a configurable data structure rather than hardcoded logic

### Cost Observations
- Sessions: ~4 (Phase 34, 35, 36, 37 each had dedicated sessions)
- Notable: Phase 37 completed in 81 seconds -- well-structured configurable code enables rapid modification

---

## Milestone: v1.8 -- Episode-Level Cancer Linkage & First-Line Therapy Identification

**Shipped:** 2026-06-01
**Phases:** 4 | **Plans:** 6

### What Was Built
- ENCOUNTERID propagation through treatment episodes + standalone drug name resolution via RxNorm API (Phase 60)
- Encounter-level cancer linkage (ENCOUNTERID + 30-day temporal fallback) replacing patient-level joins (Phase 61)
- First-line HL regimen detection (ABVD, BV+AVD, Nivo+AVD) with dropped-agent tolerance and temporal availability rules (Phase 61)
- First-line therapy flagging for adults 21+ with 60-day clean period + death date data quality tables (Phase 62)
- Gantt v2 CSV export as superset of v1 schema with encounter-level cancer, regimen labels, first-line flags (Phase 63)

### What Worked
- Coarse phase granularity (4 phases vs research-suggested 7) kept overhead low while maintaining clear boundaries
- RDS artifact pipeline (treatment_episodes.rds enriched across phases) enabled clean cross-phase data contracts
- R/63 reading enriched RDS directly instead of re-deriving PREFIX_MAP avoided ~400 lines of complexity vs the R/49 approach
- Guard clauses for missing columns (e.g., drug_names, is_first_line) allow scripts to run independently before upstream phases are complete
- J-code fallback for regimen detection improved coverage when RxNorm resolution produced generic names

### What Was Inefficient
- REQUIREMENTS.md checkboxes for Phase 62 (FLT-01, FLT-02, DEATH-01, DEATH-02, DEATH-03) were not updated when the phase completed — caught during audit, not during transition
- Phase 62 and 63 progress table in ROADMAP.md still showed "Not started" despite being complete — stale tracking
- ENCOUNTERID population rates required data inspection on HiPerGator before linkage strategy could be finalized — this dependency isn't visible in plans
- PREFIX_MAP duplication accumulated to 5 scripts without centralization (carried forward as tech debt)

### Patterns Established
- Encounter-level linkage pattern: ENCOUNTERID direct match > temporal fallback > "none" for cancer diagnosis-to-episode linkage
- Regimen detection via drug composition fingerprint within cycle window — reusable for future protocol identification
- Gantt v2 as superset of v1 pattern: add new columns, never remove existing ones, maintain backward compatibility
- Guard clause pattern for cross-phase dependencies: `if ("column" %in% names(df))` prevents execution failures
- Idempotent joins using `anti_join` before `left_join` to prevent column duplication on re-run

### Key Lessons
1. Phase execution and requirement checkbox updates should be atomic — update REQUIREMENTS.md in the same session that completes the phase, not deferred to audit
2. Coarse phase granularity (combining 2-3 research phases into 1 execution phase) works well when requirements are well-defined and dependencies are clear
3. R/63's approach (read enriched RDS directly) vs R/49's approach (re-derive from raw data) demonstrates that downstream scripts should consume upstream artifacts, not rebuild them
4. Regimen detection is inherently fragile across real-world data — dropped-agent tolerance and J-code fallback were both necessary additions discovered during implementation

### Cost Observations
- Sessions: ~4 (Phase 60, 61, 62, 63 each had dedicated sessions)
- Timeline: 3 days (2026-05-29 to 2026-06-01)
- Notable: Phase 61 completed in 3 minutes — well-defined requirements and clear RDS contract enabled rapid script creation

---

## Milestone: v2.2 -- Local Testing Infrastructure & Clinical Refinements

**Shipped:** 2026-06-05
**Phases:** 7 | **Plans:** 11

### What Was Built
- Environment auto-detection (IS_LOCAL flag via Sys.info() with R_TESTING_ENV override) in R/00_config.R (Phase 83)
- 20-patient hand-crafted test fixtures covering 11 clinical edge cases across 15 PCORnet CDM tables (Phase 84)
- DuckDB integration validation (R/88 Sections 32-33) and end-to-end local test runner (tests/run_local_test.R) (Phase 85)
- Quality standards validation and v2.2 milestone documentation (Phase 86)
- Unified ICD-9/ICD-10 cancer code handling via shared utils_cancer.R with is_cancer_code() and 4-tier classify_codes() cascade (Phase 87)
- Instance-level drug grouping tables (R/57) with human-readable sub-category and cancer site names (Phase 88)
- Episode vs encounter grain labeling with self-documenting filenames and backward-compatible old filenames (Phase 89)

### What Worked
- Milestone audit (`/gsd:audit-milestone`) caught that Phases 85-86 were not yet started, preventing premature completion
- Gap closure phases (85-86) were quick to plan and execute once infrastructure (83-84) was solid
- Phases 87-89 formed a self-contained chain (ICD-9 foundation -> instance tables -> grain labels) that could be planned and executed independently of the testing infrastructure phases
- Shared utility extraction pattern (utils_cancer.R) worked cleanly — single source of truth for cancer code detection consumed by 10+ downstream scripts
- tribble()-based fixture generators provided self-documenting test data with clear patient-to-edge-case mapping

### What Was Inefficient
- Phases 87-89 were added ad-hoc during v2.2 execution without formal milestone scope expansion — milestone audit only covered Phases 83-86
- The v2.2 milestone audit was stale by the time of completion (gaps closed by Phases 85-86 after audit)
- Phase 87 requirements (ICD-01 through ICD-12) were never added to REQUIREMENTS.md since they weren't part of original v2.2 scope — requirement tracking gap for ad-hoc phases
- Phase 88-89 requirements (P88-D01+, P89-D01+) also tracked only in ROADMAP.md, not REQUIREMENTS.md

### Patterns Established
- Environment detection pattern: OS-based flag with env var override for transparent cross-platform support
- Fixture design pattern: FIXTURE_DESIGN.md as human-readable test matrix, generate_fixtures.R as single source of truth, CSVs as materialized artifacts
- Shared utility extraction: utils_cancer.R with is_cancer_code() and classify_codes() consumed by all cancer-related scripts
- Grain-labeled outputs: filenames self-document their aggregation level (episode_level_*, encounter_level_*)
- Dual wb$save() for backward compatibility: new grain-labeled filenames plus old filenames from same workbook object

### Key Lessons
1. Ad-hoc phases added during milestone execution should be formally scoped into the milestone before completion — either expand milestone scope or defer to next milestone
2. Milestone audits are snapshots in time and become stale — re-audit or note staleness when closing gaps after the audit
3. Shared utility extraction (utils_cancer.R pattern) is the right approach when 3+ scripts need the same logic — the refactoring cost pays for itself immediately
4. Fixture-based local testing infrastructure is achievable without heavyweight test frameworks — tribble() + run_local_test.R with conditional smoke test sections is sufficient
5. When adding grain labels to outputs, backward compatibility via dual save avoids breaking downstream consumers

### Cost Observations
- Sessions: ~7 (Phases 83, 84, 85, 86, 87, 88, 89 each had dedicated sessions, some combined)
- Timeline: 3 days (2026-06-03 to 2026-06-05)
- Notable: Phase 87 required 3 plans (most complex in v2.2) due to 10+ script modifications; Phases 88-89 each completed in single-plan sessions

---

## Milestone: v3.2 -- Meeting Gap Resolution Report

**Shipped:** 2026-07-15
**Phases:** 23 (Phases 104-126) | **Plans:** 37

### What Was Built
- Meeting gap investigations (Phases 104-107): pre-diagnosis treatment flagging, secondary-malignancy table, Ethna/transplant/SCT code + HL+NHL overlap verification, Tableau-ready encounter tables, RMarkdown gap-resolution report + delivery manifest
- Pipeline hardening (108-109): zero-warning run; date-grain co-administration analysis
- Output reshaping (110-115): HL-only 7-day V2 summary, TABLE-2 date-grain collapse, Gantt temporal-dx + universal ascending sort, post-death encounter investigation, drug-name consistency remediation, Gantt 7-day-confirmed + age
- Enrichment (116-117, 120-121): USDA RUCA rurality, lifespan Gantt, Supportive Care meaning normalization, ZIP change-frequency
- Death-cause NHL flag (118-119): created then fixed to source from the DEATH_CAUSE table
- MED_ADMIN/DISPENSING chemo-detection (122-124): root-cause col_spec fix + NDC crosswalk + get_chemo_hits() across 7 consumers, quantified (+1,328 patients / +13,762 chemo dates), fully integrated downstream with source provenance
- R/88 smoke-test fixes (125-126): stale DEATH_CAUSE guard check + stale audit xlsx regenerated so R/88 exits 0

### What Worked
- Investigate-first gate pattern (R/103 read-only diagnostic gating the R/102 rewrite; R/107 diagnostic sizing the chemo-detection loss before Phase 122) prevented building on wrong assumptions
- Shared helper extraction under load: get_chemo_hits() + NDC crosswalk fixed a class of silent-drop bugs across 7 consumers from one place
- Dual-environment discipline (structural grep/parse on Windows, runtime on HiPerGator) let 23 phases progress without cluster access, with runtime confirmation batched for the high-value chains (119, 122-124)
- R/88 Section-per-phase smoke-test convention gave every phase a structural regression guard

### What Was Inefficient
- Scope sprawl: a 4-phase charter (104-107) grew to 23 phases as new asks arrived — the milestone became a catch-all rather than closing and opening a new milestone
- REQUIREMENTS.md traceability drifted repeatedly (CODE/OVERLAP/DRUGFIX checkboxes stale, table stopped at Phase 120) — same atomic-update lesson from v1.8/v2.2 recurred
- Phase 126 shipped with no GSD artifacts (manual HiPerGator refresh, prose attestation only) — the milestone's terminal goal is not repository-verifiable
- ~8 phases carry runtime-deferred verification; end-to-end proof lives outside the repo pending a consolidated HiPerGator run
- R/88 accumulated cosmetic section-label anomalies (skipped 15l, out-of-order proton, duplicate SECTION 30)

### Patterns Established
- Investigate-first read-only diagnostic scripts (R/103, R/107, R/109) that gate or size a fix before implementation
- 5-touch-point recipe for adding a PCORnet CDM table (PCORNET_TABLES + col spec + DuckDB ingest + smoke-test count + fixture)
- Source-provenance labeling (source_hints → source_table/code_type) so newly-detected data is traceable through downstream outputs
- SCRIPT_INDEX-only diagnostic scripts (not wired into R/39) for one-off quantification/audit work

### Key Lessons
1. Set a scope ceiling per milestone — when new asks arrive after the charter is met, prefer closing the milestone and opening the next over absorbing indefinitely
2. Update REQUIREMENTS.md checkboxes and traceability in the same session that completes each phase — this lesson has now recurred across v1.8, v2.2, and v3.2
3. A phase whose only deliverable is a cluster-side data refresh still needs a VERIFICATION.md capturing the runtime evidence (pasted log), or the terminal goal is unauditable
4. Batch runtime-deferred phases into a single consolidated HiPerGator verification run before milestone completion rather than leaving proof scattered outside the repo

### Cost Observations
- Timeline: ~30 days (2026-06-15 to 2026-07-15); 330 commits, 68 `feat(`
- Model profile: balanced; mode: yolo
- Notable: many phases completed in 2-6 minutes (single-plan, well-defined); the chemo-detection chain (122-124) was the heaviest, spanning fix → quantification → downstream integration

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Key Change |
|-----------|--------|------------|
| v1.5 | 4 | Centralized payer config; dual-scope diagnostic pattern established |
| v1.8 | 4 | Encounter-level linkage pattern; RDS artifact pipeline for cross-phase contracts; coarse phase granularity |
| v2.2 | 7 | Dual-environment support; shared utility extraction (utils_cancer.R); fixture-based testing; grain-labeled outputs |
| v3.2 | 23 | Investigate-first diagnostic gates; shared helper fixes across many consumers; per-phase smoke-test sections; scope sprawl (catch-all milestone) |

### Top Lessons (Verified Across Milestones)

1. Configurable data structures (named lists, lookup tables) enable rapid iteration vs hardcoded logic
2. Materialize-early pattern for DuckDB diagnostics prevents lazy-query translation issues
3. Standalone diagnostic scripts with explicit dependencies (source R/00_config.R only) are more maintainable than scripts that source the full pipeline
4. Downstream scripts should consume upstream RDS artifacts directly rather than re-deriving data (v1.8: R/63 vs R/49 approach)
5. Guard clauses for optional cross-phase columns prevent execution ordering failures (v1.8: drug_names, is_first_line)
6. Shared utility extraction pays for itself immediately when 3+ scripts need the same logic (v2.2: utils_cancer.R; v3.2: get_chemo_hits across 7 consumers)
7. Ad-hoc phases added during milestone execution need formal scope expansion to keep requirement tracking consistent (v2.2: Phases 87-89; v3.2: 104→126 sprawl)
8. REQUIREMENTS.md checkbox/traceability drift is a recurring failure — update atomically at phase completion (v1.8, v2.2, v3.2 all hit this)
9. Investigate-first read-only diagnostics that gate or size a fix before implementation prevent building on wrong assumptions (v3.2: R/103, R/107, R/109)
10. Cluster-side-only deliverables still need an in-repo VERIFICATION.md with pasted runtime evidence, or the goal is unauditable (v3.2: Phase 126)
