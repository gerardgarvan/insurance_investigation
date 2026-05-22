# Phase 2: Add Descriptions of Codes to the Gantt CSVs - Context

**Gathered:** 2026-05-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Enrich the Gantt chart CSV exports (`gantt_episodes.csv` and `gantt_detail.csv`) with human-readable code descriptions so the third-party consumer can understand what each triggering code means without external lookups. This is a data enrichment phase — modifies R/49_gantt_data_export.R and adds a helper script to build a static code description lookup.

</domain>

<decisions>
## Implementation Decisions

### Description Source
- **D-01:** Static lookup table built from existing data sources — no NLM API calls at runtime. Sources: (1) Phase 39-41 RDS artifacts (`unmatched_codes_classified.rds` + `unmatched_ndc_classified.rds`) with NLM API lookup results, (2) R/00_config.R inline comments for curated codes, (3) R/45 `hardcoded_descriptions` for retired radiation CPT codes.
- **D-02:** Lookup stored as a standalone `code_descriptions.rds` file (named character vector: code -> description). Built once via a helper script, loaded by R/49 at runtime. Reusable by other scripts if needed.

### Column Format
- **D-03:** Detail table (`gantt_detail.csv`): add a `triggering_code_description` column alongside `triggering_code`. One description per row.
- **D-04:** Episodes table (`gantt_episodes.csv`): add a `triggering_code_descriptions` column (note: plural) with descriptions in the same comma-separated order as the `triggering_codes` column. E.g., codes=`J9000,J9040` -> descriptions=`Doxorubicin HCl,Bleomycin sulfate`.

### Missing Descriptions
- **D-05:** When a code has no description in the lookup, use an empty string. The code is still present in the `triggering_code`/`triggering_codes` column for reference.

### Output Scope
- **D-06:** Add description columns to both Gantt CSVs only. Do not modify R/44's per-type xlsx workbooks — those are a separate output with their own format.

### Claude's Discretion
- Helper script naming and numbering (following R/NN_*.R pattern)
- Whether to extract config inline comments programmatically or transcribe manually into the lookup builder
- Column ordering for the new description columns (likely placed immediately after the code column)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Gantt Export Script (Primary Modification Target)
- `R/49_gantt_data_export.R` — Current export script to modify; defines column structure for both CSVs

### Description Source Data
- `R/39_investigate_unmatched.R` — Contains `lookup_hcpcs_batch()` function and produces `unmatched_codes_classified.rds` (CPT/HCPCS code -> description via NLM API)
- `R/40_investigate_unmatched_ndc.R` — Contains RxNorm API lookup functions and produces `unmatched_ndc_classified.rds` (NDC/RXNORM code -> drug_name via RxNorm API)
- `R/41_combine_reports.R` — Harmonizes both RDS artifacts into unified schema with `description` column
- `R/45_radiation_cpt_audit.R` lines 84-130 — `hardcoded_descriptions` named vector for retired radiation CPT codes
- `R/00_config.R` lines 412+ — `TREATMENT_CODES` list with inline comments containing descriptions for curated codes

### Episode Data Structure
- `R/44_treatment_episodes.R` — Defines `triggering_codes` (episode-level, comma-separated) and `triggering_code` (detail-level, single) columns

### Configuration
- `R/00_config.R` — TREATMENT_TYPES, TREATMENT_TYPE_COLORS, GAP_THRESHOLD, and all TREATMENT_CODES vectors

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `unmatched_codes_classified.rds` — Phase 39 output with columns: code, description, lookup_status (for CPT/HCPCS codes)
- `unmatched_ndc_classified.rds` — Phase 40 output with columns: code, drug_name, lookup_status (for NDC/RXNORM codes)
- `hardcoded_descriptions` in R/45 — Named character vector for retired radiation CPT codes (77404-77421 series)
- `TREATMENT_CODES` in R/00_config.R — Has inline comments with descriptions for original curated codes (ABVD regimen, etc.)
- `write.csv()` pattern in R/49 — Existing CSV output pattern to extend with new columns

### Established Patterns
- RDS artifact loading: `readRDS(file.path(CONFIG$cache$outputs_dir, "..."))` pattern
- Column selection: explicit `select()` with named columns (R/49 Section 4)
- Output directory: `CONFIG$output_dir` for final CSV files

### Integration Points
- Input: `code_descriptions.rds` (new, built by helper script) + existing episode/detail RDS artifacts
- Modified: `R/49_gantt_data_export.R` — adds description lookup and new columns to both CSV outputs
- New: Helper script to build `code_descriptions.rds` from multiple sources

</code_context>

<specifics>
## Specific Ideas

- The Phase 39-41 RDS artifacts already contain the bulk of code->description mappings from NLM API lookups performed during those phases
- Some ICD-10-PCS codes (XW033A3, XW033B3, etc.) were noted as "no description" even after API lookup — these will get empty strings per D-05
- TUMOR_REGISTRY sources produce `NA` triggering_codes — these naturally get empty descriptions
- The lookup builder script should be runnable independently to regenerate the lookup if new codes are added later

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-add-descriptions-of-codes-to-the-gantt-csvs*
*Context gathered: 2026-05-19*
