# Phase 159: Lab Surveillance Modalities and Per-Patient Date Counts - Context

**Gathered:** 2026-09-24
**Status:** Ready for planning (revised after plan review 2026-09-24: D-19..D-27 added; plans rewritten as 159-01..159-04)

<domain>
## Phase Boundary

Add BMP, CMP, LIPID, LFT and KIDNEY as five surveillance modalities to R/147, using `lab_code_crosswalk.xlsx` as the LOINC dictionary. Then produce a wide per-patient table (LAB-06): one row per HL any-dx denominator patient, one column per modality for all 14 modalities, holding the count of unique post-anchor calendar dates the modality occurred within follow-up.

**Out of scope:** converting Phase 158's CBC rule to the analyte-rule approach; result-value / abnormal-lab flags; guideline adherence; re-running the lab code crosswalk pipeline; joining the patient table to treatment exposure.

</domain>

<decisions>
## Implementation Decisions

### Nesting (D-1 — discussed)
- **D-01:** Modality counting is **nested**. A CMP day also counts as a BMP day, an LFT day, and a KIDNEY day, because those analytes were all resulted. The question answered is "were these labs checked," not "which order set was used." The non-additive note (from 158 D-07 / KEY sheet) applies equally here: modality counts are not additive across BMP/CMP/LFT/KIDNEY; a patient's event may appear under all four.
- **D-02:** Nesting is implemented in the **codeset file** as extra panel rows (same code listed under several modalities), identical to how 158 D-20 handled stress echo. No nesting logic in the script.

### Core analytes per modality (D-2 — defaults accepted)
- **D-03 — BMP (8 analytes):** Sodium, Potassium, Chloride, CO2/Bicarbonate, BUN (Urea nitrogen), Creatinine, Glucose, Calcium.
- **D-04 — CMP (14 analytes):** BMP 8 + Albumin, Total protein, ALP (Alkaline phosphatase), ALT (Alanine aminotransferase), AST (Aspartate aminotransferase), Total bilirubin.
- **D-05 — LIPID (3 analytes):** Total cholesterol, HDL, Triglycerides. LDL is often calculated and is not required.
- **D-06 — LFT (4 analytes):** ALT, AST, ALP, Total bilirubin.
- **D-07 — KIDNEY (1 analyte):** Creatinine alone — the broadest kidney-function check. Consequence: KIDNEY primary counts will run at least as high as BMP (expected; stated on KEY sheet).

### Sensitivity definition (D-3 — changed from default)
- **D-08:** Sensitivity = **partial panel threshold**, not "any single analyte." The default ("any single analyte") would make one glucose result a BMP event *and* a CMP event simultaneously, so `_any` columns for BMP and CMP would collapse to "any chemistry drawn" and be nearly identical. A partial-panel threshold preserves the meaning "probably this panel, partly resulted or partly coded."
- **D-09 — Thresholds (one per modality, stored in the codeset rule row as `min_analyte_count`):**
  | Modality | Primary | Sensitivity (min analytes of panel total) |
  |----------|---------|-------------------------------------------|
  | BMP      | all 8   | ≥ 4 of 8                                  |
  | CMP      | all 14  | ≥ 7 of 14                                 |
  | LFT      | all 4   | ≥ 2 of 4                                  |
  | LIPID    | all 3   | ≥ 2 of 3                                  |
  | KIDNEY   | creatinine | eGFR, or cystatin C without creatinine that day, or a urine kidney marker (see D-11) |

- **D-10 — Codeset extension:** *(uniqueness and loader shape refined by D-20)* The `analyte_any_same_day` match type is replaced by `analyte_min_same_day`. Rule rows carry a `min_analyte_count` column (integer). The loader validates that `min_analyte_count` < total analyte count for the row; the validator stops on any other form. Functions in `utils_surveillance.R` split on `;`, count distinct analytes present per ID × date, and apply the threshold. The team can adjust thresholds in the codeset without code changes.
- **D-11 — KIDNEY sensitivity analytes:** *(list refined by D-22)* eGFR (GFR), Cystatin C, and urine kidney markers (albumin/creatinine ratio, urine protein). This simultaneously settles D-5: urine kidney markers are sensitivity-tier only under KIDNEY, consistent with the D-4 specimen exclusions (urine excluded from primary). The KIDNEY sensitivity rule row lists these analytes and sets `specimen` to allow urine for urine markers only (loader handles multi-specimen analytes by code, not by global specimen filter).

