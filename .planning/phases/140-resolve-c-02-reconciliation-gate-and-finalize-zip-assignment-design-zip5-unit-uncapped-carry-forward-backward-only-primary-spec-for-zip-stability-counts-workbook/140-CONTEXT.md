# Phase 139 — ZIP Assignment Plan

**Status:** Workbook `zip_stability_counts_20260806.xlsx` is on hold. C-02 gate failed.
**Inputs reviewed:** `R/115_zip_stability_counts.R`, `R/utils/utils_address.R`, run of 2026-08-06.
**Cohort N:** 9,282. **Encounters:** 1,980,122.

---

## 1. Purpose

Decide how ZIP is assigned to cohort encounters, and what has to be resolved before
`zip_stability_counts_20260806.xlsx` is released.

Three questions drive the plan:

1. Is the C-02 reconciliation failure a pipeline defect or a stale control total?
2. Should the analysis unit be ZIP9 or ZIP5, and over what carry-forward window?
3. Which of S1–S4 do we adopt, and do we accept forward lookup?

---

## 2. Blocking item — C-02 reconciliation (P-01)

`c02_reconciled = FAIL`. Computed 665 against `C02_EXPECTED = 26` (tolerance ±5).
The failure message in `R/115` attributes a materially higher number to the
ZIP5-coalescing fix not reaching raw ZIP5 values. **The QC sheet does not support that
attribution.**

| Component of the 665 | n | Share |
| --- | ---: | ---: |
| Cohort patients with zero rows in `addr_coal` | 656 | 98.6% |
| Cohort patients in `addr_coal` with no usable ZIP5 | 9 | 1.4% |

If coalescing were failing, it would show in the second row. Nine is not a coalescing
failure. The 665 is a coverage figure, and coverage is what FIX-03b deliberately made
visible by scoping the denominator to `COHORT_IDS`.

**Working hypothesis:** the team's 26-patient control total was derived over patients
*present in the address file*, i.e. against the pre-FIX-03b denominator. If so, the
expected value is stale relative to the patched definition and the pipeline is correct.

### P-01 tasks

| ID | Task | Acceptance |
| --- | --- | --- |
| P-01a | Re-derive the 26-patient control total from the originating team notes — record the exact denominator it was computed over | Written statement of the denominator, filed with the phase notes |
| P-01b | If P-01a confirms a file-present denominator, reset `C02_EXPECTED` against a re-derived cohort-scoped total and document the change in the KEY sheet | `c02_reconciled = PASS` with the basis for the new expected value stated, not just the number changed |
| P-01c | If P-01a does **not** confirm it, escalate before any further work — the coalescing hypothesis is back in scope | — |

Do not widen `C02_TOLERANCE` to absorb this. FIX-03d narrowed the tolerance to
cohort-definition drift specifically; using it as general slack would undo that.

---

## 3. Coverage investigation (P-02)

Independent of the gate, two coverage numbers need an explanation before the workbook
carries a completeness claim.

- **280-patient pre/post-filter gap.** C-02 is 385 pre-filter and 665 post-filter.
  That is 280 cohort patients who lose *every* address row to the study-period and
  unparseable-date filters.
- **4,912 unparseable `period_start_dt` records dropped**, plus 1,299 out-of-range.

| ID | Task | Acceptance |
| --- | --- | --- |
| P-02a | Sample the 4,912 unparseable dates and classify the failure modes | Format variants distinguished from genuinely absent dates |
| P-02b | If a recoverable format variant accounts for a material share, extend `parse_pcornet_date()` and re-run | Drop count reduced, or a statement that the residual is genuinely unparseable |
| P-02c | Report the 280-patient filter loss explicitly in the QC sheet rather than leaving it implicit in the pre/post comparison | Named QC row |

---

## 4. Analysis unit — recommend ZIP5 (P-03)

### Evidence

- 39.3% of all ZIP9 transitions are +4-only (same ZIP5, different delivery point).
- Validation separates ZIP5 from ZIP9 at every horizon past same-day:

| Gap (days) | n cases | ZIP9 exact | ZIP5 same |
| --- | ---: | ---: | ---: |
| 0 (same-day) | 1,111 | 97.0% | 97.7% |
| 0–30 | 964 | 62.6% | 77.4% |
| 31–90 | 1,145 | 41.7% | 65.0% |
| 91–180 | 1,308 | 34.7% | 57.0% |
| 181–365 | 2,008 | 29.1% | 52.0% |
| 366+ | 5,767 | 23.7% | 56.1% |
| Overall | 12,303 | 37.1% | 61.8% |

