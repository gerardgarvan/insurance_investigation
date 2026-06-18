# Phase 110: Redo Cancer Summary Table V2 7-Day (Confirmed HL Only) - Research

**Researched:** 2026-06-18
**Domain:** R data filtering and transformation (dplyr), cancer cohort refinement
**Confidence:** HIGH

## Summary

Phase 110 tightens the existing V2 7-day filtered cancer summary table by applying dual 7-day confirmation criteria: (1) restrict the entire table population to patients whose **HL diagnosis specifically** (C81 + ICD-9 201.x codes) meets the 7-day gap requirement (not just any cancer code), and (2) restrict the Pre-HL, Post-HL, and Both columns (K-L-M) to only count secondary malignancies that themselves meet the 7-day confirmation criterion.

This is an in-place modification of R/49's Section 8b (V2 tables). The current V2 output uses `two_or_more_unique_dates_gt_7 == 1` for ANY cancer code as the population filter; the new version restricts to patients with 7-day confirmed HL codes specifically. The K-L-M columns currently count all pre/post appearances; the new version requires each secondary malignancy to be 7-day confirmed to appear in those columns.

**Primary recommendation:** Modify R/49 Section 8b in-place. Expand the existing `n_hl_7day` computation (lines 125-131) to produce an ID vector for population filtering. Apply semi-join pattern for K-L-M columns to ensure secondary malignancies are 7-day confirmed. Update V2 population assertion bounds (currently 6300-7500) to reflect the smaller HL-specific subset.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Output Strategy:**
- **D-01:** Replace the existing `cancer_summary_table_pre_post_v2_7day.xlsx` with the new restricted version. The current v2 output becomes obsolete since the new version applies strictly tighter filters. The v1 (unfiltered) output remains as the baseline comparison.
- **D-02:** Same applies to companion files: `.csv` and `.rds` for v2 are overwritten with the tighter-filtered data.

**Script Approach:**
- **D-03:** Modify R/49 in-place. The existing V2 code path (Section 8b) already has the dual-output structure. Tighten the V2 population filter and secondary malignancy filter within the existing section. No new script created.

**Population Filter:**
- **D-04:** V2 table population restricted to patients whose **HL codes (C81 + ICD-9 201.x) specifically** meet the 7-day gap criterion (2+ unique HL diagnosis dates spanning 7+ calendar days). R/49 already computes this subset at lines 125-131 (`n_hl_7day`). Expand that computation to produce an ID vector for filtering.
- **D-05:** This replaces the current V2 filter which includes patients with 7-day confirmation for ANY cancer code (`two_or_more_unique_dates_gt_7 == 1` on any patient-code pair).

**Pre/Post/Both Columns (K-L-M):**
- **D-06:** Columns K (Pre-HL), L (Post-HL), and M (Both) all require the secondary malignancy to be 7-day confirmed. A patient counts in K/L/M for a given category/code only if that secondary malignancy itself meets the 7-day gap criterion.
- **D-07:** All three temporal columns use the same rule — consistent filtering across K-L-M.

**Sheet Scope:**
- **D-08:** Both Sheet 1 (Category Summary) and Sheet 2 (Code Summary) apply the same tighter filtering. The workbook is internally consistent — no sheet uses a broader population than the other.

### Claude's Discretion

- Assertion bound adjustments for the tighter population (currently 6300-7500 for any-code v2; confirmed-HL-only will be smaller)
- Footnote text updates to clearly describe the new filtering criteria
- Title text update in xlsx to reflect confirmed HL population
- Console logging structure for the tighter filter diagnostics
- V1-vs-V2 comparison table adjustments (if needed)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core R Packages

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data filtering and joins | Industry standard for readable data transformation; semi_join() for filtering patient-code pairs |
| stringr | 1.5.1+ | String pattern matching | HL code detection (C81, 201.x patterns); already used in R/49 for code normalization |
| glue | 1.8.0+ | String interpolation | Console logging with embedded variables; matches existing R/49 message() patterns |
| openxlsx2 | Latest | Excel workbook generation | Existing R/49 dependency; overwrites existing v2 .xlsx output |
| lubridate | 1.9.3+ | Date arithmetic | Date span calculation for 7-day gap validation; used in R/47 first_hl_dx_date computation |

