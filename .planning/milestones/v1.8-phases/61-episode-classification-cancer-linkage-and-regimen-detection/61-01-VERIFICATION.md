---
phase: 61-episode-classification-cancer-linkage-and-regimen-detection
verified: 2026-05-30T23:45:00Z
status: gaps_found
score: 1/11 must-haves verified
re_verification: false
gaps:
  - truth: "Each treatment episode has a cancer_category derived from encounter-level DIAGNOSIS, not patient-level"
    status: failed
    reason: "Script created but never executed — treatment_episodes.rds not enriched with cancer_category column"
    artifacts:
      - path: "cache/outputs/treatment_episodes.rds"
        issue: "File exists but does not contain cancer_category, cancer_link_method, is_hodgkin, or regimen_label columns (Phase 61 script was never run)"
    missing:
      - "Execute R/61_episode_classification.R to enrich treatment_episodes.rds"
      - "Verify treatment_episodes.rds contains 4 new columns after execution"
  - truth: "Episodes with ENCOUNTERID match get cancer_link_method='encounter_id'"
    status: failed
    reason: "cancer_link_method column does not exist — script not executed"
    artifacts:
      - path: "cache/outputs/treatment_episodes.rds"
        issue: "Column not present in RDS"
    missing:
      - "Execute R/61_episode_classification.R"
  - truth: "Episodes without ENCOUNTERID match but with diagnosis within 30 days get cancer_link_method='closest_date'"
    status: failed
    reason: "cancer_link_method column does not exist — script not executed"
    artifacts:
      - path: "cache/outputs/treatment_episodes.rds"
        issue: "Column not present in RDS"
    missing:
      - "Execute R/61_episode_classification.R"
  - truth: "Episodes with neither match get cancer_link_method='none' and cancer_category=NA"
    status: failed
    reason: "cancer_link_method and cancer_category columns do not exist — script not executed"
    artifacts:
      - path: "cache/outputs/treatment_episodes.rds"
        issue: "Columns not present in RDS"
    missing:
      - "Execute R/61_episode_classification.R"
  - truth: "is_hodgkin is TRUE only when cancer_category equals 'Hodgkin Lymphoma'"
    status: failed
    reason: "is_hodgkin column does not exist — script not executed"
    artifacts:
      - path: "cache/outputs/treatment_episodes.rds"
        issue: "Column not present in RDS"
    missing:
      - "Execute R/61_episode_classification.R"
  - truth: "Chemotherapy episodes containing doxorubicin+bleomycin+vinblastine+dacarbazine get regimen_label='ABVD'"
    status: failed
    reason: "regimen_label column does not exist — script not executed"
    artifacts:
      - path: "cache/outputs/treatment_episodes.rds"
        issue: "Column not present in RDS"
    missing:
      - "Execute R/61_episode_classification.R"
  - truth: "AVD variant (doxorubicin+vinblastine+dacarbazine, no bleomycin) also gets regimen_label='ABVD'"
    status: failed
    reason: "regimen_label column does not exist — script not executed"
    artifacts:
      - path: "cache/outputs/treatment_episodes.rds"
        issue: "Column not present in RDS"
    missing:
      - "Execute R/61_episode_classification.R"
  - truth: "ABVD + any extra chemo agent gets regimen_label=NA (added-agent disqualification)"
    status: failed
    reason: "regimen_label column does not exist — script not executed"
    artifacts:
      - path: "cache/outputs/treatment_episodes.rds"
        issue: "Column not present in RDS"
    missing:
      - "Execute R/61_episode_classification.R"
  - truth: "BV+AVD only assigned for episodes starting on or after 2019-01-01"
    status: failed
    reason: "regimen_label column does not exist — script not executed"
    artifacts:
      - path: "cache/outputs/treatment_episodes.rds"
        issue: "Column not present in RDS"
    missing:
      - "Execute R/61_episode_classification.R"
  - truth: "Nivo+AVD only assigned for episodes starting on or after 2024-01-01"
    status: failed
    reason: "regimen_label column does not exist — script not executed"
    artifacts:
      - path: "cache/outputs/treatment_episodes.rds"
        issue: "Column not present in RDS"
    missing:
      - "Execute R/61_episode_classification.R"
  - truth: "R/62 runs without 'regimen_label column not found' warning after Phase 61"
    status: failed
    reason: "R/62 will trigger warning guard because regimen_label column does not exist in treatment_episodes.rds"
    artifacts:
      - path: "cache/outputs/treatment_episodes.rds"
        issue: "Missing regimen_label column triggers downstream warning"
      - path: "R/62_first_line_and_death_analysis.R"
        issue: "Lines 78-82 guard will activate: 'regimen_label column not found — Phase 61 not yet run'"
    missing:
      - "Execute R/61_episode_classification.R to populate regimen_label"
