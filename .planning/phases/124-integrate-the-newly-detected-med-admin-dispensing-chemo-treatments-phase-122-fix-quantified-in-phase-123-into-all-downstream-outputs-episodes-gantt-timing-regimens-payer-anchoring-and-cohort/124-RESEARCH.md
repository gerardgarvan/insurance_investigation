# Phase 124: Integrate MED_ADMIN/DISPENSING Chemo Into All Downstream Outputs — Research

**Researched:** 2026-07-14
**Domain:** R treatment pipeline — downstream regeneration, drug-name normalization, Gantt labeling
**Confidence:** HIGH (all findings verified against actual source files)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Regenerate all in-scope downstream outputs with the expanded chemo sources. Detection is already wired via `get_chemo_hits()` (Phase 122).
- **D-02:** Produce a NEW Amy-ready output-level before/after comparison report covering: # treatment episodes, # patients with any chemo episode, first-line regimen-label distribution, first-chemo timing shifts, payer-anchor window changes.
- **D-04:** Code Type = true source code type: `NDC` for DISPENSING and MED_ADMIN-ND records, `RXNORM` for MED_ADMIN-RX (and existing PRESCRIBING) records.
- **D-05:** Source Table gains new distinct values `DISPENSING` and `MED_ADMIN` alongside existing PRESCRIBING/PROCEDURES/DIAGNOSIS values.
- **D-06:** Drug-name resolution = best-available fallback: crosswalk RxCUI → `MEDICATION_LOOKUP` first, then `RAW_MEDADMIN_MED_NAME` free-text (MED_ADMIN only), then blank. Raw free-text MUST pass through `canonicalize_drug_name()` / `DRUG_NAME_ALIASES` before output.
- **D-07:** ALL regenerated outputs must use a SINGLE canonical spelling per drug regardless of source.
- **D-08:** Unmapped names: retain cleaned (uppercased/trimmed) string in output, surface an audit list xlsx of unmapped names for SME review.
- **D-09:** Regenerate regimen labels silently — aggregate regimen-label distribution change appears in D-02 before/after report only.
- **D-10-reg:** All chemo sources treated equally as regimen input (DISPENSING/MED_ADMIN dates feed identically to PRESCRIBING).
- **D-10:** In scope: R/26, R/25, R/28, R/29, R/52, R/101, R/104, R/11, R/14, R/76, R/20, R/36, R/56, R/57.
- **D-11:** Out of scope: R/72, R/73 (PPTX), R/70 (waterfall), R/71 (Sankey).
- **D-12:** Chemo-only. Immunotherapy MED_ADMIN/DISPENSING branches stay untouched.
- **D-13:** `chemo_rxnorm` reference list is NOT edited.
- **D-14:** Cohort membership is unchanged — chemo is a flag, not a filter (R/14 line 362).
- **D-15:** HIPAA suppression standard throughout (counts 1–10).

### Claude's Discretion
- Baseline-capture mechanism for the D-02 before/after report (D-03)
- DuckDB re-run orchestration and the HiPerGator runtime checkpoint
- Exact report sheet layout/ordering and styling helpers to reuse (R/51 / TABLE pattern)
- Script number(s) / registration (R/39 vs SCRIPT_INDEX-only) and R/88 smoke sections
- Where the unmapped-name audit list lives (standalone xlsx vs a sheet in the D-02 report)

### Deferred Ideas (OUT OF SCOPE)
- Immunotherapy MED_ADMIN/DISPENSING contribution
- Correcting `chemo_rxnorm` from Phase 123 D-10's 5 candidate gaps
- PPTX (R/72/R/73), waterfall (R/70), Sankey (R/71) regeneration
- Extending drug-name aliases from the D-08 unmapped-name audit — follow-up after SME review
</user_constraints>

---

## Summary

Phase 124 is a downstream regeneration pass — no new detection logic, only running the already-wired pipeline and confirming the Phase 122 fix flows through to all final products. The core challenge is not the individual scripts (all 7 consumers were patched in Phase 122) but rather three cross-cutting concerns: (1) establishing a valid "before" baseline that genuinely predates the Phase 122 fix; (2) extending the Gantt code_type/source_table population mechanism to recognize DISPENSING and MED_ADMIN as new source values (currently the xlsx_lookups mechanism maps every chemo_rxnorm code → source_table="PRESCRIBING" regardless of which table actually contributed the hit); and (3) guaranteeing `canonicalize_drug_name()` + `MEDICATION_LOOKUP` as the single normalization choke-point for all raw drug strings reaching any output.

The run order is strictly determined by RDS dependencies: R/26 → R/28 → R/29 → R/52 → R/101 → R/104 for the Gantt chain; R/25 → payer summaries for timing/payer; R/14 and R/11 run together as the cohort build. The before/after report (a new R/110 or similar) should be an output-level diff script in the style of R/109, comparing pre-regeneration output snapshots against post-regeneration files. Because cache/outputs/ on HiPerGator currently holds RDS files that predate Phase 122 regeneration, those snapshots are the legitimate "before" baseline — no snapshotting step is needed if the plan snapshots those files before the first R/26 run.

