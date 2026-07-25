# Phase 131: Update all_codes_resolved.xlsx to include MED_ADMIN NDC-resolved codes and a normalized drug-name column - Research

**Researched:** 2026-07-22
**Domain:** R/dplyr/openxlsx2 internal-report generation; PCORnet CDM MED_ADMIN/DISPENSING NDC resolution; RxNorm/HCPCS drug-name normalization
**Confidence:** HIGH (based on direct source-code inspection of R/50, R/00_config.R, utils_treatment.R, R/105, R/108, R/88, and cross-referenced against Phase 122/120/114 history)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**MED_ADMIN/NDC fix scope**
- Extend R/50's existing MED_ADMIN query (currently `MEDADMIN_CODE %in% codes, MEDADMIN_TYPE == "RX"` only) to also resolve `MEDADMIN_TYPE == "ND"` (NDC-typed) rows and DISPENSING NDC rows, via the same NDC→RxNorm crosswalk built in Phase 122 (`ndc_rxnorm_crosswalk.rds` / `R/108`). This applies automatically across all 4 RXNORM-based vector categories R/50 already loops over (chemo_rxnorm, sct_rxnorm, immunotherapy_rxnorm, supportive_care_rxnorm) — not chemo-only.
- This closes the "broader audit of other tables/consumers for analogous code-column mismatches" item explicitly deferred at the end of Phase 122.

