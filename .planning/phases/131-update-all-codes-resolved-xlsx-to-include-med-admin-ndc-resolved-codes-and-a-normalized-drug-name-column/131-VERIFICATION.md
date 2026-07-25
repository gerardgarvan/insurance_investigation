---
phase: 131-update-all-codes-resolved-xlsx-to-include-med-admin-ndc-resolved-codes-and-a-normalized-drug-name-column
verified: 2026-07-22T20:33:15Z
status: human_needed
score: 5/5 must-haves verified (structurally); runtime regeneration on HiPerGator still outstanding
human_verification:
  - test: "Regenerate all_codes_resolved.xlsx (and the 5 per-type siblings) on HiPerGator with real DuckDB/openxlsx2 access, then run Rscript R/88_smoke_test_comprehensive.R"
    expected: "All 12 Section 15x checks PASS; chemotherapy/supportive_care/immunotherapy/sct sheets show a populated Medication column (never blank); radiation_codes_resolved.xlsx keeps its original 6-column shape with no Medication column; SCT shows Medication only for RXNORM rows; codes only reachable via MED_ADMIN (NDC) or DISPENSING (NDC) appear with non-zero Records/Patients; Source Table values distinguish MED_ADMIN (RX)/MED_ADMIN (NDC)/DISPENSING (NDC)/PRESCRIBING"
    why_human: "Dev environment lacks Rscript/openxlsx2/duckdb/here -- cannot execute R/50 or R/88 to confirm runtime behavior against real PCORnet data. All verification here is structural (grep/read-based)."
  - test: "Confirm collaborators who consume all_codes_resolved.xlsx are notified that Records-column values for existing single-source codes with multiple same-day rows will decrease relative to prior runs"
    expected: "Communication sent alongside the next regeneration, per 131-02-SUMMARY.md's explicit flag"
    why_human: "Organizational/communication step, not a code check."
---

# Phase 131: Update all_codes_resolved.xlsx to include MED_ADMIN NDC-resolved codes and a normalized drug-name column Verification Report

**Phase Goal:** Update R/50_all_codes_resolved.R (producer of all_codes_resolved.xlsx and its 5 per-type sibling files) so that (1) its MED_ADMIN/DISPENSING code detection reflects the Phase 122 NDC-crosswalk fix across all 4 RXNORM vector categories (chemo, sct, immunotherapy, supportive_care), and (2) a normalized "Medication" name column is added to Chemotherapy, Supportive Care, Immunotherapy, and SCT sheets (not Radiation), sourced primarily from MEDICATION_LOOKUP with a heuristic fallback normalizer. Both the combined all_codes_resolved.xlsx and the 5 per-type files must stay in sync.

