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
(filled by Task 2)

### Positive control
Count of repeated-digit sentinels rejected by the CURRENT filter in LDS_ADDRESS_HISTORY:
(filled by Task 2)

### Decision gate — verdict: (filled by Task 2)
HALT and investigate before 149-02 if EITHER:
- the positive control returns 0 — the existing filter has never fired, so widening it is
  not the fix; something else is wrong
- any enumerated ZIP5 is a valid US delivery ZIP — the widened filter would discard real data

Otherwise: PASS.

### has_adi_zip5 supply path
zip5_representative resolved 47,036 encounters, so has_adi_zip5 exists when
.classify_zip9_source() evaluates it — but it is NOT in the five-column select() at
utils_address.R lines 526-532. Locate where it comes from before 149-02 edits this file:
(filled by Task 2)

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
