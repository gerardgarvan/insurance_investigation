# Phase 35: Tiered Same-Day Payer Categorization - Context

**Gathered:** 2026-04-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Two deliverables per Amy Crisp's email (`payer_framework.txt`):

1. **Raw payer frequency tables** — Every distinct untransformed PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY code with occurrence counts, cross-referenced against PayerVariable.xlsx descriptions and categories. Produced for BOTH all-encounter and AV+TH scopes.

2. **Hierarchical same-day payer resolution** — For each patient-date where multiple encounters exist, resolve to a single payer assignment using the priority hierarchy: Medicaid (including codes 93, 14, and FLM-sourced encounters) > Medicare > Private > Other > Self-pay > Uninsured > Missing. Produced for BOTH all-encounter and AV+TH scopes.

Standalone diagnostic script. Does NOT modify the existing payer harmonization pipeline.

</domain>

<decisions>
## Implementation Decisions

### Category Mapping
- **D-01:** Tier mapping defined as a configurable lookup (named list or data frame) at the top of the script — NOT buried in case_when logic. This allows PIs to change mappings (e.g., "move code 93 from Medicaid to Medicare") with a one-line edit.
- **D-02:** The 6 tiers are: Medicaid, Medicare, Private, Other, Self-pay, Uninsured, Missing. These collapse the R pipeline's 9 categories: Dual eligible → Medicaid, Other government → Other, No payment/Self-pay → Self-pay, Unavailable + Unknown → Missing.
- **D-03:** Special rules per Amy Crisp: codes 93 and 14 explicitly map to Medicaid. If any encounter on a patient-date has ENCOUNTER.SOURCE = 'FLM', the resolved payer for that date is Medicaid (FLM = Florida Medicaid claims).
- **D-04:** The FLM override uses ENCOUNTER.SOURCE (not DEMOGRAPHIC.SOURCE) — it checks whether any individual encounter on that date came from the FLM claims feed.

### Raw Frequency Table
- **D-05:** Produce raw payer code frequency tables for BOTH all encounters AND AV+TH encounters, with PayerVariable.xlsx cross-reference (same format as Phase 34: code, description, xlsx category, count, percentage).
- **D-06:** This is a NEW script — does not modify Phase 34's `R/35_payer_code_frequency_av_th.R`, which remains as a verified baseline.

### Output Structure
- **D-07:** Three CSVs per scope (all-encounter and AV+TH, so 6 resolution CSVs total + 4 frequency CSVs):
  - CSV A: Per-patient-per-date detail with resolved_payer, original codes, n_encounters, resolution_reason (which tier rule fired)
  - CSV B: Patient-level summary with modal resolved payer across all dates
  - CSV C: Aggregate category distribution before vs after resolution (showing impact of the hierarchy)
- **D-08:** Frequency table outputs: primary code freq, secondary code freq, category summary — for both all-encounter and AV+TH scopes.

### Script Structure
- **D-09:** Standalone diagnostic script following Phase 33/34 pattern: `source("R/00_config.R")`, DuckDB materialize-early, conditional RDS fallback.
- **D-10:** Does NOT modify `R/02_harmonize_payer.R` or any core pipeline script. The same-day resolution can be promoted to the pipeline later if PIs approve the approach.

### Claude's Discretion
- Script numbering (likely R/36_*.R)
- Console summary format and detail level
- CSV file naming convention (with `_all` and `_av_th` suffixes to distinguish scopes)
- Whether to produce the raw frequency tables and resolution outputs in a single script or split into two
- Sort order of detail-level output (by patient then date, or by resolved payer category)
- How to handle dates with only a single encounter (pass through with resolution_reason = "single encounter")

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Amy Crisp Framework (Primary Specification)
- `payer_framework.txt` — Amy Crisp's email defining the tiered hierarchy: Medicaid (incl. 93, 14, FLM source) > Medicare > Private > Other > Self-pay > Uninsured > Missing. This is the authoritative source for the resolution logic.

### PayerVariable Reference
- `PayerVariable.xlsx` (Sheet2) — 166-row lookup table with 3 columns: "Value In Data" (raw code), "What old value means" (description), "New Value" (mapped category). Used for frequency table cross-reference.

### Existing Payer Logic
- `R/02_harmonize_payer.R` — `map_payer_category()` function with 9-category prefix-based mapping and dual-eligible detection. Reference for understanding existing code-to-category logic (not reused directly, but informs the tier mapping).
- `R/00_config.R` lines 285-314 — `PAYER_MAPPING` definition with prefix rules, exact-match overrides, sentinel values, and 9 category list.

### Phase 34 Pattern (Structural Template)
- `R/35_payer_code_frequency_av_th.R` — Phase 34 script: standalone AV+TH payer code frequency with PayerVariable.xlsx cross-reference. Structural template for the frequency table portion.
- `R/33_multi_source_overlap_av_th.R` — Phase 33 standalone AV+TH diagnostic pattern with DuckDB materialize-early.

### Infrastructure
- `R/utils_duckdb.R` — `get_pcornet_table()`, `open_pcornet_con()`, `materialize()` helpers

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `get_pcornet_table("ENCOUNTER")` — DuckDB backend-transparent access to ENCOUNTER table
- `materialize()` — Collect lazy DuckDB query to tibble
- `readxl::read_excel()` — PayerVariable.xlsx reading pattern from Phase 34
- `map_payer_category()` in R/02_harmonize_payer.R — Existing 9-category mapping (reference for understanding code→category, but the tier mapping will be its own configurable lookup)
- Phase 34 xlsx column rename pattern: "Value In Data" → `code`, "What old value means" → `description`, "New Value" → `category`

### Established Patterns
- AV+TH filter: `filter(ENC_TYPE %in% c("AV", "TH"))` applied after materialize
- Materialize-early: `get_pcornet_table("ENCOUNTER") %>% materialize()` then in-memory operations
- Standalone script structure: `source("R/00_config.R")`, conditional `source("R/01_load_pcornet.R")`, DuckDB connection management
- CSV output to `output/tables/` with `readr::write_csv()`

### Integration Points
- ENCOUNTER table columns needed: ID, ENCOUNTERID, ADMIT_DATE, SOURCE, ENC_TYPE, PAYER_TYPE_PRIMARY, PAYER_TYPE_SECONDARY
- The existing `compute_effective_payer()` in R/02_harmonize_payer.R resolves primary vs secondary payer per encounter — the same-day resolution operates at a HIGHER level (across encounters on the same date)

</code_context>

<specifics>
## Specific Ideas

- User explicitly wants the tier mapping to be easy to change if PIs revise category assignments — a configurable lookup, not hardcoded logic
- Both all-encounter and AV+TH scopes for ALL outputs (frequency tables AND resolution)
- Amy's email is the authoritative specification: `payer_framework.txt`
- Resolution should show a "before vs after" comparison so PIs can see the impact of the hierarchy
- FLM source override applies at the ENCOUNTER.SOURCE level (per-encounter, not per-patient)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 35-tiered-same-day-payer-categorization*
*Context gathered: 2026-04-27*