**Verified:** 2026-07-22T20:33:15Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Codes only reachable via MED_ADMIN `MEDADMIN_TYPE == 'ND'` or DISPENSING now contribute counts, across all 4 RXNORM vector categories | ✓ VERIFIED (structural) | `get_chemo_hits()` tags `MED_ADMIN (NDC)`/`DISPENSING (NDC)` sub-paths (R/utils/utils_treatment.R:257,281,224); R/50 Section 3's RXNORM loop (`R/50_all_codes_resolved.R:323-368`) calls `get_chemo_hits()` for PRESCRIBING/MED_ADMIN/DISPENSING for every vector selected via `filter(code_type == "RXNORM")` — generically, not chemo-only. Runtime confirmation (real non-zero counts) needs HiPerGator. |
| 2 | Source Table column reflects the real per-code detected source (e.g. "MED_ADMIN (NDC)") instead of the static per-vector string | ✓ VERIFIED (structural) | `source_labels` aggregation (R/50:358-360) + `coalesce(dyn_source_table, static_source_table)` (R/50:458) confirmed present and reaches the output row (select() at line 462 explicitly retains `source_table`, no reassignment in the final mutate). |
| 3 | Records/Patients counts are not inflated by double-counting administrations reachable via multiple source paths | ✓ VERIFIED (structural) | Separate `distinct(ID, treatment_date, code, source)` (source labeling) vs. `distinct(ID, treatment_date, code)` (counting) at R/50:348,352 — matches the documented Pitfall-2 fix. Behavioral change (Records may decrease vs. prior runs) is explicitly flagged in 131-02-SUMMARY.md as required. |
| 4 | Chemotherapy/Supportive Care/Immunotherapy/SCT sheets get a populated Medication column (never blank for a code that should have one); SCT gated to RXNORM rows; Radiation has no Medication column at all | ✓ VERIFIED (structural) | `all_codes_df$medication` case_when (R/50:481-486) gates Radiation and SCT-non-RXNORM to NA, else curated `MEDICATION_LOOKUP` or `fallback_normalize_medication()` (never-blank guarantee confirmed in R/00_config.R:2659-2745). `resolved_xlsx_layout()` (R/50:612-624) omits the Medication column entirely (6 cols, not 7-with-blanks) for Radiation. |
| 5 | Both the combined all_codes_resolved.xlsx and the 5 per-type files stay in sync (no divergence) | ✓ VERIFIED (structural) | Both `write_resolved_xlsx()` (R/50:630) and the combined-workbook per-category loop (R/50:837) call the identical `resolved_xlsx_layout(category)` helper — confirmed exactly 2 call sites via grep, both driven by the same `all_codes_df`/`df_cat` data. No independent hard-coded header/column-count logic remains in either writer. |

