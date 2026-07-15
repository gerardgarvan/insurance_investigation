# Domain Pitfalls: Adding Non-Malignant ICD Classification + Drug Attribution to an Existing Oncology Cohort Pipeline

**Domain:** PCORnet R pipeline — v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest
**Researched:** 2026-07-15
**Confidence:** HIGH (project-specific, derived from existing code + clinical informatics patterns documented in PCORnet CDM specification)

---

## Critical Pitfalls

Mistakes that produce silently wrong classification, contaminate the cancer cascade, or make clinical attribution claims the data cannot support.

---

### Pitfall 1: ICD-9/ICD-10 Numeric Collision — Confusing Short Numeric Non-Cancer Codes with ICD-9 Cancer Codes

**What goes wrong:**
The existing `classify_codes()` cascade in `utils_cancer.R` strips dots and takes 3- and 4-char prefixes. Numeric ICD-10 codes in the new diagnosis-of-interest set have prefixes that collide with ICD-9 cancer code ranges. For example:

- `D69` (ITP, IgA vasculitis) → 3-char prefix `D69` → no collision, but `D` is alpha so safe
- `M06`, `M05`, `M30`, `M31`, `M32`, `M33` → alpha prefix, no collision with ICD-9 numeric range
- `L10`, `L12`, `L95`, `I77` → alpha prefix, safe
- **Actual collision risk:** ICD-9 codes like `714.0` (RA) normalized to `7140` — prefix `714` could theoretically be confused with ICD-9 cancer range if a guard is not explicit about system

The real collision risk is not in the cancer maps themselves (those are well-bounded to C-codes and 140-209 numeric range) but in the **new ritdis map**: if someone adds a bare numeric ICD-10 code like `714` (which is a valid ICD-9 RA code), a system-agnostic prefix match will mislabel ICD-10 records whose DX_TYPE is "10" as matching an ICD-9-intended entry, or vice versa.

**Why it happens:**
`normalize_icd()` in `utils_icd.R` strips dots and uppercases. It does not separate ICD-9 from ICD-10. The existing HL matching function `is_hl_diagnosis()` correctly partitions by `DX_TYPE` ("09"/"10") before matching. A new ritdis classifier that skips `DX_TYPE` gating and does only prefix matching will misclassify ICD-9 RA code `714.0` as a match when it encounters an ICD-10 record with a code beginning in "714" — or miss legitimate ICD-9 RA records if the lookup only contains ICD-10 prefixes.

Concrete example from the seed set: `ICD-9 714.0` (RA) and `ICD-10 M06.9` both need to be captured. If the ritdis map conflates them into one undifferentiated prefix list, any ICD-10 record with a coincidentally matching prefix is a false positive.

**How to avoid:**
- Mirror the `is_hl_diagnosis()` pattern exactly: separate ICD-9 and ICD-10 ritdis code sets in `R/00_config.R` (e.g., `RITDIS_CODES$icd10` and `RITDIS_CODES$icd9`), and gate matching by `DX_TYPE` ("09"/"10") before prefix comparison.
- For ICD-9 entries, use exact-list matching (same as HL ICD-9 list) rather than prefix matching, because ICD-9 numeric ranges overlap more broadly with each other.
- Never add a bare integer prefix to the ritdis map that could span both coding systems.

**Warning signs:**
- Patient counts for RA spike implausibly after adding the ritdis layer — suggests ICD-9 RA codes are being matched on ICD-10 records.
- Any ritdis match found on a patient whose entire DIAGNOSIS record set is post-2015 (all ICD-10) but the matching code is a numeric-only format.
- A smoke-test check comparing `n_patients_with_ritdis_icd9 / n_patients_with_icd9_dx_records` — if that ratio is >> expected RA prevalence (~1% of an HL cohort), ICD-9/10 confusion is likely.

**Phase to address:** Code-set centralization phase (Phase 1 of v3.3 roadmap — the `R/00_config.R` addition).

---

### Pitfall 2: Dotted-vs-Undotted Format Mismatch in Exact-List Matching

**What goes wrong:**
The seed set in `ritdis_seed_codes.md` uses dotted notation (`M06.9`, `M05.9`, `I77.82`, `D69.2`, `L10.1`). PCORnet sites export codes in both dotted and undotted formats. If the ritdis lookup table stores dotted codes but the DIAGNOSIS table delivers undotted codes (or vice versa), exact-list matching produces zero hits with no error.

**Why it happens:**
`normalize_icd()` strips dots from input, but if the lookup table is built from the un-normalized seed (i.e., the named vector keys are `"M06.9"` not `"M069"`), the `%in%` check fails silently. The existing HL code list in `ICD_CODES` stores codes with dots in the source vector but `is_hl_diagnosis()` normalizes both sides before matching. A copy-paste of the ritdis codes into a new config block without normalizing both sides is the exact trap.

