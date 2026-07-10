# Roadmap: v3.2 Meeting Gap Resolution Report

**Milestone:** v3.2 Meeting Gap Resolution Report
**Goal:** Create investigation scripts for all remaining meeting note gaps (G4, G5, G8, G10, G11, secondary malignancy, TABLE 1/2) and compile findings into an RMarkdown report for team presentation.
**Created:** 2026-06-15
**Status:** Not started

**Previous milestone context:** v3.1 (Phases 100-103) closed analytical gaps with CONDITION table linkage, broadened drug grouping, co-administration analysis, and death date cross-tabs.

## Phases

- [x] **Phase 104: Treatment Timing Investigations** - Flag pre-diagnosis treatments and build secondary malignancy table with 7-day gap criterion (completed 2026-06-15)
- [x] **Phase 105: Code & Overlap Verification** - Verify Ethna/transplant/SCT code classifications and validate HL+NHL dual-code patients (completed 2026-06-15)
- [x] **Phase 106: Tableau-Ready Data Tables** - Produce encounter-level cancer codes and chemo drug class tables for Tableau import (completed 2026-06-15)
- [x] **Phase 107: Gap Resolution Report & Delivery** - Compile all findings into RMarkdown report, generate delivery manifest, update meeting notes (completed 2026-06-15)

## Phase Details

### Phase 104: Treatment Timing Investigations
**Goal**: User can identify and quantify treatments that occurred before HL diagnosis and review secondary malignancy patterns across the cohort
**Depends on**: Nothing (first phase in v3.2)
**Requirements**: TIMING-01, TIMING-02
**Success Criteria** (what must be TRUE):
  1. User can run a script and see a count of treatment episodes (by type: chemo, radiation, SCT, immunotherapy, proton) that occurred before the patient's first confirmed HL diagnosis date
  2. User can review flagged pre-diagnosis treatment episodes with patient IDs and dates for clinical plausibility review
  3. User can run a script and see a secondary malignancy table where diagnoses are separated by a 7-day gap criterion, with population-based columns (K-N) denominated on column E population (E3 per meeting notes)
  4. User can run R/88 smoke test and see structural validation passing for both new scripts
**Plans:** 1/1 plans complete

Plans:
- [x] 104-01-PLAN.md -- Pre-diagnosis treatment flagging (R/31), secondary malignancy table (R/32), R/88 smoke test updates

### Phase 105: Code & Overlap Verification
**Goal**: User can confirm or correct three code classification concerns and assess HL+NHL dual-code data quality
**Depends on**: Nothing (independent investigations)
**Requirements**: CODE-01, CODE-02, CODE-03, OVERLAP-01
**Success Criteria** (what must be TRUE):
  1. User can run a script and see whether "Ethna" appears in current immunotherapy code mappings, with a clear recommendation to correct or confirm classification
  2. User can run a script and see whether the organ transplant code (line 11 of all_codes_resolved) is appropriately included in SCT code mappings, with patient data cross-check
  3. User can run a script and see SCT codes above line 22 validated against actual patient data, with zero-usage and suspicious-usage codes flagged
  4. User can run a script and see a focused HL+NHL dual-code validation report showing patient-level detail for the ~4,000/8,000 dual-code patients with data quality assessment
  5. User can run R/88 smoke test and see structural validation passing for all four investigation scripts
**Plans:** 1/1 plans complete

Plans:
- [x] 105-01-PLAN.md -- Code verification (R/33: CODE-01/02/03), HL+NHL overlap validation (R/34: OVERLAP-01), R/88 smoke test updates

### Phase 106: Tableau-Ready Data Tables
**Goal**: Amy can import two xlsx tables into Tableau for interactive exploration of cancer codes and chemo drug classifications per encounter
**Depends on**: Nothing (independent of investigations; uses existing pipeline outputs)
**Requirements**: TABLE-01, TABLE-02
**Success Criteria** (what must be TRUE):
  1. User can open TABLE 1 xlsx and see each encounter ID mapped to all associated cancer diagnosis codes (comma-separated), with one row per encounter suitable for Tableau import
  2. User can open TABLE 2 xlsx and see chemotherapy drugs organized by class/category with associated cancer codes per encounter, suitable for Tableau import
  3. Both tables open cleanly in Excel and Tableau without formatting issues or truncated columns
**Plans:** 1/1 plans complete

Plans:
- [x] 106-01-PLAN.md -- Tableau-ready tables script (R/36: TABLE-01, TABLE-02) and R/88 smoke test updates

