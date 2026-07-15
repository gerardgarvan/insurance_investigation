# Architecture Patterns: v3.3 Diagnosis-of-Interest Integration

**Domain:** PCORnet HL-cohort R pipeline — v3.3 "Rituximab/Methotrexate-Associated Diagnoses of Interest"
**Researched:** 2026-07-15
**Scope:** Integration architecture ONLY. How the new diagnosis-of-interest (DoI) class fits into the existing pipeline. Not a redesign.

---

## 1. Where the Code Map Lives and How It Is Structured

### Decision: New named section in `R/00_config.R` — Section 4c

The code-map pattern is explicit throughout the codebase. Every classification layer has its constant in `R/00_config.R` and is referenced from the utility function:

- `CANCER_SITE_MAP` / `ICD9_CANCER_SITE_MAP` (Section 5b/5b2) — cancer prefix-to-category maps
- `AMC_PAYER_LOOKUP` (Section 5) — payer code-to-category lookup
- `DRUG_GROUPINGS` (Section 6) — code-to-treatment-type lookup
- `DEATH_CAUSE_MAP` (Section 5d) — ICD-10 prefix-to-cause lookup

The new constant follows this exact pattern. Place it immediately after the ICD HL code lists (Section 4b, ICD9_NLPHL_CODES) and before the payer mapping (Section 5), as new **Section 4c**.

### Structure

```r
# ==============================================================================
# SECTION 4c: RITUXIMAB/METHOTREXATE NON-MALIGNANT DIAGNOSIS-OF-INTEREST MAP ----
# ==============================================================================
# Maps ICD-10 and ICD-9 code prefixes to non-malignant diagnosis-of-interest
# categories for rituximab and methotrexate treatment attribution analysis.
#
# WHY prefix-based: Mirrors CANCER_SITE_MAP and ICD9_CANCER_SITE_MAP pattern.
#   Prefix length 3 for broad categories (M05, M06, L10), 4 for subcategory
#   discrimination where needed (e.g., D692 vs D693).
#
# WHY non-overlapping: These codes occupy ICD-10 M/L/D/G/I/K chapter space,
#   not C/D-neoplasm space. is_cancer_code() uses C/D prefix maps only.
#   No overlap is possible by ICD-10 chapter structure.
#   ICD-9 overlap risk: ICD-9 201.x is cancer; ICD-9 M-space (710-739) is
#   musculoskeletal -- separate numeric ranges. Verified safe.
#
# WHY separate from CANCER_SITE_MAP: Different chapter space, different
#   clinical purpose (comorbidity / attribution vs cancer site).
#   classify_codes() must never receive these codes -- it would return NA
#   for all of them, and its consumers assume cancer-site output.
#
# Scope: Non-malignant indications ONLY. NHL/HL/cancer codes stay in
#   CANCER_SITE_MAP. A code appearing in both would indicate a data
#   coding anomaly, not a design choice.
#
# Sources: FDA-approved and widely-used off-label indications for
#   rituximab and methotrexate. See .planning/research/ritdis_seed_codes.md.
# ==============================================================================

DOI_CODE_MAP <- c(
  # --- RHEUMATOID ARTHRITIS ---
  "M05" = "Rheumatoid Arthritis",    # RA with rheumatoid factor (all site variants)
  "M06" = "Rheumatoid Arthritis",    # RA without rheumatoid factor / other RA
  "714" = "Rheumatoid Arthritis",    # ICD-9: Rheumatoid arthritis

  # --- VASCULITIS ---
  "M30" = "Vasculitis",              # Polyarteritis nodosa and related conditions
  "M31" = "Vasculitis",              # Necrotizing vasculopathies (GPA M31.3x, MPA M31.7)
  "I77" = "Vasculitis",              # ANCA-positive vasculitis (I77.82)
  "L95" = "Vasculitis",              # Skin-limited vasculitis
  "D692" = "Vasculitis",             # IgA vasculitis (4-char to disambiguate from D693)
  "446" = "Vasculitis",              # ICD-9: Polyarteritis nodosa and allied conditions

  # --- DERMATOLOGIC ---
  "L10" = "Pemphigus",               # Pemphigus (vulgaris L10.0, vegetans L10.1, etc.)
  "L12" = "Pemphigoid",              # Bullous pemphigoid (L12.0) and variants
  "694" = "Pemphigus",               # ICD-9: Pemphigus

  # --- INFLAMMATORY MYOPATHY ---
  "M33" = "Inflammatory Myopathy",   # Dermatomyositis / polymyositis (all variants)
  "710" = "Inflammatory Myopathy",   # ICD-9: Diffuse diseases of connective tissue (DM/PM/SLE)

  # --- NEUROLOGICAL (off-label) ---
  "G36" = "Neurological Autoimmune", # Neuromyelitis optica (G36.0 Devic)
  "G37" = "Neurological Autoimmune", # Acute transverse myelitis (G37.3)
  "G70" = "Neurological Autoimmune", # Myasthenia gravis (G70.00, G70.01)
  "H46" = "Neurological Autoimmune", # Optic neuritis / retrobulbar neuritis
  "341" = "Neurological Autoimmune", # ICD-9: NMO and demyelinating (341.0)
  "358" = "Neurological Autoimmune", # ICD-9: Myasthenia gravis (358.0x)

  # --- HEMATOLOGIC (benign immune-mediated) ---
  "D693" = "Hematologic Autoimmune", # ITP -- 4-char to disambiguate from D692 vasculitis
  "D59"  = "Hematologic Autoimmune", # Autoimmune hemolytic anemia (D59.0-D59.1)
  "287"  = "Hematologic Autoimmune", # ICD-9: Purpura and hemorrhagic conditions (ITP)
  "283"  = "Hematologic Autoimmune", # ICD-9: Hemolytic anemias

  # --- SLE / CONNECTIVE TISSUE ---
  "M32" = "SLE / Connective Tissue", # Systemic lupus erythematosus (M32.x)
  "M35" = "SLE / Connective Tissue", # Sjogren syndrome (M35.0x) and overlap syndromes

  # --- PSORIASIS / PSORIATIC ARTHRITIS (MTX primary indication) ---
  "L40" = "Psoriasis",               # Psoriasis (L40.0-L40.9) + psoriatic arthritis (L40.5x)
  "696" = "Psoriasis",               # ICD-9: Psoriasis and similar disorders

  # --- INFLAMMATORY BOWEL DISEASE (MTX indication) ---
  "K50" = "Inflammatory Bowel Disease", # Crohn's disease
  "K51" = "Inflammatory Bowel Disease", # Ulcerative colitis
  "555" = "Inflammatory Bowel Disease", # ICD-9: Regional enteritis
  "556" = "Inflammatory Bowel Disease"  # ICD-9: Ulcerative colitis
)
```

