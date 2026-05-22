# Phase 7: Summary Table of Cancer Summary Data - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-21
**Phase:** 07-summary-table-of-cancer-summary-data
**Areas discussed:** Aggregation level, Summary metrics, Output format, Scope filtering

---

## Aggregation Level

| Option | Description | Selected |
|--------|-------------|----------|
| Cancer site category only | One row per cancer site category (~54 categories). Matches R/50 and R/51 patterns. | |
| Both category and code | Two sheets: one category-level summary and one code-level summary. More detail but larger output. | ✓ |
| Category with top codes | Category-level rows with additional column showing most frequent codes within each category. | |

**User's choice:** Both category and code
**Notes:** None

### Follow-up: Code-level detail threshold

| Option | Description | Selected |
|--------|-------------|----------|
| All codes | Every unique neoplasm code that appears in the data gets a row. Could be hundreds of rows. | ✓ |
| Codes with 2+ patients | Skip codes that only appear for a single patient. Reduces noise from rare coding variants. | |

**User's choice:** All codes
**Notes:** None

---

## Summary Metrics

| Option | Description | Selected |
|--------|-------------|----------|
| Patient counts | Total patients with codes in this category/code. The base metric. | ✓ |
| Confirmation rates | Confirmed patients (2+ dates), 7-day confirmed patients, and confirmation rate percentages. | ✓ |
| Date distribution stats | Mean/median unique_dates_total and unique_dates_with_sep_gt_7 per category. | ✓ |
| Record counts | Total DIAGNOSIS rows per category. Shows volume of encounters, not just distinct dates. | ✓ |

**User's choice:** All four metric groups selected
**Notes:** Multi-select question

### Follow-up: Rate format

| Option | Description | Selected |
|--------|-------------|----------|
| Both counts and percentages | Show confirmed count AND percentage. e.g., Confirmed: 341, Confirmation Rate: 85.3%. | ✓ |
| Percentages only | Just the rate column (85.3%). Cleaner but loses the raw count. | |
| Counts only | Just confirmed_patients column. User can compute rate themselves. | |

**User's choice:** Both counts and percentages
**Notes:** None

---

## Output Format

| Option | Description | Selected |
|--------|-------------|----------|
| Styled (dark headers) | Dark fill + white font headers, freeze panes, auto widths, number formatting. Matches R/47 and R/50. | ✓ |
| Minimal (like Phase 6) | Plain headers, auto widths, freeze panes only. Purely a data export. | |
| Styled with totals row | Dark headers plus a bold totals/grand total row at bottom of each sheet. | |

**User's choice:** Styled (dark headers)
**Notes:** None

### Follow-up: CSV output

| Option | Description | Selected |
|--------|-------------|----------|
| Both xlsx and CSV | One CSV per sheet. Consistent with Phase 6 outputting both formats. | |
| xlsx only | Summary table is for review/sharing. CSV not needed for a summary. | ✓ |

**User's choice:** xlsx only
**Notes:** None

### Follow-up: Filename

| Option | Description | Selected |
|--------|-------------|----------|
| cancer_summary_table.xlsx | Distinguishes from Phase 6's cancer_summary.xlsx while showing the relationship. | ✓ |
| cancer_summary_summary.xlsx | Follows convention of appending the purpose. Redundant but explicit. | |
| You decide | Claude picks a reasonable filename. | |

**User's choice:** cancer_summary_table.xlsx
**Notes:** None

---

## Scope Filtering

| Option | Description | Selected |
|--------|-------------|----------|
| All patients | Consistent with Phase 6's cancer_summary data which includes all patients in DIAGNOSIS. | ✓ |
| HL cohort only | Restrict to the ~3,000 patient HL cohort. Focused on study population. | |
| Both | Two separate sets of sheets. Doubles output but enables comparison. | |

**User's choice:** All patients
**Notes:** Consistent with Phase 6

### Follow-up: Code scope

| Option | Description | Selected |
|--------|-------------|----------|
| All neoplasm codes (C+D) | Matches Phase 6 scope. Includes in situ, benign, uncertain behavior. | ✓ |
| Malignant only (C-codes) | Focus on C00-C96. Drops benign/in situ/uncertain. Clinically focused. | |
| Separate sections | Malignant summary first, then separate section for D-codes. | |

**User's choice:** All neoplasm codes (C+D)
**Notes:** None

### Follow-up: Sort order

| Option | Description | Selected |
|--------|-------------|----------|
| Patient count descending | Most common cancer sites at top. Natural for reviewing which diagnoses dominate. | ✓ |
| Alphabetical by category | Easier to find a specific category. Matches ICD-10 organization. | |
| ICD-10 code order | Sorted by first code in each category (C00-D49 natural ordering). | |

**User's choice:** Patient count descending
**Notes:** None

---

## Claude's Discretion

- Script number assignment (likely R/54)
- Exact column header names (human-readable)
- Whether to include a totals row at bottom of each sheet
- Percentage number formatting
- Whether date stats use mean, median, or both

## Deferred Ideas

None — discussion stayed within phase scope
