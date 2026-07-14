# Phase 122: MED_ADMIN/DISPENSING Chemo-Detection Gap Closure - Research

**Researched:** 2026-07-14
**Domain:** PCORnet CDM medication table column-access patterns, NDC-to-RxNorm crosswalk, shared-helper extraction
**Confidence:** HIGH (based on direct source-code inspection of all 7 consumers)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Fix MED_ADMIN via `MEDADMIN_TYPE=='RX' & MEDADMIN_CODE %in% chemo_rxnorm` (RX-typed rows carry RxNorm CUIs directly).
- **D-02:** ALSO build an NDC->RxNorm crosswalk so DISPENSING (`NDC`) and MED_ADMIN `MEDADMIN_TYPE=='ND'` rows contribute. This is the broader scope chosen over an RX-only quick fix.
- **D-03:** Revise decision D-12 ("RXNORM_CUI only, no NDC matching") — the original premise (these tables expose RXNORM_CUI) is false for this extract; NDC matching is now in scope.
- **D-04:** Patient ID column is `ID` (not PATID) across all tables.
- **D-05:** All existing `"RXNORM_CUI" %in% colnames(...)` guards must be replaced with column-access that works on the real layout — but stay defensive: degrade gracefully (message + skip) if a table/column is genuinely absent, never crash.
- **D-06:** Fixes must be consistent across ALL consumers.
- **D-07:** Update fixtures to match real column layout (MED_ADMIN: MEDADMIN_CODE+MEDADMIN_TYPE, no RXNORM_CUI; DISPENSING: NDC, no RXNORM_CUI).

### Claude's Discretion
- NDC->RxNorm crosswalk mechanism (bundled reference file vs RxNav API `ndcstatus`/`ndcproperties` with caching) — prefer a cached/bundled approach consistent with the project's offline-capable pattern.
- Whether to centralize the corrected drug-code extraction into a shared helper (utils) vs patch each site.
- R/88 smoke-test section changes.
- HIPAA suppression already standard (counts 1-10).

### Deferred Ideas (OUT OF SCOPE)
- Immunotherapy MED_ADMIN/DISPENSING contribution (chemo-only this phase).
- Full downstream regeneration of episodes/Gantt/timing outputs after the fix (separate pass).
- Broader audit of other tables for analogous code-column mismatches (e.g., PROCEDURES code systems).
</user_constraints>

---

## Summary

Phase 122 fixes a confirmed silent-failure bug: seven consumers gate DISPENSING and MED_ADMIN chemo detection on `"RXNORM_CUI" %in% colnames(...)`, but neither table has that column in this OneFlorida+ extract. The result is that R/26, R/10, R/25, R/11, R/27, R/20, and R/76 all treat DISPENSING and MED_ADMIN as absent sources. The diagnostic (R/107) proved MED_ADMIN RX-typed rows alone add +1,139 patients and +10,752 chemo dates; DISPENSING (718k rows, 4,389 patients) and MED_ADMIN ND-typed (~22% of ~2.39M rows) are entirely unmatchable without an NDC->RxNorm crosswalk.

The fix has two independent pieces: (1) replace all seven broken guards with correct per-table column access; (2) build a `data/reference/ndc_rxnorm_crosswalk.rds` one-time lookup file (populated via RxNav API during a HiPerGator build step) so NDC-coded records resolve to chemo_rxnorm CUIs. A shared helper `get_chemo_codes_from_table()` in `R/utils/utils_treatment.R` centralises the corrected access so all seven sites stay consistent.

The fixtures currently carry a phantom `RXNORM_CUI` column that masks the bug locally. Correcting them (drop RXNORM_CUI; MED_ADMIN gets MEDADMIN_CODE+MEDADMIN_TYPE rows; DISPENSING gets NDC rows) restores the smoke-test value of the local path.

**Primary recommendation:** Build the crosswalk as a one-time RxNav-sourced RDS (offline after build), centralize access in `utils_treatment.R`, patch all seven consumers in a single wave, fix fixtures, and register a new R/88 Section 15t covering the new script(s) and fixture corrections.

---

## Project Constraints (from CLAUDE.md)

| Directive | Implication for Phase 122 |
|-----------|--------------------------|
| tidyverse ecosystem; no data.table syntax | All crosswalk build and consumer patches use dplyr, purrr, stringr |
| Named predicate functions (`has_*`, `with_*`, `exclude_*`) | Shared helper and any predicate rewrites follow this naming style |
| ID column (not PATID) | All join keys and filter lines use `ID` |
| Payer fidelity must be preserved | Consumer fixes must not drop the DISPENSING/MED_ADMIN date feeds to payer-anchoring (R/11) |
| HiPerGator + local dual environment | Crosswalk build step runs HiPerGator only (network API); crosswalk consume step is offline-safe |
| No setwd(); use here() | Crosswalk path uses `here("data", "reference", "ndc_rxnorm_crosswalk.rds")` or CONFIG-based path |
| HIPAA suppression | Counts 1-10 suppressed in any new diagnostic output |
| GSD workflow enforcement | All changes go through `/gsd:execute-phase` |

---

## Standard Stack

No new packages required. All crosswalk mechanics are achievable with the existing stack.

| Library | Purpose in this phase | Already in renv.lock? |
|---------|----------------------|----------------------|
| httr2 | RxNav API calls in crosswalk build step | Yes (used by R/27) |
| purrr | `map_dfr()` for batch NDC lookup | Yes (tidyverse) |
| dplyr | Joins, filters, dedup in all consumer patches | Yes |
| stringr | NDC format normalization (strip hyphens, zero-pad) | Yes |
| glue | Progress messages in build step | Yes |

