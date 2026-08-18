# PHASE 148 — Read `ADDRESS_ZIP5`

Context spec for the Claude Code CLI, `insurance_investigation` repo.

`get_zip9_at_date()` reads `ADDRESS_ZIP9` only, and derives ZIP5 from it. The extract also carries a
populated **`ADDRESS_ZIP5`** column that no code path has ever read. ZIP5 has therefore been `NA`
whenever `ADDRESS_ZIP9` is `NA` — by construction, not by data.

**This phase reads that column, re-runs, re-measures, and retracts what the omission caused.**

It is a small code change with a large blast radius: three phases recorded conclusions that were
artefacts of it, and one of those conclusions is currently the stated reason a downstream phase
exists.

---

## 0. The measurement

```r
addr |> dplyr::count(zip5_ok = !is.na(ADDRESS_ZIP5), zip9_ok = !is.na(ADDRESS_ZIP9))
```

| `ADDRESS_ZIP5` | `ADDRESS_ZIP9` | records | share | |
|---|---|---|---|---|
| yes | yes | 19,741 | 49.3% | |
| **yes** | **no** | **18,731** | **46.8%** | **invisible to the current code** |
| no | yes | 291 | 0.7% | ZIP5 recoverable from the ZIP9 prefix |
| no | no | 1,242 | 3.1% | genuinely unusable |
| | | **40,005** | | |

```
records with a usable ZIP5 today (code path)   20,032   50.1%
records with a usable ZIP5 after the fix       38,763   96.9%   (+46.8 pp)
```

Character-length profile confirms there is no parsing casualty: `ADDRESS_ZIP5` is 5 chars or `NA`,
`ADDRESS_ZIP9` is 9 chars or `NA`, nothing truncated.

**Prefix disagreement:** where both are present, `substr(ADDRESS_ZIP9, 1, 5) != ADDRESS_ZIP5` in
**12 of 19,741 rows (0.061%)**.

---

## 1. What this invalidates — retract in writing, do not silently supersede

Each of these is currently recorded as a finding. A later reader will treat them as current unless
they are struck through with a pointer to this phase.

| Recorded conclusion | Where | Status |
|---|---|---|
| "0 rows have ZIP5 present and ZIP9 missing" | Phase 145 D-02 diagnostic | **Artefact.** The diagnostic derived ZIP5 from `ADDRESS_ZIP9`, so the cell could never be non-zero |
| "Branch C — approximable rows exist but all have `ZIP5 = NA` (sentinel-nulled)" | Phase 145 D-02 | **Wrong cause.** Not sentinels; the ZIP5 was in a column nobody read |
| "`zip5_modal` fires zero rows — expected, not a defect" | Phase 145 console note + `data/reference/README.md` | **Wrong.** Tier 2 had 18,731 records and was shown none |
| "77.7% is a hard ceiling for every ZIP-keyed index" | Phase 146 CONTEXT §0, README, coverage sheet | **Wrong.** It reflects `ADDRESS_ZIP9` coverage (50.1% of records), not ZIP availability (96.9%) |
| "D-04 sentinel-ZIP lever, 157,472 rows" | Phase 146 §4 | **Phantom.** Those are empty `ADDRESS_ZIP9` cells, not placeholder values. The query returns almost nothing |
| "Centroid crosswalk resolves 0 encounters" | Phase 147 §0 | **Void.** Its population is about to change; Tier 2 gets first refusal |

**D-01 · Phase 147 is on hold until this phase's re-run completes.** Do not build or licence a
centroid crosswalk against numbers this phase is about to move.

---

## 2. Rules for the planner

1. **Discover, never assume — including about columns.** This whole defect traces to code that read
   one ZIP column while the extract carried two. Before touching `get_zip9_at_date()`, print
   `names()` of the real address file and record every ZIP-ish column.
2. **The test fixture is not the data.** `tests/fixtures/LDS_ADDRESS_HISTORY_Mailhot_V1.csv` has
   **one row and three columns** and does not include `ADDRESS_ZIP5`. Any fixture used to test this
   change must carry all four 2×2 cells from §0, or the test passes on a file that cannot exercise
   the fix.
3. **Read ZIP columns as character, always.** `read_csv`'s guesser typed `ADDRESS_ZIP9` as `dbl` on
   the fixture. A numeric ZIP+4 silently drops leading zeros.
