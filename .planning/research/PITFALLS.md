# Domain Pitfalls

**Domain:** Adding cancer summary refinement, temporal cohort confirmation, relative-date filtering, and Gantt enhancements to existing Hodgkin Lymphoma R pipeline
**Researched:** 2026-05-22

---

## v1.7 Critical Pitfalls

These pitfalls are specific to milestone v1.7: removing benign D-codes from cancer summary, enforcing HL cohort confirmation (2+ codes, 7-day gap), filtering cancers relative to first HL diagnosis, adding cancer category labels to Gantt data, adding is_hodgkin flag, and integrating death dates.

---

### Pitfall v1.7-1: Shared PREFIX_MAP Modification Breaks Downstream Consumers

**What goes wrong:** Removing D-codes from PREFIX_MAP in R/00_config.R breaks all scripts that use it for cancer categorization (R/47, R/50, R/51, R/53, R/54). Scripts fail with "unknown category" errors or produce blank categories for benign neoplasm codes.

**Why it happens:** PREFIX_MAP is currently duplicated across 6+ scripts rather than being centralized. Each script has its own copy including D-codes. Modifying the "wrong" copy or only some copies creates inconsistency. Even if centralized, removing D-codes changes the data contract — downstream scripts expect D-codes to map to categories.

**Consequences:**
- Cancer summary table breaks (no category for D-codes that still exist in source data)
- Gantt chart cancer category labels fail (NULL categories for benign neoplasm encounters)
- Code descriptions lookup fails for D-codes
- HIPAA suppression logic may mis-count categories (fewer codes per category → more suppressions)
- Silent data loss: rows with D-codes drop from outputs without warning

**Prevention:**
- **Phase 01 (Scope):** Decision — filter D-codes in query logic (WHERE clause), NOT by removing from PREFIX_MAP
- **Phase 01 (Scope):** PREFIX_MAP remains complete (C-codes + D-codes); filtering happens at data layer
- **Phase 02 (PREFIX_MAP audit):** Grep for all PREFIX_MAP occurrences; verify none are centralized in R/00_config.R yet
- **Phase 02 (PREFIX_MAP audit):** If duplicated across scripts, decide: centralize first (separate phase) OR accept duplication and document
- **Phase 03 (Cancer summary filtering):** Use WHERE clauses like `filter(!str_starts(cancer_code, "D"))` rather than modifying PREFIX_MAP
- **Phase 05 (Gantt category labels):** Same approach — query filters D-codes before classify_codes(), so PREFIX_MAP never sees them

**Detection:**
- Unit test: Verify classify_codes() returns expected category for D10.1, D00.5, D48.9 (one from each D-code range)
- Integration test: Count distinct categories before/after changes — should be stable
- Code review: Search for `PREFIX_MAP <-` assignments — flag any that remove D-codes
- Downstream validation: Run R/54 (cancer summary table) and verify no NA categories in output