**No new renv installs needed.**

---

## Architecture Patterns

### Recommended Project Structure Additions

```
R/
├── utils/
│   └── utils_treatment.R     # ADD: get_chemo_codes_from_table(), build/load crosswalk helpers
├── 108_build_ndc_rxnorm_crosswalk.R   # NEW: one-time crosswalk build (HiPerGator only)
data/
└── reference/
    └── ndc_rxnorm_crosswalk.rds       # NEW: built by R/108, committed after build
```

### Pattern 1: Corrected Per-Table Chemo-Code Access (shared helper)

Place in `R/utils/utils_treatment.R`. All seven consumers call this instead of the broken inline guards.

```r
#' Extract chemo-matching rows from a single PCORnet medication table
#'
#' Returns a tibble of (ID, treatment_date, triggering_code) for chemo hits,
#' or NULL with a message if the table or required columns are absent.
#'
#' @param table_name  "PRESCRIBING", "DISPENSING", or "MED_ADMIN"
#' @param chemo_rxnorm  Character vector of RxNorm CUIs (TREATMENT_CODES$chemo_rxnorm)
#' @param ndc_crosswalk Named character vector: NDC -> RxCUI (or NULL to skip NDC path)
#' @return Tibble(ID, treatment_date, triggering_code) or NULL
get_chemo_hits <- function(table_name, chemo_rxnorm, ndc_crosswalk = NULL) {
  tbl <- tryCatch(get_pcornet_table(table_name), error = function(e) NULL)
  if (is.null(tbl)) {
    message(glue("  [{table_name}] table not found — skipping chemo detection"))
    return(NULL)
  }

  if (table_name == "PRESCRIBING") {
    if (!"RXNORM_CUI" %in% colnames(tbl)) {
      message(glue("  [PRESCRIBING] RXNORM_CUI absent — unexpected; skipping"))
      return(NULL)
    }
    tbl %>%
      filter(RXNORM_CUI %in% chemo_rxnorm) %>%
      mutate(treatment_date = coalesce(RX_ORDER_DATE, RX_START_DATE)) %>%
      filter(!is.na(treatment_date)) %>%
      select(ID, treatment_date, triggering_code = RXNORM_CUI) %>%
      collect()

  } else if (table_name == "DISPENSING") {
    if (!"NDC" %in% colnames(tbl)) {
      message(glue("  [DISPENSING] NDC column absent — skipping"))
      return(NULL)
    }
    rows <- tbl %>%
      filter(!is.na(NDC), !is.na(DISPENSE_DATE)) %>%
      select(ID, treatment_date = DISPENSE_DATE, NDC) %>%
      collect()
    if (is.null(ndc_crosswalk) || length(ndc_crosswalk) == 0) {
      message("  [DISPENSING] no NDC crosswalk loaded — skipping chemo match")
      return(NULL)
    }
    rows %>%
      mutate(rxcui = ndc_crosswalk[NDC]) %>%
      filter(!is.na(rxcui), rxcui %in% chemo_rxnorm) %>%
      select(ID, treatment_date, triggering_code = rxcui)

  } else if (table_name == "MED_ADMIN") {
    required <- c("MEDADMIN_TYPE", "MEDADMIN_CODE", "MEDADMIN_START_DATE")
    missing  <- required[!required %in% colnames(tbl)]
    if (length(missing) > 0) {
      message(glue("  [MED_ADMIN] missing columns: {paste(missing, collapse=', ')} — skipping"))
      return(NULL)
    }
    # RX-typed rows: MEDADMIN_CODE holds RxNorm CUI directly
    rx_hits <- tbl %>%
      filter(MEDADMIN_TYPE == "RX",
             MEDADMIN_CODE %in% chemo_rxnorm,
             !is.na(MEDADMIN_START_DATE)) %>%
      select(ID, treatment_date = MEDADMIN_START_DATE, triggering_code = MEDADMIN_CODE) %>%
      collect()
    # ND-typed rows: MEDADMIN_CODE holds NDC — needs crosswalk
    nd_hits <- NULL
    if (!is.null(ndc_crosswalk) && length(ndc_crosswalk) > 0) {
      nd_rows <- tbl %>%
        filter(MEDADMIN_TYPE == "ND",
               !is.na(MEDADMIN_CODE),
               !is.na(MEDADMIN_START_DATE)) %>%
        select(ID, treatment_date = MEDADMIN_START_DATE, NDC = MEDADMIN_CODE) %>%
        collect()
      nd_hits <- nd_rows %>%
        mutate(rxcui = ndc_crosswalk[NDC]) %>%
        filter(!is.na(rxcui), rxcui %in% chemo_rxnorm) %>%
        select(ID, treatment_date, triggering_code = rxcui)
    }
    bind_rows(rx_hits, nd_hits)
  } else {
    message(glue("  [{table_name}] unrecognised table for get_chemo_hits() — skipping"))
    NULL
  }
}
```

### Pattern 2: Crosswalk Build Script (R/108)

One-time HiPerGator-only script. Mirrors R/27's `drug_name_lookup.rds` pattern: harvest unique NDC values, call RxNav in batch with `lookup_ndc_to_rxcui()`, cache as RDS, also write a CSV for audit.

```r
# R/108_build_ndc_rxnorm_crosswalk.R
# Harvests distinct NDCs from DISPENSING + MED_ADMIN ND-typed rows.
# Calls RxNav rxcui?idtype=NDC endpoint per NDC (with httr2 retry, 0.1s sleep).
# Writes data/reference/ndc_rxnorm_crosswalk.rds (named char: NDC -> RxCUI).
# Also writes output/ndc_rxnorm_crosswalk_audit.csv (NDC, rxcui, lookup_status).
# OFFLINE AFTER BUILD — all consumers load the .rds file.
```

