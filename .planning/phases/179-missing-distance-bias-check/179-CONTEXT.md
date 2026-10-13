# Phase 179: Missing-Distance Bias Check and CBC Capture Check — Context

**Gathered:** 2026-10-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce R/179_distance_missingness.R — a one-off interactive script that:
1. Compares CBC rates between Phase 165 analysis-set encounters and missing-distance encounters (MISS-01/02).
2. Applies the pre-specified bounding sensitivity decision rule (MISS-03).
3. Tests whether the far-from-care → CBC association reflects out-of-system care via a primary (non-CBC lab) and secondary (any encounter) in-system restriction and the Phase 167 single-source-care stratification (MISS-04).

Outputs: counts workbook in `output/` (KEY leftmost, `<11` suppression, UF colors) + encounter-level detail in `output/internal/`. Register in R/39 and SCRIPT_INDEX as a one-off; no new R/88 section.

</domain>

<decisions>
## Implementation Decisions

### CBC outcome definition (locked — do not redefine)
- **D-01:** CBC = WBC (6690-2) + Hgb (718-7) + PLT (777-3) on the same calendar date, as defined in `build_cbc_events()` (`R/utils/utils_distance_cbc.R` line ~108). Returns `tibble(ID, cbc_date)`. Whole record; no date ceiling beyond cohort bounds.
- **D-02:** Encounter-level flag = `cbc_in_encounter`: any `cbc_date` in `[ADMIT_DATE, coalesce(DISCHARGE_DATE, ADMIT_DATE)]` per encounter (`build_enc_analysis()`, line ~182).
- **D-03:** Patient-level flag (post-anchor) = any `cbc_date > hl_anchor_date`; patient-level (whole) = any `cbc_date` in record (`build_pat_analysis()`, line ~277).
- **D-04 (one-year window):** There is **no 365-day cap** in Phase 165's code. "One-year window" in REQUIREMENTS is shorthand for the **post-anchor window** (`ADMIT_DATE > hl_anchor_date`, anchor day = pre per D-13/D-25 from Phase 165). Apply identically to all groups.
- **D-05 (<1 year follow-up):** Phase 165 does **not** explicitly exclude patients with <1 year of follow-up. Patients are included as long as they have ≥1 computed-distance encounter. Apply identical rule to all groups in Phase 179 — do not introduce a follow-up-duration filter.
- **D-06 (unit):** Primary method = **encounter-level** (Rao-Scott, clustered on patient). Sensitivity = **patient-level** Fisher. Both windows (whole record and post-anchor). Matches Phase 165 D-165-01.

### MISS-01/02 — missing-distance comparison
- **D-07:** Universe for Phase 179 = encounters meeting every Phase 165 inclusion rule **except** the `distance_status == "computed"` filter. Source: R/177 candidates (`patient_zip_missing`) UNION Phase 165 analysis set (`computed`). `facility_zip_missing` and `zip_not_in_db` reported separately, not pooled into the primary comparison group.
- **D-08:** Groups: `computed` (Phase 165 set) vs `patient_zip_missing`; `facility_zip_missing` and `zip_not_in_db` reported as supplemental columns (counts + CBC rates), not included in significance tests.
- **D-09:** Comparisons: encounter-level Rao-Scott (clustered on patient) and patient-level (any CBC); breakdown by R/121 triage group (`triage` column from R/121 RDS via R/177 pattern) and by whether the patient has ALL vs SOME encounters missing distance (all-vs-some subgroup).

### MISS-03 — bounding sensitivity and decision rule (locked)
- **D-10:** Bounding sensitivity = Phase 165 association (patient-level Fisher AND Rao-Scott encounter-level) recomputed under two extreme imputation scenarios: (a) all missing encounters assigned `far_from_care_100mi = 1`; (b) all assigned `far_from_care_100mi = 0`. Both bounded ORs with CIs reported alongside the Phase 165 primary estimate.
- **D-11 (decision rule, pre-specified and locked):** If both bounded ORs fall on the **same side of 1** as the Phase 165 estimate → add a stated limitation to the Phase 165 output KEY workbook (`output/distance_cbc_association_20261008.xlsx`). If either bounded OR crosses 1 to the opposite side → flag to Amy/Erin alongside D-165-01; no further milestone analysis. Document which branch was taken and the numeric basis in the workbook KEY.

