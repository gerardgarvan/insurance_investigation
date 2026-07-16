# Phase 129: Attribution Linkage and Output - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-15
**Phase:** 129-attribution-linkage-and-output
**Areas discussed:** Small-cell suppression, Report cohort scope, "HL active" signal, Script identity

---

## Small-Cell Suppression

| Option | Description | Selected |
|--------|-------------|----------|
| Raw, no auto-suppress | Follow DOI-OUT-02 / Phase 127 D-07: raw counts, internal-only note on every sheet; consistent with R/111 and v3.1 internal-investigation pattern | ✓ |
| Auto-suppress Sheet 3 | Follow roadmap literally: suppress_small() (11L → "<11") on n_patients/n_encounters in Sheet 3 | |
| Both: two files | Emit raw internal workbook + separate suppressed workbook | |

**User's choice:** Raw, no auto-suppress
**Notes:** Resolves a direct contradiction between the ROADMAP Phase 129 design constraint (apply suppress_small to Sheet 3) + Success Criterion #3, and requirement DOI-OUT-02 (raw counts, no auto-suppression). The formal requirement governs; the roadmap constraint is treated as a stale generic-HIPAA carryover and is superseded (CONTEXT D-01). Rare-DoI single-digit cells are wanted for internal SME review.

---

## Report Cohort Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Both, split by in_hl_cohort | Full extract with in_hl_cohort dimension on every sheet — HL vs non-HL comparable | ✓ |
| HL cohort only | Restrict entire report to in_hl_cohort == TRUE | |
| Full extract only | No cohort split | |

**User's choice:** Both, split by in_hl_cohort
**Notes:** Leverages the in_hl_cohort tag Phase 128 deliberately added (128 D-01/D-02) — prevalence context + the clinically-relevant HL slice in one workbook, no re-query (CONTEXT D-02).

---

## "HL Active" Signal (three-state NA definition)

| Option | Description | Selected |
|--------|-------------|----------|
| HL dx dates from DIAGNOSIS | Small HL-code-filtered dated DuckDB pull; NA when HL dx within ±90 days of drug admin — true temporal semantics | ✓ |
| HL treatment episodes | Use HL-directed treatment episode_start/stop as the active window | |
| Coarse ever-in-cohort | NA if patient is in_hl_cohort at all (no dates) | |

**User's choice:** HL dx dates from DIAGNOSIS
**Notes:** get_hl_patient_ids() returns IDs only (no dates) and is insufficient for the NA test. A dated HL pull is mandatory so NA reflects a real dated HL co-occurrence in the same window, not mere membership (CONTEXT D-03). This is the only new DuckDB pull permitted in the phase.

---

## Script Identity

| Option | Description | Selected |
|--------|-------------|----------|
| New R/112 | R/112_doi_attribution_report.R (reads .rds artifacts + treatment_episode_detail.rds); R/111 stays classification-only | ✓ |
| Extend R/111 | Add attribution + xlsx to R/111 (matches roadmap's "R/111_doi_attribution_report.R" text) | |

**User's choice:** New R/112
**Notes:** Honors Phase 128 D-05 (one-investigation-per-script; .rds as hand-off boundary). Phase 130's "R/111_doi_attribution_report.R" references are a naming slip — attribution is R/112; classification is R/111 (CONTEXT D-04).

## Claude's Discretion

- Sheet layout for the in_hl_cohort split; xlsx writer mechanics (openxlsx); rollup grain per sheet; ascending multi-value collapse; internal-only note / CAVEATS footnote placement; how the dated HL pull is assembled.

## Deferred Ideas

- R/39 registration, SCRIPT_INDEX, R/88 section, HiPerGator runtime gate → Phase 130 (target R/112).
- Separate suppressed shareable workbook → declined for now; manual suppression per the internal-only note.
