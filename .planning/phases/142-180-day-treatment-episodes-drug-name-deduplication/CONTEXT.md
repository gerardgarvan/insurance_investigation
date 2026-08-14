# Phase 142 Context: 180-Day Treatment Episodes + Drug-Name Deduplication

## Goal
Produce 180-day versions of the Gantt CSVs (`gantt_episodes_180.csv`, `gantt_detail_180.csv`) with the same schema as the existing 90-day output, and fix drug-name deduplication so that salt/acid variants (e.g. "Vinblastine Sulfate" vs "Vinblastine") collapse to one canonical name per episode.

## User Intent
- Colleague needs a 180-day Gantt CSV to compare treatment episode windows
- Same gap logic as 90-day: window measured from episode start date (not gap between consecutive dates)
- Same output columns as existing `gantt_episodes.csv` / `gantt_detail.csv`
- Drug dedup: colleague flagged "Vinblastine" and "Vinblastine Sulfate" appearing as separate entries in `drug_names`; fix via alias in `DRUG_NAME_ALIASES` and audit for similar pairs

## Current Architecture

| File | Role |
|------|------|
| `R/00_config.R` | Defines `GAP_THRESHOLD <- 90`, `MEDICATION_LOOKUP`, `DRUG_NAME_ALIASES`, `canonicalize_drug_name()` |
| `R/26_treatment_episodes.R` | Reads raw chemo encounters, resolves drug names via 3-tier lookup, calls `calculate_episodes_detailed(gap_threshold = GAP_THRESHOLD)`, writes `treatment_episodes.rds` + `treatment_episode_detail.rds` |
| `R/52_gantt_v2_export.R` | Reads the RDS files from R/26, enriches with cancer categories / dx codes / age, writes `gantt_episodes.csv` + `gantt_detail.csv` |

## Drug-Name Dedup Root Cause
`DRUG_NAME_ALIASES` in `R/00_config.R` (line ~2637) handles doxorubicin variants but has no vinblastine entry. The RxNorm path yields "vinblastine sulfate 1 MG/ML Injectable S" for CUI 239178, which survives as a different token from "Vinblastine" (from MEDICATION_LOOKUP via J9360/67228/11198). The fix is one line in `DRUG_NAME_ALIASES`:
```r
"vinblastine sulfate" = "Vinblastine",
```
Also audit for other salt/HCl/phosphate variants in the same style as doxorubicin.

## 180-Day Episode Approach
- `calculate_episodes_detailed()` in R/26 already accepts `gap_threshold` parameter
- Drug name resolution (the expensive 3-tier lookup) runs once on `all_detail` regardless of threshold
- After resolving drug names, re-run `calculate_episodes_detailed(all_detail, gap_threshold = 180)` and `annotate_detail_with_episodes()` to produce 180-day episodes from the same underlying data
- Save as `treatment_episodes_180.rds` + `treatment_episode_detail_180.rds`
- New script `R/142_gantt_180_export.R` reads these RDS files and runs the same export logic as R/52 (same column order, same semicolon separator), writing `gantt_episodes_180.csv` + `gantt_detail_180.csv`

## Out of Scope
- No new SLURM scripts (run interactively)
- No changes to payer mapping or cohort filters

## Decisions
- D-01 (Episode rule — confirmed by Phase 143 observed maxima):
  An episode covers up to N days from its first treatment date (window from episode start).
  A treatment date falling N or more days after the episode start begins a new episode.
  Episodes therefore never exceed N-1 days in length.

  Evidence from Phase 143 output: max chemotherapy episode length is 89 days at 90-day
  window (median 56) and 179 days at 180-day window (median 100). Both maxima sit exactly
  one day under the threshold. This is only possible under a window-from-episode-start rule;
  a gap-between-doses rule would produce episodes of unbounded length.

  This is NOT a gap-between-doses rule.
- D-02: Canonical vinblastine name = "Vinblastine" (matches existing MEDICATION_LOOKUP majority)
- D-03: Output files named `*_180.csv` to distinguish from 90-day files
- D-04: 180-day RDS files named `treatment_episodes_180.rds` / `treatment_episode_detail_180.rds`
- D-05: The drug-name fix applies to both windows. R/26 and R/52 are re-run so gantt_episodes.csv and gantt_detail.csv also lose the duplicate. Prior 90-day outputs are archived as *_pre142.csv before regeneration, so the change is reversible and the before/after is auditable.
