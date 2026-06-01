# Phase 65: Foundation Reorganization - Context

**Gathered:** 2026-06-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Move all utils_*.R modules into R/utils/ subfolder, renumber the DuckDB ingest script from 25 to 03, update all source() references, and validate with a smoke test. Foundation scripts 00_config.R, 01_load_pcornet.R, and 02_harmonize_payer.R keep their current numbers.

</domain>

<decisions>
## Implementation Decisions

### Utils Scope
- **D-01:** All 8 utils_*.R files move to R/utils/ — including utils_pptx.R which is currently sourced directly by 11_generate_pptx.R and 22b_generate_phase19_20_pptx.R (not auto-sourced by config). Update those two callers to the new path.

### Utils Naming
- **D-02:** Files keep the `utils_` prefix inside R/utils/ (e.g., R/utils/utils_dates.R). This minimizes source() call changes (just prepend `utils/` to existing paths) and maintains grep-ability across the codebase.

### Foundation Script Numbering
- **D-03:** Numbering order: 00=config (unchanged), 01=load_pcornet (unchanged), 02=harmonize_payer (unchanged), 03=duckdb_ingest (renumbered from 25). Only 25_duckdb_ingest.R actually moves — the legacy CSV workflow ordering is preserved, with DuckDB ingest added as 03 since it's optional (USE_DUCKDB flag).

### Auto-Sourcing Mechanism
- **D-04:** Replace the 7 explicit source() lines in 00_config.R (lines 1501-1507) with dynamic sourcing: `list.files("R/utils", pattern = "\\.R$", full.names = TRUE)` piped to `lapply(source)`. New utils files added in future phases are auto-discovered without editing config.

### Claude's Discretion
- Utils naming convention (D-02): User deferred to Claude. Decision: keep `utils_` prefix for minimal disruption.
- Smoke test implementation approach: Claude will design the validation script during planning.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Configuration & Utils
- `R/00_config.R` -- lines 1495-1511: current auto-source block that will be replaced with dynamic sourcing
- `R/utils_attrition.R`, `R/utils_dates.R`, `R/utils_icd.R`, `R/utils_snapshot.R`, `R/utils_duckdb.R`, `R/utils_treatment.R`, `R/utils_payer.R`, `R/utils_pptx.R` -- the 8 utils files to move

### Foundation Scripts
- `R/01_load_pcornet.R` -- data loading (stays at 01)
- `R/02_harmonize_payer.R` -- payer harmonization (stays at 02)
- `R/25_duckdb_ingest.R` -- DuckDB ingest (renumbers to 03)

### Requirements
- `.planning/REQUIREMENTS.md` -- REORG-01 (sequential renumbering), REORG-03 (utils subfolder), REORG-04 (deprecated scripts archival)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/26_smoke_test_backends.R` -- existing smoke test pattern that sources 00, 01, 02 in sequence; can be adapted for foundation smoke test

### Established Patterns
- Source chain: scripts source their upstream dependency (e.g., `02_harmonize_payer.R` sources `01_load_pcornet.R` which sources `00_config.R`)
- Conditional sourcing: many scripts use `if (!exists("pcornet")) source("R/01_load_pcornet.R")` pattern
- Config auto-sources utils at end of file (lines 1501-1507)
- utils_pptx.R has a different pattern: sourced directly by PPTX-generating scripts, not by config

### Integration Points
- ~95 source() calls across all R scripts reference foundation files (00, 01, 02)
- Only 25_duckdb_ingest.R needs renumbering (to 03) — no other scripts source it directly (it sources 00_config.R)
- utils_pptx.R is sourced by 2 scripts (11_generate_pptx.R, 22b_generate_phase19_20_pptx.R)
- 7 utils files sourced by 00_config.R will change to dynamic path
- 1 script (19_flm_duplicate_dates.R:97) has a redundant direct `source("R/utils_dates.R")` that will need path update

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 65-foundation-reorganization*
*Context gathered: 2026-06-01*
