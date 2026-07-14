---
gsd_state_version: 1.0
milestone: v3.2
milestone_name: milestone
status: verifying
stopped_at: Phase 123 context gathered
last_updated: "2026-07-14T17:52:24.321Z"
last_activity: 2026-07-14
progress:
  total_phases: 20
  completed_phases: 19
  total_plans: 29
  completed_plans: 29
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-12)

**Core value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

**Current focus:** Phase 122 — med-admin-dispensing-gap-diagnostic-csv-gap-closure

## Current Position

Phase: 122
Plan: Not started
Status: Phase complete — ready for verification
Last activity: 2026-07-14

## Performance Metrics

**Milestone velocity:**

- v3.1: 4 phases (100-103) completed in 1 day (2026-06-12)
- v3.0: 5 phases (95-99) completed in 3 days (2026-06-09 to 2026-06-11)
- v2.3: 4 phases completed in 2 days

**Planning efficiency:**

- Average plans per phase: 1.0
- Average tasks per plan: 3.0
- Phase 104: 6 minutes (2 tasks)
- Phase 105: 6 minutes (3 tasks)
- Phase 106: 5 minutes (2 tasks)
- Phase 115: 6 minutes (2 tasks)
- Phase 116 Plan 01: 18 minutes (2 tasks)
- Phase 116 Plan 02: 12 minutes (3 tasks)
- Phase 117 Plan 01: 3 minutes (2 tasks)

## Accumulated Context

### Recent Decisions

**Phase 122 Plan 02 decisions:**

- R/20 DISPENSING collapsed from two blocks (RXNORM+NDC) to single NDC block with drug_name=NA_character_; RXNORM block referenced absent RXNORM_CUI+RAW_DISPENSE_MED_NAME columns
- R/27 MED_ADMIN ND-typed path emits raw NDC (not resolved RxCUI), consistent with DISPENSING harvest; code_type=NDC for both
- ndc_crosswalk_fn2 variable name used in R/11 fn2 scope to avoid collision with fn1 binding
- IS_LOCAL runtime check in Section 15t uses exists() guard for helpers; degrades gracefully if helpers not yet loaded in smoke-test scope

**Phase 122 Plan 01 decisions:**

- get_chemo_hits() ENCOUNTERID omitted from return; callers add it if source has it (Open Question 1 from RESEARCH.md resolved by omission; DISPENSING may lack ENCOUNTERID in this extract)
- ndc_rxnorm_crosswalk.rds deferred to HiPerGator (no R binary on Windows executor); synthetic mapping: NDC 00069306030 -> CUI 3639 (Doxorubicin); create with saveRDS(setNames("3639","00069306030"), here::here("data","reference","ndc_rxnorm_crosswalk.rds"))
- Synthetic NDC 00069306030 used in both MED_ADMIN ND fixture row and DISPENSING fixture hit row — single consistent synthetic crosswalk entry covers both NDC paths locally

**Phase 120 Plan 02 decisions:**

- R/105 registered as the new final comma-less R/39 investigation_scripts entry (R/104 gains a trailing comma); vector stays parse-safe (19 entries, exactly 1 comma-less)
- R/88 Section 15r (14 structural checks, continuing 15q -> 15r) inserted after the Section 15q R/104 else-branch and before Section 15g; SMOKE-120-01 summary line added after SMOKE-i1e-01
- SCRIPT_INDEX: R/105 row added to Post-Renumber Investigations (100+) table; 100+ count 5 -> 6, Total 91 -> 92
- Rule 3 fix: Section 15r Check 13 grep adapted to R/105's ACTUAL assertion forms (`N_SUPCARE_ROWS` 171L constant + `ncol(sc) != 7`) instead of the plan's literal `== 171`/`== 7` (which return 0 in R/105), preserving the round-trip-verify intent (2nd wb_load + row + col asserts)
- Runtime (Rscript parse + 15r PASS) deferred to an R-capable host (Rscript not installed on this Windows executor); verified structurally via grep + state-machine paren balance

**Phase 120 Plan 01 decisions:**

- R/105 three-step RxNav IN resolver (related.json?tty=IN -> historystatus -> canonicalize_drug_name fallback) appends non-blank Normalized Meaning col G to the 171-row Supportive Care tab in place; combos kept as sorted /-joined labels; 21 supportive-care brand->generic aliases added to DRUG_NAME_ALIASES

