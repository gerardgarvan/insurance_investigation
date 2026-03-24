# Domain Pitfalls

**Domain:** PCORnet CDM R Analysis — Multi-site Payer Harmonization and Cohort Building
**Researched:** 2026-03-24
**Confidence:** MEDIUM-HIGH

## Critical Pitfalls

### Pitfall 1: Naive Payer Category Assignment Without Temporal Overlap Detection

**What goes wrong:**
Analysts assign patients to single payer categories based on enrollment start/end dates without detecting dual-eligible periods (overlapping Medicare + Medicaid enrollment). This leads to severe undercount of dual-eligible beneficiaries — the most vulnerable population that often experiences the worst outcomes. Results show misleading payer disparities because dual-eligibles are miscategorized as "Medicare only" or "Medicaid only" based on arbitrary record ordering or enrollment date priority rules.

**Why it happens:**
PCORnet ENROLLMENT table contains multiple rows per patient with overlapping ENR_START_DATE and ENR_END_DATE periods. Dual-eligible status requires detecting when Medicare enrollment (PAYER_TYPE_PRIMARY/SECONDARY = '1') temporally overlaps with Medicaid enrollment (PAYER_TYPE_PRIMARY/SECONDARY = '2'). Simple filtering or first/last record selection misses this overlap pattern entirely. The Python pipeline has explicit dual-eligible detection logic that R reimplementations often skip, assuming "one row = one patient" or "last enrollment = current insurance."

**How to avoid:**
1. Implement temporal overlap detection: for each patient, identify all date ranges where Medicare and Medicaid enrollments co-exist
2. Create a dual-eligible flag when PAYER_TYPE_PRIMARY/SECONDARY contains both '1' and '2' with overlapping date ranges
3. Prioritize dual-eligible category over single-payer categories in the 9-category hierarchy
4. Validate against Python pipeline's dual-eligible counts — should match within 5%
5. Document the specific date ranges used for overlap detection (exact date? month-level? 30-day window?)

**Warning signs:**
- Dual-eligible count is < 5% of Medicare + Medicaid combined count (should be 10-20% for typical cohorts)
- Sum of 9 payer categories ≠ unique patient count (indicates categorization logic failure)
- Payer stratified attrition shows implausible patterns (e.g., Medicare patients younger than Medicaid patients)
- "Unknown" or "Unavailable" payer category is > 15% (often a symptom of failed temporal logic)

**Phase to address:**
Phase 1 (Data Loading & Payer Harmonization) — core logic must be correct before cohort building

---

### Pitfall 2: ICD Code Matching Without Handling Both Dotted and Undotted Formats

**What goes wrong:**
ICD codes in PCORnet DIAGNOSIS table arrive in multiple formats: dotted (C81.10), undotted (C8110), with trailing zeros (C81.1), without (C81.1x where x is literal character). Naive string matching (`DX %in% c("C81.10", "C81.11", ...)`) misses ~30-50% of true diagnoses because source systems use inconsistent formatting. This causes massive undercounting of cohort-eligible patients and breaks reproducibility when comparing to Python pipeline results.

**Why it happens:**
PCORnet CDM specification does not enforce a single canonical ICD format. Each partner site (AMS, UMI, FLM, VRT) maps from their source EHR using different ETL conventions. Some strip dots during ETL, some preserve them. Some pad with zeros, some truncate. R analysts assume stringr::str_detect() with a simple pattern will work, but regex requires escaping the dot (\\.) to match literal periods, and many forget this. Additionally, ICD-9 (201.xx) and ICD-10 (C81.xx) have different format rules and decimal placement conventions.

**How to avoid:**
1. Normalize ALL DX codes to a single format (recommend: undotted, uppercase) in the data loading phase
2. Normalize the reference ICD code list (149 codes) to the same format
3. Use `stringr::str_remove_all(DX, "\\.")` to strip dots from both data and reference
4. For regex matching, escape dots properly: `str_detect(DX, "C81\\.1")` or use fixed matching with normalized codes
5. Build both ICD-9 and ICD-10 patterns separately: `str_detect(DX, "^C81|^201")` handles both families
6. Validate match counts against Python pipeline — should be within 2% for same data extract

**Warning signs:**
- Cohort size is 40-60% smaller than Python pipeline on identical data
- Visual inspection of DIAGNOSIS table shows mix of "C81.10" and "C8110" patterns but filter only catches one
- Filter log shows large drop in patients between "has diagnosis table rows" and "matches ICD codes"
- str_detect() test queries return FALSE for codes that visually appear to match

