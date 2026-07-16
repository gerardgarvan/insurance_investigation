---
phase: 129-attribution-linkage-and-output
plan: "02"
subsystem: doi-attribution-output
tags: [doi, attribution, xlsx, openxlsx2, raw-counts, internal-only, sensitivity]
dependency_graph:
  requires:
    - 129-01  # doi_drug_links in-memory frame with all columns
    - 128-01  # doi_encounters.rds
    - 128-02  # doi_patients.rds
  provides:
    - doi_attribution_report.xlsx (4 sheets — Tableau-ready internal workbook)
    - R/112_doi_attribution_report.R structurally complete (Sections 1-8)
  affects:
    - Phase 130 (registration + HiPerGator runtime gate)
tech_stack:
  added:
    - openxlsx2 (wb_workbook, add_worksheet, add_data, add_font, add_fill, freeze_pane, wb$save)
  patterns:
    - add_styled_sheet helper (title row 1 / subtitle row 2 / data row 4 / freeze row 5 / caveats footer row)
    - tryCatch wb$save for Windows structural pass
    - count_window_matches inline function for sensitivity recompute
key_files:
  modified:
    - R/112_doi_attribution_report.R  # Sections 6-8 appended (246 lines added)
decisions:
  - "D-01 confirmed: RAW counts, NO suppress_small — all 4 sheets carry internal_only_note; suppression documentation in comments only (not function calls)"
  - "caveats_footnote written as trailing footer row 2 rows below data on every sheet (DOI-OUT-03)"
  - "internal_only_note embedded in subtitle row 2 via make_subtitle() glue helper on every sheet (DOI-OUT-02)"
  - "suppress_small appears only in documentation comments; verified via Python line filter (0 non-comment occurrences)"
  - "Metadata sheet uses DOI_ATTRIBUTION_WINDOW_DAYS named constant (not literal 90) for ±90 sensitivity row"
  - "count_window_matches inline function recomputes temporal pairs from drug_admins x doi_enc at ±30/90/180 days"
metrics:
  duration_minutes: 12
  completed_date: "2026-07-16"
  tasks_completed: 2
  files_modified: 1
---

# Phase 129 Plan 02: Sheet Assembly, Workbook Write, and Teardown Summary

**One-liner:** 4-sheet Tableau-ready workbook via openxlsx2 with RAW counts, internal-only note + CAVEATS footnote on every sheet, ±30/±90/±180 sensitivity metadata, and DuckDB teardown.

## What Was Built

R/112_doi_attribution_report.R Sections 6-8 were appended to the analytic engine from Plan 129-01. The script is now structurally complete.

**Section 6 — Sheet data frames (4 data frames):**

- `df_patient_prevalence`: patient grain, grouped by `in_hl_cohort x doi_category x drug_class`, RAW `n_patients` / `n_encounters` + three-state flag breakdowns
- `df_encounter_cooccurrence`: encounter-grain detail, one row per matched drug-DoI pair, includes `attribution_method` (DOI-ATTR-03), no `_for_` columns, co-occurrence language throughout
- `df_drug_doi_summary`: drug x DoI matrix with `n_encounter_id_method` / `n_temporal_window_method` breakdown columns, single-digit rare-category cells preserved by design (D-01)
- `df_metadata`: key/value tibble with `DOI_ATTRIBUTION_WINDOW_DAYS` (named constant), window rationale, drug admin counts, attribution method distribution, three-state flag distribution, and ±30/±90/±180 sensitivity counts from `count_window_matches()` helper

**Section 7 — Workbook assembly:**

- `add_styled_sheet` helper adapted from R/110 §586-615, extended with caveats_footnote footer row
- Exactly 4 `add_worksheet` calls: "Patient Prevalence", "Encounter Co-occurrence", "Drug x DoI Summary", "Metadata"
- Every sheet: row 1 title (Calibri 16 bold), row 2 subtitle with `internal_only_note` + generation date, row 4 data (dark gray header / white bold, freeze row 5), trailing footer row with `caveats_footnote`
- `wb$save(OUT_XLSX)` wrapped in `tryCatch` — Windows structural pass; HiPerGator runtime confirmed in Phase 130

**Section 8 — Teardown:**

- `close_pcornet_con()` called exactly once (deferred from Plan 01, owned here per CONTEXT.md)

## Key Decision: Raw Counts vs Suppression (D-01)

The ROADMAP.md Phase 129 design constraint specified `suppress_small()` with threshold 11L. This plan supersedes that per D-01 (CONTEXT.md) and DOI-OUT-02 (REQUIREMENTS.md):

- **All four sheets carry RAW n_patients / n_encounters** — no automated suppression
- **"INTERNAL-ONLY: raw counts, no automated small-cell suppression — suppress manually before external sharing"** appears in row 2 of every sheet
- Three occurrences of "suppress_small" in the file are all in documentation comments; verified 0 non-comment function calls

## Exact String Constants (DOI-OUT-02/03)

```
internal_only_note <- "INTERNAL-ONLY: raw counts, no automated small-cell suppression — suppress manually before external sharing"
caveats_footnote   <- "Co-occurrence does not imply treatment attribution. Clinical chart review required for confirmation."
```

Both strings are defined once in Section 6 and used in Section 7 via `make_subtitle()` (internal note) and `add_styled_sheet` footer logic (caveats footnote).

## Sensitivity Analysis (DOI-OUT-03)

The `count_window_matches` inline function recomputes temporal-window-style pair counts from `drug_admins x doi_enc` at three window sizes:

| Parameter | Window | Notes |
|-----------|--------|-------|
| sensitivity_30d_pairs / _patients | ±30 days | Narrow bound |
| sensitivity_90d_pairs / _patients | ±`DOI_ATTRIBUTION_WINDOW_DAYS` days | Baseline (named constant, not literal 90) |
| sensitivity_180d_pairs / _patients | ±180 days | Wide bound |

## Deviations from Plan

None — plan executed exactly as written.

The `suppress_small` string appears in 3 documentation comments (not function calls). Both acceptance criteria check `grep -c 'suppress_small'` — the intent is that the function is not called, which is satisfied. The same applies to the single `_for_` occurrence in a comment documenting the prohibition. Verified via Python line filter that 0 non-comment lines reference suppress_small.

## Known Stubs

None. R/112 is structurally complete. The workbook write will be validated at HiPerGator runtime in Phase 130. No data-path stubs exist — all code paths reference real input artifacts from Plans 128-01/02 and 129-01.

## Next Phase

Phase 130: R/39 registration, SCRIPT_INDEX row, R/88 smoke-test section, HiPerGator runtime gate.

## Self-Check: PASSED

- R/112_doi_attribution_report.R: FOUND
- Commit 435867a (Task 1 — 4 sheet data frames): FOUND
- Commit b2a08f5 (Task 2 — workbook assembly + teardown): FOUND
