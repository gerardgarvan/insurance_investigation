# Domain Pitfalls

**Domain:** PCORnet CDM R Analysis — Treatment Code Validation, Radiation CPT Audit, Cancer Site Frequency Analysis
**Researched:** 2026-04-21
**Confidence:** HIGH (v1.6 additions based on direct codebase inspection and CPT code structure knowledge)

---

## v1.6 Critical Pitfalls

These pitfalls are specific to milestone v1.6: adding treatment code validation against TreatmentVariables_2024.07.17.docx, auditing the radiation CPT range 70010-79999, cancer site frequency analysis from CancerSiteCategories.xlsx, and adding triggering code columns to treatment episode output.

---

### Pitfall v1.6-1: Treating "PROCEDURES: 70010-79999" as All Radiation Therapy

**What goes wrong:**
The TreatmentVariables docx lists radiation as "PROCEDURES: 70010-79999." Implementing this literally — treating all CPT codes in 70010-79999 as radiation therapy — captures the entire AMA radiology chapter, the vast majority of which is diagnostic imaging, not treatment. The classification contamination is severe:

- 70010-76499: Diagnostic Radiology (imaging) — X-ray, CT, MRI, PET scans
- 76500-76999: Diagnostic Ultrasound — echocardiography, abdominal ultrasound
- 77001-77022: Imaging Guidance — fluoroscopy guidance, needle placement guidance
- 77261-77799: Radiation Oncology (actual treatment) — simulation, planning, delivery, management, brachytherapy
- 77520-77525: Proton Beam Therapy (subset of radiation oncology)
- 78000-79999: Nuclear Medicine — diagnostic scans (bone scan, PET), NOT treatment

Classifying 70010-77022 as radiation therapy would cause every patient with a CT scan or MRI to be flagged as having received radiation treatment. This inflates the radiation-treated population by an order of magnitude and produces meaningless treatment cohort sizes.

**Why it happens:**
The docx range "70010-79999" is a reference range for WHERE to look for radiation codes, not an assertion that all codes in that range are radiation treatment. Analysts reading the docx without AMA CPT code structure knowledge assume the stated range is the filter to apply. The docx was written for clinical reviewers who would manually evaluate codes, not for direct range application in code.

**How to avoid:**
1. Never apply a CPT range as a binary filter. CPT ranges define a chapter (body system + modality), but codes within a chapter span from diagnostic to therapeutic.
2. Cite the AMA CPT code structure explicitly in code comments:
   - 77261-77799 = Radiation Oncology (treatment and management, the actual target)
   - 77520-77525 = Proton Beam Therapy (subset of above, already within 77261-77799)
   - Everything below 77261 in the 70000-79999 range is diagnostic
3. Cross-reference the existing `TREATMENT_CODES$radiation_cpt` list in `R/00_config.R` — these are the validated treatment codes (77401-77470 range). The new audit should CONFIRM these are correct, not add the full 70010-79999 range.
4. Produce an audit table showing: CPT range, AMA chapter name, count of occurrences in data, verdict (imaging/treatment/other), citation.
5. For proton therapy specifically: verify 77520-77525 are already captured in `TREATMENT_CODES$radiation_cpt` — they should be but confirm by checking the config list.

**Warning signs:**
- Radiation-treated patient count is 5-10x larger after "auditing" the range
- Patients with only imaging encounters (no oncology provider, no radiation facility) are flagged as radiation-treated
- The radiation episode output contains codes starting with 70xxx or 71xxx-76xxx

**Phase to address:**
Radiation CPT audit phase — document the sub-range breakdown and produce a structured exclusion rationale table rather than applying the full range

---

### Pitfall v1.6-2: Parsing ICD-10 Code Ranges from xlsx as String Comparisons Instead of Numeric Range Checks

**What goes wrong:**
CancerSiteCategories.xlsx contains ICD-10 code ranges in formats like "C000-C006, C008-C009" or "C18.0-C18.9." Implementing range matching by sorting strings ("C006" > "C000") fails for ICD-10 codes because:

1. Alphabetic comparison of codes with mixed letters and digits does not equal clinical code ordering. "C10" < "C9" alphabetically but ICD C10 comes after C9 in the code hierarchy only when comparing by subrange length.
2. Ranges that span a decimal boundary (e.g., "C18.0-C18.9") require extracting the numeric portion, not string comparison.
3. Codes with letters after the decimal (e.g., "C81.9A" for remission) fall outside alphabetic between-range checks even though they belong to C81.9x.
4. PCORnet data arrives both dotted and undotted (see existing Pitfall 2 in v1.0 section). Range matching code that handles dotted "C18.0-C18.9" will silently miss undotted "C180" through "C189" records in the data.

**Why it happens:**
R developers use `between()` or `dplyr::filter(code >= "C000", code <= "C006")` assuming string comparison works like numeric comparison for ICD codes. This works for simple same-prefix, same-length codes but breaks the moment codes span different lengths, contain letters post-decimal, or mix dotted/undotted formats.

**How to avoid:**
1. Parse the xlsx range expressions ("C000-C006") into explicit code vectors, not into range endpoints for comparison. For short ranges (C000-C006 is 7 codes), enumerate all valid codes between the endpoints.
2. For longer ranges (C18.0-C18.9 is 10 codes, but C18.0x could have subcodes), use the `expand_icd10_range()` pattern: strip dot, extract alpha prefix + numeric suffix, expand to all valid subcodes.
3. After expanding ranges to vectors, normalize ALL codes to undotted uppercase format using the existing `normalize_icd()` function in `utils_icd.R` before matching.
4. Do NOT write a new normalization function — use the existing `normalize_icd()` from `R/utils_icd.R`, which is already sourced via `R/00_config.R`.
5. Test the range expansion function against known codes: "C81.00" should match C81 range, "C8100" should also match, "C81.9A" should match if included.

**Warning signs:**
- Cancer site frequency counts are far lower than expected prevalence for common cancer sites
- Patients with dotted ICD codes appear in "unclassified" category even though their code visually falls in a defined range
- Comparing frequency table output to known cohort diagnosis code distribution shows large discrepancies

**Phase to address:**
Cancer site frequency analysis phase — build and test the range parser before running any frequency counts

---

### Pitfall v1.6-3: Word Document Cross-Reference Uses Substring Matching Instead of Exact Code Matching

**What goes wrong:**
TreatmentVariables_2024.07.17.docx contains code lists in narrative or semi-structured format. When cross-referencing the R pipeline's `TREATMENT_CODES` vectors against the docx, analysts use `grepl()` or `str_detect()` on the extracted text. This causes:

1. False positives: "J9000" matches "J9000, J9001, J9002" via substring but "J9002" is not in `TREATMENT_CODES`. The cross-reference incorrectly shows J9002 as "found."
2. False negatives: The docx may use "J-9000" or "J9000–J9999" (range notation) where the pipeline has individual codes. Substring matching against range notation finds no match for individual codes even though they're within the documented range.
3. Format variation in docx extraction: Word document text extraction via `officer` or `docx2txt` may introduce line-break artifacts, non-breaking spaces, or em-dashes that break exact matching.

**Why it happens:**
Analysts extract docx text as a single string and use regex to check if each code "appears" in the text. Code ranges and comma-separated lists in the docx look like matches for any prefix of a code in the list. The analyst reports "all codes found" when the actual match is against a range prefix, not the specific code.

**How to avoid:**
1. Parse the docx into a structured list of individual codes AND declared ranges separately. Do NOT treat the full extracted text as a lookup target.
2. For range declarations in the docx (e.g., "38230-38243"), expand to individual codes before cross-referencing.
3. Use exact string matching (`%in%`) after normalization, not `str_detect()`, for code-level cross-reference.
4. When using the `officer` R package to read the docx, extract paragraph text and table cell text separately — code lists are more likely to be in tables than in flowing paragraph text.
5. Produce a bidirectional gap report: (A) codes in pipeline but NOT in docx, (B) codes in docx but NOT in pipeline. Both directions matter — A indicates over-capture, B indicates under-capture.
6. For the "PROCEDURES: 70010-79999" range in the docx, do not expand to 10,000 individual codes. Instead, document the sub-range that IS in the pipeline (77261-77799) and note it is the treatment-relevant subset.