4. **Do not change the tier order or the `0000` guard.** This phase changes what ZIP5 *is*, not what
   the tiers do with it.
5. **Re-measure before re-concluding.** Every number in §1 is replaced by a fresh run, not by
   estimation from these record counts — encounter-level effects depend on which records match which
   dates.

Project conventions: patient key `ID`; `R/88` must pass; Windows dev box has no `Rscript` (parse
checks only); HiPerGator for real runs.

---

## 3. The change

### D-02 · ZIP5 source and precedence

```r
zip5 = dplyr::coalesce(
  normalize_zip5(ADDRESS_ZIP5),                    # the field the source populated deliberately
  normalize_zip5(substr(ADDRESS_ZIP9, 1, 5))       # fallback for the 291 ZIP9-only records
)
```

`ADDRESS_ZIP5` wins the 12 disagreements. **Inspect them before locking this in** — if they share a
pattern (one transposed digit, a PO-box pairing, one source system), that tells you which field is
more reliable and the precedence may need to flip:

```r
addr |>
  dplyr::filter(!is.na(ADDRESS_ZIP5), !is.na(ADDRESS_ZIP9),
                substr(ADDRESS_ZIP9, 1, 5) != ADDRESS_ZIP5) |>
  dplyr::select(ID, ADDRESS_ZIP5, ADDRESS_ZIP9, ADDRESS_PERIOD_START) |>
  print(n = 12)
```

Record the decision and the 12 rows in `148-DISCOVERY.md` either way. 0.061% does not change any
result, but an undocumented precedence rule becomes an unanswerable question later.

### D-03 · Where the change goes

In `R/utils/utils_address.R`, at the point `get_zip9_at_date()` loads and normalizes the address
frame. ZIP9 handling is unchanged; only ZIP5 gains a source.

Requirements:

- Read the address CSV with explicit `col_types` making **both** `ADDRESS_ZIP5` and `ADDRESS_ZIP9`
  character. Do not rely on the guesser.
- Guard the column's existence, so an extract without it fails loudly rather than silently
  reverting to today's behaviour:

```r
  required <- c("ID", "ADDRESS_ZIP5", "ADDRESS_ZIP9",
                "ADDRESS_PERIOD_START", "ADDRESS_PERIOD_END")
  missing  <- setdiff(required, names(addr_full))
  if (length(missing)) {
    stop("[utils_address] address file missing required column(s): ",
         paste(missing, collapse = ", "),
         ". ADDRESS_ZIP5 was added as a ZIP5 source in Phase 148; an extract without it ",
         "would silently fall back to deriving ZIP5 from ADDRESS_ZIP9 and lose ~47% of ZIP5 coverage.")
  }
```

- `get_zip9_at_date()`'s documented return contract is unchanged: one row per distinct
  `(ID, query_date)`. The Phase 145 `stopifnot` on duplicate keys stays.

### D-04 · The diagnostic in R/116 must show both columns

R/116's pre-approximation table is `table(match_type, is.na(ZIP9), is.na(ZIP5))`. That is what
produced the misleading zero cell. It stays, but `148-DISCOVERY.md` must record alongside it the
raw-column 2×2 from §0, so the two are never conflated again — the first describes what the
resolver produced, the second what the extract contained.

---

## 4. Re-measure

Re-run in this order and record each result:

1. **`R/115_zip_stability_counts.R`** — the other consumer of this chain. Its
   `zip_stability_counts_<date>.xlsx` went to Erin and Amy and is computed on the old ZIP5.
   Archive the existing workbook as `*_pre148.xlsx` before re-running.
2. **`R/116_encounter_ses_index.R`** — archive `encounter_ses_index_20260817.{rds,xlsx}` as
   `*_pre148.*` first; same-date filenames overwrite in place.
3. **`R/88_smoke_test_comprehensive.R`**.

Then record, as a before/after table:

| | pre-148 | post-148 |
|---|---|---|
| `zip9_observed` | 1,516,469 (77.7%) | |
| `zip5_modal` | 0 | |
| `zip5_centroid` | 0 | (still 0 — no crosswalk staged) |
| `zip5_no_zip9` | 0 | |
| `no_zip5` | 275,528 (14.1%) | |
| `none` | 158,699 (8.1%) | |
| RUCA coverage | 77.7% | |
| SDI coverage | 0% (not staged) | |

