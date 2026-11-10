---
phase: quick
plan: 261110-luq
type: execute
wave: 1
depends_on: []
files_modified:
  - R/tools/dep_map.R
autonomous: true
requirements: [LUQ-DEP-MAP]
must_haves:
  truths:
    - "source() runs to completion on HiPerGator without modifying any R/ files"
    - "output/dep_map/edges.csv, nodes.csv, dep_map.html, dep_map_scripts.mmd, risk_report.md are written"
    - "risk_report.md contains all nine R1–R9 sections with file:line citations"
    - "dep_map.html opens in browser as a self-contained interactive graph"
  artifacts:
    - path: "R/tools/dep_map.R"
      provides: "Static dependency mapper — standalone, read-only"
    - path: "output/dep_map/edges.csv"
      provides: "All dependency edges with type, artifact, file, line, resolved"
    - path: "output/dep_map/nodes.csv"
      provides: "All nodes with type, phase prefix, archived flag"
    - path: "output/dep_map/dep_map.html"
      provides: "Self-contained interactive visNetwork graph"
    - path: "output/dep_map/dep_map_scripts.mmd"
      provides: "Mermaid script->artifact->script flowchart"
    - path: "output/dep_map/risk_report.md"
      provides: "Nine-section risk report with file:line findings"
  key_links:
    - from: "R/tools/dep_map.R"
      to: "output/dep_map/"
      via: "All five outputs written in a single source() run"
    - from: "edges.csv"
      to: "dep_map.html"
      via: "visNetwork built from edges/nodes data frames"
    - from: "edges.csv"
      to: "risk_report.md"
      via: "R1–R9 risk sections derived from edge/node analysis"
---

<objective>
Write R/tools/dep_map.R — a standalone, read-only static dependency mapper for the R pipeline.

Purpose: Surface orphan reads, dead writes, mtime-based "latest file" risks, path resolution gaps, function-call coverage, and execution-order inversions across all R/**/*.R scripts. This is the primary audit tool before any large refactor.

Output: Five files in output/dep_map/ (dated, versioned): edges.csv, nodes.csv, dep_map.html, dep_map_scripts.mmd, risk_report.md.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/ROADMAP.md

