# Phase 187: Anthracycline Exposure Variables - Context

**Gathered:** 2026-10-22
**Status:** Schema probe confirmed — ready for planning

<domain>
## Phase Boundary

Produce three patient-grain variables (`any_anthracycline`, `last_anthracycline_date`, `years_since_last_anthracycline`) plus supporting columns (`any_chemo`, `follow_end`, `drugs_received`) in a single patient-grain RDS written to `output/internal/`. Write an aggregate-only summary to `output/`. Phase 187 does not join into any encounter-level or survivorship events table; Phase 188 joins this patient table to echo encounters and computes echo-level `days_since_last_anthracycline_dose`. Script registration (R/39, R/88, SCRIPT_INDEX) is Phase 189 (REG-01), not this phase.

</domain>

<decisions>
## Implementation Decisions

### D-187-01: Drug Source

- **D-01:** Drug source = 180-day treatment episode detail RDS — the same pinned object R/167 reads. One row per ID × drug × admin_date after `DRUG_NAME_ALIASES` collapse. Phase 124 already folded MED_ADMIN and DISPENSING into this pipeline; probing them separately would risk double-counting.
- **D-02:** The schema probe (`probe_inputs()` on the 180-day episode detail RDS) runs on HiPerGator **before planning begins**. The user copies `.planning/schemas/187_schema_<date>.md` to the repo unedited and confirms drug labels and `admin_date` min/max. Task 0 of the Phase 187 plan **cites that existing probe file** — it does not re-run the probe.
- **D-03:** Probe confirmed (2026-10-22): (a) only **Doxorubicin** appears after alias collapse (24,404 rows); Daunorubicin, Epirubicin, and Idarubicin have zero rows in this extract — record all three as absent in KEY, do not hunt in raw tables; (b) `treatment_date` range = 2012-01-01 to 2025-03-27, no window filter. Date column is `treatment_date` (not `admin_date`). Patient ID column is `patient_id` (not `ID`). `first_line` column is absent (D-08a confirmed).
- **D-04:** Drug set constant `ANTHRACYCLINE_DRUGS <- c("Doxorubicin", "Daunorubicin", "Epirubicin", "Idarubicin")` — define the full four-drug set; only Doxorubicin will match in practice. Mitoxantrone excluded. Pass `ANTHRACYCLINE_DRUGS` explicitly to `last_anthracycline_dose()` — never rely on a default inside the helper.
- **D-04a:** Cohort (row set). The output has one row per patient in the same follow-up table R/184 uses (the source of `follow_end`, D-11), so Phase 188 joins on an identical patient set. Patients in the episode file but not in that table are dropped and counted on KEY. The planner states the row count of that table from its probe or pin before writing code.
- **D-04b:** `any_chemo` filter = `treatment_type == "Chemotherapy"` (183,835 rows in file; probe confirmed 5 treatment_type levels: Chemotherapy, Radiation, Immunotherapy, SCT, Proton Therapy). Record filter on KEY.

### D-187-02: Patient-Grain Output Columns

- **D-05:** R/187 writes one patient-grain RDS to `output/internal/` with these columns per cohort patient:
  - `any_chemo` — TRUE if patient has any row in the 180-day episode detail RDS (any drug), FALSE if absent
  - `any_anthracycline` — TRUE if patient has a row for an included anthracycline drug, FALSE otherwise. **Never NA.**
  - `last_anthracycline_date` — max `treatment_date` across all episodes for included drugs; NA when `any_anthracycline == FALSE`
  - `years_since_last_anthracycline` — last dose → `follow_end` (Phase 161 definition); NA when `any_anthracycline == FALSE`; NA (not negative) when last dose is after `follow_end` (flag count on KEY)
  - `follow_end` — carried from `compute_followup()` output or its pinned RDS; do not reimplement the min() logic
  - `drugs_received` — one character string: included anthracycline drug names received, sorted alphabetically, joined with "; " (NA when `any_anthracycline == FALSE`). Not a list-column, so probes and CSV exports stay flat.
- **D-06:** `any_anthracycline` is TRUE/FALSE for every cohort patient including those with no chemo. `last_anthracycline_date` and `years_since_last_anthracycline` are NA (not 0) when `any_anthracycline == FALSE`. This is a correction from ANTH-01 REQUIREMENTS wording (which said NA for unexposed) — the flag itself is never NA.
- **D-07:** Cases where last dose date is after `follow_end`: set `years_since_last_anthracycline` to NA, keep the row, count on KEY. Never pass a negative value through.

### D-187-03: Survivorship Set Join

