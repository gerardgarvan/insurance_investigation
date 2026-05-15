# Feature Research

**Domain:** PCORnet CDM cohort-building and payer analysis pipeline (R) — v1.6 Treatment Code Validation & Cancer Site Analysis
**Researched:** 2026-04-21
**Confidence:** HIGH (all features are scoped extensions of existing scripts with known patterns)

---

## Feature Landscape

This document covers ONLY the new v1.6 features. Existing features (Phases 1-44) are already built and documented.

The five new feature areas are:
1. Cancer site frequency table from CancerSiteCategories.xlsx
2. TREATMENT_CODES cross-reference against TreatmentVariables_2024.07.17.docx
3. Radiation CPT 70010-79999 range audit (imaging vs treatment classification)
4. Proton therapy CPT confirmation (77520-77525 in radiation_cpt)
5. Triggering code column in treatment episode CSV output

---

### Table Stakes (Users Expect These)

Features a clinical researcher expects from this pipeline in v1.6. Missing any of these makes the milestone incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Cancer site frequency table | CancerSiteCategories.xlsx defines 42 groups; without a frequency count across actual PCORnet data, the file is unused reference material | MEDIUM | Requires reading xlsx ICD code ranges, querying DIAGNOSIS + TUMOR_REGISTRY tables, mapping each patient to the most specific cancer site group, producing patient and record counts per group with HIPAA suppression |
| TREATMENT_CODES vs TreatmentVariables docx gap report | The docx is the authoritative source for what codes the study protocol says should be captured; without comparing it to R/00_config.R, there is no validation that the pipeline is complete | MEDIUM | Two-directional: codes in docx but not in config (gaps), codes in config not in docx (additions). Output as xlsx with per-type sheets matching existing treatment xlsx style |
| Radiation CPT audit (70010-79999 imaging vs treatment) | The 70010-79999 range is diagnostic imaging, but a handful of codes in the 77xxx sub-range are legitimate radiation treatment delivery codes; the pipeline needs an explicit, cited classification for every code in the range that appears in the data | HIGH | Requires per-code classification (IMAGING / TREATMENT / PLANNING / EXCLUDED) with citation source (CPT description, AMA documentation). Output must document rationale for every excluded code in radiation_cpt coverage area |
| Proton therapy codes 77520-77525 confirmation | Proton therapy is a primary treatment modality at UFPTI; if 77520-77525 are absent from radiation_cpt, the pipeline systematically misses proton therapy cases for a UFPTI study | LOW | Grep radiation_cpt in R/00_config.R; if missing, add with citation. Single-decision task. Currently missing from config (77401-77470 range in config does not include 77520-77525) |
| Triggering code column in episode CSV output | Per-patient episodes need traceability — knowing *which specific code* triggered the episode start date enables manual QA and downstream analysis | MEDIUM | Modifies R/44_treatment_episodes.R (or a new R/45 script). The extract_all_dates() function in R/43 currently drops source code; must be extended to carry triggering_code and triggering_source_table through to episode_start row |

---

### Differentiators (Competitive Advantage)

Features that add value beyond what a minimal implementation would provide.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Cancer site frequency with ICD-O-3 + ICD-10 dual-coding | CancerSiteCategories.xlsx contains both ICD-10 and ICD-O-3 ranges; matching both code systems separately and then unioning gives higher sensitivity than matching only one | HIGH | ICD-O-3 codes appear in TUMOR_REGISTRY, ICD-10 codes appear in DIAGNOSIS. Separate match + union prevents double-counting while maximizing coverage |
| Radiation CPT audit with AMA citation text | Audit value depends entirely on citation quality; a per-code table with the actual CPT description (not just code number) and AMA section reference is defensible for IRB/protocol documentation | MEDIUM | CPT official descriptions are paywalled, but CMS RBRVS data files contain short descriptors and are public. Supplement with AMA CPT codebook descriptions where available |
| Gap report differentiated by code type | A flat "in docx / not in config" list is less actionable than a per-type (CPT, HCPCS, ICD-9, ICD-10-PCS, RXNORM, Revenue, DRG) breakdown matching the TREATMENT_CODES list structure | LOW | Within the same gap report script, group gaps by code type. Requires parsing both the docx tables and the TREATMENT_CODES list structure carefully |
| Triggering code with multiple triggering codes per episode | Some episodes are confirmed by multiple codes on the same date (e.g., both a CPT delivery code and a revenue code); listing all triggering codes on episode_start date provides richer audit trail | LOW | Collapse triggering codes into comma-separated string within the triggering_codes column for the episode_start row |

