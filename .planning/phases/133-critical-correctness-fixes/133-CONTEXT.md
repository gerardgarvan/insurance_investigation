# Phase 133: Critical Correctness Fixes - Context

**Gathered:** 2026-07-25
**Status:** Ready for planning

<domain>
## Phase Boundary

8 targeted bug fixes across 6 R scripts. The pipeline's published numbers and generated reference manual must be correct — no analytic output silently wrong or inert. All fixes are precisely specified in the ROADMAP design constraints; no new capabilities are added.

Scripts in scope: R/28, R/46, R/47, R/48, R/49, R/67, R/68, R/89, R/95, R/96, R/101.

</domain>

<decisions>
## Implementation Decisions

### Plan Decomposition
- **D-01:** All 8 fixes delivered in **1 omnibus plan**. Fixes are independent so rollback risk is low; the phase is already atomic by design.

### R/28 — SCT treatment_type string
- **D-02:** Change the `sct_dates` filter from `treatment_type == "Stem Cell Transplant"` to `treatment_type == "SCT"` to match the value used everywhere else in the pipeline. This is the only change in R/28.

### R/46 — total_records aggregation
- **D-03:** Fix the aggregation path only (minimal change). Aggregate `dx_record_counts` by category/code directly before the join, so `total_records` reflects true code-level record counts. Leave the rest of R/46's structure (summary rows, TOTAL row) as-is — they derive correctly once the upstream sum is fixed. Do **not** refactor beyond the stated bug.

### R/47 — first_hl_dx_date sentinel
- **D-04:** Define `SENTINEL_CUTOFF <- as.Date("1910-01-01")` inline at the top of R/47, matching the identical pattern already in R/48 and R/49. Do **not** centralize to R/00_config.R — that's a broader change outside this phase's scope.
- **D-05:** Replace the post-hoc `year(first_hl_dx_date) == 1900L` nullify with a pre-`min()` filter: `filter(is.na(DX_DATE) | DX_DATE >= SENTINEL_CUTOFF)` on the raw DIAGNOSIS table before computing `first_hl_dx_date`. Remove the post-hoc nullify block.

### R/48 — HL anchor code exclusion
- **D-06:** Exclude HL anchor codes (C81* and 201.x) from R/48's post-HL "second cancer" set, matching R/49's existing exclusion. R/48 inherits the corrected anchor date from the fixed R/47.

### R/49 — both_count patient intersection
- **D-07:** Fix `both_count` to reflect the true pre∩post **patient** intersection at category grain (not a per-code sum), so `pre + post − both` reconciles correctly.

### R/67/68 + R/95/96 — pmin/pmax date-source binding
- **D-08:** Minimal surgery approach — in the `pmin`/`pmax` reordering block in each of R/67, R/68, R/95, R/96: when `source_1`/`source_2` are swapped, also swap `admit_date_1`/`admit_date_2` as a bound unit in the same `mutate()`. Do **not** restructure to tuple-based representation.
- **D-09:** R/95 and R/96 receive the **identical swap fix** as R/67/R/68 (same pattern) — they are the AV+TH analogues and share the same structural issue.

### R/89 — parse_script_header() header_end anchor
- **D-10:** Change `header_end` to anchor on the **3rd** `===` bar (closing bar of the field block), not the 2nd. This is the first non-comment line boundary that correctly captures Purpose/Inputs/Outputs/Dependencies/Requirements text.

### R/101 — age_at_episode computation order
- **D-11:** Compute `age_at_episode` **before** `episode_start` is reassigned to `min()` in the `summarize()` call, or index it against the pre-collapsed `episode_start` values. The current bug: `age_at_episode[which.min(episode_start)]` is evaluated after `episode_start = min(episode_start)` makes `episode_start` a scalar, so `which.min()` always returns 1.

### Claude's Discretion
- Ordering of the 8 fixes within the plan (suggest: R/47 → R/28 → R/46 → R/48 → R/49 → R/67/68 → R/95/96 → R/89 → R/101, dependency-first)
- Exact dplyr idiom for the R/49 patient-intersection fix (use `n_distinct()` on patient IDs in the overlap set, not `sum()` of per-code counts)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Specification
- `.planning/ROADMAP.md` §"Phase 133: Critical Correctness Fixes" — design constraints and success criteria (the authoritative spec for all 8 fixes)

### Scripts Under Fix
- `R/28_episode_classification.R` — R/28 fix (SCT string, line ~647)
- `R/46_cancer_summary_table.R` — R/46 fix (total_records aggregation)
- `R/47_cancer_summary_refined.R` — R/47 fix (sentinel filter before min)
- `R/48_cancer_summary_post_hl.R` — R/48 fix (HL anchor exclusion); reference for SENTINEL_CUTOFF pattern
- `R/49_cancer_summary_pre_post.R` — R/49 fix (both_count patient intersection)
- `R/67_multi_source_overlap_detection.R` — R/67 fix (pmin/pmax swap)
- `R/68_overlap_classification.R` — R/68 fix (pmin/pmax swap)
- `R/89_generate_reference_manual.R` — R/89 fix (parse_script_header header_end)
- `R/95_multi_source_overlap_av_th.R` — R/95 fix (same pmin/pmax swap as R/67)
- `R/96_overlap_classification_av_th.R` — R/96 fix (same pmin/pmax swap as R/68)
- `R/101_gantt_lifespan_collapse.R` — R/101 fix (age_at_episode order in summarize)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SENTINEL_CUTOFF <- as.Date("1910-01-01")`: already defined identically in R/48 (line 62) and R/49 (line 63) — copy this pattern verbatim into R/47
- `pmin`/`pmax` swap block: R/67 lines ~275-279 are the reference pattern; R/95 has an identical structure

### Established Patterns
- R/28 uses `treatment_type == "Stem Cell Transplant"` at line ~647 — the rest of the pipeline uses `"SCT"` exclusively
- R/46 joins `dx_record_counts` at patient grain before summing, inflating by patient count per code
- R/47 current nullify: `mutate(first_hl_dx_date = if_else(year(first_hl_dx_date) == 1900L, as.Date(NA), ...))` — this must be replaced, not supplemented
- R/101 `summarize()` order issue: `episode_start = min(episode_start)` at line ~200 precedes `age_at_episode = age_at_episode[which.min(episode_start)]` at line ~226 inside the same `summarize()` call

### Integration Points
- R/48 and R/49 both `source()` from R/47's output (`confirmed_hl_cohort.rds`) — fixing R/47 propagates correct anchor dates to both downstream scripts without additional changes to their ingest logic
- R/68 and R/96 downstream ENCOUNTER joins depend on `(ID, admit_date, source)` tuples being correctly bound — the swap fix in R/67/R/95 must be verified to survive the join in R/68/R/96

</code_context>

<specifics>
## Specific Ideas

- No specific references beyond ROADMAP design constraints.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 133-critical-correctness-fixes*
*Context gathered: 2026-07-25*
