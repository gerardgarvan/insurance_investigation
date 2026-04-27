# Phase 35: Tiered Same-Day Payer Categorization - Research

**Researched:** 2026-04-27
**Domain:** PCORnet payer data harmonization with hierarchical same-day resolution
**Confidence:** HIGH

## Summary

Phase 35 implements a two-part deliverable: (1) raw payer code frequency tables with PayerVariable.xlsx cross-reference for both all-encounter and AV+TH scopes, and (2) hierarchical same-day payer resolution per Amy Crisp's tiered framework (Medicaid > Medicare > Private > Other > Self-pay > Uninsured > Missing). This is a standalone diagnostic script pattern following Phase 33/34 structural conventions, using DuckDB materialize-early for all operations.

The core technical challenge is implementing a configurable tier mapping that translates the existing 9-category payer scheme (from R/02_harmonize_payer.R) into 6 tiers, then applying a max-rank resolution rule to patient-date groups. Special rules include: codes 93 and 14 explicitly map to Medicaid, and any encounter with ENCOUNTER.SOURCE = 'FLM' forces the entire patient-date to resolve as Medicaid (Florida Medicaid claims override).

**Primary recommendation:** Use a named-list tier mapping at script top (code → tier_rank) for PI editability, then implement same-day resolution as a two-stage group-by-summarize: (1) identify multi-encounter patient-dates, (2) apply max(tier_rank) within each group with resolution_reason tracking (which rule fired). Output 6 resolution CSVs (3 per scope) + 4 frequency CSVs (2 per scope) = 10 total CSVs.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Tier mapping defined as a configurable lookup (named list or data frame) at the top of the script — NOT buried in case_when logic. This allows PIs to change mappings (e.g., "move code 93 from Medicaid to Medicare") with a one-line edit.
- **D-02:** The 6 tiers are: Medicaid, Medicare, Private, Other, Self-pay, Uninsured, Missing. These collapse the R pipeline's 9 categories: Dual eligible → Medicaid, Other government → Other, No payment/Self-pay → Self-pay, Unavailable + Unknown → Missing.
- **D-03:** Special rules per Amy Crisp: codes 93 and 14 explicitly map to Medicaid. If any encounter on a patient-date has ENCOUNTER.SOURCE = 'FLM', the resolved payer for that date is Medicaid (FLM = Florida Medicaid claims).
- **D-04:** The FLM override uses ENCOUNTER.SOURCE (not DEMOGRAPHIC.SOURCE) — it checks whether any individual encounter on that date came from the FLM claims feed.
- **D-05:** Produce raw payer code frequency tables for BOTH all encounters AND AV+TH encounters, with PayerVariable.xlsx cross-reference (same format as Phase 34: code, description, xlsx category, count, percentage).
- **D-06:** This is a NEW script — does not modify Phase 34's `R/35_payer_code_frequency_av_th.R`, which remains as a verified baseline.
- **D-07:** Three CSVs per scope (all-encounter and AV+TH, so 6 resolution CSVs total + 4 frequency CSVs):
  - CSV A: Per-patient-per-date detail with resolved_payer, original codes, n_encounters, resolution_reason (which tier rule fired)
  - CSV B: Patient-level summary with modal resolved payer across all dates
  - CSV C: Aggregate category distribution before vs after resolution (showing impact of the hierarchy)
- **D-08:** Frequency table outputs: primary code freq, secondary code freq, category summary — for both all-encounter and AV+TH scopes.
- **D-09:** Standalone diagnostic script following Phase 33/34 pattern: `source("R/00_config.R")`, DuckDB materialize-early, conditional RDS fallback.
- **D-10:** Does NOT modify `R/02_harmonize_payer.R` or any core pipeline script. The same-day resolution can be promoted to the pipeline later if PIs approve the approach.

