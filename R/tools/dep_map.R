# =============================================================================
# dep_map.R — Static dependency mapper for the R pipeline
# =============================================================================
# Standalone read-only audit tool. Parses all R/**/*.R scripts (excluding
# R/archive/ and this file itself) using base parse() + getParseData().
# Produces five outputs in output/dep_map/:
#   edges.csv           — dependency edges with type, artifact, file, line, resolved
#   nodes.csv           — all nodes with type, phase prefix, archived flag
#   dep_map.html        — self-contained interactive visNetwork graph
#   dep_map_scripts.mmd — Mermaid script->artifact->script flowchart
#   risk_report.md      — Nine-section risk report (R1–R9) with file:line citations
#
# Usage (from repo root on HiPerGator):
#   source("R/tools/dep_map.R", local = new.env(parent = globalenv()))
#
# CONSTRAINTS:
#   - Does NOT call source() on any pipeline script
#   - Does NOT read .rds, .parquet, .csv data, .duckdb, or .xlsx data files
#   - Does NOT write inside R/
#   - readLines() on R scripts is allowed for grep-based heuristics
# =============================================================================

# ==============================================================================
# SECTION 0 — Bootstrap
# ==============================================================================

suppressPackageStartupMessages({
  library(visNetwork)
  library(htmlwidgets)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(glue)
  library(here)
})

out_dir <- here("output", "dep_map")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dated <- format(Sys.Date(), "%Y%m%d")

# Version-safe path: append _v2, _v3, ... if file exists (for csv)
versioned_stem <- function(base, ext = "csv") {
  path <- file.path(out_dir, paste0(base, "_", dated, ".", ext))
  v <- 2L
  while (file.exists(path)) {
    path <- file.path(out_dir, paste0(base, "_", dated, "_v", v, ".", ext))
    v <- v + 1L
  }
  path
}

# ==============================================================================
# SECTION 1 — File inventory
# ==============================================================================

all_r      <- list.files(here("R"), pattern = "\\.R$", recursive = TRUE,
                         full.names = TRUE)
archive_r  <- all_r[grepl("/archive/", all_r, fixed = TRUE) |
                    grepl("\\archive\\", all_r, fixed = TRUE)]
parse_r    <- setdiff(all_r, archive_r)
tools_self <- normalizePath(here("R", "tools", "dep_map.R"), mustWork = FALSE)
parse_r    <- parse_r[normalizePath(parse_r, mustWork = FALSE) != tools_self]

message(sprintf("[dep_map] Files to parse: %d active, %d archived",
                length(parse_r), length(archive_r)))

# ==============================================================================
# SECTION 2 — CONFIG static value table
# ==============================================================================

cfg_lines <- tryCatch(
  readLines(here("R", "00_config.R"), warn = FALSE),
  error = function(e) character(0)
)

config_vals <- list()

# CONFIG$xxx <- "literal"  or  CONFIG[["xxx"]] <- "literal"
pat_cfg <- "^\\s*CONFIG(?:\\$|\\[\\[\"?)([A-Za-z0-9_]+)(?:\"?\\]\\])?\\s*<-\\s*[\"']([^\"']+)[\"']"
m_cfg <- regmatches(cfg_lines, regexpr(pat_cfg, cfg_lines, perl = TRUE))
for (hit in m_cfg) {
  parts <- regmatches(hit, regexec(pat_cfg, hit, perl = TRUE))[[1]]
  if (length(parts) == 3L) config_vals[[parts[2]]] <- parts[3]
}

# run_date / dated patterns → note as {DATE} token
run_date_token <- "{DATE}"

# ==============================================================================
# SECTION 3 — AST parser (core)
# ==============================================================================

SOURCE_FNS <- c("source", "sys.source")
WRITE_FNS  <- c("saveRDS", "write_rds", "write.csv", "write_csv", "fwrite",
                "write.xlsx", "saveWorkbook", "writexl::write_xlsx", "ggsave",
                "png", "pdf", "svg", "arrow::write_parquet",
                "DBI::dbWriteTable", "dbWriteTable", "dbExecute")
READ_FNS   <- c("readRDS", "read_rds", "read.csv", "read_csv", "fread",
               "read.xlsx", "read_excel", "loadWorkbook",
               "arrow::read_parquet", "list.files",
               "DBI::dbGetQuery", "dbGetQuery", "tbl")

ALL_KNOWN_FNS <- c(SOURCE_FNS, WRITE_FNS, READ_FNS)

