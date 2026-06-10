# Phase 97: R/60 Hot-Path Migration - Context

**Gathered:** 2026-06-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Migrate R/60_tiered_same_day_payer.R from dplyr to data.table for 5-20x speedup with identical CSV output. All three operational sections (classify swap, frequency tables, same-day resolution) are in scope. A combined benchmark + validation script proves both speedup and output parity.

</domain>

<decisions>
## Implementation Decisions

### Migration Depth
- **D-01:** Full script migration — all 3 sections of R/60 are converted to data.table, not just the hot path. This avoids revisiting the file later.
  - Section 2: Swap `classify_payer_tier()` to `classify_payer_tier_dt()` (trivial, function already exists from Phase 96)
  - Section 3: Rewrite `build_frequency_tables()` — replace `count()`, `AMC_PAYER_LOOKUP[code]` named vector lookups, and `group_by() %>% summarise()` with data.table equivalents using keyed joins
  - Section 4: Rewrite `resolve_same_day_payer()` — replace `group_by(ID, admit_date_parsed) %>% summarise(...)` with data.table `[, by=]` aggregation with `setkey()` before aggregation

### Benchmarking Method
- **D-02:** Dedicated one-time benchmark script (R/97), NOT embedded per-run timing. Adding system.time() wrappers to every run defeats the purpose of making the script faster. The benchmark script runs old dplyr path vs new data.table path side-by-side on the same data, logs the comparison. Run once to prove speedup, then sits as documentation.

### Validation Approach
- **D-03:** Combined benchmark + validation in a single R/97 script. The script both times the old vs new paths AND diffs the 12 CSV outputs to prove parity. Follows the Phase 95-96 pattern of dedicated validation scripts but avoids creating two separate files.

### Claude's Discretion
- Internal data.table patterns (setkey placement, copy semantics, := vs functional style) — follow Phase 95-96 established patterns
- Whether `build_frequency_tables()` stays as a function or gets inlined — Claude's judgment based on readability
- How the benchmark script structures the old-vs-new comparison (temporary output dirs, etc.)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 97 Target Script
- `R/60_tiered_same_day_payer.R` — The script being migrated. 3 operational sections, 12 CSV outputs, 2 scopes (all-encounter + AV+TH)

### data.table Infrastructure (Phase 95-96)
- `R/utils/utils_dt.R` — ensure_dt(), to_tibble_safe(), get_lookup_dt() helpers
- `R/utils/utils_payer.R` — classify_payer_tier() (dplyr) and classify_payer_tier_dt() (data.table) side-by-side
- `R/00_config.R` — LOOKUP_TABLES_DT with 6 keyed data.tables (AMC_PAYER_LOOKUP, TIER_MAPPING, etc.)

### Prior Validation Scripts (pattern reference)
- `R/95_validate_dt_infrastructure.R` — 45+ checks, Phase 95 validation pattern
- `R/96_validate_payer_dt.R` — 41 checks, Phase 96 parity validation pattern

### Requirements
- `.planning/REQUIREMENTS.md` — PERF-01 (data.table by= aggregation), PERF-02 (CSV identity), VALID-02 (runtime benchmark)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `classify_payer_tier_dt()` in `R/utils/utils_payer.R` — Drop-in replacement for classify_payer_tier(), returns tibble. Ready to swap in Section 2.
- `ensure_dt()` / `to_tibble_safe()` in `R/utils/utils_dt.R` — Boundary conversion helpers with defensive guards
- `get_lookup_dt()` in `R/utils/utils_dt.R` — Retrieves keyed data.tables from LOOKUP_TABLES_DT
- `LOOKUP_TABLES_DT$AMC_PAYER_LOOKUP` — Keyed data.table with code/payer_category columns, ready for update-join syntax replacing `AMC_PAYER_LOOKUP[code]` named vector lookup
- `LOOKUP_TABLES_DT$TIER_MAPPING` — Keyed data.table with payer_category/tier columns

### Established Patterns
- **Reference semantics defense:** `copy()` wraps `ensure_dt()` at entry point (Phase 96 pattern)
- **Keyed join syntax:** `dt[lookup, on=.(col), new_col := i.col]` for update joins (Phase 96 classify_payer_tier_dt)
- **fcase() over case_when():** data.table's fcase() replaces dplyr's case_when() (Phase 96 pattern)
- **Return tibble:** Functions return tibble via to_tibble_safe() for dplyr pipeline compatibility (Phase 96 D-04)

### Integration Points
- R/60 is a standalone script (not part of main pipeline sequence) — safe to modify without cascading effects
- Smoke test R/88 Section 15f validates same-day payer resolution — must still pass after migration
- 12 CSV outputs in output/tables/ consumed by downstream analysis — must remain identical

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches using the established Phase 95-96 data.table patterns.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 97-r-60-hot-path-migration*
*Context gathered: 2026-06-10*
