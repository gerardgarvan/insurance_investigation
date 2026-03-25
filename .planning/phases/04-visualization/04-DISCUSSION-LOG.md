# Phase 4: Visualization - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 04-visualization
**Areas discussed:** Waterfall design, Sankey flow axes, HIPAA suppression, Output aesthetics

---

## Waterfall Design

| Option | Description | Selected |
|--------|-------------|----------|
| Vertical bars | Classic waterfall -- vertical bars decreasing left-to-right, one per filter step | :heavy_check_mark: |
| Horizontal bars | Horizontal bars decreasing top-to-bottom, reads like CONSORT flow | |
| CONSORT flow diagram | Box-and-arrow CONSORT-style using consort package | |

**User's choice:** Vertical bars
**Notes:** Most common in epidemiological cohort papers

| Option | Description | Selected |
|--------|-------------|----------|
| Count + percentage | Each bar labeled with N remaining AND % excluded | :heavy_check_mark: |
| Count only | Just N remaining on each bar | |
| Count + exclusion reason | N on bar plus text annotation between bars with exclusion reason | |

**User's choice:** Count + percentage
**Notes:** E.g., "N=4,200 (-12.3%)"

| Option | Description | Selected |
|--------|-------------|----------|
| Gradient by remaining % | Bars shade from green to red based on attrition severity | |
| Single color | All bars same color (e.g., steel blue) | :heavy_check_mark: |
| Two-tone | Remaining portion + excluded portion stacked | |

**User's choice:** Single color
**Notes:** Bar height already tells the attrition story

| Option | Description | Selected |
|--------|-------------|----------|
| Total cohort only | One set of bars showing overall attrition | :heavy_check_mark: |
| Faceted by payer | Separate small waterfall panels per payer category | |

**User's choice:** Total cohort only
**Notes:** Payer stratification is the Sankey's job

---

## Sankey Flow Axes

| Option | Description | Selected |
|--------|-------------|----------|
| Payer -> Treatment type | Axis 1: Payer category. Axis 2: Treatment received (combinations) | :heavy_check_mark: |
| Payer -> Diagnosis -> Treatment | 3 axes with HL subtype or diagnosis year as middle axis | |
| Payer -> Treatment -> Outcome | 3 axes but outcome data likely unavailable | |

**User's choice:** Payer -> Treatment type (2 axes)
**Notes:** Shows how patients flow from insurance to treatment

| Option | Description | Selected |
|--------|-------------|----------|
| Combination categories | Mutually exclusive: Chemo only, Radiation only, Chemo+Rad, SCT, No treatment | :heavy_check_mark: |
| Separate flows per treatment | Each treatment its own flow, patients in multiple flows | |
| Any treatment vs none | Binary: Had treatment vs No treatment evidence | |

**User's choice:** Combination categories
**Notes:** Each patient in exactly one category

| Option | Description | Selected |
|--------|-------------|----------|
| Color by payer | Flows colored by payer category throughout | :heavy_check_mark: |
| Color by treatment | Flows colored by destination treatment category | |

**User's choice:** Color by payer
**Notes:** Matches requirement "stratified by payer"

| Option | Description | Selected |
|--------|-------------|----------|
| Show all 9 categories | Keep all payer categories even if some are thin | |
| Collapse small categories | Group small-N categories into "Other" for visualization | :heavy_check_mark: |
| You decide | Claude decides based on data distribution | |

**User's choice:** Collapse small categories
**Notes:** Cleaner diagram with readable flow widths

| Option | Description | Selected |
|--------|-------------|----------|
| Stratum labels + counts | Category name + N on strata, flows unlabeled | :heavy_check_mark: |
| No numeric labels | Names only, visual width is the indicator | |
| Full labels everywhere | Strata and flow bands both labeled | |

**User's choice:** Stratum labels + counts
**Notes:** E.g., "Medicare (N=1,200)"

| Option | Description | Selected |
|--------|-------------|----------|
| Simplify rare combos | Merge combos with <=10 patients into broader category | :heavy_check_mark: |
| Keep all combos | Show every combination regardless of size | |

**User's choice:** Simplify rare combos
**Notes:** Handles both readability and incidental HIPAA compliance

---

## HIPAA Suppression

| Option | Description | Selected |
|--------|-------------|----------|
| Labels only | Replace numeric labels with "<11" for counts 1-10 | |
| Labels + visual masking | Suppress labels AND gray out visual representation | |
| Full suppression | Remove small cells entirely | |
| Skip for v1 | Don't bother with HIPAA suppression | :heavy_check_mark: |

**User's choice:** Skip for v1
**Notes:** User explicitly said "don't bother with HIPAA suppression". Data stays on HiPerGator HIPAA-compliant environment, outputs are exploratory. VIZ-03 deferred.

---

## Output Aesthetics

| Option | Description | Selected |
|--------|-------------|----------|
| theme_minimal() | Clean, modern, minimal gridlines | :heavy_check_mark: |
| theme_classic() | White background, black axes, no gridlines | |
| You decide | Claude picks best for each chart | |

**User's choice:** theme_minimal()

| Option | Description | Selected |
|--------|-------------|----------|
| Colorblind-safe qualitative | viridis discrete or RColorBrewer Set2 | :heavy_check_mark: |
| Custom clinical colors | Manual color assignment per payer | |
| You decide | Claude picks palette | |

**User's choice:** Colorblind-safe qualitative

| Option | Description | Selected |
|--------|-------------|----------|
| 10x7 inches, 300 DPI | Standard presentation/report size | :heavy_check_mark: |
| 12x8 inches, 150 DPI | Larger canvas at screen resolution | |
| You decide | Claude picks dimensions | |

**User's choice:** 10x7 inches, 300 DPI

| Option | Description | Selected |
|--------|-------------|----------|
| Both (viewer + PNG) | Display in RStudio AND save PNG | :heavy_check_mark: |
| PNG only | Save to file only | |

**User's choice:** Both

---

## Claude's Discretion

- Exact bar color (steel blue family)
- Specific colorblind-safe palette (viridis vs Set2)
- ggalluvial geom configuration (lode ordering, curve type)
- Treatment combination grouping threshold tuning
- Font sizes, spacing, axis label formatting

## Deferred Ideas

- VIZ-03 HIPAA suppression -- v2 if outputs shared externally
- Faceted waterfall by payer -- supplementary figure for v2
- Interactive Sankey (plotly/networkD3) -- v1 uses static ggalluvial
- Treatment timing visualization -- separate analysis phase
