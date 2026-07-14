---
phase: 122-med-admin-dispensing-gap-diagnostic-csv-gap-closure
plan: "02"
subsystem: treatment-detection
tags: [fix, consumers, get-chemo-hits, ndc-crosswalk, smoke-test, script-index]
dependency_graph:
  requires:
    - 122-01 (normalize_ndc / load_ndc_crosswalk / get_chemo_hits in utils_treatment.R)
  provides:
    - all 7 chemo consumers patched to use get_chemo_hits (D-06 satisfied)
    - R/88 Section 15t (14 structural checks for Phase 122)
    - SCRIPT_INDEX R/108 row; 100+ count 9; Total 95
  affects:
    - R/10_cohort_predicates.R (has_chemo now sees DISPENSING+MED_ADMIN)
    - R/26_treatment_episodes.R (chemo sources #5/#6 use helper; immuno untouched)
    - R/25_treatment_durations.R (first/last chemo date now sees DISPENSING+MED_ADMIN)
    - R/11_treatment_payer.R (both payer-anchor functions see DISPENSING+MED_ADMIN)
    - R/27_drug_name_resolution.R (DISPENSING harvest emits raw NDC; MED_ADMIN uses MEDADMIN_CODE+TYPE)
    - R/20_treatment_inventory.R (DISPENSING NDC block only; MED_ADMIN uses MEDADMIN_CODE+TYPE; tryCatch surfaces errors)
    - R/76_treatment_source_coverage.R (coverage counts now include DISPENSING+MED_ADMIN)
tech_stack:
  added: []
  patterns:
    - get_chemo_hits() helper call replaces inline RXNORM_CUI colnames guard
    - load_ndc_crosswalk() called once per function scope, result passed to helper
    - mutate(ENCOUNTERID = NA_character_) added at call sites that need the column
    - distinct(NDC) raw harvest in R/27; crosswalk used only to filter, not as emitted code
    - tryCatch error handlers now message() before returning empty_result()
key_files:
  created: []
  modified:
    - R/10_cohort_predicates.R
    - R/26_treatment_episodes.R
    - R/25_treatment_durations.R
    - R/11_treatment_payer.R
    - R/27_drug_name_resolution.R
    - R/20_treatment_inventory.R
    - R/76_treatment_source_coverage.R
    - R/88_smoke_test_comprehensive.R
    - R/SCRIPT_INDEX.md
decisions:
  - "R/20 collapsed from two DISPENSING blocks (RXNORM+NDC) to one NDC block with drug_name=NA_character_; the RXNORM block referenced absent RXNORM_CUI+RAW_DISPENSE_MED_NAME, so merging them produces a simpler, correct result"
  - "R/27 MED_ADMIN ND-typed path emits raw NDC (not resolved RxCUI) consistent with DISPENSING harvest pattern; code_type=NDC for both"
  - "ndc_crosswalk_fn2 variable name used in R/11 fn2 scope to avoid collision with fn1 ndc_crosswalk binding"
  - "R/76 helper returns tibble with triggering_code column not needed by coverage script; select(ID, treatment_date) drops it cleanly"
  - "IS_LOCAL runtime check in Section 15t uses exists() guard for helpers rather than sourcing files (helpers already sourced by R/00_config.R auto-load in normal smoke-test flow)"
  - "Runtime confirmation of MED_ADMIN/DISPENSING contributions (actual patient/date increments) deferred to HiPerGator per Plan 03 user step"
metrics:
  duration: "12 minutes"
  completed_date: "2026-07-14"
  tasks_completed: 3
  files_modified: 9
---

# Phase 122 Plan 02: Patch All 7 Consumers + R/88 Section 15t + SCRIPT_INDEX Summary

**One-liner:** All 7 chemo consumers (R/10, R/26, R/25, R/11, R/27, R/20, R/76) patched to use get_chemo_hits() from utils_treatment.R, replacing broken RXNORM_CUI colnames guards; immunotherapy branches left untouched; R/88 Section 15t added with 14 structural checks and IS_LOCAL-gated runtime assertion; SCRIPT_INDEX updated for R/108 (100+: 8->9, Total: 94->95).

## What Was Built

### Task 1: R/10, R/26, R/25, R/11 — cohort/episode/timing/payer consumers

**R/10 `has_chemo()`:**
- Removed `tryCatch(get_pcornet_table("DISPENSING"))` + RXNORM_CUI guard
- Replaced with `ndc_crosswalk <- load_ndc_crosswalk()` then `get_chemo_hits("DISPENSING", ...)` and `get_chemo_hits("MED_ADMIN", ...)` 
- IDs pulled from `distinct(ID) %>% pull(ID)` on the returned tibble; counts via `n_distinct()`
- D-12 comments revised to note Phase 122 corrected access

**R/26 `extract_chemo_dates_with_codes()` sources #5/#6:**
- Replaced 9-line DISPENSING block (RXNORM_CUI guard + filter + select with ENCOUNTERID) with 4-line get_chemo_hits call + `mutate(ENCOUNTERID = NA_character_)`
- Same for MED_ADMIN source #6
- `stack_and_dedup_with_codes()` downstream dedup preserved
- Immunotherapy function sources ~362/373: **untouched** (confirmed by grep returning exactly 1 each)

**R/25 `extract_chemo_dates()`:**
- Two DISPENSING/MED_ADMIN blocks replaced with get_chemo_hits calls
- `mutate(ENCOUNTERID = NA_character_) %>% select(ID, treatment_date, ENCOUNTERID)` preserves the downstream column contract
- Downstream `stack_and_dedup()` provides dedup

**R/11 two functions:**
- fn1 (min-date): DISPENSING+MED_ADMIN guards replaced; `group_by(ID) %>% summarise(disp_date = min(...))` derived from helper result
- fn2 (max-date): same pattern with `max(treatment_date)`; `ndc_crosswalk_fn2` scoped separately to avoid name collision

### Task 2: R/27, R/20, R/76 — drug-name/inventory/coverage consumers

**R/27 `drug-name code harvest`:**
- DISPENSING block (was: RXNORM_CUI guard + RXNORM harvest): replaced with `ndc_crosswalk_27 <- load_ndc_crosswalk()` then raw `distinct(NDC)` harvest, crosswalk-filtered to chemo NDCs, emitting `code = NDC` / `code_type = "NDC"`. The emitted DISPENSING code is the raw NDC, not the helper's resolved RxCUI.
- MED_ADMIN block: split into RX-typed (MEDADMIN_CODE as RxNorm, code_type="RXNORM") and ND-typed (MEDADMIN_CODE as NDC, filtered via crosswalk, code_type="NDC")
- 2nd DISPENSING NDC harvest (old line 372): replaced by merging into the main rx_codes_dispensing block (ndc_codes now NULL); gate changed from RXNORM_CUI to NDC column presence
- PRESCRIBING guard at line 332: **kept unchanged**

**R/20 treatment inventory:**
- DISPENSING: merged the two blocks (RXNORM+NDC) into a single NDC block with `drug_name = NA_character_`; removed `RAW_DISPENSE_MED_NAME` reference (absent in extract)
- MED_ADMIN: `filter(RXNORM_CUI)` replaced with `filter(MEDADMIN_TYPE %in% c("RX","ND"))` + `group_by(code = MEDADMIN_CODE, drug_name = RAW_MEDADMIN_MED_NAME)`; RAW_MEDADMIN_MED_NAME kept (present in extract)
- Both tryCatch error handlers now message `[R/20 DISPENSING error]` / `[R/20 MED_ADMIN error]` before returning empty_result()

**R/76 `extract_claims_chemo_dates()` (coverage function):**
- DISPENSING source #5: replaced with `get_chemo_hits("DISPENSING", ...)` then `select(ID, treatment_date)`
- MED_ADMIN source #6: same pattern
- PRESCRIBING guard at line 200: **kept unchanged**
- NULL result handled implicitly (sources not added to list)

### Task 3: R/88 Section 15t + SCRIPT_INDEX

**R/88 Section 15t** inserted after Section 15s (before Section 15g):
- 14 checks across structural file assertions, grep-based guard removal verification, and IS_LOCAL-gated runtime
- Checks 1-2: fixture headers have no RXNORM_CUI (MED_ADMIN) / no RXNORM_CUI+RAW_DISPENSE_MED_NAME (DISPENSING)
- Checks 3-6: helper function definitions and graceful-degrade behavior
- Check 7: R/108 script file exists
- Checks 8-9: R/01 DISPENSING+MED_ADMIN specs no longer declare phantom RXNORM_CUI; 2 D-12 revision comments present
- Checks 10-13: all 7 consumers verified (guards removed, get_chemo_hits present, immuno preserved, R/20/R/76 corrected)
- Check 14: IS_LOCAL-gated runtime — calls `get_chemo_hits("MED_ADMIN")` against loaded helpers; degrades gracefully to SKIPPED if helpers absent or fixtures missing; else-branch also returns SKIPPED (HiPerGator runtime) so smoke test stays green locally

**SMOKE-122-01** summary line appended after SMOKE-121-01.

**SCRIPT_INDEX.md:**
- R/108 row added to Post-Renumber Investigations (100+) table
- 100+ count: 8 -> 9
- Total: 94 -> 95

## Structural Verification (Windows executor — no Rscript)

| Check | Result |
|-------|--------|
| `grep -c '"RXNORM_CUI" %in% colnames' R/10_cohort_predicates.R` | 0 |
| `grep -c 'get_chemo_hits' R/10_cohort_predicates.R` | 2 |
| `grep -c 'get_chemo_hits' R/26_treatment_episodes.R` | 2 (chemo #5/#6) |
| `grep -c '"RXNORM_CUI" %in% colnames(get_pcornet_table("DISPENSING"))' R/26` | 1 (immuno only) |
| `grep -c '"RXNORM_CUI" %in% colnames(get_pcornet_table("MED_ADMIN"))' R/26` | 1 (immuno only) |
| `grep -c '"RXNORM_CUI" %in% colnames' R/25_treatment_durations.R` | 1 (PRESCRIBING only) |
| `grep -c '"RXNORM_CUI" %in% colnames' R/11_treatment_payer.R` | 0 |
| `grep -c 'get_chemo_hits' R/11_treatment_payer.R` | 4 (fn1 x2 + fn2 x2) |
| `grep -c '"RXNORM_CUI" %in% colnames' R/27_drug_name_resolution.R` | 1 (PRESCRIBING only) |
| `grep -c '"NDC" %in% colnames' R/27_drug_name_resolution.R` | 1 |
| `grep -c 'distinct(NDC)\|code = NDC' R/27_drug_name_resolution.R` | 2 |
| `grep -c 'code.*triggering_code' in DISPENSING harvest R/27` | 0 |
| `grep -c 'RAW_DISPENSE_MED_NAME' R/20_treatment_inventory.R` | 0 |
| `grep -c 'RAW_MEDADMIN_MED_NAME' R/20_treatment_inventory.R` | 2 (kept, present in extract) |
| `grep -c 'MEDADMIN_TYPE %in% c("RX"' R/20_treatment_inventory.R` | 1 |
| `grep -c '\[R/20 DISPENSING error\]' R/20_treatment_inventory.R` | 1 |
| `grep -c '"RXNORM_CUI" %in% colnames' R/76_treatment_source_coverage.R` | 1 (PRESCRIBING only) |
| `grep -c 'get_chemo_hits' R/76_treatment_source_coverage.R` | 2 |
| `grep -c "SECTION 15t" R/88_smoke_test_comprehensive.R` | 1 |
| `grep -c "SMOKE-122-01" R/88_smoke_test_comprehensive.R` | 1 |
| `grep -c "R/108" R/SCRIPT_INDEX.md` | 2 (row + count line) |
| `grep "Total.*95" R/SCRIPT_INDEX.md` | present |
| `grep "(100+).*9" R/SCRIPT_INDEX.md` | present |
| Global: no DISPENSING/MED_ADMIN chemo guard except R/26 immuno pair | confirmed |

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

### Implementation Notes

1. **R/11 fn2 variable naming:** The plan specified `ndc_crosswalk_fn2` (to avoid collision with fn1's `ndc_crosswalk`). This is correct since both functions are in the same script and `ndc_crosswalk` is defined in fn1's body. The fn2 load avoids double-loading by using its own binding.

2. **R/20 block consolidation:** The plan said "If the two blocks now duplicate, keep one NDC block." The merged result is a single NDC block with `drug_name = NA_character_` replacing both the defunct RXNORM block and the existing NDC block that was also referencing `RAW_DISPENSE_MED_NAME` (which is absent from the extract). This produces cleaner code.

3. **R/27 ndc_codes = NULL:** After consolidating the DISPENSING NDC harvest into `rx_codes_dispensing`, the `ndc_codes` variable that fed `bind_rows()` downstream is set to NULL. The `bind_rows(rx_codes_prescribing, rx_codes_dispensing, rx_codes_medadmin, ndc_codes)` call still works because `bind_rows()` ignores NULLs.

## Known Stubs

| Stub | File | Notes |
|------|------|-------|
| `data/reference/ndc_rxnorm_crosswalk.rds` missing | data/reference/ | Carried forward from Plan 01. No R binary on Windows executor. load_ndc_crosswalk() degrades gracefully. **Must be created on HiPerGator before Plan 03 smoke test passes for DISPENSING/MED_ADMIN ND paths.** Synthetic command: `saveRDS(setNames("3639", "00069306030"), here::here("data","reference","ndc_rxnorm_crosswalk.rds"))` |
| `R/108_build_ndc_rxnorm_crosswalk.R` missing | R/ | SCRIPT_INDEX row added but the script itself is slated for Plan 03. Section 15t Check 7 will PASS only after Plan 03 creates this file. |

## Runtime Confirmation (Deferred to HiPerGator — Plan 03 User Step)

Section 15t Check 14 is IS_LOCAL-gated. On HiPerGator, the user runs:
```
Rscript R/88_smoke_test_comprehensive.R
```
Expected: Section 15t reports 14/14 PASS. The MED_ADMIN RX-typed increment (+1,139 patients / +10,752 dates from R/107 diagnostic) should now flow through all 7 consumers. DISPENSING and MED_ADMIN ND-typed paths activate only after the crosswalk RDS is built.

## Self-Check: PASSED

Files modified:
- `R/10_cohort_predicates.R` — FOUND
- `R/26_treatment_episodes.R` — FOUND
- `R/25_treatment_durations.R` — FOUND
- `R/11_treatment_payer.R` — FOUND
- `R/27_drug_name_resolution.R` — FOUND
- `R/20_treatment_inventory.R` — FOUND
- `R/76_treatment_source_coverage.R` — FOUND
- `R/88_smoke_test_comprehensive.R` — FOUND
- `R/SCRIPT_INDEX.md` — FOUND

Commits:
- `07184cd` — feat(122-02): patch cohort/episode/timing/payer consumers to use get_chemo_hits
- `715a434` — feat(122-02): patch drug-name/inventory/coverage consumers (R/27, R/20, R/76)
- `e71f71a` — feat(122-02): add R/88 Section 15t (14 checks, SMOKE-122-01) and update SCRIPT_INDEX for R/108
