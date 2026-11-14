---
phase: 201-abvd-and-tumor-registry-lymphoma-flags-in-gantt-180
plan: 01
status: complete
completed_tasks: 3 of 3
---

# Phase 201 Plan 01 Summary: Config constants, helpers, R/142 Sections 4C4/4C5

**Commits:** feafa44 (Task 1), 652916f (Task 2), a691134 (quick fix — Section 4C4 cross-tab crash)

## What was built

- `ABVD_COMPONENTS`, `AVD_COMPONENTS`, `ABVD_EXCLUDING_DRUGS` added to `R/00_config.R` (Phase 201 block).
- `classify_abvd_episode()` and `build_tr_lymphoma_flags()` added to `R/utils/utils_cancer.R`.
- Unit tests `tests/testthat/test-201-abvd-tr-flags.R` — all 7 cases pass locally.
- `R/142_gantt_180_export.R`: EPISODES_SCHEMA extended to 30 columns; `regimen_label` carry-through; Section 4C4 (ABVD flags + D-08 QC); Section 4C5 (TR flags + D-06 CSV write); PRE201 regression block.
- Quick fix (261113-t4d): Section 4C4 `ct_abvd` cross-tab recode extended to map `""` → `"(none)"`, preventing subscript-out-of-bounds crash from Section 4D's `NA → ""` conversion.

## Canonical ABVD tokens (confirmed on HiPerGator)

`canonicalize_drug_name()` output: **Doxorubicin, Bleomycin, Vinblastine, Dacarbazine**
Excluded: Brentuximab Vedotin, Nivolumab

## HiPerGator run results

**File:** `gantt_episodes_180.csv` — 22,520 rows, 30 columns. Schema verification PASSED.
**Regression:** Phase 201 regression: PASS (26 original columns unchanged). PRE201 baseline saved.

### ABVD QC (D-08)

| Category | Count |
|---|---|
| Chemotherapy episodes | 8,194 |
| `abvd_episode` TRUE — full ABVD | 1,151 |
| `abvd_episode` TRUE — AVD | 529 |
| `abvd_episode` TRUE — JCODE_ABVD | 0 |
| `abvd_episode` FALSE — ABVD_PLUS | 103 |
| `ever_abvd` TRUE patients | 1,525 |
| Patients: first chemo episode is ABVD | 1,466 |

ABVD_PLUS top added agents: Vincristine Sulfate 42, Etoposide 40, Cyclophosphamide 36, Procarbazine 15, Methotrexate 13, Rituximab 13, Gemcitabine/Ifosfamide/Carboplatin/Goserelin \<11 each.

### Cross-tab: `abvd_episode` × `regimen_label`

| abvd_episode | regimen_label | n |
|---|---|---|
| FALSE | (none) | 6,500 |
| FALSE | ABVD | 14 |
| TRUE | (none) | 0 |
| TRUE | ABVD | 1,680 |

**14 FALSE/ABVD episodes:** R/28 labeled these ABVD via its J-code fallback, which counts only J9xxx codes and ignores RxNorm-coded co-administered agents, and runs on any episode that failed drug-name detection (not only blank `drug_names`). All 14 contain added agents (ICE-type carboplatin/ifosfamide/etoposide, gemcitabine, vincristine, cyclophosphamide, or oral methotrexate RxNorm 105585). The new `abvd_episode` flag is correct — no code change. 4 of the 14 are ABVD + oral methotrexate 105585; \<11 patients, most with `immune_flag` TRUE (Rheumatoid Arthritis). → D-201-01 addendum.

0 episodes new-TRUE / R/28-not-ABVD: the earlier raw-token concern (B-01) is not supported by the data.

### Tumor-registry QC (D-08 / D-04)

| Measure | Count |
|---|---|
| `tr_present` TRUE | 863 |
| `tr_hl_dx` TRUE | 600 |
| `tr_hl_dx` FALSE | 263 |
| `tr_hl_dx` NA | 7,557 |
| `tr_nhl_dx` TRUE | 154 |
| `tr_nhl_dx` FALSE | 709 |
| `tr_nhl_dx` NA | 7,557 |
| Both TRUE | 11 |

Cross-tab `tr_hl_dx` × `any(is_hodgkin)`:

| tr_hl_dx | is_hodgkin TRUE | is_hodgkin FALSE |
|---|---|---|
| TRUE | 549 | 51 |
| FALSE | 222 | 41 |
| NA | 6,945 | 612 |

NHL caveat: `nhl_histology` list has not been validated against this extract (D-05, D-201-03).

### D-05 unlisted lymphoid histology codes (D-201-03)

Codes in ICD-O-3 lymphoid range (9590–9999) seen among export patients, in neither `hl_histology` nor `nhl_histology`:

9657, 9675, 9715, 9732, 9735, 9761, 9811, 9812, 9823 (n=13), 9831, 9834, 9836, 9837, 9861, 9867, 9920, 9950, 9962, 9980, 9986, 9989 (all others \<11)

Notes: 9657 likely HL (ICD-O-2 lymphocyte predominance); 9675, 9715, 9735 NHL candidates; 9823 CLL/SLL is a team call; myeloma/Waldenström/leukemia/myeloid codes correctly excluded from both lists.

### D-06 TR-HL patients absent from gantt_episodes_180

| Reason | Count |
|---|---|
| r1: not in confirmed_hl_cohort.rds | 121 |
| r2: in cohort, no dx date / no episodes | 0 |
| r3: other | 0 |

121 TR-HL patients absent, all r1. D-201-04 needed: follow-up phase to identify which cohort step drops them.
`output/internal/tr_hl_not_in_gantt_180.csv` written (ID, reason — internal only).

## Decisions updated after run

- **B-01 revised:** R/28 J-code fallback (D-19/D-20) runs on episodes that failed drug-name detection and counts only J9xxx codes, so ABVD + RxNorm-coded added agents get `regimen_label = ABVD`. 14 such 180-day episodes found. Fix scope: restrict fallback to blank `drug_names`, or include non-J-code agents in the added-agent count. The earlier raw-token concern is not supported (0 new-TRUE / R/28-not-ABVD episodes).
- **D-201-01 addendum:** Count ABVD + low-dose oral methotrexate (RxNorm 105585) as ABVD? 4 episodes, \<11 patients, most with RA `immune_flag`. Default: no.
- **D-201-04 populated:** 121 TR-HL patients, all not in confirmed_hl_cohort.rds. Follow-up phase to find which cohort step drops them.
