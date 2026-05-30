# Phase 60: Foundation - ENCOUNTERID Propagation & Drug Name Resolution - Research

**Researched:** 2026-05-29
**Domain:** Data pipeline enhancement (encounter linkage infrastructure, drug name resolution, treatment detection refinement)
**Confidence:** HIGH

## Summary

Phase 60 establishes infrastructure for encounter-level analysis in Phases 61-63 by propagating ENCOUNTERID values through treatment episodes, resolving chemotherapy drug names via RxNorm API, and tightening SCT detection to exclude diagnosis codes. This is a foundation phase — the columns and artifacts produced here enable downstream regimen identification (Phase 61) and Gantt v2 output (Phase 63).

The phase involves modifying existing scripts (R/43a, R/44a) to extract ENCOUNTERID alongside treatment dates, creating a standalone drug name resolution script with cached API lookups, and removing ICD diagnosis codes from SCT detection after auditing their impact. All changes integrate cleanly with the established pipeline pattern: DuckDB queries → episode calculation → RDS artifacts → Gantt export.

**Primary recommendation:** Follow the established 3-column → 4-column extraction pattern (ID, treatment_date, triggering_code → + ENCOUNTERID), reuse proven RxNorm API lookup functions from R/40, and perform the SCT source audit as a pre/post comparison to quantify impact before code removal.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Modify R/43a_treatment_durations.R and R/44a_treatment_episodes.R in-place to add ENCOUNTERID extraction. No new wrapper scripts.
- **D-02:** ENCOUNTERID is extracted alongside ID, treatment_date, and triggering_code from each source table (PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER, DIAGNOSIS). TUMOR_REGISTRY has no ENCOUNTERID — uses NA.
- **D-03:** Episode-level `encounter_ids` column uses comma-separated string format (consistent with existing `triggering_codes` pattern). Multiple encounter IDs per episode are deduplicated and joined.
- **D-04:** NULL/missing ENCOUNTERID values are omitted from the comma-separated list. An episode where all dates lack encounter IDs shows empty string. No "NA" or "MISSING" markers in the list.
- **D-05:** A data inspection step runs first to measure ENCOUNTERID population rates per source table (PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER, DIAGNOSIS) and logs results to console. Documents data quality before propagation.
- **D-06:** Drug name resolution covers chemotherapy only. Other treatment types (radiation, SCT, immunotherapy) do not get drug name resolution in this phase.
- **D-07:** Both RXNORM_CUI and NDC codes are resolved to generic drug names. Reuses R/40's `lookup_rxcui_name()` and `lookup_ndc_to_name()` functions (httr2, retry logic, 0.1s rate limiting).
- **D-08:** Only codes that actually appear in patient data (from PRESCRIBING, DISPENSING, MED_ADMIN queries) are resolved. No pre-emptive resolution of unused config codes.
- **D-09:** API results are cached in `drug_name_lookup.rds`. On re-run, cached results are loaded and only new/unresolved codes trigger API calls.
- **D-10:** Drug name resolution is a standalone script `R/60_drug_name_resolution.R` that produces `drug_name_lookup.rds` + `drug_name_lookup.csv`. Separated from episode extraction so it can be re-run independently without re-processing episodes.
- **D-11:** Existing RDS artifacts (`treatment_episodes.rds`, `treatment_episode_detail.rds`) gain new columns in-place: `encounter_ids` and `drug_names`. No v2 RDS split — Phases 61-62 consume the enhanced artifacts directly.
- **D-12:** R/44a joins drug names from `drug_name_lookup.rds` onto episode detail, then aggregates per episode as comma-separated `drug_names` column in `treatment_episodes.rds`.
- **D-13:** SCT source audit runs as a pre/post comparison: first run SCT detection with ICD DX codes included, then without, showing the delta (patients who lose SCT status vs patients retained by other sources).
- **D-14:** SCT Source Audit results appear as a sheet in the broader Phase 60 output xlsx (not a standalone report).
- **D-15:** After audit, `sct_dx_icd10` vector is removed entirely from `TREATMENT_CODES` in R/00_config.R. Clean break — no commented-out code.
- **D-16:** SCT DX code removal affects both R/43a (`extract_sct_dates()`) and R/44a (`extract_sct_dates_with_codes()`). The DIAGNOSIS source section is deleted from both functions.

