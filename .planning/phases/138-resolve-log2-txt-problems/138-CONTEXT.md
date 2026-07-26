# Phase 138: resolve-log2-txt-problems - Context

**Gathered:** 2026-07-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix the 9 script failures recorded in `log2.txt` — a real HiPerGator run of R/39_run_all_investigations.R.
The phase delivers: 3 root-cause bug fixes + R/88 smoke-test coverage for each fix.
Cascading failures (R/70, R/71, R/72, R/52, R/101, R/104) resolve automatically once root causes are fixed.

</domain>

<decisions>
## Implementation Decisions

### Root Cause 1: DuckDB gsub error (D-01)

- **D-01:** Fix in `R/13_survivorship_encounters.R` only — R/70, R/71, R/72 are cascades from R/14 (which calls R/13); they need no direct changes.
- **D-02:** Fix approach: pre-compute a combined IN-list in R before the lazy filter. Replace the two-step `gsub("\\.", "", DX) %in% hl_icd10_clean` filter with `DX %in% unique(c(ICD_CODES$hl_icd10, hl_icd10_clean))`. Matches R/14's existing pattern at lines 140-141.
- **D-03:** Do NOT use `collect()` before the filter (DIAGNOSIS has 5M rows; collect is too expensive). Do NOT use DuckDB `regexp_replace` (adds SQL complexity with no benefit over the combined IN-list approach).

**Root cause detail:** `R/13_survivorship_encounters.R` lines 125-127 use `gsub("\\.", "", DX) %in% hl_icd10_clean` inside a `filter()` on a lazy DuckDB table. dplyr translates this to `gsub('.', '', DX) IN (...)` SQL — but DuckDB has no `gsub` function. The fix pre-computes both dotted and undotted into one combined vector in R and uses a single `DX %in% combined_vec`.

### Root Cause 2: R/03 scoping bug (D-04)

- **D-04:** Fix `tables_ingested` tracking in `R/03_duckdb_ingest.R` using a local reference pattern — restructure so the ingest loop accumulates results inside the tryCatch expression block (not via `<<-` inside inner function callbacks). Use a return-value pattern or an environment reference object rather than `<<-`.
- **D-05:** Do NOT change R/39's `source(script, local = new.env(parent = globalenv()))` pattern — that isolation is intentional and correct for other scripts.

**Root cause detail:** R/39 runs each script with `source(script, local = new.env(parent = globalenv()))`. Inside R/03, `tables_ingested <<- c(tables_ingested, tbl_name)` is called inside a `tryCatch(error = function(e) {...})` callback. The `<<-` walks up from the callback's env → skips the local new.env() → updates globalenv(). The local `tables_ingested <- character(0)` in the new.env() is never updated. Result: verification runs on an empty `tables_ingested` even though all 16 tables were written. Log evidence: "All 0 ingested tables passed round-trip verification" despite all 16 writing successfully.

### Root Cause 3: R/53 PATID column bug (D-06)

- **D-06:** Fix `R/53_death_date_validation.R` line 209: change `select(ID = PATID, BIRTH_DATE)` to `select(ID, BIRTH_DATE)`. This extract uses `ID` as the patient key (not `PATID`). The rename `ID = PATID` fails because `PATID` doesn't exist in the DuckDB DEMOGRAPHIC table.
- **D-07:** Verify no other `select(... = PATID, ...)` patterns exist in R/53 — fix any that do.

**Root cause detail:** PCORnet CDM uses `PATID` but this extract renamed to `ID` at load time (confirmed by comment in R/01_load_pcornet.R line 91). R/53 line 209 incorrectly tries to rename `PATID → ID`, but the column is already `ID`. This kills R/53 → no `validated_death_dates.rds` → R/52 fails (reads that RDS) → no `gantt_episodes.csv` → R/101 and R/104 fail.

### R/88 Smoke Test Coverage (D-08)

- **D-08:** Add a new R/88 section (Section 15y or next available) with assertions verifying each fix:
  1. R/13 filter source does not contain `gsub.*DX` in a lazy context (static grep check)
  2. R/03 `tables_ingested` length equals `TABLES_TO_INGEST` length after ingest (structural check)
  3. R/53 DEMOGRAPHIC select does not reference `PATID` column (static grep check)
- **D-09:** Use the same grep-based assertion pattern as existing R/88 static checks (e.g., Section 15x from Phase 131).

### Claude's Discretion

- Exact R/88 section number (15y vs next available) — use whatever is next in sequence.
- Whether to add a brief regression comment in R/13 explaining why `gsub()` can't be used on lazy DuckDB columns (caller-facing WHY comment is appropriate here per project conventions).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

No external specs — requirements fully captured in decisions above.

### Key source files (must read before writing fixes)
- `R/13_survivorship_encounters.R` lines 115-135 — Level 2 survivorship filter (gsub bug location)
- `R/14_build_cohort.R` lines 138-148 — correct pre-computed IN-list pattern to replicate in R/13
- `R/03_duckdb_ingest.R` lines 128-215 — ingest loop with `<<-` scoping bug
- `R/53_death_date_validation.R` lines 205-215 — PATID column bug location
- `R/39_run_all_investigations.R` lines 90-100 — `run_script()` function using `new.env(parent = globalenv())`
- `R/88_smoke_check.R` — find last section number and existing static grep assertion pattern (e.g., Section 15x)
- `log2.txt` — the actual failure log; useful for verifying the error messages the fixes must eliminate

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/14_build_cohort.R` lines 140-141: `unique(c(ICD_CODES$hl_icd10, gsub("\\.", "", ICD_CODES$hl_icd10)))` — the exact pattern R/13 should replicate for its Level 2 filter fix.
- R/88 Section 15x (Phase 131): static grep assertion pattern — replicate for Section 15y.

### Established Patterns
- Combined IN-list for ICD code matching on DuckDB lazy tables: pre-compute dotted+undotted in R, use single `DX %in% combined_vec`. Never apply R string functions (gsub, sub, toupper) to DuckDB columns inside a filter() on a lazy table.
- Column naming: this extract uses `ID` for patient ID throughout (not `PATID`). DuckDB tables match this — `select(ID = PATID, ...)` will always fail.

### Integration Points
- Fix in R/13 unblocks R/14 → unblocks R/70, R/71, R/72 (cascade resolution).
- Fix in R/53 unblocks `validated_death_dates.rds` → unblocks R/52 → unblocks `gantt_episodes.csv` → unblocks R/101 and R/104.
- Fix in R/03 is self-contained (ingest result tracking doesn't cascade to other scripts in this log).

</code_context>

<specifics>
## Specific Ideas

- The 9 failures in log2.txt trace to exactly 3 bugs. No additional script changes are needed beyond R/13, R/03, R/53, and R/88.
- Log2.txt is the authoritative artifact: each fix should eliminate a specific error message visible in that log.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 138-resolve-log2-txt-problems*
*Context gathered: 2026-07-26*
