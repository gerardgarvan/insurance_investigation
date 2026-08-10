---
phase: 139-zip-stability-imputation-occurrence-counts
verified: 2026-08-05T00:00:00Z
status: human_needed
score: 15/15 must-haves verified (structural/logic); runtime output on HiPerGator remains unverified
human_verification:
  - test: "Run `Rscript R/115_zip_stability_counts.R` on HiPerGator with LDS_ADDRESS_HISTORY_Mailhot_V1.csv and the ENCOUNTER table (via DuckDB) present."
    expected: "Script completes without error and writes output/zip_stability_counts_YYYYMMDD.xlsx with all 8 sheets (KEY, A_stability_patient, A_stability_summary, A_validation_curve, B_scenario_counts, B_direction_split, C_completeness, QC) populated with real data."
    why_human: "No LDS_ADDRESS_HISTORY CSV or DuckDB/ENCOUNTER connection is available in this Windows verification environment. All four plans' own SUMMARYs explicitly defer this to a future HiPerGator run; it cannot be exercised here."
  - test: "Review the C-02 reconciliation console message and QC-sheet cell after a real run."
    expected: "n_patients_no_zip5_ever (cohort-scoped) lands within 26 +/- 5. If it does not, per 139-CONTEXT.md's explicit instruction, investigation must occur before the workbook ships to Erin/Amy -- the UF_ORANGE QC-sheet flag and console '*** C-02 RECONCILIATION FAILURE ***' banner are the intended signal, and their real-data behavior can only be confirmed on HiPerGator."
    why_human: "Depends on real address-history and cohort data; the logic itself is unit-tested against synthetic fixtures (test 6/6, `compute_c02()`), but whether the REAL cohort reconciles to ~26 is an empirical question this environment cannot answer."
  - test: "Review A-06's validation_curve Overall row on a real run."
    expected: "pct_exact_zip9_match should read a plausible non-zero percentage (the F1 record-anchored fix's whole purpose), not 0.0 across every bin."
    why_human: "139-02's own Task 3 checkpoint was explicitly deferred by the user ('defer testing') pending a real HiPerGator run; the synthetic-fixture test (stable-patient exact-match == 100) passes, but real-data behavior is unconfirmed."
  - test: "Confirm block-group crosswalk tier stays gracefully degraded (or activates correctly) if data/reference/neighborhood_atlas_block_group_crosswalk.csv is ever added to the repo."
    expected: "If absent (current state): pct_block_group_match reads NA with 'not available' documented in the KEY/A_validation_curve subtitle. If present: real join produces a plausible non-near-zero match rate, not silently near-zero."
    why_human: "File does not exist in this repo as of verification; behavior when present cannot be exercised without a real crosswalk file and real ZIP9 values to join against."
---

# Phase 139: ZIP Stability & Imputation Occurrence Counts Verification Report

**Phase Goal:** Produce `R/115_zip_stability_counts.R`, a read-only investigation script that
measures ZIP9/ZIP5 stability at the individual level (Part A), counts occurrences of each
imputation scenario named in the 08/04 meeting notes (Part B), and reports cumulative
completeness (Part C) -- delivered as a UF-branded 8-sheet Excel workbook for Erin/Amy, per
`139-CONTEXT.md`'s decision IDs A-01..A-06, B-01..B-04, C-01..C-02 (no REQUIREMENTS.md IDs map
to this phase; the CONTEXT.md decision IDs serve as its acceptance criteria).

**Verified:** 2026-08-05
**Status:** human_needed (all automated/structural checks pass; the deliverable's actual
runtime output against real HiPerGator data is the only thing this environment cannot confirm)
**Re-verification:** No -- initial verification (no prior `139-VERIFICATION.md` existed)

## Goal Achievement

### Observable Truths

