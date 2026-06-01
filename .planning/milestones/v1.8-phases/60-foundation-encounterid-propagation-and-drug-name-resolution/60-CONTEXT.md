# Phase 60: Foundation - ENCOUNTERID Propagation & Drug Name Resolution - Context

**Gathered:** 2026-05-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish infrastructure for encounter-level analysis by propagating encounter IDs through treatment episodes, resolving specific drug names for chemotherapy agents via RxNorm API, and tightening SCT detection to exclude ICD diagnosis codes. This is a foundation phase — Phases 61-63 build on the columns and artifacts produced here.

</domain>

<decisions>
## Implementation Decisions

### ENCOUNTERID Propagation
- **D-01:** Modify R/43a_treatment_durations.R and R/44a_treatment_episodes.R in-place to add ENCOUNTERID extraction from source tables. No new wrapper scripts.
- **D-02:** ENCOUNTERID is extracted alongside ID, treatment_date, and triggering_code from each source table (PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER, DIAGNOSIS). TUMOR_REGISTRY has no ENCOUNTERID — uses NA.
- **D-03:** Episode-level `encounter_ids` column uses comma-separated string format (consistent with existing `triggering_codes` pattern). Multiple encounter IDs per episode are deduplicated and joined.
- **D-04:** NULL/missing ENCOUNTERID values are omitted from the comma-separated list. An episode where all dates lack encounter IDs shows empty string. No "NA" or "MISSING" markers in the list.
- **D-05:** A data inspection step runs first to measure ENCOUNTERID population rates per source table (PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER, DIAGNOSIS) and logs results to console. Documents data quality before propagation.

### Drug Name Resolution
- **D-06:** Drug name resolution covers chemotherapy only. Other treatment types (radiation, SCT, immunotherapy) do not get drug name resolution in this phase.
- **D-07:** Both RXNORM_CUI and NDC codes are resolved to generic drug names. Reuses R/40's `lookup_rxcui_name()` and `lookup_ndc_to_name()` functions (httr2, retry logic, 0.1s rate limiting).
- **D-08:** Only codes that actually appear in patient data (from PRESCRIBING, DISPENSING, MED_ADMIN queries) are resolved. No pre-emptive resolution of unused config codes.
- **D-09:** API results are cached in `drug_name_lookup.rds`. On re-run, cached results are loaded and only new/unresolved codes trigger API calls.
- **D-10:** Drug name resolution is a standalone script `R/60_drug_name_resolution.R` that produces `drug_name_lookup.rds` + `drug_name_lookup.csv`. Separated from episode extraction so it can be re-run independently without re-processing episodes.

### Output Strategy
- **D-11:** Existing RDS artifacts (`treatment_episodes.rds`, `treatment_episode_detail.rds`) gain new columns in-place: `encounter_ids` and `drug_names`. No v2 RDS split — Phases 61-62 consume the enhanced artifacts directly.
- **D-12:** R/44a joins drug names from `drug_name_lookup.rds` onto episode detail, then aggregates per episode as comma-separated `drug_names` column in `treatment_episodes.rds`.

### SCT Detection Tightening
- **D-13:** SCT source audit runs as a pre/post comparison: first run SCT detection with ICD DX codes included, then without, showing the delta (patients who lose SCT status vs patients retained by other sources).
- **D-14:** SCT Source Audit results appear as a sheet in the broader Phase 60 output xlsx (not a standalone report).
- **D-15:** After audit, `sct_dx_icd10` vector is removed entirely from `TREATMENT_CODES` in R/00_config.R. Clean break — no commented-out code.
- **D-16:** SCT DX code removal affects both R/43a (`extract_sct_dates()`) and R/44a (`extract_sct_dates_with_codes()`). The DIAGNOSIS source section is deleted from both functions.

### Claude's Discretion
- Script numbering for the drug name resolution script (R/60 suggested)
- Column ordering for new columns in RDS and CSV output
- Console logging detail level for ENCOUNTERID population rates
- xlsx sheet ordering and styling in the Phase 60 output workbook
- Whether to source R/40's lookup functions directly or copy them into R/60

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment Episode Extraction (Primary Modification Targets)
- `R/43a_treatment_durations.R` — Per-patient treatment duration analysis. Contains `extract_sct_dates()` (lines 278-346) with DIAGNOSIS source section to remove. All extraction functions need ENCOUNTERID added.
- `R/44a_treatment_episodes.R` — Episode-level detail with triggering codes. Contains `extract_sct_dates_with_codes()` with DIAGNOSIS source section to remove. All extraction functions need ENCOUNTERID added. `calculate_episodes_detailed()` needs encounter_ids aggregation.

