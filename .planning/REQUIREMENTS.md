# Requirements: PCORnet Payer Variable Investigation (R Pipeline)

**Defined:** 2026-06-07
**Core Value:** A working cohort filter chain that reads like a clinical protocol — with logged attrition at every step and clear payer-stratified visualizations showing how patients flow from enrollment through diagnosis to treatment.

## v2.3 Requirements

Requirements for Gantt Data Enrichment milestone. Each maps to roadmap phases.

### Code Cleanup

- [x] **CLEAN-01**: Remove 5 false-positive SCT codes (Z94.84, T86.5, T86.09, Z48.290, HEMATOLOGIC_TRANSPLANT_AND_ENDOC) from treatment detection pipeline
- [x] **CLEAN-02**: Smoke test updated to verify removed codes no longer produce SCT episodes

### Gantt Enrichment

- [x] **GANTT-01**: Gantt v2 episodes CSV includes medication_name column (human-readable from xlsx column C)
- [x] **GANTT-02**: Gantt v2 episodes CSV includes code_type column (RXNORM, CPT/HCPCS, ICD-10-CM)
- [x] **GANTT-03**: Gantt v2 episodes CSV includes source_table column (PRESCRIBING, PROCEDURES, DIAGNOSIS)
- [x] **GANTT-04**: Gantt v2 episodes CSV includes treatment_line column (F/S/E/N per triggering code)
- [x] **GANTT-05**: Gantt v2 episodes CSV includes cross_use_flag column (SCT conditioning / immunotherapy cross-use)
- [x] **GANTT-06**: Gantt v2 detail CSV includes same 5 new columns at per-date level
- [x] **GANTT-07**: Existing v1 Gantt exports unchanged (backward compatible)

### Immunotherapy Flagging

- [x] **IMMU-01**: Questionable immunotherapy codes (8 vitamin combos, 2 CAR-T) flagged with confidence column in Gantt output
- [x] **IMMU-02**: Flag values distinguish vitamin combos ("questionable--vitamin") from CAR-T ambiguity ("questionable--CAR-T vs immunotherapy")

## Phase 94 Requirements

Requirements for Proton Therapy category split. Maps to Phase 94.

### Proton Therapy Category Split

- [x] **PROTON-01**: 4 proton CPT codes (77520, 77522, 77523, 77525) mapped to "Proton Therapy" in DRUG_GROUPINGS (removed from "Radiation")
- [x] **PROTON-02**: TREATMENT_TYPES expanded to 5 elements with "Proton Therapy" as distinct category
- [x] **PROTON-03**: has_proton() predicate detects proton therapy evidence; HAD_PROTON flag in cohort
- [x] **PROTON-04**: Episode detection (R/26) and duration analysis (R/25) dispatch "Proton Therapy" to dedicated extraction functions
- [x] **PROTON-05**: Treatment inventory (R/20) has extract_proton_codes() for proton-specific code frequency reporting
- [x] **PROTON-06**: Smoke test validates proton category split: config vectors, code mappings, no double-counting, all new functions exist

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
| Resolving immunotherapy classification | Collaborators haven't weighed in yet -- flag only |
| Gantt v1 schema changes | Backward compatibility required; enrichment goes to v2 only |
| Impact analysis before SCT code removal | User chose direct removal without formal impact report |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CLEAN-01 | Phase 90 | Complete |
| CLEAN-02 | Phase 90 | Complete |
| GANTT-01 | Phase 91 | Complete |
| GANTT-02 | Phase 91 | Complete |
| GANTT-03 | Phase 91 | Complete |
| GANTT-04 | Phase 91 | Complete |
| GANTT-05 | Phase 91 | Complete |
| GANTT-06 | Phase 92 | Complete |
| GANTT-07 | Phase 92 | Complete |
| IMMU-01 | Phase 93 | Complete |
| IMMU-02 | Phase 93 | Complete |
| PROTON-01 | Phase 94 | Planned |
| PROTON-02 | Phase 94 | Planned |
| PROTON-03 | Phase 94 | Planned |
| PROTON-04 | Phase 94 | Planned |
| PROTON-05 | Phase 94 | Planned |
| PROTON-06 | Phase 94 | Planned |

**Coverage:**
- v2.3 requirements: 11 total (complete)
- Phase 94 requirements: 6 total
- Mapped to phases: 17
- Unmapped: 0

---
*Requirements defined: 2026-06-07*
*Last updated: 2026-06-09 after Phase 94 planning (6 new requirements)*
