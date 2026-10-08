# Phase 166 Audit: Survivorship Modality Rates and Anthracycline-to-Echo Timing

**Prepared:** 2026-10-08
**Updated:** 2026-10-08 (Task 3 — HiPerGator data check results filled)
**Plan:** 166-01 Tasks 1 + 3 (code audit + HiPerGator confirmation)
**Status:** COMPLETE — all data-dependent items confirmed from HiPerGator run

---

## Script numbers

Next free numbers after Phase 165's script (`R/165_distance_cbc_association.R`):

| Role              | Key               | Script number |
|-------------------|-------------------|---------------|
| Rates script      | `script_rates:`   | **166**       |
| Echo-timing script| `script_echo:`    | **167**       |
| Workbook script   | `script_workbook:`| **168**       |

**Letter-suffixed scripts in the repo:** One exists (`R/122a_build_zip9_centroid_crosswalk.R`). No
letter-suffixed scripts exist in the 160s range; Phase 166 will not introduce them. Script names
are plain integers: `166_`, `167_`, `168_`.

---

## Modality set

`load_modality_lookup()` reads the `Modalities` sheet from `data/reference/surveillance_codeset.xlsx`
and returns a named character vector (modality name → column prefix) in display order.
The modalities used in `R/147` (as of Phase 163) are the same as those in the codeset after the
DIAGNOSIS exclusion fix.

Confirmed modality string for echocardiogram from `R/147` KEY sheet and `R/147_verify_vs_1006.R`:

```
echo_modality_name: "Echocardiogram"
```

The full modality set (from R/147 and R/00_config.R comments, line 3744) includes:
Mammogram, Breast MRI, Echocardiogram, Stress test, Electrocardiogram, Pulmonary function test,
Thyroid function, BMP, CMP, LIPID, LFT, KIDNEY (and submodalities). The exact ordered list comes
from `load_modality_lookup()` at runtime.

---

## Existing rate columns

| Column | Source file::function | Numerator | Denominator | Rate computed? |
|---|---|---|---|---|
| `n_dates_post_any` | `build_patient_modality()` in `utils_surveillance.R::630` | distinct ID x modality x event_date rows with window == "post", any tier | — | No |
| `n_dates_post_primary` | `build_patient_modality()` in `utils_surveillance.R::630` | distinct ID x modality x event_date rows with window == "post", tier == "primary" | — | No |
| `n_dates_pre_any` | same | pre-anchor, any tier | — | No |
| `n_dates_pre_primary` | same | pre-anchor, primary tier | — | No |
| `n_dates_after_followup_any` | same | after follow_end, any tier | — | No |
| `n_dates_after_followup_primary` | same | after follow_end, primary tier | — | No |
| `first_post_date_any`, `last_post_date_any` | same | first/last post date | — | No |
| `first_post_date_primary`, `last_post_date_primary` | same | first/last post date, primary | — | No |
| `person_years` | `compute_followup()` via `build_patient_modality()` join | — | fu_days / 365.25 per patient | No rate column |
| `events_per_person_year` | `compute_modality_stats()` `utils_surveillance.R::579` | total_event_dates (pooled) | sum(person_years) across ALL denominator patients | Yes — but POOLED, not per-patient |

**Summary:** `build_patient_modality()` has `n_dates_post_*` and `person_years` per ID x modality
but **no rate column**. `compute_modality_stats()` produces a pooled `events_per_person_year` at
modality level (total event dates / sum of all person-years) — not a per-patient rate.
`build_patient_modality_dates()` / `R/162` hold per-ID date *counts*, not rates and not per-event dates.

Phase 166's new `rate_per_py` = `n_dates_post_primary / person_years` per ID x modality is not
currently computed anywhere.

---

## Follow-up definition

```
person_years_uses_phase161_compute_followup: yes
```

**Evidence:**

1. `R/147`, line 265: `followup <- compute_followup(denominator, activity, death_resolved, EXTRACT_CUTOFF)`
   — uses the Phase 161 three-argument signature `(denominator, activity, death_resolved, cutoff)`.
2. `R/147` header comment (line 4): `[161-07 audit] Updated in Phase 161-05 (compute_followup uses death_date_resolved).`
3. `compute_followup()` in `utils_surveillance.R::457` computes `person_years = fu_days / 365.25`
   floored at 0, where `follow_end = min(death_date_resolved, obs_end, cutoff, na.rm = TRUE)`.
   `death_date_resolved` comes from `resolve_death_date()` (Phase 161), which applies grace-period
   plausibility and source-priority resolution.

