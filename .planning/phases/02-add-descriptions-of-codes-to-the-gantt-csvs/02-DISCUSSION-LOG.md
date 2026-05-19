# Phase 2: Add Descriptions of Codes to the Gantt CSVs - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-19
**Phase:** 02-add-descriptions-of-codes-to-the-gantt-csvs
**Areas discussed:** Description source, Column format, Missing descriptions, Output scope

---

## Description Source

| Option | Description | Selected |
|--------|-------------|----------|
| Static lookup table | Build a code->description lookup from existing RDS artifacts + config comments + hardcoded descriptions. No API calls at runtime. Fast and reproducible. | ✓ |
| Live NLM API calls | Query NLM API for every unique code at runtime. Slowest but gets the most up-to-date descriptions. Already implemented in R/39 and R/40. | |
| Hybrid: static + API fallback | Use static lookup first, then call NLM API only for codes not found. Best coverage but adds API dependency. | |

**User's choice:** Static lookup table
**Notes:** None — straightforward selection.

### Follow-up: Lookup Location

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone RDS file | Build a code_descriptions.rds lookup file once (via a helper script), then R/49 loads it at runtime. Keeps the export script simple and the lookup reusable. | ✓ |
| Inline in R/00_config.R | Add a CODE_DESCRIPTIONS named vector to config. Everything in one place, but config is already 900+ lines. | |
| Built on-the-fly in R/49 | R/49 loads the Phase 39-41 RDS artifacts itself and extracts descriptions. No new file, but adds complexity to the export script. | |

**User's choice:** Standalone RDS file
**Notes:** None.

---

## Column Format

| Option | Description | Selected |
|--------|-------------|----------|
| Parallel comma-separated column | Add triggering_code_descriptions column with descriptions in the same order as codes. Easy to split in any tool. | ✓ |
| Inline code:description pairs | Merge into triggering_codes column as 'J9000 (Doxorubicin HCl), J9040 (Bleomycin sulfate)'. Single column but harder to parse. | |
| You decide | Claude picks the approach that works best for the third-party consumer. | |

**User's choice:** Parallel comma-separated column
**Notes:** Applies to episodes CSV. Detail CSV gets a simple single-value `triggering_code_description` column.

---

## Missing Descriptions

| Option | Description | Selected |
|--------|-------------|----------|
| Empty string | Leave the description blank. The code is still in the triggering_code column. Third party can look it up if they need to. | ✓ |
| Repeat the code | If no description, use the code itself as the description. No blanks, but redundant. | |
| Placeholder text | Use something like 'No description available'. Explicit but adds noise to the data. | |

**User's choice:** Empty string
**Notes:** ICD-10-PCS XW0-series codes and tumor registry NA codes will get empty descriptions.

---

## Output Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Both CSVs only | Add description columns to gantt_episodes.csv and gantt_detail.csv. Don't touch R/44's xlsx. | ✓ |
| Both CSVs + R/44 xlsx | Also update the per-type episode xlsx workbooks produced by R/44_treatment_episodes.R. | |
| Detail CSV only | Only add descriptions to gantt_detail.csv. Skip the episodes CSV. | |

**User's choice:** Both CSVs only
**Notes:** R/44's xlsx workbooks are a separate output with their own format — not in scope.

---

## Claude's Discretion

- Helper script naming and numbering
- Config comment extraction approach (programmatic vs manual)
- Column ordering for new description columns

## Deferred Ideas

None — discussion stayed within phase scope.
