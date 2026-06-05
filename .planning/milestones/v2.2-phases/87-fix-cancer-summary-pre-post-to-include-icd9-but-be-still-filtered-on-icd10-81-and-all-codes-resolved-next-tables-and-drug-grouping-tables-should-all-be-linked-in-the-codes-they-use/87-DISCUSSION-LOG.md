# Phase 87: Unify ICD-9/ICD-10 Cancer Code Usage - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-03
**Phase:** 87-fix-cancer-summary-pre-post-to-include-icd9
**Areas discussed:** Cancer summary ICD-9 scope, Code list unification, all_codes_resolved linkage, HL cohort anchor

---

## Cancer Summary ICD-9 Scope

### Q1: How broadly should R/45-R/49 include ICD-9 codes?

| Option | Description | Selected |
|--------|-------------|----------|
| All ICD-9 neoplasms (140-239) | Match R/56's approach — include all ICD-9 neoplasm codes alongside ICD-10 | |
| ICD-9 HL only (201.x) | Only add ICD-9 Hodgkin Lymphoma codes | |
| You decide | Claude picks the approach | ✓ |

**User's choice:** You decide
**Notes:** Claude will determine the right ICD-9 breadth. Given subsequent decisions (full mapping, map-based detection), Claude's discretion covers the detection scope.

### Q2: Should D-codes remain excluded from cancer summary pipeline?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep D-codes excluded | R/47 already filters them out. Cancer summary stays malignant C-codes + ICD-9 equivalents | ✓ |
| Include D-codes | Add D-codes back for completeness | |
| You decide | Claude picks based on clinical sense | |

**User's choice:** Keep D-codes excluded
**Notes:** None

### Q3: Should classify_codes() map ICD-9 non-HL codes to matching categories?

| Option | Description | Selected |
|--------|-------------|----------|
| Map ICD-9 to matching categories | Build ICD-9-to-category mappings. E.g., 200.x → Non-Hodgkin Lymphoma | ✓ |
| Label ICD-9 generically | Generic label like 'ICD-9 Neoplasm (NOS)' | |
| You decide | Claude picks | |

**User's choice:** Map ICD-9 to matching categories
**Notes:** None

### Q4: How thorough should the ICD-9-to-category mapping be?

| Option | Description | Selected |
|--------|-------------|----------|
| Full mapping (all 140-239) | Map every ICD-9 neoplasm prefix. No 'Unclassified' ICD-9 codes. | ✓ |
| HL-relevant subset only | Map only codes patients in cohort actually have | |
| You decide | Claude determines depth based on data | |

**User's choice:** Full mapping (all 140-239)
**Notes:** None

### Q5: Where should the ICD-9 cancer category mapping live?

| Option | Description | Selected |
|--------|-------------|----------|
| ICD9_CANCER_SITE_MAP in R/00_config.R | New named vector alongside CANCER_SITE_MAP. Separate for clarity. | ✓ |
| Merge into CANCER_SITE_MAP | Add ICD-9 prefixes directly to existing map. Single lookup. | |
| You decide | Claude picks based on existing patterns | |

**User's choice:** ICD9_CANCER_SITE_MAP in R/00_config.R
**Notes:** None

---

## Code List Unification

### Q1: Should is_cancer_code() become a shared utility?

| Option | Description | Selected |
|--------|-------------|----------|
| Move to utils_cancer.R | Extract to R/utils/utils_cancer.R alongside classify_codes(). Single source of truth. | ✓ |
| Keep in R/56, copy to others | Each script has its own. More self-contained but duplicated. | |
| You decide | Claude picks based on DRY principles | |

**User's choice:** Move to utils_cancer.R
**Notes:** None

### Q2: Should is_cancer_code() use the new ICD9_CANCER_SITE_MAP for detection?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, use both maps | Detection driven by same data as classification | |
| Keep range-based detection | Keep 140-239 range check. Detection broad; classification specific. | |
| You decide | Claude picks to avoid gaps | ✓ |

**User's choice:** You decide
**Notes:** Claude's discretion on whether map-based or range-based detection is more appropriate.

---

## all_codes_resolved Linkage

### Q1: What does 'linked in codes they use' mean for R/50?

| Option | Description | Selected |
|--------|-------------|----------|
| Add cancer dx codes column | Add cancer diagnosis codes column to R/50 output | |
| Use same is_cancer_code() | Ensure R/50 uses shared utility if it references cancer codes | ✓ |
| Align code detection only | Consistency in how codes are identified, no structural changes | |

**User's choice:** Use same is_cancer_code()
**Notes:** No new columns needed in R/50. Just consistency in shared code detection.

---

## HL Cohort Anchor

### Q1: Should ICD-9 201.x count toward HL cohort confirmation?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, include 201.x | 2+ ICD-9 201.x codes with 7-day gap confirms HL. Captures pre-2015 diagnoses. | ✓ |
| No, keep C81 only | Cohort confirmation stays ICD-10 C81 only | |
| You decide | Claude picks based on clinical equivalence | |

**User's choice:** Yes, include 201.x. Also: "please prepare for downstream effects of this"
**Notes:** User specifically emphasized downstream impact analysis is required. The confirmed_hl_cohort.rds artifact may change, affecting all downstream scripts.

### Q2: Should cross-system codes (201.x + C81) count together?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, cross-system counts | Any combination of 201.x and C81 reaching threshold confirms HL | ✓ (category level) |
| Same system only | 2+ codes from same coding system required | |

**User's choice:** "cross system counts for category summary but not for code summary sheet"
**Notes:** Category-level summaries allow ICD-9 + ICD-10 to combine. Code-level summary sheets keep 201.x and C81.x counts separate.

---

## Claude's Discretion

- ICD-9 scope breadth for cancer summary pipeline (Q1 of Cancer summary area)
- Whether is_cancer_code() should use map-based vs range-based ICD-9 detection (Q2 of Code list area)
- ICD-9 D-code equivalent identification for exclusion
- Exact ICD-9 prefix-to-category mappings
- ICD-9 201.x subcategory mapping to classical HL subtypes

## Deferred Ideas

None — discussion stayed within phase scope.
