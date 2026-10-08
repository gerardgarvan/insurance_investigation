# Phase 166: Survivorship Modality Rates and Anthracycline-to-Echo Timing — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-08
**Phase:** 166-survivorship-modality-rates-and-anthracycline-to-echo-timing
**Areas discussed:** Per-patient rate table structure, First-line course definition for echo clock, Cumulative incidence method, Other anthracyclines in D-166-01

---

## Per-Patient Rate Table Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Wide only | One row per patient, one column per modality rate | |
| Long as main, wide as export | Long (ID × modality) for analysis; wide CSV for team | ✓ |
| Recompute from raw events | Ignore R/147 outputs, recompute from scratch | |

**User's choice:** Long as the main table, wide as the per-patient CSV export. Reuse R/147's existing `n_dates_post` and `person_years` — fits the "audit, don't redo" rule. Rate = `n_dates_post / person_years`; NA when `person_years` is 0 or missing. Audit must confirm R/147 uses Phase 161 `compute_followup()`; flag discrepancies rather than silently switching.

---

## First-Line Course Definition for Echo Clock

| Option | Description | Selected |
|--------|-------------|----------|
| ABVD 28-day cycle windows | Reconstruct first-line from drug composition windows | |
| Existing first-line flag | Use `first_line == TRUE` in treatment episode detail (180-day file) | ✓ |
| Latest-ever dose (no first-line distinction) | Use any anthracycline dose as the clock start | |

**User's choice:** Use the existing `first_line` flag in the 180-day treatment episode detail (matches current Gantt work). Last doxorubicin date within first-line episodes is the clock start. Patients with doxorubicin but no first-line episode go to QC; their latest-ever dose is the sensitivity column only. Record use of 180-day file as D-166-02.

---

## Cumulative Incidence Method

| Option | Description | Selected |
|--------|-------------|----------|
| 1 − Kaplan-Meier with note | Simple KM, annotate competing risk caveat | |
| Aalen-Johansen CIF (survival package) | Proper competing-risk estimator, death as competing event | ✓ |
| Both AJ CIF and KM | Show both; label KM as overestimate | ✓ |

**User's choice:** Proper Aalen-Johansen CIF via `survival::survfit()` with factor event (censored / echo / death). Also report 1 − KM alongside, labelled as overestimate when deaths censored. Confirm `survival` in `renv.lock` before HiPerGator run.

---

## Other Anthracyclines in D-166-01

| Option | Description | Selected |
|--------|-------------|----------|
| Doxorubicin only | Only count doxorubicin for echo clock | |
| Include all anthracyclines in clock | Doxorubicin + Daunorubicin + Epirubicin + Idarubicin if present | ✓ |
| Count others in QC only | Include counts but exclude from clock | |

**User's choice:** Include all anthracyclines in the echo clock if present (class-effect cardiotoxicity). QC lists counts per drug. Doxorubicin-only result goes in as a sensitivity sub-table. Mitoxantrone explicitly excluded (different mechanism), with a note in KEY.

---

## Claude's Discretion

- Column naming conventions
- Exact xlsx sheet layout (follow existing UF-color patterns)
- Whether 166-AUDIT.md uses markdown table or prose

## Deferred Ideas

- Stratified rates by payer, SOURCE, or rurality
- BEACOPP-specific doxorubicin dose distinction
- Per-modality trend analysis beyond fu-year breakdown
