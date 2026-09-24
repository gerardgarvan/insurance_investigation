# Phase 158: Surveillance Modality Frequency - Context

**Gathered:** 2026-09-24
**Status:** Ready for planning (revised after plan review 2026-09-24: D-23..D-30 added; plans rewritten as 158-01..158-04)

<domain>
## Phase Boundary

Deliver an investigation script that counts how often each audited Surveillance Strategy modality appears among all patients with ≥1 HL diagnosis code. The first output is a per-code presence audit (A_code_presence, including zero-count rows); frequency tables (B/C/D sheets) circulate only after the team reviews A. Also produces a patient × modality `.rds` for later linkage to treatment exposure. Registering the script in R/39, R/88, and SCRIPT_INDEX is in scope.

**Out of scope this phase:** guideline adherence analysis, uncoded modalities (BMP/LFT/colonoscopy/DEXA etc.), editing VariableDetails.xlsx, and the downstream join of SURV-06 to treatment exposure.

</domain>

<decisions>
## Implementation Decisions

### Denominator (locked L-1)
- **D-01:** Denominator = all distinct IDs with ≥1 HL diagnosis code in DIAGNOSIS (ICD-10 `C81*` with `DX_TYPE = "10"`, or ICD-9 `201*` with `DX_TYPE = "09"`). NLPHL included.
- **D-02:** Anchor date = first HL diagnosis date per patient.
- **D-03:** Each patient also carries `in_confirmed_cohort` flag from `get_hl_patient_ids()`. This flag is a column for comparability — it does not gate the denominator.
- **D-04:** *(guard behavior superseded by D-24)* A new function `get_hl_any_dx_ids()` is needed (returns tibble: `ID`, `hl_anchor_date`, `in_confirmed_cohort`). The existing `get_hl_patient_ids()` in `utils_treatment.R` returns only a character vector with no dates — it is not sufficient. Add the new function to `utils_treatment.R` alongside the existing one.

### Event grain (locked L-2)
- **D-05:** Event unit = distinct `ID` × modality × date. Add-on codes (77063, 93352, 78496, 94729, G0279) and professional/technical splits (93000/93005/93010) are de-duplicated at this grain.

### Stress echo classification (D-1 — discussed)
- **D-06:** CPT codes 93350, 93351, 93352 count under **both** Echocardiogram and Stress test modalities. Rationale: a stress echo answers two distinct clinical questions (anthracycline cardiotoxicity and radiation-related heart disease); omitting it from either modality undercounts each.
- **D-07:** KEY sheet must include a note that modality counts are not additive — a patient's events may appear under multiple modalities.
- **D-20:** D-06 is implemented in the **codeset file**, not the script (L-4). Add three rows to `surveillance_codeset.xlsx` under modality `Stress test` for 93350, 93351, 93352 (same `code_norm`, `cdm_table`, `type_filter`, `match = exact`, `tier = primary` as their Echocardiogram rows). The existing Echocardiogram rows stay. The script contains no stress-echo special case; the both-modality behavior falls out of the codeset.

### Thyroid modality name (D-2 — default accepted)
- **D-08:** Rename the "TSH" modality to "Thyroid function." Retain a TSH-only sub-count within the modality row so that the narrower measure is still visible.
- **D-21:** Both halves of D-08 are driven by the **codeset file**, not the script (L-4):
  - The rename is done in the codeset: every row with modality `Thyroid stimulating hormone` becomes `Thyroid function`.
  - A new codeset column `submodality` (character, may be blank) identifies the sub-count. Values for the thyroid rows: 84443, 11580-8, 3016-3 → `TSH`; 3024-7, 84439 → `Free T4`. Blank for all other modalities.
  - B/C sheets report sub-counts for any modality with non-blank `submodality` values, computed at the same ID × date grain as the parent. The script must not hard-code TSH code lists. Sub-counts are not additive to each other or to the parent (a TSH and a Free T4 on the same day are one parent event).

### Follow-up end date for person-years (D-3 — discussed)
- **D-09:** End of follow-up per patient = `min(death_date, last_encounter_date_any_type)`, capped at extract cutoff 2025-09-15. Rationale: OneFlorida is not a closed claims population — patients who leave the system would still accumulate denominator time under an extract-cutoff rule, artificially deflating events per person-year. Use the last encounter of any type (not HL-only).
- **D-10:** If `death_date` is NULL, use `last_encounter_date_any_type` (capped at extract cutoff).

