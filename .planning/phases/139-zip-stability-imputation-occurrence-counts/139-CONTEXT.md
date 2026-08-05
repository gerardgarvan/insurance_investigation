# Phase 139: ZIP Stability & Imputation Occurrence Counts — Context

**Gathered:** 2026-08-05
**Status:** Ready for planning
**Source of requirement:** Team meeting notes 08/04/2026 and 07/21–24/2026 (TeamMtgNotes2026.docx)
**Numbering note:** This document was originally drafted as "Phase 140" and adopted verbatim as Phase 139's CONTEXT.md during `/gsd:add-phase` + `/gsd:discuss-phase` on 2026-08-05, since the roadmap's actual next integer phase is 139, not 140. Self-references to "Phase 140" below have been renumbered to 139. See the flagged note under "Blocking question" and in `canonical_refs` for a real content discrepancy this renumbering surfaced — do not skip it.
**Patch note (2026-08-05):** This document has been amended by `139-05-PATCH.md`, a soundness-review patch applied to plans 139-01 through 139-04. Two amendments are recorded inline below: a re-confirmation of the PRECOND-01 finding (see "Blocking question"), and a reconciliation of the A-06 and B-03 decision text with the patch's corrected reasoning (see "Decisions" — A-06 and B-03). Read `139-05-PATCH.md` for the full technical rationale; this file only records the resulting decisions.

<domain>
## Phase Boundary

A **counting and validation deliverable** that answers the question assigned to GG in the
07/21 and 08/04 meetings:

> Priority – GG to see how often 9-digit zip changes at individual level; EMM suggested
> using same approach of time window as we have for dx

and the associated occurrence-count request attached to the imputation rules:

> Goal – If we have 9-digit zip code for certain encounters but not all, can we extrapolate
> for encounters that are missing 9-digit zip? *For each of the items below, we want to know
> how many times they occur*

The notes tie these together explicitly — the change-frequency analysis exists to justify the
carry-forward rules, not as a standalone descriptive:

> ...or use the centroid of the 5-digit zip extrapolated to the 9-digit level *this is why we
> want to see how often zip codes change*

**In scope:**
- `R/115_zip_stability_counts.R` — an investigation script (deferred from Phase 139)
- Part A: ZIP stability at the individual level, including a carry-forward validation curve
- Part B: occurrence counts for each imputation scenario named in the 08/04 notes
- Part C: cumulative completeness table ("See where that gets us in terms of completeness")
- One Excel workbook deliverable for Erin/Amy

**Out of scope:**
- Any change to `get_zip9_at_date()` or `approximate_zip9()` — this phase measures, it does
  not modify. Findings feed the phase that actually builds the imputation rules (see numbering
  note above — that phase does not exist yet under any number).
- ADI/SDI computation — separate phase, blocked on the open ADI-vs-SDI question (see
  "Blocking question" below).
- Choosing the time window. This phase produces the evidence; the team picks the value.

</domain>

<blocking_question>
## Raise before implementation

**Numbering/precondition discrepancy (surfaced 2026-08-05, not in the original notes):** This
document's decisions below assume a prior "Phase 139: zip9-approximation" already shipped
`approximate_zip9()`, `is_sentinel_zip5()`, and an "AMEND-01" ZIP5-coalesce fix, referenced via
`.planning/phases/139-zip9-approximation/`. That phase does not exist — no roadmap entry, no
directory, no commit, no matching function anywhere in `R/`. Only Phase 137
(`get_zip9_at_date()`, `normalize_zip9()`, `normalize_zip5()`, `normalize_zip5_raw()`) is real.
Logged in `.planning/STATE.md` under "Known Blockers." **Resolve this before planning proceeds**
— either the imputation-rules work needs to be built first (a phase inserted before 139), or
every reference below to `approximate_zip9()`, `is_sentinel_zip5()`, and AMEND-01 needs to be
re-scoped as work this phase does itself rather than a precondition it can assume.

