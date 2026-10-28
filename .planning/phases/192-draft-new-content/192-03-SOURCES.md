# 192-03 Source Confirmation

Prepared: 2026-10-28
Scope: All EMPTY-REPO-CAN-ANSWER IDs in existing §4 domains and all 12 AM-MAP-02 repo-only domain IDs.
Evidence precedence follows 192-CONTEXT D-22.

---

## Existing-domain EMPTY-REPO-CAN-ANSWER items

From AM-EVIDENCE-MAP.md AM Main Map, items with Status = EMPTY-REPO-CAN-ANSWER that are in §4 domains:

| Map ID | Statement to draft | Source opened | What the source shows |
|--------|-------------------|---------------|----------------------|
| S4-DXDT-01 | Expected structure of cancer diagnosis date | R/utils/utils_treatment.R:get_hl_any_dx_ids() | Function reads DIAGNOSIS table; anchor date = min DX_DATE (ADMIT_DATE fallback) filtered to C81.x / 201.x. |
| S4-SRC-01 | Expected structure of ENCOUNTER.SOURCE | R/169_single_source_care.R:build_single_source_result():L48-L90 | Function reads ENCOUNTER.SOURCE; partner sites AMS, UMI, FLM, VRT, UFH implied by build_single_source_result() output columns. |
| S4-SRC-03 | Cleaning rules for SOURCE | R/169_single_source_care.R:build_single_source_result():L48-L90 | NULLIF(UPPER(TRIM(SOURCE)), '') used (confirmed by SQL CTE at L127-L160 of R/169); single_source_care derived from ENCOUNTER.SOURCE only. |
| S4-INS-01 | Expected structure of payer fields | R/00_config.R:AMC_PAYER_LOOKUP (L783+); R/60_tiered_same_day_payer.R:resolve_same_day_payer() | PAYER_TYPE_PRIMARY and PAYER_TYPE_SECONDARY in ENCOUNTER; 8-category AMC framework defined in config. |
| S4-DTH-01 | Expected structure of death data | R/utils/utils_death.R:resolve_death_date():L51-L95 | Function reads DEATH table; source-priority rule resolves multiple death records; post_death_activity_days column flags post-death encounters. |
| S4-SRV-01 | Expected structure of survivorship encounters | R/utils/utils_surveillance.R:classify_surveillance_encounter() | Encounter classification by modality codes from VariableDetails.xlsx Surveillance Strategy sheet. |
| S4-SRV-03 | Cleaning rules for survivorship encounters | R/utils/utils_surveillance.R:classify_surveillance_encounter(); DEC-012 | Diagnosis table data excluded from modality classification; only PROCEDURES, PRESCRIBING, and lab codes qualify (DEC-012 confirmed 2026-10-13). |
| S4-TRT-03 | Cleaning rules for treatment window | R/26_treatment_episodes.R:calculate_episodes_detailed(); R/00_config.R:GAP_THRESHOLD (L4054) | GAP_THRESHOLD = 90 (R/00_config.R:L4054); a new episode begins when treatment_date - episode_start >= GAP_THRESHOLD. 180-day episodes built with gap_threshold = 180L (R/26:L906). |
| S4-REL-03 | Cleaning rules for relapse/refractory | DEC-007; docs/analytic_manual/TeamMtgNotes2026.md:L390-L410 | DEC-007 CONFIRMED: relapse = change in regimen with 90+ day break; refractory = change in regimen with <90 day break. Code does not yet implement full relapse/refractory classifier (Sharon pending); DEC-007 establishes the rule. |
| S4-DIST-01 | Expected structure of distance variable | R/122_encounter_distance.R:compute_encounter_distance() | Distance from patient residential ZIP to encounter facility ZIP, computed in miles using three-tier method; result column dist_mi. |

### Notes on scope

- S4-DXDT-02 (FILLED-NEEDS-CHECK), S4-DX-01/02/03/04 (FILLED-NEEDS-CHECK or EMPTY-NEEDS-TEAM), S4-INS-02 (FILLED-NEEDS-CHECK), S4-ADI-01..06 (FILLED-NEEDS-CHECK), S4-DTH-02..05 (FILLED-NEEDS-CHECK or drafted), S4-SRV-02 (OUT-OF-SCOPE), S4-SRV-04/05 (EMPTY-NEEDS-TEAM), S4-DIST-02..06 (FILLED-NEEDS-CHECK or CORRECTION/OPEN): these were handled in Plan 02 drafts already present in AM-DRAFT.md. Plan 03 only needs the EMPTY-REPO-CAN-ANSWER items not yet drafted.