**Warning signs:**
- Cross-reference reports "100% match" but manual inspection of specific codes shows mismatches
- The gap report shows zero codes in either direction (too perfect — suggests substring matching not exact matching)
- Range notation in the docx is being reported as matching individual codes

**Phase to address:**
Treatment code cross-reference phase — structure the docx parsing before writing any comparison logic

---

### Pitfall v1.6-4: Adding Triggering Code Column Breaks Downstream CSV Consumers

**What goes wrong:**
Adding a `triggering_code` or `triggering_codes` column to the treatment episode CSV output is a schema change. Any downstream code that:
- Reads the episode CSV with `read_csv()` and then accesses columns by position (`df[, 5]`) rather than name (`df$episode_start`)
- Does `names(df)` assertions or column count checks
- Has hardcoded `select()` calls that omit the new column and drop it silently

...will either break or silently produce incorrect results. In an exploratory pipeline with 40+ scripts, the downstream consumers may not be obvious.

**Why it happens:**
R scripts in exploratory pipelines tend to use `read_csv()` followed by `select()` with explicit column names, which actually handles schema additions gracefully. But the risk is in any script that (1) joins on the episode file as an intermediate, (2) does a `bind_rows()` across old and new outputs, or (3) has a styled xlsx output whose column formatting is tied to column position.

In this pipeline specifically, `R/44_treatment_episodes.R` produces the episode CSV. Any script sourcing or reading this output — including retrospective analyses and any future Phase 45+ scripts — will encounter the new column. The `openxlsx2` styling in Phase 44's xlsx output may have column-position-dependent formatting.

**How to avoid:**
1. Search the codebase for all scripts that read `treatment_episodes.csv` or the `treatment_episodes.rds` output before adding the column.
2. Add the `triggering_code` column as the LAST column in the output schema, not inserted in the middle. This minimizes positional disruption.
3. Make the column nullable (NA if no triggering code matched) rather than omitting rows. Adding rows breaks `bind_rows()` assumptions; adding a nullable column is safer.
4. If the Phase 44 xlsx has column-position-dependent styling (e.g., `wb$add_style(col = 7)`), update the style calls to use named column lookup instead.
5. Update the `D-08` decision note in `R/44_treatment_episodes.R` to document the new column and its source.
6. Run the Phase 44 test script (`R/44_test_episodes.R`) after adding the column to confirm no assertion failures.

**Warning signs:**
- `bind_rows()` throws "columns do not match" error when combining old episode output with new
- Styled xlsx has misaligned column headers after column insertion
- A downstream script produces empty results after the schema change (silent column drop from explicit `select()`)

**Phase to address:**
Triggering code traceability phase — audit downstream consumers before modifying the episode schema

---

### Pitfall v1.6-5: Cancer Site Frequency Table Uses DX Table Without Restricting to HL Cohort

**What goes wrong:**
The cancer site frequency analysis queries the DIAGNOSIS table for ICD codes matching CancerSiteCategories.xlsx ranges. If the query runs against the full DIAGNOSIS table (all patients in the PCORnet extract, not just the HL cohort), the frequency table reflects all cancer diagnoses across all PCORnet patients — not just Hodgkin Lymphoma patients. The result is a cancer site frequency table for the entire OneFlorida+ extract, which is meaningless for the study purpose and inflated by comorbid diagnoses in non-HL patients.

Additionally, even within the HL cohort, a patient may have multiple cancer site diagnoses across encounters. Without specifying "cancer site at diagnosis" vs "any cancer site ever mentioned," the table conflates incidental mentions of other cancer sites with the patient's primary cancer type.

**Why it happens:**
DuckDB backend queries (`get_pcornet_table("DIAGNOSIS")`) return all rows from the table. Analysts add frequency counts without an initial `filter(ID %in% hl_cohort_ids)` step because they're focused on the frequency logic, not the population scoping. The existing `get_hl_patient_ids()` function in `utils_treatment.R` is available but requires knowing to call it first.