**D69 disambiguation:** D69.2 (IgA vasculitis) and D69.3 (ITP) share the 3-char prefix D69. The 4-char keys `"D692"` and `"D693"` resolve this cleanly — the same 4-char-before-3-char cascade used in `classify_doi_codes()` picks the subcategory first. This mirrors the `C810`/`C81` NLPHL precedent in `CANCER_SITE_MAP` exactly.

**ICD-9 710 shared across categories:** ICD-9 710 covers SLE, dermatomyositis, and polymyositis. Map it to "Inflammatory Myopathy" (the most specific match for rituximab/MTX) and note in comments that SLE in ICD-9 era is captured here. ICD-10 M32/M33 are distinct, so ICD-10 data is unambiguous.

**No cancer overlap possible:** `CANCER_SITE_MAP` keys are `C00-C96`, `D00-D49`. `DOI_CODE_MAP` keys are in `M`, `L`, `I`, `G`, `H`, `K`, `D59`, `D69x` (D5x and D6x are outside D00-D49 neoplasm range). The only D-prefix entries in `DOI_CODE_MAP` are D59 and D692/D693, which are in the blood disorder chapter (D50-D89), not the neoplasm chapter (D00-D49). The smoke test overlap check confirms this at runtime.

---

## 2. The Classifier Helper: New `R/utils/utils_doi.R`, Not an Extension of `utils_cancer.R`

### Decision: New file, not extension

Do NOT extend `utils_cancer.R`. Reasons grounded in the actual codebase:

1. **`classify_codes()` is consumed by 10+ scripts** (R/28, R/40, R/43-R/49, R/51, R/56) and every consumer assumes the return values are cancer site categories. Adding non-malignant categories would silently corrupt cancer summary tables.
2. **`is_cancer_code()` contract** (from utils_cancer.R docstring): "every code detected as cancer can be classified by classify_codes()." A DoI code must not be detected as cancer.
3. **Precedent for functional separation:** `utils_payer.R`, `utils_treatment.R`, `utils_dates.R` each own one domain. DoI classification is its own domain.
4. **Auto-sourcing:** `R/00_config.R` globs `R/utils/*.R` at the bottom. A new `utils_doi.R` file is automatically sourced everywhere with zero config changes.

### File content pattern (mirrors utils_cancer.R)

```r
# ==============================================================================
# utils/utils_doi.R -- Diagnosis-of-Interest classification utilities
# ==============================================================================
#
# Purpose:
#   Provides is_doi_code() for detecting non-malignant rituximab/MTX indication
#   codes and classify_doi_codes() for mapping ICD-10/ICD-9 codes to DoI
#   categories using DOI_CODE_MAP from R/00_config.R.
#
#   WHY parallel to utils_cancer.R but NOT merged: DoI codes are non-malignant
#   (M/L/D-blood/G/I/K chapter space). classify_codes() consumers assume
#   cancer-site output; merging would break 10+ downstream scripts.
#
# Dependencies: DOI_CODE_MAP from R/00_config.R, stringr
# ==============================================================================

is_doi_code <- function(dx) {
  dx_clean <- str_remove(dx, "\\.")
  substr(dx_clean, 1, 4) %in% names(DOI_CODE_MAP) |
  substr(dx_clean, 1, 3) %in% names(DOI_CODE_MAP)
}

classify_doi_codes <- function(codes) {
  codes_clean <- str_remove(codes, "\\.")
  prefix4 <- substr(codes_clean, 1, 4)
  prefix3 <- substr(codes_clean, 1, 3)
  match4  <- DOI_CODE_MAP[prefix4]
  match3  <- DOI_CODE_MAP[prefix3]
  unname(ifelse(!is.na(match4), match4, match3))
}
```

This is a strict structural mirror of `is_cancer_code()` and `classify_codes()` — same normalization step, same 4-char-then-3-char cascade, same `unname()` call.

---

## 3. Grain Decision: Both Patient-Level and Encounter-Level

### Downstream consumer inventory

| Consumer | Grain needed | Why |
|----------|-------------|-----|
| Treatment attribution linkage | Encounter-level | Needs (PATID, ENCOUNTERID, DX_DATE) to join drug administrations |
| Tableau Sheet 1 prevalence | Patient-level | Unique patient counts by DoI category + payer |
| Tableau Sheet 2 co-occurrence | Encounter-level | Drug × DoI co-occurrence at the encounter level |
| Tableau Sheet 3 summary | Category-level (aggregated) | Pivot table for Tableau |
| Future episode enrichment (v3.4+) | Could join doi_patients to episodes | Patient-level summary is the natural join key |

### Decision: Produce two cached artifacts

**Artifact 1 (primary) — `cache/outputs/doi_encounters.rds`**
- Grain: one row per (PATID, ENCOUNTERID, DX_DATE, doi_code, doi_category)
- Source: DIAGNOSIS table, filtered with `is_doi_code(DX) == TRUE`
- Belt-and-suspenders guard: `filter(!is_cancer_code(DX))` to prevent any oncology code from leaking through

**Artifact 2 (derived) — `cache/outputs/doi_patients.rds`**
- Grain: one row per PATID
- Columns: `has_any_doi`, `doi_categories` (comma-sep ascending), `doi_first_date`, `doi_last_date`, `n_doi_encounters`
- Derived from Artifact 1 via `group_by(PATID) %>% summarise(...)`

This mirrors the `treatment_episodes.rds` (episode-level) + `treatment_episode_detail.rds` (encounter-level) pattern.

### How to attach without disturbing the cancer cascade

The cancer cascade — `R/28 classify_codes()` → `cancer_category` on treatment_episodes.rds — is entirely unchanged. The DoI flag is computed in a standalone script (R/111) via separate artifacts. The existing `is_hodgkin` and `cancer_category` columns on `treatment_episodes.rds` are read-only from R/111's perspective.

