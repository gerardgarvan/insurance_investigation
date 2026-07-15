---
phase: 127-code-set-and-infrastructure-centralization
plan: "01"
subsystem: config
tags: [icd-codes, doi, rituximab, methotrexate, autoimmune, r-config]

requires:
  - phase: 126-smoke-test-fix
    provides: R/88 smoke-test exits 0; R/00_config.R in stable state

provides:
  - DOI_CODE_MAP: 35-key named character vector mapping ICD prefix to DoI category (Section 4c)
  - DOI_CODE_TIER: parallel tier lookup (table-stakes/edge) with same keys as DOI_CODE_MAP
  - RITDIS_CODE_VERSION: FY2026_v1 version pin constant
  - RITUXIMAB_CODES: list(hcpcs, rxnorm) with J9310/J9311/J9312 + CUI 121191 (Section 4d)
  - MTX_CODES: list(hcpcs, rxnorm) referencing existing chemo_rxnorm CUIs by value (Section 4d)
  - DOI_ATTRIBUTION_WINDOW_DAYS: 90L integer constant (Section 4d)

affects:
  - Phase 128 (Classification): is_doi_code() / classify_doi_codes() in utils_doi.R consume DOI_CODE_MAP
  - Phase 129 (Attribution): RITUXIMAB_CODES / MTX_CODES / DOI_ATTRIBUTION_WINDOW_DAYS consumed by attribution join
  - Phase 130 (Smoke Test): intersect() check validates DOI_CODE_MAP keys don't overlap cancer maps

tech-stack:
  added: []
  patterns:
    - "Named character vector prefix map (mirrors CANCER_SITE_MAP): 3-char keys for whole ICD-10 families, 4-char keys for subcategory disambiguation (D692 vs D693, H460-H469)"
    - "Parallel tier lookup DOI_CODE_TIER with identical key set — queryable without re-parsing comments"
    - "Additive drug code sections isolated from chemo_rxnorm / DRUG_GROUPINGS"

key-files:
  created: []
  modified:
    - R/00_config.R

key-decisions:
  - "Section 4c inserted immediately after ICD9_NLPHL_CODES (line ~392) and before Section 5 PAYER MAPPING — maintains chronological block ordering without disrupting existing section numbering"
  - "I77.82 excluded: seed RTF error — ICD-10-CM FY2026 codes I77.82 as Dissection of artery, not ANCA vasculitis (DOI-CODE-02)"
  - "D47.Z2 excluded: already owned by CANCER_SITE_MAP D47 = MDS/Myeloproliferative key; double-classification prohibited (DOI-CODE-02)"
  - "14 clinical conditions map to 10 distinct label strings: Sjogrens folds into SLE / Connective Tissue (M35 key); 6 vasculitis variants (M30/M31/L95/D692/446/D891) all collapse to Vasculitis label — intentional per D-01"
  - "RITUXIMAB_CODES and MTX_CODES are additive lists in Section 4d, NOT added to TREATMENT_CODES$chemo_rxnorm or DRUG_GROUPINGS (DOI-CODE-03) — prevents inflating chemo-detection counts and corrupting ABVD/BV+AVD regimen identification"
  - "DOI_ATTRIBUTION_WINDOW_DAYS = 90L (one clinical quarter) — wider than cancer cascade +-30 days because RA/psoriasis/IBD indication-to-drug timelines span months"

patterns-established:
  - "DoI config pattern: DOI_CODE_MAP + DOI_CODE_TIER as sibling named vectors with identical key sets; tier is queryable, not just a comment"
  - "Section 4d isolation: drug codes for DoI attribution live in their own section, separate from TREATMENT_CODES and DRUG_GROUPINGS"

requirements-completed: [DOI-CODE-01, DOI-CODE-02, DOI-CODE-03, DOI-CODE-04]

duration: 12min
completed: 2026-07-15
---

# Phase 127 Plan 01: Code-Set and Infrastructure Centralization Summary

**35-key DOI_CODE_MAP (14 clinical conditions, 10 category labels) + DOI_CODE_TIER + RITDIS_CODE_VERSION + RITUXIMAB_CODES + MTX_CODES + DOI_ATTRIBUTION_WINDOW_DAYS added to R/00_config.R Sections 4c and 4d**

