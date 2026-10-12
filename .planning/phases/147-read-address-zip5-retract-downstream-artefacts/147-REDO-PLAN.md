# 147-REDO-PLAN.md — Apply the `ADDRESS_ZIP5` Fix (it never landed)

Run this on HiPerGator at `/blue/erin.mobley-hl.bcu/insurance_investigation`.

**Why this exists.** Phase 147 Plan 2 was specified correctly and never reached the file. Evidence
from the live checkout:

```
git log --oneline -3 -- R/utils/utils_address.R
  e27a466 fix(145-03): Branch C diagnosis -- document ZIP5-modal zero-rows as expected   <- last touch
  0364c89 update utils_address and encounter SES index from files_3.zip
  e49792b fix(tests): extract centroid 0000 guard to .validate_centroid_lookup()

grep -n "ADDRESS_ZIP5" R/utils/utils_address.R
  158:  # No separate ADDRESS_ZIP5 column exists in LDS_ADDRESS_HISTORY (confirmed from
```

`ADDRESS_ZIP5` appears once in the file, inside the comment denying it exists. Plan 3 then re-ran
R/115, R/116 and R/88 against unmodified code and recorded `zip5_no_zip9 = 0` as a measurement.

**Measured facts this rests on** (all from your own HiPerGator runs):

| | |
|---|---|
| `ADDRESS_ZIP5` populated | 38,472 of 40,005 records (96.2%) |
| `ADDRESS_ZIP9` populated | 20,032 (50.1%) |
| ZIP5-only records | 18,731 (46.8%) |
| ZIP9-only records | 291 (0.7%) |
| `ADDRESS_ZIP5` values nulled by `normalize_zip5()` | **0** — there are no sentinel ZIP5s |
| Prefix disagreements where both present | 12 of 19,741 (0.061%) |

Isolated proof the fix is absent:

```
get_zip9_at_date("SEP15202520240072100003076", as.Date("2019-12-14"))
  ZIP9 = NA   ZIP5 = NA   match_type = "interval"
```

The record matched on date and its `ADDRESS_ZIP5` is valid, yet `ZIP5` is `NA`.

---

## Step 0 — Precondition gate (run first, abort if it fails)

```bash
cd /blue/erin.mobley-hl.bcu/insurance_investigation

grep -q "No separate ADDRESS_ZIP5 column exists" R/utils/utils_address.R \
  && echo "CONFIRMED: fix absent, proceed" \
  || echo "STOP: false comment already gone — someone applied part of this; inspect before editing"
```

If it says STOP, run `grep -n "ADDRESS_ZIP5\|zip5_norm" R/utils/utils_address.R` and read the block
before changing anything.

---

## Step 1 — Edit `R/utils/utils_address.R`

The target is the `mutate()` inside `get_zip9_at_date()`, currently at lines ~152–162. **Replace**
this block:

```r
      zip9_norm       = normalize_zip9(ADDRESS_ZIP9),
      # Phase 139 AMEND-01 / Step 0c: coalesce ZIP5 from two sources:
      #   (1) normalize_zip5() of a valid 9-digit ZIP9 (existing path)
      #   (2) normalize_zip5_raw() applied directly to ADDRESS_ZIP9 for rows where
      #       ADDRESS_ZIP9 holds a bare 5-digit string that normalize_zip9() rejects
      # No separate ADDRESS_ZIP5 column exists in LDS_ADDRESS_HISTORY (confirmed from
      # plan analysis: ADDRESS_ZIP9 holds bare ZIP5s for some records -- Step 0a case 2).
      zip5_norm       = coalesce(normalize_zip5(zip9_norm), normalize_zip5_raw(ADDRESS_ZIP9)),
```

**with** this:

