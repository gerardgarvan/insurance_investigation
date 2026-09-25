# Phase 160: Surveillance Lab Accuracy and Reporting Improvements - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-25
**Phase:** 160-surveillance-lab-accuracy-and-reporting-improvements
**Areas discussed:** D-4 (breast imaging denominator presentation); D-1, D-2/D-3, D-5 accepted as defaults

---

## D-1: CMP sensitivity threshold

| Option | Description | Selected |
|--------|-------------|----------|
| 11 of 14 | Full BMP + ≥3 liver/protein analytes; cuts 8-of-14 and 9-of-14 days | ✓ |
| 10 of 14 | One step lower; only 236 additional days difference | |

**User's choice:** 11 of 14 (default accepted)
**Notes:** 10 vs 11 differs by only 236 patient-days out of ~190,000 — effectively the same result. 11 is the cleaner clinical boundary.

---

## D-2 / D-3: A3 diagnostic parameters

| Option | Description | Selected |
|--------|-------------|----------|
| Exactly n−1 only | Block 1: strict one-below-complete near-misses | ✓ |
| Include shallower | Block 1: n−2, n−3 etc. also reported | |
| 5,000 sample | Block 2: up to 5,000 ID × dates per rule, fixed seed | ✓ |
| Larger sample | Block 2: 10,000+ | |

**User's choice:** Defaults accepted (n−1 only; 5,000 sample)
**Notes:** These only shape a diagnostic sheet, not any counts. If 5,000 doesn't expose the missing code, the checkpoint can raise the sample without redesign.

---

## D-4: Breast imaging denominator presentation

| Option | Description | Selected |
|--------|-------------|----------|
| All-patient headline, female beside it | "Any breast imaging" leads; "among women" directly adjacent | ✓ |
| Female headline, all-patient beside it | Female-denominator leads, consistent with screening intent | |
| Female only in a separate section | Two separate table blocks | |

**User's choice:** All-patient as headline, female-denominator directly beside it
**Notes:**
- Consistency: every other modality leads with the full cohort; breast imaging should too
- Male breast imaging stays in the primary view rather than a side column
- Female-denominator label: "among women (screening population)"
- The female figure becomes the headline when the work shifts to guideline adherence (Phase 161 territory)
- Male/unknown-sex patients with ≥1 event appear in `n_patients_other_sex` / `total_event_dates_other_sex`

---

## D-5: Other analyte thresholds

| Option | Description | Selected |
|--------|-------------|----------|
| No change | BMP ≥4, LFT ≥2, LIPID ≥2 unchanged | ✓ |
| Revisit | Raise any threshold based on near-miss evidence | |

**User's choice:** No change (default accepted)
**Notes:** Near-misses just below these thresholds are small (BMP 4–6 of 8: 1,284 days; LFT 2–3 of 4: 1,888 days) — no sign of CMP-style systematic spillover.

---

## Claude's Discretion

- Exact fixed seed value for A3 block 2 sampling
- Sheet column ordering within A3 blocks
- Internal variable names for eligibility denominators

## Deferred Ideas

- Care-setting filtering (inpatient vs outpatient) — Phase 161
- Surveillance start window (post-treatment) — Phase 161