If a future milestone wants `has_doi` surfaced on the episode level, it should be a left-join enrichment in R/28 using `doi_patients.rds` — added as a new optional column, not by touching `classify_codes()`.

---

## 4. Treatment-Attribution Linkage

### Source of drug administration data

Use `treatment_episode_detail.rds` (produced by R/26, already in the pipeline). This 5-column tibble — `(patient_id, treatment_type, treatment_date, triggering_code, source_hint)` — already has source provenance from Phase 124. Filter to rituximab and MTX codes using new `RITUXIMAB_CODES` and `MTX_CODES` vectors (defined in R/00_config.R Section 4d, populated from `DRUG_GROUPINGS` keys by drug name).

Do NOT re-query DuckDB for drug administrations. The RDS artifact is already the curated, deduplicated, source-tagged ground truth.

### Join strategy: Two-tier with ENCOUNTERID first

**Tier 1 — ENCOUNTERID direct match** (higher clinical confidence)

When a DoI diagnosis and a drug administration share the same ENCOUNTERID (same visit), flag as `attribution_method = "encounter_id"`. This is the identical pattern to R/28 Step 4c.

```r
tier1 <- doi_encounters %>%
  inner_join(
    drug_detail %>% filter(!is.na(ENCOUNTERID)),
    by = c("PATID" = "patient_id", "ENCOUNTERID")
  ) %>%
  mutate(attribution_method = "encounter_id")
```

**Tier 2 — PATID + temporal window** (broader, lower confidence)

For DoI encounters not matched by ENCOUNTERID, use a PATID join with a date-distance filter:

```r
tier2 <- doi_encounters %>%
  anti_join(tier1, by = c("PATID", "ENCOUNTERID")) %>%
  left_join(drug_detail, by = c("PATID" = "patient_id"),
            relationship = "many-to-many") %>%
  filter(abs(as.numeric(DX_DATE - treatment_date)) <= ATTRIBUTION_WINDOW_DAYS) %>%
  mutate(attribution_method = "temporal_window")
```

### Attribution window: ±90 days

Justification for 90 over the cancer cascade's 30:

- R/28's ±30-day window links a treatment episode to its cancer diagnosis, which occurs within the acute treatment period. RA, psoriasis, and SLE diagnosis to rituximab initiation typically spans months (steroid trial → DMARD failure → biologic escalation).
- Rituximab maintenance dosing is every 6 months; quarterly assessment windows are the clinical standard. ±90 days (one quarter) captures the relevant dosing context without excessive noise.
- MTX for psoriasis or IBD is initiated at or near diagnosis and re-assessed at 12-week intervals. ±90 days captures the standard re-assessment window.
- ±30 days would miss the vast majority of RA/psoriasis attribution cases. ±180 days exceeds one rituximab dosing cycle and produces unacceptable noise.

Define as a named constant in R/00_config.R Section 4d: `DOI_ATTRIBUTION_WINDOW_DAYS <- 90L`. Document in the Metadata sheet of the output xlsx.

### "Likely non-lymphoma-directed" derived flag

```r
likely_non_lymphoma_directed <- case_when(
  # Strong signal: drug co-occurs with DoI diagnosis AND no HL active at same window
  near_drug == TRUE & !is_hodgkin_active ~ TRUE,

  # Ambiguous: HL also present in same window (could serve either indication)
  near_drug == TRUE & is_hodgkin_active  ~ NA_logical_,

  # No drug co-occurrence: cannot attribute
  near_drug == FALSE                     ~ FALSE
)
```

Expose as a three-state column (`TRUE` / `FALSE` / `NA`). `NA` means "co-occurring HL and DoI — reviewer discretion." This avoids silently forcing ambiguous cases to FALSE, which would undercount potential non-lymphoma attribution.

`is_hodgkin_active` is derived by checking whether any HL diagnosis (from `is_cancer_code(DX) && classify_codes(DX) == "Hodgkin Lymphoma (non-NLPHL)" || ...`) falls within the same ±90-day window. Use the existing DX data already loaded in R/111 — no additional DuckDB query needed.

---

## 5. Standalone Table: `R/111_doi_attribution_report.R`

### Convention compliance

Following R/100_ruca_rurality_summary.R exactly:

