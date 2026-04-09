# Phase 20: Check Duplicate Dates of FLM Subjects - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-09
**Phase:** 20-check-duplicate-dates-of-flm-subjects
**Areas discussed:** What's duplicated, Scope & comparison, Output & deliverables, Root cause hypothesis

---

## What's Duplicated

| Option | Description | Selected |
|--------|-------------|----------|
| Same diagnosis date repeated | Multiple DIAGNOSIS rows for the same patient with identical DX_DATE | |
| Same encounter date repeated | Multiple ENCOUNTER rows with the same ADMIT_DATE for one patient | ✓ |
| Haven't looked yet | Suspicion or external report — this phase IS the first look | |
| Treatment date overlap | Same treatment dates across multiple treatment types or tables | |

**User's choice:** Same encounter date repeated
**Notes:** User confirmed ENCOUNTER table is the focus.

### Date Columns

| Option | Description | Selected |
|--------|-------------|----------|
| ADMIT_DATE only | Focus on encounter ADMIT_DATE | |
| All encounter dates | ADMIT_DATE, DISCHARGE_DATE, and any DX_DATE | |
| You decide | Claude picks relevant date columns | |

**User's choice:** "all time things in the ENCOUNTER Table"
**Notes:** All time-related columns: ADMIT_DATE, ADMIT_TIME, DISCHARGE_DATE, DISCHARGE_TIME.

### Duplicate Type

| Option | Description | Selected |
|--------|-------------|----------|
| Same date, different rows | Same patient + same date, multiple encounter records | |
| Exact duplicate rows | Rows fully identical across all columns | |
| Both | Check both same-date collisions AND full duplicates | ✓ |

**User's choice:** Both

### Concern

| Option | Description | Selected |
|--------|-------------|----------|
| Data quality | FLM submitting duplicate records that inflate counts | |
| Pipeline impact | Duplicates inflating encounter counts, skewing payer mode | |
| Both | Quantify data quality AND assess pipeline impact | ✓ |

**User's choice:** Both

### Tables

| Option | Description | Selected |
|--------|-------------|----------|
| ENCOUNTER only | Focus exclusively on ENCOUNTER table | ✓ |
| ENCOUNTER + DIAGNOSIS | Also check DIAGNOSIS table | |
| All clinical tables | Check ENCOUNTER, DIAGNOSIS, PROCEDURES, PRESCRIBING | |

**User's choice:** ENCOUNTER only

### Observation Specifics

| Option | Description | Selected |
|--------|-------------|----------|
| Specific observation | Saw duplicates for a particular patient or time period | |
| General suspicion | No specific case — systematic check of all FLM ENCOUNTER data | ✓ |
| External report | Someone else flagged this issue | |

**User's choice:** General suspicion

### Multi-Source Key Insight

| Option | Description | Selected |
|--------|-------------|----------|
| Count per patient-date | Count how many encounter rows per patient-date pair | |
| Just flag existence | Binary: does patient have duplicate dates | |
| Distribution summary | Show distribution of 2, 3, 4+ encounters per date | |

**User's choice:** "I want to know if there are multiple sources on one date as this may account for duplication. then I want to know which source has more complete insurance information"
**Notes:** Key pivot — the investigation is about cross-site encounters (different SOURCE values for same patient on same date) and comparing payer data completeness across sources.

### Source Confirmation

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, exactly | Same patient, same date, encounters from different sites — compare payer completeness | ✓ |
| Not quite | Needs clarification | |

**User's choice:** Yes, exactly

---

## Scope & Comparison

| Option | Description | Selected |
|--------|-------------|----------|
| FLM vs all sites | Compare duplicate rates across all 4 sites | |
| FLM only | Focus exclusively on FLM encounter duplicates | |
| FLM deep dive + site summary | Deep analysis on FLM, quick per-site summary | |

**User's choice:** "use those with FLM as source in the DEMOGRAPHIC table as the IDs to look at in the ENCOUNTER table then see if they have duplicates"
**Notes:** FLM-only. Filter patients by DEMOGRAPHIC.SOURCE == "FLM", then check their ENCOUNTER records.

### Population

| Option | Description | Selected |
|--------|-------------|----------|
| All FLM patients | Check all FLM patients in raw data | ✓ |
| HL cohort FLM only | Only FLM patients in final HL cohort | |
| Both | Check all AND flag cohort members | |

**User's choice:** All FLM patients

### Grouping

| Option | Description | Selected |
|--------|-------------|----------|
| ID + date only | Any two encounters same patient same date = duplicate | ✓ |
| ID + date + ENC_TYPE | Only flag if same patient, date, AND encounter type | |
| Both analyses | Show both groupings | |

**User's choice:** ID + date only

---

## Output & Deliverables

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone R script + CSVs | Same pattern as Phase 19 | ✓ |
| Add to existing script | Fold into 07_diagnostics.R or similar | |
| Console output only | Quick script, no CSV files | |

**User's choice:** Standalone R script + CSVs (Recommended)

### CSV Files

| Option | Description | Selected |
|--------|-------------|----------|
| Patient-level duplicate summary | One row per FLM patient with duplicate stats | |
| Date-level detail | One row per patient-date with duplicate encounters | |
| Both + aggregate summary | Patient-level, date-level, AND aggregate CSV | ✓ |

**User's choice:** Both + aggregate summary

### Payer Columns

| Option | Description | Selected |
|--------|-------------|----------|
| Both PRIMARY and SECONDARY | Compare completeness on both fields across sources | ✓ |
| PRIMARY only | Focus on PAYER_TYPE_PRIMARY | |
| You decide | Claude picks | |

**User's choice:** Both PRIMARY and SECONDARY

---

## Root Cause Hypothesis

| Option | Description | Selected |
|--------|-------------|----------|
| Cross-site care | FLM patients also receiving care at other sites | |
| Data feed overlap | Same encounter submitted by multiple sites | |
| Unknown | No hypothesis — investigation is exploratory | ✓ |
| Referral pattern | FLM referring patients, both sites recording encounter | |

**User's choice:** Unknown

### Action on Findings

| Option | Description | Selected |
|--------|-------------|----------|
| Report only | Present data, decision is separate | |
| Report + recommend | Present data AND suggest source preference | ✓ |
| Report + flag for pipeline | Present findings AND flag pipeline impact | |

**User's choice:** Report + recommend

---

## Claude's Discretion

- Exact CSV file names and column structures
- Script number assignment
- Console logging format and verbosity
- Payer completeness recommendation structure
- Whether to include visualizations
- Additional breakdowns if informative

## Deferred Ideas

None — discussion stayed within phase scope
