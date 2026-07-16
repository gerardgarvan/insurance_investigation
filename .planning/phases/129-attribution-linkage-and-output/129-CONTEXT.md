# Phase 129: Attribution Linkage and Output - Context

**Gathered:** 2026-07-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce the **drug↔DoI co-occurrence linkage** (rituximab/MTX administrations ↔ diagnoses of interest) with honest **three-state attribution semantics**, and emit a **4-sheet Tableau-ready xlsx** — following the R/100+ investigation-script convention.

**In scope:**
- A new script (**R/112**) that reads the Phase 128 artifacts (`doi_encounters.rds`, `doi_patients.rds`) plus `treatment_episode_detail.rds` (read-only), performs the two-tier linkage, derives the three-state flag, and writes the 4-sheet workbook `doi_attribution_report.xlsx`.
- Two-tier join: ENCOUNTERID direct match (tier 1) → ±90-day PATID temporal window (tier 2).
- Three-state `likely_non_lymphoma_directed` (TRUE / FALSE / NA) + `attribution_method` column.
- 4 sheets: Patient Prevalence, Encounter Co-occurrence, Drug × DoI Summary, Metadata (with ±30/±180 sensitivity).
- Co-occurrence language ("with [dx]") and CAVEATS footnote on every sheet.

**Out of scope (later phases):**
- R/39 registration, SCRIPT_INDEX row, R/88 smoke-test section, HiPerGator runtime gate → **Phase 130**.

</domain>

<decisions>
## Implementation Decisions

### Small-Cell Suppression (RESOLVES a ROADMAP ↔ REQUIREMENTS conflict)
- **D-01:** **RAW counts, NO automated small-cell suppression.** All four sheets carry raw `n_patients` / `n_encounters`, and every sheet carries an **"INTERNAL-ONLY: raw counts, no automated small-cell suppression — suppress manually before external sharing"** note. This follows **DOI-OUT-02** and **Phase 127 D-07**, and is consistent with what `R/111` already does and the v3.1 internal-investigation pattern.
- **⚠ SUPERSEDES stale roadmap text:** The ROADMAP.md Phase 129 design constraint ("HIPAA suppression: `suppress_small()` (threshold 11L) applied to every `n_patients`/`n_encounters` column in Sheet 3 before xlsx write") and **Success Criterion #3** ("cells 1-10 appear as '<11'") are **superseded by this decision.** The requirement (DOI-OUT-02) is authoritative over the roadmap's generic-HIPAA carryover. Do **NOT** call `suppress_small()` on the output. The planner should treat SC#3 as satisfied-by-substitution: the internal-only note replaces automated suppression.

