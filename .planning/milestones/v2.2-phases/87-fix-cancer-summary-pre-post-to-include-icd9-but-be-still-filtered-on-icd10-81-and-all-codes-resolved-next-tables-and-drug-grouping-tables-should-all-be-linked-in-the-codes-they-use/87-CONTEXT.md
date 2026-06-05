# Phase 87: Unify ICD-9/ICD-10 Cancer Code Usage - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Unify cancer diagnosis code handling across the cancer summary pipeline (R/45, R/47, R/48, R/49) and the drug grouping tables (R/56) so all scripts use both ICD-9 and ICD-10 cancer codes via shared centralized maps. Create a full ICD-9 neoplasm category mapping (`ICD9_CANCER_SITE_MAP`), extract `is_cancer_code()` to a shared utility, include ICD-9 201.x in HL cohort confirmation, and ensure R/50 uses the same shared code detection if it references cancer codes.

**Downstream impact:** Adding ICD-9 201.x to HL cohort confirmation may change which patients are in `confirmed_hl_cohort.rds`, which ripples through every downstream script that reads that artifact. Plans MUST identify and account for all downstream effects.

</domain>

<decisions>
## Implementation Decisions

### Cancer Summary ICD-9 Scope
- **D-01:** R/45 through R/49 (cancer summary pipeline) must include ICD-9 neoplasm codes alongside ICD-10. Remove all `DX_TYPE == "10"` hard-filters in these scripts. Use the shared `is_cancer_code()` utility instead.
- **D-02:** D-codes (benign, in-situ, uncertain behavior) remain EXCLUDED from the cancer summary pipeline. R/47's D-code filtering stays in place. This applies to both ICD-10 D-codes and their ICD-9 equivalents (210-239 benign/uncertain range).
- **D-03:** Build a full ICD-9 neoplasm category mapping covering ALL of 140-239 (not just HL-relevant codes). Every ICD-9 neoplasm prefix gets mapped to the same cancer categories used by CANCER_SITE_MAP.

### ICD-9 Cancer Site Map
- **D-04:** Create `ICD9_CANCER_SITE_MAP` as a new named vector in R/00_config.R, separate from `CANCER_SITE_MAP`. Keeps ICD-9 and ICD-10 maps distinct for clarity. Same pattern: 3-digit prefix keys mapping to cancer category strings.
- **D-05:** `classify_codes()` in `R/utils/utils_cancer.R` must check both `CANCER_SITE_MAP` (ICD-10) and `ICD9_CANCER_SITE_MAP` (ICD-9). Detection order: ICD-10 4-char → ICD-10 3-char → ICD-9 exact match (existing 201.x logic) → ICD-9 3-char prefix → unclassified.

### Code List Unification
- **D-06:** Extract `is_cancer_code()` from R/56 to `R/utils/utils_cancer.R` as a shared utility. All scripts (R/45, R/47, R/48, R/49, R/56, and R/50 if applicable) source and use the same function.
- **D-07:** R/56's local `is_cancer_code()` function is replaced by the shared version. No duplicate logic across scripts.

### all_codes_resolved Linkage
- **D-08:** R/50 (`all_codes_resolved.R`) does not need new cancer code columns. The "linkage" means ensuring that if R/50 ever references cancer codes, it uses the same shared `is_cancer_code()` utility. No structural changes to R/50 output.

