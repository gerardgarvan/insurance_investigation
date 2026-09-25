# Phase 160: Surveillance Lab Accuracy and Reporting Improvements - Context

**Gathered:** 2026-09-25
**Status:** Ready for planning (revised after plan review 2026-09-25: D-07..D-13 added; plans rewritten)

<domain>
## Phase Boundary

Fix two lab-counting problems found in the 2026-09-25 R/147 run: raise the CMP sensitivity threshold so a plain BMP no longer qualifies; add a missing-analyte diagnostic (A3) to identify and then add the missing CO2 code. Add female-denominator columns for breast imaging modalities. Auto-generate a codeset summary sheet on every run.

**Out of scope:** care-setting filtering (inpatient vs outpatient), surveillance start-window redefinition, guideline adherence analysis. These are deferred to Phase 161 pending team decisions.

</domain>

<decisions>
## Implementation Decisions

### D-1 — CMP sensitivity threshold
- **D-01:** Set CMP `min_analyte_count` to **11 of 14**. This cuts out all 8-of-14 and 9-of-14 days (BMP and BMP+albumin), which account for ~36,000 and ~2,900 patient-days respectively. The difference between 10 and 11 is only 236 days (≈0.1% of the ~190,000-day base), so 11 is the cleaner clinical boundary: it requires a full BMP plus at least three of the six liver/protein analytes. Codeset edit only — no code change.

### D-2 / D-3 — A3 diagnostic parameters
- **D-02 (block 1 depth):** Near-miss depth = **exactly n_listed − 1 only**. For BMP that is 7-of-8 days; for CMP that is 13-of-14 days. Shallower near-misses are not included in block 1.
- **D-03 (block 2 sample):** *(sampling unit and comparison group refined by D-08/D-09)* Sample up to **5,000 near-miss ID × dates per rule row**, fixed seed (to be set in the plan). Sample size is printed on the A3 sheet. If the checkpoint review finds the sample did not expose the missing code, the sample size can be raised and R/147 re-run — no code redesign needed.

### D-4 — Breast imaging denominator presentation (discussed)
- **D-04:** The **all-patient figure is the headline**, labelled "any breast imaging", consistent with every other modality in the B/C sheets. The female-denominator figure sits **directly beside it**, labelled "among women (screening population)".
  - Rationale: Phase 160 measures modality occurrence across the full cohort, not guideline adherence. Keeping the all-patient figure as the lead preserves consistency with all other modalities and keeps male breast imaging in the primary view rather than a side column.
  - Male/unknown-sex patients with ≥1 breast imaging event are reported in `n_patients_other_sex` / `total_event_dates_other_sex` columns — not dropped or hidden.
  - The female figure becomes the natural headline once the work shifts to guideline adherence (deferred Phase 161 territory).
  - KEY sheet explains: all-patient columns = any breast imaging; female columns = screening-population uptake.
- **D-05:** `eligible_sex` column added to `Modalities` sheet. Values: blank (no extra view) or `F` (add female-denominator view). Set to `F` for Mammogram and Breast MRI.

### D-5 — Other analyte thresholds unchanged
- **D-06:** BMP ≥ 4 of 8, LFT ≥ 2 of 4, LIPID ≥ 2 of 3 are unchanged. The run shows no CMP-style spillover: near-misses just below these thresholds total 1,284 days (BMP 4–6 of 8) and 1,888 days (LFT 2–3 of 4) — too small to indicate systematic misclassification.

### Locked decisions (inherited from brief)
- **L-1:** All other Phase 158/159 counting rules are unchanged; thresholds, codes and eligibility come from the codeset file.
- **L-2:** A3 reports only — it never feeds events or counts. Candidate codes need human confirmation before they count.
- **L-3:** `RAW_LAB_NAME` / `RAW_LAB_CODE` appear in the INTERNAL workbook only; release workbook's A3 block 2 shows LOINC-level candidates only.
- **L-4:** A3 block 2 candidate query is restricted in DuckDB to sampled near-miss IDs before `collect()`.
- **L-5:** IMP-04 adds columns and removes nothing — all-patient figures, per-patient table and D sheet are unchanged.

### Decisions added after plan review (2026-09-25)

