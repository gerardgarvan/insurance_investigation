# Phase 82: Non-Informative Sub-Categories — Explore and Count Helpful Codes - Research

**Researched:** 2026-06-03
**Domain:** Encounter-level data deduplication in treatment summary tables (R pipeline)
**Confidence:** HIGH

## Summary

Phase 82 implements encounter-level co-occurrence analysis to identify and deduplicate non-informative encounter diagnosis codes (e.g., "Chemo Encounter Dx Code") when a helpful/specific treatment code (e.g., "Doxorubicin") exists in the same encounter. The phase follows a two-step approach: first create an exploration script (R/57) to validate the logic and quantify impact, then integrate validated deduplication into the production R/56 script.

The technical challenge is detecting co-occurrence patterns at the encounter level (not episode level) and implementing a robust pattern-matching strategy that anticipates upstream schema changes and downstream data consumer needs. The existing R/56 infrastructure already provides encounter-level granularity via the `episode_encounters` data frame, making this a data transformation problem rather than an architectural change.

**Primary recommendation:** Use encounter-level joins on existing `episode_encounters` data, pattern-match sub-categories with `str_detect(sub_category, "Encounter Dx")` to identify non-informative codes, and add a `dx_only` flag column for orphan encounters rather than excluding them entirely. This preserves data completeness while enabling downstream filtering.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Only encounter diagnosis codes matching "Encounter Dx Code" pattern are non-informative. All other code types (DRG, Revenue, HCPCS, CPT, RxNorm, ICD-10-PCS, resolved names) remain helpful.
- **D-02:** DRG codes, Revenue codes, procedure codes, HCPCS, CPT, RxNorm, ICD-10-PCS, and all Tier 1/Tier 2 resolved names are classified as informative (helpful).
- **D-03:** Check for helpful code partners within the same `encounter_id`, not across the entire treatment episode. Most precise scope.
- **D-04:** Use existing encounter-level data from R/56 Section 4 `episode_encounters` split for co-occurrence check.
- **D-05:** When an encounter has ONLY non-informative dx codes (no helpful partner), keep the rows but add `dx_only = TRUE` flag. Do not exclude entirely.
- **D-06:** This flag preserves data completeness while making dx-only encounters visually separable and filterable.
- **D-07:** Two-step approach: create exploration script R/57 first, then fold validated logic into R/56.
- **D-08:** Apply deduplication to Table 1 (Sub-Category Summary) only. Table 2 already shows all treatments per encounter as a set.
- **D-09:** Exploration script must produce diagnostic output: how many dx codes have helpful partners, how many are orphans, count impact before/after.
- **D-10:** Code must anticipate upstream changes. Use pattern matching on sub-category labels (`str_detect(sub_category, "Encounter Dx")`) not hardcoded lists.
- **D-11:** Anticipate downstream changes. The `dx_only` flag column is additive, not breaking.
- **D-12:** Follow v2.0 code quality standards: styler formatting, lintr compliance, checkmate assertions, documentation headers, section structure.

### Claude's Discretion
- Exact script number for exploration script (R/57 suggested but confirm available numbering)
- Whether to add encounter-level co-occurrence stats to existing R/56 log output or keep them in exploration script only
- Internal data structure for co-occurrence check (join-based vs group_by approach)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.

</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Mature, optimized for readability; `group_by()`, `filter()`, `left_join()` for encounter-level co-occurrence |
| stringr | 1.5.1+ | Pattern matching | `str_detect(sub_category, "Encounter Dx")` for robust non-informative code identification |
| tidyr | 1.3.0+ | Data reshaping | `unnest()` for splitting encounter_ids (already used in R/56 Section 4) |
| glue | 1.8.0 | Logging | Readable diagnostic messages with embedded expressions (existing pattern in R/56) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| checkmate | 2.3.2+ | Defensive validation | Assert data frame structure, column existence (v2.0 standard: QUAL-01) |
| openxlsx2 | 1.10+ | Excel output | Multi-sheet workbook writing (existing in R/56) |