**How to avoid:**
- Define `RITDIS_CODES` in `R/00_config.R` using the same normalization convention as `ICD_CODES` — store codes in their natural format and normalize at match time using `normalize_icd()` on both the lookup vector and the input column, matching the `is_hl_diagnosis()` pattern.
- Add an `is_ritdis_diagnosis()` function in `utils_icd.R` (or a new `utils_ritdis.R`) that mirrors `is_hl_diagnosis()` signature: `(icd_code, icd_type)` — this forces the caller to always pass both, preventing format drift.
- In the smoke test, add a check: `all(normalize_icd(RITDIS_CODES$icd10) %in% normalize_icd(RITDIS_CODES$icd10))` trivially passes but catches if normalization produces `NA`s.

**Warning signs:**
- Zero ritdis hits on the full OneFlorida+ cohort after code addition — RA prevalence in an HL cohort should be non-zero (RA and lymphoma share immunosuppression risk; expect at minimum a handful of patients).
- `str_detect(DIAGNOSIS$DX, "M06")` manually returns rows but `is_ritdis_diagnosis()` returns `FALSE` for those same rows — format mismatch confirmed.

**Phase to address:** Code-set centralization + `is_ritdis_diagnosis()` utility function (Phase 1 of v3.3 roadmap).

---

### Pitfall 3: Prefix Over-Capture — Short Prefixes Pulling in Unintended Codes

**What goes wrong:**
`classify_codes()` uses 3- and 4-character prefix matching. For the ritdis set, some categories are defined by short prefixes that span more codes than intended.