### Phase 107: Gap Resolution Report & Delivery
**Goal**: Team can review a single compiled report of all v3.2 investigation findings and user can package all deliverables for Amy
**Depends on**: Phase 104, Phase 105, Phase 106 (compiles findings from all investigation phases)
**Requirements**: REPORT-01, REPORT-02, REPORT-03
**Success Criteria** (what must be TRUE):
  1. User can render an RMarkdown file to self-contained HTML that includes tables and summaries from all gap investigations (G4, G5, G8, G10, G11, secondary malignancy)
  2. User can run a manifest script and see a listing of all output files created/updated in v3.1 and v3.2 with descriptions, ready for packaging to Amy
  3. User can open pecan_lymphoma_meeting_notes_combined.md and see resolved gaps marked with resolution notes and stale items removed
  4. User can share the HTML report in a team meeting without additional preparation (self-contained, labeled, formatted)
**Plans:** 2/2 plans complete

Plans:
- [x] 107-01-PLAN.md -- RMarkdown gap resolution report (R/37) and delivery manifest script (R/38)
- [x] 107-02-PLAN.md -- Meeting notes update with gap resolutions and R/88 smoke test validation for Phase 107

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 104. Treatment Timing Investigations | 1/1 | Complete    | 2026-06-15 |
| 105. Code & Overlap Verification | 1/1 | Complete    | 2026-06-15 |
| 106. Tableau-Ready Data Tables | 1/1 | Complete    | 2026-06-15 |
| 107. Gap Resolution Report & Delivery | 2/2 | Complete   | 2026-06-15 |

## Next Steps

1. Execute Phase 119: `/gsd:execute-phase 119`

## Coverage

**v3.2 Requirements:** 11 total
- TIMING: 2 requirements -> Phase 104
- CODE: 3 requirements -> Phase 105
- OVERLAP: 1 requirement -> Phase 105
- TABLE: 2 requirements -> Phase 106
- REPORT: 3 requirements -> Phase 107

**Coverage:** 11/11 requirements mapped (100%)

### Phase 108: Fix warnings that are in warnings.txt

**Goal:** Pipeline produces zero warnings on a successful run by resolving all 14 warnings in warnings.txt -- safe wrappers for min() on all-NA groups, removal of benign connection/empty-result warnings, filename mapping fixes, sentinel date coercion, and TABLE-2 sanity check correction
**Requirements**: WARN-01, WARN-02, WARN-03, WARN-04, WARN-05, WARN-06
**Depends on:** Phase 107
**Plans:** 2/2 plans complete

Plans:
- [x] 108-01-PLAN.md -- Add min_or_na()/max_or_na() safe wrappers, remove benign warnings, fix filename mappings, add pre-1900 date coercion, widen date range
- [x] 108-02-PLAN.md -- Replace min(na.rm=TRUE) with min_or_na() across R/02, R/11, R/13 and fix TABLE-2 vs TABLE-1 sanity check in R/36

### Phase 109: Fix co-administration analysis: remove ICD9 codes that blur single-agent detection and switch grouping from encounter to date

**Goal:** Co-administration analysis produces clean date-grain results by filtering out non-specific ICD9 procedure codes that blur single-agent detection and switching from encounter-level to date-level grouping so the analysis reflects identifiable agents on clinical dates rather than billing artifacts
**Requirements**: COADMIN-FIX-01, COADMIN-FIX-02, COADMIN-FIX-03
**Depends on:** Phase 108
**Plans:** 1/1 plans complete

Plans:
- [x] 109-01-PLAN.md -- ICD9 code filtering, date-grain single-agent detection and temporal self-join, R/88 smoke test update

### Phase 110: Redo cancer_summary_table_pre_post_v2_7day.xlsx with Confirmed HL 7-Day Gap patients only

**Goal:** V2 cancer summary table restricted to patients with HL-specific 7-day gap confirmation and secondary malignancies in K-L-M columns also individually 7-day confirmed, replacing the current any-code 7-day filter with stricter HL-only criteria
**Requirements**: V2FIX-01, V2FIX-02, V2FIX-03
**Depends on:** Phase 109
**Plans:** 1/1 plans complete

Plans:
- [x] 110-01-PLAN.md -- Tighten R/49 V2 population filter to HL-specific 7-day confirmed, update assertions/metadata/titles, update R/88 smoke test

### Phase 111: For chemo_drugs_by_class.xlsx combine agents by date per ID, collapse agents into one string for each date

**Goal:** TABLE-2 (chemo_drugs_by_class.xlsx) collapsed from per-encounter+medication grain to per-patient+date grain, combining all chemo agent names on each date into a single comma-separated string with merged cancer codes
**Requirements**: T2COLLAPSE-01, T2COLLAPSE-02
**Depends on:** Phase 110
**Plans:** 1/1 plans complete

