# 148-DISCOVERY.md — Centroid ZIP9 Crosswalk Tier 3: Gate and Route Decisions

Produced by Phase 148 Plan 1 (wave 1) — local (no HiPerGator required).
This document records all D-0x decisions with evidence before any build code runs.

---

## §0 — Gate (D-01): Should Phase 148 build a centroid crosswalk?

**Measured value (source: 147-DISCOVERY.md §4, post-147-redo column, 2026-08-18):**

| zip9_source | encounters |
|---|---|
| `zip9_observed` | 1,516,469 |
| `zip5_modal` | 198,768 |
| `zip5_centroid` | 0 (no crosswalk staged yet) |
| **`zip5_no_zip9`** | **59,818** |
| `no_zip5` | 16,942 |
| `none` | 158,699 |

**Decision: BUILD.** Per the D-01 decision table in 148-CONTEXT.md, 59,818 encounters is
"material" → the phase proceeds to build a reference file.

**Reasoning:**

(a) The `zip5_no_zip9 = 59,818` figure is NOT a pre-existing artefact. An earlier Phase 148
run (post-148 wrong column in 147-DISCOVERY.md §4) showed `zip5_no_zip9 = 0`, but that was
caused by a missing third coalesce arm (`normalize_zip5_raw(ADDRESS_ZIP9)`) — corrected
by commit `2e79285` on 2026-08-18. The statement "Phase 147's centroid crosswalk has no
population to serve" made under that earlier reading was void and retracted in 147-DISCOVERY.md §4.

(b) 59,818 encounters represent ZIP5s where no cohort member ever had an observed ZIP9 in the
LDS_ADDRESS_HISTORY extract. Because no ZIP9 was ever present for those ZIP5s, Tier 2 (modal
ZIP9 from other records for the same patient) could not resolve them — modal requires at least one
ZIP9 to exist for the patient. These 59,818 encounters are genuinely unresolved at Tiers 1 and 2.

(c) At ~60K encounters, the cost of building a reference file (`zip5_adi_summary.csv`) using an
already-staged 478 MB source file (`neighborhood_atlas_zip9_adi.csv`) is warranted. No new data
acquisition is required; the build is a grouping operation on a file already on disk.

---

## §1 — Phase 146 D-05: Does the Neighborhood Atlas publish a ZIP+4-keyed ADI file?

**Decision: YES.**

**Evidence:** `data/reference/neighborhood_atlas_zip9_adi.csv` is already staged locally
(per `data/reference/README.md` D-05 section, recorded 2026-08-17). The file has been collated
from 23 state-level exports provided by the Neighborhood Atlas portal. Column layout:

- `ZIP9` (character, 9-digit, no hyphen) — the join key
- `ADI_NATRANK` (character — suppression codes possible: "GQ", "GQ-PH", "PH", "QDI")

Row count: **37,029,488** rows. File size: 478 MB. Status: staged locally and gitignored (per
project policy for large source files); must be scp'd to HiPerGator before Wave 2 runs.

This file IS joinable on ZIP9 directly. It IS the ZIP+4-keyed ADI file Phase 146 asked about.
Each row corresponds to one 9-digit ZIP+4 delivery segment with its ADI National Rank.

D-05 is answered: **yes**, the Neighborhood Atlas provides a per-ZIP+4 ADI file, and it is staged.

---

## §2 — D-02: Route A (centroid crosswalk) vs Route B (ZIP5-level ADI summary)?

**Decision: Route B — ZIP5-level ADI summary** (`data/reference/zip5_adi_summary.csv`).

**Reasoning:**

**Route B is preferred because the source file is already joinable on ZIP9 and no coordinates
are needed.** Specifically:

1. `neighborhood_atlas_zip9_adi.csv` already contains every ZIP9 with its `ADI_NATRANK`.
   A ZIP5-level summary requires only: group by `substr(ZIP9, 1, 5)`, compute median/p25/p75
   of the numeric `ADI_NATRANK`, count `n_zip9_in_zip5`. No coordinates, no geocoding, no
   additional licence beyond the already-staged file.

