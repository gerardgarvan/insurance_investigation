---
phase: 199
name: immune-and-brentuximab-flags-in-gantt-180
status: planned
milestone: cross-milestone
depends_on: [Phase 192.2 complete (23-column gantt_episodes_180.csv)]
tags: [gantt, r142, immune-flag, rituximab, methotrexate, brentuximab, patient-level]
created: 2026-11-12
---

# Phase 199: Immune and Brentuximab Flags in gantt_episodes_180 - Context

**Gathered:** 2026-11-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Add two **patient-level** logical columns to `output/gantt_episodes_180.csv` (R/142):

| # | Column | Type | Definition |
|---|--------|------|------------|
| 24 | `immune_flag` | logical | TRUE if Case 1 **or** Case 2 holds for the patient; FALSE otherwise |
| 25 | `ever_brentuximab` | logical | TRUE if the patient ever had Brentuximab in any Gantt episode; FALSE otherwise |
| 26 | `immune_flag_dx` | character | When `immune_flag` is TRUE: the plain-language name(s) of the patient's qualifying IMMUNE_FLAG diagnoses, unique and sorted, separated by `;` (D-12). Blank when `immune_flag` is FALSE |

- **Case 1:** the patient has `drug_name == "Rituximab"` in any episode **and** at least one qualifying diagnosis from the IMMUNE_FLAG code list (D-01).
- **Case 2:** the patient has `drug_name == "Methotrexate"` in any episode **and** at least one qualifying diagnosis from the same IMMUNE_FLAG code list.

Both columns are joined to every row for the patient, including the Death and HL Diagnosis pseudo-rows. This matches how `has_autoimmune_dx` is joined.

Column count for `gantt_episodes_180.csv` goes from 23 to 26.

**Out of scope (unless the team asks):**
- `gantt_episodes.csv` (90-day, R/52), `gantt_detail_180.csv`, and the R/170 NHL-subset outputs.
- Any change to the existing 23 columns, their order, or their values.
- Any change to `AUTOIMMUNE_DX_CODES` or `has_autoimmune_dx` (that flag keeps its broader code list).
</domain>

<decisions>
## Implementation Decisions

### IMMUNE_FLAG diagnosis code list (D-01)

- **D-01:** New constant `IMMUNE_FLAG_DX_CODES` in `R/00_config.R`, Section 4c, placed next to `AUTOIMMUNE_DX_CODES`. It uses the same named-list structure (`$icd10`, `$icd9`), the same prefix matching, and the same dot stripping. Do not reuse `AUTOIMMUNE_DX_CODES`. That list is broader (it also has M08.x, L40, 714.30, 714.32, 696.0, and 696.1) and would over-flag patients.

  The **Plain-language label** column is the config value for each key. It is the text written to `immune_flag_dx` (D-12).

  | System | Key | Source code | Plain-language label |
  |--------|-----|-------------|----------------------|
  | ICD-10 | `M05` | M05 (all) | Rheumatoid Arthritis |
  | ICD-10 | `M06` | M06 (all) | Rheumatoid Arthritis |
  | ICD-10 | `M313` | M31.3 | GPA |
  | ICD-10 | `M317` | M31.7 | MPA |
  | ICD-10 | `L100` | L10.0 | Pemphigus Vulgaris |
  | ICD-9 | `7140` | 714.0 | Rheumatoid Arthritis |
  | ICD-9 | `7141` | 714.1 | Rheumatoid Arthritis |
  | ICD-9 | `7142` | 714.2 | Rheumatoid Arthritis |
  | ICD-9 | `7148` | 714.8x | Rheumatoid Arthritis (prefix covers 714.81/714.89) |
  | ICD-9 | `7149` | 714.9 | Rheumatoid Arthritis |
  | ICD-9 | `4464` | 446.4 | GPA |
  | ICD-9 | `4460` | 446.0 | MPA (446.0 broader than M31.7) |
  | ICD-9 | `6944` | 694.4 | Pemphigus Vulgaris (694.4 broader than L10.0) |

  ICD-9 and ICD-10 codes for the same condition share one label. A patient with both M06 and 714.0 therefore shows "Rheumatoid Arthritis" once.

  **D-199-04 RESOLVED 2026-11-12:** the labels are the team's plain-language terms (Rheumatoid Arthritis, GPA, MPA, Pemphigus Vulgaris). ICD-9 codes take their ICD-10 counterpart's label per the 192.2 crosswalk. The team terms pJIA and Psoriasis have no codes in IMMUNE_FLAG_DX_CODES and are unused here.

  The keys are exactly the list the user supplied (2026-11-12). Nothing is added or removed. DX_TYPE gating reuses `AUTOIMMUNE_DX_TYPE_ACCEPT` ("09" / "10").

