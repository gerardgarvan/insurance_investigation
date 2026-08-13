# Phase 141: CONTEXT-zip9-imputation - Context

**Gathered:** 2026-08-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire `approximate_zip9()` — already implemented in `R/utils/utils_address.R` (Phase 139)
— into `R/115_zip_stability_counts.R`. The function exists but no production script calls
it yet. This phase adds the call site in R/115, writes the imputed result to RDS, adds a
QC row to the workbook, and re-issues the xlsx on HiPerGator.

**In scope:**
- Add `approximate_zip9()` call in R/115 after the `get_zip9_at_date()`-equivalent step
- Write the imputed ZIP9 assignment table to RDS (alongside the existing workbook output)
- Add a named QC row in the workbook's QC sheet: imputation counts by `zip9_source`
  (`zip5_modal`, `zip5_only`, unchanged)
- Re-run R/115 on HiPerGator to regenerate the xlsx carrying the imputation QC rows
  alongside the existing completeness figures — workbook re-issue is the exit criterion

**Out of scope:**
- Wiring `approximate_zip9()` into the main cohort build / R/39 — future phase, no
  downstream SES linkage consumer exists yet
- New standalone R/116 script — no consumer to load from it
- Updating validation curves (A-06, encounter-anchored) — not triggered by imputation
  wiring alone
- Recomputing the C_completeness waterfall on post-imputation coverage — deferred; the
  waterfall remains scenario-based per Phase 140 D-2/D-4

</domain>

<decisions>
## Implementation Decisions

### Call site
- **D-01:** `approximate_zip9()` is called in **R/115 only**. The main cohort build
  pipeline is untouched. Rationale: Phase 140 finalized the ZIP assignment design for the
  workbook; wiring here unblocks the workbook release. Main pipeline wiring is deferred
  until SES linkage (ADI/SVI/SDI) is scoped.

### Output disposition
- **D-02:** The imputed assignment table (result of `get_zip9_at_date() |> approximate_zip9()`)
  is written to **RDS alongside the workbook**, consistent with the project's existing RDS
  caching pattern. It should be inspectable and reloadable without re-running R/115.

### QC / reporting
- **D-03:** Add a **named QC row in the existing QC sheet** showing imputation counts:
  rows assigned via `zip5_modal`, rows still NA (`zip5_only`), and rows unchanged
  (already had ZIP9). Consistent with how other coverage stats are reported in R/115.

### Done criteria
- **D-04:** Phase is complete when `approximate_zip9()` is wired into R/115, the imputed
  assignment table is written to RDS, the imputation QC rows are present in the workbook,
  and the xlsx has been re-issued from a real HiPerGator run. Recomputing the completeness
  waterfall on post-imputation coverage is explicitly out of scope and deferred.

### Claude's Discretion
- Exact location within R/115 where `approximate_zip9()` is called (after the
  encounter-level ZIP9 lookup step, before completeness waterfall computation)
- RDS filename and location (follow existing R/115 caching conventions)
- Whether `zip9_source` breakdown in the QC row is one row per source value or a single
  summarized row

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Core utility (the function being wired)
- `R/utils/utils_address.R` — `approximate_zip9()` is defined here (line ~343+). Read
  the full function signature, input/output schema, `zip9_source` provenance columns, and
  the probe-first gate behavior. The 5-column tibble contract and new provenance columns
  are the interface.

### Call site (where the wiring goes)
- `R/115_zip_stability_counts.R` — Read the full script to locate the encounter-level
  ZIP9 resolution step and understand where `approximate_zip9()` slots in. Also read the
  existing QC sheet construction to know where to add the imputation QC row and how the
  RDS cache is written.

### Phase 139 context (locked decisions for approximate_zip9)
- `.planning/phases/139-zip9-approximation/139-CONTEXT.md` — D-01 through D-08 define
  `approximate_zip9()`'s contract: trigger condition, approximation method, output schema,
  probe-first gate. These are locked; do not re-derive them.

### Phase 140 context (ZIP assignment design decisions)
- `.planning/phases/140-resolve-c-02-reconciliation-gate-and-finalize-zip-assignment-design-zip5-unit-uncapped-carry-forward-backward-only-primary-spec-for-zip-stability-counts-workbook/140-CONTEXT.md`
  — D-2 (ZIP5 as analysis unit), D-3 (uncapped carry-forward), D-4 (backward-only primary,
  forward-inclusive sensitivity). The imputation must be consistent with these decisions.

No external specs — requirements fully captured in decisions above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `approximate_zip9()` in `R/utils/utils_address.R` (~line 343) — ready to call; returns
  the same 5-column tibble plus `zip9_source`, `zip9_modal_n`, `zip5_lookup_n`,
  `zip9_approx_zip5` provenance columns.
- `get_zip9_at_date()` in `R/utils/utils_address.R` (~line 111) — the upstream function;
  chain is `get_zip9_at_date(ids, dates) |> approximate_zip9()`.
- Existing RDS caching pattern in R/115 — follow the same file-naming and write location
  used by other cached outputs in that script.

### Established Patterns
- Probe-first gate: `approximate_zip9()` returns input unchanged (with a console warning)
  if `LDS_ADDRESS_HISTORY` is absent — R/115 does not need to guard this call.
- QC row pattern: R/115 already has named QC rows for coverage stats — add the imputation
  breakdown row in the same style.
- `zip9_source` values: `"zip5_modal"` (imputed), `"zip5_only"` (ZIP5 exists but no
  modal ZIP9 found), `NA` / unchanged (already had ZIP9 or match_type = "none").

### Integration Points
- R/115 encounter-level ZIP9 resolution → chain `approximate_zip9()` immediately after
- R/115 QC sheet construction → add imputation counts row
- R/115 RDS output block → write imputed assignment table

</code_context>

<specifics>
## Specific Ideas

No specific "I want it like X" moments — standard wiring following existing R/115 patterns.

</specifics>

<deferred>
## Deferred Ideas

- `approximate_zip9()` wiring into main cohort build (R/39 / primary analytic dataset) —
  deferred until SES linkage (ADI/SVI/SDI) is scoped as a phase.
- Updating A-06 / encounter-anchored validation curves after imputation — not triggered
  by this phase; deferred.
- Standalone R/116 imputation script — no downstream consumer yet; deferred.

</deferred>

---

*Phase: 141-context-zip9-imputation*
*Context gathered: 2026-08-13*
