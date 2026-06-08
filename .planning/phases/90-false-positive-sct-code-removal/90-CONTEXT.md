# Phase 90: False-Positive SCT Code Removal - Context

**Gathered:** 2026-06-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Remove 5 false-positive SCT codes (status/complication codes that don't represent actual transplant procedures) from the DRUG_GROUPINGS treatment detection map in R/00_config.R. These codes should no longer trigger SCT treatment episodes. Cohort predicate logic and code descriptions are not affected.

</domain>

<decisions>
## Implementation Decisions

### Removal Scope
- **D-01:** Remove 5 codes (Z94.84, T86.5, T86.09, Z48.290, HEMATOLOGIC_TRANSPLANT_AND_ENDOC) from DRUG_GROUPINGS in R/00_config.R only.
- **D-02:** Cohort predicates in R/10_cohort_predicates.R and R/11_treatment_payer.R are NOT touched. These codes still serve as SCT history indicators for cohort inclusion — they just no longer generate treatment episodes.
- **D-03:** Code descriptions in R/42_build_code_descriptions.R and R/58_code_reference_tables.R are kept. Still useful for display/reference of diagnosis codes.

### Impact Documentation
- **D-04:** Inline comments only. Each removed code line gets a comment explaining why it's a false positive (status/complication, not a procedure). No separate impact markdown document. No runtime console messages.

### Smoke Test Validation
- **D-05:** New dedicated smoke test section (after Section 15) that asserts the 5 deprecated codes are NOT present in DRUG_GROUPINGS. Isolated and easy to find.
- **D-06:** Validation checks that no treatment episodes are triggered solely by these status/complication codes.

### Claude's Discretion
- Exact section numbering for the new smoke test section (15c, 16, etc. — follow existing numbering conventions)
- Comment format/wording for the inline removal rationale

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Treatment Detection Config
- `R/00_config.R` lines 1587-1601 — SCT section of DRUG_GROUPINGS where the 5 codes live (currently "41 codes" comment)

### Cohort Predicates (DO NOT MODIFY)
- `R/10_cohort_predicates.R` lines 493-581 — has_sct() predicate using these codes for cohort inclusion (unchanged)
- `R/11_treatment_payer.R` lines 420-445 — SCT date detection using diagnosis codes (unchanged)

### Code Descriptions (DO NOT MODIFY)
- `R/42_build_code_descriptions.R` lines 233-236 — Human-readable descriptions for removed codes (kept)
- `R/58_code_reference_tables.R` lines 193-196 — Same descriptions in reference table context (kept)

### Smoke Test
- `R/88_smoke_test_comprehensive.R` line 1156+ — Section 15 (episode enrichment). New section goes after this.

### Requirements
- `.planning/REQUIREMENTS.md` — CLEAN-01 (remove codes), CLEAN-02 (smoke test validation)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DRUG_GROUPINGS` named vector in R/00_config.R: Direct target for removal. Currently maps ~454 codes to 5 categories.
- `check()` function in R/88: Existing smoke test assertion helper. Reuse for new section.
- Section header pattern: `# SECTION N: NAME ----` with `message()` progress output.

### Established Patterns
- DRUG_GROUPINGS uses simple `"code" = "Category"` named vector entries
- Smoke test checks use `readLines()` + `grepl()` for structural validation
- Smoke test checks use `check(description, condition)` pattern
- Inline comments use `#` with rationale (see existing `# Replaces 77421` style comments on radiation codes)

### Integration Points
- R/28_episode_classification.R reads DRUG_GROUPINGS to classify treatment episodes — removing codes here prevents false-positive episodes downstream
- treatment_episodes.rds is the output that will no longer contain episodes triggered solely by these 5 codes
- SCT code count comment ("41 codes") needs updating to "36 codes" after removal

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches following existing patterns.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 90-false-positive-sct-code-removal*
*Context gathered: 2026-06-07*
