# v3.12 Milestone To-Do Status

**Milestone:** v3.12 — Team To-Do Close-out (Survivorship Rates, Anthracycline Exposure, NHL Follow-up)  
**As of:** 2026-10-27  
**Source:** Meeting notes to-do list (10/16), mapped to analysis phases

---

All analysis work for the to-do list is complete; one registration gate (R/88 on HiPerGator) and two team decisions remain open (biannual definition; questions for Amy email).

| Item | Description | Status | Closed by / Notes |
|------|-------------|--------|-------------------|
| 1 / 1.1 | Binary distance indicator (>100 miles) and chi-squared comparison against prior-year CBC | Closed-with-pointer | Delivered in v3.7: distance binary built (Phase 165); CBC × distance analysis completed (Phases 179–181, 183). MILESTONES.md — v3.11 entry: pooled primary OR 0.842/0.834. |
| 2 | Single-health-system (one SOURCE site) care flag | Closed-with-pointer | Delivered in v3.7: flag and care indicator built (Phase 167). MILESTONES.md — v3.7 entry: R/169_single_source_care.R. |
| 3 / 3.1 | NHL-only and HL+NHL patient subsets from the episode file, joined to chemotherapy combination columns | Closed-with-pointer | Delivered in v3.7: subsets built and joined (Phase 168). MILESTONES.md — v3.7 entry: R/170_nhl_gantt_subsets.R. NHL-only = 849 patients, HL+NHL = 176 patients, 0 overlap. |
| 3.2 (COMM-01) | Script-generated explainer for Amy describing how the NHL-only and HL+NHL subsets were built and what the chemotherapy combination columns contribute | Done | Phase 189 Plan 01 SUMMARY: R/189_nhl_explainer.R run on HiPerGator 2026-10-23; explainer written to output/189-NHL-EXPLAINER-20261023.md and copied to phase folder. |
| 3.2 (COMM-02) | Email to Amy (cc Ray, Erin, Sharon) with the subset explainer attached and team questions | Open | Phase 189 Plan 02: draft is ready in the phase folder (189-AMY-EMAIL-DRAFT.md) with correct recipients and sign-off. Awaiting D-189-01 — Gerard supplies the team questions before sending. |
| 4.1 (overall) | Per-modality echocardiogram count and rate at the patient level | Closed-with-pointer | Delivered in v3.7: overall patient-level modality rates built (Phase 166). MILESTONES.md — v3.7 entry: SMOKE-166-01 wired. |
| 4.1 (annual / biannual breakdown) | Per-modality rates broken out by annual and biannual surveillance windows | Done | Phase 185 Plan 01 SUMMARY: R/184 confirmed on HiPerGator 2026-10-22; annual rates in output/modality_rate_model_20261022.xlsx. Phase 186 Plan 01 SUMMARY: biannual (6-month) table in output/survivorship_rate_granularity_20261022.xlsx with complementary suppression applied. |
| 4.2 | Interaction between distance from care (>100 miles) and surveillance modality — Poisson GEE model | Done | Phase 185 Plan 01 SUMMARY: interaction estimates per modality with 95% CIs produced in the 2026-10-22 workbook. Non-convergence handling logged; small cells suppressed. |
| 4.3 (binary flag) | Binary indicator of any anthracycline administration per patient | Done | Phase 187 Plan 01 SUMMARY: any_anthracycline flag (TRUE/FALSE) built for all cohort patients; patient-grain file in output/internal/anthracycline_exposure_patient_20261022.rds; aggregate counts in output/anthracycline_exposure_summary_20261022.xlsx. |
| 4.3 (time since last dose) | Time (in years) since the last anthracycline administration, per exposed patient | Done | Phase 187 Plan 01 SUMMARY: years_since_last_anthracycline computed from last dose to end of follow-up; NA for unexposed patients; written to same patient-grain files as above. |
| 4.3 (echo rate since anthracycline) | Echocardiogram rate per patient-year since last anthracycline, among exposed patients, with reconciliation against Phase 166 timing | Done | Phase 188 Plan 01 SUMMARY: echo rate computed from Phase 187 exposure variables; encounter-grain and patient-grain results in output/internal/; Phase 166 reconciliation documented in output/20261022_188_echo_rate_anthracycline.xlsx. |
| REG-01 | Registration of new Phase 185–189 analysis scripts in the investigation registry and smoke test suite; smoke test passes on HiPerGator | Open | Phase 189 Plan 03 SUMMARY: R/186, R/187, R/188 added to R/39 registry and script index; smoke sections 15av–15az added to R/88 (Phases 184–189). HiPerGator ALL CHECKS PASSED gate is pending — user must run R/88 interactively to close this item. |
| TRACK-01 | Milestone to-do status table for team meeting notes | Done | This document (189-TODO-STATUS.md in the phase folder), written 2026-10-27 by Phase 189 Plan 04. |
| D-186-01 | Definition of "biannual" surveillance interval | Open | Provisional: every 6 months (half-year window from Phase 184 sensitivity tier). Awaiting team confirmation before treating as final. |
| D-189-01 | Questions for the Amy email | Open | Gerard supplies the questions. The email draft (189-AMY-EMAIL-DRAFT.md) is ready in the phase folder but will not be sent until this placeholder is filled. |

---

*Scope: items from the 10/16 to-do list and the two open decisions above. Other open project items are tracked separately.*
