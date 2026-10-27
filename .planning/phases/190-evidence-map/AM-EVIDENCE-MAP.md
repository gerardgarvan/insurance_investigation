---
phase: 190-evidence-map
plan: 01
created: 2026-10-27
status: DRAFT
---

# AM Evidence Map — Phase 190

Crosswalk from every item in `docs/analytic_manual/AnalyticManual_2026.01.30.md` to repo evidence.
Phase 190 identifies leads; it does not issue verdicts. Phase 191 verifies each lead.

---

## Definitions

### Item statuses

| Status | Use when |
|--------|----------|
| FILLED-NEEDS-CHECK | The manual contains a substantive rule or statement that can be checked against the repo |
| EMPTY-REPO-CAN-ANSWER | The manual field is empty (or the domain is repo-only) and the repo has a source that can answer it |
| EMPTY-NEEDS-TEAM | Empty or unresolved, and only team input can answer it (e.g., pending Sharon) |
| OUT-OF-SCOPE | Guidance/boilerplate text, sign-off boxes, title/grant with no repo source |
| BLOCKED | Depends on an input that has not been received (c0 → OneFLquestions document) |
| RETIRED | Lifecycle state only, never assigned in Phase 190. A retired row keeps its ID; its prior status is recorded in Notes as was: <STATUS> |

A row whose only evidence is PLANNING-DOC keeps its status but has PROVISIONAL at the start of Notes. Phase 191/192 must locate code or config before relying on it.

### Evidence types

CODE (current executable code: path:function() and line range) · CONFIG (R/00_config.R:KEY) · PLANNING-DOC (phase SUMMARY/CONTEXT/DISCUSSION-LOG) · TEAM-DECISION (attributed decision, linked via Decision ID) · MEETING-NOTES (TeamMtgNotes2026.md with date) · NONE

### Decision statuses (AM-MAP-03 table only)

OPEN · CONFIRMED (decision stated and in force) · SUPERSEDED (replaced by a later decision; Notes name the replacement)

### ID scheme

Pattern: S{section}-{DOMAIN}-{NN}; regex ^S(\d{1,2}|A[1-4]|B)-[A-Z]{2,6}-\d{2}$

Reserved: S4-CMNT-01 = c0, S4-CMNT-02 = c1.

---

## ID Registry

