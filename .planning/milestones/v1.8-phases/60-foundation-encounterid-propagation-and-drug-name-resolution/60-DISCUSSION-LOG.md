# Phase 60: Foundation - ENCOUNTERID Propagation & Drug Name Resolution - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-29
**Phase:** 60-foundation-encounterid-propagation-and-drug-name-resolution
**Areas discussed:** ENCOUNTERID handling, Drug name scope, Output strategy, SCT audit approach

---

## ENCOUNTERID Handling

### Q1: How should missing/NULL ENCOUNTERID values appear in episode output?

| Option | Description | Selected |
|--------|-------------|----------|
| Omit NULLs from list | Episode encounter_ids column only lists non-NULL values. Fully NULL episodes show empty string. | ✓ |
| Include NULL marker | Show 'NA' or 'MISSING' in the comma-separated list so you can see how many dates lack encounter IDs | |
| You decide | Claude picks the best approach for downstream usability | |

**User's choice:** Omit NULLs from list (Recommended)
**Notes:** None

### Q2: Should R/43a and R/44a be modified in-place to add ENCOUNTERID, or should Phase 60 create new scripts?

| Option | Description | Selected |
|--------|-------------|----------|
| Modify in-place | Add ENCOUNTERID to existing extraction functions in R/43a+R/44a. Simpler, no script proliferation. | ✓ |
| New R/60 scripts | Create R/60_*.R that wraps or replaces R/43a+R/44a. Preserves originals but adds maintenance burden. | |
| You decide | Claude picks based on codebase patterns | |

**User's choice:** Modify in-place (Recommended)
**Notes:** None

### Q3: For episodes with multiple encounter IDs, what aggregation format?

| Option | Description | Selected |
|--------|-------------|----------|
| Comma-separated string | Same pattern as triggering_codes column. Consistent with established convention. | ✓ |
| Pipe-separated string | Use | delimiter to distinguish from triggering_codes | |
| Count only | Just n_encounters integer column showing how many unique encounter IDs | |

**User's choice:** Comma-separated string (Recommended)
**Notes:** None

### Q4: Should we run a data inspection step first to measure ENCOUNTERID population rates per table?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, as part of Phase 60 | Add inspection/audit section that logs population rates per source table. Documents data quality. | ✓ |
| No, just propagate | Add ENCOUNTERID to extraction without a formal inspection step | |
| You decide | Claude picks based on TREAT-01 requirements | |

**User's choice:** Yes, as part of Phase 60 (Recommended)
**Notes:** None

---

## Drug Name Scope

### Q5: Should drug name resolution cover only chemotherapy, or all treatment types?

| Option | Description | Selected |
|--------|-------------|----------|
| Chemotherapy only | Per success criteria. Other types don't need drug names for Phase 61 regimen detection. | ✓ |
| All treatment types | Also resolve drug names for immunotherapy and SCT conditioning agents | |
| Chemo + immunotherapy | Both since Nivo+AVD includes nivolumab | |

**User's choice:** Chemotherapy only (Recommended)
**Notes:** None

### Q6: Which code types should be resolved to drug names?

| Option | Description | Selected |
|--------|-------------|----------|
| RXNORM_CUI + NDC | Both code types appear in PRESCRIBING/DISPENSING/MED_ADMIN. R/40 has functions for both. | ✓ |
| RXNORM_CUI only | Simpler, single API endpoint. NDC codes would show as unresolved. | |
| You decide | Claude picks based on data availability and Phase 61 needs | |

**User's choice:** RXNORM_CUI + NDC (Recommended)
**Notes:** None

### Q7: How should API results be cached to avoid re-lookups on re-runs?

| Option | Description | Selected |
|--------|-------------|----------|
| RDS cache file | Save drug_name_lookup.rds after first API run. On re-run, load cache and only look up new codes. | ✓ |
| Always call API | No caching — call RxNorm API every run. Simpler but slower. | |
| You decide | Claude picks the caching strategy | |

**User's choice:** RDS cache file (Recommended)
**Notes:** None

---

## Output Strategy

### Q8: Should existing RDS artifacts gain new columns in-place, or create v2 versions?

| Option | Description | Selected |
|--------|-------------|----------|
| Modify in-place | Add encounter_ids and drug_names columns to existing RDS files. Phases 61-62 consume directly. | ✓ |
| Create v2 RDS files | New treatment_episodes_v2.rds alongside originals. Clean separation but more files. | |
| You decide | Claude picks based on downstream dependency analysis | |

**User's choice:** Modify in-place (Recommended)
**Notes:** None

### Q9: Should the drug name lookup table include all codes from config, or only codes in patient data?

| Option | Description | Selected |
|--------|-------------|----------|
| Only codes in patient data | Query source tables for actual codes, then resolve. Focused, no wasted API calls. | ✓ |
| All codes from config | Resolve every code in TREATMENT_CODES vectors. More complete but includes unused codes. | |
| You decide | Claude picks the approach | |

**User's choice:** Only codes in patient data (Recommended)
**Notes:** None

### Q10: Should drug_name_lookup.rds be a standalone script or built inside R/44a?

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone R/60 script | R/60_drug_name_resolution.R builds lookup table. Can be re-run independently. | ✓ |
| Inside R/44a | Drug name resolution within R/44a during episode extraction. Simpler but couples API with data. | |
| You decide | Claude picks the architecture | |

**User's choice:** Standalone R/60 script (Recommended)
**Notes:** None

---

## SCT Audit Approach

### Q11: What output format for the SCT source audit?

| Option | Description | Selected |
|--------|-------------|----------|
| Section in broader Phase 60 xlsx | SCT Source Audit sheet in Phase 60 output xlsx. Per-source patient counts and delta. | ✓ |
| Standalone xlsx report | Separate sct_source_audit.xlsx. More visible but another file. | |
| Console output only | Log to console, no persistent artifact. | |

**User's choice:** Section in broader Phase 60 xlsx (Recommended)
**Notes:** None

### Q12: After removing DX codes from SCT detection, should sct_dx_icd10 be removed from config?

| Option | Description | Selected |
|--------|-------------|----------|
| Remove from config | Delete sct_dx_icd10 vector entirely. Clean break. | ✓ |
| Keep but comment out | Comment out with explanation note. Preserves history. | |
| You decide | Claude picks the cleanup approach | |

**User's choice:** Remove from config (Recommended)
**Notes:** None

### Q13: Should the SCT audit run as pre/post comparison or document removal only?

| Option | Description | Selected |
|--------|-------------|----------|
| Pre/post comparison | Run with DX codes, then without, show delta. Patients who lose SCT status vs retained. | ✓ |
| Document removal only | List 5 DX codes and their counts. No before/after. | |

**User's choice:** Pre/post comparison (Recommended)
**Notes:** None

---

## Claude's Discretion

- Script numbering for drug name resolution script
- Column ordering for new columns in RDS and CSV output
- Console logging detail for ENCOUNTERID population rates
- xlsx sheet ordering and styling
- Whether to source R/40 functions or copy them

## Deferred Ideas

None — discussion stayed within phase scope