- **D-07 — Delivered codeset.**
  - `data/reference/surveillance_codeset.xlsx` is delivered with exactly two data edits:
    - CMP `analyte_min_same_day` (SC132) `min_analyte_count` 7 → 11
    - a new Modalities column `eligible_sex` = F on Mammogram and Breast MRI
  - It also has two new KEY rows documenting them.
  - Every other cell of Analysis_Codeset, Lab_Analytes and Lab_Analytes_Excluded is unchanged; 160-01 verifies this against the committed file before replacing it.
- **D-08 — A3 block 2 ranks by contrast, not raw coverage.**
  - Ranking by the share of near-miss days a code appears on would put routine labs (hemoglobin, WBC, platelets) first.
  - Block 2 therefore also samples complete days (all listed analytes present) of the same rule as a comparison group, and ranks each candidate by `lift = coverage on near-miss days − coverage on complete days`.
  - Ranking is within rule × missing analyte (from block 1), keeping the top `A3_TOP_N` = 25 per group.
  - A replacement code for the missing analyte scores near 1; routine labs score near 0.
- **D-09 — A3 sampling and query.**
  - Sampling:
    - Groups are rule × missing analyte for near-miss days, and rule for complete days.
    - One day per patient per group, at most 5,000 days per group.
    - Rows are sorted before sampling with a fixed seed (`A3_SEED` = 2026), so the sample does not depend on database row order.
  - Query:
    - Sampled ID × dates are copied to a DuckDB temp table and joined to LAB_RESULT_CM on ID and date inside the database (L-4).
    - The date comes from `surv_sql_date_expr()`: ISO text, then MM/DD/YYYY, via TRY_CAST / TRY_STRPTIME.
    - Lab_Analytes LOINCs are excluded in SQL.
    - Rows are re-parsed with `parse_pcornet_date()` and filtered exactly in R.
  - If fewer than 50% of sampled days return any lab row, R/147 warns that the date expression needs checking.
  - This replaces the ID-only filter, which would pull whole lab histories.
- **D-10 — Sex handling.**
  - Patients missing from DEMOGRAPHIC, or with SEX other than F/M, count as unknown ("UN") in the other-sex columns; they are never dropped.
  - A zero eligible denominator gives NA percentages and rates.
  - Two extra columns sit beside the six IMP-04 columns:
    - `denominator_eligible` (the eligible N)
    - `total_event_dates_eligible` (needed for complementary suppression)
- **D-11 — Complementary suppression.**
  - Because the all-patient count is published, eligible = all − other-sex.
  - In the release workbook, if either the eligible or the other-sex count is 1–10, both are withheld, along with their percentage or rate.
  - The small one shows "<11" and the other shows blank.
  - This applies separately to patient counts and event-date counts, and to each C-sheet prefix.
  - Done by `suppress_eligible_columns()` before the standard suppression.
- **D-12 — Block 1 scope and release shape.**
  - Block 1 covers only `analyte_all_same_day` rules with ≥ 2 analytes (BMP, CMP, LIPID, LFT). Sensitivity (`analyte_min_same_day`) rows and single-analyte KIDNEY are excluded.
  - Block 2 is aggregated per candidate code, with the most common raw code, name and unit shown for display. The release copy drops RAW-only candidates and the raw code/name columns, so no regrouping is needed.
  - A3 also includes a by-year table (block 1b).
- **D-13 — Checks and names.**
  - R/88 checks the CMP rule as an invariant (threshold > 8, so a full BMP cannot qualify), not the literal "11".
  - Real paths and names are in the corrected canonical references below and the plans; the Modalities names are the full names (Electrocardiogram, Multiple gated acquisition (MUGA), Pulmonary function test, Complete blood count).

### Claude's Discretion
- Exact fixed seed value for A3 block 2 sampling: 2026 (`A3_SEED`).
- Sheet column ordering within A3 blocks.
- Internal variable names for eligibility denominators.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase brief (primary spec)
- `160-SURVEILLANCE-IMPROVEMENTS-BRIEF.md` — full requirements IMP-01..IMP-06, locked decisions L-1..L-5, open decisions D-1..D-5, suggested plans 160-01..160-04, success criteria, pitfalls, data mapping notes