- **D-08:** R/187 writes patient-grain only. Phase 188 is responsible for joining the Phase 187 patient table to echo encounters and computing `days_since_last_anthracycline_dose` at encounter grain. Phase 187 does not produce an encounter-grain RDS.
- **D-09:** Pins follow the consumer-owns-the-pin rule (CLAUDE.md; Phase 185 D-01). R/187 pins its own **inputs** — the 180-day episode detail RDS and the follow-up RDS — as `R187_<NAME>` env vars with dated defaults, recorded on KEY. R/187 writes its output to a dated path and prints it; `187-01-SUMMARY.md` records that exact path so R/188 can pin it as its own input. R/187 does not set an `R187_OUTPUT` variable. The Phase 187 RDS must not require Phase 188 to rebuild `follow_end` — include it as a column (D-05).
- **D-09a:** Schema probe of the output is required, not optional (ANTH-03; CLAUDE.md: Phase 188 may use only names that appear in a probe). After the HiPerGator run, `probe_inputs("187out", ...)` on the output RDS; copy the probe file into the Windows repo unedited. Patient-level values must not appear in the probe file — if `probe_inputs()` lists sample values or levels for ID or date columns, pass only the non-identifying columns or confirm it lists names/types only.
- **D-10:** ROADMAP and REQUIREMENTS are updated (as a quick task) to move `days_since_last_anthracycline_dose` to Phase 188 / ECHO-01, and to correct ANTH-02 to use "last dose → follow_end (Phase 161 definition)" rather than "min(last_encounter, data_cutoff)."

### D-187-04: follow_end Source

- **D-11:** `years_since_last_anthracycline` denominator = `follow_end` per patient from `compute_followup()` (Phase 161 definition: `min(death_date_resolved, last_observed, analysis_cutoff)`). Get `follow_end` by calling the existing helper or reading its pinned output — cite the file and lines in the plan. Do not copy the min() logic into R/187.
- **D-12:** Using `follow_end` (not a raw `min(last_encounter, cutoff)`) correctly accounts for death: a deceased patient's follow-up ends at their resolved death date, not at their last encounter.

### D-187-05: Script Architecture

- **D-13:** One new script: `R/187_anthracycline_exposure.R`. R/184 and R/166 outputs are read-only inputs; do not edit them.
- **D-14:** `last_anthracycline_dose()` from `R/utils/utils_anthracycline_echo.R` (lines 58+) is the reusable helper. It returns `last_dose_firstline_dt` / `last_dose_ever_dt`; Phase 187 uses `last_dose_ever_dt` as `last_anthracycline_date` (all episodes, not first-line only, since Phase 187 needs the full exposure history). The planner confirms from source (cite lines) that the helper runs when `first_line` is absent (D-08a fallback in that file) and that `last_dose_ever_dt` is the plain maximum admin_date over the passed drugs with no window or anchor applied. If either is not true, stop and decide before writing code.
- **D-15:** Aggregate summary in `output/`: counts by `any_chemo`, by `any_anthracycline`, and patients by drug name, plus the D-07 flagged count and the D-04a dropped count. Counts 1–10 shown as `"<11"`; zero shown as 0. Complementary suppression: where a TRUE/FALSE pair adds to a visible cohort total, if one cell is `"<11"`, the other is also suppressed. By-drug counts are not additive (a patient can receive several drugs), so no complementary rule applies to them. No patient IDs or dates in this file.
- **D-16:** The plan ends with a blocking HiPerGator checkpoint (user runs R/187 interactively, pastes the output path, row counts, flagged/dropped counts, and fixture results) before the SUMMARY is written. testthat fixtures cover: no chemo → any_anthracycline FALSE, dates NA; chemo without anthracycline → FALSE; single administration; multiple administrations (latest date kept); last dose after follow_end → years_since NA and counted.

### Claude's Discretion

- Section structure within R/187 (SECTION 0 pin, SECTION 1 read + alias, SECTION 2 compute flags, SECTION 3 write RDS + summary)
- Exact column order in the output RDS beyond what D-05 specifies

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Schema Probe (confirmed 2026-10-22)
- `.planning/schemas/187_schema_20261022.md` — Column names and types from the 180-day episode detail RDS. **Task 0 of every Phase 187 plan must cite this file.**
  - Key columns: `patient_id` (character), `treatment_type` (character), `treatment_date` (Date, range 2012-01-01 to 2025-03-27), `drug_name` (character, NA=150,317 rows — non-chemo rows have no drug name)
  - No `first_line` column (D-08a confirmed)
  - Anthracyclines present after alias collapse: **Doxorubicin only** (24,404 rows). Daunorubicin, Epirubicin, Idarubicin: zero rows.

### Drug-Name Normalization
- `R/00_config.R` lines 2749+ — `DRUG_NAME_ALIASES` lookup (Doxorubicin canonical collapse, Phase 164 D-1/D-3)
- `.planning/phases/164-doxorubicin-generic-name/164-CONTEXT.md` — D-1/D-3 liposomal collapse decisions