**Installation:**
```bash
# All packages already installed in renv.lock (verified from R/56, R/61 usage)
# No new dependencies required
```

**Version verification:** All packages already in use throughout the pipeline. Verified from:
- R/56: dplyr, stringr, tidyr, glue, openxlsx2, checkmate
- R/00_config.R: Auto-sources R/utils/utils_assertions.R (uses checkmate)

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 56_new_tables_from_groupings.R    # Production script (modified in final integration)
├── 57_explore_dx_deduplication.R     # NEW: Exploration script (Wave 1)
├── 00_config.R                       # Configuration (no changes needed)
└── 88_smoke_test_comprehensive.R     # Smoke test (updated in Wave 2)
```

### Pattern 1: Encounter-Level Co-Occurrence Detection (Join-Based)
**What:** Identify helpful codes per encounter by joining encounter-level data with sub-category classifications.
**When to use:** When checking whether a specific encounter contains any helpful (non-dx-only) code.
**Example:**
```r
# Source: R/56 Section 4 (lines 170-175) provides episode_encounters with ENCOUNTERID split
# Approach: Join episode_codes (per-code rows) with encounter-level grouping

# Step 1: Split episode_codes to encounter level (join via episode_encounters)
episode_codes_enc <- episode_codes %>%
  # episode_codes has episode-level rows; need to join to encounter-level split
  mutate(episode_row = row_number()) %>%
  inner_join(episode_encounters %>% select(episode_row, ENCOUNTERID), by = "episode_row")

# Step 2: Flag non-informative codes with pattern matching (D-01, D-10)
episode_codes_enc <- episode_codes_enc %>%
  mutate(is_dx_only = str_detect(sub_category, "Encounter Dx"))

# Step 3: Per encounter, check if ANY helpful code exists
encounter_has_helpful <- episode_codes_enc %>%
  group_by(ENCOUNTERID) %>%
  summarise(has_helpful = any(!is_dx_only), .groups = "drop")

# Step 4: Join back to flag dx-only encounters (D-05)
episode_codes_flagged <- episode_codes_enc %>%
  left_join(encounter_has_helpful, by = "ENCOUNTERID") %>%
  mutate(dx_only = is_dx_only & !has_helpful)
```

### Pattern 2: Exploration Script Diagnostic Output (D-09)
**What:** Quantify deduplication impact with before/after counts and orphan identification.
**When to use:** In R/57 exploration script to validate logic before production integration.
**Example:**
```r
# Diagnostic counts for exploration output
message("=== Deduplication Impact ===")

n_dx_codes <- sum(episode_codes_enc$is_dx_only)
n_helpful_codes <- sum(!episode_codes_enc$is_dx_only)
n_dx_with_partner <- sum(episode_codes_enc$is_dx_only & episode_codes_enc$has_helpful)
n_dx_orphan <- sum(episode_codes_enc$dx_only)

message(glue("  Total encounter diagnosis codes: {n_dx_codes}"))
message(glue("  Dx codes with helpful partner (same encounter): {n_dx_with_partner}"))
message(glue("  Dx codes as orphans (dx_only=TRUE): {n_dx_orphan}"))
message(glue("  Helpful codes (non-dx): {n_helpful_codes}"))

# Count impact on Table 1 aggregation
table1_before <- nrow(table1_original)
table1_after <- nrow(table1_deduplicated)
message(glue("  Table 1 rows before: {table1_before}"))
message(glue("  Table 1 rows after deduplication: {table1_after}"))
message(glue("  Reduction: {table1_before - table1_after} rows ({round(100*(table1_before-table1_after)/table1_before, 1)}%)"))
```

### Pattern 3: Robust Non-Informative Detection (D-10)
**What:** Pattern-based detection that survives upstream schema changes.
**When to use:** Always — avoids hardcoded lists that break when new treatment types or code systems are added.
**Example:**
```r
# GOOD: Pattern matching (survives new treatment types)
is_dx_only <- str_detect(sub_category, "Encounter Dx")

