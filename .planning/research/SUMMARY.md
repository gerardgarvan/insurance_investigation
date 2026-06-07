# Project Research Summary

**Project:** PCORnet Payer Variable Investigation (R Pipeline) — v2.3 Gantt Data Enrichment
**Domain:** Oncology treatment timeline data enrichment and clinical metadata integration
**Researched:** 2026-06-07
**Confidence:** HIGH

## Executive Summary

This research evaluates enrichment of existing Gantt chart exports (v2: 16 columns) with clinical metadata from all_codes_resolved2.xlsx (203 chemotherapy codes, 12 radiation codes, 8 SCT codes across 8 sheets). **The good news: no new stack components required.** All necessary libraries (openxlsx2, dplyr, stringr, checkmate) are already validated across 98 existing scripts. Integration follows proven patterns from R/57 (drug grouping) and R/28 (episode enrichment).

**Recommended approach:** Add 5 metadata columns (medication names, F/S/E/N treatment line labels, code type, source table, SCT cross-use flags) by creating a utility module (R/utils/utils_xlsx_lookups.R) that parses xlsx sheets, then applying lookups in existing R/28 episode classification before propagating enriched data through R/52 Gantt v2 export. The critical path starts with **code removal impact analysis** — 5 false-positive SCT codes (Z94.84 status codes, T86.x complications) must be audited and removed before enrichment to prevent propagating incorrect treatment classifications.

**Key risks and mitigations:** (1) **Many-to-many join explosion** — xlsx may contain duplicate code entries; prevent with `relationship = "many-to-one"` assertion and pre-join deduplication. (2) **Schema breaking changes** — append new columns to end of existing v2 schema (columns 17-21), never insert mid-schema. (3) **Unresolved classifications** — 8 vitamin combo codes and 2 CAR-T codes marked "TBD"; filter to HIGH/MEDIUM confidence rows only for production, export unresolved codes separately for clinical SME review. (4) **Cross-use flag overcounting** — Melphalan is both chemotherapy and SCT conditioning; implement temporal context logic (within 30 days of SCT) rather than boolean flags to prevent category sums exceeding 100%.

## Key Findings

### Recommended Stack

**NO NEW DEPENDENCIES.** All enrichment work uses existing validated libraries already in renv.lock. The xlsx → lookup → join pattern matches R/57 drug grouping instances (wb_load + wb_to_df to read multi-sheet xlsx, build named vectors, left_join to detail data).

**Core technologies:**
- **openxlsx2 1.8.2+** (xlsx reading) — Already used in 30+ scripts; handles merged headers and multi-line cells; read+write capability unlike readxl
- **dplyr 1.2.0+** (data joins/filters) — Industry standard; `left_join()` for metadata enrichment, `case_when()` for F/S/E/N normalization
- **stringr 1.5.1+** (string cleaning) — Clean F/S/E/N labels (normalize NA/blank/mixed case), handle Y/y/yes variants in cross-use flags
- **checkmate 2.3.2+** (input validation) — Validate xlsx exists, lookup tables have expected columns, enrichment preserves row counts

**Integration pattern from R/57:**
```r
ref_wb <- wb_load("all_codes_resolved2.xlsx")
chemo_sheet <- wb_to_df(ref_wb, sheet = "Chemotherapy", start_row = 2)
# Column access by index (reliable for multi-line headers)
code_col <- chemo_sheet[[1]]         # Column A: Code
med_col <- chemo_sheet[[3]]          # Column C: Medication
fsen_col <- chemo_sheet[[8]]         # Column H: F/S/E/N labels
```