- 5-field header: Purpose, Inputs, Outputs, Dependencies, Requirements
- `source("R/00_config.R")` at top (auto-loads all utils including new utils_doi.R)
- `source("R/utils/utils_assertions.R")` for `assert_rds_exists()`
- `assert_rds_exists(DETAIL_RDS, script_name = "R/111")` before loading
- `get_pcornet_table("DIAGNOSIS")` for DX pull; `open_pcornet_con()` / `close_pcornet_con()` bracket
- `add_styled_sheet()` helper (inline or imported pattern from R/100)
- Console summary block at end mirroring R/100 Section 11

### Sheet structure (Tableau-ready)

**Sheet 1: Patient Prevalence** (grain: unique PATID)
| Column | Type | Description |
|--------|------|-------------|
| PATID | character | Patient identifier |
| has_any_doi | logical | Any DoI code ever recorded for this patient |
| doi_categories | character | Comma-sep ascending DoI categories |
| doi_first_date | Date | Earliest DoI DX_DATE |
| doi_last_date | Date | Latest DoI DX_DATE |
| n_doi_encounters | integer | Count of distinct encounters with DoI DX |
| payer_category | character | AMC 8-category from ENCOUNTER (most recent or modal) |

**Sheet 2: Encounter Co-occurrence** (grain: PATID + ENCOUNTERID + doi_code)
| Column | Type | Description |
|--------|------|-------------|
| PATID | character | Patient identifier |
| ENCOUNTERID | character | Encounter identifier |
| DX_DATE | Date | Date of DoI diagnosis |
| doi_code | character | Raw ICD code |
| doi_category | character | Classified DoI category |
| near_rituximab | logical | Rituximab administered within ±90 days |
| near_mtx | logical | MTX administered within ±90 days |
| attribution_method | character | "encounter_id" / "temporal_window" / "none" |
| likely_non_lymphoma_directed | logical (3-state) | TRUE / FALSE / NA |

**Sheet 3: Drug Co-occurrence Summary** (grain: doi_category x drug_type, aggregated)
| Column | Type | Description |
|--------|------|-------------|
| doi_category | character | DoI category |
| drug_type | character | "Rituximab" or "Methotrexate" |
| n_patients | character | Suppressed count of distinct PATIDs |
| n_encounters | character | Suppressed count of distinct encounters |
| pct_of_doi_patients | numeric | Within-category percentage |

**Sheet 4: Metadata**
Run date, HL cohort size, DoI code count by category, attribution window (90 days), HIPAA suppression threshold (<11), source tables, data provenance notes.

### HIPAA suppression

Apply `suppress_small()` (define inline in R/111, pattern from R/57):

```r
suppress_small <- function(n, threshold = 11L) {
  if_else(n < threshold, "<11", as.character(n))
}
```

All `n_patients` and `n_encounters` columns in Sheet 3 pass through this before xlsx write.

---

## 6. Smoke Test Coverage (`R/88_smoke_test_comprehensive.R`)

Add a new section after the current last section. The smoke test currently opens with `[1/29]` through `[29/29]`; this becomes a 30th section `[30/30]` — or adjust the header count to match.

**New Section: DoI infrastructure checks**

```r
message("\n[30/30] Diagnosis-of-Interest (DoI) infrastructure...")

source("R/00_config.R", local = TRUE)  # load constants fresh

check("DOI_CODE_MAP constant exists", exists("DOI_CODE_MAP"))
check("DOI_CODE_MAP is named character vector", is.character(DOI_CODE_MAP))
check("DOI_CODE_MAP has >=20 entries", length(DOI_CODE_MAP) >= 20L)

# Critical: no overlap with cancer maps
overlap_keys <- intersect(
  names(DOI_CODE_MAP),
  c(names(CANCER_SITE_MAP), names(ICD9_CANCER_SITE_MAP))
)
check("DOI_CODE_MAP has no keys overlapping cancer maps",
      length(overlap_keys) == 0)

check("is_doi_code() exists", exists("is_doi_code"))
check("classify_doi_codes() exists", exists("classify_doi_codes"))

# Functional spot-checks
check("is_doi_code detects M05.9 (RA)",
      isTRUE(is_doi_code("M05.9")))
check("is_doi_code rejects C81.90 (HL -- must be FALSE)",
      isFALSE(is_doi_code("C81.90")))
check("classify_doi_codes maps M05.9 to RA",
      classify_doi_codes("M05.9") == "Rheumatoid Arthritis")

check("R/utils/utils_doi.R exists",
      file.exists(file.path("R", "utils", "utils_doi.R")))
check("R/111_doi_attribution_report.R exists",
      file.exists(file.path("R", "111_doi_attribution_report.R")))
```

