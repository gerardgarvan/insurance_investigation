# Requirements: PCORnet Payer Variable Investigation (R Pipeline)

**Defined:** 2026-06-07
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## v2.3 Requirements

Requirements for Gantt Data Enrichment milestone. Each maps to roadmap phases.

### Code Cleanup

- [ ] **CLEAN-01**: Remove 5 false-positive SCT codes (Z94.84, T86.5, T86.09, Z48.290, HEMATOLOGIC_TRANSPLANT_AND_ENDOC) from treatment detection pipeline
- [ ] **CLEAN-02**: Smoke test updated to verify removed codes no longer produce SCT episodes

### Gantt Enrichment

- [ ] **GANTT-01**: Gantt v2 episodes CSV includes medication_name column (human-readable from xlsx column C)
- [ ] **GANTT-02**: Gantt v2 episodes CSV includes code_type column (RXNORM, CPT/HCPCS, ICD-10-CM)
- [ ] **GANTT-03**: Gantt v2 episodes CSV includes source_table column (PRESCRIBING, PROCEDURES, DIAGNOSIS)
- [ ] **GANTT-04**: Gantt v2 episodes CSV includes treatment_line column (F/S/E/N per triggering code)
- [ ] **GANTT-05**: Gantt v2 episodes CSV includes cross_use_flag column (SCT conditioning / immunotherapy cross-use)
- [ ] **GANTT-06**: Gantt v2 detail CSV includes same 5 new columns at per-date level
- [ ] **GANTT-07**: Existing v1 Gantt exports unchanged (backward compatible)

### Immunotherapy Flagging

- [ ] **IMMU-01**: Questionable immunotherapy codes (8 vitamin combos, 2 CAR-T) flagged with confidence column in Gantt output
- [ ] **IMMU-02**: Flag values distinguish vitamin combos ("questionable—vitamin") from CAR-T ambiguity ("questionable—CAR-T vs immunotherapy")

## Future Requirements

Deferred to future release. Tracked but not in current roadmap.

### Treatment Line Refinement

- **TREAT-01**: Resolve immunotherapy classification questions with collaborators (vitamin combos, CAR-T)
- **TREAT-02**: SCT conditioning temporal window validation (30-day vs 14-day with clinical SME)
- **TREAT-03**: Multi-line therapy sequencing (requires episode boundary formalization)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Supportive Care codes in Gantt | User chose treatment codes only (Chemo, Rad, SCT, Immuno) |
| Unrelated codes in Gantt | Not clinically meaningful for treatment timeline visualization |
| Resolving immunotherapy classification | Collaborators haven't weighed in yet — flag only |
| Gantt v1 schema changes | Backward compatibility required; enrichment goes to v2 only |
| Impact analysis before SCT code removal | User chose direct removal without formal impact report |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CLEAN-01 | Phase 90 | Pending |
| CLEAN-02 | Phase 90 | Pending |
| GANTT-01 | Phase 91 | Pending |
| GANTT-02 | Phase 91 | Pending |
| GANTT-03 | Phase 91 | Pending |
| GANTT-04 | Phase 91 | Pending |
| GANTT-05 | Phase 91 | Pending |
| GANTT-06 | Phase 92 | Pending |
| GANTT-07 | Phase 92 | Pending |
| IMMU-01 | Phase 93 | Pending |
| IMMU-02 | Phase 93 | Pending |

**Coverage:**
- v2.3 requirements: 11 total
- Mapped to phases: 11
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-07*
*Last updated: 2026-06-07 after roadmap creation (100% coverage)*