**Phase 119 Plan 04 decisions:**

- R/103 registered in R/39 BEFORE R/102 (diagnostic-before-fix ordering); R/102 retained as the final comma-less investigation_scripts entry so the vector parses
- R/88 Section 15p (continuing 15m/15n/15o -> 15p): positive `get_pcornet_table("DEATH_CAUSE")` check + negative `!grepl('DEATH_CAUSE = all_of(death_cause_col)')` check prove the source switch both ways; guard requires R/102 AND R/103; else-branch registers SKIPPED FALSE for an honest total; Check 13 self-reads R/88 for `length(tables_found) == 16`; Check 14 IS_LOCAL-gated runtime (non-zero TRUE/FALSE) stays green locally
- SCRIPT_INDEX: R/103 row added (phase 119, read-only inventory); R/102 phase column set to `118, 119` with source-correction note; post-renumber (100+) count 3 -> 4

**Phase 119 Plan 03 decisions:**

- R/102 sources cause of death from the DEATH_CAUSE table (underlying-cause preferred via type_rank U=1/C=2/other=3, arrange + first()) joined onto the DEATH-derived deceased set; DEATH table now used only for the deceased set (ID + earliest DEATH_DATE)
- Three-state case_when (TRUE=NHL / FALSE=other coded / NA=uncoded) and exact PATID/flag output contract (transmute + write.csv row.names=FALSE na="") kept verbatim
- Labeled off-by-default PROXY BACKSTOP (D-05, USED_PROXY_BACKSTOP flag) gated on n_coded==0 falls back to NHL-in-DIAGNOSIS-history (explicitly a proxy)
- classify_codes() reads raw DEATH_CAUSE value field, not DEATH_CAUSE_CODE (coding-system indicator)
- R/35 fully corrected (Option A): reads DEATH_CAUSE table + left_join onto deceased set; death_data shape unchanged so the 5-sheet xlsx logic is untouched
- Rule 1 auto-fix: proxy DIAGNOSIS join keyed on ID (not PATID), matching this extract's convention (RESEARCH Pitfall 4)

**Phase 119 Plan 02 decisions:**

- No PCORNET_PATHS override for DEATH_CAUSE: resolves via default {TABLE}_Mailhot_V1.csv pattern; Phase 119 comment flags the runtime unknown and points at the LAB_RESULT_CM override pattern if the HiPerGator filename differs
- R/03_duckdb_ingest.R unchanged: TABLES_TO_INGEST <- PCORNET_TABLES auto-includes DEATH_CAUSE; no ENCOUNTERID so TABLES_WITH_ENCOUNTERID unchanged
- DEATH_CAUSE_SPEC keys on ID (not PATID), matching the extract convention + the DEATH join key (RESEARCH Pitfall 4)
- R/88 IS_LOCAL fixture table-count 15 -> 16 with a note that the local fixture DuckDB must be rebuilt to include DEATH_CAUSE (RESEARCH Pitfall 6)

**Phase 119 Plan 01 decisions:**

- R/103 is a read-only Wave-0 gate: structurally verified locally (grep), RUN on HiPerGator by the user who pastes back which source is populated to select the R/102 rewrite source
- Probe DEATH_CAUSE CSV directly via file.path(CONFIG$data_dir, "DEATH_CAUSE_Mailhot_V1.csv") + file.exists() — PCORNET_PATHS$DEATH_CAUSE only exists after Plan 02
- get_pcornet_table("DEATH_CAUSE") == NULL treated as expected-before-Plan-02 (Source-1 counts = NA, no error)
- Deceased-set derivation copied verbatim from R/102 Section 4 so diagnostic set == eventual output set
- Underlying-cause-preferred one-per-ID (arrange DEATH_CAUSE_TYPE != "U" then first) instead of hard == "U" filter (RESEARCH Pitfall 2)
- NAACCR sentinels (0000 alive / 7777 cert-unavailable / 7797 uncoded) filtered before classify_codes()

**Phase 118 Plan 01 decisions:**

