# Phase 161 — Death-date plausibility and follow-up end definition

## Background

R/147 (surveillance modality frequency) computes person-time from `hl_anchor_date`
(earliest HL diagnosis) to `follow_end = pmin(death_date, last_enc_date, cutoff)`.
46 of 9,331 HL patients had `hl_anchor_date >= follow_end` and were retained with
`fu_status = "zero_or_negative"` and 0 person-years. The diagnostic script
`R/161_diag_anchor_followup.R` was written to attribute these cases.

## Diagnostic findings (run 2026-10-01, cutoff 2025-12-31)

**Data quality checks: no issues**
- All date columns in DIAGNOSIS, ENCOUNTER, DEATH are typed DATE; no parse failures.
- All 9,331 HL patients have a non-NA anchor; the NA-anchor drop in R/147 removes no one.
- No orphan anchor encounters, post-cutoff anchors, or unexplained cases.

**zero_or_negative attribution (n = 46)**

| Root cause | n | Gap (median / max days) |
|---|---|---|
| Death before anchor, conflicting death dates | 14 | 901 / 2,641 |
| Death before anchor, single death date | 30 | 1,044 / 3,661 |
| Anchor = last admit; discharge date extends follow-up | 2 | 0 / 0 (≈8 days recoverable) |

**Post-death clinical activity (all decedents, n = 1,344)**

| Group | n | Activity > 30 d after death | Activity > 365 d after death |
|---|---|---|---|
| Death before anchor | 44 | 44 | 43 |
| Death after anchor | 1,300 | 217 | 136 |

261 of 1,344 decedents (19.4%) have clinical activity more than 30 days after their
earliest recorded death date (pre-fix, raw dates). For the 217 in the positive-follow-up
group, follow-up is currently truncated at an implausible death date without being flagged.

**Post-fix flag counts (N=30 grace period, resolve_death_date(), run 2026-10-01):**

| death_flag | n |
|---|---|
| plausible | 1,039 |
| conflicting_resolved (D3) | 58 |
| conflicting_unresolved | 13 |
| implausible_post_activity (D2) | 234 |
| no_death_record | 7,987 |
| **Total decedents** | **1,344** |

Reproduction check: 234 patients have `post_death_activity_days > 30` after D3 is applied
(vs. 261 pre-fix). The 27-patient reduction reflects conflicting-date cases where D3 found
an earliest-consistent date within the grace window — those are now `conflicting_resolved`,
not implausible. This is expected and correct behaviour.

"Activity" in all counts above = latest of (encounter discharge-or-admit date,
dates from DIAGNOSIS, PROCEDURES, LAB_RESULT_CM, PRESCRIBING, DISPENSING, MED_ADMIN,
VITAL, OBS_CLIN, IMMUNIZATION), restricted to dates ≤ cutoff. Phase 161 code must
use this same definition (`get_last_activity()`, 161-03) so counts reproduce.

**Follow-up end definition**

Replacing max ENCOUNTER.ADMIT_DATE with the activity definition above, while still
capping at the raw death date, extends `follow_end` for 2,759 patients (29.6%) and
increases total person-years by 0.9% (39,107 → 39,460). This figure does **not**
include the effect of D2; the expected total after D2/D3 is projected in 161-02.

**Ingest defect**

`DEATH.DEATH_DATE_IMPUTE` is typed DATE in `pcornet.duckdb`; all values are NULL.
The B/D/M imputation flags are lost somewhere between the raw extract and DuckDB.
Where the loss occurs (raw file, R/01 load, RDS cache, or R/03) is determined in 161-01.

## Root causes

1. Death records inconsistent with clinical activity — most likely linkage errors
   — are applied to follow-up without a plausibility check.
2. `last_enc_date` uses admit date only, which under-counts follow-up modestly.
3. A non-date flag column is converted to DATE during load/ingest.

## Decisions

