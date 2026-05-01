# Phase 37: Add an Other Govt Tier to the Tiered Payer Variable - Research

**Researched:** 2026-05-01
**Domain:** R-based payer categorization and same-day resolution hierarchy
**Confidence:** HIGH

## Summary

Phase 37 is a precise, surgical modification to `R/36_tiered_same_day_payer.R` that promotes "Other govt" from a collapsed category into its own distinct tier in the same-day payer resolution hierarchy. Currently, the `CODE_TO_TIER()` function (line 87-100) collapses "Other govt" into "Other" (line 92), which loses the distinction between government programs (VA, TRICARE, state agencies, corrections) and generic "Other" commercial/non-government payers. The AMC 8-category system in `R/00_config.R` already defines "Other govt" as a standard category with specific code mappings — this phase aligns the resolution logic to preserve that distinction.

The change expands the resolution hierarchy from 7 tiers to 8: **Medicaid > Medicare > Private > Other Govt > Other > Self-pay > Uninsured > Missing**. "Other govt" slots between Private and Other, reflecting the intuition that government programs rank below private insurance but above generic "Other" categories. The modification is self-contained within one script, requires no new outputs (same 12 CSV files), and builds on existing AMC infrastructure.

**Primary recommendation:** Update `CODE_TO_TIER()` to preserve "Other govt" as its own tier, insert it into `TIER_MAPPING` at position 4 (bumping Other/Self-pay/Uninsured/Missing down by one), verify all hardcoded tier lists and console summaries accommodate the 8th tier, and validate output CSVs show "Other govt" as a distinct resolved_payer value.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Tier Priority Position**
- **D-01:** The 8-tier resolution hierarchy is: Medicaid > Medicare > Private > **Other Govt** > Other > Self-pay > Uninsured > Missing. Other Govt slots between Private and Other.
- **D-02:** This matches the intuition that government programs (VA, state/federal agencies, corrections) rank below private insurance but above generic "Other" — the most conservative insertion point.

**Output Impact**
- **D-03:** Transparent update — same 12 CSV filenames, same column structure. "Other govt" appears as its own resolved_payer value and its own row in category summary CSVs. No new output files.
- **D-04:** Before-vs-after comparison CSVs will naturally show "Other govt" as a distinct category in both columns.

**Scope of Change**
- **D-05:** Full update within R/36_tiered_same_day_payer.R only. Update CODE_TO_TIER function, TIER_PRIORITY ordering vector, console summaries, and any hardcoded tier lists. Self-contained to one script.
- **D-06:** No changes to R/00_config.R, R/02_harmonize_payer.R, or any other script. AMC_PAYER_LOOKUP already maps codes to "Other govt" correctly — the only issue was the resolution step collapsing it.
- **D-07:** R/35 (Phase 34 baseline) remains untouched.

### Claude's Discretion
- Console summary formatting for the additional tier row
- Whether TIER_PRIORITY should be a named vector or character vector (as long as the ordering is correct)
- Any minor formatting adjustments to accommodate the wider tier set

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.

</user_constraints>

## Standard Stack

This phase uses the existing R/tidyverse stack already established in the project. No new packages required.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| R | 4.4.2+ | Base language | HiPerGator standard; load via `module load R/4.4.2` |
| dplyr | 1.2.0+ | Data transformation | case_when() logic for tier mapping; standard tidyverse component |
| glue | 1.8.0 | String formatting | Console logging messages |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| readr | 2.2.0+ | CSV I/O | write_csv() for output tables (already in use) |

**Installation:**
Not applicable — all packages already installed and in use in R/36_tiered_same_day_payer.R.

**Version verification:**
Versions verified from CLAUDE.md stack documentation (research/STACK.md). All packages are tidyverse ecosystem components already in production use.

## Project Constraints (from CLAUDE.md)

**Critical directives from project instructions:**

