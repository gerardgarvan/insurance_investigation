# Phase 131: Update all_codes_resolved.xlsx to include MED_ADMIN NDC-resolved codes and a normalized drug-name column - Context

**Gathered:** 2026-07-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Update `R/50_all_codes_resolved.R` (producer of `all_codes_resolved.xlsx` and its 5 per-type sibling files) so that:
1. Its MED_ADMIN/DISPENSING code detection reflects the Phase 122 NDC-crosswalk fix — codes only reachable via `MEDADMIN_TYPE == 'ND'` or DISPENSING's NDC field, previously invisible to this report, now appear.
2. A normalized/spelling-standardized "Medication" name column is added to the drug-relevant sheets, reusing the existing `MEDICATION_LOOKUP` (Phase 114, `R/00_config.R`) as the primary source, with a defined fallback normalization for codes the curated reference doesn't cover.

Both the combined `all_codes_resolved.xlsx` and the 5 per-type files (`chemotherapy_codes_resolved.xlsx`, etc.) get these changes — they're built from the same data via `write_resolved_xlsx()`.

</domain>

<decisions>
## Implementation Decisions

### MED_ADMIN/NDC fix scope
- Extend R/50's existing MED_ADMIN query (currently `MEDADMIN_CODE %in% codes, MEDADMIN_TYPE == "RX"` only) to also resolve `MEDADMIN_TYPE == "ND"` (NDC-typed) rows and DISPENSING NDC rows, via the same NDC→RxNorm crosswalk built in Phase 122 (`ndc_rxnorm_crosswalk.rds` / `R/108`). This applies automatically across all 4 RXNORM-based vector categories R/50 already loops over (chemo_rxnorm, sct_rxnorm, immunotherapy_rxnorm, supportive_care_rxnorm) — not chemo-only.
- This closes the "broader audit of other tables/consumers for analogous code-column mismatches" item explicitly deferred at the end of Phase 122.

