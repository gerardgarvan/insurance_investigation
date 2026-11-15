# Phase 203 — Input Schema (probe run 2026-11-14, HiPerGator)

Replaces `203_schema_PENDING.md`. Internal; do not distribute.

## 1. `output/confirmed_hl_cohort.rds` (default path — NOT `output/internal/`)

7,696 rows / 7,696 patients. **Only 3 columns:**

| Column | Type | Notes |
|---|---|---|
| `ID` | chr | |
| `first_hl_dx_date` | Date | |
| `first_hl_dx_source` | chr | DIAGNOSIS / TUMOR_REGISTRY / Both |

None of these planned columns exist: `n_treatment_episodes`, enrollment / first-encounter date, NLPHL indicator, age at dx, payer, `far_from_care_100mi`. Derive each one as in §5.

## 2. `output/gantt_episodes_180.csv`

22,520 rows / 8,420 patients, 32 columns.

- **Patient key is `patient_id`, not `ID`.**
- `treatment_type` values: Chemotherapy 8,194; Death 1,082; HL Diagnosis 7,696; Immunotherapy 3,211; Proton Therapy 93; Radiation 1,457; SCT 787.
- `cancer_category` on HL Diagnosis rows is always "Hodgkin Lymphoma". **It carries no NLPHL / cHL split.**
- `age_at_episode` (int) is on every row; take it from the HL Diagnosis row for age at dx.
- Also present:
  - `tr_hl_dx` / `tr_nhl_dx` (logical; blank = not in TR)
  - `ever_abvd`
  - `abvd_class`
  - `immune_flag`
  - `ever_brentuximab`
  - `has_autoimmune_dx`

### Population check (reproduces CONSORT)

Treatment types = Chemotherapy, Immunotherapy, Radiation, SCT, Proton Therapy.

| | has_tx FALSE | has_tx TRUE |
|---|---|---|
| in cohort | **3,246 (no_tx)** | **4,450 (treated)** |
| not in cohort | 166 (death-only) | 558 (tx-only) |

## 3. Single-source care (R/169)

**Use `output/internal/single_source_care_20261008.rds`.** It is a tibble with 9,331 rows.

**Do NOT use `single_source_care_parts_20261008.rds`.** That file is a list (`$result`, `$source_counts`, …). It sorts last alphabetically, so a "newest file" glob picks it by mistake. Exclude `*_parts_*`.

The plan's default `single_source_care_20261013.rds` does not exist.

| Column | Type |
|---|---|
| `ID` | chr |
| `n_encounters` | int |
| `n_sources` | int |
| `single_source_care` | int 0/1 |
| `primary_source` | chr (e.g. UFH, USF, EMY, UMI) |
| `n_encounters_post` | int |
| `n_sources_post` | int |
| `single_source_care_post` | int 0/1 |
| `any_blank_source` | lgl |
| `hl_anchor_date` | Date |

The list version's `date_range` was 1901-01-01 to 2025-03-31. **1901 is a sentinel ADMIT_DATE.**

## 4. `output/internal/tr_lymphoma_flags_all_patients_20261113.rds`

9,331 rows. Columns: `ID`, `tr_hl_dx`, `tr_nhl_dx` (1,002 non-missing). **There are no TR treatment columns here.** Registry first-course treatment comes from `TUMOR_REGISTRY_ALL` via R/202's `TR_MAP` (see `202_schema_tr_treatment_cols_20261114.md`).

## 5. Derived variables

| Variable | Source / rule |
|---|---|
| treated vs no_tx | Gantt: any `treatment_type` in the 5 treatment types |
| NLPHL vs cHL | DIAGNOSIS (open/close DuckDB): `classify_codes()` = "NLPHL" (C81.0x, ICD-9 201.4x) vs "Hodgkin Lymphoma (non-NLPHL)". Report `nlphl_any` and `nlphl_only`. |
| age at dx | Gantt `age_at_episode` on the HL Diagnosis row |
| first encounter / follow-up | ENCOUNTER: `min(ADMIT_DATE)` and `max(ADMIT_DATE)` per ID, **excluding sentinel dates (< 1990-01-01)**. Follow-up = last encounter − `first_hl_dx_date`. |
| single-source care | R/169 tibble (§3), joined on `ID` |
| far from care | `output/enc_far_from_care.rds` (1.73M encounter rows; `ID`, `ENCOUNTERID`, `ADMIT_DATE`, `SOURCE`, `distance_mi`, `far_from_care_100mi`, `post_anchor`). Patient level: `far_any_post` = any(`far_from_care_100mi` == 1 & `post_anchor` == 1); `median_distance_mi_post`. |
| payer | No patient-level payer RDS. Use `load_payer_summary(cohort_ids)` from `R/utils/utils_payer.R` (read the function to confirm the return columns), then `classify_payer_tier()`. |
| TR first-course treatment (no_tx group) | Reuse R/202's `TR_MAP` logic. Preferably factor it into a shared util (e.g. `build_tr_treatment_flags()` in `utils_cancer.R`) and call it from both R/202 and R/203. |
