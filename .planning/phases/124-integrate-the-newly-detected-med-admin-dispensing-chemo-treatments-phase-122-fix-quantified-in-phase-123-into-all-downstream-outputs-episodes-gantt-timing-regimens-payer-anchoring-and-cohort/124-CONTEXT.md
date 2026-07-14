# Phase 124: Integrate MED_ADMIN/DISPENSING Chemo Into All Downstream Outputs - Context

**Gathered:** 2026-07-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Regenerate and validate the **final downstream output products** so they reflect the
expanded chemo sources unlocked by the Phase 122 fix (MED_ADMIN `MEDADMIN_TYPE=='RX'`
matching + NDC→RxNorm crosswalk activating DISPENSING and MED_ADMIN-ND). Phase 122
already patched all 7 consumers to call the corrected `get_chemo_hits()`; Phase 123
quantified the **source-level** impact (+1,328 patients / +13,762 chemo dates, 89
patients with earlier first-chemo dates, 94 ingredients) but explicitly **deferred the
downstream regeneration**. This phase is that deferred pass.

**In scope:**
- Regenerate the core treatment outputs and confirm the new records propagate correctly
- Guarantee a single canonical drug spelling across ALL regenerated outputs, regardless of source
- Label the newly-surfaced DISPENSING/MED_ADMIN records correctly in Gantt (Code Type, Source Table, drug name)
- Produce an Amy-ready **output-level** before/after comparison proving the integration flowed
- Surface an audit list of drug names that have no canonical mapping

**Out of scope (deferred / separate):**
- Immunotherapy MED_ADMIN/DISPENSING contribution — chemo-only (R/26 immuno branches stay untouched)
- Correcting the `chemo_rxnorm` reference list — the 5 candidate gaps from Phase 123 D-10 are a separate follow-up
- PPTX decks (R/72/R/73) and waterfall/Sankey visualizations (R/70/R/71) — later regeneration pass
- Changing detection logic — Phase 122 owns that; this phase only regenerates products
</domain>

<decisions>
## Implementation Decisions

### Regeneration & validation deliverable
- **D-01:** Regenerate all in-scope downstream outputs (see D-10) with the expanded chemo
  sources. Detection is already wired via `get_chemo_hits()` (Phase 122) — this phase runs
  the products and confirms the new records flow through.
- **D-02:** Produce a NEW Amy-ready **output-level** before/after comparison report — old
  (pre-fix) output snapshot vs regenerated output — covering at least: # treatment episodes,
  # patients with any chemo episode, first-line regimen-label distribution, first-chemo
  timing shifts, and payer-anchor window changes. This is the phase's headline proof that
  the wired consumers actually changed the final products (Phase 123 was source-level; this
  is output-level).
- **D-03:** Baseline-capture mechanism (snapshot current outputs first vs reuse existing
  cached `.rds` snapshots) is **Claude's Discretion** — planner/researcher picks the cleanest
  approach and MUST verify any reused snapshot predates the Phase 122 fix.

### Gantt / new-record labeling
- **D-04:** **Code Type = true source code type.** Show the code as it actually arrived:
  `NDC` for DISPENSING and MED_ADMIN-ND records, `RXNORM` for MED_ADMIN-RX (and existing
  PRESCRIBING) records. Most faithful/auditable — a reviewer sees exactly what code matched.
- **D-05:** **Source Table** gains new distinct values `DISPENSING` and `MED_ADMIN` alongside
  the existing PRESCRIBING/PROCEDURES/DIAGNOSIS values.
- **D-06:** **Drug-name resolution = best-available fallback:** crosswalk RxCUI →
  `MEDICATION_LOOKUP` first, then `RAW_MEDADMIN_MED_NAME` free-text (MED_ADMIN carries it),
  then blank. The raw free-text is allowed as a *source* but MUST pass through
  `canonicalize_drug_name()` / `DRUG_NAME_ALIASES` before landing in any output — never
  displayed verbatim.

### Canonical drug-name normalization (cross-cutting — user requirement)
- **D-07:** In ALL regenerated outputs (not just Gantt), every drug must appear with a
  **single canonical spelling regardless of source**. A drug surfaced via NDC crosswalk or
  `RAW_MEDADMIN_MED_NAME` must collapse to the same canonical label PRESCRIBING already
  produces (e.g. "DOXORUBICIN HCL", "Doxorubicin", and a crosswalk-resolved doxorubicin all
  → one label). No raw, un-normalized source strings leak into any final output. Builds on
  Phase 114 (`MEDICATION_LOOKUP` centralization, `canonicalize_drug_name()`, 5-source
  precedence).
