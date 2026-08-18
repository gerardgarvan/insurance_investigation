# Phase 148: zip5_centroid_zip9_crosswalk — Context

**Gathered:** 2026-08-18
**Status:** Ready for planning
**Source:** PRD Express Path (148-CONTEXT-centroid.md)

<domain>
## Phase Boundary

Build the Tier 3 ZIP9 imputation crosswalk: `data/reference/zip5_centroid_zip9_crosswalk.csv`. This phase picks one representative ZIP+4 per ZIP5 using ZCTA centroid proximity, wire it into `approximate_zip9()` as Tier 3, and re-runs R/116 to measure encounters gained.

**Gating dependency:** Must read `zip5_no_zip9` from `147-DISCOVERY.md` §4 before any code. If Tier 2 (modal) absorbed all ZIP5-only rows, the crosswalk has no population and this phase closes without building anything.

**Tier ordering:** Tier 2 (modal — free, uses cohort-observed ZIP9s) gets first refusal. Tier 3 sees only the residue Tier 2 could not resolve.

**Post-Phase 147 population:**
| ADDRESS_ZIP5 | ADDRESS_ZIP9 | records | share |
|---|---|---|---|
| yes | yes | 19,741 | 49.3% |
| **yes** | **no** | **18,731** | **46.8%** — Tier 2+3 target |
| no | yes | 291 | 0.7% |
| no | no | 1,242 | 3.1% |
| | | **40,005** | |

The 77.7% ceiling from Phases 145–147 is void — it reflected ADDRESS_ZIP9 coverage (50.1%), not ZIP availability (96.9%). Use post-147 figures from `147-DISCOVERY.md` §4 exclusively.

</domain>

<decisions>
## Implementation Decisions

### D-01 — Gate: is there a population for Tier 3?
Read `zip5_no_zip9` from `147-DISCOVERY.md` §4:
- **0** → Do not build. Record outcome in `148-DISCOVERY.md` and close phase.
- **small** (< ~2,000 encounters) → Weigh cost of USPS/commercial API run vs. yield. May prefer §2 (ZIP5-level ADI summary) instead.
- **material** → Build it. Proceed to D-03.

Record the number and decision reasoning in `148-DISCOVERY.md` before any code.

### D-02 — Cheaper route if goal is ADI coverage
If the Neighborhood Atlas package includes a ZIP+4-keyed file (Phase 146 D-05), build instead:
`data/reference/zip5_adi_summary.csv` with columns: `ZIP5, adi_natrank_median, adi_natrank_p25, adi_natrank_p75, n_zip9_in_zip5, vintage, method, source`.

R/116 gains `adi_natrank_zip5_median` — never merged with `adi_natrank` (ZIP9-level). Two distinct measurements, two columns.

If D-01 says "small" or "material" AND the goal is ADI coverage (not a general ZIP9 capability), prefer this route and skip D-03.

### D-03 — Crosswalk route (only if building the full crosswalk)
| Route | Mechanism | Obstacle |
|---|---|---|
| **D-03a** USPS Web Tools / Address Validation | Reverse-geocode ZCTA centroid, read returned ZIP+4 | Registration + bulk-use terms; must confirm redistribution rights; ~41,000 ZCTAs needs checkpoint/resume |
| **D-03b** Commercial ZIP+4 centroid file | Coordinates per ZIP+4, nearest to ZCTA centroid | Purchase or UF institutional licence — ask Erin first |
| **D-03c** ADI ZIP+4 list as candidate universe | Valid ZIP+4s per ZIP5, no coordinates | "Nearest centroid" uncomputable; must NOT be labelled `zip5_centroid`; needs distinct `zip9_source` value `zip5_representative` |

Already ruled out: Census Geocoder (returns ZIP5 only), HUD USPS crosswalk (maps to tract/county, not ZIP+4).

### D-04 — Three coverage numbers to report
(a) crosswalk coverage: ZIP5s resolved of those attempted  
(b) **cohort-relevant coverage** (lead figure): of ZIP5s in `zip5_no_zip9` rows, how many does the crosswalk cover  
(c) encounters resolved: after re-running R/116, `sum(enc$zip9_source == "zip5_centroid")`

### D-05 — Rural degradation threshold
Report `distance_m` quantiles by `ruca_category`. Set a named constant for the cutoff above which the row is dropped rather than emitted. A segment >20 km from a rural ZCTA centroid represents nothing.

### D-06 — Non-centroid labelling
If D-03c is used, add `zip5_representative` to `.classify_zip9_source()` and document the selection rule in `data/reference/README.md`. Labelling a non-geographic choice as `zip5_centroid` is the same class of error as the `paste0(ZIP5, "0000")` fabrication.

