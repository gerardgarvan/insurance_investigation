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
JOB147=$(sbatch --parsable slurm/147_surveillance.sbatch)
JOB_VER=$(sbatch --parsable --dependency=afterok:$JOB147 slurm/147_verify.sbatch)
JOB88=$(sbatch  --parsable --dependency=afterany:$JOB_VER slurm/88_smoke_test.sbatch)
```

- `afterok` on JOB147 → verify only runs if R/147 exits 0
- `afterany` on JOB_VER → R/88 runs regardless of verify exit status, so a single run
  shows both verify failures and smoke-test results without needing a second sbatch

### D-02: Input path discipline — no "latest" globs
The verify script must use pinned paths, not glob-for-most-recent patterns:

- **Reference (1006) inputs:**
  - Workbook: `data/reference/surveillance_modality_frequency_20261006.xlsx` (explicit filename)
  - RDS: explicit path on /blue — `CONFIG$cache$rds_dir` +
    `surveillance_patient_modality_dates_20261006.rds`
  - Confirm the 1006 RDS is NOT overwritten by the rerun (R/147 writes dated filenames;
    the 1006 file is safe)

- **New-run inputs:**
  - Workbook: `surveillance_modality_frequency_INTERNAL_<run_date>.xlsx`
    where `<run_date>` is derived from `Sys.Date()` at verify-launch time (not a glob)
  - RDS: `surveillance_patient_modality_dates_<run_date>.rds`
  - If either file does not exist for today's date, the script calls `stop()` rather than
    falling back to a glob. This prevents verify from comparing 1006 vs itself on a failed job.

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
1. **Denominator / cohort N / person-years unchanged** — read KEY sheet from both workbooks;
   find rows labelled "Denominator", "Confirmed HL cohort" (or equivalent), and "Person-years";
   assert values identical.

2. **B identical for all 14 modalities** — the existing identical-sheet check covers B but
   add a named assertion so failures cite the modality, not just the column.

3. **C primary_* identical for all 10 unaffected modalities** — extend the existing C check
   to assert that non-CHANGED_MODS rows also have `primary_*` identical.

4. **C any_* == primary_* for Echo, ECG, Mammogram, PFT** — already present (D-03 note: keep).

5. **D identical for all 14 modalities** — add explicit check for D_pre_vs_post_anchor.
   For the four CHANGED_MODS: assert `any` rows == `primary` rows.
   For the other 10: assert D is byte-identical to reference.

6. **A2_analyte_presence identical** — already in `identical_sheets`; keep. Add explicit
   name in result key.

7. **A3 identical** — the script header lists A3 as "must be identical" but A3 is NOT in
   `identical_sheets`. Add `"A3_missing_analyte"` to `identical_sheets`.

8. **Lab rule table identical** — confirm sheet name (e.g. `"Lab_Analytes"` or similar);
   add to `identical_sheets`.

9. **QC matched-rows drop** — compute expected value rather than hard-coding 6,744:
   ```r
   z_codes <- c("SC039", "SC047", "SC065", "SC090")
   expected_drop <- sum(
     as.integer(ref_a[ref_a$codeset_row_id %in% z_codes, "n_records"]),
     na.rm = TRUE
   )
   ```
   Assert the QC sheet's "matched rows excluded (DIAGNOSIS)" value equals `expected_drop`.
   If the check fails, note in the FAIL message: "verify grain vs n_records grain before
   treating as regression."

10. **"diagnosis" text residue check** — scan A_code_presence, B, C, D, Codeset_summary
    for any cell containing the string "DIAGNOSIS" or "diagnosis" (case-insensitive). Only
    acceptable occurrences are in:
    - The HL-denominator row label
    - The anchor / follow-up anchor row label
    - The excluded-codeset QC row (already checked above)
    Any other occurrence is a FAIL.

11. **E sheet vs 1006 RDS** — the 1006 reference xlsx has no E_patient_modality_dates
    sheet (it pre-dates that addition), so the existing xlsx-vs-xlsx E check silently SKIPs
    and has never fired. Replace it with:
    ```r
    ref_rds <- readRDS(file.path(CONFIG$cache$rds_dir,
                       "surveillance_patient_modality_dates_20261006.rds"))
    new_rds <- readRDS(file.path(CONFIG$cache$rds_dir,
                       glue("surveillance_patient_modality_dates_{run_date}.rds")))
    # Compare after dropping _any columns (those changed; primary dates must match)
    ref_primary <- ref_rds[, !grepl("_any$", names(ref_rds))]
    new_primary <- new_rds[, !grepl("_any$", names(new_rds))]
    identical(ref_primary, new_primary)  # → PASS or FAIL
    ```
    Remove E_patient_modality_dates from `identical_sheets`.

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
- No manual interpretation required; downstream gates grep for `OVERALL: PASS`.

### D-05: Verify log file
The verify script writes its full output to:
```
output/logs/147_verify_vs_1006_<run_date>.txt
```
The file must end with the `OVERALL:` line. This is the artifact that gates Phases 171 and 172.

Implementation: wrap `sink()` around the entire check block, or pipe via `tee` in the
sbatch wrapper. The log file path is printed to stdout so the SLURM job log captures it.

### D-06: Downstream gate (Phases 171 and 172)
Both Phase 171 (survivorship workbook refresh) and Phase 172 (Phase 164 close-out) open
with a pre-flight gate:
```r
log_files <- list.files("output/logs",
  pattern = "147_verify_vs_1006_\\d{8}\\.txt", full.names = TRUE)