```r
      zip9_norm       = normalize_zip9(ADDRESS_ZIP9),
      # Phase 147: ZIP5 has THREE sources, in this precedence.
      #
      # The comment previously here said "No separate ADDRESS_ZIP5 column exists in
      # LDS_ADDRESS_HISTORY". That was wrong. ADDRESS_ZIP5 is populated in 38,472 of
      # 40,005 records (96.2%) against ADDRESS_ZIP9's 20,032 (50.1%), and 18,731 records
      # (46.8%) carry a ZIP5 with no ZIP9. Deriving ZIP5 from ADDRESS_ZIP9 alone made ZIP5
      # NA whenever ZIP9 was NA -- by construction, not by data. That artefact produced the
      # "0 rows with ZIP5 present and ZIP9 missing" finding in Phase 145 and the
      # "sentinel-nulled" explanation that followed it. No ADDRESS_ZIP5 value in the file
      # is rejected by normalize_zip5() -- there are no sentinel ZIP5s.
      #
      #   (1) ADDRESS_ZIP5 -- the field the source populated deliberately. Wins the 12
      #       prefix disagreements (12 of 19,741 rows where both are present, 0.061%).
      #   (2) normalize_zip5() of a valid 9-digit ZIP9 -- covers the 291 ZIP9-only records.
      #   (3) normalize_zip5_raw() on ADDRESS_ZIP9 -- Phase 139 Step 0c fallback for rows
      #       where ADDRESS_ZIP9 holds a bare 5-digit string normalize_zip9() rejects.
      zip5_norm       = coalesce(
        normalize_zip5(ADDRESS_ZIP5),
        normalize_zip5(zip9_norm),
        normalize_zip5_raw(ADDRESS_ZIP9)
      ),
```

Keep everything after it untouched — the `is_sentinel_zip5()` line, `period_start_dt`,
`period_end_dt`, and the `filter(!is.na(period_start_dt))`.

**No other edits are needed.** `vroom::cols(.default = "c")` already reads `ADDRESS_ZIP5` as
character, and there is no `select()` between the load and the mutate, so the column is in scope.

### Optional guard

Worth adding after the existing `ID` check (~line 138), so a future extract without the column
fails loudly rather than silently reverting:

```r
  if (!"ADDRESS_ZIP5" %in% names(addr_raw)) {
    stop(glue(
      "[utils_address] LDS_ADDRESS_HISTORY missing 'ADDRESS_ZIP5'. It was added as a ZIP5 ",
      "source in Phase 147; without it ZIP5 falls back to the ADDRESS_ZIP9 prefix and ~47% ",
      "of ZIP5 coverage is lost silently. Found: {paste(names(addr_raw), collapse=', ')}"
    ))
  }
```

---

## Step 2 — Prove the edit took effect (before any pipeline re-run)

```r
source("R/00_config.R")

addr <- vroom::vroom(file.path(CONFIG$data_dir, "LDS_ADDRESS_HISTORY_Mailhot_V1.csv"),
                     col_types = vroom::cols(.default = "c"), progress = FALSE)

id_zip5only <- addr |>
  dplyr::filter(!is.na(ADDRESS_ZIP5), is.na(ADDRESS_ZIP9)) |>
  dplyr::slice(1)

out <- get_zip9_at_date(id_zip5only$ID,
                        lubridate::dmy(id_zip5only$ADDRESS_PERIOD_START) + 1)
print(out)

stopifnot(
  "ZIP5 still NA -- the coalesce is not on the code path" = !is.na(out$ZIP5),
  "ZIP9 should remain NA for a ZIP5-only record"          = is.na(out$ZIP9),
  "record should still match on date"                     = out$match_type == "interval"
)
cat("PASS: ADDRESS_ZIP5 is being read\n")
```

`ADDRESS_PERIOD_START` is SAS format (`13DEC2019`), hence `lubridate::dmy()` — `ymd()` and bare
`as.Date()` both return `NA` on it.

**Do not proceed to Step 3 until this passes.** This is the check whose absence let the previous
re-run report a number from unmodified code.

---

## Step 3 — Archive, then re-run

```bash
cd output
for f in encounter_ses_index_*.rds encounter_ses_index_*.xlsx \
         encounter_ses_index_summary_*.xlsx zip_stability_counts_*.xlsx; do
  [ -e "$f" ] || continue
  case "$f" in *_pre147.*|*_pre148.*) continue;; esac
  mv "$f" "${f%.*}_pre147.${f##*.}" && echo "archived $f"
done
ls -la *_pre147.* 2>/dev/null
cd ..
```

Dated filenames overwrite in place, so archiving is mandatory. Then, in this order:

```bash
module load R/4.4.2
Rscript R/115_zip_stability_counts.R      # was delivered to Erin and Amy on the old ZIP5
Rscript R/116_encounter_ses_index.R
Rscript R/88_smoke_test_comprehensive.R
```

