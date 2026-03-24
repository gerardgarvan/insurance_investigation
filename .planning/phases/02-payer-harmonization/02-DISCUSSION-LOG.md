# Phase 2: Payer Harmonization - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-24
**Phase:** 02-payer-harmonization
**Areas discussed:** Dual-eligible method, Payer variable scope, Completeness report, Output structure

---

## Dual-eligible Method

| Option | Description | Selected |
|--------|-------------|----------|
| Encounter-level (match Python) | Check primary+secondary payer per encounter row, plus codes 14/141/142. Same logic as Python pipeline | ✓ |
| Temporal enrollment overlap | Find overlapping Medicare + Medicaid enrollment periods using lubridate intervals. Novel approach | |
| Both methods | Encounter-level primary + temporal overlap supplemental | |

**User's choice:** Encounter-level matching Python pipeline exactly
**Notes:** Key tension identified between PAYR-02 wording ("temporal overlap") and Python reference implementation (encounter-level). User chose to match Python for comparability.

### Follow-up: Effective payer computation

| Option | Description | Selected |
|--------|-------------|----------|
| Match Python exactly | Primary if valid (not sentinel), else secondary, else null. Sentinels: null, empty, NI, UN, OT | ✓ |
| Simplified (primary only) | Use primary payer only, skip fallback to secondary | |

**User's choice:** Match Python exactly

### Follow-up: Missing secondary payer

| Option | Description | Selected |
|--------|-------------|----------|
| Set dual_eligible = 0 (match Python) | Can't compute checks without secondary, implementation sets 0 | ✓ |
| Check primary for 14/141/142 only | Still check primary alone for dual-eligible codes when secondary missing | |

**User's choice:** Set to 0 when secondary missing (match Python)

### Follow-up: 99/9999 sentinel handling

| Option | Description | Selected |
|--------|-------------|----------|
| 99/9999 = Unavailable (match Python default) | Not sentinels, map to Unavailable category | ✓ |
| Make it configurable | Add CONFIG toggle for sensitivity analysis | |

**User's choice:** Match Python default, no toggle

### Follow-up: Update PAYR-02 requirement

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, update requirement | Change wording from "temporal overlap" to "encounter-level" | ✓ |
| No, leave as-is | CONTEXT.md documents actual decision | |

**User's choice:** Update PAYR-02

### Follow-up: Preserve raw category

| Option | Description | Selected |
|--------|-------------|----------|
| No, just Dual eligible | Dual-eligible overrides category. One column. Matches Python | ✓ |
| Preserve both | Add payer_category_raw column before dual-eligible override | |

**User's choice:** No separate raw column

---

## Payer Variable Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Core set | PRIMARY + AT_FIRST_DX + DUAL_ELIGIBLE + PAYER_TRANSITION + encounter counts | ✓ |
| Full Python match | All ~15 variables | |
| Minimal | PRIMARY + DUAL_ELIGIBLE only | |

**User's choice:** Core set for v1

### Follow-up: DX window

| Option | Description | Selected |
|--------|-------------|----------|
| +/-30 days from config | Use CONFIG$analysis$dx_window_days, consistent with Python | ✓ |
| Exact date match only | Only encounters on exact diagnosis date | |

**User's choice:** +/-30 days from config

### Follow-up: Tie-breaking

| Option | Description | Selected |
|--------|-------------|----------|
| Match Python (count desc, first) | Same deterministic behavior | ✓ |
| You decide | Claude picks strategy | |

**User's choice:** Match Python

### Follow-up: Named functions

| Option | Description | Selected |
|--------|-------------|----------|
| Named functions | map_payer_category(), compute_effective_payer(), detect_dual_eligible() | ✓ |
| Inline pipeline | All logic in single dplyr pipeline | |

**User's choice:** Named functions

### Follow-up: Treatment flags

| Option | Description | Selected |
|--------|-------------|----------|
| Defer to Phase 3 | Treatment flags require PRESCRIBING + PROCEDURES + TUMOR_REGISTRY logic | ✓ |
| Include in Phase 2 | Compute alongside payer summary | |

