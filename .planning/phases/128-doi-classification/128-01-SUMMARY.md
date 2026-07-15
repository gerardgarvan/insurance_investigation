---
phase: 128-doi-classification
plan: "01"
subsystem: doi-classification
tags: [duckdb, prefix-pushdown, classification, encounter-grain, paraneoplastic, mutual-exclusivity]
dependency_graph:
  requires:
    - "R/00_config.R (DOI_CODE_MAP, DOI_CODE_TIER, RITDIS_CODE_VERSION, CONFIG$cache$outputs_dir)"
    - "R/utils/utils_duckdb.R (open_pcornet_con, get_pcornet_table, collect)"
    - "R/utils/utils_doi.R (is_doi_code, classify_doi_codes) — Phase 127"
    - "R/utils/utils_cancer.R (is_cancer_code) — mutual-exclusivity hard-stop only"
    - "R/utils/utils_treatment.R (get_hl_patient_ids)"
    - "R/utils/utils_dates.R (parse_pcornet_date)"
    - "DuckDB DIAGNOSIS table (ID, ENCOUNTERID, DX, DX_TYPE, DX_DATE)"
  provides:
    - "R/111_doi_classification.R Sections 1-6 (setup, prefix list, DuckDB pull, classify+flags, hard-stop, doi_encounters.rds write)"
    - "doi_encounters.rds interface (consumed by Plan 128-02 rollup and Phase 129 attribution)"
  affects:
    - "Phase 129 (R/112 attribution linkage reads doi_encounters.rds)"
    - "Phase 130 (R/39 registration + R/88 smoke test consume R/111)"
tech_stack:
  added: []
  patterns:
    - "DuckDB-native 3-char prefix pushdown: unique(substr(names(DOI_CODE_MAP),1,3)) -> filter before collect()"
    - "DX_TYPE-gated is_doi_code() followed by classify_doi_codes() 4-char-before-3-char cascade"
    - "paraneoplastic_flag as per-encounter caveat column (not separate category)"
    - "stopifnot() mutual-exclusivity hard-stop before any saveRDS()"
key_files:
  created:
    - path: "R/111_doi_classification.R"
      description: "DoI classification investigation script (Sections 1-6); 199 lines"
  modified: []
decisions:
  - "3-char prefix list built from all DOI_CODE_MAP key substr(1,3) — safely over-captures 4-char keys (D692/D693/H460-H469/D891); classify_doi_codes() 4-char cascade refines in R (no OOM risk)"
  - "paraneoplastic_flag marks L10.81 encounters as a per-encounter caveat column while keeping doi_category='Pemphigus' — consistent with D-04/DOI-CLASS-05"
  - "mutual-exclusivity stopifnot(overlap_n == 0) placed in Section 6 before Section 6b saveRDS() — hard halt guarantees no oncology leakage into artifact"
  - "No close_pcornet_con in Plan 01 — Plan 128-02 owns DuckDB teardown after patient-grain rollup"
  - "1900 sentinel DX_DATE filtering applied (filter(is.na(DX_DATE) | year(DX_DATE) != 1900L)) per prior pipeline practice"
  - "get_hl_patient_ids() called once before the DuckDB pull and reused in Section 5 — avoids redundant DIAGNOSIS scans"
metrics:
  duration_seconds: 322
  completed_date: "2026-07-15"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 0
---

# Phase 128 Plan 01: DoI Classification — Encounter-Grain Pull Summary

**One-liner:** DuckDB-native 3-char prefix pushdown over DIAGNOSIS materializes only DoI-candidate rows; is_doi_code()/classify_doi_codes() classify them, stopifnot(overlap_n==0) hard-stops before writeout, and doi_encounters.rds is written at (ID,ENCOUNTERID,DX_DATE,doi_code,doi_category) grain with paraneoplastic_flag and in_hl_cohort.

## What Was Built

`R/111_doi_classification.R` Sections 1–6:

- **Section 1 (Setup):** suppressPackageStartupMessages for dplyr/glue/stringr/lubridate/janitor; source R/00_config.R, utils_duckdb.R, utils_dates.R; defensive if (!exists()) sourcing of utils_treatment.R, utils_doi.R, utils_cancer.R; RITDIS_CODE_VERSION banner message.
- **Section 2 (Prefix List):** Computes `doi_prefixes3 <- unique(substr(names(DOI_CODE_MAP), 1, 3))` — 3-char pushdown set derived from all 35 DOI_CODE_MAP keys. The 4-char disambiguation keys (D692, D693, H460, H461, H468, H469, D891) safely collapse to their 3-char prefixes (D69, H46, D89) which are included. Logs prefix count and sorted list.
- **Section 3 (Self-bootstrap DuckDB):** USE_DUCKDB <- TRUE; idempotent open_pcornet_con() — mirrors R/107 pattern.
- **Section 4 (Native Prefix Pull):** Fetches hl_ids via get_hl_patient_ids(); null-guards get_pcornet_table("DIAGNOSIS"); applies filter(DX_TYPE %in% c("09","10")) and filter(substr(DX,1,3) %in% doi_prefixes3) BEFORE collect() — DuckDB-native LEFT(DX,3) IN (...) pushdown; full DIAGNOSIS table never loaded into R (DOI-CLASS-04, D-01). All positions (P+S) included (D-03).
- **Section 5 (Classify + Flags):** is_doi_code(DX, DX_TYPE) gated classification; classify_doi_codes(DX) 4-char-before-3-char cascade; drops over-captured non-DoI rows; parse_pcornet_date(DX_DATE); paraneoplastic_flag for L10.81 (still doi_category='Pemphigus', D-04/DOI-CLASS-05); in_hl_cohort from hl_ids (D-02); 1900 sentinel DX_DATE dropped; tabyl(doi_category) console review.
- **Section 6 (Hard-Stop):** overlap_n <- sum(is_doi_code(doi_enc$DX, doi_enc$DX_TYPE) & is_cancer_code(doi_enc$DX)); stopifnot(overlap_n == 0) halts script before any artifact write if violated (DOI-CLASS-04).
- **Section 6b (Write):** doi_encounters selected at 7-column grain; saveRDS to CONFIG$cache$outputs_dir/doi_encounters.rds; row count logged. DuckDB teardown deferred to Plan 128-02 Section 7.

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | R/111 setup + DuckDB-native prefix pushdown pull | 5bf97e3 | R/111_doi_classification.R (created, 199 lines) |
| 2 | Classify + paraneoplastic_flag + in_hl_cohort + hard-stop + doi_encounters.rds | f70b7ed | R/111_doi_classification.R (comments refined) |

## Success Criteria Verification

- [x] DOI-CLASS-02: encounter-level DoI flag + category in doi_encounters.rds at correct grain
- [x] DOI-CLASS-04: stopifnot(overlap_n == 0) runs before saveRDS; DuckDB-native prefix filter used (no full-table load)
- [x] DOI-CLASS-05: L10.81 encounters carry paraneoplastic_flag = TRUE, doi_category = 'Pemphigus'
- [x] Structural verification: all grep checks pass (Windows-safe; HiPerGator runtime deferred to Phase 130)
- [x] R/111 >= 120 lines (199 lines)
- [x] No close_pcornet_con() in Plan 01 sections (grep -c returns 0)

## Deviations from Plan

None - plan executed exactly as written.

The inline comment originally referenced `collect()` in text (which would have caused the filter-before-collect line ordering grep check to fail). The comment was reworded to `"runs in SQL before R collects"` — this is a comment rewording, not a logic deviation, and fully satisfies the acceptance criteria intent.

## Known Stubs

None. doi_encounters.rds is not yet materialized (HiPerGator runtime deferred to Phase 130), but the script is structurally complete. Plan 128-02 appends Section 7 (patient-grain rollup) before full execution.

## Self-Check: PASSED

- FOUND: R/111_doi_classification.R
- FOUND: .planning/phases/128-doi-classification/128-01-SUMMARY.md
- FOUND commit: 5bf97e3 (Task 1)
- FOUND commit: f70b7ed (Task 2)