### Locked constraints
- Phase 146 D-05 (does Neighborhood Atlas publish a ZIP+4 file) must be answered — §2 and D-03c both depend on it.
- Build script: `R/118_build_centroid_crosswalk.R`. Follow `R/117_build_svi_zcta.R` and `R/146_stage_sdi_reference.R` conventions: explicit `col_types`, `here()`/`file.path()`, no `setwd`, no `read.csv`, no `data.table`.
- If D-03a: script must checkpoint and resume (rate-limited run over 41,000 ZCTAs will be interrupted).
- The `0000` guard in `approximate_zip9()` must remain unchanged.

### Claude's Discretion
- Wave structure and plan decomposition
- Whether Phase 146 D-05 check is a separate discovery plan or inline in the gate plan

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase context and gating
- `148-CONTEXT-centroid.md` (project root) — full phase spec including anti-patterns, §5 validation gates, schema
- `R/.planning/phases/147-read-address-zip5-retract-downstream-artefacts/147-SPEC.md` — Phase 147 spec; `zip5_no_zip9` produced by Phase 147 Plan 3 HiPerGator re-run

### Pipeline conventions (must follow)
- `R/117_build_svi_zcta.R` — reference build-script style
- `R/146_stage_sdi_reference.R` — second reference; both show col_types, here(), no setwd pattern
- `R/00_config.R` — path configuration
- `R/helpers/` — shared helpers including `approximate_zip9()` and `.classify_zip9_source()`

### Reference data landing zone
- `data/reference/README.md` — documents all staged reference files; update for any new file
- `data/reference/zip5_adi_summary.csv` (to be created if D-02 route chosen)
- `data/reference/zip5_centroid_zip9_crosswalk.csv` (to be created if D-03 route chosen)

### Downstream consumer
- `R/116` — consumes the crosswalk via `approximate_zip9()`; re-run needed after crosswalk is staged

### Validation
- §5 of `148-CONTEXT-centroid.md` — five blocking `stopifnot()` gates (character length, digit-only, ZIP5 prefix match, no 0000, uniqueness)

</canonical_refs>

<specifics>
## Specific Ideas

### Output schema (if building crosswalk)
`data/reference/zip5_centroid_zip9_crosswalk.csv`:
```
ZIP5           character(5), zero-padded
centroid_zip9  character(9), no hyphen
distance_m     numeric, metres from ZCTA centroid to chosen segment (NA for D-03c)
n_candidates   integer, ZIP+4s considered for that ZIP5
ruca_category  character, joined from staged RUCA file
vintage        character, e.g. "TIGER 2020 ZCTA + USPS AMS 2026-08"
method         character, exact route used, naming D-03a/b/c
source         character, citation and licence status
```

### Five blocking validation gates (§5)
```r
stopifnot(
  "centroid_zip9 must be 9 characters"     = all(nchar(out$centroid_zip9) == 9L),
  "centroid_zip9 must be digits only"      = all(grepl("^[0-9]{9}$", out$centroid_zip9)),
  "centroid_zip9 must start with its ZIP5" = all(substr(out$centroid_zip9, 1, 5) == out$ZIP5),
  "no synthetic 0000 add-ons"              = !any(grepl("0000$", out$centroid_zip9)),
  "ZIP5 must be unique"                    = !any(duplicated(out$ZIP5))
)
```

### Coverage reporting template (D-04)
```r
# (a) crosswalk coverage
cat(sprintf("ZIP5s resolved: %d of %d attempted\n", nrow(out), n_attempted))
# (b) cohort relevance — LEAD WITH THIS
enc  <- readRDS("output/encounter_ses_index_<date>.rds")
need <- unique(enc$ZIP5[enc$zip9_source == "zip5_no_zip9" & !is.na(enc$ZIP5)])
cat(sprintf("ZIP5s needing Tier 3: %d | covered by crosswalk: %d\n", length(need), sum(need %in% out$ZIP5)))
# (c) encounters resolved
cat(sprintf("encounters gaining a ZIP9 via zip5_centroid: %d\n", sum(enc$zip9_source == "zip5_centroid", na.rm = TRUE)))
```

</specifics>

<deferred>
## Deferred Ideas

- D-03b commercial licence path: deferred until Erin confirms whether UF holds an institutional licence.
- D-03a USPS API path: deferred until D-01 establishes a material population and D-02 is declined.
- Full R/88 smoke-test expansion: not explicitly scoped here; R/88 must pass, existing assertions sufficient unless new functions added.

</deferred>

---

*Phase: 148-148-context-centroid*
*Context gathered: 2026-08-18 via PRD Express Path (148-CONTEXT-centroid.md)*