### Prior phase context (architecture and codeset design)
- `.planning/phases/159-lab-surveillance-modalities-and-per-patient-date-counts/159-CONTEXT.md` — D-20 (loader shape), D-19 (delivered codeset structure), D-23 (column lookup from Modalities sheet); read before touching loader or codeset
- `.planning/phases/158-surveillance-modality-frequency/158-CONTEXT.md` — D-14 (DuckDB push-down), D-05 (event grain), D-09 (follow-up end date / person-years), D-13 (tier handling); these are unchanged and apply directly

### Codeset file
- `data/reference/surveillance_codeset.xlsx` — sheets: KEY, Analysis_Codeset (SC001–SC167), Lab_Analytes (LA001–LA189), Lab_Analytes_Excluded, Modalities; IMP-01 edits the Analysis_Codeset CMP row; IMP-04 adds `eligible_sex` to Modalities

### Script under modification
- `R/147_surveillance_modality_frequency.R` — Wave 3 wiring target
- `R/utils/utils_surveillance.R` — pure functions; Wave 1–2 additions go here
- `R/88_smoke_test_comprehensive.R` — Phase 159 section (15ak) extended per IMP-06
- `data/reference/lab_code_crosswalk.xlsx` — crosswalk MASTER, read by A3 for the in_master flag (staged in 159-01)

### Reference for suppression rules and workbook structure
- `data/reference/README.md` — documents the two-workbook release pattern; update per IMP-06

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `load_surveillance_codeset()` — returns tibble; unchanged callers; new companions `load_lab_analytes()` and `load_modality_lookup()` added in Phase 159
- `utils_surveillance.R` — home for all new pure functions (Wave 2): `summarise_missing_analyte()`, `rank_candidate_codes()`, `compute_modality_stats()`, `build_codeset_summary()`
- HL ID temp table pattern (158 D-29 / R/147) — reuse for sampling near-miss IDs in DuckDB before `collect()`
- `DEMOGRAPHIC.SEX` already available via the backend abstraction layer

### Established Patterns
- Codeset-driven design: thresholds and codes live in `surveillance_codeset.xlsx`; script reads and applies them without hardcoding
- DuckDB semi-join then `collect()` — mandatory for any LAB_RESULT_CM query (L-4)
- Two-workbook suppression: INTERNAL includes E sheet and raw text columns; release workbook omits them
- Synthetic fixture tests in `tests/testthat/` — all new pure functions need fixtures per IMP-06

### Integration Points
- `surveillance_codeset.xlsx` → IMP-01 (CMP threshold edit) and IMP-04 (`eligible_sex` column)
- R/147 SECTION ordering: KEY, A, A2, **A3** (new), B, C, D, E (internal only), QC, **Codeset_summary** (new)
- R/88 smoke test section extended: A3 and Codeset_summary produced; `eligible_sex` values valid; no literal row counts
- SCRIPT_INDEX and `data/reference/README.md` updated in Wave 4

</code_context>

<specifics>
## Specific Ideas

- **D-4 KEY wording (from discussion):** "all-patient columns measure any breast imaging across the full cohort; female columns measure screening-population uptake (guideline-style)" — use this framing verbatim or close to it.
- **IMP-03 checkpoint:** Keep the 2026-09-25 INTERNAL workbook on HiPerGator as the before-baseline for BMP/CMP before/after comparison.
- **A3 block 2 pitfall:** If the missing CO2 is coded only in `RAW_LAB_CODE` (no LOINC), adding it needs a new `Lab_Analytes` match column — flag at checkpoint 1 rather than improvising. The planner should surface this as a decision gate in Wave 4.

</specifics>

<deferred>
## Deferred Ideas

- **Care-setting filtering** (inpatient vs outpatient lab counts) — deferred to Phase 161; requires team decisions on ENC_TYPE allowlist and handling events with no encounter
- **Surveillance start window** (post-treatment rather than post-anchor) — deferred to Phase 161; requires team decisions on end-of-treatment definition and fallback

</deferred>

---

*Phase: 160-surveillance-lab-accuracy-and-reporting-improvements*
*Context gathered: 2026-09-25; D-07..D-13 added 2026-09-25 after plan review*
