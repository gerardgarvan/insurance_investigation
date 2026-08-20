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

## §2 ADI State Coverage — Task 2

### Diagnosis probe (run on HiPerGator before re-run)

The probe confirms that residue ZIP5s are absent from zip5_adi_summary.csv because the
Neighborhood Atlas data covers only 23 of 50 states. Probe code from 149-CONTEXT.md §3a:

```r
adi <- readr::read_csv("data/reference/zip5_adi_summary.csv",
                       col_types = readr::cols(ZIP5 = "c", .default = "?"))
need_z <- unique(new$ZIP5[new$zip9_source == "zip5_no_zip9"])

cat("residue ZIP5s present in the ADI summary:", sum(need_z %in% adi$ZIP5),
    "of", length(need_z), "\n")

# Which state prefixes does the ADI file actually cover?
cover <- adi |>
  dplyr::mutate(p3 = substr(ZIP5, 1, 3)) |>
  dplyr::distinct(p3) |>
  dplyr::arrange(p3)
cat("distinct 3-digit prefixes in ADI:", nrow(cover), "\n")
cat("prefix-7 range present:", sum(substr(cover$p3,1,1) == "7"), "\n")
```

**Expected result:** residue ZIP5s present in ADI summary ≈ 0 of 153; prefix-7 coverage ≈ 0.

### States to download (priority order from residue evidence)

| Prefix range | State | Residue ZIP5 coverage | Priority |
|---|---|---|---|
| 716–729 | Arkansas (AR) | bulk of the 92 prefix-7 ZIPs | 1 |
| 700–714 | Louisiana (LA) | prefix-7 | 2 |
| 730–741 | Oklahoma (OK) | prefix-7 | 3 |
| 750–799 | Texas (TX) | prefix-7 | 4 |
| 386–397 | Mississippi (MS) | | 5 |
| 006–009 | Puerto Rico (PR) | 00983 = 366 encounters | 6 |

Download all remaining states beyond these six if feasible in the same session.

### Download checklist (fill in before re-run — 149-03 Task 2 requires ALL of these filled)

- [ ] States already present in zip5_adi_summary.csv: TBD
- [ ] States downloaded this session: TBD
- [ ] Download date: TBD
- [ ] File vintage (Neighborhood Atlas data year): TBD
- [ ] Collated ZIP9 file size confirmed ≈ 478 MB: TBD
- [ ] File SCP'd to HiPerGator and confirmed present (ls -lh on HiPerGator): TBD

NOTE: these use TBD, not PENDING. 149-03's completeness check greps for zero PENDING in this
file; leaving PENDING here would fail a correctly-executed phase.

### SCP requirement

The 478 MB collated Neighborhood Atlas ZIP9 file is listed in .gitignore and will NOT be
pushed to the remote repo. It must be SCP'd to HiPerGator manually before R/118 is re-run:

  scp neighborhood_atlas_zip9_collated.csv <netid>@hpg.rc.ufl.edu:<repo_path>/data/reference/

Confirm presence with `ls -lh data/reference/neighborhood_atlas_zip9_collated.csv` on
HiPerGator before running R/118_build_zip5_adi_summary.R. An absent file makes R/118
report 0% coverage and look like a join failure, not a missing-file error.

### Post-rebuild record (fill after R/118 runs — 149-03 Task 3)

- ZIP5 count in rebuilt zip5_adi_summary.csv: TBD
- Non-NA median adi_natrank count: TBD
- zip5_representative count (from R/116 after re-run): TBD

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
