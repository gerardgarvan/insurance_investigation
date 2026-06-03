# Phase 80: Smoke Test Updates - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Update R/88_smoke_test_comprehensive.R to validate all v2.1 changes from Phases 75-79. Add static analysis checks for Phase 79 scripts (R/54, R/55, R/56), expand decade validation lists to include all new scripts (R/35, R/54-56, R/76), fix inconsistent section numbering, and update the validated requirements summary. No new pipeline functionality — structural smoke test additions only.

</domain>

<decisions>
## Implementation Decisions

### Validation Depth for Phase 79 Scripts
- **D-01:** Static analysis for R/54 (SCT 0362 investigation), R/55 (replaced-by verification), and R/56 (new drug grouping tables) — ~5-8 checks per script matching the existing depth used for R/26, R/35, R/49, R/52 sections.
- **D-02:** Check patterns include: source() dependencies, key column references, output file patterns (xlsx), script-specific logic (e.g., igraph usage in R/55, sheet structure in R/56), and documentation headers.

### Structural Cleanup
- **D-03:** Renumber ALL section progress labels [N/M] to reflect actual total section count. Current labels are inconsistent — sections 13-13D use [18/22]-[21/22], then sections 14-16 use [14/16]-[15/16]. After adding Phase 79 sections, all labels must be sequential and accurate.
- **D-04:** Clean sequential numbering from Section 1 through the final section. The summary line "ALL N CHECKS PASSED" will reflect the true total.

### Decade List Updates
- **D-05:** Expand cancer decade validation from 14 scripts (40-53) to include R/54, R/55, R/56 — 17 scripts total (40-56). Update the section label and expected count.
- **D-06:** Expand output decade validation from 6 scripts (70-75) to include R/76 — 7 scripts total (70-76). Update the section label and expected count.
- **D-07:** Add decade coverage for R/35 in the 30s range. Either widen an existing decade or add a new "Quality/Investigations (30-39)" decade with R/35. Claude's discretion on the cleanest boundary.

### Summary Section Updates
- **D-08:** Add CODE-01, CODE-02, TREAT-03 to the "Validated requirements" list at end of R/88.
- **D-09:** Update the version banner text if needed to reflect v2.1 completeness.

### Claude's Discretion
- Internal organization of new check sections (group by script vs group by requirement)
- Exact set of static analysis patterns to check per Phase 79 script (within the ~5-8 checks guideline)
- Whether R/35 gets its own decade group or merges into an adjacent one
- Specific check descriptions and glue() message formatting

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary File (being modified)
- `R/88_smoke_test_comprehensive.R` -- Comprehensive smoke test. 1039 lines, 16 sections. Must read entirely to understand existing patterns, section numbering, and check() function usage.

### Phase 79 Scripts (being validated)
- `R/54_investigate_sct_0362.R` -- SCT code 0362 encounter-level investigation. Check for: xlsx output, TREATMENT_CODES reference, encounter detail extraction.
- `R/55_verify_replaced_by_codes.R` -- Replaced-by code verification with cycle detection. Check for: igraph usage, xlsx output, DRUG_GROUPINGS or TREATMENT_CODES cross-reference.
- `R/56_new_tables_from_groupings.R` -- Two drug grouping summary tables. Check for: 2-sheet xlsx output, DRUG_GROUPINGS reference, treatment_episodes.rds input.

### Other v2.1 Scripts (decade list additions)
- `R/35_death_cause_quality.R` -- Death cause quality profiling. Already validated by dedicated section but not in any decade list.
- `R/76_treatment_source_coverage.R` -- Treatment source coverage analysis. Already validated by dedicated section but not in output decade list.

### Prior Phase Context
- `.planning/phases/74-smoke-testing-reference-manual/74-CONTEXT.md` -- Original smoke test decisions (D-01 through D-11). Testing framework, coverage approach, cross-platform strategy.
- `.planning/phases/79-code-investigations-new-tables/79-CONTEXT.md` -- Phase 79 script decisions (D-01 through D-17). Script numbering, output formats, validation approach.

### Requirements
- `.planning/REQUIREMENTS.md` -- QUAL-01 (v2.0 standards for all modified scripts), CODE-01, CODE-02, TREAT-03

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `check(description, condition)` function in R/88 — all new checks use this pattern
- `check_source(file, pattern, description)` helper — validates source() dependencies by reading file content
- Static analysis pattern: `readLines()` + `grepl()` for checking code patterns without execution
- `glue()` for interpolated check descriptions with dynamic counts

### Established Patterns
- Each v2.1 section follows: read script lines, run 5-10 `check()` calls, verify patterns/columns/outputs
- Phase-tagged sections: `# Phase XX (REQ-YY): description` in section headers
- Data-dependent checks gated behind `DATA_AVAILABLE` flag
- Progress labels: `message("\n[N/M] Section description...")`

### Integration Points
- New sections add after Section 15 (episode enrichment), before Section 16 (summary)
- Cancer decade list (Section 6) needs R/54, R/55, R/56 appended
- Output decade list (Section 8) needs R/76 appended
- Summary section (Section 16) needs CODE-01, CODE-02, TREAT-03 added to requirements list
- All [N/M] progress labels throughout the file must be renumbered

</code_context>

<specifics>
## Specific Ideas

- Roadmap success criteria reference "R/92, R/93" as new scripts but those are pre-existing ad-hoc scripts. The actual new Phase 79 scripts are R/54, R/55, R/56. Plan should validate R/54-56, not R/92-93.
- Section numbering inconsistency is between the original 22-section scheme and the Phase 78 additions that used a [14/16] scheme — both need unification.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 80-smoke-test-updates*
*Context gathered: 2026-06-03*