Derived from `139-CONTEXT.md`'s decision IDs (used as this phase's acceptance criteria, per
the task instructions, since no REQUIREMENTS.md IDs map to Phase 139) and each plan's
`must_haves.truths`.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `is_sentinel_zip5()` correctly flags 00000/99999/repeated-digit ZIP5s, passes NA through, and `get_zip9_at_date()` is left unmodified | VERIFIED | `R/utils/utils_address.R` lines 53-61; R/88 Section 15ad check "is_sentinel_zip5() defined ... exactly once" PASS; `get_zip9_at_date()` (lines 87-175) matches the Phase-137 original byte-for-byte in structure, only a new sibling function added before it |
| 2 | ZIP5 coalesced from raw ADDRESS_ZIP5 (preferred) with ZIP9-derived fallback, via exactly one `coalesce_zip5()` implementation (the "AMEND-01" gap, A-01/pitfall 2 precondition) | VERIFIED | `R/115` lines 83-91 (SECTION 1B); R/88 check "coalesce_zip5() defined in R/115, exactly once" PASS; reused (not re-derived) at line 1154 for the C-02 pre-filter comparison |
| 3 | Script stops loudly (not silent fallback) if raw ADDRESS_ZIP5 absent (FIX-04a) | VERIFIED | `R/115` lines 297-308: prints `names(addr_raw)` and `quit(status=0)` if `has_raw_zip5` is FALSE |
| 4 | `period_end_dt` preserves NA for open-ended records; `period_end_open`/`period_end_eff` computed separately (FIX-02) | VERIFIED | `R/115` lines 318-348; testthat fixture (test 5/6, "open-ended address record") asserts `has_direct_zip9 == TRUE`, `has_neither == FALSE` for an open-ended-covered encounter -- passes |
| 5 | Sentinel ZIP5/ZIP9, unparseable dates, out-of-study-period rows each dropped with a logged count (Pitfalls 2/3) | VERIFIED | `R/115` lines 353-390 (each drop counted and `message()`d before filtering); consolidated on QC sheet (`qc_tbl`, SECTION 13) |
| 6 | ZIP9/ZIP5 transitions computed on two independent NA-dropped-then-deduped sequences; NA is not a change (A-02, A-03) | VERIFIED | `R/115` lines 426-440 (`zip9_seq`/`zip5_seq`, `filter(!is.na(...))` before spell-collapse) |
| 7 | Exposure denominator (transitions per patient-year) computed from `period_end_eff` capped at `DATA_THROUGH`, with divide-by-zero guard (A-04, FIX-04b) | VERIFIED | `R/115` lines 519-536; `if_else(obs_span_years > 0, ..., NA_real_)` guard present |
| 8 | Gap-time distribution includes deciles (not just histogram) alongside median/IQR (A-05) | VERIFIED | `R/115` lines 575, 598-609 (`gap_days_deciles`, `gap_days_summary$deciles`); rendered into `A_stability_summary` sheet's `extra_tbl` (lines 1449-1463), not dropped in favor of the histogram alone |
| 9 | A-06 hold-out test operates on address-history RECORDS (not spells), producing a nonzero exact-match rate for unchanged addresses (F1 framing, FIX-01) | VERIFIED | `R/115` lines 93-125 (`build_validation_cases()`); synthetic-fixture test 1/6 ("stable patient") asserts `pct_exact_zip9_match == 100`, passes -- this is the specific assertion that would read 0 under the pre-patch spell-based design |
| 10 | Accuracy reported at exact-ZIP9 and same-ZIP5 tiers; block-group tier attempted only if crosswalk file found, degrades gracefully otherwise | VERIFIED | `R/115` lines 665-741 (probe + graceful degradation to `NA_real_` with documented status); crosswalk file confirmed absent in this repo, `block_group_tier_status <- "not available..."` |
| 11 | Every ENCOUNTER row classified into exactly one of already_has_zip9/S1/S2/S3/unresolvable (ordered); unordered eligible-for counts also reported, showing overlap (B-01, B-03) | VERIFIED | `R/115` lines 954-1061 (`scenario_assigned` ordered case_when; `unordered_encounter`/`unordered_patient` tables) |
| 12 | S1/S2 split backward/forward/either; S3 stays backward-only; direction split is new local logic, not a `get_zip9_at_date()` change (B-04) | VERIFIED | `R/115` lines 848-931 (`s1_elig`, `s2_elig` each with backward/forward/either; `s3_elig` backward-only) |
| 13 | Ordered "S3" column and unordered "S3-eligible" column documented as different quantities (FIX-04d) | VERIFIED | Console `NOTE` (lines 975-981), KEY-sheet field "Ordered vs unordered S3" (lines 1231, 1250-1257), `B_direction_split` sheet subtitle (lines 1494-1504) |
| 14 | Every count reported at both encounter and patient level with denominator named (B-02) | VERIFIED | `scenario_counts_encounter`/`scenario_counts_patient`, `unordered_encounter`/`unordered_patient`, `waterfall_encounter`/`waterfall_patient` all present with denominators stated in accompanying `message()`s and sheet subtitles |
| 15 | C-01 stepwise waterfall (both levels); C-02 reconciles cohort-scoped "no usable ZIP5 ever" against ~26 (+/-5), with pre-filter comparison and unmissable failure flag | VERIFIED | `R/115` lines 1079-1165 (waterfall), 1117-1163 (C-02 + pre-filter), 1535-1542 (UF_ORANGE xlsx flag on failure); synthetic-fixture test 6/6 (`compute_c02()`, cohort-absent patient) asserts `n_patients_no_zip5_ever == 2`, passes -- catches the pre-patch "invisible to group_by()" defect |
| 16 (runtime) | The workbook, when actually run on HiPerGator, produces plausible non-degenerate values (C-02 near 26, A-06 exact-match nonzero, 8 sheets populated) | **NEEDS HUMAN** | Cannot be exercised in this environment -- no LDS_ADDRESS_HISTORY CSV, no DuckDB/ENCOUNTER connection available. All four SUMMARYs explicitly and consistently scope this as deferred to a future HiPerGator run |