- Three-state flag (TRUE/FALSE/NA) preserved -- missing DEATH_CAUSE is NA not FALSE to avoid misrepresenting uncoded deaths (D-04)
- classify_codes() reused for NHL determination -- no hand-rolled ICD list (D-07)
- Only deceased patients included (valid DEATH_DATE) -- alive patients excluded entirely (D-02)
- DEATH_CAUSE field-availability guard degrades gracefully to all-NA when field absent (D-78-01)
- Section 15o used for Phase 118 smoke test (continuing 15n -> 15o sequence)

**Phase 117 Plan 01 decisions:**

- episode_length_days = span in days (max_stop - min_start), not total active days -- matches lifespan semantics (D-05)
- distinct_dates_in_episode = SUM of per-episode counts across merged episodes
- age_at_episode = patient age at the EARLIEST episode_start (which.min row within group)
- is_hodgkin re-derived from unioned cancer_category string (consistent with R/52 line 857)
- clean_multi_value() copied verbatim from R/52; union_field() helper pastes group values with ";" then calls clean_multi_value(sep_in=";") to handle already-semicolon-separated input
- Section 15n used for Phase 117 (continuing 15m -> 15n sequence)

**Phase 116 Plan 02 decisions:**

- R/88 checks 15/17 (add_worksheet count, freeze_pane count) adapted to accept add_styled_sheet >= 4 as alternative -- R/100 uses DRY add_styled_sheet() wrapper so primitives appear once inside helper, not 4+ times
- R/88 Phase 116 structural pass criterion on Windows local: all 22 checks pass in isolation; full R/88 runtime requires HiPerGator production data (stops at section 19/29 classify_codes gate)
- Used section suffix 15m for Phase 116 (skipping 15l per aesthetic guidance in plan)

**Phase 116 Plan 01 decisions:**

- Read RUCA xlsx with sheet='RUCA 2020 ZIP Code Data' and skip=1 (title row confirmed in Task 1 inspection)
- Use add_styled_sheet() helper to wrap openxlsx2 calls for DRY 5-sheet workbook
- Sheet 4 labeled episode-level (treatment_episodes.rds grain) not encounter-level per RESEARCH.md Open Question 4 recommendation
- PrimaryRUCA column read by name after skip=1

**v3.2 Roadmap decisions:**

- Phase numbering continues from Phase 103 (v3.1 last phase) -> v3.2 starts at Phase 104
- Granularity: coarse (4 phases for 11 requirements)
- CODE-01/02/03 (small verification scripts) combined with OVERLAP-01 into single Phase 105 for coarse grouping
- TIMING-01 + TIMING-02 grouped as Phase 104 (both are treatment/diagnosis timing investigations)
- TABLE-01 + TABLE-02 grouped as Phase 106 (both are Tableau-ready output tables)
- REPORT-01/02/03 must be last phase (Phase 107) since it compiles findings from all investigations
- Phases 104, 105, 106 are independent and can be executed in any order
- Phase 107 depends on all three preceding phases

**Phase 106 decisions:**

- Comma separator for cancer codes (meeting notes line 75, not semicolons like R/57)
- Separate xlsx per table (not combined workbook) for clearer Tableau import purpose
- One row per encounter+medication in TABLE-2 (no aggregation) for Tableau pivot flexibility

**v3.1 decisions (carried forward):**

- CONDITION table as 3rd-tier cancer linkage supplement (read-only investigation pattern)
- Broadened output = primary files; linked-only with _linked_only suffix
- data.table cartesian join for temporal self-join patterns
- Raw counts without HIPAA suppression for internal investigation scripts (manual suppression before sharing)

### Roadmap Evolution

**v3.2 Structure:**

- Phase 104: Treatment Timing Investigations (TIMING-01, TIMING-02)
- Phase 105: Code & Overlap Verification (CODE-01, CODE-02, CODE-03, OVERLAP-01)
- Phase 106: Tableau-Ready Data Tables (TABLE-01, TABLE-02)
- Phase 107: Gap Resolution Report & Delivery (REPORT-01, REPORT-02, REPORT-03)

**Coverage:** 11/11 v3.2 requirements mapped (100%)

