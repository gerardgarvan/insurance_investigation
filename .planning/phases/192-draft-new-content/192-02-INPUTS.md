# 192-02 Inputs Sheet

Commit hash at execution time: 56db9ae
All values read from live files; no values copied from the plan text.

---

## A. OPEN and CONFIRMED D-191 rows (from AM-EVIDENCE-MAP.md AM-MAP-03, live file)

| Decision ID | Status | Map Row(s) | Decision Text (summary) | Verdict date |
|-------------|--------|------------|------------------------|--------------|
| D-191-01 | OPEN | S0-FM-04 | Claims listed as secondary source in manual; pipeline has no claims integration | not dated in AM-MAP-03 (raised by Phase 191 verification) |
| D-191-02 | OPEN | S4-CMNT-02 | TR-first step absent from get_hl_any_dx_ids(); pipeline anchor is DIAGNOSIS-only | not dated in AM-MAP-03 |
| D-191-03 | OPEN | S4-DXDT-03 | Same finding as D-191-02 for cleaning rules row | not dated in AM-MAP-03 |
| D-191-04 | OPEN | S4-DX-03 | 7-day rule scope ambiguity: cohort-entry (HL-only) vs categorization (all types) | not dated in AM-MAP-03 |
| D-191-05 | CONFIRMED | S4-INS-03 | Manual update only: update to reflect 8-category AMC framework; no code change. Amy/Gerard confirmed 05/01/2026. | 2026-05-01 (DEC-002 date; D-191-05 declared CONFIRMED in AM-MAP-03) |
| D-191-06 | OPEN | S4-DTH-03 | Grace_days 14 (manual) vs 30 (code) at all 5 production call sites | not dated in AM-MAP-03 |
| D-191-07 | OPEN | S4-DIST-03 | Distance method: manual states zipcodeR only; code uses three-tier method | not dated in AM-MAP-03 |
| D-191-08 | CONFIRMED | S4-DIST-06 | Distance cutoff resolved to 100 mi (DEC-008); manual update only | 2026-10-13 (DEC-008; Erin/Ray) |

Source: `.planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md` AM-MAP-03 table

---

## B. CONFIRMED D-191 rows — existing manual text to correct, verbatim

### D-191-05: Insurance (S4-INS-03)

Manual text to correct (verbatim from `docs/analytic_manual/AnalyticManual_2026.01.30.md`):

```
- Cleaning Rules Applied:

  - Insurance was harmonized across all visits on a given day for a
    given individual based on the following hierarchy:

    1.  If any encounters are coded as Medicaid (including 93 and 14),
        or if FLM is a source, then all encounters on that day are
        Medicaid.

    2.  If not, if any of them are coded as Medicare, then all
        encounters on that day are Medicare.

    3.  If not, if any of them are coded as Private, then all encounters
        on that day are Private. (This includes Tricare now.)

    4.  If not, if any of them are coded as Other, then all encounters
        on that day are Other.

    5.  If not, if any of them are coded as Self-pay or Uninsured, then
        all encounters on that day are Uninsured.

    6.  If not, that means all encounters should be coded as missing,
        and nothing needs to change.
```

Lines: approximately L152–L174 of `docs/analytic_manual/AnalyticManual_2026.01.30.md`

Decision relied on: D-191-05 (status CONFIRMED); underlying authority: DEC-002 (Amy; Gerard; 2026-05-01; `TeamMtgNotes2026.md` 05/1/2026)

Code evidence: `R/60_tiered_same_day_payer.R:228–299`; `R/00_config.R:AMC_PAYER_LOOKUP`; `R/00_config.R:TIER_MAPPING`

### D-191-08: Distance cutoff (S4-DIST-06)

Manual text to correct (verbatim from `docs/analytic_manual/AnalyticManual_2026.01.30.md`):

```
- Unresolved Issues:

  - Should consider binary option, in which case, what to use for
    cutoff? 120mi (two hours travel time) or 200mi? Potentially do
    sensitivity analysis or include both in MICE.
```

