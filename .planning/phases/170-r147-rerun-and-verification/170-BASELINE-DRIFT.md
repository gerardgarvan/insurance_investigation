# 170-BASELINE-DRIFT.md — Baseline Drift Since 2026-10-06

**Generated:** 2026-10-09 (pre-execution of Phase 170 Plan 01)
**Purpose:** Record what changed in R/147's inputs since the 1006 reference run, which verify
checks it affects, and what the expected_differences list should be for the verify harness.

---

## 1. Git commits since 2026-10-06 touching R/147 inputs

```
git log --since=2026-10-06 --name-only --oneline -- \
  R/147_surveillance_modality_frequency.R \
  R/utils/utils_surveillance.R \
  R/utils/utils_death.R \
  R/00_config.R \
  data/reference/surveillance_codeset.xlsx \
  R/03_duckdb_ingest.R
```

**Result (from git log output):**

| Commit  | Message                                               | Phase | Files touched                |
|---------|-------------------------------------------------------|-------|------------------------------|
| 5064b5c | chore(168-01): pin gantt_180 snapshot MD5             | 168   | R/00_config.R                |
| f88dc58 | fix(168-01): confirm HiPerGator paths for chemo-combos| 168   | R/00_config.R                |
| 32c6bf9 | feat(168-01): Task 1 — CONFIG keys, R/170 skeleton    | 168   | R/00_config.R                |
| adc83f0 | feat(165): record D-165-01 — rao_scott selected       | 165   | R/00_config.R                |
| 9c8b601 | feat(165-01): Task 3 — CONFIG keys + utils_distance   | 165   | R/00_config.R                |
| 93fc54d | feat(164-01): T3 — normalize dox variants             | 164   | R/00_config.R                |

**None of the commits since 2026-10-06 touch:**
- `R/147_surveillance_modality_frequency.R`
- `R/utils/utils_surveillance.R`
- `R/utils/utils_death.R`
- `data/reference/surveillance_codeset.xlsx`
- `R/03_duckdb_ingest.R`

**Conclusion for post-1006 changes:** Only `R/00_config.R` has commits since 1006. All those
commits added Phase 165/168 CONFIG keys (distance CBC keys, NHL gantt keys). None affect
surveillance modality constants, codeset paths, or output paths used by R/147.

**The only change affecting R/147's output since 1006 is Phase 163** (DIAGNOSIS exclusion),
which was committed before 2026-10-06 (Phase 163 executed earlier in the timeline). The
Phase 163 DIAGNOSIS exclusion is the expected, intended change.

---

## 2. Impact analysis: which verify checks may move

| Change         | Phase | Impact on verify checks |
|----------------|-------|------------------------|
| Phase 163 DIAGNOSIS exclusion (SC039, SC047, SC065, SC090) | 163 | A_code_presence: 4 rows absent in new. Codeset_summary: 4 codes absent. C_modality_with_sensitivity: Echo/ECG/Mammogram/PFT sensitivity_n=0, any==primary. D_pre_vs_post_anchor: any rows for 4 CHANGED_MODS equal primary rows. QC: "Matched rows, type ok" drops by sum of n_records for SC039+SC047+SC065+SC090. |
| R/00_config.R (165/168 keys) | 165, 168 | None — no surveillance-relevant CONFIG changes. |

**All other verify checks (KEY denominator N, confirmed-cohort N, QC person-years, B, A2, A3, RDS primary columns, unaffected modalities _any) are expected to be identical to the 1006 reference.**

---

## 3. DuckDB file mtime (to fill on HiPerGator)

```bash
stat -c %y /blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb
```

**Fill this on HiPerGator before trusting count-based checks:**

```
DuckDB mtime: ______________________________
```

If the DuckDB mtime is after 2026-10-06, all row-count checks (KEY denominator N = 9,331,
confirmed-cohort N = 9,282, QC person-years = 40,298.9, QC matched-rows drop) may move due
to updated extract data, and verify may legitimately FAIL those checks on a data update rather
than a code regression.

