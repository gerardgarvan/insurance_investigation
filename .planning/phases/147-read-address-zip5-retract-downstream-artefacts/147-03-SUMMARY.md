---
phase: 147-read-address-zip5-retract-downstream-artefacts
plan: 03
status: complete
completed: 2026-08-18
---

# 147-03 Summary — HiPerGator Re-Run Checkpoint

## What was done

- Pre-148 archiving: user confirmed no outputs required renaming (re-run date matched existing
  filenames; both R/115 and R/116 produce date-stamped outputs that include today's date).
- R/115 → R/116 → R/88 run in order on HiPerGator 2026-08-18.
- 147-DISCOVERY.md §4 before/after table populated; §6 R/88 result added.

## Key findings

**Invariants held:**
- `zip9_observed` = 1,516,469 (unchanged ✓)
- `none` = 158,699 (unchanged ✓)

**Tier 2/3 outcome (the headline):**
- `zip5_modal` = 0 post-148 (same as pre-148)
- `zip5_no_zip9` = 0 — Tier 3's population is zero

The fix reads ADDRESS_ZIP5 directly (and correctly), but the 157,472 approximable
encounters (no direct ZIP9) all resolve to `no_zip5` via Branch C: their matched address
records have ZIP5 = NA after sentinel-nulling. The R/116 pre-approximation matrix confirms
zero encounters have `zip9_na=TRUE AND zip5_na=FALSE`.

**Implication for Phase 147:**
The centroid crosswalk (Tier 3) has no population to serve. Phase 147 is complete as a
diagnostic + fix phase. No centroid work is needed.

**R/88:** 778/781 — 3 pre-existing failures (15ad, 15ae, Phase 114 liposomal). No new regressions.

## Artifacts updated

- `.planning/phases/147-read-address-zip5-retract-downstream-artefacts/147-DISCOVERY.md` — §4 table and §6 added
- `output/zip_stability_counts_20260818.xlsx` — new R/115 run
- `output/encounter_ses_index_20260818.rds` — new R/116 run
- `output/encounter_ses_index_summary_20260818.xlsx` — new R/116 run
- `output/zip9_imputed_assignment_20260818.rds` — new R/115 run

## Decisions carried forward

- Phase 147 centroid crosswalk: NOT worth pursuing (zip5_no_zip9 = 0).
- Plan 4 (downstream artefact retraction) proceeds as planned.