| ID | Created | First Row | Notes |
|----|---------|-----------|-------|
| S0-FM-01 | 2026-10-27 | S0 title | Front matter title row |
| S0-FM-02 | 2026-10-27 | S0 grant | Front matter grant row |
| S0-FM-03 | 2026-10-27 | S0 data sources | Front matter data sources |
| S0-FM-04 | 2026-10-27 | S0 freeze version | Front matter freeze version |
| S0-FM-05 | 2026-10-27 | S0 analytic version | Front matter analytic version |
| S0-FM-06 | 2026-10-27 | S0 doc version | Front matter document version |
| S0-FM-07 | 2026-10-27 | S0 doc version | Front matter document version |
| S0-FM-08 | 2026-10-27 | S0 date updated | Front matter date last updated |
| S0-FM-09 | 2026-10-27 | S0 team roles | Front matter team roles block (L19-L27) |
| S1-LOG-01 | 2026-10-27 | S1 ingest table | §1 Data Ingest table |
| S2-COH-01 | 2026-10-27 | S2 inclusion | §2.1 Inclusion Criteria |
| S2-COH-02 | 2026-10-27 | S2 exclusion | §2.1 Exclusion Criteria |
| S2-COH-03 | 2026-10-27 | S2 index date | §2.1 Index Date Definition |
| S2-COH-04 | 2026-10-27 | S2 obs window | §2.1 Observation Window |
| S2-COH-05 | 2026-10-27 | S2 history table | §2.2 Historical Cohort Definitions |
| S3-DEC-01 | 2026-10-27 | S3 decision log | §3 Variable/Phenotype Decision Log |
| S4-CMNT-01 | 2026-10-27 | S4 comment c0 | Reserved: Amy's comment c0 (BLOCKED) |
| S4-CMNT-02 | 2026-10-27 | S4 comment c1 | Reserved: Amy's comment c1 on DXDT cleaning rules |
| S4-DXDT-01 | 2026-10-27 | S4 DXDT expected | §4 Cancer Diagnosis Date — Expected Structure |
| S4-DXDT-02 | 2026-10-27 | S4 DXDT observed | §4 Cancer Diagnosis Date — Observed Issues |
| S4-DXDT-03 | 2026-10-27 | S4 DXDT cleaning | §4 Cancer Diagnosis Date — Cleaning Rules Applied |
| S4-DXDT-04 | 2026-10-27 | S4 DXDT unresolved | §4 Cancer Diagnosis Date — Unresolved Issues |
| S4-SRC-01 | 2026-10-27 | S4 SRC expected | §4 Source — Expected Structure |
| S4-SRC-02 | 2026-10-27 | S4 SRC observed | §4 Source — Observed Issues (LNK in DEMOGRAPHIC only) |
| S4-SRC-03 | 2026-10-27 | S4 SRC cleaning | §4 Source — Cleaning Rules Applied |
| S4-SRC-04 | 2026-10-27 | S4 SRC unresolved | §4 Source — Unresolved Issues |
| S4-DX-01 | 2026-10-27 | S4 DX expected | §4 Cancer Diagnosis — Expected Structure |
| S4-DX-02 | 2026-10-27 | S4 DX observed | §4 Cancer Diagnosis — Observed Issues (erroneous HL/NHL) |
| S4-DX-03 | 2026-10-27 | S4 DX cleaning | §4 Cancer Diagnosis — Cleaning Rules Applied (7-day rule) |
| S4-DX-04 | 2026-10-27 | S4 DX unresolved | §4 Cancer Diagnosis — Unresolved Issues |
| S4-INS-01 | 2026-10-27 | S4 INS expected | §4 Insurance — Expected Structure |
| S4-INS-02 | 2026-10-27 | S4 INS observed | §4 Insurance — Observed Issues (missingness) |
| S4-INS-03 | 2026-10-27 | S4 INS cleaning | §4 Insurance — Cleaning Rules Applied (6-tier hierarchy) |
| S4-INS-04 | 2026-10-27 | S4 INS confirm | §4 Insurance — Unresolved Issues (Gerard to confirm) |
| S4-ADI-01 | 2026-10-27 | S4 ADI expected | §4 ADI — Expected Structure |
| S4-ADI-02 | 2026-10-27 | S4 ADI observed | §4 ADI — Observed Issues (missing zip) |
| S4-ADI-03 | 2026-10-27 | S4 ADI cleaning rule 1 | §4 ADI — Cleaning Rule: 5-digit matches 9-digit extrapolation |
| S4-ADI-04 | 2026-10-27 | S4 ADI cleaning rule 2 | §4 ADI — Cleaning Rule: pop-weighted average fallback |
| S4-ADI-05 | 2026-10-27 | S4 ADI cleaning rule 3 | §4 ADI — Cleaning Rule: non-matching 5-digit zip |
| S4-ADI-06 | 2026-10-27 | S4 ADI unresolved | §4 ADI — Unresolved Issues |
| S4-TRT-01 | 2026-10-27 | S4 TRT expected | §4 Treatment Window — Expected Structure |
| S4-TRT-02 | 2026-10-27 | S4 TRT observed | §4 Treatment Window — Observed Issues |
| S4-TRT-03 | 2026-10-27 | S4 TRT cleaning | §4 Treatment Window — Cleaning Rules Applied |
| S4-TRT-04 | 2026-10-27 | S4 TRT unresolved | §4 Treatment Window — Unresolved Issues (pending Sharon) |
| S4-REL-01 | 2026-10-27 | S4 REL expected | §4 Initial treatment vs relapse — Expected Structure |
| S4-REL-02 | 2026-10-27 | S4 REL observed | §4 Initial treatment vs relapse — Observed Issues |
| S4-REL-03 | 2026-10-27 | S4 REL cleaning | §4 Initial treatment vs relapse — Cleaning Rules Applied |
| S4-REL-04 | 2026-10-27 | S4 REL unresolved | §4 Initial treatment vs relapse — Unresolved Issues |
| S4-DTH-01 | 2026-10-27 | S4 DTH expected | §4 Death — Expected Structure |
| S4-DTH-02 | 2026-10-27 | S4 DTH observed | §4 Death — Observed Issues |
| S4-DTH-03 | 2026-10-27 | S4 DTH cleaning rule 1 | §4 Death — Cleaning Rule: 14-day prior rule |
| S4-DTH-04 | 2026-10-27 | S4 DTH cleaning rule 2 | §4 Death — Cleaning Rule: do not use cause of death |
| S4-DTH-05 | 2026-10-27 | S4 DTH unresolved | §4 Death — Unresolved Issues |
| S4-SRV-01 | 2026-10-27 | S4 SRV expected | §4 Survivorship encounters — Expected Structure |
| S4-SRV-02 | 2026-10-27 | S4 SRV observed | §4 Survivorship encounters — Observed Issues |
| S4-SRV-03 | 2026-10-27 | S4 SRV cleaning | §4 Survivorship encounters — Cleaning Rules Applied |
| S4-SRV-04 | 2026-10-27 | S4 SRV unresolved 1 | §4 Survivorship — VariableDetails.xlsx needs completion |
| S4-SRV-05 | 2026-10-27 | S4 SRV unresolved 2 | §4 Survivorship — Need treatment windows first |
| S4-DIST-01 | 2026-10-27 | S4 DIST expected | §4 Distance — Expected Structure |
| S4-DIST-02 | 2026-10-27 | S4 DIST observed | §4 Distance — Observed Issues |
| S4-DIST-03 | 2026-10-27 | S4 DIST cleaning rule 1 | §4 Distance — Cleaning Rule: zipcodeR package |
| S4-DIST-04 | 2026-10-27 | S4 DIST cleaning rule 2 | §4 Distance — Cleaning Rule: 9-digit → 5-digit |
| S4-DIST-05 | 2026-10-27 | S4 DIST cleaning rule 3 | §4 Distance — Cleaning Rule: no-zip fallback |
| S4-DIST-06 | 2026-10-27 | S4 DIST unresolved | §4 Distance — Unresolved Issues (binary cutoff) |
| S5-REC-01 | 2026-10-27 | S5 EHR authoritative | §5 Cross-System Reconciliation — EHR authoritative |
| S5-REC-02 | 2026-10-27 | S5 Claims authoritative | §5 Cross-System Reconciliation — Claims authoritative |
| S5-REC-03 | 2026-10-27 | S5 concordance | §5 Concordance Checks |
| S5-REC-04 | 2026-10-27 | S5 precedence | §5 Precedence Rules for Conflicts |
| S5-REC-05 | 2026-10-27 | S5 sensitivity | §5 Sensitivity Analyses Planned |
| S6-QA-01 | 2026-10-27 | S6 date logic | §6 QA — Date logic checks |
| S6-QA-02 | 2026-10-27 | S6 distribution | §6 QA — Distribution checks |
| S6-QA-03 | 2026-10-27 | S6 cross-source | §6 QA — Cross-source validation |
| S6-QA-04 | 2026-10-27 | S6 masters signoff | §6 QA — Masters biostatistician sign-off |
| S6-QA-05 | 2026-10-27 | S6 phd signoff | §6 QA — PhD biostatistician sign-off |
| S6-QA-06 | 2026-10-27 | S6 mpi signoff | §6 QA — MPI sign-off |
| S6-QA-07 | 2026-10-27 | S6 notes | §6 QA Notes field |
| S7-TRK-01 | 2026-10-27 | S7 aim1 | §7 Analysis Status — Aim 1 treatment |
| S7-TRK-02 | 2026-10-27 | S7 aim2 | §7 Analysis Status — Aim 2 survivorship |
| S7-TRK-03 | 2026-10-27 | S7 radonc | §7 Analysis Status — Rad onc subgroup |
| S8-PRK-01 | 2026-10-27 | S8 mpi questions | §8 Open Questions — MPI input required |
| S8-PRK-02 | 2026-10-27 | S8 deferred | §8 Open Questions — Deferred decisions |
| S8-PRK-03 | 2026-10-27 | S8 limitations | §8 Open Questions — Known limitations |
| S9-GUI-01 | 2026-10-27 | S9 purpose | §9 How to Use — Purpose |
| S9-GUI-02 | 2026-10-27 | S9 cadence | §9 How to Use — Update cadence |
| S9-GUI-03 | 2026-10-27 | S9 roles | §9 How to Use — Team roles |
| S9-GUI-04 | 2026-10-27 | S9 versioning | §9 How to Use — Versioning guidance |
| S10-OPT-01 | 2026-10-27 | S10 decision log | §10 Optional — Decision Log Spreadsheet |
| S10-OPT-02 | 2026-10-27 | S10 companion sop | §10 Optional — Companion SOP |
| S10-OPT-03 | 2026-10-27 | S10 code crosswalk | §10 Optional — Code Repository Crosswalk |
| S10-OPT-04 | 2026-10-27 | S10 sap xref | §10 Optional — SAP Cross-Reference Table |
| S11-LIM-01 | 2026-10-27 | S11 EHR limits | §11 Known Limitations — EHR capture |
| S11-LIM-02 | 2026-10-27 | S11 claims limits | §11 Known Limitations — Claims completeness |
| S11-LIM-03 | 2026-10-27 | S11 measurement | §11 Known Limitations — Measurement error |
| S11-LIM-04 | 2026-10-27 | S11 populations | §11 Known Limitations — Underrepresented populations |
| S11-LIM-05 | 2026-10-27 | S11 bias | §11 Implications — Potential bias |
| S11-LIM-06 | 2026-10-27 | S11 affected | §11 Implications — Analyses most affected |
| S11-LIM-07 | 2026-10-27 | S11 mitigation | §11 Implications — Planned sensitivity/mitigation |
| SA1-LOG-01 | 2026-10-27 | SA1 ingest table | Appendix A1 Data Ingest table |
| SA2-COH-01 | 2026-10-27 | SA2 cohort history | Appendix A2 Cohort Definition History |
| SA3-DEC-01 | 2026-10-27 | SA3 decision log | Appendix A3 Variable & Phenotype Decision Log |
| SA4-TRK-01 | 2026-10-27 | SA4 tracker | Appendix A4 Analysis Status Tracker |
| SB-SOP-01 | 2026-10-27 | SB purpose | Appendix B — Purpose |
| SB-SOP-02 | 2026-10-27 | SB when | Appendix B — When to update |
| SB-SOP-03 | 2026-10-27 | SB who | Appendix B — Who updates what |
| SB-SOP-04 | 2026-10-27 | SB rules | Appendix B — Documentation rules |
| SB-SOP-05 | 2026-10-27 | SB why | Appendix B — Why this matters |
| S4-SHS-01 | 2026-10-27 | S4-SHS repo | REPO-ONLY: Single-health-system flag |
| S4-CHM-01 | 2026-10-27 | S4-CHM repo | REPO-ONLY: Chemo detection |
| S4-NRM-01 | 2026-10-27 | S4-NRM repo | REPO-ONLY: Drug-name normalization |
| S4-REG-01 | 2026-10-27 | S4-REG repo | REPO-ONLY: First-line regimens |
| S4-EPI-01 | 2026-10-27 | S4-EPI repo | REPO-ONLY: Treatment episodes |
| S4-ANT-01 | 2026-10-27 | S4-ANT repo | REPO-ONLY: Anthracycline exposure |
| S4-CBC-01 | 2026-10-27 | S4-CBC repo | REPO-ONLY: CBC definition |
| S4-RUR-01 | 2026-10-27 | S4-RUR repo | REPO-ONLY: Rurality |
| S4-SDI-01 | 2026-10-27 | S4-SDI repo | REPO-ONLY: Social Deprivation Index |
| S4-DOI-01 | 2026-10-27 | S4-DOI repo | REPO-ONLY: Rituximab/methotrexate diagnoses of interest |
| S4-CLS-01 | 2026-10-27 | S4-CLS repo | REPO-ONLY: HL vs NHL classification |
| S4-PDE-01 | 2026-10-27 | S4-PDE repo | REPO-ONLY: Post-death encounters |
| DEC-001 | 2026-10-27 | AM-MAP-03 | D-190-01: OneFLquestions document location |
| DEC-002 | 2026-10-27 | AM-MAP-03 | Insurance hierarchy confirmed by Amy (5/1/2026) |
| DEC-003 | 2026-10-27 | AM-MAP-03 | 7-day two-encounter rule for all cancer types |
| DEC-004 | 2026-10-27 | AM-MAP-03 | ADI: pop-weighted average of 5-digit ZIP |
| DEC-005 | 2026-10-27 | AM-MAP-03 | ADI: if 5-digit matches 9-digit extrapolate |
| DEC-006 | 2026-10-27 | AM-MAP-03 | RUCA: can use 5-digit zip |
| DEC-007 | 2026-10-27 | AM-MAP-03 | Relapse vs refractory: 90-day break threshold |
| DEC-008 | 2026-10-27 | AM-MAP-03 | Distance cutoff: 100 miles (based on article) |
| DEC-009 | 2026-10-27 | AM-MAP-03 | NHL-only episodes removed from dataset |
| DEC-010 | 2026-10-27 | AM-MAP-03 | Err on side of including uncertain HL patients |
| DEC-011 | 2026-10-27 | AM-MAP-03 | Brand-name chemo → generic (adriamycin → doxorubicin) |
| DEC-012 | 2026-10-27 | AM-MAP-03 | Remove diagnosis table data from survivorship modality codes |

---

## Main Map

