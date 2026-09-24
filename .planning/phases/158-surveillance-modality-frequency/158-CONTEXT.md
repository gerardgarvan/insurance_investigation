# Phase 158: Surveillance Modality Frequency - Context

**Gathered:** 2026-09-24
**Status:** Ready for planning

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
- **D-04:** A new function `get_hl_any_dx_ids()` is needed (returns tibble: `ID`, `hl_anchor_date`, `in_confirmed_cohort`). The existing `get_hl_patient_ids()` in `utils_treatment.R` returns only a character vector with no dates — it is not sufficient. Add the new function to `utils_treatment.R` alongside the existing one.

### Event grain (locked L-2)
- **D-05:** Event unit = distinct `ID` × modality × date. Add-on codes (77063, 93352, 78496, 94729, G0279) and professional/technical splits (93000/93005/93010) are de-duplicated at this grain.

### Stress echo classification (D-1 — discussed)
- **D-06:** CPT codes 93350, 93351, 93352 count under **both** Echocardiogram and Stress test modalities. Rationale: a stress echo answers two distinct clinical questions (anthracycline cardiotoxicity and radiation-related heart disease); omitting it from either modality undercounts each.
- **D-07:** KEY sheet must include a note that modality counts are not additive — a patient's events may appear under multiple modalities.

### Thyroid modality name (D-2 — default accepted)
- **D-08:** Rename the "TSH" modality to "Thyroid function." Retain a TSH-only sub-count within the modality row so that the narrower measure is still visible.

### Follow-up end date for person-years (D-3 — discussed)
- **D-09:** End of follow-up per patient = `min(death_date, last_encounter_date_any_type)`, capped at extract cutoff 2025-09-15. Rationale: OneFlorida is not a closed claims population — patients who leave the system would still accumulate denominator time under an extract-cutoff rule, artificially deflating events per person-year. Use the last encounter of any type (not HL-only).
- **D-10:** If `death_date` is NULL, use `last_encounter_date_any_type` (capped at extract cutoff).

### CBC component fallback (D-4 — default accepted)
- **D-11:** Include the CBC component fallback (WBC LOINC 6690-2 + Hgb 718-7 + PLT 777-3 on the same calendar day) in the **sensitivity tier only**. Never pooled into primary counts.

### Plausible-verify codes (D-5 — default accepted)
- **D-12:** Include BH3xY0Z and ICD-10-PCS `B24*` prefix codes. Flag them in the KEY sheet as "Plausibility: verify." Their volume will be small (inpatient PCS); A_code_presence will surface whether they matter.

### Tier handling (locked L-4)
- **D-13:** Tier assignment is fixed by the codeset `tier` column. The script does not re-classify. Sensitivity results are reported in C_modality_with_sensitivity as a separate column/sheet — never silently pooled into primary counts.

### DuckDB push-down (locked L-5)
- **D-14:** All matching against PROCEDURES, LAB_RESULT_CM, and DIAGNOSIS is pushed down to DuckDB before `collect()`. R/111 is the reference implementation for this pattern.

### Code normalization
- **D-15:** Both codeset codes and CDM codes are trimmed, uppercased, and dots stripped before matching. Prefix matching (LIKE 'X%') is applied only where the codeset `match` column is `'prefix'`.

### Workbook structure (locked)
- **D-16:** Sheet order: KEY (leftmost), A_code_presence, B_modality_primary, C_modality_with_sensitivity, D_pre_vs_post_anchor, QC.
- **D-17:** UF Blue (#0021A5) headers; UF Orange (#FA4616) highlight for `present = FALSE` rows in A_code_presence.
- **D-18:** A_code_presence has exactly one row per codeset row (105 at audit baseline); zero-count rows are included, not dropped.

### Small-cell suppression
- **D-19:** Apply the project's small-cell suppression convention (cells 1–10 → `"<11"`) before the workbook leaves HiPerGator. `suppress_small()` is currently inline in R/106; copy the inline helper into the new script (do not add a dependency on R/106).

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
- `suppress_small()` inline in R/106: copy inline (do not source R/106).

### Established Patterns
- DuckDB pushdown before `collect()` — all scripts from R/111 onward.
- `source("R/00_config.R")` auto-sources utils chain — defensive re-source only if function not yet in environment (see R/111 lines 44–47).
- `glue` for all message formatting, `janitor::clean_names()` for CDM column normalization.
- UF color constants are in R/00_config.R (confirm exact variable names before use).

### Integration Points
- New script writes to `CONFIG$cache$outputs_dir` (workbook) and same directory (`.rds`).
- `get_hl_any_dx_ids()` must be added to `utils_treatment.R` — R/39 and R/88 source this file via R/00_config.R.
- Codeset file `data/reference/surveillance_codeset.xlsx` must exist before the script runs; loader function validates required columns on load.

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
*Context gathered: 2026-09-24*
