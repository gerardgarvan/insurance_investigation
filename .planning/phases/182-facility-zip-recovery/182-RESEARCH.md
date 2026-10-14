# Phase 182: Facility ZIP Recovery — Research

**Researched:** 2026-10-14
**Domain:** R/122 encounter distance pipeline — facility ZIP gap diagnosis and fill
**Confidence:** HIGH (all findings from direct source-code inspection; no external library queries required)

## Summary

Phase 182 is a targeted code-and-data surgery phase. The goal is to recover as many of the 581
MISS-01 group (b) patients as possible by filling missing facility ZIPs in R/122 using an
unambiguous same-FACILITYID consensus rule, then re-running R/122 → R/179 → R/180.

The fill logic does not exist yet. A new helper `R/utils/utils_facility_zip.R` must be written
and sourced inside R/122 after `R/00_config.R`. The two relevant columns — `FACILITYID` and
`SOURCE` — are not currently selected in R/122 Section 3 and must be added. The rest of R/122's
architecture (centroid resolution in Section 6, KEY sheet in Section 12, dated RDS output in
Section 2) is already well-structured for the additions.

R/179 already supports explicit RDS pinning via `R179_R122_RDS` environment variable. R/180
needs the same treatment (checked via context). All before/after comparison numbers are read
from workbook sheets by exact label at runtime — same pattern as Phase 181.

**Primary recommendation:** Build `utils_facility_zip.R` as a standalone pure helper first (no
file I/O, unit-testable), insert the fill step between Section 3 and the
`compute_encounter_distance()` call in Section 4, guard with
`CONFIG$facility_zip_fill` toggle, and produce the diagnostic workbook before committing to a
re-run.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Fill key = `SOURCE + FACILITYID` (never match across SOURCE).
- **D-02 (Tier 1 — primary fill):** Fill if and only if all encounters sharing that
  `(SOURCE, FACILITYID)` key with a valid `FACILITY_LOCATION` have exactly one distinct
  normalized ZIP5, with ≥ 3 supporting encounters. Any disagreement → no fill.
- **D-03 (Sensitivity tier — reported, not used in primary re-run):** Modal ZIP5 with ≥ 95%
  share and ≥ 10 supporting encounters. Report recovery under this rule but do not apply to
  the R/122 RDS used for R/179/R/180 re-run.
- **D-04:** No fill from fuzzy FACILITY_LOCATION text matching.
- **D-05:** Every encounter gets a `facility_zip_source` column:
  `observed` / `filled_tier1` / `not_filled`. FACILITYID keys with > 1 distinct ZIP listed as
  ambiguous with counts in B_facility_table.
- **D-06:** `FACILITYID` and `SOURCE` added to the R/122 encounter pull (Section 3 select).
- **D-07:** Fill logic lives in new helper `R/utils/utils_facility_zip.R`.
- **D-08:** Fill step guarded by `CONFIG$facility_zip_fill` (default `TRUE`). When `FALSE`,
  R/122 runs exactly as before.
- **D-09:** R/122 writes a new dated RDS. The 20261013-era RDS is never overwritten.
- **D-10:** Fill counts recorded in R/122 KEY sheet.
- **D-11:** zip_not_in_db diagnosis: format issues → existing normalizers; centroid-table gaps
  → check Phase 144/148 crosswalk; do not add centroids from undocumented sources.
- **D-12:** Patient-side zip_not_in_db entries: ZIP3 + count only in output artifacts.
- **D-13–D-19:** Workbook structure (KEY · A_status_summary · B_facility_table · C_zip_not_in_db · QC).
- **D-20–D-21:** `182-RECOVERY.md` script-generated; required content enumerated.
- **D-22:** R/179 reads R/122 RDS via `R179_R122_RDS` explicit override. Same for R/180.
- **D-23:** Re-running R/181 is out of scope.
- **D-24:** All pinned file paths recorded in Phase 182 KEY and 182-SUMMARY.md.
- **D-25:** Interactive R on HiPerGator (`module load R/4.5`); `source(..., local = new.env(parent = globalenv()))`.
- **D-26:** Script names: `R/utils/utils_facility_zip.R` (new); R/122 modified in place. Register in R/39 and SCRIPT_INDEX.