No discrepancy flag required.

---

## Exact filters behind n_dates_post (reconciliation contract)

Plans 02 and 03 must reproduce these filters exactly when computing dated events for B_rates_by_fu_year
and the echo block.

| Parameter | Value | Source |
|---|---|---|
| `n_dates_col:` | `n_dates_post_primary` | `build_patient_modality()` → `summ(filter(ev, tier == "primary"), "_primary")` at `utils_surveillance.R::622-628` |
| `codeset_variant:` | **primary** — tier == "primary" rows only; "any" includes sensitivity | `filter(ev, tier == "primary")` at line 626 |
| `anchor_rule:` | post = event_date **strictly after** hl_anchor_date; anchor day itself is **pre** | `ANCHOR_DAY_IS_POST <- FALSE` (R/147 line 54); `classify_event_window()` at `utils_surveillance.R::564`: `event_date <= hl_anchor_date & !anchor_day_is_post ~ "pre"` |
| `followup_clip:` | yes — post counts exclude dates where `event_date > follow_end` (`window == "after_followup"`); `build_patient_modality()` sums `window == "post"` only | `utils_surveillance.R::617-619` |
| `date_dedup:` | distinct ID x modality x event_date (before tier split); then summed by window | `event_dedup` at R/147 line 310-313; `build_patient_modality()::summ()` uses `distinct(ID, modality, window, event_date)` at line 615 |

**Reconciliation contract for Plans 02/03:** When rebuilding dated events from raw sources, filter to
`tier == "primary"`, `window == "post"` (event_date > hl_anchor_date AND event_date <= follow_end),
deduplicate at ID x modality x event_date grain. The count of distinct post-anchor primary dates per
ID x modality must equal `n_dates_post_primary` from `surveillance_modality_patient_<date>.rds`.

---

## Dated-events source

```
dated_events_source: option_a (events_win -> filter(type_ok, tier == "primary", window == "post") -> distinct(ID, modality, event_date))
```

**Rationale:**

`events_win` is produced in `R/147` SECTION 7 by calling:
1. `match_coded_events(bind_rows(proc_events_in, lab_events_in), codeset)` → matched_coded
2. `build_component_events(lab_events_in, codeset)` → comp$events
3. `build_analyte_events(analyte_hits, codeset)` → an_rules$events
4. `bind_rows(matched_coded, comp$events, an_rules$events)` → matched_all
5. `classify_event_window(matched_all, followup, anchor_day_is_post = FALSE)` → events_win

All five of these functions are **pure functions** defined in `R/utils/utils_surveillance.R` (no DuckDB,
no CONFIG dependencies). A new script can reproduce `events_win` by:
- Sourcing `R/00_config.R` (provides CONFIG, utilities)
- Opening DuckDB (PROCEDURES, LAB_RESULT_CM pulls)
- Calling the same function chain on all denominator IDs

Option a is preferred over option b (saving events_win to RDS in R/147) because it avoids adding a
large intermediate file and requires no re-run of R/147. Plans 02/03 will call the function chain
directly.

**Column names of the dated-events output** (confirmed by HiPerGator run):

`events_win` columns (after `classify_event_window()`):
`codeset_row_id`, `ID`, `code_data`, `type_val`, `event_date`, `source_table`, `modality`, `submodality`, `tier`, `type_ok`, `hl_anchor_date`, `follow_end`, `window`

After filtering and deduplication, `dated_events` columns: `ID`, `modality`, `event_date`

```
dated_events_reconciliation_sample: 1363/1363 matching, 0 mismatching → PASS
```

The option-a function chain reproduces `n_dates_post_primary` exactly on the 200-patient sample. Plans 02/03 may rely on this chain without additional reconciliation.

For Phase 166's purposes, Plans 02/03 use:
```r
events_win |>
  filter(type_ok, tier == "primary", window == "post") |>
  distinct(ID, modality, event_date)
```

---

## Treatment episode / anthracycline readiness

```
episode_180_file: treatment_episode_detail_180.rds
episode_90_file: (not found)
```

**Confirmed file** (from HiPerGator data check):
- `treatment_episode_detail_180.rds` — nrow 259,199

**Confirmed columns:**

