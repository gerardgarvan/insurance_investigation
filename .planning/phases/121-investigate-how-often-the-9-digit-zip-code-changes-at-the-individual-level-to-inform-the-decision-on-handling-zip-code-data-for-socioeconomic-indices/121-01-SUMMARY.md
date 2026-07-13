---
phase: 121-investigate-how-often-the-9-digit-zip-code-changes-at-the-individual-level-to-inform-the-decision-on-handling-zip-code-data-for-socioeconomic-indices
plan: "01"
subsystem: investigation
tags: [zip, address, socioeconomic, investigation, read-only, xlsx]
dependency_graph:
  requires:
    - R/00_config.R (auto-sources utils chain including parse_pcornet_date)
    - R/utils/utils_treatment.R (get_hl_patient_ids, optional)
  provides:
    - R/106_zip_change_frequency.R (new read-only Phase 121 investigation)
    - output/zip_change_frequency.xlsx (at runtime on HiPerGator)
  affects:
    - R/39_run_all_investigations.R (20-entry vector, R/106 final comma-less)
    - R/88_smoke_test_comprehensive.R (Section 15s, 14 checks)
    - R/SCRIPT_INDEX.md (Post-Renumber count 6->7, Total 92->93)
tech_stack:
  added: []
  patterns:
    - probe-first file.exists() gate (quit(status=0) not stop())
    - add_styled_sheet() verbatim from R/100 (DARK_GRAY/WHITE/DARK_TEXT colors)
    - normalize_zip9() with str_remove_all("-") before str_pad(9) then ^[0-9]{9}$ regex
    - HIPAA suppress_small() helper (cells <=10 -> "<11")
    - group_by(ID) per-patient distinct ZIP counts with !is.na filter before n_distinct
    - IS_LOCAL-gated runtime check (Section 15s Check 14, mirrors Section 15p)
key_files:
  created:
    - R/106_zip_change_frequency.R
  modified:
    - R/39_run_all_investigations.R
    - R/88_smoke_test_comprehensive.R
    - R/SCRIPT_INDEX.md
decisions:
  - R/106 probes LDS_ADDRESS_HISTORY via file.exists() on ADDR_FILENAME constant; exits gracefully with quit(status=0) if absent (D-02)
  - normalize_zip9 strips hyphen with str_remove_all before str_pad(9) to handle NNNNN-NNNN format (Pitfall 1)
  - ZIP5 sourced from ADDRESS_ZIP5 column when non-NA; falls back to str_sub(zip9_norm,1,5); mismatch count logged (Pitfall 3)
  - ADDRESS_PREFERRED fallback: if fill rate <5%, tie-break uses recency only; documented in Sheet 4 subtitle (D-11)
  - Sheet 3 time-between-changes uses distinct sorted ADDRESS_PERIOD_START dates per patient before lead() (Pitfall 7)
  - Section 15s Check 10 grep uses \\^\\[0-9\\]\\{9\\}\\$ (escaped regex matching the literal R string in R/106)
  - Pre-existing R/88 paren imbalance (28 diff, open > close) predates Phase 121; Section 15s additions are balanced (81/81)
metrics:
  duration: "~15 minutes"
  completed: "2026-07-13"
  tasks_completed: 3
  files_created: 1
  files_modified: 3
---

# Phase 121 Plan 01: ZIP Change Frequency Investigation Summary

## One-liner

Read-only R/106 investigation: probe-first LDS_ADDRESS_HISTORY gate + per-patient ZIP9/ZIP5 distinct-count metrics + 5-sheet styled xlsx (distribution, change-rates with ZIP9-change-only, time-between-changes, most-recent-vs-modal tie-break, recommendation/metadata) + HIPAA suppression + console summary, wired into R/39 runner and R/88 Section 15s (14 structural checks).

## What Was Built

**R/106_zip_change_frequency.R** (756 lines) — a self-bootstrapping, read-only investigation script:

- **Section 2 (Probe gate, D-02):** Probes `CONFIG$data_dir/LDS_ADDRESS_HISTORY_Mailhot_V1.csv` via `file.exists()`; if absent, prints a clear diagnostic message and exits with `quit(status = 0)` (not `stop()`). A comment flags the runtime-unknown filename and the PCORNET_PATHS override pattern.
- **Section 3 (Load):** Reads the CSV directly by path via `vroom::vroom()` (base `read.csv()` fallback); validates `ID` and `ADDRESS_ZIP9` columns are present; logs row count, distinct patient count, and fill rates for ADDRESS_ZIP9, ADDRESS_ZIP5, and ADDRESS_PREFERRED (open questions 2 and 3).
- **Section 4 (Helpers):** `normalize_zip9()` strips hyphen with `str_remove_all("-")` before `str_pad(9, pad="0")`, then validates `^[0-9]{9}$`; `normalize_zip5_raw()` for the ADDRESS_ZIP5 column; `suppress_small()` for HIPAA <=10 suppression.
- **Section 5 (ZIP normalization):** Prefers ADDRESS_ZIP5 column when non-NA; falls back to `normalize_zip5(zip9_norm)` when blank; logs mismatch count.
- **Section 6 (Per-patient metrics):** `group_by(ID)` with `!is.na()` filter before `n_distinct()` (Pitfall 5a); computes `n_zip9_distinct`, `n_zip5_distinct`, `zip9_ever_changed`, `zip5_ever_changed`, `zip9_change_only` (ZIP9 changed, ZIP5 did not — D-05).
- **Sheets 1-5 (xlsx, D-06/D-07):** ZIP9/ZIP5 side-by-side distribution (Sheet 1), headline stats + ZIP9-change-only + HIPAA-suppressed histogram (Sheet 2), time-between-changes from ADDRESS_PERIOD_START with Pitfall 7 distinct-date guard (Sheet 3), most-recent-vs-modal tie-break disagree rate with ADDRESS_PREFERRED <5% fallback (Sheet 4, D-11), recommendation text + metadata (Sheet 5). All sheets via verbatim `add_styled_sheet()` from R/100.
- **Section 11 (Console summary, D-09):** Headline stats printed before the xlsx write.

**R/39 update:** R/105 gains a trailing comma; R/106 becomes the sole comma-less final entry (20-entry parse-safe vector).

**R/88 Section 15s (14 checks):** Inserted between Sections 15r and 15g. Check 1: file.exists gate. Checks 2-13: structural greps (line count, source R/00_config, probe gate, quit(status=0), ADDRESS_ZIP9, ADDRESS_PERIOD_START, normalize_zip9 hyphen strip, normalize_zip5 str_sub, ^[0-9]{9}$ regex, group_by(ID)+n_distinct, add_styled_sheet+wb_save, HIPAA <=10). Check 14: IS_LOCAL-gated runtime xlsx check (SKIPPED locally). Else-branch mirrors Section 15r.

**R/SCRIPT_INDEX.md:** R/106 row added; Post-Renumber count 6→7 (with R/106 in parenthetical); Total 92→93.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Create R/106_zip_change_frequency.R | c7e877b |
| 2 | Register R/106 in R/39; add R/88 Section 15s + SMOKE-121-01 | f868522 |
| 3 | Update R/SCRIPT_INDEX.md (R/106 row, counts 6->7, 92->93) | 0bba2b0 |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs / Runtime Unknowns

The following require confirmation on HiPerGator (not blockers; R/106 handles each gracefully):

1. **Exact filename of LDS_ADDRESS_HISTORY** — R/106 probes `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` by default. If the filename differs, update `ADDR_FILENAME` constant at line ~69.
2. **ADDRESS_ZIP5 fill rate** — logged at load time. If predominantly NA, R/106 falls back to deriving ZIP5 from ADDRESS_ZIP9 (the mismatch count will be 0).
3. **ADDRESS_PREFERRED fill rate** — logged at load time. If <5% populated, the tie-break (Sheet 4) uses recency alone and notes this in the sheet subtitle.
4. **Cohort breadth (D-10)** — R/106 reports both the total count from LDS_ADDRESS_HISTORY and the HL-cohort overlap (via `get_hl_patient_ids()`, fallback to "unavailable" if it errors).

## Runtime Confirmation Deferred to HiPerGator

R/106 and R/88 Section 15s Check 14 cannot be run to completion locally:
- Rscript is not installed on the Windows executor
- Local test fixtures do not include `LDS_ADDRESS_HISTORY_Mailhot_V1.csv`

When the user runs on HiPerGator, they should confirm:
1. Whether `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` exists at the probed path (Open Q1)
2. Headline console stats (cohort size, % ever-changed ZIP9/ZIP5, median distinct ZIP9)
3. ADDRESS_ZIP5 fill rate vs ADDRESS_ZIP9 (Open Q2) and ADDRESS_PREFERRED fill rate (Open Q3)
4. Whether Section 15s Check 14 flips from SKIPPED to a real xlsx-present PASS

## Pre-existing R/88 Paren Imbalance Note

R/88 had a pre-existing paren imbalance of 28 (open > close) before Phase 121. Section 15s additions are balanced (81 opens, 81 closes). The net imbalance is unchanged at 28. This is out of scope for Phase 121 (deviation Rule scope boundary: fix only issues directly caused by current task changes).

## Self-Check

### File Existence

- R/106_zip_change_frequency.R: FOUND (756 lines)
- R/39_run_all_investigations.R: MODIFIED (R/106 entry added)
- R/88_smoke_test_comprehensive.R: MODIFIED (Section 15s added)
- R/SCRIPT_INDEX.md: MODIFIED (R/106 row, counts updated)

### Commits

- c7e877b: feat(121-01): create R/106_zip_change_frequency.R
- f868522: feat(121-01): register R/106 in R/39 and add R/88 Section 15s
- 0bba2b0: chore(121-01): update R/SCRIPT_INDEX.md

## Self-Check: PASSED