| ID | Origin | AM Section | Domain | Item | Manual Lines | Manual Text | Status | Evidence Type | Repo Source | What the Source Shows | Lead | Decision ID | Notes |
|----|--------|------------|--------|------|--------------|-------------|--------|---------------|-------------|----------------------|------|-------------|-------|
| S0-FM-01 | MANUAL | §0 Front Matter | FM | Document title | L1 | # Analytic Manual (AM): Blood Cancer United Hodgkin Lymphoma Study | OUT-OF-SCOPE | NONE | — | — | — | — | Title only; no repo source needed |
| S0-FM-02 | MANUAL | §0 Front Matter | FM | Project title field | L5 | Project title: | OUT-OF-SCOPE | NONE | — | — | — | — | Empty field; no repo analog |
| S0-FM-03 | MANUAL | §0 Front Matter | FM | Grant number field | L7 | Grant number: | OUT-OF-SCOPE | NONE | — | — | — | — | Empty field; no repo analog |
| S0-FM-04 | MANUAL | §0 Front Matter | FM | Data sources | L9 | Data sources: EHR (primary), Claims (secondary) | FILLED-NEEDS-CHECK | CONFIG | R/00_config.R: IS_LOCAL, DuckDB path constants | Config defines EHR (DuckDB/PCORnet) as primary; claims integration not yet implemented in pipeline. | — | — | — |
| S0-FM-05 | MANUAL | §0 Front Matter | FM | Current data freeze version | L11 | Current data freeze version: | OUT-OF-SCOPE | NONE | — | — | — | D-190-02 | Empty field; D-190-02 covers freeze label |
| S0-FM-06 | MANUAL | §0 Front Matter | FM | Current analytic version | L13 | Current analytic version (e.g., v0.1 – Initial Cleaning): | OUT-OF-SCOPE | NONE | — | — | — | — | Empty field |
| S0-FM-07 | MANUAL | §0 Front Matter | FM | Document version | L15 | Document version: | OUT-OF-SCOPE | NONE | — | — | — | — | Empty field |
| S0-FM-08 | MANUAL | §0 Front Matter | FM | Date last updated | L17 | Date last updated: 9/3/2026 | OUT-OF-SCOPE | NONE | — | — | — | — | Manual metadata; no repo source |
| S0-FM-09 | MANUAL | §0 Front Matter | FM | Team roles | L19-L27 | Team roles: MPI Ray Mailhot MD MPH; MPI Erin Mobley PhD MPH; PhD Biostatistician Amy Crisp PhD; Masters-Level Biostatistician Gerard Garvan MS | OUT-OF-SCOPE | NONE | — | — | — | — | Personnel listing; no repo source |
| S1-LOG-01 | MANUAL | §1 Data Ingest | LOG | Data Ingest & Change Log table | L29-L38 | Use this table to track all incoming data updates and their impact. \| Date \| Data source \| Description of change \| Impact on cohort or variables \| Action taken \| (table with empty rows) | EMPTY-REPO-CAN-ANSWER | PLANNING-DOC | .planning/STATE.md; phase SUMMARYs | PROVISIONAL. STATE.md records data freeze dates and extract paths; individual phase SUMMARYs record cohort impacts. No pipeline equivalent of this §1 table exists yet. | — | — | PROVISIONAL: planning documents cover data ingest history but no single log table exists |
| S2-COH-01 | MANUAL | §2 Cohort Construction | COH | Inclusion Criteria | L42-L46 | 2.1 Current Cohort Definition (Authoritative)<br>- Inclusion Criteria:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | PLANNING-DOC; CODE | R/utils/utils_treatment.R: get_hl_any_dx_ids() L310-L345; Phase 104 SUMMARY | PROVISIONAL. Inclusion logic (HL ICD codes, 2-encounter 7-day rule) is in get_hl_any_dx_ids(); manual field is blank. | L4 | — | PROVISIONAL |
| S2-COH-02 | MANUAL | §2 Cohort Construction | COH | Exclusion Criteria | L48-L50 | - Exclusion Criteria:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | PLANNING-DOC | Phase 34 SUMMARY; Phase 87 SUMMARY | PROVISIONAL. NHL-only episode exclusion decided by team (DEC-009); no single exclusion list in manual yet. | L4 | DEC-009 | PROVISIONAL |
| S2-COH-03 | MANUAL | §2 Cohort Construction | COH | Index Date Definition | L52-L54 | - Index Date Definition:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | PLANNING-DOC; CODE | R/utils/utils_treatment.R: get_hl_any_dx_ids(); Phase 133 SUMMARY | PROVISIONAL. Index date logic (TR date default, first HL code fallback) implemented in treatment utils. | L3 | — | PROVISIONAL |
| S2-COH-04 | MANUAL | §2 Cohort Construction | COH | Observation Window Requirements | L56-L58 | - Observation Window Requirements:<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | Manual field blank; no coded observation window found in repo. Requires team input. | — | — | — |
| S2-COH-05 | MANUAL | §2 Cohort Construction | COH | Historical Cohort Definitions table | L60-L67 | 2.2 Historical Cohort Definitions (Do Not Delete)<br>\| Version \| Date \| Changes \| Rationale \| (empty rows) | EMPTY-REPO-CAN-ANSWER | PLANNING-DOC | .planning/STATE.md; phase SUMMARYs 34-189 | PROVISIONAL. History is distributed across phase SUMMARYs; no consolidated version table in repo. | — | — | PROVISIONAL |
| S3-DEC-01 | MANUAL | §3 Decision Log | DEC | Variable and Phenotype Decision Log | L69-L79 | Track analytic decisions and rationale for exposures, outcomes, and covariates.<br>\| Construct \| Initial plan \| Issue identified \| Decision made \| Rationale \| Date \| Affected analyses \| (empty rows) | EMPTY-REPO-CAN-ANSWER | PLANNING-DOC | .planning/STATE.md Decisions section; phase DISCUSSION-LOGs | PROVISIONAL. AM-MAP-03 (this map) will serve as the populated version of this table for AM domains. Phase 191 will carry forward. | — | — | PROVISIONAL |
| S4-CMNT-01 | MANUAL | §4 Data Cleaning | CMNT | Amy's comment c0 — OneFLquestions reference | L81 | [Comment c0, author=Crisp Amy, 2026-10-23] Reference OneFLquestions document to ensure everything has made it into here. Anchored on: 'Data Cleaning and Harmonization Rules' (§4 heading) | BLOCKED | NONE | — | — | — | D-190-01 | D-10: pending OneFLquestions document; D-190-01 OPEN. Interim: proceed without it; list as §8 gap. |
| S4-CMNT-02 | MANUAL | §4 Data Cleaning | CMNT | Amy's comment c1 — DXDT code confirmation | L95-L101 | [Comment c1, author=Crisp Amy, 2026-10-23] Gerard to confirm this is what's in the code. Anchored on: 'Use diagnosis date from Tumor Registry as default.<br>If no diagnosis date: use first date with HL diagnosis code' | FILLED-NEEDS-CHECK | CODE | R/utils/utils_treatment.R: get_hl_any_dx_ids() L310-L345 | Code path uses tumor registry date as default and falls back to first HL ICD code date; exact priority order to be verified in Phase 191. Answered in Phase 191 with c1 (AM-VER-02). | L3 | — | — |
| S4-DXDT-01 | MANUAL | §4 Data Cleaning | DXDT | Cancer Diagnosis Date — Expected Structure | L83-L87 | Domain: Cancer Diagnosis Date<br>- Expected Structure:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | CODE | R/utils/utils_treatment.R: get_hl_any_dx_ids() L310-L345 | PROVISIONAL. Expected structure not written in manual; code implements TR-first then HL-ICD-code fallback. | L3 | — | PROVISIONAL |
| S4-DXDT-02 | MANUAL | §4 Data Cleaning | DXDT | Cancer Diagnosis Date — Observed Issues | L89-L91 | - Observed Issues:<br>  - Not everyone has a diagnosis date that makes sense for HL. | FILLED-NEEDS-CHECK | PLANNING-DOC | Phase 133 SUMMARY | Code addresses this issue by applying two-step date resolution; Phase 133 SUMMARY describes the fallback logic. | L3 | — | — |
| S4-DXDT-03 | MANUAL | §4 Data Cleaning | DXDT | Cancer Diagnosis Date — Cleaning Rules (TR default + HL fallback) | L93-L101 | - Cleaning Rules Applied:<br>  - Use diagnosis date from Tumor Registry as default.<br>  - If no diagnosis date: use first date with HL diagnosis code | FILLED-NEEDS-CHECK | CODE | R/utils/utils_treatment.R: get_hl_any_dx_ids() L310-L345 | Both bullets covered by c1 anchor. Code implements TR-first then HL-ICD fallback; exact source order to verify in Phase 191. | L3 | — | c1 anchor covers both bullets per user confirmation |
| S4-DXDT-04 | MANUAL | §4 Data Cleaning | DXDT | Cancer Diagnosis Date — Unresolved Issues | L103 | - Unresolved Issues: (empty) | OUT-OF-SCOPE | NONE | — | Empty unresolved field. | L3 | — | — |
| S4-SRC-01 | MANUAL | §4 Data Cleaning | SRC | Source — Expected Structure | L105-L109 | Domain: Source<br>- Expected Structure:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | CODE | R/169_single_source_care.R: build_single_source_result() L48-L90 | PROVISIONAL. Source logic reads ENCOUNTER.SOURCE; expected structure not written in manual. | L1 | — | PROVISIONAL |
| S4-SRC-02 | MANUAL | §4 Data Cleaning | SRC | Source — Observed Issues (LNK in DEMOGRAPHIC) | L111-L115 | - Observed Issues:<br>  - LNK is only in the demographic table, not the encounter table. Confirmed that Pat_ID is the same across sources, so as long as we use unique(patient_ID), we will not double count. | FILLED-NEEDS-CHECK | CODE | R/169_single_source_care.R: L127-L160 (SQL CTE); R/utils/utils_treatment.R | Code reads SOURCE from ENCOUNTER table, not DEMOGRAPHIC; the LNK-in-DEMOGRAPHIC issue noted in manual may be a discrepancy to verify in Phase 191. | L1 | — | — |
| S4-SRC-03 | MANUAL | §4 Data Cleaning | SRC | Source — Cleaning Rules Applied | L117-L119 | - Cleaning Rules Applied:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | CODE | R/169_single_source_care.R: build_single_source_result() | Code builds single_source_care and primary_source flags from ENCOUNTER.SOURCE. Manual cleaning rules field is empty. | L1 | — | — |
| S4-SRC-04 | MANUAL | §4 Data Cleaning | SRC | Source — Unresolved Issues | L121 | - Unresolved Issues: (empty) | OUT-OF-SCOPE | NONE | — | Empty unresolved field. | L1 | — | — |
| S4-DX-01 | MANUAL | §4 Data Cleaning | DX | Cancer Diagnosis — Expected Structure | L123-L127 | Domain: Cancer Diagnosis<br>- Expected Structure:<br>  - All patients actually have HL | FILLED-NEEDS-CHECK | PLANNING-DOC; CODE | Phase 87 SUMMARY; Phase 105 SUMMARY; R/utils/utils_cancer.R | Expected structure (all patients truly HL) partially addressed by NHL classification logic in utils_cancer.R. | L4 | — | — |
| S4-DX-02 | MANUAL | §4 Data Cleaning | DX | Cancer Diagnosis — Observed Issues (erroneous HL/NHL) | L129-L132 | - Observed Issues:<br>  - Many patients seem to be listed with HL when in fact they likely have NHL | FILLED-NEEDS-CHECK | PLANNING-DOC; CODE | Phase 87 SUMMARY; Phase 105 SUMMARY; R/utils/utils_cancer.R | NHL classification implemented; Gantt-based NHL episode detection discussed in meeting notes. | L4 | DEC-009; DEC-010 | — |
| S4-DX-03 | MANUAL | §4 Data Cleaning | DX | Cancer Diagnosis — Cleaning Rules (7-day rule, all cancers) | L134-L138 | - Cleaning Rules Applied:<br>  - Only counting cancer diagnoses with at least two separate encounters with a diagnosis of the same cancer type at least 7 days apart. This applies to all cancer types. | FILLED-NEEDS-CHECK | CODE; PLANNING-DOC | R/utils/utils_treatment.R: get_hl_any_dx_ids() L310-L345; Phase 104 SUMMARY; Phase 110 SUMMARY | Two-encounter 7-day rule implemented in get_hl_any_dx_ids(); manual states "all cancer types" — code scope to verify in Phase 191. | L4 | DEC-003 | — |
| S4-DX-04 | MANUAL | §4 Data Cleaning | DX | Cancer Diagnosis — Unresolved Issues | L140 | - Unresolved Issues: (empty) | OUT-OF-SCOPE | NONE | — | Empty field. | L4 | — | — |
| S4-INS-01 | MANUAL | §4 Data Cleaning | INS | Insurance — Expected Structure | L142-L146 | Domain: Insurance<br>- Expected Structure:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | CONFIG; CODE | R/00_config.R: AMC_PAYER_LOOKUP L783-L848; PAYER_MAPPING L849+; R/60_tiered_same_day_payer.R | Config defines 8-category payer lookup (AMC framework); manual expected structure field is empty. | L2 | — | — |
| S4-INS-02 | MANUAL | §4 Data Cleaning | INS | Insurance — Observed Issues (missingness) | L148-L150 | - Observed Issues:<br>  - Large amount of missingness for Insurance | FILLED-NEEDS-CHECK | PLANNING-DOC | Phase 34-37 SUMMARYs | Missingness documented in Phases 34-37; pipeline handles via tiered hierarchy. | L2 | — | — |
| S4-INS-03 | MANUAL | §4 Data Cleaning | INS | Insurance — Cleaning Rules (6-tier hierarchy) | L152-L174 | - Cleaning Rules Applied:<br>  - Insurance was harmonized across all visits on a given day for a given individual based on the following hierarchy:<br>  1. Medicaid (incl. 93 and 14) or FLM source → Medicaid<br>  2. Medicare → Medicare<br>  3. Private (incl. Tricare) → Private<br>  4. Other → Other<br>  5. Self-pay or Uninsured → Uninsured<br>  6. All missing → missing (no change) | FILLED-NEEDS-CHECK | CODE; CONFIG | R/60_tiered_same_day_payer.R; R/00_config.R: AMC_PAYER_LOOKUP; PAYER_MAPPING | Manual lists 6 tiers; code implements 8-category AMC framework (includes Other govt). Tricare in Private tier matches manual rule 3. Medicaid codes 93 and 14 listed in config. FLM source rule in code. Tier count difference (6 vs 8) is a lead for Phase 191. | L2 | DEC-002 | — |
| S4-INS-04 | MANUAL | §4 Data Cleaning | INS | Insurance — Unresolved: Gerard to confirm code matches | L176-L178 | - Unresolved Issues:<br>  - Gerard to confirm code matches this. | FILLED-NEEDS-CHECK | CODE | R/60_tiered_same_day_payer.R | In-body confirm request; answered in Phase 191 (AM-VER-02). | L2 | — | Answered in Phase 191 with c1 (AM-VER-02) |
| S4-ADI-01 | MANUAL | §4 Data Cleaning | ADI | ADI — Expected Structure (9-digit zip) | L180-L184 | Domain: ADI<br>- Expected Structure:<br>  - Need 9-digit zip codes to get ADI | FILLED-NEEDS-CHECK | CODE; PLANNING-DOC | R/utils/utils_address.R: approximate_zip9(); Phase 139 SUMMARY; Phase 141 SUMMARY | Code implements zip9 approximation; manual states 9-digit zip needed for ADI — consistent with repo approach. | L5 | — | — |
| S4-ADI-02 | MANUAL | §4 Data Cleaning | ADI | ADI — Observed Issues (partial zip) | L186-L188 | - Observed Issues:<br>  - Some encounters only have 5-digit zip or no zip. | FILLED-NEEDS-CHECK | CODE; PLANNING-DOC | R/utils/utils_address.R; Phase 141 SUMMARY | Code handles 5-digit and missing zip cases. Consistent with observed issue in manual. | L5 | — | — |
| S4-ADI-03 | MANUAL | §4 Data Cleaning | ADI | ADI — Cleaning Rule 1: 5-digit matches 9-digit extrapolation | L190-L194 | - Cleaning Rules Applied:<br>  - If 5-digit zip in one encounter matches a 9-digit zip in another encounter, can extrapolate the 9-digit zip to the 5-digit zip encounter. | FILLED-NEEDS-CHECK | CODE; TEAM-DECISION | R/utils/utils_address.R: approximate_zip9(); MEETING-NOTES 2026-08-18 | Code implements this extrapolation rule. Decision confirmed by team (DEC-005). | L5 | DEC-005 | — |
| S4-ADI-04 | MANUAL | §4 Data Cleaning | ADI | ADI — Cleaning Rule 2: pop-weighted average fallback | L196-L199 | - For a particular encounter, if there is no 5- or 9-digit zip, we can take a 9-digit zip from another encounter or use the population-weighted average ADI of the 5-digit zip, whichever is closest in temporal proximity. | FILLED-NEEDS-CHECK | CODE; TEAM-DECISION | R/utils/utils_address.R; Phase 144 SUMMARY; Phase 148 SUMMARY | Pop-weighted average ADI for 5-digit zip is in code (Phase 144). Decision confirmed (DEC-004). | L5 | DEC-004 | — |
| S4-ADI-05 | MANUAL | §4 Data Cleaning | ADI | ADI — Cleaning Rule 3: non-matching 5-digit zip | L201-L203 | - If they have a 5-digit zip in another encounter that does not match a 9-digit zip, use the population-weighted average ADI of the 5-digit zip for the missing zip encounter. | FILLED-NEEDS-CHECK | CODE; TEAM-DECISION | R/utils/utils_address.R; Phase 149 SUMMARY | Code applies pop-weighted average when 5-digit does not match 9-digit. Consistent with manual rule. | L5 | DEC-004 | — |
| S4-ADI-06 | MANUAL | §4 Data Cleaning | ADI | ADI — Unresolved Issues | L205 | - Unresolved Issues: (empty) | OUT-OF-SCOPE | NONE | — | Empty field. | L5 | — | — |
| S4-TRT-01 | MANUAL | §4 Data Cleaning | TRT | Treatment Window — Expected Structure | L207-L211 | Domain: Treatment Window (in order to define survivorship)<br>- Expected Structure:<br>  - (empty) | EMPTY-NEEDS-TEAM | PLANNING-DOC | .planning/STATE.md parked items | End-of-treatment rules parked pending Sharon; episode windows (90/180-day) exist in code but treatment window definition awaits Sharon confirmation. | L8 | — | — |
| S4-TRT-02 | MANUAL | §4 Data Cleaning | TRT | Treatment Window — Observed Issues | L213-L215 | - Observed Issues:<br>  - How to establish? | EMPTY-NEEDS-TEAM | NONE | — | No repo answer; awaiting Sharon. | L8 | — | — |
| S4-TRT-03 | MANUAL | §4 Data Cleaning | TRT | Treatment Window — Cleaning Rules Applied | L217-L219 | - Cleaning Rules Applied:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | CODE; PLANNING-DOC | R/142_gantt_180_export.R; Phase 142 SUMMARY; Phase 164 SUMMARY | Episode windows (90-day and 180-day) implemented in Gantt code; end-of-treatment rule pending Sharon. | L8 | — | — |
| S4-TRT-04 | MANUAL | §4 Data Cleaning | TRT | Treatment Window — Unresolved Issues (pending Sharon) | L221-L223 | - Unresolved Issues:<br>  - Waiting to confirm with Sharon. | EMPTY-NEEDS-TEAM | MEETING-NOTES | TeamMtgNotes2026.md 2026-10-13 | Meeting notes confirm Sharon confirmation still pending as of 10/13/2026. | L8 | — | — |
| S4-REL-01 | MANUAL | §4 Data Cleaning | REL | Initial treatment vs relapse — Expected Structure | L225-L229 | Domain: Initial treatment vs. relapse<br>- Expected Structure:<br>  - (empty) | EMPTY-NEEDS-TEAM | PLANNING-DOC | .planning/STATE.md parked items | Parked pending Sharon episode return. | L8 | — | — |
| S4-REL-02 | MANUAL | §4 Data Cleaning | REL | Initial treatment vs relapse — Observed Issues | L231-L233 | - Observed Issues:<br>  - How to establish? | EMPTY-NEEDS-TEAM | NONE | — | No repo answer yet; awaiting Sharon chemo episodes. | L8 | — | — |
| S4-REL-03 | MANUAL | §4 Data Cleaning | REL | Initial treatment vs relapse — Cleaning Rules Applied | L235-L237 | - Cleaning Rules Applied:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | PLANNING-DOC; MEETING-NOTES | TeamMtgNotes2026.md 2026-09-11: relapse=90-day break; refractory=<90-day break; Phase 164 SUMMARY | PROVISIONAL. Relapse/refractory definitions decided by team (DEC-007): 90+ day break = relapse, <90 days = refractory. Code partially in episode-building scripts. | L8 | DEC-007 | PROVISIONAL |
| S4-REL-04 | MANUAL | §4 Data Cleaning | REL | Initial treatment vs relapse — Unresolved Issues | L239-L241 | - Unresolved Issues:<br>  - Waiting for Sharon to return chemo episodes. | EMPTY-NEEDS-TEAM | MEETING-NOTES | TeamMtgNotes2026.md 2026-10-13 | Still pending as of 10/13/2026 meeting notes. | L8 | — | — |
| S4-DTH-01 | MANUAL | §4 Data Cleaning | DTH | Death — Expected Structure | L243-L247 | Domain: Death<br>- Expected Structure:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | CODE | R/utils/utils_death.R: resolve_death_date() L51-L95 | PROVISIONAL. Expected structure not in manual; code implements death date resolution with source priority. | L6 | — | PROVISIONAL |
| S4-DTH-02 | MANUAL | §4 Data Cleaning | DTH | Death — Observed Issues | L249-L253 | - Observed Issues:<br>  - Cause of death unreliable/missing<br>  - Death date before last treatment encounter | FILLED-NEEDS-CHECK | CODE; PLANNING-DOC | R/utils/utils_death.R: resolve_death_date() L51-L95; Phase 62 SUMMARY; Phase 118 SUMMARY | Both issues addressed: death date resolution in utils_death.R; post-death encounter handling in Phase 62/118. | L6 | — | — |
| S4-DTH-03 | MANUAL | §4 Data Cleaning | DTH | Death — Cleaning Rule: 14-day prior rule | L255-L258 | - Cleaning Rules Applied:<br>  - If death date is 14 days prior to last treatment encounter, ignore death | FILLED-NEEDS-CHECK | CODE | R/utils/utils_death.R: resolve_death_date() L51-L95 grace_days parameter | Manual states 14 days; code default is grace_days=30L (line 51). This is a potential mismatch: manual says 14, code default is 30. Lead for Phase 191 L6. | L6 | — | Potential mismatch: manual=14 days, code default=30 days grace |
| S4-DTH-04 | MANUAL | §4 Data Cleaning | DTH | Death — Cleaning Rule: do not use cause of death | L260-L262 | - Do not use Cause of Death<br>  1. Do not use NHL as cause of death to exclude patients | FILLED-NEEDS-CHECK | CODE; PLANNING-DOC | R/utils/utils_death.R; Phase 119 SUMMARY | Code does not use DEATH_CAUSE for exclusion; NHL death flag documented in Phase 119 as not used for exclusion. Consistent with manual. | L6 | — | — |
| S4-DTH-05 | MANUAL | §4 Data Cleaning | DTH | Death — Unresolved Issues | L264-L266 | - Unresolved Issues:<br>  - (empty) | OUT-OF-SCOPE | NONE | — | Empty field. | L6 | — | — |
| S4-SRV-01 | MANUAL | §4 Data Cleaning | SRV | Survivorship encounters — Expected Structure | L268-L272 | Domain: Survivorship encounters<br>- Expected Structure:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | CODE; PLANNING-DOC | R/utils/utils_surveillance.R; R/147_surveillance_modality_frequency.R; Phase 158-160 SUMMARYs | PROVISIONAL. Surveillance encounter codeset now in repo; expected structure not written in manual. | L9 | — | PROVISIONAL |
| S4-SRV-02 | MANUAL | §4 Data Cleaning | SRV | Survivorship encounters — Observed Issues | L274-L276 | - Observed Issues:<br>  - (empty) | OUT-OF-SCOPE | NONE | — | Empty field. | L9 | — | — |
| S4-SRV-03 | MANUAL | §4 Data Cleaning | SRV | Survivorship encounters — Cleaning Rules Applied | L278-L280 | - Cleaning Rules Applied:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | CODE; PLANNING-DOC | R/utils/utils_surveillance.R; VariableDetails.xlsx Surveillance Strategy sheet; Phase 184 SUMMARY; Phase 185 SUMMARY | PROVISIONAL. Modality-level rates implemented in Phase 184-186; cleaning rules not written in manual. | L9 | — | PROVISIONAL |
| S4-SRV-04 | MANUAL | §4 Data Cleaning | SRV | Survivorship — Unresolved: VariableDetails needs completion | L282-L284 | - Unresolved Issues:<br>  - Variabledetails.xlsx file needs to be completed | EMPTY-NEEDS-TEAM | NONE | — | VariableDetails.xlsx provided in docs/analytic_manual/ but Surveillance Strategy sheet completion depends on team. | L9 | — | — |
| S4-SRV-05 | MANUAL | §4 Data Cleaning | SRV | Survivorship — Unresolved: need treatment windows first | L286 | - Need to define treatment windows first. | EMPTY-NEEDS-TEAM | NONE | — | Blocked on treatment window definition (pending Sharon, same as S4-TRT-04). | L9 | — | — |
| S4-DIST-01 | MANUAL | §4 Data Cleaning | DIST | Distance — Expected Structure | L288-L292 | Domain: Distance from patient to encounter location<br>- Expected Structure:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | CODE; PLANNING-DOC | R/122_encounter_distance.R: haversine_km(); Phase 152 SUMMARY | PROVISIONAL. Distance calculation implemented; expected structure not in manual. | L7 | — | PROVISIONAL |
| S4-DIST-02 | MANUAL | §4 Data Cleaning | DIST | Distance — Observed Issues | L294-L296 | - Observed Issues:<br>  - (empty) | OUT-OF-SCOPE | NONE | — | Empty field. | L7 | — | — |
| S4-DIST-03 | MANUAL | §4 Data Cleaning | DIST | Distance — Cleaning Rule 1: zipcodeR package | L298-L301 | - Cleaning Rules Applied:<br>  - Using the zipcodeR package to calculate distance between patient zip and encounter location zip. | FILLED-NEEDS-CHECK | CODE; PLANNING-DOC | R/122_encounter_distance.R; Phase 165 SUMMARY; Phase 182 SUMMARY | Manual cites zipcodeR; Phase 182.1 SUMMARY notes a potential shift to haversine_km() with ZCTA crosswalk. Method difference is a lead for Phase 191 L7. | L7 | — | Potential method mismatch: manual=zipcodeR, repo may use haversine with ZCTA crosswalk |
| S4-DIST-04 | MANUAL | §4 Data Cleaning | DIST | Distance — Cleaning Rule 2: 9-digit → 5-digit | L303 | - If 9-digit zip, take 5-digit zip from that. | FILLED-NEEDS-CHECK | CODE | R/122_encounter_distance.R; R/utils/utils_facility_zip.R | Code extracts 5-digit from 9-digit zip. Consistent with manual rule. | L7 | — | — |
| S4-DIST-05 | MANUAL | §4 Data Cleaning | DIST | Distance — Cleaning Rule 3: temporally closest zip fallback | L305-L306 | - For a particular encounter, if there is no 5- or 9-digit zip, take temporally closest 5 or 9-digit zip. | FILLED-NEEDS-CHECK | CODE | R/122_encounter_distance.R; R/utils/utils_zip_crosswalk.R | Temporally closest zip fallback implemented in distance scripts. Consistent with manual. | L7 | — | — |
| S4-DIST-06 | MANUAL | §4 Data Cleaning | DIST | Distance — Unresolved Issues (binary cutoff) | L308-L312 | - Unresolved Issues:<br>  - Should consider binary option, in which case, what to use for cutoff? 120mi (two hours travel time) or 200mi? Potentially do sensitivity analysis or include both in MICE. | FILLED-NEEDS-CHECK | CODE; TEAM-DECISION; MEETING-NOTES | R/00_config.R: far_from_care_cutoff_mi; TeamMtgNotes2026.md 2026-10-13: decided 100 miles | Manual shows uncertainty about 120 vs 200 mi; team decided 100 miles based on doi.org/10.1182/blood-2023-182477 (10/13/2026 meeting). Code uses CONFIG$far_from_care_cutoff_mi. Manual is out of date. | L7 | DEC-008 | — |
| S5-REC-01 | MANUAL | §5 Reconciliation | REC | EHR authoritative variables | L314-L318 | ## 5. Cross-System Reconciliation (EHR vs Claims)<br>- Variables where EHR is authoritative:<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | No team decision recorded; Claims integration not started. | — | — | — |
| S5-REC-02 | MANUAL | §5 Reconciliation | REC | Claims authoritative variables | L320-L322 | - Variables where Claims is authoritative:<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | No team decision recorded. | — | — | — |
| S5-REC-03 | MANUAL | §5 Reconciliation | REC | Concordance Checks Performed | L324-L326 | - Concordance Checks Performed:<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | No concordance checks performed yet. | — | — | — |
| S5-REC-04 | MANUAL | §5 Reconciliation | REC | Precedence Rules for Conflicts | L328-L330 | - Precedence Rules for Conflicts:<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | No precedence rules recorded. | — | — | — |
| S5-REC-05 | MANUAL | §5 Reconciliation | REC | Sensitivity Analyses Planned | L332-L334 | - Sensitivity Analyses Planned:<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | No sensitivity analyses recorded. | — | — | — |
| S6-QA-01 | MANUAL | §6 QA Checklist | QA | Date logic checks | L336-L338 | ## 6. Quality Assurance and Validation Checklist<br>- [ ] Date logic checks completed | OUT-OF-SCOPE | NONE | — | Sign-off checkbox; no repo source. | — | — | — |
| S6-QA-02 | MANUAL | §6 QA Checklist | QA | Distribution checks | L340 | - [ ] Distribution checks completed | OUT-OF-SCOPE | NONE | — | Sign-off checkbox. | — | — | — |
| S6-QA-03 | MANUAL | §6 QA Checklist | QA | Cross-source validation | L342 | - [ ] Cross-source validation completed | OUT-OF-SCOPE | NONE | — | Sign-off checkbox. | — | — | — |
| S6-QA-04 | MANUAL | §6 QA Checklist | QA | Masters biostatistician sign-off | L344 | - [ ] Masters biostatistician sign-off | OUT-OF-SCOPE | NONE | — | Sign-off checkbox. | — | — | — |
| S6-QA-05 | MANUAL | §6 QA Checklist | QA | PhD biostatistician sign-off | L346 | - [ ] PhD biostatistician sign-off | OUT-OF-SCOPE | NONE | — | Sign-off checkbox. | — | — | — |
| S6-QA-06 | MANUAL | §6 QA Checklist | QA | MPI sign-off | L348 | - [ ] MPI sign-off | OUT-OF-SCOPE | NONE | — | Sign-off checkbox. | — | — | — |
| S6-QA-07 | MANUAL | §6 QA Checklist | QA | QA Notes field | L350 | Notes: | OUT-OF-SCOPE | NONE | — | Empty notes field. | — | — | — |
| S7-TRK-01 | MANUAL | §7 Status Tracker | TRK | Aim 1: treatment | L352-L356 | ## 7. Analysis Status Tracker<br>\| Aim 1: treatment \| \| \| \| | EMPTY-REPO-CAN-ANSWER | PLANNING-DOC | .planning/STATE.md; Phase 61 SUMMARY; Phase 164 SUMMARY | PROVISIONAL. Treatment analysis in progress per STATE.md; no completed status yet. | — | — | PROVISIONAL |
| S7-TRK-02 | MANUAL | §7 Status Tracker | TRK | Aim 2: survivorship care | L357 | \| Aim 2: survivorship care \| \| \| \| | EMPTY-REPO-CAN-ANSWER | PLANNING-DOC | Phase 147 SUMMARY; Phase 158-160 SUMMARYs; Phase 184-186 SUMMARYs | PROVISIONAL. Survivorship modality work largely complete per recent phases. | — | — | PROVISIONAL |
| S7-TRK-03 | MANUAL | §7 Status Tracker | TRK | Rad onc subgroup analysis | L358-L359 | \| Rad onc subgroup analysis \| \| \| Have provider id specialty type so we should be able to see if a rad onc was the provider listed for a specific encounter... \| | EMPTY-REPO-CAN-ANSWER | PLANNING-DOC | STATE.md; Phase 61 SUMMARY | PROVISIONAL. Note in manual describes planned approach using provider specialty; not yet implemented. | — | — | PROVISIONAL |
| S8-PRK-01 | MANUAL | §8 Open Questions | PRK | Questions requiring MPI input | L361-L365 | ## 8. Open Questions and Decision Parking Lot<br>- Questions requiring MPI input:<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | No questions filed; parking lot empty. | — | — | — |
| S8-PRK-02 | MANUAL | §8 Open Questions | PRK | Deferred decisions | L367-L369 | - Deferred decisions:<br>  - (empty) | EMPTY-REPO-CAN-ANSWER | PLANNING-DOC | .planning/STATE.md parked items | PROVISIONAL. STATE.md lists parked items (treatment windows, data completeness check, D-15, D-165-01). | — | — | PROVISIONAL |
| S8-PRK-03 | MANUAL | §8 Open Questions | PRK | Known limitations for manuscripts | L371-L373 | - Known limitations to document for manuscripts:<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | Not yet populated. | — | — | — |
| S9-GUI-01 | MANUAL | §9 Guidance | GUI | Purpose statement | L375-L379 | ## 9. How to Use This Living Analytic Manual (Team Guidance)<br>Purpose: This document is intended to be a living record... | OUT-OF-SCOPE | NONE | — | Guidance text; no repo source. | — | — | — |
| S9-GUI-02 | MANUAL | §9 Guidance | GUI | Update cadence | L381-L389 | Update cadence: Weekly / Monthly / Milestones | OUT-OF-SCOPE | NONE | — | Guidance text; no repo source. | — | — | — |
| S9-GUI-03 | MANUAL | §9 Guidance | GUI | Team roles and responsibilities | L391-L400 | Team roles and responsibilities: Masters / PhD / MPIs | OUT-OF-SCOPE | NONE | — | Guidance text; no repo source. | — | — | — |
| S9-GUI-04 | MANUAL | §9 Guidance | GUI | Versioning guidance | L402-L407 | Versioning guidance: update Front Matter / do not delete prior decisions | OUT-OF-SCOPE | NONE | — | Guidance text; no repo source. | — | — | — |
| S10-OPT-01 | MANUAL | §10 Optional | OPT | Decision Log Spreadsheet | L409-L415 | ## 10. Optional Enhancements and Companion Materials<br>- Decision Log Spreadsheet | OUT-OF-SCOPE | NONE | — | Guidance text. | — | — | — |
| S10-OPT-02 | MANUAL | §10 Optional | OPT | Companion SOP | L417-L418 | - Companion SOP: One-page guide | OUT-OF-SCOPE | NONE | — | Guidance text; SOP appears in Appendix B. | — | — | — |
| S10-OPT-03 | MANUAL | §10 Optional | OPT | Code Repository Crosswalk | L420-L421 | - Code Repository Crosswalk: Link analytic versions to Git commits or dataset ids | OUT-OF-SCOPE | NONE | — | Guidance text. | — | — | — |
| S10-OPT-04 | MANUAL | §10 Optional | OPT | SAP Cross-Reference Table | L423-L427 | - SAP Cross-Reference Table: Map finalized analytic decisions to the Statistical Analysis Plan | OUT-OF-SCOPE | NONE | — | Guidance text. | — | — | — |
| S11-LIM-01 | MANUAL | §11 Limitations | LIM | EHR capture limitations | L429-L436 | ## 11. Known Data Limitations and Implications<br>- Limitations related to EHR capture (e.g., care outside system):<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | Not yet populated by team. | — | — | — |
| S11-LIM-02 | MANUAL | §11 Limitations | LIM | Claims completeness limitations | L438-L440 | - Limitations related to claims completeness or lag:<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | Not yet populated. | — | — | — |
| S11-LIM-03 | MANUAL | §11 Limitations | LIM | Measurement error limitations | L442-L444 | - Measurement error or under-capture for key variables:<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | Not yet populated. | — | — | — |
| S11-LIM-04 | MANUAL | §11 Limitations | LIM | Underrepresented populations | L446-L448 | - Populations or settings underrepresented in the data:<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | Not yet populated. | — | — | — |
| S11-LIM-05 | MANUAL | §11 Limitations | LIM | Potential bias introduced | L450-L454 | Implications for Analysis and Interpretation:<br>- Potential bias introduced:<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | Not yet populated. | — | — | — |
| S11-LIM-06 | MANUAL | §11 Limitations | LIM | Analyses most affected | L456-L458 | - Analyses most affected:<br>  - (empty) | EMPTY-NEEDS-TEAM | NONE | — | Not yet populated. | — | — | — |
| S11-LIM-07 | MANUAL | §11 Limitations | LIM | Planned sensitivity or mitigation strategies | L460-L465 | - Planned sensitivity or mitigation strategies:<br>  - (empty)<br>This section should directly inform manuscript limitations sections and reviewer responses. | EMPTY-NEEDS-TEAM | NONE | — | Not yet populated. | — | — | — |
| SA1-LOG-01 | MANUAL | Appendix A1 | LOG | A1 Data Ingest table | L467-L477 | ## APPENDIX A. Embedded Working Tables<br>A1. Data Ingest & Change Log \| Date \| Data Source \| Description of Change \| Impact \| Action Taken \| (empty rows) | OUT-OF-SCOPE | NONE | — | Mirrors S1-LOG-01; empty working table for team use. | — | — | mirrors S1-LOG-01 |
| SA2-COH-01 | MANUAL | Appendix A2 | COH | A2 Cohort Definition History | L479-L486 | A2. Cohort Definition History \| Version \| Date \| Change Description \| Rationale \| Approved By \| (empty rows) | OUT-OF-SCOPE | NONE | — | Mirrors S2-COH-05; empty working table. | — | — | mirrors S2-COH-05 |
| SA3-DEC-01 | MANUAL | Appendix A3 | DEC | A3 Variable & Phenotype Decision Log | L488-L496 | A3. Variable & Phenotype Decision Log (empty rows) | OUT-OF-SCOPE | NONE | — | Mirrors S3-DEC-01; empty working table. | — | — | mirrors S3-DEC-01 |
| SA4-TRK-01 | MANUAL | Appendix A4 | TRK | A4 Analysis Status Tracker | L498-L505 | A4. Analysis Status Tracker \| Aim / Analysis \| Dataset Version \| Status \| Owner \| Notes \| (empty rows) | OUT-OF-SCOPE | NONE | — | Mirrors S7-TRK-01/02/03; empty working table. | — | — | mirrors S7-TRK-01; S7-TRK-02; S7-TRK-03 |
| SB-SOP-01 | MANUAL | Appendix B | SOP | SOP Purpose | L507-L513 | ## APPENDIX B. One-Page SOP: Using the Analytic Manual<br>**Purpose**<br>The living Analytic Manual (AM) serves as the authoritative, ongoing record... | OUT-OF-SCOPE | NONE | — | Guidance boilerplate; mirrors §9 content. | — | — | — |
| SB-SOP-02 | MANUAL | Appendix B | SOP | SOP When to update | L515-L524 | **When to update** Weekly / Monthly / Milestones | OUT-OF-SCOPE | NONE | — | Guidance text; mirrors §9 cadence. | — | — | — |
| SB-SOP-03 | MANUAL | Appendix B | SOP | SOP Who updates what | L526-L535 | **Who updates what** MS / PhD / MPIs | OUT-OF-SCOPE | NONE | — | Guidance text; mirrors §9 roles. | — | — | — |
| SB-SOP-04 | MANUAL | Appendix B | SOP | SOP Documentation rules | L537-L544 | **Documentation rules** Do not delete / tie to versions / concise language | OUT-OF-SCOPE | NONE | — | Guidance text. | — | — | — |
| SB-SOP-05 | MANUAL | Appendix B | SOP | SOP Why this matters | L546-L550 | **Why this matters** Maintaining the AM ensures analytic transparency, reproducibility... | OUT-OF-SCOPE | NONE | — | Guidance text. | — | — | — |

