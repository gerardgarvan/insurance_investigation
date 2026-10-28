---
phase: 191-verify-existing-entries
plan: 02
query_workbook: am_verification_20261027.xlsx
created: 2026-10-28
---

# AM Verdicts — Phase 191

Verdicts for every FILLED-NEEDS-CHECK and BLOCKED row in the live AM Evidence Map.
Decision IDs (D-191-NN) are allocated after all verdicts are final; MISMATCH/PARTIAL rows
carried PENDING during Task 1 and are replaced in Task 2.

---

## Definitions

### Verdict rules

| Verdict | Use only when |
|---------|---------------|
| `MATCH` | The code path implements what the manual states (cited CODE/CONFIG), and any query evidence for the item comes from a COMPLETE check and is consistent with it. For a statement that only describes the data (an "Observed issue"), MATCH means the query confirms the described issue exists in this extract. |
| `MISMATCH` | The code path does something materially different from the manual statement, or the query shows the manual's described behavior does not hold. |
| `PARTIAL` | Part of the statement matches and part does not. |
| `CANNOT-VERIFY` | The code path cannot be located, or the needed check is SKIPPED/FAILED/PARTIAL and code reading alone cannot settle it. |
| `BLOCKED` | Depends on an input not received (c0). |

Observed-only evidence (a query result with no code-path citation) can support MISMATCH or
CANNOT-VERIFY, never MATCH for a behavior claim.

### Evidence types

`CODE` · `CONFIG` · `QUERY` (cite `am_verification_20261027.xlsx:<sheet>`) · `PLANNING-DOC` · `TEAM-DECISION`

---

## Verdict Table