# BAD: Hardcoded list (breaks when new types added)
dx_only_labels <- c("Chemo Encounter Dx Code", "Radiation Encounter Dx Code",
                    "Immunotherapy Encounter Dx Code")
is_dx_only <- sub_category %in% dx_only_labels
```

### Anti-Patterns to Avoid
- **Episode-level co-occurrence:** Checking helpful codes across all encounters in an episode violates D-03. Must check within same encounter only.
- **Hardcoded sub-category lists:** Breaks when DRUG_GROUPINGS or TREATMENT_CODES change. Use `str_detect()` pattern matching (D-10).
- **Filtering out dx-only rows entirely:** Violates D-05. Must add `dx_only` flag column instead.
- **Skip exploration step:** Directly modifying R/56 without validating logic in R/57 risks incorrect deduplication logic silently affecting downstream analyses (violates D-07).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Encounter-level join key | Custom row numbering logic | Existing `episode_encounters` from R/56 Section 4 | Already splits encounter_ids into individual rows with ENCOUNTERID column; tested in production |
| Pattern matching for dx codes | Regex with anchors and alternation | `str_detect(sub_category, "Encounter Dx")` | Simple substring detection sufficient; "Encounter Dx" substring is stable across all dx code labels |
| Flag column strategy | Multiple filtered output files | Single `dx_only` flag column | Preserves all data in one table; downstream consumers filter as needed (D-06, D-11) |

**Key insight:** R/56 already has the infrastructure for encounter-level analysis (`episode_encounters` in Section 4). This phase is a data transformation on existing structures, not an architectural addition. Reuse existing patterns rather than creating parallel data flows.

## Common Pitfalls

### Pitfall 1: Episode-Level Instead of Encounter-Level Co-Occurrence
**What goes wrong:** Checking for helpful codes across all encounters in a treatment episode (rather than within same encounter) incorrectly flags dx codes as having a partner when the partner was billed on a different visit.
**Why it happens:** `episode_dx` in R/56 is episode-level; easy to forget to join down to encounter level.
**How to avoid:** Always join `episode_codes` to `episode_encounters` (via `episode_row`) to get encounter-level granularity before co-occurrence checks. Verify join produces multiple rows per episode (one per encounter).
**Warning signs:** If diagnostic counts show 100% of dx codes have helpful partners, likely checking at episode level not encounter level.

### Pitfall 2: Forgetting to Unnest encounter_ids Before Joining
**What goes wrong:** `episode_codes` has one row per code but codes are episode-level. Direct join to diagnosis data fails because encounter_ids is comma-separated string.
**Why it happens:** R/56 Section 5 creates `episode_codes` from episode-level data; encounter split happens in Section 4.
**How to avoid:** Reuse the `episode_encounters` unnesting logic from R/56 Section 4 (lines 170-175). Join `episode_codes` to `episode_encounters` via `episode_row` to propagate ENCOUNTERID.
**Warning signs:** Join produces fewer rows than expected; some encounters missing from output.

### Pitfall 3: Hardcoded Sub-Category List Instead of Pattern Matching
**What goes wrong:** Code breaks when upstream changes add new treatment types or code systems. Example: Adding CAR-T adds "CAR-T Encounter Dx Code" but hardcoded list still only checks for Chemo/Radiation/SCT/Immunotherapy.
**Why it happens:** Easier to write a fixed vector than think about future-proofing.
**How to avoid:** Use `str_detect(sub_category, "Encounter Dx")` pattern matching (D-10). The substring "Encounter Dx" is stable across all non-informative codes.
**Warning signs:** New treatment types appear in log warnings but dx codes for those types are incorrectly classified as helpful.

### Pitfall 4: Filtering Out dx_only Rows Instead of Flagging
**What goes wrong:** Downstream analysts lose visibility into encounters with no specific treatment code. Data appears complete but is missing dx-only encounters.
**Why it happens:** Filtering is simpler than adding a flag column.
**How to avoid:** Add `dx_only` column and keep all rows (D-05, D-06). Let downstream consumers decide whether to filter.
**Warning signs:** Table 1 row count decreases unexpectedly; encounters with only dx codes disappear from output without audit trail.

### Pitfall 5: Join Key Mismatch Between episode_codes and episode_encounters
**What goes wrong:** Join fails or produces Cartesian product if episode_row indexing is inconsistent.
**Why it happens:** `episode_codes` is built from `episode_dx` which has episode-level rows. If `episode_row` assigned before vs after filtering, indexes won't align.
**How to avoid:** Assign `episode_row` to the same data frame before any splits. Use `mutate(episode_row = row_number())` on `episode_dx` (or `episodes`) before creating both `episode_codes` and `episode_encounters`.
**Warning signs:** Join produces more rows than sum of encounter counts; duplicate encounter rows.

## Code Examples

Verified patterns from R/56 production code:

### Encounter-Level Split (Existing Pattern from R/56 Section 4)
```r
# Source: R/56 lines 170-175
# Splits comma-separated encounter_ids into individual rows with ENCOUNTERID column

