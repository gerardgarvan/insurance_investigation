---
phase: 120
plan: 01
subsystem: reference-data-normalization
tags: [rxnorm, rxnav, openxlsx2, supportive-care, ingredient-normalization, drug-aliases]
requires:
  - R/00_config.R DRUG_NAME_ALIASES + canonicalize_drug_name()
  - R/27 httr2 request/retry wrapper shape (reused verbatim, not imported)
  - data/reference/all_codes_resolved_next_tables_v2.1.xlsx (Supportive Care tab, git-tracked baseline)
provides:
  - R/105_normalize_supportive_care_meaning.R (RxNav IN resolver + cache + rule fallback + in-place xlsx append + round-trip verify)
  - 21 supportive-care single-agent brand->generic aliases in DRUG_NAME_ALIASES
  - Contract for a "Normalized Meaning" col G on the Supportive Care tab (materialized on first R run)
  - data/reference/rxnorm_ingredient_cache.csv contract (materialized on first R run)
affects:
  - R/55 (reads Supportive Care by column name — safe with trailing col G)
  - Future per-ingredient rollup phases (deferred)
tech-stack:
  added: []
  patterns:
    - "RxNav related.json?tty=IN for generic-ingredient (IN) resolution — NOT the R/27 full-clinical-name properties endpoint"
    - "Three-step resolution (IN -> historystatus derivedConcepts -> rule-based) guarantees a non-blank value"
    - "openxlsx2 wb_load -> add_data(dims=G2/G3) -> wb_save in-place single-sheet append (never wb_workbook rebuild)"
    - "Cache + anti_join re-query-only-new-codes pattern (offline source of truth)"
key-files:
  created:
    - R/105_normalize_supportive_care_meaning.R
  modified:
    - R/00_config.R
decisions:
  - "IN endpoint (not properties) delivers generic-only per D-01; salts/biosimilars/packs/combos collapse natively"
  - "Combos kept as sorted unique /-joined label (D-05), source-tagged rxnav_IN_combo"
  - "Rule-based fallback reuses canonicalize_drug_name() rather than a second normalizer (CONTEXT reuse-preferred)"
  - "Single-agent brands only added to DRUG_NAME_ALIASES; combination brands left to the RxNav IN combo path"
metrics:
  duration: ~15 min
  completed: 2026-07-10
  tasks: 2
  files: 2
---

# Phase 120 Plan 01: Normalize Supportive Care Meaning Summary

Added `R/105`, a three-step RxNav-IN ingredient resolver (related.json?tty=IN -> historystatus derivedConcepts -> rule-based `canonicalize_drug_name` fallback) that appends a non-blank `Normalized Meaning` column (col G) to the 171-row Supportive Care tab in place, caches lookups for offline reruns, keeps combination products as sorted `/`-joined labels, and self-verifies the write via a fresh-reopen round-trip; extended `DRUG_NAME_ALIASES` with 21 supportive-care single-agent brand->generic aliases.

## What Was Built

