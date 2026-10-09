# Phase 170: R/147 Re-run and Verification — Context

**Gathered:** 2026-10-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Re-run R/147 (surveillance modality frequency) on HiPerGator after Phase 163 changes,
upgrade verify_vs_1006.R to a self-contained PASS/FAIL harness, confirm R/88 Section 15as
(Phase 163 structural checks — new section), and produce a dated verify log that gates
Phases 171 and 172.

No new analysis. No changes to R/147's logic (Phase 163 changes are already committed).
This phase is about running, verifying, and documenting.

</domain>

<decisions>
## Implementation Decisions

### D-01: Run procedure
Reuse Phase 169's sbatch dependency-chain pattern. The Phase 170 HiPerGator task must
spell out exact commands:

```bash
git pull                    # on HiPerGator clone
export VERIFY_RUN_DATE=$(date +%Y%m%d)   # captured once; drives the verify log filename
JOB147=$(sbatch --parsable slurm/147_surveillance.sbatch)
JOB_VER=$(sbatch --parsable --dependency=afterok:$JOB147 slurm/147_verify.sbatch)
JOB88=$(sbatch  --parsable --dependency=afterany:$JOB_VER slurm/88_smoke_test.sbatch)
```

- `afterok` on JOB147 → verify only runs if R/147 exits 0
- `afterany` on JOB_VER → R/88 runs regardless of verify exit status, so a single run
  shows both verify failures and smoke-test results without needing a second sbatch
- THREE jobs total: JOB147, JOB_VER, JOB88.

### D-02: Input path discipline — no "latest" globs; INTERNAL-to-INTERNAL
The verify script must use pinned paths, not glob-for-most-recent patterns, and must compare
the INTERNAL workbook to the INTERNAL reference (NOT the release copy):

- **Reference (1006) inputs — INTERNAL copies:**
  - Workbook: `CONFIG$cache$outputs_dir` + `surveillance_modality_frequency_INTERNAL_20261006.xlsx`
    (the INTERNAL reference — the release copy has 384 suppressed cells and no E sheet, so it
    cannot be used for a value comparison)
  - RDS: `CONFIG$cache$outputs_dir` + `surveillance_patient_modality_dates_20261006.rds`
    (NOTE: `CONFIG$cache$rds_dir` does NOT exist — use `CONFIG$cache$outputs_dir`)
  - Confirm the 1006 INTERNAL files are NOT overwritten by the rerun (R/147 writes dated
    filenames; the 1006 files are safe)

- **New-run inputs:**
  - Workbook: `surveillance_modality_frequency_INTERNAL_<run_date>.xlsx`
    where `<run_date>` is derived from `Sys.Date()` at verify-launch time (not a glob)
  - RDS: `surveillance_patient_modality_dates_<run_date>.rds`
  - If either file does not exist for today's date, the script records a `[FAIL]` input entry
    (NOT a stop()) so the log still ends with OVERALL. This prevents verify from comparing
    1006 vs itself on a failed job while still always writing OVERALL.

### D-03: verify_vs_1006.R — complete check list

**Existing checks (keep, already correct):**
- C_modality_with_sensitivity: `primary_*` columns identical ← already present
- C_modality_with_sensitivity: `sensitivity_n_patients == 0` for Echo, ECG, Mammogram, PFT ← already present
- C_modality_with_sensitivity: `any_n_patients == primary_n_patients` for those four ← already present
- QC: "Codeset rows excluded (DIAGNOSIS)" row present ← already present
- QC: "DIAGNOSIS rows collected" row absent ← already present
- KEY: "163 D-01" note present ← already present
- Codeset_summary: 14 modality blocks ← already present
- Codeset_summary: no Z-codes ← already present

**Checks to add:**
1. **Denominator / cohort N / person-years unchanged** — read by EXACT string label (not
   regex). From KEY sheet: "Denominator N" (expect 9,331) and "Confirmed-cohort N"
   (expect 9,282). From QC sheet: "Total person-years" (expect 40,298.9). NOTE: the KEY
   "Person-years" row is definition TEXT, not a number — person-years lives in QC
   "Total person-years".

2. **B identical for all 14 modalities** — the existing identical-sheet check covers B but
   add a named assertion so failures cite the modality, not just the column.

3. **C primary_* identical for all 14 modalities** — the existing C check already covers all
   rows; rename its result key to "C:primary_all_14".

4. **C any_* == primary_* for Echo, ECG, Mammogram, PFT** — already present (keep).

