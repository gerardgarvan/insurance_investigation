# Technology Stack — v1.7 Cancer Summary Refinement & Gantt Enhancements

**Project:** PCORnet Payer Variable Investigation (R Pipeline)
**Milestone:** v1.7 Cancer Summary Refinement & Gantt Enhancements
**Researched:** 2026-05-22

## Executive Summary

**NO NEW PACKAGES REQUIRED.** All five new features (benign D-code filtering, HL cohort confirmation, temporal filtering, Gantt cancer category labels, death date integration) use existing validated stack. This is a logic-only enhancement milestone.

**Validated stack already provides:**
- String pattern matching (stringr) for D-code filtering
- Date arithmetic (lubridate) for 7-day separation and temporal filtering
- Data manipulation (dplyr) for cohort confirmation logic
- PREFIX_MAP infrastructure (R/53) for cancer category classification
- DuckDB access to DEMOGRAPHIC table for death dates

**Zero new dependencies = zero integration risk.**

---

## New Feature Requirements → Existing Stack Mapping

### Feature 1: Remove Benign D-Codes from Cancer Summary

**Requirement:** Filter out D10-D36 and D3A (benign neoplasms) from cancer_summary_table.xlsx

**Stack solution:**
| Component | Package | Version | Already Validated |
|-----------|---------|---------|-------------------|
| Pattern matching | stringr | 1.5.1+ | ✓ Phase 2 (ICD normalization) |
| Filtering | dplyr | 1.2.0+ | ✓ Phase 1 (all cohort logic) |
| PREFIX_MAP lookup | Base R | — | ✓ Phase 53 (R/53_cancer_summary.R) |

**Implementation approach:**
```r
# In R/53_cancer_summary.R and R/54_cancer_summary_table.R
BENIGN_PREFIXES <- c("D10", "D11", "D12", "D13", "D14", "D15", "D16",
                     "D17", "D18", "D19", "D20", "D21", "D22", "D23",
                     "D24", "D25", "D26", "D27", "D28", "D29", "D30",
                     "D31", "D32", "D33", "D34", "D35", "D36", "D3A")

dx_cancer <- dx_cancer %>%
  filter(!substr(DX_norm, 1, 3) %in% BENIGN_PREFIXES)
```

**Why no new package needed:** stringr::substr() and dplyr::filter() already validated for ICD code manipulation in Phase 2 (R/02_harmonize_payer.R) and all cohort scripts.

---

### Feature 2: HL Cohort Confirmation (2+ Codes, 7-Day Separation)

**Requirement:** Filter cohort to patients with 2+ HL diagnosis codes at least 7 days apart

**Stack solution:**
| Component | Package | Version | Already Validated |
|-----------|---------|---------|-------------------|
| Date arithmetic | lubridate | 1.9.3+ | ✓ Phase 1 (enrollment windows) |
| Date sorting | dplyr | 1.2.0+ | ✓ Phase 1 (arrange()) |
| Interval logic | Base R | — | ✓ Phase 50 (R/50_cancer_site_2date.R) |

**Implementation approach:**
```r
# Pattern validated in R/50_cancer_site_2date.R
hl_confirmed <- dx_hl %>%
  group_by(ID) %>%
  arrange(DX_DATE) %>%
  mutate(next_date = lead(DX_DATE),
         days_diff = as.numeric(next_date - DX_DATE)) %>%
  filter(any(days_diff >= 7, na.rm = TRUE)) %>%
  pull(ID) %>%
  unique()
```

**Why no new package needed:** This is the exact pattern from Phase 50 (cancer site confirmation with 7-day separation). lubridate's date arithmetic and dplyr's group-by-mutate pattern are already validated.

**Reference:** R/50_cancer_site_2date.R lines 84-140 (confirmed working pattern)

---

### Feature 3: Temporal Filtering (Cancers After First HL Diagnosis)

**Requirement:** Produce cancer_summary_table filtered to cancers occurring after first HL diagnosis date