| Column | Actual name | Notes |
|---|---|---|
| Patient ID | `patient_id` | NOTE: not `ID` — Plans 02/03 must rename to `ID` on load |
| Drug name | `drug_name` | applies DRUG_NAME_ALIASES at runtime |
| Administration date | `treatment_date` | date-level rows confirmed (see below) |
| First-line flag | **(not present)** | column absent from file — D-08a fallback triggered |
| Episode identifier | `episode_number` | |

Additional columns present: `treatment_type`, `triggering_code`, `ENCOUNTERID`, `episode_start`, `episode_stop`, `historical_flag`.

```
has_date_level_drug_rows: yes
```

Evidence: nrow 259,199 >> n_distinct(patient_id), confirming multiple rows per patient (date-level drug rows exist). The echo block can compute a last dose date.

```
first_line_flag_populated: no
episode_file_used: 180-day (fallback, D-08a — first_line column absent from treatment_episode_detail_180.rds)
```

**D-08a note:** Because `first_line` is absent from the 180-day file, Plan 03's echo block cannot restrict to first-line episodes. All anthracycline episodes in the 180-day file will be treated equivalently. The `last_dose_firstline_dt` column will be computed as the latest anthracycline date across all episodes in the 180-day file (functionally equivalent to `last_dose_ever_dt` in this dataset). This must be documented in the C_anthracycline_echo KEY sheet as D-166-02 fallback, and in the QC sheet as `first_line_flag_absent: TRUE`.

```
anthracyclines_present: not enumerated in data check (first_line column absent caused section 2 to be skipped)
```

Per-drug patient counts will be computed at runtime in Plan 03 by filtering `drug_name` (after `DRUG_NAME_ALIASES` collapse) against the pattern `/doxo|dauno|epiru|idaru|mitox/i`. Expected drugs: Doxorubicin (primary, Phase 164 canonical), Daunorubicin, Epirubicin, Idarubicin (class-effect, D-07), Mitoxantrone (QC only, D-07a). Actual counts: **confirmed at Plan 03 runtime**.

**Patient ID column name mismatch:** The file uses `patient_id`, not `ID`. Plans 02/03 must add `rename(ID = patient_id)` immediately after `readRDS()`. This is recorded as a deviation from the Phase 142/143 assumption that the column would be named `ID`.

---

## survival package

```
survival_in_renv_lock: no (renv.lock not found in repo root)
survival_installed: yes
survival_version: 3.8.9
```

`requireNamespace("survival")` returned `TRUE` on HiPerGator; `packageVersion("survival")` = `3.8.9`.
No `renv::install()` step needed before Plan 03 runs. Plan 03 may call `survival::survfit()` directly.

---

## What remains to build

| Artifact | Status |
|---|---|
| `n_dates_post_primary` per ID x modality | REUSE (from `surveillance_modality_patient_<date>.rds`) |
| `person_years` per patient | REUSE (same RDS, joined from followup) |
| `rate_per_py` long table (one row per ID x modality) | BUILD (Plan 02) |
| Wide per-patient rate table (`<modality>_rate_per_py` columns) | BUILD (Plan 02) |
| A_rates_summary (mean, median, IQR, pooled rate per modality) | BUILD (Plan 02) |
| B_rates_by_fu_year (Y1/Y2/Y3-5/5+ interval rates) | BUILD (Plan 02, needs dated events) |
| C_anthracycline_echo (last-dose timing, CIF, KM, echo rate) | BUILD (Plan 03) |
| Dated-events helper (option a function chain) | BUILD inline in Plans 02/03 (no new file) |
| `survivorship_modality_rates_<date>.xlsx` workbook | BUILD (Plan 04) |
| R/39 + SCRIPT_INDEX.md registration for scripts 166/167/168 | BUILD (Plan 04) |
| R/88 smoke test section for Phase 166 outputs | BUILD (Plan 04) |

---

---

## Additional confirmed facts (HiPerGator run)

- **Cached event/dedup/events_win files:** none found in `outputs_dir` — confirms option_a (rebuild via function chain) is required. No pre-saved events object exists.
- **Patient ID column name in episode file:** `patient_id` (not `ID`). Plans 02/03 must `rename(ID = patient_id)` on load.
- **No 90-day episode file found.** Only the 180-day file (`treatment_episode_detail_180.rds`) is available. The D-08a fallback (use 180-day without `first_line` restriction) applies by default, not as a contingency.

---

*Audit complete. All data-dependent items confirmed. Plans 02-04 may proceed.*