Confirming existing Plan 02 drafts are in place for: S4-DXDT-01 through S4-DIST-06 in AM-DRAFT.md (lines 116–360). All checked — Plan 02 has drafted all existing-domain EMPTY-REPO-CAN-ANSWER items. No additional existing-domain drafting is needed in Plan 03; the "Not drafted" section at the bottom of AM-DRAFT.md lists only the 12 repo-only IDs.

---

## 12 Repo-Only Domain IDs (AM-MAP-02)

### S4-SHS-01 — Single-health-system care flag

- Source: `R/169_single_source_care.R:build_single_source_result()` L48–L90
- What it shows:
  - Expected structure: patients have encounters from one or more SOURCE values; the function produces `single_source_care` (all non-blank encounters at one site = 1) and `primary_source` (most frequent site).
  - Observed issues: none documented in available sources.
  - Cleaning rules: NULLIF(UPPER(TRIM(SOURCE)), '') excludes blank SOURCE values; `single_source_care_post` flag applies the same logic to post-treatment encounters only; NA assigned where n_encounters = 0.
  - Unresolved: none documented in available sources.

### S4-CHM-01 — Chemo detection

- Source: `R/utils/utils_treatment.R:get_chemo_hits()` L181–L290 (PRESCRIBING, DISPENSING, MED_ADMIN branches); Phase 122 SUMMARY (RXNORM_CUI mismatch fix)
- What it shows:
  - Expected structure: chemotherapy hits drawn from three PCORnet medication tables: PRESCRIBING (RXNORM_CUI match), DISPENSING (NDC-to-RxNorm crosswalk), MED_ADMIN (MEDADMIN_TYPE RX via RXNORM_CUI; MEDADMIN_TYPE ND via NDC crosswalk).
  - Observed issues: Phase 122 found that DISPENSING and MED_ADMIN lacked usable RXNORM_CUI values; an NDC-to-RxNorm crosswalk (`data/reference/ndc_rxnorm_crosswalk.rds`, built by `R/108_build_ndc_rxnorm_crosswalk.R`) was added to resolve hits from those tables.
  - Cleaning rules: `normalize_ndc()` strips hyphens before crosswalk lookup; source column tags each hit's originating path ("PRESCRIBING", "DISPENSING (NDC)", "MED_ADMIN (RX)", "MED_ADMIN (NDC)").
  - Unresolved: none documented in available sources.

### S4-NRM-01 — Drug-name normalization

- Source: `R/00_config.R:MEDICATION_LOOKUP` (L2636–L2733); `R/00_config.R:canonicalize_drug_name` (L2750–L2814); DEC-011
- What it shows:
  - Expected structure: drug names from PRESCRIBING/MED_ADMIN/DISPENSING are normalized to generic equivalents before regimen detection.
  - Observed issues: brand-name proliferation (adriamycin variants) and salt/acid variants impede regimen identification.
  - Cleaning rules: `canonicalize_drug_name()` maps brand names to generics (e.g., adriamycin, adriamycin pfs, adriamycin rdf → Doxorubicin; vinblastine sulfate → Vinblastine; liposomal variants included). Applied to MEDICATION_LOOKUP on load (L2814). DEC-011 CONFIRMED (2026-10-13).
  - Unresolved: none documented in available sources.

### S4-REG-01 — First-line regimen labeling

- Source: `R/28_episode_classification.R` L295–L365; `R/00_config.R` L705 (ABVD context), L2958–L2959
- What it shows:
  - Expected structure: treatment episodes are labeled with a first-line regimen (ABVD, BV+AVD, Nivo+AVD, or unlabeled) based on drug combination and date.
  - Observed issues: none documented in available sources (source `return_source` column was added to track detection path but no cleaning issues logged).
  - Cleaning rules: regimen label assigned in `R/28_episode_classification.R` L328–L352 via `case_when`: (1) BV+AVD = brentuximab + doxorubicin + vinblastine + dacarbazine (post-2019-01-01 date guard); (2) ABVD = doxorubicin + bleomycin + vinblastine + dacarbazine, up to 4 unique drugs; (3) Nivo+AVD = nivolumab + doxorubicin + vinblastine + dacarbazine; drug-name detection takes priority over J-code detection.
  - Unresolved: rule to be confirmed against code — see S4-REG-01. (TEAM-INPUT-NEEDED: full first-line qualification logic, including is_first_line column, pending Sharon episode review.)

