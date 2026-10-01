---
phase: 161
plan: "02"
subsystem: diagnostics
tags: [death-dates, person-years, follow-up, duckdb, R]
key-files:
  modified:
    - R/161_diag_anchor_followup.R
decisions:
  - "Section 8b inserted verbatim from plan; no architectural changes needed"
metrics:
  completed: 2026-10-01
---

# Phase 161 Plan 02: Death-row Detail Block Summary

Inserted `# ---- 8b. Death-row detail (161-02)` into `R/161_diag_anchor_followup.R`
immediately before the `# ---- 9. Write outputs` section.

## What changed

`R/161_diag_anchor_followup.R` gained a new section (69 lines) that:

1. Pulls all DEATH rows for HL patients from DuckDB at row level (not grouped), casting
   DEATH_SOURCE and DEATH_DATE_IMPUTE as VARCHAR conditionally on column presence and
   IMPUTE_STATUS.
2. Joins against `diag` to derive `last_observed` (max of last_enc_any / last_activity_any)
   and flags each death row as `consistent` if `DEATH_DATE >= last_observed - 30 days`.
3. Summarises per-patient into `death_detail`: n_decedents, n_single_plausible,
   n_single_implausible, n_conflicting, n_conflicting_resolved, n_conflicting_unresolved,
   n_imputed_bdm, n_imputed_and_implausible, impute_flag_status.
4. Tabulates DEATH_SOURCE distribution across all HL decedent rows.
5. Projects person-years under a D2/D3/D6 approximation: picks the earliest consistent
   death date per patient, then computes follow-up to min(death_proj, obs_end, CUTOFF_DATE),
   flooring at hl_anchor_date. Emits person_years_projected_d2 and pct_increase_d2.
6. Saves three CSVs: `08b_death_detail.csv`, `08b_death_source.csv`,
   `08b_person_years_projection.csv`.

Commit: `ebb49fb`

## Steps that require HiPerGator (not executed locally)

Steps 2-4 from the plan cannot run locally because they require the rebuilt DuckDB
(`pcornet.duckdb`) on the HiPerGator filesystem and the R/4.4.2 module.

**Step 2 — Run the script on HiPerGator:**

```bash
module load R/4.4.2
Rscript -e 'options(width = 200); source("R/161_diag_anchor_followup.R")'
```

**Step 3 — Update 161-CONTEXT.md** under "Diagnostic findings" with:
- All fields from `death_detail` (n_conflicting, n_conflicting_resolved,
  n_conflicting_unresolved, n_imputed_bdm)
- DEATH_SOURCE distribution (note whether codes are N/S/D/L/T or another scheme,
  as 161-03 must map them)
- `person_years_projected_d2` and `pct_increase_d2`
- Whether `impute_flag_status = "ok"` or another value

**Step 4 — Commit** the updated 161-CONTEXT.md (do not commit patient-level output CSVs).

## Acceptance criteria (HiPerGator only)

- `161-CONTEXT.md` records n_conflicting, n_conflicting_resolved, n_conflicting_unresolved,
  n_imputed_bdm, the DEATH_SOURCE distribution, and person_years_projected_d2.
- The 46 zero-or-negative and 261 post-death-activity counts reproduce; any difference
  is explained (the rebuild only changed DEATH_DATE_IMPUTE typing, not dates).
- Decedents whose earliest death date is more than 30 days before last_observed number
  261 (same definition as the original diagnostic).
- Script exits cleanly with no DuckDB type errors.

## Deviations from Plan

None — the code block was inserted exactly as written in the plan.
