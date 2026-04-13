# Phase 21: Generalize Phase 19 to All Sources - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-13
**Phase:** 21-generalize-phase-19-to-all-sources
**Areas discussed:** Cross-site comparison, Analysis scope, Script design, Output structure

---

## Cross-site Comparison

### Q1: How should sites be compared in the output?

| Option | Description | Selected |
|--------|-------------|----------|
| Single combined CSVs | One CSV per breakdown type with a SOURCE column — all sites in the same file, easy to filter/pivot | ✓ |
| Separate CSVs per site | Each site gets its own set of 5 CSVs (like Phase 19 for UFH) | |
| Both combined + per-site | Combined CSVs for cross-site comparison PLUS per-site CSVs for deep dives | |

**User's choice:** Single combined CSVs
**Notes:** Mirrors Phase 19 structure but adds site dimension

### Q2: Should the output include a cross-site ranking or summary?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add a cross-site summary CSV | One row per site with overall missingness rates, quick comparison at a glance | ✓ |
| No, combined CSVs are enough | Users can pivot the combined CSVs themselves | |
| You decide | Claude decides based on data structure | |

**User's choice:** Yes, add a cross-site summary CSV

### Q3: Should the cross-site summary include severity flags?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add severity flags | Add missingness_severity column with HIGH/MODERATE/LOW | |
| Numbers only | Just the rates — let the user interpret | ✓ |
| You decide | Claude picks based on patterns | |

**User's choice:** Numbers only

---

## Analysis Scope

### Q1: Same 5 breakdowns as Phase 19 per site?

| Option | Description | Selected |
|--------|-------------|----------|
| Same 5 breakdowns | Reuse Phase 19's proven structure with SOURCE as grouping dimension | ✓ |
| Subset only | Skip some breakdowns to reduce output volume | |
| Expand with new dimensions | Add new breakdowns beyond Phase 19 | |

**User's choice:** Same 5 breakdowns

### Q2: Which patient population?

| Option | Description | Selected |
|--------|-------------|----------|
| HL cohort patients only | Same population as Phase 19, directly relevant to research question | ✓ |
| All patients per site | All patients from each site in raw data | |
| Both HL cohort and all patients | Two-level analysis | |

**User's choice:** HL cohort patients only

---

## Script Design

### Q1: How should the new script relate to Phase 19's script?

| Option | Description | Selected |
|--------|-------------|----------|
| New standalone script | Create new script, Phase 19 script stays unchanged | ✓ |
| Refactor Phase 19 script | Modify R/18 to accept a site parameter | |
| You decide | Claude picks the approach | |

**User's choice:** New standalone script

### Q2: Processing approach?

| Option | Description | Selected |
|--------|-------------|----------|
| Single grouped pass | Use dplyr group_by(SOURCE) for all breakdowns | ✓ |
| Loop over sites | Process each site sequentially in a for loop | |
| You decide | Claude picks based on data size and clarity | |

**User's choice:** Single grouped pass

---

## Output Structure

### Q1: CSV naming convention?

| Option | Description | Selected |
|--------|-------------|----------|
| all_source_ prefix | e.g., all_source_payer_raw_value_distribution.csv | ✓ |
| payer_missingness_ prefix | e.g., payer_missingness_raw_values.csv | |
| You decide | Claude picks consistent naming | |

**User's choice:** all_source_ prefix

### Q2: Console output verbosity?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-site summaries | Log overall missingness rate per site plus cross-site comparison | ✓ |
| Minimal — just file names | Only log which CSV files were written | |
| Verbose — all breakdowns | Log every breakdown for every site | |

**User's choice:** Per-site summaries

---

## Claude's Discretion

- Exact script number (next available)
- Cross-site summary CSV column structure
- Console formatting details
- Handling sites with very few encounters
- Whether to include an "ALL" aggregate row

## Deferred Ideas

None — discussion stayed within phase scope
