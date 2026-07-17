# Phase 131: Update all_codes_resolved_next_tables_v2.1_new.xlsx — Research

**Researched:** 2026-07-17
**Domain:** openxlsx2 in-place xlsx editing, RxNav CUI resolution, DuckDB MED_ADMIN querying
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Add rows ONLY for RxNorm CUIs that appear in MED_ADMIN (`MEDADMIN_TYPE=='RX'`) but NOT in PRESCRIBING (i.e., codes exclusive to MED_ADMIN). Existing rows with `Source Table = PRESCRIBING` are NOT modified.
- **D-02:** Source of new rows: a DuckDB query at runtime that anti-joins MED_ADMIN CUIs against PRESCRIBING CUIs for each treatment type.
- **D-03:** Scope is all applicable treatment tabs — query MED_ADMIN against each treatment type's code list and route new rows to the correct tab (Chemotherapy, Supportive Care, Immunotherapy, etc.).
- **D-04:** New rows use `Source Table = MED_ADMIN` and inherit columns appropriate to that tab (Code, Meaning, Code Type, Source Table, Records, Patients).
- **D-05:** Column name is `normalized_name` (snake_case) on ALL tabs — uniform across the workbook.
- **D-06:** Supportive Care tab: rename existing "Normalized Meaning" column header to `normalized_name`. Data values remain unchanged.
- **D-07:** For RxNorm CUI rows on any tab: apply the same RxNav ingredient lookup as R/105 (IN concept resolution with cached fallback).
- **D-08:** For non-RxNorm rows (CPT/HCPCS, ICD-10, NDC, DRG): copy the existing `Meaning` column value into `normalized_name` verbatim.
- **D-09:** Canonical filename stays `data/reference/all_codes_resolved_next_tables_v2.1.xlsx`. No R script path changes are needed.
- **D-10:** Workflow: develop/test against `v2.1_new.xlsx`, then overwrite `v2.1.xlsx` with the final result.

### Claude's Discretion

- Column position for `normalized_name`: place as the last column on each tab (appended after existing columns), consistent with how Supportive Care had "Normalized Meaning" appended as column G.
- Whether Index and Sheet1 tabs get `normalized_name`: these are summary/metadata tabs with no code rows — Claude should assess whether adding the column makes sense or skip non-code tabs.
- R/88 smoke test update: the existing check for "Normalized Meaning" (section 15r) must be updated to check for `normalized_name` — Claude decides the exact assertion update.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

## Summary

Phase 131 makes two changes to the reference xlsx workbook. First, it adds MED_ADMIN-exclusive RxNorm CUI rows to the applicable treatment tabs (Chemotherapy, Immunotherapy, Supportive Care) — these are CUIs that appeared in the real patient data from MED_ADMIN but were not captured because Phase 122's fix added them to the detection pipeline without back-filling the documentation xlsx. Second, it adds a `normalized_name` column to every code tab using the same RxNav IN resolution already implemented in R/105.

The implementation requires a DuckDB connection to the HiPerGator data to compute the MED_ADMIN-exclusive CUI anti-join, so the new script is a HiPerGator-only script (like R/105 was internet-required for its first run). The `normalized_name` column work is largely offline — all RxNorm CUIs on existing tabs can be resolved from the existing `rxnorm_ingredient_cache.csv` (if it exists on HiPerGator) or rebuilt on first run. Non-RxNorm rows (CPT/HCPCS, ICD codes, DRG, Revenue) get `Meaning` copied verbatim.

R/105 must be updated to use the column name `normalized_name` (was "Normalized Meaning"), and R/88 section 15r must be updated to assert `normalized_name` instead of the old header string. R/105's round-trip verification constant `ncol(sc) != 7` will remain correct only if the rename happens in-place without adding a column — verified below.

**Primary recommendation:** Build a single new script `R/131_update_xlsx_med_admin_and_normalized_name.R` that (1) runs the DuckDB anti-join to collect MED_ADMIN-exclusive CUIs per treatment type, (2) appends new rows to the correct tabs, (3) renames the Supportive Care header and appends `normalized_name` to all other code tabs using R/105's proven pattern, then update R/105 to write `normalized_name` instead of "Normalized Meaning" and update R/88 section 15r assertions.

