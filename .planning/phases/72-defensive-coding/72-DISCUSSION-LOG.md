# Phase 72: Defensive Coding - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-02
**Phase:** 72-defensive-coding
**Areas discussed:** Validation scope, checkmate integration, Assertion depth, Error message style

---

## Validation Scope

### Q1: Which scripts should get checkmate assertions?

| Option | Description | Selected |
|--------|-------------|----------|
| Critical path only | Foundation (00-03), cohort (10-14), treatment (20-29) — ~25 scripts forming the core pipeline | ✓ |
| All production scripts | All 67 numbered scripts get file/RDS existence checks at entry | |
| Data-loading + joins only | Only where data enters the system and at major join points | |

**User's choice:** Critical path only
**Notes:** User selected the focused approach targeting scripts where bad inputs cause the worst cascading failures.

### Q2: Should cancer and payer decades also get assertions?

| Option | Description | Selected |
|--------|-------------|----------|
| Include cancer + payer too | Foundation (00-03), cohort (10-14), treatment (20-29), cancer (40-53), payer (60-69) — ~40 scripts | ✓ |
| Just foundation through treatment | 00-03, 10-14, 20-29 only (~25 scripts) | |
| You decide | Let Claude assess highest risk scripts | |

**User's choice:** Include cancer + payer too
**Notes:** Expanded from "critical path only" to include all production decades that read upstream RDS artifacts.

### Q3: Should test and ad-hoc scripts be excluded?

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude both | Test (80-87) and ad-hoc (90-99) are diagnostic/one-off | ✓ |
| Include test scripts only | Add assertions to test scripts (80-87) only | |
| Include all | Every script gets assertions | |

**User's choice:** Exclude both
**Notes:** Focus on production pipeline; test/ad-hoc scripts handle their own errors.

---

## checkmate Integration

### Q1: Where should checkmate be loaded?

| Option | Description | Selected |
|--------|-------------|----------|
| In 00_config.R | Load once in foundation config; available everywhere via source chain | ✓ |
| Per-script library() calls | Each script adds its own library(checkmate) | |
| In a new utils module | Create R/utils/utils_assertions.R that loads checkmate | |

**User's choice:** In 00_config.R
**Notes:** Leverages existing source() chain so all production scripts get checkmate automatically.

### Q2: How should existing tryCatch and stopifnot be handled?

| Option | Description | Selected |
|--------|-------------|----------|
| Leave existing, add new | Keep ~30 tryCatch and 2 stopifnot as-is. Add NEW checkmate assertions. | ✓ |
| Replace stopifnot with checkmate | Convert 2 stopifnot calls for consistency; leave tryCatch | |
| Full audit and harmonize | Review all 30+ patterns and replace where appropriate | |

**User's choice:** Leave existing, add new
**Notes:** No refactoring of working defensive code. Different tools serve different purposes.

### Q3: Should checkmate be added to renv.lock?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, update renv | renv::install("checkmate") and renv::snapshot() | ✓ |
| Document only | Add to docs but let user handle renv on HiPerGator | |

**User's choice:** Yes, update renv

---

## Assertion Depth

### Q1: How deep should data structure validation go?

| Option | Description | Selected |
|--------|-------------|----------|
| Existence + columns | assert_data_frame + assert_names for critical columns | |
| Add row-count sanity | Above plus nrow checks after joins | |
| Full validation | Existence + columns + row counts + column types + value ranges | ✓ |

**User's choice:** Full validation
**Notes:** User selected the most comprehensive option.

### Q2: For column type checks, which columns?

| Option | Description | Selected |
|--------|-------------|----------|
| Key identifiers only | PATID, ENCOUNTERID, date columns, numeric counts | ✓ |
| All columns in critical tables | Every column in ENROLLMENT, DIAGNOSIS, ENCOUNTER, DEMOGRAPHIC | |
| You decide | Let Claude assess type-sensitivity risk | |

**User's choice:** Key identifiers only
**Notes:** Focus on columns that cause silent bugs when types are wrong.

### Q3: What date range boundaries?

| Option | Description | Selected |
|--------|-------------|----------|
| 1990-2030 range | Dates outside flagged as warnings; pre-2012 legitimately in tumor registry | ✓ |
| 2000-today range | Tighter range but needs exceptions for tumor registry dates | |
| No date range checks | Skip value ranges; historical_flag handles date quality | |

**User's choice:** 1990-2030 range

### Q4: Should range failures be warnings or hard stops?

| Option | Description | Selected |
|--------|-------------|----------|
| Warnings for ranges, hard stops for structure | File/column checks = stop(); date/row-count issues = warning() | ✓ |
| All hard stops | Any assertion failure kills pipeline | |
| All warnings | Nothing stops the pipeline | |

**User's choice:** Warnings for ranges, hard stops for structure

---

## Error Message Style

### Q1: How should error messages be structured?

| Option | Description | Selected |
|--------|-------------|----------|
| Script + context + fix hint | [R/XX ACTION] What failed — expected vs actual — fix hint. Uses glue(). | ✓ |
| Simple context only | State what failed and expected. No fix hints or script prefixes. | |
| Structured with codes | Each assertion gets a code (SAFE-001, etc.) for lookup | |

**User's choice:** Script + context + fix hint

### Q2: Should warnings use the same format as errors?

| Option | Description | Selected |
|--------|-------------|----------|
| Same format, different prefix | Warnings use same glue() template with WARNING prefix | ✓ |
| Simpler for warnings | Shorter/less structured since they don't stop execution | |

**User's choice:** Same format, different prefix

### Q3: Helper function or inline glue()?

| Option | Description | Selected |
|--------|-------------|----------|
| Helper in utils | R/utils/utils_assertions.R with assert_rds_exists(), warn_date_range(), etc. | ✓ |
| Inline glue() everywhere | Each assertion writes its own glue() message directly | |
| You decide | Let Claude determine based on repetition patterns | |

**User's choice:** Helper in utils

---

## Claude's Discretion

- Exact assertion placement within each script
- Which specific columns constitute "key identifiers" beyond PATID/ENCOUNTERID
- Row count thresholds for sanity checks
- Wave/plan decomposition strategy
- Internal structure of utils_assertions.R

## Deferred Ideas

None — discussion stayed within phase scope
