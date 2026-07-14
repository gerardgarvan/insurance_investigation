# Phase 123: Quantify MED_ADMIN/DISPENSING Chemo-Detection Fix Impact + Unmatched-NDC Audit - Context

**Gathered:** 2026-07-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce a **quantified before/after impact report** of the Phase 122 chemo-detection
fix (MED_ADMIN `MEDADMIN_TYPE=='RX'` matching + NDC→RxNorm crosswalk activating
DISPENSING and MED_ADMIN-ND) on treatment outputs, **plus an audit of unmatched
NDCs** to determine whether real chemo is still being missed.

This phase clarifies *how much the fix changed* and *what we're still missing* — it
does NOT change detection logic (Phase 122 did that) and does NOT regenerate the
full downstream product suite (deferred).

**In scope:**
- Before/after diff computed at the **source level** (PRESCRIBING-only = before;
  + MED_ADMIN-RX + NDC-resolved DISPENSING/MED_ADMIN-ND = after), cohort-scoped
- Metrics: patient & date counts, first-chemo timing shift, per-drug/ingredient
  delta, regimen-label impact
- Unmatched-NDC audit across four methods (string match, frequency review, RxNav
  re-query, resolved-non-chemo gap check)
- Single multi-sheet xlsx deliverable

**Out of scope (deferred / separate):**
- Regenerating downstream output files (episodes/Gantt/timing/payer) with the fix
- Immunotherapy MED_ADMIN/DISPENSING contribution (chemo-only)
- Changing `chemo_rxnorm` reference list — this phase *flags* gaps; correcting the
  list is a follow-up
</domain>

<decisions>
## Implementation Decisions

### Before/after baseline mechanism
- **D-01:** Construct the "before" state by **extending the R/107 diagnostic** —
  compute both sides in one cohort-scoped script. `before` = PRESCRIBING-only;
  `after` = PRESCRIBING + MED_ADMIN(`MEDADMIN_TYPE=='RX'`) + NDC-resolved
  (DISPENSING `NDC` + MED_ADMIN `MEDADMIN_TYPE=='ND'` via crosswalk).
- **D-02:** No full pipeline re-run and no toggle-flag plumbing — the diff is
  source-level and deterministic. R/107 already encodes the PRESCRIBING-baseline
  half; extend it (or a sibling script) to add the NDC sources and the after-side.

### Diff scope & metrics (all four in scope)
- **D-03:** **Patient & date counts** — # patients with any chemo (before vs after)
  and # distinct chemo `(ID, date)` pairs, broken down by contributing source
  (PRESCRIBING / MED_ADMIN-RX / DISPENSING+ND). This is the headline number.
- **D-04:** **First-chemo timing shift** — # patients gaining an EARLIER first-chemo
  date under the after-set, plus distribution of the shift in days. Extend R/107's
  existing "68 patients earlier" logic to include the NDC sources.
- **D-05:** **Per-drug/ingredient delta** — which chemo ingredients gain the most
  patients/dates from the new sources (e.g. oral agents surfaced by DISPENSING).
  Feeds the NDC audit narrative.
- **D-06:** **Regimen-label impact** — whether new chemo dates change first-line
  regimen labels (ABVD / BV+AVD / Nivo+AVD) for adults 21+. NOTE: this requires
  running regimen logic (R/25/R/26/R/62 path), not just source counts — higher
  effort than D-03..D-05. Researcher/planner to determine the least-invasive way to
  compute regimen labels on both before and after source sets.

### Unmatched-NDC audit (all four methods in scope)
- **D-07:** **Drug-name string match** — match unmatched NDCs against the chemo
  ingredient list (`chemo_rxnorm` ingredient names + `DRUG_NAME_ALIASES`) using
  `RAW_MEDADMIN_MED_NAME` (MED_ADMIN carries it) and any dispensing name text.
  Offline, uses data in hand.
- **D-08:** **Frequency-ranked review** — rank unmatched NDCs by patient/row volume,
  surface a top-N table (with name text) so highest-impact misses get attention.
- **D-09:** **RxNav re-query** — re-query the ~7,739 unresolved NDCs against
  alternate RxNav endpoints (ndcproperties / ndcstatus / historical NDC) to recover
  mappings the primary `rxcui.json?idtype=NDC` lookup missed. **HiPerGator-only
  (network)** — expect a runtime checkpoint mirroring Phase 122's R/108 build.
- **D-10:** **Resolved-non-chemo gap check** — of the ~16,588 NDCs that resolved to
  an RxCUI but weren't in `chemo_rxnorm`, check whether any resolved to a chemo
  ingredient MISSING from our `chemo_rxnorm` list (reference-list gaps, distinct
  from NDC-resolution gaps). This phase FLAGS such gaps; correcting the list is a
  follow-up.

### Deliverable & regeneration scope
- **D-11:** **Single multi-sheet xlsx** — one styled workbook, sheet per concern
  (before/after summary, timing shift, per-drug delta, regimen impact,
  unmatched-NDC top-N, resolved-gap findings). Matches project xlsx delivery
  pattern (R/51, TABLE-1/2). Amy-ready. HIPAA suppression standard (counts 1-10).
- **D-12:** **Quantification only** — this phase produces the diff + audit xlsx and
  stops. Full downstream regeneration (episodes/Gantt/timing/payer with the fix)
  remains a separate later pass, per Phase 122's deferred scope.

### Claude's Discretion
- Whether to extend R/107 in place vs create a sibling diagnostic script (D-01/D-02)
- Exact sheet layout/ordering within the xlsx and styling helpers to reuse
- Whether RxNav re-query (D-09) lands in the crosswalk-builder family (R/108) or a
  dedicated audit script; checkpoint structure for the network step
