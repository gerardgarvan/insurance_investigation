# 213-05 SUMMARY (COMPLETE, R/88 rerun pending)

## HiPerGator results (2026-11-17, pasted by Gerard)
- Task 4b: unmatched old 180 episodes 310, all HL Diagnosis, all differ only by episode_start (`first_hl_dx_date` recomputed on Rule A rows, including the ADMIT_DATE fallback). Patient+type absent from new: 0.
- R/203: cohort 9,179; no_tx 4,283; treated 4,896 (was 3,246 / 4,450); observable 3,348; TR-treated among observable 150. KEY FINDING: TR treated among no_tx 254 of 4,283. Probable prevalent 546. Workbook `output/203_no_treatment_characterization_20261117.xlsx`.
- R/208: cohort 9,179; chemo-type record 4,329; R/203 no_tx 4,283; QC 0/0. Workbook `output/208_site_treatment_data_completeness_20261117.xlsx`.
- R/88 (pre-edit): 15 of 1,165 failed = 9 pre-v3.14 baseline + 6 expected v3.15 (32-column checks: AUTOIMMUNE-FLAG-192.2 [c2], IMMUNE-FLAG-199 [c1], ABVD-TR-201 [c1], DECISIONS-206 [b]; abvd_class value-set checks: ABVD-TR-201 [d3], DECISIONS-206 [c]).

## R/88 edits (local, parse OK)
- 32 -> 34 columns: AUTOIMMUNE-FLAG-192.2 [c2], IMMUNE-FLAG-199 [c1], ABVD-TR-201 [c1], DECISIONS-206 [b] (skip labels updated).
- New ABVD-TR-201 [c8]: avd_episode at col 33, ever_avd at col 34.
- ABVD-TR-201 [d3] rewritten: valid set = REGIMEN_DICT labels + REGIMEN_UNRECOGNIZED_LABEL + ABVD / AVD / ABVD_PLUS / BV+AVD / Nivo+AVD / JCODE_ABVD / blank (DEC-213-01; abvd_class = Phase 205 regimen_label, R/142 ~line 899). Replaces the Phase 201b set.
- DECISIONS-206 [c] retired, superseded by DEC-213-01 (replaced by [d3], not loosened). [d], [e] kept. `p206_old` still read but now unused.
- 9 baseline failures unchanged (baseline, out of scope).

## R/203 edits (local)
- EXPECTED_NO_TX 4,283; EXPECTED_TREATED 4,896; QC labels updated; non-cohort expectations 166 / 558 -> 0 / 0 (Gantt is cohort-only).

## Verification
- `tools/rcheck.sh parse` R/88, R/203: OK. `tools/rcheck.sh test 203`: pass.
- Full suite: 4 failures in `test-205-regimen-dict.R` (lines 181, 188, 198, 203: "BV mono" vs "Unrecognized systemic"). Not touched by this plan; REGIMEN_DICT behaviour vs test, needs a separate look.

## R/88 rerun (HiPerGator, 2026-11-17) - RESULT
- 9/1165 failed (3 skipped). The 9 failures are exactly the pre-v3.14 baseline: 192b, IMMU x2, Linkage Improvement, SMOKE-165 [5] and [11], AUTOIMMUNE-192.2 h3a-c.
- All v3.15 checks pass: 34 columns, DEC-213-01 label set, Phase 213 section.
- No new failures from Phase 213 edits.

## Stale outputs still on the old cohort (follow-up, v3.15)
- R/31, R/32, R/34, R/48, R/49, R/77, R/177, R/39 runner, R/202, R/59 (if skipped). R/115: wording edit only.

## Assumptions (headless run)
- Phase 213 marked complete on the results above; the R/88 rerun is a confirmation, not a gate.
- [d3] uses REGIMEN_DICT labels at run time rather than a typed list, so it follows config.