**Score:** 15/15 structurally/logically verifiable truths VERIFIED; 1 truth (real-data runtime
correctness) requires human verification on HiPerGator, as every plan's own SUMMARY already
anticipated.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `R/utils/utils_address.R` | `is_sentinel_zip5()` added, `get_zip9_at_date()` unchanged | VERIFIED | Parses cleanly (`Rscript -e "parse(...)"` confirmed); function present exactly once; `get_zip9_at_date()` present and structurally unchanged |
| `R/115_zip_stability_counts.R` | Full investigation script (SECTION 1B through 15, 8-sheet xlsx assembly) | VERIFIED | 1546 lines, parses cleanly end-to-end; all 4 plans' SECTION 1B functions present (`coalesce_zip5`, `build_validation_cases`, `aggregate_validation_curve`, `classify_encounter_zip`, `compute_c02`); Sections 2-15 all present per plan spec |
| `tests/testthat/test-115-validation-curve.R` | 6 behavioral fixtures (stable/mover/+4-only/single-record/open-ended/C-02) | VERIFIED | 21 tests across 6 `test_that()` blocks, **0 failures** (confirmed by direct execution: `library(testthat); test_file(...)`) |
| `R/39_run_all_investigations.R` | R/115 registered as final `investigation_scripts` entry | VERIFIED | Line 203, no trailing comma; R/114 (previous last entry) now has a trailing comma; NOT added to `expected_xlsx` (matches R/106's precedent, confirmed) |
| `R/88_smoke_test_comprehensive.R` | Section 15ad, 14 structural checks, SMOKE-139-01 footer | VERIFIED | Confirmed by direct execution: Section 15ad reports **14 PASS, 0 FAIL**; SMOKE-139-01 footer line present (line 5138) |
| `R/SCRIPT_INDEX.md` | R/115 row, updated script counts | VERIFIED | R/115 row present (line 161); Post-Renumber Investigations count is 16 (line 215); Total is 102 (line 218) |
| `output/zip_stability_counts_YYYYMMDD.xlsx` | The actual deliverable workbook | **NOT PRODUCED** (expected) | This is the runtime output of `Rscript R/115_zip_stability_counts.R` against real data -- correctly not present in this environment since no source CSV/DuckDB connection exists here. Not a gap; matches every SUMMARY's stated scope. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `R/115_zip_stability_counts.R` | `R/utils/utils_address.R` | `normalize_zip9()`/`normalize_zip5()`/`normalize_zip5_raw()`/`is_sentinel_zip5()` auto-loaded via `R/00_config.R` | WIRED | Called throughout `coalesce_zip5()` and SECTION 3's sentinel-filtering block |
| `R/115_zip_stability_counts.R` | `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` | Direct vroom read by path, probe-gated | WIRED (structurally) | `file.exists(addr_path)` gate present; graceful `quit(status=0)` confirmed to fire correctly in this environment (file absent here) |
| `addr_coal$period_end_eff` | `classify_encounter_zip()`'s interval filter | Column contract carried from Plan 01 through Plan 03 | WIRED | `period_end_eff` used (not `period_end_dt`) in the interval filter at line 164; open-ended fixture test confirms correct classification |
| `R/115_zip_stability_counts.R` SECTION 1B | `tests/testthat/test-115-validation-curve.R` | `sys.source()` into a fresh environment before the probe gate | WIRED | Confirmed by direct execution -- all 6 fixtures capture and exercise SECTION 1B functions successfully, 0 failures |
| `R/utils/utils_treatment.R` | `R/115_zip_stability_counts.R` | `get_hl_patient_ids()` cohort pattern | WIRED (structurally) | Defensive `source()` call present (line 795); function call present (line 796); real execution requires DuckDB/DIAGNOSIS table, not available here |
| `R/115_zip_stability_counts.R` | `output/zip_stability_counts_YYYYMMDD.xlsx` | `wb_workbook()` + `wb_save()` | WIRED (structurally) | `wb_save(wb, OUTPUT_XLSX)` present at line 1544; new workbook (not `wb_load()`), correctly distinct from R/114's append pattern |
| `R/39_run_all_investigations.R` | `R/115_zip_stability_counts.R` | `investigation_scripts` vector entry, `run_script()` | WIRED | Confirmed present and correctly ordered |
| `compute_c02()` | `COHORT_IDS` (139-03) | Direct function argument, same script-level variable | WIRED | `compute_c02(COHORT_IDS, addr_coal)` at line 1121; no redefinition of `COHORT_IDS` between Plan 03 and Plan 04's Part C code |

### Requirements Coverage

No REQUIREMENTS.md IDs map to Phase 139 (per task framing: "standalone investigation
deliverable"). Cross-referencing plan-frontmatter `requirements:` decision IDs against
`139-CONTEXT.md`'s full decision-ID list instead:

| Decision ID | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| A-01 | 139-01 | Two change types (ZIP9 vs +4-only), counted separately | SATISFIED | `n_zip9_transitions`, `n_plus4_only_transitions` both computed (SECTION 4) |
| A-02 | 139-01 | NA is not a change | SATISFIED | NA dropped before spell-collapse (lines 427, 435) |
| A-03 | 139-01 | Deduplicate before counting (spell collapse) | SATISFIED | `is_new_spell` logic (lines 430, 438) |
| A-04 | 139-01 | Exposure denominator, not bare count | SATISFIED | SECTION 5, `zip9_transitions_per_patient_year` with divide-by-zero guard |
| A-05 | 139-01 | Time between changes: median/IQR/deciles | SATISFIED | `gap_days_summary` incl. `deciles` (SECTION 6) |
| A-06 | 139-02 | Carry-forward validation curve, 3 accuracy tiers, gap-binned | SATISFIED | `build_validation_cases()`/`aggregate_validation_curve()`, block-group tier attempted-and-gracefully-degraded |
| B-01 | 139-03 | Four scenarios (S1-S4) verbatim from notes, S3 flagged unresolved | SATISFIED | `scenario_assigned` levels, explicit "S3 resolution still pending" message (line 1058) |
| B-02 | 139-03 | Count at both levels, explicit denominators | SATISFIED | All Part B/C tables report both levels with named denominators |
| B-03 | 139-03 | Mutually exclusive + ordered, plus unordered "eligible for" | SATISFIED | Ordered `scenario_assigned` + unordered `unordered_encounter`/`unordered_patient` |
| B-04 | 139-03 | Direction (backward/forward/either) reported separately | SATISFIED | `s1_backward`/`s1_forward`/`s1_either`, same for S2 |
| C-01 | 139-04 | Waterfall, not single number, both levels | SATISFIED | `waterfall_encounter`/`waterfall_patient` |
| C-02 | 139-04 | Reconcile against ~26-patient control total | SATISFIED | `compute_c02()`, cohort-scoped, pre-filter comparison, unmissable failure flag (console + xlsx) |

All 12 decision IDs from `139-CONTEXT.md` (A-01..A-06, B-01..B-04, C-01..C-02) are accounted
for in `R/115_zip_stability_counts.R` -- none orphaned, none missing.

### Anti-Patterns Found

None found at blocker or warning severity. Scanned `R/115_zip_stability_counts.R`,
`R/utils/utils_address.R`, and `tests/testthat/test-115-validation-curve.R` for
TODO/FIXME/placeholder/stub patterns, empty handlers, and console-log-only implementations --
none present. Every function in SECTION 1B (`coalesce_zip5`, `build_validation_cases`,
`aggregate_validation_curve`, `classify_encounter_zip`, `compute_c02`) has a real, substantive
body backed by a passing behavioral test, not a structural-grep-only check. The two pre-existing
`R/88` failures (`source_coverage_analysis.csv`, `get_chemo_hits('MED_ADMIN')`) are confirmed
unrelated to Phase 139 via `git diff --stat` (additive-only change to R/88) and are logged in
`deferred-items.md`, not silently hidden.

### Human Verification Required

### 1. Real HiPerGator execution of R/115_zip_stability_counts.R

**Test:** Run `Rscript R/115_zip_stability_counts.R` on HiPerGator with
`LDS_ADDRESS_HISTORY_Mailhot_V1.csv` and the ENCOUNTER table (via DuckDB) present.
**Expected:** Script completes without error; `output/zip_stability_counts_YYYYMMDD.xlsx` is
written with all 8 sheets populated.
**Why human:** No source CSV or DuckDB connection exists in this Windows verification
environment -- this is the explicitly-scoped-out runtime step every one of the 4 plan SUMMARYs
names as its own remaining open item.

### 2. C-02 reconciliation against the real cohort

**Test:** After a real run, read the console `*** C-02 RECONCILIATION FAILURE ***` banner (or
its absence) and the QC sheet's C-02 row/cell color.
**Expected:** `n_patients_no_zip5_ever` (cohort-scoped) lands within 26 +/- 5. If not,
investigate before the workbook ships to Erin/Amy, per `139-CONTEXT.md`'s explicit instruction.
**Why human:** This is an empirical question about the real cohort's data quality, not a logic
question -- the logic itself is unit-tested and passes (test 6/6).

### 3. A-06 validation curve real-data plausibility

**Test:** After a real run, inspect `validation_curve`'s Overall row / the `A_validation_curve`
sheet.
**Expected:** `pct_exact_zip9_match` reads a plausible nonzero percentage (not 0.0 across every
bin -- the exact defect FIX-01 exists to prevent).
**Why human:** 139-02's own human-verify checkpoint was explicitly deferred by the user
("defer testing") pending exactly this real-data run; the synthetic-fixture proof is complete,
but real-data confirmation remains open by design.

### 4. Block-group crosswalk tier (contingent, low priority)

**Test:** If `data/reference/neighborhood_atlas_block_group_crosswalk.csv` is ever added to the
repo, re-run and confirm the block-group tier activates with a plausible (non-near-zero) match
rate rather than silently degrading.
**Expected:** Either "not available" (current state, correctly handled) or a real,
non-near-zero-match accuracy figure.
**Why human:** File does not exist in this repo; the degrade-gracefully path is exercised, but
the activate-correctly path has no real file to test against.

### Gaps Summary

No structural, logical, or wiring gaps were found. Every one of the 12 CONTEXT.md decision IDs
(A-01 through C-02) has corresponding, substantive, tested code in
`R/115_zip_stability_counts.R`; every plan's `must_haves` (truths, artifacts, key_links) checks
out against the actual codebase, not just against SUMMARY claims. All parse checks pass, all 21
testthat expectations pass (0 failures, independently re-run during this verification, not just
trusted from the SUMMARYs), and R/88's Section 15ad shows 14/14 PASS (independently re-run).
Registration in R/39, R/88, and R/SCRIPT_INDEX.md is all confirmed correct and consistent.

The only unresolved item is inherent to the phase's own nature and was never hidden: this is a
read-only investigation script whose real output (the actual xlsx, the actual C-02 reconciliation
number, the actual A-06 accuracy curve) can only be produced by running it against real
LDS_ADDRESS_HISTORY and ENCOUNTER data on HiPerGator -- infrastructure this verification
environment does not have. All four plan SUMMARYs state this identically and consistently as
their own remaining open item, not as something this phase's execution skipped. This is
reported as `human_needed`, not `gaps_found`, because nothing is missing, stubbed, or unwired in
the code itself -- the gap is purely in this environment's inability to run R against real
PCORNet data.

---
*Verified: 2026-08-05*
*Verifier: Claude (gsd-verifier)*
