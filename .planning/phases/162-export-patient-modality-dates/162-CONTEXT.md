# Phase 162 Context — Export Patient Modality Dates (no _any columns)

## Goal

Wire the already-written `R/162_export_patient_modality_dates.R` into the
pipeline's registration and validation infrastructure, confirm its output path
and internal-only classification, and produce a verified HiPerGator run.

## Background

Phase 159 (lab surveillance modalities) wired `build_patient_modality_dates()`
into R/147, producing `surveillance_patient_modality_dates_<date>.rds` — a
wide per-patient table with one column per modality, in both primary-tier
(`n_dates_<modality>`) and sensitivity-inclusive (`n_dates_<modality>_any`)
forms. The per-patient table is marked **INTERNAL only** in the 0925
surveillance workbook KEY sheet (it contains patient `ID` values and is not
cleared for release outside the enclave).

`R/162_export_patient_modality_dates.R` was written to produce a CSV version of
that table with the `_any` columns intentionally removed — keeping only the
primary-tier date counts. The script already exists; this phase registers and
validates it.

## Scope

**In scope:**
- Add an INTERNAL-use header comment to `R/162` (the script has none)
- Register `R/162` in `R/39_run_all_investigations.R` (append to
  `investigation_scripts`; R/147 must precede it)
- Add a `R/SCRIPT_INDEX.md` row for R/162
- Add `R/88` Section 15an with structural smoke-test checks (SMOKE-162-01)
- HiPerGator run checkpoint confirming the CSV is produced

**Out of scope:**
- HIPAA suppression (file stays under `/blue`, not shared outside the enclave)
- Dropping or hashing the `ID` column (internal use only)
- Adding sensitivity-inclusive (`_any`) columns back
- Changes to `R/147` or `utils_surveillance.R`

## Design Decisions

| ID | Decision |
|----|---------|
| D-01 | CSV stays **INTERNAL** — `ID` column retained, no suppression |
| D-02 | `_any` columns are **intentionally excluded** — keeps primary-tier counts only; sensitivity-inclusive totals (e.g. `n_dates_complete_blood_count_any`) are not in the CSV |
| D-03 | Output path: `output/patient_modality_dates_no_any_<YYYYMMDD>.csv` |
| D-04 | Registration follows `R/147` in `investigation_scripts` (dependency order) |

## Key Facts

- Script already exists at `R/162_export_patient_modality_dates.R`
- Source RDS pattern: `output/surveillance_patient_modality_dates_*.rds`
- Stops loudly if no RDS is present (existing `stop()` guard)
- Next R/88 section label: **15an**
- Last `investigation_scripts` entry before R/162: `R/147_surveillance_modality_frequency.R`

## Requirements

Phase-specific IDs (no REQUIREMENTS.md entries — standalone wiring phase):

| ID | Requirement |
|----|------------|
| REG-162-01 | R/162 appears in `R/39` `investigation_scripts`, after R/147 |
| REG-162-02 | R/162 has a SCRIPT_INDEX.md row in the Post-Renumber Investigations table |
| SMOKE-162-01 | R/88 Section 15an passes all 8 checks: 4 structural (R/162 file existence, R/39 registration, output path pattern, INTERNAL comment) + 4 output-level (no `_any` column names in CSV header, row count ≈ 9,331, `ID` unique and non-missing, at least one `n_dates_` column present); output-level checks wrapped in `if (length(csv_files) > 0)` so offline runs skip rather than fail |
| RUN-162-01 | HiPerGator run confirmed: CSV produced, patient × column counts logged |

## Success Criteria

1. `R/39_run_all_investigations.R` lists `R/162_export_patient_modality_dates.R` in `investigation_scripts`, after `R/147`
2. `R/SCRIPT_INDEX.md` has a row for R/162 noting it is INTERNAL and that `_any` columns (sensitivity-inclusive date counts) are intentionally excluded
3. R/88 Section 15an passes all 8 checks (SMOKE-162-01): file existence, R/39 registration, output path pattern, INTERNAL comment (4 structural always-run) + no `_any` in CSV header, row count ≈ 9,331, ID unique + non-missing, at least one `n_dates_` column (4 output-level, skipped offline)
4. HiPerGator run produces `output/patient_modality_dates_no_any_<date>.csv` with patient × column counts and RDS source filename + date logged