- Phase 108 added: Fix warnings that are in warnings.txt
- Phase 109 added: Fix co-administration analysis: remove ICD9 codes that blur single-agent detection and switch grouping from encounter to date
- Phase 110 added: redo cancer_summary_table_pre_post_v2_7day.xlsx but have it so only Confirmed (7-Day Gap) HL pts are in it and rows k through l only have Confirmed (7-Day Gap) respective malignancies
- Phase 111 added: For chemo_drugs_by_class.xlsx combine agents by date per ID, collapse agents into one string for each date
- Phase 112 added: Add cancer diagnosis temporally to Gantt data and enforce alphabetical ordering in abbreviated/condensed lists
- Phase 113 added: Investigate encounters after death date — quantify how far after death the ~200 patients encounters occur
- Phase 114 added: Investigate blank drug names and make drug_names/triggering_code_descriptions consistent with treatment reference excel
- Phase 115 added: Add 7-day confirmed column to Gantt data which indicates if on the patient level the episode_dx_categories is also in the patients unique 7-day
- Phase 116 added: address info like ruca using r pacakge like rural (RUCA rurality enrichment, R/100) -- COMPLETE
- Phase 117 added: Make a lifespan Gantt that collapses across all time but still keeps treatment type etc separate -- COMPLETE
- Phase 118 added: Create CSV outputting PATID + boolean column for whether cause of death is non-Hodgkin lymphoma
- Phase 119 added: Fix death_cause_nhl_flag
- Phase 120 added: In all_codes_resolved_next_tables_v2.1 (tab: Supportive Care) normalize meaning into a new column to disambiguate dosage/spelling variants and generic names
- Phase 121 added: Investigate how often the 9-digit ZIP code changes at the individual level, to inform the decision on handling ZIP code data for socioeconomic indices
- Phase 122 added: med_admin_dispensing_gap_diagnostic.csv gap closure (fix the RXNORM_CUI-column mismatch so DISPENSING/MED_ADMIN chemo detection stops silently dropping — MED_ADMIN codes live in MEDADMIN_CODE where MEDADMIN_TYPE=='RX'; sized by R/107 diagnostic from quick task 260714-end) -- COMPLETE
- Phase 123 added: Quantify how much the Phase 122 MED_ADMIN/DISPENSING chemo-detection fix changes treatment outputs (before/after diff) and investigate whether unmatched NDCs (~7,739/24,327 no RxCUI in the Phase 122 crosswalk) are missing real chemo

### Open Questions

None currently identified.

### Active TODOs

- [x] Plan Phase 104 (Treatment Timing Investigations) - radiation before HL dx + secondary malignancy table
- [x] Plan Phase 105 (Code & Overlap Verification) - Ethna/transplant/SCT codes + HL+NHL overlap
- [x] Plan Phase 106 (Tableau-Ready Data Tables) - encounter-level cancer codes and chemo drugs
- [ ] Plan Phase 107 (Gap Resolution Report) - RMarkdown report + manifest + meeting notes update

### Known Blockers

