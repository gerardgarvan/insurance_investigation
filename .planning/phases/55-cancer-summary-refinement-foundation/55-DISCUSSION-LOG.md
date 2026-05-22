# Phase 55: Cancer Summary Refinement Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-22
**Phase:** 55-cancer-summary-refinement-foundation
**Areas discussed:** Script structure, First HL date logic, Cohort confirmation scope, Output file handling

---

## Script Structure

| Option | Description | Selected |
|--------|-------------|----------|
| New R/55 script | Create R/55_cancer_summary_refined.R that sources R/53's CSV, applies D-code removal + cohort confirmation, then regenerates both cancer_summary and cancer_summary_table outputs. Preserves R/53 and R/54 as baseline. | Yes |
| Modify R/53 + R/54 in place | Add D-code filtering and cohort confirmation directly into R/53 and R/54. Simpler but destroys the baseline outputs that Phase 56 needs for comparison. | |
| Clone R/53 + R/54 | Clone both scripts as R/55a and R/55b with modifications. Follows the v1.4 clone-and-filter pattern but creates more PREFIX_MAP duplication. | |

**User's choice:** New R/55 script
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Self-contained R/55 | R/55 handles everything: load R/53 CSV, remove D-codes, confirm cohort, compute first_hl_dx_date, aggregate to category+code sheets, write styled xlsx. One script, one run. | Yes |
| R/55 CSV + re-run R/54 | R/55 produces a refined CSV, then you re-run R/54 pointing at the new CSV. Reuses R/54's xlsx logic but adds a manual step. | |

**User's choice:** Self-contained R/55
**Notes:** None

---

## First HL Date Logic

| Option | Description | Selected |
|--------|-------------|----------|
| Minimum across both | Take min(DIAGNOSIS earliest C81 date, TUMOR_REGISTRY DATE_OF_DIAGNOSIS) per patient. Matches CREF-03 literally. Requires querying both tables in R/55. | Yes |
| Reuse R/02's first_dx | Load the existing cohort (which has first_hl_dx_date from R/02). Faster but uses TR-preferred logic, not true minimum. | |
| You decide | Claude picks the approach that best satisfies CREF-03 | |

**User's choice:** Minimum across both
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Any C81 date | Take the earliest C81 date from either source, no confirmation threshold. The cohort confirmation step already filters patients — the date itself should be the true earliest evidence. | Yes |
| Confirmed dates only | Only use dates from C81 codes that meet the 2+ codes / 7-day gap threshold. More conservative but could shift the date later for some patients. | |
| You decide | Claude picks based on clinical epidemiology conventions | |

**User's choice:** Any C81 date
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Log source as column | Add first_hl_dx_source column to the output (values: 'DIAGNOSIS', 'TUMOR_REGISTRY', 'Both'). Satisfies success criterion #5 and is useful for Phase 56. | Yes |
| Log to console only | Print counts to console messages but don't add a column. Simpler but less traceable in the xlsx output. | |

**User's choice:** Log source as column
**Notes:** None

---

## Cohort Confirmation Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Query DIAGNOSIS directly | R/55 queries DIAGNOSIS for C81 codes, groups by patient, applies 7-day gap confirmation (max date - min date >= 7), then filters cancer_summary.csv to only those confirmed patient IDs. Self-contained, no dependency on R/04 cohort. | Yes |
| Reuse R/04 cohort | Load the existing cohort RDS from R/04 (which already has HL patients). But R/04 doesn't currently apply the 7-day gap filter — it includes all HL patients. Would need an additional filter step. | |
| You decide | Claude picks the cleanest approach | |

**User's choice:** Query DIAGNOSIS directly
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Any C81 prefix | Any two C81.xx codes (e.g., C81.10 and C81.90) at least 7 days apart confirm HL. This is clinically standard — different subtypes still confirm the disease. | Yes |
| Same exact code | Must be the same exact ICD-10 code (e.g., two C81.10 dates 7 days apart). More conservative but may miss patients with subtype reclassification. | |

**User's choice:** Any C81 prefix
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| DIAGNOSIS only | Confirmation uses DIAGNOSIS table C81 codes only (DX_DATE). TUMOR_REGISTRY contributes to first_hl_dx_date but not to the confirmation threshold. Cleaner separation of concerns. | Yes |
| Both sources | Count TUMOR_REGISTRY DATE_OF_DIAGNOSIS entries as additional C81 evidence. More inclusive but mixes data sources with different reliability characteristics. | |

**User's choice:** DIAGNOSIS only
**Notes:** None

---

## Output File Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Overwrite originals | R/55 overwrites cancer_summary.csv, cancer_summary.xlsx, and cancer_summary_table.xlsx. The originals are already generated by R/53+R/54 and can be regenerated anytime. Phase 56 creates its own _post_hl variants. | Yes |
| New suffix (_refined) | Output as cancer_summary_refined.csv, cancer_summary_refined.xlsx, cancer_summary_table_refined.xlsx. Preserves both versions on disk but Phase 56 must know which to use. | |
| You decide | Claude picks based on downstream Phase 56 needs | |

**User's choice:** Overwrite originals
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, save RDS | Save confirmed_hl_cohort.rds with columns: ID, first_hl_dx_date, first_hl_dx_source. Phase 56 (temporal filtering) and Phase 57 (Gantt enhancement) both need first_hl_dx_date. | Yes |
| No, CSV only | Downstream phases can re-derive from DIAGNOSIS. Avoids an intermediate artifact but duplicates the query logic. | |

**User's choice:** Yes, save RDS
**Notes:** None

---

## Claude's Discretion

- Styling of xlsx outputs (reuse R/54's dark header pattern)
- Console logging verbosity and attrition step messaging
- 1900 sentinel date handling (follow existing pattern from R/02)
- PREFIX_MAP: copy from R/53 for script independence or import

## Deferred Ideas

None — discussion stayed within phase scope