**Primary recommendation:** Snapshot the current HiPerGator `cache/outputs/treatment_episodes.rds` (and the current gantt CSVs) before any regeneration run, then run the pipeline in dependency order, then run the before/after diff report. This is the cleanest, lowest-risk baseline approach.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| R | 4.4.2+ | Base language | HiPerGator module; all scripts target this |
| tidyverse (dplyr, stringr, glue, purrr) | 2.0.0+ | Data manipulation | Project-wide standard; named-predicate style |
| openxlsx2 | any | xlsx output | Used by R/51, R/109, R/36 — established pattern |
| here | 1.0.2 | Path management | All scripts use here::here() for crosswalk path |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| data.table | 1.16.2+ | Fast aggregation | R/28 already uses it for metadata_agg (Phase 98) |
| lubridate | 1.9.3+ | Date arithmetic | First-chemo timing shift in D-02 report |
| checkmate | any | Assertions | Used in R/26 episode-count guard |

### Alternatives Considered
None — existing project stack is well-established and mandated by CLAUDE.md.

---

## Architecture Patterns

### Consumer → Output Dependency Graph

#### Chain 1: Core Episodes (must run first)

```
R/25_treatment_durations.R
  reads:  DuckDB PRESCRIBING, DISPENSING, MED_ADMIN, PROCEDURES, DIAGNOSIS, ENCOUNTER, TUMOR_REGISTRY_ALL
  writes: cache/outputs/treatment_durations.rds
          output/treatment_durations.xlsx
          output/{type}_durations.csv

R/26_treatment_episodes.R
  sources: R/25 (for assign_episode_ids, stack_and_dedup)
  reads:  DuckDB tables (same sources as R/25 + get_chemo_hits)
  writes: cache/outputs/treatment_episodes.rds        ← CENTRAL ARTIFACT
          cache/outputs/treatment_episode_detail.rds
          output/treatment_episodes.xlsx
          output/{type}_episodes.csv
          output/{type}_episode_detail.csv
```

#### Chain 2: Enrichment (consumes treatment_episodes.rds in-place)

```
R/28_episode_classification.R
  reads:  cache/outputs/treatment_episodes.rds  (readRDS → enrich → saveRDS in-place)
          cache/outputs/treatment_episode_detail.rds
          DuckDB DIAGNOSIS
  writes: cache/outputs/treatment_episodes.rds (adds 15+ columns including
          cancer_category, regimen_label, code_type, source_table, drug_group,
          episode_dx_codes, episode_dx_categories)
          output/episode_classification_audit.xlsx
          output/unresolved_codes_for_review.xlsx

R/29_first_line_and_death_analysis.R
  reads:  cache/outputs/treatment_episodes.rds
          cache/outputs/treatment_episode_detail.rds
          cache/outputs/validated_death_dates.rds
  writes: cache/outputs/treatment_episodes.rds (adds is_first_line flag)
          cache/outputs/first_line_therapy.rds
          output/death_analysis.xlsx
```

#### Chain 3: Gantt Export (consumes all enriched RDS)

```
R/52_gantt_v2_export.R
  reads:  cache/outputs/treatment_episodes.rds (fully enriched by R/26+R/28+R/29)
          cache/outputs/treatment_episode_detail.rds
          cache/outputs/code_descriptions.rds
          cache/outputs/validated_death_dates.rds
          output/confirmed_hl_cohort.rds
          output/tables/cancer_summary.csv (for 7-day confirmed)
          DuckDB DEMOGRAPHIC (for age_at_episode)
  writes: output/gantt_episodes.csv (20 columns)
          output/gantt_detail.csv (14 columns)

R/101_gantt_lifespan_collapse.R
  reads:  output/gantt_episodes.csv
  writes: output/gantt_lifespan.csv

R/104_gantt_entire_history.R
  reads:  output/gantt_lifespan.csv
          output/gantt_episodes.csv
  writes: output/gantt_entire_history.csv (6 columns)
```

#### Chain 4: Cohort Flags + Payer (independent from Chain 1-3, runs via R/14)

```
R/14_build_cohort.R  [sources R/10, R/11, R/12, R/13]
  R/11_treatment_payer.R
    reads:  DuckDB PRESCRIBING, DISPENSING, MED_ADMIN, PROCEDURES, DIAGNOSIS, ENCOUNTER, TUMOR_REGISTRY_ALL
    writes: in-memory treatment_payer tibble (FIRST_CHEMO_DATE, PAYER_AT_CHEMO, etc.)
  R/14 combined writes:
    output/hl_cohort.rds
    output/cohort/hl_cohort.csv
    cache/cohort/cohort_final.rds, attrition_log.rds, cohort_00_initial_population.rds, etc.
```

