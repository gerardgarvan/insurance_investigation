# Phase 95: Infrastructure Setup - Context

**Gathered:** 2026-06-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Add data.table as a project dependency, create conversion helper utilities, and build keyed data.table versions of all 6 lookup tables in R/00_config.R — without changing any existing script behavior. This is pure infrastructure that downstream phases (96-98) will consume.

</domain>

<decisions>
## Implementation Decisions

### Namespace Management
- **D-01:** Load `library(data.table)` globally in R/00_config.R so it's available to all scripts.
- **D-02:** Use explicit `package::function()` form (e.g., `data.table::between()`, `dplyr::between()`) for any functions that conflict between data.table and dplyr. Do NOT rely on load order to resolve conflicts.

### Column Naming
- **D-03:** Use semantic, table-specific column names for keyed data.tables. Examples:
  - AMC_PAYER_LOOKUP: `code` / `payer_category`
  - DRUG_GROUPINGS: `code` / `drug_group`
  - CODE_SUBCATEGORY_MAP: `code` / `subcategory`
  - CANCER_SITE_MAP: `prefix` / `cancer_site`
  - TIER_MAPPING: `payer_category` / `tier`
  - TREATMENT_CODES: `code` / `code_system` / `treatment_type`
  (Exact names at Claude's discretion — must be self-documenting in join syntax.)

### TREATMENT_CODES Conversion
- **D-04:** Flatten TREATMENT_CODES from nested list structure to a long-format 3-column keyed data.table: `code`, `code_system`, `treatment_type`. Key on `code`. This enables direct keyed joins matching the pattern used by the other 5 lookup tables.

### Error Handling
- **D-05:** Conversion helpers (`ensure_dt()`, `to_tibble_safe()`, `get_lookup_dt()`) follow defensive-with-warnings pattern:
  - NULL input: throw error (immediate stop)
  - Empty input: return empty data.table/tibble with warning
  - Already-correct type: return as-is silently (no-op)
  - Follows existing checkmate assertion style in R/utils/utils_assertions.R

### Claude's Discretion
- Exact semantic column names per table (D-03 provides examples, Claude finalizes)
- Where in R/00_config.R to place LOOKUP_TABLES_DT construction (after all named vectors, or in a dedicated section)
- Whether `get_lookup_dt()` accepts string names or uses direct variable references
- Internal implementation details of ensure_dt() type detection

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Configuration
- `.planning/REQUIREMENTS.md` -- INFRA-01 through INFRA-04 define exact deliverables for this phase
- `.planning/ROADMAP.md` -- Phase 95 success criteria (4 testable assertions)

### Codebase
- `R/00_config.R` -- All 6 lookup tables defined here; LOOKUP_TABLES_DT must be added here per INFRA-03
- `R/utils/utils_assertions.R` -- Existing checkmate assertion pattern that D-05 follows
- `R/utils/` -- 11 existing utility modules; utils_dt.R will be auto-sourced via list.files() at R/00_config.R:3428

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/utils/utils_assertions.R`: Existing checkmate-based assertion pattern — error handling in utils_dt.R should follow same style
- Auto-source mechanism at `R/00_config.R:3428`: `list.files("R/utils", "\\.R$")` means utils_dt.R will be loaded automatically

### Established Patterns
- Named vectors as lookup tables: `"code" = "category"` pattern used by AMC_PAYER_LOOKUP (234 entries), DRUG_GROUPINGS (454 entries), CODE_SUBCATEGORY_MAP, CANCER_SITE_MAP
- TIER_MAPPING is a list (not named vector): `list(Medicaid = 1L, Medicare = 2L, ...)`
- TREATMENT_CODES is a nested list: `list(chemotherapy = list(cpt = c(...), rxnorm = c(...)), ...)`
- All scripts begin with `source("R/00_config.R")` — any additions to config are globally available

### Integration Points
- LOOKUP_TABLES_DT in R/00_config.R will be consumed by Phase 96 (classify_payer_tier_dt), Phase 97 (R/60), Phase 98 (R/28)
- utils_dt.R conversion helpers used by Phases 96-98 for tibble/data.table boundary management

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches for data.table infrastructure.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 95-infrastructure-setup*
*Context gathered: 2026-06-10*
