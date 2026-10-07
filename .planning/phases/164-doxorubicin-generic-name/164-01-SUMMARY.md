---
phase: 164
plan: 01
subsystem: drug-name-normalization
tags: [doxorubicin, adriamycin, liposomal, gantt, drug-names, canonicalize]
requires: [R/00_config.R DRUG_NAME_ALIASES, canonicalize_drug_name, treatment_episode_detail.rds]
provides: [unified Doxorubicin label in all Gantt drug_names columns, 164_dox_baseline_counts.rds]
affects: [R/26 drug_names, R/52 Gantt output, R/142 Gantt 180-day output, R/88 smoke test]
tech-stack:
  added: []
  patterns: [DRUG_NAME_ALIASES alias map, canonicalize_drug_name vectorized lookup, sort(unique()) dedup]
key-files:
  created:
    - R/164_dox_baseline_counts.R
    - tests/testthat/test-164-drug-name-normalization.R
  modified:
    - R/00_config.R
    - R/42_build_code_descriptions.R
    - R/58_code_reference_tables.R
    - R/88_smoke_test_comprehensive.R
decisions:
  - D-1 canonical form: bare generic "Doxorubicin" (salt/formulation suffixes dropped; same Vinblastine precedent)
  - D-3 liposomal collapse: Doxil/Caelyx/liposomal variants all -> "Doxorubicin" (no separate liposomal label)
  - D-4 fix location: single mapping in DRUG_NAME_ALIASES / MEDICATION_LOOKUP_JCODE_SUPPLEMENT; no per-chart patches
metrics:
  duration_minutes: 4
  completed: 2026-10-07
  tasks_completed: 4
  tasks_total: 5
  files_modified: 6
  files_created: 2
requirements-met: [D-1, D-2, D-3, D-4]
requirements-deferred: []
---

# Phase 164 Plan 01: Normalize Adriamycin and Liposomal Variants to Doxorubicin Summary

Single canonical drug-name mapping applied upstream via DRUG_NAME_ALIASES, collapsing adriamycin/adriamycin pfs/adriamycin rdf, doxorubicin salt forms, and all liposomal variants (doxil/caelyx/liposomal doxorubicin/doxorubicin liposomal/doxorubicin hcl liposome) to the bare generic "Doxorubicin" in all Gantt outputs.

## Objective

Ensure every treatment-episode Gantt chart labels doxorubicin as "Doxorubicin" — no Adriamycin, Doxil, Caelyx, or liposomal labels appear as separate drug rows or colors.

## Tasks Executed

| Task | Description | Commit | Status |
|------|-------------|--------|--------|
| 1 | Inventory — grep for adriamycin/doxorubicin/doxil/caelyx/liposom; identify Gantt scripts and drug-name derivation path | (in-session, documented below) | DONE |
| 2 | Baseline counts script (R/164_dox_baseline_counts.R) | 75372c6 | DONE |
| 3 | Mapping — extend DRUG_NAME_ALIASES, update MEDICATION_LOOKUP_JCODE_SUPPLEMENT, CODE_SUBCATEGORY_MAP, remove "(Adriamycin)" from R/42 + R/58 | 93fc54d | DONE |
| 4 | Tests — testthat file + R/88 smoke-test Check 17 replacement | 2925e72 | DONE |
| 5 | HiPerGator run + visual reconciliation | (checkpoint — pending) | PENDING |

## Task 1 Findings

### Scripts and Drug-Name Source Columns

| Script | Role | Drug column | Source |
|--------|------|-------------|--------|
| R/26_treatment_episodes.R | Builds treatment_episode_detail.rds | drug_name (per row), drug_names (per episode, semicolon/comma joined) | MEDICATION_LOOKUP > canonicalize_drug_name(raw_med_name) > RxNorm cache |
| R/27_drug_name_resolution.R | Populates drug_name_lookup.rds (RxNorm cache) | drug_name | canonicalize_drug_name() applied at save |
| R/52_gantt_v2_export.R | 90-day Gantt | drug_names (episode grain), drug_name (detail grain) | Reads from treatment_episode_detail.rds |
| R/142_gantt_180_export.R | 180-day Gantt | drug_names (episode grain), drug_name (detail grain) | Reads from treatment_episode_detail.rds |
| R/104_gantt_entire_history.R | Lifespan Gantt | drug_names | Reads from episodes RDS |
| R/101_gantt_lifespan_collapse.R | Lifespan collapse | drug_names | Reads from episodes RDS |

### Raw String Variants Found

- **Brand names:** `adriamycin`, `adriamycin pfs`, `adriamycin rdf` (RXNORM ID 2001102 comment "ADRIAMYCIN IV")
- **Generic/salt forms:** `doxorubicin`, `doxorubicin hcl`, `doxorubicin hydrochloride`
- **Liposomal:** `liposomal doxorubicin` (J9223, MEDICATION_LOOKUP), `doxorubicin (liposomal)` (RxNorm 1790115/1790394), `doxil`, `caelyx`, `doxorubicin liposomal`, `doxorubicin hcl liposome`
- **Per-chart labels with Adriamycin:** R/42 and R/58 `config_descriptions` had `"J9000" = "Doxorubicin HCl (Adriamycin)"`