**PRECOND-01 re-confirmation (139-05-PATCH.md, re-checked 2026-08-05 during patch application):**
`139-05-PATCH.md` raised the possibility that a "working copy of `R/utils/utils_address.R`
reviewed on 2026-08-05" contained `approximate_zip9()` (with `zip9_source`, a memoised
ZIP5→modal-ZIP9 cache, and a probe-first gate) and the AMEND-01 coalesce inside
`get_zip9_at_date()`, and instructed that this be verified before any of Plans 01–04 execute.
That verification was performed at patch-application time:

```
git log --oneline -- R/utils/utils_address.R   → only 3dc8946 (Phase 137 creation), nothing since
git status --short R/utils/                     → clean, no uncommitted changes
grep -n "approximate_zip9|zip9_source|coalesce(normalize_zip5" R/utils/utils_address.R → zero matches
git branch -a                                   → only main/origin/main exist
```
Every commit on every branch was additionally searched for `approximate_zip9`/`zip9_source` —
zero matches anywhere, committed or uncommitted, on any branch.

**Outcome: work genuinely absent.** The "reviewed working copy" the patch's author described was
never persisted to this repository, on any branch. Per `139-05-PATCH.md`'s own instructions for
this outcome, Plans 01–04 stand as written on the coalescing-duplication question — Plan 01 Task 2
(now via a single `coalesce_zip5()` function, see Decisions below) is not a second implementation
of anything, because there is no first implementation anywhere in the repository to duplicate.
`is_sentinel_zip5()` likewise remains a genuine, small gap this phase closes (Plan 01 Task 1).

The 08/04 notes state the deprivation-measure rule as a **two-measure design**:

> Use the most precise measure of deprivation that we can; if we have a way to map 9-digit
> zip code, then we can use ADI; if we only have 5-digit zip, then we may need to use SDI

Phases 138 and the assumed-but-missing zip9-approximation work (see discrepancy note above) were
intended to implement a **one-measure design** — impute a ZIP+4 so that every record can take
ADI. No meeting note records that substitution.

This phase's Part B counts are the input to that decision either way, so scoping/design can
proceed once the precondition discrepancy above is resolved. But the counts should be presented
to the team framed as "how many records would need imputation under the ADI-for-all design,
versus how many would route to SDI under the design in the notes" — not as a foregone conclusion
in favor of imputation.

Relevant correction for that discussion: the 03/2026 notes record "SDI is at county level."
SDI is published at four geographies — county, census tract, ZCTA, and PCSA. ZCTA is the
relevant one for 5-digit-only records and is far finer than county, which likely makes the SDI
branch more attractive than it appeared when discussed.

</blocking_question>

<decisions>
## Part A — ZIP stability at the individual level

### A-01: Two change types, counted separately (not collapsed)

A ZIP+4 changing is not evidence a patient moved. USPS resegments +4 ranges, and an EHR
address correction can rewrite the +4 while the household stays put. Report:

| Metric | Definition |
|---|---|
| `n_distinct_zip9` | Distinct valid ZIP9s observed for the patient |
| `n_distinct_zip5` | Distinct valid ZIP5s observed |
| `n_zip9_transitions` | Consecutive-record ZIP9 changes, ordered by period start |
| `n_zip5_transitions` | Consecutive-record ZIP5 changes |
| `n_plus4_only_transitions` | `n_zip9_transitions` where ZIP5 was unchanged |

`n_plus4_only_transitions` is the one that matters most for the carry-forward decision. A high
ZIP9 churn rate that is almost entirely +4-only means carry-forward is *more* defensible than a
raw ZIP9 change count would suggest, because ADI is assigned at the block group and a +4
resegmentation within a ZIP5 will frequently land in the same one.

### A-02: NA is not a change

A patient sequence of `32611-1234 → NA → 32611-1234` has **zero** transitions, not two. Drop
records with NA ZIP9 before computing ZIP9 transitions; compute ZIP5 transitions on the
separate non-NA-ZIP5 sequence. Report the count of records dropped at each step.

### A-03: Deduplicate before counting

LDS_ADDRESS_HISTORY carries repeated rows for an unchanged address. Collapse consecutive
records with an identical normalized ZIP9 into a single spell before counting transitions, or
every count is inflated by record-keeping churn rather than movement.