---

# Phase 61: Episode Classification - Cancer Linkage & Regimen Detection Verification Report

**Phase Goal:** Classify treatment episodes by linking cancer diagnoses at encounter level (not patient level) and detecting specific first-line regimens through 28-day cycle matching with dropped-agent tolerance.

**Verified:** 2026-05-30T23:45:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                           | Status     | Evidence                                                                                                           |
| --- | ----------------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------ |
| 1   | Each treatment episode has a cancer_category derived from encounter-level DIAGNOSIS            | ✗ FAILED   | Script exists but never executed — RDS not enriched                                                                |
| 2   | Episodes with ENCOUNTERID match get cancer_link_method='encounter_id'                          | ✗ FAILED   | cancer_link_method column does not exist in RDS                                                                    |
| 3   | Episodes without ENCOUNTERID match but within 30 days get cancer_link_method='closest_date'    | ✗ FAILED   | cancer_link_method column does not exist in RDS                                                                    |
| 4   | Episodes with neither match get cancer_link_method='none' and cancer_category=NA               | ✗ FAILED   | cancer_link_method and cancer_category columns do not exist in RDS                                                 |
| 5   | is_hodgkin is TRUE only when cancer_category equals 'Hodgkin Lymphoma'                         | ✗ FAILED   | is_hodgkin column does not exist in RDS                                                                            |
| 6   | Chemotherapy episodes containing doxorubicin+bleomycin+vinblastine+dacarbazine get regimen_label='ABVD' | ✗ FAILED   | regimen_label column does not exist in RDS                                                                         |
| 7   | AVD variant (dox+vin+dac, no bleo) also gets regimen_label='ABVD'                              | ✗ FAILED   | regimen_label column does not exist in RDS                                                                         |
| 8   | ABVD + any extra chemo agent gets regimen_label=NA                                             | ✗ FAILED   | regimen_label column does not exist in RDS                                                                         |
| 9   | BV+AVD only assigned for episodes starting on or after 2019-01-01                              | ✗ FAILED   | regimen_label column does not exist in RDS                                                                         |
| 10  | Nivo+AVD only assigned for episodes starting on or after 2024-01-01                            | ✗ FAILED   | regimen_label column does not exist in RDS                                                                         |
| 11  | R/62 runs without 'regimen_label column not found' warning after Phase 61                      | ✗ FAILED   | R/62 lines 78-82 guard will trigger warning because regimen_label column missing                                   |

**Score:** 1/11 truths verified (only script creation verified, not execution)

### Required Artifacts

| Artifact                                        | Expected                                                          | Status      | Details                                                                                                   |
| ----------------------------------------------- | ----------------------------------------------------------------- | ----------- | --------------------------------------------------------------------------------------------------------- |
| `R/61_episode_classification.R`                 | Standalone episode classification script (200+ lines)             | ✓ VERIFIED  | File exists, 789 lines, contains all required logic (PREFIX_MAP, cancer linkage, regimen detection)       |
| `cache/outputs/treatment_episodes.rds`          | Enriched with 4 columns (cancer_category, cancer_link_method, is_hodgkin, regimen_label) | ✗ STUB      | RDS file exists but does NOT contain the 4 new columns — script was never executed to enrich it           |
| `output/episode_classification_audit.xlsx`      | Multi-sheet audit workbook                                        | ✗ MISSING   | File does not exist — script not executed                                                                 |
| `output/episode_classification_audit.csv`       | Flat CSV export of episode classification results                 | ✗ MISSING   | File does not exist — script not executed                                                                 |