### MISS-04 — CBC capture check (in-system restriction, locked)
- **D-12 (primary restriction):** ≥1 **non-CBC lab result** in `LAB_RESULT_CM` in the same window used for the CBC outcome, where non-CBC = any `LAB_LOINC` **not** in the Phase 165 CBC code set {6690-2, 718-7, 777-3}. Rationale: a patient with other in-system labs but no CBC in that window is unlikely to be receiving CBC outside our system; a patient with zero in-system labs fits out-of-system lab care.
- **D-13 (secondary restriction):** ≥1 other encounter (any `ENC_TYPE`) in our CDM in the same window, excluding the index encounter.
- **D-14 (window for restriction):** Same post-anchor window (`ADMIT_DATE > hl_anchor_date`) as the CBC outcome. For encounter-level analysis, the restriction is **per-encounter** (non-CBC lab or other encounter in that encounter's date range `[ADMIT_DATE, coalesce(DISCHARGE_DATE, ADMIT_DATE)]`), matching the CBC flag window.
- **D-15 (descriptive first):** Before running restricted associations, report far vs not-far proportions meeting each definition (primary and secondary). This is the first MISS-04 output row in the KEY.
- **D-16 (association in restricted sets):** Rerun Phase 165 OR (both D-165-01 methods: encounter-level Rao-Scott + patient-level Fisher; both windows: whole record and post-anchor) within the primary-restricted set. Report secondary restriction alongside. Apply locked MISS-04 interpretation rule **to the primary restriction result only**.
- **D-17 (interpretation rule, pre-specified and locked):** OR moves toward 1 under restriction/stratification → label "consistent with out-of-system care (non-capture)"; OR stays (or moves away from 1) → label "consistent with a true difference in CBC receipt". Report only; goes to Amy/Erin with D-165-01.
- **D-18 (Phase 167 stratification):** Run the same Phase 165 OR stratified by `single_source_care_post` from R/169 output RDS (`output/internal/single_source_care_<date>.rds`). Report alongside primary restriction result. Apply D-17 interpretation rule to stratified result.

### Methods to use everywhere
- **D-19:** Both D-165-01 methods everywhere: patient-level Fisher (`fisher.test()`) and Rao-Scott clustered chi-square (`survey` package, clustered on patient ID). Both windows (whole record and post-anchor) everywhere. CIs reported for all ORs.

### Execution
- **D-20:** Interactive R on HiPerGator: `module load R/4.5; source("R/179_distance_missingness.R", local = new.env(parent = globalenv()))`. No SLURM, no `Rscript`.
- **D-21:** Local checks = grep-only (no data available locally).

### Outputs
- **D-22:** Counts workbook in `output/` — KEY sheet leftmost, `<11` suppression, UF colors (same `openxlsx` + `suppress_small()` conventions as Phase 165).
- **D-23:** Encounter-level detail in `output/internal/` (gitignored; contains IDs).
- **D-24:** Register in `R/39` (one-off section) and `SCRIPT_INDEX`. No new `R/88` section.

### Claude's Discretion
- Sheet layout within workbook (tab naming, column order within decision-rule-specified content) — follow Phase 165/167 conventions.
- Whether to build a single combined workbook or separate MISS-01/02 and MISS-04 workbooks (recommend single workbook with sections matching MISS-01 through MISS-04 requirement grouping).
- How to source R/177 candidates — follow R/177's RDS-loading pattern (most-recent by mtime or env-var override).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### CBC outcome definition
- `R/utils/utils_distance_cbc.R` — `build_cbc_events()` (line ~108), `build_enc_analysis()` (line ~182), `build_pat_analysis()` (line ~277); CBC LOINCs, encounter flag, patient flag, window logic
- `R/165_distance_cbc_association.R` — Phase 165 primary script; `analyse_window()`, CONFIG usage, Rao-Scott call, Fisher sensitivity

### Phase 165 primary estimate (needed for bounding sensitivity)
- `output/distance_cbc_association_20261008.xlsx` — Phase 165 primary OR (whole + post-anchor, Rao-Scott + Fisher); bounding ORs go beside these in the workbook KEY

### Phase 165 context (locked decisions D-165-01, D-06a, D-13, D-25)
- `.planning/phases/165-distance-100mi-indicator-and-cbc-association/165-CONTEXT.md` — method decisions, anchor-day convention, window definitions, code asset list

### Phase 177 — candidates (missing-distance encounters)
- `R/177_temporal_match_sizing.R` — how R/177 builds `patient_zip_missing` candidate encounters (lines ~234–300); triage attachment pattern; distance_status taxonomy

### Phase 167 — single_source_care flag
- `R/169_single_source_care.R` — `build_single_source_result()`, column names (`single_source_care_post`), RDS output path
- `.planning/phases/167-single-health-system-care-flag/167-CONTEXT.md` — D-167-02 through D-167-07; output columns, anchor source

### R/121 — triage groups
- `R/121_zip_problem_inventory.R` (or its RDS output) — `triage` column used in D-09 breakdown; loading pattern from R/177 lines ~78–104

### Registration targets
- `R/39_*.R` — one-off registration section (follow existing one-off pattern)
- `SCRIPT_INDEX` — phase/script index at repo root

### Config and utilities
- `R/00_config.R` — `CONFIG$far_from_care_cutoff_mi` (100), `CONFIG$far_from_care_cutoff_mi`, date range bounds
- `R/utils/utils_format.R` — `suppress_small()`, UF color palette, `openxlsx` conventions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `build_cbc_events(con, ids)` — call exactly; do not redefine CBC LOINCs or date logic
- `build_enc_analysis(enc_distance, cbc_events, anchors, enc_dates, cutoff)` — call for both the Phase 165 set and for the Phase 179 expanded universe; filter `distance_status` after, not inside (or pass full set and let the function filter internally per its line ~192)
- `build_pat_analysis(enc_analysis, cbc_events, anchors, window)` — patient-level from any `enc_analysis` tibble
- R/177's RDS-loading block for R/121 and R/122 — copy loading pattern; do not re-derive
- `suppress_small()` from `utils_format.R` — apply to all output counts
- `survey::svychisq()` for Rao-Scott — follow Phase 165's `svydesign` call (cluster on `ID`)

### Established Patterns
- Anchor source: read from R/147's anchor RDS directly (D-167-04 pattern); do not source from Phase 165 output
- `distance_status` taxonomy: `"computed"` | `"patient_zip_missing"` | `"facility_zip_missing"` | `"zip_not_in_db"` — defined in R/122
- Post-anchor flag: `ADMIT_DATE > hl_anchor_date` (anchor day = pre); same in Phase 165, 166, 167
- Workbook: `openxlsx`, KEY sheet leftmost, dated filename, `<11` suppression throughout
- Interactive sourcing: `source(f, local = new.env(parent = globalenv()))` — no side-effects on global env

### Integration Points
- R/122 RDS → `enc_distance` tibble (distance_mi, distance_status per ENCOUNTERID)
- R/121 RDS → triage column per patient (PATID)
- R/147 anchor RDS → hl_anchor_date per patient
- R/169 single_source_care RDS → single_source_care_post per patient (MISS-04 stratification)
- Phase 165 ENCOUNTER dates source → `enc_dates` tibble (ENCOUNTERID, ADMIT_DATE, DISCHARGE_DATE, SOURCE)
- `LAB_RESULT_CM` via DuckDB → non-CBC lab check for MISS-04 primary restriction

</code_context>

<specifics>
## Specific Requirements

### MISS-04 primary restriction operationalization
- Non-CBC lab = any row in `LAB_RESULT_CM` where `LAB_LOINC NOT IN ('6690-2', '718-7', '777-3')` and result date falls in the encounter window `[ADMIT_DATE, coalesce(DISCHARGE_DATE, ADMIT_DATE)]` (encounter-level unit) or post-anchor window `(hl_anchor_date, ∞)` (patient-level unit).
- Push the LOINC filter to DuckDB SQL (same push-down pattern as `build_cbc_events()`).

### Decision rule documentation
- The workbook KEY must explicitly state which branch of MISS-03 and MISS-04 was taken and the numeric basis (all four bounded ORs, primary restriction OR, Phase 167 stratified OR).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 179-missing-distance-bias-check*
*Context gathered: 2026-10-13*