**Phase to address:**
Phase 1 (Data Loading & Payer Harmonization) — normalize during initial load, before cohort filters applied

---

### Pitfall 3: Date Parsing Failures from Multi-Format SAS Date Exports

**What goes wrong:**
PCORnet date fields (ENR_START_DATE, DX_DATE, BIRTH_DATE) export from SAS-based partner ETLs in inconsistent formats across files and even within files: DATE9 format (01JAN2020), DATETIME format (01JAN2020:00:00:00), YYYYMMDD numeric (20200101), or Excel-style serial dates (43831). readr::read_csv() auto-detection samples first 1000 rows and guesses wrong ~20% of the time for large files. Dates parse as character strings or integers, causing filter failures, incorrect temporal logic, and silent data loss when lubridate::ymd() returns NA for unparsable formats.

**Why it happens:**
PCORnet CDM specification allows multiple date formats. Partner sites use different SAS PROC EXPORT settings, and SAS formats don't map cleanly to R date types. OneFlorida+ has 4 partners (AMS, UMI, FLM, VRT) each potentially using different export formats. readr's sampling-based type detection is fast but unreliable for heterogeneous date columns. Analysts often copy-paste read_csv() calls without col_types specification, trusting auto-detection. SAS DATE9 format includes month abbreviations (JAN, FEB) that lubridate handles, but DATETIME format with colons requires parse_date_time() with explicit orders, which analysts forget.

**How to avoid:**
1. NEVER rely on readr auto-detection for date columns — always specify col_types explicitly
2. Use col_types = cols(.default = col_character()) to load everything as character initially
3. Implement multi-format date parser using lubridate::parse_date_time() with orders = c("dmy", "ymd", "mdy", "dmy HMS", "ymd HMS")
4. Build a date validation function that checks for NA rates > 5% and logs format distribution
5. Document the date formats found in each CSV during initial load for troubleshooting
6. Handle Excel serial dates separately (common when CSVs opened/saved in Excel): as.Date(as.numeric(x), origin = "1899-12-30")

**Warning signs:**
- Warning messages: "X parsing failures" during read_csv()
- Date columns show as <chr> instead of <date> in glimpse()
- Filter operations on dates return zero rows (dates parsed as character, comparison fails)
- NA rate in date columns > 5% after parsing (indicates format mismatch)
- Temporal filters (e.g., "enrollment after diagnosis") produce empty results despite data existing

**Phase to address:**
Phase 1 (Data Loading & Payer Harmonization) — date parsing must succeed before any temporal logic or cohort building

---

### Pitfall 4: Ignoring ENROLLMENT Table Gaps and Misinterpreting Missing Coverage as "No Insurance"

**What goes wrong:**
Analysts assume if a patient has no ENROLLMENT record for a time period, they were uninsured. In reality, PCORnet ENROLLMENT represents "periods where medical care should be observed," and gaps can mean: (1) care delivered outside the partner's network, (2) partner doesn't capture enrollment for non-insured patients (common for AMS, UMI), (3) patient was insured but partner has no claims/encounter data, or (4) data quality issue (missing ETL mapping). Treating gaps as "uninsured" inflates the "No payment/Self-pay" category and creates spurious payer transitions in Sankey diagrams.

**Why it happens:**
PCORnet CDM documentation states enrollment is "often insurance-based, but other methods of defining enrollment are allowed" and explicitly notes "For partners that do not have insurance-based enrollment information for some of their patients, other approaches can be used." Analysts coming from claims-based research assume enrollment = insurance coverage period. Partner-specific quirks compound this: FLM is claims-only (complete enrollment for insured, nothing for uninsured), VRT is death-only (no enrollment records at all), AMS and UMI have encounter-based enrollment (3-year lookback windows, not insurance windows).

**How to avoid:**
1. Read .planning/PROJECT.md section on partner provenance — understand each partner's enrollment data model
2. Create separate "Unknown/Missing enrollment" category distinct from "No payment/Self-pay" (which requires explicit PAYER_TYPE_PRIMARY = '9')
3. For encounter-based enrollment (AMS, UMI), enrollment gaps ≠ insurance gaps — document this limitation
4. Validate enrollment gap patterns by partner: FLM should have fewer gaps (claims-complete), VRT will have all gaps (death-only)
5. In Sankey diagrams, handle missing enrollment as separate flow to avoid implying insurance status changes
6. Compare enrollment completeness rates across partners — if one partner has 90% gaps and others have 10%, it's a data model difference not a population difference

