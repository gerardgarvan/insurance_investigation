---
phase: 201-abvd-and-tumor-registry-lymphoma-flags-in-gantt-180
created: 2026-11-13
depends_on: Phase 199 (gantt_episodes_180.csv at 26 columns), Phase 200 (D-200-01)
deliverable_to: AC (gantt_episodes_180.csv)
---

# Phase 201: ABVD and Tumor-Registry Lymphoma Flags in gantt_episodes_180

## Goal

Add four columns to `output/gantt_episodes_180.csv` (R/142), growing it from 26 to 30 columns:

| Col | Name | Level | Type | Meaning |
|----:|------|-------|------|---------|
| 27 | `ever_abvd` | patient | logical, never NA | TRUE if any Chemotherapy episode for the patient is ABVD (see D-01) |
| 28 | `abvd_episode` | episode row | logical, never NA | TRUE on the Chemotherapy episode rows that are ABVD; FALSE on all other rows (other chemo, radiation, SCT, Death, HL Diagnosis, ...). Used to find the initial ABVD treatment (earliest `episode_start` where `abvd_episode` is TRUE) |
| 29 | `tr_hl_dx` | patient | logical, NA allowed | TRUE: an HL histology appears in the tumor registry for this patient. FALSE: the patient is in the tumor registry but has no HL histology. NA: the patient is not in any tumor registry table |
| 30 | `tr_nhl_dx` | patient | logical, NA allowed | Same three-state rule, using NHL histology |

In the CSV, NA is written as a blank cell (`write.csv(..., na = "")`, unchanged).

Then deliver the regenerated file to AC.

## Team request (verbatim intent)

1. Create an "ever" ABVD flag at the patient level. Also create an encounter-level variable so the initial treatment can be identified.
2. Verify the tumor registry diagnosis (HL vs. NHL). Goal: do not exclude patients who have a tumor-registry HL diagnosis.
   - Flag for tumor-registry HL diagnosis: TRUE for HL, FALSE when HL does not appear for that patient, NA for patients who are not in the tumor registry table.
   - Repeat for NHL.
3. All of this goes into the gantt_180 file, which goes to AC.

## What already exists (do not rebuild)

