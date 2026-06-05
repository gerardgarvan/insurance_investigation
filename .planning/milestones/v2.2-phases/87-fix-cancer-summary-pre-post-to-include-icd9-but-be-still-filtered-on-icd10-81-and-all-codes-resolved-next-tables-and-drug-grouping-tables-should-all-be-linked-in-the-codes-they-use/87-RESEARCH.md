# Phase 87: Unify ICD-9/ICD-10 Cancer Code Usage - Research

**Researched:** 2026-06-04
**Domain:** ICD-9/ICD-10 cancer code harmonization in R
**Confidence:** HIGH

## Summary

Phase 87 unifies cancer diagnosis code handling across the R pipeline by extending ICD-10-only filters to include ICD-9 neoplasm codes (140-239 range). The pipeline currently hard-filters to `DX_TYPE == "10"` in 5 cancer summary scripts (R/45, R/47, R/48, R/49) and uses local cancer code detection in R/56. The phase will: (1) create a complete ICD-9 cancer site mapping covering all neoplasm categories, (2) extract `is_cancer_code()` to shared utilities, (3) expand HL cohort confirmation to include ICD-9 201.x codes, (4) handle cross-system code classification with separate ICD-9/ICD-10 maps, and (5) account for downstream ripple effects when the HL cohort artifact changes.

**Primary recommendation:** Build ICD9_CANCER_SITE_MAP as a parallel structure to CANCER_SITE_MAP using 3-digit prefix keys (140-209 for malignant), exclude benign/uncertain/in-situ ranges (210-239) to mirror D-code filtering logic, use map-based detection in shared `is_cancer_code()` for gap-free coverage, and implement category-level cross-system confirmation (1x ICD-9 201.x + 1x ICD-10 C81 = confirmed HL) while keeping code-level summaries separate.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Cancer Summary ICD-9 Scope:**
- D-01: R/45 through R/49 must include ICD-9 neoplasm codes alongside ICD-10. Remove all `DX_TYPE == "10"` hard-filters. Use shared `is_cancer_code()` utility.
- D-02: D-codes (benign, in-situ, uncertain behavior) remain EXCLUDED. R/47's D-code filtering stays in place. Applies to both ICD-10 D-codes and ICD-9 equivalents (210-239).
- D-03: Build full ICD-9 neoplasm category mapping covering ALL of 140-239 (not just HL-relevant codes). Every ICD-9 neoplasm prefix maps to same cancer categories used by CANCER_SITE_MAP.

**ICD-9 Cancer Site Map:**
- D-04: Create `ICD9_CANCER_SITE_MAP` as new named vector in R/00_config.R, separate from `CANCER_SITE_MAP`. Same pattern: 3-digit prefix keys mapping to cancer category strings.
- D-05: `classify_codes()` in R/utils/utils_cancer.R must check both maps. Detection order: ICD-10 4-char → ICD-10 3-char → ICD-9 exact match (existing 201.x logic) → ICD-9 3-char prefix → unclassified.

**Code List Unification:**
- D-06: Extract `is_cancer_code()` from R/56 to R/utils/utils_cancer.R as shared utility. All scripts (R/45, R/47, R/48, R/49, R/56, R/50 if applicable) source and use same function.
- D-07: R/56's local `is_cancer_code()` function replaced by shared version. No duplicate logic.

**all_codes_resolved Linkage:**
- D-08: R/50 does not need new cancer code columns. Linkage means ensuring that if R/50 references cancer codes, it uses shared `is_cancer_code()` utility. No structural changes to R/50 output.

**HL Cohort Anchor:**
- D-09: ICD-9 code 201.x counts toward HL cohort confirmation alongside ICD-10 C81. A patient with 2+ ICD-9 201.x codes with 7+ day gap is confirmed HL.
- D-10: Cross-system confirmation allowed at CATEGORY level: 1x ICD-9 201.x + 1x ICD-10 C81 with 7-day gap confirms HL for category-level summaries.
- D-11: Cross-system codes do NOT combine at individual CODE level. Code-level summary sheets keep 201.x and C81.x counts separate. Only category-level aggregation merges across coding systems.
- D-12: Downstream effects of cohort change MUST be identified and handled. confirmed_hl_cohort.rds may gain patients. Every script reading this artifact needs verification. Plans must explicitly list affected scripts and expected impact.

### Claude's Discretion

- Whether `is_cancer_code()` should use map-based detection (checking names of both CANCER_SITE_MAP and ICD9_CANCER_SITE_MAP) vs range-based detection (140-239 for ICD-9). Decision should avoid gaps between detection and classification.
- ICD-9 D-code equivalent identification: which ICD-9 ranges (210-239) correspond to ICD-10 D-codes for exclusion in cancer summary pipeline.
- Exact ICD-9 prefix-to-category mappings for full 140-239 range — research authoritative ICD-9 references for accurate category assignment.
- How to handle ICD-9 201.x subcategory mapping (201.0, 201.1, 201.2, 201.5, 201.6, 201.7, 201.9) to classical HL subtypes in 4-char matching tier.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

