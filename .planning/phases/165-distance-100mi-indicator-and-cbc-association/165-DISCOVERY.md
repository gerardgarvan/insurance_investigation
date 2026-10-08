# Phase 165: Discovery Answers

**Prepared:** 2026-10-08
**Scope:** Read-only code investigation — no data access. All answers supported by file:line evidence.

---

## Q1: Script numbers — are R/163 and R/164 free?

**R/163 is FREE.** No file `R/163_*.R` exists in `R/`.

**R/164 is TAKEN.** `R/164_dox_baseline_counts.R` exists (Phase 164).

**Resolution for this plan:**
- Prototype script: **R/163** (free — use as planned)
- Production script (Plan 02): **R/165** (next free after 164)

All Plan 01 files use R/163. Plan 02 must use R/165, not R/164.

**Evidence:** `ls R/` — files present: `R/162_export_patient_modality_dates.R`, `R/164_dox_baseline_counts.R`; `R/163` absent.

---

## Q2: CBC event source — does R/147 save an event-level object retaining pre-anchor events?

**Pre-anchor events are NOT retained in the saved files.** `build_patient_modality_dates()` filters `window == "post"` before building the wide table (utils_surveillance.R:774). The saved RDS (`surveillance_patient_modality_dates_<date>.rds`) is a wide patient-level table of post-anchor date counts, not a row-per-event table.

**Therefore: `build_cbc_events()` must re-derive from DuckDB LAB_RESULT_CM.**

**LOINC codes** (same as R/147 sensitivity-tier CBC D-22, confirmed R/147 line 538):
- WBC: `6690-2`
- Hgb: `718-7`
- PLT: `777-3`

**Date column** R/147 uses for LAB_RESULT_CM (R/147 line 183):
```
pick_date(lab_raw, c("RESULT_DATE", "SPECIMEN_DATE", "LAB_ORDER_DATE"))
```
Priority: `RESULT_DATE` first, then `SPECIMEN_DATE`, then `LAB_ORDER_DATE`.
`build_cbc_events()` must use the same priority: `coalesce(RESULT_DATE, SPECIMEN_DATE, LAB_ORDER_DATE)` pushed into SQL.

**Evidence:** `R/147_surveillance_modality_frequency.R` lines 181-183 (date columns), line 774 (`window == "post"` filter), lines 697-701 (saveRDS of `patient_wide` = post-only wide table).

---

## Q3: Anchor date source

`hl_anchor_date` is produced by **`get_hl_any_dx_ids()`** in `R/utils/utils_treatment.R` (line 310).

- Internally calls `hl_any_dx_from_tibble()` from `utils_surveillance.R`
- Anchor = earliest HL diagnosis `DX_DATE`, falling back to `ADMIT_DATE`
- Patients with no usable date returned with `hl_anchor_date = NA`; callers drop and count them

The `build_*` helpers must call `get_hl_any_dx_ids()` (or reuse the tibble already loaded) to get `hl_anchor_date`. They must NOT define their own anchor independently.

**Evidence:** `R/utils/utils_treatment.R` lines 300-339; `R/147_surveillance_modality_frequency.R` line 88.

---

## Q4: DuckDB connection open/close helpers

The helpers used throughout the pipeline (and in R/147) are:

- **Open:** `open_pcornet_con()` — defined in `R/utils/utils_duckdb.R` line 127
- **Close:** `close_pcornet_con()` — defined in `R/utils/utils_duckdb.R` line 163
- Both are auto-loaded via `source("R/00_config.R")`.

R/147 opens with: `if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()` (line 45).
R/163 should do the same, then close with `close_pcornet_con()` after collecting all data.

**Evidence:** `R/utils/utils_duckdb.R` lines 127, 163; `R/147_surveillance_modality_frequency.R` line 45.

---

## Q5: DISCHARGE_DATE and ENCOUNTERID

**DISCHARGE_DATE is present in ENCOUNTER.** Confirmed in `R/01_load_pcornet.R` line 174 (`DISCHARGE_DATE = col_character()`). The header comment at line 166 notes it is 70.87% missing (expected — most encounters are outpatient). `coalesce(DISCHARGE_DATE, ADMIT_DATE)` is the correct single-day fallback.

**ENCOUNTERID is the join key.** `enc_distance` (R/122 output) carries `ENCOUNTERID` as confirmed in the plan's interface block and `R/122_encounter_distance.R` description in SCRIPT_INDEX.md.

**Evidence:** `R/01_load_pcornet.R` lines 166, 174; SCRIPT_INDEX.md R/122 entry.

---

## Q6: ENCOUNTER.SOURCE column

