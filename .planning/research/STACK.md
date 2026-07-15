# Stack Research

**Domain:** v3.3 — Rituximab/Methotrexate-Associated Diagnoses of Interest (non-malignant ICD matching + treatment-attribution)
**Researched:** 2026-07-15
**Confidence:** HIGH (direct codebase inspection + established ICD package ecosystem knowledge; all negative claims verified against package documentation)

---

## Verdict: No New Dependencies

The existing stack is fully sufficient for v3.3. The `classify_codes()` prefix-matching pattern in
`utils_cancer.R` already handles all ICD-9/ICD-10 detection requirements. The `get_chemo_hits()`
helper in `utils_treatment.R` already handles rituximab/MTX detection across PRESCRIBING, DISPENSING,
and MED_ADMIN. No new R packages are warranted.

---

## What v3.3 Needs and What Already Provides It

### Need 1: Match a curated non-malignant ICD code set against DIAGNOSIS/CONDITION tables

**Already built — mirror the classify_codes() pattern exactly.**

`classify_codes()` in `R/utils/utils_cancer.R` implements a 4-tier cascade:
1. `str_remove(code, "\\.")` — normalize dotted/undotted formats
2. `substr(code, 1, 4)` lookup in `CANCER_SITE_MAP` — 4-char specificity tier
3. `substr(code, 1, 3)` lookup in `CANCER_SITE_MAP` — 3-char fallback
4. Same cascade for `ICD9_CANCER_SITE_MAP`
5. Return `NA` for unclassified

The only change needed for v3.3: add two new named vectors (`RITDIS_CODE_MAP` for ICD-10,
`ICD9_RITDIS_CODE_MAP` for ICD-9) to `R/00_config.R`, and add `is_ritdis_code()` and
`classify_ritdis_code()` to `R/utils/utils_cancer.R` (or a new `R/utils/utils_ritdis.R`).
These functions are character-for-character copies of `is_cancer_code()` and `classify_codes()`
substituting the new map names.

**Code territories are completely non-overlapping.** Cancer codes occupy C00–D49 (ICD-10) and
140–209 (ICD-9) in `CANCER_SITE_MAP` / `ICD9_CANCER_SITE_MAP`. Ritdis codes use M, L, G, K, D69,
D59 (ICD-10) and 71x, 34x, 28x, 55x, 56x, 69x (ICD-9). None of these prefixes appear in the
existing cancer maps. Zero collision risk; no guard logic needed beyond the existing cascade.

### Need 2: Treatment-attribution linkage (rituximab/MTX admin + non-malignant diagnosis)

**Already built — `get_chemo_hits()` accepts any `chemo_rxnorm` vector.**

Rituximab CPT codes (J9310, J9311, J9312) are already in `TREATMENT_CODES$chemo_cpt_hcpcs` and
`DRUG_GROUPINGS` (as "Chemotherapy" for the cancer pipeline). Methotrexate RxNorm CUIs (6851,
105585, 105586, 105587, 311625, 311627, 1655956, 1655959, 1655960, 1946772, and others) are
already in `TREATMENT_CODES$chemo_rxnorm`.

For v3.3: add a new `RITDIS_DRUG_RXNORM` vector in `R/00_config.R` containing rituximab RxNorm
CUIs (ingredient CUI 121191 and its product-level children — curate statically from rxnav.nlm.nih.gov
once before implementation) plus references to the existing MTX CUIs. Call `get_chemo_hits()` with
this vector. The helper already dispatches across PRESCRIBING, DISPENSING, and MED_ADMIN with the
NDC crosswalk; no code changes to the helper are needed.

Temporal join (±30-day window): standard `dplyr::filter(abs(as.numeric(dx_date - drug_date)) <= 30)`.
This pattern already exists in R/28 episode classification.

### Need 3: ICD code gap-filling for the seed code set

This is a **curation task, not a code task.** The seed file documents all gaps. Resolution requires
consulting ICD-10-CM tabular index and clinical references (FDA drug labels, ACR/EULAR guidelines).
No R package can substitute for this; packages like `icd` or `touch` contain the same ICD hierarchy
data that is publicly available in the tabular index. The resolved codes are entered as static
constants in `RITDIS_CODE_MAP`.

---

## Recommended Stack (No Additions)