---

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Full CPT 70010-79999 range scan for unknown radiation codes | Seems thorough — why not check every code in the range against what's in the data? | CPT 70010-79999 is the Radiology section; 99% of codes are diagnostic imaging (CT, MRI, X-ray, nuclear medicine). Treating them all as potential radiation therapy codes floods the output with irrelevant findings and obscures the handful of legitimate 77xxx treatment codes | Narrow the audit to 77000-77999 (radiation oncology subsection) plus verify any 70xxx codes appearing with radiation_cpt context. Document the exclusion boundary explicitly. |
| Automated docx-to-config sync (write back to R/00_config.R) | Seems like it would close the loop on validation | Docx contains intent; config contains validated, study-specific implementation. Not every docx code belongs in the config (e.g., codes for cancer types not in the HL cohort). Automated sync bypasses the necessary human review step | Produce a gap report. Human reviews it and makes targeted additions to config. Phase 42's per-type resolved xlsx pattern is the right precedent. |
| Cancer site frequency by site ID (per partner site) | Site-level breakdown seems informative | Small-cell suppression triggers aggressively for rare cancer sites at individual sites; most cells become suppressed and the table communicates nothing. Also raises site-specific data sensitivity concerns | Produce aggregate frequency table first. Site-level breakdowns are a v2 feature with explicit IRB review of suppression strategy. |
| Treatment code validation via NLM API lookup (CPT codes) | Phases 39-40 used NLM API for HCPCS/NDC lookup — why not reuse for CPT validation? | NLM's RxNorm API covers drug codes; CPT code descriptions are owned by AMA and are not in NLM APIs. CPT lookup requires AMA licensing or CMS public files (RBRVS). Using NLM for CPT returns empty or incorrect results. | Use CMS Medicare Physician Fee Schedule (MPFS) RVU files for CPT short descriptors (public domain). |
| Episode triggering code as a separate table | Normalized design would put triggering codes in a separate table joined to episodes | The existing episode output is a flat CSV consumed directly by researchers. Normalization adds a join step that breaks existing workflows and adds no value for QA use. | Store triggering_codes as a collapsed column in the episode row. Document the format (comma-separated, pipe-separated, or first-code-only). |

---

## Feature Dependencies

```
Cancer site frequency table (new R/45 or R/46)
    requires: CancerSiteCategories.xlsx (already exists)
    requires: DIAGNOSIS table (via get_pcornet_table dispatcher)
    requires: TUMOR_REGISTRY_ALL table (for ICD-O-3 codes)
    depends on existing: R/00_config.R (CONFIG paths), R/utils_duckdb.R (safe_table)

TREATMENT_CODES gap report (new R/46 or R/47)
    requires: TreatmentVariables_2024.07.17.docx (already exists, needs parsing)
    requires: TREATMENT_CODES list in R/00_config.R (already exists)
    uses: officer or docxtractr package for docx table extraction
    outputs: xlsx gap report matching existing treatment xlsx visual style

Radiation CPT audit (new R/47 or R/48)
    requires: TREATMENT_CODES$radiation_cpt in R/00_config.R
    requires: CMS MPFS RVU files or embedded CPT description lookup
    produces: per-code classification table (TREATMENT / IMAGING / PLANNING / EXCLUDED)
    informs: whether radiation_cpt needs additions (e.g., 77520-77525)

Proton therapy code confirmation (config update R/00_config.R)
    requires: Radiation CPT audit output (or direct CPT lookup)
    modifies: TREATMENT_CODES$radiation_cpt in R/00_config.R
    blocked by: none (can be done independently as a direct config edit)

Triggering code column in episodes (modifies R/44 or new R/45)
    requires: R/43_treatment_durations.R extract_all_dates() to carry source code
    requires: R/44_treatment_episodes.R calculate_episodes_detailed() to retain triggering_code
    modifies: per-type CSV output schema (adds triggering_codes column)
    depends on existing: R/44_treatment_episodes.R column structure (D-08 schema)
```

### Dependency Notes

- **Proton therapy confirmation requires radiation CPT audit:** The audit determines what's in the 77xxx range and whether 77520-77525 are present, correctly classified, and absent from the config. These can be done together.
- **Triggering code column modifies existing script schemas:** R/43 extract_all_dates() currently returns (ID, treatment_date) only. Adding triggering_code and source_table requires modifying R/43's extraction functions AND R/44's episode aggregation. This is a schema change to existing CSV outputs — the downstream consumer should be aware.
- **Gap report requires docx parsing:** TreatmentVariables_2024.07.17.docx contains code tables in Word table format. The officer package (available in tidyverse ecosystem) reads docx tables. This is the only new package dependency for v1.6.
- **Cancer site frequency is independent:** No dependency on treatment code features. Can be developed in parallel.

---

## MVP Definition

### Launch With (v1.6)

Minimum set to call v1.6 complete.

