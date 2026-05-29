# Technology Stack — v1.8 Episode-Level Cancer Linkage & First-Line Therapy Identification

**Project:** PCORnet Payer Variable Investigation (R Pipeline)
**Milestone:** v1.8 Episode-Level Cancer Linkage & First-Line Therapy Identification
**Researched:** 2026-05-29

## Executive Summary

**MINIMAL NEW REQUIREMENTS.** Most v1.8 features use existing validated stack (dplyr rolling joins for encounter-level linkage, lubridate for 28-day cycle windows, httr2 already validated for RxNorm API). Only potential addition: consider `rxnorm` GitHub package (nt-williams/rxnorm) if manual RxNorm API calls become cumbersome for regimen drug name resolution.

**Validated stack already provides:**
- Rolling joins with `closest()` (dplyr 1.2.0+) for encounter-level linkage with fallback to closest diagnosis date
- Interval detection with `%within%` (lubridate 1.9.5+) for 28-day cycle matching
- httr2 (1.2.2) with retry/throttle for RxNorm API (already used in Phase 40 for NDC lookup)
- DuckDB join performance for ENCOUNTERID linkage across PROCEDURES/PRESCRIBING/DISPENSING
- openxlsx2 for new Gantt output files

**Optional addition:** rxnorm package (nt-williams/rxnorm, GitHub-only) for simplified drug name resolution, but httr2 direct API calls work fine.

**Zero critical dependencies = minimal integration risk.**

---

## New Feature Requirements → Existing Stack Mapping

### Feature 1: Encounter-Level Cancer Category Linkage

**Requirement:** Replace patient-level cancer category join with encounter-level linkage (ENCOUNTERID match, fallback to closest diagnosis date)

**Stack solution:**
| Component | Package | Version | Already Validated |
|-----------|---------|---------|-------------------|
| ENCOUNTERID join | dplyr | 1.2.1 | ✓ Phase 1 (multi-table joins) |
| Rolling join (closest date fallback) | dplyr::join_by(closest()) | 1.2.1 | ✓ Phase 1 (dplyr 1.1.0+ feature) |
| Date comparison | lubridate | 1.9.5 | ✓ Phase 1 (date windows) |
| DuckDB backend | DuckDB via get_pcornet_table() | 1.3+ | ✓ Phase 30 (backend abstraction) |

**Implementation approach:**
```r
# Step 1: Direct ENCOUNTERID match (highest precision)
episodes_with_dx <- treatment_episodes %>%
  left_join(
    diagnosis_cancer %>% select(ENCOUNTERID, DX, DX_DATE, cancer_category),
    by = "ENCOUNTERID"
  )

# Step 2: Fallback to closest diagnosis date (for unmatched encounters)
episodes_unmatched <- episodes_with_dx %>%
  filter(is.na(cancer_category))

# Rolling join: closest DX_DATE <= episode_start
episodes_fallback <- episodes_unmatched %>%
  left_join(
    diagnosis_cancer %>% select(ID, DX_DATE, cancer_category),
    by = join_by(patient_id == ID, closest(episode_start >= DX_DATE))
  )

# Combine matched + fallback
episodes_final <- bind_rows(
  episodes_with_dx %>% filter(!is.na(cancer_category)),
  episodes_fallback
)
```

**Why no new package needed:** dplyr 1.2.1 includes `join_by(closest())` for rolling joins (introduced in dplyr 1.1.0, Feb 2023). DuckDB backend handles ENCOUNTERID indexing efficiently (Phase 29).

