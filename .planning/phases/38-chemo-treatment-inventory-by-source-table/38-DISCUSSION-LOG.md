# Phase 38: Chemo Treatment Inventory by Source Table - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-05-01
**Phase:** 38-chemo-treatment-inventory-by-source-table
**Areas discussed:** Treatment scope, Output granularity, Cohort scope, Output format, xlsx package choice, Script naming & placement, Styling details

---

## Treatment Scope

| Option | Description | Selected |
|--------|-------------|----------|
| All 3 types | Chemotherapy, radiation, AND stem cell transplant | |
| Chemo only | Just chemotherapy treatments | |
| All 3 + immunotherapy | Add CAR T-cell / immunotherapy as a 4th category | ✓ |

**User's choice:** All 3 + immunotherapy
**Notes:** Includes CAR T-cell immunotherapy which already has cart_icd10pcs_prefixes defined in 00_config.R.

---

## Output Granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Patient-level detail | Every treatment record per patient per table | |
| Aggregate summary only | Counts per code, per table, per treatment type | ✓ |
| Both | Patient-level detail plus aggregate summary tables | |

**User's choice:** Aggregate summary only
**Notes:** No patient IDs in output.

---

## Cohort Scope

| Option | Description | Selected |
|--------|-------------|----------|
| HL cohort only | Only patients who pass the cohort filter chain | |
| All patients in data | Everyone in the raw PCORnet extract | ✓ |
| Both scopes | Run for all patients AND separately for HL cohort | |

**User's choice:** All patients in data
**Notes:** Script can run independently of cohort pipeline.

---

## Output Format

| Option | Description | Selected |
|--------|-------------|----------|
| Console + CSV | Summary tables to console plus CSV files | |
| xlsx workbook | Single Excel workbook with styled sheets | ✓ |
| Console only | Print summary tables to console only | |

**User's choice:** xlsx workbook, matching csv_to_xlsx.py styling pattern
**Notes:** User referenced csv_to_xlsx.py as the template for visual style.

---

## HIPAA Suppression

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, suppress | Counts 1-10 replaced with '<11' | |
| No suppression | Show exact counts | ✓ |
| You decide | Claude picks | |

**User's choice:** No suppression
**Notes:** Internal exploratory tool.

---

## Code Descriptions

| Option | Description | Selected |
|--------|-------------|----------|
| From config comments | Build description lookup from 00_config.R comments | |
| Show raw codes only | Just display code values with counts | ✓ |
| You decide | Claude picks | |

**User's choice:** Show raw codes only

---

## Code Discovery

| Option | Description | Selected |
|--------|-------------|----------|
| Known codes only | Only codes in TREATMENT_CODES | |
| Include unknown codes | Also flag treatment-related codes not in our lists | ✓ |

**User's choice:** Include unknown codes
**Notes:** Broad CPT/HCPCS range heuristic (Claude's discretion on exact ranges).

---

## xlsx Package Choice

| Option | Description | Selected |
|--------|-------------|----------|
| openxlsx2 | Modern, full styling, no Java | |
| writexl + post-process | Plain xlsx then Python styling | |
| You decide | Claude picks | ✓ |

**User's choice:** You decide

---

## Script Naming & Placement

| Option | Description | Selected |
|--------|-------------|----------|
| R/38_treatment_inventory.R | Follows numbering convention | ✓ |
| R/treatment_inventory.R | Unnumbered standalone | |
| You decide | Claude picks | |

**User's choice:** R/38_treatment_inventory.R

---

## Styling Details

| Option | Description | Selected |
|--------|-------------|----------|
| Match closely | Replicate csv_to_xlsx.py visual patterns | ✓ |
| Simple formatting | Bold headers, basic formatting | |
| You decide | Claude picks | |

**User's choice:** Match closely

---

## Claude's Discretion

- xlsx package selection (openxlsx2 recommended)
- Treatment-type color scheme for xlsx pills
- Exact CPT/HCPCS range boundaries for unknown code discovery
- Internal function organization
- TUMOR_REGISTRY date column handling

## Deferred Ideas

None -- discussion stayed within phase scope
