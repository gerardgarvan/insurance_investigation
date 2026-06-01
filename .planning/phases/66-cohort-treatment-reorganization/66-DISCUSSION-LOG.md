# Phase 66: Cohort & Treatment Reorganization - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-06-01
**Phase:** 66-cohort-treatment-reorganization
**Areas discussed:** Eviction strategy, Cohort decade lineup, Treatment suffix handling, Numbering sequence

---

## Eviction Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Move to final positions now | Evicted scripts go directly to their final decade (outputs->70-79, tests->80-89, QA->60-69, etc). More work in Phase 66 but avoids double-renumbering in later phases. | Yes |
| Park in temp 9xx numbers | Move displaced scripts to temporary 900+ numbers, then let Phases 67/68 place them properly. Less scope in Phase 66 but scripts move twice. | |
| Phase 66 only touches cohort/treatment | Renumber only the cohort and treatment scripts. Leave non-cohort/non-treatment scripts at their current numbers even if they're in the 10-36 range. Later phases handle the conflicts. | |

**User's choice:** Move to final positions now (Recommended)
**Notes:** None

### Follow-up: Scope Expansion

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 66 does it all | Renumber ALL numbered scripts (03-62) in one shot. Phases 67-68 become unnecessary or get repurposed. One big renumbering is cleaner than 3 partial ones. | Yes |
| Evict only blocking scripts | Phase 66 only moves scripts that conflict with cohort (10-19) or treatment (20-27) target numbers. Non-conflicting scripts (e.g., 47-58 cancer) stay at current numbers until their phase. | |
| Evict to approximate decades | Displaced scripts get rough decade placement but exact ordering within those decades happens in Phases 67-68. | |

**User's choice:** Phase 66 does it all (Recommended)
**Notes:** This makes Phases 67 and 68 unnecessary or in need of repurposing.

---

## Cohort Decade Lineup

| Option | Description | Selected |
|--------|-------------|----------|
| Helpers before build_cohort | 10=predicates, 11=treatment_payer, 12=surveillance, 13=survivorship, 14=build_cohort. Reflects dependency order: helpers exist before the script that sources them. | Yes |
| Build_cohort first, helpers after | 10=predicates, 11=build_cohort, 12=treatment_payer, 13=surveillance, 14=survivorship. Groups the main script prominently, helpers follow. | |
| You decide | Claude picks the best ordering based on the dependency chain. | |

**User's choice:** Helpers before build_cohort (Recommended)
**Notes:** None

---

## Treatment Suffix Handling

### Test Script Placement

| Option | Description | Selected |
|--------|-------------|----------|
| Move to test decade (80-89) | Keeps treatment decade for analysis scripts only. Test scripts belong with other tests. Clean separation of concerns. | Yes |
| Keep in treatment decade (20-39) | Tests stay near the code they verify. Treatment decade has room (only using 20-27 of 20 slots). | |

**User's choice:** Move to test decade (80-89) (Recommended)
**Notes:** None

### A/B Suffix Convention

| Option | Description | Selected |
|--------|-------------|----------|
| Eliminate suffixes | Each script gets a clean unique number. No more a/b confusion. | Yes |
| Keep a/b suffixes | Preserve paired pattern. Makes the test relationship explicit. | |

**User's choice:** Eliminate suffixes (Recommended)
**Notes:** None

---

## Numbering Sequence

### Treatment Sequence (20-29)

| Option | Description | Selected |
|--------|-------------|----------|
| Proposed sequence (20-29) | 20=inventory, 21=investigate_unmatched, 22=investigate_unmatched_ndc, 23=combine_reports, 24=treatment_codes_resolved, 25=treatment_durations, 26=treatment_episodes, 27=drug_name_resolution, 28=episode_classification, 29=first_line_and_death_analysis | Yes |
| Adjust ordering | Rearrange some scripts | |

**User's choice:** Looks good (proposed sequence)
**Notes:** 10 treatment scripts require 20-29, exceeding the original "20-27" estimate.

### Remaining Decades

| Option | Description | Selected |
|--------|-------------|----------|
| Claude decides | Claude determines exact numbering within 40-49 (cancer), 60-69 (payer/QA), 70-79 (outputs), 80-89 (tests), 90-99 (ad-hoc) based on dependency analysis. | Yes |
| Review each decade | Walk through each decade one by one to approve the ordering. | |

**User's choice:** Claude decides (Recommended)
**Notes:** None

### Gantt Export Scripts

| Option | Description | Selected |
|--------|-------------|----------|
| Keep with cancer analysis (40-59) | Gantt data is derived from treatment episodes + cancer linkage. Keeping them near cancer scripts reflects the data flow. | Yes |
| Move to outputs (70-79) | Gantt CSV export is an output/report artifact. Groups with other visualization and report scripts. | |
| You decide | Claude picks based on dependency analysis. | |

**User's choice:** Keep with cancer analysis (40-59)
**Notes:** None

---

## Claude's Discretion

- Exact numbering within each remaining decade (40-59, 60-69, 70-79, 80-89, 90-99)
- How to handle decade capacity issues (payer/QA may exceed 10 slots)
- Smoke test implementation for full-pipeline validation

## Deferred Ideas

- Phases 67-68 need repurposing or removal from roadmap