Plans:
- [x] 111-01-PLAN.md -- Collapse R/36 TABLE-2 to per-patient+date grain with agents string, update R/88 smoke test for new column structure

### Phase 112: Add cancer diagnosis temporally to Gantt data, i.e., which cancer diagnoses did they have in that period. Also ensure abbreviated lists that condense multiple encounters are listed alphabetically so for example b,a,c would always be captured as a,b,c

**Goal:** Gantt episode data enriched with temporal cancer diagnosis context (all diagnoses within +/-30 days of episode span) and universal ascending alphabetical sort enforced across all multi-value fields in the Gantt export pipeline and TABLE-2
**Requirements**: GANTT-DX-01, GANTT-DX-02, SORT-01, SORT-02, SMOKE-112-01
**Depends on:** Phase 111
**Plans:** 1/1 plans complete

Plans:
- [x] 112-01-PLAN.md -- Temporal diagnosis enrichment in R/28, Gantt export schema update in R/52 with sort fix, descending sort fix in R/36 and R/57, R/88 smoke test validation

### Phase 113: Investigate encounters after death date -- quantify how far after death the ~200 patients encounters occur

**Goal:** User can run R/51 and see a meeting-ready two-sheet xlsx quantifying temporal gaps (in days) between death dates and all post-death clinical activity (encounters, diagnoses, treatments) for ~200 flagged patients, with clinically meaningful bucket distribution and per-event detail
**Requirements**: POSTDEATH-01, POSTDEATH-02, POSTDEATH-03
**Depends on:** Phase 112
**Plans:** 1/1 plans complete

Plans:
- [x] 113-01-PLAN.md -- Post-death encounter investigation script (R/51), R/88 smoke test section, R/39 pipeline runner entry

### Phase 114: Investigate blank drug names and make drug_names/triggering_code_descriptions consistent with treatment reference excel

**Goal:** Pipeline drug_names and triggering_code_descriptions use the canonical treatment reference Excel as authoritative source, with blank drug_names filled from the Medication column and inconsistent code descriptions overridden, producing a standalone audit xlsx documenting all remediation
**Requirements**: DRUGFIX-01, DRUGFIX-02, DRUGFIX-03, DRUGFIX-04, DRUGFIX-05
**Depends on:** Phase 113
**Plans:** 2/2 plans complete

Plans:
- [x] 114-01-PLAN.md -- Add MEDICATION_LOOKUP to R/00_config.R, fill blank drug_names in R/26, add reference Excel as 5th source in R/42
- [x] 114-02-PLAN.md -- Standalone audit script (R/79), R/88 smoke test section, R/39 pipeline runner entry

### Phase 115: Add 7-day confirmed column to Gantt data which indicates if on the patient level the episode_dx_categories is also in the patients unique 7-day

**Goal:** Gantt episodes CSV enriched with two new columns: (1) episode_dx_7day_confirmed showing which episode dx categories are 7-day confirmed at the patient level, and (2) age_at_episode showing integer age at episode start from DEMOGRAPHIC birth date
**Requirements**: GANTT7DAY-01, GANTT7DAY-02, GANTAGE-01, SMOKE-115-01
**Depends on:** Phase 114
**Plans:** 1/1 plans complete

Plans:
- [x] 115-01-PLAN.md -- Add episode_dx_7day_confirmed and age_at_episode to R/52 Gantt export, R/88 smoke test validation

### Phase 116: address info like ruca using r pacakge like rural

**Goal:** HL cohort enriched with USDA 2020 ZIP RUCA rurality classification derived from DEMOGRAPHIC.ZIP_CODE, producing a standalone 4-sheet styled xlsx (patient-level rurality frequency + encounter-level cross-tabs with AMC 8-category payer / 5-category treatment type / classify_codes cancer category), with the USDA reference file bundled in `data/reference/` for offline reproducibility
**Requirements**: RUCA-01, RUCA-02, RUCA-03, RUCA-04, RUCA-05, RUCA-06, SMOKE-116-01
**Depends on:** Phase 115
**Plans:** 2/2 plans complete

Plans:
- [ ] 116-01-PLAN.md -- Bundle USDA 2020 ZIP RUCA reference xlsx (data/reference/) and create standalone script R/100_ruca_rurality_summary.R with 4-sheet styled xlsx output
- [x] 116-02-PLAN.md -- R/88 smoke test section (Phase 116 structural validation), R/39 pipeline runner entry for R/100, R/SCRIPT_INDEX.md Post-Renumber Investigations section (completed 2026-07-06)

### Phase 117: make a lifespan gannt that collapses across all time but still keeps treatment type etc sepearate