**Medication column — source of truth**
- Primary source: `MEDICATION_LOOKUP` (code → normalized name, sourced from `data/reference/all_codes_resolved_next_tables_v2.1.xlsx`'s Medication column, Phase 114). Reuse it — do not reinvent.
- Fallback (codes with no MEDICATION_LOOKUP entry — new NDC-resolved MED_ADMIN codes, and existing Supportive Care/SCT/Immunotherapy codes since the reference file's Medication column is only populated for Chemotherapy): apply heuristic normalization, not blank and not raw-text passthrough.
  - RxNorm strings: strip down to the bare generic ingredient name, dropping salt form (e.g. "bendamustine hydrochloride 25 MG/ML Injectable Solution [Bendeka]" → "bendamustine"), matching the curated column's own style exactly.
  - HCPCS J-codes: apply the same "Injection, X, dose" pattern-stripping used by the curated reference (e.g. "Injection, ado-trastuzumab emtansine, 1 mg" → "ado-trastuzumab emtansine").
  - Multi-ingredient RxNorm compounds (e.g. "ascorbic acid / beta carotene / copper sulfate / ..."): show the full compound string unchanged — do not shorten to first ingredient, do not blank.
  - No visual/column distinction between curated (reference-file-sourced) vs. fallback-normalized names — a single Medication column, populated either way.

**Medication column — sheet scope**
- Add the Medication column to: Chemotherapy (already has it), Supportive Care, Immunotherapy, and SCT.
- SCT population rule: automatic by `Code Type == "RXNORM"` (SCT mixes DRG/ICD-10-PCS/RXNORM conditioning-regimen codes in one sheet) — populate Medication only for RXNORM rows, blank for procedure/DRG/ICD rows. No manually curated code list.
- Do NOT add a Medication column to Radiation — it's pure procedure/DRG/ICD codes, a column there would be all-blank noise.

**New-code visibility**
- Codes only detectable via the new NDC crosswalk (MED_ADMIN ND-type, DISPENSING) get distinguished in the existing **Source Table** column (e.g. "MED_ADMIN (RX)" vs "MED_ADMIN (NDC)", or similarly distinguishing DISPENSING) rather than a new dedicated column — reuse the existing column, don't add a flag column.
- Do NOT add a before/after delta note (e.g. "+N codes via NDC crosswalk") to the Summary/Metadata sheet — show current-run counts only, no comparison to a prior run.

**Output files**
- Both the combined `all_codes_resolved.xlsx` and the 5 per-type files get all of the above (MED_ADMIN NDC coverage + Medication column) — they share the same underlying data via `write_resolved_xlsx()`, keep them in sync.
- The 5 per-type files are legacy/low-priority in practice (nobody actively opens them), but should still get updated since they're generated from the same pipeline — don't let them silently diverge.

### Claude's Discretion
- Exact string-stripping implementation for the fallback normalizer (regex approach, whether to factor it into a shared helper vs. inline in R/50)
- Whether to reuse/extend `canonicalize_drug_name()` / `DRUG_NAME_ALIASES` for the fallback path, or write independent logic
- Exact Source Table label text distinguishing MED_ADMIN RX vs ND-resolved rows
- R/88 smoke-test additions for the new column/coverage
- Column position/ordering in the sheets

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

## Summary

Phase 131 touches a single script, `R/50_all_codes_resolved.R` (865 lines), but the two requested changes require more structural rework than the CONTEXT.md phrasing suggests, because of two facts confirmed by direct source inspection:

1. **R/50 currently has ZERO per-code source granularity.** Its RXNORM aggregation (lines 317-372) queries PRESCRIBING and MED_ADMIN (RX-typed only), `bind_rows()`s the hits, and groups by `code` alone — the resulting `source_table` value written to the sheet (`"PRESCRIBING|MED_ADMIN"`) comes from a **static per-vector string in `code_type_map`** (line 60/76/79/80), not from which table/type actually matched each code. To show "MED_ADMIN (RX)" vs "MED_ADMIN (NDC)" vs "DISPENSING" per code, the aggregation must be restructured to tag and carry a source label through `count_results` before it collapses to `all_codes_df`. This is the larger of the two changes.
2. **R/50 has ZERO Medication column today**, and has **never queried DISPENSING at all**. The "(already has it)" phrase in CONTEXT.md refers to the *reference Excel* (`all_codes_resolved_next_tables_v2.1.xlsx`) that feeds `MEDICATION_LOOKUP`, not to R/50's generated output — confirmed by grep: `write_resolved_xlsx()` (line 580) and the combined-workbook per-category loop (lines 765-837) both hard-code a fixed 6-column header (`Code, Meaning, Code Type, Source Table, Records, Patients`) with no Medication field anywhere. Both of these near-duplicate code blocks (per-type sheets vs. combined workbook sheets — they duplicate header/data-frame logic almost verbatim) must be edited in sync, or the two output shapes will diverge.

The good news: every low-level building block needed already exists and is proven in production, from three separate prior phases:
- **Phase 122** built `data/reference/ndc_rxnorm_crosswalk.rds` (NDC→RxCUI) and `get_chemo_hits()` / `load_ndc_crosswalk()` / `normalize_ndc()` in `R/utils/utils_treatment.R`. Despite its name, `get_chemo_hits(table_name, codes, ndc_crosswalk, return_raw_name)` is **fully generic** — it filters on whatever `codes` vector is passed in, so it can be called with `sct_rxnorm`, `immunotherapy_rxnorm`, or `supportive_care_rxnorm` exactly as with `chemo_rxnorm`. It already handles PRESCRIBING, MED_ADMIN (RX-typed AND ND-typed, bound together), and DISPENSING (NDC + crosswalk). **However, its return value does not tag which sub-path (RX vs ND vs DISPENSING) produced each row** — that tagging must be added, either as a new optional parameter (mirroring the existing `return_raw_name` pattern) or via bespoke logic in R/50 itself.
- **Phase 114** built `MEDICATION_LOOKUP` (R/00_config.R lines 2496-2549) — a named character vector, code → Title-Case medication name, built from column 3 ("Medication") of all 5 sheets of the reference Excel, with `canonicalize_drug_name()` / `DRUG_NAME_ALIASES` (lines 2578-2624) already applied. Confirmed: only the Chemotherapy sheet's column 3 holds real drug names in that reference file — Supportive Care/SCT/Immunotherapy column-3 values are code-type labels that get filtered out (`code_type_labels` list, line 2539), so `MEDICATION_LOOKUP` today has effectively zero coverage for those three categories.
- **Phase 120** built `R/105_normalize_supportive_care_meaning.R`, which already solves an almost-identical normalization problem: it resolves all 171 Supportive Care RXNORM codes to a bare generic ingredient name via a 3-tier cascade (RxNav `related.json?tty=IN` → RxNav `historystatus.json` → **a rule-based regex fallback, `rule_based_ingredient()`**, lines 262-320) and writes the result to a **new "Normalized Meaning" column (col G)** appended in-place to the Supportive Care sheet of the reference Excel. `rule_based_ingredient()` strips pack wrappers, dose/quantity tokens, formulation words ("Injectable Solution", "Prefilled Syringe", etc.), brand brackets, and salt words ("hydrochloride", "phosphate", "HCl"), then runs the result through `canonicalize_drug_name()` — this is a near-exact reference implementation of the "strip down to bare generic ingredient" fallback CONTEXT.md asks for, and should be reused/adapted rather than rewritten from scratch. Critically, **`MEDICATION_LOOKUP`'s builder never reads column G — only column 3** — so this existing Phase 120 asset is not currently flowing anywhere downstream. Flagged as an Open Question below.

**Primary recommendation:** (1) Add a `source` tag to `get_chemo_hits()`'s return (new optional param, backward-compatible, mirroring `return_raw_name`) and a new DISPENSING call generalized across all 4 RXNORM vectors in R/50 Section 3; carry the per-code actual source(s) through to `all_codes_df$source_table` instead of the current static per-vector string. (2) Extract/adapt `rule_based_ingredient()`'s regex logic (Supportive Care precedent) into a shared fallback normalizer covering both RxNorm-STR and HCPCS-J-code inputs, operating on R/50's already-coalesced `description` field (not raw config-file comments, which are sometimes mid-word truncated); apply it to Chemotherapy/SCT/Immunotherapy/Supportive Care sheets after MEDICATION_LOOKUP lookup fails. (3) Add both the source-tagging and the Medication column consistently in `write_resolved_xlsx()` (per-type files) AND the combined-workbook per-category loop (they are separate, duplicated code blocks). (4) Add a new R/88 structural smoke-test section (next available letter: `15x`) validating the new logic by grep, per the project's established convention (no live HiPerGator/Rscript needed locally).

---

## Project Constraints

No `CLAUDE.md` was found in the repository at the time of this research (searched project-wide) — conventions below are inferred directly from source-code inspection and the prior phase's research documents, which is the strongest available evidence.

| Directive (inferred) | Implication for Phase 131 |
|-----------------------|---------------------------|
| tidyverse ecosystem only (dplyr/stringr/purrr/glue), no data.table | All new R/50 logic follows this; `get_chemo_hits()` already does |
| `ID` is the patient-id column (not PATID) across all tables | Any new DISPENSING/MED_ADMIN aggregation uses `ID` |
| here()/repo-relative paths, no `setwd()` | R/105 and R/108 both already follow this; new code should too |
| Graceful degradation: missing table/column → message + skip, never crash | `safe_table()`, `load_ndc_crosswalk()`, `get_chemo_hits()` all follow this; extend, don't regress |
| Structural (grep-based) R/88 smoke tests when Rscript/HiPerGator unavailable locally | `workflow.nyquist_validation` is `false` in `.planning/config.json` — confirmed; R/88 checks are grep-based against source text, not live data |
| Investigation-script decade/registration conventions (R/39, R/88, SCRIPT_INDEX.md) | R/50 IS registered in `R/39_run_all_investigations.R` (line 237, in `investigation_scripts`) and IS covered by an R/88 "Cancer decade (40-56)" existence check (line 253) — but R/88 has **no content-level checks on the actual xlsx output today**; this phase adds the first ones |

---

## Standard Stack

No new packages required — everything needed is already used by R/50, `utils_treatment.R`, and R/105.

| Library | Purpose in this phase | Already in use |
|---------|------------------------|----------------|
| dplyr | filter/group_by/summarise/bind_rows for the new DISPENSING + ND-typed aggregation | Yes (R/50 throughout) |
| stringr | regex stripping for the fallback normalizer (salt/formulation/dose stripping) | Yes (R/105's `rule_based_ingredient()`, `normalize_ndc()`) |
| glue | progress/log messages | Yes |
| openxlsx2 | `write_resolved_xlsx()` and combined-workbook writer | Yes |
| tibble | intermediate frames | Yes |

**No new renv installs needed.**

---

## Architecture Patterns

### Current R/50 structure (confirmed by direct read)

```
R/50_all_codes_resolved.R (865 lines)
├── SECTION 1: code_type_map tribble (vector_name -> category/code_type/source_table/px_type/match_type)
│     RXNORM rows: chemo_rxnorm, sct_rxnorm, immunotherapy_rxnorm, supportive_care_rxnorm
│     -- all 4 declared source_table = "PRESCRIBING|MED_ADMIN" (STATIC STRING, line 60/76/79/80)
├── SECTION 2: description cascade (api_descriptions > hardcoded > config comments -> "Meaning")
├── SECTION 3: DuckDB count queries
│     - PROCEDURES loop (CPT/HCPCS/ICD-9/ICD-10-PCS/Revenue)
│     - PRESCRIBING + MED_ADMIN loop (lines 317-372) <- TARGET OF CHANGE #1
│         presc_matches <- filter(RXNORM_CUI %in% codes)                 [unchanged]
│         medadmin_matches <- filter(MEDADMIN_CODE %in% codes,
│                                    MEDADMIN_TYPE == "RX")               [MISSING: "ND" + DISPENSING]
│         combined <- bind_rows(...) %>% group_by(code) %>% summarise()  [LOSES per-row source]
│     - ENCOUNTER loop (DRG)
├── SECTION 4: assemble all_codes_df
│     vec_df <- ... %>% mutate(source_table = source_table)  <- from code_type_map, STATIC per vector
├── SECTION 5: self-mutates R/00_config.R inline comments (unrelated to this phase, do not break)
└── SECTION 6: XLSX generation <- TARGET OF CHANGE #2
    ├── write_resolved_xlsx(df, category, output_path)   [per-type files, line 580]
    │     headers <- c("Code","Meaning","Code Type","Source Table","Records","Patients")  [6 cols, NO Medication]
    └── combined workbook per-category loop (lines 765-837)  [DUPLICATE of the above, must edit BOTH]
          headers_cat <- c("Code","Meaning","Code Type","Source Table","Records","Patients")  [same 6 cols]
```

### Pattern 1: Generalize NDC/RX/ND detection across 4 RXNORM vectors using `get_chemo_hits()`

`get_chemo_hits()` (in `R/utils/utils_treatment.R`, confirmed lines 172-280) is **generic despite its name** — it takes any `codes` vector as its 2nd argument. It already:
- Filters PRESCRIBING on `RXNORM_CUI %in% codes`
- Filters MED_ADMIN on **both** `MEDADMIN_TYPE == "RX"` (direct CUI match) **and** `MEDADMIN_TYPE == "ND"` (via `ndc_crosswalk[normalize_ndc(NDC)]`) — `bind_rows()`s them together
- Filters DISPENSING on `NDC` via the same crosswalk
- Degrades gracefully (message + `NULL`/empty) if a table, column, or the crosswalk is absent

This can be called once per RXNORM vector (`chemo_rxnorm`, `sct_rxnorm`, `immunotherapy_rxnorm`, `supportive_care_rxnorm`) instead of R/50 hand-rolling its own PRESCRIBING/MED_ADMIN queries. Example adaptation:

```r
# Source: R/utils/utils_treatment.R lines 172-280 (Phase 122), signature confirmed
ndc_crosswalk <- load_ndc_crosswalk()   # character(0) if not yet built -- degrades gracefully

for (i in seq_len(nrow(rxnorm_vectors))) {
  vec_name <- rxnorm_vectors$vector_name[i]
  codes <- TREATMENT_CODES[[vec_name]]
  if (is.null(codes) || length(codes) == 0) next

  hits <- bind_rows(
    get_chemo_hits("PRESCRIBING", codes, ndc_crosswalk),
    get_chemo_hits("MED_ADMIN",   codes, ndc_crosswalk),
    get_chemo_hits("DISPENSING",  codes, ndc_crosswalk)
  )
  # NOTE: as of Phase 122, get_chemo_hits() does NOT tag which of
  # PRESCRIBING / MED_ADMIN-RX / MED_ADMIN-ND / DISPENSING produced each row.
  # See "Pitfall: source tagging" below -- this is the missing piece.
}
```

**Caution:** `get_chemo_hits()` is called by 5 existing consumers (R/10, R/25, R/26, R/11, R/76 per Phase 122 research) with the 3-column contract `(ID, treatment_date, triggering_code)`. Any change to its signature/return shape MUST be additive and backward-compatible — exactly how `return_raw_name = FALSE` (default) was added in Phase 122/123 without touching existing callers. The natural parallel is a new `return_source = FALSE` parameter.

### Pattern 2: Source-tagged aggregation for the "Source Table" column

Since `code_type_map$source_table` is a **static per-vector string**, not derived from actual matches, achieving "MED_ADMIN (RX)" vs "MED_ADMIN (NDC)" vs "DISPENSING" per code requires carrying a `source` field through the aggregation, e.g.:

```r
# Tag before binding (illustrative -- exact tagging mechanism is Claude's discretion,
# but MUST happen before bind_rows() collapses the distinction)
presc_matches   <- get_chemo_hits("PRESCRIBING", codes, ndc_crosswalk) %>% mutate(source = "PRESCRIBING")
medadmin_hits   <- get_chemo_hits("MED_ADMIN",   codes, ndc_crosswalk, return_source = TRUE) # source in {"MED_ADMIN_RX","MED_ADMIN_ND"}
disp_hits       <- get_chemo_hits("DISPENSING",  codes, ndc_crosswalk) %>% mutate(source = "DISPENSING")

combined <- bind_rows(presc_matches, medadmin_hits, disp_hits) %>% distinct(ID, treatment_date, triggering_code, source)

# Aggregate per (code, source) so a code seen via 2+ paths keeps all its source labels
per_code_sources <- combined %>%
  group_by(code = triggering_code) %>%
  summarise(
    records = n(), patients = n_distinct(ID),
    source_table = paste(sort(unique(source)), collapse = ", "),
    .groups = "drop"
  )
```

`Records`/`Patients` totals must be computed on the deduplicated `(ID, treatment_date, triggering_code)` set to avoid inflating counts when the same administration is technically re-derivable from two paths (Phase 122 Pitfall 4, same risk applies here).

### Pattern 3: Fallback drug-name normalizer, adapted from R/105's `rule_based_ingredient()`

`R/105_normalize_supportive_care_meaning.R` (confirmed lines 262-320) already implements almost exactly what CONTEXT.md's fallback decision asks for, operating on RxNorm STR-style text:

```r
# Source: R/105_normalize_supportive_care_meaning.R lines 262-320 (Phase 120)
rule_based_ingredient <- function(meaning_text) {
  s <- meaning_text
  s <- str_remove(s, "^\\{.*\\}\\s*")                       # pack wrappers
  s <- str_remove_all(s, "\\d+\\s*\\([^)]*\\)")
  s <- str_remove(s, "^\\d+(\\.\\d+)?\\s+(ML|HR)\\s+")       # leading quantity
  s <- str_remove_all(s, "\\s*\\[[^\\]]*\\]")                # brand brackets
  s <- str_remove_all(s, "\\(Base Equivalent\\)")
  s <- str_remove_all(s, regex("\\b(MG/ML|MCG/ML|UNT/ML|UNT/MG|MG/MG|MG/HR|MG|MCG|ML)\\b", ignore_case = TRUE))
  s <- str_remove_all(s, "\\d+(\\.\\d+)?")
  s <- str_remove_all(s, "%")
  formulations <- c("Oral Tablet","Disintegrating","Oral Capsule","Oral Solution","Oral Film",
                     "Injectable Solution","Injection Solution","Injection","Inj","Prefilled Syringe",
                     "Ophthalmic Solution","Ophthalmic Suspension","Ophthalmic Ointment","Ophth Oint",
                     "Otic Suspension","Transdermal System","Pack","Soln","IV")
  for (f in formulations) s <- str_remove_all(s, regex(paste0("\\b", f, "\\b"), ignore_case = TRUE))
  salts <- c("sodium phosphate", "phosphate", "hydrochloride", "HCl")
  for (sw in salts) s <- str_remove_all(s, regex(paste0("\\b", sw, "\\b"), ignore_case = TRUE))
  s <- str_squish(s); s <- str_trim(s)
  s <- canonicalize_drug_name(s)
  tolower(str_trim(s))
}
```

For Phase 131 this needs two adaptations, not present in R/105:
1. **HCPCS J-code path** ("Injection, X, dose" → "X"): a simple new regex, e.g. `str_match(desc, "^Injection,\\s*([^,]+),")`, applied only when `code_type == "CPT/HCPCS"` and the description starts with "Injection,".
2. **Multi-ingredient compound passthrough**: R/105's version always collapses via RxNav's IN-concept list; the *offline* fallback for Phase 131 must detect an already-multi-ingredient input string (e.g. contains `" / "` separating ingredient tokens, as literally seen in the `immunotherapy_rxnorm` config comments — see Code Examples) and leave it verbatim rather than stripping/shortening.

**Input source:** the fallback should run on R/50's already-coalesced `description` field (Section 2's 3-source cascade: API descriptions > hardcoded > config comments), NOT directly on `R/00_config.R` inline comments — those are sometimes **mid-word truncated** as originally written (confirmed example: `"1090823", # Phase 40: ascorbic acid / beta carotene / copper s` — cut off at "copper s"). The API-sourced description (Phase 39/40 RDS, highest cascade priority) is the more complete text when present.

### Pattern 4: Medication column population rule (per sheet/category)

```r
all_codes_df <- all_codes_df %>%
  mutate(
    medication = case_when(
      category == "Radiation" ~ NA_character_,                                   # never populate
      category == "SCT" & code_type != "RXNORM" ~ NA_character_,                  # DRG/ICD/PCS rows blank
      code %in% names(MEDICATION_LOOKUP) ~ unname(MEDICATION_LOOKUP[code]),        # tier 1: curated
      TRUE ~ fallback_normalize(description, code_type)                           # tier 2: heuristic
    )
  )
```

### Pattern 5: Two duplicated xlsx-writer code blocks must both change

`write_resolved_xlsx()` (line 580, used for the 5 per-type files) and the combined-workbook per-category sheet loop (lines 765-837, used for `all_codes_resolved.xlsx`) are **separate, near-identical blocks** — each declares its own `headers`/`headers_cat` vector and its own `data.frame(...)` construction. Both must add the Medication column (and, per the "Source Table" decision, both already reference `df$source_table`/`df_cat$source_table` so once that field carries the new per-code value upstream, both writers pick it up for free — only the Medication column is a genuinely new addition to both).

### Anti-Patterns to Avoid

- **Assuming `code_type_map$source_table` already reflects per-code truth.** It's a fixed per-vector label today; relabeling it in `code_type_map` won't achieve per-code granularity — the aggregation logic itself must change.
- **Reading `R/00_config.R` inline comments directly as the fallback-normalizer input.** Use the coalesced `description` column; config comments can be truncated.
- **Editing only one of `write_resolved_xlsx()` / the combined-workbook loop.** They will silently diverge (exactly the failure mode CONTEXT.md explicitly warns about for the 5 per-type files).
- **Calling RxNav live from R/50.** Unlike R/105 (a one-time enrichment of a static reference file, safe to hit the network), R/50 is registered in `R/39` as a repeatable investigation script — CONTEXT.md's fallback is explicitly heuristic/offline, not API-based.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|--------------|-----|
| NDC → RxCUI resolution | New crosswalk/API call | `data/reference/ndc_rxnorm_crosswalk.rds` via `load_ndc_crosswalk()` | Already built (Phase 122/HiPerGator), offline, proven |
| PRESCRIBING/MED_ADMIN(RX+ND)/DISPENSING code detection | New per-table dplyr filters in R/50 | `get_chemo_hits(table_name, codes, ndc_crosswalk)` in `utils_treatment.R` | Generic despite name; already handles graceful degradation, NDC normalization, dedup |
| NDC string normalization | Custom regex | `normalize_ndc()` in `utils_treatment.R` (11-digit, zero-padded) | Exact function already used by the crosswalk and `get_chemo_hits()` |
| Curated code→drug-name lookup | New reference data | `MEDICATION_LOOKUP` in `R/00_config.R` | Phase 114 canonical source; already alias-normalized via `canonicalize_drug_name()` |
| RxNorm-STR → bare-ingredient stripping | New regex from scratch | Adapt `rule_based_ingredient()` from `R/105_normalize_supportive_care_meaning.R` | Near-identical problem already solved and battle-tested for Supportive Care |
| Brand→generic collapsing | New alias map | `canonicalize_drug_name()` / `DRUG_NAME_ALIASES` in `R/00_config.R` | Already used by `MEDICATION_LOOKUP` and R/105; keeps naming consistent project-wide |

**Key insight:** Every piece needed for Phase 131 was already built for a narrower purpose in Phases 114/120/122. The work here is almost entirely *generalization and wiring*, not new algorithm design — except for the per-code source-tagging, which is genuinely new (see Open Questions).

---

## Common Pitfalls

### Pitfall 1: `get_chemo_hits()` doesn't tag its match source
**What goes wrong:** Calling `get_chemo_hits()` for PRESCRIBING, MED_ADMIN, and DISPENSING and `bind_rows()`-ing the results loses which path produced each hit — exactly the granularity the "Source Table" decision requires.
**Why it happens:** The function was built in Phase 122 purely to unify chemo-detection, before any need to distinguish RX vs ND vs DISPENSING existed downstream.
**How to avoid:** Add a `return_source` (or similar) optional parameter to `get_chemo_hits()`, mirroring the existing `return_raw_name` pattern (additive, default `FALSE`, zero impact on the 5 existing callers), OR tag sources in R/50-local wrapper calls immediately after each `get_chemo_hits()` call (simpler, less invasive to a shared helper with 5 other consumers, but doesn't distinguish MED_ADMIN-RX from MED_ADMIN-ND without touching the helper, since both currently return under one `bind_rows()` inside `get_chemo_hits()` itself).
**Warning signs:** If the Source Table column output for ND-only-detected codes still reads "PRESCRIBING|MED_ADMIN" (the old static string) after implementation, the tagging didn't actually thread through.

### Pitfall 2: Records/Patients double-counting across sources
**What goes wrong:** The same (ID, date) administration can appear via both MED_ADMIN-RX and MED_ADMIN-ND, or PRESCRIBING and MED_ADMIN, for the same code — summing records/patients per source before combining inflates totals.
**Prevention:** `distinct(ID, treatment_date, triggering_code)` (or `..., source` if keeping source separate) before the final `summarise()`, exactly as Phase 122's Pitfall 4 documented for the chemo-detection consumers.

### Pitfall 3: MEDADMIN_TYPE values beyond RX/ND
**What goes wrong:** MED_ADMIN also contains `NI`/`UN`/`OT` type rows; matching MEDADMIN_CODE against RxNorm CUIs or the NDC crosswalk for these rows produces false positives (code system unknown).
**Prevention:** `get_chemo_hits()` already filters explicitly on `MEDADMIN_TYPE == "RX"` / `"ND"` only — reuse it rather than writing a laxer filter.

### Pitfall 4: `MEDICATION_LOOKUP` reads reference-Excel column 3 by POSITION, not by name
**What goes wrong:** Assuming any "Medication"-labeled column in the reference file is automatically picked up. `MEDICATION_LOOKUP`'s builder (R/00_config.R line 2510) hard-codes `sheet_df[[3]]` (3rd column by position). Phase 120's R/105 appended a NEW "Normalized Meaning" column at position **G (7th column)** to the Supportive Care sheet — this is NOT read by `MEDICATION_LOOKUP` today.
**Prevention:** Recognize this is a real, existing but currently-orphaned asset (171 Supportive Care codes already normalized). Decide explicitly whether Phase 131 should (a) leave it unused and rely on the new heuristic fallback for Supportive Care codes (consistent with CONTEXT.md's literal wording), or (b) also wire `MEDICATION_LOOKUP` (or a Supportive-Care-specific lookup) to read column G, reducing reliance on re-deriving the same normalization via regex. See Open Questions.

### Pitfall 5: Two duplicated xlsx-writer blocks
**What goes wrong:** `write_resolved_xlsx()` (per-type files) and the combined workbook's per-category loop (lines 765-837) each independently declare `headers`/data-frame shape. Editing one and not the other silently produces inconsistent per-type vs. combined outputs — precisely the failure mode CONTEXT.md flags for the 5 per-type files.
**Prevention:** Grep both `headers <- c("Code"...)` occurrences (confirmed at lines 603 and 792) before considering the column-addition task complete; ideally factor the header/df-shape into one shared list/function both writers consume.

### Pitfall 6: R/50 has never queried DISPENSING — it's a net-new table dependency
**What goes wrong:** Assuming "extend the existing MED_ADMIN loop" covers DISPENSING too. Grep confirms R/50 Section 3 only ever queries PROCEDURES, PRESCRIBING, MED_ADMIN, and ENCOUNTER — never DISPENSING. This is an entirely new data-source integration, not an extension of an existing DISPENSING block.
**Prevention:** Follow the `safe_table("DISPENSING")` graceful-degradation pattern already used for PRESCRIBING/MED_ADMIN in this same script (or delegate to `get_chemo_hits("DISPENSING", ...)` which already implements this).

### Pitfall 7: R/50's Section 5 self-mutates `R/00_config.R` inline comments
**What goes wrong:** Section 5 (lines 480-573) rewrites config comments based on `all_codes_df` descriptions with `file.copy`/backup/rollback logic. Newly-visible ND/DISPENSING-resolved codes flowing into `all_codes_df` for the first time could trigger comment updates for codes that previously had `records == 0` — this is likely desirable (comments become more accurate) but is an existing side-effect the planner should be aware could touch `R/00_config.R` beyond the phase's stated file list.
**Prevention:** No code change needed, but flag this in verification: confirm Section 5 behavior with the new codes still passes its own `validation_ok` parse-and-source check before/after.

### Pitfall 8: No existing R/88 content checks on R/50's output
**What goes wrong:** Assuming there's a pattern to extend. R/88's only R/50-related check today is a file-existence check (`"50_all_codes_resolved.R" %in% cancer_expected`, line 253) — no structural checks on the generated xlsx's columns/logic exist yet.
**Prevention:** This phase's R/88 addition is a **new** section (next available letter: `15x`, since sections run through `15w` — note `15g` appears out of alphabetical order near the end of the file, likely an insertion anomaly, but `15w` is still the highest letter in the `15x` sequence), following the grep-based structural-check convention (source-code pattern matches against `R/50_all_codes_resolved.R` text), consistent with how `15t` validated Phase 122's fix.

---

## Code Examples

### Current MED_ADMIN/PRESCRIBING loop (R/50, confirmed lines 317-372) — the code being extended
```r
rxnorm_vectors <- code_type_map %>% filter(str_detect(source_table, "PRESCRIBING\\|MED_ADMIN"))

for (i in seq_len(nrow(rxnorm_vectors))) {
  vec_name <- rxnorm_vectors$vector_name[i]
  codes <- TREATMENT_CODES[[vec_name]]
  if (is.null(codes) || length(codes) == 0) next

  presc_tbl <- safe_table("PRESCRIBING")
  presc_matches <- presc_tbl %>% filter(RXNORM_CUI %in% codes) %>%
    select(ID, code = RXNORM_CUI) %>% collect()

  medadmin_tbl <- safe_table("MED_ADMIN")
  medadmin_matches <- medadmin_tbl %>%
    filter(MEDADMIN_CODE %in% codes, MEDADMIN_TYPE == "RX") %>%   # <- "ND" missing
    select(ID, code = MEDADMIN_CODE) %>% collect()

  combined <- bind_rows(presc_matches, medadmin_matches)
  # DISPENSING never queried at all
  counts <- combined %>% group_by(code) %>%
    summarise(records = n(), patients = n_distinct(ID), .groups = "drop") %>%
    mutate(vector_name = vec_name)
  count_results <- bind_rows(count_results, counts)
}
```

### `code_type_map`'s static source_table declarations (R/50, confirmed lines 57-81)
```r
code_type_map <- tribble(
  ~vector_name, ~category, ~code_type, ~source_table, ~px_type, ~match_type,
  "chemo_rxnorm", "Chemotherapy", "RXNORM", "PRESCRIBING|MED_ADMIN", NA_character_, "exact",
  ...
  "sct_rxnorm", "SCT", "RXNORM", "PRESCRIBING|MED_ADMIN", NA_character_, "exact",
  "immunotherapy_rxnorm", "Immunotherapy", "RXNORM", "PRESCRIBING|MED_ADMIN", NA_character_, "exact",
  "supportive_care_rxnorm", "Supportive Care", "RXNORM", "PRESCRIBING|MED_ADMIN", NA_character_, "exact"
)
```

### `write_resolved_xlsx()` header definition (R/50, confirmed lines 603, 617-626) — 1 of 2 places to add Medication
```r
headers <- c("Code", "Meaning", "Code Type", "Source Table", "Records", "Patients")
...
write_df <- data.frame(
  Code = df$code, Meaning = ifelse(is.na(df$description), "", df$description),
  Code_Type = df$code_type, Source_Table = df$source_table,
  Records = df$records, Patients = df$patients, stringsAsFactors = FALSE
)
```

### Combined-workbook per-category header (R/50, confirmed lines 792, 806-814) — 2nd place, must match
```r
headers_cat <- c("Code", "Meaning", "Code Type", "Source Table", "Records", "Patients")
...
write_df_cat <- data.frame(
  Code = df_cat$code, Meaning = ifelse(is.na(df_cat$description), "", df_cat$description),
  Code_Type = df_cat$code_type, Source_Table = df_cat$source_table,
  Records = df_cat$records, Patients = df_cat$patients, stringsAsFactors = FALSE
)
```

### `MEDICATION_LOOKUP` builder (R/00_config.R, confirmed lines 2496-2549) — reads column 3 by position, all 5 sheets
```r
sheets <- c("Chemotherapy", "Radiation", "SCT", "Immunotherapy", "Supportive Care")
for (sheet_name in sheets) {
  sheet_df <- openxlsx2::wb_to_df(ref_wb, sheet = sheet_name, start_row = 2)
  sheet_map <- setNames(as.character(sheet_df[[3]]), as.character(sheet_df[[1]]))
  ...
}
# Filters out rows where col 3 is a code-type label (cpt, rxnorm, drg, ...), not a drug name --
# confirms Supportive Care/SCT/Immunotherapy column 3 is mostly non-drug-name today.
```

### `immunotherapy_rxnorm` config comments showing real multi-ingredient RxNorm STR text (R/00_config.R lines 3409-3421)
```r
immunotherapy_rxnorm = c(
  "891815", # Phase 40: ascorbic acid 113 MG / beta carotene 716
  "1090823", # Phase 40: ascorbic acid / beta carotene / copper s     <- truncated example
  ...
)
```
This confirms the multi-ingredient compound scenario CONTEXT.md describes is real, present data — but the config-comment text itself is truncated; the coalesced `description` field (API-sourced when available) should be preferred as fallback input over these raw comments.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|-------------------|---------------|--------|
| MED_ADMIN chemo detection: RX-typed only | RX + ND-typed via NDC crosswalk (`get_chemo_hits`) | Phase 122 (2026-07-14) | 7 consumers already fixed; R/50 is the one remaining consumer not yet updated (explicitly deferred in Phase 122's "broader audit" item) |
| DISPENSING: entirely invisible (RXNORM_CUI column never existed in this extract) | NDC + crosswalk resolution | Phase 122 | R/50 has never queried DISPENSING at all — net-new for this script |
| Supportive Care Medication names: none | RxNorm-IN + rule-based fallback, written to reference Excel col G ("Normalized Meaning") | Phase 120 (2026-07-XX) | Solves the exact regex problem Phase 131 needs, but output isn't wired into `MEDICATION_LOOKUP` |
| `MEDICATION_LOOKUP`: Chemotherapy-only real coverage | Same (unchanged since Phase 114) | Phase 114 (2026-06-24) | Confirmed still the case; Supportive Care/SCT/Immunotherapy fallback is squarely this phase's job |

**Deprecated/outdated:** None — this is additive generalization of very recent (June-July 2026) infrastructure, not a migration away from anything.

---

## Open Questions

1. **Should `MEDICATION_LOOKUP` (or a parallel lookup) be extended to read Supportive Care's existing "Normalized Meaning" column (col G, from Phase 120's R/105) instead of re-deriving the same normalization via a new fallback?**
   - What we know: R/105 already produced exactly the kind of normalized ingredient names CONTEXT.md wants, for all 171 Supportive Care RXNORM codes, cached in the reference Excel itself.
   - What's unclear: CONTEXT.md's decisions describe building a NEW fallback normalizer without mentioning col G — possibly because the discussion didn't surface this existing asset. Reusing it for Supportive Care would reduce the fallback's real-world scope to only SCT + Immunotherapy + any new NDC-resolved chemo codes lacking `MEDICATION_LOOKUP` entries.
   - Recommendation: Flag for the planner/user to confirm — extending the lookup to consume col G is arguably even more "reuse, don't reinvent" than writing a parallel fallback, but it does touch `R/00_config.R`'s `MEDICATION_LOOKUP` builder (a file the discussion didn't explicitly scope for editing, though it's listed as a "reusable asset" in CONTEXT.md's Code Context, implying edits there are in-bounds).

2. **Exact mechanism for tagging match-source (RX vs ND vs DISPENSING) through `get_chemo_hits()`.**
   - What we know: The function is shared by 5 other consumers (R/10, R/11, R/25, R/26, R/76) and must stay backward-compatible.
   - What's unclear: Whether to add a new `return_source` parameter to the shared helper (touches a file used by 5+ scripts, larger blast radius but consistent/DRY) vs. writing R/50-local logic that doesn't modify the shared helper (smaller blast radius, but duplicates some of `get_chemo_hits()`'s internal MEDADMIN_TYPE RX/ND branching just to recover the tag).
   - Recommendation: Prefer the additive-parameter approach (mirrors the proven `return_raw_name` precedent exactly), reviewed carefully against the 5 existing call sites to confirm zero behavior change when the new parameter is omitted.

3. **Exact regex boundary between "multi-ingredient compound, pass through" vs. "single ingredient with salt/dose noise, strip it".**
   - What we know: CONTEXT.md gives one clear example each way (bendamustine HCl → strip; ascorbic acid/beta carotene/... → pass through unchanged).
   - What's unclear: The precise detection rule (e.g., "count of ` / `-delimited segments > 1 in the pre-stripped description" is a reasonable heuristic, but edge cases like single ingredient names that happen to contain a slash character, or descriptions where a dose fraction like "1/2" appears, aren't addressed in CONTEXT.md).
   - Recommendation: Use presence of `" / "` (space-slash-space, matching the RxNorm STR combination-product convention seen in the actual config comments) as the compound-detection heuristic; verify against the ~27 `immunotherapy_rxnorm` and ~171 `supportive_care_rxnorm` codes' actual description text during implementation for false positives/negatives.

---

## Sources

### Primary (HIGH confidence — direct source inspection this session)
- `R/50_all_codes_resolved.R` (full 865 lines read/grepped) — confirmed no Medication column, no DISPENSING query, static per-vector `source_table`, two duplicated xlsx-writer blocks (lines 580, 765-837)
- `R/utils/utils_treatment.R` (full 280 lines read) — confirmed `get_chemo_hits()` signature/behavior, `load_ndc_crosswalk()`, `normalize_ndc()`
- `R/00_config.R` lines 2460-2640, 2782-3460 — confirmed `MEDICATION_LOOKUP` builder (column-3-by-position), `canonicalize_drug_name()`/`DRUG_NAME_ALIASES`, RXNORM vector contents/sizes and inline-comment truncation
- `R/105_normalize_supportive_care_meaning.R` (full 439 lines read) — confirmed existing "Normalized Meaning" col-G asset and `rule_based_ingredient()` regex fallback pattern
- `R/108_build_ndc_rxnorm_crosswalk.R` (confirmed lines 1-90) — confirmed crosswalk is NDC→RxCUI only, no drug names
- `R/88_smoke_test_comprehensive.R` — confirmed only a file-existence check on R/50 today (line 253); confirmed next available section letter is `15x` (sections through `15w` present)
- `R/39_run_all_investigations.R` line 237 — confirmed R/50 IS registered as a repeatable investigation script
- `.planning/phases/122-*/122-RESEARCH.md` — Phase 122's exhaustive consumer enumeration and crosswalk design, directly informing this phase's generalization
- `.planning/config.json` — confirmed `workflow.nyquist_validation: false` (Validation Architecture section omitted per instructions)
- File-system checks: `data/reference/ndc_rxnorm_crosswalk.rds` exists (137 KB, built 2026-07-20); `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` exists (595 KB); `data/reference/rxnorm_ingredient_cache.csv` does NOT exist locally (built on HiPerGator, not committed/present in this environment)
- No `CLAUDE.md` found anywhere in the repository (project-wide glob search) — project conventions inferred from code + prior research docs only

### Secondary (MEDIUM confidence)
- None used this session beyond direct source inspection — all critical claims were verifiable via grep/read against the actual files.

### Tertiary (LOW confidence)
- `chemo_rxnorm` vector size (~265 codes) — approximated via line-range grep count, not an exact `length(TREATMENT_CODES$chemo_rxnorm)` evaluation (no local Rscript available in this environment to execute R directly)

---

## Metadata

**Confidence breakdown:**
- Current R/50 architecture (no Medication column, no DISPENSING query, static source_table): HIGH — direct full-file read and grep confirmation
- Reusability of `get_chemo_hits()` / crosswalk / `MEDICATION_LOOKUP`: HIGH — direct source inspection, cross-referenced against Phase 122/114 research
- Fallback-normalizer regex approach (via `rule_based_ingredient()` adaptation): HIGH — proven, shipped code from Phase 120, directly comparable problem
- Source-tagging mechanism for `get_chemo_hits()`: MEDIUM — no existing precedent for this exact extension; recommendation follows the established `return_raw_name` additive-parameter pattern but the design itself is new for this phase
- R/88 next section letter (`15x`) and grep-based convention: HIGH — confirmed by direct scan of all `SECTION 15*` headers in R/88

**Research date:** 2026-07-22
**Valid until:** Stable (internal source-code inspection; valid until the referenced files change — no external API/library version dependencies)