### A-04: Exposure denominator, not a bare count

A patient with one address record has zero transitions by construction — that is not stability,
it is absence of observation. Report transitions per patient-year of address-history coverage
alongside raw counts, and report the distribution of observation span so the team can see how
much of the "no change" mass is genuine.

**139-05-PATCH FIX-04b note:** the exposure span must be computed from each record's *effective
end date* (coalesced to a far-future sentinel for open-ended/current records, then capped at the
data-extraction-date proxy), not from `period_start_dt` alone — a bare start-to-start span
ignores how long the last record was actually observed and can badly inflate or deflate the
transitions-per-year rate. See `R/115_zip_stability_counts.R` Section 5 for the implementation.

### A-05: Time between changes

For patients with ≥1 transition, report the distribution of days between consecutive changes
(median, IQR, deciles). This is the direct input to EMM's time-window suggestion — the window
should be chosen against this distribution, not assumed from the diagnosis convention.

Report the diagnosis-episode window currently in use (~90 days per the 06/23 notes) as a
reference line on the plot so the team can see whether the ZIP behavior actually resembles the
dx behavior. **Do not assume it transfers.** EMM proposed the same *approach*, not the same
number.

### A-06 (recommended addition): Carry-forward validation curve

*This is not in the notes. It is the analysis that actually answers the underlying question,
and I recommend including it — flag it as an addition when presenting.*

Raw change counts do not tell the team whether carry-forward is safe. A hold-out test does:

1. Take encounters that **do** have an observed ZIP9
2. Blank the ZIP9 and apply the carry-forward rule as implemented
3. Compare the imputed value against the value that was actually there
4. Report accuracy as a function of gap length (days between the source record and the target
   encounter), binned — 0–30, 31–90, 91–180, 181–365, 366+

Report three accuracy levels at each gap: exact ZIP9 match, same ZIP5, and same block group
where the Neighborhood Atlas file is available. Block-group agreement is the one that matters
for ADI; exact ZIP9 agreement understates how well the method performs for its actual purpose.

This produces a defensible, empirical basis for the time-window choice, and it is the figure
most likely to be asked for in review.

