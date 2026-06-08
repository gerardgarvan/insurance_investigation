# Phase 90: False-Positive SCT Code Removal - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-07
**Phase:** 90-false-positive-sct-code-removal
**Areas discussed:** Removal scope, Impact documentation, Smoke test strategy, Code description cleanup

---

## Removal Scope

| Option | Description | Selected |
|--------|-------------|----------|
| DRUG_GROUPINGS only | Remove from treatment episode detection only. Keep diagnosis-based SCT detection in R/10/R/11 intact — a patient with Z94.84 dx still counts as 'has SCT history' for cohort purposes, just doesn't generate a treatment episode. | ✓ |
| Remove everywhere | Remove from both DRUG_GROUPINGS and cohort predicates. A status/complication code alone would no longer indicate SCT history. | |
| Case-by-case | Remove most from both but keep specific ones (e.g., keep HEMATOLOGIC_TRANSPLANT_AND_ENDOC in cohort since it's a registry flag, remove diagnosis codes from both). | |

**User's choice:** DRUG_GROUPINGS only (Recommended)
**Notes:** Cohort predicates serve a different purpose (detecting SCT history) vs treatment detection (generating episodes). Removing from DRUG_GROUPINGS is sufficient to prevent false-positive episodes.

---

## Impact Documentation

| Option | Description | Selected |
|--------|-------------|----------|
| Inline comments only | Add a comment block above each removed code line explaining why it's a false positive. No separate impact document. | ✓ |
| Console message at runtime | When R/28 runs, log a message like 'NOTE: 5 status/complication codes excluded from SCT detection (Phase 90)'. Plus inline comments. | |
| Brief markdown doc | Create .planning/code-removal-impact.md with a table of the 5 codes, their descriptions, and rationale. No before/after episode counts. | |

**User's choice:** Inline comments only (Recommended)
**Notes:** REQUIREMENTS.md explicitly lists "Impact analysis before SCT code removal" as Out of Scope. Inline comments provide sufficient audit trail.

---

## Smoke Test Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| New section after 15 | Add a dedicated section that asserts the 5 removed codes are NOT present in DRUG_GROUPINGS. Keeps validation isolated and easy to find. | ✓ |
| Extend Section 15 | Add checks within existing Section 15 (episode enrichment). Logically adjacent since it's about treatment episodes. | |
| Prepend to Section 1 | Put config validation at the very start of the smoke test — fail fast if deprecated codes sneak back in. | |

**User's choice:** New section after 15 (Recommended)
**Notes:** Dedicated section keeps SCT code validation isolated from episode enrichment validation. Easy to find and maintain.

---

## Code Description Cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Keep descriptions | These codes still appear in DIAGNOSIS data and cohort predicates. Descriptions remain useful for display/reference even though the codes no longer trigger treatment episodes. | ✓ |
| Remove descriptions | Clean break — if they're not treatment codes anymore, remove descriptions too. Risk: downstream displays may show raw codes without labels. | |
| Move to archive section | Keep descriptions but move them to a clearly-labeled 'deprecated treatment codes' section within R/42/R/58. | |

**User's choice:** Keep descriptions (Recommended)
**Notes:** Codes still exist in the data and are used by cohort predicates. Descriptions remain valuable for any display that encounters these codes.

---

## Claude's Discretion

- Exact section numbering for new smoke test section (after Section 15)
- Comment format/wording for inline removal rationale

## Deferred Ideas

None — discussion stayed within phase scope