- Least-invasive method to compute regimen labels on both source sets (D-06)
- Script number / registration (R/39 vs SCRIPT_INDEX-only) and R/88 smoke sections

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The Phase 122 fix + sizing (what we are quantifying)
- `.planning/phases/122-med-admin-dispensing-gap-diagnostic-csv-gap-closure/122-CONTEXT.md` — the fix decisions (D-01..D-07), real column layout, affected consumers
- `.planning/phases/122-med-admin-dispensing-gap-diagnostic-csv-gap-closure/122-VERIFICATION.md` — proven runtime numbers (+1,139 patients / +10,752 dates; crosswalk 24,327 NDCs → 16,588 resolved / 126 chemo / 42 of 97 ingredients)
- Memory: `med-admin-dispensing-rxnorm-cui-mismatch` — finding summary

### Diagnostic + crosswalk assets to build on
- `R/107_med_admin_dispensing_gap_diagnostic.R` — PRESCRIBING-baseline vs MED_ADMIN-RX increment logic + earlier-first-chemo-date logic; the script to extend for the before/after diff
- `output/med_admin_dispensing_gap_diagnostic.csv` — prior HiPerGator run output
- `R/108_build_ndc_rxnorm_crosswalk.R` — RxNav lookup pattern (httr2 req_retry, batch loop); template for D-09 re-query
- `data/reference/ndc_rxnorm_crosswalk.rds` — the NDC→RxCUI named vector (matched only)
- `output/ndc_rxnorm_crosswalk_audit.csv` — per-NDC matched/miss list; the source of the unmatched-NDC universe for D-07..D-10

### Chemo reference + normalization
- `R/00_config.R` §3 — `TREATMENT_CODES$chemo_rxnorm` (the ingredient list to gap-check in D-10), `DRUG_NAME_ALIASES`, `canonicalize_drug_name()`, ID-not-PATID note
- `R/utils/utils_treatment.R` — `get_chemo_hits` / `load_ndc_crosswalk` / `normalize_ndc` (Phase 122 helpers the diff must use for the "after" set)

### Regimen labeling (for D-06)
- `R/25_treatment_durations.R`, `R/26_treatment_episodes.R` — first/last chemo date + episode/regimen path
- Regimen labeling logic (ABVD / BV+AVD / Nivo+AVD, adults 21+) — locate current implementation before planning D-06

### Delivery + convention
- `R/51_*` (post-death xlsx) and TABLE-1/TABLE-2 scripts — styled multi-sheet xlsx pattern + HIPAA suppression helper to reuse (D-11)
- `R/39_run_all_investigations.R`, `R/88_smoke_test_comprehensive.R`, `R/SCRIPT_INDEX.md` — registration/test conventions

### Data profiles (real column layout)
- `MED_ADMIN_values.csv`, `DISPENSING_values.csv`, `PRESCRIBING_values.csv`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets
- R/107 already computes PRESCRIBING baseline + MED_ADMIN-RX increment + earlier-first-chemo-date — extend rather than rebuild (D-01)
- R/108 RxNav lookup (httr2 retry, batch progress) — template for D-09 alternate-endpoint re-query
- `output/ndc_rxnorm_crosswalk_audit.csv` already partitions matched vs miss NDCs — the audit universe is already on disk (D-07..D-10)
- `get_chemo_hits()` in utils_treatment.R gives the corrected, consistent chemo-hit extraction for the "after" set — reuse so the diff matches production detection exactly
- xlsx styling + HIPAA suppression helpers from R/51 / TABLE scripts (D-11)

### Established patterns
- Self-bootstrap DuckDB (`USE_DUCKDB <- TRUE; if (!exists("pcornet_con"...)) open_pcornet_con()`) — R/107/R/108 precedent
- HiPerGator-only network steps run as a runtime checkpoint (Phase 122 R/108 precedent) — applies to D-09
- Cohort scoping to the 9,282 HL patients (R/107 already scopes this way)

### Traps to avoid
- The "after" set must use the SAME `get_chemo_hits()` path production uses, or the diff won't reflect real detection
- D-06 regimen impact is NOT a source-count — it needs regimen logic run on both sides; scope the effort explicitly
- D-10 is distinct from D-07/D-09: it's about `chemo_rxnorm` list completeness, not NDC resolution failure

</code_context>

<specifics>
## Specific Ideas

- Deliverable is Amy-ready — single styled xlsx, one sheet per concern, matching the R/51 / TABLE-1/2 delivery style.
- Report should make the headline "how much did the fix add" number unmistakable (patients + chemo dates gained, by source).
- Windows executor has no Rscript; the RxNav re-query (D-09) and any DuckDB-backed counts will need a HiPerGator runtime confirmation, mirroring Phase 122.

</specifics>

<deferred>
## Deferred Ideas

- Full downstream regeneration of episodes/Gantt/timing/payer outputs with the fix — separate later pass (D-12)
- Correcting the `chemo_rxnorm` reference list based on D-10 findings — this phase flags gaps; the fix is a follow-up
- Immunotherapy MED_ADMIN/DISPENSING contribution — chemo-only scope
- Broader audit of other tables for analogous code-column mismatches

</deferred>

---

*Phase: 123-quantify-how-much-the-med-admin-dispensing-chemo-detection-fix-changes-treatment-outputs-before-after-diff-and-investigate-whether-unmatched-ndcs-are-missing-real-chemo*
*Context gathered: 2026-07-14*
