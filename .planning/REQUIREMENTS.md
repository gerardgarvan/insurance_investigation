# Requirements — v3.12 Team To-Do Close-out

**Milestone:** v3.12 Team To-Do Close-out (Survivorship Rates, Anthracycline Exposure, NHL Follow-up)
**Window:** 2026-10-22 → 2026-11-05
**Starts at:** Phase 185

---

## v1 Requirements

### CLOSE — Phase 184 Carry-over

- [ ] **CLOSE-01**: R/184 runs end-to-end in interactive R on HiPerGator; dated workbook pinned via env var; path recorded in KEY; formal close-out SUMMARY in `.planning/phases/185-*/`; v3.11 MILESTONES known-gap marked resolved.
- [ ] **CLOSE-02**: far_from_care_100mi × modality interaction estimates reported per modality with 95% CIs; any non-convergence logged (not silently dropped); cells with patient count < 11 suppressed; language measured and non-causal.

### RATE — Survivorship Rate Granularity

- [x] **RATE-01**: Patient-level count and rate per modality at the annual window, read from the verified R/184 output by exact label (no recomputation drift; values read from pinned workbook).
- [x] **RATE-02**: "Biannual" definition resolved via D-186-01 (recorded in CONTEXT.md before any code) and implemented — either every 6 months (reuse R/184 sensitivity tier) or every 2 years (new window).
- [x] **RATE-03**: Single team-facing table with one row per modality × window (annual / biannual); columns: patients, events, patient-years, rate; KEY sheet leftmost; UF colours (#0021A5 / #FA4616); suppression rules applied.

### ANTH — Anthracycline Exposure Variables

- [x] **ANTH-01**: `any_anthracycline` (TRUE/FALSE, **never NA**) per cohort patient; `any_chemo` (TRUE/FALSE, never NA) per cohort patient; drug set: doxorubicin (liposomal collapsed per Phase 164), daunorubicin, epirubicin, idarubicin — mitoxantrone explicitly excluded; aggregate counts reported by flag and by drug, suppressed per HIPAA.
- [x] **ANTH-02**: `last_anthracycline_date` = latest `treatment_date` across all episodes for included drugs; `years_since_last_anthracycline` = last dose → `follow_end` (Phase 161 `compute_followup()` definition, accounts for death); NA (not 0, not negative) when `any_anthracycline == FALSE` or when last dose date is after `follow_end`; `days_since_last_anthracycline_dose` per echo encounter is Phase 188 (ECHO-01), not Phase 187.
- [x] **ANTH-03**: Patient-grain RDS written to `output/internal/` (patient IDs + dates — internal only); aggregate-only summary in `output/`; variables joined into the survivorship analysis set; schema probe updated before code is written.

### ECHO — Echocardiogram Rate Since Anthracycline

- [ ] **ECHO-01**: Echo rate per patient-year since last anthracycline among `any_anthracycline == TRUE`: echoes after last dose ÷ `years_since_last_anthracycline`; echoes on or before last dose excluded and counted separately in a reconciliation column.
- [ ] **ECHO-02**: Reconciliation table vs Phase 166 anthracycline-to-echo timing (D6/D7/D8 decision chain): first- vs last-administration anchoring; differences explained in workbook KEY.

### COMM — Team Deliverables

- [x] **COMM-01**: Script-generated one-page explainer (written to `output/`, dated, copied unchanged into phase folder): how NHL-only and HL+NHL subsets were built from `gantt_episodes_180.csv`; patient counts (suppressed per HIPAA); what Chemo_combos columns E–J contribute.
- [x] **COMM-02**: Email draft ready for Gerard to send to Amy (cc Ray, Erin, Sharon); team questions supplied by Gerard (D-189-01); sign-off "Best, Gerard".

### REG — Pipeline Registration

- [x] **REG-01**: All new Phase 185–189 scripts registered in `R/39_run_all_investigations.R` and `R/SCRIPT_INDEX.md`; a new SMOKE section in `R/88_smoke_test_comprehensive.R` covering structural checks for each new script; R/88 ALL CHECKS PASSED on HiPerGator after Phase 189.

### TRACK — Status Tracking

- [ ] **TRACK-01**: To-do status table (from v3.12-milestone-brief.md map, final state) written to the Phase 189 milestone folder; every item shows Done or Closed-with-pointer; used for next team meeting notes update.

---

## Future Requirements (deferred)

- Anthracycline exposure as a covariate in the R/184 distance × modality interaction model — candidate for v3.13
- New CBC models beyond Phase 181/183 year-1 analysis
- End-of-treatment date rules (pending Sharon)
- Data-completeness check vs Medicaid claims
- D-15 primary analysis and D-165-01 method confirmation (awaiting Amy/Erin)

---

## Out of Scope

- SLURM/sbatch wrappers — interactive HiPerGator R only
- Adding mitoxantrone to the anthracycline drug set (excluded by D-187-02)
- Publication-ready figure formatting — exploratory quality sufficient

---

## Traceability

| REQ-ID   | Phase | Status |
|----------|-------|--------|
| CLOSE-01 | 185   | —      |
| CLOSE-02 | 185   | —      |
| RATE-01  | 186   | —      |
| RATE-02  | 186   | —      |
| RATE-03  | 186   | —      |
| ANTH-01  | 187   | —      |
| ANTH-02  | 187   | —      |
| ANTH-03  | 187   | —      |
| ECHO-01  | 188   | —      |
| ECHO-02  | 188   | —      |
| COMM-01  | 189   | —      |
| COMM-02  | 189   | —      |
| REG-01   | 189   | —      |
| TRACK-01 | 189   | —      |