**References:**
- [Data Contracts for Pipeline Stability](https://www.acceldata.io/blog/how-data-contracts-guarantee-pipeline-reliability-data-quality-slas)
- [Stop Breaking Downstream Pipelines](https://dataskew.io/blog/data-contracts-for-data-engineers/)

---

### Pitfall v1.7-2: Immortal Time Bias from Post-Diagnosis Filtering

**What goes wrong:** Filtering cancer_summary to "cancers after first HL diagnosis" creates immortal time bias. Patients must survive long enough post-HL to develop a second cancer code to be included. Analysis overstates survival and understates secondary cancer risk for patients who die shortly after HL diagnosis.

**Why it happens:** Retrospective filtering based on temporal ordering introduces survivorship bias. The pipeline calculates `first_hl_dx_date`, then filters `cancer_summary` to `DX_DATE >= first_hl_dx_date`. Patients who die within months of HL diagnosis (before accumulating second cancer codes) are systematically excluded from denominator, biasing secondary cancer rates upward.

**Consequences:**
- Secondary cancer prevalence is inflated (denominator excludes early deaths)
- Time-to-secondary-cancer is biased downward (immortal time excluded from analysis)
- Comparisons between pre-HL and post-HL cancer burden are invalid
- Survivorship analysis misleading — cohort no longer representative of HL population

**Prevention:**
- **Phase 01 (Scope):** Explicitly document that post-diagnosis filtering is for exploratory comparison, NOT causal inference
- **Phase 03 (Cancer filtering):** Produce BOTH versions: (1) all cancers (unfiltered), (2) post-HL cancers (filtered)
- **Phase 03 (Cancer filtering):** Label filtered output clearly: `cancer_summary_post_hl_EXPLORATORY.xlsx` to flag bias risk
- **Phase 03 (Cancer filtering):** Include denominator note: "Excludes patients with no post-HL cancer codes (including early deaths)"
- **Phase 04 (Documentation):** Add footnote to any post-HL tables: "Post-diagnosis filtering may introduce immortal time bias"
- **Future mitigation:** Proper analysis would use landmark analysis (e.g., 1-year post-HL survivors) or time-varying exposure models

**Detection:**
- Sanity check: Compare N patients in all-cancers vs post-HL-cancers — large drop suggests immortal time issue
- Stratified analysis: Count patients by survival time — if post-HL cohort is missing short-term survivors, bias confirmed
- Negative control: Apply same filtering to pre-HL cancers — if rates change dramatically, temporal filtering is distorting data

**References:**
- [Immortal Time Bias in Orthopedics](https://pmc.ncbi.nlm.nih.gov/articles/PMC8478821/)
- [Immortal Time Bias in Retrospective Studies](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8962148/)
- [Statistical Methods for Immortal Time](https://arxiv.org/pdf/2202.02369)
- [Immortal Time Bias Impact](https://blog.akianalytics.co.uk/immortal-time-bias/)

---

### Pitfall v1.7-3: HL Cohort Confirmation Logic Duplicates Existing Scripts

**What goes wrong:** Implementing "2+ HL codes, 7-day separation" filter in a new script duplicates logic already in R/50_cancer_site_confirmation.R and R/51_cancer_site_confirmation_7day.R. Subtle differences in implementation (date parsing, gap calculation, tie-breaking) produce different patient lists, causing downstream confusion about "true" HL cohort.

**Why it happens:** R/50 and R/51 implement exact code confirmation and category-level confirmation with 7-day gap logic. Rewriting this logic from scratch risks bugs, off-by-one errors in date arithmetic, and different handling of edge cases (same-date codes, NA dates, 1900 sentinels). Without unit tests, differences go undetected.

**Consequences:**
- Two "HL confirmed" cohorts with different patient lists
- Cancer summary table filters to cohort A, but Gantt chart uses cohort B → data inconsistency
- Debugging nightmare: "Why does patient X appear in cancer_summary but not gantt_episodes?"
- Wasted time: reimplementing already-solved logic
- Future maintenance burden: two codebases to update when date logic changes

**Prevention:**
- **Phase 01 (Scope):** Reuse R/51 logic rather than reimplementing
- **Phase 02 (Cohort confirmation):** Extract shared function: `get_hl_confirmed_patients(min_codes = 2, min_gap_days = 7)`
- **Phase 02 (Cohort confirmation):** Move function to utils_icd.R or utils_treatment.R for reuse
- **Phase 02 (Cohort confirmation):** R/51, cancer_summary, and any future scripts call same function → guaranteed consistency
- **Phase 03 (Integration):** Load confirmed patient list from R/51 output CSV rather than recalculating
- **Alternative (if R/51 is insufficient):** Document exact differences in implementation and rationale for divergence

**Detection:**
- Parity test: Run both implementations on same data, compare patient lists, flag discrepancies
- Unit test: Edge cases — patient with 2 codes same day (should exclude), patient with codes on day 0 and day 7 (should include), patient with 3 codes spanning 6 days (category-level include, exact-code may exclude)
- Code review: Flag any new date-gap calculation logic — verify it matches existing implementation

---

### Pitfall v1.7-4: First HL Diagnosis Date Calculation Inconsistency (DIAGNOSIS vs TUMOR_REGISTRY)

**What goes wrong:** Pipeline calculates `first_hl_dx_date` from DIAGNOSIS table only, but some patients have earlier HL dates in TUMOR_REGISTRY. Post-HL cancer filtering uses wrong anchor date, incorrectly excluding pre-DIAGNOSIS but post-TUMOR_REGISTRY cancers.

**Why it happens:** Current cohort logic (R/04_build_cohort.R) defines `first_hl_dx_date` from DIAGNOSIS.DX_DATE, ignoring TUMOR_REGISTRY date fields. But R/03_cohort_predicates tracks `HL_SOURCE` (DIAGNOSIS/TR/Both), indicating some patients have HL evidence only in TR. For "TR only" patients, `first_hl_dx_date` may be NA or wrong. Filtering `cancer_summary` by this date is inconsistent with the cohort definition.

**Consequences:**
- "TR only" patients excluded from post-HL cancer analysis (denominator bias)
- Patients with TR date earlier than DIAGNOSIS date have artificially late anchor → pre-TR cancers incorrectly classified as "post-HL"
- Time-to-secondary-cancer calculations wrong for ~20-30% of cohort (typical TR-only proportion in cancer registries)
- Results not reproducible if TR vs DIAGNOSIS data availability changes

**Prevention:**
- **Phase 01 (Scope):** Decision — use earliest HL date across DIAGNOSIS and TUMOR_REGISTRY as anchor
- **Phase 02 (First HL date):** Create `compute_first_hl_date()` function that queries both tables
- **Phase 02 (First HL date):** For each patient, take min(DIAGNOSIS.DX_DATE where HL code, TR.DX_DATE/DATE_OF_DIAGNOSIS where HL histology)
- **Phase 02 (First HL date):** Handle NA dates: if only one source has date, use that; if both NA, first_hl_dx_date = NA
- **Phase 02 (First HL date):** Log date source: add `first_hl_dx_source` column (DIAGNOSIS/TR/Both) for traceability
- **Phase 03 (Integration):** Update R/04_build_cohort.R to use multi-source first HL date
- **Phase 03 (Validation):** Compare old vs new first_hl_dx_date — expect ~10-30% changes for TR-only or Both patients

**Detection:**
- Data quality check: For patients with HL_SOURCE == "TR only", verify first_hl_dx_date is not NA
- Sanity check: Count patients where TR date < DIAGNOSIS date — should see non-zero if TR is being used
- Stratified validation: Group by HL_SOURCE, check first_hl_dx_date missingness — should be 0% for all groups
- Unit test: Mock patient with DX_DATE = 2020-06-01, TR date = 2020-03-01 → first_hl_dx_date should be 2020-03-01

**References:**
- [2026 SEER Coding Manual](https://seer.cancer.gov/manuals/2026/SPCSM_2026_MainDoc.pdf)
- [Cancer Registry Date of First Contact](https://www.registrypartners.com/ctr-coding-break-date-of-first-contact/)

---

### Pitfall v1.7-5: Death Date Misidentification (DEMOGRAPHIC vs DEATH Table Confusion)

**What goes wrong:** Code assumes DEMOGRAPHIC table has DEATH_DATE column (based on training data), but OneFlorida+ PCORnet CDM v7.0 may use separate DEATH/DEATH_CAUSE tables. Script fails with "column not found" error or silently produces all-NA death dates.

**Why it happens:** PCORnet CDM evolved across versions. Older versions (v3-v5) stored death date in DEMOGRAPHIC.DEATH_DATE. Newer versions (v6+) may use separate DEATH table with DEATH_DATE and DEATH_SOURCE columns. Training data is stale (Jan 2025 cutoff predates v7.0 release May 2025). Without inspecting actual DuckDB schema, assumptions about column location are untested.

**Consequences:**
- Script crashes at runtime on HiPerGator (works locally if local data has different schema)
- All patients show death_date = NA → Gantt chart has no death events despite real deaths in cohort
- Survival analysis impossible (denominator includes deceased patients as alive)
- HIPAA suppression may fail if death counts drop to 1-10 (missing data looks like rare event)

**Prevention:**
- **Phase 01 (Scope):** Inspect actual PCORnet schema before implementation — don't assume column location
- **Phase 02 (Death date source):** Query `PRAGMA table_info('DEMOGRAPHIC')` in DuckDB to list columns
- **Phase 02 (Death date source):** Check for DEATH, DEATH_CAUSE, VITAL tables in `get_pcornet_table()` dispatcher
- **Phase 02 (Death date source):** Implement flexible lookup: try DEMOGRAPHIC.DEATH_DATE first, fall back to DEATH table if exists
- **Phase 03 (Death integration):** Add data quality check: if death_date is 100% NA, warn user and skip death visualization
- **Phase 03 (Documentation):** Log death date source in script output: "Death dates from DEMOGRAPHIC" or "Death dates from DEATH table"

**Detection:**
- Schema validation: Run `PRAGMA table_info('DEMOGRAPHIC')` and grep for DEATH_DATE — if missing, adjust code
- Data quality gate: Count non-NA death_date before proceeding — if 0, halt with informative error
- Cross-validation: Compare death counts from DEMOGRAPHIC vs DEATH vs DEATH_CAUSE (if multiple sources exist) — flag discrepancies
- Unit test: Mock both schema versions (DEMOGRAPHIC.DEATH_DATE and separate DEATH table) — verify code works in both cases

**References:**
- [PCORnet CDM v7.0 Specification](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf)
- [PCORnet v6.0 Schema](https://data-models-service.research.chop.edu/models/pcornet/6.0.0)

---

## v1.7 Moderate Pitfalls

Issues causing data quality degradation or analysis errors, but recoverable.

---

### Pitfall v1.7-6: D-Code Classification Ambiguity (In Situ vs Benign vs Uncertain Behavior)

**What goes wrong:** Treating all D-codes as "benign" misclassifies in situ neoplasms (D00-D09) and uncertain behavior neoplasms (D37-D48). In situ melanoma (D03) and DCIS (D05) are clinically significant pre-malignant conditions, not benign polyps. Filtering all D-codes removes important disease progression markers.

**Why it happens:** PREFIX_MAP groups D-codes into 3 categories (In Situ, Benign, Uncertain Behavior), but decision documents refer to "removing benign D-codes" without specifying which ranges. Developers assume all D-codes are benign, but ICD-10 distinguishes:
- D00-D09: In situ neoplasms (pre-malignant, high progression risk)
- D10-D36: Benign neoplasms (low malignant potential)
- D37-D48: Uncertain behavior (cannot be classified as benign or malignant)

**Consequences:**
- Secondary cancer analysis misses in situ diagnoses (DCIS, melanoma in situ, cervical CIS)
- Progression from in situ to invasive cancer invisible in data
- Clinical narrative breaks: patient has DCIS (D05) in 2019, then invasive breast cancer (C50) in 2020, but filtered data shows only C50 (missing precursor)
- Misalignment with clinical practice: oncologists track in situ neoplasms closely, pipeline ignores them

**Prevention:**
- **Phase 01 (Scope):** Clarify: remove D10-D36 (benign) only, OR remove all D-codes?
- **Phase 01 (Scope):** Clinical decision: keep D00-D09 (in situ) as clinically relevant, remove only D10-D36 + D37-D48
- **Phase 02 (D-code filtering):** Implement tiered filtering: `filter(str_starts(cancer_code, "C") | str_sub(cancer_code, 1, 3) %in% c("D00", "D01", ..., "D09"))`
- **Phase 03 (Documentation):** Label outputs clearly: "Malignant and In Situ Neoplasms" not "Malignant Only"
- **Alternative:** Produce 3 versions: (1) C-codes only (malignant), (2) C+D00-D09 (malignant+in situ), (3) All codes (including benign)

**Detection:**
- Manual review: Spot-check removed codes — if D03.x or D05.x are excluded, flag for clinical review
- Category distribution: Compare D-code categories before/after filtering — if "In Situ" category has 0 patients, filtering is too broad
- Clinical validation: Ask oncology collaborator: should DCIS (D05) be included in secondary cancer analysis? Align code with answer.

**References:**
- [ICD-10-CM Neoplasm Codes C00-D49](https://www.icd10data.com/ICD10CM/Codes/C00-D49)
- [SEER D-Codes Training](https://training.seer.cancer.gov/icd10cm/neoplasm/d-codes.html)

---

### Pitfall v1.7-7: 7-Day Gap Calculation Excludes Same-Week Confirmations

**What goes wrong:** Requiring 7-day gap between HL codes excludes patients with HL codes on Monday and Sunday (6-day gap). Clinically, two codes in one week is strong confirmation, but >= 7 day filter treats it as unconfirmed.

**Why it happens:** R/51 implements 7-day gap as `max(distinct_dates) - min(distinct_dates) >= 7`. For dates [2020-01-01, 2020-01-07], gap = 6 days (despite spanning 8 calendar days if inclusive). Off-by-one error in interval interpretation: "7 days apart" = 6-day gap (exclusive) or 7-day gap (inclusive)?

**Consequences:**
- ~10-20% of legitimate HL patients excluded (2 codes in same week is common for hospital admission + discharge codes)
- Cohort shrinks unexpectedly, reducing statistical power
- Selection bias: excludes patients with acute presentation (clustered codes), retains patients with chronic recurrent disease (spread-out codes)

**Prevention:**
- **Phase 01 (Scope):** Clinical decision: does "7 days apart" mean >= 7 days (strict) or > 6 days (relaxed)?
- **Phase 02 (Gap logic review):** Audit R/51 — verify >= 7 vs > 6 semantics match clinical intent
- **Phase 02 (Gap logic review):** If strict interpretation unintended, change to `>= 6` or document rationale for >= 7
- **Phase 03 (Documentation):** Footnote: "7-day separation requires codes on different calendar weeks (>= 7 day gap)"
- **Alternative:** Implement both thresholds, compare cohort sizes, let clinical team decide

**Detection:**
- Unit test: Patient with codes on 2020-01-01 and 2020-01-07 (6-day gap) → should be included or excluded? Verify code matches decision.
- Sensitivity analysis: Re-run confirmation with >= 6 day threshold — if cohort size changes >10%, gap definition matters
- Manual review: Inspect excluded patients with 2+ HL codes but <7 day gap — clinical review to confirm they should be excluded

---

### Pitfall v1.7-8: Gantt Episode Data Structure Assumes Single Cancer per Episode

**What goes wrong:** Adding `cancer_category` column to treatment episodes assumes one-to-one relationship (one episode = one cancer type). But concurrent treatments exist: patient receives chemo for HL while also receiving radiation for secondary thyroid cancer. Single cancer_category column cannot represent this.

**Why it happens:** Current Gantt data structure (R/49) has one row per patient/treatment_type/episode. Adding cancer_category as a scalar column forces single-value assignment. If triggering_codes span multiple cancer categories, classify_codes() returns first match or most frequent category, arbitrarily prioritizing one over the other.

**Consequences:**
- Concurrent multi-cancer treatment invisible in data (thyroid cancer treatment misattributed to HL)
- Cancer category labels misleading: episode shows "Hodgkin Lymphoma" but triggering codes include C73 (thyroid)
- Downstream Gantt visualization shows all treatment as HL-related, missing secondary cancer events
- HIPAA suppression may undercount categories (two cancers collapsed into one → category appears less frequent)

**Prevention:**
- **Phase 01 (Scope):** Decision — how to handle multi-category episodes? Primary category only, comma-separated list, or separate rows?
- **Phase 02 (Category assignment):** Implement hierarchical category selection: HL > Other malignant > In situ > Benign
- **Phase 02 (Category assignment):** Add `cancer_categories_all` column (comma-separated) to preserve full list, use `cancer_category_primary` for visualization
- **Phase 03 (Validation):** Flag multi-category episodes in log: "X episodes span multiple cancer categories"
- **Phase 03 (Documentation):** Footnote: "Episodes with multiple cancer types show primary category only"
- **Alternative:** Split multi-category episodes into separate rows (one per category) — increases row count but preserves detail

**Detection:**
- Multi-category detection: For each episode, count distinct cancer categories in triggering_codes — if > 1, flag for review
- Category dominance check: In multi-category episodes, verify primary category is assigned consistently (e.g., always HL if HL codes present)
- Manual review: Inspect high-risk cases (e.g., SCT episodes) where multi-cancer treatment is common

---

### Pitfall v1.7-9: Death as Treatment Type Violates Episode Model

**What goes wrong:** Adding death as a treatment type breaks the episode data model. Treatments have start/stop dates and can recur (multiple chemo episodes). Death is singular, instantaneous, and final. Forcing it into treatment_type column creates semantic mismatch.

**Why it happens:** Gantt chart visualizations use treatment_type to color-code bars. Adding death to the same dimension treats it as a treatment modality rather than an outcome event. Episode model assumes repeating events (patient can have 3 chemo episodes); death happens once. Episode fields like episode_number, episode_length_days, distinct_dates_in_episode become meaningless for death.

**Consequences:**
- Episode fields contain nonsensical values: episode_number = 1 (always), episode_length_days = 0 (death is instant), distinct_dates = 1 (always)
- Treatment aggregation logic breaks: scripts that count episodes per treatment_type treat death as a "treatment" in averages
- Filtering logic fails: scripts that filter to "patients with treatment" now include all deceased patients even if untreated
- Semantic confusion: "patient received death treatment" is nonsensical phrasing

**Prevention:**
- **Phase 01 (Scope):** Decision — add death as separate event type, NOT treatment type
- **Phase 02 (Data model):** Add `outcome_events` table/column: fields = patient_id, event_type (death/remission/progression), event_date
- **Phase 02 (Gantt export):** Export treatment episodes and outcome events as separate CSVs, let visualization layer combine them
- **Phase 03 (Gantt viz):** Modify Gantt visualization code to overlay death markers on treatment timeline (vertical line, not horizontal bar)
- **Alternative (expedient but messy):** If death must be in treatment_type for visualization, add special handling: `if (treatment_type == "Death") skip episode logic`

**Detection:**
- Semantic code review: Grep for `treatment_type == "Death"` in episode aggregation logic — flag as code smell
- Unit test: Verify death rows have episode_number = 1, episode_length = 0, distinct_dates = 1 (if this approach is taken)
- Data validation: Count patients with >1 death episode — should be 0 (death happens once)

---

## v1.7 Minor Pitfalls

Small issues that degrade clarity or maintainability but don't affect correctness.

---

### Pitfall v1.7-10: is_hodgkin Binary Column Redundant with Cancer Category

**What goes wrong:** Adding `is_hodgkin` binary flag is redundant. `cancer_category == "Hodgkin Lymphoma"` already provides this information. Two columns for same fact increases maintenance burden and risk of inconsistency.

**Why it happens:** Convenience — easier to filter `is_hodgkin == 1` than `cancer_category == "Hodgkin Lymphoma"`. But redundant columns can desynchronize if one is updated without the other.

**Consequences:**
- Wasted storage (minor — one boolean per row)
- Maintenance risk: future code changes cancer_category logic but forgets to update is_hodgkin → data inconsistency
- Confusion: which column is authoritative? If they disagree, which to believe?

**Prevention:**
- **Phase 01 (Scope):** Decide: is binary flag worth redundancy cost?
- **Phase 02 (Implementation):** If including is_hodgkin, derive it from cancer_category in same mutate() call → guaranteed consistency
- **Phase 02 (Implementation):** Add assertion: `stopifnot(all((is_hodgkin == 1) == (cancer_category == "Hodgkin Lymphoma")))`
- **Alternative:** Skip is_hodgkin entirely; use `filter(cancer_category == "Hodgkin Lymphoma")` in downstream code

**Detection:**
- Unit test: Verify is_hodgkin = 1 iff cancer_category == "Hodgkin Lymphoma" for all rows
- Code review: Flag any code that updates cancer_category without also updating is_hodgkin

---

### Pitfall v1.7-11: CSV Column Addition Breaks Downstream Parsers

**What goes wrong:** Adding `triggering_code_descriptions` to gantt_episodes.csv shifts column positions. External scripts (Python, Excel macros) that reference columns by index (column 9 = historical_flag) break silently.

**Why it happens:** Gantt CSVs are consumed by third-party visualization tools (Python scripts, Excel, Tableau). These tools often hard-code column positions. Adding a column in the middle shifts all subsequent columns, breaking position-based references.

**Consequences:**
- External visualization scripts fail with type errors (reading string description into numeric field)
- Excel pivot tables reference wrong columns (historical_flag now in column 10, not 9)
- Silent data corruption: script reads column 10 thinking it's historical_flag, but it's now triggering_code_descriptions

**Prevention:**
- **Phase 01 (Scope):** Add new columns at END of CSV, never in middle
- **Phase 02 (Column ordering):** In gantt_episodes.csv, append `triggering_code_descriptions` as final column (column 10)
- **Phase 03 (Documentation):** Update CSV schema documentation with new column positions
- **Phase 03 (Versioning):** Add CSV version header: `# gantt_episodes v2.0` to signal schema change
- **Phase 03 (Migration guide):** If external tools exist, provide migration notes: "Column 10 added, columns 1-9 unchanged"

**Detection:**
- Schema diff: Compare old vs new CSV headers — verify existing columns in same positions
- External tool testing: If known downstream consumers exist, test them against new CSV format
- Manual review: Open CSV in Excel, verify column positions match documentation

**References:**
- [Handle Schema Changes Without Breaking ETL](https://airbyte.com/data-engineering-resources/handle-schema-changes-without-breaking-etl-pipeline)

---

### Pitfall v1.7-12: 1900 Sentinel Dates in Death Date Field

**What goes wrong:** DEATH_DATE column contains 1900-01-01 sentinel values (SAS missing date encoding). Code treats these as real death dates, placing all deaths at cohort start in visualizations.

**Why it happens:** PCORnet CDM encodes missing dates as 1900-01-01 (SAS epoch). R/04_build_cohort.R already nullifies 1900 sentinels in diagnosis dates, but death date ingestion may not apply same filter. Without explicit 1900 check, these dates propagate to Gantt chart.

**Consequences:**
- Gantt chart shows spike of deaths on 1900-01-01 (visualization artifact)
- Survival analysis treats sentinel dates as real → median survival = -120 years
- HIPAA suppression may trigger on 1900-01-01 death cluster (many patients with same "death date")

**Prevention:**
- **Phase 02 (Death date ingestion):** Apply same sentinel nullification as diagnosis dates: `mutate(death_date = if_else(year(death_date) == 1900, as.Date(NA), death_date))`
- **Phase 02 (Death date ingestion):** Log sentinel count: `message(glue("Nullified {n_sentinel} sentinel death dates (year 1900)"))`
- **Phase 03 (Validation):** Assert no death dates before 1960 (minimum plausible cohort birth year - 20)

**Detection:**
- Data quality check: `filter(year(death_date) < 1960)` — should return 0 rows
- Histogram: Plot death date distribution — if spike at 1900-01-01, sentinels not filtered
- Unit test: Mock death_date = 1900-01-01 → verify it becomes NA after ingestion

---

## v1.7 Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| D-code filtering (Phase 03) | v1.7-1 (PREFIX_MAP breaking change) | Filter at query layer, not by modifying PREFIX_MAP |
| D-code filtering (Phase 03) | v1.7-6 (D-code classification ambiguity) | Clarify in situ (D00-D09) vs benign (D10-D36) before filtering |
| Cohort confirmation (Phase 02) | v1.7-3 (duplicate HL confirmation logic) | Reuse R/51 or extract shared function |
| Cohort confirmation (Phase 02) | v1.7-7 (7-day gap excludes same-week) | Verify >= 7 vs > 6 day semantics match clinical intent |
| First HL date (Phase 02) | v1.7-4 (DIAGNOSIS vs TR inconsistency) | Query both tables, take minimum date, log source |
| Post-HL filtering (Phase 03) | v1.7-2 (immortal time bias) | Produce both filtered and unfiltered, label filtered as EXPLORATORY |
| Death date integration (Phase 02) | v1.7-5 (DEMOGRAPHIC vs DEATH table) | Inspect schema first, implement flexible lookup |
| Death date integration (Phase 02) | v1.7-12 (1900 sentinel dates) | Apply same nullification as diagnosis dates |
| Gantt category labels (Phase 05) | v1.7-8 (multi-category episodes) | Add cancer_categories_all (comma-separated) + cancer_category_primary |
| Death in Gantt (Phase 05) | v1.7-9 (death as treatment type) | Add as separate outcome_events, not treatment_type |
| Gantt CSV export (Phase 05) | v1.7-11 (column position breaking change) | Add new columns at end, version CSV schema |

---

## Sources

### Clinical Data Pipeline Pitfalls
- [Biases in Race and Ethnicity from Filtering EHR Data](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11967746/)
- [Temporal Relationship of Diagnoses in EHR](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7890604/)
- [Identifying Biases in Code Sequences in EHR](https://pmc.ncbi.nlm.nih.gov/articles/PMC10537851/)
- [Limitations of Diagnosis Codes in ML for Healthcare](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10868117/)

### Temporal Bias and Cohort Studies
- [Immortal Time Bias in Orthopedics](https://pmc.ncbi.nlm.nih.gov/articles/PMC8478821/)
- [Immortal Time Bias in Retrospective Studies](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8962148/)
- [Statistical Methods for Immortal Time](https://arxiv.org/pdf/2202.02369)
- [Immortal Time Bias Impact](https://blog.akianalytics.co.uk/immortal-time-bias/)
- [Statistical Approaches in Cohort Studies](https://journals.lww.com/picp/fulltext/2026/01000/statistical_approaches_in_ambispective_cohort.3.aspx)

### Data Pipeline Breaking Changes
- [Data Contracts for Pipeline Stability](https://www.acceldata.io/blog/how-data-contracts-guarantee-pipeline-reliability-data-quality-slas)
- [Stop Breaking Downstream Pipelines](https://dataskew.io/blog/data-contracts-for-data-engineers/)
- [Schema Evolution in CDC Pipelines](https://www.decodable.co/blog/schema-evolution-in-change-data-capture-pipelines)
- [Handle Schema Changes Without Breaking ETL](https://airbyte.com/data-engineering-resources/handle-schema-changes-without-breaking-etl-pipeline)

### Cancer Registry and ICD-10 Standards
- [ICD-10-CM Neoplasm Codes C00-D49](https://www.icd10data.com/ICD10CM/Codes/C00-D49)
- [SEER D-Codes Training](https://training.seer.cancer.gov/icd10cm/neoplasm/d-codes.html)
- [2026 SEER Coding Manual](https://seer.cancer.gov/manuals/2026/SPCSM_2026_MainDoc.pdf)
- [Cancer Registry Date of First Contact](https://www.registrypartners.com/ctr-coding-break-date-of-first-contact/)
- [PCORnet CDM v7.0 Specification](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf)
- [PCORnet v6.0 Schema](https://data-models-service.research.chop.edu/models/pcornet/6.0.0)

### Secondary Cancer and Surveillance
- [Risk of Secondary Cancer Among Lung Cancer Survivors](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12690424/)
- [Demographic Risk Factors for Colorectal Adenoma Recurrence](https://www.medrxiv.org/content/10.1101/2025.03.28.25324826.full.pdf)

---

**Confidence Level:** HIGH for pitfalls v1.7-1 through v1.7-5 (backed by code inspection, official ICD-10/PCORnet documentation, peer-reviewed temporal bias literature), MEDIUM for pitfalls v1.7-6 through v1.7-9 (inferred from common clinical data pipeline patterns), MEDIUM for pitfalls v1.7-10 through v1.7-12 (standard software engineering practices, limited to this codebase context).

**Research Method:** Codebase analysis (R/00_config.R, R/03-04, R/49-54), official ICD-10-CM and PCORnet CDM specifications, peer-reviewed literature on temporal bias and cohort study design, data pipeline best practices (2026 sources).

**Validation:** All critical pitfalls (v1.7-1 through v1.7-5) have explicit prevention strategies and detection methods tied to specific phases. Moderate/minor pitfalls (v1.7-6 through v1.7-12) include mitigation guidance but may require clinical judgment for final decisions.

---

## Previous Milestone Pitfalls

See below for pitfalls from v1.6 (Treatment Code Validation & Cancer Site Analysis) and earlier milestones. These remain relevant for ongoing maintenance.

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

*For complete v1.6 pitfalls and earlier milestone pitfalls, see git history or previous versions of this file.*