**How to avoid:**
1. Always scope the DIAGNOSIS query to the HL cohort before cancer site categorization. Use the pattern from existing scripts: `hl_ids <- get_hl_patient_ids()` then `filter(ID %in% local(hl_ids))`.
2. Document in the script header whether the frequency table is per-patient (distinct patients per cancer site) or per-encounter (total encounter rows per cancer site). Both are valid but different.
3. For cancer site frequency, consider restricting to DX_DATE within the study window (2012-2025) to avoid historical diagnoses from before the data collection period.
4. Add a sanity check: the total unique patient count in the cancer site table should not exceed the HL cohort size. If it does, the cohort scoping filter was missed.

**Warning signs:**
- Total patients in cancer site frequency table is larger than the known HL cohort size
- Cancer site categories for non-lymphoma cancers (lung, prostate, breast) show high counts, suggesting non-HL patients are included
- The frequency counts match the total PCORnet extract volume rather than the HL cohort volume

**Phase to address:**
Cancer site frequency analysis phase — cohort scoping must be the first filter applied

---

### Pitfall v1.6-6: Proton Therapy Codes 77520-77525 Assumed Present Without Verification

**What goes wrong:**
The milestone requirement states "Confirm proton therapy codes 77520-77525 are captured in radiation detection." An analyst reads the existing `TREATMENT_CODES$radiation_cpt` list in `R/00_config.R`, does not see 77520-77525 explicitly, and concludes they are missing — then adds them. But if they were already matched by a range heuristic (e.g., the `CPT_HCPCS_RANGES$Radiation$delivery = "^774[0-9]{2}$"` pattern in `R/38_treatment_inventory.R`), adding them explicitly creates no harm but adds noise. Conversely, assuming they ARE captured without checking means they silently miss patients who received proton therapy.

Proton therapy (77520-77525) is in the 77xxx range but is a distinct modality. The existing `radiation_cpt` in config includes codes in the 77401-77470 range. 77520 starts a new sub-range (77520 Proton treatment delivery, simple; 77522 Proton treatment delivery, intermediate; 77523 complex; 77525 management). These are NOT covered by any of the existing codes 77401-77470, so they are likely missing from `TREATMENT_CODES$radiation_cpt`.

**Why it happens:**
The CPT code range in config ends at 77470. 77520-77525 appears later in the 77xxx chapter but is a separate sub-range. Analysts who built the original list focused on EBRT codes (77385/77386 legacy codes, now replaced by 77401-77412) and may not have considered proton therapy as a distinct HL treatment path.

**How to avoid:**
1. Explicitly check `TREATMENT_CODES$radiation_cpt` in config for presence of 77520, 77522, 77523, 77525.
2. If absent, add them with specific comments citing AMA CPT code descriptions.
3. Check the data: query `PROCEDURES` for any of 77520-77525 in the HL cohort. Even if zero occurrences exist in this dataset, document the check and the result.
4. Do not assume the range heuristic in `38_treatment_inventory.R` covers these — the pattern `"^774[0-9]{2}$"` only matches codes starting with "774", not "775".

**Warning signs:**
- The audit table shows 77520-77525 present in PROCEDURES data but not in any TREATMENT_CODES list
- The proton therapy confirmation task is marked complete without a data query showing either presence or absence

**Phase to address:**
Radiation CPT audit phase — include proton therapy sub-range explicitly in the audit table

---

### Pitfall v1.6-7: ICD-10 Cancer Site Categories Overlap with HL Diagnosis Codes, Causing Double Classification

**What goes wrong:**
CancerSiteCategories.xlsx may contain a "Lymphoma" or "Hematologic" cancer site category that includes ICD-10 codes in the C81.xx range (Hodgkin Lymphoma). When building the cancer site frequency table, every patient in the HL cohort will appear under the Lymphoma/Hematologic cancer site category because their HL diagnosis code (C81.xx) matches the category definition. This is expected and correct for that category. However, if the analyst does not anticipate this, they may:

1. Treat the high Lymphoma category count as a data error
2. Attempt to exclude C81.xx codes from the cancer site analysis (removing the primary disease of interest)
3. Fail to document that C81.xx = HL = expected dominant category in the frequency table

A related problem: if a patient has both an HL diagnosis AND a comorbid cancer (e.g., secondary malignancy), they will appear in multiple cancer site categories. The frequency table should count patients, not diagnoses, but `n()` after `group_by(cancer_site)` counts rows, not distinct patients.

**Why it happens:**
Cancer site frequency tables for a cancer-specific cohort will obviously show the cohort-defining cancer as the top category. Analysts building a general-purpose frequency function don't account for the expected dominance of the cohort-defining diagnosis. The count-of-rows vs count-of-distinct-patients confusion is a common `group_by + summarize` error.

**How to avoid:**
1. Use `n_distinct(ID)` not `n()` when counting patients per cancer site category.
2. Document that C81.xx (Hodgkin Lymphoma) is the expected top category in the output header or footnote.
3. Consider producing TWO frequency tables: (A) including HL codes (C81.xx), (B) excluding HL codes — to show comorbid/secondary cancer site distribution separately.
4. Add a column "pct_of_cohort" alongside the count so the C81.xx category dominance is proportionally visible.

**Warning signs:**
- Cancer site "Lymphoma" has a count equal to the total cohort size (correct, but may alarm reviewer)
- Sum of patient counts across cancer sites exceeds cohort size (indicates rows not distinct patients)
- A single patient appears in 3+ cancer site categories (valid if comorbid but should be documented)

**Phase to address:**
Cancer site frequency analysis phase — define the counting unit (patients vs encounters vs diagnoses) before writing aggregation logic

---

### Pitfall v1.6-8: Cross-Reference Gap Report Uses Wrong Direction of Comparison

**What goes wrong:**
The cross-reference between TREATMENT_CODES (R pipeline) and TreatmentVariables docx (reference document) requires two-direction comparison. Analysts build only the "pipeline → docx" direction: "which pipeline codes appear in the docx?" This catches codes in the pipeline that are NOT documented. But it misses the reverse: "which docx codes are NOT in the pipeline?" — i.e., documented treatments that the pipeline fails to detect.

For HL specifically, the docx may document treatment codes that the pipeline never implemented (e.g., if the docx was updated after the pipeline was built in Phases 38-43). A one-direction gap report would pass silently even if the pipeline misses 20% of the documented treatment codes.

**Why it happens:**
Analysts default to "does my code match the spec?" (pipeline → spec direction) rather than "does my code implement everything in the spec?" (spec → pipeline direction). The second direction is harder because it requires parsing the docx into a usable code list first.

**How to avoid:**
1. Build a bidirectional gap report explicitly:
   - `in_pipeline_not_in_docx`: codes in TREATMENT_CODES that have no match in docx
   - `in_docx_not_in_pipeline`: codes/ranges from docx that have no corresponding code in TREATMENT_CODES
2. For the docx → pipeline direction, the range notation challenge (Pitfall v1.6-3) applies. Expand docx ranges to individual codes first, then use `%in%`.
3. Accept that some docx ranges (70010-79999 for radiation) will expand to thousands of codes. For these, use sub-range matching: "does the pipeline capture the treatment-relevant subset (77261-77799) of this range?" rather than code-for-code matching.
4. Report both gap directions in the output CSV, with a separate column indicating gap severity: "missing from pipeline" is higher severity than "in pipeline but not documented."

**Warning signs:**
- The gap report CSV has only one direction of comparison
- Zero gaps reported in both directions (unlikely for a large HCPCS/CPT code list — suggests comparison logic error)
- The in_docx_not_in_pipeline gap is empty despite the docx containing range notation that expands to codes not in the pipeline

**Phase to address:**
Treatment code cross-reference phase — structure the gap report template before implementing the comparison logic

---