### RxNorm API Lookup (Reusable Pattern)
- `R/40_investigate_unmatched_ndc.R` lines 227-372 — `lookup_rxcui_name()`, `lookup_ndc_to_name()`, `lookup_drug_codes_batch()` with httr2 retry logic and rate limiting

### Treatment Code Config
- `R/00_config.R` lines 946-1196 — TREATMENT_CODES SCT section with `sct_dx_icd10` vector (Z94.84, T86.5, T86.09, Z48.290, T86.0) to be removed
- `R/00_config.R` lines 392-945 — Chemotherapy RXNORM_CUI and NDC code vectors for drug name resolution scope

### Gantt Export (Downstream Consumer)
- `R/49_gantt_data_export.R` — Loads treatment_episodes.rds and treatment_episode_detail.rds. Will need to propagate new encounter_ids and drug_names columns to Gantt CSVs.

### Infrastructure
- `R/01_load_pcornet.R` — Column specs for PCORnet tables (ENCOUNTERID present in PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER, DIAGNOSIS specs)
- `R/utils_duckdb.R` — `get_pcornet_table()` dispatcher for DuckDB queries
- `R/utils_treatment.R` — `safe_table()` NULL-guard wrapper

### Prior Phase Context
- `.planning/phases/44-treatment-episode-start-stop-dates/44-CONTEXT.md` — Episode structure decisions (90-day gap, 4 types, dual-RDS output)
- `.planning/phases/59-death-date-validation-and-treatment-timeline-cleanup/59-CONTEXT.md` — Most recent modifications to R/49 and episode pipeline

### Requirements
- `.planning/REQUIREMENTS.md` — TREAT-01 (SCT audit), TREAT-02 (drug names via RxNorm), TREAT-03 (lookup table artifact), TREAT-04 (drug names in Gantt)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lookup_rxcui_name()` / `lookup_ndc_to_name()` (R/40): httr2-based RxNorm API lookup with retry logic — directly reusable for drug name resolution
- `classify_drug()` (R/40 lines 387-419): Drug classification by name (chemo, immuno, SCT, supportive care) — may be useful for validation
- `extract_dates_with_codes()` pattern (R/44a): 3-column extraction (ID, date, code) — extend to 4-column (+ ENCOUNTERID)
- `stack_and_dedup_with_codes()` (R/44a): Multi-source stacking — extend to include ENCOUNTERID
- Comma-separated aggregation pattern: `paste(unique(x), collapse = ",")` used for triggering_codes — reuse for encounter_ids and drug_names

### Established Patterns
- DuckDB-first queries via `open_pcornet_con()` / `get_pcornet_table()` / `close_pcornet_con()`
- Per-type extraction functions dispatched by `extract_all_dates(type)` / `extract_dates_with_codes(type)`
- Console logging with `glue()` at each extraction step
- RDS artifacts saved to `CONFIG$cache$outputs_dir`
- openxlsx2 styled xlsx with color-coded headers

### Integration Points
- **Input:** PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER, DIAGNOSIS tables via DuckDB (for ENCOUNTERID extraction)
- **Modified:** R/43a_treatment_durations.R (ENCOUNTERID + SCT DX removal), R/44a_treatment_episodes.R (ENCOUNTERID + drug names + SCT DX removal), R/00_config.R (sct_dx_icd10 removal), R/49_gantt_data_export.R (new columns to CSVs)
- **New:** R/60_drug_name_resolution.R (standalone drug name lookup builder)
- **New output:** drug_name_lookup.rds, drug_name_lookup.csv, Phase 60 audit xlsx
- **Modified output:** treatment_episodes.rds (+ encounter_ids, drug_names), treatment_episode_detail.rds (+ ENCOUNTERID, drug_name), gantt_episodes.csv, gantt_detail.csv (+ encounter_ids, drug_names)

</code_context>

<specifics>
## Specific Ideas

- ENCOUNTERID population rate inspection is critical because STATE.md notes 39-90% range across sites — this determines how useful encounter-level linkage will be in Phase 61
- Drug name resolution separates cleanly from episode extraction because API calls are slow (~0.1s each) and should be cached independently
- The sct_dx_icd10 codes (Z94.84 history of bone marrow transplant, T86.5 complications of SCT, etc.) are status/history codes, not procedure codes — removing them aligns with the principle that diagnosis codes indicate history, not procedure occurrence
- The pre/post SCT audit quantifies exactly how many patients' SCT detection depends solely on these DX codes, providing clinical justification for the removal

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 60-foundation-encounterid-propagation-and-drug-name-resolution*
*Context gathered: 2026-05-29*