- **D-08:** **Unmapped-name handling:** when a raw/crosswalk name has no canonical match,
  retain the cleaned (uppercased/trimmed) string in the output so no data is lost, AND
  surface it in a dedicated **audit list of unmapped names** (Phase 114-style xlsx) for SME
  review. That list drives future alias/lookup extensions in a follow-up — this phase does
  not block on resolving every name.

### Regimen labeling
- **D-09:** **Regenerate regimen labels silently** — the aggregate first-line regimen-label
  distribution change appears in the D-02 before/after report; no per-patient regimen-change
  flag is required.
- **D-10-reg:** **All chemo sources treated equally as regimen input** — a chemo date is a
  chemo date regardless of source (DISPENSING/MED_ADMIN dates feed regimen labeling
  identically to PRESCRIBING). The regimen logic keys on drug identity + timing.

### Output scope
- **D-10:** **In scope (regenerate):** episodes (R/26), durations/timing (R/25), regimens
  (R/28, R/29), Gantt exports (R/52, R/101, R/104), payer anchoring (R/11), cohort
  treatment-flags (R/14), coverage (R/76), inventory (R/20), Tableau-ready tables (R/36),
  and drug-grouping tables (R/56, R/57).
- **D-11:** **Out of scope (later pass):** PPTX decks (R/72/R/73), waterfall (R/70), Sankey
  (R/71).

### Carried-forward constraints
- **D-12:** Chemo-only. Immunotherapy MED_ADMIN/DISPENSING branches (e.g. R/26 ~line 359,
  old `"RXNORM_CUI" %in% colnames` pattern) stay untouched by design.
- **D-13:** `chemo_rxnorm` reference list is NOT edited here (Phase 123 D-10 flagged 5
  candidate gaps — separate follow-up).
- **D-14:** Cohort **membership is unchanged** — chemo is a flag, not a filter (R/14 line
  362: "flags only, not exclusion"). Only treatment flags/counts/timing annotations on the
  fixed enrollment+HL cohort change.
- **D-15:** HIPAA suppression standard throughout (counts 1–10).

### Claude's Discretion
- Baseline-capture mechanism for the D-02 before/after report (D-03)
- DuckDB re-run orchestration and the HiPerGator runtime checkpoint (Windows executor has no
  Rscript — mirrors Phase 122/123 runtime-confirmation pattern)
- Exact report sheet layout/ordering and styling helpers to reuse (R/51 / TABLE pattern)
- Script number(s) / registration (R/39 vs SCRIPT_INDEX-only) and R/88 smoke sections
- Where the unmapped-name audit list lives (standalone xlsx vs a sheet in the D-02 report)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The fix + prior quantification (what we are integrating)
- `.planning/phases/122-med-admin-dispensing-gap-diagnostic-csv-gap-closure/122-CONTEXT.md` — fix decisions, real column layout, the 7 affected consumers
- `.planning/phases/122-med-admin-dispensing-gap-diagnostic-csv-gap-closure/122-VERIFICATION.md` — proven runtime numbers (+1,139 patients MED_ADMIN-RX; crosswalk 24,327 NDCs → 16,588 resolved / 126 chemo / 42 of 97 ingredients; all 7 consumers patched)
- `.planning/phases/123-.../123-CONTEXT.md` and `123-VERIFICATION.md` — source-level before/after (+1,328 patients / +13,762 dates; 89 earlier first-chemo; 94 ingredients); 5 candidate `chemo_rxnorm` gaps
- `R/109_med_admin_dispensing_fix_impact_audit.R` — the source-level diff + xlsx delivery pattern to mirror at the output level (D-02)
- Memory: `med-admin-dispensing-rxnorm-cui-mismatch` — finding summary

### Detection helper (already wired — do not re-fix)
- `R/utils/utils_treatment.R` — `get_chemo_hits()` / `load_ndc_crosswalk()` / `normalize_ndc()`
- `data/reference/ndc_rxnorm_crosswalk.rds` — NDC→RxCUI named vector (matched only)

