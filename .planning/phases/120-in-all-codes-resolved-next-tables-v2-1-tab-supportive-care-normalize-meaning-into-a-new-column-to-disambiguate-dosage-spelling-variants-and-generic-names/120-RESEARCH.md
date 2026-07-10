# Phase 120: Normalize Supportive Care "Meaning" into a canonical-ingredient column - Research

**Researched:** 2026-07-10
**Domain:** RxNorm ingredient normalization (RxNav REST API) + in-place openxlsx2 workbook edit (R/tidyverse pipeline)
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** New column = **generic ingredient only**. Strip dose, formulation, and brand; collapse salts/esters to the base ingredient (e.g. `dexamethasone phosphate` -> `dexamethasone`). This is the RxNorm **IN** (ingredient) concept, not **PIN** (precise ingredient) — IN mapping naturally yields generic-only.
- **D-02:** **Modify the reference xlsx in place** — append the new column to the END of the Supportive Care tab in `data/reference/all_codes_resolved_next_tables_v2.1.xlsx`. RISK: 5 scripts read this workbook (R/36, R/55, R/56, R/57, R/58); planner MUST confirm no reader breaks on an extra trailing column.
- **D-03:** **RxNorm ingredient mapping via the RxNav REST API**, cached. Call RxNav (`RXCUI -> IN ingredient`) once, write results to a bundled cache CSV in `data/reference/` so subsequent runs are fully offline. First run needs internet (login node / local box — NOT a compute node).
- **D-04:** **Fallback = rule-based parse** when RxNav can't resolve a code: strip dose tokens (numbers + MG/ML/units), formulation words (Oral Tablet, Injection, Prefilled Syringe, Disintegrating...), and leading "N ML" prefixes; apply a brand->generic alias map. Every row gets a best-effort normalized value — never left blank.
- **D-05:** **Brand -> generic** (e.g. `Zofran` -> `ondansetron`). For multi-ingredient **combination products, keep a combined label** (e.g. `netupitant/palonosetron`) rather than dropping one ingredient — flagged, not silently split.
- **D-06:** New column header = **`Normalized Meaning`** (mirrors the existing `Meaning` column).

### Claude's Discretion
- Exact list of formulation/dose stop-words and the brand->generic alias entries (planner/executor build from the actual 171 Supportive Care rows — this research supplies the complete list below).
- Cache-file name/format for the RxNav lookup (suggested `data/reference/rxnorm_ingredient_cache.csv`).
- Whether to reuse/extend the existing `canonicalize_drug_name()` machinery vs a new helper for the rule-based fallback — reuse preferred if it fits.

### Deferred Ideas (OUT OF SCOPE)
- Normalizing the Meaning column on the OTHER tabs (Chemotherapy, Radiation, SCT, Immunotherapy, Unrelated) — same technique, separate phases if wanted.
- Per-ingredient rollup summary tables (records/patients aggregated by Normalized Meaning) — a natural next step once the column exists, but a new capability beyond "add the column."
</user_constraints>

<phase_requirements>
## Phase Requirements

No requirement IDs exist in the roadmap yet. Recommended IDs for the planner to assign (NHL-style / normalization convention consistent with prior phases):

