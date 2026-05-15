---
phase: 46-treatment-code-cross-reference-and-triggering-codes
verified: 2026-05-15T18:00:00Z
status: passed
score: 9/9 must-haves verified
re_verification: false
---

# Phase 46: Treatment Code Cross-Reference & Triggering Codes — Verification Report

**Phase Goal:** Users can see which codes are in the reference doc but not in config (and vice versa), and each episode row shows which code(s) triggered it
**Verified:** 2026-05-15T18:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | User can see which codes are in the reference documents but not in TREATMENT_CODES config | VERIFIED | `R/46_treatment_cross_reference.R` line 534: `in_ref_not_config = setdiff(reference_codes, config_codes)`; direction label "In Reference, Not Config" written to xlsx detail sheets for all 4 types |
| 2 | User can see which codes are in TREATMENT_CODES config but not in the reference documents | VERIFIED | Line 535: `in_config_not_ref = setdiff(config_codes, reference_codes)`; direction label "In Config, Not Reference" written to same sheets; both directions rendered per D-12 |
| 3 | Gap report is organized by treatment type with one sheet per type plus a summary sheet | VERIFIED | Lines 968-1126: wb$add_worksheet("Summary") + write_detail_sheet() called for "Chemotherapy", "Radiation", "SCT", "Immunotherapy" — 5 sheets total |
| 4 | Phase 45 audit-added codes are annotated in the gap report | VERIFIED | PHASE45_ADDED_CODES vector at line 502 contains 46 codes (verified by code count); annotation injected via build_gap_tibble() at lines 558-565 |
| 5 | Gap codes have patient count and encounter count from PROCEDURES data | VERIFIED | Lines 811-816: `get_pcornet_table("PROCEDURES") %>% ... %>% summarise(patient_count = n_distinct(ID), encounter_count = n())`; left-joined onto gap tibbles at line 837 |
| 6 | Each episode row in CSV output has a triggering_codes column showing which TREATMENT_CODES matched | VERIFIED | `R/44_treatment_episodes.R` lines 570-573: CSV write_df select includes `triggering_codes` as column 8 |
| 7 | Triggering codes are comma-separated bare codes with ALL matching codes within the episode window | VERIFIED | Line 468: `paste(sort(unique(na.omit(triggering_code))), collapse = ",")`; 3-column distinct at line 95 preserves multiple codes on same date |
| 8 | Triggering codes appear in BOTH CSV and styled xlsx output | VERIFIED | CSV: lines 570-573; xlsx: line 697 `Triggering_Codes = type_data$triggering_codes`; xlsx header line 676 "Triggering Codes"; A2:H2 dims at line 683 |
| 9 | Existing episode columns and row counts are unchanged (triggering_codes is additive only) | VERIFIED | triggering_codes appended as column 8 (last); original 7 columns unchanged in select at line 480-488; R/43_treatment_durations.R unmodified (confirmed — only has `extract_all_dates`, no `extract_dates_with_codes`) |

**Score:** 9/9 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/46_treatment_cross_reference.R` | Two-way gap report script | VERIFIED | 1175 lines (min 200 required); substantive REFERENCE_CODES covering all 4 types; DuckDB counts; openxlsx2 output |
| `R/44_treatment_episodes.R` | Episode generation with triggering_codes column | VERIFIED | 808 lines; `triggering_code` appears 60+ times; 4 type-specific extraction functions + dispatcher + aggregation in calculate_episodes_detailed() |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `R/46_treatment_cross_reference.R` | `R/00_config.R` | `source()` | WIRED | Line 60: `source("R/00_config.R")` — reads TREATMENT_CODES named list |
| `R/46_treatment_cross_reference.R` | `output/tables/treatment_cross_reference.xlsx` | `wb$save` | WIRED | Line 1132: `wb$save(OUTPUT_PATH)` where OUTPUT_PATH = `file.path(CONFIG$output_dir, "tables", "treatment_cross_reference.xlsx")` |
| `R/44_treatment_episodes.R` | `R/43_treatment_durations.R` | `source()` | WIRED | Line 52: `source("R/43_treatment_durations.R")`; uses assign_episode_ids() from it |
| `R/44_treatment_episodes.R` | `R/00_config.R` | TREATMENT_CODES usage | WIRED | TREATMENT_CODES referenced 20+ times across all 4 extraction functions |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| TXREF-01 | 46-01-PLAN.md | User can see a two-way gap report comparing TreatmentVariables_2024.07.17.docx code lists against current TREATMENT_CODES (codes in doc but not config, and codes in config but not doc) | SATISFIED | R/46_treatment_cross_reference.R implements setdiff() in both directions for all 4 treatment types, hardcodes reference data from both docx files and 3 xlsx files, writes 5-sheet xlsx with per-direction rows |
| TXREF-02 | 46-02-PLAN.md | User can see which code(s) triggered each treatment episode's start date in the episode CSV output (new triggering_codes column) | SATISFIED | R/44_treatment_episodes.R: extract_dates_with_codes() returns 3-col tibble; calculate_episodes_detailed() aggregates codes per episode; triggering_codes written as column 8 in CSV and xlsx detail sheets |

No orphaned requirements — both TXREF-01 and TXREF-02 are assigned to this phase in v1.6-REQUIREMENTS.md and both are covered by plans.

Note: v1.6-REQUIREMENTS.md still shows TXREF-01 and TXREF-02 as `[ ]` (unchecked) — these checkboxes were not updated when the plans completed. This is a documentation gap only, not a code gap; the implementations are fully present.

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| None | — | — | — |

No TODO/FIXME/placeholder comments, no empty return implementations, no `int_to_col()` (forbidden) anti-pattern, no `glue("{x:,}")` Python-style format spec found in either file.

### Human Verification Required

#### 1. Execute on HiPerGator Against Live DuckDB Data

**Test:** Run `Rscript R/46_treatment_cross_reference.R` on HiPerGator where the PCORnet DuckDB is available.
**Expected:** `output/tables/treatment_cross_reference.xlsx` is created with 5 sheets; patient_count and encounter_count columns are populated for reference-only gap codes; console summary highlights actionable gaps.
**Why human:** DuckDB/PCORnet data is not available in the local Windows environment. The script's PROCEDURES query (line 811) and wb$save (line 1132) can only be exercised on HiPerGator.

#### 2. Execute R/44_treatment_episodes.R on HiPerGator

**Test:** Run `Rscript R/44_treatment_episodes.R` on HiPerGator and inspect a generated episode CSV (e.g., `radiation_episodes.csv`).
**Expected:** CSV has 8 columns with triggering_codes as column 8; values are comma-separated bare codes (e.g., "77386,77387") or empty string; no change to existing episode row counts.
**Why human:** Requires live PCORnet data. The correctness of triggering code capture (which codes appear for which patients) is a clinical validation that needs domain review.

### Gaps Summary

No gaps. All 9 observable truths are verified. Both requirement IDs are fully covered. Both artifacts are substantive (1175 and 808 lines respectively), wired to their dependencies, and contain no stub patterns.

The two items flagged for human verification are execution tests requiring HiPerGator data access — they are not blockers to phase goal achievement but should be run as part of standard pipeline validation.

---

_Verified: 2026-05-15T18:00:00Z_
_Verifier: Claude (gsd-verifier)_
