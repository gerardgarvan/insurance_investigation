---
gsd_state_version: 1.0
milestone: v2.1
milestone_name: Clinical Data Refinements & NLPHL Breakout
status: verifying
last_updated: "2026-06-03T04:48:49.001Z"
last_activity: 2026-06-03
progress:
  total_phases: 6
  completed_phases: 4
  total_plans: 8
  completed_plans: 8
  percent: 100
---

# State: v2.1 Clinical Data Refinements & NLPHL Breakout

**Last Updated:** 2026-06-02
**Current Milestone:** v2.1 Clinical Data Refinements & NLPHL Breakout

## Project Reference

**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

**Current Focus:** Phase 78 — episode-enhancement-death-integration

## Current Position

Phase: 78 (episode-enhancement-death-integration) — EXECUTING
Plan: 2 of 2
Status: Phase complete — ready for verification
Last activity: 2026-06-03

**Progress:**

[██████████] 100%
v2.1 Milestone: [......] 0% (0/6 phases)
  Phase 75: [......] 0%

```

**Velocity:** N/A (no phases completed yet)

## Performance Metrics

**Milestone Progress:**

- Phases: 0/6 complete (0%)
- Plans: 0/TBD complete (N/A)

**Velocity:**

- Total plans completed (all milestones): 94
- v2.0 velocity: 10 phases, 30 plans (2026-06-01 to 2026-06-02)
- Average execution time: varies by phase complexity

**Historical (v1.0-v2.0):**

- Total phases: 74
- Total plans: ~180
- Overall success rate: 99.4% (4 false failures in Phase 74)

**Active Milestone Started:** 2026-06-02

## Accumulated Context

### Key Decisions This Milestone

| Decision | Rationale | Phase |
|----------|-----------|-------|
| NLPHL as distinct category | C81.0 is biologically and clinically distinct from classical HL (>90% vs 85-90% 5-year survival) | Pending |
| 4-char prefix matching before 3-char | Mutually exclusive classification: C810 → NLPHL, then C81 → classical HL | Pending |
| Drop tumor registry treatment data | TR captures 8-32% vs EHR 95-100% accuracy per literature | Pending |
| Coverage analysis before TR removal | Quantify TR-only episodes to avoid silent treatment loss | Pending |
| Extend 7-day gap to all cancers | SEER/IARC standards require temporal separation for all categories | Pending |
| Output versioning for breaking changes | Maintain baseline comparability (v1 vs v2_7day) | Pending |
| Centralize drug groupings in R/00_config.R | Follows AMC_PAYER_LOOKUP pattern from Phase 36, avoids runtime xlsx dependency | Pending |
| Profile cause of death quality first | Guard against misleading mortality analyses (>40% missingness common) | Pending |
| Phase 75 P01 | 185 | 2 tasks | 2 files |
| Phase 75 P02 | 103 | 1 tasks | 1 files |
| Phase 76 P01 | 189 | 1 tasks | 1 files |
| Phase 76 P02 | 3min | 2 tasks | 2 files |
| Phase 77 P01 | 229 | 2 tasks | 2 files |
| Phase 77 P02 | 299 | 2 tasks | 2 files |
| Phase 78 P01 | 3 | 2 tasks | 2 files |
| Phase 78 P02 | 6 | 2 tasks | 2 files |

### Open Questions

1. **SCT code 0362 provenance:** Code "0362" not in standard CPT databases (38204-38241 are standard SCT codes). Likely internal/proprietary code or data entry artifact. Requires project-specific code documentation review during Phase 79.

2. **all_codes_resolved_next_tables.xlsx schema:** Drug grouping tables and template structure referenced but not verified. Will confirm sheet names, column structure, and template formatting during Phase 77.

3. **Cause of death field availability:** PCORnet DEATH table may use DEATH_CAUSE (ICD-10), CAUSE_OF_DEATH (text), or require external linkage. Phase 78 profiling will identify available fields.

4. **Drug grouping table purpose:** "2 new tables" referenced but specific structure not documented. Likely drug group frequency by payer and by cancer category. Confirm with domain expert during Phase 79 planning.

5. **Total population = 6,347 baseline:** Confirm this is correct current cohort size by checking existing cancer_summary_table_pre_post.rds row count before implementing Phase 77 changes.

6. **igraph package for cycle detection:** Phase 79 replaced-by verification may require igraph package (not in current renv.lock) for is_dag(). Lightweight addition but new dependency. Decide during phase planning whether graph analysis justifies adding igraph.

### Active Todos

- [ ] Plan Phase 75: Configuration Extensions (NLPHL & Death Cause)
- [ ] Verify baseline cohort size = 6,347 before starting Phase 77
- [ ] Confirm all_codes_resolved_next_tables.xlsx schema during Phase 77 planning
- [ ] Review SCT code 0362 documentation before Phase 79
- [ ] Decide on igraph package addition for Phase 79 cycle detection

### Known Blockers

None. Roadmap complete, ready for phase planning.

### Technical Debt

**Carried from v2.0:**

- None identified — v2.0 cleanup addressed all major debt items

**Anticipated in v2.1:**

- Output versioning strategy (v1 vs v2_7day files) needs clear naming convention
- Drug grouping centralization follows Phase 36 pattern but adds ~100 LOC to R/00_config.R
- Potential igraph dependency for graph cycle detection (lightweight but needs approval)

## Session Continuity

### What Just Happened

- Milestone v2.1 roadmap created with 6 phases (75-80)
- Requirements defined: 14 total (10 feature + QUAL-01 cross-cutting + 3 visualization)
- Research complete: zero new package dependencies needed
- Coarse granularity: 3-wave implementation (config → core → investigations)

### Current Task

Roadmap creation complete. Ready for phase planning.

### Next Actions

1. Plan Phase 75: Configuration Extensions (NLPHL & Death Cause)
2. Execute Phase 75
3. Continue sequential phase execution through Phase 80

**Key context for next session:**

- Milestone v2.1 roadmap complete: 6 phases (75-80), 14 requirements
- Critical pitfalls identified: NLPHL double-counting, TR removal silent loss, 7-day gap baseline breakage, xlsx runtime dependencies, cause of death missingness
- Visualization phase (Phase 80) includes UI work for ggalluvial Sankey diagrams

**Files created:**

- .planning/ROADMAP.md (6 phases, success criteria, dependencies)
- .planning/STATE.md (this file)
- .planning/REQUIREMENTS.md (traceability updated)

**Ready for:** `/gsd:plan-phase 75`

---
*State initialized: 2026-06-02*
*Last activity: Roadmap creation*
