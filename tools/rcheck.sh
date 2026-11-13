#!/usr/bin/env bash
# tools/rcheck.sh — local R verification for insurance_investigation
# Works from Git Bash on Windows (what Claude Code uses) and on Linux.
#
# Usage (from anywhere inside the repo):
#   tools/rcheck.sh which              # show which Rscript is used and its version
#   tools/rcheck.sh parse [files...]   # parse-check R files; default = changed/untracked .R files,
#                                      #   or every file under R/ and tests/ if none changed
#   tools/rcheck.sh parse --all        # parse-check every .R file under R/ and tests/
#   tools/rcheck.sh test [filter]      # run tests/testthat (optional filter, e.g. 115 or utils-address)
#
# Override the R install with:  RSCRIPT="/c/Program Files/R/R-4.5.1/bin/Rscript.exe" tools/rcheck.sh ...
# Exit status is non-zero on any parse failure or test failure/error.

set -euo pipefail
shopt -s nullglob

REQUIRED_R="4.5"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

find_rscript() {
  # 1) explicit override
  if [[ -n "${RSCRIPT:-}" && -x "${RSCRIPT}" ]]; then
    echo "${RSCRIPT}"; return
  fi
  # 2) an R 4.5.x install in the usual Windows locations (preferred over PATH, which may be 4.6)
  local base cands
  for base in "/c/Program Files/R" "${HOME}/AppData/Local/Programs/R" "${LOCALAPPDATA:-/nonexistent}/Programs/R"; do
    [[ -d "${base}" ]] || continue
    cands=("${base}"/R-${REQUIRED_R}*)
    if (( ${#cands[@]} )); then
      local newest
      newest=$(printf '%s\n' "${cands[@]}" | sort -V | tail -n1)
      if [[ -x "${newest}/bin/Rscript.exe" ]]; then echo "${newest}/bin/Rscript.exe"; return; fi
    fi
  done
  # 3) any R 4.x install in the usual Windows locations (fallback; will warn on version mismatch)
  for base in "/c/Program Files/R" "${HOME}/AppData/Local/Programs/R" "${LOCALAPPDATA:-/nonexistent}/Programs/R"; do
    [[ -d "${base}" ]] || continue
    cands=("${base}"/R-4.*)
    if (( ${#cands[@]} )); then
      local newest
      newest=$(printf '%s\n' "${cands[@]}" | sort -V | tail -n1)
      if [[ -x "${newest}/bin/Rscript.exe" ]]; then echo "${newest}/bin/Rscript.exe"; return; fi
    fi
  done
  # 4) whatever is on PATH
  if command -v Rscript >/dev/null 2>&1; then command -v Rscript; return; fi
  echo "ERROR: Rscript not found. Install R ${REQUIRED_R}.x, add its bin/ to PATH, or set RSCRIPT=..." >&2
  exit 127
}

R_BIN=$(find_rscript)
# Single-line -e is safe on Windows Git Bash; multi-line -e causes segfault with Windows R binaries.
R_VER=$("${R_BIN}" --vanilla -e 'cat(paste(R.version$major, R.version$minor, sep = "."))' 2>/dev/null)

check_version() {
  if [[ "${R_VER}" != ${REQUIRED_R}* ]]; then
    echo "WARNING: using R ${R_VER} at ${R_BIN}; project renv is built for R ${REQUIRED_R} (HiPerGator: module load R/4.5)." >&2
  fi
}

# Write R code to a temp file; avoids the Windows Git Bash segfault on multi-line -e strings.
run_r_script() {
  local flags="$1"; shift
  local code="$1"; shift
  local tmp
  tmp=$(mktemp --suffix=.R)
  printf '%s\n' "${code}" > "${tmp}"
  "${R_BIN}" ${flags} "${tmp}" "$@"
  local rc=$?
  rm -f "${tmp}"
  return ${rc}
}

changed_r_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    { git diff --name-only HEAD -- 'R/*.R' 'R/**/*.R' 'tests/*.R' 'tests/**/*.R' 2>/dev/null
      git ls-files --others --exclude-standard -- 'R/*.R' 'R/**/*.R' 'tests/*.R' 'tests/**/*.R'
    } | sort -u | while read -r f; do [[ -f "$f" ]] && echo "$f"; done
  fi
}

all_r_files() {
  find R tests -type f \( -name '*.R' -o -name '*.r' \) 2>/dev/null | sort
}

PARSE_CODE='
f <- commandArgs(trailingOnly = TRUE)
bad <- 0L
for (x in f) {
  err <- tryCatch({ parse(x, keep.source = FALSE); NULL },
                  error = function(e) conditionMessage(e))
  if (is.null(err)) {
    cat("OK   ", x, "\n", sep = "")
  } else {
    cat("FAIL ", x, "\n    ", gsub("\n", "\n    ", err), "\n", sep = "")
    bad <- bad + 1L
  }
}
cat(sprintf("\n%d file(s) parsed, %d failed\n", length(f), bad))
quit(status = if (bad > 0L) 1L else 0L)
'

TEST_CODE='
a <- commandArgs(trailingOnly = TRUE)
flt <- if (length(a) && nzchar(a[1])) a[1] else NULL
res <- testthat::test_dir("tests/testthat", filter = flt,
                          reporter = "summary", stop_on_failure = FALSE)
df <- as.data.frame(res)
n_fail <- sum(df$failed) + sum(as.logical(df$error))
cat(sprintf("\nfiles: %d | expectations failed: %d | errors: %d | skipped: %d\n",
            length(unique(df$file)), sum(df$failed),
            sum(as.logical(df$error)), sum(as.logical(df$skipped))))
quit(status = if (n_fail > 0) 1L else 0L)
'

cmd="${1:-which}"; shift || true

case "${cmd}" in
  which)
    echo "Rscript: ${R_BIN}"
    echo "R version: ${R_VER}"
    check_version
    ;;

  parse)
    check_version
    files=()
    if [[ "${1:-}" == "--all" ]]; then
      mapfile -t files < <(all_r_files)
    elif (( $# )); then
      files=("$@")
    else
      mapfile -t files < <(changed_r_files)
      if (( ${#files[@]} == 0 )); then
        echo "No changed .R files; parsing everything under R/ and tests/."
        mapfile -t files < <(all_r_files)
      fi
    fi
    (( ${#files[@]} )) || { echo "Nothing to parse."; exit 0; }
    run_r_script "--vanilla" "${PARSE_CODE}" "${files[@]}"
    ;;

  test)
    check_version
    # No --vanilla: the project .Rprofile activates renv so tests use the project library
    run_r_script "" "${TEST_CODE}" "${1:-}"
    ;;

  *)
    echo "Usage: tools/rcheck.sh {which|parse [--all|files...]|test [filter]}" >&2
    exit 2
    ;;
esac