5. **D identical for all 14 modalities** — D_pre_vs_post_anchor is LONG format: one row per
   (modality × tier_scope) with tier_scope in {"primary","any"}; there are NO any_*/primary_*
   columns. Filter by modality and tier_scope and compare row-by-row. For the 4 CHANGED_MODS:
   assert the `any` row == the `primary` row in the new sheet, AND the `primary` row is
   byte-identical to the reference. For the other 10: both `primary` and `any` rows identical
   to the reference.

6. **A2_analyte_presence identical** — already in `identical_sheets`; keep with explicit name.

7. **A3 identical** — A3 is NOT in `identical_sheets`; add `"A3_missing_analyte"`.

8. **(removed)** — There is NO separate "lab rule table" artifact. Lab analyte rules live in
   A2_analyte_presence and Codeset_summary (both already checked). Do NOT add a lab-rule
   check — not even a permanent SKIP (a permanent SKIP would break the N PASS / M FAIL
   arithmetic). The check simply does not exist.

9. **QC matched-rows drop** — compute expected value rather than hard-coding 6,744, and
   compare the drop in "Matched rows, type ok" (NOT the "excluded (DIAGNOSIS)" row, which
   under Phase 163 equals the number of codeset rows = 4, not the record drop):
   ```r
   z_codes <- c("SC039", "SC047", "SC065", "SC090")
   expected_drop <- sum(as.integer(ref_a[ref_a$codeset_row_id %in% z_codes, "n_records"]), na.rm = TRUE)
   matched_ref <- as.integer(ref_qc[grepl("Matched rows, type ok", ref_qc[[1]], fixed=TRUE), 2])
   matched_new <- as.integer(new_qc[grepl("Matched rows, type ok", new_qc[[1]], fixed=TRUE), 2])
   actual_drop <- matched_ref - matched_new
   stopifnot(actual_drop == expected_drop)   # (as a PASS/FAIL result, not a hard stop)
   ```
   If the check fails, note "verify grain vs n_records grain before treating as regression."

10. **"diagnosis" text residue check** — scan A_code_presence, B, C, D, Codeset_summary,
    KEY, and QC for any cell containing "DIAGNOSIS"/"diagnosis" (case-insensitive). The
    allow-listed occurrences (HL denominator row, anchor/follow-up anchor row, excluded QC
    row, "163 D-01" note) live in KEY and QC, so those sheets MUST be in the scan set.
    Any other occurrence is a FAIL.

11. **E sheet vs 1006 RDS** — the E sheet is INTERNAL-only (absent from the release copy by
    design, NOT a timing/"pre-dates" issue), so an xlsx-vs-xlsx E check against the release
    copy would never fire. Compare INTERNAL-to-INTERNAL at the RDS level instead, tolerantly:
    ```r
    ref_rds <- readRDS(file.path(CONFIG$cache$outputs_dir,
                       "surveillance_patient_modality_dates_20261006.rds"))
    new_rds <- readRDS(file.path(CONFIG$cache$outputs_dir,
                       glue("surveillance_patient_modality_dates_{run_date}.rds")))
    # Arrange by ID, strip attributes, drop _any columns (primary dates must match):
    ref_primary <- as.data.frame(ref_rds)[order(ref_rds$ID), !grepl("_any$", names(ref_rds))]
    new_primary <- as.data.frame(new_rds)[order(new_rds$ID), !grepl("_any$", names(new_rds))]
    all.equal(ref_primary, new_primary, check.attributes = FALSE)  # → PASS or FAIL
    # Also: for the 4 CHANGED_MODS, <modality>_any == <modality>_primary in the new RDS.
    ```
    Remove E_patient_modality_dates from `identical_sheets`. Use `all.equal()` (not
    `identical()`) so row order / tibble-vs-data.frame / attribute differences don't cause
    spurious failures. Use `CONFIG$cache$outputs_dir` (NOT the nonexistent `rds_dir`).

### D-04: verify_vs_1006.R — output format
- Every check emits exactly one line: `[PASS] <name>: <detail>` or `[FAIL] <name>: <detail>`
- Final two lines of output (and of the log file):
  ```
  N PASS, M FAIL out of K checks
  OVERALL: PASS
  ```
  or
  ```
  N PASS, M FAIL out of K checks
  OVERALL: FAIL (M checks)
  ```
