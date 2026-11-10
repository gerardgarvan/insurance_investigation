---
phase: quick
plan: 261110-luq
subsystem: tooling
tags: [dependency-map, audit, static-analysis, visNetwork]
key-files:
  created:
    - R/tools/dep_map.R
  modified: []
decisions: []
metrics:
  completed: "2026-11-10"
---

# Quick Task 261110-luq: Build Static Dependency Map of R Code

One-liner: Standalone read-only AST parser that maps source/read/write/call edges across all R pipeline scripts and writes five audit outputs to output/dep_map/.

## What Was Done

Wrote `R/tools/dep_map.R` as a 1,055-line standalone script. No existing R/ files were modified.

**Ten sections:**

- **Section 0:** Bootstrap — libraries, `out_dir`, versioned-stem function (no silent overwrites).
- **Section 1:** File inventory — separates active, archived, and self.
- **Section 2:** CONFIG static value table — extracts `CONFIG$xxx <- "literal"` pairs via regex over `00_config.R` text; defers to `{DATE}` token for date patterns.
- **Section 3:** AST parser — `parse_one_file()` wraps `parse()` + `utils::getParseData()`; detects source/write/read calls by `SYMBOL_FUNCTION_CALL` token, function definitions by `LEFT_ASSIGN`/`EQ_ASSIGN` + `FUNCTION` sibling, and project function calls filtered against a `BASE_FUNS` exclusion list. Progress every 20 files.
- **Section 4:** `resolve_path()` — substitutes CONFIG values, collapses date expressions to `{DATE}`, strips simple wrappers (`here()`, `file.path()`, `paste0()`, `glue()`), marks unresolved for remaining variable references.
- **Section 5:** Collects `fn_defs` and `fn_calls` from raw records; splits into project-defined and undefined call sets.
- **Section 6:** Assembles `edges.csv` (from, to, edge_type, artifact, file, line, resolved) and `nodes.csv` (id, type, phase prefix, archived). Classifies db_read vs db_write by function name and SQL verb. Types: script, util, artifact, db_table, function, archived.
- **Section 7:** `visNetwork` interactive HTML — UF colours (#0021A5 scripts, #FA4616 risk), hierarchical LR layout, hover tooltips with file:line, node-id search, highlight-nearest.
- **Section 8:** Mermaid flowchart — script and artifact nodes, source/writes/reads edges only.
- **Section 9:** Nine-section risk report with file:line citations.
  - R1 orphan reads (read but never written) + near-miss detection (same stem, different extension)
  - R2 dead writes (written but never read)
  - R3 mtime-based `list.files()` selection, with pin check
  - R4 same-date overwrite risk (dated artifact, no version-check guard)
  - R5 unresolved paths
  - R6 hard-coded absolute paths (/blue, /orange, /ufrc, /home, C:\\, ~/)
  - R7a duplicate function definitions; R7b never-called functions; R7c undefined calls
  - R8 Kahn's topological sort + cycle detection + order inversion report
  - R9 unreachable scripts (not reachable from numeric-prefixed entry points via source() BFS; R/00_config.R implicitly reaches all utils)
- **Section 10:** Final `[dep_map] DONE` summary message with all risk counts.

## Verification

Syntax check: brace/paren balance verified via Python state-machine parser (Paren=0, Brace=0).

HiPerGator run required to verify five outputs. Command:

```r
module load R/4.5
# From repo root:
source("R/tools/dep_map.R", local = new.env(parent = globalenv()))
list.files("output/dep_map")
```

Paste back the `[dep_map] DONE` line and `list.files()` output.

## Deviations

None — plan executed as written.

## Commit

- `4c5a7e3` feat(261110-luq): add R/tools/dep_map.R — static dependency mapper