**What NOT to add:** readxl (replaced by openxlsx2), xlsx (deprecated Java-based), data.table (conflicts with project's tidyverse style), writexl (write-only).

### Expected Features

**Must have (table stakes):**
- **Treatment line classification (F/S/E/N)** — Standard oncology nomenclature (first-line, second-line, salvage, not-for-Hodgkin); clinicians expect this for treatment sequencing analysis
- **Human-readable medication names** — RxNorm codes alone meaningless; need generic names ("Doxorubicin" not "224905") from xlsx column C
- **Code type + source table metadata** — Essential for data provenance (RXNORM from PRESCRIBING, CPT/HCPCS from PROCEDURES, ICD-10-CM from DIAGNOSIS)
- **False-positive SCT code removal** — Status/complication codes (Z94.84, T86.x) mistaken for procedures; must remove from treatment detection to fix 2-3x episode inflation

**Should have (differentiators):**
- **SCT conditioning/immunotherapy cross-use flags** — Melphalan, Carmustine dual-purpose (chemo + SCT conditioning); flag prevents misclassification when codes appear outside transplant context
- **Questionable immunotherapy code flagging** — 8 vitamin combos + 2 CAR-T codes need manual review flags (not removed, just marked for clinical validation)

**Defer to v2.4+:**
- **Per-code line classification** (vs regimen-level) — Requires episode boundary formalization deferred to v3.x
- **Episode-level drug group enrichment** — Drug grouping tables already exist as separate output; nice-to-have but not essential
- **Treatment line trajectory visualization** — ggplot2 modification can be done post-export with existing CSV data
- **Multi-source code deduplication tracking** — Overlap analysis pattern exists but not integrated into Gantt output

**Anti-features (explicitly avoid):**
- **Automated treatment line inference without clean period validation** — Requires clinical context; rely on xlsx-curated F/S/E/N labels
- **Per-patient line numbering (line 1, 2, 3...)** — Out of scope per PROJECT.md; sequential numbering deferred to v3.x
- **Medication name resolution for non-chemotherapy** — PROJECT.md: "Drug name resolution for chemotherapy only"; keep blank for radiation/SCT
- **Code type auto-detection from external APIs** — Adds runtime dependency; use deterministic lookup from source table instead

### Architecture Approach

**Integration point: R/28 episode classification** — This is where enrichment happens (existing pattern: cancer linkage, regimen detection, drug groups at lines 450-600). Add 5 new columns here before saving treatment_episodes.rds. R/51 (v1 export) ignores new columns; R/52 (v2 export) propagates them to Gantt CSV.

**Major components:**

1. **R/utils/utils_xlsx_lookups.R (NEW utility module)** — Parses all_codes_resolved2.xlsx (8 sheets), extracts columns 1 (Code), 3 (Medication), 4 (Code Type), 5 (Source Table), 8 (F/S/E/N), 9 (Cross-use flags). Returns named vectors for code → metadata lookups. **Rationale:** NOT in R/00_config.R (already 2000+ lines, would bloat further). NOT inline in R/51/R/52 (DRY violation). Utility module matches existing pattern (10 utils files already).

2. **R/28_episode_classification.R (MODIFIED)** — Sources utils_xlsx_lookups.R, loads xlsx once at script start, derives 5 new columns from triggering_codes + xlsx lookups. **Derivation logic:** For line_label, aggregate from all codes in episode (if any "F" → "F", else "S", else "E", else "N"). For medication_names/code_type/source_table, map each code and join with commas. For SCT cross-use, episode-level aggregation (if any "Conditioning" + any "Immunotherapy" → "Both").

3. **R/00_config.R (MODIFIED — code removal only)** — Remove 5 false-positive SCT codes from TREATMENT_CODES$sct_* vectors with inline comments documenting removal rationale. **Impact:** R/20 treatment inventory detects fewer SCT codes (expected), R/28 episodes using only removed codes no longer classified as SCT, R/51-R/52 Gantt exports reflect corrected treatment types.

4. **R/52_gantt_v2_export.R (MODIFIED — schema extension)** — Add 5 columns to episodes_export (lines 260-292) and detail_export (lines 299-329). Apply Phase 64 cleanup (semicolon separators for multi-value fields). **Schema v2.3:** Episodes 16 → 21 columns, Detail 14 → 19 columns (append to end for non-breaking change). Death/HL Diagnosis pseudo-rows get NA for all new columns.

**Data flow (post-enrichment):**
```
R/00_config.R (5 SCT codes removed)
    ↓
R/utils/utils_xlsx_lookups.R (load_xlsx_lookups() → named vectors)
    ↓
R/28_episode_classification.R (derive 5 new columns, save enriched RDS)
    ↓
R/51 (v1 export, UNCHANGED — ignores new columns, writes 14-col CSV)
    ↓
R/52 (v2 export, MODIFIED — writes 21-col episodes, 19-col detail CSV)
```

### Critical Pitfalls

1. **Removing active codes without impact analysis** — Z94.84, T86.5, T86.09 currently active in CODE_SUBCATEGORY_MAP, triggering treatment episodes. Removing without tracking causes silent data loss (episodes disappear), attrition mismatches, broken backward compatibility. **Prevention:** Run `treatment_episodes |> filter(code %in% deprecated_codes) |> count()` to quantify affected episodes, document impact in `.planning/code-removal-impact.md`, implement deprecation flag instead of hard removal, update smoke test to validate deprecated codes don't appear in new outputs.

2. **Many-to-many join explosion from reference data** — If xlsx has duplicate entries for a code (e.g., two rows for "Melphalan" with conflicting classifications), join produces row duplication. Per dplyr docs: "If x has 100 rows for id=1 and y has 5 rows for id=1, cross product returns 500 rows." **Prevention:** Pre-join validation `xlsx_data |> count(code) |> filter(n > 1)` and error on duplicates, use `left_join(..., relationship = "many-to-one")` to error on many-to-many, unit test `expect_equal(nrow(enriched), nrow(original))`.

3. **Unresolved classifications propagating to production** — 8 vitamin combos flagged as questionable immunotherapy, 2 CAR-T codes with TBD classification. If joined as-is, Gantt CSV exports with `immunotherapy_flag = NA`, downstream analysts filter `!is.na()` and silently exclude questionable codes. **Prevention:** Add `classification_confidence` column (HIGH/MEDIUM/LOW/UNRESOLVED), filter to HIGH/MEDIUM only for production, export UNRESOLVED to separate `unresolved_codes_for_review.csv` for clinical SME.

4. **Cross-use flag logic without mutual exclusivity** — Melphalan counted in both "chemotherapy" and "SCT conditioning" causes category sums >100%. Research confirms conditioning regimens use standard chemo agents (BEAM = carmustine + etoposide + cytarabine + melphalan). **Prevention:** Implement temporal context flags (`is_sct_conditioning_context = TRUE` when code in conditioning_drugs AND within 30 days before SCT episode), use primary + secondary categories (mutually exclusive at primary level), document aggregation rules (sum primary_category only), unit test `sum(category_counts$n) == nrow(episodes)`.

5. **Schema extension breaking backward compatibility** — Adding 5 columns to Gantt v2 (16 → 21) without versioning breaks downstream consumers (R scripts with `col_types = cols(...)` fail, Excel macros with hardcoded column positions break, Tableau calculated fields reference wrong columns). **Prevention:** Append-only schema (new columns at end, not inserted mid-schema), versioned filenames (`gantt_v3.csv` alongside `gantt_v2.csv`), schema documentation with migration guide, nullable new columns with sensible defaults (NA, empty string), smoke test validates column order and names.

## Implications for Roadmap

Based on research, suggested phase structure prioritizes **data quality fixes before enrichment** to prevent propagating false positives.

### Phase 1: Code Removal Impact Analysis & Cleanup
**Rationale:** Must quantify and remove false-positive SCT codes (Z94.84, T86.x) before enrichment to prevent enriching incorrect treatment classifications. Affects ~8% of "Has SCT" cohort (status codes inflate episode counts 2-3x).

**Delivers:**
- Impact analysis script: `analysis/code_removal_impact.R` (counts affected episodes, patients, date ranges)
- Updated CODE_SUBCATEGORY_MAP (5 codes removed, documented)
- `.planning/code-removal-impact.md` (deprecation rationale, affected counts)
- Smoke test update: Section 15 validates deprecated codes absent from new treatment_episodes

**Addresses:** Pitfall #1 (removing active codes without impact analysis), Pitfall #6 (false-positive episodes from status codes)

**Avoids:** Silent data loss, attrition mismatches, downstream confusion ("Why did patient X lose their SCT episode?")

### Phase 2: Reference Data Validation & Metadata Enrichment
**Rationale:** After code cleanup, integrate xlsx metadata. Validation before join prevents many-to-many explosion. Confidence filtering prevents unresolved classifications in production.

**Delivers:**
- R/utils/utils_xlsx_lookups.R (load_xlsx_lookups() function)
- Pre-join validation (uniqueness check, deduplication logic)
- Confidence filtering (HIGH/MEDIUM only, export UNRESOLVED separately)
- R/28 modifications (5 new columns: line_label, medication_names, code_type, source_table_source, sct_cross_use_flag)
- Enriched treatment_episodes.rds (+5 columns)

**Uses:** openxlsx2 (wb_load + wb_to_df pattern from R/57), dplyr (left_join with relationship assertion), stringr (F/S/E/N normalization), checkmate (input validation)

**Implements:** Utility module pattern, episode-level enrichment (R/28 lines 450-600 pattern)

**Addresses:** Table stakes features (medication names, code type metadata), Pitfall #2 (many-to-many join), Pitfall #3 (unresolved classifications)

**Avoids:** Row explosion from duplicate xlsx entries, NA propagation from TBD codes

### Phase 3: Gantt v2 Schema Extension & Export
**Rationale:** After enrichment in R/28, extend R/52 export to propagate 5 new columns to Gantt CSV. Append-only schema maintains backward compatibility (v1 export unchanged).

**Delivers:**
- R/52 modifications (select new columns, apply Phase 64 cleanup, update pseudo-rows)
- gantt_episodes_v2.csv (16 → 21 columns)
- gantt_detail_v2.csv (14 → 19 columns)
- Schema documentation: Column ordering, nullability, example values
- Smoke test update: Section 52 validates 21-column schema, column order, new column value distributions

**Addresses:** Should-have features (SCT cross-use flags, questionable immunotherapy flagging), Pitfall #5 (schema breaking changes)

**Avoids:** Mid-schema column insertion, backward incompatibility (v1 export remains 14 columns)

### Phase 4: Cross-Use Flag Implementation & Validation
**Rationale:** After basic enrichment working, add temporal context logic for SCT conditioning flags. Requires episode date analysis (within 30 days of SCT).

**Delivers:**
- Temporal context flags: `is_sct_conditioning_context` (code in conditioning_drugs AND within 30 days before SCT episode)
- Primary + secondary category columns (mutually exclusive aggregation)
- Category aggregation rules documentation
- Smoke test update: Section 36 validates `sum(primary_category) == nrow(episodes)`

**Addresses:** Pitfall #4 (cross-use flag overcounting), should-have feature (SCT conditioning/immunotherapy dual-use)

**Avoids:** Category sums exceeding 100%, ambiguous treatment intent classification

### Phase Ordering Rationale

- **Phase 1 before Phase 2:** Must audit false-positive codes before enriching them; prevents propagating incorrect classifications to metadata layer
- **Phase 2 before Phase 3:** Enrichment happens in R/28 (episode classification); R/52 (export) consumes enriched RDS; dependency order is R/28 → R/52
- **Phase 3 before Phase 4:** Basic enrichment (medication names, code types) is table stakes and low-risk; cross-use flags with temporal context are complex and should build on validated enrichment pattern
- **Grouping rationale:** Each phase has single responsibility (Phase 1 = cleanup, Phase 2 = enrichment, Phase 3 = export, Phase 4 = advanced logic); matches existing architecture (R/28 enriches, R/52 exports)

### Research Flags

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Code Removal):** Well-documented in PROJECT.md Phase 60 ("Drop ICD DX codes from SCT detection"); impact analysis pattern exists in R/88 smoke test sections
- **Phase 2 (Metadata Enrichment):** Proven pattern from R/57 (xlsx → lookup → join); openxlsx2 usage validated across 30+ scripts
- **Phase 3 (Gantt Export):** Extension of existing R/52 pattern; Phase 64 cleanup (semicolon separators) already established
- **Phase 4 (Cross-Use Flags):** Temporal context logic similar to existing first-line detection (60-day clean period from Phase 62)

