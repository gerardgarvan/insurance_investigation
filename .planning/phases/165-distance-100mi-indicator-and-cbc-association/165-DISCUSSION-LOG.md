# Phase 165: Distance >100 mi Indicator and CBC Association - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-08
**Phase:** 165-distance-100mi-indicator-and-cbc-association
**Areas discussed:** Plan 01 scope, CBC operationalization, D-165-01 decision handoff, Confounders

---

## Plan 01 Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Written memo only | Prose comparison of candidate tests, no code | |
| Memo + prototype R script | Written comparison AND a short HiPerGator script that runs each candidate on real data | ✓ |

**User's choice:** Memo plus a small prototype. A written comparison alone won't show whether encounter clustering matters in practice. Candidates: naive chi-square, Rao-Scott (`survey`), GEE logistic (`geepack`), patient-level chi-square/Fisher. The design-effect comparison between naive and adjusted SEs is the key output. Memo remains the decision document; D-165-01 records the team's choice.

**Notes:** User flagged that `survey` and `geepack` must be checked in renv before planning — neither is currently in renv.lock. A missing package stalls the HiPerGator run.

---

## CBC Operationalization

**User's choice (one-liner):** Locked. R/147's definition (WBC + Hgb + PLT same calendar date) is fixed. The memo only addresses how CBC maps onto each unit of analysis (same-date as encounter vs. any CBC in follow-up), not alternative lab definitions.

---

## D-165-01 Decision Handoff

| Option | Description | Selected |
|--------|-------------|----------|
| Immediate handoff to team | Memo → Amy/Erin → D-165-01 → Plan 02 | |
| User reviews here first | User reads memo here, makes recommendation, then forwards to team | ✓ |
| Plan 02 starts immediately | Plan 02 written to all four candidates | |

**User's choice:** User is the gate. After Plan 01 executes, user reviews memo here and makes recommendation, then forwards to Amy/Erin. Plan 02 is blocked on D-165-01. Acceptable given that Phases 166/167/168 can proceed in parallel.

**Notes:** Plan 02 should accept the method name as a parameter/config value so it can be written in advance.

---

## Confounders in Primary vs. Sensitivity

| Option | Description | Selected |
|--------|-------------|----------|
| All three in primary | Adjusted for rurality, insurance, SOURCE in main analysis | |
| Primary unadjusted, sensitivity adjusted | Bivariate primary; adjusted model in sensitivity | ✓ |
| No confounders anywhere | Pure bivariate, no adjusted model | |

**User's choice:** Primary unadjusted (clustering accounted for by test choice). Adjusted model (rurality + insurance + SOURCE) in sensitivity (Sheet C_sensitivity).

**Notes:**
- SOURCE caution: SOURCE is likely a near-proxy for distance (far encounter often = different site). Adjusting may absorb much of the effect. Memo must flag this explicitly, not present SOURCE as a neutral covariate.
- Rurality QC: RUCA/RUCC has incomplete ZIP coverage from SES work. Adjusted model will drop patients; QC must report how many are dropped.

---

## Claude's Discretion

- R script structure and naming for Plan 01 prototype
- Exact xlsx sheet layout within the KEY/A/B/C/QC structure
- GEE working correlation structure (default exchangeable unless memo recommends otherwise)

## Deferred Ideas

None.