2. Route A (centroid crosswalk) is an indirect path: pick one representative ZIP+4 per ZCTA
   (nearest to the ZCTA centroid), then look up its ADI. This path requires:
   - A source of per-ZIP+4 coordinates (USPS, commercial, or inference from the centroid itself);
   - A selection rule for which of the N ZIP+4s in a ZCTA is the "representative" one;
   - A new `zip9_source` value (`"zip5_centroid"`) — which is already reserved in
     `approximate_zip9()` and would require that the output file satisfy the 5-character
     `centroid_zip9` validation gate in `utils_address.R`.
   Route A adds complexity with no analytical benefit for this cohort.

3. Route B is more defensible in a methods section. The output column
   `adi_natrank_zip5_median` reports the median ADI across all ZIP+4 delivery segments within
   the ZIP5 area, plus p25/p75 (IQR) as a spread measure. A single "representative" ZIP+4's
   ADI (Route A) is one draw from that same distribution — a less informative summary.

4. Route B has none of Route A's procurement obstacles:
   - No USPS API registration/bulk-use terms concern;
   - No commercial licence cost or procurement delay;
   - No need to ask Erin whether UF holds a coordinate file (D-03b).

5. The R/116 output column will be named `adi_natrank_zip5_median` — clearly distinct from
   `adi_natrank` (the ZIP9-level column populated at Tier 1). Two measurements, two columns,
   no naming collision, no conflation risk.

---

## §3 — D-03: Build route (applicable only if Route A chosen)

**Decision: D-03 NOT APPLICABLE.** Route B (§2) does not build a centroid crosswalk.

For the record, the three Route A sub-routes are ruled out for this phase:

- **D-03a** (USPS Web Tools bulk reverse-geocoding): ruled out — registration/bulk-use terms
  create redistribution risk; ~41,000 ZCTAs would require checkpoint/resume logic; not built.
- **D-03b** (commercial coordinate file): ruled out — purchase or UF institutional licence
  not confirmed; not pursued.
- **D-03c** (use ADI ZIP+4 list as universe, no centroid): ruled out as a Route A variant.
  Route B uses the same ADI ZIP+4 list, but via aggregation (group-by, not selection), so
  there is no "representative" ZIP+4 and no `centroid_zip9` column is produced.

`R/118_build_centroid_crosswalk.R` (the build script described in 148-CONTEXT.md) is
**repurposed** to build `zip5_adi_summary.csv` via Route B. The file it produces does not
match the `zip5_centroid_zip9_crosswalk.csv` schema in 148-CONTEXT.md §5; it matches the
`zip5_adi_summary.csv` schema described in §2 of this document.

---

## §4 — zip9_source for Route B encounters

**Route B does not select one representative ZIP+4.** It aggregates all ZIP+4s within a ZIP5
into a median ADI score. Therefore:

- The `zip9_source` column value written into `encounter_ses` for encounters resolved via
  Route B **cannot be `"zip5_centroid"`** (which implies a single representative ZIP+4 was
  selected and a `centroid_zip9` was filled in).
- No new ZIP9 is imputed at all — Route B resolves ADI coverage, not ZIP9 imputation.
  The encounter's ZIP9 field remains NA; only the ADI column is populated.
- The value `"zip5_representative"` must be added to `.classify_zip9_source()` in
  `R/utils/utils_address.R` to label these rows distinctly if/when ZIP9 imputation is
  desired. This is a Wave 3 code change tracked in 148-03-PLAN.md.
- The 0000 guard in `approximate_zip9()` — which rejects any crosswalk entry whose
  `centroid_zip9` ends in `0000` — remains unchanged. Route B does not interact with it.

---

## §5 — D-04 figures (measured 2026-08-19, HiPerGator re-run after fix(148) commit)

D-04 reporting requirements (from 148-CONTEXT.md §4):

- **(a)** ZIP5s resolved (rows in `zip5_adi_summary.csv`): **20,950**
  Source: R/118 run (148-02-SUMMARY.md); all 5 stopifnot gates passed.

- **(b)** Of the 36,953 unique (patient, date) records needing Tier 3, how many does the
  summary cover (lead figure): **30,725 of 36,953 = 83.2%**
  Source: `approximate_zip9()` breakdown — `zip5_representative: 30,725`,
  `zip5_no_zip9: 6,228` (36,953 total = 30,725 + 6,228).
  The 36,953 is itself the residue after Tier 2 (modal) resolved 111,599 of 148,552
  records that had ZIP5 present and ZIP9 absent.

