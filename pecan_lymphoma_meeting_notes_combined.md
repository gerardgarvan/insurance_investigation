---
doc_type: combined_meeting_notes
project: Hodgkin/Non-Hodgkin Lymphoma cancer treatment data analysis
sources:
  - meeting_notes_to_check_gaps.txt (Zoom AI summaries, multiple sessions)
  - notes_gap.docx (Quant Meeting 06/29/2026, handwritten-style notes)
people:
  - Gerard (data/tables, SAS/Tableau pipeline)
  - Amy (visualization, Tableau, data categorization)
  - Erin Mobley (PI/coordination, Sharon liaison)
  - Raymond/Ray (clinical/methodological lead)
  - Sebastian (system access)
  - Sharon (clinical reviewer, chemo/immuno classification)
  - Gerard (data cleaning, treatment timeline)
  - Sophia Smith (Duke / Hodgkins International, recruitment)
  - Audrey (email access)
  - Heather Lake Berger, Donny (IDR scheduling)
key_datasets:
  - chemotherapy tab / immunotherapy tab (to be merged into one file)
  - All Codes Resolved spreadsheet
  - secondary malignancy table
  - treatment timeline CSV (start/end dates, 90-day windows)
generated: 2026-06-15
---

# Combined Meeting Notes: Lymphoma Treatment Data Analysis

## 1. Project Scope
Reviewing and refining cancer treatment data for Hodgkin lymphoma (HL) and non-Hodgkin lymphoma (NHL) patients. Core work: correctly categorize medications/treatments (chemotherapy vs immunotherapy vs supportive care), link cancer diagnoses to treatment encounters, and visualize treatment timelines in Tableau.

## 2. Key Data Facts
- ~1,800 patients with HL; ~3,000 patients overall (06/29 meeting count).
- ~8,000 HL patients total in earlier dataset; ~4,000 of these ALSO carry NHL codes → data-quality concern.
- 276 patients had ABVD or AVD (first-line HL chemotherapy).
- 2,364 patients listed as HL only (one earlier count); 2,000 / 6,000 figure cited for diagnoses associated with encounters.
- Gerard: only ~70% of cancer cases have diagnosable/diagnosis dates (~30% missing) → key barrier.
- ICD-10 code C81.0 confirmed for Hodgkin's lymphoma (Raymond).

## 3. Core Decisions Made
- DIAGNOSIS LINKING: Focus on diagnosis code associated with each specific encounter/procedure (medication or infusion), NOT the first/initial HL diagnosis date. Encounter IDs sufficient.
- FILE MERGE: Combine chemotherapy tab + immunotherapy tab into a single final file before returning to Sharon.
- SUPPORTIVE CARE: Move non-chemotherapy/supportive-care meds out of chemo classification. Mesna specifically → move to supportive care (Gerard, Mesna ONLY).
- TUMOR REGISTRY: Remove/exclude unreliable tumor registry data for transplants (SCT).
- SCT EXCLUSION: Pull out SCT entries from diagnosis table that are only follow-up/status codes (not actual treatment).
- DEATH DATES: Remove death dates occurring before treatment dates; add death-cause information.
- SECONDARY MALIGNANCY: Confirm cases on 7-day gap criterion between diagnoses; strictly temporal from diagnosis table; columns K–N based on population in column E (E3).
- INSURANCE CATEGORIES: Combine self-pay + uninsured; merge "other government" + "other"; TRICARE moved to private; group workers' comp + auto with consolidated categories.
- RADIOTHERAPY: Add proton therapy to radiotherapy options.
- ICD CODES: Disregard certain odd-practice ICD codes, particularly for NHL cases.

## 4. GAPS / OPEN QUESTIONS (items "to check")
- G1: ~30% of cancer cases lack diagnosis dates — investigate alternative sources (condition table) to raise % of encounters with linked diagnosis.
  - **RESOLVED (v3.1 Phase 100):** CONDITION table added as 3rd-tier cancer linkage source, reducing unlinked treatment episodes. See output/condition_linkage_investigation.xlsx.