- Script calls `quit(status = ifelse(n_fail == 0, 0, 1))` as its last statement.
- The OVERALL line is ALWAYS written: the sink opens FIRST (before any check or file test),
  missing-file cases record `[FAIL]` entries instead of calling `stop()`, and every check is
  wrapped in `tryCatch(error = ...)` so a thrown error becomes a FAIL result rather than
  aborting before OVERALL. (on.exit does NOT fire at Rscript top level, so the final block
  closes the sink explicitly.)
- No manual interpretation required; downstream gates grep for `OVERALL: PASS`.

### D-05: Verify log file
The verify script writes its full output to:
```
output/logs/147_verify_vs_1006_<run_date>.txt
```
The file must end with the `OVERALL:` line. This is the artifact that gates Phases 171 and 172.

Implementation: open `sink()` around the entire check block BEFORE any check or stop(). The
log file path is printed to stdout so the SLURM job log captures it. The verify sbatch
captures the Rscript exit code (`rc=$?`) and propagates it (`exit $rc`) so a verify failure
shows as FAILED in SLURM, not COMPLETED.

### D-06: Downstream gate (Phases 171 and 172) — DATE-ANCHORED
Both Phase 171 (survivorship workbook refresh) and Phase 172 (Phase 164 close-out) open
with a DATE-ANCHORED pre-flight gate. It must key on the specific run_date that produced the
RDS being consumed — NOT a latest-file glob — because if R/147 fails, the afterok dependency
blocks the verify job so no new log is written, and a latest-glob gate would then pass on the
previous run's stale OVERALL: PASS log.
```r
run_date <- Sys.getenv("VERIFY_RUN_DATE", unset = format(Sys.Date(), "%Y%m%d"))
verify_log <- file.path("output", "logs", sprintf("147_verify_vs_1006_%s.txt", run_date))
if (!file.exists(verify_log))
  stop("No verify log for run_date ", run_date, ". Re-run Phase 170.")
if (!any(grepl("^OVERALL: PASS$", readLines(verify_log))))
  stop("Phase 170 verify did not pass for run_date ", run_date, ".")
# Then consume surveillance_patient_modality_dates_<run_date>.rds explicitly (no glob).
```
VERIFY_RUN_DATE is set once when the Phase 170 job chain is submitted and carried into the
downstream job so the gate and the RDS read use the identical date. The full copy-paste
snippet lives in 170-DOWNSTREAM-GATE.md.

### D-07: R/88 Section 15as — Phase 163 structural checks
Add Section 15as immediately after Section 15ar. Label: `PHASE 163 — DIAGNOSIS EXCLUSION`.
Smoke counter: `SMOKE-163-01`.

Four checks:
1. `EXCLUDED_CDM_TABLES` is defined in R/147 source (grep `EXCLUDED_CDM_TABLES\s*<-`)
2. R/147 contains a `stopifnot()` that ALSO references `EXCLUDED_CDM_TABLES` (the actual
   present contract is the line-297 `stopifnot(!any(codeset$cdm_table %in% EXCLUDED_CDM_TABLES))`;
   check: `any(grepl("stopifnot", src) & grepl("EXCLUDED_CDM_TABLES", src))`. Do NOT look for
   the abstract string `nrow(codeset_excluded) + nrow(codeset) == nrow(codeset_full)` — that
   is not what line 297 asserts.)
3. *(Output check — skipped ONLY in local runs with no INTERNAL workbook; on HiPerGator it
   runs)* Latest INTERNAL workbook's A_code_presence sheet has zero cells equal to "DIAGNOSIS"
4. *(Output check — skipped ONLY in local runs with no INTERNAL workbook; on HiPerGator it
   runs)* Latest INTERNAL workbook's Codeset_summary has no Z-code anywhere in a cell; pattern
   `(^|[;,[:space:]])Z[0-9]` (NOT just `^Z`, which misses `93306; Z13.6`)

On the HiPerGator run (Plan 03), Section 15as must report 4 PASS / 0 FAIL / 0 SKIP.
Section 15ao (Phase 166) and 15ar (Phase 165) are unchanged.

### D-08: SUMMARY.md content
The SUMMARY for Phase 170 records:
- Run date (ISO, e.g. 2026-10-09)
- New workbook filename (e.g. `surveillance_modality_frequency_INTERNAL_20261009.xlsx`)
- New RDS filename (e.g. `surveillance_patient_modality_dates_20261009.rds`)
- Verify log path (e.g. `output/logs/147_verify_vs_1006_20261009.txt`)
- THREE SLURM job IDs for JOB147, JOB_VER, JOB88
- R/88 Section 15as result (4 PASS / 0 FAIL / 0 SKIP)
- OVERALL verify result

