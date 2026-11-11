# New phases — insurance_investigation (v3.13)

STATE.md says Phase 192.1 is the last completed phase and the next one is Phase 191. I've drafted both new phases as decimal inserts after 192.1, so v3.13 keeps its numbering. Paste each block into `/gsd:insert-phase 192.1 "<description>"`, or add them to ROADMAP.md by hand.

---

## Phase 192.2 — ICD-9 autoimmune codes in Gantt episodes

**Goal:** Add the ICD-9 equivalents from `Autoimmune Diagnosis codes based on Rituximab and MTX.xlsx` to the Phase 192.1 autoimmune flag. A patient whose only qualifying diagnosis is an ICD-9 code will then get `has_autoimmune_dx = TRUE` and a `first_autoimmune_dx_date` in `gantt_episodes.csv` and `gantt_episodes_180.csv`.

**Why:** Phase 192.1 shipped with ICD-10 only (the `AUTOIMMUNE_DX_CODES$icd9` slot is empty, and `test_autoimmune_flags.R` asserts that). The team workbook now gives ICD-9 codes for every diagnosis.

**Codes (from the workbook):**

| Drug | Dx | ICD-10 (already in) | ICD-9 (add) | Config key(s) |
|---|---|---|---|---|
| Rituximab / MTX | Rheumatoid arthritis | M05, M06 | 714.0, 714.1, 714.2, 714.8x, 714.9 | `7140`, `7141`, `7142`, `7148` (prefix), `7149` |
| Rituximab | GPA | M31.3 | 446.4 | `4464` |
| Rituximab | MPA | M31.7 | 446.0 | `4460` |
| Rituximab | Pemphigus vulgaris | L10.0 | 694.4 | `6944` |
| MTX | pJIA | M08.3, M08.09, M08.00 | 714.30, 714.32 | `71430`, `71432` |
| MTX | Psoriasis | L40 | 696.1 | `6961` |

**Scope:**
1. `R/00_config.R`: fill `AUTOIMMUNE_DX_CODES$icd9` with the keys above, using the same dot-stripped prefix matching as `icd10`, so `7148` catches 714.81 and 714.89.
2. `is_autoimmune_code()` / `summarise_autoimmune_dx()` in `utils_doi.R`: no logic change expected, because the `'09'` DX_TYPE accept path already exists. Confirm that `AUTOIMMUNE_DX_TYPE_ACCEPT$icd9` covers the extract's DX_TYPE values.
3. Add `autoimmune_dx_code_system` (`"10"`, `"09"`, `"both"`, NA) next to the existing two columns, so the team can see how many flags come from ICD-9 alone.
4. Re-run the Gantt column injection for `gantt_episodes.csv` and `gantt_episodes_180.csv`. Detail CSVs stay excluded, as in 192.1.
5. Tests: change the two "icd9 slot is empty" / "714.0 → FALSE with real constant" tests in `tests/testthat/test_autoimmune_flags.R` to expect TRUE. Add cases for 714.81 (prefix hit), 714.32, 696.1, and 696.2 (still FALSE).
6. R/88 Section 15ba: update the expected counts and add a check that ICD-9-only patients have a date before the ICD-10 transition (≤ 2015-10-01) or a logged reason.
7. QC printout: patients flagged before vs. after, split into ICD-10 only, ICD-9 only, and both.

**Decisions to confirm:**
- **D-192.2-01:** 714.32 is in the team workbook, but 192.1 excluded 71432 per GEM. The plan follows the workbook (include). 71433 stays out.
- **D-192.2-02:** Is 446.0 (polyarteritis nodosa) acceptable as the ICD-9 proxy for MPA? There is no specific ICD-9 code for MPA, so this pulls in broader cases. Default: include it, as the workbook lists.
- **D-192.2-03:** Should "714.8x" cover all of 714.8 (714.81 rheumatoid lung and 714.89 other)? Default: yes.

**Exit criterion:** Regenerated Gantt CSVs on HiPerGator (R/4.5 interactive), R/88 15ba passing, and the before/after counts recorded in the SUMMARY.

---

## Phase 192.3 — Distance >100 mi vs CBC, split by SOURCE (Medicare reassigned to address source)

**Goal:** Re-run the far-from-care (>100 mi) × CBC association (Phase 165 `R/165_distance_cbc_association.R` / `utils_distance_cbc.R`, plus the Phase 181 year-1 version if wanted) stratified by data SOURCE. Encounters whose SOURCE is Medicare get the SOURCE of the patient's address record instead.

**Why:** The study hypothesis is that long-distance patients get CBCs outside our system. A Medicare claims source is not a health system, so it says nothing about where care was captured. The address record's source does.

**Scope:**
1. **Source reassignment helper** (new, e.g. `assign_analytic_source()` in `utils_distance_cbc.R`):
   - Keep `SOURCE_raw` and add `SOURCE_analytic` and `source_reassigned` (0/1).
   - If `SOURCE_raw` is in `CONFIG$medicare_source_codes`, set `SOURCE_analytic` to the SOURCE of the LDS_ADDRESS_HISTORY row in effect at `ADMIT_DATE`, falling back to the most recent row before that date (same backward rule as `get_zip9_at_date()`).
   - If there is no address row, or the address source is also Medicare, set `SOURCE_analytic = "Medicare_unresolved"`. These rows are kept and reported, not dropped.
2. **Plumb SOURCE through:** `build_enc_analysis()` already carries `SOURCE`. Apply the helper right after Step 2 (the ENCOUNTER join), before the far/CBC flags.
3. **Stratified outputs** (new sheets in the distance-CBC workbook; KEY stays the leftmost tab):
   - `BY_SOURCE_enc`: per `SOURCE_analytic`, a 2×2 of far × CBC, row %, chi-square (Fisher when expected <5), Woolf OR via `naive_or_se()`.
   - `BY_SOURCE_pat`: same at patient level, for the whole and post windows.
   - `SOURCE_REASSIGN_QC`: raw → analytic crosswalk counts, number reassigned, number unresolved.
   - Mantel–Haenszel pooled OR across sources plus a Breslow–Day homogeneity test, as a summary line.
   - Suppress cells 1–10 with `suppress_display()` ("<11").
4. Tests: helper fixtures (non-Medicare unchanged; Medicare → address source; Medicare with no address → unresolved; address change mid-period picks the in-effect row). Add an R/88 section for the new sheets.

**Decisions to confirm:**
- **D-192.3-01:** The exact Medicare SOURCE value(s) in ENCOUNTER. Plan step 0 is a SOURCE frequency table, and the codes go into `CONFIG$medicare_source_codes`, not the code.
- **D-192.3-02:** Does LDS_ADDRESS_HISTORY carry a SOURCE column? If not, fall back to the DEMOGRAPHIC source or the patient's modal non-Medicare encounter source. Verify in step 0.
- **D-192.3-03:** Patient-level source when a patient has several sources. Default: the modal `SOURCE_analytic` across window encounters, ties broken by most recent. The alternative is the v3.7 single-health-system flag.
- **D-192.3-04:** Run this on R/165 (whole record and post-anchor), on R/181 (year-1 CBC), or both. Default: R/165 first.

**Exit criterion:** A re-issued distance-CBC workbook with the BY_SOURCE sheets from a real HiPerGator run, with reassignment counts in the SUMMARY.
