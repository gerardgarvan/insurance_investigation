# Phase 170: R/147 Re-run and Verification — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-09
**Phase:** 170-r147-rerun-and-verification
**Areas discussed:** verify_vs_1006 pass criteria, Phase transition checkpoint, R/88 scope

---

## Run Procedure

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse Phase 169 sbatch pattern | Use same dependency-chain approach that worked for 165-168 | ✓ |
| Design new procedure | — | |

**User's choice:** Reuse whatever worked last time — Phase 169's sbatch dependency chain.
**Notes:** Phase 170 has run R/147 via sbatch for every phase since 158; no new procedure needed.

---

## verify_vs_1006 Pass Criteria

| Option | Description | Selected |
|--------|-------------|----------|
| PASS/FAIL per check + OVERALL line + non-zero exit | Machine-readable; no manual interpretation | ✓ |
| Informal summary message | Current behavior ("ALL PASS" / "REVIEW FAILURES") | |

**User's choice:** Formal PASS/FAIL per line, `OVERALL: PASS` / `OVERALL: FAIL (n checks)` final line, `quit(status=1)` on failure.

**Specific checks required:**
- Denominator / cohort N / person-years unchanged (KEY sheet)
- B identical for all 14 modalities
- C primary columns identical for all 14 modalities
- C sensitivity=0 and any=primary for Echo, ECG, Mammogram, PFT
- D identical for all 10 unaffected modalities; any=primary for 4 changed modalities
- A2_analyte_presence identical
- A3_missing_analyte identical (currently missing from identical_sheets — confirmed gap)
- Lab rule table identical (sheet name to be confirmed)
- QC matched-rows drop computed from A_code_presence n_records (SC039/SC047/SC065/SC090), not hardcoded
- "diagnosis" text residue check across sheets
- E vs 1006 RDS (primary columns only) — replaces broken xlsx-vs-xlsx E check that silently SKIPs

**Notes:** User identified that the E check against the 1006 xlsx silently SKIPs because
the 1006 reference xlsx predates the E_patient_modality_dates sheet addition (Phase 159/162).
The E check has never fired. Fix: compare RDS-to-RDS against the pinned 1006 RDS.

User directed that matched-rows drop (6,744 today) be computed rather than hardcoded, with
a note in the FAIL message to check grain alignment before treating as regression.

---

## Phase Transition Checkpoint

| Option | Description | Selected |
|--------|-------------|----------|
| Dated verify log + SUMMARY + downstream gate | Structured artifact chain | ✓ |
| Manual note in SUMMARY only | Fragile — no machine gate | |

**User's choice:**
- verify script writes `output/logs/147_verify_vs_1006_<date>.txt` ending with OVERALL line
- SUMMARY records run date, new workbook/RDS filenames, verify log path, SLURM job IDs, R/88 15as result
- Phases 171 and 172 open with a gate that checks the log exists and contains `OVERALL: PASS`

---

## R/88 Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Add Section 15as for Phase 163 checks | 15ao-15ar already used; 15as is next free | ✓ |
| Update Section 15ao | 15ao is Phase 166 — must not be changed | |

**User's choice:** Leave 15ao (Phase 166) unchanged. Add new Section 15as for Phase 163:
1. `EXCLUDED_CDM_TABLES` defined in R/147
2. `stopifnot()` assertion present
3. Latest workbook A_code_presence has no DIAGNOSIS rows (conditional on workbook present)
4. Codeset_summary has no Z-codes (conditional on workbook present)

**Confirmed facts:**
- 15ap = Phase 167, 15aq = Phase 168, 15ar = Phase 165 — all used
- Phase 169 has no R/88 section (it's the smoke test run itself)
- 15as is confirmed next free label

**Notes:** User also confirmed Phase 163 has no existing R/88 section, so these checks
are genuinely missing and belong in 15as.

---

## Claude's Discretion

- Exact KEY sheet row labels for denominator / person-years (read from workbook)
- Whether to use `sink()` or sbatch `tee` for log capture
- Lab rule table sheet name (check `excel_sheets()` on 1006 workbook)
- Whether "diagnosis" text residue check is a separate pass or per-sheet

## Deferred Ideas

None.