### Claude's Discretion

- Whether to store `facility_zip_source` in the RDS or only in the diagnostic workbook.
- Minor formatting within workbook sheets (column widths, freeze panes) — follow Phase 179/180/181 precedent.
- Whether to implement D-19 (ZIP stability by year) — only if it fits cleanly.

### Deferred Ideas (OUT OF SCOPE)

- None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FZIP-01 | Diagnose 581 MISS-01 group (b) patients: which facilities/ZIPs responsible, whether FACILITY_LOCATION or FACILITYID fill is available, whether centroid-table additions cover zip_not_in_db | Facility fill logic design in Standard Stack; zip_not_in_db diagnosis path via existing normalizers and centroid tables documented |
| FZIP-02 | Apply unambiguous fixes in R/122 (or helpers only); re-run R/122 → R/179 → R/180; produce before/after recovery report with updated OR and 95% CI | R/122 modification points identified (Section 3 select, Section 4 fill insertion, Section 12 KEY); R/179 RDS pinning pattern confirmed; workbook/recovery report architecture documented |
</phase_requirements>

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | project renv | Data manipulation, fill logic, group_by/summarise | Project convention; named-predicate style |
| openxlsx2 | project renv | Workbook output with UF colors | Established pattern in R/179, R/180, R/181 |
| glue | project renv | Log messages and file name construction | Project standard |
| vroom | project renv | CSV loading with typed columns | Project standard; already used in R/122 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| stringr | project renv | ZIP normalization (already in utils_address.R) | Already available; used inside normalize_zip5_raw() |

No new packages are needed. All required functionality is in the existing project renv and utils layer.

**Installation:** None. Use existing renv snapshot.

---

## Architecture Patterns

### Existing R/122 Section Flow (reference for where to insert)

```
Section 1:  library() + source(R/00_config.R) + source(utils_zip_calendar.R)
Section 2:  Constants + probe gates (ZCTA, ZIP9 crosswalk, DuckDB)
Section 3:  Encounter pull via DuckDB → encounters_raw tibble
            ** ADD: FACILITYID, SOURCE to dplyr::select() **
Section 4:  build_patient_zip_calendar() + compute_encounter_distance()
            ** INSERT: facility ZIP fill step before compute_encounter_distance() **
            ** After fill, zip5_facility column is already populated for observed + filled rows **
Section 5:  enc_zip9 / enc_zip5 normalization
Section 6:  Centroid resolution (zip_not_in_db diagnosis lives here conceptually)
Section 7:  Haversine distance + distance_basis
Section 8+: Assembly, summary stats
Section 12: KEY sheet builder
            ** ADD: fill count metrics (D-10) **
```

### New Helper: utils_facility_zip.R

```r
# build_facility_zip_lookup(enc_raw):
#   Input:  tibble with columns SOURCE, FACILITYID, enc_zip_raw (raw FACILITY_LOCATION)
#   Logic:
#     1. Normalize enc_zip_raw via normalize_zip5_raw() → candidate_zip5
#     2. Group by (SOURCE, FACILITYID)
#     3. For each group: count distinct non-NA candidate_zip5 values, count supporting n
#     4. Tier 1: if n_distinct == 1 AND n_supporting >= 3 → fill_zip = that ZIP, fill_status = "filled_tier1"
#     5. Tier 1 disagree: n_distinct > 1 → fill_status = "ambiguous", fill_zip = NA
#     6. No donor: n_distinct == 0 → fill_status = "no_donor", fill_zip = NA
#     7. Sensitivity (reported only): modal_zip, modal_share, modal_n — computed but not applied
#   Output: tibble keyed on (SOURCE, FACILITYID) with columns:
#           fill_zip, fill_status, n_distinct_zips, n_supporting,
#           sensitivity_modal_zip, sensitivity_modal_share, sensitivity_modal_n
#
# apply_facility_zip_fill(enc_for_dist, lookup):
#   Left-join enc_for_dist on (SOURCE, FACILITYID);
#   where zip5_facility is NA AND fill_status == "filled_tier1" → zip5_facility = fill_zip;
#   add facility_zip_source column: "observed" | "filled_tier1" | "not_filled"
#   Returns enc_for_dist with zip5_facility filled and facility_zip_source added.
```

