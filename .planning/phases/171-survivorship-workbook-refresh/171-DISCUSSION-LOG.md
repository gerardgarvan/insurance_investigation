# Phase 171: Survivorship Workbook Refresh — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-09
**Phase:** 171-survivorship-workbook-refresh
**Areas discussed:** Input wiring, Verification approach, Any-tier documentation, HiPerGator run procedure

---

## Input Wiring / Gate Integration

| Option | Description | Selected |
|--------|-------------|----------|
| Keep glob | `list.files()` + `order(mtime)` picks newest RDS | |
| Phase 170 pointer gate | Read `147_verify_last_pass.txt`, derive pinned path from `run_date` | ✓ |

**User's choice:** Phase 170 pointer gate — glob risks consuming an unverified or pre-163 RDS.

**Notes:** The pointer's `rds` field holds the E-sheet RDS (`surveillance_patient_modality_dates_<date>.rds`), not the file R/166 needs (`surveillance_modality_patient_<date>.rds`). Resolve by deriving the R/166 path from the pointer's `run_date` key. Alternatively, add a `patient_mod_rds` key to the pointer in Phase 170's verify script (one-line fix). Deriving from `run_date` avoids touching already-committed Phase 170 artifacts.

---

## Verification Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Manual visual comparison | Inspect workbooks by hand | |
| Assertions inside R/166–R/168 | Add stopifnot checks to production scripts | |
| Dedicated verify script | `R/171_verify_survivorship.R` modelled on `verify_vs_1006.R` | ✓ |

**User's choice:** Dedicated verify script — manual comparison is not repeatable; assertions in production scripts mix concerns.

**Notes:** Checks: A_rates_summary identical (all 14 modalities), B_rates_by_fu_year identical (all 14 modalities), C_anthracycline_echo identical (echo is a changed modality but rates came from primary counts — assert explicitly), QC interval reconciliation still PASS. Same PASS/FAIL/OVERALL log format as Phase 170.

---

## Any-Tier Documentation

| Option | Description | Selected |
|--------|-------------|----------|
| Separate RFSH-02.md | Stand-alone drift document | |
| Cite Phase 170 log + KEY row | SUMMARY.md cite + one KEY-sheet note | ✓ (conditional) |

**User's choice:** Confirm first whether any any-tier column flows into the survivorship workbook. If not (expected), satisfy criterion 3 by citing the Phase 170 verify log in SUMMARY.md and adding one KEY-sheet row. No separate RFSH-02.md needed.

**Notes:** The survivorship workbook was built from primary counts in R/166/R/167/R/168. The any-tier shifts live in R/147's output (Phase 170 verify log). Planner confirms before settling final approach.

---

## HiPerGator Run Procedure

| Option | Description | Selected |
|--------|-------------|----------|
| Three new chained sbatch jobs | New sbatch for each of R/166, R/167, R/168 | |
| One combined new sbatch | Single job runs all three scripts | |
| Reuse existing wrapper | `slurm/166_survivorship.sbatch` runs all three; chain verify after | ✓ |

**User's choice:** Reuse `slurm/166_survivorship.sbatch` unchanged. Chain `slurm/171_verify_survivorship.sbatch` with `afterok`, then R/88 with `afterany`.

**Notes:** `166_survivorship.sbatch` already runs testthat + R/166 + R/167 + R/168 in order with `set -e`. Only two new artifacts needed: the verify R script and its sbatch file.

---

## Claude's Discretion

- Whether to call the KEY-sheet row a "Phase 163 note" or a "Phase 171 note"
- Exact column names to match in sheet comparisons (read from reference workbook at runtime)
- Whether to use a helper function for sheet comparison or keep it flat like `verify_vs_1006.R`

## Deferred Ideas

None.
