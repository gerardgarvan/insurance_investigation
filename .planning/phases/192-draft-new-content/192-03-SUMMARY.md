---
phase: 192-draft-new-content
plan: 03
subsystem: documentation
tags: [analytic-manual, am-draft, data-cleaning, repo-only-domains, draft-check]

requires:
  - phase: 192-draft-new-content/192-01
    provides: Grammar rules, map IDs, draft-check subcommand
  - phase: 192-draft-new-content/192-02
    provides: AM-DRAFT.md with §0–§3, §4 frame with BEGIN/END markers, §5–§8, §11, A1–A4
  - phase: 190-evidence-map
    provides: AM-EVIDENCE-MAP.md AM-MAP-02 (12 repo-only domain IDs and sources)
  - phase: 191-verify-existing-entries
    provides: AM-VERDICTS.md (OPEN/CONFIRMED D-191 decisions)

provides:
  - 12 repo-only §4 domain blocks (SHS, CHM, NRM, REG, EPI, ANT, CBC, RUR, SDI, DOI, CLS, PDE) inserted between markers in AM-DRAFT.md
  - 192-03-SOURCES.md: source confirmation for all 12 AM-MAP-02 IDs
  - draft-check --stage full and validate both exit 0

affects:
  - 193-produce-updated-manual (consumes AM-DRAFT.md DRAFTED/CORRECTION units)
  - 194-team-review (TEAM-INPUT-NEEDED items become team questions)

tech-stack:
  added: []
  patterns:
    - Four-field §4 domain format (Expected Structure / Observed Issues / Cleaning Rules Applied / Unresolved Issues)
    - Citation form: path:function():Lnn-Lnn or path:CONFIG_KEY:Lnn-Lnn

key-files:
  created:
    - .planning/phases/192-draft-new-content/192-03-SOURCES.md
    - .planning/phases/192-draft-new-content/192-03-SUMMARY.md
  modified:
    - .planning/phases/192-draft-new-content/AM-DRAFT.md

key-decisions:
  - "Episode segmentation (gap from episode_start >= GAP_THRESHOLD=90), relapse/refractory classification (90-day break from end of initial tx, DEC-007), and Gantt display window (90-day vs 180-day export) are three distinct constructs — one decision does not govern the others"
  - "SDI geographic unit is ZIP5 (not tract) per R/116 implementation"
  - "CBC definition (WBC 6690-2 + Hgb 718-7 + PLT 777-3 same date) is specific to the distance-CBC analysis, not all lab encounters"
  - "Nivo+AVD regimen label requires post-2024-01-01 episode start guard (not just drug combination)"

patterns-established:
  - "All repo-only domain blocks use TEAM-INPUT-NEEDED for fields with no source; code not locatable goes under Unresolved Issues"

requirements-completed:
  - AM-FILL-02

duration: 90min
completed: 2026-10-28
---

# Phase 192 Plan 03: Draft New Content (Repo-Only Domains) Summary

**12 repo-only §4 domain blocks (SHS through PDE) drafted in four-field format from code citations; draft-check --stage full exits 0; 10-unit spot-check performed with two inaccuracies corrected inline.**

## Performance

- **Duration:** ~90 min
- **Started:** 2026-10-28T00:00:00Z
- **Completed:** 2026-10-28
- **Tasks:** 3 (Task 0: sources, Task 1: draft insertion, Task 2: spot-check + summary)
- **Files modified:** 2 (AM-DRAFT.md, 192-03-SOURCES.md created)

## Accomplishments

- Confirmed sources for all 12 AM-MAP-02 repo-only domain IDs against actual R code before drafting
- Inserted 12 four-field domain blocks between the `<!-- BEGIN REPO-ONLY DOMAINS -->` / `<!-- END REPO-ONLY DOMAINS -->` markers in §4; no text edited outside §4 and `## Not drafted`
- Spot-checked 10 DRAFTED units across all 12 domains; corrected two inaccuracies found during check (REG Nivo+AVD label missing date guard and `!has_bleo` requirement; PDE death_flag values incorrect)
- `draft-check --stage full` and `validate` both exit 0 after all corrections

## Units by Status per Domain

