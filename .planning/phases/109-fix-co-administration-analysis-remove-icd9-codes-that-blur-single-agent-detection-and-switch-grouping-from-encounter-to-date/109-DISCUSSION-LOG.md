# Phase 109: Fix co-administration analysis - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-18
**Phase:** 109-fix-co-administration-analysis-remove-icd9-codes-that-blur-single-agent-detection-and-switch-grouping-from-encounter-to-date
**Areas discussed:** ICD9 code filtering, Date vs encounter grain, Output impact

---

## ICD9 Code Filtering

| Option | Description | Selected |
|--------|-------------|----------|
| ICD9/ICD10 prefix pattern | Filter by known ICD prefix patterns: ICD9 = numeric start, ICD10 = alpha start. Catches all diagnosis codes without maintaining a list. | |
| Explicit ICD code list from reference | Build list from all_codes_resolved xlsx. Only removes codes explicitly in the reference file. | |
| You decide | Claude picks the best approach based on the data patterns | |

**User's choice:** Free-text — "my issue is that I see just the fact it was a chemo encounter not what the agent was"
**Notes:** The user clarified the issue is not about ICD9 diagnosis codes inflating counts, but about ICD9 PROCEDURE codes (e.g., 99.25) being non-specific — they indicate chemotherapy was administered without identifying which agent. These blur single-agent detection because you can't distinguish agents.

### Follow-up: Encounters with only non-specific codes

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude from analysis entirely | If the only code is non-specific, there's no identifiable agent — exclude the encounter | :heavy_check_mark: |
| Keep as 'Unspecified Chemo' | Keep with placeholder drug name. Preserves encounter count but limits analytical value. | |
| You decide | Claude picks what makes sense | |

**User's choice:** Exclude from analysis entirely
**Notes:** No identifiable agent = no contribution to co-admin detection.

---

## Date vs Encounter Grain

| Option | Description | Selected |
|--------|-------------|----------|
| Collapse to unique codes per date | Deduplicate to (patient_id, treatment_date, triggering_code). Date-to-date pairs instead of encounter-to-encounter. | |
| Keep encounter detail, group output by date | Join at encounter level but roll up output tables to date grain. | |
| You decide | Claude picks what reduces noise | |

**User's choice:** Rejected initial framing — user clarified: "I just want to make sure that a single chemo agent is on that date"
**Notes:** The user's concern is simpler than the options presented. Single-agent = one specific identifiable code per patient-date. The encounter ID is just a billing artifact. Additionally, user specified co-administration means "a different agent in that date range" — same agent on another date is repeat dosing, not co-admin. Self-join exclusion changes from encounter-based to agent-based.

---

## Output Impact

### Output file handling

| Option | Description | Selected |
|--------|-------------|----------|
| Replace existing output | Overwrite co_administration_analysis.xlsx with improved date-grain version. Same 2-sheet structure. | :heavy_check_mark: |
| New filename alongside old | Keep old encounter-level output and add new date-level version. Both coexist. | |
| You decide | Claude picks based on downstream consumers | |

**User's choice:** Replace existing output

### Detail table columns

| Option | Description | Selected |
|--------|-------------|----------|
| Drop encounter IDs | Detail shows (patient_id, index_date, index_drug, coadmin_date, coadmin_drug, days_apart). Clean date-level grain. | :heavy_check_mark: |
| Keep encounter IDs as extra columns | Still include encounter IDs for traceability. Rows may reference multiple encounters per date. | |
| You decide | Claude picks what makes sense for the grain | |

**User's choice:** Drop encounter IDs

---

## Claude's Discretion

- Exact method for identifying ICD9 non-specific codes (prefix pattern vs explicit list)
- Console logging detail for filtered codes/encounters
- Column ordering in updated detail table
- Whether to update resolve_drug_name() function

## Deferred Ideas

None — discussion stayed within phase scope.