### Specimen allowlist (D-4 — defaults accepted)
- **D-12:** Allowed specimens for analyte code selection from the crosswalk: Ser/Plas, Ser, Plas, Ser/Plas/Bld, Bld, BldV. Excluded: BldA (blood gases — avoids ICU arterial-line draws), BldC (fingerstick glucose — avoids point-of-care monitoring), Urine (excluded from primary; allowed selectively for KIDNEY sensitivity per D-11). Rationale: fingerstick and blood-gas results are not surveillance and would inflate primary counts.

### Panel codes (locked L-2)
- **D-13:** Primary events = panel code **or** all core analytes resulted same day (`analyte_all_same_day`). Panel codes (CPT 80048/80053/80061/80076/80069 and the listed panel LOINCs) are primary-tier rows. The all-analyte rule row is a separate primary-tier row. Under D-01 nesting, CMP panel code rows are duplicated for BMP, LFT, and KIDNEY modalities in the codeset.

### Per-patient table (D-7 — defaults accepted)
- **D-14:** *(lookup source set by D-23)* Columns are post-anchor primary count and post-anchor primary-or-sensitivity count only (`n_dates_<modality>` and `n_dates_<modality>_any`). No pre-anchor columns in LAB-06 (those stay in the long `.rds` from Phase 158). Column names use a fixed modality-to-column lookup (modality names contain spaces/parentheses).
- **D-15:** Every denominator ID has a row; patients with no events get zeros, not NA.

### Inheriting Phase 158 decisions (locked L-3)
- **D-16:** Denominator, anchor, follow-up window, person-years formula, two-workbook suppression, DuckDB push-down mechanics, code normalization, event grain (ID × modality × date), and codeset-driven design: unchanged from 158-CONTEXT.md D-01..D-30. The planner should read 158-CONTEXT.md before writing any task that touches these.

### A2 sheet and registration
- **D-17:** `A2_analyte_presence` is a new sheet: one row per `Lab_Analytes` row; columns: n results, n patients, first/last date, `present`. Team reviews A2 alongside A before the release workbook circulates.
- **D-18:** Workbook sheet order (INTERNAL): KEY, A_code_presence, A2_analyte_presence, B_modality_primary, C_modality_with_sensitivity, D_pre_vs_post_anchor, E_patient_modality_dates, QC. E is INTERNAL only; release workbook omits it.

### Decisions added after plan review (2026-09-24)

- **D-19 — Delivered codeset.** `data/reference/surveillance_codeset.xlsx` is delivered pre-built. Sheets, in order:
  - `KEY`
  - `Analysis_Codeset`: 167 rows; SC001–SC108 unchanged from Phase 158, SC109–SC167 new
  - `Lab_Analytes`: 189 rows, LA001–LA189
  - `Lab_Analytes_Excluded`: 43 rows; documentation only, not read by code
  - `Modalities`: 14 rows

  The new modality names are exactly `BMP`, `CMP`, `LIPID`, `LFT`, `KIDNEY`. `Analysis_Codeset` gains a `min_analyte_count` column (text; blank except on `analyte_min_same_day` rows). Plans copy the file in; they do not rebuild it.
- **D-20 — Loader shape.**
  - `load_surveillance_codeset()` still returns a tibble. It does not become a list, so Phase 158 callers, tests and R/88 are unchanged.
  - New `load_lab_analytes(path, codeset)` and `load_modality_lookup(path, codeset)` read the other two sheets.
  - The uniqueness key becomes modality × code_norm × match, so the all-analyte and min-analyte rows of a modality can list the same analytes.
  - Analyte rule rows must have blank `cdm_table` and `type_filter`.
  - `min_analyte_count` must be a whole number ≥ 1 and < the number of listed analytes on `analyte_min_same_day` rows, and blank elsewhere.
  - A file without a `min_analyte_count` column still loads.
  - Every analyte named in a rule row must exist in `Lab_Analytes`.
