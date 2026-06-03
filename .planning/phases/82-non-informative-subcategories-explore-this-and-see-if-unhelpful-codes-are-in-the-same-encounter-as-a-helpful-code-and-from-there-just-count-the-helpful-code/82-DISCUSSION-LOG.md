# Phase 82: Non-Informative Sub-Categories - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-03
**Phase:** 82-non-informative-subcategories-explore-this-and-see-if-unhelpful-codes-are-in-the-same-encounter-as-a-helpful-code-and-from-there-just-count-the-helpful-code
**Areas discussed:** Non-informative definition, Matching scope, Orphan handling, Output changes

---

## Non-Informative Definition

| Option | Description | Selected |
|--------|-------------|----------|
| Encounter Dx only (Recommended) | Only encounter diagnosis codes are non-informative — they just say 'treatment happened' without naming the drug/procedure. DRG, Revenue, and procedure codes remain. | ✓ |
| Dx + DRG + Revenue | Encounter Dx codes PLUS DRG codes PLUS Revenue codes are all non-informative — all billing/administrative codes. | |
| Everything except named | Everything that isn't a specific named medication/procedure from xlsx or CODE_SUBCATEGORY_MAP is non-informative. | |

**User's choice:** Encounter Dx only (Recommended)
**Notes:** None

---

## Matching Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Same encounter_id (Recommended) | Check within the same encounter as the dx code. Most precise — ensures specific code was billed alongside in same visit. | ✓ |
| Same treatment episode | Check across all encounters in the treatment episode. Broader — may over-deduplicate. | |
| You decide | Let Claude choose based on data structure. | |

**User's choice:** Same encounter_id (Recommended)
**Notes:** None

---

## Orphan Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Keep with dx label | Keep rows with current label. Still represent real treatment encounters. | |
| Exclude entirely | Remove encounters with only dx codes. Low-signal rows. | |
| Flag and keep | Keep rows but add a flag column (dx_only = TRUE) for easy filtering. Most flexible. | ✓ |

**User's choice:** Flag and keep
**Notes:** None

---

## Output Changes

| Option | Description | Selected |
|--------|-------------|----------|
| New exploration script (Recommended) | Create R/57 exploration script, keep R/56 as baseline. | |
| Modify R/56 directly | Add deduplication logic directly into R/56. | |
| Both: explore then integrate | First explore, then fold validated logic into R/56. | ✓ |

**User's choice:** Both: explore then integrate
**Notes:** None

### Follow-up: Table Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Table 1 only (Recommended) | Apply to Table 1 (sub-category summary) where dx codes inflate counts. | ✓ |
| Both tables | Apply to both Table 1 and Table 2. | |
| You decide | Let Claude determine. | |

**User's choice:** Table 1 only (Recommended)
**Notes:** User additionally emphasized: "I want the code to run well and anticipate downstream and upstream changes" — captured as quality directive D-10, D-11, D-12 in CONTEXT.md.

---

## Claude's Discretion

- Exact script number for exploration script
- Whether to add co-occurrence stats to R/56 log or keep in exploration script only
- Internal data structure for co-occurrence check

## Deferred Ideas

None — discussion stayed within phase scope.
