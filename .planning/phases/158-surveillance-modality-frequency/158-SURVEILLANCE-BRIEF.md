# Phase 158: Surveillance Modality Frequency in the HL Population

**Goal:** For every patient with at least one HL diagnosis code, count how often each Surveillance Strategy modality (from `VariableDetails.xlsx`) appears in the extract. First confirm which codes actually occur in the data, so zero-count and mis-specified codes are visible before any frequency is reported.
**Requirements:** SURV-01 .. SURV-06
**Depends on:** Phase 157 (independent in substance; no shared outputs)
**Plans:** TBD (suggested 3 below)

---

## Background

The team's `VariableDetails.xlsx` → *Surveillance Strategy* sheet lists codes for 10 coded modalities. A desk audit on 2026-09-24 (`surveillance_strategy_code_audit.xlsx`) found three kinds of problem:

- **Invalid or wrong codes:**
  - TSH "HCPCS 224576" is not a HCPCS code.
  - LOINC 24364-2 is an obstetric panel.
  - 93015–93018 are stress tests, not ECGs.
  - `Z13.6 ` has a trailing space.
  - C21G1ZZ is listed twice.
- **Missing legacy codes:**
  - CPT codes retired in 2017, 2018 and 2019 for mammography, breast MRI and PFT.
  - ICD-9 procedure codes.
  - Without these, trends will look like surveillance started in 2017–2019.
- **Nonspecific codes:**
  - Z13.6 and Z13.83 are screening *diagnosis* codes, so they don't show a test was done.
  - C21G1ZZ and C22G1ZZ are not MUGA-specific.

The audit's `Analysis_Codeset` sheet (105 rows; 98 primary, 7 sensitivity) is the input codeset for this phase.

---

## Requirements

- **SURV-01** — Codeset staged and loaded:
  - `Analysis_Codeset` is staged as `data/reference/surveillance_codeset.xlsx` and documented in `data/reference/README.md`.
  - Loaded through a loader function, not hard-coded in the script.
  - Codes are read as character, never numeric.
- **SURV-02** — HL denominator:
  - Distinct `ID`s with ≥1 HL diagnosis code in DIAGNOSIS: ICD-10 `C81*` with `DX_TYPE = "10"`, or ICD-9 `201*` with `DX_TYPE = "09"`. NLPHL is included.
  - Anchor date = first HL diagnosis date.
  - Each patient also carries an `in_confirmed_cohort` flag from `get_hl_patient_ids()`.
- **SURV-03** — Code presence audit. For every codeset row, restricted to HL patients:
  - n records
  - n distinct patients
  - n distinct patient-dates
  - first and last date
  - `present` (TRUE/FALSE)

  Zero-count rows are reported, not dropped.
- **SURV-04** — Modality frequency, primary tier only. Per modality:
  - n patients with ≥1 event
  - % of the HL denominator
  - distinct event dates per patient (median, IQR, max)
  - events per person-year of post-anchor follow-up
- **SURV-05** — Sensitivity tier reported separately:
  - Same metrics as SURV-04.
  - A second "primary + sensitivity" count per modality.
  - Never pooled silently into the primary counts.
- **SURV-06** — Patient-level output:
  - One row per `ID` × modality with first/last event date and n event dates (pre- and post-anchor split).
  - Saved as `.rds` so it can later be joined to treatment exposure (anthracycline, bleomycin, RT). That join is out of scope here.

---

## Locked decisions

| # | Decision | Rationale |
|---|----------|-----------|
| L-1 | Denominator = ≥1 HL code (user-specified), **not** the 7-day-confirmed cohort | User request; confirmed-cohort flag carried as a column for comparability with other deliverables |
| L-2 | Event unit = distinct `ID` × modality × date | Add-on codes (77063, 93352, 78496, 94729, G0279) and professional/technical splits (93000/93005/93010) would otherwise inflate counts |
| L-3 | Only post-anchor events count as surveillance; pre-anchor events are reported in their own columns | Keeps baseline staging workup out of surveillance frequency |
| L-4 | Tiers are fixed by the codeset `tier` column; the script does not re-classify | Single source of truth, editable by the team without code changes |
| L-5 | All matching pushed down to DuckDB before `collect()` (R/111 pattern) | PROCEDURES / LAB_RESULT_CM / DIAGNOSIS are too large to load |

## Open decisions (resolve in discuss-phase)

| # | Question | Default if not answered |
|---|----------|-------------------------|
| D-1 | Stress echo (93350/93351/93352): count under Echocardiogram, Stress test, or both? | Echocardiogram only (as on the sheet) |
| D-2 | Keep Free T4 (LOINC 3024-7, CPT 84439) under the TSH modality, or rename the modality "Thyroid function"? | Rename to "Thyroid function", with TSH-only as a sub-count |
| D-3 | End of follow-up for person-years: last encounter date, death date, or extract cutoff (2025-09-15)? | min(death date, last encounter date) |
| D-4 | Is the CBC component fallback (WBC 6690-2 + Hgb 718-7 + PLT 777-3 on the same day) acceptable as a sensitivity proxy? | Yes, sensitivity tier only |
| D-5 | Confirm "Plausible - verify" / "Medium" codes (BH3xY0Z, ICD-10-PCS `B24*` prefix) before counts are circulated | Include; flag them in the KEY sheet |

---

## Data mapping