**Warning signs:**
- "No payment/Self-pay" category is > 30% of cohort (implausible for cancer patients in U.S.)
- Sankey diagram shows massive flows from "Medicaid" to "No payment" to "Medicaid" (spurious transitions from gaps)
- Enrollment gap rate varies dramatically by partner (e.g., VRT 100% gaps, AMS 15% gaps)
- Patients have diagnoses and procedures but zero enrollment records (common with encounter-based enrollment)
- Dual-eligible detection finds zero cases despite Medicare + Medicaid existing in data (gaps prevent overlap detection)

**Phase to address:**
Phase 2 (Cohort Building & Filtering) — enrollment logic must be sound before payer-stratified outputs

---

### Pitfall 5: HIPAA Small-Cell Suppression Applied Incorrectly (Primary Only, No Secondary)

**What goes wrong:**
Analysts apply primary cell suppression (hide counts 1-10) in tables and charts, but fail to implement secondary suppression to prevent back-calculation. Example: a 3x3 table with row/column totals where one cell is suppressed — readers can subtract observed cells from the total to recover the suppressed value. This is a direct HIPAA violation. CMS policy explicitly states "no cell can be reported that allows a value of 1 to 10 to be derived from other reported cells or information." Published outputs with recoverable suppressed cells can trigger IRB violations and revocation of data access.

**Why it happens:**
Analysts understand primary suppression ("hide small counts") but don't understand mathematical disclosure by differencing. Secondary suppression requires suppressing 2-3 additional cells to prevent back-calculation, which feels like "losing too much data." There's no R package that auto-implements secondary suppression (unlike SAS PROC TABULATE with suppression rules). ggplot2 and ggalluvial don't have built-in suppression — analysts manually filter data, forgetting that marginal totals in the chart expose suppressed strata.

**How to avoid:**
1. Build a suppression validation function that checks: for every suppressed cell, can it be recovered from marginal totals?
2. Implement secondary suppression: when a cell is suppressed, suppress 2-3 additional cells in the same row/column
3. For waterfall charts with attrition counts: if any step has N ∈ [1, 10], suppress that count AND the counts before/after to prevent differencing
4. For Sankey diagrams: if any flow (edge) has N ∈ [1, 10], consider suppressing the entire payer stratum or aggregating into "Other" category
5. Document suppression rules explicitly in code comments: "Cell A suppressed (N=7), cells B and C suppressed to prevent recovery of A = Total - B - C"
6. Manual review checklist: "For every suppressed value, try to back-calculate it from visible totals — if possible, add secondary suppression"

**Warning signs:**
- Waterfall chart shows attrition steps with exact counts where one step is labeled "<11" but you can compute it by subtraction
- Sankey diagram has visible flows where sum of incoming ≠ sum of outgoing and one flow is suppressed
- Tables have suppressed cells but row/column totals are visible (test: can you solve for the suppressed cell?)
- 9-category payer breakdown sums to total cohort N despite one category suppressed (category is recoverable)
- Pilot review comments flag "I can figure out the suppressed counts"

**Phase to address:**
Phase 3 (Visualizations & Outputs) — apply suppression during output generation, with validation before export

---

### Pitfall 6: Incidence-Prevalence Bias from Cohort Definition Using Prevalent Cases

**What goes wrong:**
Cohort is defined as "patients with HL diagnosis in dataset" without restricting to incident (newly diagnosed) cases. This includes prevalent cases (diagnosed years before data window, receiving long-term follow-up). Prevalent cases over-represent long-term survivors, underestimate mortality, and bias payer analyses because insurance status changes over disease course (e.g., transition to Medicare at age 65, or to Medicaid after disability/financial toxicity). Payer disparities appear smaller than reality because you're comparing survivors (prevalent) not all diagnosed patients (incident).

**Why it happens:**
ICD code filter (`has_HL_diagnosis`) identifies patients with diagnosis codes but doesn't distinguish first diagnosis from follow-up encounters. PCORnet DIAGNOSIS table doesn't have a "newly diagnosed" flag. DX_DATE represents encounter date where diagnosis was recorded, not true diagnosis date (patient diagnosed elsewhere, presents to OneFlorida partner later → DX_DATE is delayed). Analysts focus on "building a cohort" without considering epidemiologic bias from case selection.