1. **Runtime environment:** RStudio on UF HiPerGator — scripts must work in that environment
2. **Code style:** Filtering logic uses named predicate functions (`has_*`, `with_*`, `exclude_*`) — no opaque one-liners. For this phase: tier mapping uses readable `case_when()` syntax.
3. **R packages:** tidyverse ecosystem (dplyr, ggplot2, stringr, lubridate), ggalluvial for Sankey, scales, janitor, glue
4. **Data access:** Raw CSVs on HiPerGator filesystem — paths configured in `R/00_config.R`
5. **Payer fidelity:** Must match the Python pipeline's 9-category payer mapping exactly, including dual-eligible detection. (Note: AMC 8-category system replaces this; fidelity now means preserving all 8 AMC categories including "Other govt".)

**Key architecture patterns:**
- Configuration centralization in `R/00_config.R`
- Named lists for tier priority mappings (e.g., `TIER_MAPPING <- list(...)`)
- `case_when()` for categorical mappings (readable, maintainable)
- `glue()` for console logging

## Architecture Patterns

### Current Tier Resolution Architecture (R/36 lines 71-100)

**Tier configuration pattern:**
```r
# TIER_MAPPING: Named list with integer priority ranks
# Lower rank = higher priority in same-day resolution
TIER_MAPPING <- list(
  Medicaid   = 1L,  # Highest priority
  Medicare   = 2L,
  Private    = 3L,
  Other      = 4L,  # CURRENT STATE: "Other govt" collapses here
  "Self-pay" = 5L,
  Uninsured  = 6L,
  Missing    = 7L   # Lowest priority
)

# CODE_TO_TIER: Maps AMC 8 categories to 7 resolution tiers
CODE_TO_TIER <- function(payer_category) {
  case_when(
    payer_category == "Medicaid"  ~ "Medicaid",
    payer_category == "Medicare"  ~ "Medicare",
    payer_category == "Private"   ~ "Private",
    payer_category == "Other govt" ~ "Other",  # PROBLEM: Collapses here
    payer_category == "Other"     ~ "Other",
    payer_category == "Self-pay"  ~ "Self-pay",
    payer_category == "Uninsured" ~ "Uninsured",
    payer_category == "Missing"   ~ "Missing",
    is.na(payer_category)         ~ "Missing",
    TRUE ~ "Missing"
  )
}
```

**Phase 37 target state:**
```r
TIER_MAPPING <- list(
  Medicaid   = 1L,
  Medicare   = 2L,
  Private    = 3L,
  "Other govt" = 4L,  # NEW: Promoted to its own tier
  Other      = 5L,    # Bumped down
  "Self-pay" = 6L,    # Bumped down
  Uninsured  = 7L,    # Bumped down
  Missing    = 8L     # Bumped down
)

CODE_TO_TIER <- function(payer_category) {
  case_when(
    payer_category == "Medicaid"   ~ "Medicaid",
    payer_category == "Medicare"   ~ "Medicare",
    payer_category == "Private"    ~ "Private",
    payer_category == "Other govt" ~ "Other govt",  # FIX: Preserve category
    payer_category == "Other"      ~ "Other",
    payer_category == "Self-pay"   ~ "Self-pay",
    payer_category == "Uninsured"  ~ "Uninsured",
    payer_category == "Missing"    ~ "Missing",
    is.na(payer_category)          ~ "Missing",
    TRUE ~ "Missing"
  )
}
```

### Pattern 1: Tier Priority List Updates

**What:** When adding a new tier to a resolution hierarchy, all downstream references to the tier list must be updated to maintain consistency.

**When to use:** Any time `TIER_MAPPING` is modified.

**Downstream impact points in R/36:**
1. `TIER_MAPPING` list (lines 75-83) — add "Other govt" at position 4
2. `CODE_TO_TIER()` function (lines 87-100) — change line 92 to preserve "Other govt"
3. Console summaries (lines 404-436) — verify no hardcoded tier counts
4. `arrange(match(tier, names(TIER_MAPPING)))` calls (lines 365, 369) — automatically adapts to new TIER_MAPPING
5. Safety net tier_rank assignment (line 167) — hardcoded `7L` should become `8L` (new max rank)

**Example:**
```r
# Before: Safety net assumes max rank is 7
tier_rank = if_else(is.na(tier_rank), 7L, tier_rank)

# After: Safety net must account for 8 tiers
tier_rank = if_else(is.na(tier_rank), 8L, tier_rank)
```