### Core Technologies — Unchanged

| Technology | Version | Purpose | Why Sufficient |
|------------|---------|---------|----------------|
| R | 4.4.2+ | Base language | HiPerGator standard |
| dplyr | 1.2.0+ | Predicate-style filtering, temporal joins, flag columns | Named predicate pattern already established; ritdis flagging is `filter()` + `mutate()` |
| data.table | 1.16.2+ | Keyed joins if DIAGNOSIS scan becomes a bottleneck | Already infrastructure (v3.0); use if DIAGNOSIS row count warrants it |
| stringr | 1.5.1+ | `str_remove()` dot normalization in `is_ritdis_code()` | Already used in `utils_cancer.R`; zero new usage |
| DuckDB (DBI/dbplyr) | current | Lazy queries against DIAGNOSIS/CONDITION | Existing backend; no change |
| openxlsx2 | current | Tableau-ready xlsx investigation output | Established R/100+ pattern |

### Supporting Libraries — Unchanged

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| glue | 1.8.0 | Attrition messages: `"Flagged {n} ritdis encounters"` | Already auto-sourced via 00_config.R |
| here | 1.0.2 | Output file paths | Same pattern as all prior investigation scripts |
| janitor | 2.2.1 | `tabyl()` for prevalence crosstabs | Already available |
| checkmate | current | `assert_character()`, `assert_data_frame()` in new functions | v2.0 quality standard; all new functions must validate inputs |

### Development Tools — Unchanged

| Tool | Purpose | Notes |
|------|---------|-------|
| styler | Auto-format | New utils_ritdis.R and config additions must pass styler before commit |
| lintr | Lint enforcement | .lintr already configured; new code inherits same rules |
| R/88 smoke test | Regression guard | New scripts registered in SCRIPT_INDEX + R/39; new Section 15p (or next available) |

---

## Packages Evaluated and Rejected

### `icd` package (CRAN v4.0.9)

**What it does:** `icd_comorbidities()`, `icd_charlson()`, ICD-9/ICD-10 hierarchy traversal,
parent/child code lookup, pre-built Charlson and Elixhauser comorbidity maps.

**Why not needed:**

1. **Wrong problem.** `icd` solves two problems: (a) comorbidity index scoring (Charlson,
   Elixhauser), and (b) hierarchy traversal ("give me all children of M05"). v3.3 needs neither.
   It needs `code %in% curated_set` — an `%in%` operation on normalized strings.

2. **Duplicates existing logic.** `classify_codes()` already implements the same prefix cascade
   `icd` uses internally for detection. Adding `icd` would re-implement the same mechanism at
   100MB overhead.

3. **Heavy installation burden.** `icd` depends on `icd.data` (~100 MB embedded data package)
   and requires C++/Fortran compilation. On HiPerGator, this means extended renv install time,
   potential system library issues, and a permanent dependency for functionality that three
   lines of base R (`str_remove`, `substr`, `%in%`) already provide.

4. **Wrong granularity.** The ritdis code set is clinician-curated at code-level specificity
   (e.g., "include M31.30 and M31.31 but not M31.0"). `icd` hierarchy traversal returns all
   descendants of a parent — which would pull in codes outside the intended clinical scope
   (e.g., "all M31 children" includes polyarteritis nodosa variants not treated by rituximab).

**Verdict: Do not add.** The `classify_codes()` pattern fully suffices.

### `comorbidity` package (CRAN v1.0.6)

**What it does:** Charlson and Elixhauser comorbidity scores from diagnosis code vectors.
17+ pre-built condition maps (Quan 2005, Elixhauser 1998 era mappings).

**Why not needed:** Comorbidity index scoring is not the objective. The objective is detecting
*specific FDA-approved rituximab/MTX indications*. These do not map to any Charlson or Elixhauser
index definition — they are a project-specific, clinician-curated list that must be expressed
as a custom code set, not a published comorbidity index.

**Verdict: Do not add.**

### `touch` package (CRAN v0.1.9)

**What it does:** `icd_map()`, `icd_describe()`, ICD-10-CM code lookup via embedded tables.
Lightweight runtime description lookup by code string.