### Key Link Verification

| From                                    | To                                            | Via                                             | Status      | Details                                                                                           |
| --------------------------------------- | --------------------------------------------- | ----------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------- |
| R/61_episode_classification.R           | cache/outputs/treatment_episodes.rds          | readRDS + saveRDS in-place enrichment           | ✗ NOT_WIRED | Script contains `readRDS(OUTPUT_RDS)` and `saveRDS(episodes, OUTPUT_RDS)` but never executed      |
| R/61_episode_classification.R           | cache/outputs/treatment_episode_detail.rds    | readRDS for encounter_ids per episode           | ✗ NOT_WIRED | Script contains `readRDS(DETAIL_RDS)` but never executed                                          |
| R/61_episode_classification.R           | DuckDB DIAGNOSIS table                        | get_pcornet_table('DIAGNOSIS')                  | ✗ NOT_WIRED | Script contains `get_pcornet_table("DIAGNOSIS")` but never executed                               |
| R/62_first_line_and_death_analysis.R    | treatment_episodes.rds regimen_label column   | Consumes regimen_label for first-line detection | ✗ NOT_WIRED | R/62 lines 78-82 guard will activate because regimen_label column missing from RDS                |

### Data-Flow Trace (Level 4)

**Not applicable** — Phase 61 script was never executed, so no data flows to trace. The script contains the correct logic to populate `cancer_category`, `cancer_link_method`, `is_hodgkin`, and `regimen_label` columns, but these columns do not exist in the actual RDS file because the script was never run.

### Behavioral Spot-Checks

**Skipped** — Cannot run spot-checks on non-existent output. The script would need to be executed first to produce the enriched RDS and audit outputs.

### Requirements Coverage

| Requirement | Source Plan | Description                                                                                                       | Status     | Evidence                                                                                           |
| ----------- | ----------- | ----------------------------------------------------------------------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------- |
| LINK-01     | 61-01       | Cancer diagnosis linked to treatment episodes via ENCOUNTERID (direct match)                                     | ✗ BLOCKED  | Script contains ENCOUNTERID match logic (lines 397-415) but never executed                         |
| LINK-02     | 61-01       | Temporal proximity fallback when ENCOUNTERID is NULL or missing (closest diagnosis within window)                | ✗ BLOCKED  | Script contains 30-day temporal fallback logic (lines 417-447) but never executed                  |
| LINK-03     | 61-01       | HL flag derived from encounter-level diagnosis, not patient-level                                                 | ✗ BLOCKED  | Script contains `is_hodgkin = (!is.na(cancer_category) & cancer_category == "Hodgkin Lymphoma")` (line 456) but never executed |
| LINK-04     | 61-01       | Second cancer confirmation requires 2+ diagnoses 7 days apart (encounter-level)                                  | ✗ BLOCKED  | Script contains 7-day confirmation logic (lines 462-483) for audit sheet but never executed        |
| REG-01      | 61-01       | Treatment episodes labeled with regimen name (ABVD, BV+AVD, Nivo+AVD) based on drug composition                  | ✗ BLOCKED  | Script contains case_when regimen classification (lines 519-543) but never executed                |
| REG-02      | 61-01       | Dropped-agent tolerance — ABVD with bleomycin dropped (→AVD) still classified as first-line                      | ✗ BLOCKED  | Script contains AVD variant logic (line 536: has_dox & has_vin & has_dac & !has_bleo) but never executed |
| REG-03      | 61-01       | Nothing added — ABVD+X is not ABVD                                                                                | ✗ BLOCKED  | Script contains added-agent disqualification via n_unique_drugs checks (lines 532, 536) but never executed |
| REG-04      | 61-01       | Temporal availability rules — BV+AVD post-2019, Nivo+AVD post-2024                                               | ✗ BLOCKED  | Script contains temporal guards (lines 524-525: >= 2019-01-01, lines 527-528: >= 2024-01-01) but never executed |

**Orphaned requirements:** None — all 8 requirements map to this phase.

### Anti-Patterns Found