### Claude's Discretion
- Script numbering (likely R/36_*.R)
- Console summary format and detail level
- CSV file naming convention (with `_all` and `_av_th` suffixes to distinguish scopes)
- Whether to produce the raw frequency tables and resolution outputs in a single script or split into two
- Sort order of detail-level output (by patient then date, or by resolved payer category)
- How to handle dates with only a single encounter (pass through with resolution_reason = "single encounter")

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Standard for grouping, summarizing, and joining patient-date encounter groups |
| readr | 2.2.0+ | CSV I/O | write_csv() for all 10 output files |
| readxl | 1.4.3+ | Excel reading | read_excel() for PayerVariable.xlsx lookup |
| glue | 1.8.0 | String formatting | Console logging and message formatting |
| lubridate | 1.9.3+ | Date operations | Date parsing for ADMIT_DATE (inherited from Phase 33) |
| stringr | 1.5.1+ | String operations | str_starts() for prefix-based payer code matching (inherited from R/02_harmonize_payer.R) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DBI + duckdb | 0.9.2+ / 1.1.3+ | DuckDB backend | Backend-transparent access via get_pcornet_table(), materialize-early pattern |

**Installation:**
```bash
# All dependencies already installed in project renv
# No new packages needed — Phase 35 reuses Phase 33/34 stack
```

**Version verification:** Versions inherited from existing renv.lock (verified in Phase 32 DuckDB migration).

## Architecture Patterns

### Recommended Project Structure
Phase 35 creates a NEW standalone script in the R/ directory:
```
R/
├── 36_tiered_same_day_payer.R  # NEW: Phase 35 script (numbering Claude's discretion)
├── 35_payer_code_frequency_av_th.R  # Phase 34 baseline (unchanged)
├── 33_multi_source_overlap_av_th.R  # Phase 33 pattern reference
├── 02_harmonize_payer.R  # Existing 9-category logic (reference only)
├── 00_config.R  # PAYER_MAPPING definition (reference, not modified)
└── utils_duckdb.R  # DuckDB helpers (get_pcornet_table, materialize, open_pcornet_con)

output/tables/
├── payer_resolved_detail_all.csv  # NEW: CSV A (all-encounter scope)
├── payer_resolved_detail_av_th.csv  # NEW: CSV A (AV+TH scope)
├── payer_resolved_patient_summary_all.csv  # NEW: CSV B (all-encounter)
├── payer_resolved_patient_summary_av_th.csv  # NEW: CSV B (AV+TH)
├── payer_resolved_impact_all.csv  # NEW: CSV C (all-encounter)
├── payer_resolved_impact_av_th.csv  # NEW: CSV C (AV+TH)
├── payer_primary_code_freq_all.csv  # NEW: Frequency table (all-encounter)
├── payer_primary_code_freq_av_th.csv  # Exists: Phase 34 baseline (unchanged)
├── payer_secondary_code_freq_all.csv  # NEW: Frequency table (all-encounter)
├── payer_secondary_code_freq_av_th.csv  # Exists: Phase 34 baseline (unchanged)
├── payer_category_summary_all.csv  # NEW: Category-level (all-encounter)
└── payer_category_summary_av_th.csv  # Exists: Phase 34 baseline (unchanged)
```

### Pattern 1: Configurable Tier Mapping (D-01 Compliance)
**What:** Define tier-to-rank mapping as a named list at script top, NOT buried in case_when()
**When to use:** Allows PIs to edit tier assignments with a one-line change
**Example:**
```r
# Source: User requirement D-01
# Top of script (SECTION 0: Setup)

# Tier hierarchy: lower rank = higher priority
TIER_MAPPING <- list(
  Medicaid   = 1L,  # Highest priority (includes dual-eligible, codes 93/14, FLM source)
  Medicare   = 2L,
  Private    = 3L,
  Other      = 4L,
  Self_pay   = 5L,
  Uninsured  = 6L,
  Missing    = 7L   # Lowest priority
)

# Code-to-tier mapping (D-02 collapse from 9 categories to 6 tiers)
CODE_TO_TIER <- function(payer_category_9cat) {
  case_when(
    payer_category_9cat == "Medicaid"           ~ "Medicaid",
    payer_category_9cat == "Dual eligible"      ~ "Medicaid",  # D-02 collapse
    payer_category_9cat == "Medicare"           ~ "Medicare",
    payer_category_9cat == "Private"            ~ "Private",
    payer_category_9cat == "Other government"   ~ "Other",     # D-02 collapse
    payer_category_9cat == "Other"              ~ "Other",
    payer_category_9cat == "No payment / Self-pay" ~ "Self_pay",
    payer_category_9cat == "Uninsured"          ~ "Uninsured",
    payer_category_9cat == "Unavailable"        ~ "Missing",   # D-02 collapse
    payer_category_9cat == "Unknown"            ~ "Missing",   # D-02 collapse
    is.na(payer_category_9cat)                  ~ "Missing",
    TRUE                                        ~ "Missing"
  )
}

# Special code overrides (D-03)
SPECIAL_CODE_TIER <- function(effective_payer) {
  case_when(
    effective_payer %in% c("93", "14") ~ "Medicaid",  # Amy Crisp explicit rule
    TRUE ~ NA_character_  # No override — use CODE_TO_TIER result
  )
}
```

