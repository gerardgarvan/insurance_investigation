# Phase 93: Cross-Use Flag Implementation - Context

**Gathered:** 2026-06-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Add temporal context logic for SCT conditioning and a confidence column for questionable immunotherapy codes. Two new columns: `is_sct_conditioning_context` (boolean annotation on chemotherapy episodes within 30 days before SCT) and `immuno_confidence` (flagging 11 questionable codes as vitamin combos or CAR-T ambiguity). These are annotations alongside existing treatment_type — no reclassification.

</domain>

<decisions>
## Implementation Decisions

### SCT Conditioning Temporal Context
- **D-01:** 30-day window hardcoded (not configurable). Chemotherapy episodes with any triggering code occurring within 30 days before an SCT episode start date get `is_sct_conditioning_context = TRUE`.
- **D-02:** Applies to chemotherapy episodes only. Immunotherapy near SCT is NOT flagged as conditioning.
- **D-03:** Output format: boolean `is_sct_conditioning_context` (TRUE/FALSE) in Gantt CSVs; additionally `days_to_nearest_sct` integer column in treatment_episodes.rds only (not exported to CSVs). This gives analysts re-thresholding flexibility from the RDS without complicating the export schema.
- **D-04:** NA for non-chemotherapy episodes in both columns.

### Questionable Code Identification
- **D-05:** Hardcoded named vector `QUESTIONABLE_IMMUNO_CODES` in R/00_config.R mapping code to reason string. Explicit and auditable.
- **D-06:** 8 multivitamin codes flagged as "questionable-vitamin": 891815, 891790, 1090823, 1313925, 1248142, 891716, 1090824, 891793.
- **D-07:** 3 CAR-T codes flagged as "questionable-CAR-T vs immunotherapy": 2479140 (Lisocabtagene Maraleucel RxNorm), XW033C3, XW043C3 (ICD-10-PCS procedure codes).
- **D-08:** Total: 11 questionable codes (8 vitamin + 3 CAR-T), not 10 as originally estimated.

### Confidence Column Design
- **D-09:** New standalone column `immuno_confidence` — separate from existing `sct_cross_use_flag`. Clean separation of concerns.
- **D-10:** Column values: NA (not questionable), "questionable-vitamin" (IMMU-02), "questionable-CAR-T vs immunotherapy" (IMMU-02).
- **D-11:** New column added to Gantt v2 exports. Episodes schema goes from 21 to 22 columns. Detail schema goes from 19 to 20 columns. V1 exports unchanged.
- **D-12:** Episode aggregation: any-questionable propagates. If ANY triggering code in the episode is questionable, the episode gets the flag. Matches existing sct_cross_use_flag aggregation pattern (Phase 91 D-09).

### Aggregation Rules
- **D-13:** `is_sct_conditioning_context` is an annotation only — treatment_type stays "Chemotherapy". No reclassification to "SCT Conditioning". Preserves mutual exclusivity of treatment_type.
- **D-14:** Aggregation rules documented as inline comments in R/28 and R/52. No separate markdown document.
- **D-15:** Smoke test performs full cross-tab validation: treatment_type sum check (each episode has exactly one category) PLUS cross-tab of is_sct_conditioning_context vs treatment_type confirming the flag only appears on Chemotherapy episodes.

### Claude's Discretion
- Exact placement of new columns in R/28 episode enrichment pipeline (after existing Phase 91 enrichment step)
- Smoke test section numbering (follow existing convention)
- Comment wording for aggregation rule documentation
- `days_to_nearest_sct` computation details (nearest SCT episode start date per patient, looking forward only)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Episode Classification (Primary Modification Target)
- `R/28_episode_classification.R` — Episode enrichment pipeline. Phase 91 added 5 xlsx metadata columns. Phase 93 adds is_sct_conditioning_context, days_to_nearest_sct, and immuno_confidence here.
- `R/28_episode_classification.R` lines 542-580 — `aggregate_cross_use_flag()` function and Phase 91 enrichment step. Pattern to follow for new aggregations.

### Gantt Export (Schema Extension)
- `R/52_gantt_v2_export.R` — Gantt v2 CSV export. Phase 92 added 5 metadata columns. Phase 93 adds is_sct_conditioning_context and immuno_confidence (22/20 column schemas).
- `R/52_gantt_v2_export.R` lines 210-219 — Defensive column fallback pattern for missing columns.

### Configuration (New Lookup)
- `R/00_config.R` lines 2158-2170 — Immunotherapy RxNorm codes with drug names. Contains the 8 multivitamin and 1 CAR-T (2479140) codes.
- `R/00_config.R` lines 2739-2770 — CAR T-cell ICD-10-PCS codes including XW033C3 and XW043C3.

### XLSX Lookups (Cross-Use Flag Source)
- `R/utils/utils_xlsx_lookups.R` — load_xlsx_lookups() already parses cross_use_flags from xlsx column 9. May need extension for immuno_confidence if not already captured.

### Smoke Test
- `R/88_smoke_test_comprehensive.R` lines 1375-1435 — Section 15d/15e (Phase 91/92 validation). Phase 93 adds new section for conditioning context and confidence validation.

### Requirements
- `.planning/REQUIREMENTS.md` — IMMU-01 (confidence column), IMMU-02 (flag value distinction)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `aggregate_cross_use_flag()` in R/28 line 544: Pattern for episode-level flag aggregation from comma-separated triggering codes. Reuse for immuno_confidence aggregation.
- `aggregate_treatment_line()` in R/28: F>S>E>N priority aggregation. Pattern for most-specific-wins logic.
- `DRUG_GROUPINGS` named vector in R/00_config.R: Existing pattern for code-to-category mapping. QUESTIONABLE_IMMUNO_CODES follows same structure.
- `check()` function in R/88: Smoke test assertion helper.
- Defensive column fallback in R/52 lines 210-219: Pattern for gracefully handling missing columns.

### Established Patterns
- Episode enrichment happens in R/28 Section 5C (Phase 91 xlsx metadata enrichment)
- Named vector lookup via `sapply()` over triggering_codes (comma-separated)
- Smoke test sections use `# SECTION N: NAME ----` headers with `message()` progress
- Gantt schema changes append columns at end (non-breaking)

### Integration Points
- R/28 is the enrichment point — add temporal context and confidence computation after Phase 91's xlsx enrichment
- treatment_episodes.rds is the RDS output (gains days_to_nearest_sct, is_sct_conditioning_context, immuno_confidence)
- R/52 Gantt export gains 2 new columns: is_sct_conditioning_context and immuno_confidence (not days_to_nearest_sct)
- R/88 smoke test gains new section for Phase 93 validation
- Column count constants in R/52 need updating (22 episodes, 20 detail)

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches following existing patterns.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 93-cross-use-flag-implementation*
*Context gathered: 2026-06-08*
