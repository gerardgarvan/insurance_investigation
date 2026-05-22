# Phase 4: Confirm Cancer Site Codes with 7-Day Separation - Research

**Researched:** 2026-05-19
**Domain:** Date-based validation logic in R (dplyr/tidyverse)
**Confidence:** HIGH

## Summary

Phase 4 extends Phase 3's distinct-date confirmation by adding a temporal constraint: dates must be at least 7 days apart. This is a minimal modification to the R/50 script — the 7-day gap filter replaces the simple count-based filter while keeping all other logic (PREFIX_MAP, classification, xlsx styling) identical.

The implementation leverages R's native date arithmetic (`as.numeric(max(date) - min(date))`) already used in R/43 and R/44 for episode span calculations. The 7-day threshold follows standard epidemiological practice where temporal separation strengthens diagnostic confidence beyond mere repetition.

**Primary recommendation:** Clone R/50_cancer_site_confirmation.R to R/51_cancer_site_confirmation_7day.R, modify two filter lines (lines 429 and 478 equivalents) to check date span >= 7 instead of date count >= 2, update sheet titles and output filename to reflect the 7-day requirement.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Script Structure:**
- **D-01:** Separate R/51 script (next available number). Clone of R/50 with the 7-day gap filter added. R/50 remains untouched as the Phase 3 baseline.
- **D-02:** Output is a standalone xlsx file (e.g., cancer_site_confirmation_7day.xlsx). Same column structure as Phase 3 -- no comparison columns from Phase 3 included. Users compare by opening both xlsx files side by side.

**Confirmation Logic (Carried from Phase 3):**
- **D-03:** Two confirmation levels: (1) exact ICD-10 code with 7-day gap, (2) 3-character prefix with 7-day gap. Both computed and reported in separate sheets.
- **D-04:** DIAGNOSIS table only. DX_DATE for distinct-date counting. ICD-10 codes only (DX_TYPE == "10").
- **D-05:** Per cancer site category: total_patients, confirmed_patients, unconfirmed_patients, confirmation_rate. Only populated categories (no zero-count rows).

**7-Day Gap Definition:**
- **D-06:** "7 days apart" means max(date) - min(date) >= 7 days for a patient's dates with the same code (or prefix). Standard epidemiological approach -- if the earliest and latest dates are 7+ days apart, the code is confirmed.

**Output Format (Carried from Phase 3):**
- **D-07:** Styled xlsx output following openxlsx2 patterns from R/50 (dark header, freeze panes, number formatting, auto column widths, totals row).

### Claude's Discretion

- Exact output filename convention
- Whether to add a subtitle noting the 7-day requirement in the xlsx title rows
- Column ordering and styling details beyond what's established in R/50

### Deferred Ideas (OUT OF SCOPE)

None -- discussion stayed within phase scope.

</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Group-by + filter pattern for date span logic; already used in R/50 |
| stringr | 1.5.1+ | String operations | ICD code normalization (carried from Phase 3) |
| glue | 1.8.0 | String formatting | Logging messages (carried from Phase 3) |
| openxlsx2 | 1.15.0+ | Excel output | Styled xlsx generation (carried from Phase 3) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| lubridate | 1.9.3+ | Date arithmetic (optional) | NOT needed -- base R date arithmetic sufficient for this phase |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Base R date arithmetic | lubridate::interval() | lubridate adds dependency for no gain; `as.numeric(max(date) - min(date))` is standard R and already used in R/43, R/44 |
| dplyr filter | data.table | Phase 3 already uses dplyr; consistency outweighs data.table's speed advantage |

**Installation:**

All dependencies already installed for Phase 3. No new packages required.

**Version verification:**

Versions inherited from Phase 3 (R/50 script). No version changes needed.

## Architecture Patterns

### Recommended Project Structure

Phase 4 adds one file to existing structure:

```
R/
├── 50_cancer_site_confirmation.R          # Phase 3: 2+ distinct dates
├── 51_cancer_site_confirmation_7day.R     # Phase 4: 7-day gap (NEW)
└── ...

output/
└── tables/
    ├── cancer_site_confirmation.xlsx      # Phase 3 output
    └── cancer_site_confirmation_7day.xlsx # Phase 4 output (NEW)
```

### Pattern 1: Date Span Filter in dplyr Pipeline

**What:** Replace count-based filter with date span filter in grouped context.

**When to use:** When temporal separation matters more than repetition count.

**Example:**

```r
# Phase 3 pattern (R/50 line 429):
confirmed_exact <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  distinct(ID, DX_norm, DX_DATE, category) %>%
  group_by(ID, DX_norm) %>%
  filter(n_distinct(DX_DATE) >= 2) %>%          # Count-based
  ungroup() %>%
  group_by(category) %>%
  summarise(confirmed_patients = n_distinct(ID), .groups = "drop")

# Phase 4 pattern (R/51 equivalent):
confirmed_exact <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  distinct(ID, DX_norm, DX_DATE, category) %>%
  group_by(ID, DX_norm) %>%
  filter(as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%  # Span-based
  ungroup() %>%
  group_by(category) %>%
  summarise(confirmed_patients = n_distinct(ID), .groups = "drop")
```

**Source:** Existing codebase pattern from R/43_treatment_durations.R line 501, R/44_treatment_episodes.R line 466.

### Pattern 2: Base R Date Arithmetic

**What:** Subtract Date objects directly; result is difftime in days; coerce to numeric for comparison.

**When to use:** For simple date span calculations without timezone/period complexity.

**Example:**

```r
# Standard approach (used in R/43, R/44)
episode_span_days = as.numeric(max(treatment_date) - min(treatment_date))

# For Phase 4 filter context
filter(as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7)
```

**Why `as.numeric()`:** Date subtraction returns difftime class. `as.numeric()` converts to numeric days for clean comparison. Without it, comparison operators work but produce warnings in some contexts.

### Pattern 3: Script Cloning for Parameter Variations

**What:** Create numbered script variants (R/50, R/51) for different thresholds instead of parameterizing a single script.

**When to use:** When outputs are standalone artifacts for comparison (not automated pipeline steps).

**Rationale:**
- Phase 3 and 4 outputs are exploratory/descriptive (not pipeline dependencies)
- Users compare side-by-side xlsx files manually
- Separate scripts ensure reproducibility without parameter confusion
- Established pattern in this codebase (multiple numbered scripts for variations)

### Anti-Patterns to Avoid

- **Don't use lubridate for simple spans:** `as.numeric(max(date) - min(date))` is clearer than `interval(min(date), max(date)) %>% time_length("days")` for this use case.
- **Don't filter before distinct():** The distinct() call (line 427 in R/50) deduplicates patient-code-date combinations before counting. Moving filter before distinct could miscalculate date spans.
- **Don't mutate date span as column then filter:** `mutate(span = max(date) - min(date)) %>% filter(span >= 7)` materializes unnecessary column. Filter inline.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Date span calculation | Custom date diff logic | Base R date arithmetic (`as.numeric(max(date) - min(date))`) | Already reliable and used throughout codebase (R/43, R/44) |
| ICD code classification | New PREFIX_MAP | Exact copy from R/50 | PREFIX_MAP is authoritative (53 categories, 302 lines); duplication ensures script independence |
| Excel styling | Manual xml manipulation | openxlsx2 wb_* functions | R/50 established pattern works; xlsx format quirks handled |

**Key insight:** Phase 4 is a filter-level change, not an architecture change. Reuse 99% of R/50 verbatim.

## Common Pitfalls

### Pitfall 1: Date Span Calculation on Single-Date Records

**What goes wrong:** If a patient has only one date for a code, `max(date) - min(date)` returns 0 days (same date), which fails the >= 7 filter. This correctly excludes single-date codes but may surprise if not documented.

