# Phase 93: Cross-Use Flag Implementation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-08
**Phase:** 93-cross-use-flag-implementation
**Areas discussed:** SCT conditioning window, Questionable code identification, Confidence column design, Aggregation rules

---

## SCT Conditioning Window

| Option | Description | Selected |
|--------|-------------|----------|
| 30 days (Recommended) | Standard oncology prep window. Most conditioning regimens begin 2-4 weeks before transplant. | |
| Configurable in 00_config.R | Default to 30 days but expose parameter in config for SME adjustment. | |
| 14 days | More conservative. Reduces false positives but may miss early conditioning. | |

**User's choice:** 30 days (Recommended)
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Hardcoded 30 | Simple. Matches roadmap spec exactly. | |
| Config parameter | SCT_CONDITIONING_WINDOW_DAYS = 30 in R/00_config.R. | |

**User's choice:** Hardcoded 30
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Chemo + immuno both | Both chemo and immunotherapy drugs can be part of conditioning regimens. | |
| Chemo only | Traditional conditioning is chemotherapy. Immunotherapy near SCT may be maintenance. | |
| You decide | Claude's discretion. | |

**User's choice:** Chemo only
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Boolean only | TRUE/FALSE in both RDS and Gantt CSVs. Simple. | |
| Boolean + days in RDS | Boolean flag in Gantt CSVs, plus days_to_nearest_sct integer in RDS. Re-thresholding possible. | |
| Integer only | Days-to-nearest-SCT everywhere. Most flexible but breaks flag pattern. | |

**User's choice:** Boolean + days in RDS
**Notes:** User asked about advantage of integer vs boolean. Explained that integer allows re-thresholding without rerunning pipeline, but breaks the flag-oriented schema. Compromise: boolean in CSVs, integer in RDS only.

---

## Questionable Code Identification

| Option | Description | Selected |
|--------|-------------|----------|
| Hardcoded list (Recommended) | Named vector in R/00_config.R: QUESTIONABLE_IMMUNO_CODES mapping code to reason. | |
| Pattern-match drug names | Detect 'Multivitamin' and 'CAR-T' substrings in drug name map. | |
| You decide | Claude's discretion. | |

**User's choice:** Hardcoded list (Recommended)
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| XW033C3 + XW043C3 only | 2 ICD-10-PCS codes that are ambiguous (CAR-T or other immunotherapy). | |
| All 3 (XW033C3 + XW043C3 + 2479140) | Flag all CAR-T-related codes since CAR-T classification is under discussion. | |
| Just 2479140 | Only the RxNorm code. ICD-10-PCS codes are procedure codes. | |

**User's choice:** All 3 (XW033C3 + XW043C3 + 2479140)
**Notes:** Total questionable codes: 11 (8 vitamin + 3 CAR-T), not 10 as originally estimated.

---

## Confidence Column Design

| Option | Description | Selected |
|--------|-------------|----------|
| New column (Recommended) | Add 'immuno_confidence' as column 22/20. Separate from sct_cross_use_flag. | |
| Extend sct_cross_use_flag | Add confidence values into existing cross-use flag column. | |

**User's choice:** New column (Recommended)
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| immuno_confidence | Descriptive. Matches IMMU-01 language. | |
| classification_flag | More generic. Could be reused for other categories. | |
| You decide | Claude's discretion. | |

**User's choice:** immuno_confidence
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Any-questionable propagates | If ANY code is questionable, episode gets the flag. Matches existing aggregation. | |
| Majority rules | Only flag if more than half of codes are questionable. | |
| You decide | Claude's discretion. | |

**User's choice:** Any-questionable propagates
**Notes:** None

---

## Aggregation Rules

| Option | Description | Selected |
|--------|-------------|----------|
| Comments in code only (Recommended) | Inline comments in R/28 and R/52 explaining annotation vs reclassification. | |
| Separate markdown doc | .planning/aggregation-rules.md for analysts. | |
| Both | Comments in code + markdown doc. | |

**User's choice:** Comments in code only (Recommended)
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Annotation only (Recommended) | treatment_type stays 'Chemotherapy'. Flag is metadata for analysts. | |
| Reclassify to 'SCT Conditioning' | Change treatment_type. Creates new category. | |

**User's choice:** Annotation only (Recommended)
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| treatment_type sum check | Assert each episode has exactly one treatment_type. | |
| Full cross-tab validation | Sum check PLUS cross-tab confirming flag only on Chemotherapy episodes. | |
| You decide | Claude's discretion. | |

**User's choice:** Full cross-tab validation
**Notes:** None

---

## Claude's Discretion

- Exact placement of new columns in R/28 enrichment pipeline
- Smoke test section numbering
- Comment wording for aggregation rules
- days_to_nearest_sct computation details

## Deferred Ideas

None — discussion stayed within phase scope