#### Chain 5: Investigation Scripts (consume treatment_episodes.rds)

```
R/76_treatment_source_coverage.R
  reads:  DuckDB tables (self-contained; extracts its own dates)
  writes: output/source_coverage_analysis.csv + .xlsx

R/20_treatment_inventory.R
  reads:  DuckDB tables (self-contained)
  writes: output/treatment_inventory.xlsx

R/36_tableau_ready_tables.R
  reads:  cache/outputs/treatment_episode_detail.rds
          DuckDB DIAGNOSIS
  writes: output/tableau_table1_encounter_cancer_codes.xlsx
          output/tableau_table2_chemo_drugs_by_class.xlsx

R/56_new_tables_from_groupings.R
  reads:  cache/outputs/treatment_episodes.rds (enriched)
          DuckDB DIAGNOSIS
  writes: output/episode_level_drug_grouping_tables.xlsx
          output/drug_grouping_tables.xlsx

R/57_drug_grouping_instances.R
  reads:  cache/outputs/treatment_episodes.rds (enriched) or similar
  writes: output/drug_grouping_instances.xlsx
```

### Full Run Order (R/39 order)

Per `R/39_run_all_investigations.R` lines 136-165, the canonical order is:

1. `R/14_build_cohort.R` (auto-sources R/11 for payer anchoring)
2. `R/03_duckdb_ingest.R`
3. `R/47_cancer_summary_refined.R` (produces confirmed_hl_cohort.rds)
4. `R/26_treatment_episodes.R` (sources R/25 internally)
5. `R/28_episode_classification.R`
6. `R/29_first_line_and_death_analysis.R`
7. `R/53_death_date_validation.R` (produces validated_death_dates.rds)
8. `R/42_build_code_descriptions.R` (produces code_descriptions.rds)
9. [Investigation scripts including R/36, R/56, R/57, R/76, R/20]
10. [Export scripts including R/52, then R/101, R/104 in investigation_scripts]

**Key dependency constraint:** R/52 requires all of treatment_episodes.rds (enriched by R/26+R/28+R/29), code_descriptions.rds, validated_death_dates.rds, and confirmed_hl_cohort.rds — run last in the export stage.

**R/101 and R/104 position:** Both are in the `investigation_scripts` vector (R/39 lines 191-194), which runs BEFORE R/52 in the export stage. This is a potential ordering issue: R/101 consumes `gantt_episodes.csv` which is produced by R/52 (stage 4), but R/101 is in stage 2. In practice R/39 tolerates this because R/101/R/104 fail gracefully (file.exists guards) when gantt_episodes.csv is absent. The planner should note that for a standalone targeted regeneration (not using R/39), the correct order is: R/52 → R/101 → R/104.

---

## Critical Finding: code_type / source_table for DISPENSING and MED_ADMIN

This is the most important discovery for the Gantt labeling task (D-04/D-05).

### How code_type and source_table are currently populated (Phase 91)

`R/28_episode_classification.R` at lines 510–585 builds `code_type` and `source_table` per episode using `utils_xlsx_lookups.R::load_xlsx_lookups()`. That function builds named vectors from `TREATMENT_CODES` sublist names (e.g., `chemo_rxnorm → "PRESCRIBING"`, `chemo_hcpcs → "PROCEDURES"`).

The critical gap: every RxNorm CUI in `chemo_rxnorm` is mapped `source_table = "PRESCRIBING"` (line 80 of utils_xlsx_lookups.R). When get_chemo_hits() returns a triggering_code from DISPENSING or MED_ADMIN, R/28's lookup finds that RxNorm CUI → "PRESCRIBING" and labels it wrong.

### Current episode-level flow for triggering_codes

R/26 `extract_chemo_dates_with_codes()` returns `triggering_code = rxcui` for both DISPENSING and MED_ADMIN hits (because get_chemo_hits() resolves NDC → RxCUI before returning). By the time R/28 receives treatment_episodes.rds, the triggering_codes column contains only the resolved RxCUI — there is no record of which physical table it came from.

### What must change to support D-04/D-05

Two complementary approaches (the planner must pick or combine):

**Option A — Source tag in R/26:** Add a `source_table_hint` column to the per-episode data in R/26, populated from the named source list in `stack_and_dedup_with_codes()` (currently `DISP`, `MA` etc. are the list names). Propagate this through to treatment_episodes.rds so R/28 can use it instead of the xlsx_lookup.

**Option B — Extend utils_xlsx_lookups.R source_table_map:** Add entries for `chemo_rxnorm_dispensing` and `chemo_rxnorm_med_admin` that map codes → "DISPENSING"/"MED_ADMIN" when reached via those paths. This does not work cleanly because the same RxCUI can come from multiple sources.