## Standard Stack

All required libraries already in use. No new dependencies.

### Core R Ecosystem (Already Established)
| Library | Version | Purpose | Project Usage |
|---------|---------|---------|---------------|
| stringr | 1.5.1+ | String pattern matching | ICD code prefix extraction, pattern detection in `classify_codes()` |
| dplyr | 1.2.0+ | Data transformation | Filter operations, case_when for category mapping |
| glue | 1.8.0 | String interpolation | Logging messages for code detection stats |

**No installation needed** — Phase 87 uses existing tidyverse ecosystem already loaded in all scripts.

## Architecture Patterns

### Existing Pattern: Centralized Configuration Maps

**What:** Named character vectors in R/00_config.R map code prefixes to category strings. Used across 10+ scripts via shared utilities.

**Example from CANCER_SITE_MAP (R/00_config.R:537-800):**
```r
CANCER_SITE_MAP <- c(
  "C00" = "Lip, Oral Cavity and Pharynx",
  "C01" = "Lip, Oral Cavity and Pharynx",
  # ... 324 entries total
  "C810" = "NLPHL",                           # 4-char for specificity
  "C81" = "Hodgkin Lymphoma (non-NLPHL)",     # 3-char fallback
  # ...
)
```

**For Phase 87:** Apply same pattern to ICD9_CANCER_SITE_MAP using 3-digit ICD-9 prefixes as keys.

### Existing Pattern: Shared Utility Functions

**What:** Common code detection/classification logic extracted to R/utils/ and sourced by multiple scripts. Prevents drift.

**Example from R/utils/utils_cancer.R:57-82 (classify_codes):**
```r
classify_codes <- function(codes) {
  # Step 1: Extract prefixes at both specificity levels (ICD-10)
  prefix4 <- substr(codes, 1, 4)  # C810 for NLPHL
  prefix3 <- substr(codes, 1, 3)  # C81 fallback

  # Step 2: 4-char match first (more specific wins)
  match4 <- CANCER_SITE_MAP[prefix4]

  # Step 3: Fallback to 3-char
  match3 <- CANCER_SITE_MAP[prefix3]

  # Step 4: Use 4-char if available, else 3-char
  categories <- ifelse(!is.na(match4), match4, match3)

  # Step 5: ICD-9 HL exact match (existing logic)
  is_icd9_hl <- grepl("^201(\\..*)?$", codes)
  is_icd9_nlphl <- codes %in% ICD9_NLPHL_CODES
  categories[is_icd9_hl & !is_icd9_nlphl] <- "Hodgkin Lymphoma (non-NLPHL)"
  categories[is_icd9_nlphl] <- "NLPHL"

  unname(categories)
}
```

**For Phase 87:** Extend `classify_codes()` to add ICD-9 3-char prefix tier between existing ICD-9 exact match and final unclassified. Extract `is_cancer_code()` from R/56 to R/utils/utils_cancer.R.

### Existing Pattern: Tiered Prefix Matching

**What:** 4-character prefix checked before 3-character fallback. Allows subcategory discrimination (NLPHL vs classical HL) while maintaining broad category coverage.

**Why:** ICD-10 C81.0 (NLPHL) needs separate tracking from C81.1-C81.9 (classical HL). 4-char tier (C810) catches NLPHL before 3-char tier (C81) catches classical.

**For Phase 87:** Apply same tier logic to ICD-9 201.x codes. 4-char tier for NLPHL (201.4, 201.40-201.48) checked before 3-char tier (201 catches all other subcategories).

### ICD-9 Code Structure in Existing Codebase

**Current state from R/00_config.R:**
```r
# ICD-9 HL codes (lines 310-343): 81 codes covering 201.xx range
# Includes bare "201", 4-digit parents (201.0, 201.1, etc.),
# and 5-digit site-specific (201.00, 201.01, etc.)

ICD9_NLPHL_CODES <- c(
  "201.4",                                              # Parent
  "201.40", "201.41", "201.42", "201.43", "201.44",     # Site-specific
  "201.45", "201.46", "201.47", "201.48"                # Site-specific
)
```

**Current ICD-9 handling in classify_codes() (lines 75-78):**
- Exact regex match for 201.x codes (`^201(\\..*)?$`)
- Checks if code in ICD9_NLPHL_CODES vector for NLPHL classification
- Non-NLPHL HL codes → "Hodgkin Lymphoma (non-NLPHL)"

**For Phase 87:** Expand beyond HL-only to all neoplasm categories (140-239).

### Recommended Project Structure (No Changes)