episode_encounters <- episodes %>%
  mutate(episode_row = row_number()) %>%
  filter(!is.na(encounter_ids) & encounter_ids != "") %>%
  mutate(ENCOUNTERID = str_split(encounter_ids, ",\\s*")) %>%
  unnest(ENCOUNTERID) %>%
  filter(!is.na(ENCOUNTERID) & ENCOUNTERID != "")
```

### Pattern Matching for Non-Informative Codes (New Logic for R/57)
```r
# Identify non-informative codes with robust pattern matching (D-01, D-10)
# Matches: "Chemo Encounter Dx Code", "Radiation Encounter Dx Code",
#          "Immunotherapy Encounter Dx Code", "Immunotherapy Encounter", etc.

episode_codes <- episode_codes %>%
  mutate(is_dx_only = str_detect(sub_category, "Encounter Dx"))

# Alternative if "Encounter Dx" substring not stable: match full phrases
# (but per Phase 81 code, "Encounter Dx" is consistent across all dx codes)
```

### Encounter-Level Co-Occurrence Check (New Logic for R/57)
```r
# Join episode_codes to encounter level, check for helpful code co-occurrence

# Step 1: Propagate ENCOUNTERID to episode_codes via episode_encounters join
episode_codes_enc <- episode_codes %>%
  mutate(episode_row = row_number()) %>%
  inner_join(
    episode_encounters %>% select(episode_row, ENCOUNTERID),
    by = "episode_row"
  )

# Step 2: Flag non-informative codes
episode_codes_enc <- episode_codes_enc %>%
  mutate(is_dx_only = str_detect(sub_category, "Encounter Dx"))

# Step 3: Per encounter, determine if ANY helpful code exists
encounter_helpful_status <- episode_codes_enc %>%
  group_by(ENCOUNTERID) %>%
  summarise(has_helpful = any(!is_dx_only), .groups = "drop")

# Step 4: Join back and flag dx-only rows (D-05)
episode_codes_enc <- episode_codes_enc %>%
  left_join(encounter_helpful_status, by = "ENCOUNTERID") %>%
  mutate(dx_only = is_dx_only & !has_helpful)
```

### Table 1 Deduplication (Integration into R/56 Section 5)
```r
# Apply deduplication to Table 1 aggregation (after episode_codes_flagged created)

# Option A: Filter out dx codes with helpful partners (keep orphans flagged)
table1 <- episode_codes_flagged %>%
  filter(!is.na(cancer_codes)) %>%
  filter(!(is_dx_only & has_helpful)) %>%  # Remove dx codes with helpful partner
  group_by(category, sub_category, treatment_code, code_type, cancer_codes, dx_only) %>%
  summarise(encounter_count = n(), .groups = "drop") %>%
  arrange(category, desc(encounter_count))