**139-05-PATCH FIX-01 amendment (reconciles this decision with the implemented design):** the
plan built against this decision (139-02-PLAN.md) implements the hold-out test on
**address-history records** (`addr_coal`, one row per raw address record), not on the ENCOUNTER
table literally. Each held-out record's own `period_start_dt` is the lookup date; the record is
predicted from the most recent prior address-history record with a non-NA ZIP9, and compared —
the same rule `get_zip9_at_date()` applies in production. This is a deliberate, corrected
framing (labeled "F1" in the patch): it is not a literal implementation of step 1 above ("take
encounters that do have an observed ZIP9") anchored on the ENCOUNTER table, and it is *not*
justified as a reinterpretation of Pitfall 1 ("target encounter" read as "target lookup date") —
that reinterpretation was an earlier reasoning error the patch corrected. Pitfall 1 governs
universe consistency across sheets (Part A on address history, Part B/C on encounters), not
A-06's sampling frame. The corrected justification is simpler: A-06 measures the SAME
carry-forward rule regardless of which table supplies the lookup dates, and testing it on
address-history records (rather than spell-collapsed address history, which was the actual bug
this patch fixed) retains the unchanged-address cases where carry-forward's accuracy actually
lives. An encounter-anchored framing ("F2" in the patch) was considered and rejected for this
phase only because it would move Plan 02 to wave 4 (depending on the ENCOUNTER pull) with no
accuracy benefit for this deliverable's purpose — not because it is wrong.

## Part B — Imputation scenario occurrence counts

### B-01: The four scenarios, verbatim from the 08/04 notes

| ID | Scenario | Status in notes |
|---|---|---|
| S1 | ZIP5 at an encounter matches the ZIP5 of a ZIP9 at another encounter for the same patient → extrapolate the ZIP9 | Agreed |
| S2 | Encounter has neither ZIP5 nor ZIP9 → take a ZIP9 from another encounter, or use the ZIP5 centroid | Agreed |
| S3 | ZIP5 at an encounter does **not** match the prior ZIP9's ZIP5 → use the ZIP5 centroid | ***Still pending as of 08/04*** |
| S4 | Complete-case: exclude encounters without an observed ZIP9 | Agreed as comparator |

**S3 is unresolved.** Count how often it would fire and report the count, but do not present
either resolution as decided. The count itself is what the team needs in order to resolve it.

### B-02: Count at both levels, with explicit denominators

Every count reported as N and % at **encounter level** and **patient level**, with the
denominator named in the cell label. The notes discuss encounters ("ZIP+4 only for ~half of
encounters") while eligibility and exclusion operate on patients; a table that does not say
which it is will be misread.

### B-03: Scenarios are mutually exclusive and ordered

An encounter can satisfy more than one scenario. Assign each encounter to exactly one, applying
S1 → S2 → S3 in that order, and report the assignment counts. Also report the unordered
"eligible for" counts so the team can see the overlap. Without both, the numbers will not
reconcile against anything computed a different way later.

**139-05-PATCH FIX-04d amendment:** because S1's ordered test runs before S3's, an encounter that
is eligible for S3 (by S3's own definition: the complement of S1-*backward*-eligibility) but is
ALSO eligible for S1 via the *forward* direction gets assigned "S1" by the ordered rule, not
"S3" — the ordered assignment tests S1-*either* (backward or forward) first. The ordered "S3"
column therefore undercounts true S3-eligibility whenever forward-fill would have resolved a
case S3's own definition would also claim. Both the ordered "S3" column and the unordered
"S3-eligible" column (the complement-of-S1-backward count, computed independently of ordering)
are reported on `B_scenario_counts`; the KEY sheet states explicitly that these are different
quantities so the ordered column is not misread as S3's complete count.

### B-04: Direction must be reported separately

The notes say "another encounter" without specifying direction. `get_zip9_at_date()` currently
looks only backward. Report S1 and S2 split into backward-only, forward-only, and either, so
the team can see what allowing forward fill would recover.

## Part C — Cumulative completeness

### C-01: Waterfall, not a single number

> See where that gets us in terms of completeness

Report as a stepwise table: starting encounters with an observed ZIP9, then the incremental
gain from each rule applied in order, then the residual. Both encounter and patient level.

### C-02: Reconcile against the known control total

The notes state: *"Only 26 pts with no 5-digit ZIP code at any single point."*

The final row of the patient-level waterfall — patients with no usable ZIP5 anywhere in their
address history — should land at or near 26. **If it does not, stop and investigate before
delivering.** A materially higher number means the assumed prior ZIP5-coalesce fix (see
"Blocking question" numbering/precondition discrepancy) is not reaching the bare 5-digit
values, and every downstream count in this deliverable is wrong.

This is the single most useful validation in the phase; it is free, and it checks the fix that
everything else depends on.

**139-05-PATCH FIX-03 amendment:** "26" is a study-cohort count (the notes' own patient
population, not every patient in `LDS_ADDRESS_HISTORY`). The implemented reconciliation
(`compute_c02()`, R/115 SECTION 1B) is therefore computed over the study cohort's patient list
(`get_hl_patient_ids()`, the same cohort-definition pattern R/106/R/111/R/100/R/107/R/109 already
use), with cohort patients who have zero rows in `addr_coal` at all counting toward the "no
usable ZIP5" numerator rather than being invisible to a `group_by(ID)` that never sees them. A
pre-filter comparison (the same statistic computed against the unfiltered address data) is
reported alongside the post-filter figure so any gap the study-period/unparseable-date filters
introduce is visible rather than absorbed silently into the ±5 tolerance. That tolerance is
documented as covering cohort-definition drift only, not denominator or methodological
uncertainty, now that the denominator itself is cohort-scoped and correct.

</decisions>

<pitfalls>
## Pitfalls

1. **Address-history rows are not encounters.** LDS_ADDRESS_HISTORY stores dated intervals;
   encounters are a separate table. "How often does ZIP9 change" has a different answer in each
   universe. Part A is computed on address history (that is where change is observable); Part B
   and C are computed on encounters (that is where imputation is applied). State the universe in
   every table header, and never mix them in one figure.

2. **Sentinel and placeholder ZIPs inflate change counts.** `00000` / `99999` and repeated-digit
   values will register as transitions. Apply the `is_sentinel_zip5()` filter referenced in the
   assumed prior imputation-rules work before counting — **this function does not currently
   exist in `R/`** (see "Blocking question"); confirm where it lives or needs to be written
   before this pitfall can actually be guarded against. (Resolved: `is_sentinel_zip5()` is added
   to `R/utils/utils_address.R` by Plan 01 Task 1 of this phase.)

3. **Unparseable dates silently drop records.** `get_zip9_at_date()` filters
   `!is.na(period_start_dt)`. Records with bad dates cannot be ordered and therefore cannot
   contribute a transition. Count and report them rather than letting them vanish — a patient
   whose records are half undated will look artificially stable.

4. **Left and right censoring.** A patient's first observed ZIP is not necessarily their first
   address, and address history often ends before the last encounter. Do not report a "moves per
   year" rate without stating the observation window.

   **139-05-PATCH FIX-02 note:** the same right-censoring concern applies at the interval-match
   level, not only the rate level — an open-ended address record (`period_end_dt` NA, i.e. "this
   is the patient's current address") must be treated as covering every date up through the data
   extraction date for interval-matching purposes (`period_end_eff`, coalesced to a far-future
   sentinel), or every encounter covered by a patient's CURRENT address is misclassified as
   having no covering record at all — which is most recent encounters, not an edge case.

5. **Overlapping intervals.** Same-patient address records with overlapping periods exist in
   this data (the interval matcher in `get_zip9_at_date()` handles ties for exactly this
   reason). Ordering by period start alone can manufacture spurious transitions. Define the
   consecutive-record ordering explicitly and document how overlaps are resolved.

6. **Do not report a mean number of changes.** The distribution will be heavily zero-inflated
   and right-skewed. Report the full distribution, median, and the proportion with zero
   transitions.

</pitfalls>

<deliverable>
## Deliverable

One Excel workbook: `output/zip_stability_counts_YYYYMMDD.xlsx`

| Sheet | Contents |
|---|---|
| **KEY** | Leftmost tab. Definitions of every metric, universe (address history vs encounters), denominators, exclusions applied, source file name and date, script version |
| A_stability_patient | Per-patient metrics from A-01 through A-05 |
| A_stability_summary | Distributions, with the days-between-changes histogram |
| A_validation_curve | Carry-forward accuracy by gap bin (A-06) |
| B_scenario_counts | S1–S4 at encounter and patient level, ordered and unordered |
| B_direction_split | Backward / forward / either (B-04) |
| C_completeness | Stepwise waterfall, both levels |
| QC | Records dropped at each filter, sentinel counts, unparseable dates, the 26-patient reconciliation |

Charts use UF colors (`#0021A5`, `#FA4616`). Language in the KEY sheet and any narrative
summary should be measured and neutral — describe what was counted and under what definition,
without characterizing whether the resulting completeness is adequate. That is the team's call.

</deliverable>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/utils/utils_address.R` — `get_zip9_at_date()`, `normalize_zip9()`, `normalize_zip5()`,
  `normalize_zip5_raw()` (built in Phase 137, confirmed present). Use these; do not reimplement
  normalization.
- `R/106_zip_change_frequency.R` — partially covers Part A already. Determine what it produces
  and extend rather than duplicate; if its definitions conflict with A-01 through A-03,
  reconcile explicitly and note the difference in the KEY sheet.
- `R/utils/utils_treatment.R` — `get_hl_patient_ids()`, the established study-cohort definition
  pattern (used by R/106, R/107, R/109, R/100, R/111, R/20, R/22). Reused by this phase (Plans
  03/04) for Part B/C's cohort restriction and C-02's reconciliation population (139-05-PATCH
  FIX-03a) — confirmed present, do not invent a new cohort definition.

### Missing/Unverified (blocks parts of this phase — see "Blocking question")
- `approximate_zip9()` — referenced throughout Part B/C as the imputation function whose output
  this phase counts occurrences for. **Not found anywhere in `R/`**, on any branch, committed or
  uncommitted (re-confirmed 2026-08-05 during 139-05-PATCH.md application — see PRECOND-01
  re-confirmation above).
- `is_sentinel_zip5()` — referenced in Pitfall 2 as the sentinel-ZIP filter. **Not found
  anywhere in `R/`** prior to this phase; added by Plan 01 Task 1.
- AMEND-01 ZIP5-coalesce fix — referenced in C-02 as the precondition for the 26-patient
  reconciliation. **No matching directory, commit, or code found** anywhere, on any branch
  (re-confirmed 2026-08-05). Implemented locally in this phase instead, as a single
  `coalesce_zip5()` function in `R/115_zip_stability_counts.R` (Plan 01 SECTION 1B) — not inside
  `utils_address.R`, and not duplicated anywhere else in the script (139-05-PATCH revised
  verification requires exactly one coalescing implementation).

### Integration Points
- `R/115_zip_stability_counts.R` — new script, per the notes' deferred-from-Phase-139 framing
  (script numbering continues from `R/114_zip9_temporal_lookup.R`, Phase 137's deliverable).

</code_context>

<canonical_refs>
## Canonical References

- `R/106_zip_change_frequency.R` — **read first.** Partially covers Part A. Determine what it
  already produces and extend rather than duplicate; if its definitions conflict with A-01
  through A-03, reconcile explicitly and note the difference in the KEY sheet.
- `R/utils/utils_address.R` — `get_zip9_at_date()`, `normalize_zip9()`, `normalize_zip5()`,
  `normalize_zip5_raw()`. Use these; do not reimplement normalization. (`approximate_zip9()` is
  referenced in the source notes as living here too, but is not actually present — see
  "Blocking question" and `code_context` above.)
- `.planning/phases/139-zip9-approximation/` — **referenced by the source notes as already
  existing; it does not.** No CONTEXT/PLAN/patches found at this path or under any other phase
  number. Treat every claim below sourced from "AMEND-01" as unverified until the discrepancy
  in "Blocking question" is resolved. (Re-confirmed absent 2026-08-05 — see PRECOND-01
  re-confirmation above.)
- Team meeting notes, 08/04/2026 and 07/21–24/2026 — the requirement source.

</canonical_refs>

<open_items>
## Open items for the team

1. **ADI-for-all versus ADI/SDI split** — see Blocking question. This phase produces the counts
   that inform it; it does not resolve it.
2. **S3 resolution** — still pending as of 08/04. The source notes describe a prior phase having
   shipped into this space, but no such phase exists (see Blocking question) — the count from
   B-01 should inform S3's resolution once that precondition gap is closed. Report both the
   ordered "S3" count and the unordered "S3-eligible" count (139-05-PATCH FIX-04d) — they are
   different quantities and the team should resolve S3 against the complete ("S3-eligible")
   figure.
3. **Forward fill** — currently not implemented. B-04 quantifies what it would recover.
4. **Time window** — A-05 and A-06 produce the evidence; the team selects the value.
5. **Missing precondition phase** — `approximate_zip9()`, `is_sentinel_zip5()`, and the AMEND-01
   ZIP5-coalesce fix that this document assumes are prerequisites do not exist in the codebase.
   Needs resolution before/during planning: build them as part of this phase's scope, insert a
   phase before 139 to build them, or re-derive which of this document's decisions actually still
   hold without them. **Resolved for this phase's planning purposes:** re-confirmed absent
   2026-08-05 (see PRECOND-01 re-confirmation above); Plans 01–04 build `is_sentinel_zip5()` and
   the ZIP5-coalescing logic locally, as this phase's own scope, rather than assuming them as a
   precondition.

</open_items>

<deferred>
## Deferred Ideas

None beyond what's already captured in "Out of scope" and "Open items" above — discussion
adopted the source document as-is rather than exploring new gray areas.

</deferred>

---

*Phase: 139-zip-stability-imputation-occurrence-counts*
*Context gathered: 2026-08-05*
*Amended by 139-05-PATCH.md: 2026-08-05*