Most downstream linkage (ADI, SVI, RUCA, ZCTA-level covariates) resolves at tract or
block-group level, where +4 churn is noise rather than signal.

### Countervailing consideration

Exact-ZIP9 match is a **conservative proxy** for geographic accuracy. A +4 change that
stays inside the same block group scores as a miss in the table above but would be a hit
for ADI. The block-group tier returned `#N/A` — `has_block_group_crosswalk = FALSE`.

**Recommendation:** adopt ZIP5 as the analysis unit, but obtain the crosswalk and re-run
A-06 with the block-group tier before formally excluding +4 from the design. The 23.7%
figure may materially understate ZIP9 utility at the unit we actually link on.

| ID | Task | Acceptance |
| --- | --- | --- |
| P-03a | Locate and stage the ZIP9 → block-group crosswalk | `has_block_group_crosswalk = TRUE` |
| P-03b | Re-run A-06 with the block-group tier populated | `pct_block_group_match` populated across all gap bins |
| P-03c | Confirm or revise the ZIP5 recommendation against P-03b output | Documented decision |

---

## 5. Carry-forward window — recommend no hard cap (P-04)

The ~90-day diagnosis-episode convention should not be imported. `R/115` already flags
it as a reference only, and the gap distribution supports that caution:

- Median gap between ZIP9 changes: **547 days** (p25 184, p75 1,310).
- Roughly 22% of gap observations fall under 180 days.

A 90-day cap would strand the majority of encounters for little accuracy gain. ZIP5
accuracy flattens around 52–57% past 90 days, so there is no decay cliff that justifies
a cutoff at 180 or 365 either.

**Recommendation:** carry ZIP5 forward without a cap, and write elapsed gap-days into
the analytic dataset as a variable. Recency then becomes a sensitivity analysis rather
than a discard rule, which is the more defensible posture under review.

| ID | Task | Acceptance |
| --- | --- | --- |
| P-04a | Add `gap_days_at_assignment` to the analytic dataset | Variable present, one value per assigned encounter |
| P-04b | Confirm the non-monotonic ZIP5 result (52.0% at 181–365 rising to 56.1% at 366+) is a composition effect and not a binning artifact | Written finding; if artifact, re-bin before the figure is used in methods |

---

## 6. Validation design — current curve is a lower bound (P-05)

A-06 is record-anchored: hold out an `addr_coal` record, predict from the prior one.
Address records exist *because* something changed, so non-same-day pairs are sampled at
or near change boundaries. Encounters are not distributed that way.

Compounding this, **2,339 patients were excluded** for having a single usable record.
Those are the most stable patients in the file — 64.8% of patients have zero ZIP9
transitions and the median is 0 — and they are structurally absent from the validation.

The 37.1% overall figure therefore does not describe production behaviour and should not
be presented as if it does.

| ID | Task | Acceptance |
| --- | --- | --- |
| P-05a | Build an encounter-anchored validation variant: sample actual `ADMIT_DATE`s, predict via `get_zip9_at_date()`, compare against a same-day address record where one exists | Second curve, reported alongside A-06 |
| P-05b | Label A-06 as a lower bound wherever it appears | KEY sheet and A_validation_curve subtitle updated |

---

## 7. Scenario adoption (P-06)

### Completeness waterfall as run

| Step | Gain | Cumulative |
| --- | ---: | ---: |
| already_has_zip9 | 74.4% | 74.4% |
| + S1 | +1.7pp | 76.1% |
| + S2 | +11.0pp | 87.1% |
| + S3 | +9.8pp | 96.9% |
| unresolvable | 3.1% | 100% |

### Findings

**S1 does not warrant a standalone rule.** It buys 1.7pp and is definitionally entangled
with S3 under FIX-04d — an encounter eligible only via S1-forward is assigned S1 by the
ordered rule while remaining S3-eligible. The implementation and documentation cost
exceeds the yield. Fold it into S3.