**Why not needed:** Code descriptions for the ritdis output (e.g., "Rheumatoid arthritis,
unspecified") are static for a ~100-code curated set. Embed them directly as `names()` on
the `RITDIS_CODE_MAP` vector — the same pattern already used in `MEDICATION_LOOKUP`
(code → human_name named vector). No runtime lookup package needed.

**Verdict: Do not add.** Embed descriptions as vector names in config.

### Runtime RxNorm API for rituximab CUI discovery

**What it would do:** Live queries to `rxnav.nlm.nih.gov` REST API to enumerate all RxNorm
CUIs for rituximab (ingredient → clinical drugs → branded drugs → NDC products).

**Why not needed at runtime:** The rituximab RxNorm family is small and stable. Ingredient
CUI 121191 (rituximab) with its product-level children can be enumerated once manually via the
RxNav browser and pinned as static constants in a `RITDIS_DRUG_RXNORM` vector in `R/00_config.R`.
The existing `get_chemo_hits()` helper already works with a static vector. Adding a runtime
network dependency on HiPerGator (firewall policies, rate limits, latency) for a one-time
curation step is unjustifiable.

Note: If rituximab NDC codes appear in DISPENSING/MED_ADMIN, the existing NDC crosswalk
(`ndc_rxnorm_crosswalk.rds` built by R/108) already resolves them via the ingredient CUI.
No new infrastructure.

**Verdict: Do not add a runtime API dependency.** Curate CUIs statically; add to config.

---

## Integration Points

| Integration Point | Change Required | Pattern to Mirror |
|-------------------|-----------------|-------------------|
| `R/00_config.R` — new Section 4c | Add `RITDIS_CODE_MAP` (ICD-10, named character vector) and `ICD9_RITDIS_CODE_MAP` (ICD-9) | Mirrors `CANCER_SITE_MAP` (Section 5b) / `ICD9_CANCER_SITE_MAP` (Section 5b2) exactly |
| `R/00_config.R` — new Section 5f | Add `RITDIS_DRUG_RXNORM` (rituximab RxNorm CUIs + pointer to MTX CUIs) | Mirrors `DRUG_GROUPINGS` named vector; deliberately separate from `chemo_rxnorm` |
| `R/utils/utils_cancer.R` or new `R/utils/utils_ritdis.R` | Add `is_ritdis_code()` and `classify_ritdis_code()` | Copy `is_cancer_code()` / `classify_codes()` substituting `RITDIS_CODE_MAP` |
| New `R/1xx_ritdis_*.R` investigation script(s) | Query DIAGNOSIS/CONDITION for ritdis flags; join with drug hits via ±30-day window; output styled xlsx | Mirrors R/104, R/105, R/106 standalone investigation pattern with openxlsx2 |
| `R/39_script_index.R` | Register new script(s) in `SCRIPT_INDEX` | Existing pattern |
| `R/88_smoke_test.R` | Add new section (next available number after 15o) | Existing Section 15x pattern |

### What NOT to touch

- `is_cancer_code()` — no change; M/L/G/K prefixes are not in `CANCER_SITE_MAP`, so no ritdis code can trigger it accidentally.
- `classify_codes()` — no change; ritdis classifier is a new parallel function, not a modification.
- `DRUG_GROUPINGS` entries for J9310/J9311/J9312 — remain "Chemotherapy"; correct for the cancer pipeline. The ritdis drug lookup is additive and lives in a separate vector.
- `TREATMENT_CODES$chemo_rxnorm` — do not add rituximab RxNorm CUIs here. Rituximab is not chemotherapy in the HL-pipeline sense; adding it would inflate chemo detection counts and affect regimen detection logic. Use the new `RITDIS_DRUG_RXNORM` vector instead.
- `get_chemo_hits()` — call as-is with the `RITDIS_DRUG_RXNORM` vector argument; no code changes needed.

---

## ICD Code Coverage: Gaps to Fill Before Implementation

The seed file (`ritdis_seed_codes.md`) documents these gaps. Resolve by consulting ICD-10-CM
FY2026 tabular and clinical guidelines before writing the `RITDIS_CODE_MAP` constant.

### ICD-10 codes missing from seed file

| Condition | Gap | Recommended approach |
|-----------|-----|----------------------|
| Pemphigus vulgaris | L10.0 not listed (named in RTF) | Add L10.0 explicitly; confirm L10.x prefix catches all needed pemphigus variants |
| GPA / Wegener's | M31.3x named but not enumerated | Add M31.30, M31.31; use 4-char key "M313" in map |
| Microscopic Polyangiitis | Not mentioned | Add M31.7; standard ANCA-vasculitis rituximab pair with GPA |
| Myasthenia gravis | G70.0x named but not enumerated | Add G70.00, G70.01; use 4-char key "G700" |
| ITP | Entire hematologic section absent | Add D69.3 |
| AIHA | Entire hematologic section absent | Add D59.0, D59.1, D59.9 (use prefix "D59") |
| SLE | Entire connective tissue section absent | Add M32.10, M32.9 core + M32.1x subtypes (use prefix "M32") |
| Sjogren's | Entire connective tissue section absent | Add M35.00–M35.09 (use prefix "M350") |
| Psoriasis | MTX-specific; not in rituximab-centric RTF | Add L40.0–L40.4, L40.8, L40.9 (use prefix "L40") |
| Psoriatic arthritis | MTX-specific | Add L40.50–L40.59 (use 4-char key "L405") |
| Crohn's disease | MTX-specific | Add K50 prefix |
| Ulcerative colitis | MTX-specific | Add K51 prefix |

### ICD-9 codes needed (pre-Oct-2015 diagnoses in cohort)

MEDIUM confidence — verify against ICD-9-CM Vol 1 tabular before finalizing. The prefix
approach means these can be expressed as 3-char or 4-char keys:

| Condition | ICD-9 prefix | Notes |
|-----------|-------------|-------|
| RA | 714 | 714.0 = RA |
| NMO | 3410 | Exact code 341.0; use 4-char key |
| GPA / Wegener's | 4464 | 446.4 = Wegener's; use 4-char key |
| MPA | 44621 | 446.21; use 5-char exact match or 4-char 4462 |
| ITP | 28731 | 287.31; use 4-char "2873" |
| AIHA | 2830 | 283.0x; use prefix "283" (check against ICD-9 neoplasm map — no collision) |
| SLE | 7100 | 710.0x; use 4-char "7100" |
| Sjogren's | 7102 | 710.2x; use 4-char "7102" |
| Psoriasis | 696 | 696.0, 696.1 |
| Crohn's | 555 | 555.x |
| Ulcerative colitis | 556 | 556.x |
| Myasthenia gravis | 3580 | 358.00, 358.01; use 4-char "3580" |
| Dermatomyositis | 7103 | 710.3x; use 4-char "7103" |
| Pemphigus | 6944 | 694.4x; use 4-char "6944" |

### Rituximab RxNorm CUIs to curate for RITDIS_DRUG_RXNORM

One-time curation step; do not build at runtime. Start from ingredient CUI 121191 on
rxnav.nlm.nih.gov and enumerate product-level CUIs. The ingredient CUI alone covers
MEDADMIN_TYPE = "RX" rows where the code is the base ingredient. Product-level CUIs
cover branded/formulation-specific rows.

The existing MTX CUIs in `TREATMENT_CODES$chemo_rxnorm` can be referenced by name
(not duplicated) in `RITDIS_DRUG_RXNORM` to avoid drift:

```r
# In R/00_config.R Section 5f (do not duplicate — reference)
RITDIS_DRUG_RXNORM <- list(
  rituximab = c(
    "121191",   # rituximab (ingredient) — verify and expand from RxNav
    # ... product-level CUIs from RxNav lookup
  ),
  methotrexate = TREATMENT_CODES$chemo_rxnorm[
    TREATMENT_CODES$chemo_rxnorm %in% c(
      "6851", "105585", "105586", "105587", "311625", "311627",
      "1655956", "1655959", "1655960", "1946772", "1441411", "283510",
      "283511", "287734", "1921592", "1541215", "1544388", "1544390", "1544398"
    )
  ]
)
```

This pattern avoids duplicating the MTX list while keeping rituximab CUIs additive.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative Instead |
|-------------|-------------|----------------------------------|
| Extend `classify_codes()` pattern with new named vector | `icd` package hierarchy traversal | Only if you need "all descendants of M05" dynamically at runtime — not the case for a fixed curated set |
| Static `RITDIS_DRUG_RXNORM` vector in config | Runtime RxNav API queries | Only if the drug set is expected to evolve continuously without manual curation (unlikely for approved indications) |
| Parallel `is_ritdis_code()` / `classify_ritdis_code()` functions | Modify `is_cancer_code()` to accept ritdis codes | Never — would contaminate cancer detection with non-cancer codes and break existing output parity |
| New `R/utils/utils_ritdis.R` | Add ritdis functions to `utils_cancer.R` | Either is acceptable; separate file is cleaner if ritdis logic grows beyond 2-3 functions |
| Embed descriptions as `names()` in map vector | `touch` package runtime lookup | Only if codes evolve dynamically at runtime (they do not — this is a static curated set) |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `icd` / `icd.data` packages | 100 MB data dependency + C++ compilation overhead for what is a `%in%` operation on a static named vector; hierarchy traversal pulls in codes outside clinical scope | `RITDIS_CODE_MAP` named vector + `substr()` prefix matching (identical to `CANCER_SITE_MAP` pattern) |
| `comorbidity` package | Charlson/Elixhauser scoring — wrong problem; ritdis is not a comorbidity index | Custom `RITDIS_CODE_MAP` with project-specific category names |
| `touch` package | Runtime ICD description lookup for a static 100-code set | Embed descriptions as `names()` on the map vector in config |
| Adding rituximab to `TREATMENT_CODES$chemo_rxnorm` | Inflates chemo detection; affects ABVD/BV+AVD regimen identification logic; breaks output parity with pre-v3.3 runs | New `RITDIS_DRUG_RXNORM` vector, separate from chemo detection |
| Modifying `DRUG_GROUPINGS` J9310/J9311/J9312 entries from "Chemotherapy" | Breaks existing Gantt, drug grouping, and episode outputs that rely on these being "Chemotherapy" | Leave unchanged; ritdis drug linkage uses a parallel lookup |
| Runtime NLM RxNav API calls in investigation scripts | Network dependency on HiPerGator; rate limits; adds failure mode for a one-time curation step | Static CUI list curated once offline, pinned in config |

---

## Installation

No new packages. Existing `renv.lock` is unchanged for v3.3.

```r
# Verify environment is intact before starting v3.3 work:
renv::status()
# Expected: "No issues found"
```

---

## Sources

- Direct codebase inspection (2026-07-15):
  - `R/00_config.R`: `CANCER_SITE_MAP`, `ICD9_CANCER_SITE_MAP`, `DRUG_GROUPINGS`,
    `TREATMENT_CODES$chemo_rxnorm` (MTX CUIs confirmed: 6851, 105585-105587, 311625, 311627, etc.),
    `AMC_PAYER_LOOKUP` pattern; J9310/J9311/J9312 confirmed as "Chemotherapy" in `DRUG_GROUPINGS`
    and `chemo_cpt_hcpcs`
  - `R/utils/utils_cancer.R`: `is_cancer_code()`, `classify_codes()` 4-tier cascade logic
  - `R/utils/utils_treatment.R`: `get_chemo_hits()` signature — accepts any `chemo_rxnorm` vector;
    `normalize_ndc()`, `load_ndc_crosswalk()` already operational
  - `R/utils/utils_icd.R`: `normalize_icd()`, `is_hl_diagnosis()` — confirms dot-normalization pattern
  - `.planning/research/ritdis_seed_codes.md`: Gap analysis source
- CRAN `icd` package page (v4.0.9): https://cran.r-project.org/package=icd — C++/Fortran compilation confirmed; `icd.data` dependency confirmed at ~100 MB
- CRAN `comorbidity` package page (v1.0.6): https://cran.r-project.org/package=comorbidity — Charlson/Elixhauser maps confirmed
- CRAN `touch` package page (v0.1.9): https://cran.r-project.org/package=touch — runtime ICD description lookup confirmed
- NLM RxNav (rxnav.nlm.nih.gov): rituximab ingredient CUI 121191 — MEDIUM confidence (verify before pinning product CUIs)
- ICD-10-CM FY2026 tabular: M/L/G/K/D prefix structure (code enumeration for gaps is LOW confidence until verified against official tabular before implementation)

---

*Stack research for: v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest*
*Researched: 2026-07-15*
*Prior STACK.md (v3.0 data.table research, 2026-06-10) superseded by this file for v3.3 planning.*