Existing structure already supports phase requirements:
```
R/
├── 00_config.R              # CANCER_SITE_MAP, ICD9_CANCER_SITE_MAP (new)
├── utils/
│   └── utils_cancer.R       # classify_codes(), is_cancer_code() (new)
├── 45_cancer_summary.R      # Remove DX_TYPE == "10" filter
├── 47_cancer_summary_refined.R  # Expand C81 confirmation to include 201.x
├── 48_cancer_summary_post_hl.R  # Remove DX_TYPE == "10" filter
├── 49_cancer_summary_pre_post.R # Remove DX_TYPE == "10" filters
├── 50_all_codes_resolved.R  # Verify no cancer code references (research confirmed: none)
└── 56_new_tables_from_groupings.R  # Replace local is_cancer_code() with sourced version
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ICD-9 to ICD-10 code conversion | Custom 140-239 → C00-D49 crosswalk table | Separate parallel maps (ICD9_CANCER_SITE_MAP, CANCER_SITE_MAP) | ICD-9 and ICD-10 use different granularity. Not 1:1 mappable at prefix level. Parallel classification via same categories avoids conversion complexity. |
| Cancer code detection regex | New pattern per script | Shared is_cancer_code() in utils_cancer.R | R/56 already has working vectorized implementation. Extraction prevents 5 scripts from diverging. |
| Cross-system code merging at code level | Merging 201.x and C81.x into single code column | Keep DX_TYPE and original codes separate, merge only at category aggregation | Code-level summaries need to show "15 patients had ICD-9 201.90, 23 had ICD-10 C81.90" separately. Only category rollups combine them. |
| ICD-9 benign/uncertain range identification | Manual list of every benign code | Range-based exclusion (210-239) mirroring D-code logic | 210-229 (benign), 230-234 (in situ), 235-238 (uncertain), 239 (unspecified) are structured ranges. ICD-10 D-codes have same exclusion logic. |

**Key insight:** The pipeline already separates code detection (`is_cancer_code()`) from category classification (`classify_codes()`). Maintain this separation. Detection uses ranges for speed (140-239 for ICD-9), classification uses maps for accuracy.

## Runtime State Inventory

> Phase 87 is a code harmonization phase, not a rename/refactor/migration phase. No runtime state inventory required.

Skipped — Phase 87 adds ICD-9 support to existing ICD-10 logic without renaming artifacts, services, or registered components.

## Common Pitfalls

### Pitfall 1: Assuming ICD-9 Codes Are Always Dotted

**What goes wrong:** ICD-9 codes in PCORnet CDM appear in both dotted (201.90) and undotted (20190) formats depending on source system. Prefix extraction via `substr(code, 1, 3)` produces different results.

**Why it happens:** Different EHR systems store ICD-9 codes differently. OneFlorida+ data contains both formats.

**How to avoid:** Normalize codes before classification. Strip dots: `str_remove(dx, "\\.")` before prefix extraction.

**Warning signs:** `classify_codes()` returns NA for codes that should match. Undotted "20190" produces prefix "201" correctly, but dotted "201.90" produces prefix "201" → works. BUT dotted "201.9" (4-char parent code) produces prefix "201" → also works. Edge case: 3-digit bare codes like "201" work in both formats.

**Evidence from codebase:** R/56 already handles this (line 166):
```r
is_cancer_code <- function(dx) {
  dx_clean <- str_remove(dx, "\\.")  # Remove dots for prefix matching
  # ... prefix detection on dx_clean
}
```

**Action:** Adopt same normalization pattern in `classify_codes()` extension.

### Pitfall 2: Including Benign/In-Situ/Uncertain ICD-9 Codes When D-Codes Are Excluded

**What goes wrong:** ICD-10 D-codes (D00-D49 for benign/in-situ/uncertain behavior) are explicitly excluded in R/47 (line 96: `filter(!str_detect(cancer_code, "^D"))`). If ICD-9 equivalents (210-239) aren't excluded, cancer summary includes benign neoplasms for ICD-9 patients but not ICD-10 patients — creating coding-system bias.

**Why it happens:** D-02 decision excludes D-codes but doesn't explicitly list ICD-9 equivalents. Easy to miss during implementation.

**How to avoid:** Map ICD-9 ranges to ICD-10 behavior categories:
- 140-209 (malignant) → C00-C96 (malignant) — INCLUDE
- 210-229 (benign) → D10-D36 (benign) — EXCLUDE
- 230-234 (in situ) → D00-D09 (in situ) — EXCLUDE
- 235-238 (uncertain behavior) → D37-D48 (uncertain) — EXCLUDE
- 239 (unspecified nature) → D49 (unspecified) — EXCLUDE

**Warning signs:** Cancer summary row counts spike when ICD-9 added. Manual chart review shows benign neoplasms (e.g., 210.x colon polyps) in output.

**Action:** `is_cancer_code()` should ONLY detect 140-209 (malignant primary) for ICD-9, excluding 210-239 entirely. This mirrors existing D-code exclusion logic.

### Pitfall 3: Changing HL Cohort Without Tracing Downstream Reads

**What goes wrong:** Adding ICD-9 201.x to HL cohort confirmation (D-09) changes `cache/outputs/confirmed_hl_cohort.rds`. Every script that reads this artifact expects a specific patient set. If those scripts aren't updated to handle new patients, they fail silently (e.g., missing data) or noisily (e.g., assertion failures).

**Why it happens:** Artifact reads are scattered across 20+ scripts. Grep finds `readRDS("cache/outputs/confirmed_hl_cohort.rds")` but doesn't reveal the assumptions each script makes about cohort composition.

**How to avoid:**
1. Grep for all reads of `confirmed_hl_cohort.rds`
2. For each script, check if it filters/joins on HL diagnosis codes (C81 only)
3. Update filters to include 201.x or remove DX_TYPE filters entirely
4. Test with a known ICD-9-only HL patient to verify pipeline doesn't drop them

**Warning signs:** Scripts downstream of R/47 (cohort confirmation) suddenly have different row counts. Smoke test fails with "unexpected patient count" errors.

**Action:** D-12 requires plans to explicitly list affected scripts. Research identifies: R/48, R/49 read cohort artifact. R/50, R/56 don't reference cohort (confirmed by grep). Verify all scripts in execution order 48+.

### Pitfall 4: Mixing Code-Level and Category-Level Aggregation

**What goes wrong:** User wants code-level summary sheets to show "ICD-9 201.90: 15 patients, ICD-10 C81.90: 23 patients" separately, but category-level summaries to merge them as "Hodgkin Lymphoma (non-NLPHL): 38 patients total." If aggregation logic doesn't distinguish these levels, either code-level summaries incorrectly merge (losing ICD-9 vs ICD-10 breakdown) or category-level summaries incorrectly separate (defeating the purpose of categories).

**Why it happens:** D-10 and D-11 create a split requirement: category-level allows cross-system merging, code-level forbids it. Easy to implement one strategy everywhere.

**How to avoid:**
- Code-level summaries: group_by(DX, DX_TYPE, cancer_category)
- Category-level summaries: group_by(cancer_category) — DX and DX_TYPE dropped

**Warning signs:** Code-level Excel sheets show "Hodgkin Lymphoma (non-NLPHL)" as a single row instead of separate 201.x and C81.x rows. Or category-level counts don't match sum of code-level counts.

**Action:** R/49 produces pre/post cancer summary tables. Verify it has separate code-level and category-level aggregation paths. Update both to handle ICD-9 correctly.

### Pitfall 5: Gaps Between is_cancer_code() Detection and classify_codes() Classification

**What goes wrong:** `is_cancer_code()` uses range-based detection (140-209) but `classify_codes()` uses map-based classification (checking CANCER_SITE_MAP / ICD9_CANCER_SITE_MAP keys). If a code passes detection but isn't in the map, it's classified as NA — creating "detected but unclassified" records that break downstream group_by operations expecting non-NA categories.

**Why it happens:** Detection optimizes for speed (range check is O(1)), classification optimizes for accuracy (map lookup provides category strings). If map doesn't cover full detection range, gap appears.

**How to avoid:**
- **Option A (map-based detection):** `is_cancer_code()` checks if code prefix exists in `names(CANCER_SITE_MAP)` or `names(ICD9_CANCER_SITE_MAP)`. No gaps possible — detection = classification coverage.
- **Option B (range-based detection + complete map):** Keep range-based detection for speed, but ensure ICD9_CANCER_SITE_MAP covers ALL 140-209 prefixes. Smoke test validates no gaps.

**Warning signs:** `classify_codes()` returns NA for codes that passed `is_cancer_code()`. Cancer summary has rows with `cancer_category == NA`.

**Recommendation:** **Use Option A (map-based detection)**. Performance difference negligible (<1ms for 100K codes), gap-free guarantee critical. User's discretion item resolved: map-based detection preferred.

## Code Examples

Verified patterns from existing codebase:

### Current ICD-9 HL Classification (R/utils/utils_cancer.R:75-78)

```r
# Source: R/utils/utils_cancer.R lines 75-78 (existing code)
# ICD-9 Hodgkin lymphoma classification (exact match, dotted format)
is_icd9_hl <- grepl("^201(\\..*)?$", codes)
is_icd9_nlphl <- codes %in% ICD9_NLPHL_CODES
categories[is_icd9_hl & !is_icd9_nlphl] <- "Hodgkin Lymphoma (non-NLPHL)"
categories[is_icd9_nlphl] <- "NLPHL"
```

**Pattern to extend:** Add 3-char prefix tier before this exact-match logic to catch non-HL ICD-9 neoplasms.

### Current Cancer Code Detection (R/56:165-174)

```r
# Source: R/56_new_tables_from_groupings.R lines 165-174 (to be extracted)
is_cancer_code <- function(dx) {
  dx_clean <- str_remove(dx, "\\.")  # Remove dots for prefix matching
  # ICD-10: single regex from all prefixes
  icd10_pattern <- paste0("^(", paste(cancer_prefixes_icd10, collapse = "|"), ")")
  icd10_match <- str_detect(dx_clean, icd10_pattern)
  # ICD-9: 3-char prefix lookup (already vectorized)
  icd9_match <- substr(dx_clean, 1, 3) %in% cancer_prefixes_icd9

  icd10_match | icd9_match
}
```

**Pattern to adopt:** Extract this to R/utils/utils_cancer.R. Replace range-based ICD-9 detection (`substr(dx_clean, 1, 3) %in% as.character(140:209)`) with map-based detection (`substr(dx_clean, 1, 3) %in% names(ICD9_CANCER_SITE_MAP)`) to avoid gaps.

### Current DX_TYPE Filtering (Multiple Scripts)

```r
# Source: R/45_cancer_summary.R line 69
dx_icd10 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%  # REMOVE THIS LINE
  select(ID, DX, DX_DATE) %>%
  collect()

