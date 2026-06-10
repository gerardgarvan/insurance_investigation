# Phase 95: Infrastructure Setup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-06-10
**Phase:** 95-infrastructure-setup
**Areas discussed:** Namespace Management, Column Naming, TREATMENT_CODES, Error Handling

---

## Namespace Management

| Option | Description | Selected |
|--------|-------------|----------|
| Global library() (Recommended) | Add library(data.table) to R/00_config.R so it's available everywhere. Rely on dplyr being loaded AFTER data.table to take precedence (standard tidyverse pattern). Simplest approach. | |
| Conditional loading | Only load data.table in scripts that use it (R/60, R/28, utils_dt.R). No namespace changes for other scripts, but more complex to manage. | |
| You decide | Let Claude choose the approach that best fits existing patterns. | |

**User's choice:** Global library() selected, BUT with explicit `package::function()` form for conflicting functions instead of relying on load order.
**Notes:** User specified using `package::function()` form (e.g., `data.table::between()`, `dplyr::between()`) to avoid namespace collision problems entirely, rather than depending on load order.

---

## Column Naming

| Option | Description | Selected |
|--------|-------------|----------|
| Semantic names (Recommended) | Table-specific names: AMC_PAYER has code/payer_category, DRUG_GROUPINGS has code/drug_group, CANCER_SITE_MAP has prefix/cancer_site. Self-documenting in downstream joins. | ✓ |
| Generic key/value | All tables use key/value columns. Uniform but less readable in join syntax: dt[other, on='key'] everywhere. | |
| You decide | Let Claude pick appropriate names per table. | |

**User's choice:** Semantic names
**Notes:** None -- straightforward selection of recommended option.

---

## TREATMENT_CODES

| Option | Description | Selected |
|--------|-------------|----------|
| Long-format melt (Recommended) | Flatten to a 3-column data.table: code, code_system, treatment_type. Key on 'code'. Enables direct keyed joins like DRUG_GROUPINGS. | ✓ |
| Skip conversion | Leave TREATMENT_CODES as a list -- it's only used for %in% membership checks, not lookups. Focus data.table conversion on the 5 named-vector tables. | |
| You decide | Let Claude assess whether conversion adds value for this table. | |

**User's choice:** Long-format melt
**Notes:** None -- straightforward selection of recommended option.

---

## Error Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Defensive with warnings (Recommended) | NULL = error. Empty input = return empty data.table/tibble with warning. Already-correct type = return as-is silently. Follows existing checkmate pattern in R/utils/utils_assertions.R. | ✓ |
| Strict errors everywhere | NULL, empty, or wrong-type input all throw errors immediately. Fail fast -- forces callers to validate before calling. | |
| You decide | Let Claude match the existing assertion style in the codebase. | |

**User's choice:** Defensive with warnings
**Notes:** None -- straightforward selection of recommended option.

---

## Claude's Discretion

- Exact semantic column names per table (examples provided, Claude finalizes)
- Placement of LOOKUP_TABLES_DT construction within R/00_config.R
- get_lookup_dt() parameter interface (string name vs direct reference)
- Internal type detection logic in ensure_dt()

## Deferred Ideas

None -- discussion stayed within phase scope.
