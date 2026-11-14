---
phase: 203-no-treatment-patient-characterization
plan: "03"
subsystem: characterization-workbook
tags: [no-treatment, characterization, workbook, suppression, openxlsx]
dependency_graph:
  requires: ["203-02"]
  provides: ["NOTX-05-rule-doc", "NOTX-07-workbook"]
  affects: []
tech_stack:
  added: []
  patterns: ["openxlsx workbook with KEY-first sheet order", "suppress_small at display time only", "UF colour styles via createStyle"]
key_files:
  created: []
  modified:
    - R/203_no_treatment_characterization.R
decisions:
  - "D-203-01: treatment_observable rule proposed but NOT applied; documented in D_candidate_rules sheet for team decision"
metrics:
  duration_minutes: 15
  completed_date: "2026-11-14"
  tasks_completed: 2
  files_modified: 1
---

# Phase 203 Plan 03: No-Treatment Characterization — Candidate Rule and Workbook

**One-liner:** Adds `treatment_observable` eligibility rule (documented, not applied) and assembles a 6-sheet UF-styled xlsx with `<11` suppression; patient-level RDS stays in `output/internal/` only.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | NOTX-05 candidate treatment_observable rule block | 7a0a6bd | R/203_no_treatment_characterization.R |
| 2 | Workbook assembly — KEY + 5 sheets, suppression, UF colours | 7a0a6bd | R/203_no_treatment_characterization.R |

## What Was Built

**Section 10 (NOTX-05):** Added `treatment_observable` column to `char_pt` — logical derived from `(n_enc_peri_dx >= 1) & (!window_truncated) & (!window_date_missing)`. Also derived `tx_obs_false_reason` (mutually exclusive: dates_missing / window_truncated / no_peri_dx_encounter). Built `candidate_rules_tbl` with per-group TRUE/FALSE counts and false-reason breakdown. Prominent "RULE NOT APPLIED — proposed team decision item (D-203-01)" label appears in first row and throughout comments. Rule is never used as a filter anywhere.

**Section 11 (NOTX-07):** Assembled workbook via openxlsx:
- KEY (leftmost, added first): run date, script path, all 4 pinned inputs with pinned TRUE/FALSE, group definitions, sheet descriptions, suppression note, D-203-01 note.
- A_profile: all NOTX-01..NOTX-04 characteristics with no_treatment and treated counts in adjacent columns (long table pivoted wide by group).
- B_reasons_waterfall: 3 reason rows + total for no_treatment patients; pct suppressed when n < 11.
- C_by_source: window_truncated, single_source_care, payer by SOURCE x group.
- D_candidate_rules: candidate_rules_tbl with the RULE NOT APPLIED label as first row.
- QC: population reconciliation (no_tx + treated == total), window_date_missing count, R169/TR join miss counts, suppression confirmation.

UF colours: `#0021A5` blue header, `#FA4616` orange accent. Dated filename glue pattern. `char_pt` with patient IDs written only to `output/internal/203_no_treatment_characterization_<date>.rds`.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all columns and frames are wired from live `char_pt` data. The script stops on HiPerGator with available column names if any probe-candidate name is absent.

## Self-Check: PASSED

- R/203_no_treatment_characterization.R — present and parses clean (rcheck.sh parse exits 0)
- Commit 7a0a6bd — present (git log confirmed)
- All 6 sheet names confirmed via grep: KEY, A_profile, B_reasons_waterfall, C_by_source, D_candidate_rules, QC
- suppress_small: 21 matches; 0021A5: 1 match; FA4616: 1 match
- filter(treatment_observable: 0 matches (rule not applied as filter)
- output/internal path: 1 match