# Base / tidyverse / common primitives to exclude from FUNC_CALL tracking
BASE_FUNS <- c(
  # base
  "c", "list", "data.frame", "matrix", "vector", "character", "numeric",
  "integer", "logical", "factor", "length", "nrow", "ncol", "dim", "names",
  "colnames", "rownames", "which", "any", "all", "is.na", "is.null",
  "is.numeric", "is.character", "is.logical", "is.factor", "is.data.frame",
  "is.list", "is.vector", "is.function", "is.environment",
  "as.character", "as.numeric", "as.integer", "as.logical", "as.factor",
  "as.Date", "as.POSIXct", "as.POSIXlt", "as.data.frame", "as.list",
  "print", "cat", "message", "warning", "stop", "stopifnot", "tryCatch",
  "withCallingHandlers", "try", "invisible", "return", "function",
  "if", "for", "while", "repeat", "break", "next",
  "paste", "paste0", "sprintf", "format", "formatC", "nchar", "substr",
  "substring", "gsub", "sub", "grep", "grepl", "regexpr", "regmatches",
  "regexec", "strsplit", "trimws", "toupper", "tolower", "chartr",
  "Sys.time", "Sys.Date", "date", "proc.time", "system.time",
  "file.path", "file.exists", "file.copy", "file.rename", "file.remove",
  "dir.create", "normalizePath", "dirname", "basename", "tools::file_ext",
  "readLines", "writeLines", "close", "open", "connection",
  "library", "require", "requireNamespace", "loadNamespace",
  "vapply", "sapply", "lapply", "mapply", "tapply", "Map", "Reduce",
  "do.call", "match", "match.arg", "missing", "exists", "get", "assign",
  "environment", "new.env", "parent.env", "sys.frame", "sys.call",
  "seq", "seq_len", "seq_along", "rev", "sort", "order", "rank",
  "head", "tail", "unique", "duplicated", "table", "tabulate",
  "sum", "prod", "cumsum", "cumprod", "diff", "abs", "sqrt", "log",
  "exp", "round", "ceiling", "floor", "trunc", "max", "min", "range",
  "mean", "median", "var", "sd", "cor", "cov", "quantile",
  "Inf", "NaN", "NA", "NULL", "TRUE", "FALSE",
  "options", "getOption", "Sys.getenv", "Sys.setenv",
  "switch", "ifelse", "within", "with",
  # dplyr / tidyverse
  "mutate", "filter", "select", "rename", "arrange", "group_by",
  "ungroup", "summarise", "summarize", "count", "tally", "distinct",
  "slice", "slice_head", "slice_tail", "slice_min", "slice_max",
  "left_join", "right_join", "inner_join", "full_join", "anti_join",
  "semi_join", "bind_rows", "bind_cols", "pull", "relocate",
  "across", "where", "everything", "starts_with", "ends_with",
  "contains", "matches", "num_range",
  "pivot_longer", "pivot_wider", "spread", "gather",
  "case_when", "if_else", "coalesce", "na_if",
  "n", "n_distinct", "first", "last", "nth",
  "row_number", "cumsum", "cummean", "cummax", "cummin",
  "lead", "lag", "between", "near",
  "collect", "compute", "copy_to", "show_query",
  "tibble", "tribble", "as_tibble", "glimpse",
  "%>%", "|>", "%in%", "!=", "==", "<=", ">=", "<", ">",
  # lubridate
  "ymd", "mdy", "dmy", "ymd_hms", "interval", "as.period",
  "years", "months", "weeks", "days", "hours", "minutes", "seconds",
  "year", "month", "day", "hour", "minute", "second", "yday", "wday",
  "floor_date", "ceiling_date", "round_date",
  # stringr
  "str_detect", "str_replace", "str_replace_all", "str_extract",
  "str_extract_all", "str_split", "str_c", "str_pad", "str_trim",
  "str_length", "str_sub", "str_to_upper", "str_to_lower", "str_glue",
  # glue
  "glue", "glue_sql",
  # here
  "here",
  # ggplot2
  "ggplot", "aes", "geom_bar", "geom_col", "geom_line", "geom_point",
  "geom_text", "geom_label", "geom_tile", "geom_boxplot", "geom_violin",
  "facet_wrap", "facet_grid", "theme", "theme_bw", "theme_minimal",
  "theme_classic", "scale_color_manual", "scale_fill_manual",
  "scale_x_continuous", "scale_y_continuous", "scale_x_date",
  "labs", "xlab", "ylab", "ggtitle", "coord_flip", "xlim", "ylim",
  # other common
  "openxlsx::createWorkbook", "openxlsx::addWorksheet",
  "openxlsx::writeData", "openxlsx::writeDataTable",
  "openxlsx::saveWorkbook", "createWorkbook", "addWorksheet",
  "writeData", "writeDataTable", "modifyBaseFont", "addStyle",
  "createStyle", "setColWidths", "freezePane",
  "officer::read_docx", "officer::body_add_par",
  "DBI::dbConnect", "DBI::dbDisconnect", "dbConnect", "dbDisconnect",
  "sprintf", "cat", "nchar"
)

# Extract first string-literal argument from parse data for a call node
extract_first_string_arg <- function(pd, call_id) {
  # Children of call_id — find first STR_CONST
  children <- pd[pd$parent == call_id, ]
  str_child <- children[children$token == "STR_CONST", ]
  if (nrow(str_child) == 0L) return(NA_character_)
  raw <- str_child$text[1]
  # Strip surrounding quotes
  gsub('^["\']|["\']$', "", raw)
}

