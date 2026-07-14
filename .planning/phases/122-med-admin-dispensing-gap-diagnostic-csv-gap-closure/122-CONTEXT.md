# Phase 122: MED_ADMIN/DISPENSING Chemo-Detection Gap Closure - Context

**Gathered:** 2026-07-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix the confirmed latent bug where DISPENSING and MED_ADMIN silently contribute
**zero** chemo treatment detection because the pipeline matches a `RXNORM_CUI`
column that neither table has in this OneFlorida+ extract. Restore both tables as
working chemo-detection sources across all consumers, including an NDC→RxNorm
crosswalk so NDC-coded records (DISPENSING, and MED_ADMIN `MEDADMIN_TYPE=='ND'`)
also contribute.

**Sized impact (R/107 diagnostic, quick task 260714-end, run on HiPerGator
2026-07-14):** MED_ADMIN RX-typed rows alone add **+1,139 patients / +10,752
chemo dates** beyond PRESCRIBING, with **68 patients** gaining an earlier
first-chemo date. DISPENSING = 718,891 rows / 4,389 patients, currently
unmatchable (NDC only). ND-typed MED_ADMIN ≈22% of ~2.39M rows, also unmatched.

**In scope:**
- Read MED_ADMIN codes from `MEDADMIN_CODE` where `MEDADMIN_TYPE=='RX'` (RxNorm CUIs) against `chemo_rxnorm`
- Build/source an NDC→RxNorm crosswalk so DISPENSING (`NDC`) and MED_ADMIN `MEDADMIN_TYPE=='ND'` rows resolve to RxNorm and match `chemo_rxnorm`
- Update ALL affected consumers (see code_context) to use the corrected column access
- Revise decision D-12 ("RXNORM_CUI only, no NDC matching") — NDC matching is now required
- Update test fixtures so they reflect the REAL extract column layout (fixtures currently carry a phantom `RXNORM_CUI` column that masked this bug)

