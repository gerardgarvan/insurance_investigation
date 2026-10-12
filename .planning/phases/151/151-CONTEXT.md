# Phase 151 Context: Per-Patient ZIP Problem Inventory

## Phase Goal

Phase 150 produced aggregate counts. This phase produces the underlying roster: one row per
patient `ID`, with a flag for every ZIP-related problem that patient exhibits, plus the counts
the flags derive from and a triage category telling you what can be done about them.

The deliverable answers "which patients, and what specifically is wrong with each one" — so the
1,128 / 701 / 427 / 152 / 19 / 12 groups from Phase 150 stop being aggregates and become
addressable lists.

## Predecessor Phases

| Phase | What it did |
|-------|-------------|
| 147 | Read ADDRESS_ZIP5; retracted downstream artefacts |
| 148 | ZIP centroid work |
| 149 | Closed sentinel-ZIP residue; completed ADI state coverage |
| 150 | Aggregate ZIP5-missing / ZIP9-availability counts and first-5 concordance |

## Phase 150 Results (this phase must reproduce these exactly)

| Quantity | Value |
|----------|-------|
| Patients with >=1 missing/sentinel ZIP5 | 1,128 |
| Of those, usable ZIP9 available somewhere | 701 |
| Of those, no usable ZIP9 anywhere | 427 |
| Modal concordant | 530 |
| Modal discordant | 152 |
| ZIP9 present, no observed ZIP5 to compare | 19 |
| Record-level rows with both values present | 19,739 |
| Record-level first-5 mismatches | 12 |

These are hard-coded as reconciliation constants. Phase 151 changes the unit of output, not the
definitions, so any divergence means a definition drifted and the run must fail rather than
silently ship a different roster.

**Also required from the Phase 150 summary:** the ZIP5 normalizer name printed by that run
(`normalize_zip5` or `normalize_zip5_raw`). R/121 pins this value and stops if the resolved
normalizer differs — an automatic fallback could silently change results the reconciliation
constants were derived under.

## Data Source

`LDS_ADDRESS_HISTORY_Mailhot_V1.csv` in `CONFIG$data_dir`.

Patient identifier is `ID`, not `PATID`. Columns used: `ID`, `ADDRESS_ZIP5`, `ADDRESS_ZIP9`,
`ADDRESS_PERIOD_START`, `ADDRESS_PERIOD_END`.

Date columns are assumed ISO-8601 (`YYYY-MM-DD`) because the modal tie-break sorts them
lexically. R/121 asserts this format before using it; a non-sortable format such as
`MM/DD/YYYY` would silently produce the wrong tie-break winner.

## Key Utilities (auto-loaded via R/00_config.R → utils_address.R)

Same three as Phase 150: the ZIP5 normalizer pinned above, `normalize_zip9()`,
`is_sentinel_zip5()`.

## Locked Decisions

| ID | Decision |
|----|----------|
| D-01 | Output is a workbook written to `CONFIG$output_dir`, plus a parallel RDS. This phase is not read-only |
| D-02 | Unit of output is one row per patient `ID` |
| D-03 | Roster includes every patient with at least one flag set. Clean patients are excluded from A_patient_flags but still counted in B_flag_summary denominators |
| D-04 | Flag predicates are **semantically identical** to R/120, enforced by the reconciliation gate rather than by textual comparison. Extracting the shared predicates into `utils_address.R` and calling them from both scripts is the correct long-term fix and is deferred, since it would require re-running the closed Phase 150 |
| D-05 | Reconciliation against the eight Phase 150 constants is a blocking gate — zero tolerance. On failure the script writes a clearly-named QC-failure workbook (KEY, reconciliation, QC only) so the mismatch is diagnosable, then calls `stop()` |
| D-06 | KEY is the leftmost sheet and documents **every column** written to A_patient_flags, plus every flag and triage rule |
| D-07 | Script number R/121; file name R/121_zip_problem_inventory.R |
| D-08 | Register in R/39_run_all_investigations.R, R/88_smoke_test_comprehensive.R Section 15ag, R/SCRIPT_INDEX.md |
| D-09 | The workbook contains patient identifiers. It is written to the project output directory only and is not a shareable deliverable without review |
| D-10 | The ZIP5 normalizer is pinned to the name recorded by Phase 150. No automatic fallback |

