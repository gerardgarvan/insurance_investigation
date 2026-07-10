# Phase 120: Normalize Supportive Care "Meaning" into a canonical column - Context

**Gathered:** 2026-07-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Add ONE new column to the **Supportive Care** tab (171 RXNORM codes) of
`data/reference/all_codes_resolved_next_tables_v2.1.xlsx`. The column holds a
**canonical generic-ingredient name** so that rows which are really the same drug —
differing only by dose, formulation/spelling, or brand — collapse to a single value.

Example (existing "Meaning" → new "Normalized Meaning"):
- `ondansetron 8 MG Oral Tablet`, `ondansetron injection`, `Zofran 4 mg oral tablet`, bare `ondansetron` → **`ondansetron`**
- `dexamethasone 4 MG Oral Tablet`, `dexamethasone phosphate 4 MG/ML Injectable Solution` → **`dexamethasone`**

**In scope:** the Supportive Care tab only. **Out of scope:** the other tabs
(Chemotherapy, Radiation, SCT, Immunotherapy, Unrelated) — each could be its own follow-up.

**Environment note:** unlike Phase 119, the input is a repo-bundled reference workbook
(not HiPerGator PHI), so this phase can be built AND verified locally. Only the RxNav
API first-run (see D-03) needs internet — run on a login node or local box, then it's cached offline.
</domain>

<decisions>
## Implementation Decisions

### Normalized value content
- **D-01:** New column = **generic ingredient only**. Strip dose, formulation, and brand;
  collapse salts/esters to the base ingredient (e.g. `dexamethasone phosphate` → `dexamethasone`).
  This is the RxNorm **IN** (ingredient) concept, not **PIN** (precise ingredient) — so IN mapping
  naturally yields generic-only, consistent with this decision.

### Output target
- **D-02:** **Modify the reference xlsx in place** — append the new column to the end of the
  Supportive Care tab in `data/reference/all_codes_resolved_next_tables_v2.1.xlsx`.
  RISK: 5 scripts read this workbook (R/36, R/55, R/56, R/57, R/58). See <code_context> —
  planner MUST confirm no reader breaks on an extra trailing column (R/55 iterates ALL sheets
  incl. Supportive Care; the others read Chemotherapy/Radiation/SCT by name, not Supportive Care).

### Normalization method
- **D-03:** **RxNorm ingredient mapping via the RxNav REST API**, cached. Call RxNav
  (`RXCUI → IN ingredient`) once, write results to a bundled cache CSV in `data/reference/`
  so subsequent runs are fully offline. First run needs internet (login node / local box —
  NOT a compute node).
- **D-04:** **Fallback = rule-based parse** when RxNav can't resolve a code (API miss, combo,
  odd string): strip dose tokens (numbers + MG/ML/units), formulation words (Oral Tablet,
  Injection, Prefilled Syringe, Disintegrating…), and leading "N ML" prefixes; apply a
  brand→generic alias map. Every row gets a best-effort normalized value — never left blank.

### Brand & combination handling
- **D-05:** **Brand → generic** (e.g. `Zofran` → `ondansetron`). For multi-ingredient
  **combination products, keep a combined label** (e.g. `netupitant/palonosetron`) rather than
  dropping one ingredient — flagged, not silently split.

### Column name
- **D-06:** New column header = **`Normalized Meaning`** (mirrors the existing `Meaning` column).

### Claude's Discretion
- Exact list of formulation/dose stop-words and the brand→generic alias entries (planner/executor
  build from the actual 171 Supportive Care rows).
- Cache-file name/format for the RxNav lookup (suggest `data/reference/rxnorm_ingredient_cache.csv`).
- Whether to reuse/extend the existing `canonicalize_drug_name()` machinery vs a new helper for the
  rule-based fallback — reuse preferred if it fits.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Target data
- `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` — **Supportive Care** tab (171 codes;
  real headers on row 2: Code | Meaning | Code Type | Source Table | Records | Patients). The file
  to modify in place.

### Existing canonicalization machinery (for the D-04 rule-based fallback)
- `R/00_config.R` lines ~2368-2398 — `DRUG_NAME_ALIASES` + `canonicalize_drug_name()`
  (vectorized, NA-safe, case-insensitive brand/alias collapse). Extend for supportive-care agents.

### Reader scripts (must not break on the new column — D-02 risk)
- `R/55_verify_replaced_by_codes.R` line ~81-86 — iterates ALL sheets incl. `Supportive Care`,
  reads via `wb_to_df(wb, sheet, start_row = 2)`. **Primary compatibility check.**
- `R/56_new_tables_from_groupings.R`, `R/57_drug_grouping_instances.R`,
  `R/58_code_reference_tables.R`, `R/36_tableau_ready_tables.R` — read the workbook via
  `wb_to_df(..., start_row = 2)` (Chemotherapy/Radiation/SCT by name; verify none assume col count).

### External API (D-03)
- RxNav REST API — `https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/related.json?tty=IN`
  (RXCUI → ingredient). Public, no key. Cache to `data/reference/`.

### Registration precedent (100+ scripts)
- `R/39_run_all_investigations.R`, `R/88_smoke_test_comprehensive.R` (next section suffix after
  15q → **15r**), `R/SCRIPT_INDEX.md` (Post-Renumber Investigations 100+ table).
- xlsx read/write precedent: `R/100_ruca_rurality_summary.R` (openxlsx2 patterns).
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `canonicalize_drug_name()` + `DRUG_NAME_ALIASES` (R/00_config.R) — the rule-based/brand→generic
  fallback (D-04) should reuse/extend this rather than hand-rolling a new normalizer.
- `wb_to_df()` (openxlsx2) is the established reader; `R/100` shows openxlsx2 write/styling patterns
  for producing xlsx.

### Established Patterns
- Reference workbook sheets carry a title banner on row 1; real headers on row 2 → readers pass
  `start_row = 2`. Any new column must be added on the row-2 header line + data rows.
- 100+ investigation scripts follow the R/101-R/104 style (5-field header, SECTION banners,
  registered in R/39 + R/88 + SCRIPT_INDEX).

### Integration Points
- New script slots as `R/105_*` (next free 100+ number after R/104). Registered in R/39, validated
  by a new R/88 Section 15r, indexed in SCRIPT_INDEX.
- In-place xlsx edit: read all sheets, add the column to Supportive Care, re-write the workbook
  preserving the other 7 sheets and the row-1 title banner.
</code_context>

<specifics>
## Specific Ideas

- Redundancy is real and heavy: ~8+ `ondansetron` variants, multiple `dexamethasone`/`dexamethasone
  phosphate` variants, brand `Zofran`. The normalized column is what makes per-ingredient rollups
  (records/patients per agent) possible.
- RxNorm IN vs PIN distinction is the mechanism that delivers D-01 (generic-only): request `tty=IN`.
</specifics>

<deferred>
## Deferred Ideas

- Normalizing the Meaning column on the OTHER tabs (Chemotherapy, Radiation, SCT, Immunotherapy,
  Unrelated) — same technique, separate phases if wanted.
- Per-ingredient rollup summary tables (records/patients aggregated by Normalized Meaning) — a
  natural next step once the column exists, but a new capability beyond "add the column."

None of these are in Phase 120 scope.
</deferred>

---

*Phase: 120-in-all-codes-resolved-next-tables-v2-1-tab-supportive-care-normalize-meaning-into-a-new-column-to-disambiguate-dosage-spelling-variants-and-generic-names*
*Context gathered: 2026-07-10*