### Pattern 2: AMC Category Preservation

**What:** The AMC 8-category system in `R/00_config.R` defines authoritative payer categories. Resolution logic should preserve these categories unless explicitly collapsing for a specific analytical purpose.

**When to use:** Any tier mapping or resolution logic that consumes AMC categories.

**Current issue:** `CODE_TO_TIER()` collapses "Other govt" into "Other" without documented justification. This loses information about government payers (VA, TRICARE, state agencies, corrections) that the AMC system explicitly tracks.

**Best practice:** Identity mapping for all AMC categories unless there's a specific resolution hierarchy reason to collapse (e.g., Amy Crisp framework did not originally specify "Other govt" as a separate tier, but AMC system does — align with AMC).

### Anti-Patterns to Avoid

- **Hardcoded tier counts:** Don't embed `7` or `length = 7` assumptions in logic. Use `length(TIER_MAPPING)` or dynamic checks.
- **Incomplete tier updates:** Changing TIER_MAPPING without updating CODE_TO_TIER creates mismatches between category and rank assignments.
- **Missing safety net adjustments:** The safety net `tier_rank = if_else(is.na(tier_rank), 7L, tier_rank)` (line 167) must be updated to `8L` to match the new max rank.
- **Assuming fixed output row counts:** CSV consumers should not assume category summary CSVs have exactly 7 rows — should be robust to 8 rows.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Payer code categorization | Custom lookup tables or if-else chains | AMC_PAYER_LOOKUP from R/00_config.R | Centralized, audited, aligns with AMC framework, already handles 35+ codes + prefix fallback |
| Tier priority ranking | Manual rank assignment per observation | Named list TIER_MAPPING + unlist() lookup | Single source of truth, easily auditable, self-documenting |
| CSV category ordering | Arbitrary or alphabetical | arrange(match(tier, names(TIER_MAPPING))) | Preserves resolution hierarchy order in output |

**Key insight:** The project has mature infrastructure for payer categorization (AMC_PAYER_LOOKUP) and tier resolution (TIER_MAPPING). Phase 37 is an alignment fix, not a redesign — the infrastructure is correct, it just needs a one-line change to stop collapsing "Other govt".

## Runtime State Inventory

> Omitted — greenfield phase (new tier addition, no migration/rename/refactor of existing stored data).

## Common Pitfalls

### Pitfall 1: Incomplete Tier Mapping Updates
**What goes wrong:** Developer updates `TIER_MAPPING` to add "Other govt" at position 4 but forgets to bump down the ranks of Other/Self-pay/Uninsured/Missing from 4/5/6/7 to 5/6/7/8. This creates duplicate rank values (e.g., both "Other govt" and "Other" have rank 4).

**Why it happens:** The `TIER_MAPPING` list requires manual integer assignment for each category. Adding a new tier mid-list means renumbering all subsequent tiers.

**How to avoid:**
- Update ranks sequentially: Medicaid=1, Medicare=2, Private=3, Other govt=4, Other=5, Self-pay=6, Uninsured=7, Missing=8
- Verify with `TIER_MAPPING %>% unlist() %>% sort()` — should be `1:8` with no gaps or duplicates

**Warning signs:**
- Same-day resolution produces unexpected "Other" assignments when "Other govt" should win
- `tier_rank` column in output CSVs has duplicate values
- Resolution logic behaves identically for "Other govt" and "Other"

### Pitfall 2: Forgetting Safety Net Adjustments
**What goes wrong:** Line 167 has a safety net: `tier_rank = if_else(is.na(tier_rank), 7L, tier_rank)`. If this remains `7L` after adding an 8th tier, any NA tier_rank values get assigned rank 7 (Uninsured) instead of rank 8 (Missing).

**Why it happens:** The safety net is far from the `TIER_MAPPING` definition (line 75 vs line 167), so it's easy to miss during updates.

**How to avoid:**
- Grep for hardcoded tier count references: `grep -n "7L" R/36_tiered_same_day_payer.R`
- Update safety net to `8L` to match new max rank
- Better yet, make it dynamic: `tier_rank = if_else(is.na(tier_rank), length(TIER_MAPPING), tier_rank)`

