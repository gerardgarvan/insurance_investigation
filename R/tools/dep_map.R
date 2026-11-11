# =============================================================================
# dep_map.R -- Static dependency mapper for the R pipeline (v2)
# =============================================================================
# Read-only. Parses every R/**/*.R file as language objects (no pipeline code is
# sourced or executed) and maps:
#   scripts -> scripts   source() / sys.source(), incl. loaders that source a
#                        list.files() result in a for-loop or lapply()
#   scripts -> files     reads / writes (.rds .csv .xlsx .parquet figures ...)
#   scripts -> DuckDB    tables read / written in SQL strings and tbl()
#   scripts -> functions project-defined functions called from each file
#
# Usage (from the project root):
#   Rscript R/tools/dep_map.R            # or: source("R/tools/dep_map.R")
# Environment switches:
#   DEP_MAP_FORCE=1     write outputs even if the validation gate fails
#   DEP_MAP_NO_GATE=1   skip the project-specific gate (generic thresholds kept)
#
# Outputs (output/dep_map/, never overwritten -- a _vN suffix is added):
#   edges_<date>.csv, nodes_<date>.csv, functions_<date>.csv,
#   r5_unresolved_<date>.csv, r7c_undefined_<date>.csv, gate_<date>.csv,
#   risk_report_<date>.md, dep_map_<date>.html, dep_map_scripts_<date>.mmd
# =============================================================================

