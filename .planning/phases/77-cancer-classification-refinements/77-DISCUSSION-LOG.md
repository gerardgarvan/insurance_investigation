# Phase 77: Cancer Classification Refinements - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-02
**Phase:** 77-cancer-classification-refinements
**Areas discussed:** 7-day gap application, Drug groupings format, Output versioning, NLPHL downstream scope

---

## 7-Day Gap Application

| Option | Description | Selected |
|--------|-------------|----------|
| Filter rows | In R/49, only include patient-code pairs where two_or_more_unique_dates_gt_7 == 1. Patients without ANY code meeting the 7-day threshold are excluded from the summary entirely. | :white_check_mark: |
| Filter to confirmed patients | Define 'confirmed' for each cancer category the same way HL is confirmed: 2+ dates with 7-day span. Only count patients who meet this bar for at least one code. | |
| Flag only (no filtering) | Keep all patients in the table but add a 'confirmed_7day' column per category. Total pop stays the same but each row shows whether it meets the threshold. | |

**User's choice:** Filter rows
**Notes:** This is likely what produces exactly 6,347 patients.

### Follow-up: Output handling

| Option | Description | Selected |
|--------|-------------|----------|
| Both outputs | Keep existing cancer_summary_table_pre_post.rds unchanged AND produce new cancer_summary_table_pre_post_v2_7day.rds. Enables v1 vs v2 comparison. | :white_check_mark: |
| Replace with v2 only | Stop producing the old output. Only generate the 7-day filtered version. | |
| Comparison table only | Produce v2_7day as primary output, plus a small delta table showing v1 vs v2 differences. | |

**User's choice:** Both outputs

### Follow-up: Comparison format

| Option | Description | Selected |
|--------|-------------|----------|
| Sheet in v2 xlsx | Add a 'Comparison' sheet to the v2_7day xlsx showing per-category deltas. | |
| Separate CSV | Write a standalone cancer_summary_v1_v2_comparison.csv. | |
| Console log only | Print the comparison table to console during script execution. No persistent file. | :white_check_mark: |

**User's choice:** Console log only

### Follow-up: Population assertion

| Option | Description | Selected |
|--------|-------------|----------|
| Assert with tolerance | checkmate::assert_true() that total pop is within expected range (6300-6400). Hard fail if outside range. | :white_check_mark: |
| Log only, no assertion | message() the total population count. Don't fail if it differs. | |
| Exact assert (6,347) | Hard fail if total pop != 6,347 exactly. | |

**User's choice:** Assert with tolerance (6300-6400 range)

---

## Drug Groupings Format

| Option | Description | Selected |
|--------|-------------|----------|
| Named vector | code = "group_name" pattern (like AMC_PAYER_LOOKUP, CANCER_SITE_MAP). Simple lookup. Flat structure. | :white_check_mark: |
| Nested list | List of lists: DRUG_GROUPINGS$chemo, DRUG_GROUPINGS$radiation, etc. Each contains code-to-description mappings. | |
| Data frame constant | Tibble/data frame with columns: code, description, treatment_type, drug_group. | |

**User's choice:** Named vector

### Follow-up: xlsx snapshot handling

| Option | Description | Selected |
|--------|-------------|----------|
| Copy to data/ dir | Copy all_codes_resolved_next_tables.xlsx to data/reference/ with a version suffix. Git tracks it. Config hardcodes the named vector extracted from it. | :white_check_mark: |
| Keep at project root | Leave all_codes_resolved_next_tables.xlsx where it is. Just ensure it's tracked in git. | |
| You decide | Claude picks the appropriate approach during planning. | |

**User's choice:** Copy to data/reference/ with version suffix

---

## Output Versioning

| Option | Description | Selected |
|--------|-------------|----------|
| R/49 only | Only the final pre/post summary table (R/49) gets a v2_7day variant. R/45-R/48 continue unchanged. | :white_check_mark: |
| R/47 and R/49 | R/47 (refined summary) and R/49 (pre/post) both get v2_7day variants. | |
| All cancer scripts | R/45 through R/49 all produce parallel v2_7day outputs. | |

**User's choice:** R/49 only

### Follow-up: Output formats

| Option | Description | Selected |
|--------|-------------|----------|
| Full set: rds + xlsx + csv | Match the existing output pattern. All three formats produced for v2_7day. | :white_check_mark: |
| RDS only | Only produce the .rds file for the v2 version. | |

**User's choice:** Full set (rds + xlsx + csv)

---

## NLPHL Downstream Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Split reporting | Update the C81 diagnostic section to report NLPHL and classical HL counts separately in console log. | :white_check_mark: |
| Leave as-is | Keep the diagnostic section reporting all C81 together. Category-level summaries show the split naturally. | |
| You decide | Claude determines during planning whether the diagnostic section needs splitting. | |

**User's choice:** Split reporting (NLPHL vs classical HL in console diagnostics)

### Follow-up: Other script changes

| Option | Description | Selected |
|--------|-------------|----------|
| Re-run only | R/45-R/48, R/51 use classify_codes() which now returns NLPHL. No code changes. Only R/49 gets modifications. | :white_check_mark: |
| Review each script | Have the planner review R/45-R/51 for hardcoded C81 assumptions. | |
| Update R/47 too | R/47 might have C81-specific handling that needs NLPHL awareness. Update both. | |

**User's choice:** Re-run only — no changes to other scripts

---

## Claude's Discretion

No areas deferred to Claude's discretion — all gray areas resolved by user.

## Deferred Ideas

None — discussion stayed within phase scope.
