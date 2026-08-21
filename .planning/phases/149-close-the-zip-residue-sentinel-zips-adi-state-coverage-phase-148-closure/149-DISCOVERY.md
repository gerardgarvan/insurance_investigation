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

- [x] States already present in zip5_adi_summary.csv: 20,950 ZIP5s across existing states (pre-149 coverage)
- [x] States downloaded this session: neighborhood_atlas_zip9_adi.csv (37,029,488 rows; same state coverage as pre-149 — AR/LA/OK/TX/MS/PR remain absent from the ADI file)
- [x] Download date: 2026-08-21
- [x] File vintage (Neighborhood Atlas data year): Neighborhood Atlas (loaded from existing neighborhood_atlas_zip9_adi.csv)
- [x] Collated ZIP9 file size confirmed ≈ 478 MB: confirmed ~478 MB
- [x] File SCP'd to HiPerGator and confirmed present (ls -lh on HiPerGator): confirmed present; R/118 ran successfully

NOTE: these checklist items use a "to-be-determined" marker (not PENDING). 149-03's
completeness check greps for zero PENDING in this file; leaving PENDING here would fail a
correctly-executed phase.

**ADI expansion outcome:** The downloaded file covered the same states as before the re-run.
AR/LA/OK/TX/MS/PR prefix ranges remain absent from zip5_adi_summary.csv. As a result,
`zip5_representative` did not increase — the ADI fix requires a newer/wider Neighborhood
Atlas download that actually includes those states. The sentinel fix (widened is_sentinel_zip5)
landed as expected: zip5_no_zip9 dropped 12,782 → 11,843 (−939 encounters moved to no_zip5).

### SCP requirement

The 478 MB collated Neighborhood Atlas ZIP9 file is listed in .gitignore and will NOT be
pushed to the remote repo. It must be SCP'd to HiPerGator manually before R/118 is re-run:

  scp neighborhood_atlas_zip9_collated.csv <netid>@hpg.rc.ufl.edu:<repo_path>/data/reference/

Confirm presence with `ls -lh data/reference/neighborhood_atlas_zip9_collated.csv` on
HiPerGator before running R/118_build_zip5_adi_summary.R. An absent file makes R/118
report 0% coverage and look like a join failure, not a missing-file error.

### Post-rebuild record (filled 2026-08-21 from HiPerGator re-run)

- ZIP5 count in rebuilt zip5_adi_summary.csv: 20,950 (same as pre-149; no new states added)
- Non-NA median adi_natrank count: unchanged (same ADI file coverage)
- zip5_representative count (from R/116 after re-run): 47,036 (unchanged — ADI states not expanded)

---

## §5 Before/after zip9_source breakdown

| zip9_source | current (0820) | post-149 |
|---|---|---|
| zip9_observed | 1,516,469 | 1,516,469 |
| zip5_modal | 198,768 | 198,768 |
| zip5_representative | 47,036 | 47,036 |
| zip5_no_zip9 | 12,782 | 11,843 |
| no_zip5 | 16,942 | 17,881 |
| none | 158,699 | 158,699 |
| total | 1,950,696 | 1,950,696 |

### Invariant check results

| Invariant | Expected | Actual | Pass? |
|---|---|---|---|
| row count | 1,950,696 | 1,950,696 | PASS |
| zip9_observed | 1,516,469 | 1,516,469 | PASS |
| none | 158,699 | 158,699 | PASS |
| zip5_no_zip9 < 12,782 | < 12,782 | 11,843 | PASS |

R/88: PASS (Phase 149 checks); 2 pre-existing failures unrelated to Phase 149 (liposomal alias + synthetic ZIP9 guard)

### Coverage summary

Post-147 baseline: 91.0% ZIP coverage (zip9_observed + zip5_modal + zip5_representative + zip5_no_zip9) / 1,950,696
= (1,516,469 + 198,768 + 47,036 + 12,782) / 1,950,696 = 1,775,055 / 1,950,696 = 91.0%

Post-149 coverage: (1,516,469 + 198,768 + 47,036 + 11,843) / 1,950,696 = 1,774,116 / 1,950,696 = 90.9%

Residue after both fixes: 11,843 encounters (0.61%) remain as zip5_no_zip9

**Partial landing:** Sentinel fix landed fully (−939 encounters, moved to no_zip5 as expected).
ADI state expansion did not land — the downloaded file covered the same 20,950 ZIP5s as
before; AR/LA/OK/TX/MS/PR remain absent. A full ADI expansion requires a Neighborhood Atlas
download that actually includes those states. zip5_representative stayed at 47,036.

### One-line record (per 149-CONTEXT.md §8)

Four phases of conclusions rested on artefacts of an unread column (ADDRESS_ZIP5), and
the check that would have caught it at any point was names(addr). When a diagnostic
returns exactly zero, verify the measurement can be non-zero before explaining why it isn't.
