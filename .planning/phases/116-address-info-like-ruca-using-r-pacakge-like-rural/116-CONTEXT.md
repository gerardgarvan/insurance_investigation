# Phase 116: RUCA Rurality Address Enrichment - Context

**Gathered:** 2026-07-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Enrich the HL cohort with USDA RUCA (Rural-Urban Commuting Area) rurality classification derived from DEMOGRAPHIC.ZIP_CODE, and produce a standalone rurality summary xlsx with four stratified cross-tabs (patient counts, payer, treatment type, cancer category).

**In scope:**
- Bundle USDA RUCA reference file in the repo
- ZIP-code -> RUCA lookup with both raw code and condensed 4-tier label
- New standalone R script (next available R/NN number) producing one xlsx with multiple sheets
- Encounter-level unit of analysis for cross-tabs (patient-level for the simple frequency sheet)
- R/88 smoke test section validating structural integrity of the new script

**Out of scope:**
- Adding rurality columns to Gantt or cohort snapshot outputs (deliverable is standalone xlsx, not enrichment column)
- AV+TH subset variant (unlike payer analyses)
- Auto-HIPAA suppression in the xlsx (raw counts, manual suppression before external sharing per existing v3.1 pattern)
- Longitudinal address history (DEMOGRAPHIC.ZIP_CODE is a single snapshot; no LDS_ADDRESS_HISTORY available)
- Census-tract-level RUCA (would require geocoding; ZIP-level is sufficient)

</domain>

<decisions>
## Implementation Decisions

### Data source & granularity
- Bundle USDA RUCA reference xlsx in the repo (like MEDICATION_LOOKUP pattern) -- no CRAN dependency, works offline on HiPerGator and local Windows
- Use latest available 2020 census-based ZIP RUCA if released; otherwise fall back to 2010 ZIP RUCA (planner to verify availability)
- ZIP-code-level RUCA (not census tract) -- DEMOGRAPHIC only has ZIP_CODE, no geocoding needed
- Store BOTH the raw RUCA code (e.g., 1.0, 4.1, 10.6) AND a condensed 4-tier label (Metropolitan / Micropolitan / Small town / Rural) for flexibility

### RUCA lookup location
- New standalone script: `R/NN_ruca_rurality_summary.R` (planner picks next available number)
- RUCA_LOOKUP loading logic lives inside this script (not R/00_config.R) since it's a single-consumer table; reconsider only if a second script needs it
- Follow investigation-script pattern (R/40, R/79) -- self-contained, runnable independently

### Missing ZIP handling
- Assign NA rurality for patients with blank / unmatchable / out-of-state / out-of-range ZIP
- Log count of NA assignments (attrition-style diagnostic message) so the analyst sees coverage
- NAs remain in the analysis but appear as their own row/column in cross-tabs (do NOT drop them)

### Summary xlsx contents (all four stratifications)
- Sheet 1: Patient counts by rurality category -- unique PATID counts + percentages (patient-level for this sheet)
- Sheet 2: Rurality x AMC 8-category payer (encounter-level counts) -- uses existing AMC_PAYER_LOOKUP from R/00_config.R
- Sheet 3: Rurality x Treatment type (encounter-level counts) -- chemo / radiation / SCT / immunotherapy / proton (5 categories per v2.3)
- Sheet 4: Rurality x Cancer category (encounter-level counts) -- HL / NLPHL / NHL / other categories per classify_codes()
- Row totals and column totals on each cross-tab sheet