None identified.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260709-gz2 | Fix R/88 Phase 115 Check 3 schema-count loop (comment ending in `)` stopped scan early → counted 18 not 20) | 2026-07-09 | ea5bae6 | [260709-gz2-fix-r-88-phase-115-check-3-schema-count-](./quick/260709-gz2-fix-r-88-phase-115-check-3-schema-count-/) |
| 260709-i1a | Clean drug_group in R/52 + R/101: dedup, sort, semicolon-separated, drop literal `NA` tokens (consistent with other multi-value columns) | 2026-07-09 | 513456d | [260709-i1a-clean-drug-group-in-r-52-and-r-101-dedup](./quick/260709-i1a-clean-drug-group-in-r-52-and-r-101-dedup/) |
| 260709-iyh | Drug-name canonicalization: DRUG_NAME_ALIASES + canonicalize_drug_name in R/00_config, applied to MEDICATION_LOOKUP + R/27; doxorubicin variants → "Doxorubicin Hydrochloride", liposomal kept separate | 2026-07-09 | 242c458 | [260709-iyh-add-drug-name-canonicalization-drug-name](./quick/260709-iyh-add-drug-name-canonicalization-drug-name/) |
| 260709-jhw | R/27 self-bootstraps DuckDB connection (USE_DUCKDB + open_pcornet_con at top, guarded) like R/28-R/36 — fixes "object 'pcornet_con' not found" on standalone runs | 2026-07-09 | d2afeb6 | [260709-jhw-make-r-27-self-bootstrap-duckdb-connecti](./quick/260709-jhw-make-r-27-self-bootstrap-duckdb-connecti/) |
| 260710-i1e | Create R/104_gantt_entire_history.R: 6-col projection of gantt_lifespan.csv with cancer_7day_confirmed re-derived from gantt_episodes.csv (non-fatal mismatch assertion), blank-safe read/write; registered in R/39, R/88 Section 15q (14 checks), SCRIPT_INDEX 100+ count 4->5 / Total 90->91 | 2026-07-10 | 0d48757 | [260710-i1e-create-r-104-gantt-entire-history-r-proj](./quick/260710-i1e-create-r-104-gantt-entire-history-r-proj/) |
| 260714-end | Create R/107 read-only diagnostic sizing chemo treatment-detection loss from DISPENSING/MED_ADMIN lacking RXNORM_CUI in this extract (MED_ADMIN codes live in MEDADMIN_CODE where MEDADMIN_TYPE=='RX'; DISPENSING has NDC only). Reports MED_ADMIN increment beyond PRESCRIBING baseline (new patients, new ID+date pairs, earlier-first-chemo shifts) + ND-crosswalk-needed volume + DISPENSING footprint. SCRIPT_INDEX row only (not wired into R/39/R/88); runtime deferred to HiPerGator | 2026-07-14 | cb1c892 | [260714-end-create-read-only-hipergator-diagnostic-q](./quick/260714-end-create-read-only-hipergator-diagnostic-q/) |
| Phase 118 P01 | 5 | 2 tasks | 4 files |
| Phase 119 P01 | 8min | 1 tasks | 1 files |
| Phase 119 P02 | 2min | 3 tasks | 3 files |
| Phase 119 P03 | 6min | 2 tasks | 2 files |
| Phase 119 P04 | 2min | 3 tasks | 3 files |
| Phase 120 P01 | 15min | 2 tasks | 2 files |
| Phase 120 P02 | 3min | 2 tasks | 3 files |
| Phase 121 P01 | 15 | 3 tasks | 4 files |
| Phase 122 P01 | 3 | 3 tasks | 4 files |
| Phase 122 P02 | 12 | 3 tasks | 9 files |
| Phase 122 P03 | 3 | 1 tasks | 1 files |

## Session Continuity

**Last command:** `/gsd:execute-phase` (2026-07-14)
**Stopped at:** Phase 123 context gathered
**What's next:** Execute Phase 122 Plan 03 (R/108 crosswalk build script + HiPerGator runtime verification)

### Recent Changes

- 2026-07-14: Phase 122 Plan 02 complete (all 7 chemo consumers patched to use get_chemo_hits; R/88 Section 15t 14-check smoke test; SCRIPT_INDEX 100+ 8->9, Total 94->95)
- 2026-07-10: Quick task 260710-i1e complete (R/104 gantt entire-history 6-col projection; cancer_7day_confirmed re-derived from episodes; R/39 registration; R/88 Section 15q 14-check smoke test; SCRIPT_INDEX 100+ 4->5, Total 90->91)
- 2026-07-09: Phase 118 Plan 01 complete (R/102 death cause NHL flag CSV script, R/88 Section 15o 14-check smoke test, R/39 registration, SCRIPT_INDEX row)
- 2026-07-09: Phase 117 Plan 01 complete (R/101 lifespan Gantt collapse script, R/88 Section 15n 14-check smoke test, R/39 registration, SCRIPT_INDEX row)
- 2026-07-06: Phase 116 Plan 02 complete (R/88 Section 15m 22-check smoke test, R/39 registration, SCRIPT_INDEX Post-Renumber Investigations section)
- 2026-07-06: Phase 116 Plan 01 complete (USDA RUCA reference bundled + R/100 rurality summary script created)
- 2026-06-29: Phase 115 complete (7-day confirmed column + age at episode in Gantt data)
- 2026-06-15: Phase 106 complete (Tableau-Ready Data Tables - TABLE-01/TABLE-02)
- 2026-06-15: Phase 105 complete (Code & Overlap Verification - CODE-01/02/03, OVERLAP-01)
- 2026-06-15: Phase 104 complete (Treatment Timing Investigations - TIMING-01/02)
- 2026-06-15: v3.2 roadmap created with 4 phases (104-107) covering 11 requirements
- 2026-06-12: v3.1 milestone completed (Phases 100-103, 4 phases, 9 requirements)

### Key Files Modified

**Phase 122 Plan 02:**

