# 213-04 SUMMARY (COMPLETE)

## HiPerGator results (2026-11-17, pasted by Gerard)
- R/52 rerun (cohort-only filter): removed 617 episode rows, 7,554 detail rows, 128 patients (all TR-NHL-only, other 0). gantt_episodes.csv 28,968 rows, 23 cols, 9,179 patients; detail 267,964 rows; Death rows 1,030; all chk OK.
- R/142: removed 468 episode rows, 128 patients (all TR-NHL-only). gantt_episodes_180.csv 23,563 rows, 34 cols, 9,179 patients; detail 267,964; all chk OK. D-06: all TR-HL patients present (D-201-04 resolved).
- abvd_class (180, pre-filter): ABVD 1,124; AVD 244; ABVD_PLUS 168; BV+AVD 246; Nivo+AVD 42.
- Label diff vs pre-v3.15 delivered 180 file: patients in both 8,278; old rows 21,964; new rows 22,662; old episodes without new match 310; abvd_class changed 3,332, all NA -> label (no ABVD or BV+AVD label changed).
- R/206 direct: all checks pass, file unchanged. Final flags: abvd_episode 1,248; avd_episode 570; ever_abvd 1,163 patients; ever_avd 520; both 51; abvd & avd in same episode 0.

## Findings
- Task 3 expected 0 unmatched old episodes; actual 310. Breakdown by treatment_type is in the plan 05 HiPerGator block (Task 4b). Not a gate (DEC-213-01).

## Code fix (local, 2026-11-17)
- `chk_true(label, cond)` added to `R/tools/213_chain_checks.R` (OK/FAIL, no suppression). R/206 direct mode uses it for the boolean checks (previously printed `EXPECT <11 | ACTUAL <11` because `chk_expect` suppresses 0/1). Test added in `tests/testthat/test-213-chain-checks.R`.

## Assumptions (headless run)
- Plan 04 marked complete on the pasted results; the label-diff review gate (Gerard) remains open for the 310 unmatched episodes.