## Technical Debt Patterns (v1.6 additions)

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Apply full "70010-79999" range as radiation filter | One-line implementation, matches docx literally | Captures diagnostic imaging as radiation therapy — inflates treated count 10x, invalidates analysis | Never — always apply only the radiation oncology sub-range (77261-77799) |
| String comparison for ICD range matching (">=" on undotted codes) | Familiar pattern, no custom parser needed | Fails for mixed-length codes, codes with letter suffixes (C81.9A), and any range spanning digit-count boundaries | Never for ICD ranges — enumerate codes or use numeric suffix comparison |
| One-direction docx cross-reference (pipeline → docx only) | Faster to implement | Misses docx-documented codes absent from pipeline — under-coverage invisible | Only if docx is known to be a subset of pipeline (confirmed independently) |
| Add triggering_code column in middle of episode CSV schema | Logically positioned near triggering columns | Breaks positional access in downstream scripts, misaligns xlsx column styling | Never — always append new columns at end of schema |
| Count diagnoses rows for cancer site frequency (`n()`) instead of distinct patients (`n_distinct(ID)`) | Default `summarize(n = n())` pattern | Patients with multiple encounters per cancer site counted multiple times — inflated frequencies | Only if the explicit question is "encounter volume" not "patient count" |

## Integration Gotchas (v1.6 additions)

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| CancerSiteCategories.xlsx range parsing | Apply range endpoints as string comparisons in dplyr filter | Parse ranges to explicit code vectors using a range-expansion function, normalize to undotted, use `%in%` |
| TreatmentVariables_2024.07.17.docx extraction via `officer` | Extract full document text as one string, use `str_detect()` for code lookup | Parse paragraph and table text separately, build structured code list from docx, use exact `%in%` matching |
| DuckDB backend for cancer site query | Forget to collect HL cohort IDs before filtering DIAGNOSIS | Use `local()` wrapping or collect cohort IDs first: `filter(ID %in% local(hl_ids))` for DuckDB tbl compatibility |
| openxlsx2 styled xlsx schema change | Change column count in episode output without updating style call column indices | Update all `wb$add_style(col = N)` references after schema change, or switch to named column lookup |
| CPT code range heuristics in 38_treatment_inventory.R | Assume range heuristic `"^774[0-9]{2}$"` covers proton codes (77520-77525 starts with 775) | Proton codes start with 775, not 774 — add explicit heuristic or enumerated codes for 775xx sub-range |

## Performance Traps (v1.6 additions)

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Expanding ICD-10 range "C000-C999" into individual codes in R | Range expansion produces 900+ codes, enumeration hangs | Use vectorized range expansion with `sprintf()`, not `seq()` on character codes | Any range spanning more than ~100 codes |
| Loading full DIAGNOSIS table into memory for cancer site analysis | Memory spike loading all 500k+ DIAGNOSIS rows | Use DuckDB lazy query: filter to HL cohort IDs before `collect()` | DIAGNOSIS tables > 500k rows (common in multi-site PCORnet extracts) |
| Reading TreatmentVariables docx with `officer` on HiPerGator without Office dependency | `officer` requires no external dependencies but docx parsing may be slow for large documents | Cache extracted docx content as R list in first run, use cached version for cross-reference | Docx files > 5MB or scripts run in automated mode without caching |

## "Looks Done But Isn't" Checklist (v1.6 additions)

- [ ] **Radiation CPT audit:** Often marked complete when just the range 77xxx is identified — verify a structured table exists listing EACH sub-range (70010-76499, 76500-76999, 77001-77022, 77261-77799, 77520-77525, 78000-79999) with AMA classification and occurrence count in data
- [ ] **Proton therapy confirmation:** Often assumed present without data query — verify by running `filter(PX %in% c("77520","77522","77523","77525"))` against PROCEDURES and documenting the count (zero is a valid result if no proton patients exist)
- [ ] **Cancer site ICD range parser:** Often written as string comparison — verify by testing a code at the BOUNDARY of a range (first code, last code) and a code just outside returns FALSE
- [ ] **Bidirectional gap report:** Often built in only one direction — verify both `in_pipeline_not_in_docx` and `in_docx_not_in_pipeline` columns exist in the output
- [ ] **Triggering code column downstream impact:** Often added without checking consumers — verify by searching for all scripts that `read_csv()` or `readRDS()` the treatment episode output files
- [ ] **Cancer site cohort scoping:** Often runs on full PCORnet extract — verify total unique patients in frequency table does not exceed HL cohort size
- [ ] **HL code dominance documented:** C81.xx will be top cancer site category — verify this is noted in output or footnote, not treated as an error
- [ ] **Dotted/undotted harmonization in cancer site matching:** Verify the range expansion function normalizes xlsx ranges and PCORnet data to the same format using existing `normalize_icd()` before matching

