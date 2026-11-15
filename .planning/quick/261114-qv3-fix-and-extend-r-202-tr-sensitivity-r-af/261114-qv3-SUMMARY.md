# Quick 261114-qv3 — Summary

## Changes
- `R/202_tr_sensitivity.R`: bug fix (`if_any`); new input defaults; not-captured split into no pipeline record / pipeline > 90d before / > 90d after TR date, with median (IQR) days, in A, B, C, D, E; sheet `E_coverage_window` (first `ENCOUNTER.ADMIT_DATE`, own open/close block, aggregated in DuckDB); D bands <=2009 / 2010-12 / 2013-15 / 2016-18 / 2019+ with TR dx-year fallback; C "Pipeline captured n" now includes code-only matches; A tiers renamed cumulative; KEY and QC wording.
- `R/utils/utils_tr_sensitivity.R` (new): pure helpers, unit-tested.
- `R/88` SECTION 15be: E sheet, renamed columns.
- `tests/testthat/test-202-tr-sensitivity.R` (new): 22 expectations pass locally.
- 202 SUMMARY addendum and HUMAN-UAT item 2.

## Verification
- `tools/rcheck.sh parse` on R/202, R/88, utils, test: OK.
- `tools/rcheck.sh test 202`: pass.

## Assumptions (headless run)
- `DATE_OF_DIAGNOSIS` (UFH) / `DXDATE` (ORL, TMH) are not in the probe. Used only if present in `TUMOR_REGISTRY_ALL`; the run prints which were found.
- `ENCOUNTER` key is `ID`, date column `ADMIT_DATE` (per task, per CLAUDE.md patient key).
- TR-undated (code-only) rows are retained in sheet E (cannot be placed against the window).
- Pipeline-before/after tiers use the first Gantt episode of the type only (unchanged definition).
- C "Sensitivity %" stays dated hits (<=90d) / TR given, matching A; the captured-n column adds code-only matches.
- Median/IQR is of absolute day differences, shown only when n >= 11.
- Newest-file default for R202_TR_FLAGS follows the user's explicit request; filename date sort, not mtime.

## PENDING HIPERGATOR
Rerun, then paste back: the error plus ~20 lines if any, and the "Section 10 / 10b" console lines.
```r
module load R/4.5
R --no-save
source("R/202_tr_sensitivity.R", local = new.env(parent = globalenv()))
```
Then `Sys.setenv(R202_SENSITIVITY_XLSX = "output/202_tr_sensitivity_<date>.xlsx")` and rerun R/88 SECTION 15be; paste its PASS/FAIL line.