- **D-21 — Analyte selection.**
  - Codes come from crosswalk MASTER by exact LOINC `component` per analyte:
    - `CO2` = Carbon dioxide + Bicarbonate
    - `TOTAL_BILIRUBIN` = Bilirubin
    - `TOTAL_PROTEIN` = Protein (blood specimens)
    - `URINE_PROTEIN` = Protein + Protein/Creatinine (urine)
    - `EGFR` = Glomerular filtration rate (and its .predicted / Body surface area variants)
  - Specimens: the D-12 blood list; urine only for the two urine analytes.
  - Excluded, with the reason recorded in `Lab_Analytes_Excluded`:
    - test strip / glucometer
    - challenge "Stdy" timepoints
    - pCO2
    - electrophoresis fractions
    - qualitative results
    - percentage results
    - interpretations
    - calculated blood-gas CO2 and calculated triglyceride
    - timed serum albumin
  - Single-analyte CPT codes from the crosswalk's CPT rows are PROCEDURES members.
  - `review_note` flags six codes that may come from blood gases or routine urinalysis, for A2 review.
  - Extra panel LOINCs beyond the brief: 89044-2 (BMP + albumin), 95126-9 (lipid + glucose), 50261-7 (renal + GFR), 45066-8 (creatinine + GFR).
- **D-22 — KIDNEY sensitivity list excludes creatinine:** `EGFR;CYSTATIN_C;URINE_ALBUMIN_CREATININE_RATIO;URINE_PROTEIN`, `min_analyte_count = 1`. Creatinine is already primary. Listing it in the sensitivity row would make KIDNEY sensitivity nearly equal to primary.
- **D-23 — Column lookup from the `Modalities` sheet.**
  - The per-patient column prefixes and their order come from `Modalities` (modality, column_prefix, display_order), not a constant in code.
  - The loader stops if any codeset modality is missing.
  - Prefixes: mammo, breast_mri, echo, stress, ecg, muga, pft, thyroid, cbc, bmp, cmp, lipid, lft, kidney.
  - The per-patient table therefore has 5 descriptor columns + 28 count columns.
- **D-24 — A2 is per `Lab_Analytes` row.** Counts are keyed by `analyte_row_id`, not analyte. `n_results` = distinct ID × code × raw date rows collected (DISTINCT in DuckDB). Hits whose PX_TYPE differs from `type_filter` are reported in `n_results_other_type` and not counted.
- **D-25 — Analyte events join the Phase 158 flow before windowing.**
  - `build_analyte_events()` returns the same schema as `build_component_events()`, with `source_table = "ANALYTE_RULE"`.
  - Its events are bound into `matched_all` in R/147 Section 7, before `classify_event_window()`.
  - A, B, C and D therefore include the lab modalities with no new counting code.
  - Rules are built from all dates. Window filtering happens afterwards, as for every other event.
- **D-26 — Per-patient table and checks.** The table is built from `followup` (the denominator after dropping patients with no usable anchor date), not `denom_all`. Hard stops:
  - one row per denominator ID
  - for every modality, patients with `n_dates_x > 0` equals B's `n_patients`, and `_any` equals C's any-tier `n_patients`
  - primary ≤ any-tier per ID × modality
  - D-01 nesting per ID: CMP ≤ BMP, CMP ≤ LFT, BMP ≤ KIDNEY
- **D-27 — Near-miss and suppression.**
  - The near-miss table is long format: rule row × number of listed analytes present → n ID × dates, with a `qualifies` flag and no zero row.
  - It is written under the QC table on the QC sheet.
  - In the release workbook, A2 counts and near-miss `n_id_dates` are suppressed like other counts.
  - Sheet E and the per-patient `.rds`/`.csv` are INTERNAL / HiPerGator only.