**No phases need deeper research.** All patterns validated in existing codebase, all libraries in renv.lock, all integration points explicit.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | **HIGH** | All libraries validated in 30+ existing scripts; no new dependencies; openxlsx2 + dplyr patterns proven in R/57 drug grouping |
| Features | **HIGH** | Table stakes (medication names, code types) clearly defined by oncology domain; should-haves (cross-use flags) have clinical precedent in conditioning regimens |
| Architecture | **HIGH** | Codebase patterns well-established (R/28 enrichment, R/52 export, utility module pattern); xlsx structure verified via Python inspection; integration points explicit |
| Pitfalls | **MEDIUM-HIGH** | Many-to-many join, schema breaking changes, cross-use overcounting are well-documented in dplyr/schema evolution literature; code removal impact is domain-specific but straightforward to audit |

**Overall confidence:** **HIGH**

Research is comprehensive with no major gaps. All proposed phases have validated implementation patterns. Only medium confidence on pitfalls is due to domain-specific nuances (oncology treatment classification, PCORnet CDM quirks) but these are addressable through defensive coding (pre-join validation, temporal context logic, smoke test coverage).

### Gaps to Address

**During Phase 1 (Code Removal):**
- **Actual row counts:** Research identifies Z94.84, T86.x as false positives but doesn't quantify episodes affected. Run `treatment_episodes |> filter(code %in% deprecated_codes) |> count()` to get exact numbers for documentation.

