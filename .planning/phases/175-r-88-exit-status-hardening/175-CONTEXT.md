# Phase 175: R/88 Exit-Status Hardening - Context

**Gathered:** 2026-10-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Make R/88 a reliable CI gate by:
1. Replacing the single `quit(status=1)` guard with a three-way exit strategy that never kills an interactive session
2. Converting `check("…", TRUE)` skip-as-pass calls to a dedicated `skip_check()` function so skips are reported separately and don't inflate PASS count
3. Adding an `R88_FORCE_FAIL` env-var switch and a test procedure that verifies both the interactive (`stop()`) and non-interactive (`quit(status=1)`) failure paths from HiPerGator without SLURM

Phase boundary: only `R/88_smoke_test_comprehensive.R` and the SUMMARY are modified. No pipeline scripts, no new SMOKE sections.

</domain>

<decisions>
## Implementation Decisions

### D-01: Exit-status guard — three-way strategy

Replace the current single guard at the bottom of R/88:
```r
if (failed > 0 && !identical(Sys.getenv("TESTTHAT"), "true")) {
  quit(status = 1)
}
```

With a three-way strategy:

```r
if (failed > 0) {
  if (identical(Sys.getenv("TESTTHAT"), "true")) {
    # testthat: silent — test harness sees individual FAIL lines
  } else if (interactive()) {
    stop(paste0("R/88: ", failed, " check(s) FAILED"))
  } else {
    quit(status = 1)
  }
} else {
  if (!interactive() && !identical(Sys.getenv("TESTTHAT"), "true")) {
    quit(status = 0)
  }
}
```

**Rationale:**
- Interactive R (HiPerGator `source()` pattern): `stop()` — session stays alive, error is loud
- testthat: current no-op behaviour — harness reads FAIL lines directly
- Non-interactive (Rscript): `quit(status=1)` on failure, `quit(status=0)` on success

### D-02: Skip-as-pass — add `skip_check()`, audit all `check("…", TRUE)` instances

Add at the top of R/88 (near the `check()` definition):
```r
skipped <- 0L

skip_check <- function(label, reason = "") {
  msg <- if (nzchar(reason)) glue("  SKIP: {label} ({reason})") else glue("  SKIP: {label}")
  message(msg)
  skipped <<- skipped + 1L
}
```

Footer change — Section 16 summary:
```r
total <- passed + failed   # skipped NOT in total
if (failed == 0) {
  message(glue("ALL {total} CHECKS PASSED  ({skipped} skipped)"))
} else {
  message(glue("FAILED: {failed}/{total} checks failed  ({skipped} skipped)"))
}
```

**Contract stays:** `PASS == total, FAIL == 0` means success. Skips are informational only.

**Grep audit required:** Find every `check("…", TRUE)` in R/88 and classify:
- If it is a runtime check skipped because output files are absent or environment is wrong → convert to `skip_check(label, reason)`
- If it is a genuine structural assertion that is always true → leave as `check()`
- Document the judgment for each in the SUMMARY

**Baseline shift:** The PASS total will drop by roughly the number of skip conversions (estimated ~12 from the grep). The SUMMARY must record the new baseline number after HiPerGator confirmation. Downstream phases cite "PASS == total, FAIL == 0" not a fixed number.

### D-03: Failure-path test — `R88_FORCE_FAIL` env-var switch

Add one check in R/88 near the top (after global counter initialisation, before Section 2):
```r
if (identical(Sys.getenv("R88_FORCE_FAIL"), "1")) {
  check("R88_FORCE_FAIL sentinel (always fails when env var set)", FALSE)
}
```

This check never fires in normal runs. It requires no cleanup.

**Test procedure (both paths, from interactive R on HiPerGator — no SLURM):**

```r
# Non-interactive path — expect exit code 1
ec1 <- system2("Rscript", "R/88_smoke_test_comprehensive.R",
               env = c(Sys.getenv(), R88_FORCE_FAIL = "1"))
stopifnot(ec1 == 1L)   # must be 1

# Non-interactive clean path — expect exit code 0
ec0 <- system2("Rscript", "R/88_smoke_test_comprehensive.R")
stopifnot(ec0 == 0L)   # must be 0

# Interactive path — expect stop(), session must stay alive
Sys.setenv(R88_FORCE_FAIL = "1")
try(source("R/88_smoke_test_comprehensive.R", local = new.env(parent = globalenv())))
Sys.unsetenv("R88_FORCE_FAIL")
# Confirm session is still alive (no quit() was called)
message("Session alive — interactive stop() path confirmed")
```

Run on a compute node from an Open OnDemand RStudio session (not a login node) to avoid load on login nodes.

### Claude's Discretion

- Exact placement of the `skip_check()` definition (adjacent to `check()` at the top)
- Whether `skip_check()` signature matches the existing `p163_skip_note()` pattern or is unified with it
- Order of the three test procedure steps in the SUMMARY

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### R/88 smoke test
- `R/88_smoke_test_comprehensive.R` — the only file being modified; locate all targets by content, never by line number

### Requirements
- `.planning/REQUIREMENTS.md` §HYGIENE-02 — authoritative spec for this phase

### Prior phase context
- `.planning/phases/174-smoke-check-discrepancy/174-01-SUMMARY.md` — Phase 174 counter fixes and the 963-check baseline; the skip-audit will change this total
- `.planning/phases/174-smoke-check-discrepancy/174-01-PLAN.md` — interfaces block for locating R/88 targets by content pattern

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `check(description, condition)` (lines ~56-64): canonical pass/fail function; `skip_check()` should sit beside it and share the `message()` style
- `p163_skip_note(label, why)` / `p163_skip` counter (Section 15as): existing precedent for a skip function — `skip_check()` generalises this pattern to the whole script

### Established Patterns
- Global counters (`passed`, `failed`) use `<<-` assignment inside local checker functions — `skipped` should follow the same pattern
- Section 16 footer uses `glue()` for message formatting — keep consistent

### Integration Points
- The three-way guard replaces only the final `if (failed > 0 ...)` block at the very end of R/88 — nothing else moves
- The `R88_FORCE_FAIL` check must be placed after `passed <- 0L` / `failed <- 0L` initialisation and before Section 2 structural checks, so counters are live when it fires

</code_context>

<specifics>
## Specific Ideas

- The `system2()` return value is the exit code on all platforms — no need to parse output
- Use `local = new.env(parent = globalenv())` in `source()` to avoid polluting the global env during the interactive test
- The `stop()` message should include the count: `"R/88: N check(s) FAILED"` so it matches the footer wording

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 175-r-88-exit-status-hardening*
*Context gathered: 2026-10-12*
