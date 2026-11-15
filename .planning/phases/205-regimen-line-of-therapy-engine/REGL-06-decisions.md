# Phase 205 Open Decisions (REGL-06)

These decisions require SME confirmation before Phase 205 results are interpreted.
Current pipeline defaults are shown; they remain in force until a decision is logged
and the config is updated. Open decisions do not block pipeline execution; they affect interpretation only.

Written 2026-11-14 (headless fix: R/88 SMOKE-205-01 [g] expects this exact path; Plan 205-03 Task 2 had not been executed).

| ID | Decision | Current Pipeline Default | Status |
|----|----------|--------------------------|--------|
| REGL-06-A | SME confirmation of the regimen family list (10 families in REGIMEN_DICT) | REGIMEN_DICT in R/00_config.R: ABVD, AVD, BV+AVD, Nivo+AVD, BEACOPP, escBEACOPP, Pediatric, R-CHOP, R-CVP, Salvage, Rituximab_mono, BV_consolidation (NLPHL removed 2026-11-14: a diagnosis, not a regimen) | OPEN |
| REGL-06-B | LOT gap length: treatment-free interval (non-maintenance drugs) that starts a new line | LOT_GAP_DAYS = 90L in R/00_config.R | OPEN |
| REGL-06-C | BV consolidation: maintenance (no new LOT) vs active treatment (new LOT) | Maintenance; BV_consolidation is assigned only when BV-only therapy starts on/after an SCT episode start and within BV_CONSOLIDATION_SCT_WINDOW_DAYS (90, assumed = LOT_GAP_DAYS) after SCT stop; MAINTENANCE_DRUG_CLASSES = c("BV_consolidation", "Rituximab_mono") in R/00_config.R | OPEN |
| REGL-06-D | NLPHL handling: R-CHOP / R-CVP / rituximab mono distinguished or grouped | Interim 2026-11-14: "NLPHL" label removed; R-CHOP, R-CVP and Rituximab_mono are separate families. Histology not used | OPEN |
| REGL-06-E | escBEACOPP vs BEACOPP: dose-level distinction | Same drug set in REGIMEN_DICT; dose not available from administration data alone | OPEN |
| REGL-06-F | Salvage list completeness (ICE/GVD/IGEV, BV-bendamustine, BV-nivolumab, pembrolizumab or nivolumab mono) | Salvage entry holds ifosfamide, carboplatin, etoposide only; others get "Unrecognized systemic" (Chemotherapy) or NA (Immunotherapy) | OPEN |
| REGL-06-G | Concurrency window: days around episode start in which drugs count toward the same regimen | CONCURRENCY_WINDOW_DAYS = 7L in R/00_config.R | OPEN |
| REGL-06-H | ABVD_PLUS vs BV+AVD reconciliation: how Phase 201 `abvd_class` values (ABVD with an added agent; BV+AVD / Nivo+AVD excluded from ABVD) map to Phase 205 `regimen_label` | Phase 205 labels by REGIMEN_DICT (exclusive match); R/205_reconciliation.R cross-tabulates `abvd_class` x `regimen_label` (REGL-05) | OPEN |
| REGL-06-I | D-201-01 (carried from Phase 201): count ABVD + low-dose oral methotrexate (RxNorm 105585) as ABVD? 4 episodes, <11 patients, mostly RA `immune_flag` | No (ABVD_EXCLUDING_DRUGS in R/00_config.R; `abvd_episode` unchanged). Phase 205 ABVD is `exclusive = TRUE`, consistent | OPEN |

## Impact on Phase 205 Results

- **A**: Unlisted regimens get "Unrecognized systemic" (Chemotherapy) or NA (Immunotherapy); "Other" no longer exists. Added families require re-running R/28 and R/205.
- **B**: Shorter gap gives more LOT splits; longer gap gives fewer. 90 days is a common convention; confirm with the analysis team.
- **C**: Reclassifying BV consolidation as active treatment adds a LOT for post-ASCT patients and changes `n_lines`.
- **D**: Separating NLPHL sub-types needs REGIMEN_DICT expansion and histology data.
- **E**: escBEACOPP needs dose data; feasibility depends on the MED_ADMIN/DISPENSING extract.
- **F**: Expanding Salvage needs SME input on qualifying combinations.
- **G**: Wider window merges more near-simultaneous drugs into one regimen; narrower window can split a cycle into partial regimens.
- **H**: Episodes that Phase 201 labelled ABVD-with-added-agent may be labelled "Unrecognized systemic" or Salvage in Phase 205; the reconciliation table quantifies this.
- **I**: Counting methotrexate-added episodes as ABVD would move <11 patients; no effect on cohort membership.