**Out of scope (future / separate):**
- Immunotherapy MED_ADMIN/DISPENSING (this phase is chemo; immuno detection is procedure/DRG-based and out of the diagnostic's scope)
- Re-running downstream analyses / regenerating all outputs (the fix enables it; a separate pass regenerates)
</domain>

<decisions>
## Implementation Decisions

### Fix scope (LOCKED)
- **D-01:** Fix MED_ADMIN via `MEDADMIN_TYPE=='RX' & MEDADMIN_CODE %in% chemo_rxnorm` (RX-typed rows carry RxNorm CUIs directly).
- **D-02:** ALSO build an NDC→RxNorm crosswalk so DISPENSING (`NDC`) and MED_ADMIN `MEDADMIN_TYPE=='ND'` rows contribute. This is the broader scope chosen over an RX-only quick fix.
- **D-03:** Revise decision D-12 ("RXNORM_CUI only, no NDC matching") — the original premise (these tables expose RXNORM_CUI) is false for this extract; NDC matching is now in scope.

### Correctness constraints
- **D-04:** Patient ID column is `ID` (not PATID) across all tables.
- **D-05:** All existing `"RXNORM_CUI" %in% colnames(...)` guards must be replaced with column-access that works on the real layout — but stay defensive: degrade gracefully (message + skip) if a table/column is genuinely absent, never crash (preserve the fixtures-vs-prod dual-environment safety).
- **D-06:** Fixes must be consistent across ALL consumers so treatment episodes, timing, payer anchoring, drug names, cohort membership, inventory, and coverage all see the same expanded source set.
- **D-07:** Update fixtures to match real column layout (MED_ADMIN: MEDADMIN_CODE+MEDADMIN_TYPE, no RXNORM_CUI; DISPENSING: NDC, no RXNORM_CUI) so smoke tests catch this class of bug in future.

### Claude's Discretion
- NDC→RxNorm crosswalk mechanism (bundled reference file vs RxNav API `ndcstatus`/`ndcproperties` with caching) — researcher to recommend; prefer a cached/bundled approach consistent with the project's offline-capable pattern
- Whether to centralize the corrected drug-code extraction into a shared helper (utils) vs patch each site
- R/88 smoke-test section changes
- HIPAA suppression already standard (counts 1-10)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The bug + sizing
- `R/107_med_admin_dispensing_gap_diagnostic.R` — the diagnostic that sized the gap; encodes the correct MED_ADMIN RX-typed access pattern and the PRESCRIBING-baseline comparison logic
- `output/med_admin_dispensing_gap_diagnostic.csv` — HiPerGator run output (baseline + increments)
- Memory: `med-admin-dispensing-rxnorm-cui-mismatch` — the finding summary

### Affected consumers (ALL must be fixed — grep `"RXNORM_CUI" %in% colnames`)
- `R/10_cohort_predicates.R` — cohort `has_chemo` (DISPENSING + MED_ADMIN branches)
- `R/26_treatment_episodes.R` — episodes → Gantt (chemo sources #5 DISPENSING, #6 MED_ADMIN; also immuno branches — chemo only for this phase)
- `R/25_treatment_durations.R` — first/last chemo date, timing (2 functions)
- `R/11_treatment_payer.R` — treatment-anchored payer windows (2 functions)
- `R/27_drug_name_resolution.R` — drug names → regimen; DISPENSING NDC harvest also gated on RXNORM_CUI presence
- `R/20_treatment_inventory.R` — drug landscape (tryCatch-wrapped; also references absent RAW_DISPENSE_MED_NAME)
- `R/76_treatment_source_coverage.R` — coverage report

### Config + loader + convention
- `R/00_config.R` §3 — TREATMENT_CODES$chemo_rxnorm; PCORNET_TABLES; the D-12 comment; ID-not-PATID note
- `R/01_load_pcornet.R` — DISPENSING_SPEC / MED_ADMIN_SPEC col specs that DECLARE RXNORM_CUI (readr drops it silently when absent); the "D-12: no NDC matching" comments
- `R/39_run_all_investigations.R`, `R/88_smoke_test_comprehensive.R`, `R/SCRIPT_INDEX.md` — registration/test conventions
- `tests/fixtures/MED_ADMIN_Mailhot_V1.csv`, `tests/fixtures/DISPENSING_Mailhot_V1.csv` — fixtures with phantom RXNORM_CUI to correct

### Data profiles (ground truth for real column layout)
- `MED_ADMIN_values.csv`, `DISPENSING_values.csv`, `PRESCRIBING_values.csv`

</canonical_refs>

<code_context>
## Existing Code Insights

### Real extract column layout (ground truth)
- PRESCRIBING: has `RXNORM_CUI` (+RAW_RXNORM_CUI) — works today
- DISPENSING: `NDC` only; NO `RXNORM_CUI`; NO `RAW_DISPENSE_MED_NAME`
- MED_ADMIN: `MEDADMIN_CODE` + `MEDADMIN_TYPE` (RX≈71% / ND≈22% / NI/UN/OT rest); has `RAW_MEDADMIN_MED_NAME`; NO `RXNORM_CUI`

### Reusable patterns
- R/107 already implements the correct MED_ADMIN RX-typed match + PRESCRIBING baseline — lift its access logic
- R/27 has RxNav API lookup functions (`normalize_rxnorm_drug_name`, RxCUI lookups) — a crosswalk could extend this pattern with NDC→RxCUI
- `canonicalize_drug_name()` / `DRUG_NAME_ALIASES` in R/00_config.R for name normalization
- Probe-first / graceful-skip guard pattern (R/103, R/107)

### The trap to avoid
- Do NOT keep the `"RXNORM_CUI" %in% colnames(...)` guard as-is — it silently skips. Replace with real column access + a genuine absence guard.
- The fixtures MUST be updated or the smoke tests will keep passing against a layout that doesn't exist in production.

</code_context>

<specifics>
## Specific Ideas

- Prefer a cached/bundled NDC→RxNorm crosswalk (offline-capable, HiPerGator-friendly) over live API calls during the pipeline run; a one-time build step (like R/27's cached drug_name_lookup.rds) fits the project pattern.
- Consider a shared helper (e.g., `utils_treatment.R`) that returns normalized chemo-code hits per table so the 7 consumers stay consistent — reduces the chance of fixing 6 sites and missing 1.
- Runtime confirmation on HiPerGator expected (Windows executor has no Rscript; fixtures being corrected as part of this phase).

</specifics>

<deferred>
## Deferred Ideas

- Immunotherapy MED_ADMIN/DISPENSING contribution (chemo-only this phase)
- Full downstream regeneration of episodes/Gantt/timing outputs after the fix (separate pass)
- Broader audit of other tables for analogous code-column mismatches (e.g., PROCEDURES code systems)

</deferred>

---

*Phase: 122-med-admin-dispensing-gap-diagnostic-csv-gap-closure*
*Context gathered: 2026-07-14*
