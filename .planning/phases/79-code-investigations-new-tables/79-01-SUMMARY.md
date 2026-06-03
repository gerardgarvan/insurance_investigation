---
phase: 79-code-investigations-new-tables
plan: 01
subsystem: code-investigations
tags: [code-quality, data-validation, graph-analysis, encounter-profiling]
dependency_graph:
  requires: [CODE-01, CODE-02, QUAL-01]
  provides: [sct-0362-investigation-report, replaced-by-verification-report]
  affects: [code-verification, treatment-code-integrity]
tech_stack:
  added: [igraph]
  patterns: [graph-based-cycle-detection, encounter-level-profiling, multi-sheet-xlsx-reporting]
key_files:
  created:
    - R/54_investigate_sct_0362.R
    - R/55_verify_replaced_by_codes.R
  modified: []
decisions:
  - id: D-05
    summary: Pull full encounter profiles (all procedures + diagnoses) for 0362 encounters
    rationale: Comprehensive context needed to determine if 0362 represents true SCT procedures
  - id: D-06
    summary: Three-sheet output format for investigation reports
    rationale: Patient Summary + Encounter Detail + Summary Statistics provides layered insight
  - id: D-07
    summary: Automated recommendation based on overlap rate (>80%, <30%, 30-80%)
    rationale: Data-driven thresholds convert analysis into actionable guidance
  - id: D-08
    summary: Inspect xlsx sheets dynamically for replaced-by column structure
    rationale: Handles varied column naming (replaced_by, next, old_code, new_code)
  - id: D-09
    summary: Pairwise verification against DRUG_GROUPINGS + TREATMENT_CODES
    rationale: Validates both code existence and category consistency
  - id: D-10
    summary: Graph-based cycle detection using igraph::is_dag()
    rationale: Mathematical proof of DAG property prevents infinite replacement loops
  - id: D-11
    summary: PASS/FAIL/MISSING statuses with overall verdict
    rationale: Clear actionable outcomes (PASS, NEEDS REVIEW with specific issues)
metrics:
  duration_seconds: 180
  duration_human: "3 minutes"
  tasks_completed: 2
  files_created: 2
  files_modified: 0
  commits: 2
  completed_date: "2026-06-03"
---

# Phase 79 Plan 01: Code Investigations (SCT 0362 & Replaced-by Verification)

**One-liner:** Two investigation scripts: R/54 profiles SCT code 0362 across 90 patients with encounter-level standard code cross-reference and automated recommendation; R/55 verifies replaced-by code mappings with pairwise validation and igraph-based cycle detection.

## Summary

Created two code investigation scripts following v2.0 quality standards (documentation headers, section structure, checkmate assertions, openxlsx2 multi-sheet output).

**R/54_investigate_sct_0362.R** resolves CODE-02's open question about revenue code 0362 provenance. The script:
- Queries DuckDB PROCEDURES for all encounters with revenue code 0362 (~90 patients expected)
- Pulls full encounter profiles: ALL procedures and diagnoses for each 0362 encounter
- Cross-references against standard SCT codes (CPT 38204-38241, HCPCS S2140/S2142/S2150, revenue 0815)
- Calculates overlap rate: percentage of 0362 patients who also have standard SCT codes in the same encounters
- Produces 3-sheet xlsx: Patient Summary (per-patient counts), Encounter Detail (all codes per encounter), Summary Statistics (overlap rate + automated recommendation)
- Automated recommendation logic: >80% = CONFIRMED SCT, <30% = LIKELY CODING ARTIFACT, 30-80% = MANUAL REVIEW NEEDED

**R/55_verify_replaced_by_codes.R** implements CODE-01's validation of replaced-by code mappings. The script:
- Loads all_codes_resolved_next_tables_v2.1.xlsx and dynamically inspects all sheets for replaced-by columns
- Handles varied column naming conventions (replaced_by, next, old_code, new_code)
- Builds comprehensive code list from TREATMENT_CODES vectors + DRUG_GROUPINGS keys
- Performs pairwise verification: checks both old and new codes exist in code lists and remain in same category
- Uses igraph for graph analysis:
  - Cycle detection via is_dag() — ensures no circular replacement chains
  - Long chain detection — identifies replacement chains >3 steps using shortest path analysis
- Produces 3-sheet xlsx: Pairwise Verification (PASS/FAIL/MISSING per code pair), Chain Analysis (cycles + long chains), Summary Statistics (overall verdict)
- Automated verdict: PASS (valid DAG + no category mismatches), NEEDS REVIEW (cycles detected or category failures)

Both scripts follow D-05 through D-11 decision framework, implementing encounter-level profiling, multi-sheet xlsx output, and automated recommendations based on data-driven thresholds.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | R/54 SCT Code 0362 Investigation | c56025a | R/54_investigate_sct_0362.R |
| 2 | R/55 Replaced-by Code Verification | 2a12cd6 | R/55_verify_replaced_by_codes.R |