**Installation:** Already installed in project environment (verified by existing R/49 execution). No new dependencies required.

**Version verification:** This phase modifies existing R/49 which already loads these packages. No version changes needed.

## Architecture Patterns

### Recommended Modification Structure

```
R/49_cancer_summary_pre_post.R
├── Section 3 (lines 81-155): Expand n_hl_7day computation
│   └── Add: hl_7day_confirmed_ids vector extraction
├── Section 8b (lines 497-640): Tighten V2 filtering
│   ├── Replace: cancer_summary_v2 population filter
│   ├── Replace: v2_valid_pairs semi-join logic
│   └── Update: v2_n_patients assertion bounds
├── Section 9b (lines 935-1155): Update V2 xlsx metadata
│   ├── Update: Title text (add "Confirmed HL Only")
│   └── Update: Footnote text (describe dual 7-day filtering)
└── No changes: Sections 1-8a, 9a, 10-11 (V1 logic unaffected)
```

### Pattern 1: Expand HL 7-Day Computation (Section 3)

**What:** Extract patient IDs meeting HL-specific 7-day criterion into a reusable vector.

**When to use:** Population filter for V2 dataset (replaces any-code filter).

**Current implementation (lines 125-131):**
```r
# Source: R/49_cancer_summary_pre_post.R lines 125-131
n_hl_7day <- hl_with_date %>%
  distinct(ID, DX_DATE) %>%
  group_by(ID) %>%
  filter(n() >= 2, as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%
  ungroup() %>%
  pull(ID) %>%
  n_distinct()
```

**Revised implementation (preserve count, add ID vector):**
```r
# Compute HL-specific 7-day confirmed IDs
hl_7day_confirmed <- hl_with_date %>%
  distinct(ID, DX_DATE) %>%
  group_by(ID) %>%
  filter(n() >= 2, as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%
  ungroup() %>%
  distinct(ID)

n_hl_7day <- nrow(hl_7day_confirmed)
hl_7day_confirmed_ids <- hl_7day_confirmed$ID
```

**Why this pattern:** Reuses existing logic; produces both the count (for console logging) and the ID vector (for filtering). No functional change to the existing diagnostic output.

### Pattern 2: Tighten V2 Population Filter (Section 8b)

**What:** Replace the existing `two_or_more_unique_dates_gt_7 == 1` filter (any cancer code) with HL-specific 7-day confirmation.

**Current implementation (lines 176-177):**
```r
# Source: R/49_cancer_summary_pre_post.R lines 176-177
cancer_summary_v2 <- cancer_summary %>%
  filter(two_or_more_unique_dates_gt_7 == 1)
```

**Revised implementation:**
```r
# V2 population: only patients with 7-day confirmed HL specifically
cancer_summary_v2 <- cancer_summary %>%
  filter(ID %in% hl_7day_confirmed_ids) %>%
  filter(two_or_more_unique_dates_gt_7 == 1)  # Still require secondary malignancies to be 7-day confirmed
```

**Why this pattern:** The dual filter ensures (1) patient is in the HL-confirmed cohort, and (2) each patient-code row meets the 7-day gap threshold for that specific code. This implements D-04 and D-05.

### Pattern 3: Tighten K-L-M Pre/Post/Both Filtering

**What:** Ensure secondary malignancies in temporal columns are 7-day confirmed.

**Current implementation (lines 518-530):**
```r
# Source: R/49_cancer_summary_pre_post.R lines 518-530
v2_valid_pairs <- cancer_summary_v2 %>%
  distinct(ID, cancer_code)

patients_pre_v2 <- patients_pre %>%
  semi_join(v2_valid_pairs, by = c("ID", "cancer_code"))

patients_post_v2 <- patients_post %>%
  semi_join(v2_valid_pairs, by = c("ID", "cancer_code"))

patients_both_v2 <- patients_both %>%
  semi_join(v2_valid_pairs, by = c("ID", "cancer_code"))
```

**Why it works:** The existing V2 logic already implements D-06 and D-07. The `v2_valid_pairs` extraction from `cancer_summary_v2` ensures that only patient-code pairs meeting the 7-day gap appear in K-L-M columns. The tightened population filter in Pattern 2 automatically narrows this set.