### Medication column — source of truth
- Primary source: `MEDICATION_LOOKUP` (code → normalized name, sourced from `data/reference/all_codes_resolved_next_tables_v2.1.xlsx`'s Medication column, Phase 114). Reuse it — do not reinvent.
- Fallback (codes with no MEDICATION_LOOKUP entry — new NDC-resolved MED_ADMIN codes, and existing Supportive Care/SCT/Immunotherapy codes since the reference file's Medication column is only populated for Chemotherapy): apply heuristic normalization, not blank and not raw-text passthrough.
  - RxNorm strings: strip down to the bare generic ingredient name, dropping salt form (e.g. "bendamustine hydrochloride 25 MG/ML Injectable Solution [Bendeka]" → "bendamustine"), matching the curated column's own style exactly.
  - HCPCS J-codes: apply the same "Injection, X, dose" pattern-stripping used by the curated reference (e.g. "Injection, ado-trastuzumab emtansine, 1 mg" → "ado-trastuzumab emtansine").
  - Multi-ingredient RxNorm compounds (e.g. "ascorbic acid / beta carotene / copper sulfate / ..."): show the full compound string unchanged — do not shorten to first ingredient, do not blank.
  - No visual/column distinction between curated (reference-file-sourced) vs. fallback-normalized names — a single Medication column, populated either way.

### Medication column — sheet scope
- Add the Medication column to: Chemotherapy (already has it), Supportive Care, Immunotherapy, and SCT.
- SCT population rule: automatic by `Code Type == "RXNORM"` (SCT mixes DRG/ICD-10-PCS/RXNORM conditioning-regimen codes in one sheet) — populate Medication only for RXNORM rows, blank for procedure/DRG/ICD rows. No manually curated code list.
- Do NOT add a Medication column to Radiation — it's pure procedure/DRG/ICD codes, a column there would be all-blank noise.

### New-code visibility
- Codes only detectable via the new NDC crosswalk (MED_ADMIN ND-type, DISPENSING) get distinguished in the existing **Source Table** column (e.g. "MED_ADMIN (RX)" vs "MED_ADMIN (NDC)", or similarly distinguishing DISPENSING) rather than a new dedicated column — reuse the existing column, don't add a flag column.
- Do NOT add a before/after delta note (e.g. "+N codes via NDC crosswalk") to the Summary/Metadata sheet — show current-run counts only, no comparison to a prior run.

### Output files
- Both the combined `all_codes_resolved.xlsx` and the 5 per-type files get all of the above (MED_ADMIN NDC coverage + Medication column) — they share the same underlying data via `write_resolved_xlsx()`, keep them in sync.
- The 5 per-type files are legacy/low-priority in practice (nobody actively opens them), but should still get updated since they're generated from the same pipeline — don't let them silently diverge.

### Medication column — Supportive Care col G reuse (added post-research)
- Phase 120 (`R/105_normalize_supportive_care_meaning.R`) already wrote a "Normalized Meaning" column (col G) to the Supportive Care sheet of `all_codes_resolved_next_tables_v2.1.xlsx`, covering all 171 Supportive Care RXNORM codes — but `MEDICATION_LOOKUP`'s builder only reads column 3 by position, so col G is currently orphaned.
- Decision: wire this in. Extend `MEDICATION_LOOKUP` (or add a parallel lookup consulted first for Supportive Care) to read col G for the Supportive Care sheet, using this already-validated Phase 120 output instead of re-deriving names via the new heuristic fallback.
- Net effect: the new heuristic fallback's real-world scope narrows to SCT, Immunotherapy, and any newly NDC-resolved MED_ADMIN/DISPENSING codes lacking a `MEDICATION_LOOKUP` entry — Supportive Care codes get covered by curated lookup (column 3 or col G) rather than the fallback in the common case.

### Claude's Discretion
- Exact string-stripping implementation for the fallback normalizer (regex approach, whether to factor it into a shared helper vs. inline in R/50)
- Whether to reuse/extend `canonicalize_drug_name()` / `DRUG_NAME_ALIASES` for the fallback path, or write independent logic
- Exact Source Table label text distinguishing MED_ADMIN RX vs ND-resolved rows
- R/88 smoke-test additions for the new column/coverage
- Column position/ordering in the sheets

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MEDICATION_LOOKUP` (`R/00_config.R` ~L2479-2551): code → normalized medication name, built from `all_codes_resolved_next_tables_v2.1.xlsx` Medication column across all 5 sheets, with `str_to_title` + abbreviation-preserving normalization already applied. Currently only Chemotherapy sheet's Medication column is actually populated in the source file — Supportive Care/SCT/Immunotherapy will need the fallback path.
- `canonicalize_drug_name()` / `DRUG_NAME_ALIASES` (`R/00_config.R` ~L2569-2620): vectorized, NA-safe brand→generic alias collapsing (Zofran→ondansetron, etc.) — already applied to `MEDICATION_LOOKUP`; could extend to the fallback path for consistency.
- `R/108_build_ndc_rxnorm_crosswalk.R` + `data/reference/ndc_rxnorm_crosswalk.rds` (Phase 122): the NDC→RxNorm crosswalk to reuse for MED_ADMIN ND-type / DISPENSING resolution.
- `get_chemo_hits()` pattern in `utils_treatment.R` (Phase 122): reference implementation of the RX+ND MED_ADMIN / DISPENSING-NDC detection logic, though it's chemo-specific — R/50 needs the same logic generalized across 4 RXNORM vector categories.
- `write_resolved_xlsx()` in `R/50_all_codes_resolved.R` (~L580): shared per-type xlsx builder — the column addition should happen upstream of this so both combined and per-type outputs inherit it.

### Established Patterns
- R/50's `rxnorm_vectors` loop (~L317-372) already queries PRESCRIBING + MED_ADMIN uniformly across all 4 RXNORM code vectors — extending it for NDC resolution naturally covers all 4, no per-category branching needed.
- Existing Source Table column values are plain strings (e.g. "PRESCRIBING", "PROCEDURES") — extending to "MED_ADMIN (RX)"/"MED_ADMIN (NDC)" or similar follows the existing free-text convention.

### Integration Points
- `data/reference/all_codes_resolved_next_tables_v2.1.xlsx` — read by `MEDICATION_LOOKUP` at config load; confirmed identical in code coverage to the user's Downloads copy (Downloads only adds an unrelated R-CHOP glossary blurb and an empty placeholder "Medication name" header on Supportive Care — no new reference data to import).
- `data/reference/ndc_rxnorm_crosswalk.rds` — read for NDC resolution.

</code_context>

<specifics>
## Specific Ideas

- The Downloads copy of `all_codes_resolved.xlsx` was checked against the repo's reference file — they carry identical code counts per sheet; the only differences are cosmetic (glossary text, one empty column header). No file sync/import step is needed; it served purely to confirm the target column shape.
- `all_codes_resolved.xlsx` is described (Phase 52 context) as "the definitive 'what codes does our pipeline detect?' reference — shared with collaborators" — this shapes the "don't blend fallback silently vs. curated" and "distinguish new codes in Source Table" decisions above.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 131-update-all-codes-resolved-xlsx-to-include-med-admin-ndc-resolved-codes-and-a-normalized-drug-name-column*
*Context gathered: 2026-07-22*
