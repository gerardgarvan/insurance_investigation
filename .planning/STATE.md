---
gsd_state_version: 1.0
milestone: v2.2
milestone_name: Local Testing Infrastructure
status: defining_requirements
last_updated: "2026-06-03"
last_activity: 2026-06-03
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# State: v2.2 Local Testing Infrastructure

**Last Updated:** 2026-06-03
**Current Milestone:** v2.2 Local Testing Infrastructure

## Project Reference

**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

**Current Focus:** Defining requirements for local testing infrastructure

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-06-03 — Milestone v2.2 started

## Accumulated Context

### Key Decisions This Milestone

| Decision | Rationale | Phase |
|----------|-----------|-------|
| Scoped to high-value pieces only | Full synthetic data generator for all 75 scripts has poor ROI — real data quirks can't be predicted | Pre-milestone |
| Environment auto-detection + env var override | Auto-detect OS/hostname with LOCAL_MODE override covers both dev and CI scenarios | Pre-milestone |
| Targeted fixtures over synthetic generation | Hand-crafted test data with known edge cases catches logic errors; real data testing stays on HiPerGator | Pre-milestone |

### Open Questions

None yet.

### Active Todos

- [ ] Define requirements for v2.2
- [ ] Create roadmap for v2.2

### Known Blockers

None.

### Technical Debt

**Carried from v2.1:**
- None identified

**Anticipated in v2.2:**
- R/00_config.R path switching adds conditional logic complexity
- Test fixture CSVs need maintenance if table schemas change

## Session Continuity

### What Just Happened

- Milestone v2.2 started
- Scoped down from full synthetic data to targeted testing infrastructure
- PROJECT.md and STATE.md updated

### Current Task

Defining requirements for local testing infrastructure.

### Next Actions

1. Research decision
2. Define requirements
3. Create roadmap

---
*State initialized: 2026-06-03*
*Last activity: Milestone v2.2 started*
