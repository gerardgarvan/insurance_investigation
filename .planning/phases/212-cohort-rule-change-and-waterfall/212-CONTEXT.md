# Phase 212: Cohort Rule Change and Waterfall - Context

**Gathered:** 2026-11-17 (headless, non-interactive)
**Source:** Gerard's run message, ROADMAP v3.15 Phase 212, REQUIREMENTS COHORT-01..04, 201-01-SUMMARY.md (D-201-04), R/47, R/193, utils_cancer.R

## Authorization
- Gerard explicitly authorizes changing cohort membership and the 7-day confirmation logic in v3.15. This overrides the v3.14 headless rule for this phase only. D-201-04 (121 TR-HL patients missing) is in scope here.

## Phase boundary
- Cohort membership rule lives in `R/47_cancer_summary_refined.R` Section 4 (writes `output/confirmed_hl_cohort.rds`, 3 cols: ID, first_hl_dx_date, first_hl_dx_source). Old rule: >=2 distinct HL (C81/201.x) DX_DATEs with max-min >= 7 days.
- New rule: (A) >=2 HL dx on distinct ENCOUNTERIDs AND distinct dates; (B) plus every TR-HL patient (any TUMOR_REGISTRY_ALL SOURCE: UFH, ORL, TMH); (C) minus TR-NHL patients who are not also TR-HL.
- Out of scope: downstream chain rerun and R/88 (Phase 213); treatment capture; rds schema (stays 3 cols).

## Known counts (201-01-SUMMARY / STATE)
- tr_present 863; tr_hl_dx 600; tr_nhl_dx 154; both 11; 121 TR-HL patients not in current confirmed cohort.
- Unlisted lymphoid ICD-O-3 codes 9590-9999 (in neither hl nor nhl list): 21 codes (D-201-03 list in STATE.md).

## Decisions (defaults, headless; FLAG FOR USER REVIEW)
- **D-212-01 (open Q1):** TR-HL forced includes need no minimum EHR presence beyond appearing in DEMOGRAPHIC/ENCOUNTER. Report how many TR-HL included patients have 0 ENCOUNTER rows, and how many TR-HL IDs are absent from DEMOGRAPHIC.
- **D-212-02 (open Q2):** TR-NHL = existing `tr_nhl_dx` (`ICD_CODES$nhl_histology`; D-201-03/D-05 "unverified" caveat kept). The 21 unlisted lymphoid codes neither include nor exclude; report them (code + n, <11 suppressed).
- **D-212-03:** Both TR-HL and TR-NHL (11) -> included (spec: "unless also TR-HL").
- **D-212-04:** TR-NHL exclusion also removes patients who meet rule A if TR-NHL and not TR-HL.
- **D-212-05:** HL dx rows with NA ENCOUNTERID cannot count as a distinct encounter; dropped from rule A. Report patients whose qualification would change if NA ids were counted.
- **D-212-06:** Site = DEMOGRAPHIC `SOURCE` (probed in 184 schema). TR SOURCE (UFH/ORL/TMH) reported separately for TR rows.
- **D-212-07:** Waterfall steps are sequential, each patient counted once: old cohort -> lost by 2-encounter rule (old members failing A, not TR-HL) -> gained by dropping 7-day (A and not old) -> gained by TR-HL (TR-HL, not in old, not in A) -> lost by TR-NHL exclusion -> new cohort. Must reconcile to the new total.
- **D-212-08:** first_hl_dx_date for TR-HL-only patients comes from the existing TR DATE_OF_DIAGNOSIS logic in R/47 Section 5; patients with no date stay in the cohort with NA date (reported).
- **D-212-09:** Rule is applied in R/47 only. R/212 is a read-only dry run first (no write) so counts are reviewed before R/47 overwrites the rds.

## Backup
- Before any write: copy `output/confirmed_hl_cohort.rds` to `output/internal/pre_v315_backup/confirmed_hl_cohort_pre212_<YYYYMMDD_HHMMSS>.rds`; stop if the copy fails or sizes differ. Never staged in git.

## Schema probe rule
- No probe lists DIAGNOSIS ENCOUNTERID, ENCOUNTER columns or TUMOR_REGISTRY_ALL histology columns for this phase, so plan 01 is a HiPerGator probe; code constants come only from that file. Already probed: DEMOGRAPHIC `ID`, `SOURCE` (184 schema); TUMOR_REGISTRY_ALL `ID`, `SOURCE` (202 schema).

## Consumers to review in Phase 213 (not changed here)
- R/142, R/208, R/31, R/32, R/34, R/48, R/52, R/53, R/59, R/177, R/39, R/49, R/77 read `confirmed_hl_cohort.rds`. R/115 and R/142 Sec 2B cite "7-day confirmed" wording. New TR-HL-only patients have no rows in R/45 `cancer_summary.csv`.

## Assumptions (headless run)
- Planner and checker agents not spawned; plans checked by hand against the four success criteria.
