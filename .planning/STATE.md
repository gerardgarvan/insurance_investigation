---
gsd_state_version: 1.0
milestone: v3.3
milestone_name: Rituximab/Methotrexate-Associated Diagnoses of Interest
status: roadmap_ready
stopped_at: v3.3 roadmap created — 4 phases (127-130), 19/19 requirements mapped
last_updated: "2026-07-15T00:00:00.000Z"
last_activity: 2026-07-15
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-15 after v3.2)

**Core value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

**Current focus:** v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest — Phase 127 ready to plan

## Current Position

Phase: 0 of 4 (roadmap created, Phase 127 not yet started)
Plan: —
Status: Ready to plan Phase 127
Last activity: 2026-07-15 — v3.3 roadmap created (4 phases, 19 requirements mapped)

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Milestone velocity:**
- v3.2: 23 phases (104-126) completed (2026-06-15 to 2026-07-15)
- v3.1: 4 phases (100-103) completed in 1 day (2026-06-12)
- v3.0: 5 phases (95-99) completed in 3 days

**Planning efficiency:**
- Average plans per phase: 1.0 (recent milestones)
- Average tasks per plan: 3.0

## Accumulated Context

### v3.3 Roadmap Decisions

- Phase numbering continues from Phase 126 (v3.2 last phase) — v3.3 starts at Phase 127
- Granularity: coarse (4 phases for 19 requirements, following research's recommended 4-phase decomposition)
- Phase 127 (Code-Set & Infrastructure) is a strict prerequisite for all others: DOI_CODE_MAP + utils_doi.R must exist before any classification code is written
- Phase 128 (Classification) is a strict prerequisite for Phase 129 (Attribution): doi_encounters.rds must exist before attribution joins
- Phase 130 (Registration/Smoke Test) can begin once Phase 129's R/111 structure is stable; its HiPerGator runtime gate is the v3.3 definition-of-done
- DOI_ATTRIBUTION_WINDOW_DAYS = 90L (one clinical quarter) — wider than cancer cascade's ±30 days because RA/psoriasis/IBD indication timelines span months, not weeks
- Three-state likely_non_lymphoma_directed flag: NA must not be collapsed to FALSE (would undercount the clinically interesting ambiguous HL+DoI co-occurrence cases)
- DuckDB-native prefix filter mandatory: never load full DIAGNOSIS table into R (OOM risk on HiPerGator)
- I77.82 excluded (seed error — "Dissection of artery"), D47.Z2 excluded (CANCER_SITE_MAP conflict)
- utils_doi.R as new file (not extension of utils_cancer.R): classify_codes() has 10+ consumers expecting cancer-site output; merging would silently corrupt them

### Active TODOs

- [ ] Plan Phase 127 (Code-Set and Infrastructure Centralization)

### Known Blockers

None identified.

## Session Continuity

**Last command:** `/gsd:new-project` roadmapper invocation (2026-07-15)
**Stopped at:** v3.3 ROADMAP.md created; REQUIREMENTS.md traceability filled; STATE.md updated
**What's next:** `/gsd:plan-phase 127`