## Recovery Strategies (v1.6 additions)

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Radiation CPT range applied too broadly (70010-79999) | MEDIUM (3-5 hours) | 1. Replace range filter with explicit 77261-77799 sub-range. 2. Re-run radiation detection query. 3. Recount radiation-treated patients. 4. Update audit table with correct sub-range citation. |
| ICD string comparison causes missed cancer site matches | MEDIUM (2-4 hours) | 1. Build range-expansion function that enumerates all codes between endpoints. 2. Normalize to undotted format. 3. Re-run frequency table. 4. Validate against known cohort diagnosis distribution. |
| Triggering code column breaks downstream consumer | LOW-MEDIUM (1-3 hours) | 1. Find all downstream readers of episode output. 2. Confirm column access is by name not position. 3. If positional access exists, refactor to named access. 4. Re-run affected scripts. |
| Cancer site frequency includes non-HL patients | LOW (1-2 hours) | 1. Add `filter(ID %in% local(hl_ids))` as first filter in DIAGNOSIS query. 2. Re-run frequency table. 3. Verify total unique patients ≤ HL cohort size. |
| One-direction gap report misses docx-undocumented pipeline codes | LOW (1-2 hours) | 1. Add reverse comparison: docx code list `%in%` pipeline TREATMENT_CODES. 2. Re-run cross-reference. 3. Add `in_docx_not_in_pipeline` column to output CSV. |
| Proton codes 77520-77525 missing from TREATMENT_CODES | LOW (30 min) | 1. Add codes to `TREATMENT_CODES$radiation_cpt` in 00_config.R with AMA citations. 2. Re-run treatment inventory query. 3. Document count of proton therapy patients found. |

## Pitfall-to-Phase Mapping (v1.6 additions)

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Radiation CPT range too broad (70010-79999 as filter) | Radiation CPT audit phase | Audit table enumerates sub-ranges; radiation-treated patient count is plausible (not 10x inflated) |
| ICD string comparison for cancer site range matching | Cancer site frequency analysis phase | Boundary code tests pass; dotted and undotted formats both match correctly |
| Docx cross-reference uses substring not exact matching | Treatment code cross-reference phase | Bidirectional gap report exists; zero-gap result triggers manual review |
| Triggering code column breaks downstream consumers | Triggering code traceability phase | All downstream readers verified by grep; column appended at end of schema |
| Cancer site query not scoped to HL cohort | Cancer site frequency analysis phase | Total unique patients in output ≤ HL cohort N |
| Proton codes 77520-77525 assumed present without data check | Radiation CPT audit phase | PROCEDURES query for 77520-77525 executed and count documented (zero or nonzero) |
| HL codes dominate cancer site table, treated as error | Cancer site frequency analysis phase | Output includes documentation of expected C81.xx dominance |
| One-direction gap report misses docx undocumented codes | Treatment code cross-reference phase | Output CSV contains both in_pipeline_not_in_docx and in_docx_not_in_pipeline columns |

---

## v1.0-v1.5 Pitfalls (Retained)

The following pitfalls from earlier milestone research remain valid for the full pipeline.

### Pitfall 1: Naive Payer Category Assignment Without Temporal Overlap Detection

**What goes wrong:**
Analysts assign patients to single payer categories based on enrollment start/end dates without detecting dual-eligible periods (overlapping Medicare + Medicaid enrollment). This leads to severe undercount of dual-eligible beneficiaries.

**Why it happens:**
PCORnet ENROLLMENT table contains multiple rows per patient with overlapping ENR_START_DATE and ENR_END_DATE periods. Dual-eligible status requires detecting when Medicare enrollment temporally overlaps with Medicaid enrollment.