## Flag Set

| Flag | Meaning |
|------|---------|
| `F01_missing_zip5` | >=1 record where ZIP5 is NA or sentinel |
| `F02_zip5_never_observed` | No non-missing ZIP5 on any record |
| `F03_no_usable_zip9` | No usable ZIP9 on any record |
| `F04_same_row_backfillable` | >=1 missing-ZIP5 record carries a usable ZIP9 on that same row |
| `F05_other_row_zip9_only` | Has missing ZIP5 and a usable ZIP9, but never on a missing-ZIP5 row |
| `F06_modal_discordant` | Modal ZIP9 first-5 differs from modal observed ZIP5 |
| `F07_multiple_zip5` | More than one distinct observed ZIP5 (residential mobility proxy) |
| `F08_tied_modal` | Modal ZIP5 or modal ZIP9 first-5 was decided by tie-break |
| `F09_record_level_mismatch` | >=1 record where both values present and first-5 disagree |
| `F10_sentinel_zip5_present` | >=1 ZIP5 value present but sentinel |
| `F11_invalid_zip9_present` | >=1 ZIP9 value present but not usable |
| `F12_partial_same_row` | Some missing-ZIP5 records have a same-row ZIP9 and some do not |

`F05` is gated on `F01`. Without that gate it fires for nearly every patient who has a usable
ZIP9 and nothing missing, which would sweep most of the table into the roster.

## Triage Categories

Mutually exclusive, assigned in this order. The four `F01` categories partition the 1,128.

| Category | Rule | Meaning |
|----------|------|---------|
| `NO_MISSING_ZIP5` | `!F01` | Nothing to backfill |
| `SAME_ROW_BACKFILL_ALL` | `F01` and every missing-ZIP5 record has a same-row ZIP9 | Fully fixable now at ~99.9% fidelity |
| `SAME_ROW_BACKFILL_PARTIAL` | `F01`, some missing-ZIP5 records have a same-row ZIP9, some do not | Partly fixable now; residual needs temporal matching |
| `NEEDS_TEMPORAL_MATCH` | `F01 & F05` | ZIP9 exists but only on other records; exposed to mobility |
| `UNREACHABLE_NO_ZIP9` | `F01 & F03` | No ZIP9 anywhere; ZIP5-only methods or exclusion |

The `ALL` / `PARTIAL` split matters: without it a patient with one fixable and four unfixable
missing records reads as solved. `n_missing_zip5_no_same_row_zip9` gives the residual count per
patient.

## Workbook Structure

| Sheet | Contents |
|-------|----------|
| `KEY` | Full column dictionary, flag definitions, triage rules, run metadata. Leftmost |
| `A_patient_flags` | One row per flagged patient: ID, 12 flags, supporting counts, modal values, period span, triage |
| `B_flag_summary` | Per flag: n_patients, pct of all patients, and n/pct **among F01 patients** |
| `C_triage_summary` | Per triage category: n_patients, pct |
| `D_record_mismatches` | Record-level first-5 disagreements, one row each |
| `E_reconciliation` | Expected vs observed vs PASS/FAIL for all eight Phase 150 constants |
| `QC` | Rows read, rows retained, blank IDs dropped, normalizer used, R and package versions |

## Runtime Invariants

- `!anyDuplicated(pat$pid)`
- The four `F01` triage categories sum to `EXPECTED[["n_missing_zip5"]]`
- `F04 & F05` is empty (mutually exclusive by construction)
- `F05` implies `F01`
- `period_start` matches `^\d{4}-\d{2}-\d{2}$` where present

## Deferred Ideas

- Temporal matching of missing-ZIP5 records to period-overlapping records with a ZIP9 — still
  deferred; this phase quantifies exactly how many patients and records need it
- Applying the same-row backfill to the pipeline — deferred; this phase identifies eligible
  patients but writes no corrected ZIP values
- Extracting the shared row-flag predicates into `utils_address.R` (see D-04)
- Linking the `UNREACHABLE_NO_ZIP9` group to the ZIP5-only ADI/SDI tier for completeness
  accounting — deferred to the SES linkage scope