parse_one_file <- function(fpath) {
  rel <- sub(paste0(normalizePath(here(), mustWork = FALSE), .Platform$file.sep),
             "", normalizePath(fpath, mustWork = FALSE), fixed = TRUE)
  rel <- gsub("\\\\", "/", rel)  # normalise Windows separators

  pd <- tryCatch({
    expr <- parse(fpath, keep.source = TRUE)
    utils::getParseData(expr, includeText = TRUE)
  }, error = function(e) {
    message(sprintf("[dep_map] PARSE ERROR: %s — %s", rel, conditionMessage(e)))
    return(NULL)
  })
  if (is.null(pd) || nrow(pd) == 0L) return(NULL)

  records <- list()

  # Identify all SYMBOL_FUNCTION_CALL tokens (function call sites)
  call_rows <- pd[pd$token == "SYMBOL_FUNCTION_CALL", ]

  for (i in seq_len(nrow(call_rows))) {
    fn_name  <- call_rows$text[i]
    line_no  <- call_rows$line1[i]
    call_id  <- call_rows$parent[i]   # expr for the call arguments
    # parent of SYMBOL_FUNCTION_CALL is the actual call expression
    raw_arg  <- extract_first_string_arg(pd, call_id)

    if (fn_name %in% SOURCE_FNS) {
      records[[length(records) + 1L]] <- list(
        file = rel, line = line_no, fn_name = fn_name,
        raw_arg = raw_arg, edge_type_hint = "sources"
      )
    } else if (fn_name %in% WRITE_FNS) {
      records[[length(records) + 1L]] <- list(
        file = rel, line = line_no, fn_name = fn_name,
        raw_arg = raw_arg, edge_type_hint = "writes"
      )
    } else if (fn_name %in% READ_FNS) {
      records[[length(records) + 1L]] <- list(
        file = rel, line = line_no, fn_name = fn_name,
        raw_arg = raw_arg, edge_type_hint = "reads"
      )
    }
  }

  # Function definitions: LEFT_ASSIGN or EQ_ASSIGN where RHS is FUNCTION token
  # getParseData() represents `name <- function(...)` with:
  #   SYMBOL (name) → LEFT_ASSIGN → expr containing FUNCTION token
  assign_rows <- pd[pd$token %in% c("LEFT_ASSIGN", "EQ_ASSIGN"), ]
  for (i in seq_len(nrow(assign_rows))) {
    assign_id <- assign_rows$id[i]
    assign_parent <- assign_rows$parent[i]
    # Siblings of this assign under same parent expression
    siblings <- pd[pd$parent == assign_parent, ]
    # Look for FUNCTION token among siblings (RHS)
    if (any(siblings$token == "FUNCTION")) {
      # LHS should be a SYMBOL sibling
      sym_sib <- siblings[siblings$token == "SYMBOL", ]
      if (nrow(sym_sib) > 0L) {
        fn_def_name <- sym_sib$text[1]
        records[[length(records) + 1L]] <- list(
          file = rel, line = assign_rows$line1[i], fn_name = fn_def_name,
          raw_arg = NA_character_, edge_type_hint = "fn_def"
        )
      }
    }
  }

  # Function calls to project-defined functions — collect all SYMBOL_FUNCTION_CALL
  # not in known sets; resolve later against fn_defs
  for (i in seq_len(nrow(call_rows))) {
    fn_name <- call_rows$text[i]
    if (!fn_name %in% ALL_KNOWN_FNS && !fn_name %in% BASE_FUNS) {
      records[[length(records) + 1L]] <- list(
        file = rel, line = call_rows$line1[i], fn_name = fn_name,
        raw_arg = NA_character_, edge_type_hint = "fn_call"
      )
    }
  }

  records
}

# Parse all files with progress
all_records <- list()
n_files <- length(parse_r)
for (i in seq_along(parse_r)) {
  if (i %% 20L == 0L || i == n_files) {
    message(sprintf("[dep_map] Parsed %d/%d: %s", i, n_files, basename(parse_r[i])))
  }
  recs <- parse_one_file(parse_r[i])
  if (!is.null(recs)) all_records <- c(all_records, recs)
}

message(sprintf("[dep_map] Total raw records: %d", length(all_records)))

# ==============================================================================
# SECTION 4 — Path resolution
# ==============================================================================

resolve_path <- function(raw_arg, fn_name, fpath, config_vals) {
  if (is.na(raw_arg) || raw_arg == "") {
    return(list(artifact = NA_character_, resolved = FALSE))
  }

  art <- raw_arg
  res <- TRUE

  # 1. Substitute CONFIG$xxx / CONFIG[["xxx"]]
  cfg_pat <- 'CONFIG(?:\\$|\\[\\["?)([A-Za-z0-9_]+)(?:"?\\]\\])?'
  m <- regmatches(art, gregexpr(cfg_pat, art, perl = TRUE))[[1]]
  for (token in m) {
    key <- regmatches(token, regexec(cfg_pat, token, perl = TRUE))[[1]][2]
    if (!is.null(config_vals[[key]])) {
      art <- gsub(token, config_vals[[key]], art, fixed = TRUE)
    } else {
      res <- FALSE
    }
  }

  # 2. Date patterns → {DATE} token
  date_pats <- c(
    "format\\(Sys\\.Date\\(\\)[^)]*\\)",
    "run_date",
    "\\{?[Dd]ated?\\}?",
    "[0-9]{8}"
  )
  for (dp in date_pats) {
    if (grepl(dp, art, perl = TRUE)) {
      art <- gsub(dp, "{DATE}", art, perl = TRUE)
    }
  }

  # 3. Simple file.path / paste0 / glue with only literals already resolved
  # Remove common wrappers
  wrappers <- c("here\\(", "file\\.path\\(", "paste0\\(", "glue\\(",
                "sprintf\\(")
  for (w in wrappers) {
    if (grepl(w, art)) {
      # Strip the wrapper call; keep inner string parts joined with /
      inner <- gsub(paste0(".*", w, '["\'](.*)["\'].*'), "\\1", art, perl = TRUE)
      if (inner != art) art <- inner
    }
  }

  # 4. list.files() pattern — treat as regex artifact
  if (fn_name == "list.files") {
    # pattern= argument; raw_arg is likely directory; treat as special
    art <- paste0("list.files(", art, ")")
  }

  # 5. source() relative to here() root — already resolved if no variables
  if (fn_name %in% c("source", "sys.source") && !grepl("\\{", art) &&
      !grepl("[A-Za-z_][A-Za-z0-9_]*\\s*[,(]", art)) {
    res <- TRUE
  }

  # 6. Remaining unresolved variable references
  if (grepl("\\b[A-Za-z_][A-Za-z0-9_.]*\\b", art) &&
      !grepl("\\{DATE\\}", art) &&
      !grepl("^[./~]", art) &&
      !grepl("^output/|^R/|^docs/|^data/", art)) {
    # Likely still contains a variable name
    res <- FALSE
  }

  list(artifact = art, resolved = res)
}

