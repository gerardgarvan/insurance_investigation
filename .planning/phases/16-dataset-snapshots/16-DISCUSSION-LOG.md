# Phase 16: Dataset Snapshots - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-04-03
**Phase:** 16-dataset-snapshots
**Areas discussed:** Snapshot granularity, Helper function design, Figure/table scope, Naming conventions

---

## Snapshot Granularity

### Q1: Which cohort build steps should get RDS snapshots?

| Option | Description | Selected |
|--------|-------------|----------|
| Filter steps only | Snapshot after steps 0-3 (initial, HL flag, enrollment) + final assembly. 4-5 files. Matches SNAP-01 'named filter step' language. | ✓ |
| All major stages | Snapshot after every section (all 13 stages). ~13 files. Maximum reproducibility but large disk footprint. | |
| Filter steps + enrichment milestones | Filter steps (0-3) + treatment flags + surveillance + final. ~7 files. Captures the data at key enrichment boundaries. | |

**User's choice:** Filter steps only (Recommended)
**Notes:** Only the steps that change patient count get snapshots. Enrichment stages (joins/mutates) are excluded.

### Q2: Should filter-step snapshots also save to the attrition_log automatically?

| Option | Description | Selected |
|--------|-------------|----------|
| Separate | saveRDS() calls added after each log_attrition() call. Two independent systems. | ✓ |
| Combined helper | A log_and_snapshot() wrapper that does both in one call. | |

**User's choice:** Separate (Recommended)
**Notes:** Snapshot saving and attrition logging remain independent concerns.

---

## Helper Function Design

### Q3: Where should save_output_data() live?

| Option | Description | Selected |
|--------|-------------|----------|
| New utils_snapshot.R | Dedicated file for snapshot logic. Sourced by 00_config.R alongside other utils. | ✓ |
| In utils_attrition.R | Closest thematic fit. Keeps utility file count lower. | |
| In 00_config.R directly | Helper defined where CONFIG paths live. Simplest but config file is already 400+ lines. | |

**User's choice:** New utils_snapshot.R (Recommended)
**Notes:** Clean separation between caching (load-time) and snapshots (output-time).

### Q4: What should save_output_data() handle beyond saveRDS?

| Option | Description | Selected |
|--------|-------------|----------|
| Path + log + dir creation | Constructs path from name + subdir, creates dir if needed, calls saveRDS, logs dimensions. | ✓ |
| Above + row/col attributes | Same plus stores nrow/ncol/timestamp as attributes for later introspection. | |
| You decide | Claude has discretion on helper internals. | |

**User's choice:** Path + log + dir creation (Recommended)
**Notes:** Minimal and useful. No extra attributes needed.

---

## Figure/Table Scope

### Q5: Which scripts should get figure/table backing data snapshots?

| Option | Description | Selected |
|--------|-------------|----------|
| All visualization scripts | Waterfall, Sankey, encounter analysis, and PPTX tables. Full SNAP-03/04 compliance. | ✓ |
| Only encounter analysis + PPTX | Skip waterfall and Sankey (simpler data). | |
| Only PPTX-feeding scripts | Narrowest scope. | |

**User's choice:** All visualization scripts (Recommended)
**Notes:** Every figure and summary table gets a backing .rds file.

### Q6: For 11_generate_pptx.R, save every slide table or just unique summary tables?

| Option | Description | Selected |
|--------|-------------|----------|
| Unique summary tables only | Save distinct data frames rendered into tables. ~5-8 unique data frames. | ✓ |
| Every slide table | One .rds per slide table. Maximally granular but some are duplicates. | |

**User's choice:** Unique summary tables only (Recommended)
**Notes:** Avoids saving duplicate/pivoted versions of the same data.

---

## Naming Conventions

### Q7: How should cohort step snapshot files be named?

| Option | Description | Selected |
|--------|-------------|----------|
| Numbered + descriptive | cohort_00_initial_population.rds, cohort_01_hl_flag.rds, etc. Numbers match build order. | ✓ |
| Descriptive only | cohort_initial_population.rds, etc. No numbers. | |
| You decide | Claude picks naming matching attrition log step names. | |

**User's choice:** Numbered + descriptive (Recommended)
**Notes:** Numbers ensure correct sort order; names match attrition log steps.

### Q8: How should figure/table backing data files be named?

| Option | Description | Selected |
|--------|-------------|----------|
| Match output filename + _data | waterfall_attrition_data.rds, sankey_patient_flow_data.rds, etc. | ✓ |
| Short descriptive names | waterfall_data.rds, sankey_data.rds, etc. | |
| You decide | Claude picks traceable names. | |

**User's choice:** Match output filename + _data (Recommended)
**Notes:** Easy to trace which .rds backs which figure/table.

---

## Claude's Discretion

- Exact list of unique summary tables from 11_generate_pptx.R (determined during planning)
- Console log formatting details
- save_output_data() parameter design (subdir param vs separate wrappers)
- saveRDS compression settings

## Deferred Ideas

None -- discussion stayed within phase scope.
