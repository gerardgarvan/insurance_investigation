# Phase 134: Ingest Integrity and Honest Tests - Context

**Gathered:** 2026-07-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Harden the DuckDB ingest promotion gate (R/03) and fix 5 validators/tests that currently cannot fail: R/81, R/82/R/83, R/88, R/96, and R/98. No new validation capabilities — only correctness fixes so that passing means something.

</domain>

<decisions>
## Implementation Decisions

### R/03 — DuckDB Ingest Promotion Gate
- **D-01:** Add `stop()` on any table write failure before the atomic `.tmp`→canonical swap; the `.tmp` database must be discarded on failure.
- **D-02:** Assert `setequal(ingested_tables, TABLES_TO_INGEST)` before promotion — if any expected table is missing, abort.
- **D-03:** Replace the hardcoded `"{N}/{N} passed"` summary (line 372) with a real per-table pass/fail tally derived from actual write results.

### R/81 — Type Coercion Before waldo::compare()
- **D-04:** Remove (or bypass) the `coerce_types()` call on lines 127–128 so `waldo::compare()` receives raw DuckDB and RDS outputs. Real type divergence must be visible in the diff.

### R/82 / R/83 — Speedup Benchmark Scripts
- **D-05:** R/82 must benchmark all 5 diagnostic scripts: **R/20, R/21, R/22, R/23, R/24**. The current implementation only benchmarks R/14_build_cohort.R.
- **D-06:** R/83's "≥3× speedup on 3 of 5 scripts" milestone check must evaluate against the 5-script result set, not a single-script result.

### R/88 — Smoke Test Skip vs. Pass Counters
- **D-07:** Add a `skipped` counter alongside the existing `passed`/`failed` counters. Route all SKIP paths (missing scripts, IS_LOCAL guards, HiPerGator-only checks) through `skipped <<- skipped + 1L` instead of `check(..., FALSE)`.
- **D-08:** Final summary line format: `N passed / N failed / N skipped` — three-way breakdown so a run with many skips is visibly not fully verified.
- **D-09:** Invert the `cause_of_death` "drop" check (R/88 lines ~1207–1210): it currently passes when `cause_of_death` appears anywhere in R/52. Fix so it fails when the value is genuinely absent (i.e., the check should verify the drop statement exists, not just any mention of the column name).

### R/96 — FLM-Override Fixture
- **D-10:** The fixture in `96_validate_payer_dt.R` must start from a non-Medicaid payer state so the `flm_override` path is provably exercised. Change at least one fixture row's starting state to a non-Medicaid payer code before the override is applied.

### R/98 — Independent Baseline
- **D-11:** Commit a static fixture file (`treatment_episodes_pre98_baseline.rds`) to the repo as the independent baseline.
- **D-12:** Executor decision rule: if the file already exists at the expected path on HiPerGator (pre-Phase-98 capture), commit it. If not, generate it from the current pipeline output, commit it, and document clearly that the baseline is "current output at Phase 134 time" — future drift will be detectable going forward, and the circular self-comparison is eliminated.

### Claude's Discretion
- Exact mechanism for per-table pass/fail tracking in R/03 (accumulator list vs. tryCatch per-table vs. write result vector) — choose whichever integrates cleanly with the existing atomic write pattern.
- Whether `coerce_types()` in R/81 is removed entirely or simply bypassed in the comparison path — either is acceptable as long as raw types reach `waldo::compare()`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §INGEST-01 — exact ingest promotion gate spec
- `.planning/REQUIREMENTS.md` §PATTERN-E — all 5 validator correctness requirements in one place

### Roadmap Design Constraints
- `.planning/ROADMAP.md` §Phase 134 — per-script design constraints (authoritative)

### Historical Context
- `.planning/milestones/v1.4-REQUIREMENTS.md` §DBDIAG-01 — confirms R/20–R/24 as the "5 diagnostic scripts"
- `.planning/milestones/v1.4-ROADMAP.md` §Phase 32 — original diagnostic migration context

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/03_duckdb_ingest.R` line 60: `TMP_PATH` already defined; atomic swap pattern already present at lines 338–344. Error cleanup on line 324–328 already exists but only fires for round-trip failure — extend to cover all table write failures.
- `R/88_smoke_test_comprehensive.R` lines 48–58: `passed`/`failed` counters and `check()` function — add `skipped` alongside these.

### Established Patterns
- Atomic `.tmp` write pattern in R/03 is already implemented (lines 60, 86–95, 127, 316–344) — the fix extends it, not replaces it.
- R/82 already emits `duckdb_benchmark.csv`; R/83 reads that file — adding scripts to R/82 automatically flows into R/83's report without structural changes to R/83.

### Integration Points
- R/82 writes to `output/logs/duckdb_benchmark.csv` (line 150–151); R/83 reads from the same path (line 43). Adding 5 scripts to R/82's benchmark loop is the only structural change needed for the R/82→R/83 pipeline.
- R/88 summary is emitted via `message()` calls at the end of the script — add the `skipped` count to the final summary message there.

</code_context>

<specifics>
## Specific Ideas

- For R/98: executor should check `file.exists(BASELINE_RDS)` at the expected path first. If present (pre-Phase-98 capture exists on HiPerGator), commit it. If absent, generate from current output and document the caveat in a comment at the top of the validator.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 134-ingest-integrity-and-honest-tests*
*Context gathered: 2026-07-25*
