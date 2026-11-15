# Phase 202 — Tumor Registry Treatment Column Schema (probe run 2026-11-14)

Source table: `TUMOR_REGISTRY_ALL` (483 columns, 1,145 rows, 1,002 patients).
Probe run interactively on HiPerGator, R/4.5, DuckDB read-only. Internal counts — not for external release.

## 1. Sources

| SOURCE | Rows | Field family | Notes |
|---|---|---|---|
| UFH | 726 | NAACCR summary items (`*_CODE_SUMMARY`, `*_START_DATE*`) | Richest; dates and codes agree exactly |
| ORL | 404 | Abstract-style (`DT_*`, `R_N_*`, `*_SUM`) | Reason-no codes plus dates |
| TMH | 15 | Abstract-style, mostly codes | Nearly no treatment dates; report only |

There is no TR1/TR2/TR3 split in this table. **Stratify by `SOURCE`.**

## 2. Rows per patient

| Rows | Patients |
|---|---|
| 1 | 884 |
| 2 | 101 |
| 3 | 12 |
| 4 | 3 |
| 5 | 1 |
| 6 | 1 |

Some patients have several tumor rows: other primaries, or the same tumor in more than one source. How to collapse to one row per patient:
- Use only HL-histology rows (`ICD_CODES$hl_histology`).
- Treatment "given" = any HL row says given.
- Date = earliest non-missing date across HL rows.

## 3. Column map by treatment type and source

### Chemotherapy

| Source | Date column | Code column | "Given" values |
|---|---|---|---|
| UFH | `CHEMO_START_DATE_SUMMARY` (545) | `CHEMO_CODE_SUMMARY` | 01, 02, 03 (= 545; matches the date count exactly) |
| ORL | `DT_CHEMO` (310) | `R_N_CHEMO` (reason-no scheme) | 0 = given (230); see QC note |
| TMH | `DT_CHEMO` (1) | — | date present |

UFH `CHEMO_CODE_SUMMARY` not-given values: 00 = none (169); 82 = contraindicated; 85 = died before treatment; 87 = refused; 88 = recommended, unknown if given.

### Systemic therapy (any; secondary check)

| Source | Date column |
|---|---|
| UFH | `DATE_SYSTEMIC_THERAPY_STARTED` (564) |
| ORL | `DT_SYS` (320) |
| TMH | `DT_SYS` (1) |

### Radiation

| Source | Date column | Code column | "Given" values |
|---|---|---|---|
| UFH | **none** | `REASON_NO_RADIATION` | 0 = given (166) |
| ORL | `DT_RAD` (85), `DT_RAD_END` (79) | `R_N_RAD` | 0 = given (89) |
| TMH | **none** | `DRAD_SUM` (RX Summ scheme, **0 = none**) | 0 = none (3); 8 / 9 = unknown (12) |

The two code schemes run in opposite directions:
- In the reason-no scheme (`REASON_NO_*`, `R_N_*`), 0 means the treatment was given.
- In the RX Summ scheme (`DRAD_SUM`, `DBRM_*`, `HTE_SUM`), 0 means none.

### Immunotherapy (BRM)

| Source | Date column | Code column | "Given" values |
|---|---|---|---|
| UFH | `IMMUNO_START_DATE` (66) | `IMMUNOTHERAPY_CODE` | 01 (= 66; matches the date count) |
| ORL | **none** | `DBRM_SUM` (summary), `DBRM_FAC` (facility) | 1 = given (16); 99 = unknown |
| TMH | **none** | `DBRM_SUM` | all 0 |

### Hematologic transplant / SCT — code only (no source has a date)

| Source | Code column | "Given" values |
|---|---|---|
| UFH | `HEMATOLOGIC_TRANSPLANT_AND_ENDOC` | 10 = BMT NOS; 11 = autologous (8); 12 = allogeneic; 20 = stem-cell harvest and infusion. Total 12 |
| ORL | `HTE_SUM` | 11 (2); 20 (1); 88 = recommended, unknown |
| TMH | `HTE_SUM` | all 0 |

`DT_HTE`, `HTE_FAC` and `R_N_HTE` are all empty. The placeholder date names in R/202 (`DT_SCT`, `DT_TRANSPLANT`, `HCT_DATE`, `TRANSPLANT_DATE`, `SCT_DATE`, `BMT_DATE`) **do not exist**.

### Hormone (secondary: for lymphoma, prednisone given in a regimen is commonly coded as hormone)

| Source | Date column | Code column | "Given" values |
|---|---|---|---|
| UFH | `HORMONE_START_DATE` (147) | `HORMONE_CODE` | 01 (= 147) |
| ORL | `DT_HORM` (91) | `R_N_HORM` | 0 = given (59) |

## 4. Analysis consequences for Phase 202

1. **Date-agreement analysis (B_date_diff)** is possible only where a date exists:
   - chemo: UFH and ORL
   - radiation: ORL only
   - immunotherapy: UFH only
   - transplant: none
2. **Sensitivity (A_sensitivity)** can use "any evidence of given": the date is present OR the code says given.
3. **TMH (15 rows)** is reported in C_by_source with suppressed counts, but no sensitivity is calculated for it.
4. **ORL chemo QC:** `DT_CHEMO` (310) has more rows than `R_N_CHEMO = 0` (230). For ORL, "given" = date present OR code 0. Report the disagreement in the QC sheet.
5. **Date columns** are already DuckDB `DATE` type, so no parsing is needed.