**During Phase 2 (Enrichment):**
- **Radiation/SCT/Immunotherapy sheet column structure:** STACK.md documents that Radiation sheet lacks Medication column (col 3), SCT sheet has different col 7/8/9 meanings. Defensive column indexing strategy provided but needs verification during xlsx read: print `ncol(rad_sheet)` and `names(rad_sheet)` to confirm before extraction.
- **F/S/E/N label variants:** FEATURES.md mentions "N=newly diagnosed, F=first-line, S=second-line, E=salvage" but xlsx may have "NA", "N/A", mixed case, or full strings. Normalization logic provided (`str_trim(str_to_upper())`) but needs validation against actual xlsx values.

**During Phase 4 (Cross-Use Flags):**
- **SCT conditioning temporal window:** 30 days before SCT is assumed but not clinically validated. Literature confirms "within 14 days of SCT = BEAM conditioning regimen" (PITFALLS.md source). Validate 30-day window with clinical SME or tighten to 14 days based on literature.

**All gaps are implementation-level details, not architectural uncertainties.** Proceed with confidence.

## Sources

### Primary (HIGH confidence)

**Codebase inspection:**
- R/00_config.R (2000 lines, TREATMENT_CODES lookup patterns, CODE_SUBCATEGORY_MAP)
- R/28_episode_classification.R (episode enrichment pattern, lines 450-600 existing metadata derivation)
- R/51-R/52 (dual-schema export pattern, v1 stable at 14 columns, v2 evolves)
- R/57_drug_grouping_instances.R (wb_load + wb_to_df xlsx reading pattern, lines 113-131)
- R/88_smoke_test_comprehensive.R (validation patterns for new features)
- all_codes_resolved2.xlsx (203 chemotherapy codes, 12 radiation, 8 SCT, 8 sheets total; Python openpyxl inspection 2026-06-07)