**D1. Grace period N = 30 days** *(team sign-off required before 161-03 executes)*
- Zero days would flag normal posthumous activity (labs resulting after death,
  discharge dated the day of death, final claims). The 60-day delta is unmeasured.
- 43 of 44 death-before-diagnosis cases have activity > 365 days after death,
  so the threshold matters only at the margin.
- 161-03 outputs a sensitivity table at N = 0, 30, 60, 90, 365 days.
- Boundary: activity exactly N days after death is plausible (rule is strict `>`).

**D2. Implausible death date → treated as no credible death date** *(team sign-off required)*
- `death_date_resolved = NA`; `death_flag` records why. The patient is **not**
  counted as deceased, and is **not** assigned a death on the last-contact date.
- Follow-up ends at the last observed activity (`obs_end`) through the normal
  `pmin()`; survival analyses treat the patient as censored there.
- Rationale: excluding these patients would drop ~19% of decedents with confirmed
  HL and real follow-up; the clinical record is direct evidence the patient was
  alive, the linked death record is the weaker source.
- Deliverables include a sensitivity analysis excluding flagged patients.

**D3. Conflicting death dates: highest-priority source among consistent dates, then earliest**
- "Consistent" = death_date ≥ (last_observed − N days), or no activity on record.
- Among consistent dates, choose by DEATH_SOURCE priority, then the earliest date
  within that source. PCORnet codes: N (NDI) > S (state death file) > D (SSA) >
  L (other locally determined) > T (tumor registry) > NI/UN/OT/missing.
- *Corrects earlier wording* ("earliest, with source as tiebreaker"), which could
  never apply the tiebreaker because the earliest date is unique.
- If no date is consistent, apply D2 (`conflicting_unresolved`, `death_date_resolved = NA`).
- `n_conflicting` and the number resolvable by this rule are recorded in 161-02.

**D4. Shared utility — fixed requirement**
- `get_last_activity()` (`R/utils/utils_activity.R`) and `resolve_death_date()`
  (`R/utils/utils_death.R`) are the only sources of last-activity and death dates
  for person-time or time-to-event calculations in any script.
- 161-07 audits every script that reads DEATH. Scripts whose purpose is to study
  raw death data (e.g. R/51, R/53) are exempt and keep raw dates.

**D5. Anchor-day events = pre; zero-follow-up reported as its own category**
- Events on the anchor date belong to the diagnostic/staging workup, not
  surveillance. "Post" means strictly after `hl_anchor_date`.
- `fu_status` has three levels: `positive`, `zero`, `negative`. `negative` should
  be 0 after the fix and is kept only as a regression signal.
- Whether surveillance should begin only after treatment ends is out of scope.

**D6. Posthumous diagnosis within the grace window** *(proposed — confirm with team)*
- A death date can be plausible (activity ≤ N days after it) and still fall before
  the anchor, if the HL diagnosis was coded within N days after death. No current
  patients meet this, but nothing prevents it.
- Rule: `follow_end = hl_anchor_date`, `fu_status = "zero"`, `fu_reason = "posthumous_dx"`.

## Review corrections incorporated (2026-10-01)

- D2 implemented as NA death date + flag (earlier drafts set the death date to the
  last-contact date, which would have created deaths in R/29 and Gantt outputs).
- 161-01 first locates where the imputation flags are lost before changing code.
- One shared activity definition across 161-03/04/05/06 and R/88.
- DEATH_SOURCE matched on PCORnet codes; D3 ordering made well-defined.
- Person-year acceptance targets use the 161-02 projection, not the pre-D2 0.9%.
- R/147 outputs snapshotted in 161-01, before any code change.
- R/51 and R/53 exempt from the resolved-date requirement.

## Out of scope

- Correcting source DEATH records in OneFlorida.
- Re-deriving the HL anchor definition (validated in this phase's diagnostic).
- Deciding when post-diagnosis surveillance begins relative to treatment start.
