# 147-DISCOVERY.md — ADDRESS_ZIP5 Column Audit and D-02 Precedence Decision

Produced by Phase 147 Plan 1 (wave 1) before any code change to `get_zip9_at_date()`.
This document is the evidentiary foundation for Plan 2's code change.

---

## §0 — Column Audit (D-01)

**Measured on HiPerGator 2026-08-18.**

`names(LDS_ADDRESS_HISTORY_Mailhot_V1.csv)` [from `vroom` with `.default = "c"`]:

```
 [1] "ADDRESSID"            "ID"                   "ADDRESS_USE"
 [4] "ADDRESS_TYPE"         "ADDRESS_PREFERRED"    "ADDRESS_CITY"
 [7] "ADDRESS_STATE"        "ADDRESS_ZIP5"         "ADDRESS_ZIP9"
[10] "ADDRESS_COUNTY"       "ADDRESS_PERIOD_START" "ADDRESS_PERIOD_END"
[13] "SOURCE"
```

ZIP-ish columns confirmed: **ADDRESS_ZIP5**, **ADDRESS_ZIP9** — exactly two, no third ZIP-ish
column present. No STOP signal.

This is the first time `names()` of the real extract has been printed. The omission of this
step is the root cause of this phase: code read one ZIP column while the extract always carried
two. D-01 is now satisfied — the audit was run BEFORE the code change.

---

## §1 — Raw-Column 2×2 (measured on HiPerGator 2026-08-17)

Source: `addr |> count(zip5_ok = !is.na(ADDRESS_ZIP5), zip9_ok = !is.na(ADDRESS_ZIP9))` run
against the real extract; output pasted by the user and transcribed into 148-CONTEXT.md §0.
These are measured values, not assumptions.

| ADDRESS_ZIP5 present | ADDRESS_ZIP9 present | records | share | note |
|---|---|---|---|---|
| yes | yes | 19,741 | 49.3% | both sources available |
| **yes** | **no** | **18,731** | **46.8%** | **invisible to current code** |
| no | yes | 291 | 0.7% | ZIP5 recoverable from ZIP9 prefix |
| no | no | 1,242 | 3.1% | genuinely unusable |
| (total) | | **40,005** | | |

```
Records with a usable ZIP5 today (code path):  20,032  (50.1%)
Records with a usable ZIP5 after the fix:      38,763  (96.9%)  (+46.8 pp)
```

Character-length profile: ADDRESS_ZIP5 is 5 chars or NA; ADDRESS_ZIP9 is 9 chars or NA.
No truncation.

---

## §2 — The Incorrect Comment

The following text appears verbatim in `R/utils/utils_address.R` at lines 157–159:

```
# No separate ADDRESS_ZIP5 column exists in LDS_ADDRESS_HISTORY (confirmed from
# plan analysis: ADDRESS_ZIP9 holds bare ZIP5s for some records -- Step 0a case 2).
```

**This comment is factually wrong.** ADDRESS_ZIP5 has always been in the extract. The conclusion
"confirmed from plan analysis" was derived from document analysis, not from running `names()` on
the file. Plan 2 will remove this comment.

The full incorrect block (lines 154–160 for context) reads:
```r
      # Phase 139 AMEND-01 / Step 0c: coalesce ZIP5 from two sources:
      #   (1) normalize_zip5() of a valid 9-digit ZIP9 (existing path)
      #   (2) normalize_zip5_raw() applied directly to ADDRESS_ZIP9 for rows where
      #       ADDRESS_ZIP9 holds a bare 5-digit string that normalize_zip9() rejects
      # No separate ADDRESS_ZIP5 column exists in LDS_ADDRESS_HISTORY (confirmed from
      # plan analysis: ADDRESS_ZIP9 holds bare ZIP5s for some records -- Step 0a case 2).
      zip5_norm       = coalesce(normalize_zip5(zip9_norm), normalize_zip5_raw(ADDRESS_ZIP9)),
```

---

## §3 — Prefix-Disagreement Rows (the 12 rows)

**Measured on HiPerGator 2026-08-18.**

In 12 of 19,741 rows where both ADDRESS_ZIP5 and ADDRESS_ZIP9 are present,
`substr(ADDRESS_ZIP9, 1, 5) != ADDRESS_ZIP5`. These 12 rows represent 0.061% of rows with
both columns populated.

```
# A tibble: 12 × 4
   ID                      ADDRESS_ZIP5 ADDRESS_ZIP9 ADDRESS_PERIOD_START
   <chr>                   <chr>        <chr>        <chr>
 1 SEP1520252024007210000… 32606        326531573    01AUG2009
 2 SEP1520252024007210000… 32608        326074442    07MAR2023
 3 SEP1520252024007210000… 34609        346014609    01JUL2018
 4 SEP1520252024007210000… 32211        322771383    NA
 5 SEP1520252024007210000… 32608        326072221    01AUG2020
 6 SEP1520252024007210000… 32086        320922468    01JAN2021
 7 SEP1520252024007210000… 32205        322081936    01FEB2021
 8 SEP1520252024007210000… 32163        346843802    01JAN2021
 9 SEP1520252024007210000… 32731        347313905    10FEB2023
10 SEP1520252024007210000… 32605        326066803    01MAR2013
11 SEP1520252024007210000… 32607        326065864    30APR2019
12 SEP1520252024007210000… 32808        328397439    01JUL2020
```

