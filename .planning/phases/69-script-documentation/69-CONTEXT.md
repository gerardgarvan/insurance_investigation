# Phase 69: Script Documentation - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 69 adds header blocks, section headers, and inline WHY comments to all 67 numbered production scripts plus header standardization for 8 utility scripts. This is a documentation-only phase -- no functional code changes. The goal is maintainability and onboarding: a new team member should be able to understand any script's purpose, navigate its structure via RStudio outline, and understand clinical/business rationale for non-obvious logic.

</domain>

<decisions>
## Implementation Decisions

### Header Block Template
- **D-01:** Every script gets a standard 5-field header: Purpose, Inputs (files/RDS loaded), Outputs (files/RDS created), Dependencies (source() calls), Requirements (REQ-IDs if applicable)
- **D-02:** Header is visually delimited with box-style equals signs (`# ==============`) top/bottom borders with `#` field labels inside -- matches the existing convention used by ~90% of scripts
- **D-03:** Scripts that already have headers get standardized to the 5-field format (add missing fields, don't remove existing content that adds value)

### Section Header Format
- **D-04:** Standard format is `# SECTION N: TITLE ----` with numbered sections and 4+ trailing dashes (works with RStudio Ctrl+Shift+O outline navigation)
- **D-05:** Section ordering is flexible per script -- only require a Setup section at the top and an Output section (if applicable) near the bottom. Middle sections are domain-appropriate for each script's purpose
- **D-06:** Convert existing variant formats (`# ====`, `# --- TITLE ---`, `# === TITLE ===`) to the standard `# SECTION N: TITLE ----` format

### WHY Comment Depth
- **D-07:** Comment WHY for clinical rules (90-day gap, 7-day confirmation, 60-day clean period), payer hierarchy decisions (Medicaid > Medicare > Private), magic numbers, complex joins with temporal logic, and business mappings (AMC 8-category, dual-eligible detection)
- **D-08:** Skip obvious dplyr/tidyverse operations -- don't comment `filter()`, `mutate()`, `left_join()` when their purpose is self-evident from variable names
- **D-09:** Preserve existing decision traceability references (D-01, D-02, REQ-xx) where they exist. Don't add new ones, but don't remove existing ones either

### Batching Strategy
- **D-10:** Batch documentation work by decade: one plan per decade grouping (00-03, 10-14, 20-29, 40-53, 60-69, 70-75, 80-87, 90-99). Natural grouping that's parallelizable across waves
- **D-11:** R/utils/ scripts (8 files) get header standardization only -- they already have good roxygen2 function documentation. Include them as a small plan or fold into a wave with a small decade

### Claude's Discretion
- Exact wording of header fields and section titles per script
- How many sections each script warrants (simple scripts may only need 2-3, complex scripts may need 6-8)
- Which specific lines of code warrant WHY comments (use the clinical/business rule heuristic from D-07)
- Wave grouping and parallelization of decade-based plans

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Script Inventory
- `R/SCRIPT_INDEX.md` -- Canonical listing of all 67 numbered scripts + 8 utils + 8 archived, organized by decade with purpose summaries and source() dependency chains

### Requirements
- `.planning/REQUIREMENTS.md` -- DOC-01 (header blocks), DOC-02 (section headers with 4+ dashes), DOC-03 (inline WHY comments) requirement definitions

### Documentation Best Practices (existing examples)
- `R/25_treatment_durations.R` -- Best example of WHY comments with decision traceability (D-01 through D-13)
- `R/10_cohort_predicates.R` -- Good example of clinical logic documentation with "Translation gap workaround" notes
- `R/utils/utils_attrition.R` -- Gold standard for roxygen2 function documentation in utils
- `R/72_generate_pptx.R` -- Most extensive header block (52 slides documented)

### Prior Phase Context
- `.planning/phases/68-output-test-reorganization/68-VERIFICATION-SCAN.md` -- Structural verification confirming 67 scripts across 8 decades

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- ~90% of scripts already have header blocks of varying quality -- standardization rather than creation
- R/utils/ files demonstrate the roxygen2 pattern that DOC-01 success criterion references for complex utility functions
- R/SCRIPT_INDEX.md provides the complete inventory for documentation coverage tracking

### Established Patterns
- Box-style equals (`# ==============`) for file headers -- used across majority of scripts
- Some scripts use `# --- SECTION ---` format (not RStudio-compatible) -- need conversion to `# SECTION N: TITLE ----`
- Decision traceability comments (D-xx references) appear in treatment and payer scripts -- preserve these
- 1148 occurrences of `# ===` across 83 files; 315 occurrences of `# ----` across 23 files

### Integration Points
- RStudio Ctrl+Shift+O outline navigation -- section headers must end with 4+ dashes/equals to appear in outline
- SCRIPT_INDEX.md -- could serve as cross-reference for header Purpose fields

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- standard documentation patterns with decisions captured above.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 69-script-documentation*
*Context gathered: 2026-06-02*