### CBC component fallback (D-4 — default accepted)
- **D-11:** Include the CBC component fallback (WBC LOINC 6690-2 + Hgb 718-7 + PLT 777-3 on the same calendar day) in the **sensitivity tier only**. Never pooled into primary counts.
- **D-22:** The CBC fallback is a structured codeset row, not a free-text rule:
  - `match` has a closed set of allowed values: `exact`, `prefix`, `component_all_same_day`. The loader stops on any other value.
  - For the CBC row: `match = component_all_same_day`, `code` / `code_norm` = `6690-2;718-7;777-3` (semicolon-separated, no spaces), `cdm_table = LAB_RESULT_CM`, `tier = sensitivity`. This replaces the audit workbook's `6690-2 + 718-7 + 777-3` / `component rule (all 3 same day)` text.
  - D-15 normalization is applied to each component after splitting on `;`, never to the joined string.
  - An event is an ID × date where **all** listed components have a result on that calendar day (`RESULT_DATE`, same fallback chain as other LOINC rows). A day with only two of the three components is not an event.
  - In A_code_presence this row reports the same columns as other rows, computed over qualifying ID × dates: n records = qualifying ID × dates, n distinct patients, n distinct patient-dates, first/last date, `present`. QC additionally reports the count of ID × dates with 1 or 2 of the 3 components, so a near-miss pattern is visible.

### Plausible-verify codes (D-5 — default accepted)
- **D-12:** Include BH3xY0Z and ICD-10-PCS `B24*` prefix codes. Flag them in the KEY sheet as "Plausibility: verify." Their volume will be small (inpatient PCS); A_code_presence will surface whether they matter.

### Tier handling (locked L-4)
- **D-13:** Tier assignment is fixed by the codeset `tier` column. The script does not re-classify. Sensitivity results are reported in C_modality_with_sensitivity as a separate column/sheet — never silently pooled into primary counts.

### DuckDB push-down (locked L-5)
- **D-14:** All matching against PROCEDURES, LAB_RESULT_CM, and DIAGNOSIS is pushed down to DuckDB before `collect()`. R/111 is the reference implementation for this pattern.

### Code normalization
- **D-15:** Both codeset codes and CDM codes are trimmed, uppercased, and dots stripped before matching. Prefix matching (LIKE 'X%') is applied only where the codeset `match` column is `'prefix'`. For `component_all_same_day` rows, see D-22.