**References:**
- [dplyr::join_by documentation](https://dplyr.tidyverse.org/reference/join_by.html) — Rolling join with `closest()`
- [dplyr 1.1.0 blog post](https://tidyverse.org/blog/2023/01/dplyr-1-1-0-joins/) — Inequality and rolling joins
- CRAN dplyr 1.2.1 (May 2026) — Latest stable version

**Confidence:** **HIGH** — Rolling joins are stable dplyr feature (3+ years old), DuckDB handles join performance.

---

### Feature 2: 28-Day Cycle Window Matching for Regimen Detection

**Requirement:** Detect ABVD, BV+AVD, Nivo+AVD regimens using 28-day cycle windows (drugs co-administered within 28 days = same cycle)

**Stack solution:**
| Component | Package | Version | Already Validated |
|-----------|---------|---------|-------------------|
| Date intervals | lubridate::interval() | 1.9.5 | ✓ Phase 1 (enrollment windows) |
| Interval testing | lubridate::%within% | 1.9.5 | ✓ Phase 1 (date range checks) |
| Date arithmetic | lubridate | 1.9.5 | ✓ Phase 1 (all date operations) |
| Group-by logic | dplyr | 1.2.1 | ✓ Phase 1 (cohort filtering) |

**Implementation approach:**
```r
library(lubridate)

# Define 28-day cycle window for each drug administration
drug_events <- drug_events %>%
  mutate(
    cycle_start = ADMIN_DATE,
    cycle_end = ADMIN_DATE + days(27),  # 28 days inclusive
    cycle_interval = interval(cycle_start, cycle_end)
  )

# Find co-administered drugs within same 28-day cycle
regimen_cycles <- drug_events %>%
  inner_join(drug_events,
             by = "patient_id",
             suffix = c("_A", "_B")) %>%
  filter(
    drug_name_A != drug_name_B,
    ADMIN_DATE_B %within% cycle_interval_A  # Drug B within Drug A's 28-day cycle
  ) %>%
  group_by(patient_id, cycle_start_A) %>%
  summarize(
    drugs_in_cycle = paste(sort(unique(c(drug_name_A, drug_name_B))), collapse = " + "),
    .groups = "drop"
  )

# Classify regimen based on drug combinations
regimen_cycles <- regimen_cycles %>%
  mutate(
    regimen = case_when(
      str_detect(drugs_in_cycle, "doxorubicin.*bleomycin.*vinblastine.*dacarbazine") ~ "ABVD",
      str_detect(drugs_in_cycle, "brentuximab.*doxorubicin.*vinblastine.*dacarbazine") ~ "BV+AVD",
      str_detect(drugs_in_cycle, "nivolumab.*doxorubicin.*vinblastine.*dacarbazine") ~ "Nivo+AVD",
      TRUE ~ "Other"
    )
  )
```

**Why no new package needed:** lubridate's `interval()` and `%within%` provide exact 28-day cycle detection. Already validated for enrollment windows (Phase 1) and treatment window logic (Phase 8).

**References:**
- [lubridate::%within% documentation](https://lubridate.tidyverse.org/reference/within-interval.html) — Interval membership testing
- [lubridate::interval documentation](https://lubridate.tidyverse.org/reference/interval.html) — Interval creation and manipulation
- CRAN lubridate 1.9.5 (May 2026) — Latest stable version

**Clinical reference:**
- [OncoLink Nivolumab 28-Day Cycle Calendar](https://www.oncolink.org/cancer-treatment/cancer-medications/support/regimen-calendars/regimen-calendar-nivolumab-28-day-cycle) — Standard 28-day cycle definition

**Confidence:** **HIGH** — lubridate interval operations are mature (10+ years), widely used for time window detection.

---

### Feature 3: Drug Name Resolution via RxNorm API

**Requirement:** Map RXNORM_CUI codes to granular drug names (doxorubicin, bleomycin, vinblastine, etc.) for regimen classification

**Stack solution (Option A — Direct API with httr2):**
| Component | Package | Version | Already Validated |
|-----------|---------|---------|-------------------|
| HTTP requests | httr2 | 1.2.2 | ✓ Phase 40 (NDC lookup via RxNorm API) |
| JSON parsing | jsonlite | 1.9.3+ | ✓ Phase 40 (API response parsing) |
| Retry/throttle | httr2::req_retry, req_throttle | 1.2.2 | ✓ Phase 40 (rate limiting) |

**Implementation approach (httr2 direct):**
```r
library(httr2)
library(jsonlite)

# RxNorm API endpoint for drug names
get_rxnorm_name <- function(rxcui) {
  req <- request("https://rxnav.nlm.nih.gov/REST/rxcui") %>%
    req_url_path_append(rxcui, "properties.json") %>%
    req_retry(max_tries = 3) %>%
    req_throttle(rate = 20 / 1)  # 20 requests per second (NLM default limit)

  resp <- req_perform(req)
  result <- resp_body_json(resp)

  result$properties$name %||% NA_character_
}

# Batch lookup with error handling
drug_names <- drug_codes %>%
  mutate(drug_name = map_chr(RXNORM_CUI, safely(get_rxnorm_name)))
```

**Why httr2 works:** Already validated in R/40_investigate_unmatched_ndc.R (Phase 40) for RxNorm API calls. Includes retry, throttle, and JSON parsing.

**References:**
- [httr2::req_retry documentation](https://httr2.r-lib.org/reference/req_retry.html) — Automatic retry on 429/503
- [httr2::req_throttle documentation](https://httr2.r-lib.org/reference/req_throttle.html) — Rate limiting
- CRAN httr2 1.2.2 (May 2026) — Latest stable version

**Confidence:** **HIGH** — httr2 is already working in Phase 40 for identical use case (RxNorm API lookups).

---

**Stack solution (Option B — rxnorm package, OPTIONAL):**
| Component | Package | Version | Source |
|-----------|---------|---------|--------|
| RxNorm API wrapper | rxnorm (nt-williams) | 0.2.1.9000 | GitHub only |
| Dependencies | httr2, jsonlite | (same as above) | CRAN |

**Implementation approach (rxnorm package):**
```r
# Install from GitHub (one-time, add to renv)
# remotes::install_github("nt-williams/rxnorm")
library(rxnorm)

# Simplified drug name lookup
drug_names <- drug_codes %>%
  mutate(
    drug_name = map_chr(RXNORM_CUI, ~get_in(.x) %||% NA_character_),  # Ingredient name
    brand_name = map_chr(RXNORM_CUI, ~get_bn(.x) %||% NA_character_)  # Brand name
  )
```

**Why consider rxnorm package:**
- **Pro:** Cleaner API, handles retries/errors automatically, provides drug class lookup (ATC codes)
- **Con:** GitHub-only (not on CRAN), adds external dependency, httr2 already works

**Recommendation:** **Start with httr2 direct API** (already validated in Phase 40). Only adopt rxnorm package if:
1. Drug class lookup (ATC codes) becomes needed for regimen classification
2. API call volume becomes high enough that batch optimization matters
3. Simplified code maintenance outweighs GitHub dependency risk

**References:**
- [rxnorm GitHub repository](https://github.com/nt-williams/rxnorm) — R interface to NLM RxNorm API
- [rxnorm package documentation](https://rdrr.io/github/nt-williams/rxnorm/) — Function reference

**Confidence (httr2):** **HIGH** — Already working in Phase 40
**Confidence (rxnorm package):** **MEDIUM** — GitHub-only package, not CRAN-verified, but actively maintained (updated Apr 2025)

---

### Feature 4: Drop ICD Diagnosis Codes from SCT Detection

**Requirement:** Remove DIAGNOSIS table ICD codes from SCT detection — use only PROCEDURES/PRESCRIBING/DISPENSING

**Stack solution:**
| Component | Package | Version | Already Validated |
|-----------|---------|---------|-------------------|
| Code filtering | dplyr::filter | 1.2.1 | ✓ Phase 1 (all cohort logic) |
| Source table tracking | Base R | — | ✓ Phase 9 (multi-source treatment detection) |

**Implementation approach:**
```r
# In treatment detection logic (e.g., R/09_expanded_treatment_detection.R)
# OLD: sct_codes from DIAGNOSIS, PROCEDURES, PRESCRIBING, DISPENSING
# NEW: sct_codes from PROCEDURES, PRESCRIBING, DISPENSING only

sct_events <- bind_rows(
  # Remove DIAGNOSIS table ICD codes entirely
  # procedures_tbl %>% filter(...),  # Keep
  # prescribing_tbl %>% filter(...),  # Keep
  # dispensing_tbl %>% filter(...)   # Keep
)
```

**Why no new package needed:** This is a logic change (removing a data source), not a new capability. dplyr filtering already handles source exclusion.

**Confidence:** **HIGH** — Simplification (removing code paths), zero new functionality required.

---

### Feature 5: Death Date Analysis Table

**Requirement:** Produce death date analysis table (count with death dates, death as last encounter, encounters after death)

**Stack solution:**
| Component | Package | Version | Already Validated |
|-----------|---------|---------|-------------------|
| DEMOGRAPHIC.DEATH_DATE | DuckDB access | 1.3+ | ✓ Phase 57 (death date validation) |
| Date comparison | lubridate | 1.9.5 | ✓ Phase 1 (all date logic) |
| Group-by summaries | dplyr | 1.2.1 | ✓ Phase 1 (cohort statistics) |
| xlsx output | openxlsx2 | 1.0.0+ | ✓ Phase 54 (cancer summary table) |

**Implementation approach:**
```r
# Death date analysis
death_analysis <- encounter_data %>%
  left_join(demographic %>% select(ID, DEATH_DATE), by = "ID") %>%
  mutate(
    has_death_date = !is.na(DEATH_DATE),
    encounter_after_death = !is.na(DEATH_DATE) & ENCOUNTER_DATE > DEATH_DATE,
    death_is_last_encounter = !is.na(DEATH_DATE) & ENCOUNTER_DATE == max(ENCOUNTER_DATE, na.rm = TRUE)
  ) %>%
  summarize(
    n_patients_with_death_date = sum(has_death_date),
    n_encounters_after_death = sum(encounter_after_death),
    n_death_as_last_encounter = sum(death_is_last_encounter)
  )

# Export to xlsx
openxlsx2::write_xlsx(death_analysis, "output/death_date_analysis.xlsx")
```

**Why no new package needed:** DEATH_DATE already validated in Phase 59 (impossible death exclusion). Date comparison and summarization are core dplyr/lubridate operations.

**Confidence:** **HIGH** — DEATH_DATE column confirmed populated (Phase 59), logic is standard date comparison.

---

### Feature 6: New Gantt Output Files (Preserve Existing Versions)

**Requirement:** Generate new Gantt CSV files with encounter-level cancer categories and first-line regimen labels, preserving existing v1.7 output

**Stack solution:**
| Component | Package | Version | Already Validated |
|-----------|---------|---------|-------------------|
| CSV export | readr::write_csv | 2.2.0+ | ✓ Phase 49 (Gantt CSV export) |
| File versioning | Base R | — | ✓ Phase 33 (clone-and-filter pattern) |

**Implementation approach:**
```r
# New file naming pattern (add _v1.8 suffix)
write_csv(gantt_episodes_enhanced, "output/gantt_episodes_v1.8.csv")
write_csv(gantt_full_v1.8, "output/gantt_full_v1.8.csv")

# Preserve existing files
# output/gantt_episodes.csv (v1.7)
# output/gantt_full.csv (v1.7)
```

**Why no new package needed:** File versioning is a naming convention, not a new capability. readr::write_csv already validated.

**Confidence:** **HIGH** — Trivial file naming change, zero risk.

---

## What NOT to Add

### Rejected: data.table for Join Performance

**Considered:** data.table::fread, data.table joins for ENCOUNTERID matching

**Why NOT:**
- DuckDB backend already provides optimized join performance (Phase 29-32)
- data.table syntax conflicts with "named predicate" requirement (opaque `DT[i, j, by]` syntax)
- No performance bottleneck identified in current DuckDB-backed joins
- Rolling joins with `closest()` are dplyr-native, no data.table equivalent without custom logic

**Reference:** [DuckDB join performance](https://duckdb.org/docs/guides/performance/join-ops.html) — Indexed joins on ENCOUNTERID already optimized

### Rejected: Dedicated Drug Ontology Libraries

**Considered:** rWCVP (World Checklist of Vascular Plants), ontologyIndex (general ontology tools)

**Why NOT:**
- RxNorm API (via httr2) already provides drug name resolution (validated Phase 40)
- No need for full drug ontology — only need name lookup for ~20 HL therapy drugs (ABVD, BV+AVD, Nivo+AVD)
- Ontology packages add complexity without benefit for limited drug set

### Rejected: Specialized Time Series Libraries

**Considered:** zoo, xts (time series), slider (rolling windows)

**Why NOT:**
- lubridate `%within%` handles 28-day cycle detection elegantly
- No need for sliding window aggregation (cycles are discrete, not overlapping)
- Adding time series library for single use case is overkill

---

## Integration Points

### 1. httr2 RxNorm API Pattern Already Validated

**Current state:** R/40_investigate_unmatched_ndc.R uses httr2 for RxNorm API lookups with retry/throttle

**Reuse pattern:** Copy API request builder from R/40, adapt for drug name resolution (not NDC lookup)

**No changes needed:** httr2 already in renv.lock from Phase 40

### 2. DuckDB ENCOUNTERID Indexing

**Current state:** DuckDB ingest (Phase 29) creates indexes on PATID and ENCOUNTERID

**Validation needed:** Confirm ENCOUNTERID index exists for PROCEDURES, PRESCRIBING, DISPENSING tables

**Test query:**
```r
DBI::dbGetQuery(con, "PRAGMA table_info('PROCEDURES')")  # Confirm ENCOUNTERID column
DBI::dbGetQuery(con, "SELECT COUNT(DISTINCT ENCOUNTERID) FROM PROCEDURES")  # Check coverage
```

**Expected outcome:** ENCOUNTERID populated in treatment tables, indexed for join performance

### 3. Rolling Join Fallback Strategy

**Pattern:** Try direct ENCOUNTERID match first, fall back to `closest()` date match for unmatched encounters

**Rationale:** ENCOUNTERID may be missing for some treatment records (DISPENSING often lacks ENCOUNTERID in PCORnet)

**Validation:** Track proportion of episodes matched via ENCOUNTERID vs. date fallback

### 4. openxlsx2 Already Handles Multi-Sheet Workbooks

**Current state:** Phase 54 (R/54_cancer_summary_table.R) uses openxlsx2 for styled xlsx output

**Reuse pattern:** Same workbook formatting for death date analysis table and regimen summary tables

**No changes needed:** openxlsx2 already in renv.lock

---

## Version Verification (All Current as of 2026-05-29)

| Package | Minimum | Latest Stable | Status | Source |
|---------|---------|---------------|--------|--------|
| dplyr | 1.2.0 | 1.2.1 (Apr 2026) | Current | [CRAN](https://cran.r-project.org/package=dplyr) |
| lubridate | 1.9.3 | 1.9.5 (May 2026) | Current | [CRAN](https://cran.r-project.org/package=lubridate) |
| httr2 | 1.2.0 | 1.2.2 (May 2026) | Current | [CRAN](https://cran.r-project.org/package=httr2) |
| jsonlite | 1.8.0 | 1.9.3 (Feb 2026) | Current | [CRAN](https://cran.r-project.org/package=jsonlite) |
| openxlsx2 | 1.0.0 | 1.0.0+ (2025) | Current | CRAN |
| DuckDB | 1.3.0 | 1.3.2 (Mar 2026) | Current | CRAN |
| **rxnorm** | — | 0.2.1.9000 (Apr 2025) | **OPTIONAL** | [GitHub](https://github.com/nt-williams/rxnorm) |

**All required packages already in renv.lock from previous phases. No version bumps required.**

**Optional rxnorm package:** GitHub-only, would need `remotes::install_github("nt-williams/rxnorm")` if adopted. **Not recommended unless httr2 direct API becomes cumbersome.**

---

## Implementation Recommendations

### Stack Decision: httr2 Direct API vs. rxnorm Package

**Recommendation:** **Use httr2 direct API** (already validated in Phase 40)

**Rationale:**
1. **Zero new dependencies** — httr2 already working for RxNorm API
2. **Limited drug set** — Only need ~20 drug names for ABVD/BV+AVD/Nivo+AVD regimens
3. **CRAN preference** — Avoid GitHub-only packages unless necessary
4. **Proven pattern** — R/40_investigate_unmatched_ndc.R demonstrates exact use case

**When to reconsider rxnorm package:**
- If drug class lookup (ATC codes) becomes needed for regimen classification
- If API call volume exceeds 1000+ lookups (batch optimization benefit)
- If NLM RxNorm API changes break direct httr2 calls (wrapper insulates from API changes)

**Decision deferred to implementation:** Implement with httr2 first, adopt rxnorm package only if pain points emerge.

### Phase Sequencing Suggestion

1. **Phase 60:** ENCOUNTERID linkage infrastructure (direct match + closest fallback) — Foundation for all other features
2. **Phase 61:** Drug name resolution via httr2 RxNorm API — Independent of Phase 60
3. **Phase 62:** 28-day cycle regimen detection (ABVD/BV+AVD/Nivo+AVD) — Requires Phase 61
4. **Phase 63:** Drop ICD codes from SCT detection — Cleanup, independent of Phase 60-62
5. **Phase 64:** Death date analysis table — Independent of Phase 60-63
6. **Phase 65:** New Gantt output files with encounter-level cancer + regimen labels — Requires Phase 60, 62

**Rationale:** ENCOUNTERID linkage is foundation. Drug resolution + regimen detection are sequential. SCT cleanup and death analysis are independent. Gantt output ties everything together.

### Testing Strategy

**For ENCOUNTERID linkage (Phase 60):**
1. Track proportion of episodes matched via ENCOUNTERID vs. date fallback
2. Validate cancer category assignments against known HL episodes
3. Spot-check fallback logic (closest diagnosis date should be within reasonable time window)

**For 28-day cycle detection (Phase 62):**
1. Verify ABVD cycle detection against known ABVD patients (all 4 drugs within 28 days)
2. Check for dropped drugs (ABVD→AVD should still count as first-line)
3. Validate no extraneous drugs added (ABVD + other drug ≠ ABVD)

**For drug name resolution (Phase 61):**
1. Validate RXNORM_CUI → drug name mapping against known HL drugs
2. Check error handling for invalid/missing RXNORM_CUI codes
3. Verify rate limiting (httr2 throttle) prevents 429 errors from NLM API

**Parity testing:** Compare new Gantt output (v1.8) vs. existing Gantt (v1.7) for unchanged fields (patient_id, episode dates, treatment types excluding new regimen labels).

---

## Sources

### Official Documentation
- [dplyr::join_by documentation](https://dplyr.tidyverse.org/reference/join_by.html) — Rolling joins with `closest()`
- [dplyr 1.1.0 blog post](https://tidyverse.org/blog/2023/01/dplyr-1-1-0-joins/) — Inequality and rolling joins introduction
- [lubridate::%within% documentation](https://lubridate.tidyverse.org/reference/within-interval.html) — Interval membership testing
- [lubridate::interval documentation](https://lubridate.tidyverse.org/reference/interval.html) — Interval creation and manipulation
- [httr2::req_retry documentation](https://httr2.r-lib.org/reference/req_retry.html) — Automatic retry on failure
- [httr2::req_throttle documentation](https://httr2.r-lib.org/reference/req_throttle.html) — Rate limiting
- [CRAN dplyr](https://cran.r-project.org/package=dplyr) — Version 1.2.1 (May 2026)
- [CRAN lubridate](https://cran.r-project.org/package=lubridate) — Version 1.9.5 (May 2026)
- [CRAN httr2](https://cran.r-project.org/package=httr2) — Version 1.2.2 (May 2026)

### External APIs & Packages
- [rxnorm GitHub repository](https://github.com/nt-williams/rxnorm) — R interface to NLM RxNorm API (optional)
- [NLM RxNorm API documentation](https://lhncbc.nlm.nih.gov/RxNav/APIs/api-RxNorm.getDrugs.html) — Drug name resolution API
- [RxNorm official site](https://www.nlm.nih.gov/research/umls/rxnorm/index.html) — National Library of Medicine RxNorm

### Clinical References
- [OncoLink Nivolumab 28-Day Cycle Calendar](https://www.oncolink.org/cancer-treatment/cancer-medications/support/regimen-calendars/regimen-calendar-nivolumab-28-day-cycle) — Standard 28-day cycle definition

### Project Files
- **R/00_config.R** — Existing stack configuration, DuckDB backend settings
- **R/40_investigate_unmatched_ndc.R** — httr2 RxNorm API pattern (Phase 40)
- **R/49_gantt_data_export.R** — Gantt CSV export structure
- **R/54_cancer_summary_table.R** — openxlsx2 styled table output
- **PROJECT.md** — Milestone goals, constraints, validated capabilities

---

## Confidence Assessment

| Area | Confidence | Rationale |
|------|------------|-----------|
| ENCOUNTERID linkage | **HIGH** | dplyr rolling joins stable since 1.1.0 (Feb 2023), DuckDB indexing validated Phase 29 |
| 28-day cycle detection | **HIGH** | lubridate interval operations mature (10+ years), standard clinical cycle definition |
| Drug name resolution (httr2) | **HIGH** | httr2 RxNorm API pattern validated in Phase 40 |
| Drug name resolution (rxnorm pkg) | **MEDIUM** | GitHub-only package, not CRAN-verified, but actively maintained (Apr 2025) |
| SCT ICD code removal | **HIGH** | Logic simplification, zero new functionality |
| Death date analysis | **HIGH** | DEATH_DATE validated Phase 59, standard date comparison logic |
| Gantt file versioning | **HIGH** | Trivial file naming change |

**Overall confidence:** **HIGH** — All critical features use validated stack components (dplyr rolling joins, lubridate intervals, httr2 API). Only uncertainty is whether rxnorm package adoption is worth GitHub dependency (recommendation: defer unless needed).

---

## Summary

**Minimal new dependencies.** All v1.8 features use existing validated stack:
- **ENCOUNTERID linkage:** dplyr `join_by(closest())` for rolling joins (dplyr 1.2.1, stable since 1.1.0)
- **28-day cycle detection:** lubridate `%within%` for interval testing (lubridate 1.9.5)
- **Drug name resolution:** httr2 direct RxNorm API (httr2 1.2.2, validated Phase 40)
- **Death date analysis:** DuckDB DEMOGRAPHIC access + lubridate date comparison (validated Phase 59)

**Optional addition:** rxnorm package (GitHub-only) for simplified RxNorm API, but httr2 direct calls work fine. **Recommendation: Start with httr2, adopt rxnorm only if pain points emerge.**

**Key integration points:**
1. Reuse httr2 RxNorm API pattern from R/40_investigate_unmatched_ndc.R
2. Validate DuckDB ENCOUNTERID indexing for join performance
3. Track ENCOUNTERID match rate vs. date fallback proportion

**Risk:** Minimal. No critical new dependencies, dplyr rolling joins and lubridate intervals are mature features (3-10+ years old). httr2 RxNorm API already working in Phase 40.

**Next step:** Validate DuckDB ENCOUNTERID coverage in PROCEDURES/PRESCRIBING/DISPENSING tables, then proceed with dplyr rolling join implementation using existing stack.