---

## AM-MAP-02: Repo Domains Not in Manual

| ID | Origin | AM Section | Domain | Item | Manual Lines | Manual Text | Status | Evidence Type | Repo Source | What the Source Shows | Lead | Decision ID | Notes |
|----|--------|------------|--------|------|--------------|-------------|--------|---------------|-------------|----------------------|------|-------------|-------|
| S4-SHS-01 | REPO-ONLY | §4 (repo-only) | SHS | Single-health-system care flag | — | — | EMPTY-REPO-CAN-ANSWER | CODE | R/169_single_source_care.R: build_single_source_result() L48-L90; single_source_care and single_source_care_post columns in output/internal/ | Function reads ENCOUNTER.SOURCE; flags patients where all care (and all post-treatment care) came from one institution. Not in AM §4 yet. | L1 | — | Not yet in manual; discussed in 10/13/2026 meeting as a to-do item |
| S4-CHM-01 | REPO-ONLY | §4 (repo-only) | CHM | Chemo detection across PRESCRIBING/MED_ADMIN/DISPENSING with NDC→RxNorm | — | — | EMPTY-REPO-CAN-ANSWER | CODE; PLANNING-DOC | R/utils/utils_treatment.R: get_chemo_hits(); Phase 122 SUMMARY; Phase 123 SUMMARY; Phase 124 SUMMARY | Code detects chemo across all three PCORnet medication tables; NDC→RxNorm mapping applied. Phase 122 fixed MED_ADMIN/DISPENSING RxNorm_CUI mismatch (+1,139 patients). Not in manual. | — | — | Phase 122 was a critical bug fix not reflected in manual |
| S4-NRM-01 | REPO-ONLY | §4 (repo-only) | NRM | Drug-name normalization (brand→generic; Doxorubicin incl. liposomal; Vinblastine) | — | — | EMPTY-REPO-CAN-ANSWER | CODE; PLANNING-DOC | MEDICATION_LOOKUP in R/00_config.R or utils_xlsx_lookups.R; Phase 114 SUMMARY; Phase 164 SUMMARY | Brand-to-generic normalization (adriamycin→doxorubicin) implemented; liposomal form handling included. Decided by team (DEC-011). Not in manual. | — | DEC-011 | Not in manual; normalization is a prerequisite for regimen detection |
| S4-REG-01 | REPO-ONLY | §4 (repo-only) | REG | First-line regimens (ABVD, BV+AVD, Nivo+AVD) | — | — | EMPTY-REPO-CAN-ANSWER | PLANNING-DOC | Phase 61 SUMMARY; TeamMtgNotes2026.md 2026-05-29 section on first-line regimens | PROVISIONAL. Regimen detection discussed in meeting notes and Phase 61; code implementation to verify in Phase 191. Not in manual §4. | — | — | PROVISIONAL: regimen definitions discussed in meetings; code to verify |
| S4-EPI-01 | REPO-ONLY | §4 (repo-only) | EPI | Treatment episodes (90-day and 180-day Gantt windows) | — | — | EMPTY-REPO-CAN-ANSWER | CODE; PLANNING-DOC | R/142_gantt_180_export.R; Phase 142 SUMMARY; Phase 164 SUMMARY | Two episode window sizes implemented (90-day and 180-day); Gantt export used for Sharon chemo review. Not explicitly in manual §4 as a cleaning rule. | L8 | — | Partially overlaps S4-TRT-03; episode logic is the foundation for treatment window |
| S4-ANT-01 | REPO-ONLY | §4 (repo-only) | ANT | Anthracycline exposure (any anthracycline; time since last anthracycline) | — | — | EMPTY-REPO-CAN-ANSWER | CODE; PLANNING-DOC | R/utils/utils_anthracycline_echo.R; Phase 166 SUMMARY; Phase 187 SUMMARY; Phase 188 SUMMARY | Anthracycline exposure flag and time-since-last-anthracycline variable built in Phase 187; echo rate since last anthracycline computed in Phase 188 (rate=0.2501/py). Not in manual. | — | — | Phase 187/188 outputs in output/internal/ |
| S4-CBC-01 | REPO-ONLY | §4 (repo-only) | CBC | CBC definition (WBC 6690-2 + Hgb 718-7 + PLT 777-3 same date) | — | — | EMPTY-REPO-CAN-ANSWER | CODE | R/utils/utils_distance_cbc.R: build_cbc_events(); Phase 165 SUMMARY | Function requires WBC, hemoglobin, and platelet LOINC codes on the same date to qualify as a CBC encounter. Not in manual. | — | — | Specific LOINC codes: WBC=6690-2, Hgb=718-7, PLT=777-3 |
| S4-RUR-01 | REPO-ONLY | §4 (repo-only) | RUR | Rurality (RUCA preferred, RUCC fallback) | — | — | EMPTY-REPO-CAN-ANSWER | CODE; PLANNING-DOC; MEETING-NOTES | Phase 116 SUMMARY; TeamMtgNotes2026.md 2026-07-07: RUCA can use 5-digit zip; MEETING-NOTES 2026-08-18 | RUCA uses 5-digit zip (confirmed by team, DEC-006); RUCC as fallback. Code in Phase 116. Not in manual §4. | — | DEC-006 | Team decision DEC-006: RUCA uses 5-digit ZIP |
| S4-SDI-01 | REPO-ONLY | §4 (repo-only) | SDI | Social Deprivation Index where only ZIP5 exists | — | — | EMPTY-REPO-CAN-ANSWER | PLANNING-DOC | Phase 144 SUMMARY | PROVISIONAL. SDI at county or 5-digit ZIP level used when 9-digit unavailable; code in Phase 144. Not in manual §4. | — | — | PROVISIONAL |
| S4-DOI-01 | REPO-ONLY | §4 (repo-only) | DOI | Rituximab/methotrexate diagnoses of interest | — | — | EMPTY-REPO-CAN-ANSWER | CODE | R/utils/utils_doi.R: DOI_CODE_MAP; Phase 127 SUMMARY; Phase 128 SUMMARY; Phase 129 SUMMARY; Phase 130 SUMMARY | DOI code map implemented for Rituximab and Methotrexate-associated diagnoses; used for NHL classification and DOI flag. Not in manual. | — | — | Relevant to HL vs NHL classification |
| S4-CLS-01 | REPO-ONLY | §4 (repo-only) | CLS | HL vs NHL classification | — | — | EMPTY-REPO-CAN-ANSWER | CODE; PLANNING-DOC | R/utils/utils_cancer.R; Phase 87 SUMMARY; Phase 105 SUMMARY | HL/NHL classification uses ICD codes and episode context; cross-references S4-DX rows. Not explicitly described in manual §4 as a separate domain. | L4 | DEC-009; DEC-010 | Cross-references S4-DX-02 and S4-DX-03 |
| S4-PDE-01 | REPO-ONLY | §4 (repo-only) | PDE | Post-death encounters | — | — | EMPTY-REPO-CAN-ANSWER | CODE; PLANNING-DOC | R/utils/utils_death.R: resolve_death_date(); Phase 62 SUMMARY; Phase 113 SUMMARY | Code identifies and flags encounters after death date; handling described in Phase 62/113. Related to S4-DTH-02 but a separate repo domain not in manual §4. | L6 | — | 258 patients had post-death encounters per 07/01/2026 meeting notes |