### Outputs to regenerate (in-scope consumers)
- `R/26_treatment_episodes.R` — episodes → Gantt (chemo sources #5 DISPENSING, #6 MED_ADMIN already wired; immuno branch ~L359 untouched per D-12)
- `R/25_treatment_durations.R` — first/last chemo date, timing
- `R/28_episode_classification.R`, `R/29_first_line_and_death_analysis.R` — regimen labels (ABVD / BV+AVD / Nivo+AVD, adults 21+)
- `R/52_gantt_v2_export.R`, `R/101_gantt_lifespan_collapse.R`, `R/104_gantt_entire_history.R` — Gantt outputs (Phase 91 columns: Code Type, Source Table, medication name, F/S/E/N line labels)
- `R/11_treatment_payer.R` — treatment-anchored payer windows
- `R/14_build_cohort.R` — cohort treatment flags (D-14: annotation only)
- `R/76_treatment_source_coverage.R`, `R/20_treatment_inventory.R` — coverage + drug landscape
- `R/36_tableau_ready_tables.R` — TABLE-1 / TABLE-2 (Tableau-ready)
- `R/56_new_tables_from_groupings.R`, `R/57_drug_grouping_instances.R` — drug-grouping tables

### Drug-name normalization (D-06/D-07/D-08)
- `R/00_config.R` §3 — `MEDICATION_LOOKUP`, `DRUG_NAME_ALIASES`, `canonicalize_drug_name()`, `TREATMENT_CODES$chemo_rxnorm`, ID-not-PATID note
- `R/27_drug_name_resolution.R` — drug-name resolution + RxNav lookup pattern
- `R/79_drug_name_consistency_audit.R` — Phase 114 consistency audit (template for D-08 unmapped-name audit list)

### Delivery + convention
- `R/51_post_death_encounter_investigation.R`, `R/36_tableau_ready_tables.R` — styled multi-sheet xlsx + HIPAA suppression helpers (D-02, D-08)
- `R/39_run_all_investigations.R`, `R/88_smoke_test_comprehensive.R`, `R/SCRIPT_INDEX.md` — registration/test conventions
- Data profiles: `MED_ADMIN_values.csv`, `DISPENSING_values.csv`, `PRESCRIBING_values.csv`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets
- `get_chemo_hits()` already returns the corrected, source-consistent chemo hits — all in-scope consumers call it (Phase 122). This phase runs the products, it does not re-fix detection.
- `canonicalize_drug_name()` + `DRUG_NAME_ALIASES` + `MEDICATION_LOOKUP` (R/00_config.R) are the single normalization path for D-07; Phase 114 already centralized this.
- R/109 + R/51 give the styled multi-sheet xlsx + HIPAA suppression pattern for the D-02 report.
- Project already caches cohort + output snapshots as `.rds` (Phase 16) — candidate "before" baseline for D-02/D-03 (verify provenance).
- R/79 is the precedent for a drug-name audit xlsx (D-08).

### Established patterns
- Self-bootstrap DuckDB; HiPerGator-only runtime confirmed via checkpoint (Windows executor has no Rscript) — applies to any full re-run.
- Cohort scoping to the ~9,282 HL patients; chemo is a flag not a filter (R/14 L362).

### Traps to avoid
- Do NOT touch the immuno branches (R/26 ~L359 still uses the old `"RXNORM_CUI" %in% colnames` pattern) — chemo-only scope (D-12).
- Do NOT let raw `RAW_MEDADMIN_MED_NAME` strings reach outputs un-normalized (D-06/D-07).
- Do NOT edit `chemo_rxnorm` (D-13) — flag gaps only.
- The "before" baseline must genuinely predate the Phase 122 fix or the D-02 diff is meaningless.

</code_context>

<specifics>
## Specific Ideas

- Deliverable is Amy-ready — mirror the R/109 / R/51 styled multi-sheet xlsx style, with the headline output-level before/after numbers unmistakable.
- User's explicit requirement: "all drugs normalized to same spellings despite source" in the final data — one canonical label per drug across every regenerated output (D-07).
- Unmapped names go to an audit list so they can be reviewed and folded into the lookups later (D-08) — do not block regeneration on them.

</specifics>

<deferred>
## Deferred Ideas

- Immunotherapy MED_ADMIN/DISPENSING contribution — chemo-only scope
- Correcting `chemo_rxnorm` from Phase 123 D-10's 5 candidate gaps — separate follow-up
- PPTX (R/72/R/73), waterfall (R/70), Sankey (R/71) regeneration — later pass
- Extending drug-name aliases from the D-08 unmapped-name audit — follow-up after SME review
- Broader audit of other tables for analogous code-column mismatches

### Reviewed Todos (not folded)
None — no pending todos matched this phase.

</deferred>

---

*Phase: 124-integrate-the-newly-detected-med-admin-dispensing-chemo-treatments-phase-122-fix-quantified-in-phase-123-into-all-downstream-outputs-episodes-gantt-timing-regimens-payer-anchoring-and-cohort*
*Context gathered: 2026-07-14*
