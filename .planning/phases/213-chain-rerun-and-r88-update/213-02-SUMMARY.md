# 213-02 SUMMARY (COMPLETE)

## HiPerGator results (2026-11-17, pasted by Gerard)
- Task 1 pre-run rows: stage1 19,324; stage2 19,324; _180 13,770; _180_enriched 13,770.
- Task 2 R/26: stage1 19,324 OK; _180 13,770 OK. Phase 204 capture: chemo 4,514 patients, 12,295 episodes; total 19,324 episodes, 5,018 patients; detail 265,257 rows.
- Task 3 R/28 default: stage2 19,324 OK. regimen_label: ABVD 1,674; AVD 571; BV+AVD 842; Nivo+AVD 149; ABVD_PLUS 146; Unrecognized 2,043.
- Task 4 R/28 p143: enriched 13,770 OK; mtime 2026-11-17 14:04:36 (fresh). 180d regimen_label: ABVD 1,124; ABVD_PLUS 168; AVD 244; BV+AVD 508; Nivo+AVD 86.
- No MISMATCH. Gate passed; continue to 213-03.

## Assumptions (headless run)
- Row counts unchanged as expected (DEC-213-02): episodes are built for all extract patients, not the cohort, so the new cohort does not move them.
- Task 4 mtime date matches the run date (2026-11-17), so the staleness guard is treated as passed.
