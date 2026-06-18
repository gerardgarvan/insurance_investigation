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

1. Execute Phase 109: `/gsd:execute-phase 109`

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
