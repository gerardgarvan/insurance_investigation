# Phase 104: Treatment Timing Investigations - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-15
**Phase:** 104-treatment-timing-investigations
**Areas discussed:** Pre-dx output detail, Secondary malignancy table, Script structure

---

## Pre-dx Output Detail

### Output format

| Option | Description | Selected |
|--------|-------------|----------|
| Summary + detail sheets | xlsx with Sheet 1 = summary counts by treatment type, Sheet 2 = patient-level detail rows (ID, treatment_type, episode_start, first_hl_dx_date, days_before_dx). Matches R/59 pattern. | ✓ |
| Summary only | xlsx with just aggregate counts by treatment type. Simpler, but success criteria #2 requires patient IDs and dates. | |
| Detail only | Every pre-dx episode as a row. No aggregate summary sheet. | |

**User's choice:** Summary + detail sheets (Recommended)
**Notes:** None

### Treatment type scope

| Option | Description | Selected |
|--------|-------------|----------|
| All 5 types | Chemo, Radiation, SCT, Immunotherapy, Proton Therapy. Matches TIMING-01 requirement exactly. | ✓ |
| Radiation focus, others included | Same data for all types, but radiation gets extra detail. Addresses G5 concern specifically. | |

**User's choice:** All 5 types (Recommended)
**Notes:** None

### Detail depth

| Option | Description | Selected |
|--------|-------------|----------|
| Include codes + names | Detail rows include: ID, treatment_type, episode_start, episode_stop, first_hl_dx_date, days_before_dx, triggering_codes, drug_names. | ✓ |
| Minimal (dates only) | Detail rows include: ID, treatment_type, episode_start, first_hl_dx_date, days_before_dx. | |

**User's choice:** Include codes + names (Recommended)
**Notes:** None

---

## Secondary Malignancy Table

### Column definitions (K-N, population E/E3)

| Option | Description | Selected |
|--------|-------------|----------|
| Not sure / You decide | Claude infers layout: Column E = confirmed HL cohort count, Columns K-N = secondary malignancy counts as percentages of that population. | |
| I can describe it | User provides template description. | ✓ |

**User's choice:** Free text — "there was a table that had information on pre and post HL diagnosis counts of cancers"
**Notes:** User clarified this refers to R/49's pre/post HL cancer summary. The population column E (E3) means confirmed HL cohort as denominator. All numbers should be from confirmed 7-day HL diagnosis patients. Pre and post secondary malignancy counts should also use 7-day confirmation for each cancer category.

### Output approach

| Option | Description | Selected |
|--------|-------------|----------|
| Separate table | New output file 'secondary_malignancy_table.xlsx' built from R/49 logic. R/49 output unchanged. | ✓ |
| Enhance R/49 output | Add population-based percentage columns directly to existing cancer_summary_pre_post output. | |

**User's choice:** Separate table (Recommended)
**Notes:** None

### Percentage columns

| Option | Description | Selected |
|--------|-------------|----------|
| Pre + Post + Total rates | For each cancer code/category: total, pre-HL, post-HL counts and rates. | |
| Post-HL rates only | Focus on secondary malignancies after HL diagnosis only. | |
| You decide | Claude determines layout. | |

**User's choice:** Free text — "the meaning is everything in the table should be those that have confirmed 7 day HL diagnosis. the pre and post numbers should also have respective by cancer category confirmed 7 day diagnoses."
**Notes:** Dual 7-day confirmation requirement: (1) HL diagnosis confirmed via 7-day gap, (2) secondary malignancy confirmed via 7-day gap for that specific cancer code. Population denominator = confirmed HL cohort.

---

## Script Structure

### Script count

| Option | Description | Selected |
|--------|-------------|----------|
| Two separate scripts | One for pre-dx treatment flagging, one for secondary malignancy table. Different data flows, different outputs. | ✓ |
| One combined script | Single script handles both investigations. | |

**User's choice:** Two separate scripts (Recommended)
**Notes:** None

### Script numbering

| Option | Description | Selected |
|--------|-------------|----------|
| You decide | Claude picks next available numbers in appropriate decade. | ✓ |
| I'll specify | User has specific numbering preference. | |

**User's choice:** You decide
**Notes:** None

---

## Claude's Discretion

- Script numbering
- Console logging structure
- Summary sheet layout details
- R/88 smoke test section structure

## Deferred Ideas

None — discussion stayed within phase scope
