# Project Research Summary

**Project:** PCORnet CDM Payer Analysis Pipeline — v1.6 Treatment Code Validation & Cancer Site Analysis
**Domain:** R-based clinical research data pipeline (HiPerGator HPC, PCORnet CDM, DuckDB backend)
**Researched:** 2026-04-21
**Confidence:** HIGH

## Executive Summary

This milestone (v1.6) extends an existing, functioning PCORnet Hodgkin Lymphoma analysis pipeline (Phases 1-44) with five targeted capabilities: a cancer site frequency table derived from CancerSiteCategories.xlsx, a bidirectional gap report comparing TREATMENT_CODES in R/00_config.R against TreatmentVariables_2024.07.17.docx, an audit of the radiation CPT range 70010-79999 to classify imaging vs. treatment codes, explicit confirmation and addition of proton therapy codes 77520-77525, and a triggering code column in the treatment episode CSV output. All research was conducted against direct inspection of the existing codebase, project reference files, and authoritative CPT/ICD code documentation. The research base is strong — there are no unknowns about environment, data structures, or output formats.

The recommended implementation approach adds three new standalone scripts (R/45, R/46, R/47) following the existing numbered diagnostic script pattern, makes additive column additions to R/43 and R/44, and requires only one new package (docxtractr 0.6.5) on top of the existing stack. The correct build order is: radiation CPT audit first (informs config corrections), then treatment code cross-reference (informs any remaining config gaps), then optional config corrections, then R/43+R/44 triggering code changes, then cancer site frequency. All five features are independent except the triggering code work, which requires modifying R/43 before R/44.

The two highest risks for this milestone are: (1) misapplying the docx radiation range "70010-79999" as a literal CPT filter — which would capture all diagnostic imaging as radiation treatment and inflate the treated cohort by an order of magnitude — and (2) ICD-10 range matching via string comparison rather than enumerated code vectors, which silently misses dotted/undotted format variations and causes undercounting of cancer site matches. Both risks are well-understood and fully preventable with established patterns already present in the codebase.

## Key Findings

### Recommended Stack

The existing pipeline stack is entirely sufficient for v1.6. No new infrastructure is required. The baseline stack — R 4.4.2, tidyverse (dplyr, stringr, ggplot2, lubridate, purrr), DuckDB + DBI, openxlsx2, readxl, officer, glue, janitor, scales, here — is already installed and validated on HiPerGator. The only new dependency is docxtractr 0.6.5, a purpose-built CRAN package for extracting structured tables from Word documents, needed to parse code tables from TreatmentVariables_2024.07.17.docx.

**Core technologies:**
- `docxtractr 0.6.5`: Extract code tables from TreatmentVariables docx — NEW; cleaner than officer::docx_summary() for table-structured content; install once, run `renv::snapshot()`
- `readxl 1.4.3+`: Read CancerSiteCategories.xlsx and VariableDetails.xlsx — already in pipeline (R/35, R/42); no change
- `stringr 1.5.1+`: ICD range parsing and CPT code classification — prefix matching via str_starts(); already in pipeline; no change
- `dplyr 1.2.0+`: All aggregation, joins, and frequency counts — group_by + summarise pattern; already in pipeline; no change
- `openxlsx2 current`: Styled output workbooks matching existing visual conventions — already in pipeline; no change

