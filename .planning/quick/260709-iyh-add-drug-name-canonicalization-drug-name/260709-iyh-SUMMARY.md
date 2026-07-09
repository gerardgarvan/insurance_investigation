# Quick Task 260709-iyh — Drug-Name Canonicalization — SUMMARY

**Date:** 2026-07-09
**Status:** Complete
**Commits:** `242c458` (code), `d8a74a1` (R/88 checks), docs commit (this file + STATE)

## Goal

Collapse same-drug/different-name duplicates in the Gantt `drug_names` field, starting
with doxorubicin. Canonical target for plain (non-liposomal) doxorubicin = **"Doxorubicin
Hydrochloride"**. Liposomal doxorubicin kept clinically distinct.

## What was implemented

### R/00_config.R (after the J-code supplement merge, ~line 2360)
- `DRUG_NAME_ALIASES` — 3 lowercase keys (`doxorubicin`, `doxorubicin hcl`, `doxorubicin
  hydrochloride`) → all map to canonical `"Doxorubicin Hydrochloride"`. Liposomal forms
  deliberately absent (they never match the plain keys, so they pass through untouched).
- `canonicalize_drug_name(x)` — vectorized, NA-safe, case-insensitive alias lookup;
  returns the canonical name on a key match, else the input unchanged.
- Applied to `MEDICATION_LOOKUP` (names preserved): the reference-Excel side now emits the
  same canonical form as the R/27 side.

### R/27_drug_name_resolution.R (before Save Outputs, ~line 456)
- `all_lookups <- all_lookups %>% mutate(drug_name = canonicalize_drug_name(drug_name))`
  applied to the FINAL table (cache + new). This canonicalizes new lookups AND
  re-normalizes STALE cached entries (fixes the pre-title-casing lowercase `"doxorubicin"`).
  No new API calls — pure string mapping over the existing cache.

### R/88_smoke_test_comprehensive.R (Section 15j, Phase 114 drug-name area)
- 4 structural checks: (15) R/00_config defines `DRUG_NAME_ALIASES` + `canonicalize_drug_name`;
  (16) applied to `MEDICATION_LOOKUP`; (17) alias map has NO liposomal key; (18) R/27 applies
  it to `all_lookups$drug_name`.

## Deviation note (rejected executor attempt)

The first gsd-executor run deviated from the plan and was **discarded (worktree branch
deleted, never merged)**. Its output: (a) mapped the canonical direction BACKWARDS
(`"Doxorubicin Hydrochloride" -> "Doxorubicin"`, opposite of the locked decision); (b) used
a case-sensitive title-case-keyed map that would NOT match the stale lowercase `"doxorubicin"`,
so it didn't fix the reported duplicate; (c) skipped `MEDICATION_LOOKUP`; (d) added 18
unreviewed multi-drug merges. The orchestrator re-implemented the plan's actual spec directly.

## Verification (structural, Windows-local)

- `DRUG_NAME_ALIASES` / `canonicalize_drug_name` present in R/00_config; applied to
  `MEDICATION_LOOKUP`; 3 keys all → `"Doxorubicin Hydrochloride"`; no `liposomal` key.
- R/27 applies `canonicalize_drug_name` to `all_lookups$drug_name`.
- R/88 has 4 `quick iyh` checks.
- Rscript not available locally → full parse/run deferred to HiPerGator.

## HiPerGator regeneration order (to propagate end-to-end)

1. `R/27_drug_name_resolution.R` — re-normalizes `drug_name_lookup.rds`/`.csv` cache (no new API calls).
2. `R/26_treatment_episodes.R` — rebuilds `treatment_episodes.rds` with canonical `drug_names`.
3. `R/52_gantt_v2_export.R` — regenerates `output/gantt_episodes.csv`.
4. `R/101_gantt_lifespan_collapse.R` — regenerates `output/gantt_lifespan.csv`.

After regeneration, a doxorubicin episode should show a single `"Doxorubicin Hydrochloride"`
token (no lowercase `"doxorubicin"` duplicate), while liposomal doxorubicin remains separate.