Key facts from code inspection:
- Utils loader: R/00_config.R line 4283–4302 — sources all R/utils/*.R via list.files() and prints "Loaded N utility modules from R/utils/"
- R/tools/ already exists (contains build_hrsa_crosswalk.R)
- R/archive/ exists and must be excluded from main parse but listed separately
- Pipeline entry points are numeric-prefixed scripts (R/NNN_*.R)
- DuckDB connection: open_pcornet_con() / close_pcornet_con() pattern (utils_duckdb.R)
- Dated outputs use format(Sys.Date(), ...) or run_date variables — collapse to {DATE} token
- Output privacy: nothing patient-level in output/dep_map/ — paths and counts only
</context>

<tasks>

<task type="auto">
  <name>Task 1: Write R/tools/dep_map.R — parse phase (AST extraction)</name>
  <files>R/tools/dep_map.R</files>
  <action>
Create R/tools/dep_map.R as a standalone script. Structure it in clearly delimited sections:

## SECTION 0 — Bootstrap
Load only base R + packages already in renv lockfile:
  library(visNetwork)   # for HTML output
  library(htmlwidgets)  # selfcontained HTML
  library(dplyr); library(tidyr); library(stringr); library(glue)
  library(here)

Define output directory logic:
  out_dir <- here("output", "dep_map")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dated <- format(Sys.Date(), "%Y%m%d")
  # Version suffix: if output/dep_map/edges_{dated}.csv already exists, append _v2, _v3...
  versioned_stem <- function(base) {
    path <- file.path(out_dir, paste0(base, "_", dated, ".csv"))
    v <- 2L
    while (file.exists(path)) { path <- file.path(out_dir, paste0(base, "_", dated, "_v", v, ".csv")); v <- v + 1L }
    path
  }
  # For non-csv outputs apply the same logic with their extension.

## SECTION 1 — File inventory
Enumerate R files:
  all_r <- list.files(here("R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
  archive_r <- all_r[grepl("/archive/", all_r, fixed = TRUE)]
  parse_r   <- setdiff(all_r, archive_r)
  tools_self <- normalizePath(here("R", "tools", "dep_map.R"), mustWork = FALSE)
  parse_r <- parse_r[normalizePath(parse_r, mustWork = FALSE) != tools_self]
  message(sprintf("[dep_map] Files to parse: %d active, %d archived", length(parse_r), length(archive_r)))

## SECTION 2 — CONFIG static value table
Read R/00_config.R text (readLines, no parse needed for this step):
  cfg_lines <- readLines(here("R", "00_config.R"))
  # Extract CONFIG$xxx <- "literal" or CONFIG[["xxx"]] <- "literal" assignments into a named list
  # config_vals[["xxx"]] <- "literal"  — used later in path resolution
  # Keep only string-literal RHS values; skip computed values.
  # Also capture run_date <- format(Sys.Date()...) patterns → token {DATE}

## SECTION 3 — AST parser (core)
Define parse_one_file(fpath):
  Uses tryCatch around parse(fpath, keep.source = TRUE) + utils::getParseData().
  On parse error: message(sprintf("[dep_map] PARSE ERROR: %s", fpath)); return(NULL).

  After getParseData(), walk the parse tree to detect calls by SYMBOL name:
  Calls of interest (by function name in parse data):
    SOURCE_FNS  <- c("source", "sys.source")
    WRITE_FNS   <- c("saveRDS","write_rds","write.csv","write_csv","fwrite",
                     "write.xlsx","saveWorkbook","writexl::write_xlsx","ggsave",
                     "png","pdf","svg","arrow::write_parquet",
                     "DBI::dbWriteTable","dbExecute")
    READ_FNS    <- c("readRDS","read_rds","read.csv","read_csv","fread",
                     "read.xlsx","read_excel","loadWorkbook",
                     "arrow::read_parquet","list.files",
                     "DBI::dbGetQuery","tbl","dbGetQuery")
    FUNC_DEF    <- detect `name <- function(` and `name = function(` patterns via token type "LEFT_ASSIGN"/"EQ_ASSIGN" with RHS starting a FUNCTION token.
    FUNC_CALL   <- any SYMBOL call not in the above sets and not a base/tidyverse primitive — resolve later against defined functions.

  For each detected call, extract:
    - line number (from getParseData() $line1)
    - first string-literal argument (the path/name argument) where possible
    - full call text from getParseData() $text for unresolved cases

  Return a list of raw edge records: list(file, line, fn_name, raw_arg, edge_type_hint).

  Progress: after every 20 files print "[dep_map] Parsed N/M: <filename>"

## SECTION 4 — Path resolution
resolve_path(raw_arg, fn_name, fpath, config_vals):
  1. If raw_arg contains CONFIG$xxx or CONFIG[["xxx"]], substitute from config_vals; mark resolved=TRUE if substituted, else resolved=FALSE.
  2. If raw_arg contains format(Sys.Date()...) / run_date / YYYYMMDD pattern, replace with {DATE} token; mark resolved=TRUE.
  3. Evaluate simple file.path(), paste0(), glue(), sprintf() with only string literals or already-resolved pieces.
  4. For list.files(pattern=...) calls: extract the pattern string as the artifact; set edge_type to "reads" (regex artifact).
  5. For source() / sys.source(): resolve relative to here() root.
  6. Mark resolved=FALSE for anything remaining that contains unresolved variables.
  Return: list(artifact=resolved_string, resolved=TRUE/FALSE).

## SECTION 5 — Function def/call inventory
After parsing all files, collect:
  fn_defs: data.frame(fn_name, file, line)   — from FUNC_DEF detections
  fn_calls: data.frame(fn_name, caller_file, line)  — from FUNC_CALL detections

Filter fn_calls to only those whose fn_name appears in fn_defs (project-defined functions).
Also keep fn_calls where fn_name does NOT appear in fn_defs as "undefined" (R7).

## SECTION 6 — Assemble edges.csv and nodes.csv
edges columns: from, to, edge_type, artifact, file, line, resolved
  - from/to: normalized relative path from repo root (use sub(here(), "", fpath, fixed=TRUE))
  - edge_type: "sources" / "writes" / "reads" / "db_read" / "db_write" / "calls_fn"
  - artifact: the resolved path/table/pattern string
  - file, line: source location
  - resolved: TRUE/FALSE

Classify db_read vs db_write:
  db_write: dbExecute containing CREATE TABLE / INSERT / DROP; DBI::dbWriteTable
  db_read:  dbGetQuery, tbl(), SELECT SQL strings

nodes: collect unique from/to values across all edges plus archive_r entries.
  Assign type:
    "script"   — matches R/**/*.R active file
    "util"     — matches R/utils/*.R
    "artifact" — a file path not in R/
    "db_table" — a DuckDB table name (no path separator, no extension)
    "function" — a function name from fn_defs/fn_calls
    "archived" — files in archive_r
  Phase/number prefix: extract leading digits from basename (e.g. "195" from "195_foo.R").
  archived flag: TRUE if in archive_r.

Write edges.csv and nodes.csv using versioned_stem().
message(sprintf("[dep_map] Edges: %d  Nodes: %d", nrow(edges), nrow(nodes)))

## SECTION 7 — dep_map.html (visNetwork)
Build visNetwork from nodes/edges data frames:
  Node shapes: scripts=box, artifacts=ellipse, db_table=database, function=diamond.
  Colors: scripts #0021A5 (blue), artifacts #CCCCCC (grey), db_table #888888, functions #AAAAFF.
  Risk-flag (color #FA4616): nodes appearing in R1–R6 risk findings (computed in Section 8 first, or flag after).

  Options:
    layout: hierarchical, direction="LR"
    interaction: hover tooltips showing file:line, search box (visOptions(nodesIdSelection=TRUE))
    clicking a node: highlight connected nodes/edges (highlightNearest=TRUE)

  Save with:
    htmlwidgets::saveWidget(vn, file=file.path(out_dir, paste0("dep_map_", dated, ".html")),
                            selfcontained=TRUE)
  Apply same version-suffix logic.

## SECTION 8 — dep_map_scripts.mmd (Mermaid)
Filter edges to edge_type %in% c("sources","writes","reads") only (no functions/db).
Build Mermaid flowchart LR:
  script nodes: box label = basename(file) with phase prefix
  artifact nodes: (("artifact_stem"))
  edges: --> with edge_type label
Write to file.path(out_dir, paste0("dep_map_scripts_", dated, ".mmd")).

## SECTION 9 — risk_report.md
Write to file.path(out_dir, paste0("risk_report_", dated, ".md")).

R1 Orphan reads
  Artifacts that appear as "to" in a reads edge but never as "to" in a writes edge.
  Near-miss hints: same stem different extension (e.g. .csv vs .rds), same basename different folder.
  List each with: artifact path, reader file:line.

R2 Dead writes
  Artifacts that appear as "to" in a writes edge but never as "to" in a reads edge.
  List each with: artifact path, writer file:line.

R3 "Latest file" selection
  Reads where raw_arg came from list.files() AND the call context contains
  sort|tail|order|file.mtime|max (grep raw call text).
  For each: file:line, pattern used, whether a pin/env-var override exists (grep R/ for the artifact basename).

R4 Same-date overwrite risk
  writes edges where artifact contains {DATE} but resolved=TRUE
  AND no version-check logic found in that file (grep file text for "file.exists|_v[0-9]").
  List file:line, artifact.

R5 Unresolved paths
  All edges where resolved=FALSE. List edge_type, file:line, raw artifact text.

R6 Hard-coded absolute paths
  Scan all parse_r readLines for patterns: "^/blue", "^/orange", "^C:\\\\", "^~/" in string literals.
  List file:line, path found.

R7 Utils analysis
  a. Functions defined in >1 file: list fn_name, files:lines.
  b. Functions defined but never called: list fn_name, defined file:line.
  c. Functions called but not defined in project (not in fn_defs): list fn_name, caller file:line.

R8 Execution order
  Build artifact-based DAG: script A -> artifact X -> script B (A writes X, B reads X).
  Topological sort (Kahn's algorithm in base R — no igraph needed):
    adjacency list: A precedes B if A writes something B reads.
  Report:
    - Topological order (script basenames)
    - Cycles (if any): list scripts in cycle
    - Order inversions: script with higher numeric prefix runs BEFORE a script with lower numeric prefix that it depends on.

R9 Unreachable scripts
  Entry points: scripts reachable via source() chains from any numeric-prefixed top-level script (R/NNN_*.R, not in utils/, not in tools/).
  Unreachable: active scripts not reachable and not in R/tools/ and not in R/utils/ (utils are loaded by config, not sourced individually in most cases — treat R/00_config.R as an implicit entry for all utils).
  List file path.

Each section: "No findings." if empty.

## SECTION 10 — Final summary message
message(sprintf(
  "[dep_map] DONE. Outputs in %s\n  edges: %d  nodes: %d  risks: R1=%d R2=%d R3=%d R4=%d R5=%d R6=%d R7=%d R8_cycles=%d R9=%d",
  out_dir, nrow(edges), nrow(nodes),
  nrow(r1), nrow(r2), nrow(r3), nrow(r4), nrow(r5), nrow(r6), nrow(r7_issues), n_cycles, nrow(r9)
))

CONSTRAINTS (enforce throughout):
- Do NOT call source() on any pipeline script.
- Do NOT read any .rds, .parquet, .csv data files, .duckdb files, or .xlsx files.
- Do NOT write inside R/.
- readLines() on R scripts is allowed for grep-based heuristics (R3, R6, R4).
- getParseData() is the primary AST source; raw-text regex is a fallback only for heuristics.
  </action>
  <verify>
    <automated>MISSING — requires HiPerGator run. After source("R/tools/dep_map.R", local=new.env(parent=globalenv())) from repo root, check: list.files("output/dep_map") shows edges*.csv, nodes*.csv, dep_map*.html, dep_map_scripts*.mmd, risk_report*.md. Report back the final [dep_map] DONE message.</automated>
  </verify>
  <done>
    Five output files exist in output/dep_map/ dated today. risk_report.md contains all nine R1–R9 sections. dep_map.html opens in browser with interactive graph. No R/ files modified.
  </done>
</task>

</tasks>

<verification>
On HiPerGator, from repo root:

```r
module load R/4.5
# Start R, then:
source("R/tools/dep_map.R", local = new.env(parent = globalenv()))
list.files("output/dep_map")
```

Paste back: the full [dep_map] DONE line and the list.files() output.
</verification>

<success_criteria>
- R/tools/dep_map.R sources cleanly on HiPerGator (no errors, only expected warnings)
- output/dep_map/ contains all five output files dated today
- risk_report.md has sections R1–R9 (even if some are "No findings.")
- dep_map.html is self-contained (opens offline)
- Zero modifications to any existing R/ files
</success_criteria>

<output>
No SUMMARY required for quick tasks — the five output files in output/dep_map/ are the deliverable.
</output>