Examples from the seed set:
- `M06.0x` (various joint sites of RA without RF) — 3-char prefix `M06` would also capture `M06.1` (adult-onset Still's disease), `M06.2` (rheumatoid bursitis), `M06.3` (rheumatoid nodule), `M06.4` (inflammatory polyarthropathy), etc. — some of these are NOT RA.
- `M33.x` — 3-char prefix `M33` captures all dermatomyositis AND polymyositis. If only dermatomyositis is intended, a 3-char prefix over-captures.
- `L10.x` — 3-char prefix captures all pemphigus variants including `L10.2` (pemphigus foliaceus) and `L10.3` (pemphigus brasiliensis) which may or may not be in scope.
- `M30.x`, `M31.x` — broad vasculitis categories, each spans many specific conditions.

**Why it happens:**
The seed set lists parent-level codes (M06.0x, M05.x) as shorthand, which is clinically reasonable. But translated literally into a prefix map using 3-char keys, they capture sibling codes not intended. The existing cancer classification uses 3-char prefixes for cancer site categories where the entire 3-char block is the same cancer — this assumption does not hold for autoimmune ICD blocks.

**How to avoid:**
- For each ICD-10 category in the ritdis set, enumerate the specific 4- and 5-char codes rather than relying on 3-char prefix shortcuts. Use the ICD-10-CM tabular list (CMS FY2026 release) to verify which sub-codes are actually in scope.
- For codes where an entire 3-char block is appropriate (e.g., `G36` — demyelinating diseases — where `G36.0` is Devic's and no other `G36.x` is plausible as a rituximab non-indication), 3-char prefix is acceptable, but document the justification.
- Create a `RITDIS_CODES_AUDIT.md` or inline code comments listing which sub-codes within each prefix were explicitly reviewed and intentionally included or excluded.
- Implement a verification step in the classification phase script: after classifying, `tabyl(ritdis_category)` and review that the count per category is clinically plausible.

**Warning signs:**
- Counts for "Vasculitis" or "Dermatomyositis" are implausibly high relative to RA (RA should dominate the rituximab non-malignant indication space).
- The same patient appears in two ritdis sub-categories simultaneously because a broad prefix captured a sibling code (e.g., `M06.1` flagged as RA when `M06.0x` was the intended target).

**Phase to address:** Code-set completeness/verification (Phase 1, before any classification scripts are written); also flag for clinical review at Phase 2 when counts are first visible.

---

### Pitfall 4: Overlap / Double-Counting with the Existing Cancer Cascade — Codes Present in Both

**What goes wrong:**
Some codes in the ritdis scope are ambiguous and could legitimately appear in both the cancer and non-malignant diagnosis layers.

Concrete examples:
- **Paraneoplastic pemphigus (`L10.81`)** — explicitly listed in the seed set. This is a skin manifestation OF cancer, not an independent autoimmune condition being treated with rituximab for its own sake. A patient with HL + `L10.81` almost certainly has the pemphigus as a cancer complication, not as a separate rituximab indication.
- **Dermatomyositis (`M33.x`)** — dermatomyositis is associated with paraneoplastic syndromes; up to 30% of adult-onset dermatomyositis cases are paraneoplastic. Classifying all `M33.x` in an oncology cohort as "non-malignant rituximab indication" is clinically risky.
- **`D69.2` IgA vasculitis (Henoch-Schönlein purpura)** — rare in adults; if found in a lymphoma cohort, could be paraneoplastic.
- **Neuromyelitis optica (`G36.0`)** — not directly cancer-related, but the code could appear in a cancer patient as a concurrent condition unrelated to the drug attribution question.
- **Codes near cancer ranges:** `D59.x` (autoimmune hemolytic anemia, AIHA) is in the D50-D89 hematologic range. `D69.3` (ITP) is also in that range. The existing `is_cancer_code()` function uses the `CANCER_SITE_MAP` / `ICD9_CANCER_SITE_MAP` prefix maps — verify that `D59` and `D69` prefixes are NOT in those maps. If they somehow are (e.g., due to a DRY-01 consolidation that added them), the ritdis layer would be tagging codes already claimed by the cancer cascade.

**Why it happens:**
The non-malignant ritdis layer is built independently of the cancer cascade. Without an explicit mutual-exclusivity check, both layers can fire on the same code for the same patient-encounter.

**How to avoid:**
- **Structural guarantee:** After running `is_ritdis_diagnosis()`, assert: `sum(is_ritdis_diagnosis(dx, dx_type) & is_cancer_code(dx)) == 0` across the full DIAGNOSIS table. This must be zero. If it is not zero, the overlap codes must be resolved — either remove from the ritdis set, or add to an exclusion list.
- **`L10.81` policy decision:** Remove paraneoplastic pemphigus from the ritdis code set or flag it separately as "paraneoplastic" rather than "non-malignant indication." This is a clinical judgment call that should be documented explicitly.
- **Mutual exclusivity by design:** Define the classification hierarchy explicitly: cancer cascade runs first; ritdis layer only classifies codes that `is_cancer_code()` returns FALSE for. Implement this as a filter gate in the classification script.
- Add a cross-tabulation to the smoke test: `anti_join` the ritdis code set against CANCER_SITE_MAP keys — should be zero overlapping prefixes.

**Warning signs:**
- A patient appears in both `ritdis_category` (non-malignant) and a cancer category for the same diagnosis code on the same encounter.
- The paraneoplastic pemphigus code (`L10.81`) appears in the ritdis prevalence table for many patients — in an HL cohort, paraneoplastic pemphigus is extremely rare as an independent rituximab indication.

**Phase to address:** Classification script (Phase 2 of v3.3 roadmap); mutual-exclusivity assertion should be a hard stop before any output is produced.

---

### Pitfall 5: Attribution False-Positives — Methotrexate is Extremely Common for Non-Lymphoma Indications

**What goes wrong:**
Methotrexate (MTX) has dozens of FDA-approved and common off-label uses that have nothing to do with lymphoma: low-dose RA treatment, psoriasis (`L40.x`), psoriatic arthritis (`L40.5x`), Crohn's disease (`K50.x`), ectopic pregnancy (`O00.x`), and occasionally severe asthma. An HL patient who also has RA may have been on low-dose MTX for years before and during lymphoma treatment.

The attribution false-positive occurs when:
1. Patient has HL
2. Patient also has MTX administration records
3. Pipeline infers "MTX was for a non-malignant condition" based on presence of an RA code — but the MTX was actually part of the MOPP/COPDAC-COPP regimen or another lymphoma protocol

Or the reverse:
1. Patient has RA + MTX for years
2. Patient develops HL, receives R-CHOP (which contains neither MTX nor rituximab as standard, but some centers add rituximab)
3. The RA+MTX records remain in DIAGNOSIS/PRESCRIBING
4. Pipeline flags the MTX as "non-malignant indication" when it is actually pre-dating the cancer, genuinely for RA

**Why it happens:**
Temporal windowing around a drug administration date is insufficient on its own. The drug's dose, formulation, and the clinical context (specialist, diagnosis cluster) all matter but are not reliably coded in PCORnet. Low-dose MTX (7.5-25 mg/week oral) for RA is pharmacologically distinct from high-dose IV MTX for lymphoma, but the RXNORM code may be identical.

**How to avoid:**
- **Never claim attribution — only flag co-occurrence.** The output column should be named `mtx_nonmalignant_dx_cooccurrence` (not `mtx_for_ra`). The report should state "MTX administration occurred within [window] days of a non-malignant diagnosis code in the ritdis set" — not "this MTX was for RA."
- **Dose/route as a discriminator (where available):** In PRESCRIBING and MED_ADMIN, check `RX_DOSE` and `RX_ROUTE`. High-dose IV MTX (≥500 mg/m²) is always lymphoma-directed. Weekly oral low-dose (<25 mg) is almost certainly autoimmune-directed. Document this as a flag, not a definitive classification.
- **Temporal directionality:** Distinguish MTX that predates the HL diagnosis date by >6 months (likely pre-existing autoimmune use) from MTX that starts within 60 days of HL diagnosis (likely lymphoma-directed). Include both directions in the output table but flag them differently.
- **Rituximab differs from MTX:** Rituximab at full infusion dose (375 mg/m² or 500-1000 mg fixed dose) for autoimmune conditions vs 375 mg/m² for R-CHOP in lymphoma — indistinguishable by RXNORM alone. Do not attempt to disambiguate rituximab by dose unless dose data is available and reliable.

**Warning signs:**
- The drug-attribution report shows >50% of rituximab administrations linked to a non-malignant diagnosis — implausible in an HL cohort where rituximab in R-CHOP or BV+AVD is the primary use.
- Methotrexate co-occurrence rate exceeds the known RA prevalence in the underlying population.

**Phase to address:** Temporal window design + output column naming (Phase 3, attribution linkage). Must be enforced in the output column definitions before any report is written.

---

### Pitfall 6: Temporal Window Selection Traps — "Active at Time of Drug" vs "Ever Present"

**What goes wrong:**
PCORnet DIAGNOSIS records have `ADMIT_DATE` (encounter date) but no "diagnosis end date" or "condition resolved" flag. A code present in the medical record at any point in history does not mean the condition was active when the drug was administered.

Concrete failure modes:
- **Stale historical code:** Patient had RA in 2010, went into remission, no RA codes after 2013. Rituximab administered in 2023 for HL. A wide temporal window (e.g., "any time before drug") finds the 2010 RA codes and falsely flags the rituximab as "possibly for RA."
- **Narrow window misses legitimate cases:** Patient with active RA has codes every 3-6 months at rheumatology visits. A ±30-day window around a rituximab infusion may miss the most recent RA visit if it was 45 days prior (annual visit cycle).
- **Diagnosis code on the day of chemotherapy:** Some sites bundle problem-list codes onto every encounter. An RA code on a chemotherapy encounter does not mean the chemotherapy was for RA — it means RA is on the problem list.

**How to avoid:**
- **Recency weighting:** Prefer diagnosis codes within 12 months before drug administration over codes from earlier periods. Codes older than 3 years with no recent renewal should be down-weighted or flagged separately.
- **Explicit window parameter in config:** Define `RITDIS_PARAMS$lookback_days` and `RITDIS_PARAMS$lookforward_days` as named config values (consistent with `ANALYSIS_PARAMS` pattern in `R/00_config.R`). Default recommendation: 365-day lookback, 90-day lookforward.
- **Flag "same-encounter codes"** separately — these are the highest false-positive risk because problem lists inflate co-occurrence.
- **Document window choice:** The report should state the window used. Clinical readers can then apply their own judgment.
- Do NOT use the `CONDITION` table for this purpose without understanding its grain — the CONDITION table in PCORnet CDM stores self-reported or registry-sourced conditions, not encounter-based diagnoses, and has its own date fields (`ONSET_DATE`, `RESOLVE_DATE`) which are more useful for "active" inference but may be sparsely populated in this extract (per Phase 100's finding that CONDITION was used only as a "3rd-tier supplement").

**Warning signs:**
- Attribution linkage rate is dramatically higher when using "any history" vs "within 1 year" — suggests stale historical codes are driving results.
- The oldest RA-type codes for attributed patients predate the HL diagnosis by >5 years with no recent codes.

**Phase to address:** Temporal window design (Phase 3); CONDITION table usage decision (Phase 1 or 2, since Phase 100 already investigated its coverage).

---

### Pitfall 7: DIAGNOSIS vs CONDITION Table Confusion

**What goes wrong:**
PCORnet CDM has two distinct tables for clinical conditions:
- **DIAGNOSIS** — encounter-based ICD codes from claims and clinical documentation; the primary source for this pipeline's cancer detection; `ADMIT_DATE` is the encounter date
- **CONDITION** — a separate table of diagnosed conditions with `ONSET_DATE` and `RESOLVE_DATE` (when populated), drawn from problem lists, registries, or self-report; used in Phase 100 as a 3rd-tier cancer linkage supplement

Using CONDITION as the primary source for ritdis classification would:
1. Miss patients whose autoimmune diagnoses are only coded in DIAGNOSIS (the majority)
2. Potentially double-count patients whose records appear in both tables
3. Conflate `ONSET_DATE` (when the condition started, often imprecise) with `ADMIT_DATE` (when the encounter occurred) in temporal window calculations
4. Expose a known coverage gap: Phase 100 found CONDITION was sparsely populated in this extract

**Why it happens:**
CONDITION is the "semantically correct" table for chronic conditions (RA is a chronic disease, not just an encounter diagnosis). A naive design choice would query CONDITION for RA and DIAGNOSIS for encounter-level drugs. But this extract's CONDITION table has known sparseness.

**How to avoid:**
- Primary source: DIAGNOSIS table, using `ADMIT_DATE` for temporal windows.
- CONDITION table: Optional supplement, clearly labeled if used, with a coverage report (how many patients have CONDITION records at all for the relevant codes).
- Do not mix ADMIT_DATE and ONSET_DATE in the same temporal window calculation without explicit documentation.
- Follow the Phase 100 pattern: query CONDITION separately, join on PATID, add a `source_table` column ("DIAGNOSIS" or "CONDITION") to enable downstream filtering.

**Warning signs:**
- ritdis classification finds patients who have no DIAGNOSIS records with the ritdis codes — they are being found only in CONDITION, which is sparse and may represent a biased subset of patients (e.g., only certain sites populate CONDITION).
- Counts differ materially (>20%) between DIAGNOSIS-only and DIAGNOSIS+CONDITION approaches.

**Phase to address:** Code-set and table-scope definition (Phase 1). Decision must be made before classification script is written.

---

### Pitfall 8: Clinical Validity — Rituximab + RA Code Does NOT Prove Rituximab Was for RA

**What goes wrong:**
Presenting output that says "N patients received rituximab for non-malignant indications" over-claims the data. The pipeline can only show co-occurrence. Clinical attribution requires chart review, which this pipeline does not perform.

Rituximab is an anti-CD20 antibody used for:
- B-cell lymphomas (the primary use in this cohort)
- RA (when MTX-inadequate response)
- ANCA-associated vasculitis (GPA, MPA)
- Pemphigus vulgaris
- NMO spectrum disorder
- ITP (off-label)
- AIHA (off-label)

In every case, the RXNORM code is the same. The dose, cycle, and ordering provider specialty are the only distinguishing features available in PCORnet — and all three are incompletely documented.

**How to avoid:**
- Use language of co-occurrence throughout: "rituximab administration co-occurred with a non-malignant diagnosis code in [category]" — not "rituximab was administered for [category]."
- Add a `CAVEATS` column or footnote to every output table: "Co-occurrence does not imply treatment attribution. Clinical chart review required for confirmation."
- Output a separate `attribution_confidence` flag with only two valid values: `"co-occurrence_only"` (default) and `"high_confidence"` (reserved for cases where the rituximab started > 6 months before HL diagnosis, suggesting pre-existing autoimmune use).
- Flag in the RMarkdown/Tableau report that this analysis is hypothesis-generating, not conclusive.

**Warning signs:**
- Any output column named `rituximab_for_*` or `mtx_reason_*` — reject this naming convention. Names should be `rituximab_with_*_dx` or `mtx_with_*_dx`.
- Report prose that says "patients received rituximab for autoimmune conditions" without the co-occurrence caveat.

**Phase to address:** Output design and column naming (Phase 3 attribution linkage, and enforced in Phase 4 report writing). This is also a code-review gate — flag and reject any PR that uses attribution language.

---

### Pitfall 9: HIPAA Small-Cell Suppression — Rare Autoimmune Conditions Produce Cells of 1-10

**What goes wrong:**
The ritdis code set includes rare conditions:
- Neuromyelitis optica (`G36.0`) — prevalence ~1-4 per 100,000; in a Hodgkin lymphoma cohort of several thousand patients, expect 0-5 patients
- Pemphigus vulgaris — prevalence ~1 per 100,000; similarly tiny
- GPA/Wegener's — ~3 per 100,000
- Microscopic polyangiitis — rarer still
- Paraneoplastic pemphigus in HL — extremely rare

Any output table stratified by ritdis category × payer (or ritdis category × treatment line, or ritdis category × site) will produce cells of 1-10 for these conditions.

**Why it happens:**
The HIPAA Safe Harbor method prohibits reporting counts of 1-10 for any cell that could identify an individual. The existing pipeline has HIPAA suppression logic for the cancer and payer layers (per PROJECT.md: "All patient counts 1-10 must be suppressed in any output") but it must be explicitly extended to the ritdis layer.

**How to avoid:**
- Apply the same small-cell suppression function used in existing outputs to every ritdis count column before writing to xlsx or the Tableau-ready CSV.
- Consider collapsing rare categories in the Tableau-ready output: "GPA/Wegener's", "MPA", and "Other ANCA vasculitis" may need to be merged into "ANCA-associated vasculitis" if individual sub-category counts are <11.
- Add a `suppressed` flag column (TRUE/FALSE) alongside each count column so Tableau can display "<11" without exposing the real value.
- Smoke test: After running the classification script on real data (HiPerGator), add a check that no output xlsx cell in a count column contains an integer between 1 and 10 without suppression.

**Warning signs:**
- Neuromyelitis optica or pemphigus vulgaris rows appear in Tableau output with exact counts of 1-10.
- The sub-category breakdown table has many rows with single-digit integers.

**Phase to address:** Every phase that produces output. Define the suppression helper in Phase 1 (alongside the code set) so it is available from the start, and enforce it in Phase 3 (output table) and Phase 4 (report).

---

### Pitfall 10: Dual-Environment Verification Gap — Structural Pass on Windows, Runtime Never Confirmed

**What goes wrong:**
The project's explicit constraint (per PROJECT.md Key Decisions, row marked "⚠️ Revisit"): "Dual-environment verification: structural on Windows, runtime on HiPerGator." Phase 126 was attested by prose only for the smoke test. v3.3 will add new scripts (ritdis classification, attribution linkage, report) that have never run against real data. Structural verification (linting, fixture-based local test) is not sufficient to catch:
- Columns that exist in the fixture DIAGNOSIS table but are named differently in the real extract (e.g., `DX_TYPE` vs `DX_TYPE_CD` observed in some PCORnet extracts)
- Real data containing code formats not represented in the 20-patient fixture (e.g., a ritdis code that arrives undotted in the real extract but dotted in the fixture)
- Actual counts that trigger HIPAA suppression (the fixture has 20 patients, so suppression logic can never be exercised)
- Performance: the ritdis classification loop over the full DIAGNOSIS table (millions of rows) may time out or OOM on HiPerGator if not using DuckDB queries

**How to avoid:**
- **Explicit HiPerGator runtime gate in the smoke test:** Add a v3.3 section to `R/88` that runs only when `!IS_LOCAL`, queries the full DIAGNOSIS table via DuckDB for ritdis matches, and logs counts. This forces runtime confirmation to be part of the definition of done.
- **Fixture coverage for ritdis codes:** Add at least one patient to the test fixture (or a new fixture) who carries a ritdis ICD-10 code and one who carries the ICD-9 equivalent (`714.0` for RA), so local structural testing exercises the classification path.
- **DuckDB-native classification where possible:** Instead of loading all DIAGNOSIS rows into R and classifying in-memory, push the prefix filter into DuckDB SQL (e.g., `WHERE LEFT(DX, 3) IN ('M06', 'M05', ...)`). This is consistent with the backend abstraction pattern.
- **Attest HiPerGator runtime explicitly** in the phase transition notes — not "prose only."

**Warning signs:**
- Ritdis classification script works on fixtures (IS_LOCAL=TRUE) but produces zero hits on HiPerGator — column name mismatch.
- R session killed on HiPerGator during classification — memory limit exceeded from loading full DIAGNOSIS table.
- Smoke test passes on Windows but has never been run on HiPerGator for the v3.3 sections.

**Phase to address:** All phases. Fixture augmentation in Phase 1; DuckDB-native approach in Phase 2; HiPerGator runtime gate in Phase 4 (smoke test and SCRIPT_INDEX registration).

---

### Pitfall 11: Smoke-Test Staleness — New Scripts Registered But Not Validated

**What goes wrong:**
v3.3 will add new scripts to `R/39` (SCRIPT_INDEX) and `R/88` (comprehensive smoke test). If a script is added to SCRIPT_INDEX but the corresponding R/88 section is not written, or if the R/88 section checks only that the script exists (not that its outputs are correct), the smoke test provides false confidence.

This was the failure mode in Phase 126 (stale `episode_classification_audit.xlsx` caused R/88 to fail until regenerated). The ritdis layer adds new output files (ritdis prevalence table, drug co-occurrence table) that R/88 needs to verify exist, have the correct columns, and have non-zero row counts.

**How to avoid:**
- For each new script added in v3.3, write the R/88 smoke-test section at the same time as the script (not after). The section must check: output file exists, expected columns present, count columns are numeric, no unsuppressed 1-10 values in count columns.
- Registration in R/39 and R/88 addition are both definition-of-done criteria for every v3.3 phase.
- The smoke-test section must include a check that `!IS_LOCAL` runtime has been confirmed (e.g., a log file from the last HiPerGator run is present and recent).

**Warning signs:**
- R/39 SCRIPT_INDEX has v3.3 scripts listed but R/88 has no corresponding section.
- R/88 passes on Windows but its v3.3 sections only check file existence, not content validity.

**Phase to address:** Phase 4 (smoke test and registration), but the R/88 sections should be drafted in each execution phase alongside the script itself.

---

### Pitfall 12: Code-Set Maintainability — Ritdis Codes Will Require Annual Updates

**What goes wrong:**
ICD-10-CM is updated annually (October 1 effective date). New codes are added, some codes are revised, and occasionally entire sub-categories are restructured. A ritdis code set that is correct for FY2025 may be incomplete for FY2026 and beyond. Because the pipeline hardcodes ICD-9 and ICD-10 lists in `R/00_config.R`, updates require manual code edits.

Additionally, the seed set (`ritdis_seed_codes.md`) has documented gaps: GPA/Wegener's M31.3x codes, myasthenia gravis G70.0x codes, ITP D69.3, AIHA D59.x, SLE M32.x, Sjögren's M35.0x — none of these are enumerated in the RTF. These gaps must be filled before Phase 1 ships, or the ritdis set is incomplete from day one.

**How to avoid:**
- **Fill the gaps before coding:** Research and enumerate all missing code groups from the seed document (GPA, MPA, myasthenia gravis, ITP, AIHA, SLE, Sjögren's, psoriasis/psoriatic arthritis, IBD for MTX). This is a prerequisite to Phase 1.
- **Version the code set:** Add a `RITDIS_CODE_VERSION` constant in `R/00_config.R` (e.g., `"FY2026_v1"`) and a comment with the ICD-10-CM fiscal year the set was last verified against.
- **Audit trail in config comments:** For each code group, add a comment indicating the CMS ICD-10-CM table reference and date verified.
- **Annual update checkpoint:** Document in the project that the ritdis code set must be reviewed each October when CMS releases the new ICD-10-CM table.

**Warning signs:**
- The ritdis code set ships without codes for ITP, AIHA, SLE, Sjögren's, GPA/MPA, myasthenia gravis, psoriasis, or IBD — all are confirmed seed gaps.
- No version comment or date on the `RITDIS_CODES` block in `R/00_config.R`.

**Phase to address:** Phase 1 (code-set centralization). The gap-filling research must be complete before Phase 1 begins; this is the primary input the current research task is providing.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Use 3-char prefix for entire ICD-10 block | Fewer lines in config | Over-capture of sibling codes; false-positive classification | Never for autoimmune blocks; only where entire block is in scope |
| Claim attribution ("MTX for RA") in output column names | Clearer to end users | Over-claims the data; clinically misleading | Never — use co-occurrence language only |
| Skip `DX_TYPE` gating, match all codes against unified prefix map | Simpler code | ICD-9/ICD-10 collision; incorrect classification for historical patients | Never — always gate by DX_TYPE |
| Use "any history" temporal window (no lookback limit) | More complete capture | Stale historical codes drive false attribution; RA from 2010 attributed to 2023 rituximab | Acceptable only if clearly labeled "ever-present" and distinct from "active" analysis |
| Defer HiPerGator runtime until after milestone ships | Faster local iteration | Undiscovered column mismatches, OOM errors, or HIPAA violations in production output | Never — runtime confirmation must be part of definition of done |
| Add L10.81 (paraneoplastic pemphigus) to ritdis without flagging | Complete the pemphigus category | Paraneoplastic codes in an oncology cohort are rarely independent autoimmune indications | Never add without a separate `paraneoplastic_flag` column |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `is_cancer_code()` + new ritdis layer | Assume they are mutually exclusive by definition | Assert zero overlap using `which(is_ritdis_diagnosis(dx, dx_type) & is_cancer_code(dx))` on full DIAGNOSIS table before any output |
| DIAGNOSIS table DX_TYPE column | Assume all records have a clean "09" or "10" value | DX_TYPE can be NA, "SM" (SNOMED), or other codes in PCORnet; handle NA and non-ICD values as FALSE in `is_ritdis_diagnosis()` |
| PRESCRIBING/MED_ADMIN for drug attribution | Filter by RXNORM code alone | Rituximab and MTX RXNORM codes are shared across all indications; require temporal join to diagnosis records, not just presence of the RXNORM code |
| CONDITION table as supplement | Mix ONSET_DATE and ADMIT_DATE in temporal window | Use ADMIT_DATE from DIAGNOSIS as the primary temporal anchor; document separately if CONDITION is added as a supplement |
| DuckDB query for ritdis classification | Load full DIAGNOSIS into R, then classify in memory | Push prefix filter into DuckDB SQL to reduce rows returned; use `collect()` only on filtered result |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Load full DIAGNOSIS table into R for classification | R session OOM on HiPerGator; slow on 5M+ row tables | Push DX prefix filter into DuckDB WHERE clause before collect() | At ~500k+ rows in DIAGNOSIS |
| Cross-join DIAGNOSIS × drug administration for temporal window | Cartesian product of millions of rows | Filter each table to relevant codes first, then join on PATID, then apply date window | With any non-trivial cohort size |
| `str_detect()` regex on full DX column without pre-filtering | 5-10x slower than prefix-based DuckDB filter | Use DuckDB LEFT(DX, 3/4) IN (...) and collect the subset | At >100k rows |
| Save ritdis output as RDS in the default cache without size check | Cache fills `/blue/` storage with large intermediate files | Estimate output size before caching; use `pryr::object_size()` in dev | If DIAGNOSIS table has many ritdis-positive rows |

---

## "Looks Done But Isn't" Checklist

- [ ] **Ritdis code set:** Appears complete with RA, vasculitis, pemphigus, NMO — but verify ITP (D69.3), AIHA (D59.x), SLE (M32.x), Sjögren's (M35.0x), GPA (M31.3x), MPA, myasthenia gravis (G70.0x), psoriasis (L40.x), psoriatic arthritis (L40.5x), and IBD (K50.x/K51.x for MTX) are ALL enumerated
- [ ] **Mutual exclusivity with cancer cascade:** Classification script exists but the assertion `sum(is_ritdis & is_cancer) == 0` has never been run on real data
- [ ] **ICD-9 gating:** ICD-9 ritdis codes (714.0, 341.0) are in the lookup but `is_ritdis_diagnosis()` is not partitioning by DX_TYPE before matching
- [ ] **HIPAA suppression:** Output table exists but count columns have not been passed through the suppression function
- [ ] **Attribution language:** Output columns or report prose uses "for" (causal) instead of "with" (co-occurrence)
- [ ] **HiPerGator runtime:** All v3.3 scripts pass locally on fixtures but have not been run on HiPerGator with real data
- [ ] **Smoke test sections:** New scripts are in SCRIPT_INDEX (R/39) but R/88 has no corresponding validation sections, or those sections only check file existence
- [ ] **Temporal window:** Drug-attribution output is produced but the window parameters are hardcoded magic numbers rather than named `RITDIS_PARAMS` config values
- [ ] **Paraneoplastic pemphigus:** L10.81 is in the ritdis set but has no separate paraneoplastic flag — it will inflate the "pemphigus" category with cancer-related codes

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| ICD-9/10 collision (Pitfall 1) | Phase 1: Code-set centralization in R/00_config.R | `is_ritdis_diagnosis()` unit test with DX_TYPE="09" and "10" inputs; smoke test assertion |
| Dotted/undotted mismatch (Pitfall 2) | Phase 1: `is_ritdis_diagnosis()` function using normalize_icd() on both sides | Unit test with both formats as input; zero-hit detection on real data |
| Prefix over-capture (Pitfall 3) | Phase 1: Enumerate 4-char codes; Phase 2: tabyl() review | Count per category vs expected clinical prevalence; clinical reasonableness review |
| Cancer cascade overlap (Pitfall 4) | Phase 2: Mutual-exclusivity assertion before output | `sum(is_ritdis & is_cancer) == 0` assertion in classification script AND smoke test |
| MTX attribution false-positives (Pitfall 5) | Phase 3: Column naming convention; no causal attribution claims | Code review of all output column names; reject any "for" language |
| Temporal window traps (Pitfall 6) | Phase 3: Named config params; recency weighting; same-encounter flag | Lookback sensitivity analysis (30-day vs 365-day vs "any history") in output report |
| DIAGNOSIS vs CONDITION confusion (Pitfall 7) | Phase 1: Table scope decision documented in config | Check that CONDITION is not primary source; source_table column in output |
| Clinical validity over-claiming (Pitfall 8) | Phase 3-4: Output design and report prose | Co-occurrence language audit; CAVEATS footnote present in every output |
| HIPAA small-cell suppression (Pitfall 9) | Every output phase | Smoke test: no integer 1-10 in count columns of any output xlsx |
| Dual-environment gap (Pitfall 10) | All phases; HiPerGator gate in Phase 4 | R/88 has IS_LOCAL-gated section that runs on HiPerGator; runtime attested in transition notes |
| Smoke-test staleness (Pitfall 11) | Phase 4, but draft alongside each execution phase | R/88 sections check file exists + correct columns + non-zero counts + suppression |
| Code-set maintainability / seed gaps (Pitfall 12) | Phase 1 prerequisite: research fills all seed gaps | RITDIS_CODE_VERSION constant in config; all seed-gap categories present |

---

## Sources

**Project-Specific (HIGH confidence — derived from this codebase):**
- `R/utils/utils_icd.R` — `is_hl_diagnosis()` pattern used as the correct template for `is_ritdis_diagnosis()`
- `R/utils/utils_cancer.R` — `classify_codes()` prefix-matching approach and its ICD-9/10 cascade logic
- `R/00_config.R` — ICD code list structure, ANALYSIS_PARAMS naming convention, IS_LOCAL dual-environment pattern
- `.planning/PROJECT.md` — HIPAA suppression requirement, dual-environment constraint, CONDITION table Phase 100 finding, Phase 126 smoke-test attestation gap
- `.planning/research/ritdis_seed_codes.md` — Documented gaps in seed code set (GPA, myasthenia gravis, ITP, AIHA, SLE, Sjögren's, MTX-specific indications)

**Clinical Informatics (HIGH confidence — established PCORnet CDM documentation patterns):**
- PCORnet CDM v7.0 specification: DIAGNOSIS table grain (encounter-level ICD codes with DX_TYPE "09"/"10"), CONDITION table grain (condition-level with ONSET_DATE/RESOLVE_DATE) — these are distinct semantic layers
- ICD-10-CM FY2026 tabular list (effective 2025-10-01): M06 block scope, M33 block scope, L10 block scope — prefix boundaries verified
- Clinical literature: MTX indications (RA, psoriasis, IBD, ectopic pregnancy), rituximab indications (B-cell lymphoma, RA, GPA, pemphigus, NMO, ITP, AIHA) — attribution ambiguity is a known limitation in pharmacoepidemiology studies using administrative data

**HIPAA Safe Harbor (HIGH confidence):**
- 45 CFR §164.514(b)(2): Cell sizes of 1-10 must be suppressed in de-identified data sets — this is the project's standing constraint per PROJECT.md

---
*Pitfalls research for: v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest — non-malignant ICD classification + drug attribution layer added to existing PCORnet HL cohort R pipeline*
*Researched: 2026-07-15*