Lines: approximately L308–L312 of `docs/analytic_manual/AnalyticManual_2026.01.30.md`

Decision relied on: D-191-08 (status CONFIRMED); underlying authority: DEC-008 (Erin; Ray; 2026-10-13; `TeamMtgNotes2026.md` 10/13/2026)

Code evidence: `R/00_config.R:233` (`CONFIG$far_from_care_cutoff_mi <- 100`)

---

## C. Other OPEN AM-MAP-03 rows included in §8

| ID | Type | Item summary | Source record date |
|----|------|-------------|-------------------|
| DEC-001 (D-190-01) | OPEN-DEPENDENCY | Location of OneFLquestions document (c0 blocked) | 2026-10-27 |

Source: AM-MAP-03, AM-EVIDENCE-MAP.md line for DEC-001

---

## D. STATE.md parked items confirmed still OPEN

Parked items in `.planning/STATE.md` "Parked Items" section (read 2026-10-28):

| Item | Still open? | Notes |
|------|-------------|-------|
| End-of-treatment date rules (pending Sharon) | Yes — listed as "Parked Items (no phases this milestone)" | → OPEN-DEPENDENCY §8 |
| D-15 primary analysis and D-165-01 method confirmation (awaiting Amy/Erin) | Yes — listed in "Parked Items" | → OPEN-DEPENDENCY §8 |
| Data-completeness check vs Medicaid claims | Yes — listed in "Parked Items" | → OPEN-DEPENDENCY §8 |

D-165-01 also appears in "Open Team Decisions" in STATE.md. Confirmed: still open, not resolved in any phase.

---

## E. CONFIRMED team decisions for §3 (from AM-MAP-03, CONFIRMED rows only)

| Decision ID | Construct | Decision | Rationale | Decided by | Date | Map row(s) |
|-------------|-----------|----------|-----------|------------|------|------------|
| DEC-002 | Insurance harmonization hierarchy | 6-tier hierarchy (Medicaid incl. 93/14/FLM > Medicare > Private incl. Tricare > Other > Uninsured > Missing) confirmed | Amy confirmed hierarchy at 5/1/2026 quant meeting | Amy; Gerard | 2026-05-01 | S4-INS-03 |
| DEC-003 | Cancer diagnosis confirmation | Two separate encounters with same cancer type ≥7 days apart; applies to all cancer types | Team agreed rule; prevents incidental/coding errors from driving cohort | Amy; Ray; Gerard | 2026-05-29 | S4-DX-03 |
| DEC-004 | ADI: pop-weighted average | Use population-weighted average ADI of 5-digit ZIP when 9-digit unavailable | GG/AC met 8/25 and determined method | Amy; Gerard | 2026-08-25 | S4-ADI-04; S4-ADI-05 |
| DEC-005 | ADI: 5-digit → 9-digit extrapolation | If 5-digit ZIP in one encounter matches 9-digit in another, extrapolate | Team comfortable after confirming ZIPs are consistent longitudinally | Amy; Gerard | 2026-08-18 | S4-ADI-03 |
| DEC-006 | RUCA: 5-digit ZIP acceptable | RUCA rurality can use 5-digit ZIP code | Confirmed by team | Amy; Gerard | 2026-08-25 | S4-RUR-01 |
| DEC-007 | Relapse vs refractory definition | Relapse = change in tx regimen with 90+ day break; refractory = <90-day break | Decided to treat as two separate concepts | Amy; Ray; Erin | 2026-09-11 | S4-REL-03 |
| DEC-008 | Distance cutoff: 100 miles | 100 miles based on doi.org/10.1182/blood-2023-182477 | Published literature reference | Erin; Ray | 2026-10-13 | S4-DIST-06 |
| DEC-009 | NHL-only episode exclusion | Patients with multiple lines of tx clearly NHL only removed from dataset | Err on side of accuracy for study scope | Amy; Erin; Ray | 2026-09-22 | S2-COH-02; S4-CLS-01 |
| DEC-010 | Uncertain HL inclusion | Err on side of including patients who may not be a true HL if not definite | Conservative inclusion | Amy; Erin; Ray | 2026-09-22 | S4-DX-02; S4-CLS-01 |
| DEC-011 | Brand→generic drug names | Convert all brand names to generic (adriamycin → doxorubicin) | Consistency; completed per 10/13/2026 meeting | Amy; Gerard | 2026-10-13 | S4-NRM-01 |
| DEC-012 | Remove diagnosis table from survivorship codes | Remove diagnosis table data from surveillance modality codes for survivorship care | Completed per 10/13/2026 meeting | Amy; Gerard | 2026-10-13 | S4-SRV-03 |