- [ ] **Cancer site frequency table** — directly addresses PROJECT.md target feature; CancerSiteCategories.xlsx is built and waiting
- [ ] **TREATMENT_CODES vs docx gap report** — directly addresses "cross-reference TREATMENT_CODES against TreatmentVariables" target feature; validates pipeline completeness
- [ ] **Radiation CPT 70010-79999 audit with imaging/treatment classification** — directly addresses audit target feature; cited classification is required for protocol documentation
- [ ] **Proton therapy 77520-77525 config update** — directly addresses "confirm proton therapy codes are captured" target feature; single config edit
- [ ] **Triggering code column in episode CSV** — directly addresses "add triggering code(s) column" target feature; schema addition to existing output

### Add After Validation (v1.x)

- [ ] **Cancer site frequency by ICD-O-3 topography code** — extends the frequency table with TUMOR_REGISTRY ICD-O-3 matching for sites where ICD-10 coding is incomplete; trigger: if frequency table shows high "Unclassified" counts
- [ ] **Gap report with NLM/RxNorm cross-check for drug codes** — validates RXNORM CUI codes in TREATMENT_CODES against NLM (Phases 39-40 validated HCPCS/NDC, not RXNORM in config); trigger: if gap report surfaces unexpected RXNORM discrepancies

### Future Consideration (v2+)

- [ ] **Cancer site frequency stratified by payer** — payer x cancer site frequency table enables disparity analysis by tumor site; defer until v1.6 frequency table validates classification logic
- [ ] **Site-level radiation CPT audit by partner site** — some partner sites may have different radiation coding practices; defer until aggregate audit is stable

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Cancer site frequency table | HIGH | MEDIUM | P1 |
| TREATMENT_CODES gap report | HIGH | MEDIUM | P1 |
| Radiation CPT audit (70010-79999) | HIGH | HIGH | P1 |
| Proton therapy 77520-77525 config | HIGH | LOW | P1 |
| Triggering code in episode CSV | MEDIUM | MEDIUM | P1 |
| Cancer site by ICD-O-3 dual-coding | MEDIUM | HIGH | P2 |
| Gap report with RXNORM cross-check | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Required for v1.6 milestone
- P2: Add after v1.6 validation
- P3: Future consideration

---

## Implementation Notes by Feature

### Cancer Site Frequency Table

**Expected behavior:** Read CancerSiteCategories.xlsx to extract ICD code ranges and group names. Query DIAGNOSIS table for all ICD-10 codes on HL patients. Query TUMOR_REGISTRY for ICD-O-3 topography codes. For each patient, assign cancer site group based on best match (most specific group wins if code matches multiple). Produce frequency table: cancer_site_group | n_patients | n_records | pct_of_cohort. Apply HIPAA suppression (n <= 10 → suppressed). Output as styled xlsx + CSV.

**Key design decisions to make:**
- Does a single patient get counted in multiple cancer site groups if they have multiple diagnoses? (Recommendation: count unique patients per group, allow multi-group assignment, but flag)
- What happens to ICD codes that match no category? (Recommendation: "Unclassified" catch-all group with frequency count — high count here signals gap in CancerSiteCategories.xlsx coverage)
- Priority of ICD-O-3 vs ICD-10 when both match different groups? (Recommendation: ICD-O-3 takes precedence for TUMOR_REGISTRY records; ICD-10 for DIAGNOSIS records)

**Existing pattern to follow:** R/35_payer_code_frequency_av_th.R reads a reference xlsx, matches codes against PCORnet data, and produces frequency output. Same pattern applies here.

### TREATMENT_CODES Gap Report

**Expected behavior:** Extract all code tables from TreatmentVariables_2024.07.17.docx using officer package. Parse code columns and treatment type labels. Compare against TREATMENT_CODES list in R/00_config.R element by element. Report: (a) codes in docx not in config by code type and treatment type, (b) codes in config not in docx (additions made during Phases 39-42). Output as multi-sheet xlsx with same visual style as treatment_inventory.xlsx.

**Key design decisions to make:**
- How to handle docx table format variation? (Recommendation: defensive parsing with fallback; log unparseable sections)
- Should Phase 39-42 resolved codes count as "in docx" or "additions"? (Recommendation: additions are explicitly tagged with phase number in config comments — use those as "validated additions" distinct from "unexplained differences")

**Existing pattern to follow:** R/42_treatment_codes_resolved.R produces per-type resolved xlsx files. The gap report is a cross-file comparison layer on top of the same data.

### Radiation CPT Audit

**Expected behavior:** For every CPT code in the range 70010-79999, classify it as: TREATMENT (radiation delivery or management), PLANNING (simulation, dosimetry, treatment planning — legitimate but not direct delivery), IMAGING (diagnostic radiology — should not be in radiation_cpt), or EXCLUDED (other, with rationale). For codes in the data that are currently not in radiation_cpt, determine if they should be added. For codes in radiation_cpt, confirm classification is TREATMENT or PLANNING. Cite CPT descriptions from CMS MPFS RVU file (public domain).