## Notes

- Update Status to RESOLVED with date when the SME confirms a decision, and update config accordingly.
- SCT-triggered LOT boundaries (REGL-06-B TODO in R/205_lot_output.R, R/28) remain pending an SCT schema probe.

## Fix 2026-11-14: labels leaked onto non-systemic episodes (headless fix)

Root cause: `episode_number` is unique only within (patient_id, treatment_type). `assign_regimen()` grouped on (ID, episode_number) and R/28 joined on (patient_id, episode_number), so Chemotherapy labels copied onto Radiation/SCT/Proton episodes with the same number. Changes:
- `assign_regimen()` keys on (ID, treatment_type, episode_number); only Chemotherapy/Immunotherapy rows are returned. Drugs are pooled across the patient's Chemotherapy + Immunotherapy rows within the window so BV+AVD / Nivo+AVD still match.
- No match: Chemotherapy with drug names = "Unrecognized systemic"; otherwise NA. Immunotherapy is labeled only when all its drugs belong to the matched family. "Other" removed.
- NLPHL family replaced by R-CHOP / R-CVP / Rituximab_mono.
- BV_consolidation needs a prior SCT episode (see REGL-06-C).
- R/205 section 1B prints regimen_label x treatment_type and stops if any non-systemic episode is labeled, any "Other" remains, or an Immunotherapy episode is "Unrecognized systemic".

### Reconciliation with R/142 abvd_class (REGL-06-H)

| Label | R/142 delivered 180-day file (old abvd_class) | stage2 label counts, pre-fix run (all 19324 episodes, inflated by leak) |
|---|---|---|
| ABVD | 1109 | 1561 |
| AVD | 236 | 730 |
| BV+AVD | 251 | 739 |
| Nivo+AVD | 42 | 144 |
| ABVD_PLUS | 186 | not a family; maps to "Unrecognized systemic" (ABVD + added agent fails the exclusive match) |

- The two columns are not comparable: the pre-fix counts include non-Chemotherapy episodes that inherited labels and cover all stage2 episodes, not the 180-day episode set.
- Expected after fix: ABVD/AVD/BV+AVD/Nivo+AVD counts fall toward the delivered values; Unrecognized systemic should absorb the 186 ABVD_PLUS episodes plus other unmatched chemotherapy. Differences remaining after the fix are explained by (a) the 7-day pooled window, (b) cross-type pooling, (c) 180-day episode merging in R/142 vs stage2 episodes.
- R/142 still tests `abvd_class == "ABVD_PLUS"` for `ever_abvd_plus`; with the new labels that flag will be all FALSE. Decision needed: derive `ever_abvd_plus` from "Unrecognized systemic" episodes containing all ABVD drugs, or retire the column. Not changed here.

PENDING HIPERGATOR: post-fix counts. After re-running R/28 then R/205, paste the R/205 `QC regimen_label x treatment_type` table (about 25 lines) to complete this table.

```r
module load R/4.5
R --no-save
source("R/28_episode_classification.R", local = new.env(parent = globalenv()))
source("R/205_lot_output.R", local = new.env(parent = globalenv()))
```

## First-run problems and status (2026-11-14, quick 261114-s48)

Phase 205 status: code written; NOT run on HiPerGator; pending scope review after 202-204 results.

First-run problems (earlier run, before fix):
- Regimen labels on Radiation / SCT / Proton episodes.
- "Other" = 6,591 episodes.
- "NLPHL" appeared as a label.
- BV_consolidation = 1,325.

Fix: commit 46c7389 (label only systemic episodes; key regimens on treatment_type; drop Other/NLPHL).

Before the next run:
- Re-run against the Phase 204 Gantt (22,548 rows), not the pre-204 file.
- Include a regression comparison to `abvd_class` (REGL-05 reconciliation).
- BV_consolidation 1,325 needs review under REGL-06-C.

Scope input from Phase 204: only 54.6% of treatment episodes carry `drug_names`. The remaining Rituximab (Gantt 478 vs raw 772) and Brentuximab (776 vs 954) gaps come from drug-name attribution on episodes, not missed administrations. Regimen assignment depends on `drug_names`, so the engine will under-label until attribution is addressed. Decide in scope review whether to fix attribution before or inside Phase 205.

