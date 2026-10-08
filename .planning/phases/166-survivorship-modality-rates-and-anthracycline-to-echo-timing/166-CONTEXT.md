# Phase 166: Survivorship Modality Rates and Anthracycline-to-Echo Timing — Context

**Gathered:** 2026-10-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Build a per-patient survivorship modality rate table (unique post-anchor dates / person-years of follow-up) for every surveillance modality in R/147, and an echocardiogram timing block measured from the last anthracycline dose. Plan 01 audits what R/147 already produces before any code is written; later plans build only what is confirmed missing.

All existing R/147 outputs are read-only inputs. New workbook: `survivorship_modality_rates_<date>.xlsx` with sheets KEY, A_rates_summary, B_rates_by_fu_year, C_anthracycline_echo, QC.

</domain>

<decisions>
## Implementation Decisions

### Per-Patient Rate Table Structure

- **D-01:** Main (internal) rate table is **long format**: one row per ID × modality, columns `ID`, `modality`, `n_dates_post`, `person_years`, `rate_per_py`. This is the shape that summary statistics, follow-up-year breakdowns, and anthracycline-echo joins work from.
- **D-02:** Per-patient **CSV export is wide format**: one row per patient, one column per modality rate (`<modality>_rate_per_py`). This is what the team opens.
- **D-03:** **Source for `n_dates_post` and `person_years`:** Read from R/147's existing output — `surveillance_modality_patient_<date>.rds` (from `build_patient_modality()`) — not recomputed from raw events. Consistent with the "audit, don't redo" principle of this phase. These totals feed A_rates_summary and the long/wide per-patient tables.
- **D-03a:** **Dated sources for interval work:** B_rates_by_fu_year and the echo block need event *dates*, which the patient-level RDS does not hold. Read modality dates from R/162's export / `build_patient_modality_dates()` (read-only). Plan 01 audit confirms the object, columns, and that totals from the dates reconcile to `n_dates_post` per ID × modality.
- **D-03b:** **Follow-up-year rates:** split each patient's post-anchor person-time at 365, 730, and 1825 days into Y1, Y2, Y3–5, 5+; rate per interval = dates in interval / person-years in interval. Patients contribute only the intervals they are followed through. Interval person-years summed across intervals must equal `person_years` (QC check).
- **D-04:** Rate formula: `rate_per_py = n_dates_post / person_years`. Set to `NA_real_` when `person_years == 0` or `person_years` is `NA`. Count zero-follow-up patients in QC.
- **D-05:** The audit (Plan 01) **must confirm** that R/147's `person_years` uses Phase 161's `compute_followup()` definition. If it does not (e.g., an older follow-up end is used), flag the discrepancy in `166-AUDIT.md` and do not silently switch definitions.

### Anthracycline Definition and Echo Clock Start (D-166-01)