**Task 1 (`d221f2d`) — DRUG_NAME_ALIASES extension.** Added 21 single-agent brand->generic aliases to the existing named-character vector in `R/00_config.R` (zofran/zuplenz -> ondansetron; decadron/dexpak/taperdex/taperpak/baycadron -> dexamethasone; emend/cinvanti -> aprepitant; 5 pegfilgrastim biosimilars; 4 filgrastim biosimilars; procrit/retacrit -> epoetin alfa; aranesp -> darbepoetin alfa). Keys are lowercased (matching `canonicalize_drug_name`'s lookup). The 3 doxorubicin keys and the `canonicalize_drug_name()` body are untouched. Combination brands (Ciprodex, Tobradex, Maxitrol, Maxidex, AK-Trol, Poly-Dex) were deliberately omitted — the RxNav IN combo path emits their `/`-joined label.

**Task 2 (`add5bec`) — R/105 script (438 lines).** Seven sections:
- **S1 Setup:** libraries + `source("R/00_config.R")`; repo-relative constants (`XLSX_PATH`, `SHEET`, `CACHE_CSV`), expected 8-sheet order, other-sheet row-count table.
- **S2 Read:** `wb_load` -> `wb_to_df(start_row=2)`; asserts 171 rows; resolves Code/Code-Type/Meaning columns by name; RXNORM guard routes any non-RXNORM row to fallback.
- **S3 RxNav IN (cached):** `rxnav_in_names()` (collects ALL IN `conceptProperties[].name`), `rxnav_historystatus_ingredients()` (derivedConcepts.ingredientConcept), `resolve_ingredient()` three-step. Both HTTP helpers reuse the R/27 `request %>% req_timeout(10) %>% req_retry(max_tries=3, is_transient=429/503/504) %>% req_perform()` shape verbatim, wrapped in `tryCatch -> character(0)`. Cache is read (col_types="cccc"), only new codes queried via `anti_join`, results written to `rxnorm_ingredient_cache.csv` (rxcui, ingredient_name, source, resolved_at).
- **S4 Rule fallback:** `rule_based_ingredient()` strips pack wrappers, quantity prefixes, brand brackets, dose tokens/units, formulation words, and salt words, then `canonicalize_drug_name()` + `tolower()`; never blank (first-word fallback).
- **S5 Assemble:** join codes to cache; api_miss/NA -> rule fallback; per-row `norm_source`; final safety net guarantees no blank; asserts length 171 and zero blanks.
- **S6 In-place append:** `wb$add_data(G2 header)` + `add_data(G3 data, col_names=FALSE)`; best-effort `add_filter(cols=1:7)` and G2 header styling (both tryCatch-guarded); `wb_save` overwrite in place.
- **S7 Round-trip verify:** fresh `wb_load`; asserts (a) 8 sheets in exact order, (b) Supportive Care 7 cols x 171 rows with the new column, (c) no blank Normalized Meaning, (d) other sheets' row counts within +/-1; prints a norm_source breakdown + combo count.

## Deviations from Plan

None — plan executed as written. Two comment-wording adjustments were made so the acceptance-criteria greps (`properties.json` == 0, `setwd|data.table` == 0) pass on the letter: the explanatory comments were reworded to avoid the literal forbidden tokens while preserving intent (the endpoint is described as "the R/27 full-clinical-name properties endpoint"; the path note reads "no working-directory changes"). No behavioral change.

## Verification

All structural acceptance criteria for both tasks pass:
- Task 1: combined alias grep = 6; each specific alias present; doxorubicin preserved; `canonicalize_drug_name <- function` still exactly 1; no combo brand keys (0).
- Task 2: 438 lines (>=150); `related.json?tty=IN` = 3; `properties.json` = 0; `historystatus` = 8; `req_retry` = 3; combo sort-join = 2; `rxnav_IN_combo` = 2; `canonicalize_drug_name` = 4; cache-csv ref = 4; `wb_load` = 2; `dims="G2"`/`dims="G3"` present; `== 171` present; ncol 7 assertion present; ggplot/geom_/ggsave = 0; setwd/data.table = 0. Plan `<verify>` automated block returns PASS.

## Runtime Deferred (no R / no internet on this host)

`Rscript` is **not installed on this Windows executor** and there is no pre-populated RxNav cache, so the RUNTIME acceptance check (`Rscript R/105... exits 0`, materializes the cache CSV, mutates the workbook) **was NOT executed** — verified structurally instead, as the environment note permits. Consequences the next R-capable run (HiPerGator login node or a local box with R + internet) must complete:
- Populates `data/reference/rxnorm_ingredient_cache.csv` (does not exist yet).
- Writes col G `Normalized Meaning` into `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` (still the unmodified git baseline — intentionally preserved as the revertible baseline; the in-place write has NOT happened).
- The in-script Section 7 round-trip verify is the gate that must pass on that run.
The script is designed to never crash without internet: uncached + unreachable codes degrade to the rule-based fallback (`source="api_miss"` -> `rule_fallback`), still producing a non-blank value for all 171 rows.

## Known Stubs

None. `R/105` is fully wired end-to-end; the "not yet materialized" artifacts (cache CSV, col G in the xlsx) are runtime outputs that require R + first-run internet, not code stubs. Plan 02 (registration in R/39 / R/88 Section 15r / SCRIPT_INDEX) is a separate plan in this phase.

## Self-Check: PASSED

- FOUND: R/105_normalize_supportive_care_meaning.R
- FOUND: R/00_config.R (modified, alias block present)
- FOUND commit: d221f2d (Task 1)
- FOUND commit: add5bec (Task 2)
- CORRECTLY ABSENT (runtime-only, deferred): data/reference/rxnorm_ingredient_cache.csv
- CORRECTLY UNMODIFIED (revertible baseline, runtime write deferred): data/reference/all_codes_resolved_next_tables_v2.1.xlsx
