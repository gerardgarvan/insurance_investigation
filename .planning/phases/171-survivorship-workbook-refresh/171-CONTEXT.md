# Phase 171: Survivorship Workbook Refresh — Context

**Gathered:** 2026-10-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Re-run R/166 → R/167 → R/168 from the Phase 170-verified R/147 output. Confirm
primary-tier modality rates and CIF are stable vs the 2026-10-08 workbook. Document
any expected any-tier shifts (expected: none in the survivorship workbook, since it
was built from primary counts only). Build a dedicated verify script and chain it into
the existing 166_survivorship sbatch job.

No new analysis. No changes to R/166/R/167/R/168 logic. The only code changes are:
- R/166 SECTION 1: replace the newest-file glob with a Phase 170 pointer-file gate
- New: `R/171_verify_survivorship.R` (verify script)
- New: `slurm/171_verify_survivorship.sbatch`

</domain>

<decisions>
## Implementation Decisions

### D-01: Input wiring — replace glob with Phase 170 pointer-file gate

R/166 SECTION 1 currently uses `list.files()` + `order(mtime)` to pick the newest
`surveillance_modality_patient_*.rds`. This must be replaced with the pointer-file gate
from `170-DOWNSTREAM-GATE.md` for two reasons:
1. A glob can silently consume an unverified newer R/147 run.
2. If today's R/147 run failed (no new log written), the glob falls back to the pre-163
   output without any error.

**Gate approach for R/166:** Read the pointer file `output/logs/147_verify_last_pass.txt`
to extract `run_date`. Then construct the patient-modality filename:
```r
patient_mod_rds <- file.path(out_dir,
  sprintf("surveillance_modality_patient_%s.rds", run_date))
```
Stop if that file does not exist. Do NOT use the pointer's `rds` field — that holds
`surveillance_patient_modality_dates_<date>.rds` (the E-sheet / dated-events RDS, a
different file). The `surveillance_modality_patient_<run_date>.rds` path must be derived
from `run_date`.

**One-line Phase 170 fix (if preferred):** Add `patient_mod_rds=<path>` to the pointer
file inside `R/147_verify_vs_1006.R`'s `if (n_fail == 0)` block. Either approach is
valid; deriving from `run_date` in R/166 avoids touching already-committed Phase 170
artifacts.

R/166's logic (SECTION 2 onward), R/167, and R/168 are otherwise unchanged.

### D-02: Verification — dedicated `R/171_verify_survivorship.R`

Manual comparison is not repeatable. Assertions inside production scripts mix concerns.
Build `R/171_verify_survivorship.R` modelled on `R/147_verify_vs_1006.R`:

**Reference (10-08) workbook:** `survivorship_modality_rates_20261008.xlsx` in
`CONFIG$cache$outputs_dir`. Confirm this file exists at gate time; FAIL if absent.

**New workbook:** `survivorship_modality_rates_<run_date>.xlsx` where `run_date` comes
from the Phase 170 pointer file (same pinned date used by the gate, not `Sys.Date()`).

**Checks:**
1. **A_rates_summary identical for all 14 modalities** — Phase 163 removed diagnosis
   rows from the codeset, not from primary surveillance counts, so rates should not move.