The no-overlap check is the critical guard. If a future code map addition accidentally duplicates a cancer prefix, the smoke test catches it before any data runs.

---

## 7. `R/39_run_all_investigations.R` Registration

Two targeted additions to the existing file:

**In `investigation_scripts` vector (Section 3), after R/106:**
```r
"R/111_doi_attribution_report.R"   # v3.3: DoI attribution report
```

**In `expected_xlsx` character vector (Section 7 pre-render check), after existing entries:**
```r
"doi_attribution_report.xlsx"
```

No other changes to R/39.

---

## 8. `R/SCRIPT_INDEX.md` Registration

Add a row in the "Post-Renumber Investigations (100+)" table:

```
| 111_doi_attribution_report.R | v3.3: Rituximab/MTX non-malignant DoI attribution: encounter-level DoI flags (is_doi_code), ±90-day drug attribution linkage (ENCOUNTERID-first + temporal fallback), likely_non_lymphoma_directed 3-state flag, 4-sheet Tableau-ready xlsx | 00_config, utils_doi, utils_assertions, utils_duckdb, utils_payer |
```

---

## 9. Build Order (Dependency-Respecting)

| Step | File | Type | Content | Depends On |
|------|------|------|---------|-----------|
| 1 | `R/00_config.R` | MODIFIED | Add Section 4c `DOI_CODE_MAP`, Section 4d `RITUXIMAB_CODES`, `MTX_CODES`, `DOI_ATTRIBUTION_WINDOW_DAYS` | Nothing (root config) |
| 2 | `R/utils/utils_doi.R` | NEW | `is_doi_code()`, `classify_doi_codes()` | Step 1 (DOI_CODE_MAP) |
| 3 | `R/111_doi_attribution_report.R` | NEW | All sections: DX extraction, attribution linkage, xlsx output | Steps 1+2; R/26+R/28 already run (RDS inputs) |
| 4 | `R/39_run_all_investigations.R` | MODIFIED | Add R/111 to investigation_scripts + expected_xlsx | Step 3 |
| 5 | `R/SCRIPT_INDEX.md` | MODIFIED | Add R/111 row | Step 3 |
| 6 | `R/88_smoke_test_comprehensive.R` | MODIFIED | Add DoI infrastructure section | Steps 1+2 |

Steps 4, 5, and 6 are independent of each other and can be done in parallel after Step 3 is complete. Steps 1 and 2 are strictly serial (config before utils). Step 3 requires both.

---

## 10. Integration Points: New vs Modified Per File

| File | Status | What Changes |
|------|--------|-------------|
| `R/00_config.R` | MODIFIED | +Section 4c `DOI_CODE_MAP`, +Section 4d `RITUXIMAB_CODES`, `MTX_CODES`, `DOI_ATTRIBUTION_WINDOW_DAYS` |
| `R/utils/utils_doi.R` | NEW | `is_doi_code()` + `classify_doi_codes()` |
| `R/111_doi_attribution_report.R` | NEW | Complete investigation script (DX extraction → attribution → xlsx) |
| `R/39_run_all_investigations.R` | MODIFIED | +1 entry in investigation_scripts; +1 entry in expected_xlsx |
| `R/SCRIPT_INDEX.md` | MODIFIED | +1 row for R/111 |
| `R/88_smoke_test_comprehensive.R` | MODIFIED | +1 new section, 10 checks |
| `R/utils/utils_cancer.R` | NOT MODIFIED | Parallel system; no changes |
| `R/28_episode_classification.R` | NOT MODIFIED | DoI is not an episode enrichment in v3.3 |
| `cache/outputs/treatment_episodes.rds` | READ-ONLY | Attribution joins to detail RDS; episodes not rewritten |
| `cache/outputs/treatment_episode_detail.rds` | READ-ONLY | Source for drug co-occurrence join |

