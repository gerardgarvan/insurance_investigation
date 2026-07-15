# Phase 128: DoI Classification - Context

**Gathered:** 2026-07-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce **encounter-level and patient-level diagnosis-of-interest (DoI) classification artifacts** from the real DIAGNOSIS table, with a hard guarantee that no oncology code leaks into the DoI layer.

**In scope:**
- A new investigation script (**R/111**) that pulls DIAGNOSIS via a DuckDB-native prefix filter, classifies DoI codes using the `utils_doi.R` layer from Phase 127, and writes two cached artifacts:
  - `doi_encounters.rds` — one row per (PATID, ENCOUNTERID, DX_DATE, doi_code, doi_category), plus `paraneoplastic_flag` and `in_hl_cohort`
  - `doi_patients.rds` — one row per PATID (has_any_doi, doi_categories ascending, doi_first_date, doi_last_date, n_doi_encounters, in_hl_cohort)
- The mutual-exclusivity hard-stop assertion (DOI-CLASS-04)
- `paraneoplastic_flag` handling for L10.81 (DOI-CLASS-05)
- A `tabyl(doi_category)` clinical-plausibility count review

**Out of scope (later phases):**
- Attribution linkage to rituximab/MTX administrations → Phase 129 (separate R/112)
- The 4-sheet Tableau-ready output workbook → Phase 129
- R/39 registration, SCRIPT_INDEX row, R/88 smoke-test section, HiPerGator runtime gate → Phase 130

</domain>

<decisions>
## Implementation Decisions

### Cohort Scope
- **D-01:** Classify DoI across the **full DIAGNOSIS extract** (all patients), NOT restricted to the HL cohort. The DuckDB-native prefix filter (`WHERE LEFT(DX, 3) IN (...)`) runs *before* `collect()`, so only DoI-prefixed rows are ever materialized — full-extract scope does NOT reintroduce the OOM risk the design constraint guards against. Rationale: lets the investigation observe true DoI prevalence across the extract and leaves cohort-restriction as a Phase 129 decision rather than baking it in here.
- **D-02:** Tag HL-cohort membership on the cached artifacts. Add a boolean **`in_hl_cohort`** column (derived from `get_hl_patient_ids()` in `utils_treatment.R`) to both `doi_encounters.rds` and `doi_patients.rds`. Phase 129 can then split/compare HL-cohort DoI vs full-extract DoI cheaply, and prevalence reviews can report both grains without re-querying DIAGNOSIS.

### Diagnosis Position
- **D-03:** Classify DoI on **all diagnosis positions** (principal `P` + secondary `S` — every DIAGNOSIS row), NOT principal-only. DoI conditions (RA, SLE, IBD, etc.) overwhelmingly present as secondary/comorbid diagnoses; a principal-only filter would miss most real DoI co-occurrences.

### L10.81 (Paraneoplastic Pemphigus) Rollup
- **D-04:** L10.81 encounters **count as DoI** — they set `has_any_doi = TRUE`, appear in `doi_categories`, and are included in `n_doi_encounters` — but carry **`paraneoplastic_flag = TRUE`** as a caveat (DOI-CLASS-05). The flag is the disambiguator between cancer-associated and primary autoimmune pemphigus; segregating L10.81 from the counts would lose the clinically interesting HL+paraneoplastic co-occurrence signal. Phase 129 can filter on the flag if it wants a "pure autoimmune" view.

### Script Organization
- **D-05:** Build **R/111 as a classification-ONLY script** (next number after R/110). It produces `doi_encounters.rds` + `doi_patients.rds` and nothing else. Phase 129's attribution + 4-sheet output goes in a **separate R/112** that reads these cached artifacts. Rationale: one-investigation-per-script convention (matches R/100–R/110), keeps the "utils_cancer.R / R/28 / treatment_episodes.rds are read-only from R/111's perspective" guarantee clean, and makes the cached `.rds` files the explicit hand-off boundary to Phase 129.

### Claude's Discretion
- Exact prefix-filter SQL construction (how the `LEFT(DX, 3) IN (...)` list is assembled from `DOI_CODE_MAP` keys — including handling of 4-char disambiguation keys like D692/D693 within a 3-char pushdown, then refining in R via `classify_doi_codes()`).
- `DX_DATE` null / sentinel-date handling in the encounter grain (follow existing `utils_dates.R` conventions; 1900 sentinel filtering per prior pipeline practice).
- Multi-code-per-encounter representation (the long-format one-row-per-(PATID,ENCOUNTERID,DX_DATE,doi_code,doi_category) grain already permits multiple rows per encounter — no collapse needed at encounter grain).
- `doi_categories` ascending-collapse mechanics at patient grain (sort + unique + delimiter choice), mirroring existing multi-value alphabetical-sort conventions.
- Logging / `tabyl(doi_category)` review output format.
- Whether the mutual-exclusivity assertion uses `stopifnot()` / a custom `checkmate` assertion — as long as it halts the script before any artifact is written.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Prior-phase context & code set (WHAT codes, tiers, exclusions, cross-phase decisions)
- `.planning/phases/127-code-set-and-infrastructure-centralization/127-CONTEXT.md` — locked cross-phase decisions: L10.81 → `paraneoplastic_flag` in 128 (D-02), raw counts / no auto-suppression (D-07), tier tagging, drug-code isolation
- `.planning/phases/127-code-set-and-infrastructure-centralization/127-01-SUMMARY.md` — `DOI_CODE_MAP` / `DOI_CODE_TIER` structure as built (35 prefix keys → 10 labels, Section 4c/4d)
- `.planning/phases/127-code-set-and-infrastructure-centralization/127-02-SUMMARY.md` — `is_doi_code()` / `classify_doi_codes()` signatures and the ICD-9/ICD-10 collision-safe key partitioning as built
- `.planning/research/FEATURES.md` — complete verified 14-category code set, table-stakes vs edge tiers, ICD-9 equivalents, I77.82/D47.Z2/L10.81 handling
- `.planning/research/SUMMARY.md` — executive synthesis, build order, drug-detection isolation rule
- `.planning/research/PITFALLS.md` — ICD-9/10 DX_TYPE gating, D69 4-char disambiguation, mutual-exclusivity hard-stop, dotted/undotted normalization
- `.planning/research/ARCHITECTURE.md` — grain decisions, artifact placement, auto-source glob