**Score:** 5/5 truths structurally verified. Runtime confirmation of actual generated xlsx content is deferred to HiPerGator (dev environment lacks Rscript/openxlsx2/duckdb — consistent with the project's established dual-environment convention used throughout Phases 116-130).

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/00_config.R` | MEDICATION_LOOKUP col G wiring + `fallback_normalize_medication()` | ✓ VERIFIED | Lines 2496-2556 (`med_col` selector, col 7 for Supportive Care when `ncol(sheet_df) >= 7`, else col 3); lines 2659-2745 (`fallback_normalize_medication` 3-tier priority: multi-ingredient passthrough / HCPCS strip / RxNorm-STR strip, with never-blank guarantee confirmed by reading the full function body). |
| `R/utils/utils_treatment.R` | `get_chemo_hits()` additive `return_source` param | ✓ VERIFIED | Lines 181-297: `return_source = FALSE` default; PRESCRIBING/DISPENSING/MED_ADMIN(RX)/MED_ADMIN(ND) branches each tag `source` before `bind_rows()`; `keep_cols` gating (line 287-290) ensures byte-identical 3-column output when the param is omitted, matching the 6-existing-caller non-regression requirement. |
| `R/50_all_codes_resolved.R` | RXNORM loop generalization, dynamic source_table, medication column, shared xlsx layout | ✓ VERIFIED | Confirmed line-by-line: Section 3 loop (210-368), Section 4 assembly + medication case_when (413-491), `resolved_xlsx_layout()` (612-624) and both call sites (630, 837), both `write_df`/`write_df_cat` conditional Medication field construction (665-686, 869-890). |
| `R/88_smoke_test_comprehensive.R` | Section 15x (10+ checks) + SMOKE-131-01 summary line | ✓ VERIFIED | Section 15x at line 3017, 12 `check()` calls (3040-3098), correctly positioned after Section 15w / before out-of-order Section 15g. `SMOKE-131-01` summary line present at line 4680. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| R/50 Section 3 RXNORM loop | `get_chemo_hits(table, codes, ndc_crosswalk, return_source = TRUE)` | 3 calls per vector (PRESCRIBING/MED_ADMIN/DISPENSING) | ✓ WIRED | Confirmed at R/50:333-335; `ndc_crosswalk <- load_ndc_crosswalk()` loaded once (line 321), not per-vector. |
| R/50 Section 3 source aggregation | R/50 Section 4 `all_codes_df$source_table` | `count_results` carries `source_table`; Section 4 join renames to `dyn_source_table`, coalesces over static value, survives the intervening `select()` | ✓ WIRED | `count_results` initial tibble includes `source_table = character()` (line 224); Section 4's `select(code, description, records, patients, source_table)` (line 462) explicitly retains it before the final mutate (463-470) which does NOT reassign it — matches the exact defect-avoidance called out in the plan/patch. |
| `write_resolved_xlsx()` | combined-workbook per-category loop | both consume `resolved_xlsx_layout(category)` | ✓ WIRED | 2 literal call sites confirmed (`layout <- resolved_xlsx_layout(category)` at lines 630 and 837) — not duplicated header/width logic. |
| `all_codes_df$medication` | `MEDICATION_LOOKUP` / `fallback_normalize_medication()` | `case_when(... code %in% names(MEDICATION_LOOKUP) ~ ..., TRUE ~ fallback_normalize_medication(description, code_type))` | ✓ WIRED | R/50:479-487, single call site, matches 131-03 plan's interface contract exactly. |
| `get_chemo_hits()`'s 6 non-R/50 callers | unaffected by `return_source` | additive-parameter/default-FALSE pattern | ✓ WIRED (non-regression) | `return_source` default FALSE; `keep_cols` logic only appends `"source"` when TRUE; roxygen comment explicitly documents R/10,R/11,R/25,R/26,R/76,R/109 as unaffected. Files_modified for 131-02 lists only `R/utils/utils_treatment.R` + `R/50_all_codes_resolved.R` — the 6 caller files were not touched by this phase (confirmed no other files appear in any plan's `files_modified`). |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| MEDXLSX-01 | 131-01 | MEDICATION_LOOKUP col G wiring | ✓ SATISFIED | R/00_config.R:2508-2520 |
| MEDXLSX-02 | 131-01 | fallback_normalize_medication() heuristic normalizer | ✓ SATISFIED | R/00_config.R:2659-2745 |
| MEDXLSX-03 | 131-02 | get_chemo_hits() additive return_source tagging | ✓ SATISFIED | R/utils/utils_treatment.R:181-297 |
| MEDXLSX-04 | 131-02 | R/50 RXNORM loop generalized across 4 vectors + all 3 tables | ✓ SATISFIED | R/50_all_codes_resolved.R:323-368 |
| MEDXLSX-05 | 131-02 | Dynamic per-code source_table + de-duplication | ✓ SATISFIED | R/50_all_codes_resolved.R:340-368, 437-470 |
| MEDXLSX-06 | 131-03 | all_codes_df$medication column computed with correct gating | ✓ SATISFIED | R/50_all_codes_resolved.R:479-487 |
| MEDXLSX-07 | 131-03 | Shared resolved_xlsx_layout() used by both writers | ✓ SATISFIED | R/50_all_codes_resolved.R:612-624, 630, 837 |
| SMOKE-131-01 | 131-04 | R/88 Section 15x structural validation + summary line | ✓ SATISFIED | R/88_smoke_test_comprehensive.R:3017-3098, 4680 |

**Known, pre-existing documentation gap (not a phase failure):** `.planning/REQUIREMENTS.md` has no Phase 131 section, so these ad-hoc IDs (`MEDXLSX-01..07`, `SMOKE-131-01`) cannot be cross-referenced there or checked off via `gsd-tools requirements mark-complete`. This gap is already explicitly documented in STATE.md's "Known Blockers" section (line 86) and in 131-04-SUMMARY.md's "Next Phase Readiness" section. CONTEXT.md and the ROADMAP.md Phase 131 entry are the actual source of truth for this phase's locked decisions and requirement definitions, consistent with the phase predating formal requirement tracking for this milestone. No orphaned requirements were found beyond this documented gap — every ID referenced in plan frontmatter maps to verified implementation evidence above.

### Anti-Patterns Found

None. Scanned all 4 modified files (`R/00_config.R` lines 2496-2746, `R/utils/utils_treatment.R` full file, `R/50_all_codes_resolved.R` full file, `R/88_smoke_test_comprehensive.R` lines 3017-3099) for TODO/FIXME/XXX/HACK/PLACEHOLDER/"not implemented"/"coming soon" markers — zero matches. No stub functions, no empty-return implementations, no console-log-only handlers.

### Human Verification Required

#### 1. HiPerGator runtime regeneration and R/88 execution

**Test:** Regenerate `all_codes_resolved.xlsx` (and the 5 per-type siblings) on HiPerGator with real DuckDB/openxlsx2/PCORnet-data access, then run `Rscript R/88_smoke_test_comprehensive.R`.
**Expected:** All 12 Section 15x checks PASS; chemotherapy/supportive_care/immunotherapy/sct sheets show a populated Medication column (never blank for a code that should have one); `radiation_codes_resolved.xlsx` keeps its original 6-column shape with no Medication column at all; SCT sheet shows Medication populated only for RXNORM rows and blank for DRG/ICD-10-PCS rows; codes only reachable via `MED_ADMIN (NDC)` or `DISPENSING (NDC)` appear with non-zero Records/Patients counts; Source Table values correctly distinguish `MED_ADMIN (RX)`/`MED_ADMIN (NDC)`/`DISPENSING (NDC)`/`PRESCRIBING`.
**Why human:** This dev environment lacks Rscript, openxlsx2, duckdb, and here — none of R/50 or R/88 can actually be executed to confirm runtime behavior against real PCORnet data. Every check performed in this verification is structural (source-code reading and grep), which is the maximum verification depth achievable here and matches the project's established dual-environment convention used throughout Phases 116-130.

#### 2. Collaborator communication about the Records-column behavioral change

**Test:** Confirm collaborators who consume `all_codes_resolved.xlsx` are notified that Records-column values for existing single-source codes with multiple same-day rows will decrease relative to prior runs, as a direct (intended) result of the new `(ID, treatment_date, code)` de-duplication.
**Expected:** Communication sent alongside the next regeneration/distribution of the workbook.
**Why human:** Organizational/communication step outside the codebase; cannot be verified programmatically. The code-level flag itself (131-02-SUMMARY.md's required disclosure) IS present and was verified — see truth #3 above.

### Gaps Summary

No code-level gaps found. All 5 derived observable truths, all 4 required artifacts, and all 5 key links pass structural verification against the actual current source of `R/00_config.R`, `R/utils/utils_treatment.R`, `R/50_all_codes_resolved.R`, and `R/88_smoke_test_comprehensive.R` — not just the plan/summary documents' descriptions of intended changes. All 10 task commits referenced across the 4 SUMMARY.md files were confirmed to exist in git history. All 4 SUMMARY.md files report full task completion; the single documented deviation (131-02's defensive guard for the all-three-`get_chemo_hits()`-NULL edge case) was auto-fixed, is purely additive/defensive, and does not change intended behavior in the expected production case. The mandated Records-column behavioral-change disclosure is present verbatim in 131-02-SUMMARY.md. Both xlsx-writer code paths were confirmed to derive from the single `resolved_xlsx_layout(category)` helper at exactly 2 call sites, with no duplicated header/column-count logic remaining. R/88 Section 15x's 12 checks were read in full and confirmed to be non-tautological (each tests a real, specific string/pattern in the modified source files that could plausibly fail if the corresponding implementation were absent or altered — none use always-true conditions).

The phase's only outstanding item is runtime confirmation on HiPerGator (regenerating the actual xlsx files and running R/88 with real R packages installed), which cannot be performed in this dev environment and is consistent with how every prior phase in this project's 116-130 series was verified. This is flagged for human/HiPerGator follow-up rather than treated as a code gap, since the underlying implementation is structurally complete and sound.

---

*Verified: 2026-07-22T20:33:15Z*
*Verifier: Claude (gsd-verifier)*
