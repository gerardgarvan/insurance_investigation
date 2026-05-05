# Phase 43: Establish Treatment Lengths for SCT, Chemo, and Radiation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-05
**Phase:** 43-establish-treatment-lengths-for-sct-chemo-and-radiation
**Areas discussed:** Duration definition, Episode boundaries, Output format, Treatment type scope

---

## Duration Definition

| Option | Description | Selected |
|--------|-------------|----------|
| First-to-last date span | Days between earliest and latest procedure/treatment date per patient per type | ✓ |
| First-to-last + trailing window | Days from first to last + fixed tail (e.g., +30 days) for last cycle to complete | |
| Count of distinct treatment dates | Number of unique dates with treatment activity (intensity measure) | |
| You decide | Claude picks based on data | |

**User's choice:** First-to-last date span
**Notes:** None

### Follow-up: Include count alongside span?

| Option | Description | Selected |
|--------|-------------|----------|
| Both span and count | Include days first-to-last AND number of distinct treatment dates | ✓ |
| Span only | Just calendar days between first and last | |

**User's choice:** Both span and count

### Follow-up: Single-date patients (span=0)?

| Option | Description | Selected |
|--------|-------------|----------|
| Include as 0-day span | Keep in dataset with span=0, count=1 | ✓ |
| Flag but include | Include with flag column (single_date_only=TRUE) | |
| You decide | Claude picks pragmatic approach | |

**User's choice:** Include as 0-day span

---

## Episode Boundaries

| Option | Description | Selected |
|--------|-------------|----------|
| Overall span only | One first-to-last per patient per type, no splitting | |
| Gap-based episode detection | Split when gap > threshold (90+ days = new episode) | |
| Both overall + episodes | Overall span AND episode detection within it | ✓ |

**User's choice:** Both overall + episodes

### Follow-up: Gap threshold?

| Option | Description | Selected |
|--------|-------------|----------|
| 90 days | Standard oncology gap — 3 months without treatment. Common in HL literature. | ✓ |
| 60 days | Shorter gap — catches earlier re-initiations | |
| You decide | Claude picks based on HL patterns | |

**User's choice:** 90 days

### Follow-up: Episode detail level?

| Option | Description | Selected |
|--------|-------------|----------|
| Episode summary per patient | Each row = one episode with start, end, span, count | |
| Just episode count + longest | Lighter: patient ID, type, total episodes, longest span | |
| You decide | Claude picks what fits pipeline patterns | ✓ |

**User's choice:** You decide (Claude's Discretion)

---

## Output Format

| Option | Description | Selected |
|--------|-------------|----------|
| Per-patient summary tibble | R tibble saved as RDS | ✓ |
| Styled xlsx report | Excel workbook with openxlsx2 patterns | ✓ |
| Distribution visualization | Histogram/boxplot PNG | ✓ |
| Console summary statistics | Print median, IQR during execution | ✓ |

**User's choice:** All four outputs selected (multiSelect)

### Follow-up: xlsx sheet structure?

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-sheet (per type + summary) | Separate sheets per treatment type + summary sheet | |
| Single summary sheet only | One sheet with aggregate stats per type | |
| You decide | Claude picks based on data volume | ✓ |

**User's choice:** You decide (Claude's Discretion)

---

## Treatment Type Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Chemotherapy | All chemo codes (~200+ in TREATMENT_CODES) | ✓ |
| Radiation | All radiation codes (daily fractions pattern) | ✓ |
| SCT (Stem Cell Transplant) | All SCT codes (usually single event) | ✓ |
| Immunotherapy | CAR-T and checkpoint inhibitors | ✓ |

**User's choice:** All four types selected (multiSelect)

### Follow-up: Regimen distinction within chemo?

| Option | Description | Selected |
|--------|-------------|----------|
| All chemo as one type | Pool all codes, no regimen distinction | ✓ |
| Distinguish ABVD vs other | Try to identify ABVD cycles vs other chemo | |
| You decide | Claude assesses feasibility | |

**User's choice:** All chemo as one type

---

## Claude's Discretion

- Episode output granularity (row-per-episode or counts-only)
- xlsx sheet structure (multi-sheet or single summary)
- Visualization style (histogram vs boxplot)
- Whether to reuse R/10_treatment_payer.R compute functions or write new

## Deferred Ideas

None — discussion stayed within phase scope
