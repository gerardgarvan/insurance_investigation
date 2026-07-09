# Phase 117: Lifespan Gantt (Collapsed Across Time) - Context

**Gathered:** 2026-07-09
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase produces a **new "lifespan" Gantt CSV** that collapses the treatment-episode
data across time. "Collapse across all time" does NOT mean normalizing to a relative time
axis — it means **combining every episode of the same treatment type into a single bar per
patient**, spanning that patient's earliest to latest treatment date for that type.

The output is a new CSV for Tableau (same convention as the existing `gantt_episodes.csv` /
`gantt_detail.csv`), NOT a rendered chart image. This project exports CSVs and builds the
actual visuals in Tableau — no in-R chart rendering is introduced here.

**What it delivers:** one row per `patient_id` × `treatment_type`, with the bar spanning
`min(episode_start)` → `max(episode_stop)` across all of that patient's episodes of that
type. Multi-value metadata is unioned/deduped into semicolon lists within each collapsed bar.

</domain>

<decisions>
## Implementation Decisions

### Output Artifact
- **D-01:** Output is a **new CSV for Tableau** (suggested name `gantt_lifespan.csv` — final name is Claude's discretion). No rendered chart/image. No in-R ggplot rendering.
- **D-02:** Follows the existing Gantt CSV convention (Phase 99 style): empty strings instead of NA, semicolon-separated multi-value fields, direct-Tableau-import friendly.

### Collapse Semantics ("collapse across all time")
- **D-03:** Collapse = **combine all episodes of the same treatment type per patient into one row**. It is NOT a relative/normalized time axis — calendar dates are preserved.
- **D-04:** Collapse grain: **one row per `patient_id` × `treatment_type`**.
- **D-05:** Collapsed bar span = **`episode_start` = min(episode_start)** and **`episode_stop` = max(episode_stop)** across the combined episodes (earliest start → latest stop).

### Collapse Key / Dimensions Kept Separate
- **D-06:** The ONLY grouping dimension besides patient is `treatment_type`. Nothing else (cancer_category, is_hodgkin, 7-day confirmed status) becomes part of the key — those stay as merged multi-value attributes within the single bar.
- **D-07:** Multi-value fields are **unioned, deduped, and sorted** into semicolon lists within each collapsed bar — reuse R/52's `clean_multi_value()` behavior (sort(unique()), drop blanks, semicolon separator). Applies to: cancer_category, drug_names, triggering_codes, triggering_code_descriptions, drug_group, code_type, source_table, episode_dx_codes, episode_dx_categories, episode_dx_7day_confirmed.

### Scope
- **D-08:** **Real treatment types only.** Exclude the Death and HL Diagnosis pseudo-treatment rows (`treatment_type %in% c("Death", "HL Diagnosis")`) from the collapsed output. Only Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, etc. get collapsed bars.

### Claude's Discretion
- Final output file name (suggested `gantt_lifespan.csv`).
- Which script hosts this: a new numbered/post-renumber script (e.g. `R/101_*` in the 100+ investigations block) vs an added section in `R/52`. Leaning toward a new standalone script that reads the existing `gantt_episodes.csv` (or `treatment_episodes.rds`) so the base Gantt export is untouched.
- Source input: collapse from the already-built `output/gantt_episodes.csv` (simplest, inherits all enrichments) vs from `cache/outputs/treatment_episodes.rds`. Reading the finished `gantt_episodes.csv` is preferred so no enrichment logic is duplicated.
- How to aggregate the numeric/boolean helper columns for the collapsed row:
  - `episode_length_days` → span in days = max(episode_stop) − min(episode_start) (Claude's discretion whether span vs total active days; span matches "earliest to latest").
  - `distinct_dates_in_episode` → sum or distinct-date count across episodes.
  - `is_hodgkin` → any(is_hodgkin) across combined episodes (or re-derive from unioned cancer_category, consistent with R/52 D-07).
  - `age_at_episode` → age at the earliest episode_start.
  - `episode_number` → collapses away; optionally replaced by an episode count.
- Whether to register the new script in `R/39_run_all_investigations.R` and add an `R/88` smoke-test section (follow the Phase 116 precedent — likely yes).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Gantt Export Pipeline (primary source of the data being collapsed)
- `R/52_gantt_v2_export.R` — Current Gantt export. Defines `EPISODES_SCHEMA` (20 cols), `clean_multi_value()` (lines ~772-786), pseudo-row construction for Death (Section 4B) and HL Diagnosis (Section 4C), and the per-episode grain being collapsed.
- `output/gantt_episodes.csv` — The 20-column episode-level output that this phase collapses (preferred input).

### Episode Data (alternate upstream source)
- `R/26_treatment_episodes.R` — Per-episode start/stop construction; `sort(unique())` multi-value aggregation pattern.
- `R/28_episode_classification.R` — Episode enrichment (cancer linkage, episode_dx_* columns from Phase 112).
- `cache/outputs/treatment_episodes.rds` — Enriched episode RDS (alternate input if not reading the CSV).

### Conventions & Precedent
- `R/SCRIPT_INDEX.md` — "Post-Renumber Investigations (100+)" section; where a new standalone script would be documented.
- `R/39_run_all_investigations.R` — Pipeline runner; Phase 116 registered R/100 here.
- `R/88_smoke_test_comprehensive.R` — Structural smoke test; Phase 116 added a section (15m) for its new script — follow that precedent.
- `R/100_ruca_rurality_summary.R` — Recent precedent for a standalone post-renumber investigation script (Phase 116).

### Prior Gantt Phase Context
- `.planning/phases/115-*/115-CONTEXT.md` — Most recent Gantt-data phase (7-day confirmed + age_at_episode columns).
- `.planning/phases/112-*/112-CONTEXT.md` — episode_dx_categories design + alphabetical sort rule for multi-value fields.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `clean_multi_value()` (R/52 lines ~772-786): sort(unique()), drop blanks, semicolon separator — exactly the union/dedup behavior needed for collapsing multi-value fields.
- `output/gantt_episodes.csv`: already carries all enrichments (cancer_category, drug_names, drug_group, code_type, source_table, episode_dx_*, is_hodgkin, age_at_episode). Collapsing from it avoids re-deriving anything.
- `build_output_path()` / `CONFIG$output_dir` (R/00_config, utils_snapshot): standard output path helpers.

### Established Patterns
- CSV-for-Tableau export style (Phase 64/99): empty strings not NA, semicolon multi-value fields.
- Standalone "100+" investigation script pattern (R/100, Phase 116): self-contained, sourced 00_config, registered in R/39, smoke-tested in R/88.
- Universal ascending alphabetical sort on multi-value lists (Phase 112 rule).

### Integration Points
- New script reads `output/gantt_episodes.csv` (or treatment_episodes.rds), filters out Death/HL Diagnosis, groups by patient_id + treatment_type, writes `output/gantt_lifespan.csv`.
- Optional: register in `R/39_run_all_investigations.R` and add an `R/88` smoke-test section (Phase 116 precedent).
- Base Gantt export (R/52) stays untouched — this is purely additive/downstream.

</code_context>

<specifics>
## Specific Ideas

- "Lifespan" = each patient's full observed span of a treatment type on one bar, so a Tableau Gantt shows, per patient, one bar per treatment type from first to last date — the whole life of that treatment, rather than many small episode bars.
- Because dates are preserved (not normalized), the resulting Tableau chart is still a real-calendar swimlane; the "collapse" reduces episode clutter to one bar per treatment type per patient.

</specifics>

<deferred>
## Deferred Ideas

- Relative/normalized time axis (align patients to diagnosis date, age, or first-treatment t=0) — explicitly NOT this phase; "collapse" was clarified to mean merging episodes, not rescaling time. Could be a future phase if an overlay/aligned view is wanted.
- Rendering the Gantt as an R image (ggplot PNG/PDF) — out of scope; project builds visuals in Tableau.
- Keeping cancer_category / is_hodgkin / 7-day-confirmed as separate collapse dimensions — considered and declined (treatment_type only).

</deferred>

---

*Phase: 117-make-a-lifespan-gannt-that-collapses-across-all-time-but-still-keeps-treatment-type-etc-sepearate*
*Context gathered: 2026-07-09*