### Pattern 2: Materialize-Early DuckDB Pattern (Phase 32/33/34 Established)
**What:** Load ENCOUNTER table via get_pcornet_table(), materialize immediately, then perform all operations in-memory
**When to use:** All Phase 35 operations (grouping, joining, filtering) to avoid dbplyr translation gaps
**Example:**
```r
# Source: Phase 33 R/33_multi_source_overlap_av_th.R lines 64-66
enc <- get_pcornet_table("ENCOUNTER") %>%
  materialize()  # Collect to tibble immediately

# Then apply scope filter (all-encounter or AV+TH)
enc_av_th <- enc %>% filter(ENC_TYPE %in% c("AV", "TH"))
```

### Pattern 3: Same-Day Resolution Logic
**What:** Group encounters by (ID, ADMIT_DATE), apply tier hierarchy to resolve single payer per patient-date
**When to use:** Core resolution logic for CSV A/B/C outputs
**Example:**
```r
# Source: Amy Crisp framework (payer_framework.txt)
# Step 1: Assign tier to each encounter
enc_with_tier <- enc %>%
  mutate(
    # Map existing 9-category payer_category to 6 tiers
    tier = CODE_TO_TIER(payer_category),
    # Override with special codes (93, 14)
    tier = coalesce(SPECIAL_CODE_TIER(effective_payer), tier),
    # Override with FLM source rule (D-03, D-04)
    tier = if_else(SOURCE == "FLM", "Medicaid", tier),
    # Assign rank for resolution
    tier_rank = TIER_MAPPING[[tier]]
  )

# Step 2: Group by patient-date, resolve to highest-priority tier (min rank)
resolved_detail <- enc_with_tier %>%
  group_by(ID, ADMIT_DATE) %>%
  summarise(
    n_encounters = n(),
    n_distinct_tiers = n_distinct(tier),
    resolved_payer = tier[which.min(tier_rank)],  # Tier with lowest rank wins
    resolution_reason = case_when(
      n() == 1 ~ "single encounter",
      any(SOURCE == "FLM") ~ "FLM source override",
      any(effective_payer %in% c("93", "14")) ~ "special code override (93/14)",
      TRUE ~ glue("tier hierarchy ({n_distinct_tiers} tiers present)")
    ),
    original_tiers = paste(sort(unique(tier)), collapse = "+"),
    .groups = "drop"
  )
```

### Pattern 4: Dual-Scope Output (All-Encounter + AV+TH)
**What:** Produce all 10 CSVs for BOTH all-encounter and AV+TH scopes
**When to use:** All output generation sections
**Example:**
```r
# Source: User requirement D-05, D-07, D-08
# Generate outputs twice: once for all encounters, once for AV+TH filter

# Scope 1: All encounters
enc_all <- enc  # No filter
output_suffix_all <- "_all"

# Scope 2: AV+TH only
enc_av_th <- enc %>% filter(ENC_TYPE %in% c("AV", "TH"))
output_suffix_av_th <- "_av_th"

# Loop over scopes (or duplicate code blocks with suffix substitution)
for (scope in list(
  list(data = enc_all, suffix = output_suffix_all),
  list(data = enc_av_th, suffix = output_suffix_av_th)
)) {
  # ... run resolution and frequency logic ...
  # Write CSVs with scope$suffix appended
}
```

