# Phase 64: Clean up Gantt 2 output for coherent chart generation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-01
**Phase:** 64-clean-up-gantt-2-output-for-coherent-chart-generation
**Areas discussed:** Target tool, Column cleanup, Data quality, Output structure, Separator character, Drug name cleanup, Historical episodes, Missing cancer categories

---

## Target Tool

| Option | Description | Selected |
|--------|-------------|----------|
| Excel / Google Sheets | Manual chart creation from CSV | |
| Python (matplotlib/plotly) | Programmatic chart generation | |
| R (ggplot2/ggalluvial) | Same R ecosystem | |
| Tableau | User's actual tool (free-text answer) | :heavy_check_mark: |

**User's choice:** Tableau
**Notes:** User specified Tableau as the target tool — not one of the initial options.

---

## Column Cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Trim to essentials (Recommended) | Keep only columns useful in Tableau: patient_id, treatment_type, dates, drug_names, cancer_category, regimen_label, is_first_line, triggering_code_descriptions. Drop internal IDs and metadata. | :heavy_check_mark: |
| Keep all, rename for clarity | Keep all 17 columns but rename to Tableau-friendly names. | |
| Two outputs | One trimmed 'chart-ready' file and one full 'reference' file with all columns. | |

**User's choice:** Trim to essentials
**Notes:** None

---

## Description Cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Deduplicate + drop blanks (Recommended) | Remove empty descriptions from the comma list, deduplicate repeated descriptions, produce a clean semicolon-separated list. | :heavy_check_mark: |
| Primary description only | Keep only the first non-empty description per episode. | |
| Drop descriptions entirely | The triggering_codes column is enough. | |

**User's choice:** Deduplicate + drop blanks
**Notes:** User originally flagged that triggering_code_descriptions are "kind of hard to read."

---

## Data Quality (Nulls + Pseudo-treatments)

| Option | Description | Selected |
|--------|-------------|----------|
| Clean nulls + label pseudos (Recommended) | Convert text 'NA' to true empty cells. For pseudo-treatment rows, set descriptions to the treatment_type itself. | :heavy_check_mark: |
| Blanks everywhere | Just convert 'NA' to empty. Leave pseudo-treatment descriptions blank. | |
| Remove pseudo-treatment rows | Drop Death and HL Diagnosis rows entirely. | |

**User's choice:** Clean nulls + label pseudos
**Notes:** None

---

## Output Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Episodes only (Recommended) | One clean file with episode-level bars. | |
| Both files, cleaned | Clean up both episodes and detail CSVs with same column/quality fixes. | :heavy_check_mark: |
| Merge into one | Combine episodes + detail into a single file with a row_type column. | |

**User's choice:** Both files, cleaned
**Notes:** User wants both the episode-level and detail-level files cleaned.

---

## Column Naming

| Option | Description | Selected |
|--------|-------------|----------|
| Tableau-friendly names (Recommended) | Rename to Title Case with spaces. | |
| Keep snake_case | Keep current names like patient_id, treatment_type. | :heavy_check_mark: |

**User's choice:** Keep snake_case
**Notes:** None

---

## Separator Character

| Option | Description | Selected |
|--------|-------------|----------|
| Semicolons (Recommended) | Use ';' to separate values within cells. Standard practice for CSVs with multi-value fields. | :heavy_check_mark: |
| Pipe '|' | Use '|' separator. Less ambiguous but less conventional. | |

**User's choice:** Semicolons
**Notes:** None

---

## Drug Name Cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Simplified generic names (Recommended) | Extract just the generic drug name: 'doxorubicin', 'vincristine', 'nivolumab'. Remove dosage/formulation/brand info. Deduplicate per episode. | :heavy_check_mark: |
| Keep full RxNorm descriptions | Keep the full descriptions as-is. | |
| Generic + brand if available | Show 'nivolumab (Opdivo)', 'vincristine (Vincasar)'. | |

**User's choice:** Simplified generic names
**Notes:** None

---

## Historical Episodes

| Option | Description | Selected |
|--------|-------------|----------|
| Keep but label (Recommended) | Keep these rows but ensure historical_flag stays in the trimmed columns so you can filter them in Tableau. | :heavy_check_mark: |
| Remove historical episodes | Drop all historical episodes from the output. | |
| Merge into study episodes | Remove the flag column entirely. | |

**User's choice:** Keep but label
**Notes:** 371 episodes (2.5%) have historical_flag=TRUE.

---

## Missing Cancer Categories

| Option | Description | Selected |
|--------|-------------|----------|
| Label as 'Unlinked' (Recommended) | Set empty cancer_category to 'Unlinked'. Honest label, useful as Tableau filter/color. | :heavy_check_mark: |
| Label as 'Unknown' | More generic label. | |
| Leave blank | Keep empty string as-is. | |

**User's choice:** Label as 'Unlinked'
**Notes:** 27.5% of real treatment episodes have no cancer category.

---

## Claude's Discretion

- Output file naming (overwrite vs new filenames)
- Sort order of output rows
- Regex pattern for extracting generic drug names from RxNorm strings
- Whether to also clean triggering_codes field values

## Deferred Ideas

None — discussion stayed within phase scope