### Claude's Discretion
- Script numbering for the drug name resolution script (R/60 suggested)
- Column ordering for new columns in RDS and CSV output
- Console logging detail level for ENCOUNTERID population rates
- xlsx sheet ordering and styling in the Phase 60 output workbook
- Whether to source R/40's lookup functions directly or copy them into R/60

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TREAT-01 | SCT source audit — quantify how many SCT detections come from ICD DX codes only vs PROCEDURES/PRESCRIBING/DISPENSING | Pre/post comparison pattern; DX codes are status/history codes (Z94.84 = "transplant status", T86.5 = "complications"), not procedure codes |
| TREAT-02 | Specific drug names resolved for each chemotherapy episode via RxNorm API (RXNORM_CUI/NDC → generic drug name) | RxNorm REST API `/rxcui/{rxcui}/properties` endpoint; httr2 retry logic; 0.1s rate limiting (20 req/sec API limit) |
| TREAT-03 | Drug name lookup table produced as standalone reference artifact | RDS + CSV dual output pattern; caching strategy for re-runs |
| TREAT-04 | Drug names carried through to Gantt episode output | Comma-separated aggregation pattern (reuses `triggering_codes` approach); join from lookup table to episode detail to episode summary |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Established project pattern; `group_by()` + `summarise()` for encounter ID aggregation |
| httr2 | 1.0.7+ | HTTP API requests | Modern replacement for httr; built-in retry logic for transient failures (429, 503); already used in R/40 |
| DuckDB (via R) | Latest from HiPerGator | SQL queries on PCORnet tables | Project infrastructure; `get_pcornet_table()` dispatcher pattern |
| glue | 1.8.0 | String formatting | Project logging standard; readable console messages |
| stringr | 1.5.1+ | String operations | Comma-separated string handling; `str_c()`, `str_split()` for encounter ID lists |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| purrr | 1.0.2+ | Functional iteration | Map over unique codes for batch API lookups; `map_df()` to bind results |
| tidyr | 1.3.0+ | Data reshaping | May need `separate_rows()` if comma-separated encounter IDs require row-level analysis downstream |
| openxlsx2 | Latest | Excel output | Project standard for styled xlsx reports; Phase 60 audit workbook |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| httr2 | httr (legacy) | httr2 has cleaner retry syntax (`req_retry()` vs manual loops); project already uses httr2 in R/40 |
| Comma-separated strings | List columns | List columns more flexible but break CSV export; comma-separated is project pattern (triggering_codes) |
| Standalone R/60 script | Embed in R/44a | Separation allows re-running drug lookup without re-extracting episodes; cleaner for cache invalidation |

**Installation:**
```bash
# On HiPerGator (if not already in renv.lock)
module load R/4.4.2
R
install.packages(c("httr2", "purrr"))  # Core packages likely already installed
renv::snapshot()
```

**Version verification:**
```bash
R -e "packageVersion('httr2')"  # Should be 1.0.7+
R -e "packageVersion('dplyr')"  # Should be 1.2.0+
```

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 43a_treatment_durations.R        # MODIFIED: Add ENCOUNTERID extraction, remove SCT DX section
├── 44a_treatment_episodes.R         # MODIFIED: Add ENCOUNTERID extraction, remove SCT DX section, join drug names
├── 60_drug_name_resolution.R        # NEW: Standalone drug lookup builder
├── 00_config.R                      # MODIFIED: Remove sct_dx_icd10 vector
└── 49_gantt_data_export.R           # MODIFIED: Propagate encounter_ids and drug_names to CSVs

cache/outputs/
├── drug_name_lookup.rds             # NEW: RxNorm API results cache
├── treatment_episodes.rds           # MODIFIED: + encounter_ids, drug_names columns
└── treatment_episode_detail.rds     # MODIFIED: + ENCOUNTERID, drug_name columns