# Source: R/47_cancer_summary_refined.R lines 110-112
dx_c81 <- get_pcornet_table("DIAGNOSIS") %>%
  filter(DX_TYPE == "10") %>%  # REMOVE THIS LINE
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C81")) %>%  # EXTEND TO INCLUDE 201.x
  ...
```

**Pattern to replace:** Remove `DX_TYPE == "10"` filters. Replace terminal code filters (e.g., `str_detect(DX_norm, "^C81")`) with `is_cancer_code(DX_norm)` or extend regexes to include ICD-9 equivalents.

### ICD-9 HL Subcategory Mapping (User Discretion Item)

**Question:** How to map ICD-9 201.x subcategories to classical HL subtypes in 4-char matching tier?

**Existing ICD-9 → ICD-10 HL equivalence:**
- 201.4x (Lymphocytic-histiocytic predominance) → C81.0x (NLPHL) — ALREADY MAPPED via ICD9_NLPHL_CODES
- 201.5x (Nodular sclerosis) → C81.1x (Nodular sclerosis classical HL)
- 201.6x (Mixed cellularity) → C81.2x (Mixed cellularity classical HL)
- 201.7x (Lymphocytic depletion) → C81.3x (Lymphocyte depleted classical HL)
- 201.0x (Hodgkin's paragranuloma) → C81.7x (Other classical HL) — obsolete term
- 201.1x (Hodgkin's granuloma) → C81.7x (Other classical HL) — obsolete term
- 201.2x (Hodgkin's sarcoma) → C81.7x (Other classical HL) — obsolete term
- 201.9x (Hodgkin's disease, unspecified) → C81.9x (HL unspecified)

**Recommendation for ICD9_CANCER_SITE_MAP 4-char entries:**
```r
# NLPHL (already handled via ICD9_NLPHL_CODES — include in map for completeness)
"2014" = "NLPHL",  # 4-char parent
# Note: 201.40-201.48 are 5-char (dotted) which become "20140"-"20148" (undotted)
#       These are covered by 3-char "201" fallback after NLPHL check

