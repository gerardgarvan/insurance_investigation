# Phase 88: Re-do Tables with Descriptives Instead of Counts - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-04
**Phase:** 88-re-do-tables-from-grouping-by-using-descriptives-from-codes-instead-of-counts-and-instead-of-counts-just-list-each-instance
**Areas discussed:** Which tables change, Descriptive columns, Instance-level detail, Output format

---

## Which Tables Change

| Option | Description | Selected |
|--------|-------------|----------|
| Table 2 only | Table 1 is already instance-level. Focus on expanding Table 2 from aggregated counts to individual rows. | |
| Both tables | Restructure both Table 1 and Table 2 to show descriptives and individual instances. | ✓ |
| Replace both with new design | Scrap the current 2-table structure entirely and design new table(s) from scratch. | |

**User's choice:** Both tables
**Notes:** None

---

## Descriptive Columns

| Option | Description | Selected |
|--------|-------------|----------|
| Sub-category names | Use the resolved sub-category labels (drug names, procedure types) as the primary descriptor. | ✓ |
| Full code descriptions | Use the detailed code_descriptions.rds lookup for human-readable descriptions. | |
| Both sub-cat + description | Show sub-category label AND a longer description column. | |

**User's choice:** Sub-category names
**Notes:** None

### Follow-up: Cancer Code Display

| Option | Description | Selected |
|--------|-------------|----------|
| Category names | Replace raw ICD codes with cancer site category labels from CANCER_SITE_MAP. | ✓ |
| Keep raw codes | Keep ICD codes as-is. | |
| Both codes + categories | Show raw ICD codes in one column and cancer site category in another. | |

**User's choice:** "category names in descending order"
**Notes:** User specified descending sort order for cancer site category names within each cell.

---

## Instance-Level Detail

### Row Grain

| Option | Description | Selected |
|--------|-------------|----------|
| One row per episode | Each treatment episode is its own row. | |
| One row per encounter | Each individual encounter within an episode is its own row — most granular. | |
| One row per patient-treatment | Each unique patient + treatment type combination is a row. | ✓ |

**User's choice:** One row per patient-treatment
**Notes:** None

### Episode Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Collapse to one row | One row per patient + treatment type — combine all episodes. | |
| Keep episodes separate | One row per patient + treatment type + episode — each episode is distinct. | ✓ |

**User's choice:** Keep episodes separate
**Notes:** Final grain is one row per patient + treatment type + episode.

### Identifying Columns

| Option | Description | Selected |
|--------|-------------|----------|
| Patient ID | Include PATID column. | ✓ |
| Episode dates | Include episode_start and episode_stop dates. | ✓ |
| Episode number | Include the episode sequence number. | ✓ |
| Treatment category | Include the treatment category column. | ✓ |

**User's choice:** All four columns selected (multiSelect)
**Notes:** None

---

## Output Format

### File Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Replace existing sheets | Overwrite current sheets in drug_grouping_tables.xlsx. | |
| New sheets alongside old | Keep existing sheets, add new ones. | |
| New file entirely | Create a separate xlsx file, preserving the old file unchanged. | ✓ |

**User's choice:** New file entirely
**Notes:** None

### Sheet Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Single sheet | One sheet with all instance-level rows. | |
| Two sheets | Keep the sub-category vs encounter treatment distinction as separate sheets. | ✓ |

**User's choice:** Two sheets
**Notes:** None

---

## Claude's Discretion

- New xlsx file name
- Column ordering within sheets
- Multi-sub-category handling per episode
- Row sort order
- Whether to create new script or extend R/56
- Cancer code → category name translation implementation

## Deferred Ideas

None — discussion stayed within phase scope.