| Domain | DRAFTED | TEAM-INPUT-NEEDED | OPEN-QUESTION-SEE-§8 | Total |
|--------|---------|-------------------|----------------------|-------|
| SHS | 2 | 2 | 0 | 4 |
| CHM | 3 | 1 | 0 | 4 |
| NRM | 3 | 1 | 0 | 4 |
| REG | 4 | 1 | 0 | 5 |
| EPI | 3 | 2 | 0 | 5 |
| ANT | 3 | 1 | 0 | 4 |
| CBC | 3 | 2 | 0 | 5 |
| RUR | 3 | 1 | 0 | 4 |
| SDI | 3 | 1 | 0 | 4 |
| DOI | 3 | 2 | 0 | 5 |
| CLS | 3 | 1 | 0 | 4 |
| PDE | 3 | 1 | 0 | 4 |
| **Total** | **36** | **16** | **0** | **52** |

## TEAM-INPUT-NEEDED List (repo-only domains)

Items with no locatable source or pending Sharon review:

| Domain | Field | Reason |
|--------|-------|--------|
| SHS | Observed Issues | Not documented in available sources |
| SHS | Unresolved Issues | Not documented in available sources |
| CHM | Unresolved Issues | Not documented in available sources |
| NRM | Unresolved Issues | Not documented in available sources |
| REG | Observed Issues | Not documented in available sources |
| REG | Unresolved Issues (first-line qualifier) | is_first_line column logic pending Sharon |
| EPI | Observed Issues | Not documented in available sources |
| EPI | Unresolved Issues (end-of-treatment date) | Pending Sharon confirmation (same as S4-TRT-04) |
| ANT | Unresolved Issues | D-08a noted; no further issues found |
| CBC | Observed Issues | Not documented in available sources |
| CBC | Unresolved Issues | Not documented in available sources |
| RUR | Unresolved Issues (RUCC fallback) | Not located in R/116 code |
| SDI | Unresolved Issues | Not documented in available sources |
| DOI | Observed Issues | Not documented in available sources |
| DOI | Unresolved Issues | Not documented in available sources |
| CLS | Unresolved Issues (episode-level NHL exclusion) | Not located in a single function |

## Not-Drafted List

None. All 12 AM-MAP-02 repo-only IDs are now drafted inside the markers. The `## Not drafted` section in AM-DRAFT.md reflects this.

## Spot-Check Results (10 DRAFTED units)

| # | Map ID | Domain | Field | Source opened | Result |
|---|--------|--------|-------|--------------|--------|
| 1 | S4-SHS-01 | SHS | Cleaning Rules (NA assignment) | R/169_single_source_care.R:L64-L86 | PASS — single_source_care=NA when n_sources=0 confirmed |
| 2 | S4-CHM-01 | CHM | Expected Structure | R/utils/utils_treatment.R:get_chemo_hits():L181-L290 | PASS — three-table detection, source column confirmed |
| 3 | S4-NRM-01 | NRM | Cleaning Rules (brand-to-generic) | R/00_config.R:L2750-L2814 | PASS — adriamycin → Doxorubicin, vinblastine sulfate → Vinblastine, liposomal variants confirmed |
| 4 | S4-REG-01 | REG | Cleaning Rules (Nivo+AVD) | R/28_episode_classification.R:L328-L352 | FAIL — draft missing `!has_bleo`, `n_unique_drugs==4L`, post-2024 date guard. Fixed inline. |
| 5 | S4-EPI-01 | EPI | Cleaning Rules (episode segmentation) | R/25_treatment_durations.R:assign_episode_ids():L492-L512 | PASS — new episode when treatment_date - episode_start >= gap_threshold confirmed |
| 6 | S4-ANT-01 | ANT | Cleaning Rules (first-line dose) | R/utils/utils_anthracycline_echo.R:last_anthracycline_dose():L58-L90 | PASS — first_line==TRUE filter; last_dose_ever_dt max across all confirmed |
| 7 | S4-CBC-01 | CBC | Cleaning Rules (three-LOINC requirement) | R/utils/utils_distance_cbc.R:build_cbc_events():L114-L143 | PASS — n_loincs==3L filter confirmed |
| 8 | S4-RUR-01 | RUR | Expected Structure (categories) | R/116_encounter_ses_index.R:L214-L237 | PASS — Metropolitan 1-3, Micropolitan 4-6, Small town 7-9, Rural 10, Not coded 99 confirmed |
| 9 | S4-DOI-01 | DOI | Cleaning Rules (DX_TYPE gating) | R/utils/utils_doi.R:is_doi_code():L52-L78 | PASS — gated on c("09","10"); ICD-9 vs ICD-10 split; SM/missing excluded |
| 10 | S4-PDE-01 | PDE | Cleaning Rules (death_flag values) | R/utils/utils_death.R:resolve_death_date():L50-L116 | FAIL — draft said "alive/deceased-confirmed/deceased-inferred"; actual values: plausible/implausible_post_activity/conflicting_resolved/conflicting_unresolved/no_death_record. Fixed inline. |