**How to avoid:**
1. Define index date as first observed HL diagnosis (min(DX_DATE) per patient) within the study window
2. Restrict cohort to patients where index date falls within a defined incident window (e.g., 2015-2020)
3. Exclude patients with HL diagnosis codes before the incident window (requires looking back to all available data)
4. Sensitivity analysis: compare results using "any HL diagnosis" vs "incident HL only" — if results differ substantially, incident definition is critical
5. Document the incident vs prevalent case definition in .planning/PROJECT.md and analysis outputs
6. Acknowledge limitation if partner data doesn't support incident case restriction (e.g., insufficient lookback period)

**Warning signs:**
- Mean time from diagnosis to treatment is very short (suggests capturing prevalent cases in treatment phase, not true diagnosis)
- Payer distribution at diagnosis is heavily Medicare (suggests capturing older survivors, not younger at-diagnosis population)
- Cohort size is much larger than expected for incident HL in Florida (suggests prevalent cases inflating N)
- Survival/mortality appears unrealistically high (survivor bias from prevalent cases)
- Age distribution is older than national HL incidence patterns (HL bimodal: 20s and 60s; prevalent cohort skews older)

**Phase to address:**
Phase 2 (Cohort Building & Filtering) — cohort definition must specify incident vs prevalent case selection

---

### Pitfall 7: Immortal Time Bias from Misaligned Index Date and Exposure Start

**What goes wrong:**
Cohort definition: "Patients diagnosed with HL who received treatment X." Index date (time-zero) is set to diagnosis date, but patients are only included if they eventually received treatment X (determined by looking forward from diagnosis). This creates immortal time between diagnosis and treatment receipt — patients who died before receiving treatment are excluded, biasing survival/outcome analyses upward. Payer-stratified analyses show misleading results because "treatment received" is conditioned on survival long enough to receive it, and payer affects time-to-treatment.

**Why it happens:**
Analysts define cohort retrospectively using complete information: "we know this patient got radiation, so include them." This violates the temporal logic of prospective observation. The bias is invisible in code — it looks like a simple filter (`has_radiation = TRUE`). In pharmacoepidemiology, immortal time bias is well-documented, but clinical researchers often don't recognize it. PCORnet data enables time-dependent analyses but requires explicit date-based filtering, not binary flags.

**How to avoid:**
1. Define index date (time-zero) as first diagnosis date (DX_DATE for HL ICD codes)
2. Define exposure (treatment) based on events AFTER index date only
3. Use time-dependent analysis: model "time to treatment" or "treatment within 90 days of diagnosis" instead of binary "received treatment"
4. Do NOT exclude patients who died before treatment — include them as "no treatment" and analyze time-to-event
5. For payer-stratified analyses, assign payer at index date (diagnosis) not at treatment date
6. Sensitivity analysis: restrict to patients who survived at least 90 days post-diagnosis to isolate treatment effect from early mortality

**Warning signs:**
- Cohort filter chain: "has_diagnosis → has_treatment → has_outcome" (implies looking forward from diagnosis to determine inclusion)
- All patients in cohort have treatment records (excludes patients who died before treatment)
- Time from diagnosis to treatment has no upper bound (includes patients treated years later, suggests retrospective definition)
- Payer at treatment date differs from payer at diagnosis for >30% of patients (suggests using treatment date as index)
- Survival outcomes are much better than published literature for same cancer type (survivor bias from requiring treatment)

**Phase to address:**
Phase 2 (Cohort Building & Filtering) — index date and temporal logic must be correct before any outcome analysis

---

### Pitfall 8: Partner-Specific Data Quirks Treated as Data Quality Issues

**What goes wrong:**
Analyst discovers that FLM has 80% fewer encounters than AMS, VRT has zero procedure records, UMI has no pharmacy data — interprets this as "bad data quality" and considers excluding these partners. In reality, these are expected partner-specific data models: FLM is claims-only (complete for insured, sparse for uninsured), VRT is death-only (contributes DEATH table not clinical data), UMI is academic medical center (inpatient focus, less outpatient), AMS is large network (comprehensive). Excluding partners reduces sample size and introduces selection bias.

**Why it happens:**
PCORnet distributes data across heterogeneous partners with different source systems and capture models. .planning/PROJECT.md documents this ("Partner provenance: Some partners are claims-only (FLM), some have mapped ICD codes (AMS, UMI), one is death-only (VRT)"), but analysts don't read project context before diving into code. Multi-site data heterogeneity is a feature not a bug of CDRNs — it enables studying diverse populations and care settings. Analysts expect uniform EHR-like data and panic when partners differ.