**What NOT to use:** The `icd` package (archived CRAN 2020, unmaintained, GitHub install unreliable on HiPerGator), `ICD10gm` (German codes, not US ICD-10-CM/ICD-O-3), officer for docx table extraction (flat noisy output vs. docxtractr's clean data.frame), and NLM API for CPT code descriptions (NLM covers drug codes; CPT is AMA-licensed — use CMS MPFS RVU files for public-domain descriptors).

### Expected Features

All five v1.6 features are P1 (required for milestone completion). The existing pipeline covers Phases 1-44; v1.6 adds exactly these features and nothing else.

**Must have (table stakes):**
- **Cancer site frequency table** — CancerSiteCategories.xlsx defines 42 site groups; without frequency counts from PCORnet DIAGNOSIS + TUMOR_REGISTRY tables, the file is unused reference material
- **TREATMENT_CODES vs. TreatmentVariables docx gap report** — the docx is the authoritative study protocol source; without bidirectional comparison against R/00_config.R, there is no validation that the pipeline captures the full documented treatment code set
- **Radiation CPT 70010-79999 audit with imaging/treatment classification** — the pipeline needs a per-sub-range cited classification for every code in the range; unclassified codes cannot be defended to IRB or protocol reviewers
- **Proton therapy codes 77520-77525 confirmation** — UFPTI is a proton therapy center; these codes are NOT in the existing radiation_cpt config and their systematic absence silently misses proton therapy patients
- **Triggering code column in episode CSV** — per-episode traceability to the specific CPT/HCPCS code that triggered episode_start is required for manual QA and downstream analysis defensibility

**Should have (differentiators):**
- Bidirectional gap report (both directions: in pipeline not in docx AND in docx not in pipeline)
- Cancer site frequency with dual ICD-O-3 + ICD-10 coding (higher sensitivity via TUMOR_REGISTRY + DIAGNOSIS)
- Multiple triggering codes per episode (comma-separated when same date yields multiple codes)

**Defer to v1.x / v2+:**
- Cancer site frequency stratified by payer (disparity analysis — defer until v1.6 classification validates)
- Cancer site frequency by partner site (small-cell suppression triggers aggressively; IRB review required)
- Gap report RXNORM cross-check via NLM (low priority, not surfaced in current gaps)

### Architecture Approach

The pipeline uses a standalone diagnostic script pattern: every numbered script sources R/00_config.R and R/01_load_pcornet.R, opens a DuckDB lazy connection via `get_pcornet_table()`, does its work independently, and writes to output/. There is no shared runtime state between scripts. v1.6 follows this pattern exactly. Three new scripts (R/45, R/46, R/47) are added as standalone diagnostics. Two existing scripts (R/43, R/44) receive additive column additions only. The output/ directory gains three new xlsx files and the per-type episode CSVs gain a triggering_codes column.

**Major components:**
1. `R/45_cancer_site_frequency.R` (NEW) — Reads CancerSiteCategories.xlsx Groups sheet (43 rows), expands ICD10/ICDO3 ranges to code vectors via named `expand_icd_range()` function, queries DIAGNOSIS and TUMOR_REGISTRY_ALL scoped to HL cohort, produces patient-level frequency table with HIPAA suppression; output: cancer_site_frequency.xlsx
2. `R/46_treatment_code_crossref.R` (NEW) — Reads VariableDetails.xlsx Treatment sheet (forward-fill Modality column), parses TreatmentVariables docx via docxtractr, diffs against TREATMENT_CODES in config using exact %in% matching, produces bidirectional gap report per treatment type; output: treatment_code_crossref.xlsx
3. `R/47_radiation_cpt_audit.R` (NEW) — Queries PROCEDURES for CPT codes 70010-79999 on HL patients, classifies each by numeric sub-range (IMAGING / PLANNING / TREATMENT / NUCLEAR MED), verifies proton codes 77520-77525 presence, documents exclusion rationale with CPT citations; output: radiation_cpt_audit.xlsx
4. `R/43_treatment_durations.R` (MODIFIED) — extract_all_dates() extended to return triggering_code + code_type columns alongside existing ID + treatment_date; additive only, does not rename existing columns
5. `R/44_treatment_episodes.R` (MODIFIED) — calculate_episodes_detailed() collects triggering codes per episode; triggering_codes column appended as LAST column in per-type CSV output; D-08 decision log updated

### Critical Pitfalls

1. **Radiation CPT range applied too broadly (70010-79999 as literal filter)** — Never use the docx range as a direct CPT filter. The range is a chapter reference, not an inclusion list. Apply only the radiation oncology sub-ranges: 77261-77799 (treatment, planning, management) plus proton codes 77520-77525 plus brachytherapy 77750-77799. The full 70010-79999 range includes diagnostic imaging (70010-76999) and nuclear medicine (78000-79999) — applying it literally inflates the radiation-treated patient count by an order of magnitude.

2. **ICD-10 range matching via string comparison instead of code enumeration** — CancerSiteCategories.xlsx stores ranges like "C810-C814, C817, C819". String comparison (`code >= "C810"`) fails for mixed-length codes, dotted/undotted format differences, and codes with letter suffixes (C81.9A). Build a named `expand_icd_range()` function, enumerate all codes between range endpoints, normalize to undotted uppercase using the existing `normalize_icd()` from utils_icd.R, then use `%in%`.

3. **Docx cross-reference uses substring matching (str_detect) instead of exact matching (%in%)** — Substring matching produces false positives (J9000 matches a range string "J9000-J9999") and false negatives (individual codes not found when docx uses range notation). Parse docx into a structured code list, expand declared ranges to individual codes, use exact `%in%` for all comparisons. Always produce both gap directions.

4. **Cancer site frequency table not scoped to HL cohort** — `get_pcornet_table("DIAGNOSIS")` returns all PCORnet patients. Always apply `filter(ID %in% local(hl_ids))` as the first filter using `get_hl_patient_ids()`. Sanity check: total unique patients in frequency table must not exceed HL cohort size. Use `n_distinct(ID)` not `n()` to count patients.

5. **Triggering code column inserted mid-schema or without auditing downstream consumers** — Append triggering_codes as the LAST column in the CSV output. Search the codebase for all scripts that read treatment_episodes.csv or the treatment_episodes.rds before modifying the schema. The column must be nullable (NA when no triggering code matched) to avoid bind_rows() failures.

## Implications for Roadmap

Based on combined research, four implementation phases cover all v1.6 scope with clear internal logic. The phases are presented in recommended build order.

### Phase A: Radiation CPT Audit + Proton Code Confirmation (R/47 + R/00_config.R)

**Rationale:** R/47 is the fastest new script to validate — it reads only from PROCEDURES + existing config with no new reference file parsing complexity. It immediately answers the proton therapy gap question (77520-77525 absent from radiation_cpt), which produces a config correction that should be in place before the cross-reference phase runs. Addressing the highest-risk pitfall (range misclassification) first also provides confidence before touching other components.

**Delivers:** radiation_cpt_audit.xlsx with per-sub-range classification and AMA/CMS citation; proton codes 77520-77525 confirmed absent and added to R/00_config.R with citation comments; CPT_HCPCS_RANGES heuristic in R/38 verified to confirm proton sub-range (775xx) is not covered by the existing 774xx pattern

**Addresses features:** Radiation CPT 70010-79999 audit, Proton therapy 77520-77525 confirmation

**Avoids:** Pitfall v1.6-1 (range too broad), Pitfall v1.6-6 (proton codes assumed present without data check)

**No research needed:** CPT sub-range boundaries are specified in STACK.md with cited sources; implementation is case_when with numeric boundaries

### Phase B: Treatment Code Cross-Reference (R/46)

**Rationale:** Depends on Phase A having corrected R/00_config.R so the gap report reflects the post-correction state of TREATMENT_CODES. R/46 uses docxtractr for the first programmatic extraction of TreatmentVariables_2024.07.17.docx — table structure must be discovered interactively at the start of implementation before writing the extraction logic. This phase should complete before triggering code work so any further config changes from the gap report are stable.

**Delivers:** treatment_code_crossref.xlsx with bidirectional gap report (in_pipeline_not_in_docx + in_docx_not_in_pipeline), grouped by treatment type and code type; docxtractr 0.6.5 installed and renv snapshotted; VariableDetails.xlsx Treatment sheet Modality column forward-filled before use

**Addresses features:** TREATMENT_CODES vs. TreatmentVariables docx gap report

**Avoids:** Pitfall v1.6-3 (substring matching), Pitfall v1.6-8 (one-direction comparison)

**Targeted inspection needed at implementation start:** Run `docxtractr::docx_tbl_count()` and `docx_describe_tbls()` on TreatmentVariables_2024.07.17.docx interactively before writing R/46 extraction logic — this is the first programmatic extraction of this file. Budget 30-60 minutes. STACK.md provides the usage pattern; actual table indices are unknown until the docx is opened.

### Phase C: Triggering Code Column in Episode Output (R/43 + R/44)

**Rationale:** Modifying R/43 and R/44 is the only inter-script dependency change in v1.6 and carries the highest downstream risk. It must happen after Phases A and B have stabilized the config. The triggering code change is additive (new column at end of CSV), but a downstream consumer audit must be completed before the change is made. Modify R/43 first, verify its output is unchanged except for the new columns, then modify R/44.

**Delivers:** R/43 extract_all_dates() returning triggering_code + code_type alongside existing columns; R/44 per-type CSVs with new triggering_codes column (comma-separated for multiple codes on same date) appended as last column; D-08 decision log updated; Phase 44 test script re-validated

**Addresses features:** Triggering code column in episode CSV

**Avoids:** Pitfall v1.6-4 (schema change breaks downstream consumers — requires pre-search of all readers before modifying)

**No research needed:** Architecture is fully specified in ARCHITECTURE.md; the additive column pattern is standard and low-risk

### Phase D: Cancer Site Frequency Table (R/45)

**Rationale:** Fully independent of all other v1.6 changes. Placed last because the ICD range expansion logic is the highest implementation complexity in v1.6 — range parsing for the "C810-C814, C817, C819" format, dotted/undotted normalization, dual ICD-O-3 + ICD-10 matching, HIPAA suppression, and the multi-patient-per-site-group counting decision. The `expand_icd_range()` function must be tested against boundary cases before running against all 42 site groups.

**Delivers:** cancer_site_frequency.xlsx with patient count + encounter count per cancer site group, pct_of_cohort column, HIPAA suppression (n <= 10 suppressed); optionally a second sheet excluding C81.xx (HL) codes to show comorbid cancer distribution

**Addresses features:** Cancer site frequency table

**Avoids:** Pitfall v1.6-2 (ICD string comparison), Pitfall v1.6-5 (not scoped to HL cohort), Pitfall v1.6-7 (C81.xx dominance not documented as expected)

**One data decision at implementation start:** Determine whether ICDO3 matching (TUMOR_REGISTRY) is used in addition to ICD-10 (DIAGNOSIS) — requires a quick query to check how many HL cohort patients have TUMOR_REGISTRY records. If most do, dual-coding raises sensitivity significantly. If few do, ICD-10 alone is sufficient.

### Phase Ordering Rationale

- Phase A before B: Config corrections from the radiation audit must be reflected in the gap report
- Phase A+B before C: Config must be stable before modifying R/43/R/44 output schema
- Phase D is independent but placed last due to implementation complexity, not dependency
- Within Phase C: R/43 modification must be verified before R/44 modification (the one hard internal dependency in v1.6)

### Research Flags

Phases with standard patterns (no research-phase needed):
- **Phase A (Radiation CPT audit):** CPT sub-range boundaries fully specified in STACK.md; CMS/ASTRO sources confirm 2026 code changes; implementation is case_when with numeric range boundaries — a standard dplyr pattern
- **Phase C (Triggering code column):** Architecture fully documented in ARCHITECTURE.md; additive column at end of schema is a standard, low-risk R pattern; R/44 test script provides regression validation
- **Phase D (Cancer site frequency):** ICD range format confirmed by direct xlsx inspection; normalize_icd() exists in utils_icd.R; DuckDB cohort filter pattern is established across 10+ existing scripts

Phase requiring targeted inspection (not full research-phase):
- **Phase B (Treatment code cross-reference):** TreatmentVariables_2024.07.17.docx table structure must be discovered at runtime with `docxtractr::docx_tbl_count()` and `docx_describe_tbls()` before writing extraction logic. This is a 30-60 minute interactive inspection step at the start of Phase B implementation, not a research gap.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | docxtractr 0.6.5 CRAN-current verified 2026-04-21; icd package archived status confirmed; CPT 2026 code changes confirmed via CMS/ASTRO sources; all other packages already in active use |
| Features | HIGH | All features are scoped extensions of existing, shipping scripts with confirmed patterns; scope is unambiguous; complexity estimates are grounded in prior similar work in pipeline |
| Architecture | HIGH | Derived from direct inspection of all existing R scripts and reference files; no inferred structure; data flow diagrams confirmed against actual function signatures |
| Pitfalls | HIGH | v1.6 pitfalls derive from direct CPT code structure knowledge and codebase inspection; ICD range pitfalls from prior ICD matching work in same pipeline; proton code gap confirmed by direct config inspection |

**Overall confidence:** HIGH

### Gaps to Address

- **TreatmentVariables_2024.07.17.docx table structure:** Not previously parsed programmatically. At the start of Phase B, run `docxtractr::docx_tbl_count()` and `docx_describe_tbls()` interactively to discover actual table layout and numbering. Do not hardcode table indices in R/46 before this discovery step.

- **ICDO3 vs ICD-10 matching decision for cancer site frequency:** ARCHITECTURE.md flags the ICD-O-3 column in CancerSiteCategories.xlsx as "optional." The decision of whether to use dual-coding (ICD-O-3 via TUMOR_REGISTRY + ICD-10 via DIAGNOSIS) or ICD-10 only should be made at Phase D start based on a quick count of HL cohort patients with TUMOR_REGISTRY records. This is a one-query data decision, not a research gap.

- **CPT sub-range MEDIUM confidence for IRB documentation:** The 70010-79999 sub-range classification in STACK.md carries MEDIUM confidence because boundaries come from industry billing sources, not the AMA CPT manual directly (which is paywalled). For IRB-grade documentation, supplement with CMS RBRVS RVU files (public domain) as the primary citation for CPT short descriptors. STACK.md identifies the relevant CMS URL.

## Sources

### Primary (HIGH confidence)

- Direct inspection: R/00_config.R, R/38, R/42, R/43, R/44, R/utils_icd.R, R/utils_treatment.R — all architecture findings
- Direct inspection: CancerSiteCategories.xlsx (Groups sheet, 43 rows) — ICD10 range format "C810-C814, C817, C819" confirmed
- Direct inspection: VariableDetails.xlsx (Treatment sheet, 123 rows) — Modality/Code/Description structure and forward-fill requirement confirmed
- Direct inspection: TreatmentVariables_2024.07.17.docx (text extraction) — "From PROCEDURES: 70010-79999" confirmed
- [docxtractr CRAN](https://cran.r-project.org/web/packages/docxtractr/index.html) — version 0.6.5 current, confirmed 2026-04-21
- [icd CRAN archived](https://cran.r-project.org/package=icd) — archived 2020-10-06 confirmed
- [PMC: 2026 CMS Radiation Oncology codes](https://pmc.ncbi.nlm.nih.gov/articles/PMC12842826/) — 77402/77407/77412 replacing 77385/77386, confirmed
- [ASTRO Process of Care](https://www.astro.org/practice-support/reimbursement/coding/coding-guidance/coding-faqs-and-tips/process-of-care) — 77261-77290 confirmed non-treatment (planning/simulation)
- [SEER ICD-O-3 Site Codes](https://training.seer.cancer.gov/head-neck/abstract-code-stage/codes.html) — C##.# format confirmed

### Secondary (MEDIUM confidence)

- [medicalbillersandcoders.com: Radiology Billing Codes](https://www.medicalbillersandcoders.com/blog/understand-the-basics-of-radiology-billing-codes/) — 70010-79999 subsection boundaries (industry source; supplement with CMS RBRVS for IRB citations)
- [medicalbillersandcoders.com: Radiation Oncology Codes Part 1](https://www.medicalbillersandcoders.com/blog/radiation-oncology-codes-part-1/) — 77261-77799 subsection breakdown (MEDIUM — same recommendation)
- [ICD10gm CRAN](https://cran.r-project.org/web/packages/ICD10gm/ICD10gm.pdf) — confirmed as German ICD-10-GM, not US ICD-10-CM/ICD-O-3; exclusion rationale confirmed

### Tertiary (LOW confidence)

- None — all findings have at least MEDIUM-confidence sources

---
*Research completed: 2026-04-21*
*Supersedes: SUMMARY.md dated 2026-03-24 (base pipeline research; this covers v1.6 additions only)*
*Ready for roadmap: yes*