### S4-EPI-01 — Treatment episodes

- Source: `R/26_treatment_episodes.R:calculate_episodes_detailed()` L511–L590; `R/00_config.R:GAP_THRESHOLD` L4054; `R/25_treatment_durations.R:assign_episode_ids()` L492–L512
- What it shows:
  - Expected structure: chemo dates are collapsed into episodes; each episode has a start, stop, length, and drug list.
  - Observed issues: none documented in available sources.
  - Cleaning rules: `assign_episode_ids()` starts a new episode when `treatment_date - episode_start >= gap_threshold`. Default threshold = `GAP_THRESHOLD = 90` days (`R/00_config.R:L4054`). A 180-day variant is built with `gap_threshold = 180L` (`R/26:L906`). The Gantt window (90-day or 180-day) is the display window, not a separate gap rule.
  - Unresolved: formal end-of-treatment date for survivorship window definition is pending Sharon confirmation (see S4-TRT-04).
  - NOTE: Episode segmentation (gap from episode start), relapse/refractory classification (90-day break from end of initial tx — DEC-007), and Gantt display window (90-day vs 180-day export) are three distinct constructs.

### S4-ANT-01 — Anthracycline exposure

- Source: `R/utils/utils_anthracycline_echo.R:last_anthracycline_dose()` L58–L90; Phase 187 SUMMARY; Phase 188 SUMMARY
- What it shows:
  - Expected structure: anthracycline exposure flag and date of last dose per patient, split by first-line and ever.
  - Observed issues: Phase 24 note (D-08a): `first_line` column absent from treatment_episode_detail_180.rds; `last_dose_firstline_dt` is NA when all first_line values are FALSE or NA.
  - Cleaning rules: `last_anthracycline_dose()` filters `first_line == TRUE` rows to derive `last_dose_firstline_dt`; `last_dose_ever_dt` is max admin_date across all rows.
  - Unresolved: none documented in available sources beyond D-08a above.

### S4-CBC-01 — CBC definition

- Source: `R/utils/utils_distance_cbc.R:build_cbc_events()` L108–L145; comment at L89 and L114
- What it shows:
  - Expected structure: a CBC event requires WBC (LOINC 6690-2), hemoglobin (LOINC 718-7), and platelet (LOINC 777-3) results on the same date for the same patient.
  - Observed issues: none documented in available sources.
  - Cleaning rules: SQL push-down filters LAB_RESULT_CM to the three LOINC codes; only dates where all three codes are present for the same ID are retained as CBC events (`build_cbc_events()` L137–L143). CBC definition is specific to the distance-CBC association analysis; it does not apply to all lab-based encounters.
  - Unresolved: none documented in available sources.

### S4-RUR-01 — Rurality

- Source: `R/116_encounter_ses_index.R` L12, L65, L84, L214–L237, L344–L345; DEC-006
- What it shows:
  - Expected structure: RUCA (USDA 2020 ZIP Code Data) preferred; assigned on ZIP5; four categories: Metropolitan (codes 1–3), Micropolitan (4–6), Small town (7–9), Rural (10), Not coded (99).
  - Observed issues: reference file must be present at `data/reference/RUCA-codes-2020-zipcode.xlsx`; when absent, ruca_code and ruca_category are NA (graceful degradation at L236–L237).
  - Cleaning rules: RUCA lookup joins on ZIP5 (`R/116:L344`); 5-digit ZIP is acceptable for RUCA assignment (DEC-006 CONFIRMED 2026-08-25). No RUCC fallback is documented in available sources in R/116.
  - Unresolved: RUCC fallback mentioned in AM-MAP-02 notes but not located in R/116 code. Rule to be confirmed against code — see S4-RUR-01.

### S4-SDI-01 — Social Deprivation Index

