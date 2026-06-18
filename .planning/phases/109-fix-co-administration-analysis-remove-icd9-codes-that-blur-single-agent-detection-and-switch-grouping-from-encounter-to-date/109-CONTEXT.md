# Phase 109: Fix co-administration analysis: remove ICD9 codes that blur single-agent detection and switch grouping from encounter to date - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Two targeted fixes to R/58_co_administration_analysis.R:
1. Remove non-specific ICD9 procedure codes from the triggering_code pool — they indicate "chemo happened" but don't identify which agent, blurring single-agent detection
2. Switch the analysis grain from encounter-level to date-level — encounter IDs are billing artifacts; what matters is which specific agents appeared on which dates

NOT in scope: changing the ±30-day window, modifying regimen exclusion logic, adding non-chemo treatment types, or creating new output files.

</domain>

<decisions>
## Implementation Decisions

### ICD9 Code Filtering
- **D-01:** Remove non-specific ICD9 procedure codes from the triggering_code pool before single-agent detection. These codes (e.g., ICD9 99.25 "injection/infusion of cancer chemotherapeutic substance") tell you chemotherapy was administered but NOT which agent. They blur single-agent detection by inflating the distinct-code count without adding agent-level information.
- **D-02:** Encounters where the ONLY triggering code is a non-specific ICD9 code are **excluded from the analysis entirely**. No identifiable agent means no contribution to single-agent or co-admin detection.

### Date vs Encounter Grain
- **D-03:** Single-agent detection operates at date grain: after removing non-specific ICD9 codes, deduplicate to unique (patient_id, treatment_date, specific_triggering_code), then count distinct specific codes per patient-date. Single-agent = exactly 1 unique specific chemo code on that date.
- **D-04:** Temporal self-join operates at date grain, not encounter grain. The self-join exclusion changes from `ENCOUNTERID != i.ENCOUNTERID` (different encounter) to `triggering_code != i.triggering_code` (different agent). Co-administration = a DIFFERENT chemo agent within ±30 days of the single-agent date. Same agent on different dates is repeat dosing, not co-administration.
- **D-05 (carries forward Phase 102 D-01, modified):** "Single-agent" definition updated: one **specific** chemo triggering_code per patient-date, after filtering out non-specific ICD9 codes.

### Output Impact
- **D-06:** Replace existing `co_administration_analysis.xlsx` — same filename, same 2-sheet structure ("Co-Administration Detail" + "Pattern Summary"), but with date-grain data. Old encounter-level output is superseded.
- **D-07:** Drop encounter IDs from the detail table. New detail columns: (patient_id, index_date, index_drug_code, index_drug_name, coadmin_date, coadmin_drug_code, coadmin_drug_name, days_apart). Clean date-level grain with no encounter artifacts.

### Carried Forward from Phase 102 (Unchanged)
- ±30-day window (Phase 102 D-03)
- Chemo-to-chemo only (Phase 102 D-04)
- Exclude regimen-classified encounters (Phase 102 D-05)
- Two-sheet xlsx output (Phase 102 D-06)
- Show both drug name and triggering_code (Phase 102 D-08)
- Self-contained investigation script, no upstream modification (Phase 102 D-10)

### Claude's Discretion
- Exact method for identifying ICD9 non-specific codes (prefix pattern vs explicit list from reference data)
- Whether to add console logging for how many ICD9 codes were filtered and how many encounters lost
- Column ordering in updated detail table
- Whether to update the resolve_drug_name() function or leave as-is

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary Script to Modify
- `R/58_co_administration_analysis.R` — Current encounter-level co-administration analysis. All sections need review; Section 2 (filtering), Section 4 (single-agent detection), Section 5 (temporal self-join), Section 6 (detail table) are the main modification targets.

### Phase 102 Context (Original Decisions)
- `.planning/phases/102-single-agent-co-administration-analysis/102-CONTEXT.md` — Original implementation decisions. D-01/D-03/D-04/D-05 carried forward with D-01 modified. D-07 (detail table format) overridden by new D-07.

### Code & Drug Mappings
- `R/00_config.R` — CONFIG paths, CODE_SUBCATEGORY_MAP, TREATMENT_CODES for code classification
- `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` — Sub-category mappings; Chemotherapy sheet maps codes to medication names. May help identify which codes are ICD9 vs procedure/NDC.

### Episode Data
- `R/28_episode_classification.R` — Regimen detection (regimen_label). Defines which encounters are regimen-classified and should be excluded (Phase 102 D-05, carried forward).

### Validation
- `R/88_smoke_test_comprehensive.R` — Existing validation section for R/58 output needs updating if column structure changes.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/58` Section 3: `resolve_drug_name()` function with multi-tier resolution (xlsx reference -> CODE_SUBCATEGORY_MAP -> drug_name -> code fallback). Can be reused for the date-grain version.
- `R/58` Section 5: data.table cartesian self-join pattern. Needs modification from encounter-exclusion to agent-exclusion but the join structure stays.
- `R/00_config.R` TREATMENT_CODES: May contain code type metadata useful for identifying ICD9 vs CPT/HCPCS codes.

### Established Patterns
- data.table `[i, on=, allow.cartesian=TRUE]` for temporal self-joins (used in R/58, R/28)
- openxlsx2 multi-sheet workbook pattern (R/57, R/58, R/36)
- Console attrition logging with glue (count before/after each filter step)

### Integration Points
- `treatment_episode_detail.rds`: Primary input. Contains `triggering_code` field that mixes specific (J-codes, CPT) and non-specific (ICD9 procedure) codes. Filtering happens IN this script, not upstream.
- `treatment_episodes.rds`: Episode-level with regimen_label. Used for regimen exclusion — unchanged.
- `R/88_smoke_test_comprehensive.R`: Has existing R/58 validation section that checks output column names — must be updated for new column structure.

</code_context>

<specifics>
## Specific Ideas

- The user's core concern: "I just want to make sure that a single chemo agent is on that date" — the analysis should be about identifiable agents on dates, not billing encounters.
- ICD9 codes "just show that it was a chemo encounter, not what the agent was" — filtering them is about signal quality, not data volume.
- Co-administration means a DIFFERENT agent within ±30 days — same agent on another date is repeat dosing.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 109-fix-co-administration-analysis-remove-icd9-codes-that-blur-single-agent-detection-and-switch-grouping-from-encounter-to-date*
*Context gathered: 2026-06-18*