- **D-06:** Primary anthracycline = **Doxorubicin (incl. liposomal)**, as established by Phase 164 via `DRUG_NAME_ALIASES` in `R/00_config.R`. This is the canonical definition.
- **D-06a:** The audit confirms the treatment episode detail holds **date-level drug rows** (one row per administration date × drug), which "last dose" requires. If it holds only a drug list per episode, stop and report before building the echo block.
- **D-07:** **D-166-01 record:** Inspect treatment episode detail for other anthracyclines (Daunorubicin, Epirubicin, Idarubicin). If any appear in the cohort, include them in the echo clock start (class-effect cardiotoxicity rationale applies to all anthracyclines in HL/NHL treatment). QC lists counts per drug.
- **D-07a:** **Mitoxantrone** is excluded from the primary echo clock because it is an anthracenedione, not an anthracycline, and is rarely used in HL. It is counted in QC. KEY states that it is also cardiotoxic (the Children's Oncology Group long-term follow-up guidelines count it with a dose-equivalence factor). If any cohort patients received it, add a sensitivity row with mitoxantrone included in the clock.
- **D-08:** **"First-line course"** = treatment episodes flagged `first_line == TRUE` in the treatment episode detail file. Use the **180-day episode file** (matches current Gantt work); record this choice in KEY as D-166-02.
- **D-08a:** The audit confirms `first_line` is actually populated in the 180-day file (Phase 143 dealt with blank enrichment columns there). If it is blank or absent, fall back to the 90-day file and record the fallback in KEY and 166-AUDIT.md.
- **D-09:** Last anthracycline dose = **last doxorubicin (or included anthracycline) date within first-line episodes**. Patients with anthracycline exposure but no first-line episode are counted in QC; their latest-ever dose goes only into the sensitivity column (`last_dose_ever_dt`).
- **D-10:** Sensitivity column: **latest-ever anthracycline date** across all episodes (not just first-line) — for re-treated patients. Both primary (`last_dose_firstline_dt`) and sensitivity (`last_dose_ever_dt`) columns emitted; sensitivity used where they differ.

### Cumulative Incidence Method

- **D-11:** Use **Aalen-Johansen estimator** (proper competing-risk CIF) with death as the competing event. Implemented via `survival::survfit(Surv(time, event) ~ 1)` with a factor event (censored / echo / death). No additional packages required if `survival` is already a dependency.
- **D-12:** **Also compute 1 − Kaplan-Meier** (deaths treated as censored at the death date) and report it alongside CIF, explicitly labelled "overestimate when deaths are censored." Showing both makes the competing-risk correction concrete for the team.
- **D-13:** Confirm `survival` is in `renv.lock` before the HiPerGator run. Flag if absent so it can be added before the run stalls (lessons learned from Phase 165 / `survey`/`geepack`).
- **D-14:** Cumulative incidence reported at 1, 2, and 5 years post last anthracycline dose. Time-to-event = days from `last_dose_firstline_dt` to the first echo dated **strictly after** the last dose (same-day and pre-treatment baseline echoes do not count); death (resolved death date) is the competing event; otherwise censored at `follow_end`.
- **D-14a:** Patients whose `follow_end` is on or before the last dose date have no usable time; they are excluded from the echo block and counted in QC (`n_no_time_after_last_dose`), never entered at time 0.
- **D-14b (SRATE-04):** **Echo rate per person-year after the last dose** = echo dates strictly after `last_dose_firstline_dt` and on or before `follow_end`, divided by person-years from the last dose to `follow_end`. Same NA rule as D-04 for zero person-time. Reported per patient (long table, modality = "echo_post_anthracycline") and summarised in C_anthracycline_echo (mean, median, IQR, pooled rate). Sensitivity versions use `last_dose_ever_dt` and the doxorubicin-only definition.
- **D-14c:** **Data visibility caveat (KEY):** echoes done outside OneFlorida+ partner sites are not captured, so cumulative incidence and rates are lower bounds on echo receipt.

### Claude's Discretion

- Exact column naming in the long vs. wide table (follow the `<modality>_rate_per_py` pattern used for surveillance outputs)
- Sheet layout within `survivorship_modality_rates_<date>.xlsx` (follow existing UF-color xlsx conventions from R/147)
- Whether `166-AUDIT.md` uses markdown table or prose — markdown table preferred for scannability
- How zero-event patients appear in the per-modality long table (include them with `n_dates_post = 0L`, `rate_per_py = 0`)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Core Phase 166 Specs
- `.planning/ROADMAP.md` §"Phase 166: Survivorship Modality Rates and Anthracycline-to-Echo Timing" — Goal, design constraints, success criteria, plan breakdown
- `.planning/REQUIREMENTS.md` §"SRATE-01..SRATE-04" — Acceptance criteria

### Surveillance Infrastructure (read-only inputs)
- `R/147_surveillance_modality_frequency.R` — Produces `surveillance_modality_patient_<date>.rds` (source of `n_dates_post`, `person_years`); R/147 outputs are read-only for Phase 166
- `R/162_export_patient_modality_dates.R` — Exports patient modality dates; source of dated events for B_rates_by_fu_year and the echo block (D-03a)
- `R/utils/utils_surveillance.R` — `compute_followup()`, `build_patient_modality()`, `build_patient_modality_dates()`, `compute_modality_stats()` — understand what rates already exist before building
- `data/reference/surveillance_codeset.xlsx` — Modality definitions (the set of modalities that need rates); audit confirms the echocardiogram modality name used in R/147 outputs

### Treatment Episode and Anthracycline Sources
- Treatment episode detail RDS (180-day file, path from `CONFIG$cache$outputs_dir`) — provides `first_line` flag and drug-level dates
- `R/00_config.R` — `DRUG_NAME_ALIASES` (Doxorubicin canonical collapse), `MEDICATION_LOOKUP_JCODE_SUPPLEMENT` (J9000/J9001/J9223 → Doxorubicin)

### Follow-up Definition
- `R/utils/utils_surveillance.R` §`compute_followup()` — authoritative follow-up function (Phase 161 updated to use `death_date_resolved`)
- `R/utils/utils_death.R` §`resolve_death_date()` — death date resolution used by `compute_followup()`

### Phase Context Files
- `.planning/phases/158-surveillance-modality-frequency/158-CONTEXT.md` — D-01..D-30 for surveillance counting decisions
- `.planning/phases/164-doxorubicin-generic-name/164-CONTEXT.md` — Doxorubicin collapse decisions (D-1/D-3)
- `.planning/phases/161-death-date-plausibility-and-follow-up-end-definition/` — `compute_followup()` updates

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `compute_followup()` in `utils_surveillance.R` — already produces `person_years` per patient; Phase 166 reads this from R/147 output, does not recompute
- `build_patient_modality()` — produces `n_dates_post` per ID × modality + `person_years` join; Phase 166's long rate table derives directly from this
- `suppress_small(threshold = 10L)` / `suppress_table()` — apply to all displayed counts in the xlsx. Confirm the parameter suppresses 1–10 (the project rule, shown as "<11"); if it suppresses only values below 10, pass the value that suppresses 1–10
- `add_styled_sheet()` with UF_BLUE (`#0021A5`) / UF_ORANGE (`#FA4616`) — existing xlsx styling convention; use for new workbook
- `DRUG_NAME_ALIASES` in `R/00_config.R` — Doxorubicin canonical name already set up (Phase 164)
- `survival::survfit()` with factor event — standard R survival package, likely already a transitive dependency

### Established Patterns
- Dated filenames: `survivorship_modality_rates_YYYYMMDD.xlsx` (matches all other Phase 159+ outputs)
- KEY sheet as leftmost sheet with run constants, decision log, and data-dictionary entries
- QC sheet as rightmost sheet with reconciliation checks and suppressed-count counts
- `INTERNAL` flag on files containing patient IDs; public release file suppresses small cells

### Integration Points
- Phase 166 reads `surveillance_modality_patient_<date>.rds` (most recent, from R/147); must handle the case where the RDS isn't present (stop with a clear message, like R/162 does)
- Treatment episode detail RDS read for anthracycline dates; the 180-day file is the source of truth for Phase 166 (D-166-02), subject to D-08a
- Modality dates (R/162 / `build_patient_modality_dates()`) read for follow-up-year rates and echo timing (D-03a)
- R/39 (script registry) and SCRIPT_INDEX.md must be updated for the new Phase 166 script(s)
- R/88 smoke test section must cover Phase 166 output structure

</code_context>

<specifics>
## Specific Ideas

- **Long → wide rate pivot pattern:** `tidyr::pivot_wider(names_from = modality, values_from = rate_per_py, names_glue = "{modality}_rate_per_py")` on the long table.
- **Aalen-Johansen in R:** `survival::survfit(Surv(days_to_event, event_factor) ~ 1)`, where `event_factor` is a factor with levels `c("censored", "echo", "death")`. Extract CIF at 365, 730, 1825 days.
- **KM alongside CIF:** `survival::survfit(Surv(days_to_event, had_echo) ~ 1)` with binary `had_echo`; 1 - KM at the same time points. Label clearly in xlsx.
- **Doxorubicin-only sensitivity for echo:** filter to `drug_name == "Doxorubicin"` (after `DRUG_NAME_ALIASES` collapse) and rerun the echo block; report in C_anthracycline_echo as a sensitivity sub-table.
- **Mitoxantrone note:** one KEY sheet row: "Mitoxantrone excluded from the primary anthracycline clock — an anthracenedione rather than an anthracycline and rarely used in HL; it is also cardiotoxic and is counted in QC (see D-07a)."
- **Zero-follow-up patients:** reported in QC as `n_zero_py_patients`; appear in long rate table with `rate_per_py = NA_real_`, not dropped.
- **Echo block QC rows:** patients with any anthracycline, with a first-line last dose, without a first-line episode (sensitivity only), with no time after last dose (D-14a), echo events, deaths before echo, and per-drug anthracycline counts incl. mitoxantrone.
- **Interval reconciliation:** sum of Y1/Y2/Y3–5/5+ person-years equals `person_years`, and sum of interval dates equals `n_dates_post`, per ID × modality (QC pass/fail).

</specifics>

<deferred>
## Deferred Ideas

- Stratified rates by payer, SOURCE site, or rurality — out of scope for Phase 166; could be a Phase 170+ addition
- Per-modality trend over follow-up years beyond the B_rates_by_fu_year breakdown — out of scope
- Beacopp/re-treatment regimen-specific anthracycline timing — current scope is first-line (D-166-02); re-treatment timing deferred
- BEACOPP regimen identification (doxorubicin dose in BEACOPP vs ABVD differs) — Phase 166 uses the existing first-line flag without distinguishing regimen

</deferred>

---

*Phase: 166-survivorship-modality-rates-and-anthracycline-to-echo-timing*
*Context gathered: 2026-10-08*
