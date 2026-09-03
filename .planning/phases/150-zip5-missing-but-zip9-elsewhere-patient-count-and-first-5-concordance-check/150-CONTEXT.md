# Phase 150 Context: ZIP5-Missing but ZIP9-Elsewhere

## Phase Goal

For patients who have at least one address record with a missing ZIP5, determine how many also
have a usable ZIP9 on file, and for those patients check whether the first 5 digits of that
ZIP9 match the non-missing ZIP5 they carry on other records — quantifying whether ZIP9 can
reliably backfill ZIP5 gaps.

## Predecessor Phases

| Phase | What it did |
|-------|-------------|
| 147 | Read ADDRESS_ZIP5; retracted downstream artefacts |
| 148 | ZIP centroid work |
| 149 | Closed sentinel-ZIP residue; completed ADI state coverage |

## Data Source

`LDS_ADDRESS_HISTORY_Mailhot_V1.csv` in `CONFIG$data_dir`.

Key columns: `ID`, `ADDRESS_ZIP5`, `ADDRESS_ZIP9`, `ADDRESS_PERIOD_START`, `ADDRESS_PERIOD_END`.

**Patient identifier is `ID`, not `PATID`.** This is the project-wide convention and applies to
this table. Any code in this phase referencing `PATID` is a defect.

Study period for this table is 2012-01-01 to 2025-03-31. No date filtering is applied in this
phase; `ADDRESS_PERIOD_START` is used only as a modal tie-break.

## Key Utilities (auto-loaded via R/00_config.R → utils_address.R)

| Function | Purpose |
|----------|---------|
| `normalize_zip5(zip5)` | Normalize to 5-char string |
| `normalize_zip9(zip9)` | Normalize to 9-char string |
| `is_sentinel_zip5(zip5)` | TRUE for invalid placeholder ZIPs (five repeated digits OR numeric < 501) |

**Open item (O-01):** if `utils_address.R` also defines `normalize_zip5_raw()` for raw column
input — with `normalize_zip5()` reserved for already-normalized ZIP9-derived strings — then
`normalize_zip5_raw()` is the correct call on `ADDRESS_ZIP5` and this table should be amended
to list both. R/120 resolves this at runtime by preferring `normalize_zip5_raw()` when it
exists, so the script is correct either way, but the table should be corrected once confirmed
by `grep -n "normalize_zip5" R/utils/utils_address.R`.

`get_zip9_at_date()` is NOT used — this phase analyses the raw address table, not
encounter-anchored lookups.

## Locked Decisions

| ID | Decision |
|----|----------|
| D-01 | Read-only investigation — no output files, no RDS written, console output only |
| D-02 | Required outputs (1)–(4) are patient-level (distinct `ID`), not record counts |
| D-03 | Script number R/120; file name R/120_zip5_backfill_concordance.R |
| D-04 | Use dplyr throughout — no data.table |
| D-05 | Load CSV via vroom with explicit col_types; use CONFIG$data_dir for path |
| D-06 | Must register in R/39_run_all_investigations.R, R/88_smoke_test_comprehensive.R Section 15af, and R/SCRIPT_INDEX.md |
| D-07 | Count (2) means a usable ZIP9 on **any** record for that patient, same row included. The same-row / other-row split is reported separately so both readings are visible |
| D-08 | Modal ZIP per patient is picked deterministically: record frequency, then latest `ADDRESS_PERIOD_START`, then ZIP lexically. The number of patients with a tied mode is reported |
| D-09 | A supplementary **record-level** same-record check is printed as output (5). It is a diagnostic, not one of the required patient-level outputs, and does not alter D-02 |

## Required Console Outputs

Five counts plus one rate, plus one supplementary diagnostic:

1. **n_missing_zip5** — patients with >=1 address record where ZIP5 is NA or sentinel
2. **n_zip9_available** — of those, patients with a usable ZIP9 on at least one record
   - 2a: usable ZIP9 on a missing-ZIP5 record itself (overlaps 2b)
   - 2b: usable ZIP9 on a record where ZIP5 is present
3. Concordance breakdown for patients in group 2:
   - **n_concordant** — modal ZIP9 first-5 == modal observed ZIP5
   - **n_discordant** — modal ZIP9 first-5 != modal observed ZIP5
   - **n_no_zip5_elsewhere** — ZIP9 present but no non-missing ZIP5 to compare
4. **Concordance rate** — n_concordant / (n_concordant + n_discordant), with a measured
   interpretation stating what the comparison does and does not establish
5. **(Supplementary)** Record-level same-record agreement: on rows carrying both a usable ZIP9
   and a non-missing ZIP5, the share where `substr(zip9, 1, 5) == zip5`

Note: the earlier draft of this document described these as "four counts." There are five
counts and one rate. The checkpoint paste-back should include all of them.

## Interpretation Caveat

Output (4) compares patient-level modal values across all of a patient's records. A residential
move within the study period registers as discordance even where ZIP9 is a faithful record-level
backfill, so (4) is a **lower bound** on ZIP9 fidelity and is a proxy, not direct evidence, that
ZIP9 recovers any specific missing ZIP5. Output (5) measures the same-row mechanism directly and
is unaffected by moves; read the two together.

## Invariants Asserted at Runtime

- `nrow(zip9_first5_by_pat) == n_zip9_available` — one modal row per group-2 patient. Fails
  loudly if the modal pick is accidentally ungrouped.
- `n_concordant + n_discordant + n_no_zip5_elsewhere == n_zip9_available` — buckets exhaust
  group 2; detects dropped or duplicated patients.

## Deferred Ideas

- Writing output to xlsx or RDS — deferred; console-only for this phase
- Encounter-level concordance — deferred; patient-level per D-02
- Temporal matching of a missing-ZIP5 row to the nearest or period-overlapping record with a
  ZIP9 — deferred; modal ZIP per patient is used instead (D-08). This is the natural successor
  phase if output (4) and output (5) diverge substantially
- Classifying tied modal ZIPs as "ambiguous" rather than resolving them — deferred; ties are
  resolved per D-08 and counted
