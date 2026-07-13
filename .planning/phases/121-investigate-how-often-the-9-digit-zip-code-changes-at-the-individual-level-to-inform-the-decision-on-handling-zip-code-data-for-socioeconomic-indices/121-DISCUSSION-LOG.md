# Phase 121: Investigate 9-Digit ZIP Change Frequency - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-13
**Phase:** 121-investigate-how-often-the-9-digit-zip-code-changes-at-the-individual-level
**Areas discussed:** ZIP data source, Definition of "change", Output & metrics, Cohort scope & tie-break

---

## ZIP Data Source

| Option | Description | Selected |
|--------|-------------|----------|
| LDS_ADDRESS_HISTORY (probe first) | Probe for LDS_ADDRESS_HISTORY / raw address CSV in the HiPerGator extract; if present, load and analyze ZIP9 over time. Only PCORnet source with time-varying 9-digit ZIP. | ✓ |
| DEMOGRAPHIC, multi-row check | Check whether raw DEMOGRAPHIC CSV has multiple rows per patient; derive changes there or report unanswerable. | |
| I'll confirm what's available | User specifies which file/table holds the 9-digit ZIP + date fields. | |

**User's choice:** LDS_ADDRESS_HISTORY (probe first)
**Notes:** DEMOGRAPHIC (loaded, 16-table set) holds one 5-digit ZIP per patient with no
time dimension — confirmed via DEMOGRAPHIC_values.csv. LDS_ADDRESS_HISTORY is the CDM
table with ADDRESS_ZIP9 + ADDRESS_PERIOD_START/END but is NOT currently loaded.
Probe-first mirrors the Phase 119 R/103 diagnostic-gate pattern.

---

## Definition of "Change"

| Option | Description | Selected |
|--------|-------------|----------|
| Both ZIP9 and ZIP5 | Report distinct ZIP9 (ADI+4 granularity) AND distinct ZIP5 (SVI/tract granularity) per patient. | ✓ |
| ZIP9 only | Count any 9-digit change; most sensitive, may overstate instability. | |
| ZIP5 only | Collapse to 5-digit; aligns with most SES indices but misses ZIP9 moves. | |

**User's choice:** Both ZIP9 and ZIP5
**Notes:** Different SES indices key on different granularity (ADI ~ ZIP9/block-group;
SVI/deprivation ~ ZIP5/tract). Reporting both keeps the downstream decision informed.

---

## Output & Metrics

| Option | Description | Selected |
|--------|-------------|----------|
| Styled xlsx + console summary | Multi-sheet styled xlsx (distribution, % changed, time-between-changes, tie-break, recommendation/metadata) + console headline stats; R/39 + R/88 registered. Matches R/100. | ✓ |
| CSV outputs only | One/two CSVs, no styling; R/39 + R/88 registered. | |
| Console/log report only | Print metrics only, nothing persisted. | |

**User's choice:** Styled xlsx + console summary
**Notes:** Follows the R/100 RUCA report family (openxlsx2, add_styled_sheet) and the
project investigation-script convention (R/39 runner, R/88 smoke section, SCRIPT_INDEX row).

---

## Cohort Scope & Tie-Break

| Option | Description | Selected |
|--------|-------------|----------|
| HL cohort; recommend most-recent | HL cohort only; recommend most-recent ZIP, report modal-vs-recent disagreement. | |
| HL cohort; recommend modal | HL cohort only; recommend modal ZIP, report recent as comparison. | |
| All patients in extract | All patients with address history; report tie-break options without committing. | ✓ |

**User's choice:** All patients in extract
**Notes:** Broadest denominator for the stability question. Tie-break (most-recent via
ADDRESS_PERIOD_START/PREFERRED vs modal) is quantified and reported, but the choice is
left to the downstream SES-index phase.

---

## Claude's Discretion

- Exact xlsx sheet layout / column ordering / styling (follow R/100)
- HIPAA suppression of small ZIP cells (1–10) in shareable output (project constraint)
- NA / malformed ZIP handling rule (define + log)
- The R/NN script number and R/88 section suffix (next available in sequence)

## Deferred Ideas

- Computing/attaching an actual SES index (ADI/SVI/SDI) — future phase
- Permanently adding LDS_ADDRESS_HISTORY to PCORNET_TABLES / DuckDB ingest
- Time-varying ZIP + SES index in the production cohort pipeline
- Local fixture for LDS_ADDRESS_HISTORY so R/88 can run this section end-to-end locally
