# Phase 58: Cancer Summary Pre/Post HL Counts - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-26
**Phase:** 58-cancer-summary-pre-post-hl-counts
**Areas discussed:** Column structure, Same-day handling, Output strategy, Patients with no dates, Sheet structure, Sentinel dates, HL row handling, Column ordering, Styling, TUMOR_REGISTRY codes, HL date source

---

## Column Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Replace with pre/post | Drop all rate/date-stat columns. Keep: Category, Total Patients, Pre-HL, Post-HL, Both, Total Records | |
| Add pre/post alongside | Keep existing count columns but drop percentages and date stats. Add Pre-HL, Post-HL, Both as new columns | ✓ |
| Full replacement | Category, Pre-HL, Post-HL, Both, Total Records only | |

**User's choice:** Add pre/post alongside
**Notes:** Keep Total Patients, Confirmed (2+ Dates), Confirmed (7-Day Gap), Total Records. Add Pre-HL, Post-HL, Both. Drop all percentage and date-stat columns.

---

## Both Column Logic

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, intersection | Both = patient had code before AND after first HL dx date. Pre/Post are non-exclusive. | ✓ |
| Mutually exclusive | Pre = only before, Post = only after, Both = in both periods. No overlap. | |

**User's choice:** Intersection (non-exclusive Pre/Post)
**Notes:** Pre + Post - Both = total unique patients with temporal data

---

## Same-Day Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Pre (Recommended) | Same-day = pre. Pre: DX_DATE <= first_hl_dx_date, Post: DX_DATE > first_hl_dx_date | ✓ |
| Post | Same-day = post | |
| Exclude same-day | Neither pre nor post | |

**User's choice:** Pre (same-day counted as pre-HL)
**Notes:** Consistent with R/56's strict > convention

---

## Output Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| New script, new file (Recommended) | R/58_cancer_summary_pre_post.R, outputs cancer_summary_table_pre_post.xlsx | ✓ |
| Modify R/55 in-place | Update R/55 to replace existing columns | |
| Add sheets to existing | Add pre/post sheets to existing cancer_summary_table.xlsx | |

**User's choice:** New script, new file
**Notes:** Leaves R/55 and R/56 outputs untouched

---

## Patients with No Dates

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude from pre/post (Recommended) | Still in Total Patients, excluded from Pre/Post/Both columns | ✓ |
| Count as pre | Treat NA-date codes as pre-HL | |
| Exclude entirely | Drop from table if no dates exist | |

**User's choice:** Exclude from pre/post only
**Notes:** Appear in Total Patients but not in temporal columns

---

## Sheet Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Both sheets (Recommended) | Category Summary + Code Summary, matching R/55 | ✓ |
| Category only | Just category-level sheet | |
| Code only | Just code-level sheet | |

**User's choice:** Both sheets

---

## Sentinel Dates

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, exclude (Recommended) | DX_DATE < 1910-01-01 excluded from pre/post | ✓ |
| No, include | Include all dates | |

**User's choice:** Exclude sentinels
**Notes:** Consistent with R/56

---

## HL Row Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Same as others | Treat C81 identically to all other codes | |
| Flag it specially | Include with visual indicator | |
| Exclude HL row | Remove C81/Hodgkin Lymphoma from table | ✓ |

**User's choice:** Exclude HL row
**Notes:** C81 is the anchor diagnosis — pre/post is self-referential. Table focuses on OTHER cancers.

---

## Column Ordering

| Option | Description | Selected |
|--------|-------------|----------|
| Group pre/post together (Recommended) | Category, Total Patients, Confirmed (2+), Confirmed (7-Day), Pre-HL, Post-HL, Both, Total Records | ✓ |
| Pre/post first | Pre/Post/Both before confirmation columns | |
| You decide | Claude picks | |

**User's choice:** Group pre/post together after confirmation columns

---

## Styling

| Option | Description | Selected |
|--------|-------------|----------|
| Same styling (Recommended) | Dark header, totals row, comma counts, frozen pane, Calibri | ✓ |
| Different styling | Custom look | |

**User's choice:** Same styling as R/55

---

## TUMOR_REGISTRY Codes

| Option | Description | Selected |
|--------|-------------|----------|
| DIAGNOSIS only (Recommended) | Consistent with R/55 and R/56 | ✓ |
| Both tables | Include TUMOR_REGISTRY cancer codes | |

**User's choice:** DIAGNOSIS only

---

## HL Date Source

| Option | Description | Selected |
|--------|-------------|----------|
| Use existing RDS | Load confirmed_hl_cohort.rds as-is from R/55 | ✓ |
| Change the source | Modify first_hl_dx_date computation | |

**User's choice:** Use existing RDS

---

## Claude's Discretion

- Companion CSV file production
- Population denominator note in xlsx
- PREFIX_MAP handling (copy vs factor out)

## Deferred Ideas

None — discussion stayed within phase scope