**Key radiation CPT sub-ranges to document:**
- 70010-76999: Diagnostic Radiology (imaging — should NOT be in radiation_cpt)
- 77001-77299: Radiation Oncology — planning/simulation (legitimate but not delivery)
- 77300-77399: Treatment planning and dosimetry (PLANNING)
- 77400-77499: Radiation treatment delivery (TREATMENT — current radiation_cpt lives here)
- 77500-77599: Radiation treatment management (TREATMENT)
- 77600-77799: Hyperthermia and clinical brachytherapy (TREATMENT for 776xx/777xx)
- 77785-77799: Brachytherapy (TREATMENT)
- 78000-78999: Nuclear Medicine (imaging — NOT treatment)
- 79000-79999: Therapeutic Nuclear Medicine (TREATMENT for some codes, IMAGING for others)

**Proton therapy specifically:** 77520 (proton treatment delivery, simple), 77522 (proton delivery, simple with compensation), 77523 (proton delivery, intermediate), 77525 (proton delivery, complex) are TREATMENT codes and are absent from current radiation_cpt. These should be added.

**Existing pattern to follow:** R/39_investigate_unmatched.R produces a classification report with cited rationale per code. Same output structure applies.

### Triggering Code Column

**Expected behavior:** Extend extract_all_dates() in R/43 to return (ID, treatment_date, triggering_code, triggering_source_table) instead of just (ID, treatment_date). In R/44's calculate_episodes_detailed(), retain the triggering_code(s) associated with episode_start: collect all distinct codes that appeared on the episode_start date. In the per-type CSV output, add a triggering_codes column (comma-separated if multiple) and a triggering_source column. The D-08 schema from Phase 44 decision log will need to be updated.

**Key design decisions to make:**
- New script (R/45) or modify R/44 in place? (Recommendation: new R/45 to preserve Phase 44 as stable reference; Phase 44 is already shipped per ROADMAP.md)
- If same date has codes from multiple source tables, how to format? (Recommendation: pipe-separated "J9000|PROCEDURES" format for triggering_codes_with_source; or two columns: triggering_codes and triggering_sources)
- Should triggering code be captured for ALL dates in episode or only episode_start? (Recommendation: only episode_start — this is what defines episode identity for QA purposes)

---

## Complexity Summary

### Low Complexity (1-2 hours)
- Proton therapy 77520-77525 config update: grep config, add 4 codes with citation comments, verify in radiation_cpt vector

### Medium Complexity (half day to 1 day each)
- Cancer site frequency table: xlsx parsing, dual-table query (DIAGNOSIS + TUMOR_REGISTRY), group matching, styled output
- TREATMENT_CODES gap report: officer-based docx parsing + config comparison + styled xlsx
- Triggering code column: modify extract_all_dates() schema + calculate_episodes_detailed() aggregation + CSV schema update

### High Complexity (1-2 days)
- Radiation CPT audit: CPT range research, per-code classification with citations for 70010-79999 (roughly 1000 codes, most auto-classified by range), output formatting

---

## Sources

### Cancer Site Classification
- CancerSiteCategories.xlsx (project file, 42 groups, ICD-10 and ICD-O-3 code ranges)
- ICD-O-3 topography code documentation: https://www.naaccr.org/icdo3/
- PCORnet CDM v7.0 TUMOR_REGISTRY table spec: https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf

### CPT Radiation Codes
- CMS MPFS RVU files (public domain CPT short descriptors): https://www.cms.gov/medicare/payment/fee-schedules/physician/pfs-relative-value-files
- AMA CPT codebook section D (Radiology, 70010-79999) — requires AMA license for full descriptors
- CMS OPPS Addendum B (radiation oncology): https://www.cms.gov/medicare/payment/prospective-payment-systems/hospital-outpatient/addendum-b
- Proton therapy CPT codes 77520-77525: confirmed in AMA CPT 2025 section 77520-77525 (Proton Beam Treatment Delivery)

### Docx Parsing (R)
- officer package documentation: https://davidgohel.github.io/officer/
- docxtractr package: https://cran.r-project.org/package=docxtractr

### Existing Pipeline Patterns
- R/35_payer_code_frequency_av_th.R: xlsx-reference cross-match pattern
- R/39_investigate_unmatched.R: code classification with cited rationale pattern
- R/42_treatment_codes_resolved.R: per-type resolved xlsx output pattern
- R/44_treatment_episodes.R: episode CSV schema (D-08) to be extended with triggering_codes

---
*Feature research for: v1.6 Treatment Code Validation & Cancer Site Analysis*
*Researched: 2026-04-21*
