# Pitfalls Research

**Domain:** Treatment Metadata Enrichment for Oncology Data Pipelines
**Researched:** 2026-06-07
**Confidence:** MEDIUM-HIGH

## Critical Pitfalls

### Pitfall 1: Removing Active Codes Without Downstream Impact Analysis

**What goes wrong:**
Codes marked "Remove" in reference data (Z94.84, T86.5, T86.09, Z48.290, HEMATOLOGIC_TRANSPLANT_AND_ENDOC) are currently active in CODE_SUBCATEGORY_MAP and actively triggering treatment episode creation. Removing them without tracking downstream dependencies causes:
- Silent data loss (treatment episodes disappear from output)
- Attrition count mismatches (prior cohorts no longer reproducible)
- Broken backward compatibility (RDS cache files contain episodes for removed codes)
- Ambiguous documentation ("Why did patient X lose their SCT episode?")

**Why it happens:**
These codes were initially included based on keyword matching ("transplant" → SCT category) without clinical validation. Upon review, they represent post-transplant complications/status codes (Z94.84 = bone marrow transplant status, T86.x = transplant complications, Z48.290 = aftercare following transplant), not the transplant procedure itself. The reference xlsx marks them "Remove" but doesn't specify impact on existing data.

**How to avoid:**
1. **Before removal:** Run `treatment_episodes |> filter(code %in% c("Z94.84", "T86.5", "T86.09", "Z48.290", "HEMATOLOGIC_TRANSPLANT_AND_ENDOC")) |> count()` to quantify affected episodes
2. **Document impact:** Create `.planning/code-removal-impact.md` with counts, affected patients, and date ranges
3. **Version the mapping:** Add `CODE_SUBCATEGORY_MAP_V2` with removed codes excluded, keep V1 for reproducibility
4. **Archive flag approach:** Instead of removing, add `is_deprecated = TRUE` column, filter in treatment detection but preserve in metadata joins
5. **Update smoke test:** Add Section validating that deprecated codes don't appear in new treatment_episodes but do appear in archived outputs

**Warning signs:**
- Reference data has "Remove" annotation but codes still exist in active lookup tables
- No impact analysis script exists
- Smoke test doesn't validate deprecated code handling
- No versioning strategy for CODE_SUBCATEGORY_MAP

**Phase to address:**
Phase 1 (Code Removal Impact Analysis) — Must precede Phase 2 (Metadata Enrichment)

---

### Pitfall 2: Many-to-Many Join Explosion from Reference Data

**What goes wrong:**
Joining `treatment_episodes` (one row per code instance) to `all_codes_resolved2.xlsx` (one row per code definition) appears safe (one-to-one), but hidden duplicates in reference data cause row explosion:
- If xlsx has duplicate entries for a code (e.g., two rows for "Melphalan" with conflicting classifications), join produces 2x rows
- If xlsx has both exact code and wildcard pattern match, both rows join
- Result: 14-column Gantt suddenly has 50,000 rows instead of 25,000
- Downstream: Aggregations double-count episodes, patient timelines show phantom duplicates

