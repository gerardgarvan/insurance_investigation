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

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Key Change |
|-----------|--------|------------|
| v1.5 | 4 | Centralized payer config; dual-scope diagnostic pattern established |
| v1.8 | 4 | Encounter-level linkage pattern; RDS artifact pipeline for cross-phase contracts; coarse phase granularity |

### Top Lessons (Verified Across Milestones)

1. Configurable data structures (named lists, lookup tables) enable rapid iteration vs hardcoded logic
2. Materialize-early pattern for DuckDB diagnostics prevents lazy-query translation issues
3. Standalone diagnostic scripts with explicit dependencies (source R/00_config.R only) are more maintainable than scripts that source the full pipeline
4. Downstream scripts should consume upstream RDS artifacts directly rather than re-deriving data (v1.8: R/63 vs R/49 approach)
5. Guard clauses for optional cross-phase columns prevent execution ordering failures (v1.8: drug_names, is_first_line)