# ==============================================================================
# SECTION 5 — Function def/call inventory
# ==============================================================================

fn_defs_list  <- list()
fn_calls_list <- list()
raw_edges_list <- list()

for (rec in all_records) {
  if (rec$edge_type_hint == "fn_def") {
    fn_defs_list[[length(fn_defs_list) + 1L]] <- data.frame(
      fn_name = rec$fn_name,
      file    = rec$file,
      line    = rec$line,
      stringsAsFactors = FALSE
    )
  } else if (rec$edge_type_hint == "fn_call") {
    fn_calls_list[[length(fn_calls_list) + 1L]] <- data.frame(
      fn_name     = rec$fn_name,
      caller_file = rec$file,
      line        = rec$line,
      stringsAsFactors = FALSE
    )
  } else {
    raw_edges_list[[length(raw_edges_list) + 1L]] <- rec
  }
}

fn_defs  <- if (length(fn_defs_list)  > 0L) bind_rows(fn_defs_list)  else
  data.frame(fn_name=character(), file=character(), line=integer(),
             stringsAsFactors=FALSE)
fn_calls <- if (length(fn_calls_list) > 0L) bind_rows(fn_calls_list) else
  data.frame(fn_name=character(), caller_file=character(), line=integer(),
             stringsAsFactors=FALSE)

# Filter fn_calls to project-defined + undefined sets
project_fns   <- unique(fn_defs$fn_name)
fn_calls_proj <- fn_calls[fn_calls$fn_name %in% project_fns, ]
fn_calls_undef <- fn_calls[!fn_calls$fn_name %in% project_fns, ]

# ==============================================================================
# SECTION 6 — Assemble edges.csv and nodes.csv
# ==============================================================================

repo_root <- normalizePath(here(), mustWork = FALSE)

make_rel <- function(p) {
  p <- normalizePath(p, mustWork = FALSE)
  out <- sub(paste0(repo_root, .Platform$file.sep), "", p, fixed = TRUE)
  gsub("\\\\", "/", out)
}

# Build edges from raw_edges_list
edges_rows <- list()

for (rec in raw_edges_list) {
  resolved_info <- resolve_path(rec$raw_arg, rec$fn_name, rec$file, config_vals)
  artifact <- resolved_info$artifact
  resolved <- resolved_info$resolved
  hint     <- rec$edge_type_hint

  # Classify db_read / db_write more precisely
  edge_type <- hint
  if (hint == "writes" && rec$fn_name %in% c("dbExecute")) {
    # check raw_arg for SQL verb
    sql_up <- toupper(ifelse(is.na(rec$raw_arg), "", rec$raw_arg))
    if (grepl("^(CREATE|INSERT|DROP|ALTER|UPDATE|DELETE)", sql_up)) {
      edge_type <- "db_write"
    } else {
      edge_type <- "writes"
    }
  } else if (hint == "writes" && rec$fn_name %in% c("DBI::dbWriteTable", "dbWriteTable")) {
    edge_type <- "db_write"
  } else if (hint == "reads" &&
             rec$fn_name %in% c("DBI::dbGetQuery", "dbGetQuery", "tbl")) {
    edge_type <- "db_read"
  }

  edges_rows[[length(edges_rows) + 1L]] <- data.frame(
    from      = rec$file,
    to        = ifelse(is.na(artifact), paste0("<unresolved:", rec$fn_name, ">"), artifact),
    edge_type = edge_type,
    artifact  = ifelse(is.na(artifact), NA_character_, artifact),
    file      = rec$file,
    line      = rec$line,
    resolved  = resolved,
    stringsAsFactors = FALSE
  )
}

# Add fn_calls_proj as "calls_fn" edges
for (i in seq_len(nrow(fn_calls_proj))) {
  def_row <- fn_defs[fn_defs$fn_name == fn_calls_proj$fn_name[i], ][1, ]
  edges_rows[[length(edges_rows) + 1L]] <- data.frame(
    from      = fn_calls_proj$caller_file[i],
    to        = def_row$file,
    edge_type = "calls_fn",
    artifact  = fn_calls_proj$fn_name[i],
    file      = fn_calls_proj$caller_file[i],
    line      = fn_calls_proj$line[i],
    resolved  = TRUE,
    stringsAsFactors = FALSE
  )
}

edges <- if (length(edges_rows) > 0L) bind_rows(edges_rows) else
  data.frame(from=character(), to=character(), edge_type=character(),
             artifact=character(), file=character(), line=integer(),
             resolved=logical(), stringsAsFactors=FALSE)

# --- Nodes ---
all_node_ids <- unique(c(edges$from, edges$to))

# Archive relative paths
archive_rel <- gsub("\\\\", "/",
  sub(paste0(repo_root, .Platform$file.sep), "", normalizePath(archive_r, mustWork = FALSE),
      fixed = TRUE))

active_rel <- gsub("\\\\", "/",
  sub(paste0(repo_root, .Platform$file.sep), "", normalizePath(parse_r, mustWork = FALSE),
      fixed = TRUE))

classify_node <- function(id) {
  if (id %in% active_rel) {
    if (grepl("^R/utils/", id)) return("util")
    return("script")
  }
  if (id %in% archive_rel) return("archived")
  if (grepl("\\.R$", id, ignore.case = TRUE)) return("script")
  if (grepl("[/\\\\]", id) || grepl("\\.[a-zA-Z0-9]+$", id)) return("artifact")
  if (grepl("^list\\.files\\(", id)) return("artifact")
  if (grepl("^<unresolved:", id)) return("artifact")
  # DuckDB table: no separator, no extension
  if (!grepl("[/\\\\.]", id)) return("db_table")
  return("artifact")
}

