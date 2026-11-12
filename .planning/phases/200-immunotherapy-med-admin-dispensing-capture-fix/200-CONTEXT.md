---
phase: 200
name: immunotherapy-med-admin-dispensing-capture-fix
status: decision-only (no code changes)
milestone: cross-milestone
depends_on: [Phase 199 complete]
tags: [immunotherapy, rituximab, methotrexate, r26, analytic-decision]
created: 2026-11-12
---

# Phase 200: Immunotherapy MED_ADMIN/DISPENSING Capture Fix - Context

**Gathered:** 2026-11-12
**Status:** Decision recorded — no planning or execution required

<domain>
## Phase Boundary

Record the team analytic decision about indication-based filtering of rituximab and methotrexate treatment episodes. No code changes.

**Background:** The original Phase 200 description called for switching `extract_immunotherapy_dates_with_codes()` in R/26 from RXNORM_CUI filtering to `get_chemo_hits()`-style matching, and adding rituximab RxNorm CUIs and biosimilar HCPCS codes. All of that was implemented in Phase 199 (Plan 01, 2026-11-12) before this phase was scoped. What remained was the underlying analytic question: should indication-based filtering be applied to prevent autoimmune-use rituximab/MTX records from appearing in the Gantt treatment timelines?

</domain>

<decisions>
## Implementation Decisions

### Indication-based Filtering (D-200-01)

- **D-200-01 (team decision, 2026-11-12):** Gantt treatment episodes capture ALL rituximab / methotrexate / immunotherapy administrations regardless of clinical indication. Patients whose rituximab or MTX use may be for an autoimmune condition are identified by the Phase 199 `immune_flag` column (with `immune_flag_dx` listing the qualifying diagnoses), and are NOT removed from the treatment timelines. No indication-based filtering is applied in R/26 or any downstream script.

  **Rationale:** Downstream analysts use `immune_flag` to stratify or exclude patients in their own analyses. Filtering at the pipeline level would remove information needed to make that determination. The flag approach preserves optionality.

### What Phase 199 Already Delivered

For reference, the following items were implemented in Phase 199 Plan 01 — they are not in scope here:

- `extract_immunotherapy_dates_with_codes()` switched from RXNORM_CUI guard to `get_chemo_hits()` for both DISPENSING (NDC→RxNorm crosswalk) and MED_ADMIN (MEDADMIN_CODE/MEDADMIN_TYPE).
- Rituximab ingredient CUI 121191, branded CUIs 1719312 and 2049106 added to `immunotherapy_rxnorm` in R/00_config.R.
- Biosimilar HCPCS Q5115 (Truxima), Q5119 (Ruxience), Q5123 (Riabni) added to `immunotherapy_hcpcs`.
- Before/after counts by triggering_code and source (pre-dedup) printed at runtime in R/26.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 199 decisions (drug exposure and flag logic)
- `.planning/phases/199-immune-brentuximab-flags-gantt-episodes-180/199-CONTEXT.md` — D-02b (full-history drug exposure union), D-200-01 origin, all immune_flag logic

### Code locations
- `R/26_treatment_episodes.R` lines 388–488 — `extract_immunotherapy_dates_with_codes()` as fixed in Phase 199
- `R/00_config.R` lines 3851–3901 — `immunotherapy_hcpcs` and `immunotherapy_rxnorm` code lists

No external specs — requirements fully captured in D-200-01 above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `get_chemo_hits()` in R/26 — the shared helper now used by both chemo and immunotherapy extraction
- `IMMUNE_DRUG_DEFS` / `get_drug_exposure_ids()` in `R/utils/utils_doi.R` — full-history drug search used by Phase 199 immune_flag logic

### Established Patterns
- Indication-based stratification is done via output columns (`immune_flag`, `immune_flag_dx`), not pipeline filtering — consistent with how `has_autoimmune_dx` is handled.

### Integration Points
- R/26 feeds R/28 → R/29 → R/52 → R/142 (and NHL subsets via R/170). The D-200-01 decision means none of those scripts filter on indication either.

</code_context>

<specifics>
## Specific Ideas

No specific implementation requirements — this phase is decision-only.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 200-immunotherapy-med-admin-dispensing-capture-fix*
*Context gathered: 2026-11-12*