if (length(log_files) == 0) stop("No verify log found. Run Phase 170 first.")
latest_log <- log_files[which.max(file.mtime(log_files))]
log_lines  <- readLines(latest_log)
if (!any(grepl("^OVERALL: PASS$", log_lines)))
  stop("Phase 170 verify did not pass. Fix R/147 output before running this script.")
```
The gate reads the latest log (not pinned date) so it still works if Phase 170 is rerun.

### D-07: R/88 Section 15as — Phase 163 structural checks
Add Section 15as immediately after Section 15ar. Label: `PHASE 163 — DIAGNOSIS EXCLUSION`.
Smoke counter: `SMOKE-163-01`.

Four checks:
1. `EXCLUDED_CDM_TABLES` is defined in R/147 source
2. `stopifnot(nrow(codeset_excluded) + nrow(codeset) == nrow(codeset_full))` assertion
   is present in R/147 source (exact string match acceptable)
3. *(Conditional — skip if no INTERNAL workbook present)* Latest INTERNAL workbook's
   A_code_presence sheet has zero rows where the `cdm_table` or equivalent column equals
   "DIAGNOSIS"
4. *(Conditional — skip if no INTERNAL workbook present)* Latest INTERNAL workbook's
   Codeset_summary sheet has zero rows where any code column matches `^Z`

Section 15ao (Phase 166) is unchanged.

### D-08: SUMMARY.md content
The SUMMARY for Phase 170 records:
- Run date (ISO, e.g. 2026-10-09)
- New workbook filename (e.g. `surveillance_modality_frequency_INTERNAL_20261009.xlsx`)
- New RDS filename (e.g. `surveillance_patient_modality_dates_20261009.rds`)
- Verify log path (e.g. `output/logs/147_verify_vs_1006_20261009.txt`)
- SLURM job IDs for JOB147, JOB_VER, JOB88
- R/88 Section 15as result (PASS / FAIL / n checks)
- OVERALL verify result

### Claude's Discretion
- Exact column names in KEY sheet for denominator / person-years rows (read from the 1006
  workbook at plan time; don't assume names)
- Whether to use `sink()` or sbatch `tee` for the log file — either is fine
- Sheet name for the lab rule table (check `excel_sheets()` on the 1006 workbook)
- Whether D-04's "diagnosis" text residue check is a separate pass or integrated into the
  per-sheet checks

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 163 — the change being verified
- `.planning/phases/163-files-1-unzip-this/163-01-PLAN.md` — DIAGNOSIS exclusion decision (D-01); codeset split logic
- `R/147_surveillance_modality_frequency.R` lines ~55-70 — `EXCLUDED_CDM_TABLES` constant and codeset split

### verify_vs_1006 script (to be upgraded, not replaced)
- `R/147_verify_vs_1006.R` — current implementation; all additions go here

### R/88 smoke test (section 15as to be added)
- `R/88_smoke_test_comprehensive.R` lines ~6381+ — Section 15ar (last section); insert 15as after

### Phase 169 run procedure (reuse)
- `.planning/phases/169-registration-smoke-test-and-hipergator-run/169-CONTEXT.md` — D-05 (exact sbatch commands), D-06 (pre-run checks)

### Phase 162 — RDS reference path
- `.planning/phases/162-export-patient-modality-dates/162-01-SUMMARY.md` — confirms RDS path on /blue

### No external specs — requirements fully captured in decisions above

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/147_verify_vs_1006.R` — upgrade in-place; skeleton of check loop, `read_sheet()` helper, and `results[]` accumulator all reusable
- `R/88_smoke_test_comprehensive.R` — `check_163()` helper pattern follows `check_158()`, `check_160()` etc.; copy nearest section for template
- Phase 169's sbatch dependency-chain — copy and modify JOB names

### Established Patterns
- All R/88 sections follow: `read_or_null()`, `check_<phase>()` helper, counter vars `p<N>_pass`/`p<N>_fail`, summary `message()` at end
- verify script: `results[[name]] <- "PASS — ..."` or `"FAIL — ..."` pattern; final tally loop
- `quit(status = N)` is the correct R exit code setter in Rscript context

### Integration Points
- `output/logs/` directory — verify log lands here; Phases 171/172 gate reads from here
- `CONFIG$cache$rds_dir` — path to dated RDS files on HiPerGator (defined in R/00_config.R)
- `CONFIG$cache$outputs_dir` — path to dated xlsx outputs on HiPerGator

</code_context>

<specifics>
## Specific Requirements

- **A3 missing from identical_sheets** — this is a confirmed gap in the current script; must be added
- **Lab rule table** — sheet name unknown locally; planner must check `excel_sheets()` on the 1006 workbook and add it to `identical_sheets`
- **E check replacement** — drop E from `identical_sheets`; add RDS-vs-RDS comparison for primary (non-`_any`) columns only
- **QC matched-rows drop** — compute from A_code_presence `n_records` for SC039/SC047/SC065/SC090; do not hardcode 6,744
- **`afterany` on JOB_VER** — deliberately chosen so R/88 always reports even when verify fails

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 170-r147-rerun-and-verification*
*Context gathered: 2026-10-09*