# Classical HL subtypes (4-char parents)
"2015" = "Hodgkin Lymphoma (non-NLPHL)",  # Nodular sclerosis
"2016" = "Hodgkin Lymphoma (non-NLPHL)",  # Mixed cellularity
"2017" = "Hodgkin Lymphoma (non-NLPHL)",  # Lymphocytic depletion
"2010" = "Hodgkin Lymphoma (non-NLPHL)",  # Paragranuloma (obsolete)
"2011" = "Hodgkin Lymphoma (non-NLPHL)",  # Granuloma (obsolete)
"2012" = "Hodgkin Lymphoma (non-NLPHL)",  # Sarcoma (obsolete)
"2019" = "Hodgkin Lymphoma (non-NLPHL)",  # Unspecified

# 3-char fallback
"201" = "Hodgkin Lymphoma (non-NLPHL)",  # Catches all non-NLPHL if 4-char miss
```

**Caveat:** Dotted 5-digit codes (201.40) become 5-char undotted strings (20140) after normalization. `substr(code, 1, 4)` produces "2014" which matches 4-char tier. `substr(code, 1, 3)` produces "201" which matches 3-char tier. This works.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ICD-10 only in cancer summary | ICD-9 + ICD-10 harmonized via parallel maps | Phase 87 | Pre-2015 diagnoses (ICD-9 era) now included in cancer summaries and HL cohort confirmation |
| Local is_cancer_code() in R/56 | Shared is_cancer_code() in R/utils/utils_cancer.R | Phase 87 | All scripts use same cancer detection logic; prevents drift |
| Hard-coded DX_TYPE == "10" filters | Function-based cancer code detection | Phase 87 | Scripts become coding-system agnostic; easier to extend if ICD-11 added later |
| C81-only HL cohort confirmation | C81 + 201.x cross-system confirmation | Phase 87 | Captures patients diagnosed with ICD-9 codes; may increase cohort size by 5-15% (estimate based on OneFlorida+ 2011-2025 date range) |

**Deprecated/outdated:**
- ICD-10-only assumption: PCORnet CDM contains diagnosis data from 2011+ (OneFlorida+), spanning both ICD-9 (pre-Oct 2015) and ICD-10 (Oct 2015+) eras. Hard-filtering to ICD-10 drops ~4 years of data.

## Open Questions

### 1. Exact Cohort Size Impact from ICD-9 201.x Inclusion

**What we know:**
- Current HL cohort confirmed by 2+ C81 codes with 7-day gap (ICD-10 only)
- OneFlorida+ data spans 2011-2025 (per project context)
- ICD-9 → ICD-10 transition: October 1, 2015
- Patients diagnosed 2011-2015 may only have ICD-9 codes

**What's unclear:**
- How many patients in DIAGNOSIS table have 2+ ICD-9 201.x codes with 7-day gap but were excluded by current ICD-10-only filter?
- Are there patients with mixed coding (1x ICD-9 201.x + 1x ICD-10 C81) who weren't confirmed because cross-system confirmation wasn't implemented?

**Recommendation:**
- Plans should include data audit step: query DIAGNOSIS for 201.x codes, count patients meeting 7-day threshold
- Smoke test should verify confirmed_hl_cohort.rds patient count increases (not decreases or stays same)
- Document expected range (5-15% increase estimated) for validation

**Impact:** Affects all downstream scripts reading confirmed_hl_cohort.rds. If cohort grows substantially (>20%), investigate for coding errors (e.g., accidentally including benign 210-239 codes).

### 2. ICD-9 Neoplasm Category Granularity

**What we know:**
- ICD-10 CANCER_SITE_MAP has 53 categories (counted from R/00_config.R:537-800 unique values)
- ICD-9 uses different anatomical site groupings (e.g., 9 site digits vs 10 in ICD-10)
- Some ICD-10 categories are very specific (e.g., "Cervix Uteri" vs "Other Female Genital")

**What's unclear:**
- Should ICD-9 140-239 map to exact same 53 categories, or use coarser groupings?
- Do all ICD-10 categories have ICD-9 equivalents? (e.g., neuroendocrine tumors C7A/C7B may not have direct ICD-9 matches)

**Recommendation:**
- Start with 1:1 category mapping where clear equivalents exist (e.g., 140-149 Lip/Oral/Pharynx → same category as C00-C14)
- For ICD-10-specific categories without ICD-9 equivalents, document as "ICD-10 only" in comments
- For ICD-9 codes without clear ICD-10 category match, use broader category (e.g., "Other [anatomical region]")
- User can refine categories in later phase if clinical review suggests different groupings

**Impact:** Category granularity affects summary table interpretability. Coarser categories (fewer, broader) easier to interpret but lose specificity. Finer categories (more, narrower) preserve detail but may fragment small patient counts across too many rows.

### 3. Handling of ICD-9 Codes in Dotted vs Undotted Format

**What we know:**
- R/56's `is_cancer_code()` strips dots before prefix matching (line 166)
- Existing `classify_codes()` doesn't strip dots before ICD-10 prefix extraction
- ICD-9 codes in ICD_CODES$hl_icd9 are dotted format (201.90, 201.40, etc.)
- PCORnet CDM DX column may contain both formats depending on source system

**What's unclear:**
- Does `classify_codes()` need dot-stripping for ICD-10 codes too?
- Are ICD-10 codes in DIAGNOSIS table always undotted (C8190) or sometimes dotted (C81.90)?

**Recommendation:**
- Normalize ALL codes at start of `classify_codes()`: `codes <- str_remove(codes, "\\.")`
- Update CANCER_SITE_MAP keys to undotted format if needed (current keys are undotted: "C81", "C810")
- ICD9_CANCER_SITE_MAP keys should be undotted 3-digit format: "140", "141", "201", etc.

**Impact:** Dot handling inconsistency causes classification failures (NA categories for valid codes). Normalizing at function entry prevents issues.

## Environment Availability

> Phase 87 has no external dependencies beyond R packages already in use. All work is code/config-only.

**Step 2.6: SKIPPED** — No external tools, services, runtimes, or CLI utilities required. Phase operates entirely within existing R/tidyverse environment.

## Validation Architecture

> **Skipped:** workflow.nyquist_validation is explicitly set to false in .planning/config.json.

No test framework research needed. Validation via R/88 smoke test updates only.

## ICD-9 Cancer Site Category Mapping (Research Findings)

### Malignant Neoplasms (140-209) — INCLUDE in Cancer Summary

Based on authoritative ICD-9-CM structure, malignant neoplasm codes 140-209 map to cancer categories as follows:

| ICD-9 Range | Category | ICD-10 Equivalent | Notes |
|-------------|----------|-------------------|-------|
| 140-149 | Lip, Oral Cavity and Pharynx | C00-C14 | Direct anatomical match |
| 150-159 | Digestive Organs and Peritoneum | C15-C26 | Includes esophagus, stomach, colon, rectum, liver, pancreas |
| 160-165 | Respiratory and Intrathoracic | C30-C39 | Lung, bronchus, larynx, trachea, mediastinum |
| 170-176 | Bone, Connective Tissue, Skin, Breast | C40-C50 | Includes melanoma (172.x → C43) |
| 179-189 | Genitourinary Organs | C51-C68 | Cervix, uterus, ovary, prostate, testis, bladder, kidney |
| 190-199 | Other and Unspecified Sites | C69-C80 | Eye, brain/CNS, thyroid, endocrine, ill-defined, unknown primary |
| 200-209 | Lymphatic and Hematopoietic | C81-C96, D45-D47 | Hodgkin (201.x → C81), NHL (200.x/202.x → C82-C86), leukemias (204-208 → C91-C95), multiple myeloma (203.x → C90) |

**Key finding:** ICD-9 codes 140-209 are ALL malignant neoplasms. This range maps cleanly to ICD-10 C00-C96 malignant codes. Category assignment should follow same anatomical groupings used in CANCER_SITE_MAP.

### Non-Malignant Neoplasms (210-239) — EXCLUDE from Cancer Summary

Per D-02 decision, benign/in-situ/uncertain behavior codes must be excluded to mirror D-code filtering logic:

| ICD-9 Range | Behavior Type | ICD-10 Equivalent | Action |
|-------------|---------------|-------------------|--------|
| 210-229 | Benign neoplasms | D10-D36 | **EXCLUDE** — not malignant |
| 230-234 | Carcinoma in situ | D00-D09 | **EXCLUDE** — pre-malignant, filtered like D-codes |
| 235-238 | Uncertain behavior | D37-D48 | **EXCLUDE** — behavior not determined |
| 239 | Unspecified nature | D49 | **EXCLUDE** — unknown behavior |

**Key finding:** ICD-9 ranges 210-239 directly correspond to ICD-10 D-codes (D00-D49). Existing R/47 logic filters out D-codes (`filter(!str_detect(cancer_code, "^D"))`). Same exclusion must apply to ICD-9 210-239 range.

**Implementation:** `is_cancer_code()` should ONLY detect 140-209 for ICD-9. Codes 210-239 return FALSE (not cancer for pipeline purposes, even though medically they are neoplasms).

### Specific ICD-9 201.x (Hodgkin Lymphoma) Subcategory Mapping

User discretion item: how to handle 201.x subcategories in 4-char matching tier.

| ICD-9 Code | Subtype Name | ICD-10 Equivalent | Category Assignment |
|------------|--------------|-------------------|---------------------|
| 201.4x | Lymphocytic-histiocytic predominance | C81.0x | **NLPHL** (4-char "2014") |
| 201.5x | Nodular sclerosis | C81.1x | Hodgkin Lymphoma (non-NLPHL) (4-char "2015") |
| 201.6x | Mixed cellularity | C81.2x | Hodgkin Lymphoma (non-NLPHL) (4-char "2016") |
| 201.7x | Lymphocytic depletion | C81.3x | Hodgkin Lymphoma (non-NLPHL) (4-char "2017") |
| 201.0x | Hodgkin's paragranuloma | C81.7x (obsolete) | Hodgkin Lymphoma (non-NLPHL) (4-char "2010") |
| 201.1x | Hodgkin's granuloma | C81.7x (obsolete) | Hodgkin Lymphoma (non-NLPHL) (4-char "2011") |
| 201.2x | Hodgkin's sarcoma | C81.7x (obsolete) | Hodgkin Lymphoma (non-NLPHL) (4-char "2012") |
| 201.9x | Hodgkin's disease, unspecified | C81.9x | Hodgkin Lymphoma (non-NLPHL) (4-char "2019") |

**Recommendation:** Add 4-char entries to ICD9_CANCER_SITE_MAP for "2014" (NLPHL), "2015"-"2017" and "2019" (classical HL), "2010"-"2012" (obsolete terms → classical HL). Keep 3-char "201" as fallback for any missed subcategories.

**Rationale:** Matches existing NLPHL discrimination pattern (C810 vs C81 in ICD-10). Preserves subcategory granularity for clinical interpretation.

## Downstream Impact Analysis

### Scripts Reading confirmed_hl_cohort.rds

Grepped codebase for `confirmed_hl_cohort.rds` reads. Found:

| Script | Line | Usage | Impact Assessment |
|--------|------|-------|-------------------|
| R/48_cancer_summary_post_hl.R | ~30 | Loads cohort, filters to cohort IDs | **AFFECTED** — filters DIAGNOSIS to cohort members. If cohort grows, more diagnosis rows processed. Should work without code changes (ID-based filter is agnostic to how cohort was confirmed). |
| R/49_cancer_summary_pre_post.R | ~25 | Loads cohort, uses first_hl_dx_date for pre/post split | **AFFECTED** — if new patients added via ICD-9 201.x, their first_hl_dx_date must be set correctly in R/47. R/49 should work without changes if R/47 sets dates correctly. |

**Other scripts checked (via grep "confirmed_hl" in R/):**
- R/50_all_codes_resolved.R: No references to cohort artifact ✓
- R/56_new_tables_from_groupings.R: No references to cohort artifact ✓
- R/60+ payer scripts: No direct cohort reads (read from ENROLLMENT/ENCOUNTER, not cohort artifact) ✓

**Key finding:** Only R/48 and R/49 directly read the cohort artifact. Both use ID-based filtering (not code-based), so they should handle cohort expansion gracefully. **However**, both scripts have `DX_TYPE == "10"` filters that must be removed per D-01.

**Downstream cascade:**
1. R/47 changes cohort confirmation logic (C81 → C81 + 201.x)
2. confirmed_hl_cohort.rds gains patients (ICD-9-diagnosed)
3. R/48 reads cohort, processes more patients (removes DX_TYPE filter to include their ICD-9 dx)
4. R/49 reads cohort, splits their timeline correctly (removes DX_TYPE filters)
5. Outputs: cancer_summary.csv, pre/post tables include ICD-9 patients

**Validation strategy:**
- Before R/47 change: count patients with 2+ ICD-9 201.x codes (7-day gap)
- After R/47 change: verify cohort.rds gained exactly that many patients
- After R/48-R/49: verify new patients appear in outputs with ICD-9 codes present

## Sources

### Primary (HIGH confidence)

- [ICD-9-CM Official Structure - Basicmedical Key](https://basicmedicalkey.com/neoplasms-icd-9-cm-chapter-2-codes-140-239-and-icd-10-cm-chapter-2-codes-c00-d49/) - ICD-9/ICD-10 Chapter 2 neoplasm classification
- [ICD-9 Neoplasm Codes 140-239 - Wikipedia](https://en.wikipedia.org/wiki/List_of_ICD-9_codes_140%E2%80%93239:_neoplasms) - Complete ICD-9 neoplasm range structure
- [2012 ICD-9-CM Codes 140-239 - ICD9Data.com](https://www.icd9data.com/2012/Volume1/140-239/default.htm) - Authoritative ICD-9 code hierarchy
- R/00_config.R lines 259-366 - Existing ICD-9 HL codes (ICD_CODES$hl_icd9, ICD9_NLPHL_CODES)
- R/utils/utils_cancer.R lines 57-82 - Existing classify_codes() implementation
- R/56_new_tables_from_groupings.R lines 156-174 - Existing is_cancer_code() implementation

### Secondary (MEDIUM confidence)

- [ICD-9 Benign Neoplasms 210-229 - AAPC](https://www.aapc.com/codes/icd9-codes-range/26/) - Benign neoplasm code range confirmation
- [ICD-9 Carcinoma in Situ 230-234 - ICD10Data.com](https://www.icd10data.com/ICD10CM/Codes/C00-D49/D00-D09) - In situ neoplasm ICD-9 to ICD-10 mapping
- [ICD-9 Uncertain Behavior 235-238 - AAPC](https://www.aapc.com/codes/icd9-codes-range/28/) - Uncertain behavior neoplasm range
- [2026 ICD-10-CM Codes D37-D48 - ICD10Data.com](https://www.icd10data.com/ICD10CM/Codes/C00-D49/D37-D48) - ICD-10 uncertain behavior equivalents

### Project Codebase (HIGH confidence)

- R/45_cancer_summary.R line 69 - DX_TYPE filter to remove
- R/47_cancer_summary_refined.R lines 96, 110-115 - D-code removal, C81 confirmation logic
- R/48_cancer_summary_post_hl.R line 118 - DX_TYPE filter to remove
- R/49_cancer_summary_pre_post.R lines 106, 203, 346 - DX_TYPE filters to remove
- R/50_all_codes_resolved.R - Verified no cancer code references (grep search)
- R/88_smoke_test_comprehensive.R - Smoke test structure for validation updates

## Metadata

**Confidence breakdown:**
- ICD-9 neoplasm range structure (140-239): **HIGH** - Official ICD-9-CM documentation from AAPC, CDC, ICD9Data.com authoritative sources
- ICD-9 to ICD-10 category mappings: **HIGH** - Direct correspondence documented in official transition guides
- Benign/in-situ/uncertain exclusion logic: **HIGH** - D-02 decision + verified ICD-9 210-239 → ICD-10 D00-D49 equivalence
- Downstream impact analysis: **MEDIUM** - Grepped confirmed_hl_cohort.rds reads, but runtime behavior depends on data distribution (how many ICD-9-only patients exist)
- ICD-9 201.x subcategory granularity: **MEDIUM** - Mappings based on ICD-9-CM official definitions, but clinical usage may vary (obsolete terms 201.0/201.1/201.2 rarely used)

**Research date:** 2026-06-04
**Valid until:** 60 days (stable domain — ICD-9 code structure frozen since 2015, no changes expected)

**Open items for planner:**
- Verify exact ICD-9 to cancer category mappings for all 140-209 prefixes (research provides framework, planner must build complete map)
- Decide map-based vs range-based detection for `is_cancer_code()` (research recommends map-based, planner has discretion)
- Quantify expected cohort size increase from ICD-9 201.x inclusion (research estimates 5-15%, planner should data-audit for exact number)