**Goal:** A new "lifespan" Gantt CSV (`output/gantt_lifespan.csv`) collapses the per-episode Gantt export into one row per patient_id x treatment_type, spanning each patient's earliest episode_start to latest episode_stop (calendar dates preserved, not normalized). Multi-value metadata is unioned/deduped/sorted (reusing R/52 `clean_multi_value`), Death and HL Diagnosis pseudo-rows excluded, produced by a new standalone script R/101 registered in R/39, smoke-tested in R/88, and indexed in R/SCRIPT_INDEX.md
**Requirements**: LIFESPAN-01, LIFESPAN-02, LIFESPAN-03, LIFESPAN-04, SMOKE-117-01
**Depends on:** Phase 116
**Plans:** 1/1 plans complete

Plans:
- [x] 117-01-PLAN.md -- Create R/101_gantt_lifespan_collapse.R (collapse gantt_episodes.csv to patient x treatment_type lifespan CSV) + register in R/39, R/88 Section 15n, R/SCRIPT_INDEX.md

### Phase 118: create csv that outputs PATID and a column where cause of death is non-hodgkins lymphoma true or cause of death is non-hodgkins lymphoma false

**Goal:** A new standalone script `R/102_death_cause_nhl_flag.R` writes `output/death_cause_nhl_flag.csv` — one row per deceased patient (valid DEATH_DATE in the DuckDB DEATH table, 1900 sentinel handled, aggregated to earliest death per patient) with `PATID` and a THREE-STATE `cause_of_death_is_nhl` column: TRUE when DEATH_CAUSE classifies as Non-Hodgkin Lymphoma via `classify_codes()` (ICD-10 C82-C86/C88, ICD-9 200/202; not C81/C91/C96), FALSE when DEATH_CAUSE is a different coded cause, and blank when DEATH_CAUSE is missing/uncoded (`write.csv(na="")`). Registered in R/39, smoke-tested in R/88 Section 15o, indexed in R/SCRIPT_INDEX.md.
**Requirements**: NHLDEATH-01, NHLDEATH-02, NHLDEATH-03, SMOKE-118-01
**Depends on:** Phase 117
**Plans:** 1/1 plans complete

Plans:
- [x] 118-01-PLAN.md -- Create R/102_death_cause_nhl_flag.R (deceased-only three-state NHL cause-of-death flag CSV) + register in R/39, R/88 Section 15o, R/SCRIPT_INDEX.md

### Phase 119: fix death_cause_nhl_flag

**Goal:** `output/death_cause_nhl_flag.csv` carries REAL TRUE/FALSE values (not 100% blank) by sourcing cause of death from the separate PCORnet CDM `DEATH_CAUSE` table instead of the non-existent `DEATH.DEATH_CAUSE` column. Investigate-first: a read-only HiPerGator diagnostic (R/103) inventories every candidate cause-of-death source (DEATH_CAUSE table, TUMOR_REGISTRY1.CAUSE_OF_DEATH, TR2/TR3.DCAUSE) restricted to the ~1,344 deceased patients and gates implementation. Then the `DEATH_CAUSE` table is loaded via the 5-touch-point recipe (PCORNET_TABLES + col spec + DuckDB ingest + R/88 table count 15->16), R/102 is rewritten to read the underlying cause (DEATH_CAUSE_TYPE == "U" preferred) and classify via `classify_codes() == "Non-Hodgkin Lymphoma"`, preserving the exact three-state output contract (PATID + cause_of_death_is_nhl, `write.csv(row.names=FALSE, na="")`). A labeled diagnosis-history proxy backstop (D-05) is included but off by default; R/35's identical stale assumption is corrected/annotated. Registered in R/39, validated by R/88 Section 15p, indexed in R/SCRIPT_INDEX.md.
**Requirements**: NHLFIX-01, NHLFIX-02, NHLFIX-03, NHLFIX-04, NHLFIX-05, SMOKE-119-01
**Depends on:** Phase 118
**Plans:** 4/4 plans complete

Plans:
- [x] 119-01-PLAN.md -- R/103 read-only HiPerGator diagnostic: cause-of-death signal inventory over the deceased set (gates implementation)
- [x] 119-02-PLAN.md -- Load DEATH_CAUSE table (PCORNET_TABLES + DEATH_CAUSE_SPEC + R/88 table count 15->16)
- [x] 119-03-PLAN.md -- Rewrite R/102 to source cause from DEATH_CAUSE table (underlying-cause preferred) + proxy backstop; correct/annotate R/35
- [x] 119-04-PLAN.md -- Register R/103 in R/39, R/88 Section 15p structural validation, R/SCRIPT_INDEX.md updates
