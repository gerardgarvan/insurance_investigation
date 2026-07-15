# Plan 124-04 Summary — HiPerGator Regeneration + Runtime Confirmation

**Status:** Complete
**Type:** checkpoint:human-action (HiPerGator runtime; no Rscript on Windows executor)
**Date:** 2026-07-15

## What was done

The full in-scope downstream chain was regenerated on HiPerGator (RStudio, R/4.4.2) in
dependency order with the Phase 124 code, then the output-level before/after report and
smoke test were run. Three first-real-run bugs were found and fixed mid-execution (see
Deviations); after the fixes the chain completed clean.

Run order executed: R/26 → R/28 → R/29 → R/52 → R/101 → R/104 → (R/20/R/36/R/56/R/57) →
R/110 → R/88.

## Runtime confirmation (pasted-back evidence, verbatim)

1. **Chemo episodes increased (D-01/D-10):** episodes `treatment_episodes.rds` = 18,448 rows;
   Gantt chemo episodes 12,205 (was 11,208). Gantt total 26,447 → **27,444** (+997 episodes,
   +89 patients) vs the pre-fix baseline.
2. **Source attribution landed (D-05):** `table(gantt_episodes.csv$source_table)` now includes
   **DISPENSING (1,058)** and **MED_ADMIN (1,668)** tokens — both were 0 in the pre-fix and
   Phase-122-only outputs. `code_type` now includes **NDC (1,058)**, exactly matching the
   DISPENSING count (D-04: DISPENSING → NDC).
3. **Chemo-only (D-12):** only Chemotherapy grew; Death/HL-Dx/Immunotherapy/Proton/Radiation/SCT
   row counts unchanged. Immuno branches untouched.
4. **Canonical drug names (D-07):** DISPENSING/MED_ADMIN episodes show canonical names
   (e.g. "Bleomycin;Dacarbazine;Doxorubicin Hydrochloride"), alphabetically sorted; no raw
   free-text leaked.
5. **Report delivered (D-02/D-08/D-15):** `output/output_level_before_after_report.xlsx` written,
   5 sheets — Summary (5 rows), Regimen Distribution (1 row: ABVD; after-only, see caveat),
   Timing Shift (1 row), Payer-Anchor (placeholder — payer_at_chemo.csv absent), Unmapped Names
   (0 — all names canonical). HIPAA suppression via suppress_small (9 calls).
6. **Smoke (SMOKE-124-01 / Section 15v):** **13/13 PASS.** Overall R/88 = 2/692 fail, both
   benign and NOT Phase 124 regressions:
   - R/102 DEATH_CAUSE field-availability guard — pre-existing (Phase 118/119).
   - `episode_classification_audit.xlsx` 'Linkage Improvement' sheet — run-order artifact: R/28
     regenerated the workbook; R/30 (out-of-scope investigation) not re-run to re-append the
     sheet. `git log -S "Linkage Improvement"` confirms the sheet was never in R/28; the check
     targets R/30's append step.
7. **Out-of-scope untouched (D-11/D-13):** R/70/R/71/R/72/R/73 not run; `chemo_rxnorm` not edited;
   cohort membership unchanged (chemo is a flag not a filter — R/14; HL-diagnosis pseudo-row
   count 7,696 identical old→new).

## Deviations (first-real-run bugs fixed during the checkpoint)

These paths had never executed on real data (Phase 122 deferred downstream regeneration to this
phase), so latent bugs surfaced and were fixed atomically:

- **R/20** (`0f279c6`): DISPENSING block grouped by a literal `drug_name = NA_character_` inside the
  lazy DuckDB pipeline → DuckDB typed the column INTEGER on collect → `bind_rows` type clash. Moved
  `NA_character_` out of `group_by` into the post-`collect()` `mutate`.
- **R/110** (`0887244`): six Python-style `{expr:,}` glue format specs (invalid in R glue) → parse
  error. Replaced with `{format(nrow(x), big.mark = ',')}`.
- **R/110** (`8733304`): read episodes from `here("cache","outputs")` instead of
  `CONFIG$cache$outputs_dir` (on HiPerGator an absolute out-of-project path) → episodes "not found",
  Regimen/Unmapped sheets empty. Pointed all three episode/detail paths at `CONFIG$cache$outputs_dir`.

## Known limitations (accepted, not blocking)

- **Episode-level "before" baseline unavailable.** `treatment_episodes_pre_p124.rds` was never
  snapshotted (the file lived at `clean/rds/outputs`, not the `cache/outputs` STEP 0 checked, and
  the live file was overwritten by the good run). The report's episode-level *before* column is
  blank; the **Gantt-level** before/after (26,447 → 27,444) is intact and is the headline. No
  committed pre-fix `treatment_episodes.rds` exists to reconstruct it — treated as out of scope.
- **Regimen Distribution = 1 row** (ABVD only): honest — R/29 produced only ABVD (2,750);
  BV+AVD/Nivo+AVD were 0 in this cohort, and the before baseline is absent.
- **Payer-Anchor placeholder:** `payer_at_chemo.csv` not produced by this chain; sheet guards.

## Follow-ups (optional / out of scope)

- Run `R/30_condition_linkage_investigation.R` to re-append the 'Linkage Improvement' sheet and
  clear the benign R/88 failure.
- R/102 DEATH_CAUSE smoke failure remains (pre-existing Phase 118/119) — track separately.