### Anthracycline Helper
- `R/utils/utils_anthracycline_echo.R` lines 58–90 — `last_anthracycline_dose()`: use `last_dose_ever_dt` column as `last_anthracycline_date` for Phase 187 (Phase 166 used `last_dose_firstline_dt` — different clock)
- D-08a note in that file: `first_line` was absent in the 180-day episode detail; fallback documented there

### Follow-up Definition
- `R/utils/utils_surveillance.R` §`compute_followup()` — authoritative Phase 161 definition of `follow_end`; cite file and lines in plan
- `.planning/phases/166-survivorship-modality-rates-and-anthracycline-to-echo-timing/166-CONTEXT.md` — D-06 through D-14c for Phase 166 anthracycline decisions (context for what Phase 187 is extending)

### Requirements
- `.planning/REQUIREMENTS.md` §ANTH-01, ANTH-02, ANTH-03 — acceptance criteria (to be updated per D-06 and D-10 corrections)

### Phase 188 Interface
- Phase 187 output path: dated `output/internal/anthracycline_exposure_patient_<YYYYMMDD>.rds`, recorded in `187-01-SUMMARY.md`; R/188 pins it as its own input (D-09)
- Output schema: `.planning/schemas/187out_schema_<date>.md` (D-09a)
- Phase 188 reads the patient-grain RDS and joins to echo encounters

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `last_anthracycline_dose()` — `R/utils/utils_anthracycline_echo.R` lines 58–90; inputs: episodes tibble (ID, drug_name, admin_date, first_line, episode_id), drugs character vector; use `last_dose_ever_dt` column as Phase 187's `last_anthracycline_date`
- `DRUG_NAME_ALIASES` — `R/00_config.R` lines 2749+; already applied in the 180-day episode detail build; confirm it is applied upstream or apply in R/187 before filtering
- `compute_followup()` — `R/utils/utils_surveillance.R`; do not reimplement; read its pinned output or call it with the same arguments as R/184
- `sup()` / suppress_small pattern — carry through for aggregate summary counts
- `add_styled_sheet()` with UF_BLUE / UF_ORANGE — use for aggregate summary workbook if xlsx format is chosen (or plain CSV per discretion)

### Established Patterns
- Pin pattern: `pin("R187_<INPUT_NAME>", "<dated input path>")` for each input, with `pinned TRUE/FALSE` logged to KEY (same as R/184 SECTION 0 lines 217–219)
- One script per phase, source from repo root: `source("R/187_anthracycline_exposure.R", local = new.env(parent = globalenv()))`
- Dated filenames: `anthracycline_exposure_patient_<YYYYMMDD>.rds` (internal), `anthracycline_exposure_summary_<YYYYMMDD>.xlsx` (public)

### Integration Points
- R/187 reads the 180-day episode detail RDS (same path R/167 pins; researcher confirms exact env var name)
- R/187 reads `follow_end` from `compute_followup()` output (same survivorship followup RDS that R/184 reads)
- R/187 output is read by Phase 188; record the dated path in `187-01-SUMMARY.md` so R/188 can use it as its pinned default
- R/39, `R/SCRIPT_INDEX.md` and an R/88 structural check for R/187 are Phase 189 (REG-01) work; list them in the SUMMARY as handed off

</code_context>

<specifics>
## Specific Requirements

- `any_anthracycline` is TRUE/FALSE, never NA — corrects ANTH-01 wording. Use `any_chemo` to distinguish "no chemo" (FALSE) from "chemo, no anthracycline" (also FALSE — distinguishable by `any_chemo == TRUE`).
- `years_since_last_anthracycline` denominator = `follow_end` (Phase 161 definition), not a raw `min()` — accounts for death correctly.
- Last dose after `follow_end`: set `years_since_last_anthracycline = NA`, count on KEY, never pass negative.
- Phase 187 output RDS includes `follow_end` so Phase 188 never has to recompute it.
- `days_since_last_anthracycline_dose` (echo-encounter-level) is Phase 188's output, not Phase 187's.
- ROADMAP and REQUIREMENTS updates (moving `days_since` to ECHO-01, fixing ANTH-01/ANTH-02 wording) are a separate quick task run after CONTEXT.md is committed.

</specifics>

<deferred>
## Deferred Ideas

- Mitoxantrone sensitivity row (already defined in Phase 166 D-07a; Phase 188 can add it as a sensitivity if any cohort patients received it — not Phase 187's scope)
- Cumulative dose calculation (cardiotoxicity dose-equivalence) — out of scope for this phase

</deferred>

---

*Phase: 187-anthracycline-exposure-variables*
*Context gathered: 2026-10-22*
