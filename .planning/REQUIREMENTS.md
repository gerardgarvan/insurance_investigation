# Requirements - v3.15 ABVD/AVD Flag Simplification and Cohort Rule Change

v3.14 requirements archived at `.planning/milestones/v3.14-REQUIREMENTS.md` (milestone still open).

## Active Requirements

### ABVD - Episode and patient flags
- [ ] **ABVD-01**: `abvd_episode` TRUE when the episode contains doxorubicin, bleomycin, vinblastine and dacarbazine regardless of other compounds; else FALSE. ABVD_PLUS episodes become TRUE. Computed from episode drugs, not `abvd_class`; `abvd_class` stays as a descriptive column.
- [ ] **ABVD-02**: `avd_episode` TRUE when the episode contains doxorubicin, vinblastine and dacarbazine and no bleomycin, regardless of other compounds (BV+AVD, Nivo+AVD are TRUE). Assertion that no episode has both flags TRUE.
- [ ] **ABVD-03**: Patient-level `ever_abvd = any(abvd_episode)`, `ever_avd = any(avd_episode)` over entire episode history; both may be TRUE. `ever_abvd_plus` kept as deprecated, documented. KEY sheet / data dictionary list all four flags.
- [x] **ABVD-04**: Before/after impact table (episodes and patients, old vs new, crosstab by old `abvd_class`; patient crosstab ever_abvd x ever_avd), <11 suppression; reconciled with R/209 (pipeline ever_abvd 1,244; ABVD-class-episode-derived 1,052; ever_abvd_plus 163).

### COHORT - Cohort rule change
- [ ] **COHORT-01**: Drop 7-day HL diagnosis confirmation; require >=2 HL diagnoses on distinct encounters (different ENCOUNTERIDs, different dates).
- [ ] **COHORT-02**: Always include patients with HL in the tumor registry (UFH, ORL, TMH) regardless of the >=2 rule.
- [ ] **COHORT-03**: Exclude patients with NHL in the tumor registry unless they also have HL in the tumor registry.
- [ ] **COHORT-04**: Cohort waterfall old vs new: gained by dropping 7-day, gained by TR-HL include, lost by TR-NHL exclusion; by site; <11 suppression.

### CHAIN - Rerun and smoke test
- [ ] **CHAIN-01**: Rerun on HiPerGator (cohort -> R/26 -> R/28 -> R/28 p143 pass -> R/53 -> R/29 -> R/52 -> R/142 -> R/206 decision rules -> R/88) after backing up delivered outputs to `output/internal/pre_v315_backup/`; expected count changes documented per step.
- [ ] **CHAIN-02**: R/88 updated for new ABVD/AVD definitions and cohort rules; the 9 pre-v3.14 baseline failures remain baseline.

## Open Questions (recorded, not decided)
- Should BV+AVD / Nivo+AVD count as `avd_episode`? (ABVD-02 currently reads yes.)
- Minimum EHR presence for TR-HL forced includes (COHORT-02).
- TR NHL by ICD-O-3 histology vs site field, and which histology list (COHORT-03).

## Out of Scope
- Changes to treatment capture (R/26) or the regimen/LOT engine (Phase 205).
- Pushing to remote; any HiPerGator access from the local machine.

## Traceability
| Requirement | Phase |
|-------------|-------|
| ABVD-01, ABVD-02, ABVD-03 | 210 |
| ABVD-04 | 211 |
| COHORT-01, COHORT-02, COHORT-03, COHORT-04 | 212 |
| CHAIN-01, CHAIN-02 | 213 |
