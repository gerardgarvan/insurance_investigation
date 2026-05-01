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

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Key Change |
|-----------|--------|------------|
| v1.5 | 4 | Centralized payer config; dual-scope diagnostic pattern established |

### Top Lessons (Verified Across Milestones)

1. Configurable data structures (named lists, lookup tables) enable rapid iteration vs hardcoded logic
2. Materialize-early pattern for DuckDB diagnostics prevents lazy-query translation issues
3. Standalone diagnostic scripts with explicit dependencies (source R/00_config.R only) are more maintainable than scripts that source the full pipeline
