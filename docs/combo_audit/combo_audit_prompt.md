/gsd:add-phase 'Chemo combination change audit: old vs new Gantt'. Run non-interactively: do not ask questions; record assumptions and open questions in the phase CONTEXT. Then write the CONTEXT and PLAN for the phase.

Goal: account for every change in the set of distinct chemo drug_names combinations between the old combination list (docs/combo_audit/chemo_combo_check.csv, 498 rows) and the new Gantt (docs/combo_audit/unique_chemo_drugs.csv, 504 rows plus one blank), and deliver a list of all new combinations with the confirmed reason each one changed. docs/combo_audit/combo_change_list_2026-11-19.csv is the starting classification; its cause column is an unconfirmed hypothesis to test, not a result.

COMBO-01 New script R/NNN_combo_change_audit.R (next free number). Normalise both sides: split on ';', trim, apply the existing Phase 164 drug alias map from config (Adriamycin and Doxorubicin Hydrochloride -> Doxorubicin), dedupe, sort, rejoin. Classify every combination as unchanged / label_only / new / dropped. Expected from the reference files: 314 / 161 / 29 / 21. Report differences from these numbers in QC; do not fail on them.

COMBO-02 Identify the old Gantt snapshot that reproduces chemo_combo_check.csv (candidates: the pinned 2026-08-14 gantt_episodes_180 snapshot, output/internal/pre_v315_backup/). Stop with a clear message if none reproduces it. The new side is the current gantt_episodes_180.csv.

COMBO-03 For each new and each dropped combination: number of episodes and patients carrying it (new Gantt for new, old snapshot for dropped).

COMBO-04 Attribute a cause per affected episode by matching old and new episodes on patient_id and overlapping episode dates. Categories: (a) label normalisation only; (b) drug added to an existing episode - record which drug, source_table and triggering code, and whether it traces to the Phase 200 R/26 MED_ADMIN/DISPENSING capture fix or the added Rituximab/Methotrexate codes; (c) drug removed from an existing episode; (d) patient newly in cohort under the v3.15 rules; (e) patient no longer in cohort (including tumor-registry NHL exclusion); (f) episode boundaries changed (split or merge); (g) unexplained. Roll up to one primary cause per combination plus counts by cause.

COMBO-05 Specific checks: the 11 old combinations whose only new counterpart is the same combination plus Rituximab; all combinations containing Brentuximab Vedotin, Nivolumab or Pembrolizumab (absent from the old list); Ofatumumab (in the old list, absent from the new); the blank drug_names row in the new file - count by treatment_type.

COMBO-06 Deliverable workbook in output/internal/: KEY sheet leftmost, then New_combinations, Dropped_combinations, Label_only, Cause_summary, QC. Small-cell suppression (1-10 -> '<11') in any version meant for the team. UF colours, Arial.

COMBO-07 Register in R/39, R/88 (one smoke check) and SCRIPT_INDEX; testthat fixtures for normalisation and classification using the three docs/combo_audit files.

Constraints: local-first edits; never try to reach HiPerGator or real data; end the plan with a HiPerGator checkpoint giving interactive R console steps (module load R/4.5, then R), not sbatch; commit by explicit path only; do not push.