local({

# -----------------------------------------------------------------------------
# 0. Small helpers
# -----------------------------------------------------------------------------
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
is_miss <- function(x) identical(x, quote(expr = ))
cap <- function(x, n = 6L) { x <- unique(x); x[seq_len(min(length(x), n))] }
has_tok <- function(s) grepl("\\{[A-Za-z_.][^{}]*\\}", s)
strip_tok <- function(s) gsub("\\{[A-Za-z_.][^{}]*\\}", "", s)
is_list_val <- function(s) !is.na(s) & startsWith(s, "LIST::")
mk_list_val <- function(dir, pat, rec = FALSE)
  paste0("LIST::", dir, "::", pat %||% "", "::", if (isTRUE(rec)) "R" else "")
parse_list_val <- function(s) {
  p <- strsplit(s, "::", fixed = TRUE)[[1]]
  list(dir = p[2] %||% "", pat = p[3] %||% "", rec = identical(p[4], "R"))
}

call_name <- function(e) {
  h <- e[[1]]
  if (is.name(h)) return(as.character(h))
  if (is.call(h) && is.name(h[[1]]) && as.character(h[[1]]) %in% c("::", ":::"))
    return(as.character(h[[3]]))
  NA_character_
}
call_pkg <- function(e) {
  h <- e[[1]]
  if (is.call(h) && is.name(h[[1]]) && as.character(h[[1]]) %in% c("::", ":::"))
    return(as.character(h[[2]]))
  NA_character_
}
# arguments of a call, missing args dropped; names "" for positional
call_args <- function(e) {
  if (length(e) < 2) return(list())
  a <- as.list(e)[-1]
  nm <- names(a) %||% rep("", length(a))
  keep <- !vapply(seq_along(a), function(i) is_miss(a[[i]]), logical(1))
  a <- a[keep]; names(a) <- nm[keep]
  a
}
# R-style argument matching against a formals prefix
match_arg <- function(args, formals, target, alt = character()) {
  nms <- names(args) %||% rep("", length(args))
  for (t in c(target, alt)) if (t %in% nms) return(args[[which(nms == t)[1]]])
  named_used <- intersect(nms[nms != ""], formals)
  free <- setdiff(formals, named_used)
  pos <- args[nms == ""]
  k <- match(target, free)
  if (is.na(k) || k > length(pos)) return(NULL)
  pos[[k]]
}

# -----------------------------------------------------------------------------
# 1. Call specification: which argument of which function is a path / SQL
# -----------------------------------------------------------------------------
SPEC <- list(
  # sources
  source      = list("sources", c("file"), "file"),
  sys.source  = list("sources", c("file"), "file"),
  # reads
  readRDS     = list("reads", c("file"), "file"),
  read_rds    = list("reads", c("file"), "file"),
  read.csv    = list("reads", c("file"), "file"),
  read.delim  = list("reads", c("file"), "file"),
  read.table  = list("reads", c("file"), "file"),
  read_csv    = list("reads", c("file"), "file"),
  read_tsv    = list("reads", c("file"), "file"),
  read_delim  = list("reads", c("file"), "file"),
  vroom       = list("reads", c("file"), "file"),
  fread       = list("reads", c("input"), "input", "file"),
  read.xlsx   = list("reads", c("xlsxFile"), "xlsxFile", "file"),
  read_excel  = list("reads", c("path"), "path"),
  read_xlsx   = list("reads", c("path"), "path"),
  read_xls    = list("reads", c("path"), "path"),
  loadWorkbook = list("reads", c("file"), "file", "xlsxFile"),
  getSheetNames = list("reads", c("file"), "file"),
  read_parquet = list("reads", c("file"), "file"),
  open_dataset = list("reads", c("sources"), "sources"),
  read_feather = list("reads", c("file"), "file"),
  read_fst    = list("reads", c("path"), "path"),
  load        = list("reads", c("file"), "file"),
  read_json   = list("reads", c("path"), "path"),
  fromJSON    = list("reads", c("txt"), "txt"),
  read_docx   = list("reads", c("path"), "path"),
  # writes
  saveRDS     = list("writes", c("object", "file"), "file"),
  write_rds   = list("writes", c("x", "file"), "file", "path"),
  write.csv   = list("writes", c("x", "file"), "file"),
  write.table = list("writes", c("x", "file"), "file"),
  write_csv   = list("writes", c("x", "file"), "file", "path"),
  write_tsv   = list("writes", c("x", "file"), "file", "path"),
  write_delim = list("writes", c("x", "file"), "file", "path"),
  fwrite      = list("writes", c("x", "file"), "file"),
  write.xlsx  = list("writes", c("x", "file"), "file"),
  write_xlsx  = list("writes", c("x", "path"), "path"),
  saveWorkbook = list("writes", c("wb", "file"), "file"),
  wb_save     = list("writes", c("wb", "file"), "file"),
  ggsave      = list("writes", c("filename"), "filename"),
  png         = list("writes", c("filename"), "filename"),
  jpeg        = list("writes", c("filename"), "filename"),
  tiff        = list("writes", c("filename"), "filename"),
  svg         = list("writes", c("filename"), "filename"),
  pdf         = list("writes", c("file"), "file"),
  cairo_pdf   = list("writes", c("filename"), "filename"),
  write_parquet = list("writes", c("x", "sink"), "sink"),
  write_feather = list("writes", c("x", "sink"), "sink"),
  write_fst   = list("writes", c("x", "path"), "path"),
  write_json  = list("writes", c("x", "path"), "path"),
  saveWidget  = list("writes", c("widget", "file"), "file"),
  save        = list("writes", character(), "file"),
  sink        = list("writes", c("file"), "file"),
  writeLines  = list("writes", c("text", "con"), "con"),
  readLines   = list("reads", c("con"), "con"),
  # db
  dbGetQuery  = list("sql", c("conn", "statement"), "statement"),
  dbExecute   = list("sql", c("conn", "statement"), "statement"),
  dbSendQuery = list("sql", c("conn", "statement"), "statement"),
  dbSendStatement = list("sql", c("conn", "statement"), "statement"),
  dbReadTable = list("db_read", c("conn", "name"), "name"),
  dbWriteTable = list("db_write", c("conn", "name"), "name"),
  dbAppendTable = list("db_write", c("conn", "name"), "name"),
  dbCreateTable = list("db_write", c("conn", "name"), "name"),
  tbl         = list("db_read", c("src", "from"), "from")
)
NO_WALK <- c("quote", "bquote", "expression", "substitute", "alist", "~")
DATE_FNS <- c("Sys.Date", "Sys.time", "today", "now", "date")
PASS1 <- c("head", "tail", "sort", "rev", "unique", "normalizePath", "path.expand",
           "as.character", "enc2utf8", "trimws", "(", "sample", "max", "min",
           "fs::path_norm", "path_norm", "suppressWarnings", "suppressMessages",
           "identity", "invisible", "force", "na.omit", "Filter")
SQL_START <- "^\\s*\\(?\\s*(SELECT|WITH|CREATE|INSERT|COPY|UPDATE|DELETE|DROP|ALTER|ATTACH)\\b"

# -----------------------------------------------------------------------------
# 2. Path resolver: expression -> character vector of alternatives
#    Tokens: {DATE}, {ROOT}, {ENV:X}, {CONFIG$x}, {sym}, {fn()}
#    Listing results are encoded as LIST::dir::regex::R
# -----------------------------------------------------------------------------
new_scope <- function(parent = emptyenv()) new.env(parent = parent)

combine <- function(parts, sep = "") {
  parts <- lapply(parts, function(p) if (length(p)) p else "")
  lst <- unlist(lapply(parts, function(p) p[is_list_val(p)]))
  if (length(lst)) return(cap(lst))
  out <- parts[[1]]
  if (length(parts) > 1) for (p in parts[-1])
    out <- cap(as.vector(outer(out, p, function(a, b) paste0(a, sep, b))))
  cap(out)
}

res <- function(e, sc, cfg, depth = 0L) {
  if (depth > 30L) return("{deep}")
  if (is.null(e)) return("{NULL}")
  if (is.character(e)) { e[is.na(e)] <- "{NA}"; return(if (length(e)) cap(e) else "") }
  if (is.numeric(e) || is.logical(e)) return(as.character(e[1]))
  if (is.name(e)) {
    nm <- as.character(e)
    if (nm == "") return("{}")
    v <- get0(nm, envir = sc, inherits = TRUE)
    if (is.character(v)) return(v)
    return(paste0("{", nm, "}"))
  }
  if (!is.call(e)) return("{?}")
  fn <- call_name(e)
  if (is.na(fn)) return("{call}")
  a <- call_args(e)
  un <- a[names(a) == ""]
  r <- function(x) res(x, sc, cfg, depth + 1L)

  # CONFIG$a$b / x$y
  if (fn %in% c("$", "[[", "@")) {
    key <- dollar_key(e)
    if (!is.null(key)) {
      if (startsWith(key, "CONFIG$")) {
        k <- sub("^CONFIG\\$", "", key)
        return(cfg[[k]] %||% paste0("{", key, "}"))
      }
      v <- get0(key, envir = sc, inherits = TRUE)
      if (is.character(v)) return(v)
      base <- r(e[[2]])
      if (any(is_list_val(base))) return(base)
      return(paste0("{", key, "}"))
    }
    base <- r(e[[2]])
    if (any(is_list_val(base))) return(base)
    return("{index}")
  }
  if (fn == "[") return(r(e[[2]]))
  if (fn == "{") return(if (length(e) > 1) r(e[[length(e)]]) else "{}")
  if (fn %in% c("local", "isolate", "withr::with_dir")) return(if (length(un)) r(un[[1]]) else "{local}")
  if (fn %in% c("%||%", "%|%", "coalesce")) return(cap(unlist(lapply(un, r))))
  if (fn %in% PASS1 && length(un)) return(r(un[[1]]))
  if (fn %in% DATE_FNS) return("{DATE}")
  if (fn == "Sys.getenv") return(if (length(un)) paste0("{ENV:", r(un[[1]])[1], "}") else "{ENV}")
  if (fn %in% c("here", "dr_here")) {
    if (!length(un)) return("{ROOT}")
    return(combine(c(list("{ROOT}"), lapply(un, r)), "/"))
  }
  if (fn %in% c("file.path", "path")) {
    if (!length(un)) return("")
    return(combine(lapply(un, r), "/"))
  }
  if (fn %in% c("paste0", "str_c", "str_glue_data")) return(combine(lapply(un, r), ""))
  if (fn == "paste") {
    sep <- if (!is.null(a$sep)) r(a$sep)[1] else " "
    return(combine(lapply(un, r), sep))
  }
  if (fn %in% c("c", "list")) return(cap(unlist(lapply(a, r))))
  if (fn %in% c("ifelse", "if_else", "if", "switch")) return(cap(unlist(lapply(a[-1], r))))
  if (fn %in% c("sprintf", "gettextf")) {
    if (!length(un)) return("{sprintf}")
    fmt <- r(un[[1]])[1]
    vals <- lapply(un[-1], function(x) r(x)[1])
    i <- 0L
    out <- fmt
    repeat {
      m <- regexpr("%(\\d+\\$)?[-+ 0#]*\\d*(\\.\\d+)?[sdifgeExX]", out, perl = TRUE)
      if (m < 0) break
      i <- i + 1L
      rep_v <- if (i <= length(vals)) vals[[i]] else "{arg}"
      out <- paste0(substr(out, 1, m - 1), rep_v, substr(out, m + attr(m, "match.length"), nchar(out)))
    }
    return(gsub("%%", "%", out, fixed = TRUE))
  }
  if (fn %in% c("glue", "str_glue", "glue_sql")) {
    nmd <- a[names(a) != "" & !names(a) %in% c(".con", ".envir", ".sep", ".open", ".close", ".na", ".trim")]
    ch <- new_scope(sc)
    for (n in names(nmd)) assign(n, r(nmd[[n]]), envir = ch)
    tmpl <- paste(vapply(un, function(x) r(x)[1], ""), collapse = "")
    return(glue_fill(tmpl, ch, cfg, depth))
  }
  if (fn == "format") {
    if (length(un)) {
      x <- un[[1]]
      if (is.call(x) && call_name(x) %in% DATE_FNS) return("{DATE}")
      return(r(x))
    }
    return("{format}")
  }
  if (fn %in% c("basename", "dirname", "tools::file_path_sans_ext", "file_path_sans_ext")) {
    v <- r(un[[1]])
    if (any(is_list_val(v))) return(v)
    f <- switch(fn, basename = basename, dirname = dirname, tools::file_path_sans_ext)
    return(cap(vapply(v, function(s) if (has_tok(s) && fn != "basename") s else f(s), "")))
  }
  if (fn %in% c("sub", "gsub", "str_replace", "str_replace_all")) {
    if (fn %in% c("sub", "gsub")) { pat <- match_arg(a, c("pattern", "replacement", "x"), "pattern")
      rep <- match_arg(a, c("pattern", "replacement", "x"), "replacement")
      x   <- match_arg(a, c("pattern", "replacement", "x"), "x")
    } else { x <- match_arg(a, c("string", "pattern", "replacement"), "string")
      pat <- match_arg(a, c("string", "pattern", "replacement"), "pattern")
      rep <- match_arg(a, c("string", "pattern", "replacement"), "replacement") }
    if (is.null(x)) return("{sub}")
    xv <- r(x)
    pv <- if (!is.null(pat)) r(pat)[1] else NA
    rv <- if (!is.null(rep)) r(rep)[1] else NA
    if (!is.na(pv) && !is.na(rv) && !has_tok(pv) && !has_tok(rv)) {
      g <- fn %in% c("gsub", "str_replace_all")
      out <- tryCatch(vapply(xv, function(s) if (g) gsub(pv, rv, s, perl = TRUE) else sub(pv, rv, s, perl = TRUE), ""),
                      error = function(e) xv)
      return(cap(unname(out)))
    }
    return(xv)
  }
  if (fn %in% c("list.files", "dir", "dir_ls", "list.dirs")) {
    fa <- c("path", "pattern", "all.files", "full.names", "recursive")
    p  <- match_arg(a, fa, "path")
    pt <- match_arg(a, fa, "pattern", c("regexp"))
    gl <- a[["glob"]]
    rc <- match_arg(a, fa, "recursive")
    dirv <- if (is.null(p)) "." else {
      dv <- r(p); ok <- !grepl("^\\{TMP\\}|^tests/|/tests/fixtures/", vapply(dv, norm_path, ""))
      if (any(ok)) dv[ok][1] else dv[1]
    }
    patv <- if (!is.null(pt)) r(pt)[1] else if (!is.null(gl)) utils::glob2rx(r(gl)[1]) else ""
    return(mk_list_val(norm_path(dirv), patv, isTRUE(rc) || identical(rc, quote(TRUE))))
  }
  if (fn == "Sys.glob") {
    g <- norm_path(r(un[[1]])[1])
    return(mk_list_val(dirname(g), utils::glob2rx(basename(g))))
  }
  if (fn %in% c("tempfile", "tempdir")) return("{TMP}")
  paste0("{", fn, "()}")
}

dollar_key <- function(e) {
  # flatten a$b$c / a[["b"]] into "a$b$c"; NULL if not a simple chain
  if (is.name(e)) return(as.character(e))
  if (!is.call(e)) return(NULL)
  fn <- call_name(e)
  if (!fn %in% c("$", "[[", "@") || length(e) < 3) return(NULL)
  left <- dollar_key(e[[2]])
  if (is.null(left)) return(NULL)
  k <- e[[3]]
  kk <- if (is.name(k)) as.character(k) else if (is.character(k)) k[1] else return(NULL)
  if (fn == "[[" && is.name(k)) return(NULL)  # x[[var]] -- unknown key
  paste0(left, "$", kk)
}

glue_fill <- function(tmpl, sc, cfg, depth) {
  out <- tmpl
  repeat {
    m <- regexpr("\\{[^{}]+\\}", out, perl = TRUE)
    if (m < 0) break
    inner <- substr(out, m + 1, m + attr(m, "match.length") - 2)
    if (inner %in% c("DATE", "ROOT", "TMP")) {
      # resolver token carried in from a resolved argument: keep it
      out <- paste0(substr(out, 1, m - 1), "\u0001", inner, "\u0002",
                    substr(out, m + attr(m, "match.length"), nchar(out)))
      next
    }
    v <- tryCatch({
      ex <- parse(text = inner, keep.source = FALSE)[[1]]
      res(ex, sc, cfg, depth + 1L)[1]
    }, error = function(e) paste0("{", inner, "}"))
    v <- gsub("\\{([^{}]*)\\}", "\u0001\\1\u0002", v)
    out <- paste0(substr(out, 1, m - 1), v, substr(out, m + attr(m, "match.length"), nchar(out)))
  }
  gsub("\u0002", "}", gsub("\u0001", "{", out, fixed = TRUE), fixed = TRUE)
}

# -----------------------------------------------------------------------------
# 3. Path normalisation
# -----------------------------------------------------------------------------
ROOT_ABS <- NULL
norm_path <- function(p) {
  if (is.na(p) || !nzchar(p)) return(p)
  if (is_list_val(p)) return(p)
  p <- gsub("\\\\", "/", p)
  p <- gsub("\\{[^{}]*(date|dated|today|stamp|ymd|yyyymmdd)[^{}]*\\}", "{DATE}", p,
            ignore.case = TRUE, perl = TRUE)
  p <- gsub("(?<![0-9])20[0-9]{6}(?![0-9])", "{DATE}", p, perl = TRUE)
  if (!is.null(ROOT_ABS) && startsWith(p, paste0(ROOT_ABS, "/"))) p <- substring(p, nchar(ROOT_ABS) + 2)
  p <- sub("^\\{ROOT\\}/?", "", p)
  p <- sub("^\\{(PROJECT_ROOT|PROJ_ROOT|project_root|root|ROOT_DIR|repo_root|proj_dir)\\}/", "", p)
  # absolute or token prefix in front of a project folder -> make relative
  p <- sub("^(/[^{}]*?/|\\{[^{}]+\\}/)(output|R|data|docs|\\.planning)/", "\\2/", p, perl = TRUE)
  p <- gsub("/+", "/", p)
  p <- sub("^\\./", "", p)
  p
}

# -----------------------------------------------------------------------------
# 4. SQL table extraction
# -----------------------------------------------------------------------------
sql_tables <- function(s) {
  s <- gsub("--[^\n]*", " ", s)
  s <- gsub("/\\*.*?\\*/", " ", s, perl = TRUE)
  S <- toupper(s)
  ident <- "((?:\"[^\"]+\"|[A-Za-z_][A-Za-z0-9_]*|\\{[^{}]+\\})(?:\\.(?:\"[^\"]+\"|[A-Za-z_][A-Za-z0-9_]*|\\{[^{}]+\\}))*)"
  grab <- function(rx) {
    m <- regmatches(S, gregexpr(rx, S, perl = TRUE))[[1]]
    if (!length(m)) return(character())
    sub(rx, "\\1", m, perl = TRUE)
  }
  cte <- grab(paste0("(?:WITH|,)\\s+", ident, "\\s+AS\\s*\\("))
  rd  <- grab(paste0("\\b(?:FROM|JOIN)\\s+", ident))
  wr  <- c(grab(paste0("\\bCREATE\\s+(?:OR\\s+REPLACE\\s+)?(?:TEMP(?:ORARY)?\\s+)?(?:TABLE|VIEW)\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?", ident)),
           grab(paste0("\\bINSERT\\s+(?:OR\\s+REPLACE\\s+)?INTO\\s+", ident)),
           grab(paste0("\\bUPDATE\\s+", ident, "\\s+SET\\b")),
           grab(paste0("\\bALTER\\s+TABLE\\s+", ident)),
           grab(paste0("\\bCOPY\\s+", ident, "\\s+FROM\\b")))
  del <- grab(paste0("\\bDELETE\\s+FROM\\s+", ident))
  wr <- c(wr, del)
  clean <- function(x) {
    x <- gsub("\"", "", x)
    x <- sub(".*\\.", "", x)
    x <- x[!x %in% c("SELECT", "LATERAL", "UNNEST", "VALUES", "GENERATE_SERIES", "RANGE", "")]
    unique(x)
  }
  rd <- setdiff(clean(rd), c(clean(cte), clean(del)))
  files_r <- regmatches(s, gregexpr("(?i)read_(?:parquet|csv(?:_auto)?|json(?:_auto)?)\\s*\\(\\s*'([^']+)'", s, perl = TRUE))[[1]]
  files_r <- sub("(?i).*'([^']+)'.*", "\\1", files_r, perl = TRUE)
  files_w <- regmatches(s, gregexpr("(?i)\\bTO\\s+'([^']+)'", s, perl = TRUE))[[1]]
  files_w <- sub("(?i).*'([^']+)'.*", "\\1", files_w, perl = TRUE)
  list(reads = rd, writes = clean(wr), file_reads = files_r, file_writes = files_w)
}

# -----------------------------------------------------------------------------
# 5. The walker
# -----------------------------------------------------------------------------
analyze <- function(root) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  ROOT_ABS <<- root
  all_r <- list.files(file.path(root, "R"), pattern = "\\.[Rr]$", recursive = TRUE, full.names = TRUE)
  rel_of <- function(p) sub(paste0("^", gsub("([.|()\\^{}+$*?\\[\\]])", "\\\\\\1", root), "/"), "",
                            normalizePath(p, winslash = "/", mustWork = FALSE))
  rel <- vapply(all_r, rel_of, "", USE.NAMES = FALSE)
  self <- c("R/tools/dep_map.R", "tools/dep_map.R")
  keep <- !rel %in% self
  all_r <- all_r[keep]; rel <- rel[keep]
  archived <- grepl("(^|/)archive/", rel)
  ftype <- ifelse(archived, "archived",
           ifelse(startsWith(rel, "R/utils/"), "util",
           ifelse(startsWith(rel, "R/tools/"), "tool", "script")))

  # accumulators
  E <- new.env()
  E$edges <- list(); E$defs <- list(); E$calls <- list(); E$refs <- character()
  E$listings <- list(); E$assigned <- character(); E$formals <- character()
  E$strs <- character(); E$pkgs <- character(); E$pin_depth <- 0L
  add_edge <- function(file, line, type, art, fn, raw, resolution, pattern = FALSE) {
    E$edges[[length(E$edges) + 1L]] <- list(file = file, line = line, edge_type = type,
      artifact = art, fn = fn, raw = substr(raw, 1, 160), resolution = resolution, is_pattern = pattern)
  }
  resolution_of <- function(v) {
    if (is_list_val(v)) { lv <- parse_list_val(v)
      return(if (nzchar(lv$pat) && !has_tok(lv$dir)) "full" else if (nzchar(lv$pat)) "partial" else "none") }
    lit <- strip_tok(gsub("\\{DATE\\}", "", v))
    if (!grepl("[A-Za-z0-9]", lit)) return("none")
    toks <- regmatches(v, gregexpr("\\{[A-Za-z_.][^{}]*\\}", v))[[1]]
    toks <- toks[!toks %in% c("{DATE}")]
    if (!length(toks)) "full" else "partial"
  }

  CFG <- list()
  STATE <- new.env()
  STATE$mode_config <- FALSE

  prefer_prod <- function(vals) {
    if (length(vals) < 2) return(vals)
    nv <- vapply(vals, function(v) if (is_list_val(v)) v else norm_path(v), "")
    alt <- grepl("^\\{TMP\\}|^(LIST::)?tests/|/tests/fixtures/|^LIST::\\{TMP\\}", nv)
    if (any(!alt)) vals[!alt] else vals
  }
  record_path_edge <- function(type, expr, fn, file, line, sc) {
    if (is.null(expr)) { add_edge(file, line, type, NA, fn, "<no arg>", "none"); return(invisible()) }
    vals <- prefer_prod(res(expr, sc, CFG))
    raw <- paste(deparse(expr, width.cutoff = 200L), collapse = " ")
    for (v in vals) {
      if (is_list_val(v)) {
        add_edge(file, line, type, v, fn, raw, resolution_of(v), pattern = TRUE)
      } else {
        nv <- norm_path(v)
        add_edge(file, line, type, nv, fn, raw, resolution_of(nv))
      }
    }
  }
  record_source <- function(expr, file, line, sc, fn = "source") {
    vals <- if (is.character(expr) && length(expr) > 1) expr else res(expr, sc, CFG)
    raw <- paste(deparse(expr, width.cutoff = 200L), collapse = " ")
    for (v in vals) {
      if (is_list_val(v)) {
        lv <- parse_list_val(v)
        hits <- rel[startsWith(rel, paste0(sub("/$", "", lv$dir), "/")) &
                    (lv$rec | dirname(rel) == sub("/$", "", lv$dir))]
        if (nzchar(lv$pat)) hits <- hits[vapply(basename(hits), function(b)
          isTRUE(tryCatch(grepl(lv$pat, b, perl = TRUE), error = function(e) FALSE)), logical(1))]
        if (length(hits)) for (h in hits) add_edge(file, line, "sources", h, fn, raw, "full")
        else add_edge(file, line, "sources", v, fn, raw, "partial", pattern = TRUE)
      } else {
        nv <- norm_path(v)
        add_edge(file, line, "sources", nv, fn, raw, resolution_of(nv))
      }
    }
  }
  record_sql <- function(s_expr, file, line, sc, fn) {
    vals <- if (is.character(s_expr)) s_expr else res(s_expr, sc, CFG)
    raw <- paste(deparse(s_expr, width.cutoff = 200L), collapse = " ")
    any_sql <- FALSE
    for (s in vals) {
      if (!grepl(SQL_START, s, ignore.case = TRUE, perl = TRUE)) next
      any_sql <- TRUE
      t <- sql_tables(s)
      for (x in t$reads)  add_edge(file, line, "db_read",  paste0("db:", x), fn, raw, if (has_tok(x)) "partial" else "full")
      for (x in t$writes) add_edge(file, line, "db_write", paste0("db:", x), fn, raw, if (has_tok(x)) "partial" else "full")
      for (x in t$file_reads)  add_edge(file, line, "reads",  norm_path(x), fn, raw, resolution_of(norm_path(x)))
      for (x in t$file_writes) add_edge(file, line, "writes", norm_path(x), fn, raw, resolution_of(norm_path(x)))
    }
    any_sql
  }

  snap <- function(sc) { n <- new_scope(parent.env(sc)); for (k in ls(sc, all.names = TRUE)) assign(k, get(k, envir = sc), envir = n); n }
  merge_sc <- function(s1, s2, into) {
    for (k in union(ls(s1, all.names = TRUE), ls(s2, all.names = TRUE))) {
      v <- cap(c(get0(k, envir = s1, inherits = FALSE), get0(k, envir = s2, inherits = FALSE)))
      assign(k, v, envir = into)
    }
    into
  }

  # main recursive walker. sc is an environment holding the scope (it is modified)
  walk <- function(e, file, line, sc, depth = 0L, fn_ctx = NA_character_) {
    if (depth > 400L) return(invisible())
    if (is.character(e)) { if (length(e) == 1 && !is.na(e) && nchar(e, type = "bytes") < 400) E$strs <- c(E$strs, e); return(invisible()) }
    if (is.name(e)) { nm <- as.character(e); if (nzchar(nm)) E$refs <- c(E$refs, nm); return(invisible()) }
    if (!is.call(e)) return(invisible())
    fn <- call_name(e)
    pkg <- call_pkg(e)
    if (!is.na(pkg)) E$pkgs <- c(E$pkgs, pkg)
    if (is.na(fn)) {                     # e.g. f()(x) or (function(x) ...)(1)
      for (i in seq_along(e)) if (!is_miss(e[[i]])) walk(e[[i]], file, line, sc, depth + 1L, fn_ctx)
      return(invisible())
    }
    if (fn %in% NO_WALK) return(invisible())

    # --- blocks: keep per-statement line numbers
    if (fn == "{") {
      sr <- attr(e, "srcref")
      for (i in seq_along(e)[-1]) {
        if (is_miss(e[[i]])) next
        ln <- if (!is.null(sr) && length(sr) >= i) sr[[i]][1] else line
        walk(e[[i]], file, ln, sc, depth + 1L, fn_ctx)
      }
      return(invisible())
    }
    # --- if / else: walk both branches, merge assignments
    if (fn == "if") {
      walk(e[[2]], file, line, sc, depth + 1L, fn_ctx)
      cond_txt <- paste(deparse(e[[2]], width.cutoff = 200L), collapse = " ")
      pinny <- grepl("nzchar|override|pin|getenv|file\\.exists", cond_txt, ignore.case = TRUE)
      if (pinny) { E$pin_depth <- E$pin_depth + 1L; on.exit(E$pin_depth <- E$pin_depth - 1L, add = TRUE) }
      pre <- snap(sc)
      s1 <- snap(pre); walk(e[[3]], file, line, s1, depth + 1L, fn_ctx)
      s2 <- snap(pre); if (length(e) >= 4) walk(e[[4]], file, line, s2, depth + 1L, fn_ctx)
      for (k in ls(sc, all.names = TRUE)) rm(list = k, envir = sc)
      merge_sc(s1, s2, sc)
      return(invisible())
    }
    # --- for loop: bind loop var to the resolved sequence
    if (fn == "for") {
      var <- as.character(e[[2]])
      walk(e[[3]], file, line, sc, depth + 1L, fn_ctx)
      seqv <- if (is.name(e[[3]]) || is.call(e[[3]])) res(e[[3]], sc, CFG) else "{seq}"
      assign(var, seqv, envir = sc)
      walk(e[[4]], file, line, sc, depth + 1L, fn_ctx)
      return(invisible())
    }
    # --- function literal
    if (fn == "function") {
      fs <- names(e[[2]]) %||% character()
      E$formals <- c(E$formals, fs)
      inner <- new_scope(sc)
      for (f in fs) assign(f, paste0("{", f, "}"), envir = inner)
      walk(e[[3]], file, line, inner, depth + 1L, fn_ctx)
      return(invisible())
    }
    # --- assignment
    if (fn %in% c("<-", "=", "<<-", "assign")) {
      if (fn == "assign") {
        a <- call_args(e); nmx <- match_arg(a, c("x", "value"), "x"); val <- match_arg(a, c("x", "value"), "value")
        if (is.character(nmx) && !is.null(val)) {
          lhs_key <- nmx
          if (is.call(val) && identical(call_name(val), "function"))
            E$defs[[length(E$defs) + 1L]] <- list(fn = nmx, file = file, line = line, top = depth <= 2L)
          walk(val, file, line, sc, depth + 1L, fn_ctx)
          E$assigned <- c(E$assigned, nmx)
        }
        return(invisible())
      }
      lhs <- e[[2]]; rhs <- e[[3]]
      key <- dollar_key(lhs)
      is_fun <- is.call(rhs) && identical(call_name(rhs), "function")
      if (is_fun && is.name(lhs))
        E$defs[[length(E$defs) + 1L]] <- list(fn = as.character(lhs), file = file, line = line,
                                               top = identical(fn_ctx, NA_character_))
      walk(rhs, file, line, sc, depth + 1L, if (is_fun && is.name(lhs)) as.character(lhs) else fn_ctx)
      if (!is.name(lhs)) walk(lhs, file, line, sc, depth + 1L, fn_ctx)
      if (!is.null(key)) {
        E$assigned <- c(E$assigned, key)
        if (!is_fun) {
          if (startsWith(key, "CONFIG")) {
            if (key == "CONFIG" && is.call(rhs) && call_name(rhs) %in% c("list", "modifyList")) {
              lst <- if (identical(call_name(rhs), "list")) rhs else rhs[[3]]
              cfg_from_list(lst, "", sc)
            } else if (key != "CONFIG") {
              k <- sub("^CONFIG\\$", "", key)
              CFG[[k]] <<- cap(c(res(rhs, sc, CFG)))
            }
          } else {
            v <- res(rhs, sc, CFG)
            assign(key, v, envir = sc)
            if (is.call(rhs) && identical(call_name(rhs), "list")) {
              ra <- call_args(rhs)
              for (n in names(ra)[names(ra) != ""]) assign(paste0(key, "$", n), res(ra[[n]], sc, CFG), envir = sc)
            }
          }
        }
      }
      return(invisible())
    }
    # --- magrittr pipe: insert placeholder as first arg of the rhs call
    if (fn %in% c("%>%", "%T>%", "%<>%")) {
      walk(e[[2]], file, line, sc, depth + 1L, fn_ctx)
      rhs <- e[[3]]
      if (is.call(rhs)) {
        has_dot <- any(vapply(as.list(rhs)[-1], function(x) identical(x, quote(.)), logical(1)))
        if (!has_dot) rhs <- as.call(c(as.list(rhs)[1], list(quote(.PIPE)), as.list(rhs)[-1]))
      } else if (is.name(rhs)) rhs <- as.call(list(rhs, quote(.PIPE)))
      walk(rhs, file, line, sc, depth + 1L, fn_ctx)
      return(invisible())
    }

    # --- record call (for function index)
    E$calls[[length(E$calls) + 1L]] <- list(fn = fn, file = file, line = line, pkg = pkg)
    a <- call_args(e)
    if (fn %in% c("library", "require", "requireNamespace", "p_load")) {
      for (x in a[names(a) %in% c("", "package")]) {
        if (is.name(x)) E$pkgs <- c(E$pkgs, as.character(x))
        else if (is.character(x)) E$pkgs <- c(E$pkgs, x)
      }
    }

    handled <- FALSE
    spec <- SPEC[[fn]]
    if (!is.null(spec)) {
      kind <- spec[[1]]; formals <- spec[[2]]; target <- spec[[3]]; alt <- if (length(spec) > 3) spec[[4]] else character()
      if (fn == "save") arg <- a[["file"]] else arg <- match_arg(a, formals, target, alt)
      if (kind == "sources") {
        if (!is.null(arg)) record_source(arg, file, line, sc, fn)
      } else if (kind %in% c("reads", "writes")) {
        if (!is.null(arg) || !fn %in% c("png", "sink", "load", "save", "writeLines", "readLines"))
          record_path_edge(kind, arg, fn, file, line, sc)
      } else if (kind == "sql") {
        if (!is.null(arg)) {
          ok <- record_sql(arg, file, line, sc, fn)
          if (!ok) add_edge(file, line, if (fn == "dbExecute") "db_write" else "db_read", NA, fn,
                            paste(deparse(arg, width.cutoff = 200L), collapse = " "), "none")
        }
      } else if (kind %in% c("db_read", "db_write")) {
        if (!is.null(arg)) {
          if (is.call(arg) && call_name(arg) %in% c("sql", "SQL")) {
            record_sql(call_args(arg)[[1]], file, line, sc, fn)
          } else {
            nmv <- if (is.call(arg) && call_name(arg) %in% c("in_schema", "Id", "I")) {
              aa <- call_args(arg); res(aa[[length(aa)]], sc, CFG)
            } else res(arg, sc, CFG)
            for (v in nmv) add_edge(file, line, kind, paste0("db:", toupper(sub(".*\\.", "", gsub("\"", "", v)))),
                                    fn, paste(deparse(arg, width.cutoff = 200L), collapse = " "),
                                    if (has_tok(v)) "partial" else "full")
          }
        }
      }
      handled <- TRUE
    }
    # list.files: remember the listing for R3
    if (fn %in% c("list.files", "dir", "dir_ls", "Sys.glob")) {
      v <- res(e, sc, CFG)[1]
      E$listings[[length(E$listings) + 1L]] <- list(file = file, line = line, value = v, pin = E$pin_depth > 0L)
    }
    # print(doc, target = ...) / cat(..., file = ...) / file.copy(from, to)
    if (fn == "print" && !is.null(a[["target"]])) record_path_edge("writes", a[["target"]], "print(target)", file, line, sc)
    if (fn == "cat" && !is.null(a[["file"]])) {
      fv <- a[["file"]]; if (!(is.character(fv) && fv == "")) record_path_edge("writes", fv, "cat(file)", file, line, sc)
    }
    if (fn == "file.copy") {
      fr <- match_arg(a, c("from", "to"), "from"); to <- match_arg(a, c("from", "to"), "to")
      if (!is.null(fr)) record_path_edge("reads", fr, "file.copy", file, line, sc)
      if (!is.null(to)) record_path_edge("writes", to, "file.copy", file, line, sc)
    }
    # functional application of source: lapply(files, source), purrr::walk(files, source)
    if (fn %in% c("lapply", "sapply", "vapply", "walk", "map", "Map", "invisible", "for_each", "purrr::walk")) {
      fns <- vapply(seq_along(a), function(i) is.name(a[[i]]) && as.character(a[[i]]) %in% c("source", "sys.source"), logical(1))
      if (any(fns) && length(a) >= 1 && !fns[1]) { record_source(a[[1]], file, line, sc, "source (apply)"); handled <- TRUE }
    }
    # generic SQL detection for wrapper helpers, e.g. duck_query(con, "SELECT ...")
    if (!handled) {
      for (i in seq_along(a)) {
        x <- a[[i]]
        if (is.character(x) && length(x) == 1 && grepl(SQL_START, x, ignore.case = TRUE, perl = TRUE)) {
          record_sql(x, file, line, sc, paste0(fn, " (sql)")); break
        }
        if (is.name(x)) {
          v <- get0(as.character(x), envir = sc, inherits = TRUE)
          if (is.character(v) && any(grepl(SQL_START, v, ignore.case = TRUE, perl = TRUE))) {
            record_sql(v, file, line, sc, paste0(fn, " (sql)")); break
          }
        }
      }
    }
    # walk into arguments
    for (i in seq_along(a)) walk(a[[i]], file, line, sc, depth + 1L, fn_ctx)
    invisible()
  }

  cfg_from_list <- function(lst, prefix, sc) {
    la <- call_args(lst)
    for (n in names(la)[names(la) != ""]) {
      x <- la[[n]]
      k <- if (nzchar(prefix)) paste0(prefix, "$", n) else n
      if (is.call(x) && identical(call_name(x), "list")) cfg_from_list(x, k, sc)
      else CFG[[k]] <<- res(x, sc, CFG)
    }
  }

  walk_file <- function(path, relp, sc) {
    ex <- tryCatch(parse(path, keep.source = TRUE), error = function(e) e)
    if (inherits(ex, "error")) {
      add_edge(relp, NA, "parse_error", NA, "parse", conditionMessage(ex), "none"); return(invisible())
    }
    sr <- attr(ex, "srcref")
    for (i in seq_along(ex)) {
      ln <- if (!is.null(sr)) sr[[i]][1] else NA
      walk(ex[[i]], relp, ln, sc)
    }
    # string constants (for R6 and string references of function names)
    pd <- tryCatch(utils::getParseData(ex, includeText = TRUE), error = function(e) NULL)
    if (!is.null(pd)) {
      sc_ <- pd[pd$token == "STR_CONST", c("line1", "text")]
      if (nrow(sc_)) E$strconst[[relp]] <- sc_
    }
  }
  E$strconst <- list()

  # config pass first: its symbols seed every other file's scope
  cfg_rel <- rel[grepl("^R/0+_config\\.R$", rel)][1]
  base_sc <- new_scope()
  if (!is.na(cfg_rel)) walk_file(all_r[rel == cfg_rel], cfg_rel, base_sc)
  for (i in seq_along(all_r)) {
    if (!is.na(cfg_rel) && rel[i] == cfg_rel) next
    if (archived[i]) next                      # archived scripts: node only, not walked
    walk_file(all_r[i], rel[i], snap(base_sc))
  }

  # ---- assemble tables
  ed <- if (length(E$edges)) do.call(rbind, lapply(E$edges, as.data.frame, stringsAsFactors = FALSE)) else
    data.frame(file = character(), line = integer(), edge_type = character(), artifact = character(),
               fn = character(), raw = character(), resolution = character(), is_pattern = logical())
  ed$from <- ed$file
  ed$to <- ifelse(is.na(ed$artifact), paste0("<unresolved:", ed$fn, ">"), ed$artifact)
  ed$resolved <- ed$resolution == "full"
  defs <- if (length(E$defs)) do.call(rbind, lapply(E$defs, as.data.frame, stringsAsFactors = FALSE)) else
    data.frame(fn = character(), file = character(), line = integer(), top = logical())
  calls <- if (length(E$calls)) do.call(rbind, lapply(E$calls, function(x) data.frame(fn = x$fn, file = x$file,
            line = x$line %||% NA, pkg = x$pkg %||% NA, stringsAsFactors = FALSE))) else
    data.frame(fn = character(), file = character(), line = integer(), pkg = character())
  list(root = root, rel = rel, ftype = ftype, archived = archived, edges = ed, defs = defs,
       calls = calls, refs = unique(E$refs), strs = unique(E$strs), listings = E$listings,
       assigned = unique(E$assigned), formals = unique(E$formals), pkgs = unique(E$pkgs),
       strconst = E$strconst, cfg = CFG)
}

# -----------------------------------------------------------------------------
# 6. Derived analysis: matching, function index, risks
# -----------------------------------------------------------------------------
INTERMEDIATE_EXT <- c("rds", "rda", "rdata", "csv", "tsv", "txt", "parquet", "feather", "fst", "json", "duckdb", "qs")

art_dir  <- function(a) ifelse(grepl("/", a), sub("/[^/]*$", "", a), "")
art_base <- function(a) sub(".*/", "", a)
sample_name <- function(b) gsub("\\{[A-Za-z_.][^{}]*\\}", "X", gsub("{DATE}", "20261110", b, fixed = TRUE))
pat_to_regex <- function(p) {
  p <- gsub("\\{DATE\\}", "[0-9]{8}", p)
  gsub("\\{[A-Za-z_.][^{}]*\\}", ".*", p, perl = TRUE)
}
dir_compat <- function(d1, d2, rec = FALSE) {
  if (!nzchar(d1) || !nzchar(d2) || has_tok(d1) || has_tok(d2) || d1 == "." || d2 == ".") return(TRUE)
  d1 == d2 || (rec && startsWith(d2, paste0(d1, "/")))
}

match_reads <- function(ed) {
  # returns data.frame(read_row, write_row) pairs
  rd <- which(ed$edge_type %in% c("reads", "db_read") & !is.na(ed$artifact) & ed$resolution != "none")
  wr <- which(ed$edge_type %in% c("writes", "db_write") & !is.na(ed$artifact) & !ed$is_pattern & ed$resolution != "none")
  if (!length(rd) || !length(wr)) return(data.frame(r = integer(), w = integer()))
  wa <- ed$artifact[wr]; wdir <- art_dir(wa); wbase <- art_base(wa); wsamp <- sample_name(wbase)
  out <- list()
  for (i in rd) {
    a <- ed$artifact[i]
    if (startsWith(a, "db:")) {
      hit <- wr[wa == a]
    } else if (ed$is_pattern[i]) {
      lv <- parse_list_val(a)
      re <- pat_to_regex(lv$pat)
      ok <- vapply(seq_along(wr), function(j) {
        if (startsWith(wa[j], "db:")) return(FALSE)
        dir_compat(lv$dir, wdir[j], lv$rec) &&
          (!nzchar(lv$pat) || isTRUE(tryCatch(grepl(re, wsamp[j], perl = TRUE), error = function(e) FALSE)))
      }, logical(1))
      hit <- wr[ok]
    } else {
      b <- art_base(a); d <- art_dir(a)
      ok <- wa == a | (wbase == b & mapply(dir_compat, d, wdir))
      if (has_tok(b) && nchar(gsub("[^A-Za-z0-9]", "", sub("\\.[A-Za-z0-9]+$", "", strip_tok(gsub("{DATE}", "", b, fixed = TRUE))))) >= 3) {
        re <- paste0("^", pat_to_regex(gsub("([.+()^$|\\[\\]])", "\\\\\\1", b)), "$")
        ok <- ok | vapply(wsamp, function(s) isTRUE(tryCatch(grepl(re, s, perl = TRUE), error = function(e) FALSE)), logical(1))
      }
      hit <- wr[ok]
    }
    if (length(hit)) out[[length(out) + 1L]] <- data.frame(r = i, w = hit)
  }
  if (length(out)) do.call(rbind, out) else data.frame(r = integer(), w = integer())
}

pkg_exports <- function(pkgs) {
  base <- c("base", "stats", "utils", "methods", "graphics", "grDevices", "tools", "parallel", "grid", "splines", "datasets")
  pk <- unique(c(base, pkgs))
  missing <- character()
  ex <- character()
  for (p in pk) {
    if (!requireNamespace(p, quietly = TRUE)) { missing <- c(missing, p); next }
    ex <- c(ex, tryCatch(getNamespaceExports(p), error = function(e) character()))
  }
  list(exports = unique(ex), missing = missing)
}

downstream <- function(dag, node) {
  seen <- character(); fr <- node
  while (length(fr)) {
    nx <- unique(dag$succ[dag$pred %in% fr]); nx <- setdiff(nx, c(seen, node)); seen <- c(seen, nx); fr <- nx
  }
  seen
}

read_lines_safe <- function(root, relp) tryCatch(readLines(file.path(root, relp), warn = FALSE), error = function(e) character())

derive <- function(A) {
  ed <- A$edges
  pairs <- match_reads(ed)
  # script DAG from artifacts
  dag <- if (nrow(pairs)) unique(data.frame(pred = ed$from[pairs$w], succ = ed$from[pairs$r],
                                             via = ed$artifact[pairs$w], stringsAsFactors = FALSE)) else
    data.frame(pred = character(), succ = character(), via = character())
  dag <- dag[dag$pred != dag$succ, , drop = FALSE]
  dag_s <- unique(dag[, c("pred", "succ")])

  # function index
  defs <- A$defs
  top <- defs[defs$top, , drop = FALSE]
  proj_fns <- unique(defs$fn)
  calls <- A$calls
  cp <- calls[calls$fn %in% top$fn & is.na(calls$pkg), , drop = FALSE]
  if (nrow(cp)) {
    cp$def_file <- top$file[match(cp$fn, top$fn)]
    fn_edges <- unique(cp[cp$def_file != cp$file, c("file", "def_file", "fn")])
    fn_first_line <- aggregate(line ~ file + fn, data = cp, FUN = min)
    fn_edges$line <- fn_first_line$line[match(paste(fn_edges$file, fn_edges$fn), paste(fn_first_line$file, fn_first_line$fn))]
  } else fn_edges <- data.frame(file = character(), def_file = character(), fn = character(), line = integer())

  pe <- pkg_exports(A$pkgs)
  local_names <- unique(c(A$assigned, A$formals, proj_fns, ".", "J", "CJ", "SJ", ".SD", ".N", ".I", ".GRP", ".BY"))
  und <- calls[is.na(calls$pkg) & !calls$fn %in% local_names & !calls$fn %in% pe$exports, , drop = FALSE]
  und <- und[!vapply(und$fn, function(f) exists(f, envir = baseenv()), logical(1)), , drop = FALSE]
  r7c <- if (nrow(und)) {
    agg <- aggregate(line ~ fn, data = und, FUN = length); names(agg)[2] <- "n_calls"
    agg$callers <- vapply(agg$fn, function(f) { u <- und[und$fn == f, ]
      paste(head(unique(paste0(u$file, ":", u$line)), 8), collapse = "; ") }, "")
    agg[order(-agg$n_calls), ]
  } else data.frame(fn = character(), n_calls = integer(), callers = character())

  # R7a / R7b
  dup <- top[top$fn %in% top$fn[duplicated(top$fn)], , drop = FALSE]
  dup <- dup[order(dup$fn), , drop = FALSE]
  dup_multi <- dup[ave(dup$file, dup$fn, FUN = function(x) length(unique(x))) > 1, , drop = FALSE]
  called <- unique(c(calls$fn, A$refs, A$strs))
  never <- top[!top$fn %in% called, , drop = FALSE]

  # R1 orphan reads / R2 dead writes
  rd_rows <- which(ed$edge_type %in% c("reads", "db_read") & !is.na(ed$artifact) & ed$resolution != "none")
  wr_rows <- which(ed$edge_type %in% c("writes", "db_write") & !is.na(ed$artifact) & ed$resolution != "none")
  matched_r <- unique(pairs$r); matched_w <- unique(pairs$w)
  orph <- setdiff(rd_rows, matched_r)
  is_external <- function(a) (grepl("^(/|\\{CONFIG\\$data|\\{ENV|~|data/)", a) | !grepl("/", a)) & !grepl("^(output|R)/", a) & !is_list_val(a)
  orph_art <- ed$artifact[orph]
  orph_ext <- orph[is_external(orph_art) | startsWith(orph_art, "db:")]
  orph_int <- setdiff(orph, orph_ext)
  near <- function(i) {
    a <- ed$artifact[i]
    w <- unique(ed$artifact[wr_rows]); w <- w[!startsWith(w, "db:")]
    if (ed$is_pattern[i]) {
      lv <- parse_list_val(a)
      alt <- gsub("\\\\\\.(rds|csv|xlsx|parquet)", "\\\\.[a-z]+", lv$pat)
      re <- pat_to_regex(alt)
      h <- w[vapply(sample_name(art_base(w)), function(s) isTRUE(tryCatch(grepl(re, s, perl = TRUE), error = function(e) FALSE)), logical(1))]
    } else {
      stem <- sub("\\.[A-Za-z0-9]+$", "", art_base(a))
      h <- w[sub("\\.[A-Za-z0-9]+$", "", art_base(w)) == stem]
    }
    if (length(h)) {
      who <- unique(ed$from[wr_rows][ed$artifact[wr_rows] %in% h])
      paste0(paste(head(h, 3), collapse = ", "), " (written by ", paste(head(who, 3), collapse = ", "), ")")
    } else ""
  }
  r1 <- if (length(orph_int)) data.frame(artifact = ed$artifact[orph_int], reader = paste0(ed$from[orph_int], ":", ed$line[orph_int]),
                                         reader_file = ed$from[orph_int],
                                         near_miss = vapply(orph_int, near, ""), stringsAsFactors = FALSE) else
    data.frame(artifact = character(), reader = character(), reader_file = character(), near_miss = character())
  r1_ext <- if (length(orph_ext)) unique(data.frame(artifact = ed$artifact[orph_ext], reader = ed$from[orph_ext])) else data.frame()

  dead <- setdiff(wr_rows, matched_w)
  ext <- tolower(sub(".*\\.", "", ed$artifact[dead]))
  dead_int <- dead[ext %in% INTERMEDIATE_EXT | startsWith(ed$artifact[dead], "db:")]
  r2 <- if (length(dead_int)) data.frame(artifact = ed$artifact[dead_int], writer = paste0(ed$from[dead_int], ":", ed$line[dead_int]),
                                         writer_file = ed$from[dead_int], stringsAsFactors = FALSE) else
    data.frame(artifact = character(), writer = character(), writer_file = character())
  r2_deliv <- length(setdiff(dead, dead_int))

  # R3 latest-file selection
  r3 <- list()
  for (L in A$listings) {
    ln <- read_lines_safe(A$root, L$file)
    if (!length(ln) || is.na(L$line)) next
    ctx <- paste(ln[max(1, L$line - 2):min(length(ln), L$line + 8)], collapse = " ")
    if (!grepl("file\\.mtime|file\\.info|which\\.max|order\\(|sort\\(|tail\\(|rev\\(|max\\(|\\[\\s*length\\(", ctx)) next
    pre <- paste(ln[max(1, L$line - 6):min(length(ln), L$line + 2)], collapse = " ")
    env <- regmatches(pre, gregexpr("Sys\\.getenv\\(\\s*[\"']([A-Za-z0-9_]+)[\"']", pre, perl = TRUE))[[1]]
    pin <- isTRUE(L$pin) || grepl("Sys\\.getenv", pre)
    lv <- if (is_list_val(L$value)) parse_list_val(L$value) else list(dir = L$value, pat = "")
    r3[[length(r3) + 1L]] <- data.frame(file = L$file, line = L$line, location = paste0(L$file, ":", L$line),
      dir = lv$dir, pattern = if (nzchar(lv$pat)) lv$pat else "(none)", has_pin = pin,
      pin_env = paste(unique(sub(".*\\(\\s*[\"']([A-Za-z0-9_]+).*", "\\1", env)), collapse = ","), stringsAsFactors = FALSE)
  }
  r3 <- if (length(r3)) do.call(rbind, r3) else data.frame(file = character(), line = integer(), location = character(),
                                                           dir = character(), pattern = character(), has_pin = logical(), pin_env = character())

  # R4 same-date overwrite
  wd <- which(ed$edge_type == "writes" & grepl("{DATE}", ed$artifact, fixed = TRUE))
  r4 <- list()
  for (i in wd) {
    ln <- read_lines_safe(A$root, ed$from[i])
    if (!length(ln) || is.na(ed$line[i])) next
    ctx <- paste(ln[max(1, ed$line[i] - 20):min(length(ln), ed$line[i] + 3)], collapse = " ")
    if (grepl("file\\.exists|_v[0-9]|_v\\\"|versioned|next_version|overwrite\\s*=\\s*FALSE", ctx)) next
    r4[[length(r4) + 1L]] <- data.frame(location = paste0(ed$from[i], ":", ed$line[i]), file = ed$from[i], artifact = ed$artifact[i],
      explicit_overwrite = grepl("overwrite\\s*=\\s*TRUE", ctx), stringsAsFactors = FALSE)
  }
  r4 <- if (length(r4)) unique(do.call(rbind, r4)) else data.frame(location = character(), file = character(), artifact = character(), explicit_overwrite = logical())

  # R5 unresolved
  r5 <- ed[ed$resolution != "full" & ed$edge_type != "parse_error", c("edge_type", "from", "line", "fn", "resolution", "artifact", "raw")]

  # R6 absolute paths in string constants
  r6 <- list()
  for (f in names(A$strconst)) {
    s <- A$strconst[[f]]
    hit <- grepl("^[\"'](/blue|/orange|/ufrc|/home|/apps|[A-Za-z]:[\\\\/]|~/)", s$text)
    if (any(hit)) r6[[length(r6) + 1L]] <- data.frame(location = paste0(f, ":", s$line1[hit]), file = f, path = s$text[hit], stringsAsFactors = FALSE)
  }
  r6 <- if (length(r6)) do.call(rbind, r6) else data.frame(location = character(), file = character(), path = character())

  # R8 topological order, cycles, inversions
  nodes_dag <- unique(c(dag_s$pred, dag_s$succ))
  indeg <- setNames(vapply(nodes_dag, function(n) sum(dag_s$succ == n), 0), nodes_dag)
  q <- names(indeg)[indeg == 0]; topo <- character(); rem <- dag_s
  while (length(q)) {
    q <- q[order(suppressWarnings(as.numeric(sub("^R/([0-9]+).*", "\\1", q))), q)]
    n <- q[1]; q <- q[-1]; topo <- c(topo, n)
    succ <- rem$succ[rem$pred == n]; rem <- rem[rem$pred != n, , drop = FALSE]
    for (s in unique(succ)) if (!s %in% rem$succ) q <- c(q, s)
  }
  cyc <- setdiff(nodes_dag, topo)
  num <- function(x) suppressWarnings(as.numeric(sub("^R/(?:[a-z]+/)?([0-9]+).*", "\\1", x, perl = TRUE)))
  inv <- dag[!is.na(num(dag$pred)) & !is.na(num(dag$succ)) & num(dag$pred) > num(dag$succ), , drop = FALSE]

  # R11 artifacts written by more than one script (order-dependent results)
  mw <- ed[wr_rows, c("artifact", "from")]
  mw <- unique(mw[!startsWith(mw$artifact, "db:") | TRUE, ])
  nw <- tapply(mw$from, mw$artifact, function(x) length(unique(x)))
  multi <- names(nw)[nw > 1]
  r11 <- if (length(multi)) data.frame(artifact = multi, writers = vapply(multi, function(a)
    paste(sort(unique(mw$from[mw$artifact == a])), collapse = "; "), ""), n_writers = as.integer(nw[multi]),
    stringsAsFactors = FALSE) else data.frame(artifact = character(), writers = character(), n_writers = integer())
  r11 <- r11[order(-r11$n_writers, r11$artifact), , drop = FALSE]

  # R10 scripts that write R code / config
  w10 <- which(ed$edge_type == "writes" & grepl("\\.[Rr](\\.bak)?$", ed$artifact))
  r10 <- if (length(w10)) unique(data.frame(location = paste0(ed$from[w10], ":", ed$line[w10]), file = ed$from[w10],
                                            artifact = ed$artifact[w10], stringsAsFactors = FALSE)) else
    data.frame(location = character(), file = character(), artifact = character())

  # R9 isolated scripts
  scripts <- A$rel[A$ftype == "script"]
  connected <- unique(c(dag_s$pred, dag_s$succ, ed$to[ed$edge_type == "sources"]))
  r9 <- setdiff(scripts, connected)

  list(pairs = pairs, dag = dag, dag_s = dag_s, fn_edges = fn_edges, r1 = r1, r1_ext = r1_ext, r2 = r2,
       r2_deliv = r2_deliv, r3 = r3, r4 = r4, r5 = r5, r6 = r6, r7a = dup_multi, r7b = never, r7c = r7c,
       pkgs_missing = pe$missing, topo = topo, cycles = cyc, inversions = inv, r9 = r9, r10 = r10, r11 = r11)
}

# -----------------------------------------------------------------------------
# 7. Validation gate
# -----------------------------------------------------------------------------
gate_generic <- function(A) {
  ed <- A$edges
  rate <- function(types, lv = c("full", "partial")) {
    x <- ed[ed$edge_type %in% types, ]; if (!nrow(x)) return(NA_real_)
    mean(x$resolution %in% lv)
  }
  src_full <- rate("sources", "full")
  rw <- rate(c("reads", "writes"))
  data.frame(check = c("sources edges fully resolved >= 80%", "reads/writes resolved (full+partial) >= 50%",
                       "no parse errors"),
             pass = c(isTRUE(src_full >= 0.8), isTRUE(rw >= 0.5), !any(ed$edge_type == "parse_error")),
             detail = c(sprintf("%.1f%%", 100 * src_full), sprintf("%.1f%%", 100 * rw),
                        paste(ed$from[ed$edge_type == "parse_error"], collapse = ", ")),
             blocking = TRUE, stringsAsFactors = FALSE)
}

# Project-specific checks (Mailhot & Mobley HL / insurance_investigation).
# Edit these if scripts are renamed.
gate_project <- function(A, D) {
  ed <- A$edges; dag <- D$dag
  link <- function(from_rx, to_rx, via_rx) {
    any(grepl(from_rx, dag$pred) & grepl(to_rx, dag$succ) & grepl(via_rx, dag$via))
  }
  reads_rx <- function(f_rx, a_rx) any(grepl(f_rx, ed$from) & ed$edge_type == "reads" & grepl(a_rx, ed$artifact))
  defined_in <- function(fn, f_rx) any(A$defs$fn == fn & grepl(f_rx, A$defs$file))
  calls_fn <- function(f_rx, fn) any(grepl(f_rx, D$fn_edges$file) & D$fn_edges$fn == fn)
  utils_files <- A$rel[A$ftype == "util"]
  utils_sourced <- unique(ed$to[ed$edge_type == "sources" & ed$to %in% utils_files])
  r3_165 <- D$r3[grepl("R/165_", D$r3$file), ]
  chk <- list(
    c("R/122 -> R/165 via encounter_distance", link("R/122_", "R/165_", "encounter_distance")),
    c("R/165 reads payer_summary*.rds pattern", reads_rx("R/165_", "payer_summary.*rds")),
    c("R/02 -> R/165 via payer_summary.csv", link("R/02_", "R/165_", "payer_summary")),
    c("R/116 -> R/165 via encounter_ses_index", link("R/116_", "R/165_", "encounter_ses_index")),
    c("get_hl_any_dx_ids defined in utils_treatment.R", defined_in("get_hl_any_dx_ids", "R/utils/utils_treatment\\.R$")),
    c("R/165 calls get_hl_any_dx_ids (calls_fn edge)", calls_fn("R/165_", "get_hl_any_dx_ids")),
    c("zi_normalise_xwalk not in R7c", !"zi_normalise_xwalk" %in% D$r7c$fn),
    c("zip_distance not in R7c", !"zip_distance" %in% D$r7c$fn),
    c(sprintf("all %d R/utils files reached by source() (%d reached)", length(utils_files), length(utils_sourced)),
      length(utils_sourced) == length(utils_files)),
    c("R3 lists R/165 encounter_distance with has_pin = TRUE",
      any(grepl("encounter_distance", r3_165$pattern) & r3_165$has_pin))
  )
  # previous (v1) R3 hits must reappear within 10 lines
  prev <- c("R/166_survivorship_modality_rates.R:79", "R/167_anthracycline_echo.R:63", "R/168_survivorship_workbook.R:51",
            "R/168_survivorship_workbook.R:63", "R/179_cbc_patient_year.R:153", "R/179_cbc_patient_year.R:170",
            "R/180_cbc_missing_capture.R:184", "R/180_cbc_missing_capture.R:205", "R/182_facility_zip_recovery_report.R:151",
            "R/183_mice_sensitivity_distance.R:388", "R/88_smoke_test_comprehensive.R:6342", "R/88_smoke_test_comprehensive.R:7444",
            "R/88_smoke_test_comprehensive.R:7446", "R/88_smoke_test_comprehensive.R:7575", "R/88_smoke_test_comprehensive.R:7577",
            "R/88_smoke_test_comprehensive.R:7606", "R/89_generate_reference_manual.R:293", "R/89_generate_reference_manual.R:303")
  prev <- prev[sub(":.*", "", prev) %in% A$rel]
  if (length(prev)) {
    miss <- prev[!vapply(prev, function(p) { f <- sub(":.*", "", p); l <- as.integer(sub(".*:", "", p))
      any(D$r3$file == f & abs(D$r3$line - l) <= 10) }, logical(1))]
    chk[[length(chk) + 1L]] <- c(sprintf("[info] v1 R3 hits reappear (%d/%d)", length(prev) - length(miss), length(prev)),
                                 length(miss) == 0)
    if (length(miss)) chk[[length(chk)]][1] <- paste0(chk[[length(chk)]][1], " missing: ", paste(miss, collapse = ", "))
  }
  out <- data.frame(check = vapply(chk, `[`, "", 1), pass = as.logical(vapply(chk, `[`, "", 2)), detail = "",
                    blocking = TRUE, stringsAsFactors = FALSE)
  out$blocking[startsWith(out$check, "[info]")] <- FALSE   # v1 used a looser regex; differences are expected
  out
}

# -----------------------------------------------------------------------------
# 8. Outputs
# -----------------------------------------------------------------------------
md_table <- function(df, cols = names(df), n = Inf) {
  if (is.null(df) || !nrow(df)) return("No findings.")
  df <- df[seq_len(min(nrow(df), n)), intersect(cols, names(df)), drop = FALSE]
  esc <- function(x) gsub("\\|", "\\\\|", gsub("\n", " ", as.character(x)))
  c(paste("|", paste(names(df), collapse = " | "), "|"),
    paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|"),
    apply(df, 1, function(r) paste("|", paste(esc(r), collapse = " | "), "|")))
}

write_outputs <- function(A, D, G, out_dir, gate_ok) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dated <- format(Sys.Date(), "%Y%m%d")
  sfx <- ""; v <- 2L
  while (file.exists(file.path(out_dir, paste0("edges_", dated, sfx, ".csv")))) { sfx <- paste0("_v", v); v <- v + 1L }
  P <- function(stem, ext) file.path(out_dir, paste0(stem, "_", dated, sfx, ".", ext))
  ed <- A$edges

  # edges incl. calls_fn (file -> defining util)
  fe <- D$fn_edges
  fn_rows <- if (nrow(fe)) data.frame(from = fe$file, to = fe$def_file, edge_type = "calls_fn", artifact = fe$fn,
                                      file = fe$file, line = fe$line, resolved = TRUE, resolution = "full",
                                      fn = fe$fn, raw = "", is_pattern = FALSE, stringsAsFactors = FALSE) else NULL
  edges_out <- rbind(ed[, c("from", "to", "edge_type", "artifact", "file", "line", "resolved", "resolution", "fn", "raw", "is_pattern")], fn_rows)
  write.csv(edges_out, P("edges", "csv"), row.names = FALSE)

  # nodes
  flagged <- unique(c(D$r1$reader_file, D$r3$file[!D$r3$has_pin], D$r4$file, D$r2$writer_file))
  art_nodes <- unique(ed$to[!ed$to %in% A$rel])
  ntype <- function(a) ifelse(startsWith(a, "<unresolved"), "unresolved", ifelse(startsWith(a, "db:"), "db_table",
                      ifelse(is_list_val(a), "pattern", ifelse(grepl("^(/|~)", a), "external", "artifact"))))
  nodes <- rbind(
    data.frame(id = A$rel, type = A$ftype, phase = sub("^([0-9]+).*", "\\1", ifelse(grepl("^[0-9]", basename(A$rel)), basename(A$rel), NA)),
               archived = A$archived, stringsAsFactors = FALSE),
    data.frame(id = art_nodes, type = ntype(art_nodes), phase = NA, archived = FALSE, stringsAsFactors = FALSE))
  nodes$n_out <- vapply(nodes$id, function(n) sum(edges_out$from == n), 0)
  nodes$n_in  <- vapply(nodes$id, function(n) sum(edges_out$to == n), 0)
  nodes$flagged <- nodes$id %in% flagged
  nodes$downstream_scripts <- vapply(nodes$id, function(n) if (n %in% A$rel) length(downstream(D$dag_s, n)) else NA_real_, 0)
  write.csv(nodes, P("nodes", "csv"), row.names = FALSE)

  fx <- A$defs; fx$n_calls <- vapply(fx$fn, function(f) sum(A$calls$fn == f), 0)
  write.csv(fx, P("functions", "csv"), row.names = FALSE)
  write.csv(D$r5, P("r5_unresolved", "csv"), row.names = FALSE)
  write.csv(D$r7c, P("r7c_undefined", "csv"), row.names = FALSE)
  write.csv(G, P("gate", "csv"), row.names = FALSE)

  # ---- risk report
  res_tab <- with(ed[ed$edge_type != "parse_error", ], as.data.frame.matrix(table(edge_type, factor(resolution, levels = c("full", "partial", "none")))))
  res_tab$edge_type <- rownames(res_tab)
  res_tab$pct_full <- sprintf("%.0f%%", 100 * res_tab$full / (res_tab$full + res_tab$partial + res_tab$none))
  res_tab <- res_tab[, c("edge_type", "full", "partial", "none", "pct_full")]

  ds <- function(f) vapply(f, function(x) length(downstream(D$dag_s, x)), 0)
  top <- rbind(
    if (nrow(D$r1)) data.frame(cat = "R1 orphan read", location = D$r1$reader, what = D$r1$artifact, file = D$r1$reader_file, stringsAsFactors = FALSE),
    if (nrow(D$r3[!D$r3$has_pin, ])) with(D$r3[!D$r3$has_pin, ], data.frame(cat = "R3 latest-file, no pin", location = location, what = pattern, file = file, stringsAsFactors = FALSE)),
    if (nrow(D$r4)) data.frame(cat = "R4 same-date overwrite", location = D$r4$location, what = D$r4$artifact, file = D$r4$file, stringsAsFactors = FALSE),
    if (nrow(D$r10)) data.frame(cat = "R10 writes R code/config", location = D$r10$location, what = D$r10$artifact, file = D$r10$file, stringsAsFactors = FALSE)
  )
  if (!is.null(top) && nrow(top)) {
    top$downstream_scripts <- ds(top$file)
    top <- top[order(-top$downstream_scripts, top$cat), ]
  }
  r5_by_file <- if (nrow(D$r5)) { t <- sort(table(D$r5$from), decreasing = TRUE); data.frame(file = names(t), n_unresolved = as.integer(t)) } else data.frame()
  counts <- data.frame(category = c("R1 orphan reads (internal)", "R1 external inputs (info)", "R2 dead intermediate writes",
                                    "R2 deliverable writes never read (info)", "R3 latest-file selections", "R3 ... without pin",
                                    "R4 same-date overwrite risk", "R5 not fully resolved edges", "R6 absolute paths",
                                    "R7a functions defined in >1 file", "R7b functions never called", "R7c called but undefined",
                                    "R8 cycles", "R8 order inversions", "R9 isolated scripts", "R10 scripts writing R code/config", "R11 files written by >1 script"),
                       n = c(nrow(D$r1), nrow(D$r1_ext), nrow(D$r2), D$r2_deliv, nrow(D$r3), sum(!D$r3$has_pin), nrow(D$r4),
                             nrow(D$r5), nrow(D$r6), length(unique(D$r7a$fn)), nrow(D$r7b), nrow(D$r7c),
                             length(D$cycles), nrow(D$inversions), length(D$r9), nrow(D$r10), nrow(D$r11)))
  rpt <- c(
    paste0("# Dependency Risk Report -- ", dated, if (!gate_ok) "  (GATE FAILED -- forced output)" else ""), "",
    sprintf("Generated by `R/tools/dep_map.R` (v2) from %d files (%d scripts, %d utils, %d tools, %d archived). Root: `%s`",
            length(A$rel), sum(A$ftype == "script"), sum(A$ftype == "util"), sum(A$ftype == "tool"), sum(A$archived), A$root), "",
    "## Validation gate", "", md_table(G), "",
    "## Resolution rates", "", md_table(res_tab), "",
    if (length(D$pkgs_missing)) paste0("_Packages referenced but not installed (R7c may include their functions): ",
                                       paste(D$pkgs_missing, collapse = ", "), "_") else "", "",
    "## Summary", "", md_table(counts), "",
    "### Top 10 findings by downstream reach (R1, R3 unpinned, R4, R10)", "", if (is.null(top)) "No findings." else md_table(top, c("cat", "location", "what", "downstream_scripts"), 10), "",
    "---", "",
    "## R1 -- Orphan reads", "", "Artifacts a script reads that no script in R/ writes (internal paths only). `near_miss` = a written artifact with the same stem or a different extension.", "",
    md_table(D$r1, c("artifact", "reader", "near_miss")), "",
    sprintf("_External inputs (absolute paths / data dir / DuckDB tables with no writer in R/): %d -- listed in edges.csv, not flagged._", nrow(D$r1_ext)), "",
    "## R2 -- Dead intermediate writes", "", "Intermediate files (rds/csv/parquet/...) and DuckDB tables written but never read by any script.", "",
    md_table(D$r2, c("artifact", "writer")), "",
    sprintf("_Deliverables (xlsx/png/pdf/docx/...) written and not read: %d -- expected, not flagged._", D$r2_deliv), "",
    "## R3 -- 'Latest file' selection", "", "list.files()/Sys.glob() results selected by sort/mtime/tail nearby. `has_pin` = the listing sits inside an if/else on an override / env var / pin, or Sys.getenv() is read within 6 lines.", "",
    md_table(D$r3, c("location", "dir", "pattern", "has_pin", "pin_env")), "",
    "## R4 -- Same-date overwrite risk", "", "Dated outputs written with no file.exists()/version check in the 20 lines before the write.", "",
    md_table(D$r4, c("location", "artifact", "explicit_overwrite")), "",
    "## R5 -- Not fully resolved paths", "", sprintf("%d edges (full list in r5_unresolved csv). By file (top 30):", nrow(D$r5)), "",
    md_table(r5_by_file, n = 30), "",
    "## R6 -- Hard-coded absolute paths", "", md_table(D$r6, c("location", "path"), 100), "",
    "## R7 -- Functions", "",
    "### R7a -- Top-level functions defined in more than one file", "", md_table(D$r7a, c("fn", "file", "line")), "",
    "### R7b -- Top-level functions never called or referenced", "", md_table(D$r7b, c("fn", "file", "line"), 100), "",
    sprintf("### R7c -- Called but not defined in project or installed packages (%d; top 50, full list in r7c_undefined csv)", nrow(D$r7c)), "",
    md_table(D$r7c, c("fn", "n_calls", "callers"), 50), "",
    "## R8 -- Execution order (from data dependencies)", "",
    if (length(D$topo)) paste(seq_along(D$topo), D$topo, sep = ". ") else "No data dependencies resolved.", "",
    if (length(D$cycles)) paste0("**Cycles** (scripts on a loop of data dependencies; see R10/R11 for the files causing them): ", paste(D$cycles, collapse = "; ")) else "No cycles detected.", "",
    "**Order inversions** (higher-numbered script produces data a lower-numbered script reads):", "",
    md_table(D$inversions, c("pred", "succ", "via")), "",
    "## R9 -- Isolated scripts", "", "Scripts with no resolved data link (read or write) to any other script. Often one-off probes; check before deleting.", "",
    if (length(D$r9)) paste0("- ", D$r9) else "No findings.", "",
    "## R10 -- Scripts that write R code or config", "", "A pipeline script that rewrites a .R file (e.g. R/00_config.R) changes the code every other script runs.", "",
    md_table(D$r10, c("location", "artifact")), "",
    "## R11 -- Files written by more than one script", "",
    "The file's contents depend on which writer ran last. Usually the cause of R8 cycles (a script reads a file, then rewrites it).", "",
    md_table(D$r11, c("artifact", "n_writers", "writers")), "",
    paste0("_Generated ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "_"))
  writeLines(unlist(rpt), P("risk_report", "md"))

  # ---- Mermaid (scripts linked through resolved artifacts only)
  mid <- function(x) gsub("[^A-Za-z0-9_]", "_", x)
  dg <- D$dag
  mmd <- c("flowchart LR")
  if (nrow(dg)) {
    sc <- unique(c(dg$pred, dg$succ)); av <- unique(dg$via)
    mmd <- c(mmd, sprintf('  %s["%s"]', mid(sc), basename(sc)),
             sprintf('  %s(["%s"])', paste0("a_", mid(av)), substr(gsub('"', "'", basename(av)), 1, 50)),
             unique(sprintf("  %s --> %s", mid(dg$pred), paste0("a_", mid(dg$via)))),
             unique(sprintf("  %s --> %s", paste0("a_", mid(dg$via)), mid(dg$succ))))
  }
  writeLines(mmd, P("dep_map_scripts", "mmd"))

  # ---- HTML
  if (requireNamespace("visNetwork", quietly = TRUE)) {
    vis_e <- edges_out[!startsWith(edges_out$to, "<unresolved") & edges_out$edge_type != "parse_error", ]
    vis_e <- unique(vis_e[, c("from", "to", "edge_type", "file", "line")])
    # attach pattern reads to the artifacts they match
    if (nrow(D$pairs)) {
      pr <- D$pairs[A$edges$is_pattern[D$pairs$r], , drop = FALSE]
      if (nrow(pr)) vis_e <- rbind(vis_e, unique(data.frame(from = A$edges$artifact[pr$w], to = A$edges$artifact[pr$r],
                                                            edge_type = "matches", file = "", line = NA)))
    }
    ids <- unique(c(vis_e$from, vis_e$to))
    nd <- nodes[match(ids, nodes$id), ]
    nd$id <- ids
    nd$type[is.na(nd$type)] <- ifelse(startsWith(ids[is.na(nd$type)], "db:"), "db_table", "artifact")
    col <- c(script = "#0021A5", util = "#4A63C9", tool = "#7F8FD6", archived = "#BBBBBB", artifact = "#D9D9D9",
             pattern = "#EFEFEF", db_table = "#8C8C8C", external = "#F2F2F2")
    shp <- c(script = "box", util = "box", tool = "box", archived = "box", artifact = "ellipse", pattern = "ellipse",
             db_table = "database", external = "ellipse")
    lab <- ifelse(is_list_val(ids), vapply(ids, function(x) if (is_list_val(x)) paste0("[", parse_list_val(x)$pat, "]") else x, ""),
                  ifelse(startsWith(ids, "db:"), ids, basename(ids)))
    vn_nodes <- data.frame(id = ids, label = lab, title = ids, group = nd$type,
                           color.background = unname(col[nd$type]), color.border = ifelse(nd$flagged %in% TRUE, "#FA4616", "#555555"),
                           borderWidth = ifelse(nd$flagged %in% TRUE, 4, 1), shape = unname(shp[nd$type]),
                           font.color = ifelse(nd$type %in% c("script", "util", "tool"), "#FFFFFF", "#222222"), stringsAsFactors = FALSE)
    ecol <- c(sources = "#0021A5", reads = "#2E7D32", writes = "#FA4616", db_read = "#8D6E00", db_write = "#B71C1C",
              calls_fn = "#9E9E9E", matches = "#BDBDBD")
    vn_edges <- data.frame(from = vis_e$from, to = vis_e$to, title = paste0(vis_e$edge_type, " ", vis_e$file, ifelse(is.na(vis_e$line), "", paste0(":", vis_e$line))),
                           color = unname(ecol[vis_e$edge_type]), dashes = vis_e$edge_type %in% c("calls_fn", "matches"),
                           arrows = "to", stringsAsFactors = FALSE)
    vn_edges$color[is.na(vn_edges$color)] <- "#999999"
    vn <- visNetwork::visNetwork(vn_nodes, vn_edges, main = paste0("R pipeline dependency map -- ", dated),
                                 submain = "Boxes: scripts/utils. Ellipses: files. Cylinders: DuckDB tables. Orange border: has R1/R2/R3/R4 finding.",
                                 width = "100%", height = "900px")
    vn <- visNetwork::visOptions(vn, highlightNearest = list(enabled = TRUE, degree = list(from = 50, to = 50), algorithm = "hierarchical"),
                                 nodesIdSelection = list(enabled = TRUE, useLabels = FALSE), selectedBy = "group")
    vn <- visNetwork::visHierarchicalLayout(vn, direction = "LR", sortMethod = "directed", levelSeparation = 260, nodeSpacing = 60)
    vn <- visNetwork::visPhysics(vn, enabled = FALSE)
    vn <- visNetwork::visEdges(vn, smooth = list(type = "cubicBezier", forceDirection = "horizontal"))
    vn <- visNetwork::visInteraction(vn, hover = TRUE, navigationButtons = TRUE)
    hp <- P("dep_map", "html")
    ok <- tryCatch({ visNetwork::visSave(vn, hp, selfcontained = TRUE)
      lib <- sub("\\.html$", "_files", hp)
      if (dir.exists(lib) && !any(grepl(basename(lib), readLines(hp, warn = FALSE), fixed = TRUE))) unlink(lib, recursive = TRUE)
      TRUE }, error = function(e) {
      message("[dep_map] self-contained HTML failed (", conditionMessage(e), "); writing with a lib folder")
      tryCatch({ visNetwork::visSave(vn, hp, selfcontained = FALSE); TRUE }, error = function(e) FALSE) })
    if (!ok) message("[dep_map] HTML not written")
  } else message("[dep_map] visNetwork not installed -- HTML skipped")
  message("[dep_map] Outputs: ", out_dir, " (suffix ", dated, sfx, ")")
  invisible(P("risk_report", "md"))
}

# -----------------------------------------------------------------------------
# 9. Self-test on a fixture repo (runs before the real analysis)
# -----------------------------------------------------------------------------
self_test <- function() {
  td <- file.path(tempdir(), paste0("dep_map_fixture_", Sys.getpid()))
  unlink(td, recursive = TRUE); dir.create(file.path(td, "R", "utils"), recursive = TRUE)
  w <- function(p, ...) writeLines(c(...), file.path(td, p))
  w("R/00_config.R",
    'CONFIG <- list(data_dir = "/orange/x", output_dir = file.path(here::here(), "output"))',
    'u <- list.files(file.path("R", "utils"), pattern = "^utils_.*\\\\.R$", full.names = TRUE)',
    'for (f in u) source(f)')
  w("R/utils/utils_a.R", 'helper_a <- function(con) DBI::dbGetQuery(con, "SELECT * FROM DIAGNOSIS d JOIN DEMOGRAPHIC p ON d.PATID = p.PATID")',
    'wrap_q <- function(con, sql) DBI::dbGetQuery(con, sql)')
  w("R/utils/utils_b.R", 'helper_b = function(x) helper_a(x)', 'unused_b <- function() 1')
  w("R/02_payer.R", 'source("R/00_config.R")', 'p <- file.path(CONFIG$output_dir, "tables", "payer_summary.csv")', 'readr::write_csv(x, p)')
  w("R/10_make.R", 'source(here::here("R", "00_config.R"))', 'rd <- format(Sys.Date(), "%Y%m%d")',
    'out <- glue::glue("{CONFIG$output_dir}/thing_{rd}.rds")', 'x %>% saveRDS(out)',
    'DBI::dbExecute(con, "CREATE OR REPLACE TABLE stage1 AS SELECT * FROM ENCOUNTER")', 'saveRDS(x, "output/shared.rds")')
  w("R/20_use.R", 'source("R/00_config.R")', 'pin <- Sys.getenv("PIN_THING")',
    'if (nzchar(pin)) { p <- pin } else {', '  cands <- list.files(CONFIG$output_dir, pattern = "^thing_.*\\\\.rds$", full.names = TRUE)',
    '  p <- cands[which.max(file.mtime(cands))]', '}', 'x <- readRDS(p)',
    'pr <- list.files(CONFIG$output_dir, pattern = "^payer_summary.*\\\\.rds$", recursive = TRUE)',
    'y <- readRDS(pr[1])', 'z <- wrap_q(con, "SELECT * FROM stage1 s LEFT JOIN LAB_RESULT_CM l ON s.a = l.a")',
    'h <- helper_b(1)', 'cache <- { if (TRUE) file.path("output", "cache") else "x" }', 'saveRDS(z, file.path(cache, "blk.rds"))',
    'od <- NULL %||% "output"', 'cd <- if (interactive()) file.path(tempdir(), "c") else file.path("output", "c")',
    'saveRDS(z, file.path(cd, "alt.rds"))', 'writeLines("ok", file.path("output", "logs", "pass.txt"))',
    'saveRDS(z, file.path("output", "shared.rds"))', 'readRDS(file.path(od, "blk.rds"))', 'cat("x", file = "R/00_config.R", append = TRUE)', 'saveRDS(z, file.path("output", paste0("use_", format(Sys.Date(), "%Y%m%d"), ".rds")))')
  A <- analyze(td); D <- derive(A); ed <- A$edges
  has <- function(f, t, a) any(ed$from == f & ed$edge_type == t & grepl(a, ed$artifact, fixed = TRUE))
  checks <- c(
    utils_sourced  = all(c("R/utils/utils_a.R", "R/utils/utils_b.R") %in% ed$to[ed$edge_type == "sources" & ed$from == "R/00_config.R"]),
    src_here       = has("R/10_make.R", "sources", "R/00_config.R"),
    csv_write      = has("R/02_payer.R", "writes", "output/tables/payer_summary.csv"),
    glue_pipe      = has("R/10_make.R", "writes", "output/thing_{DATE}.rds"),
    db_write       = has("R/10_make.R", "db_write", "db:STAGE1"),
    db_read_util   = has("R/utils/utils_a.R", "db_read", "db:DEMOGRAPHIC"),
    db_wrapper     = has("R/20_use.R", "db_read", "db:LAB_RESULT_CM"),
    dag_thing      = any(D$dag$pred == "R/10_make.R" & D$dag$succ == "R/20_use.R" & grepl("thing", D$dag$via)),
    dag_stage1     = any(D$dag$pred == "R/10_make.R" & D$dag$succ == "R/20_use.R" & D$dag$via == "db:STAGE1"),
    r1_payer_rds   = any(grepl("payer_summary", D$r1$artifact) & grepl("payer_summary.csv", D$r1$near_miss)),
    r3_pinned      = any(D$r3$file == "R/20_use.R" & grepl("thing", D$r3$pattern) & D$r3$has_pin),
    r4_use         = any(D$r4$file == "R/20_use.R"),
    fn_def         = any(A$defs$fn == "helper_b" & A$defs$file == "R/utils/utils_b.R"),
    fn_edge        = any(D$fn_edges$file == "R/20_use.R" & D$fn_edges$fn == "helper_b"),
    r7b_unused     = "unused_b" %in% D$r7b$fn && !"helper_a" %in% D$r7b$fn,
    r7c_clean      = !any(c("helper_a", "helper_b", "wrap_q") %in% D$r7c$fn),
    brace_block    = has("R/20_use.R", "writes", "output/cache/blk.rds"),
    null_coalesce  = has("R/20_use.R", "reads", "output/blk.rds"),
    r10_config     = any(D$r10$file == "R/20_use.R"),
    no_token_match = !any(D$dag$via == "{build_path()}"),
    prefer_prod    = has("R/20_use.R", "writes", "output/c/alt.rds") && !any(grepl("{TMP}", ed$artifact, fixed = TRUE)),
    writelines     = has("R/20_use.R", "writes", "output/logs/pass.txt"),
    r11_multi      = any(D$r11$artifact == "output/shared.rds" & D$r11$n_writers == 2)
  )
  unlink(td, recursive = TRUE)
  if (!all(checks)) stop("[dep_map] SELF-TEST FAILED: ", paste(names(checks)[!checks], collapse = ", "))
  message(sprintf("[dep_map] self-test passed (%d checks)", length(checks)))
  invisible(TRUE)
}

# -----------------------------------------------------------------------------
# 10. Main
# -----------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args) && dir.exists(args[1])) args[1] else
  if (requireNamespace("here", quietly = TRUE)) here::here() else getwd()
if (!dir.exists(file.path(root, "R"))) stop("[dep_map] no R/ folder under ", root)

self_test()
t0 <- Sys.time()
message("[dep_map] analysing ", normalizePath(root, winslash = "/"))
A <- analyze(root)
D <- derive(A)
G <- gate_generic(A)
if (!nzchar(Sys.getenv("DEP_MAP_NO_GATE"))) G <- rbind(G, gate_project(A, D))
for (i in seq_len(nrow(G))) message(sprintf("  [%s] %s %s", if (G$pass[i]) "PASS" else if (G$blocking[i]) "FAIL" else "WARN", G$check[i],
                                            if (nzchar(G$detail[i])) paste0("(", G$detail[i], ")") else ""))
gate_ok <- all(G$pass | !G$blocking)
force <- nzchar(Sys.getenv("DEP_MAP_FORCE"))
ed <- A$edges
tab <- table(ed$edge_type, factor(ed$resolution, levels = c("full", "partial", "none")))
message("[dep_map] edges by type x resolution:"); print(tab)
if (!gate_ok && !force) {
  message("[dep_map] GATE FAILED -- no outputs written. Inspect with: dep_map_last$A$edges / dep_map_last$D. ",
          "Set DEP_MAP_FORCE=1 to write outputs anyway.")
} else {
  write_outputs(A, D, G, file.path(root, "output", "dep_map"), gate_ok)
}
assign("dep_map_last", list(A = A, D = D, G = G), envir = globalenv())
message(sprintf("[dep_map] done in %.1f s", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
})
