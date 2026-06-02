# Phase 75: Configuration Extensions (NLPHL & Death Cause) - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Extend the configuration layer (`R/00_config.R`) with NLPHL classification logic and death cause mapping. Update `classify_codes()` in `R/utils/utils_cancer.R` to support 4-char prefix matching for NLPHL breakout. Add unit tests for mutual exclusivity. No downstream script changes — those happen in Phase 77+.

</domain>

<decisions>
## Implementation Decisions

### NLPHL Category Naming
- **D-01:** NLPHL category label = `"NLPHL"` (short clinical abbreviation, concise in tables)
- **D-02:** Classical HL category label = `"Hodgkin Lymphoma (non-NLPHL)"` (explicitly signals exclusion of NLPHL)
- **D-03:** No roll-up constant in config. Downstream scripts combine NLPHL + non-NLPHL when needed. Keep CANCER_SITE_MAP atomic.

### Death Cause Grouping
- **D-04:** All-cause detailed grouping scheme (~30-40 category groups covering cancer subtypes and all major non-cancer causes)
- **D-05:** Explicit `"Unknown or Unspecified"` category for empty/invalid codes — makes missingness visible in output tables rather than silent NA
- **D-06:** 3-char ICD-10 prefixes as map keys — same pattern as CANCER_SITE_MAP (e.g., `"C81" = "Hodgkin Lymphoma"`, `"I25" = "Ischemic Heart Disease"`)
- **D-07:** DEATH_CAUSE_MAP as a separate top-level named vector in R/00_config.R — follows existing convention (CANCER_SITE_MAP, TIER_MAPPING, AMC_PAYER_LOOKUP)

### ICD-9 NLPHL Scope
- **D-08:** ICD9_NLPHL_CODES = 201.40 through 201.48 (9 site-specific codes) plus parent code 201.4 (10 codes total). Mirrors ICD-10 approach of including all C81.0x codes.
- **D-09:** Single `classify_codes()` function with dual logic — 4-char prefix first (C810 -> NLPHL), then 3-char fallback for ICD-10; ICD9_NLPHL_CODES list check for ICD-9. One function handles everything (simpler API for 15 downstream scripts).

### Claude's Discretion
No areas deferred to Claude's discretion — all gray areas resolved by user.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Configuration
- `R/00_config.R` -- CANCER_SITE_MAP (line ~413), ICD_CODES (line ~164), all lookup tables. Primary file being extended.
- `R/utils/utils_cancer.R` -- classify_codes() function (line ~36). Needs 4-char prefix logic added.

### Requirements
- `.planning/REQUIREMENTS.md` -- CANCER-01 (NLPHL breakout), DEATH-01 (death quality profiling), DEATH-02 (death in outputs), QUAL-01 (v2.0 standards)

### Quality Standards
- `R/88_smoke_test_comprehensive.R` -- Existing smoke test patterns from Phase 74. New tests must follow these patterns.

### Downstream Consumers (do not modify in this phase, but understand impact)
- `R/40_cancer_site_frequency.R` through `R/49_cancer_summary_pre_post.R` -- 10 scripts using classify_codes()
- `R/51_gantt_data_export.R` -- Uses classify_codes() for Gantt cancer categories
- `R/28_episode_classification.R` -- Uses classify_codes() for episode-level cancer linkage

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CANCER_SITE_MAP` (R/00_config.R:413): 324-entry named vector mapping 3-char ICD-10 prefixes to cancer site categories. NLPHL entry goes here.
- `classify_codes()` (R/utils/utils_cancer.R:36): Simple 3-char prefix lookup. Needs extension to 4-char-first logic.
- `ICD_CODES` list (R/00_config.R:164): Already contains C81.0x in `hl_icd10` and 201.4x in `hl_icd9`. New `ICD9_NLPHL_CODES` is a subset extraction.

### Established Patterns
- Named vectors for lookup maps (CANCER_SITE_MAP, TIER_MAPPING, AMC_PAYER_LOOKUP) — all top-level in R/00_config.R
- Section headers with `# SECTION N: NAME ----` format
- Documentation headers at top of each file
- testthat-style tests in R/88_smoke_test_comprehensive.R

### Integration Points
- `classify_codes()` is called by 15 downstream scripts via `source("R/00_config.R")` which auto-sources all utils
- DEATH table already loaded in PCORNET_TABLES (added Phase 57) — DEATH_CAUSE_MAP will be consumed by Phase 78

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches for ICD-10 death cause grouping following CDC/WHO conventions.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 75-configuration-extensions-nlphl-death-cause*
*Context gathered: 2026-06-02*
