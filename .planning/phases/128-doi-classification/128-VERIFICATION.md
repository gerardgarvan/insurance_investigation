---
phase: 128-doi-classification
verified: 2026-07-15T22:30:00Z
status: passed
score: 8/8 must-haves verified
re_verification: false
human_verification:
  - test: "Run R/111_doi_classification.R against real DIAGNOSIS table on HiPerGator and review tabyl(doi_category) output"
    expected: "RA encounters dominate; NMO and pemphigus rows are rare; overlap_n == 0 confirmed on real data; doi_encounters.rds and doi_patients.rds produced with non-zero row counts"
    why_human: "No Rscript execution against real DuckDB DIAGNOSIS table in Windows environment; real-data counts and .rds artifact production are the Phase 130 HiPerGator gate"
  - test: "Inspect doi_encounters.rds on HiPerGator: confirm paraneoplastic_flag == TRUE rows still carry doi_category == 'Pemphigus'"
    expected: "All L10.81 rows have paraneoplastic_flag = TRUE and doi_category = 'Pemphigus' — no paraneoplastic row reclassified to a separate category"
    why_human: "Requires real data execution; structural check confirms code path is correct but cannot validate against actual L10.81 rows in the extract"
---

# Phase 128: DoI Classification Verification Report

**Phase Goal:** Encounter-level and patient-level DoI classification artifacts are produced from the real DIAGNOSIS table with a hard guarantee that no oncology code leaks into the DoI layer.
**Verified:** 2026-07-15T22:30:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | R/111 exists and pulls DIAGNOSIS via a DuckDB-native prefix filter that runs before collect() | VERIFIED | `get_pcornet_table("DIAGNOSIS")` at line 114; `filter(substr(DX, 1, 3) %in% doi_prefixes3)` at line 123; `collect()` at line 125 — filter line (123) precedes collect line (125) |
| 2 | Mutual-exclusivity assertion runs and halts script before any .rds is written | VERIFIED | `stopifnot(... = overlap_n == 0)` at line 170–172; first `saveRDS` at line 185 — hard-stop precedes both saves |
| 3 | doi_encounters.rds written at (ID, ENCOUNTERID, DX_DATE, doi_code, doi_category, paraneoplastic_flag, in_hl_cohort) grain | VERIFIED | `select(ID, ENCOUNTERID, DX_DATE, doi_code, doi_category, paraneoplastic_flag, in_hl_cohort)` at line 182; `saveRDS(doi_encounters, doi_encounters_path, compress = TRUE)` at line 185 |
| 4 | L10.81 encounters carry paraneoplastic_flag = TRUE while staying in doi_category 'Pemphigus' | VERIFIED | `paraneoplastic_flag = str_remove(toupper(DX), "\\.") %in% c("L1081")` at line 146; classified by `classify_doi_codes(DX)` which maps L10.x to 'Pemphigus'; no exclusion of paraneoplastic rows from doi_category |
| 5 | doi_patients.rds derived from doi_encounters grain at one row per ID | VERIFIED | `doi_patients <- doi_encounters %>% group_by(ID) %>% summarise(...)` at lines 203–213; comment at line 200 states "DIAGNOSIS is NOT re-queried (DOI-CLASS-03)" |
| 6 | doi_patients has all six required fields (has_any_doi, doi_categories, doi_first_date, doi_last_date, n_doi_encounters, in_hl_cohort) | VERIFIED | All six fields present in summarise block lines 206–212; ascending-collapse `paste(sort(unique(doi_category)), collapse = "; ")` at line 207; `n_distinct(ENCOUNTERID)` at line 210 |
| 7 | tabyl(doi_category) clinical-plausibility count review logged before teardown | VERIFIED | `doi_encounters %>% janitor::tabyl(doi_category)` at line 230; printed to console; paraneoplastic count and HL-cohort summary also logged (lines 232–237) |
| 8 | close_pcornet_con() runs exactly once at end of script | VERIFIED | `close_pcornet_con()` at line 247; `grep -c` returns 1; appears after both saveRDS calls |