phase_prefix <- function(id) {
  bn <- basename(id)
  m <- regmatches(bn, regexpr("^[0-9]+", bn))
  if (length(m) > 0L && m != "") m else NA_character_
}

nodes_all <- unique(c(all_node_ids, archive_rel))
nodes <- data.frame(
  id      = nodes_all,
  type    = vapply(nodes_all, classify_node, character(1L)),
  phase   = vapply(nodes_all, phase_prefix, character(1L)),
  archived = nodes_all %in% archive_rel,
  stringsAsFactors = FALSE
)

# Write edges and nodes
edges_path <- versioned_stem("edges")
nodes_path <- versioned_stem("nodes")
write.csv(edges, edges_path, row.names = FALSE)
write.csv(nodes, nodes_path, row.names = FALSE)
message(sprintf("[dep_map] Edges: %d  Nodes: %d", nrow(edges), nrow(nodes)))

# ==============================================================================
# SECTION 7 — dep_map.html (visNetwork)
# ==============================================================================

# Risk sections computed after (see Section 8), but we colour later.
# Build base visNetwork first, re-save after risk flagging.

node_color <- function(type) {
  switch(type,
    script   = "#0021A5",
    util     = "#4455CC",
    artifact = "#CCCCCC",
    db_table = "#888888",
    function = "#AAAAFF",
    archived = "#DDDDDD",
    "#CCCCCC"
  )
}

node_shape <- function(type) {
  switch(type,
    script   = "box",
    util     = "box",
    artifact = "ellipse",
    db_table = "database",
    `function` = "diamond",
    archived = "box",
    "ellipse"
  )
}

vn_nodes <- data.frame(
  id    = nodes$id,
  label = basename(nodes$id),
  title = nodes$id,       # tooltip
  color = vapply(nodes$type, node_color, character(1L)),
  shape = vapply(nodes$type, node_shape, character(1L)),
  group = nodes$type,
  stringsAsFactors = FALSE
)

edge_color_map <- c(
  sources  = "#2255AA",
  writes   = "#FA4616",
  reads    = "#44AA44",
  db_read  = "#AA8800",
  db_write = "#CC2200",
  calls_fn = "#888888"
)

vn_edges <- data.frame(
  from   = edges$from,
  to     = edges$to,
  label  = edges$edge_type,
  title  = paste0(edges$file, ":", edges$line),
  color  = vapply(edges$edge_type,
                  function(e) ifelse(e %in% names(edge_color_map),
                                     edge_color_map[[e]], "#999999"),
                  character(1L)),
  arrows = "to",
  stringsAsFactors = FALSE
)

vn <- visNetwork(vn_nodes, vn_edges,
                 main = paste0("R Pipeline Dependency Map — ", dated)) |>
  visEdges(arrows = "to") |>
  visOptions(
    highlightNearest = TRUE,
    nodesIdSelection = TRUE
  ) |>
  visLayout(randomSeed = 42L) |>
  visHierarchicalLayout(direction = "LR", sortMethod = "directed") |>
  visInteraction(hover = TRUE, tooltipDelay = 100)

html_path <- file.path(out_dir, paste0("dep_map_", dated, ".html"))
v2 <- 2L
while (file.exists(html_path)) {
  html_path <- file.path(out_dir, paste0("dep_map_", dated, "_v", v2, ".html"))
  v2 <- v2 + 1L
}

htmlwidgets::saveWidget(vn, file = html_path, selfcontained = TRUE)
message(sprintf("[dep_map] HTML saved: %s", basename(html_path)))

# ==============================================================================
# SECTION 8 — dep_map_scripts.mmd (Mermaid)
# ==============================================================================

script_edges <- edges[edges$edge_type %in% c("sources", "writes", "reads"), ]

# Sanitize node IDs for Mermaid (no special chars)
mermaid_id <- function(x) {
  gsub("[^A-Za-z0-9_]", "_", x)
}

mmd_lines <- c("flowchart LR")

# Collect unique script and artifact nodes
script_nodes  <- unique(c(
  script_edges$from[script_edges$from %in% active_rel],
  script_edges$to[script_edges$to %in% active_rel]
))
artifact_nodes <- unique(c(
  script_edges$from[!script_edges$from %in% active_rel],
  script_edges$to[!script_edges$to %in% active_rel]
))

for (n in script_nodes) {
  mmd_lines <- c(mmd_lines,
    sprintf('  %s["%s"]', mermaid_id(n), basename(n)))
}
for (n in artifact_nodes) {
  mmd_lines <- c(mmd_lines,
    sprintf('  %s(("%s"))', mermaid_id(n),
            substr(basename(n), 1L, 40L)))
}

for (i in seq_len(nrow(script_edges))) {
  mmd_lines <- c(mmd_lines,
    sprintf('  %s -->|%s| %s',
            mermaid_id(script_edges$from[i]),
            script_edges$edge_type[i],
            mermaid_id(script_edges$to[i])))
}

mmd_path <- file.path(out_dir, paste0("dep_map_scripts_", dated, ".mmd"))
v2 <- 2L
while (file.exists(mmd_path)) {
  mmd_path <- file.path(out_dir, paste0("dep_map_scripts_", dated, "_v", v2, ".mmd"))
  v2 <- v2 + 1L
}
writeLines(mmd_lines, mmd_path)
message(sprintf("[dep_map] Mermaid saved: %s", basename(mmd_path)))

