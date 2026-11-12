---
phase: 198
name: ndc-crosswalk-obsolete-ndc-fallback
status: planned
milestone: cross-milestone
depends_on: [Phase 197 HiPerGator verification complete]
tags: [ndc, rxnav, chemo, r108, obsolete-ndc]
created: 2026-11-12
---

# Phase 198 Context — NDC Crosswalk: Obsolete-NDC Fallback

## Goal

Apply the `ndcstatus.json?ndc=` second-pass query to R/108 for NDCs that return
OBSOLETE status on the first pass, reusing the cache already built by R/109 D-09.
Propagate any new chemo matches downstream through the full chain, then get SME
confirmation on the intended scope of `chemo_rxnorm` before marking complete.

## Background

R/109 D-09 (commit b82c86b) added an OBSOLETE-NDC re-query to R/109's MED_ADMIN
and DISPENSING matching. On the 2026-11-12 HiPerGator run:

- 7,739 unmatched NDCs queried
- 6,802 recovered (mostly OBSOLETE)
- 25 matched `chemo_rxnorm` → 629 pt-dates, 302 NEW, 2 NEW patients, 12 earlier first-chemo dates
- Cache: `CONFIG$cache$outputs_dir/rxnav_ndc_requery_cache.rds`

R/108 (`108_ndc_crosswalk.R`) performs the initial NDC-to-RxNorm crosswalk used
by all downstream chemo detection. It currently discards OBSOLETE-status NDCs.
Adding the same `ndcstatus.json?ndc=` fallback to R/108 would recover these
matches earlier in the pipeline, allowing R/10, R/11, R/25, R/26, R/28, R/53,
and R/29 to benefit without requiring per-script patches.

## Expected Impact

Small. The R/109 patch already captured the incremental yield for delivered
outputs. The R/108 fix makes the pipeline internally consistent so OBSOLETE-NDC
recovery is not scattered across individual scripts.

Rough bounds from R/109 D-09 run (upper bound for R/108 fix):
- ≤ 302 NEW chemo dates
- ≤ 2 NEW chemo patients
- ≤ 12 patients with earlier first-chemo date

## Downstream Rerun Chain

R/108 is early in the pipeline. After any change to its output, rerun in order:

```
R/108  →  R/10  →  R/11  →  R/25  →  R/26  →  R/28  →  R/53  →  R/29  →  consumers
```

- **R/53** must run before **R/29** (provides `validated_death_dates.rds`; enforced by Phase 197-01).
- **R/29** writes the canonical `treatment_episodes.rds`.
- Consumers: R/39 chain (R/107, R/109, R/110, R/142, R/100, R/165, R/181, R/183, R/186–R/189, etc.).

## Cache Reuse

R/109's `rxnav_ndc_requery_cache.rds` stores `{ndc → list(status, rxcui, name)}`
for 7,739 NDCs. R/108 should load this cache as a lookup table before hitting the
RxNav API, so only NDCs absent from the cache require a live query.

Pin: `R108_OBSOLETE_NDC_CACHE` env var → default path `CONFIG$cache$outputs_dir/rxnav_ndc_requery_cache.rds`.

## SME Item — chemo_rxnorm Scope (OPEN)

`chemo_rxnorm` currently includes:

- **Oral methotrexate 2.5 mg tablets** (RxCUI: check cache) — commonly non-oncologic
  (rheumatoid arthritis, psoriasis); may inflate chemo-patient counts in an HL cohort.
- **Gemcitabine** — used in HL salvage (GVD) but also for lung/pancreatic cancer.
- **Carboplatin** — salvage regimens; also used in non-HL malignancies.
- **Etoposide** — BEACOPP, EPOCH; also broad use.
- **Bendamustine** — R-CHOP alternative; also NHL/CLL.

**Decision needed from SME (Amy/Erin/Sharon):** Are all five of these intended
inclusions for the HL cohort? If oral methotrexate 2.5 mg should be excluded,
remove its RxCUI from `chemo_rxnorm` before the R/108 re-query so recovered
OBSOLETE matches for methotrexate don't enter the pipeline.

This decision gates Phase 198 plan execution.

## Implementation Notes

- R/108 currently calls `rxnav_ndc_lookup()` (or equivalent) for each NDC.
  Add a post-pass: for any NDC whose status is `"OBSOLETE"`, query
  `ndcstatus.json?ndc=<ndc>` and attempt to map via the `ndcHistory` → current
  `rxcui` chain (same logic as R/109 D-09).
- Reuse R/109's helper verbatim (cite `R/109:line`); do not duplicate the HTTP
  retry logic.
- Guard: if `rxnav_ndc_requery_cache.rds` exists and is newer than `R/108`'s
  input NDC list, load and filter rather than re-querying.
- KEY sheet row: `R108_OBSOLETE_NDC_CACHE`, `pinned = TRUE/FALSE`, path, nrow of
  cache loaded.

## Success Criteria

1. R/108 output RDS gains `ndc_obsolete_recovered` logical column (`TRUE` for
   NDCs resolved via second-pass query).
2. `dep_map` shows no new duplicate writers after the chain rerun.
3. `treatment_episodes.rds` row count changes are within expected bounds (≤ 2
   new patients, ≤ 302 new pt-dates).
4. SME has confirmed (or restricted) `chemo_rxnorm` scope before plan execution.
5. KEY/QC sheet records before/after counts at R/108, R/29, and each intermediate.
