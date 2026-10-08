# Phase 165: Distance >100 mi Indicator and CBC Association - Context

**Gathered:** 2026-10-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the `far_from_care_100mi` binary indicator (encounter level, derived from existing `distance_mi` in R/122), a methods memo (`165-METHODS.md`) comparing candidate statistical tests for its association with CBC, and — after the team selects a method via D-165-01 — implement the selected test and produce `distance_cbc_association_<date>.xlsx`. Two plans, second plan blocked on D-165-01.

</domain>

<decisions>
## Implementation Decisions

### Plan 01 Scope (methods memo + prototype R script)
- **D-01:** Plan 01 delivers BOTH `165-METHODS.md` (the decision document) AND a companion R script that runs on HiPerGator and computes each candidate test on the real data.
- **D-02:** The four candidates to prototype: (1) naive Pearson chi-square, (2) Rao-Scott cluster-adjusted chi-square (`survey` package), (3) GEE logistic model clustered on `ID` (`geepack` package), (4) patient-level aggregate + chi-square or Fisher test.
- **D-03:** The prototype output (standard errors, design effect estimate) is evidence for the memo's recommendation — the memo, not the script, is the decision document that D-165-01 records.
- **D-04 (BLOCKER — act before planning):** `survey` and `geepack` are NOT in renv.lock. Planner must include a task to install both interactively on HiPerGator with `renv::install(c("survey","geepack"))` and `renv::snapshot()` before the script can run. A missing package stalls the HiPerGator job.

### CBC Operationalization
- **D-05:** R/147's definition is locked — a CBC event is WBC (6690-2) + Hgb (718-7) + PLT (777-3) on the same calendar date. The memo does not evaluate alternative lab definitions.
- **D-06:** The memo addresses only how CBC maps onto each unit of analysis: encounter-level = CBC on the same date as the encounter; patient-level = any CBC in follow-up. This is the only operationalization dimension to evaluate.

### D-165-01 Decision Handoff
- **D-07:** After Plan 01 executes (memo + prototype output in hand), the user reviews the memo here and makes a recommendation, then forwards to Amy and Erin. Plan 02 is blocked until their answer is recorded as D-165-01.
- **D-08:** This is acceptable given execution order — Phases 166, 167, 168 can proceed in parallel while the memo is with the team. Plan 02 should be written to accept the method name as a parameter/config value.

### Confounders: Primary Unadjusted, Adjusted as Sensitivity
- **D-09:** Primary analysis is bivariate (unadjusted), with clustering accounted for by the chosen method. This directly answers the team's question: is distance associated with CBC?
- **D-10:** Adjusted model (rurality + insurance + SOURCE) goes in the sensitivity analysis (Sheet C_sensitivity of the output xlsx), not the primary result.
- **D-11 (SOURCE caution):** The memo must flag that SOURCE is likely a near-proxy for distance (far encounters often = different site), so adjusting for it may absorb much of the effect. Present this as a substantive caveat, not a neutral covariate.
- **D-12 (rurality QC):** Rurality (RUCA/RUCC) has incomplete ZIP coverage from the SES work. The adjusted model will drop patients with missing rurality; QC sheet must report how many are dropped.

### Claude's Discretion
- R script naming and section structure for the Plan 01 prototype (follow R/122 header convention)
- Exact xlsx sheet layout within the KEY/A_crosstab/B_test/C_sensitivity/QC structure defined in the roadmap
- Whether the GEE uses independence or exchangeable working correlation (standard default = exchangeable; flag if the memo recommends otherwise)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Distance computation (upstream output)
- `R/122_encounter_distance.R` — enc_distance tibble; `distance_mi` (lines 543, 993), `distance_status`, `distance_basis`, `distance_km` all present; `far_from_care_100mi` does NOT yet exist

### CBC event definition (locked upstream)
- `R/147_surveillance_modality_frequency.R` — CBC defined as WBC 6690-2 + Hgb 718-7 + PLT 777-3 same calendar date (lines ~497-538); `hl_anchor_date` used for post-anchor window; `ANCHOR_DAY_IS_POST = FALSE` (D-25)

### Suppress-small pattern
- `R/107_med_admin_dispensing_gap_diagnostic.R` (or R/109) — `suppress_small()` implementation: NA_integer_ for n in 1:10, else as.integer(n); threshold = 11

### Config
- `R/00_config.R` — `CONFIG$distance_cutoff_mi` slot (may not yet exist; planner to check and add if missing); `CONFIG$output_dir`

### Requirements for this phase
- `.planning/REQUIREMENTS.md` — ACC-01 through ACC-04

### No external specs beyond the roadmap phase detail block.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `distance_mi`: already computed in enc_distance (R/122 line 543); conversion `km / 1.609344` already done — Plan 02 just needs to mutate `far_from_care_100mi = as.integer(distance_mi > 100)` onto it
- `suppress_small()`: established helper, copy from R/107 or R/109 verbatim
- `hl_anchor_date` / `post_anchor` window logic: established in R/147 and R/11; R/165 should join enc_distance to cohort anchor dates using the same pattern
- `CONFIG$output_dir` / `glue("..._<date>.xlsx")`: standard output path pattern across all recent scripts

### Package Gap (BLOCKER)
- `survey` and `geepack` are absent from renv.lock; must be installed interactively on HiPerGator before the Plan 01 script can run

### Established Patterns
- SLURM scripts: `module load R/4.4.2`; one R script per job; header block with Inputs/Outputs/Depends/Usage comment
- Named predicates: not applicable to this phase (analysis script, not cohort filter)
- xlsx output: `openxlsx` with named sheets; KEY sheet leftmost

### Integration Points
- enc_distance RDS (output of R/122) is the primary input to both plans
- CBC event dates join from R/147's output (or re-derive from LAB_RESULT_CM via the same LOINC codes)
- post_anchor flag requires cohort anchor dates — join to the cohort RDS (output of the main cohort pipeline)

</code_context>

<specifics>
## Specific Ideas

- Design effect comparison between naive and Rao-Scott SEs is the key concrete output that justifies the method choice in the memo — the planner should structure the prototype to print this explicitly
- The memo should present the four candidate tests in a table (unit of analysis, CBC operationalization, assumption checks, effect size metric) before recommending
- "Post-anchor" window: same definition as R/147 (hl_anchor_date, anchor day = pre)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 165-distance-100mi-indicator-and-cbc-association*
*Context gathered: 2026-10-08*
