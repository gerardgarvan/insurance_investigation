---
phase: 200
name: immunotherapy-med-admin-dispensing-capture-fix
status: planned
milestone: cross-milestone
depends_on: [Phase 199 complete]
tags: [immunotherapy, rituximab, methotrexate, r26, chemo-lists, treatment-capture]
created: 2026-11-12
---

# Phase 200: Immunotherapy MED_ADMIN/DISPENSING Capture Fix - Context

**Gathered:** 2026-11-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix treatment capture in `extract_immunotherapy_dates_with_codes()` (R/26) and extend the chemo
treatment code lists to include rituximab biosimilar HCPCS and oral MTX, then rerun the downstream
pipeline chain through R/142 and R/170. R/88 smoke checks must pass.

**Scope:**
1. The R/26 MED_ADMIN/DISPENSING switch to `get_chemo_hits()` is the core bug fix (confirmed 2026-11-12: neither table has RXNORM_CUI). This was implemented in the Phase 199 working tree but NOT yet committed as Phase 200 work.
2. Add rituximab biosimilar HCPCS (Q5115/Q5119/Q5123) and rituximab RxNorm CUIs to the chemo treatment code lists — J9310 precedent means rituximab is classified as Chemotherapy in the pipeline (see `R/00_config.R` line 2055).
3. Add oral methotrexate HCPCS J8610 to the chemo/MTX code lists.
4. Run read-only before/after counts by drug and treatment type (R/26 checkpoint output).
5. Rerun R/26 → R/28 → R/29 → R/52 → R/142 → R/170 and dependents on HiPerGator.
6. R/88 smoke checks.
7. Rerun `R/tools/check_199_full_history.R` — raw-only counts should drop to near zero after the fix.

**Out of scope:**
- Changes to `immune_flag`, `ever_brentuximab`, or `immune_flag_dx` columns (Phase 199).
- Any changes to `has_autoimmune_dx` / `first_autoimmune_dx_date` (Phase 192.1).
- Indication-based filtering of rituximab/MTX (D-200-01: not done — see Team Decision below).

</domain>

<decisions>
## Implementation Decisions

### Team Decision (D-200-01)

- **D-200-01 (team decision, 2026-11-12):** Gantt treatment episodes capture ALL rituximab / methotrexate / immunotherapy administrations regardless of clinical indication. Patients whose rituximab or MTX use may be for an autoimmune condition are identified by the Phase 199 `immune_flag` column (with `immune_flag_dx`), and are NOT removed from the timelines. No indication-based filtering is applied in R/26 or any downstream script.

### Code list placement for rituximab biosimilars and oral MTX

- **D-200-02 (OPEN — resolve in research):** The existing comment at `R/00_config.R` line 722 warns: "Adding rituximab CUIs to chemo_rxnorm would inflate chemo-detection counts and corrupt ABVD / BV+AVD regimen identification." The researcher must determine whether Q5115/Q5119/Q5123 and additional RxNorm CUIs should go into `chemo_hcpcs` / `chemo_rxnorm`, or only into `immunotherapy_hcpcs` / `immunotherapy_rxnorm`, or both — and explain the impact on regimen identification. J9310/J9311/J9312 are classified as "Chemotherapy" in DRUG_GROUPINGS (line 2055) but were kept out of `chemo_hcpcs`; the researcher must check whether this was intentional or an earlier omission.

- **D-200-03 (OPEN — resolve in research):** J8610 (methotrexate oral, 2.5 mg) should be added to MTX code detection. Determine which list(s) in R/00_config.R receive it: `MTX_CODES$hcpcs`, `chemo_hcpcs`, or both; and whether IMMUNE_DRUG_DEFS already covers it (line 873 of config diff shows J8610 is there in the uncommitted Phase 199 changes).

### Rerun chain

- **D-200-04:** Rerun order: R/26 → R/28 → R/29 → R/52 → R/142 → R/170 → R/88 → `R/tools/check_199_full_history.R`. Exact HiPerGator `source()` commands must appear in the plan task as a checkpoint.

### Before/after counts

- **D-200-05:** R/26 already prints pre-dedup counts by triggering_code and source (Phase 199 checkpoint code). The plan must include a HiPerGator checkpoint step where Gerard pastes back: (a) the pre-dedup count table from R/26, (b) the final row count from R/28, (c) the check_199_full_history.R raw-only counts after the fix.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Core scripts being modified
- `R/26_treatment_episodes.R` — `extract_immunotherapy_dates_with_codes()` (lines 388–488 in working tree); `get_chemo_hits()` helper used by chemo path
- `R/00_config.R` — `TREATMENT_CODES$chemo_hcpcs` (line 3140), `TREATMENT_CODES$chemo_rxnorm` (line 3237), `TREATMENT_CODES$immunotherapy_hcpcs` (line 3851), `TREATMENT_CODES$immunotherapy_rxnorm` (line 3868), `RITUXIMAB_CODES` (line 738), `MTX_CODES` (line 747), `IMMUNE_DRUG_DEFS` (line ~855)

### Phase 199 decisions (must carry forward)
- `.planning/phases/199-immune-brentuximab-flags-gantt-episodes-180/199-CONTEXT.md` — D-02b (full-history drug exposure), D-03 (drug label confirmation), D-200-01 origin

### Warning to investigate
- `R/00_config.R` lines 719–756 comment block — explains why rituximab CUIs were kept out of `chemo_rxnorm` (regimen identification concern); researcher must assess whether this still applies after Phase 199

No external specs — requirements fully captured in decisions above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `get_chemo_hits()` in R/26 — shared helper for DISPENSING (NDC crosswalk) + MED_ADMIN (MEDADMIN_CODE/MEDADMIN_TYPE); already works for chemo, now used for immunotherapy
- `load_ndc_crosswalk()` — NDC→RxNorm crosswalk used by both chemo and immunotherapy paths
- `R/tools/check_199_full_history.R` — read-only validation tool; rerun to verify fix

### Established Patterns
- Code list changes go in `R/00_config.R` TREATMENT_CODES section; new code blocks get a Phase N label comment
- Downstream chain: R/26 → R/28 → R/29 → R/52 → R/142 → R/170 (NHL subset)
- HiPerGator checkpoint tasks: provide exact `source()` commands; ask Gerard to paste count rows, not full output

### Integration Points
- R/26 treatment episodes feed R/28 (episode builder) → R/29 (episode summary) → R/52 (Gantt 90-day) → R/142 (Gantt 180-day) → R/170 (NHL subsets)
- R/88 smoke tests verify column counts and spot-checks on output CSVs

</code_context>

<specifics>
## Specific Ideas

- Rituximab biosimilar HCPCS to add: Q5115 (Truxima/rituximab-abbs), Q5119 (Ruxience/rituximab-pvvr), Q5123 (Riabni/rituximab-arrx)
- RxNorm CUIs already added to `immunotherapy_rxnorm` in Phase 199 working tree: 121191 (ingredient), 1719312, 2049106
- Oral MTX HCPCS: J8610 (methotrexate 2.5 mg oral)
- `check_199_full_history.R` found 409 rituximab, 26 MTX, 365 brentuximab patients missed by episodes alone — this count should drop after the fix

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 200-immunotherapy-med-admin-dispensing-capture-fix*
*Context gathered: 2026-11-12*
