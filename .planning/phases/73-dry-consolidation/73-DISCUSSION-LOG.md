# Phase 73: DRY Consolidation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-06-02
**Phase:** 73-dry-consolidation
**Areas discussed:** Consolidation scope, Utility organization, Payer logic extraction, File I/O helpers

---

## Consolidation Scope

| Option | Description | Selected |
|--------|-------------|----------|
| All five targets | PREFIX_MAP, TIER_MAPPING, classify_codes(), payer tier logic, and file I/O helpers. Covers both DRY-01 and DRY-02 comprehensively. | ✓ |
| High-impact only | PREFIX_MAP, TIER_MAPPING, classify_codes() only. Defers payer logic and file I/O helpers to a future phase. | |
| Lookups + cancer only | PREFIX_MAP, TIER_MAPPING, classify_codes(). No payer refactoring, no file I/O. Minimal scope. | |

**User's choice:** All five targets (Recommended)
**Notes:** Full comprehensive DRY consolidation covering both requirements (DRY-01 and DRY-02).

---

## Utility Organization

### Cancer classification function

| Option | Description | Selected |
|--------|-------------|----------|
| New utils_cancer.R | Dedicated file for cancer-specific utilities. Matches domain separation of existing utils_payer.R, utils_treatment.R. | ✓ |
| Add to utils_icd.R | classify_codes() relates to ICD code parsing. Keeps file count lower but mixes domains. | |

**User's choice:** New utils_cancer.R (Recommended)
**Notes:** Dedicated domain-specific file, consistent with existing organizational pattern.

### Payer tier classification function

| Option | Description | Selected |
|--------|-------------|----------|
| Expand utils_payer.R | Already has is_missing_payer(), CODE_TO_TIER(), field_match(). Adding classify_payer_tier() keeps all payer logic in one place. | ✓ |
| New utils_payer_tier.R | Separate file for tier-resolution logic. More granular but adds another module. | |

**User's choice:** Expand utils_payer.R (Recommended)
**Notes:** Consolidate with existing payer utilities.

### File I/O helper

| Option | Description | Selected |
|--------|-------------|----------|
| Expand utils_snapshot.R | Already has save_output_data(). Adding build_output_path() groups all output-related helpers together. | ✓ |
| New utils_io.R | Dedicated file for path construction and directory management. Cleaner separation but adds a module. | |

**User's choice:** Expand utils_snapshot.R (Recommended)
**Notes:** Natural fit alongside existing save_output_data().

---

## Payer Logic Extraction

| Option | Description | Selected |
|--------|-------------|----------|
| Full row-level classification | Extract entire mutate() chain (effective_payer, dual_eligible, payer_category, tier) as classify_payer_tier(df). Each script calls it once. Scripts handle own grouping/summarization. | ✓ |
| Sub-functions only | Extract smaller pieces: resolve_effective_payer(), detect_dual_eligible(), map_payer_category(). Scripts compose them. More flexible but 3 new functions instead of 1. | |
| You decide | Claude picks the extraction boundary based on what makes the code cleanest. | |

**User's choice:** Full row-level classification (Recommended)
**Notes:** Single function encapsulating the complete classification pipeline.

---

## File I/O Helper

| Option | Description | Selected |
|--------|-------------|----------|
| Path + auto-mkdir | build_output_path("tables", "filename.xlsx") returns full path AND creates parent directories. One call replaces two lines. | ✓ |
| Path only, manual mkdir | Just returns file.path(). Scripts still call dir.create() separately. Less magic, more explicit. | |
| Defer this target | Skip file I/O helper for Phase 73. Focus on PREFIX_MAP and payer consolidation instead. | |

**User's choice:** Path + auto-mkdir (Recommended)
**Notes:** Maximum boilerplate reduction -- one call replaces two lines in 56 files.

---

## Claude's Discretion

- Internal structure of CANCER_SITE_MAP in R/00_config.R (section placement, naming)
- How classify_payer_tier() handles minor differences between R/60, R/61, R/62
- Wave/plan decomposition strategy
- Which of the 56 file I/O sites to convert in Phase 73 vs leave for later
- Smoke test validation approach

## Deferred Ideas

None -- discussion stayed within phase scope.