**Why it happens:** The 7-day requirement implicitly requires 2+ distinct dates (you can't have 7 days between a single date). But the logic is "span >= 7" not "count >= 2 AND span >= 7."

**How to avoid:** Accept this as correct behavior. Document in script comments that span-based filter subsumes the count requirement. If a patient has dates [2020-01-01, 2020-01-01] (duplicates), distinct() collapses to single date, span = 0, excluded. This is epidemiologically sound.

**Warning signs:** If confirmation rates in Phase 4 are dramatically lower than Phase 3, verify date quality (many duplicate dates?) vs. expected tightening from 7-day gap.

### Pitfall 2: Forgetting to Group by Prefix in Prefix-Level Confirmation

**What goes wrong:** Copy-pasting the exact code filter for prefix confirmation without changing `group_by(ID, DX_norm)` to `group_by(ID, prefix3)` will calculate spans across exact codes, not prefixes.

**Why it happens:** The only difference between exact and prefix confirmation (R/50 lines 425-432 vs. 474-481) is the grouping variable. Easy to miss during modification.

**How to avoid:** When modifying R/51, change both filter lines (exact and prefix sections) independently. Grep for `group_by(ID, DX_norm)` and `group_by(ID, prefix3)` to verify both sections updated.

**Warning signs:** Prefix confirmation rates identical to exact confirmation rates (should be higher since prefix aggregates codes).

### Pitfall 3: NA Date Handling

**What goes wrong:** If `filter(!is.na(DX_DATE))` is omitted, `max(DX_DATE) - min(DX_DATE)` returns NA when any date is NA, causing the entire group to be dropped silently.

**Why it happens:** Date arithmetic propagates NAs.

**How to avoid:** R/50 already includes `filter(!is.na(DX_DATE))` at line 426 (exact) and 475 (prefix). Keep this line unchanged when cloning to R/51.

**Warning signs:** Unexpectedly low patient counts with no error messages.

### Pitfall 4: Date Class Assumptions

**What goes wrong:** If DX_DATE is stored as character or timestamp (datetime) instead of Date, date arithmetic may fail or produce incorrect units.

**Why it happens:** PCORnet DuckDB schema uses DATE type, but R may coerce on import depending on dplyr translation.

**How to avoid:** R/50 uses `get_pcornet_table("DIAGNOSIS")` which reads DX_DATE as Date class via DBI/duckdb. Verify with `class(dx_cancer$DX_DATE)` if issues arise. Convert with `as.Date()` if needed.

**Warning signs:** `as.numeric(max(date) - min(date))` returns very large numbers (seconds instead of days) or errors like "non-numeric argument to binary operator."

## Code Examples

Verified patterns from R/50 (Phase 3 implementation):

### Exact Code Confirmation with 7-Day Gap

```r
# Source: Adapted from R/50_cancer_site_confirmation.R lines 425-432
# Modification: Line 429 filter changed from count >= 2 to span >= 7

confirmed_exact <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%                           # Remove NA dates
  distinct(ID, DX_norm, DX_DATE, category) %>%          # Deduplicate
  group_by(ID, DX_norm) %>%                             # Per patient-code
  filter(as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%  # 7-day span
  ungroup() %>%
  group_by(category) %>%                                # Per category
  summarise(confirmed_patients = n_distinct(ID), .groups = "drop")
```

### Prefix-Level Confirmation with 7-Day Gap

```r
# Source: Adapted from R/50_cancer_site_confirmation.R lines 474-481
# Modification: Line 478 filter changed from count >= 2 to span >= 7

confirmed_prefix <- dx_prefix %>%
  filter(!is.na(DX_DATE)) %>%                           # Remove NA dates
  distinct(ID, prefix3, DX_DATE, category) %>%          # Deduplicate
  group_by(ID, prefix3) %>%                             # Per patient-prefix
  filter(as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%  # 7-day span
  ungroup() %>%
  group_by(category) %>%                                # Per category
  summarise(confirmed_patients = n_distinct(ID), .groups = "drop")
```

### Date Span Verification (for debugging)

```r
# Check date span distribution before filtering (optional QA)
date_spans <- dx_cancer %>%
  filter(!is.na(DX_DATE)) %>%
  distinct(ID, DX_norm, DX_DATE, category) %>%
  group_by(ID, DX_norm) %>%
  summarise(
    n_dates = n_distinct(DX_DATE),
    span_days = as.numeric(max(DX_DATE) - min(DX_DATE)),
    .groups = "drop"
  )

# Summary: How many patient-code pairs have 7+ day spans?
table(date_spans$span_days >= 7)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single-date diagnosis codes accepted | 2+ distinct dates required (Phase 3) | 2026-05-19 | Filters out rule-out diagnoses |
| Any 2 dates sufficient | Dates must be 7+ days apart (Phase 4) | 2026-05-19 (this phase) | Strengthens temporal separation requirement |

**Deprecated/outdated:**

None. This is new analysis, not replacing existing patterns.

**Rationale for 7-day threshold:**

- Standard epidemiological practice: single encounter codes may reflect differential diagnosis; repeat codes on temporally separated encounters suggest confirmed diagnosis
- 7 days balances false negatives (too strict) vs. false positives (same-week follow-up visits)
- Not from formal guideline, but epidemiologically reasonable and user-specified in phase description

## Open Questions

1. **Should Phase 4 report span statistics (min/max/median date span) in addition to confirmation counts?**
   - What we know: D-05 specifies same column structure as Phase 3 (total/confirmed/unconfirmed/rate). No span statistics mentioned.
   - What's unclear: Would knowing "median span = 45 days for confirmed Hodgkin Lymphoma" add value?
   - Recommendation: Defer to v2. D-02 says "no comparison columns from Phase 3 included" — interpret conservatively as "keep columns identical to Phase 3."

2. **How sensitive is confirmation rate to the 7-day threshold? (5 days? 14 days?)**
   - What we know: User chose 7 days in phase description. D-06 locks this as the definition.
   - What's unclear: No sensitivity analysis requested.
   - Recommendation: Implement 7-day threshold as specified. If user wants sensitivity analysis, that's a future phase (Phase 5?).

3. **Should unconfirmed patients be flagged for manual chart review?**
   - What we know: Phase 4 scope is "produce styled xlsx" (D-02). No mention of flagging for review.
   - What's unclear: Downstream use of unconfirmed patient lists.
   - Recommendation: Out of scope. Confirmation output is descriptive (category-level summaries), not actionable (patient-level lists). No patient-level output planned.

## Environment Availability

> Skip this section if the phase has no external dependencies (code/config-only changes).

Phase 4 is code-only. All dependencies inherited from Phase 3 (already verified working in R/50 execution). No new tools or services required.

## Sources

### Primary (HIGH confidence)
- R/50_cancer_site_confirmation.R (Phase 3 implementation) — Complete reference for script structure, PREFIX_MAP, classification, xlsx styling
- R/43_treatment_durations.R line 501, R/44_treatment_episodes.R line 466 — Established date span calculation pattern (`as.numeric(max(date) - min(date))`)
- .planning/phases/04-.../04-CONTEXT.md — User decisions (D-01 through D-07)
- .planning/phases/03-.../03-CONTEXT.md — Phase 3 decisions carried forward

### Secondary (MEDIUM confidence)
- Base R documentation: Date arithmetic behavior well-documented and stable across R versions
- dplyr 1.2.0 documentation: filter() behavior in grouped context

### Tertiary (LOW confidence)
- None (no external web search needed; all patterns exist in codebase)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already in use in Phase 3; no new dependencies
- Architecture: HIGH - Straightforward modification to existing script; pattern established in R/43, R/44
- Pitfalls: HIGH - Pitfalls documented from Phase 3 experience (distinct() positioning, NA handling) plus standard date arithmetic edge cases

**Research date:** 2026-05-19
**Valid until:** 2026-06-19 (30 days — stable domain, no fast-moving dependencies)