Source: AM-MAP-03 table, AM-EVIDENCE-MAP.md

Exclusions from §3 (per D-15): D-191-05 and D-191-08 are CONFIRMED but are updates to existing decisions (DEC-002, DEC-008) — they are not separate original team decisions. D-190-01 is OPEN. Unattributed candidates are excluded.

---

## F. Map IDs available by section (from AM-EVIDENCE-MAP.md ID Registry)

### S0 Front Matter
- S0-FM-01 through S0-FM-09 (all allocated 2026-10-27)
- No new IDs needed: all FM fields map to existing IDs

### S1 Data Ingest (and A1)
- S1-LOG-01 (table row unit); SA1-LOG-01 (appendix mirror)
- Status in map: EMPTY-REPO-CAN-ANSWER (S1-LOG-01), OUT-OF-SCOPE (SA1-LOG-01)
- No new IDs needed for individual event rows: all rows share S1-LOG-01 / SA1-LOG-01 at table level

### S2 Cohort (and A2)
- S2-COH-01 (Inclusion), S2-COH-02 (Exclusion), S2-COH-03 (Index Date), S2-COH-04 (Obs Window), S2-COH-05 (Historical table); SA2-COH-01 (appendix)
- No new IDs needed

### S3 Decision Log (and A3)
- S3-DEC-01; SA3-DEC-01 (appendix)
- No new IDs needed (all rows share the table-level ID)

### S5 EHR vs Claims
- S5-REC-01 through S5-REC-05 (all OUT-OF-SCOPE or EMPTY-NEEDS-TEAM in map)
- No new IDs needed

### S6 QA
- S6-QA-01 through S6-QA-07 (all OUT-OF-SCOPE in map)
- No new IDs needed

### S7 Status Tracker (and A4)
- S7-TRK-01, S7-TRK-02, S7-TRK-03; SA4-TRK-01 (appendix)
- No new IDs needed

### S8 Parking Lot
- S8-PRK-01, S8-PRK-02, S8-PRK-03 (existing); status EMPTY-REPO-CAN-ANSWER / EMPTY-NEEDS-TEAM
- New rows needed for OPEN D-191 items: D-191-01 through D-191-07, D-190-01, parked items
- No new map IDs needed for §8 rows (they cite the map IDs of the rows they flag)

### S11 Limitations
- S11-LIM-01 through S11-LIM-07 (all EMPTY-NEEDS-TEAM in map)
- No new IDs needed

### §4 existing domains (CONFIRMED CORRECTION or D-27 OPEN-QUESTION flags)
Domains with CONFIRMED corrections to draft:
- INS: S4-INS-03 (D-191-05 CONFIRMED)
- DIST: S4-DIST-06 (D-191-08 CONFIRMED)

Domains with D-27 OPEN-QUESTION flags needed:
- DXDT: S4-DXDT-03 (D-191-03 OPEN)
- CMNT (comment c1 anchor): S4-CMNT-02 (D-191-02 OPEN)
- DX: S4-DX-03 (D-191-04 OPEN)
- DTH: S4-DTH-03 (D-191-06 OPEN)
- DIST: S4-DIST-03 (D-191-07 OPEN)