### Fill Insertion Point in R/122 Section 4

```r
# (existing) enc_for_dist <- encounters_raw %>%
#   dplyr::mutate(zip5_facility = normalize_zip5_raw(enc_zip_raw))

# ---- NEW FILL STEP ----
if (isTRUE(CONFIG$facility_zip_fill)) {
  fac_lookup <- build_facility_zip_lookup(enc_for_dist)
  enc_for_dist <- apply_facility_zip_fill(enc_for_dist, fac_lookup)
  message(glue(
    "  [facility_zip_fill] Tier 1 filled: {sum(enc_for_dist$facility_zip_source == 'filled_tier1')}  ",
    "ambiguous: {sum(fac_lookup$fill_status == 'ambiguous')}  ",
    "no_donor: {sum(fac_lookup$fill_status == 'no_donor')}"
  ))
} else {
  enc_for_dist <- enc_for_dist %>%
    dplyr::mutate(facility_zip_source = dplyr::if_else(
      !is.na(zip5_facility), "observed", "not_filled"
    ))
  message("  [facility_zip_fill] CONFIG$facility_zip_fill = FALSE -- no fill applied")
}
# ---- END FILL STEP ----

dist_result <- compute_encounter_distance(enc_for_dist, cal)
```

### R/179 Pinning (already implemented — use as-is)

```r
# From R/179_cbc_patient_year.R lines 148-156:
r122_override <- Sys.getenv("R179_R122_RDS", unset = "")
if (nzchar(r122_override)) {
  stopifnot("R179_R122_RDS file not found" = file.exists(r122_override))
  enc_dist_path <- r122_override; r122_pinned <- TRUE
} else {
  # auto-latest pickup (fallback)
}
```

To use the new RDS: `Sys.setenv(R179_R122_RDS = "/path/to/encounter_distance_YYYYMMDD.rds")`
before sourcing R/179. Confirm the same pattern exists in R/180 before planning the re-run step.

### Workbook Pattern (follow R/179/R/180/R/181 precedent)

- `openxlsx2` workbook; UF color palette from CONFIG.
- KEY sheet leftmost; QC sheet rightmost.
- `suppress_small()` (or equivalent `sup()`) for counts 1–10.
- Workbook filename: `output/182_facility_zip_diagnosis_YYYYMMDD.xlsx`.
- Sheet order: KEY · A_status_summary · B_facility_table · C_zip_not_in_db · QC.

### Anti-Patterns to Avoid

- **Do not use FACILITYID alone as fill key** — FACILITYID is not unique across OneFlorida+ SOURCE partners (D-01).
- **Do not apply the sensitivity tier fill to the primary RDS** — it goes in the workbook only (D-03).
- **Do not overwrite the 20261013-era RDS** — R/122 writes a new dated RDS; old one stays (D-09).
- **Do not hand-roll date-keyed ZIP lookups** — `compute_encounter_distance()` already handles patient-side ZIP; the new fill is only for the facility side.
- **Do not include 5-digit patient ZIPs in output** — ZIP3 + count only for patient-side zip_not_in_db (D-12).
- **Do not use `setwd()` or absolute paths** — use `here()` or CONFIG-relative paths (CLAUDE.md).
- **Do not use `data.table` syntax** — dplyr only (CLAUDE.md).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ZIP format normalization | Custom regex | `normalize_zip5_raw()` / `normalize_zip9()` in utils_address.R | Already handles edge cases (leading zeros, ZIP+4, garbage text) |
| Centroid lookup | Custom lat/lon table | `get_zip_centroid()` in utils_address.R | Vectorized, memoized, handles both ZIP5 and ZIP9 |
| Small-cell suppression | Custom if_else | `sup()` / `suppress_small()` from Phase 180 | Established project pattern |
| Workbook colors/styles | Manual hex values | `CONFIG$uf_colors` (or equivalent CONFIG palette) | Already defined; used in R/179/R/180/R/181 |
| R/179 RDS pinning | Custom file picker | `R179_R122_RDS` environment variable (already implemented in R/179) | Lines 148–156 of R/179 already handle this |