### Existing Normalization Helper

`canonicalize_drug_name()` in R/00_config.R with `DRUG_NAME_ALIASES` map existed from Phase 142 (Vinblastine fix). Previously mapped dox variants → `"Doxorubicin Hydrochloride"` (not the bare generic). This plan extends it.

### HCPCS Codes Found

- J9000 = Doxorubicin HCl (conventional, Adriamycin)
- J9001 = Doxorubicin HCl liposomal (Doxil) — not previously in MEDICATION_LOOKUP_JCODE_SUPPLEMENT
- J9223 = Liposomal Doxorubicin — previously mapped to `"Liposomal Doxorubicin"` in CODE_SUBCATEGORY_MAP

## Task 3 Changes

### DRUG_NAME_ALIASES extended (R/00_config.R)

Added keys (all → `"Doxorubicin"`):
- `"adriamycin"`, `"adriamycin pfs"`, `"adriamycin rdf"`
- `"doxorubicin"` (retarget: was → `"Doxorubicin Hydrochloride"`, now → `"Doxorubicin"`)
- `"doxorubicin hcl"` (same retarget)
- `"doxorubicin hydrochloride"` (same retarget)
- `"doxil"`, `"caelyx"`, `"liposomal doxorubicin"`, `"doxorubicin liposomal"`,
  `"doxorubicin hcl liposome"`, `"doxorubicin (liposomal)"`

### MEDICATION_LOOKUP_JCODE_SUPPLEMENT updated

- J9000: `"Doxorubicin Hydrochloride"` → `"Doxorubicin"` (then alias also applies)
- J9001: NEW → `"Doxorubicin"`

### CODE_SUBCATEGORY_MAP updated

- J9001: NEW → `"Doxorubicin"`
- J9223: `"Liposomal Doxorubicin"` → `"Doxorubicin"`

### Per-chart patches removed

- R/42_build_code_descriptions.R: `"J9000" = "Doxorubicin HCl (Adriamycin)"` → `"Doxorubicin HCl"`
- R/58_code_reference_tables.R: same change

### Deduplication

Automatic — `drug_names` aggregation in R/26 already uses `paste(sort(unique(drug_name)), collapse = ",")`. After mapping, formerly-distinct tokens that now equal `"Doxorubicin"` are deduplicated by `unique()`.

## Task 4 Tests

### tests/testthat/test-164-drug-name-normalization.R (8 test blocks)

1. Adriamycin brand names (adriamycin, adriamycin pfs, adriamycin rdf, case variants) → `"Doxorubicin"`
2. Generic/salt forms (doxorubicin, doxorubicin hcl, doxorubicin hydrochloride) → `"Doxorubicin"`
3. Liposomal variants (doxil, caelyx, liposomal doxorubicin, doxorubicin liposomal, doxorubicin hcl liposome) → `"Doxorubicin"`
4. ABVD and other drugs pass through unchanged
5. Idempotency: normalizing twice gives same result
6. NA → NA
7. Duplicate collapse: mixed dox tokens → single `"Doxorubicin"` in sorted-unique join
8. Vectorized: mixed input vector works correctly

### R/88 smoke test changes

- **Check 17 replaced:** Was "liposomal is NOT an alias key". Now: "required dox alias keys ARE present" — verifies adriamycin, doxil, caelyx, liposomal doxorubicin, doxorubicin liposomal, doxorubicin hcl liposome all present in alias map.
- **Check 17b added:** Verifies R/52 and R/142 have NO inline `adriamycin|doxil|caelyx|liposom` string patches in code lines (comments excluded).

## Deviations from Plan

None — plan executed exactly as written. Task 1 was an in-session inventory (no separate commit required). Deduplication (Task 3 last bullet) was already implemented by R/26's existing `sort(unique())` logic — no code change needed.

## Task 5 (Pending — HiPerGator Checkpoint)

Task 5 requires:
1. Sync changes to HiPerGator
2. Run `R/164_dox_baseline_counts.R` BEFORE re-running Gantt scripts (baseline already recorded if run pre-change)
3. Re-run R/52 and R/142 under `module load R/4.5`
4. Reconcile: patient count with doxorubicin unchanged; row-drop equals brand/generic + liposomal/conventional duplicates from baseline
5. Visual confirmation: no Adriamycin/liposomal label; single Doxorubicin row/color per patient-episode
6. Update R/SCRIPT_INDEX.md if needed (add R/164)

## Self-Check: PASSED

- R/164_dox_baseline_counts.R: FOUND
- tests/testthat/test-164-drug-name-normalization.R: FOUND
- Commits 75372c6, 93fc54d, 2925e72: FOUND (git log confirmed)
