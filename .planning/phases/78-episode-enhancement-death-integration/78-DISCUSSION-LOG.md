# Phase 78: Episode Enhancement & Death Integration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-03
**Phase:** 78-episode-enhancement-death-integration
**Areas discussed:** Death quality profiling, Triggering code description mapping, Cause of death integration, Episode-level scope

---

## Death Quality Profiling

### Q1: Where should the cause of death quality report live?

| Option | Description | Selected |
|--------|-------------|----------|
| New standalone script (Recommended) | Dedicated R/XX producing console + xlsx. Follows R/35, R/40 pattern. | ✓ |
| New section in R/52 | Add quality profiling as gating section in R/52. | |
| You decide | Claude picks. | |

**User's choice:** New standalone script
**Notes:** None

### Q2: What stratifications in the death cause quality report?

| Option | Description | Selected |
|--------|-------------|----------|
| Payer + site + overall (Recommended) | Completeness by AMC payer, by partner site, plus overall. | ✓ |
| Overall + payer only | Skip site stratification. | |
| Overall only | Minimal report. | |

**User's choice:** Payer + site + overall
**Notes:** None

### Q3: What output format?

| Option | Description | Selected |
|--------|-------------|----------|
| Console + xlsx (Recommended) | Console diagnostics + multi-sheet xlsx. Matches R/35. | ✓ |
| Console only | No persistent file. | |
| Console + csv | Flat CSV export. | |

**User's choice:** Console + xlsx
**Notes:** None

### Q4: Should the quality report gate R/52's integration?

| Option | Description | Selected |
|--------|-------------|----------|
| Hard gate at 40% threshold | Skip column if >40% missing. | |
| Soft warning, always integrate | Always add column, warn if >40%. | |
| You decide | Claude picks based on data. | ✓ |

**User's choice:** You decide
**Notes:** Claude's discretion based on actual quality findings

---

## Triggering Code Description Mapping

### Q1: What should triggering_code_description contain?

| Option | Description | Selected |
|--------|-------------|----------|
| Drug group from DRUG_GROUPINGS | Category labels (Chemotherapy, Radiation, etc.) | |
| Human-readable name from code_descriptions.rds | Drug/procedure names (Doxorubicin HCl, etc.) | ✓ |
| Both as separate columns | Two new columns. | |

**User's choice:** Human-readable name from code_descriptions.rds
**Notes:** None

### Q2: Where does DRUG_GROUPINGS get used?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-episode cancer_category verification | Quality check, not a new column. | |
| Separate drug_group column alongside description | Two new columns: description + group. | ✓ |
| You decide | Claude determines. | |

**User's choice:** Separate drug_group column alongside description
**Notes:** None

### Q3: How should multi-code descriptions/groups be joined?

| Option | Description | Selected |
|--------|-------------|----------|
| Semicolon-separated matching order (Recommended) | Per-code mapping, semicolon-joined. Matches R/52 pattern. | ✓ |
| Most common group only | Single value per episode. | |
| You decide | Claude picks. | |

**User's choice:** Semicolon-separated matching order
**Notes:** None

---

## Cause of Death Integration

### Q1: Where does cause_of_death column appear?

| Option | Description | Selected |
|--------|-------------|----------|
| Column 15 at end (Recommended) | Non-breaking change. NA for treatment rows. | ✓ |
| After cancer_category (column 13) | Groups context together but shifts positions. | |
| You decide | Claude picks. | |

**User's choice:** Column 15 at end
**Notes:** None

### Q2: How should unmapped/missing codes be represented?

| Option | Description | Selected |
|--------|-------------|----------|
| "Unknown or Unspecified" for missing (Recommended) | Matches DEATH_CAUSE_MAP Phase 75 D-05. Makes missingness visible. | ✓ |
| NA for all missing | Blends with treatment rows. | |
| Empty string for treatment, Unknown for missing death | Three states. | |

**User's choice:** "Unknown or Unspecified" for missing
**Notes:** None

### Q3: Should gantt_detail_v2.csv also get cause_of_death?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, both CSVs (Recommended) | Consistent schemas. Detail inherits episode columns. | ✓ |
| Episodes only | Detail stays at 13 columns. | |
| You decide | Claude picks. | |

**User's choice:** Yes, both CSVs
**Notes:** None

### Q4: How should >40% missingness footnote work?

| Option | Description | Selected |
|--------|-------------|----------|
| Console warning + quality report flag (Recommended) | R/52 logs warning, quality xlsx documents breakdown. No CSV embedding. | ✓ |
| Footnote row in xlsx exports | Bottom row in xlsx with missingness %. | |
| You decide | Claude picks. | |

**User's choice:** Console warning + quality report flag
**Notes:** None

---

## Episode-Level Scope

### Q1: "Populated for all episodes" meaning?

| Option | Description | Selected |
|--------|-------------|----------|
| Just add new columns (Recommended) | No linkage changes. Unlinked keep NA. | ✓ |
| Improve linkage coverage | Wider window, additional fallbacks. | |
| You decide | Claude interprets. | |

**User's choice:** Just add new columns
**Notes:** None

### Q2: Should new columns propagate to Gantt v2?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add drug_group to Gantt v2 (Recommended) | Gantt episodes 15->16 columns. | ✓ |
| R/28 only, not Gantt | Minimal schema change. | |
| You decide | Claude picks. | |

**User's choice:** Yes, add drug_group to Gantt v2
**Notes:** None

---

## Claude's Discretion

- D-04: Hard gate vs soft warning for >40% cause of death missingness in R/52
- Script number assignment for new death cause quality script

## Deferred Ideas

None — discussion stayed within phase scope