---

## Common Pitfalls

### Pitfall 1: FACILITYID collisions across SOURCE
**What goes wrong:** Two OneFlorida+ partners each have a FACILITYID "1234". Merging on FACILITYID alone assigns the wrong ZIP to one.
**Why it happens:** FACILITYID is partner-scoped, not globally unique in PCORnet CDM.
**How to avoid:** Fill key must be `(SOURCE, FACILITYID)` (D-01). utils_facility_zip.R groups by both.
**Warning signs:** If fill lookup has suspiciously large n_supporting counts for a single FACILITYID — likely cross-SOURCE collision.

### Pitfall 2: Applying fill to already-populated zip5_facility rows
**What goes wrong:** `apply_facility_zip_fill()` overwrites a valid observed ZIP with the lookup ZIP if the logic is not conditioned on `is.na(zip5_facility)`.
**How to avoid:** Fill only where `is.na(zip5_facility)` — observed rows keep `facility_zip_source = "observed"` and their original value.

### Pitfall 3: Overwriting the 20261013-era RDS
**What goes wrong:** R/122's `OUTPUT_RDS` uses `RUN_DATE <- format(Sys.Date(), "%Y%m%d")` — running on a new date automatically produces a new filename. However, if the run date matches a past run, it would overwrite.
**How to avoid:** D-09 is enforced by the dated filename. Verify the new run date differs from 20261013. The old RDS is retained as-is; do not delete it.