**How to avoid:**
Implement temporal overlap detection. Create a dual-eligible flag when PAYER_TYPE_PRIMARY/SECONDARY contains both '1' and '2' with overlapping date ranges.

**Warning signs:**
Dual-eligible count is < 5% of Medicare + Medicaid combined count. Sum of 9 payer categories ≠ unique patient count.

**Phase to address:**
Phase 1 (Data Loading & Payer Harmonization)

---

### Pitfall 2: ICD Code Matching Without Handling Both Dotted and Undotted Formats

**What goes wrong:**
ICD codes in PCORnet DIAGNOSIS table arrive in multiple formats. Naive string matching misses ~30-50% of true diagnoses.

**How to avoid:**
Normalize ALL DX codes to undotted uppercase format using `normalize_icd()` from `utils_icd.R`. Normalize reference code lists to the same format before matching.

**Warning signs:**
Cohort size is 40-60% smaller than expected. Mix of dotted and undotted codes visible in DIAGNOSIS table but filter only catches one format.

**Phase to address:**
Phase 1 (Data Loading & Payer Harmonization)

---

### Pitfall 3: Date Parsing Failures from Multi-Format SAS Date Exports

**What goes wrong:**
PCORnet date fields export in inconsistent formats. `readr::read_csv()` auto-detection fails ~20% of the time for large files.

**How to avoid:**
Never rely on readr auto-detection for date columns. Use `col_types = cols(.default = col_character())` initially, then parse with `lubridate::parse_date_time()` with multiple orders.

**Phase to address:**
Phase 1 (Data Loading & Payer Harmonization)

---

### Pitfall 4: HIPAA Small-Cell Suppression Applied Incorrectly (Primary Only, No Secondary)

**What goes wrong:**
Primary suppression applied without secondary suppression. Readers can subtract observed cells from totals to recover suppressed values. Direct HIPAA violation.

**How to avoid:**
Build suppression validation function. For every suppressed cell, verify it cannot be recovered from marginal totals. Apply secondary suppression to 2-3 adjacent cells.

**Phase to address:**
Phase 3 (Visualizations & Outputs)

---

## Sources

### CPT Code Structure
- AMA CPT 2024 Code Set — Radiology section 70000-79999 chapter structure (HIGH confidence, reflected in AMA CPT manual organization)
- CMS 2026 Physician Fee Schedule — radiation oncology codes 77261-77799 (HIGH confidence)
- CMS 2026 changes: 77385/77386 deleted, replaced by complexity-based 77401-77412 (reflected in existing `R/00_config.R` comments)
- Proton beam therapy 77520-77525 (AMA CPT, HIGH confidence)

### ICD-10 Code Range Structure
- ICD-10-CM Official Guidelines for Coding and Reporting (HIGH confidence for code structure)
- Existing `utils_icd.R` and `R/00_config.R` codebase (direct inspection, HIGH confidence)

### R Ecosystem
- `officer` package documentation for docx text extraction (MEDIUM confidence — package exists, version-specific behavior not verified)
- `openxlsx2` package for xlsx reading (HIGH confidence — already in use in pipeline)
- `readxl` package for xlsx reading (HIGH confidence — already in use in `R/35_payer_code_frequency_av_th.R`)

### Pipeline-Specific Context
- Direct inspection of `R/00_config.R` TREATMENT_CODES list (Phase 39 additions) — HIGH confidence
- Direct inspection of `R/38_treatment_inventory.R` CPT_HCPCS_RANGES heuristics — HIGH confidence
- Direct inspection of `R/44_treatment_episodes.R` output schema and D-08 decision — HIGH confidence
- Direct inspection of `R/35_payer_code_frequency_av_th.R` xlsx cross-reference pattern — HIGH confidence
- Direct inspection of `R/utils_icd.R` normalize_icd() and is_hl_diagnosis() functions — HIGH confidence

---
*Pitfalls research for: PCORnet CDM R Analysis — v1.6 Treatment Code Validation & Cancer Site Analysis*
*Researched: 2026-04-21*
