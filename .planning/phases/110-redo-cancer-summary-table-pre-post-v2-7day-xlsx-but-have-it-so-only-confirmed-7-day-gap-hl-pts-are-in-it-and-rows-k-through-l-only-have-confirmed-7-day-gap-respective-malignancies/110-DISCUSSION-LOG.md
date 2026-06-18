# Phase 110: Redo Cancer Summary Table V2 7-Day (Confirmed HL Only) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-18
**Phase:** 110-redo-cancer-summary-table-pre-post-v2-7day
**Areas discussed:** Output file strategy, Script approach, Both column (M) rule, Code-level sheet scope

---

## Output File Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Replace v2_7day | Overwrite existing cancer_summary_table_pre_post_v2_7day.xlsx with the new restricted version. The current v2 becomes obsolete since the new version is strictly better (tighter population). V1 (unfiltered) still preserved. | ✓ |
| New file alongside | Create a new file like cancer_summary_table_pre_post_v3_confirmed_hl.xlsx. Keeps existing v2 for comparison. Adds a third output variant. | |
| You decide | Claude picks the approach based on codebase patterns and simplicity. | |

**User's choice:** Replace v2_7day (Recommended)
**Notes:** V1 remains as baseline comparison. No need for a third variant.

---

## Script Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Modify R/49 in-place | Update the existing V2 section (Section 8b) in R/49 to use 7-day confirmed HL population + 7-day confirmed secondary malignancy filtering. R/49 already has the V2 code path — just tighten the filters. No new script needed. | ✓ |
| New standalone script | Create a new R/50 script that reads the same inputs as R/49 but applies the tighter filters. Keeps R/49 untouched. Adds a new file to maintain. | |

**User's choice:** Modify R/49 in-place (Recommended)
**Notes:** R/49 Section 8b already has the V2 dual-output structure. Tighten filters within existing code.

---

## Both Column (M) Rule

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, same rule as K-L | Column M counts patients who had the same 7-day confirmed secondary malignancy both before AND after HL dx. Consistent with K-L — all three temporal columns use the same 7-day confirmed filter. | ✓ |
| No, M stays unfiltered | K-L get the 7-day filter but M counts any patient with pre+post codes regardless of confirmation. Creates an inconsistency between columns. | |

**User's choice:** Yes, same rule as K-L (Recommended)
**Notes:** Consistent filtering across all three temporal columns.

---

## Code-Level Sheet Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, both sheets | Both Sheet 1 (Category Summary) and Sheet 2 (Code Summary) restrict to 7-day confirmed HL population with 7-day confirmed K-L-M. Keeps the workbook internally consistent. | ✓ |
| Sheet 1 only | Only the Category Summary sheet gets the tighter filtering. Code Summary stays as-is with the broader v2 population. Allows code-level detail for the broader set. | |

**User's choice:** Yes, both sheets (Recommended)
**Notes:** Workbook stays internally consistent.

---

## Claude's Discretion

- Assertion bound adjustments for tighter population
- Footnote and title text updates
- Console logging structure
- V1-vs-V2 comparison adjustments

## Deferred Ideas

None — discussion stayed within phase scope