**Warning signs:**
- Encounters with unparseable ADMIT_DATE or missing payer codes get assigned "Uninsured" instead of "Missing"
- Console summaries show zero "Missing" category when some should exist

### Pitfall 3: Console Summary Hardcoding
**What goes wrong:** Console summaries (lines 404-436) may have hardcoded tier names or counts. If they assume 7 tiers, they might truncate the 8th tier or produce misaligned output.

**Why it happens:** Console summaries often use manual message() calls with hardcoded strings for readability.

**How to avoid:**
- Review console summary logic to ensure it dynamically handles tier counts
- Verify no hardcoded tier name lists (e.g., `c("Medicaid", "Medicare", ..., "Missing")` with 7 elements)
- If tier names are hardcoded for formatting, update to include "Other govt"

**Warning signs:**
- Console output shows 7 categories instead of 8
- "Other govt" frequency appears in console but is not labeled or is mislabeled
- Tier summary counts don't add up to total encounters

### Pitfall 4: Output CSV Regression
**What goes wrong:** CSV consumers (e.g., downstream R scripts, PowerPoint automation, manual review) may assume category summary CSVs have exactly 7 rows. Adding an 8th row breaks those assumptions.

**Why it happens:** Phase 36/35 outputs had 7 categories. Consumers may hardcode row counts or categorical filters.

**How to avoid:**
- Document in phase summary: "Output CSVs now have 8 category rows instead of 7"
- Flag for validation: Check that downstream scripts (if any) handle variable row counts
- No code changes needed in R/36 itself — CSVs will naturally have 8 rows once tier mapping is updated

**Warning signs:**
- Downstream scripts error with "unexpected row count" or "unknown category"
- Manual PowerPoint slides show 7 categories instead of 8

## Code Examples

Verified patterns from R/36_tiered_same_day_payer.R:

### Tier Mapping Definition (Target State)
```r
# Source: R/36_tiered_same_day_payer.R lines 75-83 (TO BE UPDATED)
# ==========================================================================
# TIER HIERARCHY CONFIGURATION (per Amy Crisp framework + AMC alignment)
# Lower rank = higher priority. PIs can edit this with one-line changes.
# ==========================================================================
TIER_MAPPING <- list(
  Medicaid     = 1L,  # Highest priority (includes dual-eligible, codes 93/14, FLM source)
  Medicare     = 2L,
  Private      = 3L,
  "Other govt" = 4L,  # NEW: VA, TRICARE, state agencies, corrections
  Other        = 5L,  # Generic other (worker's comp, auto insurance, etc.)
  "Self-pay"   = 6L,
  Uninsured    = 7L,
  Missing      = 8L   # Lowest priority
)
```

### CODE_TO_TIER Function (Target State)
```r
# Source: R/36_tiered_same_day_payer.R lines 87-100 (TO BE UPDATED)
# Map the AMC 8-category payer scheme to the 8 resolution tiers
# AMC categories now align 1:1 with tiers (no collapsing)
CODE_TO_TIER <- function(payer_category) {
  case_when(
    payer_category == "Medicaid"   ~ "Medicaid",
    payer_category == "Medicare"   ~ "Medicare",
    payer_category == "Private"    ~ "Private",
    payer_category == "Other govt" ~ "Other govt",  # FIXED: Preserve category
    payer_category == "Other"      ~ "Other",
    payer_category == "Self-pay"   ~ "Self-pay",
    payer_category == "Uninsured"  ~ "Uninsured",
    payer_category == "Missing"    ~ "Missing",
    is.na(payer_category)          ~ "Missing",
    TRUE ~ "Missing"
  )
}
```

### Safety Net Adjustment (Target State)
```r
# Source: R/36_tiered_same_day_payer.R line 167 (TO BE UPDATED)
# Safety net: ensure tier_rank is never NA (maps to Missing)
tier_rank = if_else(is.na(tier_rank), 8L, tier_rank)  # UPDATED: 7L → 8L
# Or better: dynamic
tier_rank = if_else(is.na(tier_rank), as.integer(length(TIER_MAPPING)), tier_rank)
```

