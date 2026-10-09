# Phase 170 Downstream Gate — Phases 171 and 172

**Applies to:** Phase 171 (survivorship workbook refresh) and Phase 172 (Phase 164 close-out)

---

## How the Gate Works

When Phase 170 runs successfully, `R/147_verify_vs_1006.R` writes a dated pointer file:

```
output/logs/147_verify_last_pass.txt
```

This pointer file is only written when the verify script exits with `OVERALL: PASS`. A failed
or partial run never overwrites it, so the file always points to the last _verified_ run, not
the most recent unverified output.

The pointer file contains key=value pairs (one per line, no quotes, `=` delimiter):

```
run_date=20261009
log=output/logs/147_verify_vs_1006_20261009.txt
rds=output/surveillance_patient_modality_dates_20261009.rds
```

---

## Gate Snippet (paste at the top of Phase 171 / Phase 172 scripts)

```r
# ---- Phase 170 pre-flight gate (D-06) ----
ptr <- file.path(CONFIG$output_dir, "logs", "147_verify_last_pass.txt")
if (!file.exists(ptr)) stop("No verified R/147 run found (", ptr, "). Run Phase 170 first.")
kv <- read.delim(ptr, sep = "=", header = FALSE, col.names = c("k", "v"), quote = "")
get <- function(k) kv$v[kv$k == k][1]
run_date <- get("run_date"); verify_log <- get("log"); rds_path <- get("rds")
stopifnot(grepl("^[0-9]{8}$", run_date))
if (!file.exists(verify_log) || !any(readLines(verify_log) == "OVERALL: PASS"))
  stop("Verify log for ", run_date, " missing or not PASS: ", verify_log)
if (!file.exists(rds_path)) stop("Verified RDS missing: ", rds_path)
# Optional strictness: warn if a newer INTERNAL workbook exists without a passing verify
newer <- list.files(CONFIG$cache$outputs_dir, "^surveillance_modality_frequency_INTERNAL_\\d{8}\\.xlsx$")
newer_dates <- sub(".*_(\\d{8})\\.xlsx$", "\\1", newer)
if (any(newer_dates > run_date))
  warning("A newer R/147 run (", max(newer_dates), ") exists but has not passed verification; using ", run_date)
message("Phase 170 gate OK: R/147 run ", run_date)
# ---- end gate ----
```

After the gate passes, consume the verified RDS by its pinned date:

```r
surv_rds <- readRDS(rds_path)   # rds_path is set by the gate above
```

---

## Design Rationale

| Property | Why |
|----------|-----|
| Pointer file written only on PASS | A failing run or SLURM job cancellation cannot move the pointer, so the gate always reflects a genuinely verified state |
| Key=value pointer (not a glob) | No `which.max(file.mtime())` risk: the gate reads the exact dated log and RDS paths that the verify script recorded when it passed |
| Dated log checked for `OVERALL: PASS` | Confirms the log file itself ended cleanly, not just that it exists |
| Dated RDS existence confirmed | Guards against a run where the xlsx passed but the RDS write was interrupted |
| Stale-run warning | If someone re-ran R/147 but did not re-run verify, downstream scripts warn rather than silently consuming stale output |
| No VERIFY_RUN_DATE env var required | Phases 171/172 may run in a separate session where that env var is not set; the pointer file removes that dependency entirely |

---

## How `147_verify_last_pass.txt` is Written

At the end of `R/147_verify_vs_1006.R`, when the final tally confirms `n_fail == 0`:

```r
if (n_fail == 0) {
  ptr_path <- file.path("output", "logs", "147_verify_last_pass.txt")
  writeLines(
    c(
      paste0("run_date=", run_date),
      paste0("log=",      verify_log_path),
      paste0("rds=",      rds_path)
    ),
    ptr_path
  )
  message("Pointer written: ", ptr_path)
}
```

The verify script is `R/147_verify_vs_1006.R`. The pointer is written inside the
`if (n_fail == 0)` block, never in the failure branch, and never in `on.exit()`.

---

## SLURM Job Chain (Phase 170)

```bash
git pull
JOB147=$(sbatch --parsable slurm/147_surveillance.sbatch)
JOB_VER=$(sbatch --parsable --dependency=afterok:$JOB147  slurm/147_verify.sbatch)
JOB88=$(sbatch  --parsable --dependency=afterany:$JOB_VER slurm/88_smoke_test.sbatch)
```

- `afterok` on JOB147: verify only runs if R/147 exits 0
- `afterany` on JOB_VER: R/88 always runs so smoke-test results are visible even when verify fails
- If JOB147 fails, JOB_VER is skipped → no new pointer file → Phases 171/172 gate uses the previous PASS pointer (correct behavior)

---

*Phase: 170-r147-rerun-and-verification*
*Applies to: Phases 171, 172*
*Last updated: 2026-10-09*
