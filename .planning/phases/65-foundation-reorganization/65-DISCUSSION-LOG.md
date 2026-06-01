# Phase 65: Foundation Reorganization - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-06-01
**Phase:** 65-foundation-reorganization
**Areas discussed:** Utils scope & naming, Foundation numbering, Auto-sourcing mechanism

---

## Utils Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, move all 8 | Move utils_pptx.R too. It's a utility module -- consistent to keep them together. Update its source() callers. | ✓ |
| Move 7, leave pptx | Keep utils_pptx.R in R/ since it has a different sourcing pattern. Move when those scripts are renumbered in Phase 68. | |
| You decide | Claude picks the approach that's simplest and safest. | |

**User's choice:** Yes, move all 8
**Notes:** All 8 utils files move to R/utils/ including utils_pptx.R despite its different sourcing pattern.

---

## Utils Naming

| Option | Description | Selected |
|--------|-------------|----------|
| Keep utils_ prefix | Files stay as utils_dates.R, utils_icd.R, etc. inside R/utils/. Redundant but grep-friendly. | |
| Strip prefix | Rename to dates.R, icd.R, etc. inside R/utils/. Cleaner paths. Requires updating all source() calls and comments. | |
| You decide | Claude picks whichever causes fewer downstream changes. | ✓ |

**User's choice:** You decide
**Notes:** Deferred to Claude's discretion.

---

## Foundation Numbering

| Option | Description | Selected |
|--------|-------------|----------|
| 01=DuckDB, 02=Load, 03=Payer | DuckDB ingest first (creates the database), then data loading, then payer harmonization. Matches USE_DUCKDB=TRUE execution order. | |
| 01=Load, 02=Payer, 03=DuckDB | Keep current ordering for Load (01) and Payer (02). DuckDB ingest at 03 since it's optional. Matches legacy CSV workflow. | ✓ |
| 01=DuckDB, 02=Payer, 03=Load | DuckDB first (infrastructure), payer harmonization (transforms), then data loading. | |

**User's choice:** 01=Load, 02=Payer, 03=DuckDB
**Notes:** Preserves existing script numbers for 01 and 02. Only 25_duckdb_ingest.R is actually renumbered to 03.

---

## Auto-Sourcing Mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Dynamic sourcing | Use list.files() + lapply(source). New utils files auto-discovered without config edits. | ✓ |
| Explicit source lines | Keep individual source() lines, just update paths. More visible/debuggable. | |
| You decide | Claude picks based on what's safest for this project. | |

**User's choice:** Dynamic sourcing (Recommended)
**Notes:** Replace 7 explicit source() lines with dynamic sourcing via list.files + lapply.

---

## Claude's Discretion

- Utils naming: Decided to keep `utils_` prefix for minimal source() change impact and grep-ability
- Smoke test design: Will be determined during planning

## Deferred Ideas

None -- discussion stayed within phase scope