# ==============================================================================
# SECTION 9 — risk_report.md
# ==============================================================================

# Helper: format a table or "No findings."
risk_table <- function(df, cols, header = NULL) {
  if (is.null(df) || nrow(df) == 0L) return("No findings.")
  if (!is.null(header)) {
    df <- df[, intersect(cols, colnames(df)), drop = FALSE]
  } else {
    df <- df[, intersect(cols, colnames(df)), drop = FALSE]
  }
  # Simple markdown table
  lines <- character(nrow(df) + 2L)
  lines[1] <- paste("|", paste(colnames(df), collapse = " | "), "|")
  lines[2] <- paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|")
  for (i in seq_len(nrow(df))) {
    lines[i + 2L] <- paste("|", paste(as.character(df[i, ]), collapse = " | "), "|")
  }
  paste(lines, collapse = "\n")
}

# --- R1: Orphan reads ---
write_artifacts <- unique(edges$to[edges$edge_type %in% c("writes", "db_write")])
read_artifacts  <- unique(edges$to[edges$edge_type %in% c("reads", "db_read")])

r1_art <- setdiff(read_artifacts, write_artifacts)
# Remove unresolved placeholders and list.files entries from primary set
r1_art <- r1_art[!grepl("^<unresolved:|^list\\.files\\(", r1_art)]

r1 <- if (length(r1_art) > 0L) {
  r1_edges <- edges[edges$to %in% r1_art &
                    edges$edge_type %in% c("reads", "db_read"), ]
  data.frame(
    artifact = r1_edges$to,
    reader   = paste0(r1_edges$file, ":", r1_edges$line),
    stringsAsFactors = FALSE
  )
} else data.frame(artifact=character(), reader=character(), stringsAsFactors=FALSE)

# Near-miss: same stem different extension
stem_map <- function(paths) {
  tools::file_path_sans_ext(basename(paths))
}
r1_near <- character(0)
if (length(r1_art) > 0L && length(write_artifacts) > 0L) {
  r1_stems <- stem_map(r1_art)
  w_stems  <- stem_map(write_artifacts)
  r1_near  <- r1_art[r1_stems %in% w_stems]
}

# --- R2: Dead writes ---
r2_art <- setdiff(write_artifacts, read_artifacts)
r2_art <- r2_art[!grepl("^<unresolved:|^list\\.files\\(", r2_art)]

r2 <- if (length(r2_art) > 0L) {
  r2_edges <- edges[edges$to %in% r2_art &
                    edges$edge_type %in% c("writes", "db_write"), ]
  data.frame(
    artifact = r2_edges$to,
    writer   = paste0(r2_edges$file, ":", r2_edges$line),
    stringsAsFactors = FALSE
  )
} else data.frame(artifact=character(), writer=character(), stringsAsFactors=FALSE)

# --- R3: "Latest file" selection ---
# list.files() reads where call context contains sort|tail|order|file.mtime|max
r3_list <- list()
for (rec in raw_edges_list) {
  if (rec$fn_name != "list.files") next
  # Read the file lines around this call
  fpath_abs <- file.path(repo_root, gsub("/", .Platform$file.sep, rec$file))
  flines <- tryCatch(readLines(fpath_abs, warn = FALSE), error = function(e) character(0))
  if (length(flines) == 0L) next
  ctx_start <- max(1L, rec$line - 3L)
  ctx_end   <- min(length(flines), rec$line + 3L)
  ctx_text  <- paste(flines[ctx_start:ctx_end], collapse = " ")
  if (grepl("sort|tail|order|file\\.mtime|max", ctx_text, perl = TRUE)) {
    # Check if a pin/env-var exists for this artifact
    art_base <- if (!is.na(rec$raw_arg)) basename(rec$raw_arg) else "unknown"
    has_pin <- FALSE
    for (pf in parse_r) {
      plines <- tryCatch(readLines(pf, warn = FALSE), error = function(e) character(0))
      if (any(grepl(art_base, plines, fixed = TRUE) &
              grepl("Sys\\.getenv|R[0-9]+_", plines, perl = TRUE))) {
        has_pin <- TRUE; break
      }
    }
    r3_list[[length(r3_list) + 1L]] <- data.frame(
      file     = paste0(rec$file, ":", rec$line),
      pattern  = ifelse(is.na(rec$raw_arg), "NA", rec$raw_arg),
      has_pin  = has_pin,
      stringsAsFactors = FALSE
    )
  }
}
r3 <- if (length(r3_list) > 0L) bind_rows(r3_list) else
  data.frame(file=character(), pattern=character(), has_pin=logical(),
             stringsAsFactors=FALSE)

# --- R4: Same-date overwrite risk ---
r4_list <- list()
write_edges_dated <- edges[edges$edge_type %in% c("writes", "db_write") &
                           grepl("\\{DATE\\}", edges$to, fixed = TRUE) &
                           edges$resolved == TRUE, ]
if (nrow(write_edges_dated) > 0L) {
  for (i in seq_len(nrow(write_edges_dated))) {
    fpath_abs <- file.path(repo_root,
      gsub("/", .Platform$file.sep, write_edges_dated$file[i]))
    ftext <- tryCatch(paste(readLines(fpath_abs, warn = FALSE), collapse = "\n"),
                      error = function(e) "")
    if (!grepl("file\\.exists|_v[0-9]", ftext, perl = TRUE)) {
      r4_list[[length(r4_list) + 1L]] <- data.frame(
        file     = paste0(write_edges_dated$file[i], ":", write_edges_dated$line[i]),
        artifact = write_edges_dated$to[i],
        stringsAsFactors = FALSE
      )
    }
  }
}
r4 <- if (length(r4_list) > 0L) bind_rows(r4_list) else
  data.frame(file=character(), artifact=character(), stringsAsFactors=FALSE)

