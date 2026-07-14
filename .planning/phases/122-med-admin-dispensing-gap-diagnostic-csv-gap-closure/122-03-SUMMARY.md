---
phase: 122-med-admin-dispensing-gap-diagnostic-csv-gap-closure
plan: "03"
subsystem: treatment-detection
tags: [ndc-crosswalk, rxnav, crosswalk-builder, hipergator-only, checkpoint]
dependency_graph:
  requires:
    - 122-01 (normalize_ndc / load_ndc_crosswalk / get_chemo_hits in utils_treatment.R)
    - 122-02 (all 7 consumers patched; R/88 Section 15t)
  provides:
    - R/108_build_ndc_rxnorm_crosswalk.R (committed, structurally verified)
    - data/reference/ndc_rxnorm_crosswalk.rds (PENDING: HiPerGator build step by user)
  affects:
    - All get_chemo_hits() NDC paths (DISPENSING + MED_ADMIN ND) activate once RDS present
    - R/88 Section 15t Check 7 (R/108 file-exists check) now PASSES
tech_stack:
  added: []
  patterns:
    - httr2 req_retry(max_tries=3, is_transient=~resp_status(.x) %in% c(429,503,504))
    - purrr::map_chr batch lookup with progress counter every 100 calls
    - stats::setNames named-vector crosswalk (NDC->RxCUI); misses dropped before saveRDS
    - self-bootstrap DuckDB pattern (R/107 precedent)
key_files:
  created:
    - R/108_build_ndc_rxnorm_crosswalk.R
  modified: []
decisions:
  - "R/108 SCRIPT_INDEX-only (not R/39), mirroring R/107 — one-time data-prep, not repeatable investigation"
  - "saveRDS writes matched-only named vector; misses excluded from RDS but captured in audit CSV"
  - "Batch loop (for + map_chr) with explicit progress message every 100 calls addresses RESEARCH Open Question 2 (distinct-NDC count + progress counter before and during API calls)"
  - "data/reference/ndc_rxnorm_crosswalk.rds path matches load_ndc_crosswalk() here() path exactly — key alignment confirmed"
metrics:
  duration: "3 minutes"
  completed_date: "2026-07-14"
  tasks_completed: 1
  tasks_at_checkpoint: 1
  files_modified: 1
---

# Phase 122 Plan 03: NDC->RxNorm Crosswalk Builder (R/108) Summary

**One-liner:** R/108 crosswalk builder created — harvests+normalises NDCs from DISPENSING+MED_ADMIN ND, resolves via RxNav rxcui.json?idtype=NDC with httr2 retry, writes named-vector RDS + audit CSV; PENDING user HiPerGator run to populate data/reference/ndc_rxnorm_crosswalk.rds.

## Status

| Task | Name | Status | Commit |
|------|------|--------|--------|
| 1 | Create R/108_build_ndc_rxnorm_crosswalk.R | COMPLETE | 5c34392 |
| 2 | HiPerGator runtime confirmation | CHECKPOINT (awaiting user) | — |

## What Was Built

### Task 1: R/108_build_ndc_rxnorm_crosswalk.R (272 lines)

**Header block:**
- Purpose (one-time NDC->RxNorm build, HiPerGator-only, offline-after-build)
- Inputs: DISPENSING.NDC + MED_ADMIN MEDADMIN_TYPE=="ND".MEDADMIN_CODE
- Outputs: `data/reference/ndc_rxnorm_crosswalk.rds` + `output/ndc_rxnorm_crosswalk_audit.csv`
- Dependencies: httr2, purrr, dplyr, stringr, glue, here
- Requirements: D-02, D-03
- REGISTRATION NOTE: SCRIPT_INDEX only, not R/39

**Section 1 — Setup:** Loads httr2, purrr, dplyr, stringr, glue, here. Sources R/00_config.R, R/utils/utils_duckdb.R, R/utils/utils_dates.R. Defensively sources utils_treatment.R if normalize_ndc not yet loaded.

