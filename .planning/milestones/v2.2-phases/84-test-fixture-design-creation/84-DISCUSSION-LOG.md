# Phase 84: Test Fixture Design & Creation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-04
**Phase:** 84-test-fixture-design-creation
**Areas discussed:** Patient Design, Fixture Creation, Table Coverage, Edge Case Scope

---

## Patient Design

### Q1: Patient-to-edge-case mapping

| Option | Description | Selected |
|--------|-------------|----------|
| One case per patient | ~20 patients, each targeting 1-2 edge cases. FIXTURE_DESIGN.md reads like a test matrix. Easy to trace failures to specific patients. | ✓ |
| Packed patients | ~10-12 patients with 2-4 edge cases each. Smaller fixtures but harder to isolate which case caused a failure. | |
| You decide | Claude picks the approach that best balances traceability and fixture size. | |

**User's choice:** One case per patient (Recommended)
**Notes:** Clear traceability preferred over smaller fixture size.

### Q2: Patient ID naming pattern

| Option | Description | Selected |
|--------|-------------|----------|
| PT001-PT020 | Sequential zero-padded IDs matching ROADMAP success criteria. Clearly synthetic, easy to reference. | ✓ |
| Descriptive IDs | IDs hinting at edge case: DUAL_01, NLPHL_01. Self-documenting but breaks PCORnet format. | |
| Random synthetic IDs | SYN00001 style. More realistic format but less readable. | |

**User's choice:** PT001-PT020 (Recommended)
**Notes:** Matches ROADMAP success criteria references.

### Q3: Encounter ID convention

| Option | Description | Selected |
|--------|-------------|----------|
| ENC{patient}_{seq} | e.g., ENC001_01, ENC001_02. Visual link to patient. | ✓ |
| Sequential global IDs | ENC0001, ENC0002. Simple but no visual patient link. | |
| You decide | Claude picks convention for DuckDB indexing compatibility. | |

**User's choice:** ENC{patient}_{seq} (Recommended)
**Notes:** Visual traceability between encounters and patients.

### Q4: Date range for diagnoses

| Option | Description | Selected |
|--------|-------------|----------|
| 2012-2014 diagnoses | Tight range around ICD-9/ICD-10 transition. Tests both DX_TYPE values. | ✓ |
| All 2010 diagnoses | Single year. Simpler but less realistic for cross-system testing. | |
| You decide | Claude picks dates for optimal pipeline exercise. | |

**User's choice:** 2012-2014 (Recommended)
**Notes:** Spans ICD-9 to ICD-10 transition for realistic dual-system testing.

---

## Fixture Creation

### Q5: Source of truth

| Option | Description | Selected |
|--------|-------------|----------|
| Script is source of truth | R script with tribble() definitions writes CSVs. CSVs committed but regenerable. | ✓ |
| CSVs are source of truth | Hand-edit CSVs directly. R script just validates structure. | |
| Both canonical | Either can be edited. Risk of drift between script and CSVs. | |

**User's choice:** Script is source of truth (Recommended)
**Notes:** Edit script, re-run, commit both script and CSVs.

### Q6: Script location

| Option | Description | Selected |
|--------|-------------|----------|
| tests/generate_fixtures.R | Alongside fixtures. Clear relationship. source() to regenerate. | ✓ |
| R/99_generate_fixtures.R | In main pipeline sequence. Follows numbering but isn't a pipeline step. | |
| You decide | Claude picks best location for project structure. | |

**User's choice:** tests/generate_fixtures.R (Recommended)
**Notes:** Co-located with the fixtures it generates.

---

## Table Coverage

### Q7: Low-traffic table handling

| Option | Description | Selected |
|--------|-------------|----------|
| Header + 1-2 rows | Every table gets minimal rows. DuckDB ingest succeeds. Pipeline won't choke. | ✓ |
| Header-only stubs | Just column headers. Some scripts may fail on empty tables. | |
| Skip entirely | Don't create CSVs for unused tables. DuckDB ingest may fail. | |

**User's choice:** Header + 1-2 rows (Recommended)
**Notes:** Maximum compatibility with minimal effort.

### Q8: TUMOR_REGISTRY column scope

| Option | Description | Selected |
|--------|-------------|----------|
| Pipeline-used columns only | ~15-20 columns per TR table. Small, readable. Missing columns default to NA. | ✓ |
| All columns | Full 140-314 column schema. Realistic but huge and hard to maintain. | |
| You decide | Claude scans pipeline code for used columns. | |

**User's choice:** Pipeline-used columns only (Recommended)
**Notes:** Keeps fixtures manageable. Unused columns can be omitted.

---

## Edge Case Scope

### Q9: Additional edge cases

| Option | Description | Selected |
|--------|-------------|----------|
| These 8 are sufficient | Original 8 edge cases cover main pipeline logic. | ✓ |
| Add ICD-9/ICD-10 transition | Cross-system patient with 201.x + C81.x for Phase 87 confirmation. | ✓ |
| Add missing payer | Patient with "NI" or NA payer code for exclude_missing_payer. | ✓ |
| Add regimen detection | ABVD drug codes for first-line therapy identification. | ✓ |

**User's choice:** All options selected (11 total edge cases)
**Notes:** Original 8 + 3 additions for comprehensive coverage.

### Q10: Baseline patients

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, 1-2 baselines | Establishes "normal" output reference. | ✓ |
| No baselines | Every patient tests an edge case. | |

**User's choice:** Yes, 1-2 baselines (Recommended)
**Notes:** Reference for correct pipeline output.

---

## Claude's Discretion

- Exact RXNORM_CUI values for ABVD drugs
- TUMOR_REGISTRY column selection (scan pipeline for used columns)
- Enrollment date ranges per patient
- DISPENSING vs PRESCRIBING vs MED_ADMIN for drug edge cases
- SOURCE values per patient (OneFlorida+ partner sites)

## Deferred Ideas

None — discussion stayed within phase scope.