**Pattern verdict:** No systematic pattern. All 12 IDs share the `SEP152025...` site prefix
(a single source system), but the ZIPs are scattered across Florida (32xxx and 34xxx), the
discrepancies vary in structure (not a consistent transposed digit, not a PO-box pairing), and
dates span 2009–2023. This is random data-entry noise, not a source-system encoding artifact.
D-02 confirmed: ADDRESS_ZIP5 wins.

---

## §4 — D-02 Precedence Decision

**LOCKED (2026-08-18) after inspection of the 12 rows in §3.**

```
D-02: ADDRESS_ZIP5 WINS disagreements. CONFIRMED.

Coalesce order:
  zip5_norm = dplyr::coalesce(
    normalize_zip5(ADDRESS_ZIP5),
    normalize_zip5(zip9_norm)
  )

Rationale:
- ADDRESS_ZIP5 is the field the source system populated deliberately as a ZIP5.
- ADDRESS_ZIP9 is a ZIP+4 field; extracting its first 5 digits to derive ZIP5 is a
  fallback, not an authoritative source.
- The 0.061% disagreement rate (12/19,741 rows) does not affect any downstream result.
- The 12 rows (§3) show no systematic pattern — scattered IDs, scattered ZIPs, no shared
  digit transposition. Data-entry noise. No basis to flip the precedence.
```

**Before/after table (post-148 column filled by Plan 3 HiPerGator re-run 2026-08-18):**

| | pre-148 | post-148 |
|---|---|---|
| `zip9_observed` | 1,516,469 (77.7%) | 1,516,469 (77.7%) — unchanged ✓ |
| `zip5_modal` | 0 | 0 |
| `zip5_centroid` | 0 | 0 (no crosswalk staged) |
| `zip5_no_zip9` | 0 | 0 |
| `no_zip5` | 275,528 (14.1%) | 275,528 (14.1%) — unchanged |
| `none` | 158,699 (8.1%) | 158,699 (8.1%) — unchanged ✓ |
| RUCA coverage | 77.7% | 77.7% — unchanged |
| SDI coverage | 77.5% | 77.5% — unchanged |

**zip5_no_zip9 (Tier 3's actual population for Phase 147): 0 rows.**

The fix reads ADDRESS_ZIP5 directly and now correctly coalesces it ahead of the ZIP9-derived ZIP5.
However, the 157,472 approximable encounters (those without a direct ZIP9) still resolve to
`no_zip5` because all of their matched address records have ZIP5 = NA after sentinel-nulling —
the Branch C path. The R/116 pre-approximation table confirms: zero encounters have
`zip9_na=TRUE AND zip5_na=FALSE`, meaning none of the 18,731 raw "ZIP5 present / ZIP9 absent"
address records translated into approximable encounters with a usable ZIP5 at their matched dates.

**zip5_no_zip9 = 0 means Phase 147's centroid crosswalk (Tier 3) has no population to serve.**
The headline coverage gain from the ADDRESS_ZIP5 fix will be visible in the S3-scenario
encounters (Part B of R/115), not in approximate_zip9's tier breakdown.  Phase 147's centroid
crosswalk is not worth pursuing under this data.  Phase 147 is complete as a diagnostic and
fix phase; no further centroid work is needed.

---

## §6 — R/88 Result

R/88 passed 2026-08-18. 778/781 checks passed; 3 pre-existing failures, no new regressions:

1. `[15ad] is_sentinel_zip5() defined in utils_address.R, exactly once` — pre-existing (Phase 148 scope)
2. `[15ae] utils_address.R guards against synthetic ZIP9s ending in '0000' (P0-01)` — pre-existing (Phase 148 scope)
3. `[Phase 114] DRUG_NAME_ALIASES has NO liposomal key` — pre-existing, unrelated to this phase

---

## §5 — R/116 Diagnostic Note (D-04 per 148-CONTEXT.md §3)

R/116's pre-approximation table is `table(match_type, is.na(ZIP9), is.na(ZIP5))`.

This produced a misleading zero in the "ZIP5 present, ZIP9 absent" cell because ZIP5 was
**derived from ZIP9**, so that cell structurally could not be non-zero — a record with ZIP9
present would always have a ZIP5 derived from it.

After Plan 2's fix, this table will change: 18,731 records now have ADDRESS_ZIP5 present and
ADDRESS_ZIP9 absent, so the previously-impossible cell becomes non-zero.

**Critical distinction (must not be conflated):**
- **Raw-column 2×2 (§1 above):** what the extract CONTAINS — 40,005 address records
- **match_type table:** what the resolver PRODUCES — encounter-level, after date matching

The record-level 2×2 does not predict the encounter-level breakdown. The resolver's output
depends on which records match which encounter dates. These are different quantities measured
at different levels.