2. **B_rates_by_fu_year identical for all 14 modalities** — same reasoning.
3. **C_anthracycline_echo identical** — echo events come from the primary code set;
   echo is one of the 4 changed modalities, but the change was to the any-tier/sensitivity
   designation, not primary. Assert explicitly (it's worth confirming).
4. **QC interval reconciliation still PASS** — sum of interval person-years == total
   person-years (tolerance: < 0.01 days).

**Not checked (out of scope):**
- Any-tier columns in the survivorship workbook — see D-03.

**Output format:** identical to `verify_vs_1006.R`:
- One `[PASS] <name>: <detail>` or `[FAIL] <name>: <detail>` line per check
- Final two lines: `N PASS, M FAIL out of K checks` then `OVERALL: PASS` or `OVERALL: FAIL (M checks)`
- Writes to `output/logs/171_verify_survivorship_<run_date>.txt`; sink opens before
  any check; missing-file cases emit `[FAIL]`, never `stop()`; checks are tryCatch-wrapped
- Script exits `quit(status = ifelse(n_fail == 0, 0, 1))`

### D-03: Any-tier documentation — confirm first, then cite Phase 170 log

**Planner must confirm:** Do any any-tier columns flow into the survivorship workbook
(`survivorship_modality_rates_<date>.xlsx`)? The workbook was built from primary counts
in R/166/R/167/R/168. If the answer is no (expected), then:

- **Success criterion 3** is satisfied by:
  1. Citing the Phase 170 verify log in Phase 171's SUMMARY.md: "Primary-tier rates
     unaffected; any-tier shifts are in `147_verify_vs_1006_<date>.txt` (Phase 170)."
  2. Adding one KEY-sheet row to the new survivorship workbook: "Phase 163 removed
     diagnosis-based sensitivity codes; primary-tier survivorship rates unaffected."
  3. No separate RFSH-02.md needed.

If any-tier columns DO flow into the workbook (unexpected), the planner should add a
check to `R/171_verify_survivorship.R` asserting the expected direction of shift for
Echo/ECG/Mammogram/PFT, and document the delta in SUMMARY.md.

### D-04: HiPerGator run procedure

Reuse `slurm/166_survivorship.sbatch` unchanged (already runs R/166 → R/167 → R/168
with `set -e`). Chain two new jobs after it:

```bash
JOB166=$(sbatch --parsable slurm/166_survivorship.sbatch)
JOB_VER=$(sbatch --parsable --dependency=afterok:$JOB166  slurm/171_verify_survivorship.sbatch)
JOB88=$(sbatch  --parsable --dependency=afterany:$JOB_VER slurm/88_smoke_test.sbatch)
```

- `afterok` on JOB166: verify only runs if all three scripts exit 0
- `afterany` on JOB_VER: R/88 always runs so smoke results are visible even on verify failure

**New artifacts needed:**
- `R/171_verify_survivorship.R` (verify script)
- `slurm/171_verify_survivorship.sbatch` (runs the verify script, propagates exit code)

No new R/88 section required for this phase (Phase 170 already added SMOKE-163-01).

### Claude's Discretion

- Whether to call the KEY-sheet row a "Phase 163 note" or a "Phase 171 note"
- Exact column names to match in the A/B/C sheet comparisons (read from the reference
  workbook at runtime, don't hardcode)
- Whether to split the verify script into a helper function for sheet comparison or
  keep it flat like `verify_vs_1006.R`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 170 gate and pointer format
- `.planning/phases/170-r147-rerun-and-verification/170-DOWNSTREAM-GATE.md` — full
  gate snippet and pointer-file format (`run_date`, `log`, `rds` keys); R/166's gate
  derives `surveillance_modality_patient_<run_date>.rds` from the `run_date` key
- `.planning/phases/170-r147-rerun-and-verification/170-CONTEXT.md` — D-05 (log path
  convention), D-06 (gate design rationale)

### Verify script pattern to follow
- `R/147_verify_vs_1006.R` — sink-first pattern, results accumulator, OVERALL line,
  tryCatch-wrapped checks, `quit(status=N)` — replicate exactly for Phase 171

### Scripts being re-run (read for input/output paths, not logic)
- `R/166_survivorship_modality_rates.R` — SECTION 1 (the glob to replace), output RDS names
- `R/167_anthracycline_echo.R` — input path (reads R/166's dated events RDS)
- `R/168_survivorship_workbook.R` — output workbook filename pattern

### SLURM wrapper (reuse unchanged)
- `slurm/166_survivorship.sbatch` — already chains R/166 → R/167 → R/168 with `set -e`

### Requirements
- `.planning/REQUIREMENTS.md` §RFSH-02 — acceptance criteria for this phase

### Reference workbook (10-08 baseline)
- `CONFIG$cache$outputs_dir/survivorship_modality_rates_20261008.xlsx` — the comparison
  target; verify its existence at gate time

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/147_verify_vs_1006.R` — template for `R/171_verify_survivorship.R`: sink pattern,
  `read_sheet()` helper, `results[]` accumulator, OVERALL tally loop, `quit(status=N)`
- `slurm/147_verify.sbatch` — template for `slurm/171_verify_survivorship.sbatch`
- `slurm/166_survivorship.sbatch` — existing wrapper; reused unchanged as JOB166

### Established Patterns
- Phase 170 gate: read pointer → extract `run_date` → derive pinned filename → stop if absent
- Verify scripts: `[PASS]`/`[FAIL]` line per check, OVERALL always written, sink before
  first check, tryCatch around every check, exit code via `quit(status=N)`
- sbatch chains: `afterok` for data-dependent steps, `afterany` for R/88 smoke test

### Integration Points
- `output/logs/147_verify_last_pass.txt` — pointer file written by Phase 170; R/166's
  gate reads it; `run_date` key also drives the verify script's reference workbook lookup
- `CONFIG$cache$outputs_dir` — all dated input/output RDS and xlsx files land here
- `output/logs/171_verify_survivorship_<run_date>.txt` — new verify log; SUMMARY.md
  and RFSH-02 criterion reference this file

</code_context>

<specifics>
## Specific Requirements

- **Different RDS files:** the pointer's `rds` field holds `surveillance_patient_modality_dates_<date>.rds`
  (R/162's export); R/166 SECTION 1 needs `surveillance_modality_patient_<date>.rds` (R/147's
  patient-modality stats). Derive from `run_date`, not from the pointer's `rds` field.
- **C_anthracycline_echo assertion is explicit:** even though echo is a changed modality,
  echo timing came from primary counts — assert identical rather than skip.
- **Any-tier check: planner confirms first** — if no any-tier column flows into the
  survivorship workbook, D-03 approach applies (cite Phase 170 log + KEY-sheet row).
- **No new R/88 section** — Phase 170 already covers the relevant structural checks.
- **Pointer-based run_date for verify reference** — the verify script reads `run_date`
  from the pointer, not from `Sys.Date()`, so the reference workbook lookup is pinned
  to the same date as the gate.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 171-survivorship-workbook-refresh*
*Context gathered: 2026-10-09*