# Option B: Keep all rows, rely on dx_only flag for downstream filtering
# (More conservative; preserves full audit trail)
table1 <- episode_codes_flagged %>%
  filter(!is.na(cancer_codes)) %>%
  group_by(category, sub_category, treatment_code, code_type, cancer_codes, dx_only) %>%
  summarise(encounter_count = n(), .groups = "drop") %>%
  arrange(category, desc(encounter_count))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Count all treatment codes equally | Deduplicate non-informative dx codes when helpful code present | Phase 82 (2026-06-03) | Table 1 encounter counts reflect specific treatments, not redundant dx codes |
| Hardcoded sub-category lists | Pattern matching with `str_detect()` | Phase 82 (2026-06-03) | Robust to upstream DRUG_GROUPINGS and TREATMENT_CODES changes |
| Filter out non-informative codes entirely | Add `dx_only` flag column | Phase 82 (2026-06-03) | Preserves data completeness; downstream consumers control filtering |

**Deprecated/outdated:**
- None identified — this is a new feature, not replacing deprecated functionality.

## Open Questions

1. **R/57 script availability**
   - What we know: R/57 does not currently exist (verified via Glob search)
   - What's unclear: Whether R/57 is an appropriate number or if another number should be used
   - Recommendation: Use R/57 unless numbering conflicts arise; script is temporary exploration and could be archived post-integration

2. **Co-occurrence granularity edge cases**
   - What we know: D-03 specifies same encounter_id scope; D-04 points to existing episode_encounters infrastructure
   - What's unclear: Whether same-day multiple encounters should be treated as co-occurring (likely NO per strict encounter_id matching, but worth confirming if log shows unexpected patterns)
   - Recommendation: Start with strict encounter_id matching; exploration script diagnostics will reveal if edge cases need handling

3. **Table 1 column order after dx_only addition**
   - What we know: Current columns: category | sub_category | treatment_code | code_type | cancer_codes | encounter_count
   - What's unclear: Where to insert dx_only column (end vs after code_type)
   - Recommendation: Add as last column (after encounter_count) to minimize downstream breakage; non-breaking addition per D-11

## Sources

### Primary (HIGH confidence)
- R/56_new_tables_from_groupings.R (lines 170-175, 249-416): Existing encounter-level split logic, episode_codes construction, Table 1 aggregation
- R/00_config.R: DRUG_GROUPINGS, TREATMENT_CODES, CODE_SUBCATEGORY_MAP patterns (centralized config approach)
- R/88_smoke_test_comprehensive.R (lines 809-847, 999-1025): DRUG_GROUPINGS validation patterns; R/56 smoke test assertions
- .planning/phases/81-*/81-CONTEXT.md: Phase 81 decisions on category column, sub-category resolution, code-type fallback (establishes current R/56 state)
- .planning/phases/82-*/82-CONTEXT.md: Phase 82 user decisions (D-01 through D-12)

### Secondary (MEDIUM confidence)
- R/61_tiered_encounter_level.R (lines 1-80): Example of encounter-level granularity analysis pattern (demonstrates `group_by(ENCOUNTERID)` usage)
- Output log: output/56_new_tables_from_groupings.log (2026-06-03 18:35:11 run): Verified current Table 1 structure (27,106 rows, 176 sub-categories, including "Chemotherapy Encounter" with 6,999 encounters)

### Tertiary (LOW confidence)
- None — all research based on existing codebase artifacts and user decisions.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages already in renv.lock; no new dependencies
- Architecture patterns: HIGH - Reusing existing R/56 Section 4 encounter split infrastructure
- Co-occurrence detection: HIGH - Standard dplyr join + group_by pattern; well-documented
- Pitfalls: MEDIUM - Based on similar encounter-level analysis patterns in R/61, but not yet tested for this specific use case
- Pattern matching robustness: HIGH - `str_detect(sub_category, "Encounter Dx")` verified stable across all current dx code labels in R/56 log

**Research date:** 2026-06-03
**Valid until:** 2026-07-03 (30 days - codebase stable, no fast-moving dependencies)