### HL Cohort Anchor
- **D-09:** ICD-9 code 201.x (Hodgkin's disease) counts toward HL cohort confirmation alongside ICD-10 C81. A patient with 2+ ICD-9 201.x codes with 7+ day gap is confirmed HL. This changes R/47's cohort confirmation query.
- **D-10:** Cross-system confirmation is allowed at the CATEGORY level: 1x ICD-9 201.x + 1x ICD-10 C81 with 7-day gap confirms HL for category-level summaries.
- **D-11:** Cross-system codes do NOT combine at the individual CODE level. Code-level summary sheets keep 201.x and C81.x counts separate. Only category-level aggregation merges across coding systems.
- **D-12:** Downstream effects of cohort change MUST be identified and handled. The confirmed_hl_cohort.rds artifact may gain new patients. Every script that reads this artifact needs verification. Plans must explicitly list affected scripts and expected impact.

### Claude's Discretion
- Whether `is_cancer_code()` should use map-based detection (checking names of both CANCER_SITE_MAP and ICD9_CANCER_SITE_MAP) vs range-based detection (140-239 for ICD-9). Decision should avoid gaps between detection and classification.
- ICD-9 D-code equivalent identification: which ICD-9 ranges (210-239) correspond to ICD-10 D-codes for exclusion in the cancer summary pipeline.
- Exact ICD-9 prefix-to-category mappings for the full 140-239 range — research authoritative ICD-9 references for accurate category assignment.
- How to handle the ICD-9 201.x subcategory mapping (201.0, 201.1, 201.2, 201.5, 201.6, 201.7, 201.9) to classical HL subtypes in the 4-char matching tier.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Cancer Summary Pipeline (scripts being modified)
- `R/45_cancer_summary.R` — Upstream cancer summary; has `DX_TYPE == "10"` filter at line 69 that must be removed
- `R/47_cancer_summary_refined.R` — Cohort confirmation (C81 → C81+201.x) and D-code removal; lines 96, 110-115
- `R/48_cancer_summary_post_hl.R` — Temporal filtering; has `DX_TYPE == "10"` filter at line 118
- `R/49_cancer_summary_pre_post.R` — Pre/post HL counts; has `DX_TYPE == "10"` filters at lines 106, 203, 346

### Drug Grouping Tables
- `R/56_new_tables_from_groupings.R` — Has local `is_cancer_code()` at lines 156-174 that moves to shared utility

### Treatment Code Tables
- `R/50_all_codes_resolved.R` — Verify no cancer code references need updating

### Configuration & Utilities
- `R/00_config.R` — CANCER_SITE_MAP (lines 537-800), ICD9_NLPHL_CODES (lines 382-386); new ICD9_CANCER_SITE_MAP goes here
- `R/utils/utils_cancer.R` — classify_codes() (lines 57-82); receives is_cancer_code() and updated classification logic

### Downstream Artifacts (verify impact)
- `cache/outputs/confirmed_hl_cohort.rds` — May gain patients from ICD-9 201.x inclusion
- `cache/outputs/cancer_summary.csv` — Will include ICD-9 cancer codes
- `cache/outputs/treatment_episodes.rds` — Downstream of cohort; verify impact

### Quality
- `R/88_smoke_test_comprehensive.R` — Must be updated for ICD-9 code presence in outputs

### Prior Phase Context
- `.planning/phases/77-cancer-classification-refinements/77-CONTEXT.md` — NLPHL breakout decisions
- `.planning/phases/79-code-investigations-new-tables/79-CONTEXT.md` — R/56 creation decisions
- `.planning/phases/81-filter-unknown-from-cancer-codes-in-treatment-summary-add-category-column-to-sub-category-summary-map-unmapped-sub-categories/81-CONTEXT.md` — Table 1 structure, NA filtering
- `.planning/phases/82-non-informative-subcategories-explore-this-and-see-if-unhelpful-codes-are-in-the-same-encounter-as-a-helpful-code-and-from-there-just-count-the-helpful-code/82-CONTEXT.md` — Encounter-level deduplication

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CANCER_SITE_MAP` (R/00_config.R:537-800): 324-entry ICD-10 named vector — pattern for new ICD9_CANCER_SITE_MAP
- `ICD9_NLPHL_CODES` (R/00_config.R:382-386): 10 ICD-9 NLPHL codes — already exists, will be subsumed by ICD9_CANCER_SITE_MAP
- `classify_codes()` (R/utils/utils_cancer.R:57-82): Already handles ICD-9 201.x via exact match — needs extension for full ICD-9 range
- `is_cancer_code()` (R/56:156-174): Local function detecting ICD-9 (140-239) + ICD-10 (C/D) — candidate for extraction to shared utility

### Established Patterns
- Centralized config maps in R/00_config.R as named vectors (CANCER_SITE_MAP, DRUG_GROUPINGS, AMC_PAYER_LOOKUP)
- Shared utility functions in R/utils/ sourced by multiple scripts
- 4-char prefix matching before 3-char fallback in classify_codes()
- `DX_TYPE` column values: "09" for ICD-9, "10" for ICD-10

### Integration Points
- R/45 line 69: `DX_TYPE == "10"` filter → remove and replace with `is_cancer_code()` detection
- R/47 lines 110-115: C81 cohort confirmation query → expand to include 201.x
- R/47 line 96: D-code removal → extend to exclude ICD-9 benign/uncertain equivalents (210-239)
- R/48 line 118: `DX_TYPE == "10"` filter → remove and replace with `is_cancer_code()` detection
- R/49 lines 106, 203, 346: `DX_TYPE == "10"` filters → remove and replace
- R/56 lines 156-174: Local is_cancer_code() → replace with sourced shared utility

</code_context>

<specifics>
## Specific Ideas

- User emphasized: "prepare for downstream effects" — plans must trace the impact of ICD-9 201.x inclusion in HL cohort confirmation through all downstream artifacts and scripts.
- Cross-system confirmation rule: category summaries allow ICD-9 + ICD-10 to combine; code-level summaries keep them separate. This distinction must be clearly implemented in R/47 and propagated to R/49.
- The ICD-9 201.x → C81 equivalence table (201.4x=NLPHL, 201.5x=Nodular sclerosis, etc.) should inform the ICD9_CANCER_SITE_MAP subcategory entries for HL.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 87-fix-cancer-summary-pre-post-to-include-icd9-but-be-still-filtered-on-icd10-81-and-all-codes-resolved-next-tables-and-drug-grouping-tables-should-all-be-linked-in-the-codes-they-use*
*Context gathered: 2026-06-03*