- **Regimen rules:** R/28 Section 5 assigns `regimen_label` (ABVD, BV+AVD, Nivo+AVD) to Chemotherapy episodes by drug name, with a J-code fallback (D-10..D-14, D-19, D-20 in R/28's header). R/28 runs on the 180-day episodes when called with the `p143_*` options, so `treatment_episodes_180_enriched.rds` should already carry `regimen_label`. R/142 does not export it today.
- **Tumor-registry histology:** `ICD_CODES$hl_histology` (9650–9667, in use since the start) and `ICD_CODES$nhl_histology` (quick-260716; header marks it **UNVERIFIED**) in R/00_config.R. The match pattern is in R/14 Step 1 and R/113: `get_pcornet_table("TUMOR_REGISTRY_ALL")`, TR1 `HISTOLOGICAL_TYPE` and TR2/TR3 `MORPH`, `substr(as.character(x), 1, 4) %in% code_list`.
- **R/142 pattern for patient-level flags:** Section 4C2 (autoimmune) and 4C3 (immune / brentuximab) — helper returns one row per patient, `left_join` on `patient_id`, row-count `stopifnot`, suppressed QC block.

## Decisions

### D-01: ABVD definition — recompute on canonical drug names, using R/28's rules
`abvd_episode` is TRUE when a Chemotherapy episode meets R/28's ABVD rule, re-applied in R/142 **after** Section 4D canonicalizes `drug_names`:
- full ABVD: Doxorubicin + Bleomycin + Vinblastine + Dacarbazine, no Brentuximab, no Nivolumab, at most 4 distinct drugs (D-10, D-12);
- AVD (bleomycin dropped): Doxorubicin + Vinblastine + Dacarbazine, no Bleomycin / Brentuximab / Nivolumab, at most 3 distinct drugs (D-11, RATHL);
- episodes with blank `drug_names` fall back to R/28's `regimen_label == "ABVD"` (J-code path, D-19).

**Why recompute:** R/28 counts drugs with `str_count(drug_names, ",") + 1` on the **raw, un-canonicalized** names. A raw string such as `Doxorubicin, Doxorubicin Hydrochloride, Bleomycin, Vinblastine, Vinblastine Sulfate, Dacarbazine` counts as 6 drugs, so the added-agent rule (D-12) drops a real ABVD episode. R/142 Section 4D already collapses those variants (`canonicalize_drug_name`, DRUG_NAME_ALIASES), so counting there is accurate. The R/28 label is kept only as a QC cross-check (D-08) and for the J-code fallback. R/28 itself is **not** changed in this phase (logged as backlog item B-01).

BV+AVD and Nivo+AVD are **not** ABVD for this flag. → open team question D-201-01.

### D-02: `ever_abvd` = any(`abvd_episode`) within patient
Constant within `patient_id`. Patients with no Chemotherapy rows get FALSE.

### D-03: "Encounter-level" variable lives on the episode rows of gantt_episodes_180
Each row of `gantt_episodes_180.csv` is one treatment episode (grouped encounters). `abvd_episode` flags those rows. The initial ABVD treatment is the row with the earliest `episode_start` among `abvd_episode == TRUE` for that patient. `gantt_detail_180.csv` (per-date rows) is **not** changed. → open team question D-201-02.

### D-04: Tumor-registry flags use TUMOR_REGISTRY_ALL histology, three states
For each `patient_id` in the export:
- `tr_present` = ID appears in TUMOR_REGISTRY_ALL (any of TR1/TR2/TR3, any row);
- `tr_hl_dx` = NA if `!tr_present`; else TRUE if any row's 4-digit `HISTOLOGICAL_TYPE` (TR1) or `MORPH` (TR2/TR3) is in `ICD_CODES$hl_histology`; else FALSE;
- `tr_nhl_dx` = same, with `ICD_CODES$nhl_histology`.

A patient can be TRUE for both (both histologies recorded). No date restriction ("ever"). Rows with a blank or non-numeric histology still count toward `tr_present`.

### D-05: NHL code list is unverified — ship the flag with a caveat
`ICD_CODES$nhl_histology` has not been checked against this extract or by a registry SME. The column ships, the KEY/handoff note says so, and the QC block prints every lymphoid-range histology code (9590–9999) seen in the TR rows of export patients that is in **neither** list, with patient counts, so the team can review. → open team question D-201-03.

### D-06: "Do not exclude TR-HL patients" — verify and report; no population change in this phase
R/142 builds the Gantt population from 180-day treatment episodes plus HL Diagnosis pseudo-rows from `confirmed_hl_cohort.rds`. This phase:
1. builds the full TR-HL ID set (all of TUMOR_REGISTRY_ALL, not just export patients);
2. reports how many TR-HL patients are **absent** from `gantt_episodes_180.csv`, split by reason:
   - (r1) not in `confirmed_hl_cohort.rds`;
   - (r2) in the cohort but no `first_hl_dx_date` and no 180-day episodes;
   - (r3) other;
3. writes the absent IDs and reasons to `output/internal/tr_hl_not_in_gantt_180.csv` (internal only, never sent).

Adding the missing patients means changing the cohort build (R/14 / R/55), which is out of scope. If (r1) + (r2) > 0, it goes to the team as D-201-04 and a follow-up phase.

### D-07: Regression — first 26 columns unchanged
Same pattern as Phase 199. Under `RUN_PRE201_REGRESSION=TRUE`, save `output/internal/gantt_episodes_180_PRE201.csv` (26 columns, keep-if-exists) before writing; after writing, check row count, names 1–26, and the sorted pasted rows of columns 1–26 against the baseline. Print `Phase 201 regression: PASS (26 original columns unchanged)`. The existing PRE199 block stays as is (it compares columns 1–23 and still holds).

### D-08: QC console block (counts 1–10 shown as "<11")
- Chemo episodes; `abvd_episode` TRUE (full ABVD vs AVD); via J-code fallback.
- Cross-tab of new `abvd_episode` vs R/28 `regimen_label` (ABVD / BV+AVD / Nivo+AVD / NA) on Chemotherapy rows. Rows where the two disagree are expected mostly where R/28 over-counted salt variants (D-01); print the 10 most common `drug_names` strings for "new TRUE, R/28 NA" (suppressed counts).
- Chemo episodes containing all four ABVD drugs **plus** other agents (excluded by D-12), with the top added agents. This is the input the team needs for D-201-01.
- `ever_abvd` TRUE patients; patients whose **first** Chemotherapy episode is ABVD.
- `tr_present` patients; `tr_hl_dx` TRUE / FALSE / NA; `tr_nhl_dx` TRUE / FALSE / NA; both TRUE.
- Cross-tab `tr_hl_dx` × `is_hodgkin` (patient-level any).
- D-06 absent-from-Gantt counts by reason.
- D-05 unlisted lymphoid histology codes.

### D-09: Handoff to AC
After the HiPerGator run passes R/88, send AC the regenerated `gantt_episodes_180.csv` with a short column note (four new columns, the three-state NA rule, the NHL caveat, the ABVD/AVD definition). The draft note is written into `201-02-SUMMARY.md` for Gerard to send; nothing is emailed automatically. Small-cell suppression applies to any counts in the note.

## Open team questions (defaults apply if no answer)

| ID | Question | Default |
|----|----------|---------|
| D-201-01 | Should BV+AVD (and Nivo+AVD) count toward `ever_abvd`? Should ABVD + an added agent (e.g., rituximab) count? **Also: count ABVD + low-dose oral methotrexate (RxNorm 105585) as ABVD? 4 episodes, \<11 patients, most with RA `immune_flag`. Default: no.** | No / No (R/28 rules) |
| D-201-02 | Does AC also want the ABVD marker on `gantt_detail_180.csv` (per-date rows), or a `first_abvd_date` column? | Episode file only; no date column |
| D-201-03 | Who reviews `nhl_histology` against the extract? | Ship with caveat; review list printed by QC |
| D-201-04 | If TR-HL patients are missing from the Gantt file, should a follow-up phase add them to the cohort? **121 TR-HL patients absent, all r1 (not in confirmed_hl_cohort.rds). Follow-up phase to find which cohort step drops them.** | Report only in this phase |

## Out of scope
- Changing R/26, R/28, R/29, R/52, the 90-day `gantt_episodes.csv`, or `gantt_detail_180.csv`.
- Changing cohort membership (D-06).
- Validating `nhl_histology` (D-05).

## Backlog created
- **B-01:** R/28 J-code fallback (D-19/D-20) runs on episodes that failed drug-name regimen detection and counts only J9xxx codes, so ABVD + RxNorm-coded added agents (ICE, gemcitabine, oral MTX) get `regimen_label = ABVD`. 14 such 180-day episodes found in Phase 201. Fix: restrict fallback to blank `drug_names`, or include non-J-code agents in the added-agent count. The earlier raw-token concern is not supported by the data (0 episodes new-TRUE / R/28-not-ABVD). Separate phase; affects R/28 → R/29 → R/52 outputs.

## Files touched
- `R/00_config.R` — `ABVD_COMPONENTS`, `AVD_COMPONENTS`, `ABVD_EXCLUDING_DRUGS` constants (canonical tokens)
- `R/utils/utils_cancer.R` — `classify_abvd_episode()`, `build_tr_lymphoma_flags()`
- `R/142_gantt_180_export.R` — Sections 4C4 (ABVD) and 4C5 (TR flags), schema 26 → 30, PRE201 regression
- `R/88_smoke_test_comprehensive.R` — 26 → 30 column checks in 15bb [c2] and 15bc [c1]; new Section 15bd
- `R/SCRIPT_INDEX.md` — R/142 outputs line
- `tests/testthat/test-201-abvd-tr-flags.R` — unit tests for both helpers (local)