Per dplyr documentation: "If both x and y have multiple matches for a key, the result is the cross product... if x has 100 rows for id=1 and y has 5 rows for id=1, it returns 500 rows for id=1" ([R for Data Science - Joins](https://r4ds.hadley.nz/joins.html)).

**Why it happens:**
all_codes_resolved2.xlsx is a working document with unresolved questions (8 vitamin combos, 2 CAR-T codes TBD). Excel allows duplicate entries during exploratory work. No uniqueness constraint on code columns.

**How to avoid:**
1. **Pre-join validation:** Run `xlsx_data |> count(code_with_type) |> filter(n > 1)` and error if duplicates exist
2. **Assert relationship:** Use `left_join(..., relationship = "many-to-one")` (dplyr 1.1+) to error on many-to-many ([dplyr mutate-joins reference](https://dplyr.tidyverse.org/reference/mutate-joins.html))
3. **Deduplicate reference data:** Filter xlsx to `distinct(code_with_type, .keep_all = TRUE)` with precedence rules (e.g., prioritize rows with non-NA medication_name)
4. **Unit test join:** `expect_equal(nrow(episodes_enriched), nrow(treatment_episodes))`

**Warning signs:**
- Reference xlsx has "TBD" or "?" in classification columns
- No uniqueness check before join
- Row count increases after join
- Smoke test doesn't validate pre/post join row counts

**Phase to address:**
Phase 2 (Reference Data Validation & Deduplication) — First sub-task before enrichment join

---

### Pitfall 3: Unresolved Classifications Propagating to Production Output

**What goes wrong:**
8 vitamin combo codes flagged as questionable immunotherapy and 2 CAR-T codes with TBD classification (immunotherapy vs CAR-T category) exist in all_codes_resolved2.xlsx. If joined as-is:
- Gantt CSV exports with `immunotherapy_flag = NA` or `treatment_line = "?"`
- Downstream analysts filter `!is.na(immunotherapy_flag)`, silently excluding questionable codes
- Published figures show incomplete treatment timelines
- Clinical reviewers question data quality: "Why is this vitamin supplement labeled immunotherapy?"

Research shows this is a known oncology data quality issue: "Varying definitions of cancer therapies (such as what constitutes chemotherapy vs immunotherapy and modes of administration)... have made comparisons and evaluation of treatment across studies challenging, with varying therapy definitions affecting study design, misclassification, and results" ([Development and Utility of Cancer Medications Enquiry Database](https://pmc.ncbi.nlm.nih.gov/articles/PMC7868035/)).

**Why it happens:**
Clinical domain expertise required for classification exceeds data engineering scope. Codes fall into gray areas:
- Vitamin combos: Supportive care or immunomodulatory agents?
- CAR-T: Technically cellular immunotherapy, but often tracked separately due to distinct workflow/toxicity profile

Per 2026 literature: "CAR-T cell therapies are advanced therapy medicinal products (ATMPs) that represent a new generation of personalized cancer immunotherapy" ([Engineering Immunity: CAR-T Cell Therapy](https://www.mdpi.com/1422-0067/27/2/909)), but also "Within the broader immunotherapy landscape, engineered tumor-specific T cell receptors (TCR) and chimeric antigen receptors (CAR) comprise one category of cellular immunotherapy approaches" ([Editorial: Cellular immunotherapy](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12605324/)). Both classifications are valid depending on analytical context.

**How to avoid:**
1. **Flag mechanism:** Add `classification_confidence` column (`HIGH/MEDIUM/LOW/UNRESOLVED`)
2. **Defer to output:** Export questionable codes with `classification_confidence = "UNRESOLVED"` rather than blocking on resolution
3. **Document rationale:** Add `classification_notes` column with clinical reasoning or "TBD - requires oncology SME review"
4. **Staged rollout:** Phase 1 exports confident classifications only (HIGH/MEDIUM), Phase 2 adds UNRESOLVED with documented caveats
5. **Clinical review checkpoint:** Schedule SME review session before production deployment, not before development

**Warning signs:**
- Reference data has "TBD", "?", or blank classification cells
- No confidence/quality column exists
- Enrichment logic treats all classifications equally (no filtering by confidence)
- No clinical SME review scheduled

**Phase to address:**
Phase 2 (Metadata Enrichment) with explicit confidence filtering + Phase 4 (Clinical SME Review) for resolution

---

### Pitfall 4: Cross-Use Flag Logic Without Mutual Exclusivity Validation

**What goes wrong:**
5 chemotherapy codes flagged as SCT conditioning agents (Melphalan, Carmustine, Temsirolimus) and 2 CAR-T codes flagged for potential dual classification (immunotherapy vs CAR-T). If cross-use flags implemented naively:
- Melphalan episode counted in both "chemotherapy" and "SCT conditioning" groups
- Summing counts across categories produces >100% totals
- Payer stratification logic breaks: "Patient has chemo but no SCT? Check: Conditioning flag = TRUE... wait, is this SCT or not?"

Research confirms conditioning regimens use standard chemotherapy agents: "Total-body irradiation and cyclophosphamide or busulfan and cyclophosphamide are the commonly used myeloablative therapies" and "BCNU (carmustine), etoposide, ara-C (cytarabine), and melphalan (BEAM regimen)" ([Stem Cell Transplant Conditioning Regimens](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12293537/)). These drugs appear in both chemotherapy and SCT contexts — context is temporal (within 30 days before SCT) not code-based.

**Why it happens:**
Same drug code appears in multiple clinical contexts. CODE_SUBCATEGORY_MAP assigns single category per code, but reality is multi-modal:
- Melphalan alone = multiple myeloma chemotherapy
- Melphalan + Carmustine + Etoposide within 14 days of SCT = BEAM conditioning regimen

**How to avoid:**
1. **Temporal context flags:** Add `is_sct_conditioning_context = TRUE` when (code in conditioning_drugs) AND (within 30 days before SCT episode)
2. **Primary + secondary categories:** `primary_category = "chemotherapy"`, `secondary_category = "SCT_conditioning"` (mutually exclusive at primary level)
3. **Explicit aggregation rules:** Document that category sums should use `primary_category` only; `secondary_category` for subgroup analysis
4. **Unit test mutual exclusivity:** `expect_true(sum(category_counts$n) == nrow(treatment_episodes))`

**Warning signs:**
- Cross-use flags implemented as boolean columns without aggregation guidance
- No temporal context logic (dates relative to SCT)
- Smoke test sums don't validate to total episode count
- Category definitions document doesn't specify mutual exclusivity rules

**Phase to address:**
Phase 3 (Cross-Use Flag Implementation) with temporal context logic

---

### Pitfall 5: Schema Extension Breaking Backward Compatibility

**What goes wrong:**
Gantt v1 has 14 columns, v2 has 16 columns. Adding 5+ new columns (treatment_line, medication_name, code_type, source_table, cross_use_flags) without schema versioning:
- Existing R scripts that read Gantt CSV with `col_types = cols(...)` fail with "7 columns expected, 19 found"
- Excel macros with hardcoded column positions (column P = payer) break when new columns inserted at column C
- Downstream Python pipeline assumes column 15 = is_first_line, gets medication_name instead
- Published Tableau dashboards break (calculated fields reference column index not name)

Schema evolution research confirms: "Adding a field, removing a column, or altering nullability may seem harmless upstream, but can trigger downstream failures in production" and "unexpected additions or removals of columns can break downstream views" ([Data Lineage & Impact Analysis](https://atlan.com/know/data-lineage-impact-analysis/)).

**Why it happens:**
No formal schema versioning strategy. Outputs named `gantt_export.csv` get silently overwritten with new schema. Consumers assume stable schema.

**How to avoid:**
1. **Append-only schema:** New columns added at end (columns 17-21), not inserted mid-schema
2. **Versioned filenames:** `gantt_export_v3.csv` (new schema) alongside `gantt_export_v2.csv` (legacy, frozen)
3. **Schema documentation:** `docs/gantt_schema_v3.md` with migration guide from v2
4. **Nullable new columns:** All new columns have sensible defaults (NA, empty string, FALSE) so old rows don't break
5. **Smoke test schema contract:** `expect_named(gantt_v3, c("patid", "start_date", ..., "medication_name", "cross_use_flag"))` in fixed order

Per best practices: "One of the safest ways to ensure backward compatible database changes is through additive changes—adding new columns or tables without altering existing ones—ensuring that older applications continue to function correctly while new features are introduced" ([Backward Compatible Database Changes](https://planetscale.com/blog/backward-compatible-databases-changes)).

**Warning signs:**
- No schema version number in filename or header
- Columns inserted mid-schema (breaking column index references)
- No migration guide for downstream consumers
- Smoke test doesn't validate column order and names

**Phase to address:**
Phase 2 (Gantt Schema v3 Design) — Must define append-only schema before implementation

---

### Pitfall 6: False-Positive Treatment Episodes from Status/Complication Codes

**What goes wrong:**
Z94.84 (bone marrow transplant status), T86.x (transplant complications), Z48.290 (aftercare following transplant) currently trigger SCT episode creation. Result:
- Patient with 2015 SCT shows phantom "SCT episodes" every time they have a follow-up visit in 2020-2025
- Attrition logic filters "patients with SCT" → includes patients who only have status codes, not actual procedures
- Treatment timeline shows SCT spanning 10 years (diagnosis codes, not treatment events)
- Episode counts inflated 2-3x (one actual PROCEDURES code + dozens of DIAGNOSIS status codes)

This is a PCORnet CDM-specific pitfall. Per research: "Treatment and test procedures have been identified using Current Procedural Terminology (CPT) and Healthcare Common Procedure Coding System (HCPCS) codes within PCORnet CDM tables" ([PCORnet Data Resources](https://ascopubs.org/doi/10.1200/CCI.19.00142)). Status codes (ICD-10-CM) are diagnosis codes, not procedure codes — mixing them causes category confusion.

Project decision already addresses this partially: "Drop ICD DX codes from SCT detection — Diagnosis codes indicate history/status, not procedure occurrence — PROCEDURES/PRESCRIBING/DISPENSING are authoritative" (PROJECT.md, Phase 60). But implementation incomplete — codes still in CODE_SUBCATEGORY_MAP.

**Why it happens:**
Initial code mapping used keyword search ("transplant" → SCT category) without filtering by code system (CPT/HCPCS vs ICD-10-CM) or table source (PROCEDURES vs DIAGNOSIS). ICD-10-CM Z-codes and T-codes are valid in DIAGNOSIS table but don't represent treatment events.

**How to avoid:**
1. **Table source restriction:** SCT detection from PROCEDURES/DISPENSING/MED_ADMIN only, exclude DIAGNOSIS table
2. **Code system validation:** ICD-10-CM codes (Zxx.xx, Txx.xx pattern) automatically excluded from treatment detection
3. **Audit existing episodes:** `treatment_episodes |> filter(source_table == "DIAGNOSIS", sub_category == "SCT") |> count()` to quantify false positives
4. **Reclassify vs remove:** Z94.84 et al. move to "SCT_history" category (not treatment), or remove entirely
5. **Document distinction:** Add comments in CODE_SUBCATEGORY_MAP: `# Z94.84: Status code, not procedure — excluded from treatment detection`

**Warning signs:**
- ICD-10-CM codes in treatment detection logic
- DIAGNOSIS table included in SCT/chemotherapy source tables
- Episode counts orders of magnitude higher than expected
- Treatment durations spanning years (status codes have ongoing dates)

**Phase to address:**
Phase 1 (Code Removal Impact Analysis) — Quantify false positives before schema changes

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Join all xlsx columns even if some have NAs | "Future-proof" — new metadata available when filled | NA propagation breaks downstream filters; unclear which NAs are "missing data" vs "not applicable" | Never — filter to complete/confident rows only |
| Use Excel row numbers as join keys | Fast xlsx iteration during development | Inserting rows breaks joins; no stable identifier for code definitions | Never — use code+type composite key |
| Overwrite existing Gantt CSV with new schema | Avoids filename proliferation | Silent breaking changes for downstream consumers | Only in pre-release development; never post-v1.0 |
| Hard-code column positions in aggregation logic | Faster than referencing by name | Schema reordering breaks logic silently | Never — use `select(medication_name, ...)` not `.[, 15]` |
| Defer clinical SME review until "output looks wrong" | Unblocks development without scheduling meetings | Waste time building features for misclassified codes; rework after SME corrections | Only for LOW confidence codes explicitly flagged as "pending review" |
| Implement cross-use flags as simple boolean (no context) | Easiest to implement | Category summaries produce >100% totals; no way to determine primary category | Only for non-overlapping categories (e.g., oral vs IV route) |

## Integration Gotchas

Common mistakes when connecting to external reference data.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Excel xlsx reference data | Assume first row is always header, no validation | Use `read_excel(..., skip = 0)` and validate expected column names with `assert_names()` |
| Excel xlsx reference data | Assume no hidden rows/columns with metadata | Filter `!is.na(code)` after read to drop blank/comment rows |
| Excel xlsx reference data | Trust Excel dates (serial numbers vs formatted strings) | Specify `col_types = c(..., medication_name = "text", ...)` to prevent date autoconversion |
| F/S/E/N treatment line labels | Join on exact string match ("First line" vs "first line" vs "F") | Normalize to single-char codes before join: `str_to_upper(str_sub(treatment_line, 1, 1))` |
| RxNorm medication names | Assume one name per code | Codes have generic name + brand names; pick canonical with precedence (generic > brand > ingredient) |
| Code type classification | Infer from code pattern (5-digit = CPT, J-code = HCPCS) | Use source_table explicitly: PROCEDURES = CPT/HCPCS, PRESCRIBING = RXNORM, DIAGNOSIS = ICD-10-CM |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full xlsx re-join on every run (no caching) | Slow runs (10-20 sec overhead) | Cache enriched lookup table as RDS: `cache/code_metadata_lookup.rds` | >5000 unique codes (~3 sec xlsx read + 2 sec join) |
| String matching for code type inference | `case_when(str_detect(code, "^J") ~ "HCPCS", ...)` on 50k rows | Join to pre-classified lookup table or use source_table column directly | >50k rows (~5 sec regex overhead) |
| Repeated left_join for each metadata column | 5 separate joins (one per new column) | Single wide join: `left_join(treatment_episodes, code_lookup, by = "code")` | >3 joins (~linear slowdown) |
| Excel formulas in reference xlsx (VLOOKUP chains) | Excel recalculates on open, blocking file access | Export xlsx to CSV before R read, or use `read_excel(..., .name_repair = "unique")` to skip formula eval | >1000 rows with complex formulas (~10 sec Excel overhead) |

## Data Quality Traps

Domain-specific data quality issues in oncology treatment metadata.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Assuming RxNorm codes are standardized medication names | RxNorm includes non-drug entities (device codes, procedure codes); joining blindly adds "TRANSPLANT KIT" as medication | Filter RxNorm to `TTY IN ('SCD', 'SBD', 'GPCK', 'BPCK')` (clinical drugs only) |
| Mixing ICD-9-CM and ICD-10-CM in same lookup table without system flag | Z94.84 (ICD-10) and V42.81 (ICD-9) both = "transplant status" but different eras; joining on description causes duplication | Add `code_system` column, validate no ICD-9 codes in post-2015 data |
| Trusting "first-line" labels without clean-period validation | Excel marks regimen as "first-line" but patient had prior chemo 45 days ago (not 60-day clean) | Cross-validate F/S/E/N labels against calculated `is_first_line` flag; flag discrepancies |
| Accepting incomplete medication names ("Doxorubicin" without route/dose form) | "Doxorubicin" matches both liposomal (Doxil) and conventional; affects regimen matching | Require full RxNorm SCD (Semantic Clinical Drug) level: "Doxorubicin 50 MG Injection" |
| Ignoring vitamin/supplement codes in immunotherapy category | Vitamin combos flagged as immunomodulatory but clinical significance unclear; inflates immunotherapy counts | Create separate "Supportive_care_immunomodulatory" category, exclude from primary immunotherapy analysis |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Metadata join implemented:** Verify join relationship is many-to-one (use `relationship = "many-to-one"` argument)
- [ ] **New columns added to Gantt:** Verify all new columns documented in schema file with data type, nullability, example values
- [ ] **Treatment line labels (F/S/E/N):** Verify cross-validated against existing `is_first_line` calculated flag; discrepancies documented
- [ ] **Medication names populated:** Verify non-NA rate >95% for chemotherapy codes (acceptable to be NA for radiation/surgery)
- [ ] **Cross-use flags implemented:** Verify aggregation logic documented (primary category only vs secondary for subgroups)
- [ ] **Deprecated codes removed:** Verify `CODE_SUBCATEGORY_MAP` no longer contains Z94.84, T86.5, T86.09, Z48.290, HEMATOLOGIC_TRANSPLANT_AND_ENDOC
- [ ] **Smoke test updated:** Verify Section 34 validates new columns, Section 35 validates join row counts unchanged, Section 36 validates schema version
- [ ] **Backward compatibility preserved:** Verify old Gantt v2 file still generated alongside new v3 file
- [ ] **Reference data versioned:** Verify all_codes_resolved2.xlsx copied to `data/reference/code_metadata_v2.3.xlsx` with date stamp
- [ ] **Unresolved classifications handled:** Verify TBD codes either resolved or excluded from production output (not silently included with NA)

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Many-to-many join explosion discovered in QA | LOW | 1. Revert enrichment script to pre-join commit. 2. Add `distinct(code, .keep_all = TRUE)` to xlsx read. 3. Re-run with `relationship = "many-to-one"` assertion. 4. Smoke test validates row counts. |
| Removed codes cause 20% episode loss | MEDIUM | 1. Restore CODE_SUBCATEGORY_MAP from git history. 2. Implement deprecation flag instead of removal. 3. Add `filter(!is_deprecated)` to treatment detection. 4. Regenerate all outputs. 5. Update docs with "deprecated but preserved for reproducibility". |
| Downstream consumer breaks from schema change | MEDIUM | 1. Restore old Gantt v2 file alongside v3. 2. Create `R/80_gantt_export_v2_legacy.R` frozen at old schema. 3. Document migration guide. 4. Email consumers with deprecation timeline. 5. Maintain dual export for 2 milestone cycles. |
| False-positive SCT episodes from status codes | HIGH | 1. Audit: `treatment_episodes \|> filter(source_table == "DIAGNOSIS", sub_category == "SCT")`. 2. Quantify: 250 episodes, 45 patients affected. 3. Reclassify: Move Z/T codes to new category "SCT_history_not_treatment". 4. Regenerate cohort from `01_build_cohort.R` forward. 5. Compare attrition logs (expect ~8% reduction in "Has SCT" step). 6. Update all downstream analyses. 7. Archive old RDS cache. 8. Document in v2.3 release notes. **Note: Requires full pipeline re-run (~30 min HiPerGator time).** |
| Unresolved classifications in production output | LOW | 1. Hotfix: Add `filter(classification_confidence %in% c("HIGH", "MEDIUM"))` to enrichment join. 2. Create `unresolved_codes_pending_review.csv` for clinical SME. 3. Schedule review meeting. 4. Redeploy with resolved classifications in v2.3.1 patch. |
| Cross-use flag sums exceed 100% | MEDIUM | 1. Add `primary_category` and `secondary_category` columns. 2. Update aggregation scripts to `group_by(primary_category)` only. 3. Document secondary_category as "Additional context, not for summation". 4. Re-run all category summary outputs. 5. Update smoke test to validate sum(primary_category) == nrow(episodes). |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Removing active codes without impact analysis | Phase 1: Code Removal Impact Analysis | Script `analysis/code_removal_impact.R` exists, outputs row counts to console |
| Many-to-many join explosion | Phase 2: Reference Data Validation | `expect_equal(nrow(episodes_enriched), nrow(treatment_episodes))` in smoke test Section 35 |
| Unresolved classifications propagating | Phase 2: Metadata Enrichment (with confidence filtering) | Gantt v3 output has zero rows with `classification_confidence = "UNRESOLVED"` |
| Cross-use flag logic without mutual exclusivity | Phase 3: Cross-Use Flag Implementation | Smoke test Section 36: `sum(category_counts$n) == nrow(treatment_episodes)` |
| Schema extension breaking backward compatibility | Phase 2: Gantt Schema v3 Design | Both `gantt_export_v2.csv` (14 cols) and `gantt_export_v3.csv` (19 cols) exist in output/ |
| False-positive treatment episodes from status codes | Phase 1: Code Removal Impact Analysis | `treatment_episodes \|> filter(code %in% deprecated_codes) \|> nrow()` returns 0 |

## Validation Workflow for Reference Data

Best practices for managing working documents (all_codes_resolved2.xlsx) in production pipeline:

**Stage 1: Exploratory (Current State)**
- Excel allows duplicates, TBDs, unresolved questions
- Multiple annotators can add rows/flags
- No enforcement of uniqueness or completeness

**Stage 2: Pre-Production Validation (Phase 2)**
1. Export xlsx to versioned CSV: `data/reference/code_metadata_YYYYMMDD.csv`
2. Run validation script:
   ```r
   # Check uniqueness
   duplicates <- code_metadata |> count(code, code_type) |> filter(n > 1)
   assert_that(nrow(duplicates) == 0, msg = "Duplicate codes found")

   # Check completeness for confident rows
   confident <- code_metadata |> filter(classification_confidence %in% c("HIGH", "MEDIUM"))
   incomplete <- confident |> filter(is.na(medication_name) | is.na(treatment_line))
   assert_that(nrow(incomplete) == 0, msg = "Confident rows missing metadata")

   # Flag unresolved
   unresolved <- code_metadata |> filter(classification_confidence == "UNRESOLVED")
   message(glue("{nrow(unresolved)} codes flagged as UNRESOLVED - exported for SME review"))
   write_csv(unresolved, "output/unresolved_codes_for_review.csv")
   ```
3. Filter to production-ready subset:
   ```r
   production_metadata <- code_metadata |>
     filter(classification_confidence %in% c("HIGH", "MEDIUM")) |>
     distinct(code, code_type, .keep_all = TRUE)
   ```

**Stage 3: Production Use (Phase 3+)**
- Pipeline reads versioned CSV (not live xlsx)
- Smoke test validates no duplicates, no NAs in critical columns
- Unresolved codes tracked separately for future resolution

**Stage 4: Iterative Updates (Post-v2.3)**
- SME resolves TBD codes → update xlsx → re-export CSV with new date → increment version
- Old versions preserved: `code_metadata_20260607.csv`, `code_metadata_20260614.csv`
- Pipeline config points to active version: `CODE_METADATA_VERSION <- "20260614"`

## Sources

**Oncology Coding & Treatment Classification:**
- [Oncology 2026 CPT Codes + Modifiers](https://questns.com/oncology-cpt-codes-for-2026-modifiers/) — Radiation delivery code restructuring (77402/77407/77412), deleted codes (77385/77386/77014)
- [Coding Changes Threaten Cancer Care](https://www.oncologynewscentral.com/oncology/coding-changes-threaten-cancer-care) — Financial impact of code changes (30-40% revenue decline)
- [Development and Utility of Cancer Medications Enquiry Database](https://pmc.ncbi.nlm.nih.gov/articles/PMC7868035/) — Medication code misclassification, varying therapy definitions across studies

**Clinical Data Pipeline & Metadata Enrichment:**
- [9 Common Data Quality Problems 2026](https://www.ovaledge.com/blog/data-quality-problems) — Duplicate records without unique IDs
- [Data Pipeline Quality Validation Tool](https://pmc.ncbi.nlm.nih.gov/articles/PMC12878310/) — Low quality data capture barriers, validation strategies
- [How to Audit Data Enrichment Workflows in 2026](https://versium.com/blog/how-to-audit-data-enrichment-workflows-in-2026/) — Pre-enrichment validation, post-enrichment match review
- [Healthcare Data Cleansing & Enrichment](https://www.symmetrichealthsolutions.com/data-cleansing-enrichment-attribution) — Enriching dirty data embeds inaccuracies

**R dplyr Joins & Data Integration:**
- [R for Data Science (2e) - Joins](https://r4ds.hadley.nz/joins.html) — Many-to-many join pitfalls, row duplication from cross products
- [dplyr mutate-joins reference](https://dplyr.tidyverse.org/reference/mutate-joins.html) — relationship = "many-to-one" assertion (dplyr 1.1+)
- [Data Analysis in R - Joining with dplyr](https://medium.com/@imanjokko/data-analysis-in-r-series-vi-joining-data-using-dplyr-fc0a83f0f064) — NA handling in key columns (na_matches parameter)

**Schema Evolution & Backward Compatibility:**
- [Backward Compatibility in Schema Evolution Guide](https://www.dataexpert.io/blog/backward-compatibility-schema-evolution-guide) — Providing default values for new fields
- [Backward Compatible Database Changes](https://planetscale.com/blog/backward-compatible-databases-changes) — Additive changes (new columns) vs breaking changes
- [Data Lineage & Impact Analysis](https://atlan.com/know/data-lineage-impact-analysis/) — Downstream failures from column additions/removals
- [Schema Evolution Tools That Don't Break Downstream](https://medium.com/@reliabledataengineering/15-schema-evolution-tools-that-dont-break-downstream-d81e3be1dda8) — Null values for missing columns in old data

**CAR-T & Treatment Classification:**
- [Engineering Immunity: CAR-T Cell Therapy](https://www.mdpi.com/1422-0067/27/2/909) — CAR-T as transformative immunotherapy, advanced therapy medicinal products (ATMPs)
- [Editorial: Cellular Immunotherapy](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12605324/) — CAR-T within broader immunotherapy landscape, TCR and CAR categories
- [Stem Cell Transplant Conditioning Regimens](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12293537/) — Chemotherapy agents in conditioning (cyclophosphamide, busulfan, carmustine/BCNU, melphalan/BEAM)

**PCORnet CDM & Data Quality:**
- [Exploration of PCORnet Data Resources](https://ascopubs.org/doi/10.1200/CCI.19.00142) — Treatment procedures identified via CPT/HCPCS codes
- [Evaluating Foundational Data Quality in PCORnet](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5983028/) — Data validation processing, quality remediation

**Oncology Real-World Data Quality:**
- [Strengthening Oncology Real-World Data Quality](https://www.pharmacytimes.com/view/q-a-strengthening-oncology-real-world-data-quality-through-clinically-relevant-edit-checks) — Edit checks for resectability, staging, treatment line definitions, biomarker testing gaps

---
*Pitfalls research for: Treatment Metadata Enrichment for Oncology Data Pipelines*
*Researched: 2026-06-07*
*Focus: Adding F/S/E/N labels, medication names, code metadata, cross-use flags to existing Gantt exports while removing false-positive SCT codes*