### §4 repo-only domains (all 12 — Plan 03 content; marker region only in this plan)
- S4-SHS-01, S4-CHM-01, S4-NRM-01, S4-REG-01, S4-EPI-01, S4-ANT-01, S4-CBC-01, S4-RUR-01, S4-SDI-01, S4-DOI-01, S4-CLS-01, S4-PDE-01
- All allocated 2026-10-27; no new IDs needed

---

## G. New map IDs needed

Assessment: No new IDs are needed. All content units for this plan map to existing IDs from the registry. Individual §8 rows do not require their own IDs (they appear in the §8 table under S8-PRK-01/02/03 with IDs in the Map ID column citing the relevant map row). Individual §1 and §3 rows share their section-level table IDs.

---

## H. Workbook filename and sheets (from 192-01-SUMMARY.md citing 191-01-SUMMARY.md)

Workbook: `am_verification_20261027.xlsx`
Sheets referenced: S4_DIST (for D-191-08/D-191-07 evidence); V1_SOURCE, V2_INSURANCE, V3_DXDATE, V4_DXSCOPE, V6_DEATH

Source: `.planning/phases/191-verify-existing-entries/AM-VERDICTS.md` (frontmatter: `query_workbook: am_verification_20261027.xlsx`)

---

## I. §0 facts from sources

| Field | Value | Source | Type |
|-------|-------|--------|------|
| Extract name | Mailhot_V1_20250915 | `R/00_config.R:L65` (`/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915`) | directory path |
| Extract receipt / freeze date | [date to confirm] — not present in config or TeamMtgNotes as an explicit date | `R/00_config.R:L83` comment: "Extract date for current PCORnet CDM data pull (Mailhot_V1_20250915)" — no specific date beyond the folder name | folder name suggests 2025-09-15; type unknown (received vs freeze) |
| DuckDB build date | [date to confirm] — not present in any repo file as a constant | Config defines path `/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb`; no build-date log found in repo | — |
| Analytic version | v3.13 | STATE.md: `milestone: v3.13` | planning doc |
| Data sources text | EHR (primary), Claims (secondary) | `docs/analytic_manual/AnalyticManual_2026.01.30.md:L9` | existing manual (unchanged; D-191-01 goes to §8) |
| Project title, grant number, PIs, analytic lead | Not stated in TeamMtgNotes2026.md or repo docs in a canonical form; names appear in manual L19-L27 | `docs/analytic_manual/AnalyticManual_2026.01.30.md:L19-L27` (team roles block); no title or grant number in repo | → `[TEAM INPUT NEEDED]` for title/grant; team roles readable from manual |
| Date last updated, document version | Set in Phase 193 | 192-CONTEXT.md D-11 | planning doc |

---

## J. §1 data / reference-file events with dates

Events reconstructable from repo sources:

| Event | Description | Date | Date type | Source |
|-------|-------------|------|-----------|--------|
| PCORnet CDM extract (Mailhot_V1) | OneFlorida+ HL cohort, 22 CSV tables | 2025-09-15 (folder name) | [date to confirm — received vs freeze unclear] | `R/00_config.R:L65,L83,L102` |
| DuckDB build | Initial DuckDB ingest (Phase 29) | [date to confirm] | REBUILT | `R/00_config.R:L159–171`; Phase 29 SUMMARY |
| DEATH_CAUSE table added | Added as 14th PCORnet table | [date to confirm] | INTEGRATED | Phase 118/119 SUMMARYs |
| MED_ADMIN / DISPENSING chemo detection enabled | NDC→RxNorm crosswalk; get_chemo_hits() fix | [date to confirm] | INTEGRATED | Phase 122 SUMMARY |
| LDS_ADDRESS_HISTORY | Address history table for ZIP9 temporal lookup | [date to confirm] | INTEGRATED | Phase 137 SUMMARY |
| Neighborhood Atlas ADI 2024 | External reference: ADI 2024 edition | [date to confirm] | RECEIVED | Phase 144 SUMMARY (ADI reference file) |
| HRSA ZCTA crosswalk | HRSA ZIP-to-ZCTA crosswalk for distance fallback | [date to confirm] | RECEIVED | Phase 152/182 SUMMARYs |
| RUCA codes | Rural-Urban Commuting Area classification | [date to confirm] | RECEIVED | Phase 116 SUMMARY |
| SDI | Social Deprivation Index reference data | [date to confirm] | RECEIVED | Phase 144 SUMMARY |
| VariableDetails.xlsx (surveillance codeset) | Surveillance modality codeset from team | [date to confirm] | RECEIVED | 192-CONTEXT.md; STATE.md |