### Claude's Discretion
- QC near-miss reporting format for partial-panel days (how many analytes were present when a day didn't qualify as primary or sensitivity).
- Whether `min_analyte_count` lives on the rule row itself or on a separate sub-table — rule row is simpler and consistent with existing `code_norm` semicolon field.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 158 decisions (authoritative for inherited decisions)
- `.planning/phases/158-surveillance-modality-frequency/158-CONTEXT.md` — D-01..D-30 govern denominator, anchor, event grain, person-years, suppression, DuckDB mechanics, code normalization, workbook structure
- `.planning/phases/158-surveillance-modality-frequency/158-SURVEILLANCE-BRIEF.md` — locked decisions L-1..L-5 and data-mapping table

### Phase 159 specification
- `159-LAB-MODALITIES-BRIEF.md` (project root) — LAB-01..LAB-07 requirements, data mapping, suggested plans, success criteria, pitfalls
- `.planning/REQUIREMENTS.md` — LAB-01..LAB-07 (confirm entries match the brief)

### Existing implementation to extend
- `R/147_surveillance_modality_frequency.R` — script being extended; read all sections before planning
- `R/utils/utils_surveillance.R` — all new matching functions go here beside `build_component_events()`
- `data/reference/surveillance_codeset.xlsx` — codeset file being extended with `Lab_Analytes` sheet and new rule rows

### Code crosswalk (source for analyte code selection)
- `lab_code_crosswalk.xlsx` — MASTER sheet; analytes selected by exact `component` match + D-12 specimen allowlist (not by grouping flags)

### No external specs beyond the above
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `utils_surveillance.R` — `build_component_events()` (CBC component rule pattern for the new `analyte_all_same_day` / `analyte_min_same_day` functions to follow), `compute_modality_stats()`, `suppress_small()`, `suppress_table()`, `load_surveillance_codeset()` (needs extending to read `Lab_Analytes` and validate `min_analyte_count`)
- `utils_treatment.R` — `get_hl_any_dx_ids()` and `get_hl_patient_ids()` (both already exist from Phase 158)
- `R/147_surveillance_modality_frequency.R` — SECTION 4 (LAB_RESULT_CM pull pattern), SECTION 7 (event dedup + component rule), SECTION 8 (output tables) — all extend, not rewrite

### Established Patterns
- DuckDB push-down: `DISTINCT ID, code, raw_date` inside DuckDB before `collect()`; HL-ID semi-join via temp table (D-29 from 158-CONTEXT)
- Codeset-driven design: analyte lists and thresholds in the file, not in code (L-4)
- Two-workbook pattern (INTERNAL unsuppressed + release suppressed)
- `codeset_row_id` carried on every event for per-row presence in A (must be extended to analyte rows with `analyte_row_id`)

### Integration Points
- `surveillance_codeset.xlsx`: new sheet `Lab_Analytes` + new rule rows (SC109+) for panel codes and `analyte_all_same_day` / `analyte_min_same_day` rows
- `R/147`: new SECTION (analyte pull from LAB_RESULT_CM + PROCEDURES), new output sheets A2 and E, updated sheet-order
- `R/88`: extend Phase 158 section with `Lab_Analytes` load check and new modality rows
- `SCRIPT_INDEX` and `data/reference/README.md`: update with new output files

</code_context>

<specifics>
## Specific Ideas

- **Nesting via codeset rows:** CMP panel code CPT 80053 appears as a row under CMP, BMP, LFT, and KIDNEY. Same for CMP all-analyte rule row. This is the explicit pattern from 158 D-20 (stress echo). No script logic.
- **`min_analyte_count` column:** Enables team to tune sensitivity thresholds (e.g., lower BMP to ≥3 if data proves sparse) without code changes.
- **Glucose review:** Check A2 rows for glucose first — it is the largest analyte set and most likely to include glucose challenge/tolerance LOINCs that should not be in the primary rule.
- **KEY sheet annotation:** Add a note that BMP/CMP/LFT/KIDNEY counts are not additive (nested) and that KIDNEY primary counts will run at least as high as BMP.

</specifics>

<deferred>
## Deferred Ideas

- Converting Phase 158's CBC rule to the `analyte_min_same_day` approach (natural follow-on once Phase 159 lands).
- Result-value / abnormal-lab flags.
- Guideline adherence analysis.

</deferred>

---

*Phase: 159-lab-surveillance-modalities-and-per-patient-date-counts*
*Context gathered: 2026-09-24*