## Second HiPerGator run (2026-11-14) and revision (quick 261114-sir)

Outputs NOT shipped; Phase 204 files restored; 205 candidates in `output/internal/p205_candidate/`.

Findings (180-day file):
- abvd_class 204 -> 205 (chemo episodes): ABVD 1,109 -> 851 (+18 AVD, 50 Unrecognized, **190 blank**); ABVD_PLUS 186 -> mostly ABVD/AVD/BV+AVD/Unrecognized (26 blank); AVD 236 -> 197 (31 blank); BV+AVD 251 -> 175 (38 blank); Nivo+AVD 42 -> 34 (1 blank).
- All 190 ABVD blanks have episode drug set exactly Bleomycin;Dacarbazine;Doxorubicin;Vinblastine; all 38 BV+AVD blanks have Dacarbazine;Doxorubicin;Vinblastine.
- "Unrecognized systemic" (2,464 episodes) holds known regimens: CHOP backbone 110, BEAM components 94, BEACOPP 82, R-CHOP 73, full ABVD 54, CHOEP 47, partial ABVD (Bleo+Dac+Dox) 35, AVD 29, plus Bendamustine, salvage agents, methotrexate alone (253), leuprolide (30).
- LOT assigned to all 19,324 episodes incl. Radiation/SCT/Proton; n_lines up to 19. R/29 first-line counted any label: 2,536 patients (1,245 Unrecognized) vs 1,379 before.
- R/205 default stage2 path pointed at output/internal/; column-count guard did not compare values.

Root cause of blanks (code reading; confirm on HiPerGator): `assign_regimen()` built episode keys only from date-level rows (`episode_detail` rows with a non-blank `drug_name`). Episodes with `drug_names` but no such rows were never keyed, so the left join in R/28 returned NA. The date-level pool could also be polluted by neighbouring drugs within +/-7 days. R/28 now prints the count of systemic episodes with drug_names but no date-level rows, so the cause can be confirmed.

Changes:
- Labels: every Chemotherapy/Immunotherapy episode with drug_names gets a label, never NA. Priority: strict date-level match, strict episode-level match (pooled), strict own-drugs match, loose matches (ABVD_PLUS, ABVD/AVD partial), then "Unrecognized systemic". `regimen_basis` = "date" or "episode"; `regimen_detail` holds the salvage family or other detail. Separators "," and ";" both handled (`split_drug_names()`).
- Immunotherapy episodes outside any regimen now get "Unrecognized systemic" (previously NA); R/205 QC no longer stops on this.
- REGIMEN_DICT: BEACOPP (+/- procarbazine, prednisone), CHOP, R-CHOP, CHOEP, BR, Bendamustine mono, BEAM (Conditioning (BEAM) within BEAM_SCT_WINDOW_DAYS = 30 of an SCT episode, else Salvage), salvage families (ICE, ESHAP, DHAP, GVD, GDP, gemcitabine-based, platinum-based) under one "Salvage" label, ABVD/AVD partial, Non-lymphoma / supportive (leuprolide; methotrexate alone with immune_flag / autoimmune dx, applied in R/142). escBEACOPP stays in the dictionary but is not auto-matched (dose-based).
- LOT: only recognized systemic regimens; NA for Unrecognized, Non-lymphoma, Radiation, SCT, Proton. New line on family change or same family after gap >= LOT_GAP_DAYS. BV_consolidation, Rituximab_mono and Conditioning (BEAM) attach to the current line. SCT no longer starts a line. Families: `REGIMEN_LOT_FAMILY_MAP` in utils_regimen.R (ABVD family = ABVD, AVD, BV+AVD, Nivo+AVD, ABVD_PLUS, partial).
- R/29 first-line: `first_line_eligible()` (ABVD family, BEACOPP, BV+AVD, Nivo+AVD, CHOP family, BR, Pediatric); excludes Unrecognized, Salvage, Conditioning, Non-lymphoma, maintenance.
- R/205: stage2 default from `CONFIG$cache$outputs_dir`; value-level reconciliation vs pinned `R205_BASELINE_GANTT`; warns (does not stop) on > 5% change in any ABVD-family class; QC lists patients with > 4 lines and top sequences.

