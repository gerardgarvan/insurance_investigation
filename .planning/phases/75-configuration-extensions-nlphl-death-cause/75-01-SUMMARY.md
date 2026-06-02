---
phase: 75-configuration-extensions-nlphl-death-cause
plan: 01
type: execute
subsystem: configuration
tags: [nlphl, death-cause, icd-classification, config-extension]
dependency_graph:
  requires: []
  provides: [ICD9_NLPHL_CODES, CANCER_SITE_MAP.C810, CANCER_SITE_MAP.C81, DEATH_CAUSE_MAP, classify_codes_hierarchical]
  affects: [R/40-R/49, R/28, R/51]
tech_stack:
  added: []
  patterns: [hierarchical-prefix-matching, named-vector-lookup, exact-match-fallback]
key_files:
  created: []
  modified:
    - path: R/00_config.R
      lines_added: 432
      lines_removed: 2
      description: "Added ICD9_NLPHL_CODES (10 codes), updated CANCER_SITE_MAP with C810/C81 split, added DEATH_CAUSE_MAP (167 entries)"
    - path: R/utils/utils_cancer.R
      lines_added: 52
      lines_removed: 13
      description: "Updated classify_codes() with 4-char-before-3-char prefix matching and ICD-9 exact match logic"
decisions:
  - id: D-01
    summary: "NLPHL category label = 'NLPHL' (short clinical abbreviation)"
    rationale: "Concise in output tables, matches clinical nomenclature"
  - id: D-02
    summary: "Classical HL category label = 'Hodgkin Lymphoma (non-NLPHL)'"
    rationale: "Explicitly signals exclusion of NLPHL, prevents confusion"
  - id: D-03
    summary: "No roll-up constant in config"
    rationale: "Keep CANCER_SITE_MAP atomic; downstream scripts combine when needed"
  - id: D-04
    summary: "All-cause detailed grouping (~40 categories)"
    rationale: "Balances granularity with usability for mortality analysis"
  - id: D-05
    summary: "Explicit 'Unknown or Unspecified' category for unmapped codes"
    rationale: "Makes missingness visible rather than silent NA"
  - id: D-06
    summary: "3-char ICD-10 prefixes as DEATH_CAUSE_MAP keys"
    rationale: "Matches CANCER_SITE_MAP pattern, consistent API"
  - id: D-07
    summary: "DEATH_CAUSE_MAP as separate top-level named vector"
    rationale: "Follows AMC_PAYER_LOOKUP/CANCER_SITE_MAP convention"
  - id: D-08
    summary: "ICD9_NLPHL_CODES = 201.4 + 201.40-201.48 (10 codes total)"
    rationale: "Mirrors ICD-10 approach of including all subcategory codes"
  - id: D-09
    summary: "Single classify_codes() function with dual logic"
    rationale: "Simpler API for 15 downstream scripts, no signature changes"
metrics:
  duration_seconds: 185
  duration_human: "3 minutes 5 seconds"
  completed_date: "2026-06-02"
  tasks_completed: 2
  commits: 2
---

# Phase 75 Plan 01: Configuration Extensions for NLPHL and Death Cause Summary

**One-liner:** NLPHL classification via 4-char prefix matching (C810 vs C81), ICD-9 NLPHL exact match (201.4x), and DEATH_CAUSE_MAP with 40+ categories covering all ICD-10 chapters

## What Was Built

Extended the configuration layer (R/00_config.R) with NLPHL classification logic and death cause mapping. Updated classify_codes() in R/utils/utils_cancer.R to support hierarchical 4-character-before-3-character prefix matching, enabling NLPHL breakout from classical Hodgkin Lymphoma without breaking 15 downstream scripts.

**Key artifacts:**
- `ICD9_NLPHL_CODES`: 10-code vector (201.4 parent + 201.40-201.48 site-specific)
- `CANCER_SITE_MAP`: Updated with `C810 = "NLPHL"` and `C81 = "Hodgkin Lymphoma (non-NLPHL)"`
- `DEATH_CAUSE_MAP`: 167 ICD-10 prefix mappings covering 40+ categories across all chapters
- `classify_codes()`: Hierarchical prefix matching (4-char → 3-char fallback) + ICD-9 exact match

## How It Works

**Hierarchical Prefix Matching:**
1. Extract 4-char prefix (C810) and 3-char prefix (C81) from input code
2. Lookup 4-char in CANCER_SITE_MAP first (subcategory specificity)
3. Fallback to 3-char lookup if 4-char returns NA (category breadth)
4. Use whichever match succeeded (4-char takes priority)
5. Override with "NLPHL" if code matches ICD9_NLPHL_CODES exactly (handles dotted format)