### Pattern 5: Frequency Table with PayerVariable.xlsx Cross-Reference (Phase 34 Reuse)
**What:** Count distinct PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY codes, left-join to PayerVariable.xlsx for description + category
**When to use:** Frequency table outputs (CSV for primary codes, CSV for secondary codes, CSV for category summary)
**Example:**
```r
# Source: Phase 34 R/35_payer_code_frequency_av_th.R lines 69-92, 129-151
payer_lookup <- readxl::read_excel("PayerVariable.xlsx", sheet = "Sheet2")
names(payer_lookup) <- c("code", "description", "category")
payer_lookup <- payer_lookup %>%
  mutate(across(everything(), ~trimws(as.character(.))))

primary_freq <- enc %>%
  mutate(
    code = case_when(
      is.na(PAYER_TYPE_PRIMARY) ~ "<NA>",
      PAYER_TYPE_PRIMARY == "" ~ "<EMPTY>",
      TRUE ~ PAYER_TYPE_PRIMARY
    )
  ) %>%
  count(code, name = "n") %>%
  left_join(payer_lookup, by = "code") %>%
  mutate(
    description = ifelse(is.na(description) & !code %in% c("<NA>", "<EMPTY>"),
                         "NOT IN XLSX", description),
    category = ifelse(is.na(category) & !code %in% c("<NA>", "<EMPTY>"),
                      "NOT IN XLSX", category),
    pct = round(100 * n / nrow(enc), 2)
  ) %>%
  arrange(desc(n))
```

### Anti-Patterns to Avoid

- **Hardcoded tier logic in case_when():** Violates D-01 (PI editability requirement). Use TIER_MAPPING named list at script top.
- **Lazy DuckDB queries for grouping operations:** Phase 32 established materialize-early as the standard pattern. Lazy queries cause translation gaps.
- **Modifying R/02_harmonize_payer.R or R/00_config.R:** Violates D-10 (standalone diagnostic script, no pipeline changes).
- **Single-scope output:** Violates D-05 and D-07 (BOTH all-encounter AND AV+TH scopes required for all outputs).
- **Using DEMOGRAPHIC.SOURCE for FLM override:** Violates D-04 (must use ENCOUNTER.SOURCE per-encounter, not per-patient).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Payer code frequency counting | Custom aggregation logic | Phase 34 pattern (count + left_join to xlsx) | Already verified, handles NA/EMPTY/NOT IN XLSX cases correctly |
| Date parsing | Custom regex parsers | Phase 33 pattern (as.Date + parse_pcornet_date fallback) | Handles multiple SAS export formats, already tested on HiPerGator |
| DuckDB connection management | Manual dbConnect/dbDisconnect | open_pcornet_con() / close_pcornet_con() from utils_duckdb.R | Enforces read-only mode, creates TUMOR_REGISTRY_ALL view automatically |
| Tier ranking logic | Nested if-else chains | Named list TIER_MAPPING with numeric ranks | Allows PI editing without touching case_when logic, prevents off-by-one errors |

**Key insight:** Phase 33 and Phase 34 provide complete structural templates. Phase 35 is a recombination: Phase 34's frequency logic + Phase 33's DuckDB materialize-early + new same-day resolution logic. The only novel code is the tier mapping and patient-date grouping.

## Environment Availability

> All external dependencies verified in Phase 32 (DuckDB migration). No new dependencies introduced.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| DuckDB | Backend-transparent table access | ✓ | 1.1.3 (verified Phase 32) | — |
| readxl | PayerVariable.xlsx reading | ✓ | 1.4.3 (verified Phase 34) | — |
| R 4.4.2+ | All operations | ✓ | 4.4.2 (HiPerGator module) | — |
| tidyverse | dplyr, readr, stringr, glue, lubridate | ✓ | 2.0.0+ (verified Phase 32) | — |

