# Phase 214: Chemo Combination Change Audit (old vs new Gantt) - Context

**Gathered:** 2026-11-19 (headless, non-interactive)
**Source:** Gerard's add-phase message (docs/combo_audit/combo_audit_prompt.md), ROADMAP v3.15, R/00_config.R (DRUG_NAME_ALIASES line 2950, canonicalize_drug_name line 3044, gantt_180_snapshot_path line 272), R/206 SCHEMA_32 (lines 46-60)

## Phase boundary
- Read-only audit: no change to cohort membership, 7-day logic, D-201-04, or any Gantt output.
- Requirements COMBO-01..07 as written in docs/combo_audit/combo_audit_prompt.md.

## Assumptions (headless run)
- A-214-01: Phase number 214. `gsd-tools phase add` returned 1 (it cannot parse this ROADMAP); its ROADMAP insert and `01-` directory were reverted and the entry added by hand at the end of v3.15.
- A-214-02: **The three reference CSVs are not on this machine.** docs/combo_audit/ holds only combo_audit_prompt.md. The 314/161/29/21 check and the three-file tests cannot run locally. Gerard must copy chemo_combo_check.csv, unique_chemo_drugs.csv and combo_change_list_2026-11-19.csv into docs/combo_audit/. Until then, synthetic fixtures run and the three-file tests skip with a message (`skip_if_not(file.exists(...))`). No assertion weakened or deleted.
- A-214-03: Column names of the three CSVs and of the old/new Gantt are not probed. Gantt names come from R/206 SCHEMA_32 / R/142 (patient_id, treatment_type, episode_start, episode_stop, drug_names, triggering_codes, source_table, code_type); no `.planning/schemas/` probe lists them. CSV header names (drug_names, cause) are unknown. Plan 01 Task 0 adds a probe script; its run is PENDING HIPERGATOR for the Gantt files. Script constants stay marked `# UNVERIFIED` until the probe output is read.
- A-214-04: Old-side candidates in order: `CONFIG$gantt_180_snapshot_path` (gantt_episodes_180_20260814_PINNED.csv), then explicit gantt_episodes_180*.csv files in output/internal/pre_v315_backup/ listed by the probe (no mtime pick). "Reproduces" = normalised distinct combination set of Chemotherapy rows equals the normalised chemo_combo_check.csv set. Report each candidate's extra/missing counts; stop with a clear message if none match. Pins: env `R214_OLD_GANTT`, `R214_NEW_GANTT`, `R214_OLD_COMBOS`, `R214_NEW_COMBOS`, `R214_CHANGE_LIST`, dated defaults, stop if missing.
- A-214-05: Normalisation = split on ';', trim, drop empty tokens, `canonicalize_drug_name()` (Phase 164 map), dedupe, sort (C locale), rejoin with "; ". Blank drug_names is kept as key `(blank)` and counted by treatment_type (COMBO-05).
- A-214-06: `unchanged` = raw string identical on both sides; `label_only` = raw strings differ but normalised key is on both sides; `new` = normalised key only in new; `dropped` = only in old. The unit is the raw string per file, as in the reference files. Count differences from 314/161/29/21 go to QC; no stop.
- A-214-07: Episode matching: same patient_id, treatment_type Chemotherapy, overlapping [episode_start, episode_stop]. Precedence per episode: (e) patient absent from new Gantt, (d) patient absent from old Gantt, (f) 1:n or n:1 overlap, (a) same normalised drug set, (b) new is superset, (c) new is subset, (g) otherwise. "In cohort" = patient_id present in that Gantt file (both are cohort-only after Phase 213); cohort rules are not re-derived. Tumor-registry NHL exclusion is identified for (e) by joining to the existing TR flag columns (tr_nhl_dx, tr_hl_dx in SCHEMA_32) on the old Gantt.
- A-214-08: Cause (b) detail: report added drug, the new episode's source_table, triggering_codes and code_type. "Consistent with Phase 200 R/26 capture fix" = source_table in MED_ADMIN or DISPENSING; "consistent with added Rituximab/Methotrexate codes" = added drug is Rituximab or Methotrexate and the code is in the added-code list, read from R/26/config at execution (not typed from memory). Wording is "consistent with", not "confirmed", unless the old snapshot has no episode for that patient/date window.
- A-214-09: Roll-up: primary cause per combination = most frequent cause among its affected episodes (tie: alphabetical a..g); counts by cause also output. The change-list `cause` column is compared to the computed primary cause (agreement count in QC) and never copied into results.
- A-214-10: Workbook in output/internal/ holds real counts, no IDs, no per-patient dates. A team copy in output/ applies 1-10 -> "<11" to every count column; rates only when numerator and denominator >= 11.
- A-214-11: Script is R/214 (highest existing numbered script is 212). Helpers in `R/utils/utils_combo_audit.R` (pure functions, auto-sourced by config).
- A-214-12: R/88 gets one smoke check; R/39 gets an "analysis only" entry near line 263; SCRIPT_INDEX row after R/208.

## Open questions (do not decide)
- Q-214-01: Is the old-list "combination" unit the raw drug_names string (assumed) or a patient-level regimen?
- Q-214-02: Is the blank drug_names row a chemo row with no mapped drug, or a non-chemo row? COMBO-05 counts by treatment_type to inform this.
- Q-214-03: Is Ofatumumab's absence a capture loss or an intended removal? The audit reports facts only.
- Q-214-04: Per-drug code attribution may need per-code rows from R/142; confirm after the probe.