### Unit of analysis
- Cross-tabs (sheets 2-4): encounter-level (each encounter carries the patient's rurality)
- Simple frequency (sheet 1): patient-level (one row per PATID) since "patient counts" is inherently patient-scoped
- Document the mixed grain clearly in xlsx titles / sheet notes so analysts don't confuse the two

### Output conventions
- No HIPAA auto-suppression -- raw counts in xlsx, manual suppression before external sharing (v3.1 pattern)
- No AV+TH subset variant -- rurality is a patient attribute; ENC_TYPE subsetting adds noise without insight for this analysis
- Ascending alphabetical sort on any multi-value labels (per SORT-01/SORT-02 from Phase 112)

### R/88 smoke test integration
- Standard structural validation section for the new script (matches v2.0+ pattern)
- Verify: RUCA_LOOKUP loading, ZIP normalization, NA count logging, all four sheets produced, correct column structure per sheet
- Add pipeline runner entry if the script should join R/39 sequence (planner decides)

### Claude's Discretion
- Exact next R script number (planner picks from available slots)
- USDA download URL and file structure parsing details
- 4-tier condensed grouping mapping specifics (standard USDA definitions apply)
- xlsx styling (openxlsx pattern used elsewhere)
- Whether to add a small metadata sheet (data source version, run date, cohort size)
- Whether to include the rurality assignment as a small companion csv/rds so downstream scripts can reuse

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- **DEMOGRAPHIC.ZIP_CODE** (R/01_load_pcornet.R:204): Already loaded as character, preserving leading zeros
- **AMC_PAYER_LOOKUP** (R/00_config.R): 8-category payer mapping for sheet 2 stratification
- **classify_codes()** cascade (R/utils/utils_cancer.R): For cancer category assignment in sheet 4
- **Treatment category taxonomy** (5 categories, per v2.3 Phase 94): chemo / radiation / SCT / immunotherapy / proton for sheet 3
- **openxlsx styling patterns** (R/79_drug_name_consistency_audit.R, R/36 TABLE-2): Two-sheet styled xlsx template
- **MEDICATION_LOOKUP bundling pattern** (Phase 114): Precedent for shipping reference data files in the repo

### Established Patterns
- **Investigation-script pattern** (R/40_cancer_site_frequency.R, R/79): Standalone, self-contained scripts that produce one styled xlsx
- **DuckDB-first data access** (get_pcornet_table dispatcher): Use for encounter joins
- **Ascending alphabetical sort** (SORT-01, Phase 112): Applied to all multi-value fields
- **Raw counts, no auto-suppression** (v3.1 decision): For internal investigation outputs
- **R/88 smoke test section per new script** (v2.0+ standard): Structural validation

### Integration Points
- **DEMOGRAPHIC** table -> PATID + ZIP_CODE for rurality assignment
- **ENCOUNTER + payer resolution** -> encounter-level payer for sheet 2
- **Treatment episodes / gantt data** -> encounter-level treatment type for sheet 3
- **Encounter-level cancer categories** (Phase 61 output) -> for sheet 4
- **R/88 smoke test** -> new validation section
- **R/39 pipeline runner** -> potential new entry (planner decides)

</code_context>

<specifics>
## Specific Ideas

- User referenced "R package like rural" -- planner should still check whether a suitable CRAN package (`rural`, `ruca`, or similar) is worth using in place of the bundled USDA xlsx, but the decision made was to bundle the file for offline reproducibility
- User asked for "address info like ruca" -- broader theme is rurality/geography enrichment. RUCA is the concrete deliverable; other geography enrichments (SVI, SDOH, ADI) are deferred (see below)
- Encounter-level cross-tabs weight the analysis toward high-utilizer patients -- flag this in sheet titles so analysts read numbers correctly

</specifics>

<deferred>
## Deferred Ideas

- **Census-tract-level RUCA** with geocoding -- requires patient street addresses (not available; only ZIP)
- **Social Vulnerability Index (SVI)** enrichment at ZIP or census tract level -- would be a natural companion phase
- **Area Deprivation Index (ADI)** enrichment -- similar
- **Longitudinal address / migration** -- DEMOGRAPHIC ZIP is a snapshot; PCORnet does not expose an address history table in this extract
- **Gantt / cohort snapshot enrichment column** for rurality -- if analysts start slicing repeatedly, add rurality as a column downstream; deferred for now since deliverable is the standalone xlsx
- **AV+TH-subset variant** -- kept simple for this phase; can be added if the base analysis warrants it
- **Auto-HIPAA suppression** -- v3.1 pattern is manual pre-share suppression; automated version deferred as a shared utility

</deferred>

---

*Phase: 116-address-info-like-ruca-using-r-pacakge-like-rural*
*Context gathered: 2026-07-06*