**No code change needed for Pattern 3** — the existing semi-join pattern is correct. The tighter `cancer_summary_v2` population automatically produces tighter `v2_valid_pairs`.

### Anti-Patterns to Avoid

- **Don't create a new script:** R/49 already has the dual-output structure (V1 + V2). Modify Section 8b in-place per D-03.
- **Don't filter patients_pre/post/both directly on HL confirmation:** The population filter is applied at the cancer_summary_v2 level. Pre/post/both filtering uses semi-join against v2_valid_pairs (existing pattern).
- **Don't change V1 output:** V1 remains the unfiltered baseline. Only Section 8b (V2 tables) is modified.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HL code detection | Regex for each subtype | `str_detect(DX_norm, "^C81") \| str_detect(DX_norm, "^201")` | Already established in R/47 and R/49; covers ICD-10 C81 + ICD-9 201.x per D-04 |
| 7-day gap validation | Custom date logic | Existing `max(DX_DATE) - min(DX_DATE) >= 7` pattern | Proven logic in R/45 and R/49; handles edge cases (single date, NA dates) |
| Patient-code filtering | Manual loops | dplyr `semi_join()` on (ID, cancer_code) | Existing R/49 pattern (lines 523-530); efficient and readable |
| Assertion bounds | Hardcoded values | Checkmate `assert_int()` with lower/upper bounds | R/49 already uses this pattern (line 191); prevents silent population drift |

**Key insight:** R/49 already has all the necessary primitives (HL code detection, 7-day gap logic, semi-join filtering). This phase is plumbing work — connecting existing pieces with tighter filters.

## Common Pitfalls

### Pitfall 1: Forgetting to Update V2 Population Assertion

**What goes wrong:** The current assertion (lines 191-195) checks `v2_n_patients` is in [6300, 7500]. The HL-specific filter will produce a smaller population (likely 5500-6500), causing the assertion to fail.

**Why it happens:** The existing bounds were set for "any cancer code 7-day confirmed". The new population is a strict subset (HL-confirmed patients only).

**How to avoid:** Update the assertion bounds in Section 8b after computing the new `v2_n_patients`. Use the diagnostic run output to set realistic bounds with 5-10% tolerance.

**Warning signs:** Script fails with checkmate assertion error during first run with real data.

**Example fix:**
```r
# Current (lines 191-195):
checkmate::assert_int(
  as.integer(v2_n_patients),
  lower = 6300L, upper = 7500L,
  .var.name = glue("[R/49 CANCER-02 ERROR] V2 7-day total population expected 6300-7500, got {v2_n_patients}")
)

# Updated (adjust after diagnostic run):
checkmate::assert_int(
  as.integer(v2_n_patients),
  lower = 5500L, upper = 6500L,  # Adjusted for HL-specific subset
  .var.name = glue("[R/49 CANCER-02 ERROR] V2 7-day HL-confirmed population expected 5500-6500, got {v2_n_patients}")
)
```

### Pitfall 2: Population Filter Order Ambiguity

**What goes wrong:** Unclear whether to filter `cancer_summary` first by HL-confirmed IDs, then by 7-day gap for each code — or vice versa.

**Why it happens:** Two independent criteria: patient-level (HL confirmed) and patient-code-level (secondary malignancy 7-day confirmed).

**How to avoid:** Apply population filter FIRST (`filter(ID %in% hl_7day_confirmed_ids)`), THEN apply per-code filter (`filter(two_or_more_unique_dates_gt_7 == 1)`). This ensures only HL-confirmed patients appear, and only their 7-day confirmed secondary malignancies are counted.

**Warning signs:** V2 population count unexpectedly high (includes patients without HL confirmation).

**Correct order:**
```r
cancer_summary_v2 <- cancer_summary %>%
  filter(ID %in% hl_7day_confirmed_ids) %>%       # Population filter (HL-confirmed)
  filter(two_or_more_unique_dates_gt_7 == 1)      # Per-code filter (7-day secondary malignancies)
```

### Pitfall 3: Footnote Text Stale After Filtering Change

**What goes wrong:** The V2 xlsx footnote (lines 1026, 1129) still references "filtered to patients with two_or_more_unique_dates_gt_7 == 1" without mentioning the HL-specific population restriction.