## Deviations from Plan

None — plan executed exactly as written. Both scripts follow v2.0 standards with complete section structure, documentation headers, checkmate assertions, and multi-sheet xlsx output patterns.

## Key Decisions Made

**D-05: Full encounter profiles**
- Decision: Pull ALL procedures and diagnoses for 0362 encounters (not just 0362 code rows)
- Rationale: Comprehensive encounter context required to determine whether 0362 co-occurs with standard SCT codes (38230-38241, S2140/S2142/S2150, 0815)
- Impact: Enables robust overlap rate calculation across ~90 patients

**D-06: Three-sheet output format**
- Decision: Patient Summary + Encounter Detail + Summary Statistics for both investigation reports
- Rationale: Layered insight — high-level metrics (sheet 3) + patient aggregates (sheet 1) + encounter granularity (sheet 2)
- Pattern: Reusable template for future investigation scripts

**D-07: Automated recommendations**
- Decision: Data-driven thresholds (>80% confirmed, <30% artifact, 30-80% manual review)
- Rationale: Converts raw analysis into actionable guidance for CODE-02 resolution
- Output: Clear recommendation in Summary Statistics sheet + console diagnostics

**D-08: Dynamic xlsx inspection**
- Decision: Inspect all sheets and column names dynamically rather than hardcoding sheet/column references
- Rationale: Handles varied xlsx structures (column naming conventions: replaced_by vs next vs old_code/new_code)
- Robustness: Script works across xlsx versions without modification

**D-09: Comprehensive pairwise verification**
- Decision: Validate against both DRUG_GROUPINGS (454 codes) and all TREATMENT_CODES vectors
- Rationale: Catches codes missing from either lookup source, ensures replaced-by pairs stay within same treatment category
- Statuses: PASS (both codes valid, same category), FAIL (category mismatch), MISSING (code not found)

**D-10: Graph-based cycle detection**
- Decision: Use igraph::is_dag() for mathematical proof of DAG property
- Rationale: Replaced-by chains must be acyclic to prevent infinite resolution loops
- Added dependency: igraph package (lightweight, well-maintained, standard R graph library)

**D-11: Actionable verdict structure**
- Decision: Overall verdict (PASS vs NEEDS REVIEW) with specific failure modes documented
- Rationale: Enables CODE-01 closure decision — if PASS, replaced-by mappings are valid; if NEEDS REVIEW, specific issues flagged (cycles, category mismatches, long chains)
- Output format: Summary Statistics sheet contains single-row verdict + detailed failure breakdowns

## Technical Details

**R/54 implementation:**
- Section 1: Setup (suppressPackageStartupMessages, source R/00_config.R + utils)
- Section 2: Identify 0362 encounters via DuckDB query (PX == "0362", PX_TYPE == "RE")
- Section 3: Pull full encounter profiles (semi_join on ID + ENCOUNTERID)
- Section 4: Detect standard SCT codes (CPT 38204-38241, HCPCS S2140/S2142/S2150, revenue 0815)
- Section 5: Build output tables (patient summary, encounter detail, summary statistics)
- Section 6: Write multi-sheet xlsx via openxlsx2
- Section 7: Console summary (overlap rate, recommendation)

**R/55 implementation:**
- Section 1: Setup (load igraph, openxlsx2, checkmate)
- Section 2: Load xlsx, inspect sheets, identify replaced-by columns dynamically
- Section 3: Pairwise verification (code existence, category matching, PASS/FAIL/MISSING statuses)
- Section 4: Graph analysis (igraph cycle detection, long chain identification via distances())
- Section 5: Build output tables (pairwise verification, chain analysis, summary statistics)
- Section 6: Write multi-sheet xlsx
- Section 7: Console summary (status counts, DAG check, overall verdict)

**Validation:**
- Both scripts use checkmate::assert_file_exists for input validation
- Both scripts use assert_df_valid from utils_assertions for post-query validation
- R/54 validates PROCEDURES and DIAGNOSIS table structure before processing
- R/55 validates xlsx file existence and handles missing replaced-by mappings gracefully

**igraph dependency:**
- New dependency added for Phase 79 (not in prior renv.lock)
- Justification: Graph cycle detection is mathematically robust; alternative (manual traversal) would be error-prone
- Package maturity: igraph 2.1.3+ (widely used, CRAN stable)
- Added to tech_stack.added in frontmatter for tracking

## Known Issues

None. Both scripts are structurally complete and ready for execution once DuckDB connection is available on HiPerGator.

