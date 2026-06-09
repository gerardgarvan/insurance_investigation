# Phase 94: Make Proton Therapy a Distinct Category from Radiation - Context

**Gathered:** 2026-06-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Separate proton beam therapy (CPT 77520, 77522, 77523, 77525) from the general "Radiation" treatment category into its own distinct "Proton Therapy" category throughout the entire pipeline. This includes config definitions, cohort flags, episode detection, duration analysis, treatment inventory, Gantt output, summary tables, xlsx exports, and smoke tests.

</domain>

<decisions>
## Implementation Decisions

### Category Naming
- **D-01:** New category name is "Proton Therapy" (not "Proton" or "Proton Beam")
- **D-02:** This string appears in DRUG_GROUPINGS values, TREATMENT_TYPES vector, TREATMENT_TYPE_COLORS, GANTT_TREATMENT_TYPES, xlsx sheet names, Gantt labels, and all summary outputs

### Detection Code Scope
- **D-03:** Full split — proton codes removed from TREATMENT_CODES$radiation_cpt and placed in new TREATMENT_CODES$proton_cpt list
- **D-04:** New has_proton() predicate function added in R/10 (parallel to existing has_radiation())
- **D-05:** R/26 episode detection handles "Proton Therapy" as a separate treatment type with its own code list lookup
- **D-06:** 4 codes affected: 77520 (Simple), 77522 (Simple w/ Compensation), 77523 (Intermediate), 77525 (Complex)
- **D-07:** DRUG_GROUPINGS entries for these 4 codes change from "Radiation" to "Proton Therapy"

### Downstream Output Handling
- **D-08:** Full treatment — Proton Therapy gets its own xlsx sheet in treatment reports (R/20, R/24), own Gantt color in TREATMENT_TYPE_COLORS, own smoke test section, own row in summary tables
- **D-09:** TREATMENT_TYPES becomes 5 elements: c("Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Proton Therapy")
- **D-10:** All for(type in TREATMENT_TYPES) loops automatically pick up the new category — no per-loop changes needed unless there's type-specific branching

### Aggregation Behavior
- **D-11:** Standalone only — "Proton Therapy" appears as its own row, "Radiation" appears as its own row (now 11 codes instead of 15). No combined "Radiation (All)" row.
- **D-12:** Prior outputs that lumped proton into radiation will naturally show different counts. This is expected and intentional.

### Claude's Discretion
- Exact Gantt color choice for Proton Therapy (should be visually distinct from Radiation's green)
- Order of "Proton Therapy" within TREATMENT_TYPES (end or after Radiation)
- Whether CODE_SUBCATEGORY_MAP needs a "Proton Therapy" entry
- Handling of proton-specific ICD-10-PCS codes if any exist in TREATMENT_CODES (e.g., D70 beam radiation includes proton modality qualifiers)
- Whether R/25 get_gap_threshold() needs a proton-specific gap threshold or inherits from radiation

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment category definitions
- `R/00_config.R` lines 1370-1860 — DRUG_GROUPINGS named vector (4 proton codes currently mapped to "Radiation")
- `R/00_config.R` lines 3348-3374 — TREATMENT_TYPES, TREATMENT_TYPE_COLORS, GANTT_TREATMENT_TYPES definitions
- `R/00_config.R` lines 2510-2605 — TREATMENT_CODES$radiation_cpt (contains 4 proton codes to extract)

### Cohort flag detection
- `R/10_build_cohort.R` — has_radiation() predicate function (needs parallel has_proton())

### Episode detection and duration
- `R/26_treatment_episodes.R` lines 391-400 — type-specific code list dispatch (has `if (type == "Radiation")` branch)
- `R/25_treatment_durations.R` lines 93-100 — type-specific gap threshold dispatch (has `if (type == "Radiation")` branch)

### Treatment inventory and reporting
- `R/20_treatment_inventory.R` — treatment type sheet generation, radiation-specific logic at line 485
- `R/24_treatment_codes_resolved.R` — per-category xlsx sheet generation

### Code descriptions
- `R/00_config.R` lines 2143-2146 — CODE_DESCRIPTIONS already has "Proton Beam" labels for 77520/77522/77523/77525
- `R/42_build_code_descriptions.R` — duplicate proton descriptions (check for consistency)
- `R/45_cancer_summary.R` — duplicate proton descriptions
- `R/50_all_codes_resolved.R` — duplicate proton descriptions
- `R/58_code_reference_tables.R` — duplicate proton descriptions

### Gantt output
- `R/52_gantt_v2_export.R` — Gantt v2 CSV export with treatment_category column

### Smoke test
- `R/88_smoke_test_comprehensive.R` — existing validation sections for treatment categories

### Drug grouping tables
- `R/56_drug_grouping_tables.R` — sub-category summary tables using DRUG_GROUPINGS
- `R/57_drug_grouping_instance_tables.R` — instance-level tables per treatment type

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- TREATMENT_TYPES vector drives all for-loops — adding "Proton Therapy" automatically propagates to most scripts
- TREATMENT_TYPE_COLORS list provides xlsx styling — needs one new entry
- CODE_DESCRIPTIONS map already has human-readable proton beam labels
- has_radiation() pattern in R/10 provides template for has_proton()

### Established Patterns
- Treatment type branching in R/25 and R/26 uses if/else chains on type name — needs new "Proton Therapy" branch
- Radiation-specific code lists in TREATMENT_CODES use named sub-lists — proton_cpt follows same pattern
- DRUG_GROUPINGS is the single source of truth for code → category mapping
- xlsx sheet generation iterates TREATMENT_TYPES — auto-creates proton sheet

### Integration Points
- R/00_config.R: DRUG_GROUPINGS, TREATMENT_TYPES, TREATMENT_TYPE_COLORS, TREATMENT_CODES, GANTT_TREATMENT_TYPES
- R/10: Cohort flag predicates
- R/20, R/24, R/25, R/26: Treatment analysis scripts with type-specific branching
- R/42, R/45, R/50, R/58: Code description maps with hardcoded proton entries
- R/52: Gantt v2 export
- R/56, R/57: Drug grouping tables
- R/88: Smoke test validation

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches following existing treatment type patterns.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 94-make-proton-therapy-a-distinct-category-from-radiation*
*Context gathered: 2026-06-09*