Key endpoint (already used in R/27's `lookup_ndc_to_name()`):
```
GET https://rxnav.nlm.nih.gov/REST/rxcui.json?idtype=NDC&id={ndc_11digit}
Response path: data$idGroup$rxnormId[[1]]
```

### Pattern 3: Crosswalk Load Helper

Add to `R/utils/utils_treatment.R`:

```r
#' Load NDC->RxNorm crosswalk from data/reference/ndc_rxnorm_crosswalk.rds
#'
#' Returns named character vector (NDC -> RxCUI) or empty vector with message.
#' Named vector allows O(1) lookup: rxcui <- crosswalk[ndc_value].
#' @return Named character vector or character(0)
load_ndc_crosswalk <- function() {
  path <- here::here("data", "reference", "ndc_rxnorm_crosswalk.rds")
  if (!file.exists(path)) {
    message("  NDC->RxNorm crosswalk not found at ", path,
            " — NDC-coded rows will NOT contribute to chemo detection.")
    message("  Run R/108_build_ndc_rxnorm_crosswalk.R on HiPerGator to build it.")
    return(character(0))
  }
  cw <- readRDS(path)
  message(glue("  NDC crosswalk loaded: {length(cw)} NDC->RxCUI mappings"))
  cw
}
```

### Anti-Patterns to Avoid

- **Keep the phantom RXNORM_CUI guard as-is:** The current `"RXNORM_CUI" %in% colnames(DISPENSING)` guard is silently false in production. It must be replaced, not supplemented.
- **Live API calls during pipeline run:** Never call RxNav from R/26, R/10, etc. The crosswalk must be pre-built and loaded from RDS.
- **Mutating the crosswalk vector inline:** Use `ndc_crosswalk[NDC]` named-vector lookup, not a loop or join — named-vector lookup is O(1) and avoids join column-name collisions.
- **Double-counting:** After expanding sources, `bind_rows()` then `distinct(ID, treatment_date)` before downstream aggregation — the same (ID, date) can appear in both RX-typed and ND-typed rows if a patient received a drug twice same day coded differently.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| NDC->RxCUI HTTP lookup | Custom curl wrapper | R/27's existing `lookup_ndc_to_name()` pattern (httr2 + retry + sleep) | Already battle-tested; same rate-limit handling |
| NDC format normalization | Custom regex | `stringr::str_remove_all(ndc, "-") |> str_pad(11, "right", "0")` | Standard 11-digit NDC normalization; one line |
| Crosswalk caching | Custom file format | `.rds` named vector, identical to R/27's `drug_name_lookup.rds` | Instantaneous load; named-vector O(1) lookup |
| Column-absence handling | `tryCatch` everywhere inline | `get_chemo_hits()` helper with single guard point | Seven sites all behaving consistently |

---

## Exact Consumer Call-Site Enumeration

All confirmed by direct grep (`"RXNORM_CUI" %in% colnames`). Line numbers reference the current file state.

### R/10_cohort_predicates.R — `has_chemo()`
- **Line 336:** `if (!is.null(disp_tbl) && "RXNORM_CUI" %in% colnames(disp_tbl))`
  - Current: DISPENSING guard, filters `RXNORM_CUI %in% chemo_rxnorm`
  - Fix: replace with `get_chemo_hits("DISPENSING", ...)` and `distinct(ID) %>% pull(ID)`
- **Line 347:** `if (!is.null(ma_tbl) && "RXNORM_CUI" %in% colnames(ma_tbl))`
  - Current: MED_ADMIN guard, filters `RXNORM_CUI %in% chemo_rxnorm`
  - Fix: replace with `get_chemo_hits("MED_ADMIN", ...)` and `distinct(ID) %>% pull(ID)`
- **Note:** PRESCRIBING guard at a nearby line uses the same pattern but PRESCRIBING does have RXNORM_CUI — leave it unchanged or convert to helper for consistency.

### R/26_treatment_episodes.R — `extract_chemo_dates_with_codes()`
- **Line 185:** DISPENSING guard (source #5)
  - Current: `"RXNORM_CUI" %in% colnames(get_pcornet_table("DISPENSING"))` then `filter(RXNORM_CUI %in% chemo_rxnorm)`, selects `triggering_code = RXNORM_CUI`
  - Fix: `get_chemo_hits("DISPENSING", chemo_rxnorm, ndc_crosswalk)` — `triggering_code` now holds the resolved RxCUI
- **Line 196:** MED_ADMIN guard (source #6)
  - Current: `"RXNORM_CUI" %in% colnames(get_pcornet_table("MED_ADMIN"))` then `filter(RXNORM_CUI %in% chemo_rxnorm)`
  - Fix: `get_chemo_hits("MED_ADMIN", chemo_rxnorm, ndc_crosswalk)`
- **Also lines 371, 382:** Second function `extract_immunotherapy_dates_with_codes()` also has DISPENSING/MED_ADMIN guards — **scope of this phase is chemo only**; immunotherapy guards left unchanged (deferred per D-03 / CONTEXT deferred).

### R/25_treatment_durations.R — `get_first_chemo_date()` / related function
- **Line 172:** DISPENSING guard
- **Line 183:** MED_ADMIN guard
  - Both: same replacement pattern. Note R/25 uses `ENCOUNTERID` in the select — `get_chemo_hits()` signature should include ENCOUNTERID as optional or callers handle it after the helper returns.

### R/11_treatment_payer.R — two functions
- **Line 186:** DISPENSING guard (first function, returns `disp_date = min(DISPENSE_DATE)`)
- **Line 197:** MED_ADMIN guard (same function)
- **Line 623:** DISPENSING guard (second function, returns `tx_date = max(DISPENSE_DATE)`)
- **Line 631:** MED_ADMIN guard (second function)
  - Fix: In each function, replace the guard+filter block with `get_chemo_hits()` then derive the date aggregate from the returned tibble.

### R/27_drug_name_resolution.R — code harvest
- **Line 332:** PRESCRIBING guard — keep as-is (PRESCRIBING has RXNORM_CUI)
- **Line 345:** DISPENSING guard (`"RXNORM_CUI" %in% colnames(get_pcornet_table("DISPENSING"))`) — current logic harvests `RXNORM_CUI` codes from DISPENSING plus NDC codes where `RXNORM_CUI` matches chemo
  - Fix: DISPENSING has NDC only. Replace with: harvest all distinct NDC values from chemo-matching DISPENSING rows (using crosswalk), emit them as code_type="NDC". Remove the RXNORM_CUI path for DISPENSING entirely.
- **Line 358:** MED_ADMIN guard — fix to access `MEDADMIN_CODE` where `MEDADMIN_TYPE=='RX'` for RXNORM codes, and `MEDADMIN_CODE` where `MEDADMIN_TYPE=='ND'` for NDC codes
- **Line 372:** Second DISPENSING guard (NDC harvest) — currently gated on `RXNORM_CUI` present, which is always false. Fix: gate on `NDC %in% colnames(tbl)` directly.

### R/20_treatment_inventory.R — inventory by source table
- **Line ~209:** DISPENSING: `group_by(code = RXNORM_CUI, drug_name = RAW_DISPENSE_MED_NAME)` — `RXNORM_CUI` column absent; also `RAW_DISPENSE_MED_NAME` column absent from this extract (confirmed in CONTEXT.md code_context).
  - Fix (RXNORM_CUI): replace with NDC-keyed path: `group_by(code = NDC, drug_name = NA_character_)` — no drug name from DISPENSING in this extract; `tryCatch` wrapper already present so errors degrade gracefully.
  - Fix (RAW_DISPENSE_MED_NAME): remove the column reference; use `NA_character_` as drug_name for DISPENSING rows. The existing `tryCatch(..., error = function(e) empty_result())` wrapper means current runtime silently returns empty — the fix surfaces real data.
- **Line ~242:** MED_ADMIN: `group_by(code = RXNORM_CUI, drug_name = RAW_MEDADMIN_MED_NAME)` — `RXNORM_CUI` absent; `RAW_MEDADMIN_MED_NAME` IS present in this extract.
  - Fix: Replace `code = RXNORM_CUI` with `code = MEDADMIN_CODE` where `MEDADMIN_TYPE %in% c("RX","ND")`; keep `drug_name = RAW_MEDADMIN_MED_NAME`.

### R/76_treatment_source_coverage.R
- **Line 232:** DISPENSING guard
- **Line 242:** MED_ADMIN guard
  - Fix: same `get_chemo_hits()` replacement pattern.

---

## NDC-to-RxNorm Crosswalk Options

### Option A: RxNav API + cached RDS (RECOMMENDED)

Mirrors R/27's `drug_name_lookup.rds` one-time-build pattern. R/108 harvests distinct NDCs from both DISPENSING and MED_ADMIN ND-typed rows, calls `rxcui.json?idtype=NDC` for each, saves as named character RDS.

**RxNav endpoint (confirmed in R/27 source, line 219):**
```
GET https://rxnav.nlm.nih.gov/REST/rxcui.json?idtype=NDC&id={ndc_normalized}
Response: data$idGroup$rxnormId[[1]]  (character, or NULL if not found)
```

Rate limit: ~20 req/sec is safe; R/27 uses 0.1s sleep (10 req/sec). For 718k dispensing rows the distinct NDC count will be much smaller — likely hundreds to low thousands of unique NDC codes for the HL cohort.

**OFFLINE after build:** The RDS is committed to `data/reference/ndc_rxnorm_crosswalk.rds`. All seven consumers load it once at startup via `load_ndc_crosswalk()`. No network access during pipeline runs. This satisfies the HiPerGator offline requirement.

**Confidence: HIGH** — the endpoint shape is verified in R/27 lines 218-241.

### Option B: Bundled NLM RxNorm NDC reference file

NLM distributes `RXNSAT.RRF` (RxNorm RXNSAT attribute file) and a dedicated `NDC` crosswalk file as part of the full RxNorm distribution. These are large (~500MB compressed). Loading the full file would require either a filtered pre-built CSV or reading a multi-GB flat file.

**Why not recommended:** The RxNav API approach is already implemented in R/27 and produces a minimal extract (only NDCs actually present in this patient cohort). The full RxNorm distribution adds a large non-code dependency and setup complexity inappropriate for an exploratory pipeline. MEDIUM confidence on format/size — not inspected directly.

### NDC Format Normalization

PCORnet CDM v7.0 specifies NDC in 11-digit format without hyphens (e.g., `00069306030`). However, source data in this extract may include hyphenated forms (e.g., `0069-3060-30`). The RxNav API accepts both forms but the project should normalize before lookup and storage.

```r
# Normalize NDC to 11-digit no-hyphen for crosswalk key
normalize_ndc <- function(ndc) {
  stringr::str_remove_all(ndc, "-") %>%
    stringr::str_pad(width = 11, side = "left", pad = "0")
}
```

**Pitfall:** Different NDC formats in source data vs crosswalk keys cause silent misses. Normalize both at build time (when saving crosswalk keys) and at lookup time (before named-vector access).

---

## D-12 Revision Scope

D-12 ("RXNORM_CUI only, no NDC matching") is documented in multiple places and all must be updated:

| Location | Current text | Required change |
|----------|-------------|-----------------|
| `R/01_load_pcornet.R` line ~307 | `# RXNORM_CUI is the key matching column for chemo drugs (D-12: no NDC matching)` (DISPENSING_SPEC) | Update to: `# NDC is the key column in this extract (D-12 revised Phase 122: NDC->RxNorm crosswalk used)` |
| `R/01_load_pcornet.R` line ~322 | Same comment in `RXNORM_CUI = col_character() # KEY: chemo matching per D-12` in DISPENSING_SPEC | DISPENSING_SPEC: Remove the `RXNORM_CUI` column declaration entirely (it does not exist in this extract — declaring it causes readr/vroom to silently add an all-NA column which then makes the old guard silently pass on fixtures but silently fail on prod — this is the root cause mechanism). |
| `R/01_load_pcornet.R` (MED_ADMIN_SPEC) | `RXNORM_CUI = col_character() # KEY: chemo matching per D-12` | Remove `RXNORM_CUI` declaration; add comment noting MEDADMIN_CODE+MEDADMIN_TYPE encode the drug code. |
| `R/10_cohort_predicates.R` | Comment `# DISPENSING: RXNORM_CUI matching per D-12` (line ~334) | Update comment |
| `R/11_treatment_payer.R` | Comment `# DISPENSING DISPENSE_DATE: RXNORM_CUI matching per D-12` (line ~184) | Update comment |
| `R/25_treatment_durations.R` | Comment `# 5. DISPENSING: RXNORM_CUI matching` (line ~169) | Update |
| `R/26_treatment_episodes.R` | Comment `# 5. DISPENSING: RXNORM_CUI — bare RxNorm CUI` (line ~182) | Update |

**Critical insight on root-cause mechanism:** `DISPENSING_SPEC` in R/01 declares `RXNORM_CUI = col_character()`. When vroom/readr loads a CSV that lacks this column, the declared column is silently added as all-NA. The test fixture *also* declares the column (and has it in the header per `head -1` inspection). So locally the fixture has RXNORM_CUI (all-NA) which makes `"RXNORM_CUI" %in% colnames(disp_tbl)` return TRUE — but then `filter(RXNORM_CUI %in% chemo_rxnorm)` returns zero rows silently. In production with DuckDB, `get_pcornet_table("DISPENSING")` returns only columns actually in the CSV, so RXNORM_CUI is absent and the guard short-circuits. **Removing RXNORM_CUI from the col_specs is therefore part of the fix, not optional cleanup.**

---

## Fixture Corrections

### MED_ADMIN_Mailhot_V1.csv

Current header (confirmed by `head -1` inspection):
```
MEDADMINID,ID,ENCOUNTERID,PRESCRIBINGID,MEDADMIN_CODE,MEDADMIN_TYPE,MEDADMIN_START_DATE,MEDADMIN_STOP_DATE,MEDADMIN_ROUTE,RXNORM_CUI,RAW_MEDADMIN_MED_NAME,SOURCE
```

Required new header (drop RXNORM_CUI, keep all others):
```
MEDADMINID,ID,ENCOUNTERID,PRESCRIBINGID,MEDADMIN_CODE,MEDADMIN_TYPE,MEDADMIN_START_DATE,MEDADMIN_STOP_DATE,MEDADMIN_ROUTE,RAW_MEDADMIN_MED_NAME,SOURCE
```

Required rows: at least one row with `MEDADMIN_TYPE = "RX"` and `MEDADMIN_CODE` in `TREATMENT_CODES$chemo_rxnorm`, and at least one row with `MEDADMIN_TYPE = "ND"` with a synthetic NDC that is also a key in the committed crosswalk RDS (so the ND path executes locally). Also include rows with `MEDADMIN_TYPE = "NI"` or `"OT"` to confirm those are filtered out.

### DISPENSING_Mailhot_V1.csv

Current header (confirmed):
```
DISPENSINGID,PRESCRIBINGID,ID,DISPENSE_DATE,NDC,DISPENSE_SUP,DISPENSE_AMT,DISPENSE_DOSE_DISP,DISPENSE_DOSE_DISP_UNIT,DISPENSE_ROUTE,RAW_NDC,RXNORM_CUI,DISPENSE_SOURCE,RAW_DISPENSE_MED_NAME,SOURCE
```

Required new header (drop RXNORM_CUI, drop RAW_DISPENSE_MED_NAME — neither exists in production):
```
DISPENSINGID,PRESCRIBINGID,ID,DISPENSE_DATE,NDC,DISPENSE_SUP,DISPENSE_AMT,DISPENSE_DOSE_DISP,DISPENSE_DOSE_DISP_UNIT,DISPENSE_ROUTE,RAW_NDC,DISPENSE_SOURCE,SOURCE
```

Required rows: at least one row with an NDC that maps to a chemo CUI in the crosswalk RDS, and at least one row with an NDC that has no crosswalk hit (to confirm graceful skip for misses).

**Important:** The fixture crosswalk RDS must include a synthetic entry for the NDC used in the fixture, so the ND/DISPENSING path exercises successfully without a network call locally.

---

## R/39 and R/88 Registration Mechanics

### R/39 registration

R/108 (the crosswalk build script) should NOT be in `investigation_scripts` in R/39 — it is a one-time data preparation step, not a repeatable investigation. Following the R/107 precedent (SCRIPT_INDEX only, not R/39/R/88), register R/108 in SCRIPT_INDEX.md only.

If the consumer-fix logic is embedded directly in the existing scripts (R/10, R/26, etc.) rather than in a new standalone script, there is nothing new to register in R/39. The `investigation_scripts` vector in R/39 already includes those scripts.

### R/88 smoke-test section

Current last section: **15s** (Phase 121, R/106). The next section is **15t**.

New section `15t` covers:
1. Fixture column headers (MED_ADMIN: no RXNORM_CUI; DISPENSING: no RXNORM_CUI, no RAW_DISPENSE_MED_NAME)
2. `get_chemo_hits()` function exists in `utils_treatment.R`
3. `load_ndc_crosswalk()` function exists in `utils_treatment.R`
4. `R/108_build_ndc_rxnorm_crosswalk.R` exists
5. R/10, R/25, R/26, R/11, R/27, R/20, R/76 — grep confirms old broken guard removed
6. R/10, R/25, R/26 — grep confirms `get_chemo_hits` appears in the file
7. R/01 DISPENSING_SPEC: `RXNORM_CUI` column declaration removed
8. R/01 MED_ADMIN_SPEC: `RXNORM_CUI` column declaration removed
9. D-12 comment in R/01 updated (grep "D-12 revised Phase 122" or equivalent)
10. `data/reference/ndc_rxnorm_crosswalk.rds` exists (for local fixture-based run: requires synthetic crosswalk fixture)
11-14: 4 additional structural checks on helper signature, SCRIPT_INDEX R/108 row, summary message in R/88, etc.

Follow the 14-check convention used by Sections 15m-15s.

### SCRIPT_INDEX.md

- Add R/108 row to Post-Renumber Investigations (100+) table
- 100+ count: 8 → 9
- Total: 94 → 95

---

## Common Pitfalls

### Pitfall 1: readr/vroom col_spec declaring absent columns
**What goes wrong:** `RXNORM_CUI = col_character()` in `DISPENSING_SPEC` causes vroom to inject an all-NA column. `"RXNORM_CUI" %in% colnames(tbl)` returns TRUE locally but the column is all-NA, so the filter produces zero rows silently. In DuckDB mode, the CSV columns are read directly and the absent column does not appear.
**Prevention:** Remove `RXNORM_CUI` from DISPENSING_SPEC and MED_ADMIN_SPEC. The fix and the spec update are the same task.

### Pitfall 2: NDC leading-zero truncation
**What goes wrong:** NDC values stored as numeric or read without explicit character type lose leading zeros: `00069306030` becomes `69306030`. The crosswalk key built from the full 11-digit form will not match.
**Prevention:** `NDC = col_character()` is already set in DISPENSING_SPEC (confirmed). Ensure the crosswalk build script also normalizes/pads to 11 digits before storing keys.

### Pitfall 3: MEDADMIN_TYPE values other than RX and ND
**What goes wrong:** Values NI (no information), UN (unknown), OT (other) appear in MEDADMIN_TYPE. Matching `MEDADMIN_CODE` for these rows against chemo_rxnorm or an NDC crosswalk produces false matches (the code system is unknown).
**Prevention:** `get_chemo_hits()` explicitly filters `MEDADMIN_TYPE == "RX"` and `MEDADMIN_TYPE == "ND"`. Any other value is implicitly excluded.

### Pitfall 4: Double-inflation of episode counts
**What goes wrong:** The same patient-date pair appears in both PRESCRIBING (via RXNORM_CUI) and MED_ADMIN RX-typed (same CUI recorded in both tables for the same administration event). Stacking without dedup inflates episode counts and (ID,date) pair counts.
**Prevention:** The existing `stack_and_dedup_with_codes()` in R/26 already handles this. In R/25 and R/11, the call to `distinct(ID, treatment_date)` before `group_by` aggregation is the dedup point. Confirm these downstream dedup steps are present before or immediately after adding the new sources.

### Pitfall 5: Crosswalk misses (NDC with no RxCUI)
**What goes wrong:** Not every dispensed drug is a chemo drug. A large fraction of DISPENSING NDCs will return no RxCUI (patient comorbidity medications). These generate `NA` in the crosswalk lookup and must be filtered before the `%in% chemo_rxnorm` check.
**Prevention:** `filter(!is.na(rxcui), rxcui %in% chemo_rxnorm)` — both conditions required. The `!is.na()` guard handles crosswalk misses gracefully.

### Pitfall 6: Windows local / no Rscript dual-environment
**What goes wrong:** R/108 makes live network calls to RxNav. These cannot run on the Windows local dev machine (no `Rscript`, and more importantly, results should come from the actual production NDC values).
**Prevention:** R/108 is HiPerGator-only by design (mirrors R/107 precedent). The R/88 Section 15t check for `data/reference/ndc_rxnorm_crosswalk.rds` should include an IS_LOCAL guard or accept that this check is skipped locally if the file doesn't exist — but consumer tests using the fixture synthetic crosswalk entry CAN run locally.

### Pitfall 7: R/20 tryCatch masking real errors
**What goes wrong:** R/20 wraps each source table block in `tryCatch(..., error = function(e) empty_result())`. This currently swallows the RXNORM_CUI column-access error silently. After the fix, if the new column access (e.g., `group_by(code = NDC, ...)`) also fails due to a different issue, the tryCatch will again swallow it.
**Prevention:** Add a `message(glue("  [R/20 DISPENSING error]: {e$message}"))` inside the error handler so failures are visible in logs even when gracefully skipped.

### Pitfall 8: R/27 NDC harvest logic relies on `RXNORM_CUI` presence to gate NDC harvest
**What goes wrong:** R/27 line 372 gates the NDC harvest from DISPENSING on `"RXNORM_CUI" %in% colnames(get_pcornet_table("DISPENSING"))` (the logic being: harvest NDCs that appear alongside chemo RXNORM_CUIs). Since RXNORM_CUI is absent, this block never runs in production — the NDC codes from DISPENSING are never collected and their drug names are never resolved.
**Prevention:** Fix this specific block to gate on `"NDC" %in% colnames(tbl)` instead, and use the crosswalk to identify which NDCs are chemo-related before harvesting for drug name lookup.

---

## Code Examples

### NDC normalization (verified pattern from R/27 usage of stringr)
```r
normalize_ndc <- function(ndc) {
  ndc |>
    stringr::str_remove_all("-") |>
    stringr::str_pad(width = 11, side = "left", pad = "0")
}
```

### RxNav NDC-to-RxCUI lookup (verified shape from R/27 lines 214-261)
```r
lookup_ndc_to_rxcui <- function(ndc, sleep_sec = 0.1) {
  url <- glue::glue(
    "https://rxnav.nlm.nih.gov/REST/rxcui.json?idtype=NDC&id={ndc}"
  )
  result <- tryCatch({
    resp <- httr2::request(url) |>
      httr2::req_timeout(10) |>
      httr2::req_retry(max_tries = 3,
        is_transient = ~ httr2::resp_status(.x) %in% c(429, 503, 504)) |>
      httr2::req_perform()
    data <- httr2::resp_body_json(resp)
    if (!is.null(data$idGroup$rxnormId) && length(data$idGroup$rxnormId) > 0) {
      data$idGroup$rxnormId[[1]]
    } else {
      NA_character_
    }
  }, error = function(e) NA_character_)
  Sys.sleep(sleep_sec)
  result
}
```

### Named-vector crosswalk build (batch)
```r
# After harvesting distinct NDCs from DISPENSING + MED_ADMIN ND rows:
# ndc_vec <- c("00069306030", "00310090230", ...)
rxcui_vec <- purrr::map_chr(ndc_vec, lookup_ndc_to_rxcui)
crosswalk <- stats::setNames(rxcui_vec, ndc_vec)
crosswalk <- crosswalk[!is.na(crosswalk)]   # drop misses
saveRDS(crosswalk, here::here("data", "reference", "ndc_rxnorm_crosswalk.rds"))
```

### Corrected MED_ADMIN access (from R/107, verified lines 244-250)
```r
ma_tbl %>%
  filter(MEDADMIN_TYPE == "RX",
         MEDADMIN_CODE %in% TREATMENT_CODES$chemo_rxnorm,
         !is.na(MEDADMIN_START_DATE)) %>%
  select(ID, treatment_date = MEDADMIN_START_DATE, triggering_code = MEDADMIN_CODE) %>%
  collect()
```

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| RxNav API (rxnav.nlm.nih.gov) | R/108 crosswalk build | HiPerGator only (network) | Current NLM API | None — build step must run on HiPerGator |
| httr2 | R/108 API calls | Yes (in renv.lock, used by R/27) | >= 1.0.0 | None needed |
| R/utils/utils_treatment.R | All consumers (already sourced via R/00_config.R) | Yes | Current | N/A |
| data/reference/ndc_rxnorm_crosswalk.rds | All NDC consumers at runtime | Does not exist yet | — | `load_ndc_crosswalk()` returns character(0) with message; NDC path gracefully skipped |

**Missing dependencies with no fallback:**
- RxNav network access for the build step (R/108 must run on HiPerGator, not locally). This blocks NDC crosswalk population but does NOT block the MED_ADMIN RX-typed fix or the consumer guard fixes.

**Missing dependencies with fallback:**
- `ndc_rxnorm_crosswalk.rds` absent: `load_ndc_crosswalk()` returns empty with message; DISPENSING and MED_ADMIN ND rows skip chemo detection gracefully until the file is built.

**Execution sequence implication:** The phase has a natural two-wave ordering:
1. Wave 1 (locally verifiable): fix all seven consumer guards + `utils_treatment.R` helpers + fixture corrections + R/01 col_spec updates. This enables MED_ADMIN RX-typed hits immediately.
2. Wave 2 (HiPerGator required): run R/108 to build the crosswalk, commit the RDS, then MED_ADMIN ND and DISPENSING contributions activate.

---

## Validation Architecture

Phase 122 does not introduce a new standalone investigation script (R/108 is a data preparation utility, not an analysis script). The smoke-test approach follows the existing Section 15x convention in R/88.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | R/88_smoke_test_comprehensive.R (project-specific structural smoke test) |
| Config file | None — sourced directly |
| Quick run command | `Rscript R/88_smoke_test_comprehensive.R` (HiPerGator) |
| Full suite command | Same (single script) |
| Windows local | Structural grep-only checks only (no Rscript) |

### Phase Requirements → Test Map

| Requirement | Behavior | Test Type | Command | Notes |
|-------------|----------|-----------|---------|-------|
| D-01 (MED_ADMIN RX fix) | `get_chemo_hits("MED_ADMIN")` uses MEDADMIN_CODE+TYPE | Structural | grep R/utils/utils_treatment.R for `MEDADMIN_TYPE.*RX` | Section 15t Check 3 |
| D-02 (NDC crosswalk) | `get_chemo_hits("DISPENSING")` uses NDC + crosswalk | Structural | grep utils_treatment.R for `ndc_crosswalk` | Section 15t Check 4 |
| D-05 (graceful skip) | Guards degrade with message, not crash | Structural | grep all 7 consumers for absence of old guard | Section 15t Checks 5-11 |
| D-07 (fixture correction) | MED_ADMIN fixture has no RXNORM_CUI header | Structural | grep fixture header | Section 15t Check 1 |
| D-07 (fixture correction) | DISPENSING fixture has no RXNORM_CUI header | Structural | grep fixture header | Section 15t Check 2 |
| D-12 revision | R/01 specs no longer declare RXNORM_CUI for DISPENSING/MED_ADMIN | Structural | grep R/01 for absence of `RXNORM_CUI.*DISPENSING_SPEC` | Section 15t Check 8 |

### R/88 Section 15t Wave 0 Gaps
- [ ] Section 15t does not yet exist — must be authored as part of this phase
- [ ] Synthetic crosswalk fixture for local testing: a minimal `ndc_rxnorm_crosswalk.rds` with one or two NDC-to-RxCUI mappings matching the DISPENSING fixture rows, committed to `data/reference/` so the local NDC path exercises locally

---

## Open Questions

1. **ENCOUNTERID in DISPENSING and MED_ADMIN**
   - What we know: R/26 includes ENCOUNTERID in its selects from all sources. DISPENSING_SPEC does not declare ENCOUNTERID; MED_ADMIN_SPEC declares ENCOUNTERID.
   - What's unclear: Does DISPENSING in this extract actually have an ENCOUNTERID column? If not, `select(..., ENCOUNTERID)` will error.
   - Recommendation: In `get_chemo_hits()`, omit ENCOUNTERID from the return (let callers add a NULL column if needed) OR check `"ENCOUNTERID" %in% colnames(tbl)` before selecting it. R/26's `stack_and_dedup_with_codes()` presumably handles NULL ENCOUNTERID.

2. **Distinct NDC count for crosswalk build time estimate**
   - What we know: DISPENSING has 718,891 rows and 4,389 cohort patients. The number of distinct NDC values across all 718k rows is unknown but likely in the hundreds to low thousands for the HL cohort.
   - What's unclear: Total distinct NDC count determines how long the API build step takes. At 0.1s/call: 1,000 NDCs = ~2 minutes; 10,000 NDCs = ~17 minutes.
   - Recommendation: R/108 should report the distinct NDC count before making API calls and offer a progress counter (every 100 calls).

3. **Synthetic crosswalk RDS for local testing**
   - What we know: To test the DISPENSING NDC path locally, a minimal crosswalk RDS with a known mapping is needed.
   - What's unclear: Whether to commit a hand-crafted fixture RDS or generate it from the fixture NDC values during the R/88 Section 15t test setup.
   - Recommendation: Commit a minimal hand-crafted RDS alongside the fixture CSVs (e.g., `tests/fixtures/ndc_rxnorm_crosswalk_test.rds`) and have `load_ndc_crosswalk()` use a different path when `IS_LOCAL == TRUE`. Alternatively, commit the synthetic RDS to `data/reference/` as the canonical path and point both environments at it — safe because the crosswalk is append-only.

4. **R/20 broader DISPENSING/MED_ADMIN rewrite scope**
   - What we know: R/20 references both `RXNORM_CUI` and `RAW_DISPENSE_MED_NAME` — both absent from the real extract. The `tryCatch` wrapper currently hides these failures.
   - What's unclear: Whether R/20 should fully surface DISPENSING NDC codes (grouped by NDC, drug_name=NA) in the inventory output, or whether the simpler fix is to just silence the RXNORM_CUI reference and leave DISPENSING mostly absent from the inventory.
   - Recommendation: Surface the NDC codes with `drug_name = coalesce(NA_character_)` for now — the inventory will show NDC codes without names, which is still informative. A separate phase can add drug_name resolution to the inventory if needed.

---

## Sources

### Primary (HIGH confidence)
- Direct source inspection: R/107_med_admin_dispensing_gap_diagnostic.R — confirmed correct MED_ADMIN RX-typed access pattern
- Direct source inspection: R/27_drug_name_resolution.R lines 214-261 — confirmed RxNav NDC-to-RxCUI endpoint shape
- Direct source inspection: R/01_load_pcornet.R lines 304-348 — confirmed phantom RXNORM_CUI in DISPENSING_SPEC and MED_ADMIN_SPEC
- Direct source inspection: grep output — confirmed all 7 broken call sites with line numbers
- Direct source inspection: R/00_config.R — confirmed TREATMENT_CODES$chemo_rxnorm exists; confirmed ID not PATID convention
- Direct source inspection: `head -1` of fixture CSVs — confirmed phantom RXNORM_CUI column in both fixtures
- Direct source inspection: R/88_smoke_test_comprehensive.R — confirmed last section is 15s; next is 15t
- Direct source inspection: R/39_run_all_investigations.R — confirmed R/107 not in investigation_scripts (SCRIPT_INDEX only)

### Secondary (MEDIUM confidence)
- RxNav API endpoint `rxcui.json?idtype=NDC` — endpoint shape confirmed via R/27 code; live availability not verified this session but known stable NLM service

### Tertiary (LOW confidence)
- DISPENSING distinct NDC count estimate — not measured; derived from row count heuristics

---

## Metadata

**Confidence breakdown:**
- Consumer call sites: HIGH — direct grep with line numbers
- NDC crosswalk approach: HIGH — endpoint shape verified in R/27
- Fixture correction: HIGH — `head -1` confirms exact headers
- R/88 next section (15t): HIGH — last section 15s confirmed
- SCRIPT_INDEX counts (100+ count 8→9, Total 94→95): HIGH — grep confirmed current state
- Distinct NDC count for build-time estimate: LOW — not measured

**Research date:** 2026-07-14
**Valid until:** Stable (this is internal source inspection; valid until the files change)
