# Phase 148 Context — Centroid ZIP9 Crosswalk (Tier 3)

Source: `148-CONTEXT-centroid.md` (project root). Re-gated 2026-08-18 after Phase 147-redo
measured `zip5_no_zip9 = 59,818` (was previously recorded as 0 due to a missing coalesce arm —
see `147-DISCOVERY.md` §4 retraction). Phase 148 was previously closed with a plan that said
"no population"; that plan is void.

---

## Gate value (now known)

| | value | source |
|---|---|---|
| `zip5_no_zip9` (Tier 3 population) | **59,818 encounters** | `147-DISCOVERY.md` §4 post-147-redo column |
| `zip5_modal` | 198,768 | same |
| `no_zip5` | 16,942 | same |
| `none` | 158,699 | same — unchanged |
| `zip9_observed` | 1,516,469 | same — unchanged |

Per `148-CONTEXT-centroid.md` D-01: 59,818 is **material** → the phase proceeds to build.

---

## D-01 — Decision table (from spec)

| `zip5_no_zip9` | Reading | Action |
|---|---|---|
| 0 | Tier 2 absorbed everything | Do not build |
| small (< ~2,000) | Thin residue | Weigh cost |
| **material** | Real population | **Build — §3 onward** |

59,818 is material. Record the decision and reasoning in `148-DISCOVERY.md` before any code.

---

## D-02 — Centroid crosswalk vs ZIP5-level ADI summary

Two routes exist if the goal is ADI coverage:

**Route A — Centroid crosswalk** (`data/reference/zip5_centroid_zip9_crosswalk.csv`):
Pick one representative ZIP+4 per ZCTA (nearest to the ZCTA centroid), then look up its ADI.
Requires coordinates + a way to map ZCTA centroids to ZIP+4.

**Route B — ZIP5-level ADI summary** (`data/reference/zip5_adi_summary.csv`):
If Neighborhood Atlas publishes a ZIP+4-keyed file, summarise ADI across all ZIP+4s within each
ZIP5. No coordinates. No geocoding. No extra licence beyond the ADI file. More defensible:
a median + IQR states the distribution; a single representative ZIP+4's ADI is one draw.
R/116 gains `adi_natrank_zip5_median` — distinct from `adi_natrank` (ZIP9-level).

**Phase 146 D-05 is still open:** does the Neighborhood Atlas publish a ZIP+4-keyed file?
If yes, Route B may be preferred. The planner should answer this before choosing.

---

## D-03 — Crosswalk build routes (if Route A chosen)

| Route | Mechanism | Obstacle |
|---|---|---|
| **D-03a** USPS Web Tools | Reverse-geocode ZCTA centroid → ZIP+4 | Registration; bulk-use/redistribution terms; ~41,000 ZCTAs needs checkpoint/resume |
| **D-03b** Commercial file | Coordinates per ZIP+4; nearest to ZCTA centroid | Purchase or institutional licence — **ask Erin whether UF holds one** |
| **D-03c** ADI ZIP+4 list | Valid ZIP+4s per ZIP5, no coordinates | Not a centroid method; needs `zip9_source = "zip5_representative"`, not `zip5_centroid` |

Already ruled out: Census Geocoder (returns ZIP5 only), HUD USPS crosswalk (ZIP5→tract/county, not ZIP+4).

---

## Schema (if building crosswalk)

`data/reference/zip5_centroid_zip9_crosswalk.csv`:
```
ZIP5           character(5), zero-padded
centroid_zip9  character(9), no hyphen
distance_m     numeric, metres from ZCTA centroid to chosen segment (NA for D-03c)
n_candidates   integer, ZIP+4s considered
ruca_category  character, joined from staged RUCA file
vintage        character, e.g. "TIGER 2020 ZCTA + USPS AMS 2026-08"
method         character, D-03a/b/c
source         character, citation and licence status
```

Build script: `R/118_build_centroid_crosswalk.R`. Follow R/117 conventions.
If D-03a: must checkpoint and resume.

---

## Validation gates (all blocking — from spec §5)

```r
stopifnot(
  "centroid_zip9 must be 9 characters"     = all(nchar(out$centroid_zip9) == 9L),
  "centroid_zip9 must be digits only"      = all(grepl("^[0-9]{9}$", out$centroid_zip9)),
  "centroid_zip9 must start with its ZIP5" = all(substr(out$centroid_zip9, 1, 5) == out$ZIP5),
  "no synthetic 0000 add-ons"              = !any(grepl("0000$", out$centroid_zip9)),
  "ZIP5 must be unique"                    = !any(duplicated(out$ZIP5))
)
```

The 0000 guard in `approximate_zip9()` must not be weakened.

---

## Reporting requirements (D-04)

Three numbers, in order:
- **(a)** ZIP5s resolved (crosswalk coverage)
- **(b)** of the ZIP5s in `zip5_no_zip9` rows, how many does the crosswalk cover — **lead with this**
- **(c)** encounters gaining a ZIP9 via `zip5_centroid` after re-running R/116

Rural degradation (D-05): report `distance_m` quantiles by `ruca_category`; set a named cutoff
above which rows are dropped, not emitted.

---

## Acceptance criteria (from spec §7)

- [ ] `zip5_no_zip9 = 59,818` recorded in `148-DISCOVERY.md` with D-01 decision (build).
- [ ] Phase 146 D-05 answered (Neighborhood Atlas ZIP+4 file availability).
- [ ] D-02 recorded: centroid crosswalk or ZIP5-level ADI summary, with reasoning.
- [ ] If building: D-03 route chosen, licence status confirmed.
- [ ] `R/118_build_centroid_crosswalk.R` committed; checkpoint/resume if D-03a.
- [ ] All five §5 validation gates present and passing.
- [ ] `distance_m` quantiles by RUCA; cutoff as named constant.
- [ ] D-04 figures (a), (b), (c) all reported; (b) leads.
- [ ] If D-03c: `zip9_source = "zip5_representative"`, not `zip5_centroid`.
- [ ] The 0000 guard in `approximate_zip9()` unchanged.
- [ ] R/116 re-run; new coverage recorded against post-147-redo figures.
- [ ] `R/88` passes.

---

## Anti-patterns

| Do not | Because |
|---|---|
| Reuse the 77.7% ceiling | Void since Phase 147 — it was ADDRESS_ZIP9 coverage (50.1% of records), not ZIP availability (96.9%) |
| Cite "resolves 0 encounters" | That was a diagnostic artefact from the missing coalesce arm |
| `paste0(ZIP5, "0000")` or any constant suffix | Not a delivery segment; the loader guard rejects it |
| Label D-03c as `zip5_centroid` | No coordinates; needs its own `zip9_source` value |
| Start build before D-03 route + licence settled | Prevents committing the file; Phase 146 lesson |
| Report crosswalk coverage as cohort coverage | D-04(a) can be high while D-04(b) is near zero |
| Emit rural rows at any distance | 20 km from centroid attaches an unrelated neighbourhood's ADI |