**Missing dependencies with no fallback:** None

**Missing dependencies with fallback:** None

## Common Pitfalls

### Pitfall 1: FLM Override Applied at Wrong Granularity
**What goes wrong:** Applying FLM override at patient level (any patient with FLM encounters → all dates Medicaid) instead of patient-date level (only dates with FLM encounters → Medicaid).
**Why it happens:** Misreading D-04 as "if patient has any FLM encounter, resolve all their dates to Medicaid."
**How to avoid:** Use ENCOUNTER.SOURCE within the group_by(ID, ADMIT_DATE) summarise, checking if any(SOURCE == "FLM") per date.
**Warning signs:** FLM patients with non-FLM encounters on other dates showing resolved_payer = "Medicaid" for ALL dates.

### Pitfall 2: Tier Mapping vs Code Mapping Confusion
**What goes wrong:** Mapping raw PAYER_TYPE_PRIMARY codes directly to tiers, skipping the 9-category intermediate step.
**Why it happens:** The existing `map_payer_category()` function in R/02_harmonize_payer.R already performs prefix-based mapping (1→Medicare, 2→Medicaid, etc.). Phase 35 collapses the 9 categories to 6 tiers, not the raw codes.
**How to avoid:** Reuse `map_payer_category()` logic to get 9-category payer_category first, THEN apply CODE_TO_TIER() to collapse to 6 tiers.
**Warning signs:** Codes like "141" (dual-eligible) not mapping to Medicaid tier, or "99" (Unavailable) not collapsing to Missing.

### Pitfall 3: Forgetting to Materialize Before Grouping
**What goes wrong:** Lazy DuckDB query attempts to execute group_by() + summarise() with custom functions (TIER_MAPPING lookup, which.min()), causing dbplyr translation errors.
**Why it happens:** Phase 32 established materialize-early as the standard, but it's easy to forget the collect step.
**How to avoid:** Always `materialize()` immediately after `get_pcornet_table()` and any scope filters. All downstream operations are in-memory.
**Warning signs:** Error messages like "no applicable method for 'group_by' applied to an object of class 'tbl_dbi'".

### Pitfall 4: Missing NA Handling in Tier Assignment
**What goes wrong:** Encounters with is.na(payer_category) or is.na(effective_payer) fail to map to "Missing" tier, causing NA propagation through tier_rank and which.min() errors.
**Why it happens:** CODE_TO_TIER() case_when() doesn't have an explicit NA catch-all (though it should per the pattern above).
**How to avoid:** Ensure CODE_TO_TIER() has `is.na(payer_category_9cat) ~ "Missing"` as a case, and `TRUE ~ "Missing"` as the final catch-all.
**Warning signs:** NA values appearing in resolved_payer column of CSV A, or "missing value where TRUE/FALSE needed" errors in which.min().

### Pitfall 5: Duplicate Suffix Collision (All-Encounter vs AV+TH)
**What goes wrong:** Writing CSV outputs for all-encounter scope with `_av_th` suffix by mistake (or vice versa), overwriting Phase 34 baseline files.
**Why it happens:** Copy-paste error when duplicating code blocks for the two scopes.
**How to avoid:** Use a loop or function with scope-specific suffix variables. Verify output file names before write_csv().
**Warning signs:** Phase 34 baseline CSVs (`payer_primary_code_freq_av_th.csv`, etc.) showing different row counts after Phase 35 run.

## Code Examples

Verified patterns from official sources:

### Special Code Override (D-03)
```r
# Source: Amy Crisp framework (payer_framework.txt)
# "including 93 and 14" → explicit Medicaid mapping

enc_with_overrides <- enc %>%
  mutate(
    # Apply special code rule BEFORE tier mapping
    tier_override = case_when(
      PAYER_TYPE_PRIMARY == "93" ~ "Medicaid",
      PAYER_TYPE_PRIMARY == "14" ~ "Medicaid",
      PAYER_TYPE_SECONDARY == "93" ~ "Medicaid",  # Check both fields
      PAYER_TYPE_SECONDARY == "14" ~ "Medicaid",
      TRUE ~ NA_character_
    )
  )
```