**Expected direction, to be checked not assumed:**

- `no_zip5` falls sharply — those rows had a ZIP5 all along.
- `zip5_modal` becomes non-zero for the first time. This is the headline: Tier 2 was built in
  Phase 139 and has never fired.
- `zip5_no_zip9` becomes non-zero — ZIP5-only rows the modal tier could not resolve. **That
  residue, not 157,472, is Tier 3's actual population**, and it is the number Phase 147 needs.
- `zip9_observed` is **unchanged** at 1,516,469. This phase adds no ZIP9s. If it moves, something
  other than ZIP5 sourcing changed.
- RUCA coverage rises, because RUCA joins on ZIP5.
- `none` is unchanged at 158,699 — no address record covers those dates regardless of columns.

Any result contradicting the last two is a defect in this change, not a finding.

---

## 5. Update the record

- `data/reference/README.md` — remove the 77.7% ceiling and the "`zip5_modal` reports zero rows,
  expected, not a defect" note. Replace with the post-run figures.
- `utils_address.R` — remove or rewrite the Phase 145 Branch C console message. It currently states
  a cause that was wrong.
- Phase 145 `145-DISCOVERY.md`, Phase 146 `146-CONTEXT.md` §0/§4, Phase 147 `147-CONTEXT.md` §0 —
  add a dated superseded-by-148 note at the top of each affected section. Do not delete the
  original text; the reasoning was sound given what the code exposed, and the record of how a
  column omission propagated into four phases of conclusions is worth keeping.

---

## 6. Acceptance criteria

- [ ] `148-DISCOVERY.md` records `names()` of the real address file and every ZIP-ish column.
- [ ] The 12 prefix-disagreement rows are printed and the D-02 precedence decision recorded.
- [ ] `ADDRESS_ZIP5` and `ADDRESS_ZIP9` are both read as character with explicit `col_types`.
- [ ] The missing-column guard is present and its message names Phase 148.
- [ ] The test fixture carries all four 2×2 cells; a test asserts a ZIP5-only record yields a
      non-NA ZIP5.
- [ ] `get_zip9_at_date()` still returns one row per distinct `(ID, query_date)`; the Phase 145
      duplicate-key `stopifnot` is intact.
- [ ] R/115 and R/116 both re-run; prior outputs archived as `*_pre148.*`, not overwritten.
- [ ] The before/after table in §4 is complete, with `zip9_observed` unchanged and `none` unchanged.
- [ ] `zip5_no_zip9` — Tier 3's real population — is recorded and handed to Phase 147.
- [ ] README, the Branch C console note, and the three phase documents are corrected or annotated.
- [ ] `R/88` passes.

---

## 7. Anti-patterns

| Do not | Because |
|---|---|
| Test against `tests/fixtures/LDS_ADDRESS_HISTORY_Mailhot_V1.csv` as-is | One row, three columns, no `ADDRESS_ZIP5` — it cannot exercise this change |
| Let `read_csv` guess the ZIP column types | It typed `ADDRESS_ZIP9` as `dbl`; leading zeros vanish |
| Estimate the new coverage from the 40,005 record counts | Encounter-level effects depend on which records match which dates — re-run |
| Overwrite the 2026-08-17 outputs | Same-date filenames; the before/after is the evidence |
| Silently supersede the Phase 145/146/147 conclusions | They read as current; annotate them |
| Change tier order or the `0000` guard | This phase changes what ZIP5 is, not what the tiers do |
| Report `zip5_modal > 0` as a bug | It is the tier working for the first time since Phase 139 |
| Proceed with Phase 147 before this re-run | Its population is defined by what Tier 2 leaves behind |

---

## 8. What to report

- The 2×2 from §0 and what it means: 96.9% of address records carry a usable ZIP5, not 50.1%.
- Post-fix coverage per index, replacing the 77.7% ceiling.
- Whether `zip5_modal` fired, and how many rows remain `zip5_no_zip9` — the number that decides
  whether a centroid crosswalk is worth pursuing at all.
- That R/115's delivered workbook was computed on the old ZIP5 and has been re-issued.
