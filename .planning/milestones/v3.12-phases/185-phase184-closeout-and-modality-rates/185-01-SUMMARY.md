# Phase 185-01 Summary: Phase 184 Close-out and Modality Rates

**Phase:** 185 — Phase 184 Close-out and Modality Rates  
**Plan:** 01  
**Run date (HiPerGator):** 2026-10-22  
**Status:** PASS

---

## Section 0: Objective

Formally close Phase 184 by confirming R/184_modality_rate_model.R ran end-to-end on HiPerGator, record the dated output workbook filename for downstream use, probe the workbook into a schema file for exact-label reads, and mark Phase 184 complete in ROADMAP.md and MILESTONES.md.

---

## Section 1: Phase 186 R184_OUTPUT Default

The dated output workbook produced by this run is:

```
output/modality_rate_model_20261022.xlsx
```

This filename is the default value for the `R184_OUTPUT` environment variable in Phase 186. Phase 186's planner must use this exact filename (no guessing from a pattern match) when pinning `R184_OUTPUT`.

---

## Section 2: Rates Annual-Section Header (RATE-01, D-04)

The schema probe (`probe_inputs("185", files = c("output/modality_rate_model_20261022.xlsx"))`) was run in the same R session immediately after the workbook was produced. The probe recorded the Rates sheet's first column header as:

```
Annual rates (years 2+) — by modality x far
```

(verbatim from `.planning/schemas/185_schema_20261022.md`, column name `Annual.rates.(years.2+).—.by.modality.x.far`; the em dash character — is preserved as written by R/184.)

This is the exact header string that Phase 186 must use when reading the Rates sheet by label. The provisional text in CONTEXT.md matches; the probe is authoritative per D-04.

---

## Section 3: Reproduction Gate (D-09, D-10)

Gate result from the HiPerGator console:

```
REPRODUCTION GATE PASSED: OR 0.8339 (0.7192-0.9668) vs Phase 179 0.834 (0.719-0.967)
```

**Reproduction gate: PASS (within 0.005)**

- Observed OR: 0.8339 (reference: 0.834) — difference: 0.0001
- Observed CI low: 0.7192 (reference: 0.719) — difference: 0.0002
- Observed CI high: 0.9668 (reference: 0.967) — difference: 0.0002

**Global Wald test (primary, years 2+):**

```
[Primary: years 2+] Global Wald: chi2=19.15 df=13 p=0.1184
```

Gate counts (years 2+, complete-case):
- Patient-years total: 47,050
- Patient-years far=1: 4,691
- Patient-years far=0: 42,359
- Patients total: 7,262
- Patients far=1: 739
- Patients far=0: 6,523

---

## Section 4: D-05 Annual-Rates Row Count (years 2+)

The annual-rates (years 2+) block in the Rates sheet contains one row per modality × far level. With 14 modalities and 2 far levels (far=0, far=1), the block contains **28 data rows**. This figure is consistent with the suppression audit printed by R/184 (14 modalities × 2 cells each = 28 cells for the "annual years 2+" table).

The probe records 289 total rows in the Rates sheet across all five rate sections (annual years 2+, annual all years, year_index_cat years 2+, half-year years 2+, half-year all years) plus section-header rows.

---

## Section 5: R/88 Smoke Test Count (D-10)

```
ALL 982 CHECKS PASSED  (3 skipped)
```

No FAIL lines were emitted. The 3 skipped checks are R/88's normal production-mode skips (fixture schema validation, runtime checks requiring IS_LOCAL). The stale-workbook WARNING for `distance_cbc_association_20261015.xlsx` is a date-stamp note, not a FAIL, and is unrelated to Phase 185.

---

## Section 6: CLOSE-02 — Model_Results Sheet Confirmation

The schema probe confirms the Model_Results sheet exists with 89 rows and columns:

```
Primary:.years.2+ | X2 | X3 | X4 | X5
```

The per-modality far×modality interaction estimates printed to console confirm that the RR, CI_low, CI_high, and p columns are populated for all 14 modalities in the primary (years 2+) fit. No `[<label>] GEE FAILED:` message was emitted for the primary fit. All sensitivity fits (secondary all-years, NB, adjusted, half-year, data-end) completed without non-convergence. No labelled Note rows were written by `write_rr_block()` because no fit returned an error object.

Per the plan's D-07 guidance: no refitting was performed. The half-year GEE sensitivity produced a Global Wald chi2=19.15 df=13 p=0.1184 and modality RR estimates identical to the primary GEE; this is reported as-is without refitting.

---

## Section 7: Registration Grep Result

Grep for "184" in the three registration files:

| File | Result |
|------|--------|
| `R/39_run_all_investigations.R` | **PRESENT** — `"R/184_modality_rate_model.R"` at line 249 |
| `R/SCRIPT_INDEX.md` | **PRESENT** — row at line 178 with full description |
| `R/88_smoke_test_comprehensive.R` | **NOT PRESENT** — no Phase 184 smoke section |

The R/88 smoke section for R/184 is missing. This item is handed to **Phase 189 (REG-01)** per the CONTEXT.md decision to defer script registration.

---

## Section 8: Pin Deviation

The R/184 default pin for `R184_EVENTS_RDS` pointed to `survivorship_dated_events_20261009.rds`, which did not exist on HiPerGator. The available files were `survivorship_dated_events_20261008.rds` and `survivorship_dated_events_20261012.rds`. The run used `20261012` via an env-var override before sourcing:

```r
Sys.setenv(R184_EVENTS_RDS = "/blue/erin.mobley-hl.bcu/clean/rds/outputs/survivorship_dated_events_20261012.rds")
```

The reproduction gate passed, confirming the `20261012` file is the correct upstream input. The pin in R/184 (defaulting to `20261009`) should be corrected in a future quick task to match the file that actually exists.

---

## Section 9: Schema Probe File

Schema probe written on HiPerGator:

```
/blue/erin.mobley-hl.bcu/insurance_investigation/.planning/schemas/185_schema_20261022.md
```

This file must be copied unchanged to the Windows repo at:

```
.planning/schemas/185_schema_20261022.md
```

The probe records: 6 sheets (KEY | Rates | Model_Results | Interaction | Diagnostics | QC). The KEY sheet has 26 rows with first-column labels documenting all run parameters and pin values. The Rates sheet first-column header is the annual-rates section header recorded in Section 2 above.

---

## Section 10: Artifacts Produced

| Artifact | Path | Notes |
|----------|------|-------|
| Output workbook | `output/modality_rate_model_20261022.xlsx` | 6 sheets; KEY leftmost |
| Memo | `output/184-MEMO_20261022.md` | Script-generated |
| Internal RDS | `output/internal/modality_long_20261022.rds` | 714,902 rows; internal only |
| Schema probe | `.planning/schemas/185_schema_20261022.md` | Copy from HiPerGator unedited |
| This SUMMARY | `.planning/phases/185-.../185-01-SUMMARY.md` | Close-out document |

---

## Section 11: Requirements Satisfied

| Requirement | Status |
|-------------|--------|
| CLOSE-01: R/184 end-to-end without error; dated workbook pinned | ✓ |
| CLOSE-02: Model_Results per-modality far×modality RR+CI confirmed; non-convergence labelled not blank | ✓ (no non-convergence) |
| RATE-01: Annual-window modality rates readable by exact label from pinned workbook | ✓ |
| D-06: No R/184 code changes | ✓ |
| D-07: No new modeling; GEE results reported as-is | ✓ |
| D-09: Reproduction gate PASS | ✓ |
| REG-01: R/88 smoke section deferred to Phase 189 | Deferred |