---

## 11. Data Flow Diagram

```
R/00_config.R
  DOI_CODE_MAP (Section 4c)
  RITUXIMAB_CODES, MTX_CODES, DOI_ATTRIBUTION_WINDOW_DAYS (Section 4d)
      |
      v (auto-sourced by R/00_config.R utils glob)
R/utils/utils_doi.R
  is_doi_code(), classify_doi_codes()
      |
      +---------------------------+
      |                           |
      v                           v
DIAGNOSIS table (DuckDB)    treatment_episode_detail.rds (R/26)
  filter: is_doi_code(DX)     filter: code in RITUXIMAB_CODES | MTX_CODES
  guard:  !is_cancer_code(DX)
      |
      v
doi_encounters (PATID, ENCOUNTERID, DX_DATE, doi_code, doi_category)
doi_patients   (PATID, has_any_doi, doi_categories, ...)
      |
      v
Attribution join (ENCOUNTERID-first, then ±90-day PATID temporal)
  --> likely_non_lymphoma_directed (TRUE/FALSE/NA)
      |
      v
output/doi_attribution_report.xlsx
  Sheet 1: Patient Prevalence   (patient-level)
  Sheet 2: Encounter Co-occur.  (encounter-level)
  Sheet 3: Drug x DoI Summary   (aggregated, HIPAA-suppressed)
  Sheet 4: Metadata
```

The existing cancer cascade is entirely separate:

```
R/28_episode_classification.R
  classify_codes(DX) --> cancer_category on treatment_episodes.rds
  [R/utils/utils_cancer.R + CANCER_SITE_MAP]
  [NOT AFFECTED by v3.3 -- runs in parallel]
```

---

## 12. Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Code map location | R/00_config.R Section 4c | Mirrors CANCER_SITE_MAP, AMC_PAYER_LOOKUP, DEATH_CAUSE_MAP pattern — every classifier constant lives here |
| New utils file vs extend utils_cancer.R | NEW `R/utils/utils_doi.R` | 10+ scripts consume `classify_codes()` expecting cancer-site output; merging breaks them; precedent: one file per functional domain |
| Primary grain | Encounter-level (`doi_encounters.rds`) | Attribution requires encounter context; patient-level is derived convenience |
| Attribution join primary key | ENCOUNTERID first, PATID+temporal second | Mirrors R/28 D-01/D-02 pattern; ENCOUNTERID is highest-confidence, temporal is fallback |
| Attribution window | ±90 days | RA/psoriasis/IBD indication timelines; 3x wider than cancer's ±30 days; one clinical quarter; documented for SME review |
| "Likely non-lymphoma-directed" type | Three-state logical (TRUE/FALSE/NA) | Ambiguous cases (HL + DoI co-present) must not be forced to FALSE |
| Script number | R/111 | Follows R/100-R/110 post-renumber investigation sequence |
| R/28 modification | NOT modified | DoI is a parallel analysis, not an episode enrichment in v3.3 |
| HIPAA suppression | `<11` threshold on all patient/encounter counts | Consistent with existing R/57 and project constraint |

---

## Sources

All findings are based on direct inspection of codebase files:

- `R/00_config.R` lines 529-806 (CANCER_SITE_MAP structure), 427-493 (AMC_PAYER_LOOKUP), 969-1037 (DEATH_CAUSE_MAP) — classifier constant patterns
- `R/utils/utils_cancer.R` — `is_cancer_code()` and `classify_codes()` structure to mirror
- `R/28_episode_classification.R` lines 190-237 — ENCOUNTERID-first + 30-day temporal fallback pattern
- `R/100_ruca_rurality_summary.R` — R/100+ investigation script convention, `add_styled_sheet()`, RDS guard pattern
- `R/39_run_all_investigations.R` lines 176-201 — investigation_scripts registration and expected_xlsx list
- `R/88_smoke_test_comprehensive.R` lines 51-80 — section structure and `check()` function
- `R/SCRIPT_INDEX.md` — existing investigation registration table
- `.planning/research/ritdis_seed_codes.md` — seed code set with gaps identified
- `.planning/PROJECT.md` lines 91-97 — v3.3 requirements