**Future execution notes:**
- R/54 assumes ~90 patients with 0362 code (per Open Question 1 in STATE.md); actual count TBD on first run
- R/55 handles missing replaced-by mappings gracefully (produces minimal report if no mappings found)
- Both scripts require DuckDB connection via open_pcornet_con() — execution depends on HiPerGator access

## Verification

**Structural checks (completed):**
- [x] Both files exist in R/ directory
- [x] Documentation headers present with Purpose, Inputs, Outputs, Dependencies, Requirements
- [x] suppressPackageStartupMessages blocks present
- [x] Section headers (SECTION 1: through SECTION 7:) present
- [x] R/54 references TREATMENT_CODES$sct_cpt and queries PROCEDURES table
- [x] R/55 references DRUG_GROUPINGS and uses igraph for cycle detection
- [x] Both use wb_workbook() with three add_worksheet() calls
- [x] Both use checkmate assertions (assert_file_exists, assert_df_valid)

**CODE-02 resolution path:**
- R/54 produces overlap_rate_pct metric: % of 0362 patients with standard SCT codes
- Automated recommendation provides actionable closure: CONFIRMED SCT vs LIKELY ARTIFACT vs MANUAL REVIEW
- Decision: If >80% overlap, include 0362 as valid SCT code; if <30%, exclude; if 30-80%, manual patient chart review needed

**CODE-01 validation path:**
- R/55 produces overall_verdict: PASS (valid DAG + no failures) or NEEDS REVIEW (specific issues documented)
- Pairwise Verification sheet lists all FAIL/MISSING statuses for manual correction
- Chain Analysis sheet documents cycles and long chains (>3 steps) requiring attention
- Decision: If PASS, replaced-by mappings validated; if NEEDS REVIEW, fix documented issues before code resolution pipeline use

## Files Created

**R/54_investigate_sct_0362.R** (286 lines)
- Purpose: Investigate SCT code 0362 encounter-level data quality
- Inputs: DuckDB PROCEDURES + DIAGNOSIS tables, R/00_config.R (TREATMENT_CODES)
- Outputs: output/sct_0362_investigation.xlsx (3 sheets)
- Requirements: CODE-02, QUAL-01
- Key functions: get_pcornet_table, semi_join for encounter profiling, case_when for recommendation logic

**R/55_verify_replaced_by_codes.R** (375 lines)
- Purpose: Verify replaced-by code mappings with pairwise validation and cycle detection
- Inputs: all_codes_resolved_next_tables_v2.1.xlsx, R/00_config.R (DRUG_GROUPINGS, TREATMENT_CODES)
- Outputs: output/replaced_by_verification.xlsx (3 sheets)
- Requirements: CODE-01, QUAL-01
- Key functions: wb_load for xlsx inspection, graph_from_data_frame, is_dag, distances for chain analysis

## Next Steps

**Immediate (within Phase 79):**
1. Execute Phase 79 Plan 02: Create 2 new tables using template and groupings from all_codes_resolved_next_tables.xlsx
2. Update smoke test (R/88) to include R/54 and R/55 in script inventory

**CODE-02 closure:**
1. Run R/54 on HiPerGator with DuckDB connection
2. Review overlap_rate_pct and automated recommendation
3. If >80%: Add 0362 to TREATMENT_CODES$sct_revenue with inline comment documenting validation
4. If <30%: Document as coding artifact in KNOWN_ISSUES.md, exclude from SCT detection
5. If 30-80%: Perform manual chart review on sample of 0362 patients without standard SCT codes

**CODE-01 closure:**
1. Run R/55 to validate replaced-by mappings
2. If PASS: Document validation in REQUIREMENTS.md, mark CODE-01 complete
3. If NEEDS REVIEW: Fix documented failures (category mismatches, missing codes) in xlsx source, re-run R/55 until PASS
4. Long chains >3 steps: Review for unnecessary indirection (e.g., A->B->C->D could be A->D direct)

## Self-Check

**Files created:**
```bash
# Check R/54
[ -f "C:\Users\Owner\Documents\insurance_investigation\R\54_investigate_sct_0362.R" ] && echo "FOUND: R/54" || echo "MISSING: R/54"

# Check R/55
[ -f "C:\Users\Owner\Documents\insurance_investigation\R\55_verify_replaced_by_codes.R" ] && echo "FOUND: R/55" || echo "MISSING: R/55"
```

**Commits exist:**
```bash
# Check Task 1 commit
git log --oneline --all | grep -q "c56025a" && echo "FOUND: c56025a (R/54)" || echo "MISSING: c56025a"

# Check Task 2 commit
git log --oneline --all | grep -q "2a12cd6" && echo "FOUND: 2a12cd6 (R/55)" || echo "MISSING: 2a12cd6"
```

**Self-check result:** PASSED (both files created, both commits exist)

---

*Duration: 3 minutes | Completed: 2026-06-03*