### Report Cohort Scope
- **D-02:** **Cover the full extract, but carry the `in_hl_cohort` dimension on every sheet** so HL vs non-HL DoI co-occurrence is directly comparable. This leverages the `in_hl_cohort` tag Phase 128 deliberately added (128 D-01/D-02) — full-extract prevalence context AND the clinically-relevant HL slice in one workbook, with no re-query. Sheets should either split rows by `in_hl_cohort` or include it as a group/column dimension (planner's choice on layout).

### "HL Active in Window" Signal (defines the three-state NA)
- **D-03:** Define **"HL also active in the same ±90-day window"** using **actual HL diagnosis dates pulled from DIAGNOSIS** (a small, DX_TYPE-gated, HL-ICD-9/10-filtered DuckDB pull — cheap, native-filtered before collect()). The **NA** state fires when an HL diagnosis falls within ±`DOI_ATTRIBUTION_WINDOW_DAYS` of the drug administration. This gives true temporal semantics matching the rigor of the two-tier join. `get_hl_patient_ids()` (IDs only, no dates) is **insufficient** for the NA test — a dated HL pull is required. Mirror the HL-code filter logic already in `get_hl_patient_ids()` (`ICD_CODES$hl_icd10` / `ICD_CODES$hl_icd9`) but retain `DX_DATE`.
- Three-state semantics (locked by roadmap, restated for the planner): **TRUE** = drug co-occurs with a DoI AND no HL active in the same window; **NA** = HL also active in the same ±90-day window (ambiguous — must NOT be collapsed to FALSE); **FALSE** = no drug↔DoI co-occurrence.

### Script Organization
- **D-04:** Build attribution as a **NEW script `R/112_doi_attribution_report.R`**, keeping `R/111` classification-only. This honors Phase 128 D-05 (one-investigation-per-script; `.rds` artifacts as the clean hand-off boundary).
- **⚠ SUPERSEDES stale roadmap text:** Phase 130's roadmap references to **`R/111_doi_attribution_report.R`** are a naming slip — the attribution script is **`R/112_doi_attribution_report.R`**. Phase 130 registration (R/39, SCRIPT_INDEX, R/88) must target **R/112** for attribution and **R/111** for classification. The output workbook is `doi_attribution_report.xlsx`.

### Locked by ROADMAP / prior phases (not re-discussed — restated so the planner has them)
- Two-tier join: ENCOUNTERID direct match (tier 1, higher confidence) before ±90-day PATID window (tier 2); `DOI_ATTRIBUTION_WINDOW_DAYS = 90L` is the named constant, never a magic number.
- `attribution_method` column values: `encounter_id` / `temporal_window` / `none`.
- **Co-occurrence language only:** all column names and prose use "with [dx]" — never "for [dx]"; no column named `rituximab_for_*` / `mtx_reason_*` / anything with `_for_`.
- CAVEATS footnote on **every** sheet: "Co-occurrence does not imply treatment attribution. Clinical chart review required for confirmation."
- 4 sheets: (1) Patient Prevalence, (2) Encounter Co-occurrence (with `attribution_method`), (3) Drug × DoI Summary, (4) Metadata.
- Metadata sheet documents `DOI_ATTRIBUTION_WINDOW_DAYS = 90` plus ±30-day and ±180-day sensitivity comparison counts for SME review.
- Drug administrations read from `treatment_episode_detail.rds` (read-only) filtered to `RITUXIMAB_CODES | MTX_CODES` (match on `triggering_code`) — **no additional DuckDB query for drug administrations** (the only new DuckDB pull permitted is the dated HL-diagnosis pull for D-03).

### Claude's Discretion
- Exact sheet layout for the `in_hl_cohort` split (separate row-blocks, a grouping column, or per-sheet — as long as HL vs non-HL is comparable per D-02).
- xlsx writer mechanics (openxlsx workbook/sheet/footnote styling) — mirror an existing multi-sheet writer (e.g. R/36 / R/109 / R/110).
- Encounter-grain vs patient-grain rollup mechanics for each sheet, ascending-alphabetical multi-value collapse (v3.2 Phase 112 convention, "; " delimiter).
- How the dated HL pull is assembled (standalone helper vs inline), as long as it stays a native-filtered pull before collect().
- Placement/format of the internal-only note and CAVEATS footnote within each sheet.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative requirements & cross-phase decisions
- `.planning/REQUIREMENTS.md` — **DOI-ATTR-01/02/03, DOI-OUT-01/02/03**. DOI-OUT-02 (raw counts / no auto-suppression) is **authoritative over** the ROADMAP Phase 129 suppression design constraint (see D-01).
- `.planning/ROADMAP.md` §"Phase 129" — design constraints + success criteria. NOTE: the `suppress_small()`/"<11" constraint (SC#3) and the "R/111_doi_attribution_report.R" naming are **superseded** by D-01 and D-04 respectively.
- `.planning/phases/128-doi-classification/128-CONTEXT.md` — locked decisions D-01..D-05: full-extract scope, `in_hl_cohort` tag rationale (D-02), L10.81 `paraneoplastic_flag`, R/111 classification-only / R/112 attribution boundary (D-05).
- `.planning/phases/128-doi-classification/128-01-SUMMARY.md` — `doi_encounters.rds` columns as built: `ID, ENCOUNTERID, DX_DATE, doi_code, doi_category, paraneoplastic_flag, in_hl_cohort`.
- `.planning/phases/128-doi-classification/128-02-SUMMARY.md` — `doi_patients.rds` columns as built: one row per ID with `has_any_doi, doi_categories, doi_first_date, doi_last_date, n_doi_encounters, in_hl_cohort`.
- `.planning/phases/127-code-set-and-infrastructure-centralization/127-CONTEXT.md` — D-07 (raw counts / manual suppression) and drug-code isolation.

### Research (code set, tiers, pitfalls, architecture)
- `.planning/research/SUMMARY.md` — executive synthesis, build order, drug-detection isolation rule.
- `.planning/research/FEATURES.md` — full DoI code set, table-stakes vs edge tiers, ICD-9 equivalents.
- `.planning/research/PITFALLS.md` — DX_TYPE gating, dotted/undotted normalization, temporal-window pitfalls.
- `.planning/research/ARCHITECTURE.md` — grain decisions, artifact placement.

### Code to read/reuse
- `R/111_doi_classification.R` — the input producer (writes `doi_encounters.rds` / `doi_patients.rds`); mirror its header, internal-only note, and DuckDB self-bootstrap for the D-03 HL pull.
- `R/26_treatment_episodes.R` §865-870 — writes `treatment_episode_detail.rds`; columns: `patient_id, treatment_type, treatment_date, triggering_code, ENCOUNTERID, drug_name, episode_number, episode_start, episode_stop, historical_flag`. Filter `triggering_code %in% (RITUXIMAB_CODES | MTX_CODES)` for drug administrations.
- `R/utils/utils_treatment.R` §62-88 — `get_hl_patient_ids()`: HL ICD-9/10 filter logic to mirror for the **dated** HL pull (D-03). Note it returns IDs only — you must add `DX_DATE`.
- `R/00_config.R` — `RITUXIMAB_CODES`, `MTX_CODES`, `DOI_ATTRIBUTION_WINDOW_DAYS = 90L` (Section 4d); `DOI_CODE_MAP` (Section 4c); `ICD_CODES$hl_icd10` / `ICD_CODES$hl_icd9`; `CONFIG$cache$outputs_dir` / `CONFIG$output_dir`.
- `R/utils/utils_duckdb.R` — `open_pcornet_con()`, `get_pcornet_table()` (lazy tbl), native-filter-then-collect idiom for the dated HL pull.
- `R/36_tableau_ready_tables.R`, `R/109_med_admin_dispensing_fix_impact_audit.R`, `R/110_output_level_before_after_report.R` — multi-sheet xlsx writer patterns (openxlsx). NOTE: these define a local `suppress_small()` — do **NOT** apply it here (D-01); read them only for sheet/footnote mechanics.
- `R/107_med_admin_dispensing_gap_diagnostic.R` — representative recent investigation-script header + DuckDB self-bootstrap + close_pcornet_con teardown.
- `R/39_run_all_investigations.R` + `R/SCRIPT_INDEX.md` — registration targets (Phase 130), must reference **R/112** for attribution.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `treatment_episode_detail.rds` (R/26) — drug administrations at `(patient_id, treatment_date, triggering_code, ENCOUNTERID, drug_name, ...)`; filter `triggering_code` to `RITUXIMAB_CODES | MTX_CODES`. Read-only.
- `doi_encounters.rds` / `doi_patients.rds` (R/111) — DoI encounter + patient grains, both carrying `in_hl_cohort`. Read-only.
- `get_hl_patient_ids()` HL-code filter (utils_treatment.R) — pattern to mirror for the dated HL pull (add `DX_DATE`, keep DX_TYPE gating).
- Multi-sheet xlsx writers in R/36 / R/109 / R/110 (openxlsx) — layout/footnote mechanics.
- `RITUXIMAB_CODES`, `MTX_CODES`, `DOI_ATTRIBUTION_WINDOW_DAYS` (config, Section 4d) — the named constants for the join.

### Established Patterns
- Investigation scripts R/100–R/111: standardized header, `source()` utils, DuckDB pull → dplyr transform → `.rds`/xlsx, read-only w.r.t. upstream artifacts, self-bootstrap DuckDB + `close_pcornet_con()` teardown.
- `suppress_small()` is copy-pasted per-script (not centralized) with two conventions ("<11" string vs `NA_integer_`) — **not used here** per D-01, but this is why there's no shared suppression util.
- Multi-value fields sorted ascending alphabetically, "; " delimiter (v3.2 Phase 112).
- Two-tier ENCOUNTERID-then-temporal-window join mirrors R/28 D-01/D-02.

### Integration Points
- Inputs: `doi_encounters.rds` + `doi_patients.rds` (R/111) + `treatment_episode_detail.rds` (R/26) + a new dated HL-dx DuckDB pull + config constants.
- Output: `doi_attribution_report.xlsx` (4 sheets) in the standard output dir — the hand-off to Phase 130 registration.
- Read-only dependencies (must NOT mutate): `treatment_episode_detail.rds`, `utils_cancer.R`, R/28, R/111 artifacts.

</code_context>

<specifics>
## Specific Ideas

- The suppression conflict was surfaced during discussion and resolved in favor of the formal requirement (DOI-OUT-02): raw counts + internal-only note, NO `suppress_small()`. Rare DoI categories (NMO, pemphigus, GPA) will show single-digit cells by design — that signal is wanted for internal SME review.
- The three-state flag's clinical value is the **NA** state — it must reflect a real dated HL-diagnosis co-occurrence in the same ±90-day window, not mere HL-cohort membership. A dated HL pull is mandatory.
- `in_hl_cohort` is the comparison axis Phase 128 built for; the report should make HL vs non-HL DoI co-occurrence legible on every sheet.

</specifics>

<deferred>
## Deferred Ideas

- **R/39 registration, SCRIPT_INDEX row, R/88 smoke-test section, HiPerGator runtime gate** — Phase 130 (must target R/112 for attribution).
- **A separate externally-shareable, suppressed workbook** — considered (suppression option "Both: two files") and declined for now; can be produced manually before sharing per the internal-only note.
- **Roadmap text cleanup** (SC#3 suppression wording; "R/111_doi_attribution_report.R" naming) — superseded by D-01/D-04 in this context; the roadmap prose itself was left as-is (decisions captured here govern).

None of the discussion strayed outside the attribution + output boundary.

</deferred>

---

*Phase: 129-attribution-linkage-and-output*
*Context gathered: 2026-07-15*
