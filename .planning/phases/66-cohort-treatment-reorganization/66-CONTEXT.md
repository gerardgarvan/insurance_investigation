# Phase 66: Cohort & Treatment Reorganization - Context

**Gathered:** 2026-06-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Renumber ALL pipeline scripts (03-62+) into their final decade positions in one comprehensive renumbering pass. This includes cohort building (10-19), treatment analysis (20-29), cancer site analysis (40-59), payer/QA (60-69), outputs (70-79), tests (80-89), and ad-hoc (90-99). Update all source() cross-references across the codebase and validate with parity tests and smoke tests.

**Scope expansion from original:** Originally scoped for cohort (10-19) and treatment (20-39) only. User decided to place ALL evicted scripts into their final positions rather than temporary numbers — making this the single comprehensive renumbering phase. Phases 67 and 68 will need to be repurposed or dropped from the roadmap.

</domain>

<decisions>
## Implementation Decisions

### Eviction Strategy
- **D-01:** All scripts from 03 through 62 (plus unnumbered ad-hoc scripts) get renumbered to their final decade positions in THIS phase. No temporary numbers. No double-renumbering.
- **D-02:** Scripts currently occupying target decade ranges (e.g., 11_generate_pptx in the 10-19 range, 17_value_audit in the 20-39 range) move directly to their final positions in the outputs, QA, or ad-hoc decades.

### Cohort Decade (10-19)
- **D-03:** Helpers are numbered BEFORE the main build_cohort script (reflects dependency order):
  - 10 = cohort_predicates (from 03_cohort_predicates)
  - 11 = treatment_payer (from 10_treatment_payer)
  - 12 = surveillance (from 13_surveillance)
  - 13 = survivorship_encounters (from 14_survivorship_encounters)
  - 14 = build_cohort (from 04_build_cohort)
- **D-04:** Visualization scripts (05_visualize_waterfall, 06_visualize_sankey) are NOT cohort scripts — they go to 70-79 outputs decade.

### Treatment Decade (20-29)
- **D-05:** Treatment analysis scripts numbered 20-29 in pipeline execution order:
  - 20 = treatment_inventory (from 38)
  - 21 = investigate_unmatched (from 39)
  - 22 = investigate_unmatched_ndc (from 40)
  - 23 = combine_reports (from 41)
  - 24 = treatment_codes_resolved (from 42)
  - 25 = treatment_durations (from 43a)
  - 26 = treatment_episodes (from 44a) — sources 25
  - 27 = drug_name_resolution (from 60)
  - 28 = episode_classification (from 61)
  - 29 = first_line_and_death_analysis (from 62)
- **D-06:** Treatment test scripts (43b_test_durations, 44b_test_episodes) move to 80-89 test decade, NOT treatment decade.

### Suffix Convention
- **D-07:** All a/b suffixes are eliminated in the new numbering. Every script gets a clean unique number. This applies to 43a/43b, 44a/44b, 45a/45b, 46a/46b, 48a/48b, and 22a/22b.

### Gantt Export Scripts
- **D-08:** Gantt data export scripts (49_gantt_data_export, 63_gantt_v2_export) stay with cancer analysis in the 40-59 decade, not outputs.

### Claude's Discretion
- Exact numbering within cancer decade (40-59): ordering of cancer site frequency, confirmation, summary, and gantt scripts
- Exact numbering within payer/QA decade (60-69): ordering of payer tiering, overlap, audit, diagnostics, and missingness scripts. NOTE: 10 slots may be insufficient for all payer/QA/diagnostic scripts — Claude may need to extend into 56-59 or reclassify some scripts as ad-hoc
- Exact numbering within outputs decade (70-79): ordering of visualization, PPTX, documentation, and encounter analysis scripts
- Exact numbering within tests decade (80-89): ordering of smoke tests, parity tests, benchmarks, and verification tests
- Exact numbering within ad-hoc decade (90-99): ordering of one-off diagnostic and exploratory scripts
- Which scripts qualify as "ad-hoc" vs "QA" when decade capacity is tight — Claude should prioritize placing active pipeline scripts in numbered decades and move one-off milestone investigation scripts to ad-hoc
- Smoke test implementation approach for validating the renumbering

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 65 Outcomes (predecessor)
- `.planning/phases/65-foundation-reorganization/65-CONTEXT.md` -- Foundation decade decisions, utils/ subfolder pattern, auto-sourcing mechanism
- `.planning/phases/65-foundation-reorganization/65-01-PLAN.md` -- Foundation renumbering execution pattern (reuse approach)
- `.planning/phases/65-foundation-reorganization/65-02-PLAN.md` -- Smoke test creation pattern

### Script Inventory
- `R/SCRIPT_INDEX.md` -- Complete script inventory with dependency chains, functional groupings, and source() relationships
- `R/00_config.R` -- Foundation config with auto-sourcing; all renumbered scripts that source 00_config need no changes to config itself
- `R/65_smoke_test_foundation.R` -- Foundation smoke test pattern to adapt for full-pipeline validation

### Requirements
- `.planning/REQUIREMENTS.md` -- REORG-01 (sequential renumbering), REORG-02 (cross-reference updates)
- `.planning/ROADMAP.md` -- Phase 66 success criteria, decade allocation scheme

### Key Dependency Chain (must be preserved)
- `R/04_build_cohort.R` lines 27, 277, 383, 396 -- sources cohort_predicates, treatment_payer, surveillance, survivorship_encounters (all 4 source() paths must update)
- `R/44a_treatment_episodes.R` line 52 -- sources 43a_treatment_durations (path must update to new number)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/65_smoke_test_foundation.R` -- Smoke test pattern from Phase 65 that validates source() resolution and script execution; can be extended to cover all decades
- `.planning/phases/65-foundation-reorganization/65-01-PLAN.md` -- Execution pattern for renumbering (rename file, update source() calls, commit atomically)

### Established Patterns
- Source chain: scripts source their upstream dependency (e.g., 02 sources 01 which sources 00)
- Conditional sourcing: `if (!exists("pcornet")) source("R/01_load_pcornet.R")` pattern used by many scripts
- Phase 65 renumbered R/25 to R/03 and updated all references -- same mechanical pattern applies to every script in this phase
- A/b suffixes on scripts are inconsistent: 43a/43b are analysis/test pairs, but 45a/45b and 46a/46b are unrelated scripts that share a number

### Integration Points
- ~95 source() calls across all R scripts reference files being renumbered
- 04_build_cohort.R internally sources 4 other scripts that are all being renumbered (lines 27, 277, 383, 396)
- 22b_generate_phase19_20_pptx.R sources 18_uf_insurance_missingness.R and 19_flm_duplicate_dates.R -- all 3 renumber
- 11_generate_pptx.R sources 16_encounter_analysis.R -- both renumber
- 44a_treatment_episodes.R sources 43a_treatment_durations.R -- both renumber
- Smoke test scripts (26, 27, 28) source foundation and cohort scripts -- all references must update
- SCRIPT_INDEX.md must be regenerated after renumbering

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

- Phases 67 and 68 need to be repurposed or dropped from the roadmap since Phase 66 now handles all renumbering. Possible repurposing: Phase 67 could become script documentation prep, Phase 68 could become the archive folder creation (REORG-04).

</deferred>

---

*Phase: 66-cohort-treatment-reorganization*
*Context gathered: 2026-06-01*