---

## 4. RDS column naming

From `R/147_surveillance_modality_frequency.R` and Phase 162 SUMMARY context:

`build_patient_modality_dates()` produces columns:
- `ID`
- `hl_anchor_date`
- `follow_end`
- `person_years`
- `in_confirmed_cohort`
- `n_dates_<modality>` — one column per modality (primary count)
- `n_dates_<modality>_any` — one column per modality (any-tier count)

The 14 modalities: Echocardiogram, Electrocardiogram, Mammogram, `Pulmonary function test`,
Bone density scan, Colonoscopy, Dental exam, Eye exam, Influenza vaccine, Neurology visit,
Physical exam, Primary care visit, Psychiatry visit, Skin exam.

**Normalised matching pattern (used in verify harness):** `tolower(gsub("[^a-z0-9]", "", x))`

Example: "Pulmonary function test" → "pulmonaryfunctiontest"; its primary col would be
`n_dates_Pulmonary function test` or similar. **The verify harness must discover column names
from `names(readRDS(ref_rds_path))` at runtime — do NOT hardcode them.**

---

## 5. Sheet layout: title/subtitle rows

From code review of R/147 (which uses `openxlsx2` wb_workbook pattern):
- B_modality_primary, A_code_presence, Codeset_summary, A2, A3: **first data row IS the
  header** — no title/subtitle rows above. `read_excel(..., col_types = "text")` returns a
  clean tibble with column names from row 1.
- KEY and QC sheets: written with a two-column key/value layout; first column is label,
  second is value. No title rows — first row of the sheet is the first key/value pair.

**No title/subtitle stripping is needed** — `read_excel()` header detection handles these
sheets correctly.

The `data_rows()` helper in the verify harness should simply return `read_excel()` output
directly (or at most strip rows where all values are NA).

---

## 6. A_code_presence and Codeset_summary: codeset_row_id column

- **A_code_presence**: the column holding codeset_row_id is named `codeset_row_id` (from
  R/147 source, confirmed by Phase 160 Codeset_summary additions). This is the column to
  filter on for EXCLUDED_IDS.
- **Codeset_summary**: per-modality block layout (one row per code per modality, since
  Phase 160). The column holding codeset_row_id is also `codeset_row_id`.
  The 4 excluded codes (SC039, SC047, SC065, SC090) should be absent from the new
  Codeset_summary entirely.

---

## 7. expected_differences

```
expected_differences:
  - "A:excluded_rows_gone"          # SC039/SC047/SC065/SC090 absent from new A_code_presence
  - "Codeset_summary:excl_gone"     # same 4 codes absent from new Codeset_summary
  - "C_modality_with_sensitivity:Echocardiogram"
  - "C_modality_with_sensitivity:Electrocardiogram"
  - "C_modality_with_sensitivity:Mammogram"
  - "C_modality_with_sensitivity:Pulmonary function test"
  - "D:Echocardiogram:any_eq_primary"
  - "D:Electrocardiogram:any_eq_primary"
  - "D:Mammogram:any_eq_primary"
  - "D:Pulmonary function test:any_eq_primary"
  - "QC:matched_rows_drop"
```

NOTE: These are EXPECTED changes — the harness should PASS (not FAIL) when these specific
outcomes occur. The checks named above assert the expected outcome; an unexpected value there
is still a FAIL. This list is used by the verify harness's `EXPECTED_DIFFS` constant only to
skip truly-optional comparison rows (none needed here — all checks are explicit assertions,
not "skip on difference").

**ACTUAL EXPECTED_DIFFS in the harness = `character(0)` (empty).** None of the Phase 163
changes require skipping a check entirely — they all have known expected outcomes that are
positively asserted. The checks named in the list above ARE the harness checks; they PASS
when the expected outcome is observed, not SKIP.

---

*Phase 170 Plan 01 Task 0 — complete*
