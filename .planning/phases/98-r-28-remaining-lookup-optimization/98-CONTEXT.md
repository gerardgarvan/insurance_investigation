# Phase 98: R/28 + Remaining Lookup Optimization - Context

**Gathered:** 2026-06-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace all named vector lookups (`DRUG_GROUPINGS[code]`, `CODE_SUBCATEGORY_MAP[code]`) with data.table keyed joins across the entire codebase. Primary target is R/28 episode classification (explode-join-collapse for comma-separated triggering_codes), with a full sweep of 7 additional files for consistency. Validate with dedicated R/98 parity script and full R/88 smoke test as the v3.0 gate.

</domain>

<decisions>
## Implementation Decisions

### Migration Scope
- **D-01:** Full codebase sweep — replace ALL `DRUG_GROUPINGS[` named vector lookups with keyed join syntax. Not just R/28 but also R/55, R/56, R/57_drug_grouping_instances, R/57_explore_dx_deduplication, R/58, R/88, and R/utils/utils_xlsx_lookups.R. Even where performance impact is negligible, keyed joins replace named vectors for consistency.
- **D-02:** CODE_SUBCATEGORY_MAP lookups in R/56, R/57, R/57_drug_grouping_instances, R/58, and utils_xlsx_lookups.R are also in scope (same pattern, same sweep).

### Comma-Separated Lookup Pattern (R/28)
- **D-03:** Explode-join-collapse approach for R/28's sapply-based patterns. Unnest comma-separated `triggering_codes` into one-row-per-code, do a single vectorized keyed join against LOOKUP_TABLES_DT, then re-aggregate with `paste(collapse=",")`. Eliminates the R-level sapply/str_split loop entirely.
- **D-04:** Applies to all R/28 sections that use the pattern: Section 5B (map_codes_to_descriptions, map_codes_to_drug_groups), Section 5C (map_codes_to_xlsx_metadata, aggregate_treatment_line, aggregate_cross_use_flag, aggregate_immuno_confidence), and Section 6B (TBD code export loop).

### Validation Approach
- **D-05:** Dedicated R/98 parity validation script that compares R/28 output (treatment_episodes.rds) before vs after optimization. Validates structure (columns, order, types) and content (row-by-row match). Follows the R/95/R/96/R/97 validation script pattern.
- **D-06:** No benchmark timing needed — R/28 processes ~1K episodes (not 1M encounters like R/60). The optimization is for consistency with the data.table milestone, not for measurable speedup.
- **D-07:** Full R/88 smoke test (all 35 sections) serves as the final v3.0 gate. Must pass after all changes.