| File                              | Line | Pattern                                                    | Severity   | Impact                                                                                                      |
| --------------------------------- | ---- | ---------------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------- |
| R/61_episode_classification.R     | N/A  | Script created but never executed                          | 🛑 Blocker | Phase goal unmet — RDS not enriched, downstream Phase 62 cannot proceed with first-line therapy analysis    |
| cache/outputs/treatment_episodes.rds | N/A  | File exists but missing 4 required columns                 | 🛑 Blocker | Script execution required to add cancer_category, cancer_link_method, is_hodgkin, regimen_label             |
| output/episode_classification_audit.xlsx | N/A  | Output file does not exist                                  | 🛑 Blocker | No audit trail for linkage methods or regimen distribution                                                  |
| output/episode_classification_audit.csv  | N/A  | Output file does not exist                                  | 🛑 Blocker | No flat CSV export for downstream analysis                                                                  |

### Human Verification Required

**Not applicable** — Cannot perform human verification on non-existent outputs. Once the script is executed and outputs are produced, the following human checks would be needed:

1. **Test:** Open episode_classification_audit.xlsx and review "Linkage Summary" sheet. Check that percentages of encounter_id, closest_date, and none linkage methods sum to 100%.
   **Expected:** Linkage method distribution is reasonable (majority via encounter_id or closest_date, small percentage unlinked).
   **Why human:** Requires clinical judgment to assess if linkage method distribution is plausible given data quality.

2. **Test:** Review "Regimen Distribution" sheet. Check that ABVD count is non-zero and BV+AVD/Nivo+AVD counts align with temporal availability rules.
   **Expected:** ABVD episodes exist across all years; BV+AVD only post-2019; Nivo+AVD only post-2024 (if any).
   **Why human:** Requires understanding of regimen adoption timelines and clinical plausibility.

3. **Test:** Review "Unlinked Episodes" sheet. Assess whether unlinked episodes are expected (e.g., historical treatments, missing diagnosis records).
   **Expected:** Unlinked episodes are explainable (e.g., historical_flag=TRUE, treatment dates outside diagnosis window).
   **Why human:** Requires clinical context to determine if unlinked episodes indicate data quality issues or expected gaps.

### Gaps Summary

**ROOT CAUSE:** R/61_episode_classification.R was created and committed (commit b8805cd) but **never executed**. The SUMMARY.md claims "treatment_episodes.rds enriched with 4 new columns" but this is FALSE — the RDS file exists with its prior schema (from Phase 60) but does NOT contain the 4 new columns that Phase 61 was supposed to add.

**IMPACT:**
- Phase 61 goal FAILED — episode classification did not occur
- All 11 observable truths FAILED — no columns exist to verify
- All 8 requirements BLOCKED — logic exists in script but was never applied to data
- Downstream Phase 62 BLOCKED — R/62 lines 78-82 guard will trigger warning: "regimen_label column not found — Phase 61 not yet run. First-line detection will produce 0 results."

**WHAT'S MISSING:**
1. Execute `Rscript R/61_episode_classification.R` to enrich treatment_episodes.rds
2. Verify enriched RDS contains 15 columns (original 11 + 4 new: cancer_category, cancer_link_method, is_hodgkin, regimen_label)
3. Verify episode_classification_audit.xlsx exists with 5 sheets
4. Verify episode_classification_audit.csv exists with all episodes

**CODE QUALITY:** The R/61 script itself is **well-written and complete**. It contains:
- ✓ Full PREFIX_MAP (337 lines, copied from R/49)
- ✓ Correct cancer linkage logic (ENCOUNTERID match + 30-day temporal fallback)
- ✓ Correct regimen detection logic (ABVD/BV+AVD/Nivo+AVD with temporal guards)
- ✓ Proper deduplication (slice(1) after arrange by HL preference)
- ✓ Empty string guards (filter(!is.na(encounter_ids_list) & encounter_ids_list != ""))
- ✓ Added-agent disqualification via n_unique_drugs checks
- ✓ Multi-sheet audit workbook with styled headers
- ✓ All 18 decision points (D-01 through D-18) traceable in code

The script is **ready to execute** — it just hasn't been run yet.

---

**Verified:** 2026-05-30T23:45:00Z
**Verifier:** Claude (gsd-verifier)
**Next Action:** Execute R/61_episode_classification.R and re-verify to close gaps.