### AMC Code Mapping (Reference — No Changes Needed)
```r
# Source: R/00_config.R lines 321-328
# "Other govt" codes already correctly mapped in AMC_PAYER_LOOKUP
AMC_PAYER_LOOKUP <- c(
  # ... (other codes)
  "382"   = "Other govt",  # Federal, State, Local not specified - FFS
  "349"   = "Other govt",  # Other
  "3"     = "Other govt",  # Other Government (excl. Corrections)
  "32126" = "Other govt",  # Other Federal Agency
  "32121" = "Other govt",  # Fee Basis
  "32"    = "Other govt",  # Department of Veterans Affairs
  "44"    = "Other govt"   # Corrections Unknown Level
)

# Prefix fallback (R/00_config.R lines 342-343)
# "3" = "Other govt",
# "4" = "Other govt",
```

### CSV Ordering Pattern (No Changes Needed — Dynamically Adapts)
```r
# Source: R/36_tiered_same_day_payer.R lines 365, 369
# Before-vs-after impact CSV
before_resolution <- enc_scope %>%
  filter(!is.na(admit_date_parsed)) %>%
  count(tier, name = "n_encounters_before") %>%
  arrange(match(tier, names(TIER_MAPPING)))  # Automatically uses 8-tier order

after_resolution <- resolved_detail %>%
  count(resolved_payer, name = "n_patient_dates_after") %>%
  arrange(match(resolved_payer, names(TIER_MAPPING)))  # Automatically uses 8-tier order
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 7-tier resolution (collapses "Other govt" into "Other") | 8-tier resolution (preserves "Other govt" as distinct) | Phase 37 (2026-05-01) | Aligns tier resolution with AMC 8-category system; preserves government payer distinction for VA, TRICARE, state programs |
| Amy Crisp framework original 7-tier hierarchy | AMC-aligned 8-tier hierarchy | Phase 37 (2026-05-01) | Amy Crisp framework (payer_framework.txt) did not originally specify "Other govt" separately, but AMC system does — this phase extends the hierarchy |

**Deprecated/outdated:**
- None — this is a greenfield extension, not a deprecation. The 7-tier system was correct for its context (matching Amy Crisp's original specification). Phase 37 aligns with the AMC 8-category system introduced in Phase 36.

## Open Questions

None. The phase is mechanically straightforward with well-defined scope:
- What we know: Exact lines to change (TIER_MAPPING, CODE_TO_TIER, safety net), target tier order, AMC category names
- What's unclear: Nothing blocking planning
- Recommendation: Proceed with implementation

## Environment Availability

**Step 2.6: SKIPPED** (no external dependencies identified)

This phase modifies only R code logic (tier mapping and case_when statements). No external tools, databases, or services are required beyond the existing R/tidyverse environment already validated in Phases 1-36.

## Sources

### Primary (HIGH confidence)
- R/36_tiered_same_day_payer.R (direct code inspection) - Current tier mapping implementation
- R/00_config.R lines 239-362 (direct code inspection) - AMC_PAYER_LOOKUP and PAYER_MAPPING definitions
- .planning/phases/37-add-an-other-govt-tier-to-the-tiered-payer-variable/37-CONTEXT.md - User decisions from /gsd:discuss-phase
- .planning/phases/36-all-encounter-payer-frequency-and-same-day-categorization-with-amc-8-category-coding/36-CONTEXT.md - D-08 documents "Other govt" collapsing issue
- payer_framework.txt - Amy Crisp original 7-tier hierarchy specification

### Secondary (MEDIUM confidence)
- CLAUDE.md - Project constraints and stack documentation (verified stack versions from official CRAN references)

### Tertiary (LOW confidence)
- None used

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages already in use, versions verified from project documentation
- Architecture: HIGH - Direct inspection of R/36 code, clear tier mapping pattern
- Pitfalls: HIGH - Derived from code inspection and tier mapping logic analysis
- Project constraints: HIGH - CLAUDE.md explicitly lists runtime environment, code style, package requirements

**Research date:** 2026-05-01
**Valid until:** 2026-05-31 (30 days for stable domain — R/tidyverse tier mapping logic is mature and unlikely to change)
