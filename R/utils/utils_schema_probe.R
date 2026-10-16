# ==============================================================================
# R/utils/utils_schema_probe.R -- Schema probe for pipeline inputs
# ==============================================================================
# Writes a small Markdown file of column names, types, row counts and safe
# summaries for RDS / CSV / XLSX inputs and DuckDB tables, so code can be written
# against real names instead of guesses.
#
# Privacy: no patient-level values are written. Identifier-like columns (ID, ZIP,
# address, birth date, name, phone, email) show type and NA count only.
# Category tables are shown only for columns with <= max_levels distinct values,
# with counts 1-10 shown as "<11". Do not probe output/internal/ workbooks.
#
# Usage (interactive R on HiPerGator, repo root, after source("R/00_config.R")):
#   probe_inputs("184",
#     files  = c("output/internal/cbc_patient_year_20261015.rds",
#                "output/cbc_patient_year_20261015.xlsx"),
#     tables = c("DEMOGRAPHIC"))
# Output: .planning/schemas/<name>_schema_<YYYYMMDD>.md (also printed)
# ==============================================================================

.probe_sensitive_pat <- "(^|_)(ID|PATID|ENCOUNTERID|MRN)$|ZIP|ADDRESS|BIRTH|NAME|PHONE|EMAIL"

.probe_sup <- function(n) ifelse(n >= 1 & n <= 10, "<11", format(n, big.mark = ",", trim = TRUE))

probe_df <- function(df, label, max_levels = 30L) {
  out <- c(sprintf("## %s", label),
           sprintf("rows: %s | columns: %d", format(nrow(df), big.mark = ","), ncol(df)))
  if ("ID" %in% names(df))
    out <- c(out, sprintf("distinct ID: %s", format(dplyr::n_distinct(df$ID), big.mark = ",")))
  for (nm in names(df)) {
    x    <- df[[nm]]
    cls  <- paste(class(x), collapse = "/")
    line <- sprintf("- `%s` <%s> NA=%s", nm, cls, .probe_sup(sum(is.na(x))))
    sens <- grepl(.probe_sensitive_pat, nm, ignore.case = TRUE)
    if (sens) {
      line <- paste0(line, " (identifier/sensitive: values not shown)")
    } else if (inherits(x, c("Date", "POSIXt"))) {
      r <- suppressWarnings(range(x, na.rm = TRUE))
      line <- paste0(line, sprintf(" range=[%s, %s]", format(r[1]), format(r[2])))
    } else if (is.numeric(x)) {
      q <- suppressWarnings(stats::quantile(x, c(0, 0.5, 1), na.rm = TRUE, names = FALSE))
      line <- paste0(line, sprintf(" min/median/max=%s", paste(signif(q, 4), collapse = "/")))
    } else if (is.character(x) || is.factor(x) || is.logical(x)) {
      k <- dplyr::n_distinct(x, na.rm = TRUE)
      if (k <= max_levels) {
        tb <- sort(table(x, useNA = "no"), decreasing = TRUE)
        line <- paste0(line, sprintf(" levels(%d): %s", k,
                        paste(sprintf("%s=%s", names(tb), .probe_sup(as.integer(tb))), collapse = "; ")))
      } else {
        line <- paste0(line, sprintf(" distinct=%s (not listed)", format(k, big.mark = ",")))
      }
    }
    out <- c(out, line)
  }
  c(out, "")
}

probe_inputs <- function(name, files = character(), tables = character(),
                         out_dir = ".planning/schemas", max_levels = 30L) {
  out_dir <- here::here(out_dir)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out <- c(sprintf("# Schema probe: %s (%s)", name, format(Sys.time(), "%Y-%m-%d %H:%M")),
           "Names, types and counts only. Counts 1-10 shown as <11. No patient-level values.", "")

  for (f in files) {
    if (grepl("output/internal/.*\\.xlsx$", f)) {
      out <- c(out, sprintf("## %s\nSKIPPED (internal workbook)", f), ""); next
    }
    if (!file.exists(f)) { out <- c(out, sprintf("## %s\nNOT FOUND", f), ""); next }
    ext <- tolower(tools::file_ext(f))
    if (ext == "rds") {
      obj <- readRDS(f)
      if (is.data.frame(obj)) {
        out <- c(out, probe_df(obj, f, max_levels))
      } else {
        out <- c(out, sprintf("## %s", f),
                 sprintf("object class: %s", paste(class(obj), collapse = "/")),
                 sprintf("names: %s", paste(names(obj), collapse = ", ")), "")
        for (el in names(obj)) if (is.data.frame(obj[[el]]))
          out <- c(out, probe_df(obj[[el]], sprintf("%s $ %s", f, el), max_levels))
      }
    } else if (ext %in% c("csv", "txt", "tsv")) {
      sep <- if (ext == "tsv") "\t" else ","
      # all columns read as text (no type guessing; IDs/codes keep leading zeros)
      out <- c(out, probe_df(utils::read.csv(f, sep = sep, check.names = FALSE,
                                             colClasses = "character"), f, max_levels))
    } else if (ext == "xlsx") {
      sh <- openxlsx::getSheetNames(f)
      out <- c(out, sprintf("## %s", f), sprintf("sheets (in order): %s", paste(sh, collapse = " | ")))
      for (s in sh) {
        d <- openxlsx::read.xlsx(f, sheet = s)
        out <- c(out, sprintf("### sheet `%s`: %d rows; columns: %s", s, nrow(d),
                              paste(sprintf("`%s`", names(d)), collapse = " | ")))
        if (nrow(d) > 0 && nrow(d) <= 80)
          out <- c(out, paste0("  first-column labels: ",
                               paste(sprintf("`%s`", unique(as.character(d[[1]]))), collapse = " | ")))
      }
      out <- c(out, "")
    } else {
      out <- c(out, sprintf("## %s\nUNSUPPORTED extension: %s", f, ext), "")
    }
  }

  if (length(tables)) {
    con <- open_pcornet_con()
    on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
    for (t in tables) {
      ds <- DBI::dbGetQuery(con, sprintf("DESCRIBE %s", t))
      n  <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", t))$n
      out <- c(out, sprintf("## DuckDB table `%s`: %s rows", t, format(n, big.mark = ",")),
               sprintf("- `%s` <%s>", ds$column_name, ds$column_type), "")
    }
  }

  path <- file.path(out_dir, sprintf("%s_schema_%s.md", name, format(Sys.Date(), "%Y%m%d")))
  writeLines(out, path)
  cat(out, sep = "\n")
  message("Schema probe written: ", path)
  invisible(path)
}
