# Phase 36: All-Encounter Payer Frequency & Same-Day Categorization (AMC 8-Category) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-30
**Phase:** 36-all-encounter-payer-frequency-and-same-day-categorization-with-amc-8-category-coding
**Areas discussed:** Script strategy, AMC category source, Output deliverables, Baseline handling

---

## Script Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Refactor R/36 in-place | Update R/36 to use centralized AMC_PAYER_LOOKUP from config.R, replace PayerVariable.xlsx cross-ref with AMC categories, keep same file | |
| New R/37 script | Fresh script using AMC 8-category mapping throughout. Keep R/35 and R/36 as historical baselines from Phases 34/35 | |
| Replace R/36, keep R/35 | Overwrite R/36 with a clean AMC-native version. Keep R/35 (Phase 34's AV+TH-only frequency) as baseline | |

**User's choice:** "replace everything that used the old code just use amc code" — update R/36 in-place to use AMC throughout
**Notes:** User wants a clean AMC-native approach, not a new script file

### Follow-up: R/35 handling

| Option | Description | Selected |
|--------|-------------|----------|
| R/36 only (Recommended) | R/36 already produces dual-scope output. Update it to use AMC_PAYER_LOOKUP. R/35 becomes a historical baseline. | ✓ |
| Both R/35 and R/36 | Update both scripts to use AMC mapping | |
| New single R/37 script | Create one clean R/37 that replaces both | |

**User's choice:** R/36 only
**Notes:** R/35 stays as Phase 34 historical baseline

---

## AMC Category Source

| Option | Description | Selected |
|--------|-------------|----------|
| AMC_PAYER_LOOKUP from config.R | Use the centralized AMC_PAYER_LOOKUP named vector for code→category mapping. | ✓ |
| payer_primary_codes_frequency_AMC.xlsx | Use the AMC xlsx file for both descriptions and categories | |
| Both — AMC_PAYER_LOOKUP + PayerVariable.xlsx descriptions | Use AMC_PAYER_LOOKUP for category mapping but still join PayerVariable.xlsx for descriptions | |

**User's choice:** AMC_PAYER_LOOKUP from config.R
**Notes:** No PayerVariable.xlsx dependency

### Follow-up: Description column

| Option | Description | Selected |
|--------|-------------|----------|
| Code + AMC category only | Simpler output: code, amc_category, n, pct. No human-readable descriptions. | ✓ |
| Keep PayerVariable.xlsx descriptions too | code, description, amc_category, n, pct | |
| You decide | Claude picks the approach | |

**User's choice:** Code + AMC category only
**Notes:** Clean approach without descriptions

### Follow-up: Unmapped codes

| Option | Description | Selected |
|--------|-------------|----------|
| Keep prefix fallback (Recommended) | Codes not in AMC_PAYER_LOOKUP get categorized via prefix rules. Every code gets a category. | ✓ |
| Flag as unmapped | Codes not in AMC_PAYER_LOOKUP flagged as 'NOT IN AMC' | |

**User's choice:** Keep prefix fallback
**Notes:** Ensures every code gets a category

---

## Output Deliverables

| Option | Description | Selected |
|--------|-------------|----------|
| Same 12 CSVs, updated content | Same CSV structure and filenames, category column now shows AMC 8 categories. Existing files get overwritten. | ✓ |
| New filenames with _amc suffix | Create new CSV files with '_amc' suffix so old and new coexist | |
| xlsx instead of CSV | Switch output format to xlsx | |

**User's choice:** Same 12 CSVs, updated content
**Notes:** No filename changes, just category values updated

### Follow-up: Column structure

| Option | Description | Selected |
|--------|-------------|----------|
| Just swap categories, keep structure | Same CSV columns and structure. Only change: category values from AMC_PAYER_LOOKUP. | ✓ |
| Drop description column entirely | Frequency CSVs simplify to: code, amc_category, n, pct (4 columns instead of 5) | |

**User's choice:** Just swap categories, keep structure
**Notes:** Structure preserved, category values updated

---

## Baseline Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Keep R/35 as-is (Recommended) | R/35 stays as Phase 34 historical baseline using PayerVariable.xlsx. R/36 gets updated to AMC. | ✓ |
| Delete R/35 | Remove R/35 to avoid confusion | |
| Update R/35 too | Also update R/35 for consistency | |

**User's choice:** Keep R/35 as-is
**Notes:** Two scripts, two eras

### Follow-up: Local function copies

| Option | Description | Selected |
|--------|-------------|----------|
| Refactor to use config.R (Recommended) | Remove local function copies. Use AMC_PAYER_LOOKUP directly from config.R. Reduces duplication. | ✓ |
| Keep local copies | Keep standalone local functions for isolation | |

**User's choice:** Refactor to use config.R
**Notes:** Remove duplicated map_payer_category_local, compute_effective_payer_local, detect_dual_eligible_local

---

## Claude's Discretion

- How to handle left_join-based frequency table logic when switching from PayerVariable.xlsx to AMC_PAYER_LOOKUP vector
- Whether to source R/02_harmonize_payer.R or use inline simplified versions of compute_effective_payer/detect_dual_eligible
- Console summary format adjustments

## Deferred Ideas

None — discussion stayed within phase scope.