Open decisions:
- **D-201-01 (ABVD_PLUS):** kept as a loose class (AVD drugs + any agent other than BV / nivolumab) so `abvd_class` stays comparable to the delivered file. Decide whether to keep, rename or retire it.
- **Partial AVD:** "ABVD/AVD partial" = two or more ABVD drugs and nothing else, from the drug set alone. Decide whether a partial set counts as ABVD for `ever_abvd` / first-line (currently counted for first-line, not for `abvd_episode`), and whether the "within an ABVD course" wording needs a date-based rule.
- BEAM window (30 days), CHOP-family grouping for LOT, and Pediatric first-line eligibility are assumptions.

PENDING HIPERGATOR: re-run, then paste the output lines named in the SUMMARY.

## Fix round 4 (2026-11-14, quick 261114 round 4)

Changes (R/00_config.R, R/utils/utils_regimen.R, R/205_lot_output.R, R/28_episode_classification.R, tests/testthat/test-205-regimen-round4.R):
- CHOP / R-CHOP / CHOEP / BEACOPP: already in REGIMEN_DICT at a04c74b and resolve in unit tests for the exact drug sets (any order, comma or semicolon). Drug tokens are now also normalized (trailing "(IV)", salt words). If HiPerGator still shows them as "Unrecognized systemic", R/28 now prints the top 15 unrecognized drug sets so the cause is visible.
- New dictionary entries: BV mono, BV+Nivo, BV+PD-1, PD-1 mono (detail = agent; both agents = "(switch)"), Other checkpoint (non-HL), Non-HL agent. BV_consolidation still wins when an SCT episode precedes BV mono. "Other checkpoint (non-HL)" and "Non-HL agent" are in REGIMEN_NON_HL_LABELS: no LOT, never first-line. BV mono, PD-1 mono, BV+Nivo, BV+PD-1 count in LOT as salvage lines and are not first-line.
- ABVD family is now episode-anchored (`adjust_abvd_family()`, `classify_abvd_set()`): for a Chemotherapy episode whose drugs include doxorubicin, vinblastine and dacarbazine, the drug set is pooled with every systemic row (any treatment_type) within +/-CONCURRENCY_WINDOW_DAYS of the episode's administration-date span (first - 7 to last + 7).
  - No extras: ABVD (bleomycin) / AVD. AVD + BV: BV+AVD (BV wins over nivolumab). AVD + nivolumab: Nivo+AVD. ABVD + BV or nivolumab: ABVD_PLUS (Phase 201 rule).
  - Any other agent: ABVD_PLUS; regimen_detail lists the added agents.
  - Supportive agents (SUPPORTIVE_AGENTS: leuprolide, goserelin, triptorelin, histrelin, nafarelin, buserelin) are ignored.
- R/205 reconciliation prints a drug-set breakdown for every 204 -> 205 class change with n >= 11, writes it to the reconciliation CSV (section drugset_204_to_205), and reports the BV+AVD / Nivo+AVD residual vs 204. The >5% warnings are kept.
- Deviation: the existing test "Strict episode-level match beats a polluted date-level pool" expected ABVD with a prednisone row 2 days away; under rule (c) that is ABVD_PLUS, so the test now asserts that and adds a far-away (stays ABVD) case.
- Known difference from the Phase 201 code: R/142 used Immunotherapy BV/nivolumab rows only; 205 pools any systemic row, per the round-4 request. Rule (c) also counts any non-supportive agent (not only BV / nivolumab) as "plus". The residual vs 204 is reported in R/205; expected non-zero where 204 ignored other agents.

PENDING HIPERGATOR: re-run R/28, R/142 (p143 options), R/205; paste the R/28 "Top 'Unrecognized systemic' drug sets" lines, the R/205 `204 -> 205 class changes` block, and the two `residual vs 204` lines.

```r
module load R/4.5
R --no-save
source("R/28_episode_classification.R", local = new.env(parent = globalenv()))
source("R/142_gantt_180_export.R", local = new.env(parent = globalenv()))
source("R/205_lot_output.R", local = new.env(parent = globalenv()))
```

### Open policy decisions (team)

| ID | Question | Proposed | Status |
|----|----------|----------|--------|
| D-201-01 | Does ABVD_PLUS exclude supportive agents (leuprolide, goserelin, GnRH agonists)? | Yes (implemented via SUPPORTIVE_AGENTS) | OPEN, confirm |
| REGL-06-J | Does "ABVD/AVD partial" count toward `ever_abvd`? | No (unchanged) | OPEN |
| REGL-06-K | Bendamustine mono / BR in HL first-line: likely NHL or elderly patients | Exclude from HL first-line and report separately. NOT yet implemented: both remain in REGIMEN_FIRST_LINE_LABELS until decided | OPEN |

