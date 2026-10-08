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
- **D-04 (BLOCKER — act before planning):** `survey` and `geepack` are NOT in renv.lock. Planner must include a task to install both interactively on HiPerGator under `module load R/4.5` with `renv::install(c("survey","geepack"))` and `renv::snapshot()` before the script can run, then copy renv.lock back to the local repo. A missing package stalls the HiPerGator job.

### CBC Operationalization
- **D-05:** R/147's definition is locked — a CBC event is WBC (6690-2) + Hgb (718-7) + PLT (777-3) on the same calendar date. The memo does not evaluate alternative lab definitions.
- **D-06:** The memo addresses only how CBC maps onto each unit of analysis: encounter-level = CBC dated within the encounter (ADMIT_DATE to DISCHARGE_DATE; ADMIT_DATE only when no discharge date); patient-level = any CBC in the window. This is the only operationalization dimension to evaluate.
- **D-06a:** CBC events must cover the whole record (pre- and post-anchor). If R/147's saved events are filtered to the surveillance window, re-derive from LAB_RESULT_CM with the same LOINCs and date column.

### D-165-01 Decision Handoff
- **D-07:** After Plan 01 executes (memo + prototype output in hand), the user reviews the memo here and makes a recommendation, then forwards to Amy and Erin. Plan 02 is blocked until their answer is recorded as D-165-01.
- **D-08:** This is acceptable given execution order — Phases 166, 167, 168 can proceed in parallel while the memo is with the team. Plan 02 should be written to accept the method name as a parameter/config value.

### Confounders: Primary Unadjusted, Adjusted as Sensitivity
- **D-09:** Primary analysis is bivariate (unadjusted), with clustering accounted for by the chosen method. This directly answers the team's question: is distance associated with CBC?
- **D-10:** Adjusted model (rurality + insurance + SOURCE) goes in the sensitivity analysis (Sheet C_sensitivity of the output xlsx), not the primary result.
- **D-11 (SOURCE caution):** The memo must flag that SOURCE is likely a near-proxy for distance (far encounters often = different site), so adjusting for it may absorb much of the effect. Present this as a substantive caveat, not a neutral covariate.
- **D-12 (rurality QC):** Rurality (RUCA/RUCC) has incomplete ZIP coverage from the SES work. The adjusted model will drop patients with missing rurality; QC sheet must report how many are dropped.

### Windows, Cutoff, Script Numbers
- **D-13:** Every analysis (all four prototype candidates; Plan 02 primary and sensitivity) is run for two windows reported side by side: whole record, and post-anchor (ADMIT_DATE > hl_anchor_date; anchor day = pre, as R/147). Settled at milestone level 2026-10-08.
- **D-14:** The cutoff lives in `CONFIG$far_from_care_cutoff_mi` (= 100), the single source for Phase 165 scripts. `CONFIG$distance_cutoff_mi` is left to Phase 155 with its NA-default semantics. R/122 is not modified.
- **D-15:** Analysis sets are built by shared helpers in `R/utils/utils_distance_cbc.R`, used by both the prototype and the production script so they cannot drift.
- **D-16:** Script numbers follow the R/ sequence, not the phase number: R/163 (prototype) and R/164 (production), subject to the Plan 01 discovery check against SCRIPT_INDEX.
- **D-17:** Sensitivity model covariates are rurality (R/116 encounter-level output), payer, and SOURCE — all three.

### Claude's Discretion
- R script naming and section structure for the Plan 01 prototype (follow R/122 header convention)
- Exact xlsx sheet layout within the KEY/A_crosstab/B_test/C_sensitivity/QC structure defined in the roadmap
- Whether the GEE uses independence or exchangeable working correlation (default exchangeable via `CONFIG$distance_gee_corstr`; fall back to independence if exchangeable is infeasible at this cluster size, and say so in the memo)

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
- `suppress_small()`: the R/107 version is scalar; use a vectorized form for tables, and show suppressed cells as "<11" with complementary suppression of row/column totals
- `hl_anchor_date` / `post_anchor` window logic: established in R/147; Phase 165 scripts reuse R/147's anchor source
- `CONFIG$output_dir` / `glue("..._<date>.xlsx")`: standard output path pattern across all recent scripts

### Package Gap (BLOCKER)
- `survey` and `geepack` are absent from renv.lock; must be installed interactively on HiPerGator before the Plan 01 script can run

### Established Patterns
- SLURM scripts: `module load R/4.5` (the project renv library is built for R/4.5; plain `module load R` picks R/4.6, and there is no R/4.4.2 module); one R script per job; header block with Inputs/Outputs/Depends/Usage comment
- Output filenames use `YYYYMMDD` dates (e.g., `zip_stability_counts_20260806.xlsx`)
- Code is edited in the local Windows repo and synced to HiPerGator; no Rscript locally (brace-balance proxy only)
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