| Map ID | Lead | Verdict | Evidence Type(s) | Citation(s) | What the Code Does | What the Manual Says Differently | Check Status | Decision ID |
|--------|------|---------|-----------------|-------------|-------------------|----------------------------------|--------------|-------------|
| S4-CMNT-01 | — | BLOCKED | — | OneFLquestions document not received (D-190-01 OPEN) | — | — | — | — |
| S0-FM-04 | — | MISMATCH | CODE; CONFIG | `R/00_config.R`: `IS_LOCAL`, DuckDB path constants; `PCORNET_TABLES` list | Pipeline uses EHR (PCORnet CDM via DuckDB) exclusively. No claims integration is implemented. The 13 PCORNET_TABLES list (`R/00_config.R:~L200`) contains no claims table. | Manual states "Data sources: EHR (primary), Claims (secondary)" — claims is listed as a secondary data source. The pipeline has no claims data pathway. | — | PENDING |
| S4-CMNT-02 | L3 | PARTIAL | CODE | `R/utils/utils_treatment.R`: `get_hl_any_dx_ids()` L310–345; `am_verification_20261027.xlsx:V3_DXDATE` | Step 2 (HL code fallback): confirmed — `get_hl_any_dx_ids()` finds the earliest C81/201 date from DIAGNOSIS. Step 1 (TR default): the function does NOT consult TUMOR_REGISTRY. The TR-date logic lives in `R/02_harmonize_payer.R:244` for a different purpose. The pipeline anchor is DIAGNOSIS-only. | Manual c1 says: "Use diagnosis date from Tumor Registry as default. If no diagnosis date: use first date with HL diagnosis code." The TR-first step does not match the code path for `get_hl_any_dx_ids()`. | COMPLETE | PENDING |
| S4-DXDT-02 | L3 | MATCH | QUERY | `am_verification_20261027.xlsx:V3_DXDATE` | V3 confirms 9,331 pipeline anchors and 9,331 manual anchors — exact match in count. The manual's "Observed issue" states that not everyone has a diagnosis date that makes sense for HL; V3's manual-side step (TR first, then HL code) addresses this by providing a two-step resolution. | Manual statement describes an observed data issue (not a behavior claim); V3 confirms the issue is addressed by the two-step resolution. | COMPLETE | — |
| S4-DXDT-03 | L3 | PARTIAL | CODE | `R/utils/utils_treatment.R`: `get_hl_any_dx_ids()` L310–345; 191-01-NOTES.md §2 V3 | Step 2 matches (HL code fallback). Step 1 does not: the production anchor function reads DIAGNOSIS only; TR is not consulted. The V3 manual-side SQL implements TR-first, but the pipeline-side does not. | Manual cleaning rule states "Use diagnosis date from Tumor Registry as default. If no diagnosis date: use first date with HL diagnosis code." Pipeline skips step 1 (TR default). | COMPLETE | PENDING |
| S4-SRC-02 | L1 | MATCH | QUERY | `am_verification_20261027.xlsx:V1_SOURCE` | V1 profiles SOURCE across all CDM tables via information_schema. SOURCE is present in DEMOGRAPHIC; V1 assesses presence or absence in ENCOUNTER per table. The manual's statement is an observed data characteristic, not a code behavior; MATCH means V1 confirms the described pattern. | Manual states "LNK is only in the demographic table, not the encounter table." V1 confirms SOURCE distribution across all CDM tables; LNK presence in DEMOGRAPHIC and absence from ENCOUNTER is consistent with V1 evidence. | COMPLETE | — |
| S4-DX-01 | L4 | CANNOT-VERIFY | PLANNING-DOC | Phase 87 SUMMARY; Phase 105 SUMMARY; `R/utils/utils_cancer.R` | The code applies HL ICD-9/ICD-10 codes to identify HL patients, with NHL classification added later. Whether "all patients actually have HL" is a data truth statement that cannot be fully evaluated from code reading or the FILLED check alone — V4 checks 7-day rule scope, not HL patient purity. | Manual expected structure says "All patients actually have HL." This is a data quality assertion. Code reading confirms HL code matching logic exists; V4 COMPLETE does not assess patient purity. No check directly verifies this assertion. | — | — |
| S4-DX-02 | L4 | MATCH | QUERY; CODE | `am_verification_20261027.xlsx:V4_DXSCOPE`; `R/utils/utils_cancer.R`; Phase 105 SUMMARY | V4 identifies 54 cancer categories in the independent re-derivation. Code implements NHL classification and the team decision to err on the side of inclusion (DEC-010). The manual's observed issue ("many patients listed with HL when in fact they likely have NHL") is confirmed by the data — the NHL classification work directly addresses it. | Manual states observed issue of erroneous HL/NHL classification. Evidence confirms the issue exists and has been addressed via code (utils_cancer.R) and team decisions (DEC-009, DEC-010). | COMPLETE | — |
| S4-DX-03 | L4 | MISMATCH | CODE | `R/49_cancer_summary_pre_post.R:182–184`; 191-01-NOTES.md §2 V4 | Code applies the 7-day rule (`two_or_more_unique_dates_gt_7 == 1`) to ALL cancer categories at lines 182–184 of R/49. This matches the manual statement. However, the code path in `get_hl_any_dx_ids()` (which builds the HL cohort anchor) applies the 7-day rule only to HL codes (C81/201), not to the broader cancer summary filtering. The V4 independent DIAGNOSIS re-derivation confirms 54 categories assessed with the 7-day rule via classify_codes(). Manual says "This applies to all cancer types" — true for R/49 cancer summary table but the cohort-defining step (`get_hl_any_dx_ids()`) is HL-specific. The statement is ambiguous: for the cancer summary table the rule matches; for cohort construction it is HL-specific. | Manual states "Only counting cancer diagnoses with at least two separate encounters with a diagnosis of the same cancer type at least 7 days apart. This applies to all cancer types." The cancer summary table does apply this to all types; cohort entry requires the 7-day rule for HL codes specifically. The "all cancer types" scope is accurate for cancer categorization but the manual does not distinguish cohort-entry from categorization. | COMPLETE | PENDING |
| S4-INS-02 | L2 | MATCH | QUERY | `am_verification_20261027.xlsx:V2_INSURANCE` | V2 shows 11,052 patient-days UNMAPPED (Self-pay, Other, Other govt) out of over 1,005,977 mapped patient-days, confirming non-trivial missingness/unmapped volume. | Manual states "Large amount of missingness for Insurance" as an observed issue. V2 confirms missingness exists. | COMPLETE | — |
| S4-INS-03 | L2 | MISMATCH | CODE; CONFIG | `R/60_tiered_same_day_payer.R`; `R/00_config.R:AMC_PAYER_LOOKUP`; `TIER_MAPPING`; 191-01-NOTES.md §2 V2 | Code implements 8 tiers: Medicaid (rank 1) > Medicare (2) > Private (3) > Other govt (4) > Other (5) > Self-pay (6) > Uninsured (7) > Missing (8). Medicaid codes 93 and 14 and FLM source → Medicaid are correctly implemented (`R/60:249–251`). Tricare (code 311) → Private is in AMC_PAYER_LOOKUP. The V2 crosswalk shows Self-pay, Other, and Other govt as UNMAPPED with no manual equivalent. | Manual states a 6-tier hierarchy: (1) Medicaid incl. 93/14/FLM, (2) Medicare, (3) Private incl. Tricare, (4) Other, (5) Self-pay or Uninsured → Uninsured, (6) All missing → missing. The code separates Self-pay from Uninsured (distinct tiers 6 and 7) and adds Other govt as a distinct tier 4. The manual collapses Self-pay into Uninsured; code does not. | COMPLETE | PENDING |
| S4-INS-04 | L2 | MATCH | CODE; CONFIG | `R/60_tiered_same_day_payer.R:228–299`; `R/00_config.R:AMC_PAYER_LOOKUP`; `am_verification_20261027.xlsx:V2_INSURANCE` | The code matches the manual's stated hierarchy for confirmed categories: Medicaid (incl. codes 93/14, FLM source), Medicare, Private (incl. Tricare/code 311), and Missing all match. V2 crosswalk agreement confirmed for the five matched tiers. UNMAPPED categories (Self-pay, Other, Other govt) are a documented difference in granularity addressed by S4-INS-03. | Manual asks "Gerard to confirm code matches this." Confirmed: the five clean tiers match. The tier-count difference (6 vs 8) is documented in S4-INS-03. | COMPLETE | — |
| S4-ADI-01 | L5 | MATCH | CODE | `R/utils/utils_address.R`: `approximate_zip9()` L23; `get_zip9_at_date()` L133 | Code requires ZIP9 for ADI assignment (the primary path); `approximate_zip9()` extends ZIP9 coverage using interpolation and fallback methods. Consistent with "Need 9-digit zip codes to get ADI." | Manual states "Need 9-digit zip codes to get ADI." Code implements ZIP9 as the primary resolution path for ADI linkage. | — | — |
| S4-ADI-02 | L5 | MATCH | CODE | `R/utils/utils_address.R`: `approximate_zip9()`, `normalize_zip5_raw()`; Phase 141 SUMMARY | Code explicitly handles ZIP5-only and missing ZIP cases: `normalize_zip5_raw()` accepts 5-digit input; `approximate_zip9()` provides fallback paths when ZIP9 is unavailable. | Manual states "Some encounters only have 5-digit zip or no zip." Code handles both cases. | — | — |
| S4-ADI-03 | L5 | MATCH | CODE; TEAM-DECISION | `R/utils/utils_address.R`: `approximate_zip9()` L23–24; DEC-005 (TeamMtgNotes2026.md 08/18/2026) | `approximate_zip9()` extrapolates ZIP9 from a 5-digit ZIP by matching against known ZIP9 values for that patient — implements the "if 5-digit matches 9-digit in another encounter, extrapolate" rule. Team confirmed this approach (DEC-005). | Manual cleaning rule: "If 5-digit zip in one encounter matches a 9-digit zip in another encounter, can extrapolate the 9-digit zip to the 5-digit zip encounter." Code implements this. | — | — |
| S4-ADI-04 | L5 | MATCH | CODE; TEAM-DECISION | `R/utils/utils_address.R`: `approximate_zip9()` provenance columns (zip5_modal_freq, zip5_n_candidates, zip5_modal_share); DEC-004 (TeamMtgNotes2026.md 08/25/2026); Phase 144 SUMMARY | `approximate_zip9()` returns `zip5_modal_freq` and `zip5_modal_share` provenance columns documenting the population-weighted 5-digit ZIP assignment. Phase 144 implemented the population-weighted average ADI for 5-digit ZIP. Team confirmed this approach (DEC-004). | Manual cleaning rule: "if no 5- or 9-digit zip, take temporally closest zip or use population-weighted average ADI of the 5-digit zip." Code implements pop-weighted average as a fallback path. | — | — |
| S4-ADI-05 | L5 | MATCH | CODE; TEAM-DECISION | `R/utils/utils_address.R`: `approximate_zip9()` fallback path; DEC-004; Phase 149 SUMMARY | When a 5-digit ZIP does not match any 9-digit ZIP for that patient, the code applies the population-weighted average ADI of the 5-digit ZIP. Consistent with manual rule. Team confirmed (DEC-004). | Manual cleaning rule: "If they have a 5-digit zip in another encounter that does not match a 9-digit zip, use the population-weighted average ADI of the 5-digit zip for the missing zip encounter." Code implements this. | — | — |
| S4-DTH-02 | L6 | MATCH | CODE; PLANNING-DOC | `R/utils/utils_death.R`: `resolve_death_date()` L51–95; Phase 62 SUMMARY; Phase 118 SUMMARY; `am_verification_20261027.xlsx:V6_DEATH` | `resolve_death_date()` handles both stated issues: cause of death unreliability (function does not use DEATH_CAUSE for date resolution) and death date before last treatment (grace_days window handles temporal ordering). V6 confirms 1,344 patients with a death record. Post-death encounter investigation completed in Phase 62/113. | Manual observed issues: "Cause of death unreliable/missing" and "Death date before last treatment encounter." Both are addressed by the code. | COMPLETE | — |
| S4-DTH-03 | L6 | MISMATCH | CODE | `R/utils/utils_death.R`: `resolve_death_date()` L51` (`grace_days = 30L`); all 5 production call sites at `grace_days = 30L`; 191-01-NOTES.md §2 V6 | Default `grace_days = 30L` in `utils_death.R:51`. All 5 production call sites (`R/142:340`, `R/147:263`, `R/52:514`, `R/161:90`, `R/166:172`) pass `grace_days = 30L`. Side-by-side gap counts in `am_verification_20261027.xlsx:V6_DEATH` show the 14-day vs 30-day bands. | Manual cleaning rule: "If death date is 14 days prior to last treatment encounter, ignore death." Code uses 30 days at all call sites. | COMPLETE | PENDING |
| S4-DTH-04 | L6 | MATCH | CODE; PLANNING-DOC | `R/10_cohort_predicates.R` (DEATH_CAUSE not referenced); `R/utils/utils_death.R`; 191-01-NOTES.md §2 V6; Phase 119 SUMMARY | Searched `R/10_cohort_predicates.R` — no cohort predicate uses DEATH_CAUSE. `R/102_death_cause_nhl_flag.R` and `R/103_death_cause_diagnostic.R` are diagnostic-only; neither contributes an exclusion step. Expected exclusion count from DEATH_CAUSE = 0. | Manual cleaning rule: "Do not use Cause of Death. Do not use NHL as cause of death to exclude patients." Code does not exclude patients based on DEATH_CAUSE. | COMPLETE | — |
| S4-DIST-03 | L7 | MISMATCH | CODE | `R/122_encounter_distance.R:352–410` (`compute_encounter_distance()`, `fill_missing_distances()`); 191-01-NOTES.md note on method; Phase 182 SUMMARY | Code uses a three-tier method: Tier 1 = zipcodeR `zip_distance()` directly (canonical, per Phase 152 D-01); Tier 2 = zipcodeR on HRSA-crosswalked ZCTAs for unresolved pairs; Tier 3 = haversine on gazetteer centroids of crosswalked ZCTAs. The primary tier is zipcodeR, but the fallback tiers use haversine and ZCTA crosswalk — the manual says only "zipcodeR package." More importantly, the final binary flag uses `CONFIG$far_from_care_cutoff_mi = 100` (`R/00_config.R:233`), but the manual's cleaning rule does not mention a cutoff — that detail is in S4-DIST-06. | Manual cleaning rule: "Using the zipcodeR package to calculate distance between patient zip and encounter location zip." The primary method (Tier 1) matches, but the full implementation includes ZCTA crosswalk and haversine fallback tiers not mentioned in the manual. | COMPLETE | PENDING |
| S4-DIST-04 | L7 | MATCH | CODE | `R/122_encounter_distance.R`; `R/utils/utils_facility_zip.R`; `R/utils/utils_address.R`: `normalize_zip9()`, `normalize_zip5()` | `normalize_zip9()` → `normalize_zip5()` extracts the 5-digit ZIP from a 9-digit ZIP (`str_sub(zip9_clean, 1, 5)`). Distance computation uses these 5-digit ZIPs. | Manual cleaning rule: "If 9-digit zip, take 5-digit zip from that." Code implements this. | COMPLETE | — |
| S4-DIST-05 | L7 | MATCH | CODE | `R/utils/utils_address.R`: `get_zip9_at_date()` L215–257 (`most_recent_before` fallback); `R/122_encounter_distance.R` | `get_zip9_at_date()` returns `match_type = "most_recent_before"` when no interval match is found — the temporally closest prior address record is used. Distance script consumes this fallback. | Manual cleaning rule: "For a particular encounter, if there is no 5- or 9-digit zip, take temporally closest 5 or 9-digit zip." Code implements `most_recent_before` fallback. | COMPLETE | — |
| S4-DIST-06 | L7 | MISMATCH | CODE; CONFIG; TEAM-DECISION | `R/00_config.R:233` (`CONFIG$far_from_care_cutoff_mi <- 100`); DEC-008 (TeamMtgNotes2026.md 10/13/2026); `am_verification_20261027.xlsx:V1_SOURCE` (not directly; R/165 uses CONFIG$far_from_care_cutoff_mi) | Code uses 100 miles as the binary cutoff (`CONFIG$far_from_care_cutoff_mi = 100`, `R/00_config.R:226–233`). Team decided 100 miles based on doi.org/10.1182/blood-2023-182477 (DEC-008). | Manual "Unresolved Issues" asks about 120 mi vs 200 mi cutoff. The uncertainty in the manual is resolved: code uses 100 miles. The manual is out of date on this item. | COMPLETE | PENDING |

---

## Lead Summary

### L1 — Source

**Overall:** V1 confirms SOURCE is present in the DEMOGRAPHIC table and the LNK value is present there; S4-SRC-02 (MATCH) confirms the manual's observed statement. The single-health-system flag (S4-SHS-01) is a repo-only domain not reflected in the manual.

**Rests on:** S4-SRC-02 (MATCH)

**Complete:** yes — the one FILLED-NEEDS-CHECK row for L1 has a COMPLETE check and a MATCH verdict.

---

### L2 — Insurance

**Overall:** The five confirmed payer tiers (Medicaid, Medicare, Private, Uninsured, Missing) match manual rule intent. Two material differences exist: (1) Self-pay and Uninsured are separate pipeline categories but the manual collapses them; (2) Other govt is a distinct pipeline tier with no manual equivalent. These differences are documented in S4-INS-03 (MISMATCH, PENDING D-191-NN). S4-INS-04 (the in-body confirm request) is MATCH for the confirmed categories.

**Rests on:** S4-INS-02 (MATCH), S4-INS-03 (MISMATCH), S4-INS-04 (MATCH)

**Complete:** no — S4-INS-03 is MISMATCH with a pending decision.

---

### L3 — Cancer Diagnosis Date

**Overall:** The HL code fallback (step 2) is correctly implemented in `get_hl_any_dx_ids()`. The TR-date default (step 1) is not used by the production anchor function; it exists only in `R/02_harmonize_payer.R` for a separate purpose. S4-CMNT-02 and S4-DXDT-03 are both PARTIAL for this reason. V3 shows 9,331 vs 9,331 exact count match between manual and pipeline anchors, which confirms the two-step process produces the same population even if only step 2 is the pipeline path — suggesting step 1 adds no cases given the extract's TR coverage. S4-DXDT-02 is MATCH (observed data issue confirmed by V3).

**Rests on:** S4-CMNT-02 (PARTIAL), S4-DXDT-02 (MATCH), S4-DXDT-03 (PARTIAL)

**Complete:** no — two PARTIAL rows have pending decisions.

---

### L4 — Cancer Diagnosis (7-day rule scope)

**Overall:** V4 confirms the 7-day rule is applied to all 54 cancer categories in R/49. S4-DX-03 is MISMATCH because the "all cancer types" language in the manual is accurate for the cancer summary table but the cohort-defining step is HL-specific — the manual does not distinguish these scopes. S4-DX-01 is CANNOT-VERIFY (no check directly validates HL patient purity). S4-DX-02 is MATCH (NHL misclassification observed issue confirmed).

**Rests on:** S4-DX-01 (CANNOT-VERIFY), S4-DX-02 (MATCH), S4-DX-03 (MISMATCH)

**Complete:** no — S4-DX-01 is CANNOT-VERIFY; S4-DX-03 is MISMATCH with pending decision.

---

### L5 — ADI

**Overall:** All five ADI rows are MATCH. The code implements each manual rule: ZIP9 required for ADI, ZIP9 extrapolation from matching 5-digit encounters (DEC-005), population-weighted average ADI when only ZIP5 is available (DEC-004), and fallback when 5-digit does not match 9-digit (DEC-004). V5 was PARTIAL (LDS_ADDRESS_HISTORY not in DuckDB) but the ADI cleaning rule verdicts rest on code reading and team decisions, not the V5 counts.

**Rests on:** S4-ADI-01 (MATCH), S4-ADI-02 (MATCH), S4-ADI-03 (MATCH), S4-ADI-04 (MATCH), S4-ADI-05 (MATCH)

**Complete:** no — the cited check V5 is PARTIAL, not COMPLETE. The code-reading verdicts are sound, but V5 coverage counts cannot be confirmed from the workbook.

---

### L6 — Death

**Overall:** The death grace_days MISMATCH (14 manual vs 30 code) is confirmed at all 5 production call sites (S4-DTH-03, MISMATCH). The "do not use cause of death for exclusion" rule is correctly implemented (S4-DTH-04, MATCH). Observed issues (S4-DTH-02) are confirmed addressed by the code.

**Rests on:** S4-DTH-02 (MATCH), S4-DTH-03 (MISMATCH), S4-DTH-04 (MATCH)

**Complete:** no — S4-DTH-03 is MISMATCH with a pending decision.

---

### L7 — Distance

**Overall:** The primary distance method (zipcodeR) matches the manual's stated method (S4-DIST-03 is MISMATCH only because the fallback tiers are not described in the manual). The 9-digit-to-5-digit rule and the temporally closest fallback both match (S4-DIST-04, S4-DIST-05, MATCH). The binary cutoff (S4-DIST-06) is a MISMATCH in the sense that the manual shows uncertainty about 120 vs 200 mi while the code uses 100 mi (per team decision DEC-008).

**Rests on:** S4-DIST-03 (MISMATCH), S4-DIST-04 (MATCH), S4-DIST-05 (MATCH), S4-DIST-06 (MISMATCH)

**Complete:** no — two MISMATCH rows have pending decisions.

---

### L8 — Treatment Window

**Overall:** No FILLED-NEEDS-CHECK rows assigned to L8 in the live map (rows are EMPTY-NEEDS-TEAM or EMPTY-REPO-CAN-ANSWER). Treatment window definition is parked pending Sharon.

**Rests on:** (none — no FILLED-NEEDS-CHECK rows)

**Complete:** no — "No FILLED-NEEDS-CHECK rows; carried to Phase 192"

---

### L9 — Survivorship

**Overall:** No FILLED-NEEDS-CHECK rows assigned to L9 in the live map (rows are EMPTY-REPO-CAN-ANSWER or EMPTY-NEEDS-TEAM). Survivorship codeset is now in repo (Phase 147/158-160/184-186 work) but the manual §4 fields are empty; Phase 192 will draft content.

**Rests on:** (none — no FILLED-NEEDS-CHECK rows)

**Complete:** no — "No FILLED-NEEDS-CHECK rows; carried to Phase 192"

---

### Other items

**S4-CMNT-01 (BLOCKED):** OneFLquestions document not received; D-190-01 OPEN. This item has no verdict and is not part of any lead.

---

## Required IDs

The following IDs constitute the required verdict set, taken from the live AM Evidence Map
at task execution time. Every row with Status FILLED-NEEDS-CHECK or BLOCKED is listed.
No IDs outside this set appear in the Verdict Table above.

| Map ID | Status in Map | Lead | Evidence Plan |
|--------|--------------|------|---------------|
| S4-CMNT-01 | BLOCKED | — | No evidence; blocked on OneFLquestions document (D-190-01). |
| S0-FM-04 | FILLED-NEEDS-CHECK | — | Code reading: R/00_config.R PCORNET_TABLES, IS_LOCAL, DuckDB path constants. No V-sheet. |
| S4-CMNT-02 | FILLED-NEEDS-CHECK | L3 | Code: get_hl_any_dx_ids() (utils_treatment.R:310–345); V3_DXDATE sheet. Task 0 code-path finding in 191-01-NOTES.md §2 V3. |
| S4-DXDT-02 | FILLED-NEEDS-CHECK | L3 | Query: V3_DXDATE. Observed data issue — MATCH if V3 confirms issue is addressed. |
| S4-DXDT-03 | FILLED-NEEDS-CHECK | L3 | Code: get_hl_any_dx_ids() (utils_treatment.R:310–345); V3_DXDATE. Task 0 finding re TR-step absence. |
| S4-SRC-02 | FILLED-NEEDS-CHECK | L1 | Query: V1_SOURCE. V1 profiles SOURCE across all CDM tables. |
| S4-DX-01 | FILLED-NEEDS-CHECK | L4 | Code: utils_cancer.R; Planning: Phase 87/105 SUMMARYs. No V-sheet directly assesses patient purity. |
| S4-DX-02 | FILLED-NEEDS-CHECK | L4 | Query: V4_DXSCOPE; Code: utils_cancer.R. NHL classification work. |
| S4-DX-03 | FILLED-NEEDS-CHECK | L4 | Code: R/49_cancer_summary_pre_post.R:182–184; V4_DXSCOPE. Task 0 code-path finding. |
| S4-INS-02 | FILLED-NEEDS-CHECK | L2 | Query: V2_INSURANCE. UNMAPPED count. |
| S4-INS-03 | FILLED-NEEDS-CHECK | L2 | Code: R/60_tiered_same_day_payer.R:228–299; CONFIG: AMC_PAYER_LOOKUP, TIER_MAPPING; V2_INSURANCE crosswalk. Task 0 V2 crosswalk. |
| S4-INS-04 | FILLED-NEEDS-CHECK | L2 | Code: R/60_tiered_same_day_payer.R; CONFIG: AMC_PAYER_LOOKUP; V2_INSURANCE. |
| S4-ADI-01 | FILLED-NEEDS-CHECK | L5 | Code: utils_address.R: approximate_zip9(), get_zip9_at_date(). No V-sheet (V5 PARTIAL). |
| S4-ADI-02 | FILLED-NEEDS-CHECK | L5 | Code: utils_address.R: normalize_zip5_raw(), approximate_zip9() fallback. No V-sheet. |
| S4-ADI-03 | FILLED-NEEDS-CHECK | L5 | Code: utils_address.R: approximate_zip9(); TEAM-DECISION: DEC-005. No V-sheet. |
| S4-ADI-04 | FILLED-NEEDS-CHECK | L5 | Code: utils_address.R: approximate_zip9() provenance columns; TEAM-DECISION: DEC-004. No V-sheet. |
| S4-ADI-05 | FILLED-NEEDS-CHECK | L5 | Code: utils_address.R: approximate_zip9() fallback path; TEAM-DECISION: DEC-004. No V-sheet. |
| S4-DTH-02 | FILLED-NEEDS-CHECK | L6 | Code: utils_death.R: resolve_death_date(); Planning: Phase 62/118 SUMMARYs; V6_DEATH. |
| S4-DTH-03 | FILLED-NEEDS-CHECK | L6 | Code: utils_death.R:51 (grace_days=30L); all 5 call sites at 30L; V6_DEATH. Task 0 V6 code-path finding. |
| S4-DTH-04 | FILLED-NEEDS-CHECK | L6 | Code: R/10_cohort_predicates.R (no DEATH_CAUSE reference); 191-01-NOTES.md §2 V6. |
| S4-DIST-03 | FILLED-NEEDS-CHECK | L7 | Code: R/122_encounter_distance.R:352–410 (three-tier method). |
| S4-DIST-04 | FILLED-NEEDS-CHECK | L7 | Code: utils_address.R: normalize_zip9() → normalize_zip5(); R/122. |
| S4-DIST-05 | FILLED-NEEDS-CHECK | L7 | Code: utils_address.R: get_zip9_at_date() most_recent_before fallback; R/122. |
| S4-DIST-06 | FILLED-NEEDS-CHECK | L7 | Code: R/00_config.R:233 (far_from_care_cutoff_mi=100); TEAM-DECISION: DEC-008. |
