# Phase 61: Episode Classification - Cancer Linkage & Regimen Detection - Context

**Gathered:** 2026-05-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Classify treatment episodes by linking cancer diagnoses at encounter level (replacing patient-level linkage in R/49) and labeling chemotherapy episodes with specific regimen names (ABVD, BV+AVD, Nivo+AVD). Produces `regimen_label`, `cancer_category`, `cancer_link_method`, and `is_hodgkin` columns in treatment_episodes.rds consumed by Phase 62 (first-line flagging) and Phase 63 (Gantt v2).

</domain>

<decisions>
## Implementation Decisions

### Cancer Linkage Strategy
- **D-01:** Cancer diagnosis linked to treatment episodes via ENCOUNTERID (direct match from DIAGNOSIS table). When ENCOUNTERID match succeeds, cancer_link_method = "encounter_id".
- **D-02:** When ENCOUNTERID match fails, temporal fallback uses closest DIAGNOSIS record with DX_DATE <= episode_start within 30-day window. cancer_link_method = "closest_date".
- **D-03:** Temporal fallback looks backward only (DX_DATE <= episode_start). Diagnosis should precede treatment.
- **D-04:** When multiple cancer diagnoses exist near the same treatment episode, closest date wins. If same date, prefer HL (C81) diagnoses since this is an HL study.
- **D-05:** DIAGNOSIS table only for encounter-level linkage. TUMOR_REGISTRY excluded (no ENCOUNTERID, limited DX_DATE granularity). TUMOR_REGISTRY remains used only for confirmed_hl_cohort.rds (Phase 55).
- **D-06:** HL flag (is_hodgkin) derived from encounter-level cancer_category, not patient-level problem list. TRUE when cancer_category indicates Hodgkin Lymphoma.
- **D-07:** Second cancer confirmation requires 2+ diagnoses at least 7 days apart at encounter level (per SC4). Same confirmation logic as Phase 55 but scoped to encounter-level linkage.
- **D-08:** Episodes with no ENCOUNTERID match AND no temporal match get cancer_link_method = "none" and cancer_category = NA.

### Regimen Matching
- **D-09:** Regimen matching operates at episode level (all drugs across the full episode), not cycle level. An ABVD episode spanning 6 months just needs all required drugs present somewhere in the episode's drug_names.
- **D-10:** Three regimen definitions:
  - ABVD = {doxorubicin, bleomycin, vinblastine, dacarbazine} (all 4 required)
  - BV+AVD = {brentuximab, doxorubicin, vinblastine, dacarbazine} (brentuximab replaces bleomycin)
  - Nivo+AVD = {nivolumab, doxorubicin, vinblastine, dacarbazine} (nivolumab replaces bleomycin)
- **D-11:** Dropped-agent tolerance: ONLY bleomycin can be dropped from ABVD (per RATHL trial standard of care). AVD (doxorubicin + vinblastine + dacarbazine, no bleomycin) still classified as ABVD variant. Missing doxorubicin, vinblastine, or dacarbazine = unknown regimen.
- **D-12:** Added agents disqualify: ABVD + any other agent is NOT ABVD (per SC7).
- **D-13:** Temporal availability rules: BV+AVD only for episodes starting post-2019, Nivo+AVD only post-2024 (per SC8).
- **D-14:** Non-matching chemotherapy episodes get regimen_label = NA (no label forced).

### Output Structure
- **D-15:** New standalone script R/61_episode_classification.R. Loads treatment_episodes.rds and treatment_episode_detail.rds, adds cancer linkage + regimen columns, saves treatment_episodes.rds back in-place. Does not modify R/44a or R/49.
- **D-16:** Columns added to treatment_episodes.rds: cancer_category, cancer_link_method, is_hodgkin, regimen_label.
- **D-17:** Standalone audit xlsx produced (following Phase 60 audit pattern) with sheets for: cancer linkage method distribution, cancer category frequency, regimen distribution, unlinked episode summary.
- **D-18:** Audit xlsx + flat CSV output to output/ directory.

### Claude's Discretion
- Drug name string matching strategy (base ingredient substrings vs explicit name lists, based on drug_name_lookup.rds contents)
- Column ordering for new columns in treatment_episodes.rds
- Audit xlsx sheet count, styling, and column layout
- Console logging detail level
- How to handle the BV+AVD regimen when both brentuximab AND bleomycin appear in the same episode (edge case)
- Whether to produce a CSV export alongside the audit xlsx

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment Episode Data (Primary Input)
- `R/44a_treatment_episodes.R` — Episode extraction with triggering codes, encounter_ids, drug_names. Contains `calculate_episodes_detailed()` for episode splitting. Produces treatment_episodes.rds and treatment_episode_detail.rds.
- `R/43a_treatment_durations.R` — Treatment type definitions and date extraction functions.

### Drug Name Resolution (Phase 60)
- `R/60_drug_name_resolution.R` — Standalone drug name lookup via RxNorm API. Produces drug_name_lookup.rds mapping codes to generic drug names.
- `.planning/phases/60-foundation-encounterid-propagation-and-drug-name-resolution/60-CONTEXT.md` — ENCOUNTERID propagation and drug name resolution decisions. treatment_episodes.rds schema now includes encounter_ids and drug_names columns.

