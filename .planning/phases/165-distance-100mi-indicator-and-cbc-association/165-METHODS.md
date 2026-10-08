# Distance >100 mi and CBC: Statistical Methods Memo

**Phase:** 165 · **Prepared:** 2026-10-08 · **Status:** Draft — awaiting D-165-01

---

## Question

Among HL cohort patients, is having an encounter more than 100 miles from the residence
on file associated with CBC receipt?

---

## Definitions

- **far_from_care_100mi:** encounter-level 0/1 indicator; ZIP-centroid straight-line distance
  (residence to encounter facility) > `CONFIG$far_from_care_cutoff_mi` (100 mi).
  All ENC_TYPE retained (AV, OT, IC, ED, OA, TH, OS, IP, EI, IS, NI, UN).
- **CBC (locked, R/147):** WBC 6690-2 + Hgb 718-7 + PLT 777-3 resulted on the same calendar date.
  Re-derived from DuckDB LAB_RESULT_CM for whole-record coverage (R/147 saves post-anchor only).
- **Encounter-level CBC:** a CBC dated within the encounter window
  (ADMIT_DATE to DISCHARGE_DATE; ADMIT_DATE alone for single-day encounters).
- **Patient-level CBC:** any CBC in the analysis window.
- **Windows:** whole record (all computed-distance encounters with a known anchor date);
  post-anchor (encounter ADMIT_DATE > HL anchor date; anchor day counted as pre, per R/147 D-25).

---

## Analysis Set

| Metric | Whole record | Post-anchor |
|--------|-------------|-------------|
| Encounter rows | 1,725,592 | 1,341,955 |
| Distinct patients | 8,455 | 8,397 |
| Far encounters (>100 mi) | 285,125 (16.5%) | 225,914 (16.8%) |
| CBC-in-encounter | 219,287 (12.7%) | 185,741 (13.8%) |

Telehealth (TH): 21,979 encounters retained in the analysis. All ENC_TYPE are included;
a sensitivity run excluding TH is available in Plan 02 if needed.

---

## Why the test choice matters

Patients contribute many encounters to this dataset. The whole-record cluster distribution is:
min=1, Q1=25, median=87, Q3=232, p95=728, max=8,752, mean=204.

Encounters from the same patient are not independent — the same person's distance from care is
largely constant across encounters, and their propensity for CBC is similarly correlated within
patient. A naive chi-square treats the 1.7M encounter rows as 1.7M independent observations and
therefore understates uncertainty. The design effect quantifies by how much.

---

## Candidates

| # | Method | Unit | CBC measure | Clustering | Effect size |
|---|--------|------|-------------|------------|-------------|
| 1 | Pearson chi-square | Encounter | CBC within encounter | Ignored | OR (Woolf) |
| 2 | Rao-Scott chi-square (F) | Encounter | CBC within encounter | Patient clusters (survey design) | OR (svyglm, quasibinomial) |
| 3 | GEE logistic | Encounter | CBC within encounter | Robust SE, cluster = patient | Marginal OR |
| 4 | Patient-level chi-square / Fisher | Patient | Any CBC in window | Not applicable (one row per patient) | OR (Fisher exact) |

---

## Results

### 2×2 Tables

**Encounter-level — whole record**

|  | CBC = 0 | CBC = 1 |
|--|---------|---------|
| far = 0 | 1,244,080 | 196,387 |
| far = 1 | 262,225 | 22,900 |

**Encounter-level — post-anchor**

|  | CBC = 0 | CBC = 1 |
|--|---------|---------|
| far = 0 | 950,323 | 165,718 |
| far = 1 | 205,891 | 20,023 |

**Patient-level — whole record**

|  | CBC = 0 | CBC = 1 |
|--|---------|---------|
| far = 0 | 1,234 | 2,522 |
| far = 1 | 2,139 | 2,560 |

**Patient-level — post-anchor**

|  | CBC = 0 | CBC = 1 |
|--|---------|---------|
| far = 0 | 1,646 | 2,520 |
| far = 1 | 2,106 | 2,125 |

Expected cells: all well above 5 in all four tables; no sparse-cell concern.
Cell counts ≥ 11 in all cells; no HIPAA suppression required for this memo.

### Numeric Results

| Window | Candidate | Unit | N rows | N patients | OR | 95% CI | SE(log OR) | DEFF | p | Notes |
|--------|-----------|------|--------|------------|-----|--------|-----------|------|---|-------|
| whole | C1 naive Pearson | encounter | 1,725,592 | 8,455 | — | — | 0.0073 | — | <2e-16 | OR undefined (integer overflow at scale); SE retained for DEFF reference |
| whole | C2 Rao-Scott | encounter | 1,725,592 | 8,455 | 0.553 | [0.470, 0.651] | 0.0833 | **130.1** | 6.8e-13 | F-statistic = 51.77 |
| whole | C3 GEE | encounter | — | — | — | — | — | — | — | Skipped: computationally infeasible at 1.7M encounters within SLURM time limit |
| whole | C4 patient Fisher | patient | 8,455 | 8,455 | 0.586 | [0.535, 0.641] | 0.0454 | — | <2e-16 | chi2 = 139.67 |
| post | C1 naive Pearson | encounter | 1,341,955 | 8,397 | — | — | 0.0079 | — | <2e-16 | OR undefined (integer overflow at scale) |
| post | C2 Rao-Scott | encounter | 1,341,955 | 8,397 | 0.558 | [0.468, 0.665] | 0.0898 | **130.3** | 4.9e-11 | F-statistic = 43.33 |
| post | C3 GEE | encounter | — | — | — | — | — | — | — | Skipped (same reason) |
| post | C4 patient Fisher | patient | 8,397 | 8,397 | 0.659 | [0.604, 0.719] | 0.0442 | — | <2e-16 | chi2 = 89.49 |