**Score:** 8/8 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/111_doi_classification.R` | DuckDB DIAGNOSIS pull, prefix pushdown, classify_doi_codes, mutual-exclusivity hard-stop, doi_encounters.rds writer | VERIFIED | 248 lines (exceeds 120-line minimum); all required sections present |
| `R/111_doi_classification.R` | Section 7 patient-grain rollup + tabyl review + doi_patients.rds writer + close_pcornet_con | VERIFIED | Section 7 appended (lines 197–248); all Plan 02 requirements present |
| `R/utils/utils_doi.R` | is_doi_code / classify_doi_codes | VERIFIED (pre-existing) | File exists; sourced defensively at line 70 |
| `R/utils/utils_cancer.R` | is_cancer_code for hard-stop | VERIFIED (pre-existing) | File exists; sourced defensively at line 71 |
| `R/utils/utils_duckdb.R` | open_pcornet_con, get_pcornet_table, close_pcornet_con | VERIFIED (pre-existing) | File exists; sourced at line 64 |
| `R/utils/utils_treatment.R` | get_hl_patient_ids | VERIFIED (pre-existing) | File exists; sourced defensively at line 69 |
| `R/utils/utils_dates.R` | parse_pcornet_date | VERIFIED (pre-existing) | File exists; sourced at line 65 |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| R/111_doi_classification.R | DuckDB DIAGNOSIS table | `get_pcornet_table("DIAGNOSIS")` with prefix filter before collect() | WIRED | Line 114: get_pcornet_table("DIAGNOSIS"); line 123: substr filter pushed to SQL; line 125: collect() |
| R/111_doi_classification.R | utils_doi.R / utils_cancer.R | is_doi_code / classify_doi_codes / is_cancer_code calls | WIRED | classify_doi_codes at line 137; is_doi_code at line 136 and 168; is_cancer_code at line 168 |
| R/111_doi_classification.R | doi_encounters.rds | saveRDS after hard-stop passes | WIRED | stopifnot at line 170; saveRDS(doi_encounters at line 185 — correct ordering confirmed |
| R/111_doi_classification.R Section 7 | doi_encounters (in-memory from Section 6) | group_by(ID) %>% summarise rollup | WIRED | doi_patients derived from doi_encounters at lines 203–213; no DIAGNOSIS re-query |
| R/111_doi_classification.R | doi_patients.rds | saveRDS to CONFIG$cache$outputs_dir | WIRED | `file.path(CONFIG$cache$outputs_dir, "doi_patients.rds")` at line 241; saveRDS(doi_patients at line 242 |

---

### Data-Flow Trace (Level 4)

Skipped per phase instructions: structural-only verification on Windows. No Rscript execution against real DuckDB DIAGNOSIS table. Real-data counts and .rds artifact production are the Phase 130 HiPerGator gate.

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — no Rscript execution against real DuckDB in Windows environment. The Phase 130 HiPerGator run is the behavioral gate.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| DOI-CLASS-02 | 128-01-PLAN.md | Encounter-level DoI flag + category artifact, guaranteed non-overlapping with cancer | SATISFIED | doi_encounters.rds select at line 182 includes doi_code + doi_category; hard-stop at line 170 guarantees no cancer overlap |
| DOI-CLASS-03 | 128-02-PLAN.md | Patient-level DoI summary derived from encounter grain | SATISFIED | group_by(ID) summarise at lines 203–213; comment "DIAGNOSIS is NOT re-queried" at line 200 |
| DOI-CLASS-04 | 128-01-PLAN.md | Mutual-exclusivity hard-stop runs before any output; DuckDB-native prefix filter (no full-table load) | SATISFIED | stopifnot(overlap_n == 0) at line 170–172 precedes both saveRDS calls; substr(DX,1,3) %in% doi_prefixes3 filter at line 123 before collect() at line 125 |
| DOI-CLASS-05 | 128-01-PLAN.md | L10.81 encounters carry paraneoplastic_flag; distinguishable from primary autoimmune pemphigus; still counted as DoI | SATISFIED | paraneoplastic_flag = str_remove(toupper(DX), "\\.") %in% c("L1081") at line 146; L10.81 kept in classify_doi_codes output (Pemphigus category); rows not excluded from doi_encounters |

All four requirement IDs (DOI-CLASS-02, DOI-CLASS-03, DOI-CLASS-04, DOI-CLASS-05) accounted for. REQUIREMENTS.md maps all four to Phase 128 and marks them complete.

No orphaned requirements found: DOI-CLASS-01 is marked Phase 127 (Complete) in REQUIREMENTS.md and does not appear in Phase 128 plans — correctly excluded.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| R/111_doi_classification.R | 158 | `print(tabyl(doi_enc, doi_category))` in Section 5 | Info | A Section 5 category distribution print appears before the formal Section 7 tabyl review. This is not a stub — it is an additional console diagnostic using the pre-hard-stop doi_enc frame. The Section 7 review (line 230) uses doi_encounters (the final artifact grain), which is the authoritative clinical-plausibility check. No impact on goal achievement. |

No TODO/FIXME/placeholder comments found. No empty implementations. No hardcoded empty data arrays that flow to rendering. No stubs.

The Section 5 tabyl at line 158 uses `tabyl(doi_enc, doi_category)` (two-argument form on the pre-select frame). The Section 7 tabyl at line 230 uses `doi_encounters %>% janitor::tabyl(doi_category)` (pipe form on the final artifact). Both are substantive; neither is a stub.

---

### Human Verification Required

#### 1. Real-Data HiPerGator Run (Phase 130 Gate)

**Test:** Run `Rscript R/111_doi_classification.R` on HiPerGator with the real DIAGNOSIS table loaded in DuckDB.
**Expected:** (a) overlap_n == 0 (no mutual-exclusivity violation); (b) doi_encounters.rds written with a non-zero row count; (c) doi_patients.rds written at one row per unique patient ID; (d) tabyl(doi_category) output shows RA as dominant category; NMO and pemphigus are rare.
**Why human:** Rscript cannot be executed against the real DuckDB DIAGNOSIS table in the Windows development environment. Structural correctness of the code has been verified; behavioral correctness against real data is the Phase 130 HiPerGator gate.

#### 2. Paraneoplastic Flag Clinical Validation

**Test:** After the HiPerGator run, inspect doi_encounters.rds: `filter(paraneoplastic_flag == TRUE)` and confirm all such rows have `doi_category == "Pemphigus"`.
**Expected:** Every L10.81 encounter row has paraneoplastic_flag = TRUE and doi_category = "Pemphigus" — no reclassification to a different category or exclusion from the artifact.
**Why human:** Requires real DIAGNOSIS data with actual L10.81 codes present in the extract. Code path is verified structurally but cannot be confirmed against real L10.81 occurrences without a live run.

---

### Gaps Summary

No gaps. All eight observable truths pass structural verification. All four requirement IDs are satisfied. All key links are wired. The only deferred items are the two human verification checks above, both of which are explicitly scoped to the Phase 130 HiPerGator gate per the phase instructions.

---

_Verified: 2026-07-15T22:30:00Z_
_Verifier: Claude (gsd-verifier)_