### Claude's Discretion
- Internal data.table patterns for the explode-join-collapse (CJ vs manual unnest, .SD usage, re-aggregation method)
- Whether helper functions (lookup_drug_group, map_codes_to_drug_groups, etc.) are rewritten as data.table functions or replaced with inline operations
- How to handle the xlsx_lookups vectors (currently named character vectors, not in LOOKUP_TABLES_DT) — may need temporary data.table wrappers
- R/98 validation script structure and specific checks
- Whether code_descriptions.rds lookup (also in R/28) gets the same treatment or stays as-is (it's loaded from RDS, not a config lookup table)
- Ordering and grouping of the 8-file sweep for the plan

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 98 Primary Target
- `R/28_episode_classification.R` — Primary script being optimized. 1039 lines, 7 sections. Key lookup patterns at lines 460-495 (Section 5B: DRUG_GROUPINGS/code_descriptions sapply), lines 510-594 (Section 5C: xlsx metadata sapply), lines 740-767 (Section 6B: TBD code export loop)

### Files in DRUG_GROUPINGS Sweep
- `R/55_verify_replaced_by_codes.R` — Lines 180-181: `DRUG_GROUPINGS[old_code]`, `DRUG_GROUPINGS[new_code]`
- `R/56_new_tables_from_groupings.R` — Lines 262, 285: `DRUG_GROUPINGS[treatment_code]`; Line 333: `CODE_SUBCATEGORY_MAP[treatment_code]`
- `R/57_drug_grouping_instances.R` — Line 272: `DRUG_GROUPINGS[triggering_code]`; Line 320: `CODE_SUBCATEGORY_MAP[triggering_code]`
- `R/57_explore_dx_deduplication.R` — Line 284: `DRUG_GROUPINGS[treatment_code]`; Line 296: `CODE_SUBCATEGORY_MAP[treatment_code]`
- `R/58_code_reference_tables.R` — Line 370: `CODE_SUBCATEGORY_MAP[treatment_code]`
- `R/88_smoke_test_comprehensive.R` — Line 1623: `DRUG_GROUPINGS[proton_codes]` (validation check)
- `R/utils/utils_xlsx_lookups.R` — Lines 145, 147: `CODE_SUBCATEGORY_MAP[code]`, `DRUG_GROUPINGS[code]`

### data.table Infrastructure (Phase 95-97)
- `R/utils/utils_dt.R` — ensure_dt(), to_tibble_safe(), get_lookup_dt() helpers
- `R/00_config.R` — LOOKUP_TABLES_DT with 6 keyed data.tables (DRUG_GROUPINGS keyed on `code` with `drug_group` column, CODE_SUBCATEGORY_MAP keyed on `code` with `subcategory` column)
- `R/utils/utils_payer.R` — classify_payer_tier_dt() established pattern for keyed join usage

### Requirements
- `.planning/REQUIREMENTS.md` — PERF-03 (R/28 keyed joins), PERF-04 (treatment_episodes.rds unchanged), VALID-01 (R/88 all 35 sections pass)

### Prior Phase Context
- `.planning/phases/95-infrastructure-setup/95-CONTEXT.md` — D-03 (semantic column names), D-04 (TREATMENT_CODES flattening)
- `.planning/phases/96-classify-payer-tier-dt-implementation/96-CONTEXT.md` — Keyed join patterns, copy() at entry, to_tibble_safe() at exit
- `.planning/phases/97-r-60-hot-path-migration/97-CONTEXT.md` — Full script migration pattern, ensure_dt()/copy() patterns

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `LOOKUP_TABLES_DT$DRUG_GROUPINGS` — Keyed data.table with `code`/`drug_group` columns. Direct replacement for `DRUG_GROUPINGS[code]` named vector lookups.
- `LOOKUP_TABLES_DT$CODE_SUBCATEGORY_MAP` — Keyed data.table with `code`/`subcategory` columns. Direct replacement for `CODE_SUBCATEGORY_MAP[code]` lookups.
- `ensure_dt()` / `to_tibble_safe()` — Boundary conversion helpers from utils_dt.R
- `get_lookup_dt()` — Retrieves keyed data.tables by name from LOOKUP_TABLES_DT

### Established Patterns
- **Keyed join syntax:** `dt[lookup, on=.(col), new_col := i.col]` for update joins (Phase 96/97 pattern)
- **Reference semantics defense:** `copy()` wraps `ensure_dt()` at entry point
- **Return tibble:** Functions return tibble via to_tibble_safe() for dplyr pipeline compatibility
- **Named vector pattern being replaced:** `DRUG_GROUPINGS[code]` returns the drug group for a code; `LOOKUP_TABLES_DT$DRUG_GROUPINGS[.(code), drug_group]` is the data.table equivalent

### Integration Points
- R/28 output (treatment_episodes.rds) is consumed by R/30 (Gantt export), R/75 (encounter analysis), and downstream xlsx exports. Structure must remain identical.
- R/88 smoke test Section 15 validates R/28 output structure and content
- The 7 sweep files are standalone analysis scripts — changes are isolated
- R/utils/utils_xlsx_lookups.R is sourced by R/28 — changes there propagate to R/28's behavior

</code_context>

<specifics>
## Specific Ideas

- The vroom parsing warnings in log3.txt (from R/97 HiPerGator run) are pre-existing and benign — they occur during raw PCORnet CSV loading, not from Phase 97 code. No action needed.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 98-r-28-remaining-lookup-optimization*
*Context gathered: 2026-06-10*