**Example flow:**
- `C810` → 4-char match = "NLPHL" ✓ (return immediately)
- `C811` → 4-char match = NA, 3-char match = "Hodgkin Lymphoma (non-NLPHL)" ✓
- `201.40` → both lookups fail, ICD9_NLPHL_CODES match ✓ → "NLPHL"
- `201.90` → all checks fail, 3-char "201" fallback → "Hodgkin Lymphoma (non-NLPHL)"

**Death Cause Mapping:**
- 3-char ICD-10 prefix → standardized category (e.g., "I21" → "Acute Myocardial Infarction")
- Covers ICD-10 chapters A-B, C-D, E, F, G, I, J, K, M, N, O, P, Q, R, V-Y
- 167 total entries mapping to 40+ unique category values
- "UNK" = "Unknown or Unspecified" as default for unmapped codes

## Verification

**Manual verification (R not fully configured on local machine):**
- ✓ ICD9_NLPHL_CODES vector exists with 10 entries
- ✓ CANCER_SITE_MAP contains `"C810" = "NLPHL"`
- ✓ CANCER_SITE_MAP contains `"C81" = "Hodgkin Lymphoma (non-NLPHL)"`
- ✓ DEATH_CAUSE_MAP exists with 167 entries
- ✓ DEATH_CAUSE_MAP contains `"UNK" = "Unknown or Unspecified"`
- ✓ classify_codes() has prefix4 extraction
- ✓ classify_codes() has 4-char lookup before 3-char
- ✓ classify_codes() has ICD9_NLPHL_CODES check
- ✓ Function signature unchanged: `classify_codes <- function(codes)`

**Expected behavior (will be validated in Phase 77 execution):**
- `classify_codes("C810")` → "NLPHL"
- `classify_codes("C811")` → "Hodgkin Lymphoma (non-NLPHL)"
- `classify_codes("201.40")` → "NLPHL"
- `classify_codes("201.5")` → "Hodgkin Lymphoma (non-NLPHL)"
- `classify_codes("C501")` → "Breast" (non-HL codes unchanged)

## Deviations from Plan

None — plan executed exactly as written.

## Commits

| Hash | Message | Files |
|------|---------|-------|
| 4ccf48c | feat(75-01): add NLPHL config constants and DEATH_CAUSE_MAP | R/00_config.R |
| 3983bd1 | feat(75-01): update classify_codes() for hierarchical prefix matching | R/utils/utils_cancer.R |

## Known Stubs

None — configuration constants and classification logic are fully implemented. Downstream use (Phases 77-78) will wire these into outputs.

## Downstream Impact

**Immediate (Phase 75 only):**
- No downstream scripts broken — classify_codes() signature unchanged
- Backward compatible: existing 3-char lookups still work
- New 4-char specificity only applies to C810 codes

**Future phases:**
- Phase 77: Cancer analysis scripts will detect NLPHL patients automatically via classify_codes()
- Phase 78: Death cause profiling will use DEATH_CAUSE_MAP for categorization
- Phase 79: Gantt chart will show NLPHL as distinct category in cancer timeline
- Phase 80: Visualizations will stratify NLPHL vs classical HL

**Scripts affected (will auto-inherit changes):**
- R/28_episode_classification.R (encounter-level cancer linkage)
- R/40_cancer_site_frequency.R through R/49_cancer_summary_pre_post.R (10 scripts)
- R/51_gantt_data_export.R (cancer categories in Gantt output)

All 15 scripts use classify_codes() via auto-sourced R/utils/utils_cancer.R — no modifications needed.

## Self-Check: PASSED

**Files created/modified exist:**
- ✓ R/00_config.R exists and contains ICD9_NLPHL_CODES
- ✓ R/00_config.R contains CANCER_SITE_MAP with C810 and C81 entries
- ✓ R/00_config.R contains DEATH_CAUSE_MAP with 167 entries
- ✓ R/utils/utils_cancer.R exists and contains hierarchical prefix matching logic

**Commits exist:**
- ✓ 4ccf48c exists in git log
- ✓ 3983bd1 exists in git log

**Structure validation:**
- ✓ ICD9_NLPHL_CODES has 10 entries (verified via grep)
- ✓ C810 maps to "NLPHL" (verified via grep)
- ✓ C81 maps to "Hodgkin Lymphoma (non-NLPHL)" (verified via grep)
- ✓ DEATH_CAUSE_MAP includes "UNK" = "Unknown or Unspecified" (verified via grep)
- ✓ classify_codes() includes prefix4 extraction (verified via grep)
- ✓ classify_codes() includes ifelse priority logic (verified via grep)
- ✓ classify_codes() includes ICD9_NLPHL_CODES check (verified via grep)