**S2 is the main lever and the weakest evidentially.** 201,118 of 217,570 S2 encounters
(92%) are forward-only. The same pattern holds in S1 (22,961 forward vs 12,561
backward). Forward lookup infers a past address from a future one, and
`get_zip9_at_date()` is backward-only — so adopting S1/S2 as specified is a
methodological change to production, not a coverage patch.

**Complete-case is not viable.** S4-excluded removes 507,400 encounters and 7,446 of
9,282 patients (80.2%). Any patient-level complete-case restriction retains under a
fifth of the cohort. This should be stated explicitly in the memo as the reason
imputation is being done at all.

### Recommended specification

| Specification | Composition | Approximate coverage |
| --- | --- | --- |
| **Primary — backward-only** | already_has_zip9 + S2-backward + S3 | ~86% of encounters |
| **Sensitivity — forward-inclusive** | Full ordered waterfall | 96.9% of encounters |

Agreement between the two preempts the obvious reviewer objection to forward inference.
Divergence is itself a reportable finding.

> **Do not compute the ~86% by summing `B_direction_split` rows.** Those counts are
> unordered and overlapping. The backward-only figure requires a recomputed ordered
> waterfall.

| ID | Task | Acceptance |
| --- | --- | --- |
| P-06a | Add a backward-only ordered waterfall as a parallel column in `C_completeness` | Column present, computed not derived by arithmetic |
| P-06b | Collapse S1 into S3 in the ordered assignment; retain the S1 counts as reporting-only | FIX-04d caveat becomes unnecessary rather than restated |
| P-06c | Team decision on whether forward lookup is acceptable as primary | Recorded decision (see §9) |
| P-06d | If forward lookup is adopted as primary, extend `utils_address.R` with a forward variant rather than keeping the logic local to `R/115` | Shared utility, single implementation |

---

## 8. Smaller items (P-07)

| ID | Item | Action |
| --- | --- | --- |
| P-07a | Part A is not cohort-scoped — runs over `addr_coal` (n = 8,675) while Part B/C run over the 9,282 cohort. Overlap is ~8,626, so Part A includes ~49 non-cohort patients and omits 656 cohort patients whose stability is unmeasurable. The stability figures describe the address file, not the cohort. | Re-run Part A cohort-restricted, or state the universe difference prominently on each Part A sheet |
| P-07b | Sentinel nulling is negligible — 1 ZIP9, 32 ZIP5 | Close as clean; note in the memo rather than leaving it open on QC |
| P-07c | `get_zip9_at_date()` has no injection seam for the address table, so unit tests must round-trip through `CONFIG$data_dir` | Optional `addr_full = NULL` parameter with character coercion, if test coverage is wanted |

---

## 9. Decisions required from the team

| # | Decision | Owner | Blocks |
| --- | --- | --- | --- |
| D-1 | Confirm the denominator behind the 26-patient control total | Erin / Amy | P-01, release |
| D-2 | Accept ZIP5 as the analysis unit (pending P-03b) | Erin / Amy | P-03c |
| D-3 | Accept uncapped carry-forward with gap-days as a covariate | Erin / Amy | P-04a |
| D-4 | Accept or reject forward lookup in the primary specification | Erin / Amy | P-06c, P-06d |

---

## 10. Sequence

1. **P-01** — resolve the C-02 gate. Nothing ships before this.
2. **P-02** — coverage investigation, in parallel with P-01.
3. **P-03a/b** — obtain crosswalk, re-run A-06 with block-group tier.
4. **D-1 through D-4** — team decisions, informed by steps 1–3.
5. **P-06a/b, P-04a** — recompute waterfall and analytic dataset per decisions.
6. **P-05a** — encounter-anchored validation.
7. **P-07** — cleanup, re-issue workbook.

---

## 11. Out of scope

- Changes to `normalize_zip9()` / `normalize_zip5()` — sentinel and normalization
  behaviour is performing as specified (P-07b).
- Caching of `LDS_ADDRESS_HISTORY` — D-06 load-on-demand stands.
- Any release of `zip_stability_counts_20260806.xlsx` in its current form.

---

## Summary

Hold the workbook, but treat C-02 as a stale expected value rather than a pipeline
defect until P-01a says otherwise — 656 of the 665 are coverage, not coalescing. Build
on ZIP5 with uncapped carry-forward and a gap-days covariate, pending the block-group
crosswalk. Lead with the backward-only specification and report forward-inclusive as
sensitivity.