- Source: `R/116_encounter_ses_index.R` L9, L66, L85, L240–L265, L346–L347
- What it shows:
  - Expected structure: SDI (Robert Graham Center, ZIP5-level) assigned per encounter ZIP5. Columns: ZIP5, sdi_score (numeric, 0–100).
  - Observed issues: SDI reference file (`data/reference/zip5_sdi_reference.csv`) gated by probe; if absent or missing ZIP5/SDI_score columns, sdi_score is NA with a warning (L259–L264).
  - Cleaning rules: `normalize_zip5_raw()` applied to ZIP5 before join; SDI joined by ZIP5 (`R/116:L346–L347`). SDI is ZIP5-level only; no ZIP9 or census-tract granularity is used (geographic unit = ZIP5, not tract).
  - Unresolved: none documented in available sources.

### S4-DOI-01 — Rituximab/methotrexate diagnoses of interest

- Source: `R/utils/utils_doi.R:is_doi_code()` L52–L78; `R/utils/utils_doi.R:classify_doi_codes()` L98–L115; `R/00_config.R:DOI_CODE_MAP`
- What it shows:
  - Expected structure: ICD-10 and ICD-9 diagnosis codes for non-malignant conditions (autoimmune, inflammatory, hematologic) associated with rituximab or methotrexate use are flagged via prefix match against `DOI_CODE_MAP`.
  - Observed issues: none documented in available sources.
  - Cleaning rules: `is_doi_code()` is gated on DX_TYPE (ICD-9 vs ICD-10) to avoid cross-version mismatches; `classify_doi_codes()` tries 4-character then 3-character prefix cascade.
  - Unresolved: none documented in available sources.

### S4-CLS-01 — HL vs NHL classification

- Source: `R/utils/utils_cancer.R:classify_codes()` L97–L115 (cancer site classification); DEC-009; DEC-010; Phase 87 SUMMARY context (NHL episode exclusion)
- What it shows:
  - Expected structure: patients with ICD-10 C81.x or ICD-9 201.x are classified as HL; patients whose treatment episodes are clearly NHL-only are excluded (DEC-009); ambiguous cases are retained (DEC-010).
  - Observed issues: many patients have mixed HL/NHL codes; Gantt-based episode detection used to identify NHL-only episodes.
  - Cleaning rules: `classify_codes()` maps ICD codes to cancer-site categories; NHL-only episode exclusion implemented per DEC-009; uncertain HL/NHL patients retained per DEC-010.
  - Unresolved: full NHL classification code path (episode-level logic) to be confirmed against code — see S4-CLS-01. (utils_cancer.R contains `classify_codes()` but the NHL episode-level exclusion logic was not located in a single function.)

### S4-PDE-01 — Post-death encounters

- Source: `R/utils/utils_death.R:resolve_death_date()` L50–L116; `R/51_post_death_encounter_investigation.R` (diagnosis); `R/29_first_line_and_death_analysis.R` L258–L259
- What it shows:
  - Expected structure: encounters occurring after the resolved death date are identified and quantified; they are not removed from the encounter table but are flagged.
  - Observed issues: deaths that precede the last treatment encounter exist in the data (noted in S4-DTH-02); Phase 29 (R/29:L258–L259) reports the count of patients with post-death activity.
  - Cleaning rules: `resolve_death_date()` computes `post_death_activity_days` = days from death_date_raw to last_observed (L101–L112); zero if no post-death activity. `death_flag` column distinguishes alive, deceased-confirmed, and deceased-inferred states.
  - Unresolved: none documented in available sources beyond the grace-window question (D-191-06) already addressed in S4-DTH-03.

---

## Coverage check

All 12 AM-MAP-02 repo-only IDs confirmed above with at least one source located or explicitly noted as not located:
S4-SHS-01, S4-CHM-01, S4-NRM-01, S4-REG-01 (partial — full first-line qualifier pending Sharon), S4-EPI-01, S4-ANT-01, S4-CBC-01, S4-RUR-01 (RUCC fallback not located), S4-SDI-01, S4-DOI-01, S4-CLS-01 (episode exclusion logic location noted), S4-PDE-01.

All existing-domain EMPTY-REPO-CAN-ANSWER items confirmed as already drafted in Plan 02 output within AM-DRAFT.md.