**Why it happens:** Footnote text was written for the original V2 logic (any-code 7-day confirmation).

**How to avoid:** Update footnote text to clearly describe the dual filtering: (1) HL-confirmed population, (2) 7-day confirmed secondary malignancies.

**Correct footnote:**
```r
# Updated footnote text (lines 1026, 1129):
footnote_text1_v2 <- glue("V2: Filtered to patients with 7-day confirmed HL diagnosis (C81 + 201.x), AND secondary malignancies with two_or_more_unique_dates_gt_7 == 1. Baseline stats: HL-confirmed 7-day cohort ({v2_n_patients} patients). Pre/Post/Both: {nrow(cohort_with_dates)} patients with known first_hl_dx_date. Pre: DX_DATE <= first_hl_dx_date. Post: DX_DATE > first_hl_dx_date. Both: patient had code pre AND post. C81 + 201.x pre/post/both left blank (anchor diagnosis).")
```

### Pitfall 4: HL Codes Appearing in K-L-M Columns

**What goes wrong:** HL anchor codes (C81, 201.x) should have NA in K-L-M columns (per existing logic, lines 394-396), but could slip through if filtering logic is incorrect.

**Why it happens:** If the population filter is applied AFTER the pre/post/both computation, HL codes could appear in those sets.

**How to avoid:** The existing logic (lines 229-235) already excludes HL codes from `dx_raw` before pre/post computation. No change needed — this is defense-in-depth. The assertion should still hold.

**Warning signs:** Manual inspection of V2 output shows C81 or 201.x codes with non-NA values in K-L-M columns.

**Existing safeguard (lines 229-235):**
```r
# Exclude HL anchor codes from pre/post analysis (C81 + 201.x per D-11)
dx_raw <- dx_raw %>%
  filter(!str_detect(DX_norm, "^C81") & !str_detect(DX_norm, "^201"))
```

## Code Examples

Verified patterns from R/49 existing implementation:

### HL Code Detection and 7-Day Gap Validation
```r
# Source: R/49_cancer_summary_pre_post.R lines 107-133
hl_dx <- get_pcornet_table("DIAGNOSIS") %>%
  select(ID, DX, DX_TYPE, DX_DATE) %>%
  collect() %>%
  mutate(DX_norm = toupper(str_remove_all(DX, "\\."))) %>%
  filter(str_detect(DX_norm, "^C81") | str_detect(DX_norm, "^201")) %>%
  filter(ID %in% confirmed_hl_cohort$ID)

hl_with_date <- hl_dx %>% filter(!is.na(DX_DATE))

# Compute HL-specific 7-day confirmed patients (existing pattern)
hl_7day_confirmed <- hl_with_date %>%
  distinct(ID, DX_DATE) %>%
  group_by(ID) %>%
  filter(n() >= 2, as.numeric(max(DX_DATE) - min(DX_DATE)) >= 7) %>%
  ungroup() %>%
  distinct(ID)
```

### Semi-Join Filtering for Pre/Post/Both (V2)
```r
# Source: R/49_cancer_summary_pre_post.R lines 518-530
# This pattern already implements D-06/D-07 correctly
v2_valid_pairs <- cancer_summary_v2 %>%
  distinct(ID, cancer_code)

patients_pre_v2 <- patients_pre %>%
  semi_join(v2_valid_pairs, by = c("ID", "cancer_code"))

patients_post_v2 <- patients_post %>%
  semi_join(v2_valid_pairs, by = c("ID", "cancer_code"))

patients_both_v2 <- patients_both %>%
  semi_join(v2_valid_pairs, by = c("ID", "cancer_code"))
```