**Stack solution:**
| Component | Package | Version | Already Validated |
|-----------|---------|---------|-------------------|
| Date comparison | lubridate | 1.9.3+ | ✓ Phase 1 (date windows) |
| Join logic | dplyr | 1.2.0+ | ✓ Phase 3 (multi-table joins) |
| Filtering | dplyr | 1.2.0+ | ✓ Phase 1 |

**Implementation approach:**
```r
# Step 1: Get first HL diagnosis date per patient
first_hl_date <- dx_hl %>%
  group_by(ID) %>%
  summarize(first_hl_date = min(DX_DATE, na.rm = TRUE))

# Step 2: Filter cancer summary to post-HL cancers
cancer_summary_post_hl <- cancer_summary %>%
  left_join(first_hl_date, by = "ID") %>%
  filter(DX_DATE >= first_hl_date)
```

**Why no new package needed:** Date comparison and left_join() are core dplyr operations validated across all cohort scripts.

---

### Feature 4: Add Cancer Category Labels to Gantt Episodes

**Requirement:** Add cancer category label to each treatment episode in Gantt data (same CancerSiteCategories mapping minus D-codes)

**Stack solution:**
| Component | Package | Version | Already Validated |
|-----------|---------|---------|-------------------|
| PREFIX_MAP lookup | Base R | — | ✓ Phase 53 (R/53_cancer_summary.R) |
| Join logic | dplyr | 1.2.0+ | ✓ Phase 49 (Gantt data export) |
| Code normalization | stringr | 1.5.1+ | ✓ Phase 2 |

**Implementation approach:**
```r
# In R/49_gantt_data_export.R or new R/55_gantt_cancer_labels.R
# Reuse PREFIX_MAP from R/53_cancer_summary.R (copy or source)
# Exclude benign D-codes

gantt_episodes_enhanced <- gantt_episodes %>%
  left_join(cancer_category_lookup, by = c("patient_id" = "ID")) %>%
  mutate(is_hodgkin = ifelse(cancer_category == "Hodgkin Lymphoma", 1, 0))
```

**Why no new package needed:** PREFIX_MAP infrastructure already exists in R/53_cancer_summary.R. Just needs to be imported/reused and joined to Gantt data.

**Integration note:** Requires coordination between:
- R/53_cancer_summary.R (cancer category classification source)
- R/49_gantt_data_export.R (Gantt CSV export destination)

Consider extracting PREFIX_MAP to R/00_config.R for DRY principle (same as AMC_PAYER_LOOKUP migration in Phase 36).

---

### Feature 5: Add Death Date to Gantt Chart

**Requirement:** Add death date from DEMOGRAPHIC/DEATH tables to Gantt chart and treat death as a treatment type for graphing

**Stack solution:**
| Component | Package | Version | Already Validated |
|-----------|---------|---------|-------------------|
| Table access | DuckDB via get_pcornet_table() | 1.3+ | ✓ Phase 30 (backend abstraction) |
| Date parsing | lubridate | 1.9.3+ | ✓ Phase 1 (multi-format dates) |
| Join logic | dplyr | 1.2.0+ | ✓ Phase 3 |

**PCORnet CDM structure:**
- **DEMOGRAPHIC table** already loaded (R/00_config.R line 115)
- **DEATH_DATE column** is standard PCORnet CDM v7.0 field (date format: YYYY-MM-DD or YYYYMMDD)
- **DEATH table** does NOT exist in PCORnet CDM — death data is in DEMOGRAPHIC

**Implementation approach:**
```r
# In R/49_gantt_data_export.R or new enhancement script
demographic <- get_pcornet_table("DEMOGRAPHIC") %>%
  select(ID, BIRTH_DATE, DEATH_DATE) %>%
  collect()

# Join to gantt_episodes
gantt_with_death <- gantt_episodes %>%
  left_join(demographic %>% select(ID, DEATH_DATE),
            by = c("patient_id" = "ID"))

# Treat death as pseudo-treatment type for visualization
death_events <- demographic %>%
  filter(!is.na(DEATH_DATE)) %>%
  transmute(
    patient_id = ID,
    treatment_type = "Death",
    episode_start = DEATH_DATE,
    episode_stop = DEATH_DATE,
    episode_length_days = 0
  )
```