**Recommended (Option A):** The cleanest approach is to carry a `source_table_hint` alongside `triggering_code` through R/26. The stack_and_dedup_with_codes function already knows which named source each row came from (DISP, MA, RX, PX, etc.) — attach a source label before stacking, preserve it through the summarise step (taking the semicolon-separated set of sources per episode), and write it to treatment_episodes.rds. R/28 then uses this column to populate `source_table` for DISPENSING/MED_ADMIN records instead of the xlsx_lookup.

**Code Type for D-04:**
- DISPENSING hits: `triggering_code = rxcui` (after NDC→RxCUI crosswalk) → code_type = "RXNORM" (correct, but conceptually this came from an NDC match)
- MED_ADMIN-RX hits: `triggering_code = MEDADMIN_CODE` = RxNorm CUI → code_type = "RXNORM" (correct)
- MED_ADMIN-ND hits: `triggering_code = rxcui` (NDC→RxCUI crosswalk) → code_type = "RXNORM" (resolved form)

Decision D-04 says: "NDC for DISPENSING and MED_ADMIN-ND records." This means the plan must decide whether to show the original NDC code or the resolved RxCUI as `code`. If showing NDC: requires keeping the raw NDC alongside the RxCUI, which get_chemo_hits() does NOT currently return (it only returns the resolved `triggering_code = rxcui`). If showing RXNORM (the resolved form): code_type = "RXNORM" is accurate and no schema change is needed. The planner must resolve this: D-04's "NDC" label likely refers to the code_type column value, not the code value itself — i.e., label what kind of code originally matched, not what code is stored. Either way, source_table = "DISPENSING"/"MED_ADMIN" (D-05) is the more critical new column.

---

## Drug-Name Normalization (D-06/D-07/D-08)

### Current normalization chain in R/26 (lines 671–734)

R/26 Section 5B already performs a 2-tier cascade:
1. `MEDICATION_LOOKUP[triggering_code]` — reference Excel lookup (canonical)
2. `drug_name_lookup.rds` — RxNorm API cache (fallback)
3. `coalesce(ref_drug_name, rxnorm_drug_name)` → `drug_name`

This produces `drug_name` per detail row, then aggregates to `drug_names` per episode via `paste(sort(unique(drug_name)), collapse = ",")`.

### What the new sources bring

- **DISPENSING:** `triggering_code = rxcui` (crosswalk-resolved). MEDICATION_LOOKUP is keyed by code. If the rxcui is in MEDICATION_LOOKUP (i.e., in `chemo_rxnorm`), the name resolves via Tier 1. If not, falls to Tier 2 (RxNorm API cache). No raw text available (DISPENSING has no RAW_DISPENSE_MED_NAME in this extract — confirmed by Phase 122 CONTEXT).

- **MED_ADMIN-RX:** `triggering_code = MEDADMIN_CODE` = RxNorm CUI. Same resolution path as DISPENSING.

- **MED_ADMIN-ND:** `triggering_code = rxcui` (NDC→RxCUI crosswalk). Same path. Raw text `RAW_MEDADMIN_MED_NAME` is available in the source row but is NOT returned by `get_chemo_hits()` (the helper only returns ID, treatment_date, triggering_code).

### D-06 fallback to RAW_MEDADMIN_MED_NAME

D-06 requires using `RAW_MEDADMIN_MED_NAME` as fallback for MED_ADMIN records that cannot resolve via MEDICATION_LOOKUP or RxNorm cache. This requires changes to get_chemo_hits() or to R/26:

**Option 1:** Extend get_chemo_hits() to optionally return `raw_med_name` from `RAW_MEDADMIN_MED_NAME` (MED_ADMIN only, with `any_of()` guard as in R/109 lines 533-534). Callers (R/26 currently) add it as a fallback tier.

**Option 2:** Modify R/26's extract_chemo_dates_with_codes() MED_ADMIN block (lines 189-193) to additionally select RAW_MEDADMIN_MED_NAME before the get_chemo_hits() call, then join it back by (ID, treatment_date) after collection.

**Recommendation:** Option 1 is cleaner — extend get_chemo_hits() to accept `return_raw_name = FALSE` parameter. When TRUE, the return tibble gains an optional `raw_med_name` column. R/26 then adds a Tier 2.5: `coalesce(ref_drug_name, raw_med_name_canonical, rxnorm_drug_name)` where `raw_med_name_canonical = canonicalize_drug_name(toupper(trimws(raw_med_name)))`.

### canonicalize_drug_name() is the single choke point

`canonicalize_drug_name()` is defined in R/00_config.R at line 2413. It is vectorized, NA-safe, and case-insensitive. It is already applied to `MEDICATION_LOOKUP` values at load time (line 2423). The plan must ensure all raw strings (from RAW_MEDADMIN_MED_NAME) pass through `canonicalize_drug_name()` before reaching any output. Current gap: raw strings have never flowed into outputs before — this is new work.

### D-08 unmapped-name audit list

