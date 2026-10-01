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
recorded death date. For the 217 in the positive-follow-up group, follow-up is
currently truncated at an implausible death date without being flagged.

**Follow-up end definition**

Replacing max ENCOUNTER.ADMIT_DATE with the latest of discharge/admit date and any
CDM activity (≤ cutoff) extends `follow_end` for 2,759 patients (29.6%), increasing
total person-years by 0.9% (39,107 → 39,460).

**Ingest defect**

`DEATH.DEATH_DATE_IMPUTE` is typed DATE in `pcornet.duckdb`; all values are NULL.
The B/D/M imputation flags were lost at ingest (R/03), so imputed death dates
cannot currently be identified.

## Root causes

1. Death records inconsistent with clinical activity — most likely linkage errors
   — are applied to follow-up without a plausibility check.
2. `last_enc_date` uses admit date only, which under-counts follow-up modestly.
3. R/03 assigns DATE type to a non-date flag column.

## Decisions (locked)

**D1. Grace period N = 30 days** *(team sign-off required before 161-03 executes)*
- Zero days would incorrectly flag normal posthumous activity (labs resulting after
  death, discharge dated day of death, final claims). Sixty days would flag fewer
  patients but the delta is unmeasured.
- 43 of 44 death-before-diagnosis cases have activity > 365 days after death,
  so the threshold only matters at the margin.
- **161-03 must output a sensitivity table at N = 0, 30, 60, 90, 365 days** so
  the choice is documented rather than assumed.

**D2. Ignore implausible death date; end follow-up at last observed activity; flag patient** *(team sign-off required)*
- Excluding 261 patients would drop ~19% of decedents — patients with confirmed HL
  and real follow-up (median 150 encounters among the 44 death-before-diagnosis cases).
- The clinical record is direct evidence the patient was alive; the linked death
  record is the weaker source.
- Ending follow-up at last activity is standard practice when true end date is unknown.
- The deliverable must include a sensitivity analysis excluding flagged patients.

**D3. Conflicting death dates: use the earliest date consistent with activity; apply D2 if none**
- *Corrects plan draft, which said "latest."* Choosing the latest consistent date
  would stretch follow-up past anything confirmable; earliest consistent is safer.
- "Consistent" = death_date ≥ (last_activity_date − N days).
- If `DEATH_SOURCE` is populated, use source priority as tiebreaker:
  NDI or state death files > SSA > local / tumor-registry records.
- `n_conflicting` and `n_death_max_reconciles` are still pending; re-run
  `R/161_diag_anchor_followup.R` with `print(width = Inf)` to confirm how many
  cases this rule resolves.

**D4. Shared utility — fixed requirement, not optional**
- `resolve_death_date()` must be implemented in a shared utility (e.g.
  `R/utils/utils_death.R`) and called by every script that reads DEATH, not
  only R/147. If it is only applied in R/147, all other scripts will continue
  using uncorrected death dates.
- 161-07 must audit every script that reads DEATH and confirm each uses
  `resolve_death_date()`.

**D5. Anchor-day events = pre; zero-follow-up patients reported as their own category**
- Events on the anchor date are part of the diagnostic and staging workup, not
  surveillance. "Post" means strictly after `hl_anchor_date`.
- After the D2/D3/D4 fix, very few zero-day patients should remain (the 2
  inpatient cases gain ~8 days each). Report zero-follow-up separately from
  negative-follow-up in all output tables.
- Whether surveillance should begin only after treatment ends is a definitional
  question for the team and is out of scope for this phase.

## Out of scope

- Correcting source DEATH records in OneFlorida.
- Re-deriving the HL anchor definition (anchor logic validated in this phase's diagnostic).
- Deciding when post-diagnosis surveillance begins relative to treatment start.
