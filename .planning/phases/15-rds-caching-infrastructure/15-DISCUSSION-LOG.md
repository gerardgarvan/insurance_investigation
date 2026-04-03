# Phase 15: RDS Caching Infrastructure - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-04-03
**Phase:** 15-rds-caching-infrastructure
**Areas discussed:** Time savings tracking, Cache invalidation, Cache scope

---

## Time Savings Tracking

| Option | Description | Selected |
|--------|-------------|----------|
| RDS attribute | Store original CSV parse time as attr() on the saved object. readRDS() preserves attributes, so on cache hit you can show savings. Zero extra files. | Y |
| Separate metadata file | Write a small JSON/RDS alongside each table (e.g., ENROLLMENT_meta.rds) with parse time, timestamp, row count. More visible but doubles file count. | |
| You decide | Claude picks the approach during planning | |

**User's choice:** RDS attribute (Recommended)
**Notes:** Clean approach, zero extra files. `attr(df, "csv_parse_seconds")` stored once, retrieved on every cache hit.

---

## Cache Invalidation

| Option | Description | Selected |
|--------|-------------|----------|
| Mtime only + FORCE_RELOAD | Simple: RDS newer than CSV = cache hit. If code changes, set FORCE_RELOAD <- TRUE once. Exploratory pipeline, user knows when code changes. | Y |
| Mtime + schema hash | Store a hash of col_spec + validation logic version. Auto-invalidate if schema changes. More robust but adds complexity for infrequent code changes. | |
| You decide | Claude picks the approach during planning | |

**User's choice:** Mtime only + FORCE_RELOAD (Recommended)
**Notes:** Simple invalidation appropriate for an exploratory pipeline where the user controls code changes.

---

## Cache Scope - TUMOR_REGISTRY_ALL

| Option | Description | Selected |
|--------|-------------|----------|
| Reconstruct always | bind_rows(TR1, TR2, TR3) is fast (~milliseconds for ~1K rows). Caching separately adds a file that can go stale. | |
| Cache it too | Save TUMOR_REGISTRY_ALL.rds for consistency. One more file but avoids even trivial bind_rows cost. | Y |
| You decide | Claude picks during planning | |

**User's choice:** Cache it too
**Notes:** User prefers consistency — all loaded tables get corresponding RDS files.

---

## Cache Scope - Diagnostic Logging on Cache Hits

| Option | Description | Selected |
|--------|-------------|----------|
| Skip on cache hit | Diagnostics are informational, useful on first load but noisy on repeat runs. Cache hit = data trusted. | Y |
| Always run diagnostics | Run PROVIDER/LAB diagnostics every time regardless of cache status. | |
| You decide | Claude picks during planning | |

**User's choice:** Skip on cache hit (Recommended)
**Notes:** Reduces console noise on cached runs. Diagnostics only fire on CSV parse (first load or FORCE_RELOAD).

---

## Claude's Discretion

- Cache directory creation logic (auto-create vs error if missing)
- Console log formatting details
- Additional RDS attributes beyond parse time

## Deferred Ideas

None -- discussion stayed within phase scope.
