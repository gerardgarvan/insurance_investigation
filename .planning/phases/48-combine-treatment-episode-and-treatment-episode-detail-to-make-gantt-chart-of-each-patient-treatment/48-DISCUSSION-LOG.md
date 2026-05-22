# Phase 1: Combine Treatment Episode and Detail for Gantt Chart — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-19
**Phase:** 01-combine-treatment-episode-and-treatment-episode-detail-to-make-gantt-chart-of-each-patient-treatment
**Areas discussed:** Visual layout, Patient scope, Output format, Detail overlay, Multiple codes per date

---

## Visual Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Horizontal bars per episode | Classic Gantt style with colored bars per episode | |
| Swim lanes by treatment type | 4 horizontal lanes per patient | |
| You decide | Claude picks layout | |

**User's choice:** "I'm passing this data on to a third party to plot, so I'm really only focused on data structure"
**Notes:** This reframed the entire phase from visualization to data preparation. No chart code needed.

---

## Patient Grouping

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-patient chart | Multiple patients per chart | |
| One patient per chart | Individual timelines | |
| Both | Summary + detail views | |

**User's choice:** "Just making dataset for graphing"
**Notes:** Confirmed data-only scope — no visualization decisions needed.

---

## Data Structure (Columns)

| Option | Description | Selected |
|--------|-------------|----------|
| Episode bars + detail ticks | Two output tables: episode-level bars and detail-level ticks | ✓ |
| Single flat table | One table with detail rows enriched with episode context | |
| You decide | Claude structures for Gantt consumption | |

**User's choice:** Episode bars + detail ticks (Recommended)
**Notes:** Two-table approach preserves both granularity levels for the third-party plotter.

---

## Payer Data

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — include payer tier | Join Phase 46 date-level payer tier | |
| No — treatment data only | Keep focused on treatment episodes | ✓ |
| You decide | Claude determines if payer is useful | |

**User's choice:** No payer now but it might be implemented in future
**Notes:** Deferred to a future phase.

---

## Output Format

| Option | Description | Selected |
|--------|-------------|----------|
| CSV | Two CSVs: gantt_episodes.csv and gantt_detail.csv | ✓ |
| Excel (xlsx) | Styled multi-sheet workbook | |
| RDS | R binary format | |

**User's choice:** CSV (Recommended)
**Notes:** Universal format for third-party consumption.

---

## Patient Scope

| Option | Description | Selected |
|--------|-------------|----------|
| All patients | Full cohort — every patient with at least one treatment episode | ✓ |
| Configurable filter | Parameter to filter by type, count, or date range | |
| You decide | Claude determines default scope | |

**User's choice:** All patients
**Notes:** Third party handles any filtering.

---

## Multiple Treatment Codes Per Date

| Option | Description | Selected |
|--------|-------------|----------|
| One row per code | 3 codes on one date = 3 rows. Full granularity preserved. | ✓ |
| One row per date, codes comma-separated | Collapse to one row per date with comma-separated codes | |
| One row per date+type | One row per patient+date+treatment_type | |

**User's choice:** One row per code (Recommended)
**Notes:** Preserves all granularity for the consumer.

---

## Concurrent Treatment Overlap

| Option | Description | Selected |
|--------|-------------|----------|
| Separate rows by type | Each type has own rows; overlap shown naturally | ✓ |
| Add overlap flag | Boolean column indicating concurrent treatment | |

**User's choice:** Separate rows by type (Recommended)
**Notes:** No overlap flag needed; plotter handles visual overlap.

---

## Claude's Discretion

- Column ordering within CSVs
- Whether to add derived columns useful for Gantt plotting
- Script naming convention

## Deferred Ideas

- Payer tier integration (user noted "might be implemented in future")
- Actual Gantt chart visualization code (third party handles)