---

## Verified xlsx Structure (HIGH confidence — inspected directly)

Inspected `data/reference/all_codes_resolved_next_tables_v2.1_new.xlsx` with Python/openpyxl.

### Sheet names (exact order, 8 sheets)

```
Index, Sheet1, Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, Unrelated
```

### Per-tab column layout (row 2 = header in this workbook)

| Tab | Cols | Header row (exact values) | Data rows |
|-----|------|---------------------------|-----------|
| Index | 5 | Sheet, Total codes, Needed lookup, Resolved, Unresolved RxNorm | 21 |
| Sheet1 | 3 | Chemo (column C), Cancer code(s) for the encounter, Count of encounters | 6 |
| Chemotherapy | 9 | Code, Meaning, Medication, Code Type, Source Table, Records, Patients, First line/…, SCT or Immunotherapy also? | 203 |
| Radiation | 7 | Code, Meaning, Code Type, Source Table, Records, Patients, (None) | 13 |
| SCT | 7 | Code, Meaning, Code Type, Source Table, Records, Patients, (None) | 41 |
| Immunotherapy | 7 | Code, Meaning, Code Type, Source Table, Records, Patients, (None) | 27 |
| Supportive Care | 7 | Code, Meaning, Code Type, Source Table, Records, Patients, **Normalized Meaning** | 171 |
| Unrelated | 6 | Code, Meaning, Code Type, Source Table, Records, Patients | 9866 |

**Important:** Radiation and SCT have a 7th column with `None` header (likely an empty trailing column). Planner should inspect this when determining where to append `normalized_name`.

### Code types per tab (determines normalized_name strategy)

| Tab | Code Types | Source Tables | Strategy for normalized_name |
|-----|-----------|---------------|------------------------------|
| Chemotherapy | RXNORM (108 rows), CPT/HCPCS (95 rows) | PRESCRIBING, PROCEDURES | RxNav for RXNORM; Meaning verbatim for CPT/HCPCS |
| Radiation | CPT/HCPCS only | PROCEDURES | Meaning verbatim for all rows |
| SCT | ICD-9-CM Vol3, Revenue, DATE_COLUMN, ICD-10-PCS, CPT, DRG, ICD-10-CM | TUMOR_REGISTRY, DIAGNOSIS, ENCOUNTER, PROCEDURES | Meaning verbatim for all rows |
| Immunotherapy | RXNORM (12 rows), CPT/HCPCS (16 rows) | PRESCRIBING, PROCEDURES | RxNav for RXNORM; Meaning verbatim for CPT/HCPCS |
| Supportive Care | RXNORM (171 rows) | PRESCRIBING | Already has "Normalized Meaning" — rename header only |
| Unrelated | RXNORM (9479 rows), CPT/HCPCS (387 rows) | PRESCRIBING, PROCEDURES | RxNav for RXNORM; Meaning verbatim for CPT/HCPCS |

### Non-code tabs decision

- **Index** and **Sheet1**: Summary/metadata tabs with no Code/Meaning/CodeType columns. No `normalized_name` column should be added — it would be meaningless on these tabs. Skip both.

---

## MED_ADMIN Exclusive CUI Analysis

### Which tabs get new MED_ADMIN rows

Only tabs with `RXNORM` code type and `Source Table = PRESCRIBING` can have MED_ADMIN-exclusive CUI additions (D-03). That is:

- **Chemotherapy**: 108 RXNORM rows, all PRESCRIBING
- **Immunotherapy**: 12 RXNORM rows, all PRESCRIBING
- **Supportive Care**: 171 RXNORM rows, all PRESCRIBING

**Radiation**, **SCT**, and **Unrelated** have no RXNORM rows from PRESCRIBING that map to MED_ADMIN (`MEDADMIN_TYPE=='RX'`). Radiation and SCT are CPT/ICD/DRG-coded procedures, not drug administrations. Unrelated has RXNORM rows but these represent unrelated drugs — MED_ADMIN anti-join should still be run per D-03 to be complete, but expect few or no new rows for Unrelated.

### MED_ADMIN anti-join logic

The `get_chemo_hits()` function in `R/utils/utils_treatment.R` shows the exact pattern:

```r
# MED_ADMIN RX-typed rows: MEDADMIN_CODE is RxNorm CUI directly
tbl %>%
  dplyr::filter(
    MEDADMIN_TYPE == "RX",
    MEDADMIN_CODE %in% chemo_rxnorm,
    !is.na(MEDADMIN_START_DATE)
  )
```

For the xlsx update, we need the anti-join variant: CUIs in MED_ADMIN that are NOT already in the tab's PRESCRIBING rows. The new rows need Records and Patients counts, which requires a grouped count query.

### chemo_rxnorm list size

`TREATMENT_CODES$chemo_rxnorm` in `R/00_config.R` (lines 2782–2880) contains approximately 98 RxNorm CUIs for chemotherapy. Immunotherapy codes are at lines ~3408+. The script must use these lists as the starting code universe, then anti-join against what's already in the xlsx.

### DuckDB requirement

Because the anti-join requires actual patient data (MED_ADMIN and PRESCRIBING tables), the MED_ADMIN row generation MUST run on HiPerGator with a live DuckDB connection. This is a HiPerGator-only phase. The normalized_name column work can run locally if the cache is available (it isn't locally — `rxnorm_ingredient_cache.csv` does not exist in `data/reference/` on this Windows machine).

---

## openxlsx2 In-Place Edit Pattern (HIGH confidence — from R/105)

R/105 is the canonical reference. Exact working pattern:

```r
# 1. Load workbook preserving all sheets + styles
wb <- openxlsx2::wb_load(XLSX_PATH)

# 2. Read a sheet as data frame (row 2 = header in this workbook)
df <- wb_to_df(wb, sheet = "Supportive Care", start_row = 2)

# 3. Write header to a specific cell (e.g., column G row 2)
wb$add_data(sheet = "Supportive Care", x = "normalized_name", dims = "G2")

# 4. Write data vector to cells below header (col_names = FALSE critical)
wb$add_data(sheet = "Supportive Care", x = values_vec, dims = "G3", col_names = FALSE)

# 5. Optionally widen autofilter (best-effort, tryCatch-wrapped)
tryCatch(wb$add_filter(sheet = "Supportive Care", cols = 1:7), error = function(e) NULL)

# 6. Save in place (overwrites)
openxlsx2::wb_save(wb, XLSX_PATH)

# 7. Round-trip verify with fresh wb_load
wb2 <- openxlsx2::wb_load(XLSX_PATH)
```

**Key constraints from R/105 experience:**
- Do NOT rebuild with `wb_workbook()` — this drops other sheets
- `col_names = FALSE` is required when writing a bare vector to `add_data`
- Header lives in row 2, data starts in row 3 (workbook convention: row 1 is a banner/formatting row)
- The `dims` parameter uses Excel cell notation (e.g., `"G2"`, `"G3"`)

### Column letter reference for append

After `normalized_name` append (last column):

| Tab | Existing cols | New col letter | dims header | dims data start |
|-----|--------------|---------------|-------------|-----------------|
| Chemotherapy | 9 (A–I) | J | J2 | J3 |
| Radiation | 6 real + 1 empty = 7 | col 8 = H | H2 | H3 |
| SCT | same as Radiation | H | H2 | H3 |
| Immunotherapy | 6 (A–F) | G | G2 | G3 |
| Supportive Care | 7, rename col G header only | G (rename) | G2 | — |
| Unrelated | 6 (A–F) | G | G2 | G3 |

**Note on Radiation/SCT:** The 7th column with `None` header may be column G. If so, `normalized_name` should either replace that None header or go in column H. The planner should instruct the implementer to read the actual column count via `ncol(wb_to_df(...))` at runtime and append dynamically rather than hardcoding letter positions. For Immunotherapy and Supportive Care the column count matches R/105's pattern exactly.

---

## R/105 Updates Required

R/105 currently writes `"Normalized Meaning"` as the header. After this phase:
- Line 363: `wb$add_data(sheet = SHEET, x = "Normalized Meaning", dims = "G2")` → change to `"normalized_name"`
- Line 404: `if (!("Normalized Meaning" %in% names(sc)))` → change to `"normalized_name"`
- Line 407: `nm <- sc[["Normalized Meaning"]]` → change to `sc[["normalized_name"]]`
- Round-trip check (line 404) passes because column count stays 7 — the rename does not change `ncol(sc) != 7`

---

## R/88 Smoke Test Updates Required (Section 15r)

Section 15r (lines 2414–2501) performs structural greps against the R/105 file text. Affected checks:

**Check 12** (line 2479–2482): asserts `grepl("Normalized Meaning", r105_text)`. After the rename this will FAIL. Must be changed to:
```r
check("R/105 appends normalized_name at col G (G2 header + G3 data)",
      grepl("normalized_name", r105_text) &&
        grepl("G2", r105_text) && grepl("G3", r105_text))
```

**Section 15r header comment** (line 2419, 2423): references "Normalized Meaning" — update to `normalized_name` in the comment text.

**Section 15r message** (line 2427): `message("\n[Phase 120] Supportive Care Normalized Meaning (R/105)...")` — cosmetic, update if desired.

No other R/88 sections reference "Normalized Meaning" directly (confirmed by grep). The new script `R/131_...` will need its own Section 15x block in R/88 if smoke test coverage is desired for Phase 131.

---

## Architecture Patterns

### Recommended script structure: R/131_update_xlsx_med_admin_and_normalized_name.R

```
SECTION 1: SETUP + PATHS
SECTION 2: LOAD WORKBOOK + READ ALL CODE TABS
SECTION 3: DUCKDB — MED_ADMIN EXCLUSIVE CUI ANTI-JOIN (per treatment type)
SECTION 4: APPEND NEW MED_ADMIN ROWS TO APPLICABLE TABS
SECTION 5: LOAD/BUILD RXNORM INGREDIENT CACHE (reuse R/105 functions)
SECTION 6: ASSEMBLE normalized_name VECTORS (per tab)
SECTION 7: WRITE normalized_name COLUMN TO ALL CODE TABS
  7a: Supportive Care — rename header G2 only, no new column
  7b: All other code tabs — append new last column
SECTION 8: SAVE + ROUND-TRIP VERIFY
SECTION 9: CONSOLE SUMMARY
```

### Reuse strategy

The three functions from R/105 should be sourced or copy-pasted into R/131:
- `rxnav_in_names(rxcui)` — GET related.json?tty=IN
- `rxnav_historystatus_ingredients(rxcui)` — fallback for retired CUIs
- `resolve_ingredient(rxcui, sleep_sec)` — three-step resolution

The cache loading/updating pattern (anti_join new codes, append, write_csv) is also directly reusable.

### DuckDB query pattern for MED_ADMIN anti-join

Based on `get_chemo_hits()` in `utils_treatment.R`:

```r
# Get MED_ADMIN CUIs for a treatment type with patient/record counts
med_admin_hits <- med_admin_tbl %>%
  dplyr::filter(
    MEDADMIN_TYPE == "RX",
    MEDADMIN_CODE %in% treatment_rxnorm_list
  ) %>%
  dplyr::group_by(MEDADMIN_CODE) %>%
  dplyr::summarise(
    Records  = dplyr::n(),
    Patients = dplyr::n_distinct(ID),
    .groups  = "drop"
  ) %>%
  dplyr::collect()

# Anti-join against existing xlsx tab codes
existing_codes <- tab_df$Code  # already PRESCRIBING codes
new_rows <- med_admin_hits %>%
  dplyr::filter(!MEDADMIN_CODE %in% existing_codes)
```

New rows then need `Meaning` populated from `TREATMENT_CODES` (the CUI label), `Code Type = "RXNORM"`, `Source Table = "MED_ADMIN"`.

### Getting Meaning for new MED_ADMIN rows

The new rows need a `Meaning` string. Options:
1. **RxNav `name` endpoint** — `GET /rxcui/{rxcui}/property.json?propName=RxNorm Name` returns the official CUI display name
2. **From existing PRESCRIBING rows** — if the same CUI exists on another tab, copy its Meaning (but MED_ADMIN-exclusive CUIs by definition are not on the tab)
3. **RxNav related.json** — the ingredient lookup already fetches names

The cleanest approach: use a simple RxNav `/rxcui/{rxcui}/name.json` call or `/rxcui/{rxcui}/property.json?propName=RxNorm Name` to get the display name. This can share the httr2 pattern from R/105.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| xlsx multi-sheet editing | Custom XML manipulation | `openxlsx2::wb_load` + `add_data` + `wb_save` |
| RxNorm CUI → ingredient name | Custom string parsing alone | RxNav REST API (`related.json?tty=IN`) with `rule_based_ingredient` fallback |
| Cache management | Database | `rxnorm_ingredient_cache.csv` via `readr::read_csv` + `anti_join` + `write_csv` |
| DuckDB table access | Raw DBI calls | `safe_table()` from `utils_treatment.R` via `get_pcornet_table()` |
| HTTP with retries | Custom retry loop | `httr2::req_retry(max_tries = 3)` |

---

## Common Pitfalls

### Pitfall 1: Hardcoding column letter positions
**What goes wrong:** Writing `dims = "G2"` when the tab has 9 columns (Chemotherapy) puts normalized_name in the wrong position, overwriting Patients data.
**How to avoid:** Compute the next column letter dynamically from `ncol(wb_to_df(...))` at runtime. Use openxlsx2's `int2col()` or equivalent to convert column index to letter. Never hardcode per-tab column letters.

### Pitfall 2: Forgetting the banner row
**What goes wrong:** Row 1 in this workbook is a formatting/banner row. Data starts at row 2 (header) and row 3+ (data). Writing to row 1 corrupts the visual header band.
**How to avoid:** Always `start_row = 2` when reading. Write header at `row2`, data from `row3`. This is the established pattern from R/105.

### Pitfall 3: Clobbering other sheets when saving
**What goes wrong:** Loading workbook, adding data, then rebuilding with `wb_workbook()` silently drops the 7 other sheets.
**How to avoid:** Operate on the loaded `wb` object only. Never rebuild from scratch. Always verify all 8 sheets exist in round-trip check.

### Pitfall 4: Unrelated tab has 9,866 RXNORM rows — RxNav rate limiting
**What goes wrong:** Querying RxNav for ~9,479 unique CUIs sequentially with `Sys.sleep(0.1)` between calls takes ~16 minutes minimum and risks API timeouts.
**How to avoid:** Rely heavily on the existing `rxnorm_ingredient_cache.csv` from HiPerGator (built by R/105 for Supportive Care's 171 CUIs). The Unrelated tab will have many uncached CUIs — plan for a long first run or use batch queries. Consider chunking or increasing the sleep interval. The Meaning-verbatim fallback (D-08) is available for non-RxNorm rows but Unrelated's RXNORM rows still need proper resolution per D-07.
**Warning signs:** More than ~200 `codes_to_query` items indicates a potentially slow first run.

### Pitfall 5: Normalized Meaning vs normalized_name in R/105 round-trip check
**What goes wrong:** After renaming R/105 to write `normalized_name`, the R/105 round-trip check at line 404 will fail if it still checks for `"Normalized Meaning"` in `names(sc)`.
**How to avoid:** Update R/105 line 404 and 407 simultaneously with the `add_data` header change.

### Pitfall 6: MED_ADMIN exclusive CUIs may have no RxNav Meaning
**What goes wrong:** A CUI that is MEDADMIN-exclusive might be a retired or non-standard CUI with no RxNav display name.
**How to avoid:** Build the same three-step fallback: RxNav name → historystatus → rule_based on the CUI string itself. Never leave Meaning blank in a new row.

### Pitfall 7: Radiation/SCT trailing None column
**What goes wrong:** Radiation and SCT each have a 7th column with `None` as the header (confirmed by inspection). Appending `normalized_name` to column 8 (H) when the workbook already has a column G with no header may produce unexpected visual results.
**How to avoid:** At runtime, read the actual last non-None column index. If the last column header is None/empty, use that column for `normalized_name` rather than appending a new column H.

---

## R/105 and R/88 Update Scope Summary

| File | Change | Section/Line |
|------|--------|-------------|
| `R/105_normalize_supportive_care_meaning.R` | Write `"normalized_name"` instead of `"Normalized Meaning"` | Section 6, line 363 |
| `R/105_normalize_supportive_care_meaning.R` | Round-trip check: assert `"normalized_name"` in names | Section 7, lines 404, 407 |
| `R/88_smoke_test_comprehensive.R` | Section 15r Check 12: grep for `normalized_name` not `Normalized Meaning` | Lines 2479–2482 |
| `R/88_smoke_test_comprehensive.R` | Section 15r comments: update "Normalized Meaning" → `normalized_name` | Lines 2419, 2423 |
| `R/88_smoke_test_comprehensive.R` | Add new Section 15x for Phase 131 script | After 15w (~line 3000+) |

---

## Environment Availability

| Dependency | Required By | Available Locally | Available HiPerGator | Notes |
|------------|------------|------------------|---------------------|-------|
| openxlsx2 | xlsx editing | Not in renv lib locally (renv project) | Yes (renv) | Load via renv |
| DuckDB / PCORnet CSVs | MED_ADMIN anti-join | No | Yes | HiPerGator only for Section 3 |
| rxnorm_ingredient_cache.csv | RxNorm resolution | Not present locally | Expected present | Built by R/105 on HiPerGator |
| RxNav API (internet) | New CUI resolution | Yes | Login node only | Compute nodes have no internet |
| httr2 | RxNav calls | Via renv | Yes | Available in stack |
| readr | Cache CSV read/write | Via renv | Yes | Standard stack |

**Missing dependencies with no fallback (for local run):** DuckDB / PCORnet data — MED_ADMIN row generation is HiPerGator-only.

**Missing dependencies with fallback:** `rxnorm_ingredient_cache.csv` — script will build it from scratch on first HiPerGator run (internet via login node).

---

## Open Questions

1. **Unrelated tab RxNorm resolution scale**
   - What we know: 9,479 RXNORM rows on Unrelated tab; cache has 171 entries from R/105 (Supportive Care only)
   - What's unclear: How many of the 9,479 Unrelated CUIs overlap with the Supportive Care 171? Likely some overlap but most are uncached.
   - Recommendation: Plan for a long first run (~30–60 min) or accept that `normalized_name` for Unrelated can fallback to `rule_based_ingredient(Meaning)` on first pass, with a note that cache will grow over time.

2. **Radiation/SCT None-header column**
   - What we know: Python inspection shows 7 columns with the 7th having `None` header
   - What's unclear: Is this a truly empty column, a merged cell artifact, or a stray data column?
   - Recommendation: At implementation time, print `names(wb_to_df(wb, "Radiation", start_row = 2))` and decide whether to overwrite or append.

3. **MED_ADMIN exclusive CUI count**
   - What we know: The code lists exist and get_chemo_hits() queries them correctly from MED_ADMIN
   - What's unclear: Without running the DuckDB query, we cannot know how many new rows will be added
   - Recommendation: The plan should include a discovery sub-step (print counts before writing) so the implementation can validate the scale.

---

## Sources

### Primary (HIGH confidence)
- Direct inspection of `data/reference/all_codes_resolved_next_tables_v2.1_new.xlsx` via Python/openpyxl — sheet names, column headers, row counts, code types, source tables
- `R/105_normalize_supportive_care_meaning.R` — full openxlsx2 write pattern, RxNav resolution logic, cache management
- `R/utils/utils_treatment.R` — `get_chemo_hits()` MED_ADMIN DuckDB query pattern
- `R/88_smoke_test_comprehensive.R` lines 2414–2501 — section 15r exact assertions that must be updated
- `R/00_config.R` lines 2476, 2782–2880 — REFERENCE_XLSX path, chemo_rxnorm list

### Secondary (MEDIUM confidence)
- `R/00_config.R` lines 3408+ — immunotherapy RXNORM codes (not fully read, but confirmed location)

---

## Metadata

**Confidence breakdown:**
- xlsx structure: HIGH — inspected directly with openpyxl
- openxlsx2 pattern: HIGH — taken verbatim from working R/105
- DuckDB query pattern: HIGH — taken verbatim from utils_treatment.R
- MED_ADMIN row counts: LOW — cannot query without HiPerGator connection
- Unrelated tab RxNav resolution time: MEDIUM — extrapolated from R/105 rate

**Research date:** 2026-07-17
**Valid until:** Stable reference — valid until xlsx structure changes or openxlsx2 major version bump
