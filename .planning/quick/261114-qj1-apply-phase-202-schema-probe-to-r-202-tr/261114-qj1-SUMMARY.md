# Quick 261114-qj1 — Apply Phase 202 schema probe to R/202_tr_sensitivity.R

Probe used: `.planning/schemas/202_schema_tr_treatment_cols_20261114.md`

## Changes
- `R/202_tr_sensitivity.R`: PENDING-PROBE constants replaced by `TR_MAP` (source x trtype: date_col, code_col, code_scheme, given_values); `CODE_UNKNOWN` per scheme; placeholder SCT/date columns removed.
- Stratified by `SOURCE` (UFH/ORL); TMH in C_by_source with `fmt_sup()` and footnote "n = <n> TR rows; too few for sensitivity".
- Patient-level collapse on HL-histology rows: tr_given = date OR given code; tr_first_date = earliest date; unknown codes tracked separately (`unknown_code` tier, outside denominator).
- B_date_diff limited to `B_PAIRS` (chemo UFH/ORL, radiation ORL, immuno UFH, hormone UFH/ORL); SCT has no B row (footnote row).
- QC: ORL `DT_CHEMO` x `R_N_CHEMO` cross-tab (suppressed). KEY: both code schemes, opposite meaning of 0.
- Percentages now require numerator and denominator >= 11 (CLAUDE.md rule).
- Sheet names unchanged, so R/88 SECTION 15be needs no edit. New columns: A `Captured, TR undated n`, `TR unknown code n`; B `SOURCE`; C `TR given n`, `TR unknown code n`, `Note`.
- 202-HUMAN-UAT item 1 marked done.

## Assumptions (headless run)
- Histology columns `HISTOLOGICAL_TYPE` / `MORPH` are not in the probe; taken from R/10_cohort_predicates.R:83,92. Script stops if neither exists.
- Gantt label "Hormone" is unconfirmed; checked at run time. If absent, hormone is not compared (QC row + B footnote). Systemic has no Gantt counterpart (descriptive only).
- Unknown codes per scheme: reason_no 8/9; naaccr_rx 88/99; rx_summ 8/9/88/99 (user list; reason_no unknowns not in probe).
- TMH `DRAD_SUM` has no given value in probe; given_values empty.
- Gantt `SOURCE` dropped from `gantt_pts` (TR `SOURCE` is the stratifier).
- First dates >90 d apart still count as not captured (unchanged).

## Verification
- `tools/rcheck.sh parse R/202_tr_sensitivity.R`: OK. Synthetic check of `tr_row_evidence`/`collapse_evidence`: OK.

## PENDING HIPERGATOR
```
module load R/4.5; R --no-save
source("R/202_tr_sensitivity.R", local = new.env(parent = globalenv()))
```
Paste back: any error plus ~20 lines; the `HL rows by SOURCE` line; the QC sheet rows (ORL chemo cross-tab, hormone compared); `nrow()` of each sheet.