### Code patterns to mirror / reuse
- `R/utils/utils_doi.R` — `is_doi_code(dx, dx_type)` + `classify_doi_codes(codes)` (the classification layer built in Phase 127 — the core dependency)
- `R/00_config.R` — `DOI_CODE_MAP` (Section 4c, ~line 434), `DOI_CODE_TIER`, `RITDIS_CODE_VERSION`; `CANCER_SITE_MAP` / `ICD9_CANCER_SITE_MAP` for the mutual-exclusivity comparison
- `R/utils/utils_cancer.R` — `is_cancer_code()` (reused verbatim in the DOI-CLASS-04 mutual-exclusivity assertion) / `classify_codes()`
- `R/utils/utils_duckdb.R` — `open_pcornet_con()`, `get_pcornet_table()` (lazy `tbl`), `materialize()` — the DuckDB pull + native-filter-then-collect idiom
- `R/utils/utils_treatment.R` — `get_hl_patient_ids()` (the `in_hl_cohort` tag source, D-02)
- `R/utils/utils_dates.R` — DX_DATE parsing + 1900-sentinel conventions
- `R/107_med_admin_dispensing_gap_diagnostic.R` — representative recent investigation script: DuckDB `get_pcornet_table()` → `filter()` → `collect()` pattern, header format, cache/output conventions
- `R/39_run_all_investigations.R` + `R/SCRIPT_INDEX.md` — registration targets (deferred to Phase 130, but structure R/111 to fit)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `is_doi_code()` / `classify_doi_codes()` (utils_doi.R) — the classification core; already DX_TYPE-gated and ICD-9/ICD-10 collision-safe.
- `is_cancer_code()` (utils_cancer.R) — reused directly for the DOI-CLASS-04 mutual-exclusivity hard-stop.
- `get_pcornet_table("DIAGNOSIS")` → lazy dbplyr tbl; `filter(substr(DX,1,3) %in% prefixes)` translates to a native SQL `LEFT(DX,3) IN (...)` pushdown before `collect()`.
- `get_hl_patient_ids()` (utils_treatment.R) — supplies the `in_hl_cohort` membership set (D-02).
- `utils_dates.R` — DX_DATE parsing + 1900-sentinel filtering.

### Established Patterns
- Investigation scripts R/100–R/110: standardized header block, `source()` utils at top, DuckDB pull → dplyr transform → `.rds`/xlsx output, read-only w.r.t. upstream artifacts.
- Long-format encounter grain with patient-level rollup derived from it (mirrors treatment-episode / cancer-linkage patterns).
- Multi-value fields sorted ascending alphabetically (universal convention from v3.2 Phase 112).

### Integration Points
- Input: DIAGNOSIS (DuckDB) + `DOI_CODE_MAP`/`DOI_CODE_TIER` (config) + `get_hl_patient_ids()`.
- Output: `doi_encounters.rds` + `doi_patients.rds` in the standard output cache directory — these are the hand-off to Phase 129's R/112.
- Read-only dependencies (must NOT mutate): `utils_cancer.R`, `R/28`, `treatment_episodes.rds`.

</code_context>

<specifics>
## Specific Ideas

- Full-extract classification with an `in_hl_cohort` flag is the explicit design: it gives Phase 129 both the full-extract prevalence and a cheap cohort split without re-querying DIAGNOSIS.
- The mutual-exclusivity assertion must fire and HALT *before* any `.rds` is written — it is a correctness gate, not a warning.
- `paraneoplastic_flag` is a per-encounter caveat column, not a separate category — L10.81 still classifies to its pemphigus DoI category.

</specifics>

<deferred>
## Deferred Ideas

- **Attribution linkage** (rituximab/MTX administration ↔ DoI, ±`DOI_ATTRIBUTION_WINDOW_DAYS`) — Phase 129 (R/112).
- **4-sheet Tableau-ready output workbook + three-state `likely_non_lymphoma_directed` flag** — Phase 129.
- **R/39 registration, SCRIPT_INDEX row, R/88 smoke-test section, HiPerGator runtime gate** — Phase 130.
- **Automated HIPAA small-cell suppression** — explicitly NOT applied (Phase 127 D-07: internal investigation, raw counts, manual suppression before sharing).

None of the discussion strayed outside the classification boundary.

</deferred>

---

*Phase: 128-doi-classification*
*Context gathered: 2026-07-15*
