# Requirements: v3.4 R Pipeline Code Review Remediation

**Defined:** 2026-07-23
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.
**Source:** `R_pipeline_code_review.md` (full-pipeline review, reviewed 2026-07-23, ~115 pipeline scripts + 14 utils modules)

## Milestone Goal

Fix the crash-causing and wrong-published-number defects surfaced by the code review, and standardize the 8 recurring cross-cutting bug patterns at the shared-helper layer so they stop recurring script-by-script. Scope is locked to the review's 8 numbered critical/high findings, its 8 cross-cutting patterns (A-H), and its 2 flagged loose ends — matching the review's own "Suggested fix order" stages 1-4. The ~80 additional per-script Low/Med findings are explicitly deferred (see Future Requirements).

## v3.4 Requirements

### Crash Fixes (CRASH)

- [x] **CRASH-01**: `R/74`, `R/81`, `R/82`, `R/83`, `R/84`, `R/85` run without aborting on the stray bare `n` token left in by an editor (three occurrences in `84`/`85`)
- [x] **CRASH-02**: `R/84` uses `purrr::walk()` (or an attached `library(purrr)`) instead of an unqualified `walk()` call, so its triggered branch no longer crashes with `could not find function "walk"`

### Published-Number Correctness (DATA)

- [x] **DATA-01**: `R/28_episode_classification.R` matches `treatment_type == "SCT"` (not `"Stem Cell Transplant"`) so `sct_dates`, `is_sct_conditioning_context`, and `days_to_nearest_sct` are no longer permanently empty/FALSE/NA
- [x] **DATA-02**: `R/46_cancer_summary_table.R`'s `total_records` (including the TOTAL row) reflects true code-level record counts, not per-code records multiplied by patient count
- [x] **DATA-03**: `R/47_cancer_summary_refined.R`'s `first_hl_dx_date` is computed by filtering sentinel dates (`DX_DATE >= 1910-01-01`, matching `48`/`49`'s `SENTINEL_CUTOFF`) **before** taking `min()`, not nullified post-hoc on exact-`1900` only — so a patient with both a real HL date and a sentinel keeps their true anchor instead of losing it
- [x] **DATA-04**: `R/48_cancer_summary_post_hl.R` excludes HL anchor codes (C81 + 201.x) from its post-HL "second cancer" set, consistent with `R/49`, so HL recurrence is not conflated with new malignancy
- [x] **DATA-05**: `R/49_cancer_summary_pre_post.R`'s category/total `both_count` reflects the true pre∩post **patient** intersection at category grain (not a per-code sum), so `pre + post − both` reconciles
- [x] **DATA-06**: `R/67`→`R/68` and `R/95`→`R/96`'s same-week detail files keep each `(admit_date, source)` pair correctly bound together after the `pmin`/`pmax` reordering, so the downstream `(ID, date, source)` join back to ENCOUNTER no longer misclassifies pairs into Distinct/Partial or undercounts near-duplicates
- [x] **DATA-07**: `R/101_gantt_lifespan_collapse.R`'s `age_at_episode` reflects the row at the group's earliest `episode_start`, not whichever row happened to be first in input order

### Data Integrity (INGEST)

- [x] **INGEST-01**: `R/03_duckdb_ingest.R` aborts (via `stop()`, discarding the `.tmp` database) when any table fails to write instead of silently promoting a database missing tables, asserts `setequal(ingested, expected)` before promotion, and its summary reports the real per-table pass/fail counts instead of a hardcoded `"N/N passed"`

### Documentation Tooling (DOCS)

- [x] **DOCS-01**: `R/89_generate_reference_manual.R`'s `parse_script_header()` correctly anchors `header_end` to the field block's closing bar, so the generated manual captures each script's actual Purpose/Inputs/Outputs/Dependencies/Requirements instead of "Not documented" for every script

### Cross-Cutting Pattern Standardization (PATTERN)