### FLM Source Override (D-03, D-04)
```r
# Source: Amy Crisp framework (payer_framework.txt)
# "if FLM is a source" → ENCOUNTER.SOURCE check, not DEMOGRAPHIC.SOURCE

resolved_detail <- enc_with_tier %>%
  group_by(ID, ADMIT_DATE) %>%
  summarise(
    resolved_payer = if_else(
      any(SOURCE == "FLM"),  # Check ENCOUNTER.SOURCE per date
      "Medicaid",
      tier[which.min(tier_rank)]  # Else use tier hierarchy
    ),
    resolution_reason = if_else(
      any(SOURCE == "FLM"),
      "FLM source override",
      glue("tier hierarchy ({n_distinct(tier)} tiers)")
    ),
    .groups = "drop"
  )
```

### Before vs After Comparison (CSV C)
```r
# Source: User requirement D-07 (CSV C)
# Show impact of hierarchical resolution on category distribution

# Before resolution: count encounters by tier
before_resolution <- enc_with_tier %>%
  count(tier, name = "n_encounters_before")

# After resolution: count patient-dates by resolved_payer
after_resolution <- resolved_detail %>%
  count(resolved_payer, name = "n_patient_dates_after")

# Combined impact table
impact <- before_resolution %>%
  full_join(after_resolution, by = c("tier" = "resolved_payer")) %>%
  mutate(
    n_encounters_before = coalesce(n_encounters_before, 0L),
    n_patient_dates_after = coalesce(n_patient_dates_after, 0L),
    change = n_patient_dates_after - n_encounters_before
  ) %>%
  arrange(TIER_MAPPING[[tier]])  # Sort by tier priority
```