**ENCOUNTER.SOURCE exists.** The column is named `SOURCE` in the ENCOUNTER table. Confirmed across the codebase:
- `R/00_config.R` line 315: `# NOTE: SOURCE column = partner/site identifier (AMS, UMI, FLM, VRT)`
- `R/02_harmonize_payer.R` line 341-343: `get SOURCE from DEMOGRAPHIC (one row per patient)`; ENCOUNTER also carries SOURCE (used in R/67, R/68, etc.)

The `enc_distance` tibble (R/122 output) also retains SOURCE — confirmed by SCRIPT_INDEX.md R/122 description.

**Evidence:** `R/00_config.R` line 315; `R/02_harmonize_payer.R` lines 341-343.

---

## Q7: R/116 encounter-level SES output — path and rurality column names

**Output path pattern:** `output/encounter_ses_index_YYYYMMDD.rds` (R/116 line 61)

**Rurality column names** in the RDS:
- `ruca_code` — integer, primary RUCA code (R/116 line 219-222)
- `ruca_category` — character, one of: "Metropolitan", "Micropolitan", "Small town", "Rural", "Not coded" (R/116 lines 223-228)

**Full schema** (R/116 lines 352-356):
```
PATID, ENCOUNTERID, ADMIT_DATE,
ZIP9, ZIP5, match_type, zip9_source,
sdi_score, adi_natrank, adi_natrank_zip5_median, svi_score,
ruca_code, ruca_category
```

Note: join key in R/116 is `PATID` (not `ID`); Plan 02's sensitivity model join must account for this.

**Evidence:** `R/116_encounter_ses_index.R` lines 61, 219-228, 352-356.

---

## Q8: Harmonized patient-level payer object

**Object:** `payer_summary` — produced by `R/02_harmonize_payer.R` (line 348)

**Key column for analysis:** `PAYER_CATEGORY_PRIMARY` — mode payer category across all valid encounters, one of the AMC 8 categories: Medicaid, Medicare, Private, Other govt, Other, Self-pay, Uninsured, Missing (R/02 lines 295-306).

**Evidence:** `R/02_harmonize_payer.R` lines 8-19, 295-306, 348, 361-365.

---

## Q9: Vectorized suppress_small() definition

**No vectorized NA-returning version exists in the shared utils.** The only shared definition is `suppress_small()` in `R/utils/utils_surveillance.R` lines 640-642 — it returns strings ("<11" for counts 1-10), not NA. This is a display/HIPAA-suppression version, not an integer-NA version.

The scalar version cited in the context (R/107) uses the same pattern: `NA_integer_` for 1-10.

**Therefore:** `utils_distance_cbc.R` must define two versions:
- `suppress_small_vec(n)` — vectorized, returns `NA_integer_` for n in 1:10 (integer analysis use)
- `suppress_display(n)` — vectorized, returns `"<11"` string (table output use, matches pipeline convention)

**Evidence:** `R/utils/utils_surveillance.R` lines 640-642 (display-only string version); no integer-NA vectorized version found in any utils file.

---

## Summary Table

| Q | Answer | Action for Task 3/4 |
|---|--------|---------------------|
| Q1 | R/163 free; R/164 taken | Use R/163 for prototype; Plan 02 uses R/165 |
| Q2 | R/147 saves post-only wide table; no event-level pre+post CBC file | `build_cbc_events()` re-derives from DuckDB LAB_RESULT_CM; date priority: RESULT_DATE > SPECIMEN_DATE > LAB_ORDER_DATE; LOINCs 6690-2, 718-7, 777-3 |
| Q3 | `get_hl_any_dx_ids()` returns tibble(ID, hl_anchor_date, in_confirmed_cohort) | Helpers call `get_hl_any_dx_ids()` or reuse that tibble |
| Q4 | `open_pcornet_con()` / `close_pcornet_con()` in utils_duckdb.R | R/163 uses same open/close pattern as R/147 |
| Q5 | DISCHARGE_DATE present (70.87% missing); ENCOUNTERID is join key | `coalesce(DISCHARGE_DATE, ADMIT_DATE)` for single-day encounters |
| Q6 | ENCOUNTER.SOURCE = site identifier (AMS/UMI/FLM/VRT) | Pull SOURCE from ENCOUNTER in SQL along with DISCHARGE_DATE |
| Q7 | `encounter_ses_index_YYYYMMDD.rds`; columns `ruca_code`, `ruca_category`; join key PATID | Plan 02 joins on PATID (not ID) for rurality covariate |
| Q8 | `payer_summary` tibble, column `PAYER_CATEGORY_PRIMARY` | Plan 02 sensitivity model joins payer_summary on ID |
| Q9 | No vectorized NA-returning version; utils_surveillance has display-only string version | Define both `suppress_small_vec()` (NA integer) and `suppress_display()` ("<11" string) in utils_distance_cbc.R |