### Workbook structure (locked)
- **D-16:** Sheet order: KEY (leftmost), A_code_presence, B_modality_primary, C_modality_with_sensitivity, D_pre_vs_post_anchor, QC.
- **D-17:** UF Blue (#0021A5) headers; UF Orange (#FA4616) highlight for `present = FALSE` rows in A_code_presence.
- **D-18:** A_code_presence has exactly one row per codeset row; zero-count rows are included, not dropped. The check is `nrow(A_code_presence) == nrow(codeset)` — no literal row count in code. For reference, the codeset after the D-20/D-21/D-22 edits has **108 rows** (105 audit baseline + 3 stress-echo rows under Stress test); the brief's "105" is superseded.

### Small-cell suppression
- **D-19:** *(superseded by D-27)* Apply the project's small-cell suppression convention (cells 1–10 → `"<11"`) before the workbook leaves HiPerGator. `suppress_small()` is currently inline in R/106; copy the inline helper into the new script (do not add a dependency on R/106).

### Decisions added after plan review (2026-09-24)

- **D-23 — Staged codeset and row key.** `data/reference/surveillance_codeset.xlsx` is delivered pre-built with D-20/D-21/D-22 already applied (108 rows; sheets KEY, Analysis_Codeset). Every row has a unique `codeset_row_id` (SC001..SC108) that is carried on every matched event, so per-row presence survives de-duplication and prefix matching. `type_filter` holds the bare value (`CH`, `10`, `09`; blank for LAB_RESULT_CM) — never `PX_TYPE='CH'`; the loader rejects any other form. A `plausibility` column marks D-12 rows (`verify`). Blank cells read back as NA and are converted to `""` by the loader.
- **D-24 — Denominator guards stop, never return empty.** `get_hl_any_dx_ids()` stops (does not `tryCatch` to an empty tibble) if DIAGNOSIS is unavailable, is not a lazy DuckDB tbl, or `get_hl_patient_ids()` returns no IDs. The script checks `get_hl_patient_ids()` directly (not the flag column): both sets non-empty and every confirmed ID in the any-dx set. Anchor = earliest `DX_DATE`, falling back to `ADMIT_DATE`; patients with no usable date are dropped from the denominator and counted in QC.
- **D-25 — Event window.** Each event is `pre` (before the anchor), `post` (after the anchor, on or before `follow_end`), or `after_followup` (after `follow_end`, or no follow-up date). Only `post` counts toward B/C frequency and person-year rates; `after_followup` is excluded and counted in QC and D. Anchor-day events are `pre` by default (`ANCHOR_DAY_IS_POST <- FALSE`, stated on the KEY sheet; the team may flip it).
- **D-26 — Person-years.** Pooled rate = post-anchor event dates / total person-years of the whole denominator (not only patients with events). Patients with follow-up of zero or less, or with no follow-up date, contribute 0 person-years and are counted in QC.
- **D-27 — Two workbooks; suppression in one shared helper.** The script writes an unsuppressed `surveillance_modality_frequency_INTERNAL_<date>.xlsx` (stays on HiPerGator; used for the A_code_presence review) and a release `surveillance_modality_frequency_<date>.xlsx` (counts 1–10 shown as `<11`; derived columns such as percentages, medians and rates blanked where their count is suppressed). Suppression runs after every `stopifnot`. `suppress_small()` / `suppress_table()` live in `R/utils/utils_surveillance.R` (no copy of R/106's helper). The patient-level `.rds` is unsuppressed and stays on HiPerGator.
- **D-28 — Dates and death.** All CDM dates are parsed with `parse_pcornet_date()` after `collect()`, never with `as.Date()` or compared as strings in SQL. Death date comes from the `DEATH` table (`DEATH_DATE`), earliest per ID. Last encounter = latest `ADMIT_DATE`/`DISCHARGE_DATE` in ENCOUNTER (all types).
- **D-29 — Pushdown mechanics.** Code matching is pushed down with SQL built by `surv_code_where()` (`REPLACE(UPPER(TRIM(col)), '.', '') IN (...)` / `LIKE 'X%'`), mirroring R/111. HL IDs are copied to a temporary DuckDB table on the same connection (`dbplyr::remote_con()`) and joined with `semi_join()` — no inlined ID vectors. PX_TYPE/DX_TYPE are not filtered in SQL; rows whose type differs from the codeset `type_filter` are kept out of the counts but reported (A: `n_records_other_type`, `other_types`; QC: type distribution) so legacy values such as `C4`/`HC` are visible. LAB rows match on `LAB_LOINC`, or on `LAB_PX` where `LAB_PX_TYPE = 'LC'` when those columns exist.
- **D-30 — Where the logic lives and how it is tested.** All counting rules are pure functions in a new `R/utils/utils_surveillance.R` (loader, normalization, SQL builders, HL helper, matching, component rule, presence, follow-up, window, frequency, patient-level, suppression), covered by `tests/testthat/test-158-codeset-loader.R` and `tests/testthat/test-158-surveillance-counts.R`. The investigation script only wires DuckDB pulls to these functions. `get_hl_any_dx_ids()` (DuckDB wrapper) stays in `utils_treatment.R` per D-04. Frequency tables: B = primary; C = primary, sensitivity and primary-or-sensitivity side by side (each with the full SURV-04 metric set); submodality rows appear under their parent in B and C.

### Claude's Discretion
- Script structure (section headers, defensive sourcing pattern) — follow R/111 as the template.
- Next free R/ script number — executor must confirm by checking `ls R/ | grep -E '^[0-9]+_' | sort -n | tail -5` before writing the script header.
- Whether `get_hl_any_dx_ids()` uses a DuckDB prefix pushdown (like R/111) or the existing in-memory `%in%` pattern from `get_hl_patient_ids()` — the codeset is small enough that either works for the denominator query; DuckDB pushdown preferred for consistency.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary spec
- `.planning/phases/158-surveillance-modality-frequency/158-SURVEILLANCE-BRIEF.md` — requirements SURV-01..06, locked decisions L-1..L-5, data mapping table, suggested plan breakdown, success criteria, pitfalls

### Existing functions to reuse / extend
- `R/utils/utils_treatment.R` — `get_hl_patient_ids()` (character-vector-only; `get_hl_any_dx_ids()` is a new function to be added here)
- `R/utils/utils_surveillance.R` — new in 158-01/158-02 (D-30)
- `R/utils/utils_cancer.R` — `is_cancer_code()`, `classify_codes()` (reuse for HL prefix logic if applicable)
- `R/utils/utils_duckdb.R` — `open_pcornet_con()`, `get_pcornet_table()`, `close_pcornet_con()`

### DuckDB push-down reference implementation
- `R/111_doi_classification.R` — canonical pattern: prefix-set construction, DuckDB pushdown, `collect()` timing, section structure

### Registration targets
- `R/39_run_all_investigations.R` — add new script here
- `R/88` (smoke test) — add structural checks in next free Section
- `R/SCRIPT_INDEX.md` — add script row

### Codeset staging
- `data/reference/README.md` — document `surveillance_codeset.xlsx` here (path, columns, vintage)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `get_hl_patient_ids()` (`utils_treatment.R`): Returns `character(0)` on DuckDB failure — extend, don't replace. New `get_hl_any_dx_ids()` should follow the same `tryCatch` + `safe_table()` guard pattern.
- `is_cancer_code()` / `classify_codes()` (`utils_cancer.R`): Can detect C81* / 201* — evaluate whether these functions already isolate HL codes precisely enough before writing new prefix logic.
- R/111 section structure: SECTION 1 Setup, SECTION 2 prefix list/pushdown, SECTION 3+ per-CDM-table queries, SECTION N output write — use this as the script skeleton.
- `suppress_small()` inline in R/106: *(superseded by D-27 — use `suppress_small()`/`suppress_table()` from `utils_surveillance.R`)*.

### Established Patterns
- DuckDB pushdown before `collect()` — all scripts from R/111 onward.
- `source("R/00_config.R")` auto-sources utils chain — defensive re-source only if function not yet in environment (see R/111 lines 44–47).
- `glue` for all message formatting, `janitor::clean_names()` for CDM column normalization.
- UF color constants are in R/00_config.R (confirm exact variable names before use).

### Integration Points
- New script writes to `CONFIG$cache$outputs_dir` (workbook) and same directory (`.rds`).
- `get_hl_any_dx_ids()` must be added to `utils_treatment.R` — R/39 and R/88 source this file via R/00_config.R.
- Codeset file `data/reference/surveillance_codeset.xlsx` must exist before the script runs; loader function validates required columns on load.

### Codeset edits required before staging (D-20, D-21, D-22)
*(Done: the delivered `surveillance_codeset.xlsx` already contains these edits — see D-23. Kept here as the record of what changed.)*
The audit workbook's `Analysis_Codeset` sheet is the starting point but must be edited before it is staged as `surveillance_codeset.xlsx`:
1. Add 3 `Stress test` rows for 93350, 93351, 93352 (D-20).
2. Rename modality `Thyroid stimulating hormone` → `Thyroid function`; add `submodality` column with TSH / Free T4 values (D-21).
3. Replace the CBC component row's `code`, `code_norm`, and `match` with the structured form (D-22).

Loader validation (`load_surveillance_codeset()`) must check:
- required columns present, including `submodality`
- `tier` ∈ {primary, sensitivity}
- `match` ∈ {exact, prefix, component_all_same_day}
- no duplicate `modality` × `code_norm`
- all code columns are character (`col_types = "text"`)
- every `component_all_same_day` row has ≥2 components after splitting on `;` and `cdm_table = LAB_RESULT_CM`

</code_context>

<specifics>
## Specific Ideas

- **D-6/D-7 (stress echo both-modality):** The KEY sheet non-additive note can be a single sentence: *"Modality counts are not additive — a single encounter may contribute to more than one modality (e.g., stress echocardiogram counted under both Echocardiogram and Stress test)."*
- **D-9 (follow-up end):** The last_encounter_date_any_type must come from the full ENCOUNTER table (all encounter types), not a filtered HL or treatment subset.
- **Pitfall callout from spec:** Excel stores CPT codes as numbers — `readxl` will silently coerce `77063` to a double. The codeset loader must specify `col_types = "text"` for the code column.

</specifics>

<deferred>
## Deferred Ideas

- Guideline adherence analysis (whether a patient got the recommended test on schedule given treatment exposure) — natural Phase 159 or later.
- Adding uncoded modalities (BMP/LFT/CMP/lipids/DEXA etc.) — pending lab code crosswalk workbook.
- Joining SURV-06 patient × modality output to treatment exposure (anthracycline, bleomycin, RT) — out of scope; SURV-06 is designed to enable this join.

</deferred>

---

*Phase: 158-surveillance-modality-frequency*
*Context gathered: 2026-09-24; D-20..D-22 added 2026-09-24 (codeset-driven implementation of D-06, D-08, D-11); D-23..D-30 added 2026-09-24 after plan review*