## Fix round 5 (2026-11-14, HiPerGator run 4 = commit 02c067e, results in output/internal/p205_candidate_v3)

Run-4 reconciliation vs 204: ABVD 1108/1109 kept; AVD 236/236; Nivo+AVD 42/42; BV+AVD 242/251 (13 episodes differ); ABVD_PLUS 166/186 (16 -> ABVD, supportive leuprolide/goserelin); ever_abvd 1230 -> 1250.

- **LOT rule (REGL-06-B, revised).** A new line starts only when the regimen family changes. A same-family restart stays on the same line unless the gap is >= `LOT_SAME_FAMILY_RESTART_DAYS` (new constant in R/00_config.R, default 365). `LOT_GAP_DAYS` (90) is kept for compatibility but no longer opens lines. BV mono, PD-1 mono, BV+Nivo and BV+PD-1 are separate families (each is its own label); consecutive identical labels collapse onto one line. Reason: run 4 had 76 patients with > 4 lines (max 14) from same-regimen restarts after >= 90 days (e.g. `3:BV mono;4:BV mono`, `1:ABVD;2:ABVD;3:ABVD`, `PD-1 mono;PD-1 mono`). New n_lines distribution and the > 4-line QC are printed by R/205 (section 3).
- **Chemotherapy episode labels (own drugs first).** 68 Chemotherapy episodes (90-day stage2) were labelled BV mono / PD-1 mono although their own drug_names lacked brentuximab / nivolumab / pembrolizumab (e.g. Bendamustine; Carmustine+Etoposide; Gemcitabine; Cisplatin+Gemcitabine), because the date-level pooled concurrency pass won. `assign_regimen()` now drops an immunotherapy-only candidate (`REGIMEN_IMMUNO_ONLY_LABELS`: BV mono, PD-1 mono, BV+Nivo, BV+PD-1) on a Chemotherapy episode whose own drug set (`own_drug_sets_chemo()`) has none of those agents, and falls back to the own-drugs label. Concurrent BV / nivolumab only upgrades an AVD-family set to BV+AVD / Nivo+AVD (`adjust_abvd_family()`, Phase 201 rule). Hard QC in R/205 section 1B stops if any such episode remains (must be 0).
- **BV+AVD residual (13 episodes).** R/205 now prints their drug sets by direction (204 vs 205) and writes them to the reconciliation CSV (section `bv_avd_residual_drugsets`). Counts 1-10 shown as `<11`.

PENDING HIPERGATOR: re-run R/28, R/142 (p143 options), R/205. Paste back: the R/205 `QC Chemotherapy episodes labelled BV mono / PD-1 mono` line, the `n_lines distribution` table, the `QC patients with > 4 lines` block, the `BV+AVD residual episodes by direction and drug set` table, and the two `residual vs 204` lines.

```r
module load R/4.5
R --no-save
source("R/28_episode_classification.R", local = new.env(parent = globalenv()))
source("R/142_gantt_180_export.R", local = new.env(parent = globalenv()))
source("R/205_lot_output.R", local = new.env(parent = globalenv()))
```

### Open team decisions (round 5)

| ID | Question | Current behaviour | Status |
|----|----------|-------------------|--------|
| D-201-01 | Supportive agents (leuprolide, goserelin, other GnRH agonists) excluded from ABVD_PLUS? | Excluded via SUPPORTIVE_AGENTS; 16 ABVD_PLUS episodes in 204 become ABVD | OPEN, confirm |
| REGL-06-J | Do "ABVD/AVD partial" episodes count toward `ever_abvd`? | Not counted (unchanged) | OPEN |
| REGL-06-K2 | NHL-family first-line regimens (R-CHOP 115, CHOP 108, Bendamustine 82, BR 48 patients) suggest non-HL or composite cases | Still in REGIMEN_FIRST_LINE_LABELS; report separately, no exclusion implemented | OPEN, report separately |
| D-205-LOT-RESTART | Same-family restart threshold for a new line | 365 days (`LOT_SAME_FAMILY_RESTART_DAYS`) | OPEN, confirm |