### Claude's Discretion
- Exact column names in KEY/QC sheets for denominator / cohort / person-years rows (match by
  exact label: "Denominator N", "Confirmed-cohort N" in KEY; "Total person-years" in QC)
- Whether to use `sink()` or sbatch `tee` for the log file — sink() opened first is preferred
  so the OVERALL line is always captured
- Whether D-04's "diagnosis" text residue check is a separate pass or integrated into the
  per-sheet checks

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 163 — the change being verified
- `.planning/phases/163-files-1-unzip-this/163-01-PLAN.md` — DIAGNOSIS exclusion decision (D-01); codeset split logic
- `R/147_surveillance_modality_frequency.R` lines ~55-70 and line 297 — `EXCLUDED_CDM_TABLES` constant, codeset split, and the stopifnot guard

### verify_vs_1006 script (to be upgraded, not replaced)
- `R/147_verify_vs_1006.R` — current implementation; all additions go here

### R/88 smoke test (section 15as to be added)
- `R/88_smoke_test_comprehensive.R` lines ~6381-6620 — Section 15ar (last section); insert 15as after

### Phase 169 run procedure (reuse)
- `.planning/phases/169-registration-smoke-test-and-hipergator-run/169-CONTEXT.md` — D-05 (exact sbatch commands), D-06 (pre-run checks)

### Phase 162 — RDS reference path
- `.planning/phases/162-export-patient-modality-dates/162-01-SUMMARY.md` — confirms RDS path on /blue (outputs_dir)

### No external specs — requirements fully captured in decisions above

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/147_verify_vs_1006.R` — upgrade in-place; `read_sheet()` helper and `results[]` accumulator reusable
- `R/88_smoke_test_comprehensive.R` — Section 15ar (lines 6381-6620) is the nearest template for 15as
- Phase 169's sbatch dependency-chain — copy and modify JOB names

### Established Patterns
- All R/88 sections follow: counter vars `p<N>_pass`/`p<N>_fail`, a `p<N>_chk()` helper that
  also bumps global `passed`/`failed`, output-gated checks with an offline-skip branch, and a
  `message(glue("SMOKE-<N>-01: ..."))` footer
- verify script: `results[[name]] <- "PASS — ..."` / `"FAIL — ..."` pattern; final tally loop
- `quit(status = N)` is the correct R exit code setter in Rscript context

### Integration Points
- `output/logs/` directory — verify log lands here; Phases 171/172 gate reads from here
- `CONFIG$cache$outputs_dir` — path to dated xlsx AND dated RDS files on HiPerGator, AND the
  INTERNAL 1006 reference files (there is NO `CONFIG$cache$rds_dir`)

</code_context>

<specifics>
## Specific Requirements

- **INTERNAL-to-INTERNAL comparison** — the reference is
  `surveillance_modality_frequency_INTERNAL_20261006.xlsx` in `CONFIG$cache$outputs_dir`, NOT
  the release copy (which has 384 suppressed cells). The E sheet is INTERNAL-only; compare
  INTERNAL-to-INTERNAL for the RDS check.
- **A3 missing from identical_sheets** — confirmed gap in the current script; must be added
- **No lab-rule table** — there is no distinct lab-rule artifact; rules live in A2 and
  Codeset_summary (both already checked). Do NOT add a lab-rule check (not even a SKIP).
- **E check replacement** — drop E from `identical_sheets`; add tolerant RDS-vs-RDS comparison
  (`all.equal`, arrange by ID, strip attributes) for primary (non-`_any`) columns; also assert
  `<mod>_any == <mod>_primary` for the 4 CHANGED_MODS in the new RDS
- **QC matched-rows drop** — compute from A_code_presence `n_records` for SC039/SC047/SC065/SC090;
  compare the drop in "Matched rows, type ok" (NOT the "excluded (DIAGNOSIS)" row); do not hardcode 6,744
- **OVERALL always written** — sink opens first, missing files FAIL (no stop()), checks are tryCatch-wrapped
- **Verify sbatch propagates exit code** — `rc=$?` then `exit $rc`
- **`afterany` on JOB_VER** — deliberately chosen so R/88 always reports even when verify fails
- **Date-anchored downstream gate** — keyed on VERIFY_RUN_DATE, reads the specific dated log/RDS, no glob

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 170-r147-rerun-and-verification*
*Context gathered: 2026-10-09 (revised 2026-10-09 per review)*
</content>