output/
├── drug_name_lookup.csv             # NEW: Human-readable reference
├── phase_60_audit.xlsx              # NEW: ENCOUNTERID population rates + SCT source audit
├── gantt_episodes.csv               # MODIFIED: + encounter_ids, drug_names columns
└── gantt_detail.csv                 # MODIFIED: + ENCOUNTERID, drug_name columns
```

### Pattern 1: ENCOUNTERID Extraction (4-Column Query Pattern)

**What:** Extend existing 3-column extraction (ID, treatment_date, triggering_code) to 4-column (+ ENCOUNTERID). NULL ENCOUNTERID values are allowed; downstream aggregation handles omission.

**When to use:** Every source table query in R/43a and R/44a that supports ENCOUNTERID column (PROCEDURES, PRESCRIBING, DISPENSING, MED_ADMIN, ENCOUNTER, DIAGNOSIS). TUMOR_REGISTRY queries use `ENCOUNTERID = NA_character_`.

**Example:**
```r
# Source: Existing R/44a pattern (lines 110-121) — BEFORE modification
px_dates <- get_pcornet_table("PROCEDURES") %>%
  filter(
    (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
    (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
    (PX_TYPE == "10" & str_detect(PX, chemo_icd10pcs_rx)) |
    (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue)
  ) %>%
  filter(!is.na(PX_DATE)) %>%
  select(ID, treatment_date = PX_DATE, triggering_code = PX) %>%
  collect()

# AFTER Phase 60 modification — add ENCOUNTERID
px_dates <- get_pcornet_table("PROCEDURES") %>%
  filter(
    (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
    (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
    (PX_TYPE == "10" & str_detect(PX, chemo_icd10pcs_rx)) |
    (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue)
  ) %>%
  filter(!is.na(PX_DATE)) %>%
  select(ID, treatment_date = PX_DATE, triggering_code = PX, ENCOUNTERID) %>%  # Added ENCOUNTERID
  collect()

# TUMOR_REGISTRY pattern — no ENCOUNTERID column exists, so add NA
tr_dates <- tr_data %>%
  pivot_longer(...) %>%
  mutate(
    treatment_date = as.Date(treatment_date),
    triggering_code = NA_character_,
    ENCOUNTERID = NA_character_  # Explicit NA for consistency
  ) %>%
  select(ID, treatment_date, triggering_code, ENCOUNTERID)
```

**Downstream aggregation:**
```r
# Per D-03, D-04: Comma-separated encounter IDs, omit NULLs, empty string if all NULL
# In calculate_episodes_detailed() function (R/44a lines 439-491)
group_by(ID, episode_id) %>%
summarise(
  episode_start = min(treatment_date),
  episode_stop = max(treatment_date),
  ...,
  triggering_codes = paste(sort(unique(na.omit(triggering_code))), collapse = ","),
  encounter_ids = paste(sort(unique(na.omit(ENCOUNTERID))), collapse = ","),  # Same pattern
  .groups = "drop"
)
```

### Pattern 2: RxNorm API Lookup with Retry and Caching

**What:** Query RxNorm REST API for drug names by RXNORM_CUI or NDC code. Use httr2 retry logic for transient failures (429 rate limit, 503 service unavailable). Cache results in RDS to avoid re-querying on subsequent runs.

**When to use:** Drug name resolution for chemotherapy RXNORM_CUI and NDC codes from PRESCRIBING, DISPENSING, MED_ADMIN tables. Only resolve codes that actually appear in patient data (per D-08).

**Example:**
```r
# Source: R/40_investigate_unmatched_ndc.R lines 227-265 (lookup_rxcui_name function)
library(httr2)

lookup_rxcui_name <- function(rxcui, sleep_sec = 0.1) {
  result <- tryCatch({
    url <- glue("https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/properties.json")

    resp <- request(url) %>%
      req_timeout(10) %>%
      req_retry(
        max_tries = 3,
        is_transient = ~ resp_status(.x) %in% c(429, 503, 504)  # Rate limit, service unavailable
      ) %>%
      req_perform()

    data <- resp_body_json(resp)

    if (!is.null(data$properties) && !is.null(data$properties$name)) {
      tibble(
        code = rxcui,
        drug_name = data$properties$name,
        lookup_status = "success"
      )
    } else {
      tibble(code = rxcui, drug_name = NA_character_, lookup_status = "not_found")
    }
  }, error = function(e) {
    tibble(code = rxcui, drug_name = NA_character_, lookup_status = glue("error: {e$message}"))
  })

  Sys.sleep(sleep_sec)  # Rate limiting: 0.1s = 10 req/sec (API limit is 20/sec)
  result
}

# Caching pattern (per D-09)
CACHE_FILE <- file.path(CONFIG$cache$outputs_dir, "drug_name_lookup.rds")

if (file.exists(CACHE_FILE)) {
  cached_lookups <- readRDS(CACHE_FILE)
  message(glue("  Loaded {nrow(cached_lookups)} cached drug name lookups"))
} else {
  cached_lookups <- tibble(code = character(0), drug_name = character(0), lookup_status = character(0))
}

# Only query codes not in cache
codes_to_query <- setdiff(unique_codes$code, cached_lookups$code)
message(glue("  {length(codes_to_query)} new codes to resolve via RxNorm API"))

# Query and combine with cache
new_lookups <- map_df(codes_to_query, lookup_rxcui_name)
all_lookups <- bind_rows(cached_lookups, new_lookups)

# Save updated cache
saveRDS(all_lookups, CACHE_FILE)
```

### Pattern 3: Pre/Post Audit for Code Removal

**What:** Before removing SCT diagnosis codes from config, run SCT detection twice: once WITH DX codes, once WITHOUT. Compare patient-level SCT status to quantify impact. Log delta counts (patients who lose SCT status entirely vs retained by other sources).

**When to use:** Any time removing codes from treatment detection logic. Provides clinical justification and data quality assurance.

**Example:**
```r
# Source: Adapted from Phase 60 requirement TREAT-01

# Step 1: Extract SCT dates WITH DX codes (current R/43a logic)
sct_with_dx <- extract_sct_dates()  # Includes DX source (lines 295-303)
patients_with_dx <- n_distinct(sct_with_dx$ID)

# Step 2: Temporarily disable DX source, extract again
# (Simulated by filtering out DX source after extraction, or modifying function)
sct_without_dx <- extract_sct_dates_exclude_dx()  # Modified version with DX section commented
patients_without_dx <- n_distinct(sct_without_dx$ID)

# Step 3: Patient-level comparison
patients_lost <- setdiff(sct_with_dx$ID, sct_without_dx$ID)
n_lost <- length(patients_lost)
n_retained <- patients_without_dx

audit_summary <- tibble(
  metric = c("Patients with SCT (WITH DX codes)",
             "Patients with SCT (WITHOUT DX codes)",
             "Patients lost (DX-only detection)",
             "Retention rate"),
  value = c(patients_with_dx, patients_without_dx, n_lost,
            paste0(round(100 * patients_without_dx / patients_with_dx, 1), "%"))
)

message(glue("SCT Source Audit:"))
message(glue("  WITH DX codes: {patients_with_dx} patients"))
message(glue("  WITHOUT DX codes: {patients_without_dx} patients"))
message(glue("  Lost (DX-only): {n_lost} patients ({round(100 * n_lost / patients_with_dx, 1)}%)"))
```

### Anti-Patterns to Avoid

- **Don't pre-query all config codes:** Only resolve codes that appear in patient data (per D-08). Querying 200+ chemotherapy RXNORM_CUI codes from config when only 30 appear in data wastes API calls and slows execution.
- **Don't embed drug lookup in R/44a:** Separation (R/60 standalone script per D-10) allows re-running drug resolution without re-extracting episodes. Embedding creates tight coupling and cache invalidation issues.
- **Don't include "NA" strings in comma-separated lists:** Per D-04, NULL/missing ENCOUNTERID values are omitted entirely. `paste(na.omit(x), collapse = ",")` produces empty string if all NA, not "NA,NA,NA".
- **Don't remove config codes without audit:** Pre/post comparison (Pattern 3) provides clinical justification and prevents silent data loss. Removing `sct_dx_icd10` without audit risks undetected impact.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| API retry logic | Manual sleep loops with counters | httr2 `req_retry()` | Handles exponential backoff, jitter, Retry-After headers, transient error detection automatically. Building manually risks infinite loops or missing edge cases. |
| Comma-separated aggregation | Custom string concatenation loops | dplyr `summarise()` + `paste(collapse = ",")` | Group-level aggregation is dplyr's strength. Manual loops are verbose, error-prone, and slower. Project already uses this pattern for triggering_codes. |
| Drug code type detection | Regex on code format | Explicit code type column in lookup | RXNORM_CUI and NDC codes can overlap in format (both numeric). Use source column (RXNORM_CUI vs NDC) to dispatch to correct API endpoint. |
| NULL handling in aggregation | Manual filtering before paste | `na.omit()` inside summarise | Per D-04, NULL values are omitted from comma-separated lists. `paste(na.omit(x), collapse = ",")` is one-liner vs multi-step filter. |

**Key insight:** This phase reuses proven patterns (httr2 API calls from R/40, comma-separated aggregation from R/44a triggering_codes, DuckDB extraction from all treatment scripts). The architecture is extension, not invention. Don't rebuild what already works.

## Common Pitfalls

### Pitfall 1: ENCOUNTERID Population Rate Assumptions
**What goes wrong:** Assuming ENCOUNTERID is well-populated across all source tables without verifying. Planning downstream linkage strategy (Phase 61) without knowing actual availability.

**Why it happens:** PCORnet CDM specifies ENCOUNTERID as a standard column, leading to assumption it's always populated. In reality, population rates are site-dependent (STATE.md notes 39-90% validated range).

**How to avoid:** Per D-05, run data inspection FIRST to measure ENCOUNTERID population per source table before implementing propagation. Log results to console and include in Phase 60 audit xlsx.

**Warning signs:**
- Large proportion of empty `encounter_ids` strings in treatment_episodes.rds
- Downstream Phase 61 linkage strategy assumes 90%+ availability but actual rate is 40%

**Data inspection code:**
```r
# Before extraction, profile ENCOUNTERID availability
tables_to_check <- c("PROCEDURES", "PRESCRIBING", "DISPENSING", "MED_ADMIN", "ENCOUNTER", "DIAGNOSIS")

encounterid_profile <- map_df(tables_to_check, function(tbl) {
  if (is.null(get_pcornet_table(tbl))) {
    return(tibble(table = tbl, total_rows = 0, encounterid_populated = 0, population_rate = 0))
  }

  stats <- get_pcornet_table(tbl) %>%
    summarise(
      total_rows = n(),
      encounterid_populated = sum(!is.na(ENCOUNTERID), na.rm = TRUE)
    ) %>%
    collect()

  tibble(
    table = tbl,
    total_rows = stats$total_rows,
    encounterid_populated = stats$encounterid_populated,
    population_rate = round(100 * stats$encounterid_populated / stats$total_rows, 1)
  )
})

message("ENCOUNTERID Population Rates:")
print(encounterid_profile)
```

### Pitfall 2: RxNorm API Rate Limit Violation
**What goes wrong:** Querying RxNorm API too quickly triggers 429 rate limit errors. Retry logic exhausts attempts, lookups fail silently or incompletely.

**Why it happens:** RxNorm API has 20 requests/second limit (per web search). 0.1s sleep = 10 req/sec is safe, but batch processing 200+ codes without rate awareness can still hit limits if transient failures trigger retries.

**How to avoid:** Use 0.1s sleep between requests (per R/40 pattern and D-07). Monitor console logs for retry attempts. If failures occur, increase sleep to 0.15s or 0.2s. Cache results aggressively (per D-09) so re-runs don't re-query.

**Warning signs:**
- Console logs show multiple "retrying request" messages
- lookup_status column contains "error: 429" entries
- API lookups take significantly longer than expected (0.1s * N codes)

### Pitfall 3: SCT Diagnosis Codes Are Status, Not Procedure Evidence
**What goes wrong:** Treating Z94.84 ("stem cells transplant status") and T86.5 ("complications of stem cell transplant") as equivalent to procedure codes. Patients with these codes may have had SCT years ago, not during the analysis period.

**Why it happens:** ICD-10 codes appear in DIAGNOSIS table alongside procedure evidence. Without understanding code semantics, they seem like valid detection sources.

**How to avoid:** Recognize status codes (Z94.84) indicate transplant history, not current procedure. Complications codes (T86.5) indicate follow-up, not the transplant event itself. Per D-13/D-15/D-16, remove these from SCT detection logic after auditing impact. Retain only PROCEDURES (CPT, ICD-10-PCS), ENCOUNTER (DRG), and TUMOR_REGISTRY sources.

**Warning signs:**
- SCT dates appearing years before any chemotherapy/radiation treatment
- SCT detection dates matching follow-up visits, not inpatient procedure dates
- Pre/post audit shows DX-only patients have no other treatment evidence

**Clinical justification:**
- Z94.84 = POA-exempt status code, not acute event code
- T86.5 = complication/rejection, indicates ongoing management, not transplant date
- Procedure codes (ICD-10-PCS 30243*, CPT 38240) and DRGs (014, 016, 017) are actual procedure evidence

### Pitfall 4: Drug Name Cache Invalidation Timing
**What goes wrong:** Modifying chemotherapy code lists in R/00_config.R after building drug_name_lookup.rds. New codes added to config don't get resolved because they're not in patient data YET (per D-08), but when new data arrives, they're missing from lookup.

**Why it happens:** Cache (drug_name_lookup.rds) is built from codes present in current patient data, not from config. Config is source of truth for detection, but lookup only resolves codes that match. Adding codes to config doesn't trigger cache update.

**How to avoid:** Re-run R/60_drug_name_resolution.R when:
1. Chemotherapy code lists in R/00_config.R change
2. New patient data arrives with previously unseen codes
3. RxNorm API results were incomplete (lookup_status = "error" or "not_found")

Document cache build date and config version in drug_name_lookup.csv header.

**Warning signs:**
- Episode detail rows with triggering_code but drug_name = NA
- Console warnings about unmatchable codes during R/44a join step
- drug_name_lookup.csv last modified date is weeks/months old despite recent config changes

## Code Examples

Verified patterns from existing project code:

### ENCOUNTERID Extraction (4-Column Pattern)
```r
# Source: R/44a_treatment_episodes.R lines 110-121 (existing 3-column extraction)
# Extended to 4-column for Phase 60

# PROCEDURES source
px_dates <- get_pcornet_table("PROCEDURES") %>%
  filter(
    (PX_TYPE == "CH" & PX %in% TREATMENT_CODES$chemo_hcpcs) |
    (PX_TYPE == "09" & PX %in% TREATMENT_CODES$chemo_icd9) |
    (PX_TYPE == "10" & str_detect(PX, chemo_icd10pcs_rx)) |
    (PX_TYPE == "RE" & PX %in% TREATMENT_CODES$chemo_revenue)
  ) %>%
  filter(!is.na(PX_DATE)) %>%
  select(ID, treatment_date = PX_DATE, triggering_code = PX, ENCOUNTERID) %>%  # 4th column
  collect()

# PRESCRIBING source
rx_dates <- get_pcornet_table("PRESCRIBING") %>%
  filter(RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm) %>%
  mutate(treatment_date = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
  filter(!is.na(treatment_date)) %>%
  select(ID, treatment_date, triggering_code = RXNORM_CUI, ENCOUNTERID) %>%  # 4th column
  collect()

# TUMOR_REGISTRY source (no ENCOUNTERID column in table)
tr_dates <- tr_data %>%
  pivot_longer(
    cols = all_of(tr_chemo_cols),
    names_to = "date_source",
    values_to = "treatment_date"
  ) %>%
  filter(!is.na(treatment_date)) %>%
  mutate(
    treatment_date = as.Date(treatment_date),
    triggering_code = NA_character_,
    ENCOUNTERID = NA_character_  # Explicit NA for tables without ENCOUNTERID
  ) %>%
  select(ID, treatment_date, triggering_code, ENCOUNTERID)
```

### RxNorm API Lookup with httr2 Retry
```r
# Source: R/40_investigate_unmatched_ndc.R lines 227-318
# Reusable for Phase 60 drug name resolution

library(httr2)
library(glue)
library(dplyr)

# Lookup RXNORM_CUI -> drug name
lookup_rxcui_name <- function(rxcui, sleep_sec = 0.1) {
  result <- tryCatch({
    url <- glue("https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/properties.json")

    resp <- request(url) %>%
      req_timeout(10) %>%
      req_retry(
        max_tries = 3,
        is_transient = ~ resp_status(.x) %in% c(429, 503, 504)
      ) %>%
      req_perform()

    data <- resp_body_json(resp)

    if (!is.null(data$properties) && !is.null(data$properties$name)) {
      tibble(
        code = rxcui,
        drug_name = data$properties$name,
        lookup_status = "success"
      )
    } else {
      tibble(code = rxcui, drug_name = NA_character_, lookup_status = "not_found")
    }
  }, error = function(e) {
    tibble(code = rxcui, drug_name = NA_character_, lookup_status = glue("error: {e$message}"))
  })

  Sys.sleep(sleep_sec)
  result
}

# Lookup NDC -> RxCUI -> drug name (2-step)
lookup_ndc_to_name <- function(ndc, sleep_sec = 0.1) {
  # Step 1: NDC -> RxCUI
  rxcui_result <- tryCatch({
    url <- glue("https://rxnav.nlm.nih.gov/REST/rxcui.json?idtype=NDC&id={ndc}")

    resp <- request(url) %>%
      req_timeout(10) %>%
      req_retry(max_tries = 3, is_transient = ~ resp_status(.x) %in% c(429, 503, 504)) %>%
      req_perform()

    data <- resp_body_json(resp)

    if (!is.null(data$idGroup) && !is.null(data$idGroup$rxnormId) &&
        length(data$idGroup$rxnormId) > 0) {
      data$idGroup$rxnormId[[1]]  # Take first RxCUI
    } else {
      NA_character_
    }
  }, error = function(e) {
    NA_character_
  })

  if (is.na(rxcui_result)) {
    return(tibble(code = ndc, drug_name = NA_character_, lookup_status = "ndc_not_found"))
  }

  Sys.sleep(sleep_sec)

  # Step 2: RxCUI -> Name
  name_result <- lookup_rxcui_name(rxcui_result, sleep_sec = sleep_sec)

  tibble(
    code = ndc,
    drug_name = name_result$drug_name,
    lookup_status = name_result$lookup_status
  )
}
```

### Comma-Separated Aggregation with NULL Omission
```r
# Source: R/44a_treatment_episodes.R lines 454-490 (calculate_episodes_detailed)
# Pattern for encounter_ids and drug_names aggregation

dates_df %>%
  group_by(ID) %>%
  arrange(treatment_date, .by_group = TRUE) %>%
  mutate(episode_id = assign_episode_ids(treatment_date, gap_threshold)) %>%
  group_by(ID, episode_id) %>%
  summarise(
    episode_start = min(treatment_date),
    episode_stop = max(treatment_date),
    episode_length_days = as.numeric(max(treatment_date) - min(treatment_date)),
    distinct_dates_in_episode = n_distinct(treatment_date),
    # Existing triggering_codes pattern — reuse for encounter_ids and drug_names
    triggering_codes = paste(sort(unique(na.omit(triggering_code))), collapse = ","),
    encounter_ids = paste(sort(unique(na.omit(ENCOUNTERID))), collapse = ","),  # NEW
    # drug_names aggregation happens AFTER join to lookup table in R/44a
    .groups = "drop"
  ) %>%
  # ... episode_number and historical_flag logic
```

### Drug Name Join and Aggregation
```r
# Conceptual pattern for R/44a modification (per D-12)
# After loading drug_name_lookup.rds and before episode aggregation

# Load lookup table (built by R/60)
drug_lookup <- readRDS(file.path(CONFIG$cache$outputs_dir, "drug_name_lookup.rds"))

# Join to episode detail (one row per patient/date/code)
# Detail has triggering_code column; lookup has code column
detail_with_names <- detail %>%
  left_join(
    drug_lookup %>% select(code, drug_name),
    by = c("triggering_code" = "code")
  )

# Aggregate to episode level (for treatment_episodes.rds)
episodes_with_drugs <- detail_with_names %>%
  group_by(patient_id, episode_number) %>%
  summarise(
    # ... existing episode-level columns
    drug_names = paste(sort(unique(na.omit(drug_name))), collapse = ","),
    .groups = "drop"
  )
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| httr (legacy) | httr2 for API requests | 2023 (httr2 1.0.0 release) | Cleaner retry syntax, better error handling, modern request pipeline |
| Manual retry loops | httr2 `req_retry()` with transient detection | 2023 (httr2 1.0.0) | Automatic exponential backoff, Retry-After header support, configurable transient error detection |
| Treatment detection without encounter linkage | Encounter IDs propagated through episodes | Phase 60 (2026-05) | Enables encounter-level cancer diagnosis linkage (Phase 61), regimen identification within 28-day cycles |
| SCT detection includes DX status codes | SCT detection from procedures/DRGs only | Phase 60 (2026-05) | Aligns with clinical semantics (Z94.84 is history, not event), improves temporal accuracy |

**Deprecated/outdated:**
- **httr package:** Replaced by httr2 for new code. httr is maintenance-only; httr2 is actively developed.
- **Manual ENCOUNTERID extraction:** Phase 60 establishes systematic extraction pattern. Future phases extend rather than rebuild.
- **ICD DX codes in SCT detection:** Z94.84, T86.5, T86.09, Z48.290, T86.0 removed from TREATMENT_CODES after Phase 60 audit (per D-15).

## Open Questions

1. **ENCOUNTERID population rate impact on Phase 61 linkage strategy**
   - What we know: STATE.md notes 39-90% range across sites; D-05 mandates data inspection
   - What's unclear: Actual rate in this dataset; whether low rate requires fallback strategy
   - Recommendation: Run data inspection first (Pitfall 1). If <60%, Phase 61 must implement temporal proximity fallback. If >80%, direct ENCOUNTERID match is primary strategy.

2. **Drug name generic vs brand name standardization**
   - What we know: RxNorm API returns concept name property; R/40 uses this successfully
   - What's unclear: Whether RxNorm returns generic names consistently or mix of generic/brand
   - Recommendation: Accept RxNorm API results as-is for Phase 60. If Phase 61 regimen identification requires standardization (e.g., "brentuximab vedotin" vs "Adcetris"), add normalization step in R/61.

3. **NDC vs RXNORM_CUI resolution success rate**
   - What we know: R/40 implements both pathways; NDC requires 2-step lookup (NDC→RxCUI→name)
   - What's unclear: Whether NDC codes in PRESCRIBING/DISPENSING/MED_ADMIN are well-formed for RxNorm API
   - Recommendation: Track lookup_status distribution in drug_name_lookup.rds. If NDC "not_found" rate >20%, investigate NDC format issues (leading zeros, segment separators).

## Validation Architecture

> Skipped — workflow.nyquist_validation is explicitly set to false in .planning/config.json

## Sources

### Primary (HIGH confidence)
- [RxNorm API Documentation - RxNorm REST APIs](https://lhncbc.nlm.nih.gov/RxNav/APIs/RxNormAPIs.html) - API endpoints, properties endpoint for RxCUI→name lookup
- [httr2 req_retry documentation](https://httr2.r-lib.org/reference/req_retry.html) - Retry logic, transient error detection, exponential backoff
- [PCORnet CDM v6.1 Specification](https://onefl.net/wordpress/files/2025/02/PCORnet-Common-Data-Model-v61.pdf) - ENCOUNTERID column spec, data quality validation guidelines
- [Z94.84 ICD-10 Code - Stem cells transplant status](https://icd10coded.com/cm/Z94.84/) - Code semantics (status code, not procedure)
- [T86.5 ICD-10 Code - Complications of stem cell transplant](https://www.icd10data.com/ICD10CM/Codes/S00-T88/T80-T88/T86-/T86.5) - Complication code semantics
- Existing project code: R/40_investigate_unmatched_ndc.R (lines 227-372), R/44a_treatment_episodes.R (lines 79-100, 439-491), R/01_load_pcornet.R (column specs with ENCOUNTERID)

### Secondary (MEDIUM confidence)
- [How to Collapse Text by Group in R](https://www.r-bloggers.com/2024/05/how-to-collapse-text-by-group-in-a-data-frame-using-r/) - dplyr comma-separated aggregation patterns
- [DuckDB NULL Values Documentation](https://duckdb.org/docs/lts/sql/data_types/nulls) - NULL handling in SQL queries
- [PCORnet Data Quality Validation](https://pcornet.org/news/resources-common-data-model-cdm-data-quality-validation/) - Data quality validation process, ENCOUNTERID linkage integrity checks

### Tertiary (LOW confidence)
- [API Rate Limiting Best Practices 2026](https://www.getknit.dev/blog/10-best-practices-for-api-rate-limiting-and-throttling) - General guidance (not RxNorm-specific)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - httr2, dplyr, DuckDB are established project patterns; versions verified
- Architecture: HIGH - All patterns reuse existing project code (R/40 API calls, R/44a aggregation, DuckDB extraction)
- Pitfalls: HIGH - ENCOUNTERID population variability documented in STATE.md; ICD code semantics verified via official sources; API rate limits from official documentation
- RxNorm API: HIGH - Official NLM documentation, R/40 proven implementation pattern
- SCT code semantics: HIGH - Official ICD-10 code definitions (Z94.84 = status, T86.5 = complications)

**Research date:** 2026-05-29
**Valid until:** 2026-06-28 (30 days - stable domain: RxNorm API, PCORnet CDM, httr2)