# --- R5: Unresolved paths ---
r5 <- edges[edges$resolved == FALSE, c("edge_type", "file", "line", "artifact")]
if (nrow(r5) > 0L) r5$location <- paste0(r5$file, ":", r5$line)

# --- R6: Hard-coded absolute paths ---
r6_list <- list()
abs_pats <- c("^/blue", "^/orange", "^/ufrc", "^/home", "^C:\\\\", "^~\\/")
for (pf in parse_r) {
  pf_abs <- file.path(repo_root, gsub("/", .Platform$file.sep, pf))
  plines <- tryCatch(readLines(pf_abs, warn = FALSE), error = function(e) character(0))
  for (li in seq_along(plines)) {
    for (ap in abs_pats) {
      m <- regmatches(plines[li],
                      gregexpr(paste0("[\"']", ap, "[^\"']*[\"']"), plines[li], perl = TRUE))[[1]]
      for (hit in m) {
        r6_list[[length(r6_list) + 1L]] <- data.frame(
          file = paste0(pf, ":", li),
          path = hit,
          stringsAsFactors = FALSE
        )
      }
    }
  }
}
r6 <- if (length(r6_list) > 0L) bind_rows(r6_list) else
  data.frame(file=character(), path=character(), stringsAsFactors=FALSE)

# --- R7: Utils analysis ---
# a. Functions defined in >1 file
fn_multi <- fn_defs |>
  group_by(fn_name) |>
  filter(n() > 1L) |>
  ungroup()
fn_multi_fmt <- if (nrow(fn_multi) > 0L) {
  fn_multi |>
    mutate(location = paste0(file, ":", line)) |>
    group_by(fn_name) |>
    summarise(locations = paste(location, collapse = "; "), .groups = "drop")
} else data.frame(fn_name=character(), locations=character(), stringsAsFactors=FALSE)

# b. Defined but never called
fn_called <- unique(fn_calls$fn_name)
fn_never_called <- fn_defs[!fn_defs$fn_name %in% fn_called, ]

# c. Called but not defined
fn_calls_undef_uniq <- fn_calls_undef |>
  group_by(fn_name) |>
  summarise(
    callers = paste(paste0(caller_file, ":", line), collapse = "; "),
    .groups = "drop"
  )

r7_issues <- bind_rows(
  if (nrow(fn_multi_fmt) > 0L) data.frame(issue="duplicate_def", detail=fn_multi_fmt$fn_name, stringsAsFactors=FALSE) else NULL,
  if (nrow(fn_never_called) > 0L) data.frame(issue="never_called", detail=fn_never_called$fn_name, stringsAsFactors=FALSE) else NULL,
  if (nrow(fn_calls_undef_uniq) > 0L) data.frame(issue="call_undefined", detail=fn_calls_undef_uniq$fn_name, stringsAsFactors=FALSE) else NULL
)
if (is.null(r7_issues) || nrow(r7_issues) == 0L)
  r7_issues <- data.frame(issue=character(), detail=character(), stringsAsFactors=FALSE)

# --- R8: Execution order (Kahn's topological sort) ---
# Build artifact-based DAG: script A -> X -> script B
# A precedes B if A writes something B reads.
write_map <- edges[edges$edge_type %in% c("writes", "db_write") &
                   !is.na(edges$artifact), c("from", "artifact")]
read_map  <- edges[edges$edge_type %in% c("reads", "db_read") &
                   !is.na(edges$artifact), c("from", "artifact")]

# Join: for each artifact written by A and read by B, A -> B
dag_edges <- inner_join(write_map, read_map, by = "artifact",
                        suffix = c("_writer", "_reader")) |>
  rename(pred = from_writer, succ = from_reader) |>
  filter(pred != succ) |>
  distinct(pred, succ)

scripts_in_dag <- unique(c(dag_edges$pred, dag_edges$succ))

# Kahn's algorithm
in_degree <- table(factor(dag_edges$succ, levels = scripts_in_dag))
queue <- names(in_degree)[in_degree == 0L]
topo_order <- character(0)
remaining <- dag_edges

while (length(queue) > 0L) {
  node <- queue[1]; queue <- queue[-1]
  topo_order <- c(topo_order, node)
  successors <- remaining$succ[remaining$pred == node]
  remaining  <- remaining[remaining$pred != node, ]
  for (s in successors) {
    if (!s %in% remaining$succ) queue <- c(queue, s)
  }
}

cycles <- scripts_in_dag[!scripts_in_dag %in% topo_order]
n_cycles <- length(cycles)

# Order inversions: higher numeric prefix precedes lower numeric prefix dependency
num_prefix <- function(x) {
  as.integer(sub("^([0-9]+).*", "\\1", basename(x)))
}

order_inv <- list()
if (nrow(dag_edges) > 0L) {
  for (i in seq_len(nrow(dag_edges))) {
    p_num <- num_prefix(dag_edges$pred[i])
    s_num <- num_prefix(dag_edges$succ[i])
    if (!is.na(p_num) && !is.na(s_num) && p_num > s_num) {
      order_inv[[length(order_inv) + 1L]] <- data.frame(
        higher_prefix = dag_edges$pred[i],
        lower_prefix  = dag_edges$succ[i],
        stringsAsFactors = FALSE
      )
    }
  }
}
order_inv_df <- if (length(order_inv) > 0L) bind_rows(order_inv) else
  data.frame(higher_prefix=character(), lower_prefix=character(),
             stringsAsFactors=FALSE)

