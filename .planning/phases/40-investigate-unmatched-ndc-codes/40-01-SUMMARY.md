---
phase: 40-investigate-unmatched-ndc-codes
plan: 01
subsystem: data-investigation
tags: [R, RxNorm, NDC, drug-codes, httr2, API, PCORnet]

# Dependency graph
requires:
  - phase: 39-investigate-unmatched-codes
    provides: Investigation script pattern (8 sections, httr/API lookup, xlsx styling)
  - phase: 38-chemo-treatment-inventory-by-source-table
    provides: safe_table() helper, get_hl_patient_ids() pattern, TREATMENT_TYPE_COLORS palette
provides:
  - R/40_investigate_unmatched_ndc.R investigation script (NDC + RXNORM lookup, 6-category classification)
  - output/unmatched_ndc_report.xlsx styled report template
  - output/unmatched_ndc_classified.rds artifact for Plan 02 config update
  - RxNorm API integration pattern with httr2 retry logic
affects: [40-02, drug-detection, TREATMENT_CODES-expansion]

# Tech tracking
tech-stack:
  added: [httr2 for HTTP requests with retry, RxNorm REST API]
  patterns: [NDC->RxCUI->Name 2-step lookup, Supportive Care classification priority]

key-files:
  created:
    - R/40_investigate_unmatched_ndc.R
  modified: []

key-decisions:
  - "httr2 (modern) instead of httr (legacy) for API requests with req_retry() for transient failures"
  - "Supportive Care classification checked FIRST in case_when() to avoid misclassifying G-CSF/antiemetics as chemotherapy"
  - "NDC lookup requires 2-step API pattern (NDC->RxCUI->Name) per RxNorm API design"
  - "Fall back to RAW_*_MED_NAME from PCORnet tables when RxNorm API lookup fails"

patterns-established:
  - "RxNorm API integration: rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/properties.json for drug names"
  - "NDC resolution: rxnav.nlm.nih.gov/REST/rxcui.json?idtype=NDC&id={ndc} then properties lookup"
  - "TREATMENT_TYPE_COLORS palette with 'SCT-related' key (not 'SCT') for consistency across phases"

requirements-completed: [D-01, D-02, D-03, D-04, D-05, D-06, D-07, D-08, D-09, D-12, D-13]

# Metrics
duration: 3min
completed: 2026-05-04
---

# Phase 40 Plan 01: Investigate Unmatched NDC Codes Summary

**NDC and unmatched RXNORM drug code investigation script with RxNorm API lookup, 6-category auto-classification (Supportive Care prioritized), and styled xlsx report generation**

## Performance

- **Duration:** 3 min
- **Started:** 2026-05-04T16:35:41Z
- **Completed:** 2026-05-04T16:38:50Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Created 803-line investigation script extracting NDC and unmatched RXNORM codes from 3 drug tables (DISPENSING, PRESCRIBING, MED_ADMIN)
- Integrated RxNorm REST API with httr2 retry logic for drug name lookup (NDC requires 2-step NDC->RxCUI->Name pattern)
- Auto-classification into 6 treatment categories with Supportive Care checked first to prevent G-CSF/antiemetic misclassification
- Styled xlsx report with summary sheet, per-category sheets, and TREATMENT_TYPE_COLORS palette
- RDS artifact saved for Plan 02 config update consumption

## Task Commits

Each task was committed atomically:

1. **Task 1: Create R/40_investigate_unmatched_ndc.R investigation script** - `83eed98` (feat)

**Plan metadata:** (next commit)

## Files Created/Modified
- `R/40_investigate_unmatched_ndc.R` - Investigation script with 7 sections: setup, extraction (3 drug tables x 2 code types), RxNorm API lookup (RXNORM CUI direct + NDC 2-step), classification (6 categories), xlsx report generation, RDS artifact, main execution orchestration

## Decisions Made

1. **httr2 over httr:** Used httr2 (modern) instead of httr (legacy) per RESEARCH.md recommendation. httr2 provides req_retry() for transient failure handling (429, 503, 504 status codes) with max_tries=3.

2. **Supportive Care priority:** Classification function checks Supportive Care FIRST in case_when() before Chemotherapy to prevent misclassifying filgrastim/G-CSF/ondansetron/antiemetics as chemo (per D-09 and Phase 39 Pitfall 3).

3. **NDC 2-step lookup:** NDC codes require 2-step RxNorm API pattern: (1) NDC->RxCUI via idtype=NDC endpoint, (2) RxCUI->Name via properties endpoint. Single-step lookup not available.

4. **Raw name fallback:** When RxNorm API lookup fails (not_found or error status), fall back to RAW_*_MED_NAME from PCORnet tables (RAW_DISPENSE_MED_NAME, RAW_RX_MED_NAME, RAW_MEDADMIN_MED_NAME) for classification.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- R/40_investigate_unmatched_ndc.R ready for execution on HiPerGator with data access
- RDS output (unmatched_ndc_classified.rds) will be consumed by Plan 02 for programmatic config update
- TREATMENT_CODES will be expanded with new vectors: chemo_ndc, supportive_care_ndc, immunotherapy_rxnorm, etc.

## Self-Check: PASSED

**Created files:**
- FOUND: R/40_investigate_unmatched_ndc.R (803 lines)

**Commits:**
- FOUND: 83eed98 (feat(40-01): create NDC/RXNORM investigation script)

---
*Phase: 40-investigate-unmatched-ndc-codes*
*Completed: 2026-05-04*
