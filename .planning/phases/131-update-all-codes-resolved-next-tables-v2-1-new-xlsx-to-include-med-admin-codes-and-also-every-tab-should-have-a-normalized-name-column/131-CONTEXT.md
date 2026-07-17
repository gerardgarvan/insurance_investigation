# Phase 131: Update all_codes_resolved_next_tables_v2.1_new.xlsx — Context

**Gathered:** 2026-07-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Two changes to `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` (the reference xlsx that documents all resolved treatment codes):

1. **Add MED_ADMIN codes** — After Phase 122 fixed MED_ADMIN chemo detection, the xlsx does not yet reflect MED_ADMIN as a source. Add new rows for RxNorm CUIs that appear in MED_ADMIN data but NOT in PRESCRIBING, across all applicable treatment tabs.
2. **Add `normalized_name` column to every tab** — Supportive Care already has a "Normalized Meaning" column (Phase 120 / R/105). Rename it to `normalized_name` and add the same column to all other tabs (Chemotherapy, Radiation, SCT, Immunotherapy, Unrelated, Index, Sheet1).

The canonical file stays `all_codes_resolved_next_tables_v2.1.xlsx` — no script path changes. Changes are developed against `v2.1_new.xlsx` then written back to overwrite `v2.1.xlsx`.

</domain>

<decisions>
## Implementation Decisions

### MED_ADMIN code rows
- **D-01:** Add rows ONLY for RxNorm CUIs that appear in MED_ADMIN (`MEDADMIN_TYPE=='RX'`) but NOT in PRESCRIBING (i.e., codes exclusive to MED_ADMIN). Existing rows with `Source Table = PRESCRIBING` are NOT modified.
- **D-02:** Source of new rows: a DuckDB query at runtime that anti-joins MED_ADMIN CUIs against PRESCRIBING CUIs for each treatment type.
- **D-03:** Scope is all applicable treatment tabs, not just Chemotherapy — query MED_ADMIN against each treatment type's code list and route new rows to the correct tab (Chemotherapy, Supportive Care, Immunotherapy, etc.).
- **D-04:** New rows use `Source Table = MED_ADMIN` and inherit columns appropriate to that tab (Code, Meaning, Code Type, Source Table, Records, Patients).

### normalized_name column
- **D-05:** Column name is `normalized_name` (snake_case) on ALL tabs — uniform across the workbook.
- **D-06:** Supportive Care tab: rename existing "Normalized Meaning" column header to `normalized_name`. Data values remain unchanged.
- **D-07:** For RxNorm CUI rows on any tab: apply the same RxNav ingredient lookup as R/105 (IN concept resolution with cached fallback). This collapses dosage/brand/salt variants to a canonical ingredient name.
- **D-08:** For non-RxNorm rows (CPT/HCPCS, ICD-10, NDC, DRG): copy the existing `Meaning` column value into `normalized_name` verbatim. No external lookup needed.

### File versioning
- **D-09:** Canonical filename stays `data/reference/all_codes_resolved_next_tables_v2.1.xlsx`. No R script path changes are needed.
- **D-10:** Workflow: develop/test against `v2.1_new.xlsx`, then overwrite `v2.1.xlsx` with the final result.

### Claude's Discretion
- Column position for `normalized_name`: place as the last column on each tab (appended after existing columns), consistent with how Supportive Care had "Normalized Meaning" appended as column G.
- Whether Index and Sheet1 tabs get `normalized_name`: these are summary/metadata tabs with no code rows — Claude should assess whether adding the column makes sense or skip non-code tabs.
- R/88 smoke test update: the existing check for "Normalized Meaning" (section 15r) must be updated to check for `normalized_name` — Claude decides the exact assertion update.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Reference xlsx
- `data/reference/all_codes_resolved_next_tables_v2.1_new.xlsx` — the working copy being updated (source of current sheet structure)
- `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` — the canonical file to overwrite with final result

### Scripts that read/write the xlsx (must remain compatible)
- `R/105_normalize_supportive_care_meaning.R` — writes "Normalized Meaning" col on Supportive Care tab (line 67: XLSX_PATH, line 363: col header write); must be updated to use `normalized_name`
- `R/00_config.R` — defines `REFERENCE_XLSX` at line 2476; also defines `TREATMENT_CODES` (chemo_rxnorm list) used to identify MED_ADMIN chemo hits
- `R/36_tableau_ready_tables.R` — reads xlsx via `REFERENCE_XLSX` at line 70
- `R/55_verify_replaced_by_codes.R` — reads xlsx via `XLSX_PATH` at line 52
- `R/56_new_tables_from_groupings.R` — reads xlsx via `REFERENCE_XLSX` at line 80
- `R/57_drug_grouping_instances.R` — reads xlsx via `REFERENCE_XLSX` at line 75
- `R/57_explore_dx_deduplication.R` — reads xlsx via `REFERENCE_XLSX` at line 71
- `R/58_code_reference_tables.R` — reads xlsx at line 41
- `R/88_smoke_test_comprehensive.R` — checks for "Normalized Meaning" in section 15r (lines 2479-2481); must be updated to check `normalized_name`

### Phase 120 / R/105 reference implementation
- `R/105_normalize_supportive_care_meaning.R` — full implementation of RxNav ingredient lookup with cache. This is the reference implementation for the normalized_name RxNorm resolution logic.

### Phase 122 context (MED_ADMIN fix)
- `R/107_med_admin_dispensing_gap_diagnostic.R` — documents MED_ADMIN structure: `MEDADMIN_CODE` (CUI), `MEDADMIN_TYPE` ('RX' ≈71% / 'ND' ≈22%)
- `R/utils/utils_treatment.R` — `get_chemo_hits()` helper that queries MED_ADMIN; shows how to query MED_ADMIN CUIs from DuckDB

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/105_normalize_supportive_care_meaning.R` §§ 2–4: RxNav resolution loop + `rxnorm_ingredient_cache.csv` — reuse for `normalized_name` on RxNorm rows in other tabs
- `R/utils/utils_treatment.R` `get_chemo_hits()` — shows DuckDB MED_ADMIN query pattern (`MEDADMIN_TYPE=='RX'`, `MEDADMIN_CODE`)
- `data/reference/rxnorm_ingredient_cache.csv` — already built; reuse to avoid re-querying RxNav

### Established Patterns
- In-place xlsx edit via `openxlsx2`: workbook loaded, column appended, saved back to same path (R/105 §6 pattern)
- Column append: write header to row 2 of target column, data to rows 3+
- Round-trip verification: re-open and assert column exists + no blank values (R/105 §7)

### Integration Points
- `REFERENCE_XLSX` defined in R/00_config.R (line 2476) — all readers use this variable; no path change needed but note that R/105 has its own hardcoded `XLSX_PATH`
- R/88 smoke tests reference "Normalized Meaning" column by name — must be updated when renaming to `normalized_name`

</code_context>

<specifics>
## Specific Ideas

- The `v2.1_new.xlsx` is already the working copy — it was presumably the file being prepared for this update. Inspect it first to confirm current sheet structure before writing.
- MED_ADMIN rows should populate Records and Patients counts from the DuckDB query (same columns as existing rows).
- The `normalized_name` RxNav resolution can share the existing `rxnorm_ingredient_cache.csv` — no need for a separate cache file.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 131-update-all-codes-resolved-next-tables-v2-1-new-xlsx*
*Context gathered: 2026-07-17*