### Patient-Level Modal Summary (CSV B)
```r
# Source: User requirement D-07 (CSV B)
# Modal resolved_payer across all patient-dates

patient_summary <- resolved_detail %>%
  group_by(ID, resolved_payer) %>%
  summarise(n_dates_with_payer = n(), .groups = "drop") %>%
  arrange(ID, desc(n_dates_with_payer), resolved_payer) %>%
  group_by(ID) %>%
  slice(1) %>%
  ungroup() %>%
  select(ID, modal_resolved_payer = resolved_payer, n_dates_with_payer)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual tier assignment in downstream analysis | Configurable TIER_MAPPING lookup at script top | Phase 35 (D-01 requirement) | PIs can edit tier rules without touching case_when logic |
| Encounter-level payer category only | Patient-date-level resolved payer with hierarchy | Phase 35 (Amy Crisp framework) | Resolves multi-encounter same-day payer conflicts |
| 9-category payer scheme | 6-tier collapsed scheme (Medicaid/Medicare/Private/Other/Self-pay/Uninsured/Missing) | Phase 35 (D-02) | Simplifies presentation, collapses rare categories (Dual→Medicaid, Other govt→Other) |
| AV+TH scope only (Phase 34 baseline) | Dual-scope outputs (all-encounter AND AV+TH) | Phase 35 (D-05) | Allows comparison of payer patterns across encounter types |

**Deprecated/outdated:**
- **Single-encounter-type analysis:** Phase 34 analyzed AV+TH only. Phase 35 introduces dual-scope analysis (all encounters + AV+TH) as the new standard for payer diagnostics.

## Open Questions

1. **CSV naming convention for all-encounter scope**
   - What we know: Phase 34 uses `_av_th` suffix for AV+TH scope. User decision D-07 requires dual-scope outputs.
   - What's unclear: Should all-encounter scope use `_all` suffix or no suffix? (Recommendation: `_all` for symmetry, prevents confusion.)
   - Recommendation: Use `_all` suffix for all-encounter scope, `_av_th` suffix for AV+TH scope. Document in CSV output section console messages.

2. **Handling dates with only a single encounter**
   - What we know: Same-day resolution is designed for multi-encounter dates. Single-encounter dates have no conflict to resolve.
   - What's unclear: Should these pass through with resolved_payer = tier and resolution_reason = "single encounter", or should they be excluded from CSV A?
   - Recommendation: Include in CSV A with resolution_reason = "single encounter" for completeness. PIs may want to see the full patient-date timeline.

3. **Treatment of PAYER_TYPE_SECONDARY in resolution logic**
   - What we know: `compute_effective_payer()` in R/02_harmonize_payer.R already resolves primary vs secondary (primary if valid, else secondary). `map_payer_category()` operates on effective_payer.
   - What's unclear: Do we apply the tier hierarchy to effective_payer (already-resolved), or do we treat primary and secondary separately within a patient-date?
   - Recommendation: Use effective_payer (already-resolved per encounter). The hierarchy operates on encounter-level effective payer, not on separate primary/secondary fields. This matches the existing pipeline logic.

## Canonical References

**Must read before planning:**

1. **payer_framework.txt** — Amy Crisp's email defining the tiered hierarchy: Medicaid (incl. 93, 14, FLM source) > Medicare > Private > Other > Self-pay > Uninsured > Missing. This is the authoritative source for the resolution logic.

2. **PayerVariable.xlsx (Sheet2)** — 166-row lookup table with 3 columns: "Value In Data" (raw code), "What old value means" (description), "New Value" (mapped category). Used for frequency table cross-reference.

3. **R/02_harmonize_payer.R** — `map_payer_category()` function with 9-category prefix-based mapping and dual-eligible detection. Reference for understanding existing code-to-category logic (not reused directly, but informs the tier mapping).

4. **R/00_config.R lines 285-314** — `PAYER_MAPPING` definition with prefix rules, exact-match overrides, sentinel values, and 9 category list.

5. **R/35_payer_code_frequency_av_th.R** — Phase 34 script: standalone AV+TH payer code frequency with PayerVariable.xlsx cross-reference. Structural template for the frequency table portion.

6. **R/33_multi_source_overlap_av_th.R** — Phase 33 standalone AV+TH diagnostic pattern with DuckDB materialize-early.

7. **R/utils_duckdb.R** — `get_pcornet_table()`, `open_pcornet_con()`, `materialize()` helpers

## Sources

### Primary (HIGH confidence)
- **payer_framework.txt** (Amy Crisp email) — Authoritative specification for tier hierarchy and special rules (FLM source, codes 93/14)
- **35-CONTEXT.md** — User decisions from `/gsd:discuss-phase`, all implementation constraints verified
- **R/35_payer_code_frequency_av_th.R** (Phase 34) — Verified frequency table pattern, PayerVariable.xlsx cross-reference logic
- **R/33_multi_source_overlap_av_th.R** (Phase 33) — Verified DuckDB materialize-early pattern, dual-scope output structure
- **R/02_harmonize_payer.R** — Verified 9-category mapping logic, compute_effective_payer() and map_payer_category() functions
- **R/00_config.R** — PAYER_MAPPING definition with prefix rules and exact-match overrides

### Secondary (MEDIUM confidence)
- **CLAUDE.md** — Project constraints: tidyverse ecosystem, DuckDB backend, named predicate style, HiPerGator environment

### Tertiary (LOW confidence)
None — all research based on authoritative project files and user decisions.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All packages verified in Phase 32 (DuckDB migration), Phase 33 (multi-source overlap), Phase 34 (payer code frequency)
- Architecture patterns: HIGH — All patterns inherited from verified Phase 33/34 scripts with explicit user decisions from CONTEXT.md
- Tier mapping logic: HIGH — Amy Crisp framework (payer_framework.txt) is the authoritative specification, user decisions D-01 through D-10 are explicit and unambiguous
- Special rules (FLM source, codes 93/14): HIGH — Specified in payer_framework.txt and confirmed in CONTEXT.md D-03/D-04
- Output structure: HIGH — User decision D-07 specifies CSV A/B/C structure explicitly, D-08 specifies frequency table structure

**Research date:** 2026-04-27
**Valid until:** 60 days (stable domain — PCORnet CDM and payer harmonization logic are established, tier hierarchy from PI is locked)
