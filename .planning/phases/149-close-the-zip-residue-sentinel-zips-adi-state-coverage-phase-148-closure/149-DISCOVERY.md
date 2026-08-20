# 149-DISCOVERY.md — ZIP Residue Closure Evidence

Phase 149: Close the ZIP Residue — Sentinel ZIPs, ADI State Coverage, Phase 148 Closure
Baseline: `output/encounter_ses_index_20260820.rds` (1,950,696 rows)

---

## §1 Enumeration — sub-00501 ZIPs

Widening a sentinel filter REMOVES DATA. Every ZIP5 it newly rejects must be confirmed
invalid before the change is made. This section is filled from a real HiPerGator run in
Task 2; 149-02 must not execute until the verdict below reads PASS.

### Probe (from 149-CONTEXT.md §2a)

```r
source("R/00_config.R")
new <- readRDS(Sys.glob("output/encounter_ses_index_*.rds") |> sort() |> tail(1))

# (a) what a widened filter would newly reject
cand <- new |>
  dplyr::filter(!is.na(ZIP5)) |>
  dplyr::mutate(n5 = suppressWarnings(as.integer(ZIP5))) |>
  dplyr::filter(!is.na(n5), n5 < 501) |>   # as.integer(ZIP5) < 501
  dplyr::count(ZIP5, sort = TRUE)
print(cand, n = Inf)
cat("encounters affected:", sum(cand$n), "\n")

# (b) POSITIVE CONTROL — does the current filter fire at all?
addr <- vroom::vroom(file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv"),
                     col_types = vroom::cols(.default = "c"), progress = FALSE)
cat("repeated-digit sentinels in ADDRESS_ZIP5:",
    sum(is_sentinel_zip5(addr$ADDRESS_ZIP5), na.rm = TRUE), "\n")
```

And, in the shell:

```bash
grep -n "has_adi_zip5\|adi_summary\|zip5_adi" R/utils/utils_address.R
```

### Output

From `output/encounter_ses_index_20260820.rds` (real HiPerGator run, 2026-08-20):

```
# A tibble: 3 × 2
  ZIP5      n
  <chr> <int>
1 00009   854
2 00001    95
3 00007    85
encounters affected: 1034
```

Three ZIP5s newly rejected by the widened filter: `00009` (854 encounters), `00001` (95),
`00007` (85). All three are numerically below 00501 — invalid by definition (lowest real US
ZIP is 00501, Holtsville NY). No real delivery ZIP appears in the list.

### Positive control

Count of repeated-digit sentinels rejected by the CURRENT filter in LDS_ADDRESS_HISTORY:

```
repeated-digit sentinels in ADDRESS_ZIP5: 52
```

52 > 0 — the existing filter fires. Widening it is the correct fix.

### Decision gate — verdict: PASS

HALT and investigate before 149-02 if EITHER:
- the positive control returns 0 — the existing filter has never fired, so widening it is
  not the fix; something else is wrong
- any enumerated ZIP5 is a valid US delivery ZIP — the widened filter would discard real data

Otherwise: PASS.

Both conditions checked: positive control = 52 (non-zero); all enumerated ZIP5s (00009,
00001, 00007) are below 00501 and invalid by definition. **149-02 may proceed.**

### has_adi_zip5 supply path

From `grep -n "has_adi_zip5\|adi_summary\|zip5_adi" R/utils/utils_address.R`:

```
326:          has_adi_zip5                           ~ "zip5_representative",
339:          has_adi_zip5                           ~ "zip5_representative",
361:    has_adi_zip5      = logical()
```

`has_adi_zip5` is initialized as `logical()` at **utils_address.R line 361** (empty logical
column in the output tibble accumulator), then consumed in `case_when` at **lines 326 and
339** where it maps to the `"zip5_representative"` zip9_source label. It is a derived logical
column computed internally within utils_address.R — not passed in from outside and not in the
five-column `select()`. 149-02 must not remove or rename this column.

---

## §2 ADI state coverage (149-02 fills this)
PENDING.

---

## §5 Before/after zip9_source breakdown (149-03 fills the post-149 column)
| zip9_source | current (0820) | post-149 |
|---|---|---|
| zip9_observed | 1,516,469 | PENDING |
| zip5_modal | 198,768 | PENDING |
| zip5_representative | 47,036 | PENDING |
| zip5_no_zip9 | 12,782 | PENDING |
| no_zip5 | 16,942 | PENDING |
| none | 158,699 | PENDING |
| total | 1,950,696 | PENDING |