- G2: Chemotherapies/treatments NOT associated with a cancer diagnosis are being MISSED. Current counts (e.g. the 276 ABVD/AVD) reflect only encounters WITH a cancer diagnosis attached. Applies to ALL treatment types including radiation (RT). Need to size how big the data becomes when including encounters NOT tied to a cancer diagnosis.
  - **RESOLVED (v3.1 Phase 101):** Broadened drug grouping output now includes ALL treatment encounters with cancer_linked TRUE/FALSE flag. See output/drug_grouping_instances.xlsx.
- G3: Single agents given alone (dacarbazine, bleomycin, doxorubicin) — check what OTHER chemotherapies are given within 30 days.
  - **RESOLVED (v3.1 Phase 102):** Co-administration analysis shows other chemotherapies given within +/-30 days for each single agent. See output/co_administration_analysis.xlsx.
- G4: High overlap of HL + NHL codes (~4,000 of 8,000) — validate accuracy; Erin skeptical many combinations are real.
  - **RESOLVED (v3.2 Phase 105):** Temporal validation of dual-code patients completed with same-day, <30d, 30-180d, >180d categorization and data quality assessment. See output/hl_nhl_overlap_validation.xlsx.
- G5: Radiation occurring BEFORE HL diagnosis — review these cases.
  - **RESOLVED (v3.2 Phase 104):** Pre-diagnosis treatments flagged across all 5 treatment types (chemo, radiation, SCT, immunotherapy, proton). See output/pre_diagnosis_treatments.xlsx.
- G6: Radiation codes in brackets (e.g. "replaced by 77385…") — confirm whether present in data and should be included.
- G7: Immunotherapy labeling — rows 5, 10, 11, 16 appear labeled as multivitamins; confirm with Sharon whether these should count as immunotherapy. (Rephrase question to AVOID the word "multivitamin" to prevent confusing Sharon.)
- G8: "Ethna" listed as immunotherapy — needs correction/review.
  - **RESOLVED (v3.2 Phase 105):** Etanercept (Enbrel) correctly excluded from immunotherapy classification -- it is a TNF-alpha inhibitor, not anticancer immunotherapy. See output/code_verification.xlsx.
- G9: Line 130 medication — determined to REMAIN in current category (treats hormonally driven cancers).
- G10: Organ transplant code (line 11 of codes spreadsheet) — cross-check whether it should be included.
  - **RESOLVED (v3.2 Phase 105):** Revenue code 0362 investigated with SCT evidence cross-reference. Findings in output/code_verification.xlsx.
- G11: Codes above line 22 in stem cell codes — potential issues; verify patient data.
  - **RESOLVED (v3.2 Phase 105):** SCT diagnosis codes Z94.84, T86.5, T86.09 validated as status/complication codes -- correctly excluded from treatment groupings. See output/code_verification.xlsx.
- G12: CAR-T information may need more detail in immunotherapy tab.
- G13: Multivitamins generally — should they count as immunotherapy? (Sharon to confirm.)
- G14: Lymphoma studies email address not yet set up (Sebastian/Audrey).
- G15: Death-date table breakdown needed: (i) how many have a death date, (ii) of those, how many is it the last encounter, (iii) how many have encounters AFTER death.
  - **RESOLVED (v3.1 Phase 103):** Three-tier death date cross-tab produced: (i) patients with death date, (ii) death as last encounter, (iii) encounters after death. See output/death_date_summary.xlsx.

## 5. Action Items by Person