---

## Step 4 — Record the before/after

| | pre-147 | post-147 | expected |
|---|---|---|---|
| `zip9_observed` | 1,516,469 (77.7%) | | **unchanged** — this adds no ZIP9s |
| `zip5_modal` | 0 | | non-zero, or see note |
| `zip5_no_zip9` | 0 | | non-zero — Tier 3's real population |
| `zip5_centroid` | 0 | | 0 — no crosswalk staged |
| `no_zip5` | 275,528 (14.1%) | | **falls sharply** |
| `none` | 158,699 (8.1%) | | **unchanged** — no address record covers those dates |
| RUCA coverage | 77.7% | | **rises** — RUCA joins on ZIP5 |

**The assertion that was missing last time:**

```r
stopifnot("Phase 147 had no effect" = (n_zip5_modal + n_zip5_no_zip9) > 0)
```

`zip9_observed` unchanged and `none` unchanged both pass on untouched code — they cannot tell "the
fix worked" from "the fix never ran". This one can.

**On `zip5_modal` specifically:** zero is possible and is not automatically a defect. Modal needs a
ZIP5-only row **and** another cohort record sharing that ZIP5 that *does* have an observed ZIP9. If
the 18,731 records cluster in ZIP5s where nobody has one, modal correctly fires zero and they land
in `zip5_no_zip9` — which strengthens the case for the centroid crosswalk rather than weakening it.
What must not be zero is the **sum**.

---

## Step 5 — Retract, and hand the number forward

Phase 147's Plan 4 retractions stay correct in substance — the 77.7% ceiling and the sentinel
explanation were wrong regardless of whether the fix landed. But they point at post-147 figures that
did not exist. After Step 4:

- Fill the real numbers into `147-DISCOVERY.md` §4.
- Add one more retraction, of the sentinel claim specifically. It originated in Phase 145's Branch C,
  became Phase 146's D-04 lever (157,472 rows of supposed upside), and was then used to justify
  closing Phase 148. **Zero `ADDRESS_ZIP5` values are nulled by `normalize_zip5()`** — the
  explanation never had any basis in the data.
- Correct the Branch C console note in `utils_address.R` (Phase 147 Plan 4 Task 3). It currently
  prints a cause that is now disproven.
- **`148-01-PLAN.md` must not execute.** Its closure rests on `zip5_no_zip9 = 0`, which came from
  unmodified code. Re-gate Phase 148 on the Step 4 value.

---

## Done when

- [ ] Step 0 confirmed the fix was absent.
- [ ] `grep -c "normalize_zip5(ADDRESS_ZIP5)" R/utils/utils_address.R` returns 1.
- [ ] `grep -c "No separate ADDRESS_ZIP5 column exists" R/utils/utils_address.R` returns 0.
- [ ] Step 2 prints `PASS: ADDRESS_ZIP5 is being read`.
- [ ] Outputs archived as `*_pre147.*`; nothing overwritten.
- [ ] R/115, R/116, R/88 all run; R/88 passes.
- [ ] `zip9_observed == 1,516,469` and `none == 158,699` in the post-147 column.
- [ ] `zip5_modal + zip5_no_zip9 > 0`.
- [ ] `147-DISCOVERY.md` §4 filled with real figures; the sentinel claim retracted.
- [ ] Phase 148 re-gated on the new `zip5_no_zip9`; `148-01-PLAN.md` not executed as written.
- [ ] Committed with a message naming the phase, e.g.
      `fix(147): read ADDRESS_ZIP5 in get_zip9_at_date -- Plan 2 never landed`.

---

## Do not

| | Because |
|---|---|
| Remove the `normalize_zip5(zip9_norm)` or `normalize_zip5_raw()` arms | They cover the 291 ZIP9-only records and Phase 139's bare-ZIP5-in-ZIP9 case |
| Skip Step 2 | Its absence is exactly why a number from unmodified code became a finding |
| Touch `is_sentinel_zip5()` | It rejects nothing in this file; it is not the problem |
| Change the tier order or the `0000` guard | This changes what ZIP5 *is*, not what the tiers do with it |
| Overwrite the pre-147 outputs | The before/after is the evidence |
| Treat `zip5_modal = 0` as failure | Check the sum; see Step 4 |
| Run `148-01-PLAN.md` | Its gate value is void |