### Drug match (D-02)

- **D-02:** The drug test runs on the canonicalized `drug_names` field of `episodes_export`, after the R/142 Section 4D cleanup (semicolon-split, `canonicalize_drug_name()` applied). A patient "has Rituximab" if any token in any of their episodes equals the canonical Rituximab label exactly. The same rule applies to Methotrexate. Exact match on the canonical label means name variants (for example "Rituximab-abbs") count only if `canonicalize_drug_name()` already collapses them.
- **D-02a (2026-11-12, post-implementation review):** Exact matching was replaced by **case-insensitive prefix matching per drug family** (`^rituximab`, `^methotrexate`, `^brentuximab`). The drug_names sources (MEDICATION_LOOKUP title-case names, R/27 RxNorm names) can produce variants such as "Methotrexate Sodium", "Rituximab (Truxima)", "Rituximab/Hyaluronidase" or lowercase forms, and DRUG_NAME_ALIASES has no entries for these drugs. Matching runs on a copy passed to build_immune_flags(), so the CSV `drug_names` column is unchanged. The D-03 printout shows which family each raw token is counted under.
- **D-02b (2026-11-12, user: flags must reflect each patient's ENTIRE history):** drug exposure is the **UNION** of (1) Gantt episode `drug_names` (family-matched, D-02a) and (2) `get_drug_exposure_ids()` in `R/utils/utils_doi.R`. That function searches PROCEDURES (HCPCS), PRESCRIBING (RxNorm + medication name), MED_ADMIN (code + medication name) and DISPENSING (medication name) over **all dates** for the cohort, using `IMMUNE_DRUG_DEFS` in config. The defs add codes missing from the treatment code lists: rituximab biosimilar HCPCS Q5115/Q5119/Q5123, RITUXIMAB_CODES$rxnorm, oral MTX J8610, plus brand names. Evidence: `R/tools/check_199_full_history.R` (2026-11-12) found the episodes alone missed 409 rituximab, 26 methotrexate and 365 brentuximab patients. The raw search in turn missed 24 MTX patients that the episodes had (likely NDC-only), which is why both are combined. `build_immune_flags(raw_history = TRUE)` is the default; `FALSE` reproduces episode-only. Diagnoses were already full-history (all DIAGNOSIS rows; only the 1910 sentinel applies).
  - *Open for team (D-199-05):* should a PRESCRIBING order alone (no administration or dispensing record) count as exposure? Default: yes, the same as the treatment pipeline.
  - *Separate finding (not fixed here):* the Gantt treatment episodes themselves miss many MED_ADMIN rituximab and brentuximab records. Logged for a separate phase.
- **D-03:** The executor must confirm the canonical labels before hard-coding them. Print the distinct canonical tokens that match `regex("rituximab|methotrexate|brentuximab", ignore_case = TRUE)` across `episodes_export$drug_names`. Then store the confirmed labels in config as `IMMUNE_FLAG_DRUGS <- c("Rituximab", "Methotrexate")` and `BRENTUXIMAB_DRUG <- "<confirmed label>"`. The label is expected to be "Brentuximab" or "Brentuximab Vedotin". If more than one raw variant is found that canonicalization does not merge, stop and record it as D-199-01 rather than guessing.

### Timing (D-04)

- **D-04 (RESOLVED 2026-11-12, user):** The diagnosis is "ever". There is no ordering or window between the drug and the diagnosis, and both are patient-level "ever" conditions. D-199-02 is closed.

### Valid-date rule (D-05)

- **D-05:** A qualifying diagnosis must have a valid date under the same rule as `has_autoimmune_dx` (`sentinel = SENTINEL_CUTOFF`). This keeps the two flags comparable. QC prints how many drug-exposed patients have a qualifying code with **no** valid date. Those patients are `immune_flag = FALSE` under this rule. *Open for team (D-199-03):* should undated qualifying records count? Default: no.

### Helper (D-06)

- **D-06:** Reuse the Phase 192.1/192.2 infrastructure in `R/utils/utils_doi.R`. If `build_autoimmune_dx_flags()` / `summarise_autoimmune_dx()` do not already take a `codes =` argument, add one that defaults to `AUTOIMMUNE_DX_CODES`, so existing callers (R/52, R/142, R/170) are unaffected. Then add a thin wrapper `build_immune_flags(episodes_export, codes = IMMUNE_FLAG_DX_CODES, drugs = IMMUNE_FLAG_DRUGS, brentuximab = BRENTUXIMAB_DRUG, sentinel = SENTINEL_CUTOFF)`. It returns one row per patient with `patient_id`, `immune_flag`, `ever_brentuximab`, `immune_flag_dx`, and the QC-only columns `has_rituximab`, `has_methotrexate`, `has_immune_flag_dx`, and `qc_immune_dx_no_valid_date`. Only `immune_flag`, `ever_brentuximab`, and `immune_flag_dx` go into the CSV. `immune_flag_dx` needs the matched code **records**, not just the patient-level flag. Get them by adding `return_records = TRUE` to `build_autoimmune_dx_flags()` (default FALSE, so existing callers are unchanged), or by running the same DuckDB DIAGNOSIS query separately. Either way, use the same DX_TYPE gate and valid-date rule as the flag.

### Output and type (D-07)

- **D-07:** `immune_flag` and `ever_brentuximab` are written as logical values (`TRUE`/`FALSE`, never NA), placed after `autoimmune_dx_code_system`. `immune_flag_dx` (character) follows as column 26, written as `""` when `immune_flag` is FALSE. Patients missing from the helper output (none are expected) get FALSE after the join, with a `stopifnot` showing that the join kept the row count. `DETAIL_SCHEMA` and `detail_export` are not touched.

### Regression (D-08)

- **D-08:** Before R/142 runs, copy the current 23-column `gantt_episodes_180.csv` to `output/internal/gantt_episodes_180_PRE199.csv`. Use `stop()` if the copy already exists. After the run, all 23 original columns must match the baseline exactly (row count, column order, and multiset of rows). The only change allowed is the three new trailing columns.

### QC console output (D-09)

- **D-09:** Print patient-level counts, with values from 1 to 10 shown as `"<11"` through the existing `fmt_sup`:
  - patients with Rituximab; with Methotrexate; with both
  - patients with a qualifying IMMUNE_FLAG diagnosis
  - `immune_flag = TRUE`, split into Case 1 only, Case 2 only, and both cases
  - drug-exposed patients with a qualifying code but no valid date (D-05)
  - `ever_brentuximab = TRUE`
  - among `immune_flag = TRUE` patients: count per plain-language label, and the number of patients with more than one label
  - cross-tab of `immune_flag` by `has_autoimmune_dx` (sanity check: `immune_flag` TRUE should be a subset of `has_autoimmune_dx` TRUE except for codes in the IMMUNE list but not in the AUTOIMMUNE list, which should be none; report any)

### R/88 smoke test (D-10)

- **D-10:** Two parts:
  - **Fix the 15bb checks that will break:** 15bb (c) asserts exactly 23 columns in *both* Gantt CSVs, and (d) asserts that `autoimmune_dx_code_system` is the last column. For `gantt_episodes_180.csv`, change these checks to 26 columns with `autoimmune_dx_code_system` at position 23. Leave the 90-day CSV checks unchanged.
  - **Add a new section:** use the next free `15b*` id after the last one in R/88 (grep first, because Phases 192.3–197 may have used 15bc+). It covers:
    - (a) config keys exactly equal the D-01 table (13 keys)
    - (b) `is_autoimmune_code("M0579", "10", codes = IMMUNE_FLAG_DX_CODES)` returns TRUE, `("M083", "10", ...)` returns FALSE, `("7140", "09", ...)` returns TRUE, and `("6961", "09", ...)` returns FALSE
    - (c) the 180 CSV has 26 columns, with `immune_flag` at 24, `ever_brentuximab` at 25, and `immune_flag_dx` at 26
    - (d) the two flag columns parse as logical with no NA
    - (e) all three new columns are constant within `patient_id`
    - (f) every `immune_flag == TRUE` patient also has `has_autoimmune_dx == TRUE` (IMMUNE_FLAG_DX_CODES is a subset of AUTOIMMUNE_DX_CODES). The old token check was dropped in D-02b: exposure can come from raw history and not show in `drug_names`.
    - (g) every patient with a `^brentuximab` token in `drug_names` has `ever_brentuximab == TRUE`. One direction only since D-02b.
    - (h) `immune_flag_dx` is non-blank exactly when `immune_flag == TRUE`
    - (i) every `;`-split token of `immune_flag_dx` is one of `unique(unlist(IMMUNE_FLAG_DX_CODES))`, and the tokens within a cell are unique and sorted

  Checks (d)–(i) are gated by `!IS_LOCAL`.

### Run order (D-11)

- **D-11:** HiPerGator interactive session (`module load R/4.5`):
  1. `source("R/142_gantt_180_export.R", local = new.env(parent = globalenv()))`
  2. `source("R/88_smoke_test_comprehensive.R", local = new.env(parent = globalenv()))`

  R/52 and R/170 do not need to run. *Note:* Phase 198 (obsolete-NDC fallback) may add new methotrexate rows. If 198 lands after this phase, re-run R/142 so `immune_flag` picks them up.

### Plain-language diagnosis column (D-12, added 2026-11-12 per user)

- **D-12:** `immune_flag_dx` is built for patients with `immune_flag == TRUE` only:
  1. Take every qualifying, validly-dated IMMUNE_FLAG record for the patient. Any date counts ("ever"), and the records are not tied to a particular drug exposure.
  2. Match each record to its config key. If more than one key matches, use the longest prefix.
  3. Map each key to its plain-language label (the config value).
  4. Remove duplicates, sort alphabetically, and join with `"; "`.

  Example: `"Pemphigus Vulgaris; Rheumatoid Arthritis"`. Patients with `immune_flag == FALSE` get `""`, even if they have a qualifying diagnosis but no Rituximab/Methotrexate exposure. The labels live in config and can be edited. D-199-04 resolved 2026-11-12 (team terms; see D-01).

### Claude's Discretion
- Whether `build_immune_flags()` lives in `utils_doi.R` (preferred, next to the autoimmune helpers) or in a new `utils_immune.R`.
- Exact wording of the QC console lines.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `R/142_gantt_180_export.R`:
  - Section 4C2 (autoimmune flags, `build_autoimmune_dx_flags()` call, `aim` join, `stopifnot` on row count)
  - Section 4D (drug_names canonicalization + final column-trim `select()`)
  - `EPISODES_SCHEMA` (23 entries)
  - Header "Outputs" line (still says "20 columns"; correct it to 26)
- `R/utils/utils_doi.R`: `is_autoimmune_code()`, `summarise_autoimmune_dx()`, `build_autoimmune_dx_flags()`
- `R/00_config.R` Section 4c: `AUTOIMMUNE_DX_CODES`, `AUTOIMMUNE_DX_TYPE_ACCEPT`, `SENTINEL_CUTOFF`
- `R/88_smoke_test_comprehensive.R`: SECTION 15ba, 15bb, and any later 15b* sections
- `.planning/phases/192.1-autoimmune-diagnosis-flags-in-gantt-episodes/192.1-CONTEXT.md`
- `.planning/phases/192.2-icd-9-autoimmune-codes-in-gantt-episodes/192.2-CONTEXT.md`
- `.planning/phases/198-*/198-CONTEXT.md` (methotrexate NDC scope interaction, D-11)
- Readers of `gantt_episodes_180.csv`: run `grep -rn "gantt_episodes_180" R/` and check the dep_map `reads` edges for strict column-count or `identical(names(...))` checks that three extra trailing columns would break
</canonical_refs>

<code_context>
## Existing Code Insights

- Section 4C2 in R/142 already shows the pattern: build a patient-level table, `left_join` on `patient_id`, `stopifnot` on row count, then QC with `fmt_sup`. The new Section 4C3 copies this.
- **Ordering constraint:** `drug_names` is canonicalized only in Section 4D, which runs *after* 4C2. Either compute the immune flags inside 4D after the `drug_names` mutate and before the column-trim `select()`, or canonicalize a local copy in 4C3. Preferred: a new block at the end of the 4D cleanup, just before the column-trim `select()`.
- `write.csv(..., na = "")` writes logical values as `TRUE`/`FALSE`, which matches `has_autoimmune_dx`.
- R/142 is standalone and not registered in R/39 (deliberate). No R/39 change is needed.
</code_context>

<deferred>
## Deferred Ideas
- Propagating `immune_flag` / `ever_brentuximab` to `gantt_episodes.csv` (R/52) and the R/170 subsets
- First-date columns (`first_brentuximab_date`, `first_immune_flag_dx_date`)
- Analytic Manual entry for the two new variables
</deferred>

---

*Phase: 199-immune-and-brentuximab-flags-in-gantt-180*
*Context gathered: 2026-11-12*