- Modified: R/10_cohort_predicates.R (has_chemo DISPENSING+MED_ADMIN use get_chemo_hits)
- Modified: R/26_treatment_episodes.R (chemo sources #5/#6 use get_chemo_hits; immuno untouched)
- Modified: R/25_treatment_durations.R (chemo DISPENSING+MED_ADMIN use get_chemo_hits)
- Modified: R/11_treatment_payer.R (fn1+fn2 DISPENSING+MED_ADMIN use get_chemo_hits)
- Modified: R/27_drug_name_resolution.R (DISPENSING emits raw NDC; MED_ADMIN uses MEDADMIN_CODE+TYPE)
- Modified: R/20_treatment_inventory.R (DISPENSING NDC block only; MED_ADMIN uses MEDADMIN_CODE+TYPE; tryCatch surfaces errors)
- Modified: R/76_treatment_source_coverage.R (DISPENSING+MED_ADMIN use get_chemo_hits)
- Modified: R/88_smoke_test_comprehensive.R (Section 15t added: 14 Phase 122 checks; SMOKE-122-01 summary line)
- Modified: R/SCRIPT_INDEX.md (R/108 row added; 100+ count 8->9; Total 94->95)
- Created: .planning/phases/122-med-admin-dispensing-gap-diagnostic-csv-gap-closure/122-02-SUMMARY.md

**Phase 118 Plan 01:**

- Created: R/102_death_cause_nhl_flag.R (226 lines, death cause NHL three-state flag CSV script)
- Modified: R/88_smoke_test_comprehensive.R (Section 15o added: 14 Phase 118 checks; summary: 4 NHLDEATH/SMOKE-118 messages)
- Modified: R/39_run_all_investigations.R (R/102 added to investigation_scripts vector)
- Modified: R/SCRIPT_INDEX.md (R/102 row added to Post-Renumber Investigations (100+) table)
- Created: .planning/phases/118-create-csv-that-outputs-patid-and-a-column-where-cause-of-death-is-non-hodgkins-lymphoma-true-or-cause-of-death-is-non-hodgkins-lymphoma-false/118-01-SUMMARY.md

**Phase 117 Plan 01:**

- Created: R/101_gantt_lifespan_collapse.R (314 lines, lifespan Gantt collapse script)
- Modified: R/88_smoke_test_comprehensive.R (Section 15n added: 14 Phase 117 checks; summary: 5 LIFESPAN/SMOKE-117 messages)
- Modified: R/39_run_all_investigations.R (R/101 added to investigation_scripts vector)
- Modified: R/SCRIPT_INDEX.md (R/101 row added to Post-Renumber Investigations (100+) table)
- Created: .planning/phases/117-make-a-lifespan-gannt-that-collapses-across-all-time-but-still-keeps-treatment-type-etc-sepearate/117-01-SUMMARY.md

**Phase 116 Plan 02:**

- Modified: R/88_smoke_test_comprehensive.R (Section 15m added: 22 Phase 116 checks; Section 16 summary: 7 new RUCA/SMOKE-116 messages)
- Modified: R/39_run_all_investigations.R (R/100 added to investigation_scripts vector)
- Modified: R/SCRIPT_INDEX.md (Post-Renumber Investigations (100+) section added)
- Created: .planning/phases/116-address-info-like-ruca-using-r-pacakge-like-rural/116-02-SUMMARY.md

**Phase 116 Plan 01:**

- Created: data/reference/RUCA-codes-2020-zipcode.xlsx (USDA 2020 ZIP RUCA reference, 1530 KB)
- Created: R/100_ruca_rurality_summary.R (441 lines, 5-sheet rurality summary xlsx)
- Created: .planning/phases/116-address-info-like-ruca-using-r-pacakge-like-rural/116-01-SUMMARY.md

### Outstanding Work

**Immediate (v3.2):**

- Phase 104: Treatment timing investigations (2 requirements) — COMPLETE
- Phase 105: Code & overlap verification (4 requirements) — COMPLETE
- Phase 106: Tableau-ready data tables (2 requirements) — COMPLETE
- Phase 107: Gap resolution report & delivery (3 requirements)

**Deferred from v3.0:**

- Phase 98 Plan 02: R/98 validation script and R/88 full smoke test (1 of 2 plans pending)

---
*State updated: 2026-07-09 after Phase 117 Plan 01 completion*