## Performance

- **Duration:** 12 min
- **Started:** 2026-07-15T20:30:00Z
- **Completed:** 2026-07-15T20:42:00Z
- **Tasks:** 2 (both executed as a single additive edit)
- **Files modified:** 1

## Accomplishments

- Section 4c added to R/00_config.R: DOI_CODE_MAP with 35 prefix keys spanning all 14 clinical conditions (RA, 6 vasculitis variants, Pemphigus, Pemphigoid, Inflammatory Myopathy, 4 neurological conditions, ITP, AIHA, SLE, Sjogrens, Psoriasis, IBD Crohns, IBD UC), verified against ICD-10-CM FY2026 with zero key overlap against CANCER_SITE_MAP and ICD9_CANCER_SITE_MAP
- DOI_CODE_TIER parallel lookup (35 keys, "table-stakes"/"edge" values) and RITDIS_CODE_VERSION = "FY2026_v1" added alongside DOI_CODE_MAP; tier is queryable without comment parsing (DOI-CODE-04)
- Section 4d added: RITUXIMAB_CODES (J-codes + CUI 121191), MTX_CODES (J-codes + existing CUIs by reference), DOI_ATTRIBUTION_WINDOW_DAYS = 90L — all additive, no modification of chemo_rxnorm or DRUG_GROUPINGS (DOI-CODE-03)

## Task Commits

Both tasks executed as a single additive edit:

1. **Task 1: Add Section 4c — DOI_CODE_MAP + RITDIS_CODE_VERSION** - `c8da699` (feat)
2. **Task 2: Add Section 4d — RITUXIMAB_CODES, MTX_CODES, DOI_ATTRIBUTION_WINDOW_DAYS** - `c8da699` (feat, same commit — contiguous insertion at same anchor point)

## Files Created/Modified

- `R/00_config.R` — 198 lines added: Section 4c (DOI_CODE_MAP, DOI_CODE_TIER, 14->10 label collapse comment, RITDIS_CODE_VERSION) and Section 4d (RITUXIMAB_CODES, MTX_CODES, DOI_ATTRIBUTION_WINDOW_DAYS)

## Decisions Made

- Both sections (4c and 4d) inserted in one edit at the same anchor point (after ICD9_NLPHL_CODES, before Section 5 PAYER MAPPING) since they are logically and positionally contiguous — no reason to split into two separate edits
- L10.81 (paraneoplastic pemphigus) is CAPTURED via the L10 3-char key but flagged in inline comment for Phase 128 paraneoplastic_flag handling — not excluded, per plan specification
- H46.2 (nutritional) and H46.3 (toxic) optic neuropathy excluded via 4-char key approach (H460, H461, H468, H469) — 3-char H46 prefix would falsely include these non-autoimmune conditions
- D692 (IgA vasculitis / HSP) and D693 (ITP) use 4-char keys to disambiguate within the D69 family

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The `openxlsx2` package is missing from the local Windows R library, causing `source("R/00_config.R")` to error after our new sections (which appear early in the file). This is a pre-existing issue that does not affect the new constants — they are defined before the openxlsx2 library call. Verified via `tryCatch(source(...))` that all 6 constants (DOI_CODE_MAP, DOI_CODE_TIER, RITDIS_CODE_VERSION, RITUXIMAB_CODES, MTX_CODES, DOI_ATTRIBUTION_WINDOW_DAYS) exist after source is called with error suppression. This pre-existing openxlsx2 issue is out of scope for this plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- DOI_CODE_MAP is ready for consumption by `is_doi_code()` / `classify_doi_codes()` in Phase 128's `R/utils/utils_doi.R`
- RITUXIMAB_CODES / MTX_CODES / DOI_ATTRIBUTION_WINDOW_DAYS are ready for Phase 129 attribution join
- Zero key overlap with cancer maps confirmed; smoke-test intersect() check (Phase 130) can validate this at runtime

---
*Phase: 127-code-set-and-infrastructure-centralization*
*Completed: 2026-07-15*