**Why no new package needed:** DEMOGRAPHIC table already loaded via DuckDB. Date parsing via parse_pcornet_date() (R/01_load_pcornet.R) already handles DEATH_DATE format.

**PCORnet CDM reference:**
- DEMOGRAPHIC.DEATH_DATE is a DATE field (not DATETIME)
- Format: YYYY-MM-DD per PCORnet CDM v7.0 specification
- Already handled by existing parse_pcornet_date() function

---

## What NOT to Add

### Rejected: New Date/Time Libraries

**Considered:** data.table::fread, clock (new R date/time library)

**Why NOT:**
- data.table conflicts with named predicate requirement (opaque syntax)
- clock is redundant with lubridate (already validated)
- No performance bottleneck identified requiring data.table

### Rejected: New Visualization Libraries

**Considered:** gtsummary, gt (table formatting)

**Why NOT:**
- openxlsx2 already handles styled table output (Phase 54)
- No requirement for publication-quality tables in v1.7
- CSV output for Gantt charts is sufficient (third-party tool consumes)

### Rejected: Dedicated Survival Analysis Libraries

**Considered:** survival, survminer (for death date analysis)

**Why NOT:**
- Out of scope: "Statistical modeling / regression — exploration only" (PROJECT.md line 63)
- Death date is treated as visualization element (Gantt pseudo-treatment), not survival endpoint
- Defer to v2 if survival analysis becomes a requirement

---

## Integration Points

### 1. PREFIX_MAP Centralization (Recommended)

**Current state:** PREFIX_MAP duplicated in R/47_cancer_site_frequency.R, R/53_cancer_summary.R, R/54_cancer_summary_table.R

**Recommendation:** Extract to R/00_config.R (same pattern as AMC_PAYER_LOOKUP in Phase 36)

**Benefits:**
- Single source of truth for cancer category mapping
- Eliminates drift risk when categories change
- Easier to add benign D-code exclusion logic

**Migration pattern:**
```r
# In R/00_config.R (after AMC_PAYER_LOOKUP)
CANCER_CATEGORY_MAP <- list(
  prefix_map = c(...),  # Full PREFIX_MAP from R/53
  benign_prefixes = c("D10", "D11", ..., "D3A"),
  classify_codes = function(codes) { ... }
)
```

### 2. DEMOGRAPHIC Table Already Loaded

**Current state:** DEMOGRAPHIC listed in CONFIG$tables (R/00_config.R line 115)

**Validation needed:** Confirm DEATH_DATE column populated in HiPerGator data

**Test query:**
```r
demographic <- get_pcornet_table("DEMOGRAPHIC") %>%
  select(ID, DEATH_DATE) %>%
  filter(!is.na(DEATH_DATE)) %>%
  collect()

message(glue("Patients with death date: {nrow(demographic)}"))
```

**Expected outcome:** Some non-zero count (VRT is death-only partner site, PROJECT.md line 140)

### 3. Cohort Confirmation Pattern Reuse

**Source:** R/50_cancer_site_2date.R (Phase 50 validation)

**Pattern:** Group-by ID, arrange by date, calculate lead() differences, filter any() >= 7 days

**Reuse in:** New cohort confirmation script or enhancement to existing cohort filter chain

**No changes needed:** Pattern already validated for cancer site confirmation

---

## Version Verification (All Current as of 2026-05-22)