**How to avoid:**
1. Read .planning/PROJECT.md Context section BEFORE data exploration — understand partner data models
2. Profile data completeness BY PARTNER: create table of encounter counts, diagnosis counts, procedure counts per partner
3. Document expected missingness patterns: FLM low encounters for uninsured (expected), VRT zero procedures (expected, death-only)
4. Do NOT exclude partners based on missingness — instead, stratify analyses by partner to detect site-specific patterns
5. Acknowledge multi-site heterogeneity as limitation in outputs: "Partner X contributes primarily insured patients, Partner Y contributes death data"
6. Validate partner-specific patterns against OneFlorida+ documentation (if available) or query project PI

**Warning signs:**
- Automated data quality checks flag entire partners as "low quality" based on missingness
- Analyst proposes excluding VRT or FLM from analysis without understanding their data models
- Encounter rates vary 10-fold between partners, treated as error rather than documented heterogeneity
- Cohort size by partner shows extreme imbalance (e.g., AMS 500 patients, VRT 2 patients) and analyst assumes VRT data is "broken"
- Analysis plan doesn't account for partner-specific data capture differences

**Phase to address:**
Phase 1 (Data Loading & Payer Harmonization) — profile and document partner-specific patterns early, before cohort building

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip col_types specification, rely on readr auto-detection | Faster initial code writing (5 min saved) | Date parsing failures, type mismatches, silent data corruption — 2-4 hours debugging later | NEVER for date columns, ENR dates, DX dates, BIRTH_DATE — auto-detection fails 20% of time |
| Use `DX %in% c(...)` for ICD matching instead of normalized + regex | Simpler code, no regex knowledge needed | Misses 30-50% of diagnoses due to format variation (dotted vs undotted) — cohort size wrong | Never for ICD codes — always normalize or use regex with both formats |
| Assign payer by last enrollment record instead of temporal logic | One-liner: `group_by(PATID) %>% slice_max(ENR_END_DATE)` | Misses dual-eligible patients, wrong payer assignments for ~15% of cohort | Only if dual-eligible is not a research question AND Python pipeline validation not required |
| Apply primary cell suppression only, skip secondary | Faster to implement, don't lose as much data | HIPAA violation, IRB risk, data access revocation | Never — secondary suppression is mandatory for any shared output |
| Load all 22 CSVs at once with read_csv() without memory checks | Convenient, "just load everything" | R crashes with out-of-memory errors on ENCOUNTER (millions of rows), DIAGNOSIS tables | Only on high-memory HiPerGator nodes (64GB+) or for small test datasets |
| Hardcode file paths instead of using config.R | Faster initial setup | Breaks when moving to HiPerGator, sharing code with collaborators, running on different machines | Only for initial prototype on local machine — must switch to config.R before HiPerGator |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Python pipeline payer logic | Assume R and Python will "just match" without validation | Load Python pipeline's payer mapping CSV, use as reference, validate R output matches within 5% for dual-eligible, Medicare, Medicaid counts |
| HiPerGator filesystem | Use relative paths from RStudio working directory | Use absolute paths from config.R: `/path/to/oneflorida/data/` — RStudio working directory changes between sessions |
| ggalluvial Sankey with small cells | Plot raw data, suppress counts in axis labels | Filter data to remove suppressed flows BEFORE ggplot() call — otherwise flows are visible even if labels hidden |
| lubridate + dplyr::mutate | Use mutate(DX_DATE = ymd(DX_DATE)) expecting error handling | Wrap in tryCatch or use parse_date_time with multiple orders — ymd() fails silently on non-ymd formats |
| PCORnet value sets (NI, OT, UN) | Treat NI (No Information) as NA and filter out | Retain NI, OT (Other), UN (Unknown) as distinct categories — they carry information about data provenance and should be reported separately |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| read_csv() with auto-detection on large files (ENCOUNTER 5M+ rows) | Hangs for 5-10 minutes during type guessing phase | Specify col_types explicitly, or use vroom::vroom() with col_types for faster parsing | Files > 1GB, especially ENCOUNTER, DIAGNOSIS, PROCEDURES |
| Unnested filter chains without intermediate counts | 20-step filter chain runs, final N is surprisingly small, no idea which step failed | Log N after every filter step: `log_attrition <- function(df, step_name) { message(step_name, ": N=", nrow(df)); df }` | Cohort building phase — essential for debugging filter logic |
| Repeated full joins on PATID without indexing | Multi-minute join times on 100k+ patient cohort | Use dplyr joins (already optimized) but check for duplicate PATIDs before joining — duplicates cause exponential explosion | Joining ENROLLMENT to DIAGNOSIS to PROCEDURES — explodes if ENROLLMENT has overlaps |
| ggplot2 with millions of points for Sankey | R crashes or produces 50MB PNG files | Aggregate to payer-stratum level BEFORE ggalluvial — plot flows (N per payer transition) not individual patients | Cohorts > 50k patients with 9 payer categories and 3+ time points |
| stringr operations on millions of ICD codes | str_detect() runs for minutes on DIAGNOSIS table | Normalize once during data load, use fixed matching instead of regex where possible, or vectorize with str_detect(DX, pattern) | DIAGNOSIS table with 500k+ rows — normalize early, filter late |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Include raw PATIDs in output charts or logs | Re-identification risk, HIPAA violation if PATID is linked to other datasets | Strip PATIDs before creating any output objects, use anonymous row numbers for debugging |
| Log exact counts < 11 in console messages during debugging | Console history saved in .Rhistory, may be shared or committed to git | Suppress exact counts in logs: `if (n < 11) message("N < 11 (suppressed)") else message("N = ", n)` |
| Export intermediate CSVs with unsuppressed data to shared folder | Data breach if folder permissions too open, IRB violation | Keep intermediate data in secure HiPerGator directory with restricted permissions, only export suppressed final outputs |
| Hardcode date ranges or patient counts in code comments | Exposes cohort size and study period, may be PHI if combined with public info | Use generic comments: "Study period: YYYY-MM-DD to YYYY-MM-DD" without revealing exact cohort N |
| Share R scripts with absolute paths that reveal project/PI names | Information disclosure about study design and collaborators | Use config.R with variables: `data_path <- Sys.getenv("DATA_PATH")` instead of `/blue/PI_NAME/project_name/` |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Waterfall chart with unsuppressed intermediate steps | User sees exact attrition counts, some < 11, HIPAA violation in output | Apply suppression to ALL steps, not just final N — if any step N ∈ [1,10], suppress it and adjacent steps |
| Sankey diagram with 9 payer categories where 4 have < 20 patients | Visual clutter, hard to read, exposes small cells | Aggregate rare categories into "Other" (combine "Other government", "Other", "Unavailable" if each < 20) |
| Filter chain output is "Cohort: N = 347" with no context | User doesn't know what filters were applied, can't reproduce | Log every step: "After has_HL_diagnosis: N=1203 → After age_18_plus: N=891 → After enrollment_overlap: N=347" |
| Date parsing warnings printed to console but analysis continues | User assumes dates parsed correctly, doesn't notice 15% NAs | Stop execution on parsing warnings: `if (sum(is.na(DX_DATE)) > 0.05 * n()) stop("Date parsing failed for >5% of records")` |
| Payer category "Unknown" is 25% of cohort with no explanation | User questions data quality, loses trust in results | Document known reasons for Unknown: "Unknown includes VRT (death-only, no enrollment), FLM uninsured patients (no enrollment)" |

