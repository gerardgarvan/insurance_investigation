# Phase 5: all_codes_resolved.xlsx Update - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-20
**Phase:** 05-all-codes-resolved-xlsx-update-because-we-added-more-codes-in-config-etc
**Areas discussed:** Code source, Descriptions, Output structure, Script approach

---

## Code Source

### Q1: Where should the updated all_codes_resolved.xlsx pull its code lists from?

| Option | Description | Selected |
|--------|-------------|----------|
| R/00_config.R directly (Recommended) | Read TREATMENT_CODES vectors straight from config. This is the current source of truth — it includes Phase 45 proton additions, Phase 46 ICD-10-PCS additions, and all earlier expansions. No dependency on the May 5 combined_unmatched_report.xlsx. | ✓ |
| Merge config + combined report | Use combined_unmatched_report.xlsx as base, then overlay any codes in config that aren't in the report. Preserves the original patient/record counts from the report but adds new codes without counts. | |
| You decide | Claude picks the approach that best fits the codebase patterns. | |

**User's choice:** R/00_config.R directly (Recommended)
**Notes:** None

### Q2: Should the xlsx include patient/record counts from the data, or just list the codes with descriptions?

| Option | Description | Selected |
|--------|-------------|----------|
| Codes + descriptions only | Just list each code with its description and treatment type. No DuckDB/HiPerGator query needed — can generate locally. | |
| Include counts (needs HiPerGator) | Query PROCEDURES/DISPENSING/PRESCRIBING/etc. for patient count and record count per code. Requires running on HiPerGator with data access. | ✓ |
| You decide | Claude picks based on what the existing per-type resolved files include. | |

**User's choice:** Include counts (needs HiPerGator)
**Notes:** None

### Q3: For data counts, should the script query all PCORnet tables or just PROCEDURES?

| Option | Description | Selected |
|--------|-------------|----------|
| All relevant tables (Recommended) | Query each code against the table(s) it could appear in (CPT/HCPCS → PROCEDURES, NDC → DISPENSING, RXNORM → PRESCRIBING/MED_ADMIN, ICD-10-PCS → PROCEDURES). Gives accurate per-code counts. | ✓ |
| PROCEDURES only | Simpler query but misses NDC/RXNORM codes that only appear in DISPENSING/PRESCRIBING/MED_ADMIN. | |
| You decide | Claude picks based on code types present in TREATMENT_CODES. | |

**User's choice:** All relevant tables (Recommended)
**Notes:** None

---

## Descriptions

### Q4: Where should code descriptions come from?

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-source cascade (Recommended) | 1st: Phase 39-41 RDS artifacts (NLM/RxNorm API descriptions). 2nd: R/45 hardcoded radiation descriptions. 3rd: R/00_config.R inline comments. 4th: Mark as 'No description available'. Covers all code origins. | |
| Config comments only | Parse R/00_config.R inline comments. Simpler but many codes lack inline comments. | |
| Runtime NLM API lookup | Call NLM HCPCS/RxNorm APIs at runtime for any code missing a description. Most complete but requires internet access on HiPerGator and adds runtime dependency. | |
| You decide | Claude picks the approach that maximizes description coverage with minimal complexity. | |

**User's choice:** Free text — "yes there should also the comments should be updated and curated when need be"
**Notes:** User wants multi-source cascade AND config comments should be updated/curated.

### Q5: Should the script update R/00_config.R inline comments when it finds a better description?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, update config comments (Recommended) | When the script finds a code in config with no comment or a generic comment, and a better description exists in the RDS artifacts, update the config comment. Makes config self-documenting. | ✓ |
| No, keep config as-is | Only update the xlsx output. Config comments stay untouched — description curation happens only in the xlsx. | |

**User's choice:** Yes, update config comments (Recommended)
**Notes:** None

---

## Output Structure

### Q6: How should all_codes_resolved.xlsx be organized?

| Option | Description | Selected |
|--------|-------------|----------|
| One sheet per type (Recommended) | Separate sheets for Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care — matches the per-type files but consolidated into one workbook. Plus a Summary sheet with totals. | ✓ |
| Single combined sheet | All codes on one sheet with a 'Treatment Type' column. Easier to filter/sort across types. | |
| Both approaches | Per-type sheets PLUS a combined 'All Codes' sheet in the same workbook. | |

**User's choice:** One sheet per type (Recommended)
**Notes:** None

### Q7: Should the script also regenerate the individual per-type resolved files?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, regenerate all (Recommended) | Update all 5 per-type files plus the consolidated all_codes_resolved.xlsx. Everything stays in sync with current config. | ✓ |
| No, only all_codes_resolved.xlsx | Just produce the consolidated file. Leave the per-type files at their May 5 state. | |

**User's choice:** Yes, regenerate all (Recommended)
**Notes:** None

---

## Script Approach

### Q8: How should the generation script be organized?

| Option | Description | Selected |
|--------|-------------|----------|
| New script R/52 (Recommended) | Create R/52_all_codes_resolved.R as a standalone script. R/42 stays as historical record. | ✓ |
| Extend R/42 | Modify R/42_treatment_codes_resolved.R to also read from config and produce consolidated file. | |
| You decide | Claude picks based on codebase conventions. | |

**User's choice:** New script R/52 (Recommended)
**Notes:** None

### Q9: Should config comment update be part of R/52 or a separate step?

| Option | Description | Selected |
|--------|-------------|----------|
| Same script, early section | R/52 first reads config, looks up descriptions, updates config comments inline, then sources config again to generate the xlsx. | |
| Separate prep script | A separate script curates config comments first, then R/52 reads the already-curated config. | |
| You decide | Claude picks the approach that minimizes risk of breaking config. | ✓ |

**User's choice:** You decide
**Notes:** None

---

## Claude's Discretion

- Config comment curation approach (inline in R/52 vs separate step)
- Exact xlsx styling details
- Code type to source table mapping logic
- Console output format

## Deferred Ideas

None — discussion stayed within phase scope