### Cancer Diagnosis Data
- `R/49_gantt_data_export.R` lines 110-403 — Current patient-level PREFIX_MAP cancer category classification. Phase 61 replaces this with encounter-level linkage for the RDS, but R/49 patient-level stays for Gantt v1 backward compatibility.
- `R/55_cancer_summary_refined.R` lines 459-464 — confirmed_hl_cohort.rds creation (ID, first_hl_dx_date, first_hl_dx_source). Phase 55 7-day confirmation logic is the reference for SC4.

### Treatment Code Config
- `R/00_config.R` lines 419-427 — HCPCS codes for ABVD + BV + Nivo (J9000 Doxorubicin, J9040 Bleomycin, J9360 Vinblastine, J9130 Dacarbazine, J9042 Brentuximab, J9299 Nivolumab)
- `R/00_config.R` lines 526-636 — RXNORM CUI codes for chemotherapy agents with inline comments naming each drug

### Downstream Consumers
- `R/62_first_line_and_death_analysis.R` — Expects `regimen_label` column in treatment_episodes.rds (line 79-82: guard with warning if missing). Phase 61 must produce this column.
- `.planning/phases/62-first-line-therapy-and-death-analysis/62-CONTEXT.md` — Phase 62 decisions referencing Phase 61 output (D-01: first-line requires regimen_label)

### Infrastructure
- `R/utils_duckdb.R` — get_pcornet_table() dispatcher for DIAGNOSIS queries
- `R/utils_dates.R` — parse_pcornet_date() for DX_DATE parsing
- `R/01_load_pcornet.R` — Column specs for DIAGNOSIS table (DX, DX_DATE, ENCOUNTERID, DX_TYPE, PDX)

### Requirements
- `.planning/REQUIREMENTS.md` — LINK-01 (encounter linkage), LINK-02 (temporal fallback), LINK-03 (HL from encounter), LINK-04 (second cancer confirmation), REG-01 (regimen labels), REG-02 (dropped-agent tolerance), REG-03 (added agents disqualify), REG-04 (temporal availability)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PREFIX_MAP` (R/49 lines 120-379): Maps 3-character ICD-10-CM prefixes to cancer site categories — reuse for classifying diagnosis codes linked to encounters
- `classify_codes()` (R/49 lines 383-387): Derives category from cancer_code using PREFIX_MAP
- `drug_name_lookup.rds` (Phase 60): Maps RxNorm CUI/NDC codes to generic drug names — the source for understanding what drugs are in each episode
- `confirmed_hl_cohort.rds` (Phase 55): Validated HL patients with first_hl_dx_date — reference for HL confirmation logic
- openxlsx2 styled xlsx pattern (R/60 audit, R/59, R/55): Multi-sheet workbook with color headers, freeze panes
- Episode enrichment pattern (R/62): Load treatment_episodes.rds, add column, save back — same pattern for Phase 61

### Established Patterns
- DuckDB-first queries via `open_pcornet_con()` / `get_pcornet_table()` / `close_pcornet_con()`
- RDS artifact enrichment: Phase 60 added encounter_ids + drug_names in-place; Phase 62 adds is_first_line. Phase 61 follows same pattern.
- Console logging with glue() at each analysis step
- Comma-separated aggregation: `paste(sort(unique(x)), collapse = ",")` for multi-value columns

### Integration Points
- **Input:** treatment_episodes.rds (encounter_ids, drug_names from Phase 60), treatment_episode_detail.rds (per-date drug_name, ENCOUNTERID), DIAGNOSIS table via DuckDB (DX, DX_DATE, ENCOUNTERID)
- **New:** R/61_episode_classification.R, episode_classification_audit.xlsx
- **Modified:** treatment_episodes.rds (+ cancer_category, cancer_link_method, is_hodgkin, regimen_label)
- **Downstream:** Phase 62 reads regimen_label for first-line flagging; Phase 63 reads all 4 new columns for Gantt v2

</code_context>

<specifics>
## Specific Ideas

- ENCOUNTERID population rates vary 39-90% across sites — the temporal fallback will handle a significant portion of linkage. The audit xlsx should clearly show what percentage linked via each method.
- Bleomycin drop from ABVD is per RATHL trial (randomized non-inferiority trial showing AVD non-inferior to ABVD after 2 cycles). This is standard of care, not an edge case.
- BV+AVD (ECHELON-1 trial, FDA approved 2018, widely adopted ~2019) replaces bleomycin with brentuximab vedotin. Nivo+AVD (CheckMate 205/Keynote-204 derivatives, recent adoption ~2024) replaces bleomycin with nivolumab.
- The drug_names column in treatment_episodes.rds is comma-separated generic names. The matching strategy needs to handle RxNorm name variants (e.g., "doxorubicin hydrochloride" vs "doxorubicin").
- R/62 already has a guard (lines 79-82) for missing regimen_label — Phase 61 must produce this column for Phase 62 to work correctly.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 61-episode-classification-cancer-linkage-and-regimen-detection*
*Context gathered: 2026-05-30*
