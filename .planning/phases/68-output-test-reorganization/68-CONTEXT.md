# Phase 68: Output & Test Reorganization (Repurposed: Verification Gate) - Context

**Gathered:** 2026-06-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 68 is repurposed as a **verification gate**. Original scope (output/test/ad-hoc renumbering) was absorbed by Phase 66 during expanded comprehensive renumbering. Phase 67 handled remaining cleanup (archive, smoke test relocation, SCRIPT_INDEX regeneration).

This phase verifies that REORG-04 and REORG-05 requirements are satisfied, scans for remaining loose ends, updates documentation to reflect the repurposed scope, and formally closes the reorganization work stream.

</domain>

<decisions>
## Implementation Decisions

### Verification Method
- **D-01:** Run structural checks locally on Windows (file existence, source() parsing, sequential numbering validation — the parts of R/87 that don't require data)
- **D-02:** Create a HiPerGator verification checklist documenting what must be run on-cluster for full REORG-05 validation (data-dependent checks)
- **D-03:** Phase 68 does NOT require a successful HiPerGator run to close — the checklist is the deliverable for deferred execution

### Scope of Done
- **D-04:** Scan for additional scripts that may need archiving (beyond the 8 already in R/archive/)
- **D-05:** Verify R/87 smoke test coverage against REORG-05 criteria (sequential numbering, source() resolution, RDS dependency checks)
- **D-06:** Check for orphan output files that don't correspond to any active script
- **D-07:** If scan reveals gaps: create follow-up items (don't block Phase 68 completion for minor issues)
- **D-08:** If scan confirms current state is clean: mark REORG-04 and REORG-05 complete

### Claude's Discretion
- **Documentation updates:** Rewrite ROADMAP Phase 68 description/success criteria to reflect repurposed verification scope (current criteria reference absorbed original scope). Update REQUIREMENTS.md traceability. Update STATE.md. Claude decides the exact phrasing and level of detail.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Reorganization Requirements
- `.planning/REQUIREMENTS.md` — REORG-04 (archive deprecated scripts) and REORG-05 (smoke test validation) definitions

### Current Pipeline State
- `R/SCRIPT_INDEX.md` — Canonical script numbering reference (regenerated Phase 67)
- `R/archive/README.md` — Documents 8 archived scripts with safe-to-delete assessments
- `R/87_smoke_test_full_pipeline.R` — Full pipeline smoke test (structural + data checks)

### Prior Phase Artifacts
- `.planning/phases/67-cancer-payer-qa-reorganization/67-01-VERIFICATION.md` — Phase 67 verification (if exists)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/87_smoke_test_full_pipeline.R` — Existing smoke test covering decade validation, source() resolution, numbering checks
- `R/86_smoke_test_foundation.R` — Foundation-specific smoke test (config, data loading)
- `R/archive/README.md` — Template for documenting archived scripts with assessments

### Established Patterns
- Decade-based numbering: 00-09 foundation, 10-19 cohort, 20-29 treatment, 40-59 cancer, 60-69 payer/QA, 70-79 outputs, 80-89 tests, 90-99 ad-hoc
- Archive pattern: Script + README entry with purpose, why archived, dependencies, safe-to-delete assessment

### Integration Points
- REQUIREMENTS.md traceability table (Phase 68 row needs status update)
- ROADMAP.md Phase 68 section (needs full rewrite to reflect repurposed scope)
- STATE.md (session tracking and current position)

</code_context>

<specifics>
## Specific Ideas

No specific requirements — standard verification workflow with scan-and-confirm approach.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 68-output-test-reorganization*
*Context gathered: 2026-06-01*