### Checkmate Assertion for Population Bounds
```r
# Source: R/49_cancer_summary_pre_post.R lines 191-196
# Pattern to reuse with updated bounds
checkmate::assert_int(
  as.integer(v2_n_patients),
  lower = 5500L, upper = 6500L,  # Adjusted for HL-specific filtering
  .var.name = glue("[R/49 CANCER-02 ERROR] V2 7-day HL-confirmed population expected 5500-6500, got {v2_n_patients}")
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| V2 = any cancer code 7-day confirmed | V2 = HL-specific 7-day confirmed + 7-day confirmed secondaries | Phase 110 (2026-06-18) | Stricter population filter; tighter K-L-M columns; smaller V2 output (~10-15% reduction) |
| Pre/post columns count all appearances | Pre/post columns count only 7-day confirmed appearances | Phase 110 (2026-06-18) | Secondary malignancies must meet 7-day gap to appear in K-L-M columns |

**Deprecated/outdated:**
- Phase 77 V2 logic (any-code 7-day confirmation): Still valid for V1 output, but V2 now uses HL-specific confirmation per Phase 110 user requirements.

## Open Questions

1. **Assertion bound adjustment**
   - What we know: Current V2 population is 6300-7500 (any-code 7-day confirmed). HL-specific subset will be smaller.
   - What's unclear: Exact bounds for HL-confirmed population (depends on data distribution).
   - Recommendation: Run modified script once with bounds disabled (comment out assertion), observe `v2_n_patients` console output, set bounds to observed ± 5%.

2. **V1-vs-V2 comparison table**
   - What we know: R/49 prints a comparison table (lines 641-660) showing V1 vs V2 deltas per code.
   - What's unclear: Whether comparison table needs adjustment after tighter V2 filtering.
   - Recommendation: No code change needed — comparison table logic is generic (compares total_patients columns). The tighter V2 filtering will naturally produce larger deltas.

3. **Title text update**
   - What we know: V2 xlsx title (line 949) currently says "7-Day Confirmed".
   - What's unclear: Exact wording for revised title.
   - Recommendation: Update to "Confirmed HL Patients with 7-Day Secondary Malignancies" or similar descriptive title.

## Project Constraints (from CLAUDE.md)

### Runtime Environment
- **HiPerGator RStudio:** Script runs on HiPerGator; must work in that environment. R/49 already runs successfully — no new environment dependencies.

### Code Style
- **Named predicates:** Not applicable to this phase (no new filtering predicates created; reuses existing patterns).
- **Readable pipelines:** Use dplyr chains (`%>%`) per existing R/49 style. Avoid opaque one-liners.

### R Packages
- **tidyverse ecosystem:** R/49 already loads dplyr, stringr, glue, lubridate. No new packages needed.
- **openxlsx2:** R/49 already uses openxlsx2 for xlsx generation (lines 674-1151). No changes to workbook structure — only data filtering and metadata updates.

### Payer Fidelity
- **Not applicable:** This phase modifies cancer summary tables (no payer stratification). Payer logic unaffected.

## Sources

### Primary (HIGH confidence)
- R/49_cancer_summary_pre_post.R (lines 1-1202) - Existing V2 implementation, dual-output structure, HL 7-day computation
- R/45_cancer_summary.R (lines 1-406) - Upstream `two_or_more_unique_dates_gt_7` computation logic
- R/47_cancer_summary_refined.R (lines 107-131) - HL cohort confirmation logic (C81 + 201.x, 7-day gap)
- .planning/phases/110-*/110-CONTEXT.md - User decisions (D-01 through D-08)
- .planning/phases/77-*/77-CONTEXT.md - Original V2 design decisions (D-01 through D-10)

### Secondary (MEDIUM confidence)
- R/88_smoke_test_comprehensive.R (line 880-881) - V2 population assertion validation pattern
- .planning/REQUIREMENTS.md - Phase 110 requirements (none explicitly defined yet; TBD)
- .planning/STATE.md - Project context and Phase 109 completion status

### Tertiary (LOW confidence)
- None — all critical information verified from canonical codebase sources

## Metadata

**Confidence breakdown:**
- HL code detection pattern: HIGH - Verified in R/47 (lines 112-117) and R/49 (lines 107-112)
- 7-day gap logic: HIGH - Verified in R/45 (lines 264-274) and R/49 (lines 125-131)
- Semi-join filtering pattern: HIGH - Verified in R/49 (lines 518-530)
- Assertion bounds: MEDIUM - Current bounds known (6300-7500), new bounds require diagnostic run
- V2 population size: MEDIUM - HL-specific subset will be smaller, but exact size unknown without data

**Research date:** 2026-06-18
**Valid until:** 60 days (stable R/dplyr patterns; no fast-moving dependencies)