| Code system | CDM table | Match column | Type filter | Date column |
|-------------|-----------|--------------|-------------|-------------|
| CPT / HCPCS | PROCEDURES | `PX` | `PX_TYPE = 'CH'` | `PX_DATE` (fallback `ADMIT_DATE`) |
| ICD-10-PCS | PROCEDURES | `PX` | `PX_TYPE = '10'` | `PX_DATE` |
| ICD-9-CM proc | PROCEDURES | `PX` (dots stripped) | `PX_TYPE = '09'` | `PX_DATE` |
| LOINC | LAB_RESULT_CM | `LAB_LOINC`; also `LAB_PX` where `LAB_PX_TYPE = 'LC'` | — | `RESULT_DATE` (fallback `SPECIMEN_DATE`, `LAB_ORDER_DATE`) |
| ICD-10 dx | DIAGNOSIS | `DX` (dots stripped) | `DX_TYPE = '10'` | `DX_DATE` (fallback `ADMIT_DATE`) |

- **Normalization:** trim and uppercase both sides, and strip dots from DX/PX.
- **Prefix matching:** only codeset rows with `match = 'prefix'` use `LIKE 'X%'`.
- **Patient key:** `ID` (post-R/01 convention). The executor should confirm the column name in the DuckDB views before writing SQL.
- **Lab codes in PROCEDURES:** CPT lab codes (85025, 84443, …) can appear in PROCEDURES, and lab LOINCs can appear in LAB_RESULT_CM. The same CBC can hit both, which L-2 de-duplicates. Report source-table provenance per event.

---

## Suggested plans

**158-01 — Codeset loader + HL denominator (Wave 1)**
- `load_surveillance_codeset()` returns a validated tibble:
  - required columns present
  - `tier` limited to primary/sensitivity
  - no duplicate `modality` × `code_norm`
  - all codes are character
- `get_hl_any_dx_ids()` returns `ID`, `hl_anchor_date`, `in_confirmed_cohort`.
  - If `utils_cancer.R`'s `is_cancer_code()` / `classify_codes()` already give an HL category, reuse them rather than writing a new prefix rule.
- testthat fixtures cover:
  - numeric-looking CPT codes survive as character
  - `"Z13.6 "` trims to match
  - an ICD-9 `201.xx` patient enters the denominator
  - a `C81` code with the wrong `DX_TYPE` does not

**158-02 — Presence audit + frequency script (Wave 2, depends on 158-01)**
- New investigation script (next free `R/` number; executor to confirm):
  - SECTION pulls: one DuckDB query per CDM table, semi-joined to HL `ID`s and the codeset.
  - Build the event table at `ID` × modality × date grain, with `tier`, `source_table`, `code`, and `pre_post_anchor`.
  - Compute SURV-03 through SURV-06.
- Workbook `surveillance_modality_frequency_<date>.xlsx`, with sheets in this order:
  1. **KEY** — leftmost; covers:
     - denominator definition and N
     - confirmed-cohort N
     - codeset version/date
     - event-grain rule, anchor rule, follow-up rule
     - open-decision outcomes (D-1..D-5)
     - tier definitions
  2. **A_code_presence** — every codeset row; `present = FALSE` rows highlighted in UF Orange.
  3. **B_modality_primary**
  4. **C_modality_with_sensitivity**
  5. **D_pre_vs_post_anchor**
  6. **QC** — denominator waterfall, rows matched per CDM table, and duplicate-collapse counts.
- Patient-level `.rds` per SURV-06.
- Headers in UF Blue (#0021A5).

**158-03 — Registration + HiPerGator run (Wave 3, depends on 158-02)**
- Register the new script in:
  - `R/39_run_all_investigations.R`
  - `R/88` (next free Section, structural checks)
  - `R/SCRIPT_INDEX.md`
- Human-action checkpoint: run on HiPerGator and review `A_code_presence` with the team. Codes present in the data but clinically implausible, and codes absent from the data, both go back to the codeset owner before `B`/`C` are circulated.

---

## Success criteria

1. `A_code_presence` has exactly one row per codeset row (105 at audit baseline) and no row is silently dropped.
2. Denominator reconciles:
   - HL any-dx N ≥ confirmed-cohort N
   - every confirmed-cohort ID is in the any-dx set (`stopifnot`)
3. For every modality, patients with ≥1 primary event ≤ patients with ≥1 primary-or-sensitivity event ≤ denominator (`stopifnot`).
4. The event table has no duplicate `ID` × modality × date rows after collapse (`stopifnot`).
5. Changing a code's `tier` in the codeset file changes the output with no code edit.
6. R/88 passes with the new section; the workbook is issued from a HiPerGator run.

## Out of scope

- Uncoded modalities: BMP, LFT, CMP, lipids, dental, carotid US, thyroid US, colonoscopy, derm, hip/knee MRI, DEXA, and diagnostic imaging.
  - BMP/LFT/CMP/lipids can be added once the lab code crosswalk workbook is finished.
- Guideline adherence: whether a patient got the *recommended* test on schedule given their treatment exposure (the sheet's "Type of tx" column). SURV-06 sets this up for a follow-on phase.
- Editing `VariableDetails.xlsx` itself. Corrections go back to the sheet owner.

## Pitfalls

- **Code types:** Excel stores CPT codes as numbers. `readxl` will return `77063` as a double unless `col_types = "text"`.
- **Retired codes:** these only occur in older years, so a low count for a retired code is expected, not a defect. Show the first and last date beside every count.
- **Panel vs component labs:** PCORnet LAB_RESULT_CM usually stores component results. Panel LOINCs (58410-2, 57021-8) may be near zero even though CBCs were done. This is why D-4 matters.
- **Add-on codes:** 93352, 78496, 94729 and G0279 never occur alone. They add events only if the base code is missing from the extract, which is worth a QC count.
- **Small cells:** apply the project's small-cell suppression convention before the workbook leaves HiPerGator.
