---
phase: 210-abvd-avd-episode-and-patient-flags
plan: 01
requirements-completed: [ABVD-01, ABVD-02, ABVD-03]
key-files:
  created: [R/utils/utils_abvd_flags.R, tests/testthat/test-210-abvd-avd-flags.R]
  modified: [R/00_config.R]
---

# Phase 210 Plan 01: ABVD/AVD episode flag helper Summary

Pure helper `compute_abvd_avd_flags()` derives `abvd_episode` / `avd_episode` / `abvd_jcode_fallback` from drug tokens plus HCPCS J-code evidence, with `patient_ever_flag()` and `abvd_flag_dictionary()`; config constant `AVD_INCLUDES_BV_NIVO`.

## What changed
- `R/00_config.R`: `AVD_INCLUDES_BV_NIVO` (default TRUE, env override `AVD_INCLUDES_BV_NIVO`) after `ABVD_EXCLUDING_DRUGS`, with stopifnot validation.
- `R/utils/utils_abvd_flags.R`: helper, `ABVD_JCODE_MAP` (J9000 Doxorubicin, J9040 Bleomycin, J9360 Vinblastine, J9130 Dacarbazine, J9042 Brentuximab Vedotin, J9299 Nivolumab), `ABVD_FLAG_CHEMO_LABEL`, `patient_ever_flag()`, `abvd_flag_dictionary()`.
- `tests/testthat/test-210-abvd-avd-flags.R`: all plan cases plus J-code and fallback cases.

## Probe / Task 0
- Probe: `.planning/schemas/203_schema_inputs_20261114.md` section 2 (32-col `output/gantt_episodes_180.csv`). `drug_names`, `treatment_type`, `triggering_codes`, `code_type` are in R/142 `EPISODES_SCHEMA` and the probe column list. "Chemotherapy" label per plan.
- Code column found: `triggering_codes` (also `code_type`, `triggering_code_descriptions`). Helper takes `code_text`; callers (plans 02/03) should pass `triggering_codes`. Whether `triggering_codes` holds HCPCS J-codes for chemo rows is not confirmed by the probe; verify on HiPerGator.

## Deviations from Plan
- **[User adjustment] J-code evidence and JCODE_ABVD fallback replace CONTEXT assumption A1** (blank drug_names -> F/F). Drug evidence = drug_names tokens (supportive removed) union J-code-implied drugs. If `abvd_class == "JCODE_ABVD"` and no drug tokens and no recognised J-codes, Chemotherapy rows get abvd TRUE, avd FALSE, `abvd_jcode_fallback` TRUE. Blank drugs with other/NA abvd_class remain F/F. New optional args `abvd_class`, `code_text`; returns a third logical column. CONTEXT not edited. Dictionary `abvd_episode` definition documents the fallback.
- Single commit after Task 2 (green) as instructed; Task 1 red tests not committed separately.

## Assumptions (headless run)
- Env override for `AVD_INCLUDES_BV_NIVO` kept per plan.
- J-code tokens are matched exactly (upper-cased) after splitting on `[,;| ]`; unrecognised codes are not evidence.
- J9042/J9299 map to the canonical `ABVD_EXCLUDING_DRUGS` names, so they follow `AVD_INCLUDES_BV_NIVO`.
- Fallback applies to Chemotherapy rows only.

## Verification
- `tools/rcheck.sh parse` on the 3 files: 0 failed.
- `test 210`: 0 failures; `test 201`: 0 failures; `test 205-regimen` (3 files): 0 failures.
- Only warning: reference Excel absent locally (MEDICATION_LOOKUP empty), unrelated.

## Self-Check: PASSED