---

## AM-MAP-03: Team Decisions

| Decision ID | Original ID | Decision Text | Raised By | Decided By | Date | Source File | Map Row(s) | Status | Notes |
|-------------|-------------|---------------|-----------|------------|------|-------------|------------|--------|-------|
| DEC-001 | D-190-01 | Location of the OneFLquestions document referenced in c0 | Amy (comment c0) | — | 2026-10-27 | 190-CONTEXT.md D-10 | S4-CMNT-01 | OPEN | Interim: c0 BLOCKED; Phases 191-192 proceed without it; Phase 194 follows up |
| DEC-002 | — | Insurance harmonization hierarchy confirmed (6-tier: Medicaid incl. 93/14/FLM > Medicare > Private incl. Tricare > Other > Uninsured > Missing) | Amy | Amy; Gerard | 2026-05-01 | TeamMtgNotes2026.md 05/01/2026 | S4-INS-03 | CONFIRMED | Code implements 8-category AMC framework; manual states 6 tiers; difference is a Phase 191 lead |
| DEC-003 | — | Two separate encounters with a diagnosis of the same cancer type at least 7 days apart; applies to all cancer types | Amy; Ray | Amy; Ray; Gerard | 2026-05-29 | TeamMtgNotes2026.md 05/29/2026 | S4-DX-03 | CONFIRMED | — |
| DEC-004 | — | ADI: use population-weighted average of 5-digit zip code when 9-digit is unavailable | Amy; Gerard | Amy; Gerard | 2026-08-25 | TeamMtgNotes2026.md 08/25/2026 | S4-ADI-04; S4-ADI-05 | CONFIRMED | 8/25 GG and AC met and determined method |
| DEC-005 | — | ADI: if 5-digit zip in one encounter matches 9-digit zip in another encounter, extrapolate 9-digit to 5-digit | Amy; Gerard | Amy; Gerard | 2026-08-18 | TeamMtgNotes2026.md 08/18/2026 | S4-ADI-03 | CONFIRMED | Team comfortable after confirming zips are consistent longitudinally |
| DEC-006 | — | RUCA rurality: can use 5-digit zip code | Amy; Gerard | Amy; Gerard | 2026-08-25 | TeamMtgNotes2026.md 08/25/2026 | S4-RUR-01 | CONFIRMED | — |
| DEC-007 | — | Relapse defined as change in tx regimen with 90+ day break from stop of initial tx to start of second line; refractory defined as change in regimen with <90-day break | Amy; Ray; Erin; Sharon | Amy; Ray; Erin | 2026-09-11 | TeamMtgNotes2026.md 09/11/2026 | S4-REL-03 | CONFIRMED | Decided to think of relapse and refractory as two separate concepts |
| DEC-008 | — | Distance cutoff: 100 miles based on doi.org/10.1182/blood-2023-182477 | Erin; Ray | Erin; Ray | 2026-10-13 | TeamMtgNotes2026.md 10/13/2026 | S4-DIST-06 | CONFIRMED | Supersedes earlier uncertainty between 120mi and 200mi options |
| DEC-009 | — | Patients with multiple lines of tx that are clearly NHL only will be removed from the dataset | Amy; Erin; Ray | Amy; Erin; Ray | 2026-09-22 | TeamMtgNotes2026.md 09/22/2026 | S2-COH-02; S4-CLS-01 | CONFIRMED | — |
| DEC-010 | — | Err on the side of including patients who may not be a true HL if the information is not definite | Amy; Erin; Ray | Amy; Erin; Ray | 2026-09-22 | TeamMtgNotes2026.md 09/22/2026 | S4-DX-02; S4-CLS-01 | CONFIRMED | — |
| DEC-011 | — | Convert all brand names to generic (adriamycin → doxorubicin) | Amy; Gerard | Amy; Gerard | 2026-10-13 | TeamMtgNotes2026.md 10/13/2026 | S4-NRM-01 | CONFIRMED | Completed per 10/13/2026 meeting notes |
| DEC-012 | — | Remove diagnosis table data from surveillance modality codes for survivorship care | Amy; Gerard | Amy; Gerard | 2026-10-13 | TeamMtgNotes2026.md 10/13/2026 | S4-SRV-03 | CONFIRMED | Completed per 10/13/2026 meeting notes |

