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

- **D-04:** Fix `R/03_duckdb_ingest.R` by targeted conversion of `<<-` to `<-` at the two
  confirmed top-level-expression sites — line 199 (`ingest_log`) and line 207
  (`tables_ingested`). Both variables are initialised with `<-` in the sourced script's
  new.env (lines 114 and 130) and superassigned from inside a `tryCatch` *expression*
  argument, which evaluates in new.env; `<<-` therefore begins its search at
  parent.env(new.env) = globalenv and skips the local binding.
- **D-04a:** PRESERVE `<<-` at line 181 (`df[[cc]] <<- iconv(...)`). That superassignment
  is inside an `error = function(e)` handler whose closure environment is new.env, so the
  search starts at new.env and correctly finds `df`. Converting it to `<-` would bind in
  the handler frame and silently rewrite the unsanitised frame on retry. Add a WHY comment
  at that line so the remaining `<<-` does not read as an oversight.
- **D-04b:** Do NOT adopt a full return-value / environment-reference restructure. That
  approach was selected under uncertainty about the enclosing scope of line 207; the scope
  is now confirmed (tryCatch expression, not a callback), so the restructure's robustness
  advantage no longer applies while its risk — breaking line 181, or half-converting the
  `index_results` group — remains.
- **D-04c:** Leave the `index_results` / `n_created` / `n_failed` superassignments (lines
  232, 249, 256, 271, 278, 286, 287) unchanged in this phase. They function correctly
  because those variables are never locally initialised, so reads and writes both resolve
  to globalenv consistently. They do pollute globalenv against D-05's intent — log as a
  separate low-priority cleanup. A partial conversion is worse than none: lines 249 and 271
  are in tryCatch expressions and would need `<-`, while 256 and 278 are in error handlers
  and would need to stay `<<-`.
- **D-05:** Do NOT change R/39's `source(script, local = new.env(parent = globalenv()))` pattern — that isolation is intentional and correct for other scripts.

**Root cause detail:** R/39 runs each script with
`source(script, local = new.env(parent = globalenv()))`. Line 207 sits in the expression
argument of the inner `tryCatch` at line 144, which is itself inside a `for` loop inside
the expression argument of the outer `tryCatch` at line 132. A `tryCatch` expression
argument is a promise evaluated in the caller's environment, and `for` creates no frame —
so line 207 evaluates directly in new.env. `<<-` begins its search at
parent.env(new.env) = globalenv, skipping the line-130 binding.

NOTE: the earlier characterisation of this as an "inside a callback" bug was incorrect and
inverts the fix. A `<<-` inside a callback *defined while sourcing* would have an
enclosing environment of new.env and would resolve correctly — which is precisely the case
at line 181, where the superassignment must be preserved.

### Root Cause 3: R/53 PATID column bug (D-06)

- **D-06:** Fix `R/53_death_date_validation.R` line 209: change `select(ID = PATID, BIRTH_DATE)` to `select(ID, BIRTH_DATE)`. This extract uses `ID` as the patient key (not `PATID`). The rename `ID = PATID` fails because `PATID` doesn't exist in the DuckDB DEMOGRAPHIC table.
- **D-07:** Verify no other `select(... = PATID, ...)` patterns exist in R/53 — fix any that do.

**Root cause detail:** PCORnet CDM uses `PATID` but this extract renamed to `ID` at load time (confirmed by comment in R/01_load_pcornet.R line 91). R/53 line 209 incorrectly tries to rename `PATID → ID`, but the column is already `ID`. This kills R/53, so no fresh `validated_death_dates.rds` is written.

The onward cascade to R/52 / R/101 / R/104 is NOT established. `validated_death_dates.rds`
exists on disk from a prior run and loads successfully after R/53's failure — see log2.txt
line 1348 (R/59) and line 1412 (R/51), both reporting 1344 patients. Whatever
"cannot open the connection" refers to in those three scripts, it is not that RDS.
See D-10.

Separate concern: the stale RDS reports 1344 patients while R/53's current logic was
heading toward 1299 (log lines 979-983). Downstream scripts have been consuming figures
that do not match present validation rules.

### R/88 Smoke Test Coverage (D-08)

- **D-08:** Add a new R/88 section (Section 15y or next available) with assertions verifying each fix:
  1. R/13 filter source does not contain `gsub.*DX` in a lazy context (static grep check)
  2. R/03 static checks: `tables_ingested` and `ingest_log` no longer use `<<-`, AND the
     line-181 `df[[cc]] <<-` is still present (guards against a future cleanup pass
     removing the one superassignment that must stay), AND the runtime guard from
     138-02 Step 4 is in place.
  3. R/53 DEMOGRAPHIC select does not reference `PATID` column (static grep check)
- **D-09:** Use the same grep-based assertion pattern as existing R/88 static checks (e.g., Section 15x from Phase 131).

### Fourth Root Cause: R/52 / R/101 / R/104 (D-10)

- **D-10:** R/52, R/101 and R/104 require independent diagnosis. Their shared failure
  ("cannot open the connection") is a bare `file()` error with no path in the message, and
  the assumed cause — a missing `validated_death_dates.rds` — is disproved by the log.
  Scope a fifth plan (138-05) to identify the actual missing artefact before claiming
  log2.txt is resolved.
- **D-11:** Execution order independently breaks the assumed chain. R/101 runs at log line
  2141 and R/104 at 2275 (Stage 2); R/52 runs at line 3742 (Stage 4). If R/101 and R/104
  consume an artefact produced by R/52, they cannot obtain it in the same run. Either the
  dependency is misidentified or R/52 must move ahead of Stage 2 in the R/39 SCRIPT_INDEX.
- **D-12:** Replace bare file reads in R/52, R/101 and R/104 with the existing
  `assert_*_exists()` convention already used in R/03 (line 147,
  `assert_rds_exists(rds_path, script_name = "R/03")`). The undiagnosable error message is
  the reason this went unattributed.

### R/03 database promotion risk (D-13)

- **D-13:** Fixing R/03 changes pipeline behaviour beyond result tracking. The verification
  failure currently triggers `Cleaning up .tmp file after error`, so the freshly built
  database is discarded and every script reads the previous `pcornet.duckdb`. Once R/03
  succeeds it will promote a new database mid-run at ~line 371. R/14, R/47, R/26, R/28,
  R/29, R/53 and R/42 all execute earlier in Stage 1 and will read the old database while
  Stages 2-6 read the new one. Move R/03 ahead of R/14 in the Stage 1 ordering. The same
  bug is also suppressing index creation (`Indexes: 0 created, 0 failed (of 0 total)`), so
  expect a runtime profile change as well.

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
- `R/88_smoke_test_comprehensive.R` — find last section number and existing static grep assertion pattern (e.g., Section 15x)
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