**Section 2 — Self-bootstrap DuckDB:** `USE_DUCKDB <- TRUE; if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()` — mirrors R/107/R/27 pattern.

**Section 3 — Harvest distinct NDCs:**
- DISPENSING: filter(!is.na(NDC), NDC != "") -> distinct(NDC) -> pull(NDC)
- MED_ADMIN: filter(MEDADMIN_TYPE == "ND", !is.na(MEDADMIN_CODE), MEDADMIN_CODE != "") -> distinct(MEDADMIN_CODE) -> pull(MEDADMIN_CODE)
- Union + normalize_ndc() + unique(); reports distinct-NDC count before any API calls (RESEARCH Open Question 2)

**Section 4 — lookup_ndc_to_rxcui():**
- `httr2::request(url) |> req_timeout(10) |> req_retry(max_tries=3, is_transient=~resp_status(.x) %in% c(429L,503L,504L)) |> req_perform()`
- `resp_body_json(resp)$idGroup$rxnormId[[1]]` or NA_character_
- tryCatch -> NA_character_ on any error; Sys.sleep(sleep_sec) after every call

**Section 5 — Batch lookup:** for-loop over ndc_vec, progress message every 100 calls with matched-so-far count.

**Section 6 — Write outputs:**
- `crosswalk <- stats::setNames(rxcui_vec, ndc_vec); crosswalk[!is.na(crosswalk)]` (misses dropped)
- `saveRDS(crosswalk, here::here("data","reference","ndc_rxnorm_crosswalk.rds"))`
- `write.csv(audit_df, ...)` with columns NDC, rxcui, lookup_status (matched/miss)

**Section 7 — Final summary:** n distinct NDCs, n matched, n misses, both output paths, next-steps instructions.

## Structural Verification (Windows executor — no Rscript)

| Check | Result |
|-------|--------|
| Line count >= 80 | 272 lines PASS |
| `grep -c "idtype=NDC"` | 3 (URL, comment, function doc) PASS |
| `grep -c "saveRDS"` and references ndc_rxnorm_crosswalk | 1; saveRDS(crosswalk, rds_path) where rds_path = here("data","reference","ndc_rxnorm_crosswalk.rds") PASS |
| `grep -c 'MEDADMIN_TYPE == "ND"'` | 3 (harvest filter + 2 inline comments) PASS |
| `grep -c "normalize_ndc"` | 3 (call + defensive load comment) PASS |
| `grep -c "req_retry"` | 1 PASS |
| `grep -cE "data.table\|\bDT\["` | 0 (tidyverse only) PASS |
| Brace balance | 0 (balanced) PASS |
| Paren balance | 0 (balanced) PASS |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

| Stub | File | Notes |
|------|------|-------|
| `data/reference/ndc_rxnorm_crosswalk.rds` missing | data/reference/ | Intentional — requires HiPerGator run (network + real production NDC values). load_ndc_crosswalk() degrades gracefully to character(0) with message. Task 2 checkpoint awaits user confirmation of build. |

## Runtime Confirmation (Checkpoint: Task 2)

Task 2 is a `checkpoint:human-verify` gate. The user must perform three HiPerGator steps before this plan is marked complete:

1. `Rscript R/108_build_ndc_rxnorm_crosswalk.R` — build + commit ndc_rxnorm_crosswalk.rds
2. `Rscript R/88_smoke_test_comprehensive.R` — confirm Section 15t 14/14 PASS
3. `Rscript R/107_med_admin_dispensing_gap_diagnostic.R` — confirm DISPENSING + MED_ADMIN ND contributions are non-zero

See CHECKPOINT REACHED block in executor output for exact steps.

## Self-Check: PASSED

Files created:
- `R/108_build_ndc_rxnorm_crosswalk.R` — FOUND (272 lines)

Commits:
- `5c34392` — FOUND (feat(122-03): create R/108 NDC->RxNorm crosswalk builder)
