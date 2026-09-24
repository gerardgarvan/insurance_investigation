---
phase: 158-surveillance-modality-frequency
plan: "03"
subsystem: surveillance-investigation-script
tags: [DuckDB, workbook, suppression, HL-denominator, surveillance]
dependency_graph:
  requires:
    - 158-01 (load_surveillance_codeset, surv_code_where, normalize_surv_code, surv_components, get_hl_any_dx_ids)
    - 158-02 (match_coded_events, build_component_events, build_code_presence, compute_followup, classify_event_window, compute_modality_stats, build_patient_modality, suppress_small, suppress_table)
  provides:
    - R/147_surveillance_modality_frequency.R
  affects:
    - CONFIG$cache$outputs_dir (workbook + .rds outputs)
tech_stack:
  added:
    - openxlsx (workbook writing with styled headers)
  patterns:
    - DuckDB semi_join on temp table for HL ID pushdown (D-29)
    - surv_code_where() SQL WHERE builder before collect() (D-14)
    - Two-workbook pattern: INTERNAL (unsuppressed) + release (suppress_table) (D-27)
key_files:
  created:
    - R/147_surveillance_modality_frequency.R
  modified: []
decisions:
  - "Script number 147 (next free after 146_stage_sdi_reference.R)"
  - "EXTRACT_CUTOFF from EXTRACT_DATE constant in R/00_config.R (line 84); no separate CONFIG key exists"
  - "No UF color constants in 00_config.R; hex literals #0021A5 / #FA4616 used directly in write_workbook()"
  - "Zero inline counting logic: all matching, presence, follow-up, window, frequency, suppression delegated to utils_surveillance.R"
metrics:
  duration_minutes: 10
  tasks_completed: 1
  tasks_total: 1
  files_created: 1
  files_modified: 0
  completed_date: "2026-09-24"
---

# Phase 158 Plan 03: Investigation Script (DuckDB Wiring)

**One-liner:** Investigation script 147 wires DuckDB pulls via surv_code_where() pushdown and semi_join on a temp HL-ID table to the unit-tested utils_surveillance.R counting functions, writing both INTERNAL and release workbooks plus a patient-level .rds.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Write investigation script | 1bdfd41 | R/147_surveillance_modality_frequency.R |

## Environment-Specific Adjustments (recorded per plan instructions)

1. **EXTRACT_CUTOFF:** `R/00_config.R` defines `EXTRACT_DATE <- "2025-09-15"` at line 84. Script uses `as.Date(EXTRACT_DATE)` instead of the literal `"2025-09-15"`.
2. **UF color constants:** `R/00_config.R` contains no UF_BLUE / UF_ORANGE constants. Hex literals `#0021A5` and `#FA4616` are used directly in `write_workbook()`.
3. **DEATH / DEATH_DATE column names:** No evidence of alternate names in the codebase; script uses `DEATH` / `DEATH_DATE` as specified.
4. **Patient key:** Existing codebase uses `ID` throughout; no adjustment needed.

## Key Decisions

1. **Script number 147** — confirmed by `ls R/ | grep -E '^[0-9]+_' | sort -n | tail -5`; next free after `146_stage_sdi_reference.R`.
2. **EXTRACT_DATE constant used** — avoids duplicating the cutoff date; single source of truth in R/00_config.R.
3. **No UF color constants** — hex literals embedded directly in `createStyle()` calls; matches the plan's fallback instruction.

## Deviations from Plan

None — plan executed exactly as written. All environment-specific substitutions are listed above and are the expected adjustments the plan explicitly requested.

## Verification (Structural Fallback — Rscript unavailable on Windows dev host)

Per plan's `<verification>` section, since `Rscript` is not available in this Windows environment, the structural fallback was applied:

- **All 12 keyword checks passed:**
  - `load_surveillance_codeset` (3), `get_hl_any_dx_ids` (2), `surv_code_where` (4), `remote_con` (1), `semi_join` (3), `parse_pcornet_date` (2), `build_code_presence` (1), `compute_modality_stats` (2), `classify_event_window` (1), `suppress_table` (1), `INTERNAL` (3), `saveRDS` (1)
- **Forbidden pattern `as.Date(PX_DATE` — ABSENT (correct)**
- **Brace balance: 29 open / 29 close = 0**

**End-to-end run deferred to 158-04 Task 2** on HiPerGator.

## Known Stubs

None — script requires live DuckDB connection; no rendering stubs or hardcoded empty values.

## Self-Check: PASSED

- [x] R/147_surveillance_modality_frequency.R exists (364 lines)
- [x] Commit 1bdfd41 present in git log
- [x] All 12 structural keyword checks passed
- [x] No forbidden `as.Date(PX_DATE` pattern
- [x] Brace balance 0