| Package | Minimum | Latest Stable | Status |
|---------|---------|---------------|--------|
| dplyr | 1.2.0 | 1.2.1 (Feb 2026) | Current |
| lubridate | 1.9.3 | 1.9.4 (Jan 2026) | Current |
| stringr | 1.5.1 | 1.5.2 (Dec 2025) | Current |
| openxlsx2 | Latest | 1.0.0+ (2025) | Current |
| DuckDB | 1.3.0 | 1.3.2 (Mar 2026) | Current |

**Source:** CRAN package pages (accessed 2026-05-22)

All packages already in renv.lock from previous phases. No version bumps required.

---

## Implementation Recommendations

### Phase Sequencing Suggestion

1. **Phase 1:** Benign D-code filtering (modify R/53, R/54) — Lowest risk
2. **Phase 2:** HL cohort confirmation (new cohort predicate or standalone filter) — Reuses Phase 50 pattern
3. **Phase 3:** Temporal filtering (clone R/54, add first_hl_date join) — Independent of Phase 2
4. **Phase 4:** PREFIX_MAP centralization (extract to R/00_config.R, update dependents) — Foundation for Phase 5
5. **Phase 5:** Gantt cancer category labels (enhance R/49 or new script) — Requires Phase 4
6. **Phase 6:** Death date integration (enhance R/49, add death pseudo-treatment) — Independent of Phase 5

**Rationale:** D-code filtering is simplest and validates the "no new packages" assumption. HL cohort confirmation reuses proven pattern. PREFIX_MAP centralization before Gantt enhancement avoids duplication.

### Testing Strategy

**For each feature:**
1. Verify row count changes make sense (benign D-code filtering should reduce cancer_summary rows)
2. Spot-check cancer category assignments against CancerSiteCategories.xlsx
3. Validate 7-day separation logic with known HL patients (compare to Phase 50 output)
4. Check death date join (expect matches for VRT site patients)

**Parity testing NOT required:** These are new features, not migrations. No baseline to compare against.

---

## Sources

- **R/00_config.R** — Existing stack configuration, DEMOGRAPHIC table loading
- **R/53_cancer_summary.R** — PREFIX_MAP structure, cancer category classification
- **R/50_cancer_site_2date.R** — 7-day separation pattern validation
- **R/49_gantt_data_export.R** — Gantt CSV export structure
- **PCORnet CDM v7.0 Specification** — DEMOGRAPHIC.DEATH_DATE field definition
- **CRAN package pages** — dplyr 1.2.1, lubridate 1.9.4, stringr 1.5.2 (verified 2026-05-22)
- **PROJECT.md** — Milestone goals, constraints, validated capabilities

---

## Confidence Assessment

| Area | Confidence | Rationale |
|------|------------|-----------|
| D-code filtering | **HIGH** | stringr pattern matching validated in Phase 2 |
| HL cohort confirmation | **HIGH** | Exact pattern from Phase 50 (R/50_cancer_site_2date.R) |
| Temporal filtering | **HIGH** | lubridate date comparison used throughout cohort pipeline |
| Gantt cancer labels | **HIGH** | PREFIX_MAP already exists, just needs join logic |
| Death date integration | **MEDIUM** | DEMOGRAPHIC table confirmed, DEATH_DATE column needs validation on HiPerGator data |

**Overall confidence:** **HIGH** — All features use validated stack components. Only uncertainty is DEATH_DATE column population in HiPerGator extract (expected to be populated per VRT partner site).

---

## Summary

**Zero new dependencies.** All five v1.7 features are logic enhancements using:
- Existing tidyverse packages (dplyr, lubridate, stringr)
- Existing infrastructure (PREFIX_MAP, DuckDB backend, parse_pcornet_date)
- Validated patterns (7-day separation from Phase 50, cancer classification from Phase 53)

**Key integration point:** Consider PREFIX_MAP centralization in R/00_config.R to avoid duplication across R/47, R/53, R/54, and new Gantt enhancement script.

**Risk:** Minimal. No package installation, no version conflicts, no new external dependencies.

**Next step:** Validate DEATH_DATE column population in HiPerGator DEMOGRAPHIC table, then proceed with implementation using existing stack.
