# Phase 127: Code-Set and Infrastructure Centralization - Context

**Gathered:** 2026-07-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the infrastructure the DoI layer classifies against: the `DOI_CODE_MAP` (ICD-9/ICD-10 non-malignant diagnosis codes) plus drug-code references and the attribution-window constant in `R/00_config.R`, the `is_doi_code()` / `classify_doi_codes()` utilities in a new `R/utils/utils_doi.R`, and minimal DoI test fixtures.

This phase produces NO classification output and touches NO real data — it delivers a correct, complete, versioned code map and a tested utility layer. Classification (Phase 128), attribution + output (Phase 129), and registration/runtime (Phase 130) are separate. The cancer cascade (`utils_cancer.R`, `CANCER_SITE_MAP`, R/28) is read-only throughout.

</domain>

<decisions>
## Implementation Decisions

### Code-Set Scope
- **D-01:** Include ALL conditions — the ~11 table-stakes (FDA-approved / strong-guideline) AND the ~7 edge/off-label ones — with each code group tagged by **tier** (`table-stakes` vs `edge`) so downstream outputs can filter edge noise. Edge conditions: EGPA/Churg-Strauss (M30.1), cold agglutinin disease (D59.12), myasthenia gravis (G70.0x), ulcerative colitis (K51), Sjögren's (M35.0x), cryoglobulinemic vasculitis (D89.1), IgA vasculitis (D69.2), optic neuritis (H46.0x/1x/8/9), skin-limited vasculitis (L95.8/L95.9).
- **D-02:** Exclude I77.82 (seed error — "Dissection of artery", not vasculitis) and D47.Z2 (already owned by `CANCER_SITE_MAP` as MDS/Myeloproliferative), each with an inline exclusion comment. Include L10.81 (paraneoplastic pemphigus) in the map but it will carry a `paraneoplastic_flag` downstream (Phase 128).
- **D-03:** Pin `RITDIS_CODE_VERSION` to FY2026 with inline per-code-group audit comments citing the clinical source (FEATURES.md).

### ICD-9 Coverage
- **D-04:** ICD-10 for ALL conditions (table-stakes + edge). ICD-9 equivalents only for the **table-stakes** conditions where the mapping is high-confidence — RA (714.x), SLE (710.0), psoriasis/PsA (696.0/696.1), IBD (555.x/556.x), pemphigus/pemphigoid (694.x), dermatomyositis/PM (710.3/710.4), GPA (446.4), ITP (287.31), AIHA (283.0), NMO (341.0). Skip ICD-9 for edge conditions (MEDIUM/LOW-confidence crosswalks). Matches the existing `ICD9_CANCER_SITE_MAP` parity pattern but scoped to avoid shaky edge mappings.

### Drug Detection
- **D-05:** Rituximab detected via BOTH HCPCS J-codes (J9310/J9311/J9312 — already in the pipeline, in PROCEDURES) AND RxNorm CUIs + NDC (via the existing `get_chemo_hits()` NDC→RxNorm crosswalk). Requires a **one-time manual RxNav enumeration** of rituximab RxNorm CUIs including biosimilars (Rituxan, Truxima, Ruxience, Riabni). Store as a new `RITUXIMAB_CODES` structure — defined ADDITIVELY, NOT added to `TREATMENT_CODES$chemo_rxnorm` or `DRUG_GROUPINGS` (would contaminate chemo/regimen detection).
- **D-06:** Methotrexate — the MTX RxNorm CUIs ALREADY live in `chemo_rxnorm` (105585, 105587, 1655960, 1946772, 311627, 1544390, …). `MTX_CODES` references those existing CUIs by name (plus MTX HCPCS J-codes where applicable) WITHOUT duplicating or modifying `chemo_rxnorm`.

### Output Policy (cross-phase — affects Phase 129 / DOI-OUT-02)
- **D-07:** DoI outputs are **internal investigation outputs → raw counts, NO automated HIPAA small-cell suppression**. Manual suppression applied before any external sharing. This is consistent with the v3.1 decision ("raw counts without HIPAA suppression for internal investigation scripts; manual suppression before sharing"). **This relaxes DOI-OUT-02** — the R/111 output should carry an "internal-only; suppress manually before sharing" note rather than running `suppress_small()`. Recorded here in Phase 127 because it changes what Phase 129 builds; REQUIREMENTS.md DOI-OUT-02 updated to match.

### Fixtures
- **D-08:** Minimal fixture augmentation — one ICD-10 DoI patient (e.g., M05.9 RA) and one ICD-9 DoI patient (e.g., 714.0 RA), enough to exercise `is_doi_code()` on both coding systems. No suppression-testing or multi-category fixtures. Prevalence realism verified at HiPerGator runtime (Phase 130).