# --- R9: Unreachable scripts ---
# Entry points: numeric-prefixed scripts in R/ (not utils/, not tools/)
entry_points <- active_rel[grepl("^R/[0-9]+_", active_rel) &
                           !grepl("^R/utils/|^R/tools/", active_rel)]

# BFS over source() edges
source_edges <- edges[edges$edge_type == "sources", c("from", "to")]

reachable <- unique(entry_points)
frontier  <- reachable
visited   <- character(0)

while (length(frontier) > 0L) {
  new_reaches <- source_edges$to[source_edges$from %in% frontier]
  new_reaches <- setdiff(new_reaches, visited)
  visited   <- c(visited, frontier)
  frontier  <- setdiff(new_reaches, visited)
  reachable <- unique(c(reachable, new_reaches))
}

# R/00_config.R implicitly reaches all utils
config_script <- active_rel[grepl("00_config\\.R$", active_rel)]
utils_scripts  <- active_rel[grepl("^R/utils/", active_rel)]
reachable <- unique(c(reachable, config_script, utils_scripts))

unreachable <- active_rel[!active_rel %in% reachable &
                          !grepl("^R/tools/", active_rel) &
                          !grepl("^R/utils/", active_rel)]

r9 <- data.frame(file = unreachable, stringsAsFactors = FALSE)

# --- Write risk_report.md ---
rpt_path <- file.path(out_dir, paste0("risk_report_", dated, ".md"))
v2 <- 2L
while (file.exists(rpt_path)) {
  rpt_path <- file.path(out_dir, paste0("risk_report_", dated, "_v", v2, ".md"))
  v2 <- v2 + 1L
}

rpt <- c(
  paste0("# Dependency Risk Report — ", dated),
  "",
  paste0("Generated by `R/tools/dep_map.R` from ", length(parse_r),
         " active scripts (", length(archive_r), " archived)."),
  "",
  "---",
  "",
  "## R1 — Orphan Reads",
  "",
  "Artifacts read by at least one script but never written by any script.",
  "",
  risk_table(r1, c("artifact", "reader")),
  "",
  if (length(r1_near) > 0L)
    paste0("**Near-misses (same stem, different extension):** ",
           paste(r1_near, collapse = "; "))
  else "",
  "",
  "---",
  "",
  "## R2 — Dead Writes",
  "",
  "Artifacts written by at least one script but never read by any script.",
  "",
  risk_table(r2, c("artifact", "writer")),
  "",
  "---",
  "",
  "## R3 — 'Latest File' Selection",
  "",
  "list.files() calls where context suggests mtime/sort-based selection.",
  "",
  risk_table(r3, c("file", "pattern", "has_pin")),
  "",
  "---",
  "",
  "## R4 — Same-Date Overwrite Risk",
  "",
  "Scripts writing dated artifacts without version-check logic.",
  "",
  risk_table(r4, c("file", "artifact")),
  "",
  "---",
  "",
  "## R5 — Unresolved Paths",
  "",
  "Edges where artifact path could not be statically resolved.",
  "",
  risk_table(r5, c("edge_type", "file", "line", "artifact")),
  "",
  "---",
  "",
  "## R6 — Hard-Coded Absolute Paths",
  "",
  "String literals beginning with /blue, /orange, /ufrc, /home, C:\\\\, ~/.",
  "",
  risk_table(r6, c("file", "path")),
  "",
  "---",
  "",
  "## R7 — Utils Analysis",
  "",
  paste0("### R7a — Functions defined in more than one file (", nrow(fn_multi_fmt), ")"),
  "",
  risk_table(fn_multi_fmt, c("fn_name", "locations")),
  "",
  paste0("### R7b — Functions defined but never called (", nrow(fn_never_called), ")"),
  "",
  risk_table(fn_never_called, c("fn_name", "file", "line")),
  "",
  paste0("### R7c — Functions called but not defined in project (",
         nrow(fn_calls_undef_uniq), ")"),
  "",
  risk_table(fn_calls_undef_uniq, c("fn_name", "callers")),
  "",
  "---",
  "",
  "## R8 — Execution Order",
  "",
  paste0("Topological order (", length(topo_order), " scripts resolved):"),
  "",
  paste(seq_along(topo_order), basename(topo_order), sep = ". ", collapse = "\n"),
  "",
  if (n_cycles > 0L)
    paste0("**Cycles detected (", n_cycles, "):** ", paste(basename(cycles), collapse = "; "))
  else "No cycles detected.",
  "",
  if (nrow(order_inv_df) > 0L) {
    c("**Order inversions:**", risk_table(order_inv_df, c("higher_prefix", "lower_prefix")))
  } else "No order inversions detected.",
  "",
  "---",
  "",
  "## R9 — Unreachable Scripts",
  "",
  "Active scripts not reachable via source() chains from any numeric-prefixed entry point.",
  "",
  risk_table(r9, c("file")),
  "",
  "---",
  "",
  paste0("*Report generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC"), "*")
)

writeLines(rpt, rpt_path)
message(sprintf("[dep_map] Risk report saved: %s", basename(rpt_path)))

# ==============================================================================
# SECTION 10 — Final summary message
# ==============================================================================

message(sprintf(
  "[dep_map] DONE. Outputs in %s\n  edges: %d  nodes: %d  risks: R1=%d R2=%d R3=%d R4=%d R5=%d R6=%d R7=%d R8_cycles=%d R9=%d",
  out_dir,
  nrow(edges), nrow(nodes),
  nrow(r1), nrow(r2), nrow(r3), nrow(r4), nrow(r5), nrow(r6), nrow(r7_issues),
  n_cycles, nrow(r9)
))