Note: All dates are `[date to confirm]` unless a source gives one explicitly. The folder name `Mailhot_V1_20250915` provides a candidate date (2025-09-15) of unknown type.

---

## K. §2 rule sources — functions and config keys with current line ranges

| §2 field | Code / Config | Location | Lines |
|----------|---------------|----------|-------|
| Inclusion: HL ICD code filter | `get_hl_any_dx_ids()` | `R/utils/utils_treatment.R` | L310–339 |
| Inclusion: ICD-10 HL codes (C81%) | `filter(DX_TYPE='10' AND DX LIKE 'C81%')` | `R/utils/utils_treatment.R:321` | L320–322 |
| Inclusion: ICD-9 HL codes (201%) | `filter(DX_TYPE='09' AND DX LIKE '201%')` | `R/utils/utils_treatment.R:321` | L320–322 |
| Inclusion: 2-encounter 7-day rule | `hl_any_dx_from_tibble()` via confirmed cohort | `R/utils/utils_treatment.R:331` / `R/utils/utils_surveillance.R:291–303` | L291–303 (surveillance) |
| Exclusion: NHL-only episodes | DEC-009; team decision | `TeamMtgNotes2026.md:09/22/2026`; AM-MAP-03 DEC-009 | — |
| Index date: earliest HL code date | `hl_any_dx_from_tibble()` — earliest DX_DATE (fallback ADMIT_DATE) | `R/utils/utils_treatment.R:318–331` | L318–331 |
| Index date: TR-first rule | NOT implemented in `get_hl_any_dx_ids()`; OPEN D-191-02 applies | — | — |
| Observation window | Not coded as a named constant; `date_range_max = 2025-03-31` | `R/00_config.R:2949` | L2949 |
| Study period lower bound | `date_range_min = 1901-01-01` (sentinel-date filter) | `R/00_config.R:2948` | L2948 |

---

## Summary: items confirmed, items to flag

- CONFIRMED CORRECTION directives: D-191-05 (S4-INS-03), D-191-08 (S4-DIST-06)
- OPEN flags in draft (D-27 applies): D-191-01 (§0 data sources; S0-FM-04), D-191-02/03 (index date, cleaning rule; S4-CMNT-02, S4-DXDT-03), D-191-04 (7-day scope; S4-DX-03), D-191-06 (grace_days; S4-DTH-03), D-191-07 (distance method; S4-DIST-03)
- D-190-01 (DEC-001): OPEN-DEPENDENCY §8 row
- STATE.md parked items: OPEN-DEPENDENCY §8 rows (treatment window pending Sharon; D-15/D-165-01; data completeness vs Medicaid)
- D-191-01: §5 draft describes code as EHR-only; D-191-01 question added to §8 per D-16
- D-191-05 AM-MAP-03 decision text check: text says "claims not implemented" is not verbatim; it says "Manual update only: update to reflect 8-category AMC framework" — §5 D-16 instruction to reword D-191-01 does not apply here; D-191-01 is the claims row (OPEN); D-191-05 is insurance (CONFIRMED, different map row). No AM-MAP-03 rewording needed.