## Task Commits

1. **Task 0: Source confirmation** - `7d88585` (chore)
2. **Task 1: Draft §4 content in place** - `e3a2777` (feat)

## Files Created/Modified

- `.planning/phases/192-draft-new-content/192-03-SOURCES.md` — source confirmation for all 12 repo-only domain IDs
- `.planning/phases/192-draft-new-content/AM-DRAFT.md` — 12 repo-only domain blocks inserted; Not-drafted section updated

## Decisions Made

- Episode segmentation (GAP_THRESHOLD=90 days from episode_start), relapse/refractory classification (DEC-007, 90-day break from end of initial tx), and Gantt display window (90-day vs 180-day export) are three distinct constructs. A decision about one does not govern the others.
- SDI is assigned at ZIP5 geographic unit (not census tract) per R/116 implementation.
- CBC definition (WBC 6690-2 + Hgb 718-7 + PLT 777-3 same date) is analysis-specific: used only in the distance-CBC association analysis.
- Nivo+AVD label requires `episode_start >= 2024-01-01` date guard and `!has_bleo`, in addition to the drug combination.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Nivo+AVD regimen label description was incomplete**
- **Found during:** Task 2 spot-check (S4-REG-01)
- **Issue:** Draft described Nivo+AVD as "nivolumab + doxorubicin + vinblastine + dacarbazine" without the `!has_bleo` requirement, `n_unique_drugs == 4L` constraint, or post-2024-01-01 date guard that are in the code
- **Fix:** Updated S4-REG-01 Nivo+AVD unit to include all code conditions; cite updated to L333-L336
- **Files modified:** .planning/phases/192-draft-new-content/AM-DRAFT.md
- **Committed in:** e3a2777 (Task 1 commit, corrected before final commit)

**2. [Rule 1 - Bug] PDE death_flag values were wrong**
- **Found during:** Task 2 spot-check (S4-PDE-01)
- **Issue:** Draft described death_flag as "alive, deceased-confirmed, deceased-inferred" but the actual code values are: plausible, implausible_post_activity, conflicting_resolved, conflicting_unresolved, no_death_record
- **Fix:** Replaced the description with the actual five values from resolve_death_date()
- **Files modified:** .planning/phases/192-draft-new-content/AM-DRAFT.md
- **Committed in:** e3a2777 (Task 1 commit, corrected before final commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 — bugs found during spot-check)
**Impact on plan:** Both corrections necessary for accuracy. No scope creep.

## Issues Encountered

- Citation format checker (`am_evidence_map.py draft-check`) requires `path:function()` or `path:CONFIG_KEY` form; bare line-number cites (`path:Lnn-Lnn`) are invalid. Fixed all new citations to use the correct form. R/116 and R/29 are script files without exported functions — cited using uppercase config-variable names (RUCA_PATH, SDI_PATH, DEATH_RDS) as the function token.

## Known Stubs

None. All units either have a DRAFTED status with a valid citation or carry TEAM-INPUT-NEEDED for fields with no available source.

## Next Phase Readiness

- AM-DRAFT.md is complete: all §4 domains drafted (existing and repo-only), §0–§3 and §5–§11 from Plan 02, `draft-check --stage full` exits 0
- Phase 193 can proceed: DRAFTED units are inserted as new text; CORRECTION directives are applied as tracked changes to `AnalyticManual_2026.01.30.docx`
- Phase 194 team review package: TEAM-INPUT-NEEDED items in repo-only domains are the primary unresolved set; §8 OPEN D-191 rows are documented for Sharon/team response

---
*Phase: 192-draft-new-content*
*Completed: 2026-10-28*
