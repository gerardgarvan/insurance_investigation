# Phase 127: Code-Set and Infrastructure Centralization - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-15
**Phase:** 127-code-set-and-infrastructure-centralization
**Areas discussed:** Edge-code scope, Rituximab detection source, ICD-9 coverage depth, Fixture scope (+ HIPAA output policy)

---

## Edge-Code Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Include all, tag by tier | Table-stakes + edge, each labeled tier so downstream can filter | ✓ |
| Table-stakes only | Ship only FDA-approved / strong-guideline; defer edge | |
| Include all, no tier label | One undifferentiated set | |

**User's choice:** Include all, tag by tier
**Notes:** Tier column becomes the mechanism to suppress edge/off-label co-occurrence noise later without dropping recall.

---

## Rituximab Detection Source

| Option | Description | Selected |
|--------|-------------|----------|
| HCPCS + RxNorm/NDC | J-codes plus enumerated rituximab RxNorm CUIs via get_chemo_hits crosswalk; one-time RxNav curation | ✓ |
| HCPCS J-codes only | J9310/J9311/J9312 already in pipeline; no CUI enumeration | |
| You decide during planning | Let researcher/planner assess extract coverage | |

**User's choice:** HCPCS + RxNorm/NDC
**Notes:** Requires one-time manual enumeration of rituximab RxNorm CUIs incl. biosimilars (Rituxan, Truxima, Ruxience, Riabni). Kept separate from chemo_rxnorm/DRUG_GROUPINGS. MTX CUIs already present in chemo_rxnorm — referenced by name, not duplicated.

---

## ICD-9 Coverage Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Full ICD-9 + ICD-10 parity | ICD-9 equivalents for all conditions | |
| ICD-9 for table-stakes only | Full ICD-10; ICD-9 only for high-confidence common conditions | ✓ |
| ICD-10 only | Skip ICD-9 entirely | |

**User's choice:** ICD-9 for table-stakes only
**Notes:** Avoids the MEDIUM/LOW-confidence ICD-9 edge-condition crosswalks while keeping historical coverage for the common conditions (RA, SLE, psoriasis, IBD, etc.).

---

## Fixture Scope + HIPAA Output Policy

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal (1 ICD-10 + 1 ICD-9) | Just enough to exercise is_doi_code() on both systems | ✓ |
| Broader multi-category | Several categories + rare + co-occurrence for local suppression testing | |

**User's choice:** Minimal fixtures + "do not worry about HIPAA small-cell suppression"
**Notes:** Clarified via follow-up — user chose interpretation (1): DoI outputs are internal, raw counts, NO automated suppression; manual suppression before external sharing (consistent with v3.1 internal-investigation pattern). This relaxes DOI-OUT-02 (updated in REQUIREMENTS.md). Fixtures stay minimal; prevalence/suppression realism verified at HiPerGator.

---

## Claude's Discretion

- Prefix-key granularity (3-char/4-char/individual) per research recommendations
- utils_doi.R function signatures (mirror is_hl_diagnosis / classify_codes)
- Specific fixture PATIDs / rows
- Exact MTX HCPCS J-code set

## Deferred Ideas

- Payer-stratified DoI (DOI-FUT-01)
- MTX dose/route disambiguation (DOI-FUT-02)
- Cohort attrition impact (DOI-FUT-03)