## "Looks Done But Isn't" Checklist

- [ ] **Dual-eligible detection:** Often missing temporal overlap logic — verify by checking if dual-eligible count is 10-20% of Medicare + Medicaid combined
- [ ] **ICD code normalization:** Often missing format harmonization — verify by testing both dotted and undotted codes in test queries
- [ ] **Date parsing validation:** Often missing NA rate checks — verify by asserting sum(is.na(date_col)) / n() < 0.05 after parsing
- [ ] **Secondary suppression:** Often missing in tables/charts — verify by attempting to back-calculate suppressed cells from marginal totals
- [ ] **Enrollment gap handling:** Often misinterpreted as "uninsured" — verify by checking enrollment gap rates by partner (should vary if partner-specific data models exist)
- [ ] **Partner-specific profiling:** Often skipped, all partners treated uniformly — verify by creating completeness table (encounter counts, diagnosis counts) stratified by partner
- [ ] **Index date definition:** Often undefined or inconsistent — verify by checking that index date (time-zero) is documented and cohort inclusion doesn't look forward from index date
- [ ] **Attrition logging:** Often incomplete (only final N reported) — verify by checking that EVERY filter step logs N before and after
- [ ] **ICD-9 and ICD-10 both included:** Often only ICD-10 implemented — verify by testing with known ICD-9 code (201.90) and ICD-10 code (C81.90) in separate queries
- [ ] **Configuration externalized:** Often hardcoded paths in scripts — verify by checking that config.R exists and all file paths reference config variables

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Payer categories don't match Python pipeline | MEDIUM (4-8 hours) | 1. Export Python pipeline's PATID-to-payer mapping as CSV reference. 2. Inner join R output to Python reference on PATID. 3. Compare payer assignments, identify discrepancies. 4. Debug temporal overlap logic for dual-eligible. 5. Re-run cohort pipeline. |
| ICD matching misses 40% of diagnoses | MEDIUM (3-6 hours) | 1. Profile DX format distribution (dotted vs undotted). 2. Build normalization function to strip dots and uppercase. 3. Apply to both data and reference ICD list. 4. Re-run has_HL_diagnosis filter. 5. Validate cohort N against Python. |
| Date parsing failures cause temporal logic errors | HIGH (8-12 hours) | 1. Reload CSVs with col_character() for all date columns. 2. Profile date formats using regex patterns. 3. Build multi-format parser with parse_date_time(orders = c(...)). 4. Validate NA rate < 5%. 5. Re-run entire cohort pipeline from data load. |
| Small-cell suppression recoverable by differencing | LOW (1-2 hours) | 1. Identify suppressed cells. 2. For each suppressed cell, check if row/column totals allow back-calculation. 3. Add secondary suppression for 2-3 adjacent cells. 4. Regenerate charts/tables. 5. Manual review to confirm no recovery possible. |
| Cohort includes prevalent cases, biasing payer analyses | HIGH (6-10 hours) | 1. Define incident window (e.g., 2015-2020). 2. Calculate first DX_DATE per PATID. 3. Filter to patients where first DX_DATE in incident window. 4. Check for lookback bias (need data before incident window to exclude prevalent). 5. Re-run cohort and compare to original. |
| Enrollment gaps misinterpreted, "Unknown" payer is 40% | MEDIUM (4-6 hours) | 1. Profile enrollment by partner (gap rates, enrollment patterns). 2. Read PROJECT.md partner provenance. 3. Separate "Unknown/Missing enrollment" from "No payment/Self-pay". 4. Document partner-specific limitations. 5. Re-categorize and regenerate outputs. |
| Immortal time bias from retrospective cohort definition | HIGH (8-15 hours) | 1. Redefine index date as first diagnosis. 2. Remove filters that look forward from index (e.g., "has_treatment"). 3. Implement time-dependent analysis (time to treatment, treatment within 90 days). 4. Include all patients who meet diagnosis criteria. 5. Re-run analysis. |
| Partner data quirks treated as errors, partners excluded | LOW (2-3 hours) | 1. Review PROJECT.md Context section. 2. Profile data completeness by partner. 3. Restore excluded partners. 4. Stratify analyses by partner or control for partner in models. 5. Document heterogeneity as limitation. |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Dual-eligible detection failure | Phase 1: Data Loading & Payer Harmonization | Dual-eligible count is 10-20% of Medicare + Medicaid combined, matches Python pipeline within 5% |
| ICD format mismatch | Phase 1: Data Loading & Payer Harmonization | Test query with known dotted + undotted codes both return TRUE, cohort N matches Python within 2% |
| Date parsing failures | Phase 1: Data Loading & Payer Harmonization | All date columns show <date> type in glimpse(), NA rate < 5%, no parsing warnings in console |
| Enrollment gap misinterpretation | Phase 2: Cohort Building & Filtering | Enrollment gap rates vary by partner (as expected from partner data models), "Unknown" payer < 15% |
| Incidence-prevalence bias | Phase 2: Cohort Building & Filtering | Index date defined as first DX_DATE, cohort restricted to incident window, age distribution matches HL epidemiology |
| Immortal time bias | Phase 2: Cohort Building & Filtering | Index date = diagnosis date, cohort inclusion doesn't require survival to treatment, exposure defined post-index only |
| Partner quirks treated as errors | Phase 1: Data Loading & Payer Harmonization | Data completeness table by partner created, PROJECT.md partner provenance consulted, no partners excluded based on missingness |
| Small-cell suppression violations | Phase 3: Visualizations & Outputs | Manual review: attempt to back-calculate all suppressed cells from visible totals — if possible, secondary suppression added |