### Unattributed candidates (not counted)

- TeamMtgNotes2026.md 06/23/2026: 90-day episode window definition; source: Erin/Ray/Amy but decision framing unclear — may be refractory/relapse precursor to DEC-007
- TeamMtgNotes2026.md 05/05/2026: inclusion of brentuximab single agent as potentially first-line; no clear named decision-maker; overlaps DEC-003 scope

---

## Coverage

| Line Reference | Reason | Notes |
|----------------|--------|-------|
| L3 | Section heading already represented by S0-FM-01 | §0 heading; content captured across S0-FM-01 through S0-FM-09 |
| L34 | Table separator row (markdown \|---|----\|) | Formatting line in §1 table; not a content line |
| L40 | Section heading already represented by S2-COH-05 | §2 heading; content captured in S2-COH-01 through S2-COH-05 |
| L63 | Table separator row | Formatting line in §2.2 table |
| L75 | Table separator row | Formatting line in §3 table |
| L87 | Empty bullet under Expected Structure | Blank placeholder; content captured in S4-DXDT-01 row |
| L109 | Empty bullet under Expected Structure | Blank placeholder; captured in S4-SRC-01 |
| L119 | Empty bullet under Cleaning Rules Applied | Blank placeholder; captured in S4-SRC-03 |
| L146 | Empty bullet under Expected Structure | Blank placeholder; captured in S4-INS-01 |
| L211 | Empty bullet under Expected Structure | Blank placeholder; captured in S4-TRT-01 |
| L219 | Empty bullet under Cleaning Rules Applied | Blank placeholder; captured in S4-TRT-03 |
| L229 | Empty bullet under Expected Structure | Blank placeholder; captured in S4-REL-01 |
| L237 | Empty bullet under Cleaning Rules Applied | Blank placeholder; captured in S4-REL-03 |
| L247 | Empty bullet under Expected Structure | Blank placeholder; captured in S4-DTH-01 |
| L266 | Empty dash under Unresolved Issues | Blank placeholder; captured in S4-DTH-05 |
| L272 | Empty bullet under Expected Structure | Blank placeholder; captured in S4-SRV-01 |
| L276 | Empty dash under Observed Issues | Blank placeholder; captured in S4-SRV-02 |
| L280 | Empty dash under Cleaning Rules Applied | Blank placeholder; captured in S4-SRV-03 |
| L292 | Empty bullet under Expected Structure | Blank placeholder; captured in S4-DIST-01 |
| L296 | Empty dash under Observed Issues | Blank placeholder; captured in S4-DIST-02 |
| L318 | Empty bullet under EHR authoritative | Blank placeholder; captured in S5-REC-01 |
| L322 | Empty bullet under Claims authoritative | Blank placeholder; captured in S5-REC-02 |
| L326 | Empty bullet under Concordance | Blank placeholder; captured in S5-REC-03 |
| L330 | Empty bullet under Precedence | Blank placeholder; captured in S5-REC-04 |
| L334 | Empty bullet under Sensitivity Analyses | Blank placeholder; captured in S5-REC-05 |
| L355 | Table separator row | Formatting line in §7 table |
| L359 | Empty row in §7 table | Blank table row; §7 content captured in S7-TRK-01/02/03 |
| L365 | Empty bullet under MPI input | Blank placeholder; captured in S8-PRK-01 |
| L369 | Empty bullet under Deferred decisions | Blank placeholder; captured in S8-PRK-02 |
| L373 | Empty bullet under Known limitations | Blank placeholder; captured in S8-PRK-03 |
| L436 | Empty bullet under EHR limitations | Blank placeholder; captured in S11-LIM-01 |
| L440 | Empty bullet under Claims limitations | Blank placeholder; captured in S11-LIM-02 |
| L444 | Empty bullet under Measurement error | Blank placeholder; captured in S11-LIM-03 |
| L448 | Empty bullet under Populations | Blank placeholder; captured in S11-LIM-04 |
| L454 | Empty bullet under Potential bias | Blank placeholder; captured in S11-LIM-05 |
| L458 | Empty bullet under Analyses affected | Blank placeholder; captured in S11-LIM-06 |
| L462 | Empty bullet under Mitigation strategies | Blank placeholder; captured in S11-LIM-07 |
| L472 | Table separator row | Formatting line in A1 table |
| L473-L477 | Empty rows in A1 table | Blank rows; content of A1 table captured in SA1-LOG-01 |
| L482 | Table separator row | Formatting line in A2 table |
| L483-L486 | Empty rows in A2 table | Blank rows; content captured in SA2-COH-01 |
| L491 | Table separator row | Formatting line in A3 table |
| L492-L496 | Empty rows in A3 table | Blank rows; content captured in SA3-DEC-01 |
| L501 | Table separator row | Formatting line in A4 table |
| L502-L505 | Empty rows in A4 table | Blank rows; content captured in SA4-TRK-01 |

### Comment anchors (from word/comments.xml)

| Comment | Author | Date | Text | Anchor (from XML) | Manual Lines |
|---------|--------|------|------|-------------------|--------------|
| c0 (S4-CMNT-01) | Crisp, Amy | 2026-10-23T13:35:00Z | Reference OneFLquestions document to ensure everything has made it into here. | Data Cleaning and Harmonization Rules (§4 heading) | L81 |
| c1 (S4-CMNT-02) | Crisp, Amy | 2026-10-23T13:31:00Z | Gerard to confirm this is what's in the code. | Use diagnosis date from Tumor Registry as default.<br>If no diagnosis date: use first date with HL diagnosis code | L95-L101 |
