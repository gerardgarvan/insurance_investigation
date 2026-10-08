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
- **D-03:** **Source for `n_dates_post` and `person_years`:** Read from R/147's existing output — `surveillance_modality_patient_<date>.rds` (from `build_patient_modality()`) — not recomputed from raw events. Consistent with the "audit, don't redo" principle of this phase.
- **D-04:** Rate formula: `rate_per_py = n_dates_post / person_years`. Set to `NA_real_` when `person_years == 0` or `person_years` is `NA`. Count zero-follow-up patients in QC.
- **D-05:** The audit (Plan 01) **must confirm** that R/147's `person_years` uses Phase 161's `compute_followup()` definition. If it does not (e.g., an older follow-up end is used), flag the discrepancy in `166-AUDIT.md` and do not silently switch definitions.

### Anthracycline Definition and Echo Clock Start (D-166-01)

- **D-06:** Primary anthracycline = **Doxorubicin (incl. liposomal)**, as established by Phase 164 via `DRUG_NAME_ALIASES` in `R/00_config.R`. This is the canonical definition.
- **D-07:** **D-166-01 record:** Inspect treatment episode detail for other anthracyclines (Daunorubicin, Epirubicin, Idarubicin). If any appear in the cohort, include them in the echo clock start (class-effect cardiotoxicity rationale applies to all anthracyclines in HL/NHL treatment). QC lists counts per drug. Mitoxantrone is explicitly **excluded** (different mechanism; note in KEY).
- **D-08:** **"First-line course"** = treatment episodes flagged `first_line == TRUE` in the treatment episode detail file. Use the **180-day episode file** (matches current Gantt work); record this choice in KEY as D-166-02.
- **D-09:** Last anthracycline dose = **last doxorubicin (or included anthracycline) date within first-line episodes**. Patients with anthracycline exposure but no first-line episode are counted in QC; their latest-ever dose goes only into the sensitivity column (`last_dose_ever_dt`).
- **D-10:** Sensitivity column: **latest-ever anthracycline date** across all episodes (not just first-line) — for re-treated patients. Both primary (`last_dose_firstline_dt`) and sensitivity (`last_dose_ever_dt`) columns emitted; sensitivity used where they differ.

### Cumulative Incidence Method

- **D-11:** Use **Aalen-Johansen estimator** (proper competing-risk CIF) with death as the competing event. Implemented via `survival::survfit(Surv(time, event) ~ 1)` with a factor event (censored / echo / death). No additional packages required if `survival` is already a dependency.
- **D-12:** **Also compute 1 − Kaplan-Meier** (death censored at 0) and report it alongside CIF, explicitly labelled "overestimate when deaths are censored." Showing both makes the competing-risk correction concrete for the team.
- **D-13:** Confirm `survival` is in `renv.lock` before the HiPerGator run. Flag if absent so it can be added before the run stalls (lessons learned from Phase 165 / `survey`/`geepack`).
- **D-14:** Cumulative incidence reported at 1, 2, and 5 years post last anthracycline dose. Time-to-event = days from `last_dose_firstline_dt` to first subsequent echo; censored at `follow_end`.

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
- `R/162_export_patient_modality_dates.R` — Exports patient modality dates; audit must inspect this too
- `R/utils/utils_surveillance.R` — `compute_followup()`, `build_patient_modality()`, `build_patient_modality_dates()`, `compute_modality_stats()` — understand what rates already exist before building
- `data/reference/surveillance_codeset.xlsx` — Modality definitions (the set of modalities that need rates)

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
- `suppress_small(threshold = 10L)` / `suppress_table()` — apply to all displayed counts in the xlsx
- `add_styled_sheet()` with UF_BLUE (`#0021A5`) / UF_ORANGE (`#FA4616`) — existing xlsx styling convention; use for new workbook
- `DRUG_NAME_ALIASES` in `R/00_config.R` — Doxorubicin canonical name already set up (Phase 164)
- `survival::survfit()` with factor event — standard R survival package, likely already a transitive dependency

### Established Patterns
- Dated filenames: `survership_modality_rates_YYYYMMDD.xlsx` (matches all other Phase 159+ outputs)
- KEY sheet as leftmost sheet with run constants, decision log, and data-dictionary entries
- QC sheet as rightmost sheet with reconciliation checks and suppressed-count counts
- `INTERNAL` flag on files containing patient IDs; public release file suppresses small cells

### Integration Points
- Phase 166 reads `surveillance_modality_patient_<date>.rds` (most recent, from R/147); must handle the case where the RDS isn't present (stop with a clear message, like R/162 does)
- Treatment episode detail RDS read for anthracycline dates; the 180-day file is the source of truth for Phase 166 (D-166-02)
- R/39 (script registry) and SCRIPT_INDEX.md must be updated for the new Phase 166 script(s)
- R/88 smoke test section must cover Phase 166 output structure

</code_context>

<specifics>
## Specific Ideas

- **Long → wide rate pivot pattern:** `tidyr::pivot_wider(names_from = modality, values_from = rate_per_py, names_glue = "{modality}_rate_per_py")` on the long table.
- **Aalen-Johansen in R:** `survival::survfit(Surv(days_to_event, event_factor) ~ 1)`, where `event_factor` is a factor with levels `c("censored", "echo", "death")`. Extract CIF at 365, 730, 1825 days.
- **KM alongside CIF:** `survival::survfit(Surv(days_to_event, had_echo) ~ 1)` with binary `had_echo`; 1 - KM at the same time points. Label clearly in xlsx.
- **Doxorubicin-only sensitivity for echo:** filter to `drug_name == "Doxorubicin"` (after `DRUG_NAME_ALIASES` collapse) and rerun the echo block; report in C_anthracycline_echo as a sensitivity sub-table.
- **Mitoxantrone exclusion note:** one KEY sheet row: "Mitoxantrone excluded from anthracycline clock — different mechanism (topoisomerase II inhibitor, not intercalating agent); see D-166-01."
- **Zero-follow-up patients:** reported in QC as `n_zero_py_patients`; appear in long rate table with `rate_per_py = NA_real_`, not dropped.

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