**Official documentation:**
- [CRAN openxlsx2](https://cran.r-project.org/web/packages/openxlsx2/index.html) v1.8.2 (Dec 2025)
- [dplyr mutate-joins reference](https://dplyr.tidyverse.org/reference/mutate-joins.html) — relationship = "many-to-one" assertion (dplyr 1.1+)
- [R for Data Science (2e) - Joins](https://r4ds.hadley.nz/joins.html) — Many-to-many join pitfalls
- [PCORnet Common Data Model v7.0](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf)

### Secondary (MEDIUM confidence)

**Oncology treatment classification:**
- [Stem Cell Transplant Conditioning Regimens](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12293537/) — Chemotherapy agents in conditioning (cyclophosphamide, busulfan, carmustine/BCNU, melphalan/BEAM)
- [Engineering Immunity: CAR-T Cell Therapy](https://www.mdpi.com/1422-0067/27/2/909) — CAR-T as advanced therapy medicinal products (ATMPs), distinct from traditional immunotherapy
- [Development and Utility of Cancer Medications Enquiry Database](https://pmc.ncbi.nlm.nih.gov/articles/PMC7868035/) — Varying therapy definitions (chemotherapy vs immunotherapy) affect study design and classification

**Schema evolution best practices:**
- [Backward Compatible Database Changes](https://planetscale.com/blog/backward-compatible-databases-changes) — Additive changes (new columns at end)
- [Data Lineage & Impact Analysis](https://atlan.com/know/data-lineage-impact-analysis/) — Downstream failures from column additions/removals

**Data quality validation:**
- [Exploration of PCORnet Data Resources](https://ascopubs.org/doi/10.1200/CCI.19.00142) — Treatment procedures identified via CPT/HCPCS codes (not ICD diagnosis codes)
- [9 Common Data Quality Problems 2026](https://www.ovaledge.com/blog/data-quality-problems) — Duplicate records without unique IDs

---

*Research completed: 2026-06-07*
*Ready for roadmap: yes*
*Files synthesized: STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md*
*Phase count: 4 suggested phases with clear dependencies and rationale*
