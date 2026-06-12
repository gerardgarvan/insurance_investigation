# Phase 101: Broadened Drug Grouping Output - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-12
**Phase:** 101-broadened-drug-grouping-output
**Areas discussed:** Scope of broadening, Cross-tab summary, Output file strategy

---

## Scope of Broadening

### Q1: Which scripts to broaden?

| Option | Description | Selected |
|--------|-------------|----------|
| R/57 only (Recommended) | Broaden encounter-level instances only. R/56 episode summaries stay cancer-linked-only. Matches ROADMAP scope exactly. | ✓ |
| Both R/57 and R/56 | Broaden both scripts. Encounter instances AND episode summaries get all-encounters + cancer_linked flag. | |
| You decide | Claude picks the right scope based on the requirements and downstream usage (Phase 102 co-administration). | |

**User's choice:** R/57 only
**Notes:** Matches ROADMAP scope which specifically references drug_grouping_instances.

### Q2: cancer_linked flag source

| Option | Description | Selected |
|--------|-------------|----------|
| Encounter DX presence (Recommended) | cancer_linked = TRUE when encounter has cancer DX codes (existing R/57 logic). Self-contained within R/57, no dependency change. | ✓ |
| R/28 cancer_category | cancer_linked = TRUE when episode has cancer_category from R/28 linkage. More clinically precise but ties to episode not encounter. | |
| You decide | Claude picks based on technical fit and downstream usage. | |

**User's choice:** Encounter DX presence
**Notes:** Keeps R/57 self-contained with no new upstream dependencies.

### Q3: Filter scope for broadened output

| Option | Description | Selected |
|--------|-------------|----------|
| Keep existing code filter (Recommended) | Broadened output still filters to valid reference codes + Immunotherapy. Only the cancer_category_names NA filter is removed. Consistent data quality. | ✓ |
| Remove all filters | Include every row from treatment_episode_detail.rds regardless of code validity. Maximum coverage but noisier. | |
| You decide | Claude picks based on what makes sense for downstream Phase 102 co-administration analysis. | |

**User's choice:** Keep existing code filter
**Notes:** Only the cancer-linked filter is removed; reference code quality filter stays.

---

## Cross-Tab Summary

### Q1: Where does the cross-tab live?

| Option | Description | Selected |
|--------|-------------|----------|
| New sheet in broadened xlsx (Recommended) | Add a 3rd sheet 'Linked vs Unlinked Summary' to the broadened drug_grouping_instances.xlsx. Self-contained. | ✓ |
| Separate xlsx file | Create a standalone drug_grouping_crosstab.xlsx. | |
| Sheet in episode_classification_audit.xlsx | Add to R/28's existing audit workbook. | |

**User's choice:** New sheet in broadened xlsx
**Notes:** Self-contained — user opens one file, sees data + summary.

### Q2: Cross-tab format

| Option | Description | Selected |
|--------|-------------|----------|
| Simple 3-column (Recommended) | treatment_type, linked_count, unlinked_count. One row per treatment type (5 types). | ✓ |
| Detailed with percentages | treatment_type, linked_count, unlinked_count, total, pct_linked. | |
| You decide | Claude picks the format for team meeting presentation use case. | |

**User's choice:** Simple 3-column
**Notes:** Matches success criteria directly.

---

## Output File Strategy

### Q1: File naming organization

| Option | Description | Selected |
|--------|-------------|----------|
| Broadened=primary, linked=suffix (Recommended) | drug_grouping_instances.xlsx becomes broadened. drug_grouping_instances_linked_only.xlsx preserves cancer-linked-only. | ✓ |
| New broadened name, keep old as-is | drug_grouping_instances_all.xlsx for broadened. drug_grouping_instances.xlsx stays cancer-linked-only. | |
| You decide | Claude picks based on dual-output pattern from Phase 89. | |

**User's choice:** Broadened=primary, linked=suffix
**Notes:** Matches success criteria which says "_linked_only suffix".

### Q2: Grain-labeled filename pattern

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, update both (Recommended) | encounter_level_drug_grouping_instances.xlsx = broadened. encounter_level_drug_grouping_instances_linked_only.xlsx = cancer-linked-only. | ✓ |
| Grain-labeled broadened only | Only update grain-labeled file to broadened. No grain-labeled linked-only file. | |
| You decide | Claude picks based on existing dual-output pattern. | |

**User's choice:** Yes, update both
**Notes:** Consistent grain-labeled naming across all outputs.

### Q3: Sheet structure parity

| Option | Description | Selected |
|--------|-------------|----------|
| 2 sheets only (Recommended) | Linked-only file keeps exact current structure (2 sheets). Cross-tab only in broadened file since it compares linked vs unlinked. | ✓ |
| 3 sheets for both | Both files get cross-tab sheet. Less useful for linked-only but consistent. | |
| You decide | Claude picks based on cross-tab purpose. | |

**User's choice:** 2 sheets only
**Notes:** Cross-tab compares linked vs unlinked, so only meaningful in broadened file.

---

## Claude's Discretion

- Sheet naming within 31-char Excel limit
- Column ordering for cancer_linked flag
- Smoke test (R/88) validation section additions

## Deferred Ideas

None — discussion stayed within phase scope.