Pattern is R/79 (two-sheet xlsx: Summary + Detail). The unmapped-name audit list should capture:
- Raw name strings (from RAW_MEDADMIN_MED_NAME) that had no MEDICATION_LOOKUP hit, no canonicalize_drug_name alias match, and no RxNorm API result
- Format: code | raw_name | cleaned_name_in_output | source_table | n_episodes | n_patients

**Recommendation:** Embed this as a sheet in the D-02 before/after report (not a standalone file) to keep deliverables consolidated. Model on R/109's `add_styled_sheet()` pattern.

---

## Regimen Regeneration (D-09 / D-10-reg)

### Where regimen labels live

R/28 (lines 509–607): regimen detection applies to `treatment_type == "Chemotherapy"` episodes using `has_drug()` (substring match on `drug_names`) and `has_jcode()` (J-code fallback). Labels: `ABVD`, `BV+AVD` (≥2019-01-01), `Nivo+AVD` (≥2024-01-01), `NA` otherwise.

The new DISPENSING/MED_ADMIN records contribute to `drug_names` (via R/26 Section 5B), and those drug_names feed directly into `has_drug()` in R/28. No source-weighting or special handling is needed — D-10-reg is automatically satisfied as long as canonicalization is working (same drug name regardless of source).

### Prerequisite chain

treatment_episodes.rds must be freshly regenerated by R/26 before R/28 can update regimen labels. Phase 123 VERIFICATION confirmed that treatment_episodes.rds was ABSENT on HiPerGator at Phase 123 runtime — meaning Phase 123 never regenerated it. Phase 124 must run R/26 as Wave 1, then R/28 as Wave 2.

### Before/after regimen distribution

R/28 enriches treatment_episodes.rds in-place. The D-02 report needs to compare regimen_label distributions before and after. This requires snapshotting the pre-regeneration treatment_episodes.rds before Phase 124 runs R/26.

---

## Baseline Capture for D-02/D-03 Before/After Report

### Current state of output files

On the Windows checkout:
- `output/gantt_episodes.csv`, `output/gantt_detail.csv`, `output/gantt_lifespan.csv`, `output/gantt_entire_history.csv` — committed and present locally
- `cache/outputs/` directory — EMPTY on Windows (all RDS caches live only on HiPerGator)

### Git commit history of the Phase 122 fix

The Phase 122 consumer patch was committed as `07184cd feat(122-02): patch cohort/episode/timing/payer consumers to use get_chemo_hits`. The current gantt CSVs in the repo were committed BEFORE that patch — they reflect the pre-fix PRESCRIBING-only detection. This means the committed gantt CSVs are a valid "before" baseline for output-level metrics.

On HiPerGator, however, the `.rds` caches may be stale from even earlier runs. The safest approach:

**Recommended D-03 approach:** Before running R/26 on HiPerGator in Wave 1:
1. Copy the current HiPerGator `cache/outputs/treatment_episodes.rds` to `cache/outputs/treatment_episodes_pre_p124.rds` (on HiPerGator, no git needed).
2. The gantt CSVs committed to git serve as "before" baselines for Gantt-level metrics (since they predate Phase 122's regeneration).
3. The D-02 report script reads both pre- and post-regeneration artifacts side-by-side.

This avoids a separate "snapshot" script and uses HiPerGator's existing file system. The plan instructions for HiPerGator runtime should include an explicit `file.copy(src, dst)` before any regeneration.

---

## Common Pitfalls

### Pitfall 1: Immuno branches in R/26 and R/26 (D-12 guard)
**What goes wrong:** R/26 `extract_immunotherapy_dates_with_codes()` lines 360-378 still uses `"RXNORM_CUI" %in% colnames(get_pcornet_table("DISPENSING"))` guard — intentionally left broken for immunotherapy. Any refactoring of the MED_ADMIN/DISPENSING extraction pattern must not touch these branches.
**How to avoid:** Scope all chemo-specific changes to `extract_chemo_dates_with_codes()` (lines 129-205) only. The immunotherapy function at lines 320-399 must remain unchanged.

### Pitfall 2: R/28 code_type/source_table lookup gap
**What goes wrong:** After regenerating treatment_episodes.rds, R/28's `load_xlsx_lookups()` will label DISPENSING and MED_ADMIN-sourced RxCUIs as `source_table = "PRESCRIBING"` because `chemo_rxnorm` codes map to "PRESCRIBING" in `utils_xlsx_lookups.R` line 80.
**How to avoid:** Implement Option A (source_table_hint in R/26) before running R/28. Failure to do this means the D-05 requirement (DISPENSING/MED_ADMIN as distinct Source Table values) is silently unmet in gantt_episodes.csv.

### Pitfall 3: ENCOUNTERID = NA_character_ for DISPENSING/MED_ADMIN rows
**What goes wrong:** R/26 lines 185-193 set `ENCOUNTERID = NA_character_` for DISPENSING and MED_ADMIN hits (DISPENSING may lack ENCOUNTERID in this extract, per Phase 122 Plan 01 decisions). R/28's encounter-level cancer linkage (step 4a-4c) will then route ALL DISPENSING/MED_ADMIN episodes to the temporal fallback path (R/28 line 211). This is by design — document explicitly in the plan.
**Warning sign:** If suddenly all DISPENSING/MED_ADMIN episodes get `cancer_link_method = "temporal"`, that is expected and correct.

### Pitfall 4: R/56 consumes fully-enriched treatment_episodes.rds
**What goes wrong:** R/56 reads `treatment_episodes.rds` (line visible in its inputs header) which must include `cancer_category`, `drug_group`, `encounter_ids`, `triggering_codes`. Running R/56 before R/28 or R/29 complete their in-place enrichment will produce drug grouping tables without regimen/cancer labels.
**How to avoid:** R/56 must run after R/29 completes.

### Pitfall 5: R/76 is self-contained (re-extracts from DuckDB)
**What goes wrong:** R/76 does NOT read treatment_episodes.rds — it re-extracts dates from DuckDB. It already calls `get_chemo_hits()` (Phase 122 patch verified). Running R/76 post-fix is sufficient; no prerequisite RDS files needed.
**Why it matters:** This means R/76 can run in parallel with R/26 (independent inputs).

### Pitfall 6: R/25 sources R/26 indirectly — don't double-source
**What goes wrong:** R/26 begins with `source("R/25_treatment_durations.R")` to import `assign_episode_ids()` and `stack_and_dedup()`. When running R/39, R/25 runs first (line 146) and R/26 runs second (line 147). R/26's source() call re-runs all of R/25 again. This is existing behavior — the plan must not add another explicit R/25 run step; just run R/26.

### Pitfall 7: treatment_episodes.rds absent on HiPerGator (Phase 123 precedent)
**What goes wrong:** Phase 123 VERIFICATION confirmed `treatment_episodes.rds` was absent on HiPerGator at runtime (guarded skip at D-06). This means R/52, R/28, R/29, R/56 will all fail unless R/26 runs successfully first.
**Cache path:** `cache/outputs/treatment_episodes.rds` is the canonical path (CONFIG$cache$outputs_dir + "treatment_episodes.rds").

### Pitfall 8: R/20 MED_ADMIN code_type mislabeled
**What goes wrong:** R/20 lines 228-236 assign `code_type = "RXNORM"` to ALL MED_ADMIN codes regardless of MEDADMIN_TYPE. ND-typed rows (NDC codes) should be `code_type = "NDC"`. This is a pre-existing quirk — the plan should note whether to fix it.
**Scope decision:** Fix within Phase 124 scope (chemo only) since R/20 is an in-scope script. The fix is a one-line case_when in the MA block.

---

## Code Examples

### get_chemo_hits() return contract (utils_treatment.R lines 149-246)

```r
# Returns: tibble(ID, treatment_date, triggering_code) with distinct rows
# ENCOUNTERID intentionally omitted (callers add NA_character_ if needed)
# For DISPENSING: triggering_code = rxcui (resolved from NDC via crosswalk)
# For MED_ADMIN-RX: triggering_code = MEDADMIN_CODE (already an RxCUI)
# For MED_ADMIN-ND: triggering_code = rxcui (resolved from NDC via crosswalk)
```

### R/26 chemo source stack (lines 182-205) — current state

```r
# Source #5 DISPENSING (Phase 122 wired):
disp_dates <- get_chemo_hits("DISPENSING", TREATMENT_CODES$chemo_rxnorm, ndc_crosswalk)
if (!is.null(disp_dates)) {
  disp_dates <- disp_dates %>% mutate(ENCOUNTERID = NA_character_)
}
# Source #6 MED_ADMIN (Phase 122 wired):
ma_dates <- get_chemo_hits("MED_ADMIN", TREATMENT_CODES$chemo_rxnorm, ndc_crosswalk)
if (!is.null(ma_dates)) {
  ma_dates <- ma_dates %>% mutate(ENCOUNTERID = NA_character_)
}
# Stack with list names DISP and MA (important for source_table_hint approach)
stack_and_dedup_with_codes(
  sources = list(PX=px_dates, RX=rx_dates, DX=dx_dates,
                 DRG=drg_dates, DISP=disp_dates, MA=ma_dates),
  type_name = "Chemotherapy"
)
```

### R/28 xlsx_lookups source_table gap (utils_xlsx_lookups.R line 80)

```r
# CURRENT — maps ALL chemo_rxnorm codes to PRESCRIBING:
chemo_rxnorm = "PRESCRIBING",

# NEEDED for D-05: source_table must reflect actual table (DISPENSING or MED_ADMIN)
# This lookup is code-keyed, not (code, source)-keyed — cannot distinguish by code alone
# → source_table_hint column in treatment_episodes.rds is the correct fix
```

### canonicalize_drug_name() usage (R/00_config.R lines 2413-2419)

```r
canonicalize_drug_name <- function(x) {
  key <- tolower(stringr::str_trim(x))
  hit <- DRUG_NAME_ALIASES[key]
  out <- ifelse(!is.na(hit), unname(hit), x)
  out[is.na(x)] <- NA_character_
  out
}
# Applied to all raw strings: canonicalize_drug_name(toupper(trimws(raw_med_name)))
```

### R/109 styled xlsx pattern (confirmed by Phase 123 VERIFICATION)

The D-02 report should use `add_styled_sheet()` with the R/51-verbatim styling constants:
- Header fill: `FF374151` (dark slate)
- Header font: `FFFFFFFF` (white)
- Body text: `FF1F2937` (dark)
- Subtitle/meta: `FF6B7280` (gray)

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Drug name normalization | Custom string matching | `canonicalize_drug_name()` + `MEDICATION_LOOKUP` | Phase 114 centralized this; re-implementing risks inconsistency |
| NDC resolution | Custom NDC→name lookup | `ndc_rxnorm_crosswalk.rds` + `load_ndc_crosswalk()` | Already built by Phase 122 R/108 |
| Styled xlsx output | openxlsx2 raw calls | `add_styled_sheet()` helper from R/109 or R/51 pattern | Established convention; HIPAA suppression already wired |
| Episode aggregation | Custom episode logic | `assign_episode_ids()` from R/25 | Used by R/26; must stay consistent |
| Chemo detection | Re-implementing column access | `get_chemo_hits()` from utils_treatment.R | Phase 122 established this as the single correct path |

---

## Open Questions

1. **D-04: Code Type value for DISPENSING hits — "NDC" or "RXNORM"?**
   - What we know: `get_chemo_hits()` returns the resolved `rxcui` as `triggering_code` for DISPENSING, not the raw NDC. So the stored code is a RxNorm CUI.
   - What's unclear: D-04 says "NDC for DISPENSING." Does this mean the `code_type` column should say "NDC" (labeling the original match method), or should the stored code itself be the original NDC?
   - Recommendation: Label `code_type = "NDC"` for DISPENSING and MED_ADMIN-ND to indicate the matching code type, even though the stored triggering_code is a resolved RxCUI. This is the most informative for auditing. If the planner wants the raw NDC shown, get_chemo_hits() must be extended to return it.

2. **Source_table_hint approach vs. schema extension to treatment_episodes.rds**
   - What we know: The episodes RDS currently has no source_table column for the source TABLE (only `source_table` via R/28's xlsx_lookup which is wrong for new sources).
   - What's unclear: Whether adding `source_table_hint` as a new column in R/26 breaks any downstream assertion (`stopifnot` in R/28 line 832 checks a specific set of columns but does not prohibit extra columns).
   - Recommendation: Add the column — R/28's `stopifnot` only checks that required columns ARE present, not that no extras exist.

3. **Before-baseline validity on HiPerGator**
   - What we know: The committed gantt CSVs predate Phase 122 regeneration. The HiPerGator RDS cache provenance is unknown (Phase 123 VERIFICATION confirmed treatment_episodes.rds was ABSENT at run time, so no stale post-fix file exists to worry about).
   - What's unclear: Whether any other output files (e.g., source_coverage_analysis.xlsx) were regenerated on HiPerGator after Phase 122 and before Phase 124. Safely: snapshot everything before starting Wave 1.

4. **R/20 MED_ADMIN code_type fix — in scope?**
   - R/20 is explicitly in-scope (D-10). The `code_type = "RXNORM"` assignment for all MED_ADMIN rows (line 236) is wrong for ND-typed rows. A `mutate(code_type = ifelse(MEDADMIN_TYPE == "ND", "NDC", "RXNORM"))` fix is small and appropriate.
   - Recommendation: Include as a sub-task in the R/20 regeneration wave.

5. **D-02 report script number and R/39 registration**
   - Next sequential R/1xx number: R/109 exists, R/110 is free.
   - The D-02 report is a deliverable comparable to R/109 (post-fix diff + styled xlsx). R/109 is SCRIPT_INDEX-only (not in R/39). The same pattern applies here — register in SCRIPT_INDEX, add a Section 15v smoke test in R/88 (continuing the 15t → 15u → 15v sequence), but do NOT wire into R/39 (it is a one-off analysis script, not part of the routine pipeline).

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Rscript | Full pipeline runs | ✗ (Windows) | — | HiPerGator only |
| R/utils/utils_treatment.R + get_chemo_hits() | All consumers | ✓ | Phase 122 (committed) | — |
| data/reference/ndc_rxnorm_crosswalk.rds | get_chemo_hits DISPENSING/MED_ADMIN-ND | ✗ (Windows — HiPerGator only) | Built by R/108 | load_ndc_crosswalk() degrades gracefully |
| cache/outputs/treatment_episodes.rds | R/28, R/29, R/52, R/56 | ✗ (empty on Windows; must be regenerated on HiPerGator) | — | Must run R/26 first |
| output/gantt_episodes.csv (pre-fix) | D-02 "before" baseline | ✓ (committed to git) | Pre-Phase-122 | — |

**Missing dependencies with no fallback (block execution on HiPerGator):**
- treatment_episodes.rds absent → R/28, R/29, R/52, R/56 will fail; fix = run R/26 first

**Windows structural verification (no Rscript):**
- All plan tasks that modify R source files are structurally verifiable via grep on Windows
- Runtime confirmation (actual output file sizes, row counts) requires HiPerGator checkpoint
- Pattern: grep-based structural PASS on Windows → HiPerGator runtime checkpoint → paste-back confirmation

---

## Project Constraints (from CLAUDE.md)

- Runtime: RStudio on HiPerGator (production); Windows RStudio for local fixture testing only (no Rscript on Windows executor)
- R packages: tidyverse, vroom, ggalluvial, scales, janitor, glue — no data.table for new code EXCEPT where already established (R/28 already uses data.table for metadata_agg — keep)
- Code style: named predicate functions (`has_*`, `with_*`, `exclude_*`); no opaque one-liners
- Payer fidelity: Must match Python pipeline's 9-category payer mapping
- HIPAA: counts 1-10 suppressed in all Amy-facing outputs
- DuckDB self-bootstrap: `USE_DUCKDB <- TRUE; if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()` — standard per R/27, R/28, R/29, etc.
- GSD workflow enforcement: changes only via GSD commands

---

## Sources

### Primary (HIGH confidence)
- Verified by direct file reads of all in-scope R scripts (2026-07-14)
- `R/utils/utils_treatment.R` — get_chemo_hits() full contract, lines 149-246
- `R/utils/utils_xlsx_lookups.R` — source_table_map, lines 77-109 (gap confirmed)
- `R/26_treatment_episodes.R` — chemo extraction chain, lines 129-205, 671-734
- `R/28_episode_classification.R` — metadata_agg, lines 510-607; regimen detection; final column order
- `R/29_first_line_and_death_analysis.R` — is_first_line flag; reads/writes treatment_episodes.rds
- `R/52_gantt_v2_export.R` — EPISODES_SCHEMA (20 cols), DETAIL_SCHEMA (14 cols), lines 144-165
- `R/39_run_all_investigations.R` — full run order, lines 136-165, 176-197
- `R/11_treatment_payer.R` — compute_payer_at_chemo, already uses get_chemo_hits lines 184-198
- `R/00_config.R` — MEDICATION_LOOKUP (lines 2295-2365), DRUG_NAME_ALIASES (2368-2407), canonicalize_drug_name (2413-2419)
- `R/109_med_admin_dispensing_fix_impact_audit.R` — R/51-verbatim styling constants, xlsx delivery pattern
- `.planning/phases/122-*/122-VERIFICATION.md` — confirmed all 7 consumers patched, runtime numbers
- `.planning/phases/123-*/123-VERIFICATION.md` — treatment_episodes.rds absent on HiPerGator at Phase 123; +1,328 patients / +13,762 dates confirmed

### Secondary (MEDIUM confidence)
- `R/101_gantt_lifespan_collapse.R` header — confirmed input is gantt_episodes.csv (R/52 output)
- `R/104_gantt_entire_history.R` header — confirmed inputs are gantt_lifespan.csv + gantt_episodes.csv
- `R/20_treatment_inventory.R` lines 201-240 — DISPENSING NDC block + MED_ADMIN RXNORM/NDC blocks
- `R/56_new_tables_from_groupings.R` header — confirmed reads treatment_episodes.rds
- `R/88_smoke_test_comprehensive.R` summary section — 15t = Phase 122, 15u = Phase 123; next is 15v

---

## Metadata

**Confidence breakdown:**
- Consumer dependency graph: HIGH — verified by reading all in-scope scripts
- source_table gap finding: HIGH — confirmed by reading utils_xlsx_lookups.R lines 77-110 and cross-referencing with R/28 lines 510-585
- Drug normalization chain: HIGH — verified R/26 Section 5B and R/00_config.R canonicalize_drug_name
- Before/after baseline: HIGH — git log confirms gantt CSVs predate Phase 122; HiPerGator RDS state verified by Phase 123 VERIFICATION
- Gantt code_type/source_table extension: MEDIUM — Option A (source_table_hint) is recommended but exact implementation requires planner decision
- R/101/R/104 ordering in R/39: MEDIUM — inferred from investigation_scripts position vs export_scripts position; confirmed R/101 consumes gantt_episodes.csv which R/52 produces

**Research date:** 2026-07-14
**Valid until:** 2026-08-14 (stable pipeline, no expected upstream changes)
