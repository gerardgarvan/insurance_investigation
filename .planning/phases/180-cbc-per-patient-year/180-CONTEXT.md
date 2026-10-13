# Phase 180: CBC per Patient-Year — Context (Seed)

**Gathered:** 2026-10-13
**Status:** Seed decisions captured — Phase not yet in ROADMAP.md. Run `/gsd:plan-phase 180` after adding to roadmap.

<domain>
## Phase Boundary

[To be defined when phase is added to roadmap. Working name: "CBC per patient-year (CBCY) association analysis."]

</domain>

<decisions>
## Implementation Decisions

### CBCY-04 — Exposure definition
- **CBCY-04a (primary exposure):** Patient-level **median of per-encounter `distance_mi`** from R/122 `enc_distance`, restricted to `distance_status == "computed"` post-anchor encounters. One value per patient; applied uniformly to all of that patient's patient-years.
  - Far = median > `CONFIG$far_from_care_cutoff_mi` (100 mi).
  - Source: R/122 RDS (`enc_distance` tibble, same as Phase 165/179).
  - Window: post-anchor encounters only (`ADMIT_DATE > hl_anchor_date`).
  - Patients with **no computed-distance post-anchor encounter** → exposure **missing** (excluded from primary analysis; handled in Phase 180, not Phase 179).

- **CBCY-04b (sensitivity exposure):** Per-year median over that calendar year's computed post-anchor encounters. Patient-years with zero computed encounters in that year are **excluded from the sensitivity only** (not from the primary). Report how many patient-years drop out under this definition vs CBCY-04a.

### Claude's Discretion
- Definition of "patient-year" (calendar year vs anchor-relative year vs observation year) — to be decided during Phase 180 discussion.
- Outcome definition for the CBCY analysis — carry forward Phase 165's `build_cbc_events()` / `build_pat_analysis()` conventions unless changed by Amy/Erin via D-165-01.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `R/utils/utils_distance_cbc.R` — `build_cbc_events()`, `build_enc_analysis()`, `build_pat_analysis()`; exposure and outcome building blocks
- `R/00_config.R` — `CONFIG$far_from_care_cutoff_mi` (100 mi cutoff)
- `.planning/phases/179-missing-distance-bias-check/179-CONTEXT.md` — Phase 179 exposure/outcome decisions (CBCY-04 inherits distance_status and anchor-day conventions from there)
- `.planning/phases/165-distance-100mi-indicator-and-cbc-association/165-CONTEXT.md` — D-165-01, anchor-day convention, CBC LOINC set

</canonical_refs>

<deferred>
## Deferred / Open

- CBCY-01 through CBCY-03 definitions (not yet provided — capture when given).
- "Patient-year" operationalization — calendar year, anchor-relative year, or observation year.
- How to handle patients missing exposure (no computed post-anchor encounter): exclusion rule confirmed as Phase 180's responsibility.

</deferred>

---

*Phase: 180-cbc-per-patient-year*
*Seed decisions captured: 2026-10-13*