- **(c)** Encounters gaining `zip5_representative` in the final encounter_ses output:
  **47,036** (final zip9_source table after many-to-one join back to encounter level).
  Source: `logs/148_r116_rerun.log` — `zip5_representative: 47,036`.

**Bug note:** The initial 148-03 run (commit b7a5e52) reported `zip5_representative: 0`
because `isTRUE(has_adi_zip5)` is not vectorized — it evaluated the entire column as a
single scalar FALSE inside `case_when`, so the branch never fired. Fixed in commit 5b65d56
(`fix(148): replace isTRUE(has_adi_zip5) with bare has_adi_zip5 in case_when`). The
`adi_natrank_zip5_median` column was always being populated correctly (84.1% ADI coverage
was already correct); only the `zip9_source` classification was wrong.

**zip9_source final breakdown (encounter-level, 2026-08-19):**

| zip9_source | encounters |
|---|---|
| `zip9_observed` | 1,516,469 |
| `zip5_modal` | 198,768 |
| `zip5_representative` | **47,036** |
| `zip5_no_zip9` | 12,782 |
| `no_zip5` | 16,942 |
| `none` | 158,699 |

**SES coverage (post-fix):**

| Index | Coverage |
|---|---|
| SDI | 90.2% |
| ADI (ZIP9-level) | 84.1% |
| SVI | 90.2% |
| RUCA | 91.0% |

---

## §6 — R/118 re-run after fix (118-FIX-PLAN.md steps 6–7, 2026-08-19)

Script run: `Rscript R/118_build_zip5_adi_summary.R` on HiPerGator after `git pull` of commits
`6a9eb6e` / `96c32a9` / `d9caad7` (rename + gate fix + coverage floor).

**Summary output (`zip5_adi_summary.csv`):**

- ZIP5s in summary (rows): **20,950** (unchanged from §5 — floor suppresses values to NA, not rows)
- ZIP5s with a non-NA median: **14,688** (20,950 − 6,262 floor-suppressed)
- ZIP5s suppressed by coverage floor (ADI_COVERAGE_FLOOR = 0.50): **6,262**

**Denominator basis (Step 5 finding):**

The Atlas source column is `BENE_ZIP_CD` — beneficiary-based. The denominator for each ZIP5's
median is ZIP+4 segments present in the Neighborhood Atlas file, which covers Medicare
beneficiary locations, **not** all USPS delivery segments in a ZIP5. This is recorded in the
`METHOD` constant in `R/118_build_zip5_adi_summary.R` and will appear in the `method` column
of `zip5_adi_summary.csv`.

**Florida coverage (FL ZIPs 320xx–349xx):**

- Florida ZIP5s in summary: **1,448**
- Florida ZIP5s with a non-NA median: **914**

**Cohort ZIP5 coverage (lead figure):**

- Cohort ZIP5s needing coverage: **1,940**
- In summary: **1,639** (84.5%)
- With a non-NA median: **1,521** (78.4%) ← **lead figure**

**Decision:** Florida is present. 1,521 of 1,940 cohort ZIP5s have a usable median ADI —
sufficient to proceed with wiring `adi_natrank_zip5_median` into R/116 in a separate plan.
All four validation gates passed. `zip5_adi_summary.csv` written.

---

## §7 — R/116 re-run confirming adi_natrank_zip5_median wiring (2026-08-20)

Run: `Rscript R/116_encounter_ses_index.R` on HiPerGator after quick task `260820-fap`
(commit `584eb56`). All five coverage lines printed; RDS and xlsx written for run date 20260820.

**Coverage summary (1,950,696 encounter rows):**

| Index | Coverage |
|---|---|
| SDI | 90.2% |
| ADI (ZIP9-level) | 84.1% |
| **ADI ZIP5 median (new)** | **87.7%** |
| SVI | 90.2% |
| RUCA | 91.0% |

The 3.6 pp gain (87.7% vs 84.1%) comes from the 47,036 `zip5_representative` encounters
that had no ZIP9 (so `adi_natrank` = NA) but did have a ZIP5 in `zip5_adi_summary.csv`.
Phase 148 D-04(b)/(c) figures confirmed: `zip5_representative: 47,036` encounters in the
encounter-level output. Wiring is complete; no further action required for this phase.