### Pitfall 4: facility_zip_source column not present in RDS causes R/179 to fail
**What goes wrong:** If `facility_zip_source` is added to `enc_for_dist` but dropped before the RDS write (or only kept in the workbook), R/179 may encounter a missing column if it ever references it.
**How to avoid:** Decide before coding whether `facility_zip_source` lives in the RDS or workbook only (Claude's discretion). Document the decision clearly; be consistent across the fill step, write step, and any downstream consumers.

### Pitfall 5: R/180 RDS pinning not verified before planning re-run
**What goes wrong:** R/179 has confirmed `R179_R122_RDS` pinning. If R/180 does not have an equivalent mechanism, the re-run silently picks up the old R/179 output (auto-latest), not the newly generated one.
**How to avoid:** Inspect R/180 source for its R/179 RDS input pattern before writing the re-run plan step. Confirm the variable name (likely `R180_R179_RDS` or equivalent).

### Pitfall 6: Before/after comparison using hard-coded numbers
**What goes wrong:** Numbers hard-coded from a prior workbook read become stale and mislead the report if the workbook is updated.
**How to avoid:** 182-RECOVERY.md must be script-generated (D-20) with workbook values read by exact label at runtime — same principle as Phase 181 D-10.

---

## Code Examples

### build_facility_zip_lookup() skeleton (utils_facility_zip.R)

```r
# Source: Phase 182 CONTEXT.md D-01 through D-05
build_facility_zip_lookup <- function(enc_raw) {
  # enc_raw must have: SOURCE, FACILITYID, enc_zip_raw
  stopifnot(all(c("SOURCE", "FACILITYID", "enc_zip_raw") %in% names(enc_raw)))

  enc_raw %>%
    dplyr::mutate(candidate_zip5 = normalize_zip5_raw(enc_zip_raw)) %>%
    dplyr::group_by(SOURCE, FACILITYID) %>%
    dplyr::summarise(
      n_total           = dplyr::n(),
      n_distinct_zips   = dplyr::n_distinct(candidate_zip5[!is.na(candidate_zip5)]),
      n_supporting      = sum(!is.na(candidate_zip5)),
      fill_zip          = dplyr::if_else(
                            n_distinct_zips == 1L & n_supporting >= 3L,
                            candidate_zip5[!is.na(candidate_zip5)][1],
                            NA_character_),
      fill_status       = dplyr::case_when(
                            n_distinct_zips == 1L & n_supporting >= 3L ~ "filled_tier1",
                            n_distinct_zips > 1L                       ~ "ambiguous",
                            TRUE                                       ~ "no_donor"),
      # Sensitivity tier (reported only; not applied to primary re-run)
      sensitivity_modal_zip   = names(which.max(table(candidate_zip5[!is.na(candidate_zip5)]))),
      sensitivity_modal_n     = max(tabulate(match(
                                  candidate_zip5[!is.na(candidate_zip5)],
                                  unique(candidate_zip5[!is.na(candidate_zip5)]))), 0),
      sensitivity_modal_share = sensitivity_modal_n / n_supporting,
      .groups = "drop"
    )
}
```

### CONFIG toggle addition (R/00_config.R)

```r
# Source: Phase 182 CONTEXT.md D-08
# Add to CONFIG list in R/00_config.R:
CONFIG$facility_zip_fill <- TRUE  # set FALSE to reproduce 20261013-era output exactly
```

### R/122 Section 3 select modification

```r
# Source: Phase 182 CONTEXT.md D-06
# Change:
dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE, enc_zip_raw = FACILITY_LOCATION)
# To:
dplyr::select(ID, ENCOUNTERID, ADMIT_DATE, ENC_TYPE,
              enc_zip_raw = FACILITY_LOCATION, FACILITYID, SOURCE)
```

### R/179 re-run with pinned RDS (HiPerGator interactive)

```r
# Source: Phase 182 CONTEXT.md D-22 + D-25; R/179 lines 148-156
Sys.setenv(R179_R122_RDS = "/path/to/output/encounter_distance_YYYYMMDD.rds")
source("R/179_cbc_patient_year.R", local = new.env(parent = globalenv()))
```

---

## Environment Availability

All execution is on HiPerGator (interactive R session). No new external dependencies.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R/4.5 | All scripts | ✓ (confirmed used in Phase 181) | 4.5 | — |
| DuckDB ENCOUNTER table | R/122 encounter pull | ✓ (used in all prior phases) | existing | — |
| `output/cbc_missing_capture_20261013.xlsx` | Source of truth for 581 | ✓ (Phase 180 output) | 2026-10-13 | — |
| `output/internal/cbc_patient_year_20261013.rds` | R/180 re-run baseline | ✓ (Phase 179 output) | 2026-10-13 | — |
| `data/reference/zcta_gazetteer_centroids.csv` | R/122 centroid resolution | ✓ (probe gate in R/122 Section 2) | current | — |
| `data/reference/zip9_bg_centroid_crosswalk.parquet` | R/122 ZIP9 centroids | ✓ (degrading probe; falls back to ZIP5 if absent) | current | ZIP5-only centroid resolution |
| openxlsx2 | Workbook output | ✓ (used in R/179/R/180/R/181) | renv | — |

**Missing dependencies with no fallback:** None identified.

---

## Validation Architecture

Nyquist validation: no automated test suite for R scripts in this project (HiPerGator runtime dependency). Validation is via QC sheets and before/after comparison.

### Phase Requirements → Validation Map

| Req ID | Behavior | Validation Type | Command/Check |
|--------|----------|-----------------|---------------|
| FZIP-01 | Diagnosis workbook produced with A/B/C/QC sheets correctly populated | Manual inspection | Open `output/182_facility_zip_diagnosis_YYYYMMDD.xlsx`; verify sheet order, QC reconciliation |
| FZIP-01 | B_facility_table: FACILITYID fill status matches raw data | QC sheet auto-check | QC sheet: Tier 1 n == sum of filled_tier1 encounters; no encounter flipped from `computed` |
| FZIP-02 | R/122 re-run produces new dated RDS without overwriting 20261013 | File system check | `ls output/encounter_distance_*.rds` shows both old and new files |
| FZIP-02 | 182-RECOVERY.md numbers match workbook KEY | Script-generated | 182-RECOVERY.md generated by script reading workbook by exact label |
| FZIP-02 | CONFIG toggle FALSE reproduces 20261013-era output exactly | Manual re-run | Set `CONFIG$facility_zip_fill <- FALSE`; re-run; confirm distance_status breakdown matches 20261013 baseline |

### Wave 0 Gaps

- [ ] `R/utils/utils_facility_zip.R` — does not exist yet; must be created in Wave 1.
- [ ] `CONFIG$facility_zip_fill` toggle — not yet in `R/00_config.R`; must be added.
- [ ] R/180 RDS pinning mechanism — must be verified by reading R/180 source before planning the re-run step (may require an environment variable addition analogous to R/179's `R179_R122_RDS`).

---

## Open Questions

1. **Does R/180 have an equivalent RDS pinning mechanism to R/179's `R179_R122_RDS`?**
   - What we know: R/179 uses `Sys.getenv("R179_R122_RDS")` (confirmed lines 148–156).
   - What's unclear: R/180 pattern not yet verified in this research session.
   - Recommendation: Read R/180 source (Section 1 inputs) in Wave 0 of the plan before writing the re-run task. If no pin exists, add `R180_R179_RDS` following the same pattern.

2. **Will `facility_zip_source` be stored in the RDS or only in the workbook?**
   - What we know: CONTEXT.md leaves this to Claude's discretion.
   - Recommendation: Store in the RDS. It adds negligible size, ensures provenance is traceable in all downstream consumers (R/179, R/180, future phases), and costs no extra code — just include it in the RDS write step.

3. **Are there any zip_not_in_db rows where the format normalizer has already failed silently?**
   - What we know: `normalize_zip5_raw()` strips non-digits and validates `^[0-9]{5}$`; it returns NA for non-conforming values. Phase 144/148 crosswalk work added some ZIPs.
   - What's unclear: Which specific ZIP5 values in the 581 fall into format-fixable vs truly-not-in-centroid-table without running the diagnosis.
   - Recommendation: Diagnosis step (FZIP-01) runs before any fix is applied; diagnosis workbook C_zip_not_in_db sheet enumerates these.

---

## Sources

### Primary (HIGH confidence)
- `R/122_encounter_distance.R` — Section 3 (encounter pull), Section 4 (fill insertion point), Section 6 (centroid/zip_not_in_db), Section 12 (KEY); read directly
- `R/utils/utils_zip_calendar.R` — `compute_encounter_distance()` signature and distance_status values; read directly
- `R/utils/utils_address.R` — `normalize_zip5_raw()`, `normalize_zip9()`, `get_zip_centroid()` contracts; read directly
- `R/179_cbc_patient_year.R` — `R179_R122_RDS` pinning pattern (lines 148–156); read directly
- `.planning/phases/182-facility-zip-recovery/182-CONTEXT.md` — all decisions D-01 through D-26; read directly

### Secondary (MEDIUM confidence)
- `.planning/REQUIREMENTS.md` — FZIP-01 and FZIP-02 requirement text
- `.planning/STATE.md` — Phase 180 close-out context (581 patients, MISS-01 group b characterization)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already in project renv; no new dependencies
- Architecture: HIGH — insertion points identified by direct code inspection
- Pitfalls: HIGH — all from direct code inspection; cross-SOURCE FACILITYID collision verified from PCORnet CDM conventions stated in R/122 comments
- R/180 pinning: LOW — not yet verified; flagged as Open Question 1

**Research date:** 2026-10-14
**Valid until:** Until R/122, R/179, or R/180 are modified (otherwise stable indefinitely)
