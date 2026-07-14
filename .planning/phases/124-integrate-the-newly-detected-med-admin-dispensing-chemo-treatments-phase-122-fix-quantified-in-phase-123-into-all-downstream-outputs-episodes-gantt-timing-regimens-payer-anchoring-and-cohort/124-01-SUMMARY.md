---
phase: 124-integrate-med-admin-dispensing-chemo-downstream
plan: 01
subsystem: treatment-episodes
tags: [source-provenance, drug-names, chemo-detection, med-admin, dispensing, canonicalization]
dependency_graph:
  requires: [Phase 122 (get_chemo_hits fix), Phase 123 (impact audit)]
  provides: [source_hints episode column, raw-name fallback tier]
  affects: [R/28 (Gantt Source Table), treatment_episodes.rds schema, drug_names resolution]
tech_stack:
  added: []
  patterns: [<<- global assignment for script-scope side-effect, purrr::imap source labeling, dplyr::any_of() column guard, 3-tier coalesce drug-name resolution]
key_files:
  created: []
  modified:
    - R/utils/utils_treatment.R
    - R/26_treatment_episodes.R
decisions:
  - "<<- used inside extract_chemo_dates_with_codes() to expose raw_name_lookup to script scope — avoids restructuring function signature or moving logic out of the extraction function"
  - "source_hints parallel-column approach (same sort order as triggering_codes) chosen over embedding hint inside triggering_code string — preserves downstream code compatibility"
  - "MED_ADMIN priority > DISPENSING > PROCEDURES > PRESCRIBING > DIAGNOSIS — newest/most-auditable sources win when same code seen in multiple sources"
  - "raw_med_name_canonical always passes through canonicalize_drug_name(toupper(trimws())) — raw string never reaches drug_names"
  - "DISPENSING raw_med_name = NA_character_ (confirmed no RAW_DISPENSE_MED_NAME in this extract)"
metrics:
  duration_minutes: 5
  completed_date: "2026-07-14"
  tasks_completed: 3
  files_modified: 2
---

# Phase 124 Plan 01: Source Provenance + Raw-Name Fallback Plumbing Summary

Source-provenance plumbing and raw drug-name fallback tier that the Phase 122 chemo fix needs in order to label newly-surfaced DISPENSING and MED_ADMIN records correctly and resolve their drug names canonically.

## What Was Built

### Task 1: `get_chemo_hits()` return_raw_name parameter (fccb0f4)

Added `return_raw_name = FALSE` to `get_chemo_hits()` in `R/utils/utils_treatment.R`.

- PRESCRIBING branch: `raw_med_name = NA_character_` when `return_raw_name = TRUE` (no free-text field)
- DISPENSING branch: `raw_med_name = NA_character_` when `return_raw_name = TRUE` (no RAW_DISPENSE_MED_NAME in this extract)
- MED_ADMIN RX + ND branches: selects `RAW_MEDADMIN_MED_NAME` guarded by `dplyr::any_of()` — missing column degrades to NA rather than error. Deduplication via `group_by + summarise(first(raw_med_name))` prevents row multiplication
- Default path (return_raw_name = FALSE): returns 3-column tibble (ID, treatment_date, triggering_code) — all existing callers (R/10, R/11, R/25, R/76, R/20) unaffected (D-12)

### Task 2: source_hint plumbing through R/26 stacking (5576a8e)

Added per-code source provenance through R/26's chemo path.

`stack_and_dedup_with_codes()` changes:
- Tags each source's rows with physical table label via `purrr::imap()` + SOURCE_LABEL_MAP (PX/DRG -> PROCEDURES, RX -> PRESCRIBING, DX -> DIAGNOSIS, DISP -> DISPENSING, MA -> MED_ADMIN)
- Priority collapse: MED_ADMIN > DISPENSING > PROCEDURES > PRESCRIBING > DIAGNOSIS
- Empty-input guard updated to include `source_hint = character(0)`
- Returns 5-column tibble (adds `source_hint`)

`calculate_episodes_detailed()` changes:
- New `source_hints` column parallel to `triggering_codes`: same ascending-alphabetical sort order, one hint per distinct code
- Empty-input guard updated to include `source_hints = character(0)`
- `source_hints` added to final select (after `triggering_codes`, before `encounter_ids`)

Script-level combine: all_episodes combine select, final select (after drug_names join), and per-type CSV write_df all include `source_hints`. Immuno branch untouched (D-12).

### Task 3: Canonicalized raw-name fallback tier in Section 5B (1f706d1)

Extended R/26 Section 5B from 2-tier to 3-tier drug-name cascade (D-06 order):
  Tier 1: MEDICATION_LOOKUP (reference Excel, canonical — highest priority)
  Tier 2: raw_med_name_canonical = canonicalize_drug_name(toupper(trimws(raw_med_name)))
  Tier 3: RxNorm API cache (drug_name_lookup.rds)

- `disp_dates` and `ma_dates` called with `return_raw_name = TRUE`
- `raw_name_lookup` built from combined disp_dates + ma_dates; propagated to script scope via `<<-`
- D-07: `raw_med_name_canonical` NEVER writes raw string — always canonicalize_drug_name() output
- 3-arg coalesce: `dplyr::coalesce(ref_drug_name, raw_med_name_canonical, rxnorm_drug_name)`
- `drug_names = paste(sort(unique(drug_name)), collapse = ",")` aggregation unchanged

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] raw_name_lookup scope bridging via `<<-`**
- Found during: Task 3 implementation
- Issue: raw_name_lookup built inside extract_chemo_dates_with_codes() — inaccessible to Section 5B at script scope. Plan assumed availability without specifying mechanism.
- Fix: `<<-` (global assignment) inside function body; `exists("raw_name_lookup")` guard in Section 5B for resilience.
- Files modified: R/26_treatment_episodes.R
- Commit: 1f706d1

**2. [Rule 2 - Missing critical functionality] source_hints in final all_episodes select and per-type CSV**
- Found during: Task 2 review
- Issue: Plan specified the combine step but not the second select after drug_names join or per-type CSV — would have silently dropped source_hints from output.
- Fix: Added source_hints to both post-drug-names select and per-type CSV write_df select.
- Files modified: R/26_treatment_episodes.R
- Commit: 5576a8e

## Known Stubs

None — all data paths are wired. Runtime validation (source_hints populated, raw-name fallback resolving, row counts stable) confirmed in Plan 04 on HiPerGator.

## Self-Check: PASSED

Commits verified:
- fccb0f4: Task 1 (R/utils/utils_treatment.R — return_raw_name param)
- 5576a8e: Task 2 (R/26_treatment_episodes.R — source_hint + source_hints)
- 1f706d1: Task 3 (R/26_treatment_episodes.R — Section 5B 3-tier coalesce)