| ID | Description | Research Support |
|----|-------------|------------------|
| SUPCARE-01 | Resolve each Supportive Care RXNORM code to its RxNorm IN ingredient via RxNav, cached to `data/reference/rxnorm_ingredient_cache.csv` | RxNav `related.json?tty=IN` verified live (Standard Stack, Code Examples); R/27 already has httr2 lookup infra to extend |
| SUPCARE-02 | Salts/esters collapse to base ingredient (dexamethasone phosphate -> dexamethasone); biosimilars collapse to base (filgrastim-sndz -> filgrastim) | Verified live: rxcui 1116927 -> `dexamethasone`; 1605074 -> `filgrastim` (Code Examples) |
| SUPCARE-03 | Combination products keep a sorted, "/"-joined combined ingredient label; never silently drop an ingredient | Verified live: rxcui 403908 -> ciprofloxacin+dexamethasone; 309679 -> dexamethasone+neomycin+polymyxin B (Pitfall 3) |
| SUPCARE-04 | Rule-based fallback (strip dose/formulation tokens + brand->generic alias) fills any row RxNav cannot resolve; every one of the 171 rows gets a non-blank value | Complete stop-word + brand-alias lists derived from the 171 rows (Don't Hand-Roll, Code Examples) |
| SUPCARE-05 | Append `Normalized Meaning` as a trailing column (G) to the Supportive Care tab in place, preserving the other 7 sheets, the row-1 title banner, styles, and the row-2 autofilter | openxlsx2 round-trip risk analysis + widen-filter guidance (Architecture, Pitfall 1, Open Q1) |
| SMOKE-120-01 | R/88 Section 15r validates Phase 120 structural integrity | Registration precedent: 15q is the current last suffix -> 15r (Registration Pattern) |
</phase_requirements>

## Summary

This phase adds one column (`Normalized Meaning`, header col G) to the Supportive Care tab of `data/reference/all_codes_resolved_next_tables_v2.1.xlsx`. The tab holds **171 rows, all of code type RXNORM** (verified by direct XML inspection of the workbook), so the "skip non-RXNORM rows" concern is moot for this tab — but a code-type guard should still be written for robustness. The workbook has **8 sheets** in order: `Index, Sheet1, Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, Unrelated`. The Supportive Care sheet has a merged row-1 title banner ("Supportive Care — 171 codes"), a row-2 header (`Code | Meaning | Code Type | Source Table | Records | Patients`), and 171 data rows (A3:F173), with a frozen pane at row 2 and an autofilter defined name `'Supportive Care'!$A$2:$F$173`.

The project **already has production RxNav infrastructure** in `R/27_drug_name_resolution.R` (httr2 with retry/backoff, a caching pattern, and a `historystatus.json` fallback for retired RxCUIs). R/27 uses the `/properties.json` endpoint which returns the full clinical name — this phase needs the **`/related.json?tty=IN` endpoint** to get the generic ingredient (D-01). I verified live against RxNav that this endpoint correctly collapses salts (dexamethasone phosphate -> `dexamethasone`), biosimilars (filgrastim-sndz -> `filgrastim`), and packs (TaperDex pack -> `dexamethasone`), and returns multiple IN concepts for combination products (ciprofloxacin/dexamethasone). A **critical wrinkle**: several bare-ingredient RxCUIs in the tab (e.g. 104896, 104897) are **retired** and return an empty `{}` from properties and an empty IN group — they must be recovered via `historystatus.json` -> `derivedConcepts.ingredientConcept[].ingredientName` (also verified live: 104896 -> `ondansetron`, remapped ingredient rxcui 26225). This three-step resolution (related IN -> historystatus derived ingredient -> rule-based fallback) guarantees D-04's "every row gets a value."

The main implementation risk is **D-02's in-place edit**. openxlsx2's `wb_load()` round-trip preserves other sheets, data, and most styling, but the append must (a) widen the row-2 header, (b) style the new header cell to match, (c) write 171 data values, and (d) ideally extend the autofilter/dimension to column G. Reader-script analysis shows appending a trailing column to Supportive Care is **safe for all 5 readers**: R/55 reads by column name (`str_detect(..., "code"/"meaning")`) across all sheets, and R/36/56/57/58 only read the Chemotherapy/Radiation/SCT sheets (never Supportive Care) by positional index.

**Primary recommendation:** Create `R/105_normalize_supportive_care_meaning.R`. Extend R/27's httr2 lookup functions to call `/related.json?tty=IN` (with `historystatus.json` -> derivedConcepts fallback), cache to `data/reference/rxnorm_ingredient_cache.csv`, apply an extended `canonicalize_drug_name()`-style rule-based fallback for misses, then edit the workbook in place with `openxlsx2::wb_load()` -> `wb_add_data(dims="G2")` header + `dims="G3"` data -> widen autofilter to G -> `wb_save()`. Register in R/39, add R/88 Section 15r, and add a SCRIPT_INDEX 100+ row (count 5 -> 6, Total 91 -> 92).

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| httr2 | (already installed; used by R/27) | RxNav REST calls with retry/backoff | R/27 already builds `request() %>% req_timeout() %>% req_retry() %>% req_perform()`; reuse verbatim |
| openxlsx2 | (already installed; R/55, R/56, R/57, R/58, R/100) | Read + in-place write of the .xlsx | The established workbook tool; `wb_load()` round-trips the whole workbook |
| dplyr / stringr / glue / purrr | tidyverse 2.0.0+ | Row transforms, token stripping, logging | Project standard; named predicates; no data.table (CLAUDE.md) |
| tibble | 3.2.1+ | Cache table + lookup joins | tidyverse default |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| jsonlite (via `httr2::resp_body_json`) | bundled with httr2 | Parse RxNav JSON | Already the R/27 pattern (`resp_body_json(resp)`) |
| checkmate | (R/55 pattern) | Input file/column assertions | `assert_file_exists(XLSX_PATH)`, assert 171 rows / RXNORM |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `related.json?tty=IN` | `properties.json` (R/27's choice) | properties returns the full clinical NAME (dose+form), NOT the IN — wrong for D-01 |
| RxNav REST | local RxNorm RRF files | RRF requires a UMLS license + large download; REST is public/no-key and already wired |
| openxlsx2 `wb_load` round-trip | rebuild the whole workbook with `wb_workbook()` (R/100 style) | Rebuilding would drop the other 7 sheets' Excel-native formatting/filters unless every sheet is re-authored — far more work and risk. `wb_load` is correct for a single-sheet in-place edit |
| openxlsx2 | writexl / readxl+writexl | writexl cannot preserve an existing multi-sheet workbook's styling; wrong tool for in-place |

**Installation:** No new packages. All of httr2, openxlsx2, tidyverse, checkmate are already used in the repo. First RxNav run requires internet (login node or local box, NOT a compute node); thereafter the committed cache CSV makes runs fully offline.

**Version verification note:** R ecosystem is not in Context7 (per CLAUDE.md). Versions confirmed against the repo's existing working scripts (R/27, R/55, R/100) rather than a fresh registry query — these are the versions the pipeline already runs against on HiPerGator R/4.4.2+.

## Architecture Patterns

### Recommended Script Structure (`R/105_normalize_supportive_care_meaning.R`)
```
SECTION 1  Setup: libraries (dplyr, stringr, glue, purrr, httr2, openxlsx2, checkmate),
           source("R/00_config.R"); define XLSX_PATH, SHEET = "Supportive Care",
           CACHE_CSV = "data/reference/rxnorm_ingredient_cache.csv"
SECTION 2  Read Supportive Care sheet: wb <- wb_load(XLSX_PATH);
           df <- wb_to_df(wb, sheet = SHEET, start_row = 2)  # 171 rows, cols Code..Patients
           assert nrow == 171; assert all Code Type == "RXNORM" (guard/flag any non-RXNORM)
SECTION 3  RxNav IN resolution (cached):
           - load CACHE_CSV if present; anti_join to find codes_to_query
           - for each RXCUI: resolve_ingredient() (related IN -> historystatus derived -> NA)
           - append new results to cache; write CACHE_CSV
SECTION 4  Rule-based fallback (D-04) for NA/combo edge cases:
           extend/reuse canonicalize_drug_name(): strip dose+form tokens, brand->generic alias
SECTION 5  Assemble Normalized Meaning per row (never blank); combos = sorted "/"-join
SECTION 6  In-place write: wb_add_data(wb, SHEET, x="Normalized Meaning", dims="G2");
           wb_add_data(wb, SHEET, x=norm_vec, dims="G3", col_names=FALSE);
           (widen autofilter/dimension to col G); wb_save(wb, XLSX_PATH)
SECTION 7  Console summary: n resolved via IN / via historystatus / via fallback; combos flagged
```

### Pattern 1: Three-step RxNorm IN resolution (guarantees a value)
**What:** Resolve RXCUI -> ingredient with graceful degradation.
**When:** Every RXNORM code in the tab.
```r
# Source: verified live against https://rxnav.nlm.nih.gov (2026-07-10)
resolve_ingredient <- function(rxcui, sleep_sec = 0.1) {
  # Step 1: related.json?tty=IN  (active concepts, salts/biosimilars/packs collapse to base)
  ins <- rxnav_in_names(rxcui)                     # character() if empty
  if (length(ins) == 0) {
    Sys.sleep(sleep_sec)
    ins <- rxnav_historystatus_ingredients(rxcui)  # retired codes -> derivedConcepts
  }
  Sys.sleep(sleep_sec)
  if (length(ins) == 0) return(list(name = NA_character_, source = "api_miss"))
  if (length(ins) == 1) return(list(name = ins,                              source = "rxnav_IN"))
  list(name = paste(sort(unique(ins)), collapse = "/"), source = "rxnav_IN_combo")  # D-05
}
```
Reuse R/27's `request() %>% req_timeout(10) %>% req_retry(max_tries=3, is_transient = ~ resp_status(.x) %in% c(429,503,504)) %>% req_perform()` wrapper verbatim inside `rxnav_in_names()` / `rxnav_historystatus_ingredients()`.

### Pattern 2: In-place single-sheet append (openxlsx2 round-trip)
**What:** Load the whole workbook, touch only Supportive Care, save back.
**When:** D-02 in-place edit.
```r
# Source: openxlsx2 wb_load/wb_add_data/wb_save; pattern adapted from R/55 (wb_load) + R/100 (wb_add_data dims)
wb <- openxlsx2::wb_load(XLSX_PATH)                          # preserves all 8 sheets + styles
wb$add_data(sheet = "Supportive Care", x = "Normalized Meaning", dims = "G2")
wb$add_data(sheet = "Supportive Care", x = normalized_vec,   dims = "G3", col_names = FALSE)
# match header style of F2 and widen the autofilter to include G (see Pitfall 1 / Open Q1)
openxlsx2::wb_save(wb, XLSX_PATH)                            # overwrite in place (D-02)
```

### Anti-Patterns to Avoid
- **Rebuilding the workbook with `wb_workbook()` (R/100 style).** That is for *new* outputs. For an in-place edit it would drop the other 7 sheets unless every one is re-authored — do NOT do this. Use `wb_load()`.
- **Using `properties.json` for the ingredient.** It returns the full dose+form clinical name (R/27's use case), not the IN. Wrong for D-01.
- **Trusting RxNav's IN ordering for combos.** The API returns ingredients in an unspecified order; always `sort()` before joining so the combined label is deterministic across reruns.
- **data.table syntax** (CLAUDE.md anti-pattern #1) — keep the transform in dplyr/stringr.
- **`setwd()` / absolute paths** (CLAUDE.md anti-pattern #2) — use the repo-relative `data/reference/...` path as the other scripts do.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Salt/ester -> base ingredient | A hand-maintained salt map | RxNav `related.json?tty=IN` | Verified: dexamethasone phosphate/sodium phosphate all -> `dexamethasone` automatically |
| Biosimilar suffix stripping (-sndz, -aafi, -jmdb, -apgf, -cbqv, -bmez, -ayow, -epbx, tbo-) | Regex to strip suffixes | RxNav IN | Verified: filgrastim-sndz -> `filgrastim`; RxNorm already models biosimilar->base |
| Retired-code name recovery | Skipping/blanking retired RxCUIs | `historystatus.json` -> `derivedConcepts.ingredientConcept` | Verified: 104896 (retired SBD) -> `ondansetron`; R/27 already has the historystatus call |
| HTTP retry/backoff/throttle | Manual loop + `tryCatch` | R/27's `req_retry()` wrapper + `Sys.sleep(0.1)` | Already built, handles 429/503/504 |
| Cached lookup / re-query only new codes | Fresh API hit every run | R/27's cache + `anti_join` pattern | Already the D-09 pattern in R/27 |

**Key insight:** RxNav's IN concept does ~90% of D-01/D-02/D-05 work automatically (salts, biosimilars, packs, combos). The rule-based fallback (D-04) is only a safety net for API misses and the handful of retired/free-text-name rows — it should reuse and extend `canonicalize_drug_name()` (R/00_config.R ~L2377-2398) rather than being a second normalizer.

### Rule-based fallback inputs (built from the actual 171 rows)

**Dose/formulation stop-words + patterns to strip (D-04):**
- Leading quantity prefixes: `^\d+(\.\d+)?\s+(ML|HR)\s+` (e.g. "1 ML", "2 ML", "18 ML", "168 HR", "0.6 ML").
- Pack wrappers: strip `^\{.*\}\s*` and inner `\d+\s*\(...\)` (e.g. `{21 (dexamethasone 1.5 MG Oral Tablet) } Pack`).
- Brand brackets: strip `\s*\[[^\]]*\]` (e.g. `[Decadron]`, `[Neulasta]`, `[Emend]`, `[Zarxio]`).
- Dose units: `MG`, `MCG`, `ML`, `MG/ML`, `MCG/ML`, `UNT/ML`, `UNT/MG`, `MG/MG`, `MG/HR`, numbers, `%`, `(Base Equivalent)`.
- Formulation words: `Oral Tablet`, `Disintegrating`, `Oral Capsule`, `Oral Solution`, `Oral Film`, `Injectable Solution`, `Injection`, `Injection Solution`, `Inj`, `Prefilled Syringe`, `Ophthalmic Solution/Suspension/Ointment/Ophth Oint`, `Otic Suspension`, `Transdermal System`, `Pack`, `Soln`, `IV`.
- Salt words (fallback only; RxNav already handles these): `phosphate`, `sodium phosphate`, `HCl`, `hydrochloride`.

**Brand -> generic alias entries needed (from `[Brand]` tags + free-text rows in the 171):**
| Brand seen in rows | Generic |
|---|---|
| Zofran, Zuplenz | ondansetron |
| Decadron, DexPak, TaperDex, TaperPak, Baycadron | dexamethasone |
| Emend, Cinvanti | aprepitant (Emend Injection / fosaprepitant -> keep as fosaprepitant where the code is fosaprepitant) |
| Neulasta, Fulphila, Udenyca, Ziextenzo, Nyvepria | pegfilgrastim |
| Neupogen, Zarxio, Nivestym, Granix | filgrastim |
| Procrit, Retacrit | epoetin alfa |
| Aranesp | darbepoetin alfa |
| Maxitrol, Maxidex, AK-Trol, Poly-Dex | (dexamethasone-containing combo — prefer RxNav combo label) |
| Ciprodex | ciprofloxacin/dexamethasone (combo) |
| Tobradex | dexamethasone/tobramycin (combo) |

**Full ingredient set present in the 171 rows (the "answer key" for validation):**
`ondansetron, dexamethasone, filgrastim, pegfilgrastim, epoetin alfa, darbepoetin alfa, aprepitant, fosaprepitant, palonosetron, granisetron, raloxifene` (single agents) plus combos:
`ciprofloxacin/dexamethasone, dexamethasone/neomycin/polymyxin B, dexamethasone/neomycin/polymyxin B (Ophthalmic), dexamethasone/tobramycin`.
(Note: `raloxifene hydrochloride 60 MG Oral Tablet` -> `raloxifene`; it is the lone SERM in the tab.)

## Code Examples

Verified live against RxNav on 2026-07-10 (see Sources).

### Salt collapse (D-01) — dexamethasone phosphate -> dexamethasone
```
GET https://rxnav.nlm.nih.gov/REST/rxcui/1116927/related.json?tty=IN
-> conceptGroup[tty=IN].conceptProperties = [{ rxcui:"3264", name:"dexamethasone" }]
```

### Combination product (D-05) — keep BOTH ingredients
```
GET https://rxnav.nlm.nih.gov/REST/rxcui/403908/related.json?tty=IN
-> IN concepts = ["ciprofloxacin","dexamethasone"]   # -> label "ciprofloxacin/dexamethasone" (sorted, "/"-join)
GET https://rxnav.nlm.nih.gov/REST/rxcui/309679/related.json?tty=IN
-> IN concepts = ["dexamethasone","neomycin","polymyxin B"]  # 3-ingredient combo, all kept
```

### Biosimilar collapse — filgrastim-sndz -> filgrastim
```
GET https://rxnav.nlm.nih.gov/REST/rxcui/1605074/related.json?tty=IN
-> [{ rxcui:"68442", name:"filgrastim" }]
```

### Pack wrapper — TaperDex pack -> dexamethasone
```
GET https://rxnav.nlm.nih.gov/REST/rxcui/1998482/related.json?tty=IN
-> [{ rxcui:"3264", name:"dexamethasone" }]
```

### Retired-code fallback (empty IN) — 104896 recovered via historystatus
```
GET https://rxnav.nlm.nih.gov/REST/rxcui/104896/related.json?tty=IN
-> { conceptGroup:[{ tty:"IN" }] }              # EMPTY — no conceptProperties
GET https://rxnav.nlm.nih.gov/REST/rxcui/104896/properties.json
-> {}                                            # retired: properties empty too
GET https://rxnav.nlm.nih.gov/REST/rxcui/104896/historystatus.json
-> attributes.name = "ondansetron 8 MG Oral Tablet [Zofran]" (tty SBD, retired)
   derivedConcepts.ingredientConcept = [{ ingredientRxcui:"26225", ingredientName:"ondansetron" }]
# => resolve to "ondansetron"
```

### R/27 httr2 wrapper to reuse (already in repo)
```r
# Source: R/27_drug_name_resolution.R L114-153 — reuse the request/retry/parse shape
resp <- request(url) %>%
  req_timeout(10) %>%
  req_retry(max_tries = 3, is_transient = ~ resp_status(.x) %in% c(429, 503, 504)) %>%
  req_perform()
data <- resp_body_json(resp)
```

### Suggested cache CSV schema (`data/reference/rxnorm_ingredient_cache.csv`)
```
rxcui,ingredient_name,source,resolved_at
3264,dexamethasone,rxnav_IN,2026-07-10
1116927,dexamethasone,rxnav_IN,2026-07-10
403908,ciprofloxacin/dexamethasone,rxnav_IN_combo,2026-07-10
104896,ondansetron,rxnav_historystatus,2026-07-10
<free-text-only row>,<value>,rule_fallback,2026-07-10
```
`source` values: `rxnav_IN`, `rxnav_IN_combo`, `rxnav_historystatus`, `rule_fallback`, `api_miss` — enables the console/validation breakdown.

## Runtime State Inventory

> This is a data-append phase, not a rename/refactor. Included for completeness because D-02 mutates a bundled artifact.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | The reference workbook `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` itself is mutated in place (D-02). New cache CSV `data/reference/rxnorm_ingredient_cache.csv` created. | Both files are aggregate ingredient/code reference data (NO PHI); safe to commit (see Open Q2). Git will show the .xlsx as modified. |
| Live service config | None — no external service stores this string. | None. |
| OS-registered state | None. | None. |
| Secrets/env vars | None — RxNav is a public, no-key API. | None. |
| Build artifacts | None — no compiled package; script is sourced. R/27's existing RDS cache (`cache/outputs/drug_name_lookup.rds`) is a DIFFERENT cache (chemo full-names) and is NOT touched. | None — keep the new cache separate. |

**Nothing found in 4 of 5 categories** — verified: RxNav needs no key (tested unauthenticated), no service/OS/secret coupling. The only "state" is the two files under `data/reference/`.

## Common Pitfalls

### Pitfall 1: openxlsx2 in-place round-trip and the stale autofilter/dimension
**What goes wrong:** After appending column G, the sheet's `<dimension ref="A1:F173">` and the autofilter defined name `'Supportive Care'!$A$2:$F$173` still say "F". Excel may not extend the filter dropdown to the new column, and some strict readers key off `dimension`.
**Why it happens:** `wb_add_data` writes the cell but does not automatically widen the sheet dimension or the workbook-scoped `_FilterDatabase` defined name.
**How to avoid:** After writing, extend the filter/dimension to column G. openxlsx2 exposes `wb_set_dims` / `wb$set_sheetview` and can re-set the autofilter via `wb$add_filter(sheet="Supportive Care", cols=1:7)` (or `wb$remove_filter()` then re-add over A2:G173). Verify in the R/88 smoke test that reading the saved file back gives 7 columns and 171 data rows on Supportive Care. **This is the single highest-risk step — the planner should make "round-trip preserves the other 7 sheets + row-1 banner + reads back as 7 cols x 171 rows" an explicit verification task.**
**Warning signs:** Reopened file shows the filter arrow only on A-F; `wb_to_df(..., start_row=2)` returns 6 columns not 7; other sheets lost merged banners.

### Pitfall 2: `wb_add_data` overwrites header style / row-1 banner alignment
**What goes wrong:** New G2 header appears unstyled (no bold/fill) next to the styled F2 header, or the merged A1:F1 banner does not visually extend.
**Why it happens:** `add_data` writes value only; style must be copied. The banner merge is A1:F1 (6 cols) — it will NOT auto-extend to G1.
**How to avoid:** Copy F2's style to G2 (`wb$add_font`/`wb$add_fill` matching the existing dark-header style, per R/100's `add_styled_sheet`), and decide whether to re-merge the title banner to A1:G1 (cosmetic; acceptable to leave at F1 since D-06 only asks for the column). Document the choice.
**Warning signs:** Visual mismatch in the header row; banner ends before the new column.

### Pitfall 3: combination products silently reduced to one ingredient
**What goes wrong:** Taking `conceptProperties[[1]]$name` drops the second/third ingredient (violates D-05).
**Why it happens:** IN group can contain 2-3 concepts for combos (verified: ciprofloxacin/dexamethasone; dexamethasone/neomycin/polymyxin B).
**How to avoid:** Always collect ALL `conceptProperties[].name`, `sort()`, and `paste(collapse="/")`; tag `source = "rxnav_IN_combo"` so combos are auditable.
**Warning signs:** A combo row's Normalized Meaning is a single ingredient; combo count in the summary is 0.

### Pitfall 4: retired RxCUIs return empty and get blanked
**What goes wrong:** `related.json?tty=IN` returns `{"tty":"IN"}` with no conceptProperties AND `properties.json` returns `{}` — code left NA, violating D-04 "never blank."
**Why it happens:** Some tab RxCUIs are obsolete (e.g. 104896, 104897) — RxNav prunes them from active relations.
**How to avoid:** Chain to `historystatus.json` -> `derivedConcepts.ingredientConcept[].ingredientName` (verified to recover `ondansetron`), then rule-based fallback, then only NA -> which the fallback string-parse of the Meaning text must still fill.
**Warning signs:** any `source == "api_miss"` in the cache with a blank Normalized Meaning after fallback.

### Pitfall 5: assuming non-RXNORM rows exist to skip
**What goes wrong:** Writing complex code-type branching that never fires.
**Why it happens:** The phase description hedges on code type.
**How to avoid:** Direct inspection confirms **all 171 rows are Code Type == "RXNORM"**. Write a simple guard/assert (`assert all == "RXNORM"`, message any exception) rather than a branch; if a future non-RXNORM row appears, route it straight to the rule-based fallback.
**Warning signs:** none expected; guard is defensive.

### Pitfall 6: RxNav rate limiting
**What goes wrong:** HTTP 429 on rapid calls.
**Why it happens:** NLM asks callers to stay under ~20 requests/second.
**How to avoid:** R/27 already sleeps `0.1s` between calls (~10 req/s) and retries 429/503/504. With only ~171 unique codes (and cached after first run) total runtime is well under a minute. Keep the 0.1s sleep.
**Warning signs:** `lookup_status`/`source` shows repeated 429s.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| R/27 `/properties.json` -> full clinical name, then regex-strip to ingredient (`normalize_rxnorm_drug_name`) | RxNav `/related.json?tty=IN` -> ingredient directly | This phase | Eliminates the brittle regex ingredient-extraction; RxNorm's own IN mapping handles salts/biosimilars/packs |
| Manual brand/salt alias lists as the primary normalizer | RxNav IN as primary, `canonicalize_drug_name()` as fallback only | This phase | Alias list shrinks to a safety net; RxNorm is authoritative |

**Deprecated/outdated:** none for this phase. The R/27 `normalize_rxnorm_drug_name()` regex approach is NOT deprecated (it still serves R/27's chemo full-name use case) — it is simply the wrong tool for generic-only IN mapping, so this phase does not reuse it.

## Registration Pattern (verified against current repo state)

- **New script number:** `R/104` is the highest existing 100+ script -> create **`R/105_normalize_supportive_care_meaning.R`**.
- **R/39_run_all_investigations.R** — add `"R/105_normalize_supportive_care_meaning.R"` to the `investigation_scripts` vector (L176-194 block). Note the file's quirk: the LAST entry has no trailing comma (currently `R/104...`), so add the comma to the current last line and make R/105 the new final comma-less entry, OR insert R/105 before R/104 — match whatever keeps the vector parsing (the file added R/104 as the final comma-less entry).
- **R/88_smoke_test_comprehensive.R** — current last section suffix is **15q** (Gantt entire history, L2327). Add **Section 15r** for Phase 120 (structural checks: R/105 exists, sources 00_config, reads the Supportive Care sheet, calls `related.json?tty=IN`, has historystatus fallback, writes cache CSV, appends `Normalized Meaning`, no ggplot). Add a `SMOKE-120-01` summary message in the Section-16 summary block (~L3983, after the SMOKE-i1e-01 line). Note: R/88 uses local structural `check()`s that don't need HiPerGator data (nyquist validation is OFF, see below) — a runtime check that re-reads the saved xlsx and asserts 7 cols x 171 rows on Supportive Care is possible LOCALLY since the workbook is repo-bundled.
- **R/SCRIPT_INDEX.md** — add an `R/105_...` row to the "Post-Renumber Investigations (100+)" table (L140-150); bump the 100+ count **5 -> 6** (L203) and **Total 91 -> 92** (L206).

## Open Questions

1. **Does openxlsx2 `wb_load()` round-trip preserve the other 7 sheets' Excel-native formatting, and does the autofilter/dimension need manual widening?**
   - What we know: `wb_load()` reads the full workbook object (R/55 does exactly this and iterates all sheets). Writing to one sheet with `wb_add_data(dims=...)` and `wb_save()` preserves untouched sheets in practice. The autofilter is a workbook-scoped defined name (`'Supportive Care'!$A$2:$F$173`) and the sheet `dimension` is `A1:F173` — neither auto-extends to G.
   - What's unclear: whether the specific styles in THIS Excel-authored file (merged banners, frozen panes, filters, theme) survive a save byte-for-byte. openxlsx2 generally preserves styles it understands but can normalize/rewrite parts of the XML.
   - Recommendation: Make this an explicit, LOCAL verification task — after `wb_save`, reopen with a fresh `wb_load` and assert: (a) 8 sheets still present in the same order, (b) Supportive Care reads as 7 columns x 171 data rows via `wb_to_df(start_row=2)`, (c) row-1 title banner text intact, (d) other sheets' row counts unchanged (Chemo A2:G205, Radiation A2:F14, SCT A2:F43, Immuno A2:F29, Unrelated A2:F9868 per the filter defined-names). Explicitly widen the filter/dimension to G (`wb$add_filter(cols=1:7)` or re-set the defined name). **Safety net:** keep a git copy of the original .xlsx (it's committed) so a bad write is trivially revertible; do NOT delete/overwrite without the git baseline.

2. **Is the RxNav cache (and the mutated .xlsx) safe to commit?**
   - What we know: The cache is aggregate RxCUI -> ingredient-name reference data (public RxNorm concepts). The workbook holds code-level Records/Patients counts (already committed in the repo). Neither contains patient identifiers. This is unlike the Gantt PHI files.
   - Recommendation: YES — commit both `data/reference/rxnorm_ingredient_cache.csv` and the modified workbook (D-02/D-03 intend the cache to be bundled for offline reruns). Confirm no small-cell HIPAA concern in the existing Records/Patients columns is worsened (this phase adds no counts, only a name column), so no new suppression is needed.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| RxNav REST API (`rxnav.nlm.nih.gov`) | SUPCARE-01/02/03 first run | Yes (verified live 2026-07-10, no key) | public | After first run, committed cache CSV -> fully offline |
| httr2 | RxNav calls | Yes (used by R/27) | repo-installed | — |
| openxlsx2 | in-place xlsx edit | Yes (R/55/56/57/58/100) | repo-installed | — |
| Internet on run host | first RxNav run only | Login node / local box: yes; compute node: NO | — | Run first pass locally/login node; commit cache; compute-node reruns use cache |
| The target workbook | all | Yes, repo-bundled (`data/reference/...v2.1.xlsx`, 595 KB, 8 sheets) | v2.1 | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** internet on a HiPerGator *compute* node — mitigated by running the RxNav pass on a login node / local box first and committing the cache (D-03).

## Sources

### Primary (HIGH confidence)
- **RxNav REST API — live verification (2026-07-10):** `related.json?tty=IN` for rxcui 1116927 (dexamethasone phosphate->dexamethasone), 403908 (combo->ciprofloxacin+dexamethasone), 309679 (3-ingredient combo), 1605074 (filgrastim-sndz->filgrastim), 1998482 (TaperDex pack->dexamethasone), 3264 (IN self), 104896/104897 (retired->empty), and `historystatus.json` for 104896 (derivedConcepts->ondansetron / 26225). https://rxnav.nlm.nih.gov/REST/
- **Target workbook direct XML inspection:** `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` — 8 sheets (Index, Sheet1, Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, Unrelated); Supportive Care sheet7.xml dimension A1:F173, row-1 merged banner (sharedString 520 "Supportive Care — 171 codes"), row-2 headers (Code/Meaning/Code Type/Source Table/Records/Patients), autofilter `'Supportive Care'!$A$2:$F$173`; all 171 rows Code Type == RXNORM; full 171 Meaning-value inventory extracted.
- **R/27_drug_name_resolution.R** — existing httr2 RxNav infra (properties + historystatus, retry/backoff, cache/anti_join pattern) to reuse.
- **R/55_verify_replaced_by_codes.R** — reads ALL sheets incl. Supportive Care via `wb_to_df(start_row=2)`, resolves Code/Meaning columns by NAME (safe with trailing column).
- **R/36/56/57/58** — read only Chemotherapy/Radiation/SCT sheets (never Supportive Care) by positional index; unaffected by a new Supportive Care column.
- **R/100_ruca_rurality_summary.R** — openxlsx2 `add_data(dims=...)` / styling / `wb_save` patterns.
- **R/39, R/88, R/SCRIPT_INDEX.md** — current registration state (R/104 last script, R/88 last section 15q, SCRIPT_INDEX 100+ count 5 / Total 91).
- **CLAUDE.md** — R/tidyverse stack, named predicates, no data.table, no setwd, here()/repo-relative paths.

### Secondary (MEDIUM confidence)
- NLM RxNav usage guidance: stay under ~20 req/s (reflected in R/27's 0.1s sleep + 429 retry). Not re-fetched live this session; consistent with prior project practice.

### Tertiary (LOW confidence)
- openxlsx2 exact style/XML byte-preservation on round-trip of this specific Excel-authored file — inferred from the API's documented behavior and R/55's successful `wb_load`, but not empirically saved-and-diffed this session. Flagged as Open Question 1 for a LOCAL verification task.

## Metadata

**Confidence breakdown:**
- RxNav IN resolution (salts/combos/biosimilars/packs/retired): **HIGH** — verified live against the API with the actual RxCUIs from the tab.
- Workbook structure & reader compatibility: **HIGH** — direct XML inspection + reader-script code review.
- openxlsx2 in-place round-trip fidelity: **MEDIUM** — API behavior is known and R/55 loads the file fine, but a save-and-reopen was not empirically executed this session (git baseline + a local verify task mitigate).
- Rule-based fallback stop-words/aliases: **HIGH** — derived from the full 171-row inventory, not guessed.
- Registration pattern: **HIGH** — verified against current R/39, R/88, SCRIPT_INDEX.

**Validation Architecture:** OMITTED — `.planning/config.json` sets `workflow.nyquist_validation: false`. (Concrete structural + runtime checks are instead folded into the R/88 Section 15r guidance and Open Question 1's local verification task, per the phase's build-and-verify-locally note.)

**Research date:** 2026-07-10
**Valid until:** ~2026-08-09 (30 days; RxNav is stable, workbook is static). RxCUI status can change (codes retire), but the cache-once model insulates reruns.