### Gerard
- Move Mesna (ONLY Mesna) from chemotherapy tab to supportive care.
- Work on Gantt chart updates in the interim; Gantt plots for next meeting.
- Exclude SCT entries from diagnosis table that are only follow-up/status codes.
- Investigate bracketed radiation codes (e.g. "replaced by 77385…") — confirm presence/inclusion.
- Send encounter-level data breakdown to team.
- Send current treatment dates file (start/end dates + type, 90-day windows CSV) to Amy.
- Check for new codes (reported: found ZERO new codes).

### Amy
- Add note in column H of chemotherapy tab for Mesna (and similar) → "NA" or "Not treatment."
- Continue data presentation prep for Ray's review (drug–cancer type appropriateness).
- Finish SCT and radiation grouping/categorization in working file (Dropbox version) to support Gerard's tables.
- Build/refine Tableau visualizations: per encounter, show associated cancer diagnosis codes + treatment type; show specific radiation episodes rather than all cancers.
- Visualize treatment timeline data (90-day windows) and distribute to team.
- Sort chemo data; update columns H and I in chemo tab; provide update in a couple of days.
- Send meeting to-do items to group, CC all attendees (new standard practice).
- Document data-cleaning decisions/rationale in methods section (references to files in master file).
- Coordinate possible Wednesday meeting (Amy out Thu/Fri).
- Prefers cross-bar charts over current bullet format for cancer-type visualization.

### Erin
- Review chemotherapy list for other meds that should be supportive care; ask Sharon to label.
- Email Sharon: review chemotherapy tab, specifically the "N" in column H; indicate supportive-care drugs.
- Email Sharon: review immunotherapy tab to confirm agents should count as immunotherapy.
- Email Sharon re: drugs used for supportive care AND conditioning (HL/NHL protocols).
- Move final Excel file to Data Details folder; archive old version in prior-versions folder.
- Follow up weekly with Heather Lake Berger to schedule IDR meeting; pass availability to Donny/IDR.
- Forward Zoom AI meeting notes to group for QA of action items.
- Meet Sophia Smith Friday 7:00 AM re: recruitment; update Raymond after.

### Raymond/Ray
- Send weekly reminder to Sharon re: chemotherapy/immunotherapy coding input.
- (Clinical guidance) Focus on diagnosis tied to specific medication/infusion; encounter IDs sufficient.

### Sebastian
- Email Audrey to request access to lymphoma studies email address; provide skater/Slack link.

### Gerard
- Continue data cleaning and treatment-vs-relapse analysis (significant work remaining).
- Treatment timeline analysis within 90-day windows (in progress).

## 6. Visualization Notes (Tableau)
- Dashboard includes: HL diagnosis dates, chemotherapy, radiation, SCT, immunotherapy episodes.
- Challenge: displaying up to 18 different cancer types in a single episode.
- Amy prefers cross-bar charts over bullet format.
- Refine to show specific radiation episodes rather than all cancers.

## 7. Scheduling / Logistics
- Thursday meeting CANCELED (Amy out of town Thu/Fri); team to decline in Outlook.
- Possible Wednesday meeting after Tuesday meeting.
- Friday meeting confirmed 8:00 AM (treatment timelines + insurance coding); Raymond visiting Baptist that day.
- Erin/Sophia Smith: Friday 7:00 AM (recruitment).
- Amy + Gerard: meet Thursday to review progress.
- ASH abstract possibly submitted in August; June 18th deadline already passed.

## 8. Clinical Reference Terms
- HL = Hodgkin lymphoma; NHL = non-Hodgkin lymphoma.
- NLPHL = nodular lymphocyte-predominant Hodgkin's lymphoma (vs classical HL).
- ABVD / AVD = first-line HL chemotherapy regimens.
- C81.0 = ICD-10 code for Hodgkin's lymphoma.
- Single agents noted: dacarbazine, bleomycin, doxorubicin.
- Multi-use drugs (multiple cancer types): asparaginase, Rituxan/rituximab.
- SCT = stem cell transplant; RT = radiation therapy; CAR-T = immunotherapy.
- Color code (06/29 notes): green = NB/note, yellow = to-do.