---

## Interpretation

**Design effect.** DEFF = 130 in both windows. This means the effective sample size for the
encounter-level analysis is 1,725,592 / 130 ≈ 13,274 independent units — not 1.7 million.
The naive chi-square SE of 0.0073 (whole) is approximately 11× smaller than the Rao-Scott
SE of 0.0833. Ignoring clustering produces dramatically overconfident p-values and intervals
that cannot be trusted. The encounter count in this cohort is large enough that DEFF = 130
is plausible: median 87 encounters per patient, max 8,752.

**C1 (naive Pearson) is not usable.** Beyond ignoring clustering, the Woolf OR computation
overflowed to NA at 1.7M encounter rows. C1 is excluded from consideration.

**C3 (GEE) could not be evaluated.** With 1.7M rows and max cluster size 8,752,
the geeglm fitting loop exceeded the SLURM time budget before convergence. Note also that
CONFIG$distance_gee_corstr was automatically overridden to "independence" by the prototype
due to cluster size. If a GEE estimate is needed for the primary analysis, it would require
a 10% patient sample run or a dedicated high-memory, longer-time allocation.

**Direction agreement.** C2 (Rao-Scott, encounter-level) and C4 (patient-level, Fisher) agree
in direction: far-from-care encounters are negatively associated with CBC receipt (OR < 1 in
both windows). The association is robust to the unit of analysis.

**Windows agree.** The OR estimates are close across windows: C2 gives 0.553 (whole) vs 0.558
(post); C4 gives 0.586 (whole) vs 0.659 (post). The post-anchor patient-level OR is slightly
attenuated, which is consistent with patients who travel far for care potentially receiving
some monitoring at their home site in the post-treatment period.

---

## Caveats

- **SOURCE:** Encounters far from home tend to occur at a different SOURCE site than the
  patient's usual care, so SOURCE partly measures the same thing as distance. Adjusting for
  SOURCE in the sensitivity model (Plan 02, Sheet C_sensitivity) may absorb a substantial
  portion of the association; the adjusted estimate should be interpreted with that in mind.
  This is not a neutral covariate — it is likely a near-proxy for the exposure itself.

- **Rurality:** RUCA coverage is incomplete for some ZIP codes. The adjusted sensitivity
  model drops encounters without a RUCA match; the QC sheet in Plan 02 will report how many
  are dropped.

- **Distances are ZIP-centroid straight-line distances**, not travel distance or time.
  Patients in rural areas may face longer effective travel times even at shorter straight-line
  distances.

- **Telehealth (TH): 21,979 encounters** carry a facility ZIP that reflects the provider
  location, not travel burden. All ENC_TYPE are retained in the primary analysis; a TH-excluded
  sensitivity run can be added to Plan 02 if the team wishes.

- **C3 GEE was not obtained.** The evidence base for the recommendation is C2 and C4 only.

---

## Recommendation

**Primary analysis: C4 (patient-level Fisher / chi-square).**

The DEFF of 130 at the encounter level is not a minor correction — it eliminates the
inferential value of encounter-level analysis unless clustering is properly accounted for.
C2 (Rao-Scott) does account for it and gives consistent results, but it requires the survey
package and produces an estimate whose interpretation depends on the encounter universe (which
includes telehealth, repeat monitoring, and unrelated visits). C4 collapses to one row per
patient, so clustering is irrelevant by construction, and the estimand — is a patient who
has any far-from-care encounter less likely to receive a CBC? — maps directly to the clinical
question.

C4 results are also numerically stable (no overflow, no failed convergence), fast, and easy
to communicate to clinical collaborators.

**Sensitivity check: C2 (Rao-Scott encounter-level).**

C2 confirms the direction and approximate magnitude of C4 while using a different unit of
analysis. It should be reported alongside C4 in the final output to demonstrate robustness
to the unit-of-analysis choice. The DEFF should be stated explicitly in the output so readers
understand that the encounter count understates effective information.

If the team prefers an encounter-level primary result, C2 is the only defensible choice given
the clustering structure observed here.

---

## D-165-01

Team selection: ________  Date: ________

*(Record here and in 165-CONTEXT.md Decisions; set CONFIG$distance_assoc_method before Plan 02 runs.
Recommended value: "patient_fisher" for C4 primary; "rao_scott" for C2 sensitivity.)*