## Sources

### PCORnet CDM and Data Quality
- [PCORnet Common Data Model v7.0 Specification](https://pcornet.org/wp-content/uploads/2025/01/PCORnet-Common-Data-Model-v70-2025_01_23.pdf) — Official CDM specification
- [Tailoring Rule-Based Data Quality Assessment to PCORnet CDM](https://pmc.ncbi.nlm.nih.gov/articles/PMC10148276/) — Data quality validation approaches
- [CDM Data Quality Validation](https://pcornet.org/wp-content/uploads/2024/12/CDM-Data-Quality-Validation.pdf) — Quality validation strategies
- [Clinical encounter heterogeneity in networked EHR data](https://www.medrxiv.org/content/10.1101/2022.10.14.22281106v1.full) — Multi-site heterogeneity challenges

### Payer and Enrollment Data
- [Harmonization of CDMs and Open Standards](https://aspe.hhs.gov/harmonization-various-common-data-models-open-standards-evidence-generation) — CDM harmonization challenges
- [CMS Guidance: Dual-Eligible Beneficiaries](https://www.medicaid.gov/tmsis/dataguide/t-msis-coding-blog/cms-guidance-reporting-expectations-for-dual-eligible-beneficiaries-updated/) — Dual-eligible detection requirements
- [Identifying Dual Eligible Medicare Beneficiaries](https://resdac.org/articles/identifying-dual-eligible-medicare-beneficiaries-medicare-beneficiary-enrollment-files) — Dual status identification methods
- [EHR vs Claims Data Gaps](https://aspe.hhs.gov/sites/default/files/documents/023bf056262c303792f8522a7c442f28/aspe-covid-data-gaps.pdf) — Enrollment and payer data limitations
- [Sentinel System: Claims vs EHR Data](https://www.sentinelinitiative.org/sites/default/files/documents/Claims_vs_EHR.pdf) — Data source limitations

### Cohort Building and Bias
- [Inclusion and Exclusion Criteria](https://pmc.ncbi.nlm.nih.gov/articles/PMC6044655/) — Common mistakes in cohort definition
- [Immortal Time Bias in Cohort Studies](https://pmc.ncbi.nlm.nih.gov/articles/PMC12089111/) — Concept explanation and prevention
- [Immortal Time Bias in Observational Studies](https://link.springer.com/article/10.1186/s12874-022-01581-1) — EHR-specific immortal time issues
- [Where to Look for the Most Frequent Biases](https://pmc.ncbi.nlm.nih.gov/articles/PMC7318122/) — Temporal bias in clinical research

### ICD Code Matching
- [Regular Expression Pattern ICD Codes](https://www.johndcook.com/blog/2019/05/05/regex_icd_codes/) — Regex for ICD matching
- [ICD-9 and ICD-10 Code Regex](https://gist.github.com/jakebathman/c18cc117caaf9bb28e7f60e002fb174d) — Format handling examples
- [Are ICD Codes Reliable for Observational Studies](https://pmc.ncbi.nlm.nih.gov/articles/PMC11528819/) — Coding consistency and format issues
- [stringr Regular Expressions](https://stringr.tidyverse.org/articles/regular-expressions.html) — R regex with stringr

### R Data Parsing and Performance
- [Reading Large Data Files in R](https://inbo.github.io/tutorials/tutorials/r_large_data_files_handling/) — Performance best practices
- [readr Column Types](https://readr.tidyverse.org/articles/column-types.html) — Type specification to avoid auto-detection
- [lubridate parse_date_time](https://lubridate.tidyverse.org/reference/parse_date_time.html) — Multi-format date parsing
- [datefixR Package](https://docs.ropensci.org/datefixR/) — Handling messy date formats
- [Wrangling Categorical Data in R](https://peerj.com/preprints/3163.pdf) — Factor handling pitfalls

### HIPAA Small-Cell Suppression
- [CMS Cell Size Suppression Policy](https://resdac.org/articles/cms-cell-size-suppression-policy) — Official suppression requirements
- [Review of Statistical Disclosure Control](https://pmc.ncbi.nlm.nih.gov/articles/PMC5409873/) — Implementation failures and prevention
- [Washington DOH Small Numbers Standards](https://www.doh.wa.gov/portals/1/documents/1500/smallnumbers.pdf) — Secondary suppression implementation

### Domain-Specific Experience
- Personal experience with OneFlorida+ PCORnet CDM data (reflected in PROJECT.md partner provenance documentation)
- Python pipeline payer harmonization logic (reference implementation for dual-eligible detection)

---
*Pitfalls research for: PCORnet CDM R Analysis — Multi-site Payer Harmonization and Cohort Building*
*Researched: 2026-03-24*