### Claude's Discretion
- Exact prefix-key granularity (3-char vs 4-char vs individual code) per the FEATURES.md / SUMMARY.md recommendations (e.g., D692 vs D693 disambiguation, M350, D591, H46 individual keys).
- `utils_doi.R` function signatures — mirror `is_hl_diagnosis()` (DX_TYPE-gated) and `classify_codes()`.
- Specific fixture PATIDs / which fixture CSV rows to add.
- Exact MTX HCPCS J-code set (verify J9250/J9260 applicability at planning).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Code set (WHAT codes, tiers, exclusions, ICD-9 equivalents)
- `.planning/research/FEATURES.md` — complete verified 14-category code set, table-stakes vs edge tiers, ICD-9 equivalents, I77.82/D47.Z2/L10.81 handling, per-code implementation notes for R/00_config.R
- `.planning/research/SUMMARY.md` — executive synthesis, build order, drug-detection isolation rule, exclusions
- `.planning/research/ritdis_seed_codes.md` — original seed extracted from ritdis.rtf (with gaps flagged)
- `ritdis.rtf` — original user-supplied clinical source document (project root)

### Architecture & pitfalls (HOW to factor and what to avoid)
- `.planning/research/ARCHITECTURE.md` — config Section 4c/4d placement, `utils_doi.R` as new file, auto-source glob, grain decisions
- `.planning/research/PITFALLS.md` — ICD-9/10 DX_TYPE gating, D69 4-char disambiguation, mutual-exclusivity hard-stop, dotted/undotted normalization

### Code patterns to mirror
- `R/00_config.R` — `CANCER_SITE_MAP` (line 543), `ICD9_CANCER_SITE_MAP` (line 840), `DRUG_GROUPINGS` (line 1390), `MEDICATION_LOOKUP` (~line 2000, J9310→"Rituximab"), `TREATMENT_CODES` (line 2480) / `chemo_rxnorm` (line 2581, already holds MTX CUIs + rituximab J-codes in the HCPCS list)
- `R/utils/utils_icd.R` — `is_hl_diagnosis()` DX_TYPE-gated matching + `normalize_icd()` (the template for `is_doi_code()`)
- `R/utils/utils_cancer.R` — `is_cancer_code()` / `classify_codes()` cascade to structurally mirror AND reuse for the mutual-exclusivity exclusion check
- `R/utils/utils_treatment.R` — `get_chemo_hits()` signature (rituximab NDC/RxNorm detection path)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `is_cancer_code()` (utils_cancer.R) — reused directly for the Phase 128 mutual-exclusivity assertion; also confirms no DOI prefix collides with cancer prefixes.
- `normalize_icd()` (utils_icd.R) — dotted/undotted normalization, use verbatim in `is_doi_code()`.
- `classify_codes()` / `is_hl_diagnosis()` — structural templates (named-vector prefix cascade + DX_TYPE gate).
- `get_chemo_hits()` (utils_treatment.R) + NDC→RxNorm crosswalk — rituximab RxNorm/NDC detection path (D-05).
- utils auto-source glob in `R/00_config.R` — `utils_doi.R` is picked up with zero extra config.

### Established Patterns
- Named prefix→category character vectors organized by config "Section" (4a/4b/4c/4d…); DoI map goes in a new Section 4c with drug codes/window in 4d.
- DX_TYPE gating ("09"/"10", NA/SNOMED→FALSE) before prefix matching — never mix coding systems in one lookup.
- Additive drug-code constants kept separate from `chemo_rxnorm`/`DRUG_GROUPINGS` to protect regimen detection.

### Integration Points
- `DOI_CODE_MAP` + `RITDIS_CODE_VERSION` → R/00_config.R Section 4c.
- `RITUXIMAB_CODES`, `MTX_CODES`, `DOI_ATTRIBUTION_WINDOW_DAYS <- 90L` → Section 4d.
- `utils_doi.R` → `R/utils/` (new file, auto-sourced).
- Fixtures → existing local test fixture CSVs (DIAGNOSIS + a patient row).

</code_context>

<specifics>
## Specific Ideas

- Rituximab biosimilars explicitly in scope for CUI enumeration: Rituxan, Truxima, Ruxience, Riabni.
- Tier column is the mechanism for controlling edge-condition noise later — table-stakes vs edge must be queryable, not just a comment.
- "Co-occurrence, not attribution" language constraint (from research) applies to naming even at the config layer — avoid `*_for_*` naming in the drug-code constants.

</specifics>

<deferred>
## Deferred Ideas

- Payer-stratified DoI co-occurrence (DOI-FUT-01) — future milestone.
- Methotrexate dose/route disambiguation, high-dose IV oncologic vs low-dose oral autoimmune (DOI-FUT-02) — future milestone.
- Cohort-level attrition impact of reclassifying likely-non-lymphoma-directed episodes (DOI-FUT-03) — future milestone.

None of these belong in Phase 127; captured so they are not lost.

</deferred>

---

*Phase: 127-code-set-and-infrastructure-centralization*
*Context gathered: 2026-07-15*