**User's choice:** Defer to Phase 3

### Follow-up: First DX date source

| Option | Description | Selected |
|--------|-------------|----------|
| DIAGNOSIS table only | Use DX_DATE from DIAGNOSIS for first HL DX | |
| Both DIAGNOSIS + TUMOR_REGISTRY | Earliest of DX_DATE and DATE_OF_DIAGNOSIS | ✓ |

**User's choice:** Both tables -- earliest date wins

### Follow-up: ICD normalization

| Option | Description | Selected |
|--------|-------------|----------|
| Config codes + normalize (remove dots) | Handles C81.10 vs C8110 | ✓ |
| Exact match only | Match DX against ICD_CODES as-is | |

**User's choice:** Normalize with dot removal

### Follow-up: ICD utility location

| Option | Description | Selected |
|--------|-------------|----------|
| R/utils_icd.R (shared utility) | normalize_icd(), is_hl_diagnosis(), auto-sourced via 00_config.R | ✓ |
| Inline in 02_harmonize_payer.R | Keep local to this script | |

**User's choice:** Shared utility file

---

## Completeness Report

| Option | Description | Selected |
|--------|-------------|----------|
| Console summary table | Print formatted table via message() + glue | ✓ |
| Data frame + console | Return tibble AND print it | |
| Full diagnostic report | Detailed output with histograms and heatmaps | |

**User's choice:** Console summary table

### Follow-up: Gap definition

| Option | Description | Selected |
|--------|-------------|----------|
| Break >30 days | Between consecutive enrollment periods for same patient/partner | ✓ |
| Any non-contiguous periods | Any break at all | |
| You decide | Claude picks threshold | |

**User's choice:** >30 days threshold

### Follow-up: Duration calculation

| Option | Description | Selected |
|--------|-------------|----------|
| Total covered days | Sum of actual enrollment period durations, excluding gaps | ✓ |
| Total span | Last end minus first start | |
| Both | Report both perspectives | |

**User's choice:** Total covered days

### Follow-up: Payer distribution per partner

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add payer breakdown | Show category counts per partner alongside enrollment completeness | ✓ |
| No, enrollment only | Keep report focused on enrollment coverage | |

**User's choice:** Include payer breakdown per partner

---

## Output Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Patient-level summary tibble | One row per patient with core payer variables | ✓ |
| Annotated encounter table | Add payer columns to each encounter row | |
| Both | Encounter-level + patient-level | |

**User's choice:** Patient-level summary tibble

### Follow-up: Save to CSV

| Option | Description | Selected |
|--------|-------------|----------|
| Both (environment + CSV) | payer_summary object AND output/tables/payer_summary.csv | ✓ |
| In-memory only | R object only | |
| CSV only | Write to file, read back | |

**User's choice:** Both -- environment object and CSV

### Follow-up: Validation summary

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, print comparison | Total patients, per-category counts, dual-eligible rate, flag if outside range | ✓ |
| No automatic validation | User validates manually | |

**User's choice:** Automatic validation summary

### Follow-up: Script sourcing

| Option | Description | Selected |
|--------|-------------|----------|
| Source 01_load_pcornet.R | Self-contained, running 02 loads everything | ✓ |
| Expect data already loaded | User must source 01 first | |

**User's choice:** Self-contained sourcing

---

## Claude's Discretion

- Internal structure of map_payer_category() and compute_effective_payer() functions
- Console formatting for completeness report and validation summary
- Exact dplyr pipeline structure within named functions
- Edge case handling in gap detection (missing ENR_END_DATE, etc.)

## Deferred Ideas

- Treatment-specific payer variables (AT_FIRST_CHEMO, etc.) -- add after v1 core
- Temporal enrollment overlap as supplemental dual-eligible analysis
- Configurable 99/9999 sentinel toggle
- Full diagnostic enrollment report with histograms/heatmaps