- [ ] **PATTERN-A**: Record/patient totals in `R/23`, `R/33` (CODE-03), `R/43`/`R/44` (TOTAL rows), `R/50` (grand total), `R/91`, `R/100` (Sheet 1) are computed by de-duplicating to the intended grain (`n_distinct(ID)` / distinct code) before totaling, not by summing per-code counts across codes a patient/record may appear under more than once (`R/46`'s instance is DATA-02 above, already covered)
- [ ] **PATTERN-B**: A single shared code-normalization convention (strip **all** dots + `toupper()` + dotted/undotted union) is applied consistently across `R/13_survivorship_encounters.R`, `R/42_build_code_descriptions.R`, `utils_cancer.R` (`classify_codes`/`is_cancer_code`), and `utils_doi.R` (`classify_doi_codes()`) — eliminating the dotted-only vs. dotted+undotted vs. case-sensitive drift documented in the review
- [ ] **PATTERN-C**: Neoplasm filters in `R/40`, `R/43`, `R/44`, `R/46` use `is_cancer_code()` (or an equivalent `^C|^D[0-4]` pattern) instead of the over-inclusive `^[CD]`, so D50-D89 anemias/cytopenias/neutropenia no longer land in the "Unclassified" neoplasm bucket
- [ ] **PATTERN-D**: External-API calls in `R/21_investigate_unmatched.R`, `R/27`, `R/105`, `R/108` classify transient errors (429/503/504/timeout/500/502) separately from a genuine "not found," retry transient errors (`R/21` currently has no retry at all), and never persist a transient failure as a permanent cache miss / dropped crosswalk entry
- [ ] **PATTERN-E**: Tests/validators that currently cannot fail are corrected: `R/81` no longer coerces types before `waldo::compare()`; `R/82`/`R/83`'s "≥3× speedup on 3 of 5 scripts" check actually benchmarks all 5 scripts (not 1); `R/88` separates skip counters from pass counters and its `cause_of_death` "drop" check fails when the value is genuinely absent (not present); `R/96_validate_payer_dt`'s FLM-override fixture starts from a non-Medicaid state so the override is provably exercised; `R/98_validate_r28_migration` compares against an independently-generated baseline, not a copy of its own output
- [ ] **PATTERN-F**: In-place `R/00_config.R` rewriting in `R/21`, `R/22`, `R/50`, `R/98` either moves to a data-driven config source or hardens its regex/quote-handling so newly-discovered codes are never silently dropped when a parse/write attempt fails
- [x] **PATTERN-G**: Missing NA/sentinel/impossible-date guards are added: `R/53_death_date_validation.R` gets a death-before-birth check (flags negative `age_at_death`); `R/14`, `R/31`, `R/93` use NA-safe `min_or_na`/`max_or_na` helpers (or equivalent guards) consistently instead of producing silent `Inf` durations, unguarded `episode_start`, or dropped NA treatment flags
- [ ] **PATTERN-H**: Grain-mislabeled columns are renamed or re-aggregated to match their documented grain: `R/56`'s `encounter_count` (actually episode count), `R/57_explore_dx_deduplication`'s same mislabel, `R/62`'s `date_tier_detail` (patient×type×episode×date, not one-row-per-patient-per-date), `R/67`'s `n_total_encounters` (double-counts dates used in both roles)

### Confirm Loose Ends (CONFIRM)

- [ ] **CONFIRM-01**: Locate where `suppress_small()`, `clean_multi_value()`, and `union_field()` are actually defined and confirm they load correctly (not found in any of the 14 `utils_*.R` modules during the review; `clean_multi_value` is referenced as "reused from R/52")
- [ ] **CONFIRM-02**: Reconcile `CONFIG$analysis$date_range_max` (2025-03-31) against the actual data extract cutoff (20250915) and correct the bound if valid Apr-Sep 2025 encounters/deaths are currently being flagged out-of-range and dropped by `R/01`'s date validation

## Future Requirements

Deferred to a later milestone. Tracked but not in the current roadmap — the ~80 per-script Low/Med findings cataloged by area in the review.

### Per-Script Findings Backlog (REVIEW-FUT)

- **REVIEW-FUT-01**: Foundation/config low findings (`R/00`-`R/03`) — case-sensitive source pattern, `supportive_care_*` name-split mis-bucket, stale count comments, invalid/placeholder codes, dual `14x` payer prefix fallthrough, `02`'s header/table mismatch, `03`'s no-DB-window swap
- **REVIEW-FUT-02**: Cohort layer (`R/10`-`R/14`) — dead-code predicates, lazy-`tbl_dbi` local-join gap in `R/10`/`R/11`, `R/14` non-NA-safe min/max
- **REVIEW-FUT-03**: Treatment analysis (`R/20`-`R/29`) low/med findings not covered by DATA-01 — `R/20` CAR-T prefix-vs-exact mismatch, `R/21` brittle NLM JSON parse + 773xx fallthrough, `R/22` RXNORM_CUI silent-swallow + checkpoint-inhibitor chemo/immuno priority + fan-out join, `R/25` 90-day episode-splitting window-from-start bug + missing Proton Therapy color, `R/26` source_hints/triggering_codes misalignment, `R/28` temporal tie-break preference, `R/29` NA-age dropout
- **REVIEW-FUT-04**: Investigations (`R/30`-`R/39`) — `R/33` record-vs-patient CODE-03 count, `R/34` dual-code population-mismatch denominator, `R/35` empty-frame sequence footgun, `R/37` merged-title guard, `R/38` manifest self-listing, `R/39` Stage 2/4 ordering bug (High — `101`/`104` run before their producer `52`)
- **REVIEW-FUT-05**: Cancer site (`R/40`-`R/53`) findings not covered by DATA-03..05 — `R/40` ICD-O-3-through-ICD-10-CM classifier divergence, `R/42` dotted-key mismatch, `R/50` additive-with-overlap grand total, `R/52_gantt_v2_export` comma-splitting corruption, `R/53` no-1900-birth-sentinel + `DEATH_SOURCE`/date mismatch, `R/55` off-by-one chain count
- **REVIEW-FUT-06**: Codes/death/drug groupings (`R/56`-`R/59`) findings not covered by PATTERN-H — `R/57_drug_grouping_instances` pivot_wider crash risk, `R/58_co_administration_analysis` code-identity-vs-drug-identity spurious pairs + directional double-count, `R/59` no-encounter-as-death-is-last miscount
- **REVIEW-FUT-07**: Payer & overlap (`R/60`-`R/69`, `R/76`) — `R/60` alphabetical tie-break, `R/63` `ID$` regex also dropping `_VALID` columns, `R/64`/`R/65` unvalidated-table assertion mismatch, `R/66` magrittr dot gotcha, `R/68` same-date self-join over-weighting, `R/76` exact-day-vs-±7-day tolerance inconsistency
- **REVIEW-FUT-08**: Outputs & viz (`R/70`-`R/79`) — `R/71` ≤10-patient mislabel, `R/72_generate_pptx` triple Med finding (NA→"Missing" ordering hides true unassigned rate; slide-14 date-equality complement miscount; CWD write + missing ggplot2 library()), `R/73` stale "phase24" labels, `R/74` output-filename mismatch, `R/75` encounter-ratio-vs-percent column conflation + unmapped-payer silent drop, `R/79` overlapping summary buckets
- **REVIEW-FUT-09**: Tests & smoke tests (`R/80`-`R/89`) findings not covered by CRASH/PATTERN-E — `R/80` header/implementation mismatch + partial-sample predicates, `R/87` broken-source() false positives + loose decade thresholds, `test_phase78_human.R` unsafe `source()` of `R/88`
- **REVIEW-FUT-10**: Ad-hoc diagnostics (`R/90`-`R/99`) — `R/90` silent column skip + inconsistent threshold, `R/91` grand-total-attributed-to-single-source + boolean-vs-count bug, `R/92` unreachable branch, `R/93` NA-treatment-flag dropout (also PATTERN-G), `R/95`/`R/96` AV+TH scope confirmation, `R/97_payer_code_frequency` join-key asymmetry + numeric-coercion leading-zero loss, `R/98_radiation_cpt_audit` config-rewrite trailing-comma bug (also PATTERN-F) + nuclear-medicine gap, `R/99_claude_diagnostics` unclosed sink()
- **REVIEW-FUT-11**: Post-renumber investigations (`R/100`-`R/112`) findings not covered by CONFIRM-02 — `R/100` ZIP de-dup fan-out risk, `R/102` DEATH_CAUSE-absent silent proxy switch, `R/103` coverage-denominator mismatch, `R/104` doc/behavior mismatch, `R/105` hardcoded-column-G append + transient-outage cache poisoning (also PATTERN-D), `R/106` different-row-subset ZIP9/ZIP5 misclassification + missing `suppress_small()` on Sheet 4, `R/107` PRESCRIBING-absent overcount, `R/108` transient-vs-genuine-miss crosswalk loss (also PATTERN-D) + `normalize_ndc()` mis-padding, `R/109` constant-flagged-patient-count reconciliation bug, `R/110` `.` pronoun / `.data[[...]]` fallback-branch errors, `R/112` uncoerced `treatment_date` type
- **REVIEW-FUT-12**: Utility modules (`utils_*.R`) findings not covered by PATTERN-B/CONFIRM-01 — `utils_dates.R` Excel-serial catch-all + `ymd()`-first US-date pre-emption + 2-digit-year cutoff, `utils_icd.R` strict-equality `DX_TYPE` gating, `utils_payer.R` dual-eligible ordering + sentinel-list drift + `TIER_MAPPING` list/dt divergence, `utils_duckdb.R` eager-vs-lazy return-type footgun, `utils_treatment.R` `normalize_ndc()` mis-padding + no match-rate logging, `utils_doi.R` no-uppercase gate/classifier inconsistency + V/E-code digit-partition trap, `utils_xlsx_lookups.R` dead duplicate-code `stop()`, `utils_snapshot.R` non-atomic RDS write + inconsistent root paths

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| The ~80 per-script Low/Med findings not in Future Requirements' backlog list | Tracked in REVIEW-FUT-01..12 above, not individually re-derived here — the backlog groupings are the scope boundary |
| Re-running the full pipeline on HiPerGator to re-verify fixed outputs | Each fix is verified structurally (code-level) in this milestone; a consolidated HiPerGator re-run is a v3.3-style deferred verification step, tracked separately once this milestone's fixes are complete |
| Rewriting `R/00_config.R`'s in-place mutation to a fully data-driven (CSV/RDS) config source | PATTERN-F requires hardening the existing regex/guard approach at minimum; a full architectural move to data-driven config is a larger design decision left for a future milestone if the hardened guard proves insufficient |
| Auditing scripts the review marked "clean" | Not revisited — the review's "clean" verdicts are trusted as-is for this milestone |

## Traceability

Which phases cover which requirements. Populated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CRASH-01 | Phase 132 | Complete |
| CRASH-02 | Phase 132 | Complete |
| DATA-01 | Phase 133 | Complete |
| DATA-02 | Phase 133 | Complete |
| DATA-03 | Phase 133 | Complete |
| DATA-04 | Phase 133 | Complete |
| DATA-05 | Phase 133 | Complete |
| DATA-06 | Phase 133 | Complete |
| DATA-07 | Phase 133 | Complete |
| INGEST-01 | Phase 134 | Complete |
| DOCS-01 | Phase 133 | Complete |
| PATTERN-A | Phase 135 | Pending |
| PATTERN-B | Phase 135 | Pending |
| PATTERN-C | Phase 135 | Pending |
| PATTERN-D | Phase 135 | Pending |
| PATTERN-E | Phase 134 | Pending |
| PATTERN-F | Phase 135 | Pending |
| PATTERN-G | Phase 135 | Complete |
| PATTERN-H | Phase 135 | Pending |
| CONFIRM-01 | Phase 136 | Pending |
| CONFIRM-02 | Phase 136 | Pending |

**Coverage:**
- v3.4 requirements: 21 total (2 CRASH + 7 DATA + 1 INGEST + 1 DOCS + 8 PATTERN + 2 CONFIRM)
- Mapped to phases: 21 (roadmap complete)
- Unmapped: 0 ✓

**Phase breakdown** (follows the review's own "Suggested fix order" 5 stages):
- Phase 132 (Crash Fixes): CRASH-01, CRASH-02 — stage 1
- Phase 133 (Critical Correctness Fixes): DATA-01..07, DOCS-01 — stage 2 (wrong published numbers + the content-empty reference manual, findings #2/#4/#5/#6/#7/#8)
- Phase 134 (Ingest Integrity and Honest Tests): INGEST-01, PATTERN-E — stage 3
- Phase 135 (Shared-Helper Standardization): PATTERN-A/B/C/D/F/G/H — stage 4
- Phase 136 (Confirm Loose Ends): CONFIRM-01, CONFIRM-02 — stage 5

---
*Requirements defined: 2026-07-23*
*Last updated: 2026-07-24 after roadmap creation — all 21 requirements mapped to Phases 132-136*
