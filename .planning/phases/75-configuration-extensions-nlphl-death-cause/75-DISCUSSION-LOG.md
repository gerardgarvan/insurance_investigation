# Phase 75: Configuration Extensions (NLPHL & Death Cause) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-02
**Phase:** 75-configuration-extensions-nlphl-death-cause
**Areas discussed:** NLPHL naming, Death cause scheme, ICD-9 NLPHL scope

---

## NLPHL Naming

### Q1: NLPHL category label

| Option | Description | Selected |
|--------|-------------|----------|
| NLPHL | Short clinical abbreviation. Matches how oncologists refer to it in practice. Concise in tables. | Y |
| Nodular Lymphocyte Predominant HL | Full formal name. Clearer for non-oncology readers but takes more column space. | |
| NLPHL (C81.0) | Abbreviation with ICD code reference. Self-documenting but verbose. | |

**User's choice:** NLPHL
**Notes:** None

### Q2: Classical HL label

| Option | Description | Selected |
|--------|-------------|----------|
| Classical Hodgkin Lymphoma | Standard oncology term (cHL). Clearly distinguishes from NLPHL. Used in NCCN guidelines. | |
| Hodgkin Lymphoma (non-NLPHL) | Matches the success criteria wording. Explicitly signals exclusion of NLPHL. More descriptive. | Y |
| cHL | Short abbreviation matching 'NLPHL' style. Very concise but may be unclear to non-specialists. | |

**User's choice:** Hodgkin Lymphoma (non-NLPHL)
**Notes:** None

### Q3: Roll-up constant

| Option | Description | Selected |
|--------|-------------|----------|
| No roll-up in config | Keep CANCER_SITE_MAP clean with only the two distinct categories. Downstream scripts combine when needed. | Y |
| Add roll-up constant | Define HL_CATEGORIES constant in config for easy grouping. Extra constant but avoids hardcoding. | |

**User's choice:** No roll-up in config
**Notes:** Follows existing pattern where maps are atomic

---

## Death Cause Scheme

### Q4: Grouping approach

| Option | Description | Selected |
|--------|-------------|----------|
| Cancer-focused + broad | Detailed cancer subtypes + broad non-cancer groups. Best for HL study. | |
| ICD-10 chapter-level | One category per ICD-10 chapter (21 chapters). Simple but lumps all cancers together. | |
| All-cause detailed | Granular categories across all causes (~30-40 groups). Maximum flexibility. | Y |
| You decide | Claude picks the best scheme for an HL cohort mortality study. | |

**User's choice:** All-cause detailed
**Notes:** None

### Q5: Missing/invalid codes

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit 'Unknown' category | Map empty/invalid codes to 'Unknown or Unspecified'. Makes missingness visible. | Y |
| Leave as NA | Unmapped codes return NA. Consistent with CANCER_SITE_MAP pattern. | |

**User's choice:** Explicit 'Unknown' category
**Notes:** Makes missingness visible in output tables rather than silently dropping

### Q6: Map key granularity

| Option | Description | Selected |
|--------|-------------|----------|
| 3-char prefixes | Same pattern as CANCER_SITE_MAP. Consistent. 50+ entries. | Y |
| Mixed: 3-char cancer, 1-char rest | Detailed cancer breakout but broad chapters for non-cancer. | |
| Full 4-char codes | Most granular. Hundreds of entries. Maximum detail but large config. | |

**User's choice:** 3-char prefixes
**Notes:** Consistent with existing CANCER_SITE_MAP pattern

### Q7: Map location in config

| Option | Description | Selected |
|--------|-------------|----------|
| Separate top-level vector | DEATH_CAUSE_MAP <- c(...) at top level. Same pattern as CANCER_SITE_MAP. | Y |
| Inside CONFIG list | CONFIG$death_cause_map. Groups with other config but differs from existing maps. | |

**User's choice:** Separate top-level vector
**Notes:** Follows existing convention

---

## ICD-9 NLPHL Scope

### Q8: Which 201.4x codes

| Option | Description | Selected |
|--------|-------------|----------|
| 201.40-201.48 + 201.4 | All 9 site-specific codes plus parent code. Mirrors ICD-10 approach. | Y |
| 201.40-201.48 only | Only site-specific codes. Exclude ambiguous parent. | |
| Full 201.4x expanded | Include all possible permutations and 5-digit variants. | |

**User's choice:** 201.40-201.48 + 201.4
**Notes:** Mirrors ICD-10 approach of including all C81.0x codes

### Q9: classify_codes() ICD-9 routing

| Option | Description | Selected |
|--------|-------------|----------|
| Single function, dual logic | classify_codes() checks 4-char first, then 3-char fallback. ICD-9 check against list. One function. | Y |
| Separate ICD-9 helper | New classify_icd9_codes() for ICD-9. classify_codes() stays ICD-10 only. | |
| You decide | Claude picks cleanest approach. | |

**User's choice:** Single function, dual logic
**Notes:** Simpler API for 15 downstream scripts

---

## Claude's Discretion

No areas deferred to Claude's discretion.

## Deferred Ideas

None — discussion stayed within phase scope.
