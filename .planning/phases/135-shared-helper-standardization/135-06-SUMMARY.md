---
phase: 135-shared-helper-standardization
plan: "06"
subsystem: api-retry-and-config-safety
tags: [httr2, retry, transient-errors, config-rewrite, pattern-d, pattern-f]
dependency_graph:
  requires: []
  provides: [PATTERN-D, PATTERN-F]
  affects:
    - R/21_investigate_unmatched.R
    - R/22_investigate_unmatched_ndc.R
    - R/50_all_codes_resolved.R
    - R/98_radiation_cpt_audit.R
    - R/27_drug_name_resolution.R
    - R/105_normalize_supportive_care_meaning.R
    - R/108_build_ndc_rxnorm_crosswalk.R
tech_stack:
  added: [httr2 (replaces httr in R/21)]
  patterns:
    - httr2 req_retry with is_transient predicate covering 429/500/502/503/504
    - PATTERN-F verify-before-write (tempfile parse check before writeLines to real path)
    - Transient vs permanent cache distinction (error: transient_* prefix)
key_files:
  created: []
  modified:
    - R/21_investigate_unmatched.R
    - R/22_investigate_unmatched_ndc.R
    - R/50_all_codes_resolved.R
    - R/98_radiation_cpt_audit.R
    - R/27_drug_name_resolution.R
    - R/105_normalize_supportive_care_meaning.R
    - R/108_build_ndc_rxnorm_crosswalk.R
decisions:
  - "R/21 httr::GET replaced with httr2 pipeline; req_error(is_error=~FALSE) lets code branch on status instead of req_perform throwing"
  - "Exhausted transient statuses cached as error: transient_http_{status} (not permanent miss) so next run retries them"
  - "PATTERN-F uses if/else form (not early-return) so it is safe in both function-body and top-level-script scope (R/50 is top-level)"
  - "R/98 already had temp-file validate pattern; renamed tmp->tmp_verify, added PATTERN-F marker, converted error() to warning() for consistency"
  - "httr2 must be installed interactively (install.packages + renv::snapshot) before any SLURM use of R/21 - this is a human action"
metrics:
  duration: "~25 minutes"
  completed: "2026-07-25"
  tasks_completed: 2
  files_modified: 7
---

# Phase 135 Plan 06: API Transient Retry and Config Rewrite Hardening Summary

Fix PATTERN-D (transient-error retry for API callers) and PATTERN-F (verify-before-write for config rewriters) across seven R scripts.

## Objective

Two recurring bug patterns were found across the API-calling scripts:

- **PATTERN-D:** R/21 used `httr::GET` with no retry — any 429 or 5xx was cached as a permanent error, poisoning the crosswalk. R/27/R/105/R/108 already retried 429/503/504 but treated 500/502 as permanent.
- **PATTERN-F:** R/21, R/22, R/50, R/98 all wrote to `R/00_config.R` unconditionally with `writeLines()`, then validated afterward. A regex failure during line construction would write a corrupted file before the parse check caught it.

## Tasks Completed

### Task 1: Switch R/21 API caller to httr2 with transient-error retry (PATTERN-D)

**Commit:** c134ee7

Replaced the `httr::GET(url, timeout(10))` block in `lookup_hcpcs_batch()` with an httr2 pipeline:

- Transient statuses that survive all retries are cached as `error: transient_http_{status}` (not permanent miss)
- Timeouts from the error handler use `error: transient_timeout`
- Genuine permanent errors (404, etc.) use `error: HTTP {status}`
- `req_error(is_error=~FALSE)` prevents httr2 from throwing on 4xx/5xx, allowing status-based branching
- `library(httr)` replaced with `library(httr2)`
- R/21 has no cache anti_join step so sub-step 4 filter was not needed

Also added PATTERN-F verify-before-write to `update_config_treatment_codes()` in the same file.

**renv setup note (HUMAN ACTION REQUIRED):** `httr2` must be installed interactively in an RStudio session on HiPerGator before any SLURM batch use:
```r
install.packages("httr2")
renv::snapshot()
```

### Task 2: Harden config rewrite (PATTERN-F) and extend transient set (PATTERN-D)

**Commit:** 626db57

**PATTERN-F (verify-before-write) applied to 4 scripts:**

For R/22 and R/50: added tempfile parse check before the unconditional `writeLines()`. Parse failure produces `warning()` and preserves backup without writing to the real config path.

For R/98: the existing code already had a temp-file validate pattern (write to `tmp`, parse, only write to real path on success). Renamed `tmp` to `tmp_verify`, added `# PATTERN-F` marker, and converted `message()` failure logging to `warning()` for consistency.

**PATTERN-D extension (500, 502 added to transient set) in 3 scripts:**

- R/27: three `req_retry` calls updated from `c(429, 503, 504)` to `c(429L, 500L, 502L, 503L, 504L)`
- R/105: two `req_retry` calls updated identically
- R/108: one `req_retry` call updated identically

## Verification

All seven files parsed without error. All structural checks passed: `req_retry` in R/21, `transient_timeout` in R/21, no `GET(url,` in R/21, `tmp_verify|PATTERN-F` in all four rewriters, `500` in `is_transient` for R/27/R/105/R/108.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- Task 1 commit: c134ee7 (R/21 httr2 + PATTERN-F)
- Task 2 commit: 626db57 (R/22, R/50, R/98 PATTERN-F; R/27, R/105, R/108 PATTERN-D extension)
- All 7 files: parse OK confirmed via Rscript
