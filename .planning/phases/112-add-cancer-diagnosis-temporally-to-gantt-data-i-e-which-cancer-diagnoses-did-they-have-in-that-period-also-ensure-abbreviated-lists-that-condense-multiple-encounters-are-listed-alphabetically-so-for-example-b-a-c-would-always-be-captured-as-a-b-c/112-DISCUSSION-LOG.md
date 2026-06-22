# Phase 112: Add Cancer Diagnosis Temporally to Gantt Data - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-22
**Phase:** 112-add-cancer-diagnosis-temporally-to-gantt-data
**Areas discussed:** Diagnosis date range, New columns design, Alphabetical sort audit, Sort direction

---

## Diagnosis Date Range

| Option | Description | Selected |
|--------|-------------|----------|
| Strict episode span | Only diagnoses where DX_DATE falls between episode_start and episode_stop | |
| Episode span + 30-day pre-buffer | Include diagnoses from 30 days before episode_start through episode_stop | |
| Episode span + buffer both sides | Include diagnoses from 30 days before episode_start through 30 days after episode_stop | ✓ |

**User's choice:** Episode span + buffer both sides

**Follow-up: Buffer size**

| Option | Description | Selected |
|--------|-------------|----------|
| 30 days both sides | Consistent with existing 30-day convention in R/28 linkage | ✓ |
| 7 days both sides | Tighter window — only captures diagnoses very close to episode boundaries | |
| 30 days before, 7 days after | Asymmetric — wider pre-episode window, tighter post-episode | |

**User's choice:** 30 days both sides

---

## New Columns Design

| Option | Description | Selected |
|--------|-------------|----------|
| Both codes + categories | Two new columns: ICD codes and category names, both comma-separated | ✓ |
| Category names only | One column with category names | |
| Codes only | One column with ICD codes | |

**User's choice:** Both codes + categories, with deduplication
**Notes:** User specified "codes and categories and deduplicate"

**Follow-up: Existing cancer_category column**

| Option | Description | Selected |
|--------|-------------|----------|
| Keep alongside (Recommended) | Keep existing single-value cancer_category, add new temporal columns separately | ✓ |
| Replace it | Remove cancer_category and replace with new multi-value columns | |

**User's choice:** Keep alongside (Recommended)

---

## Alphabetical Sort Audit

| Option | Description | Selected |
|--------|-------------|----------|
| All multi-value fields | Audit every comma/semicolon-separated field across entire Gantt export | ✓ |
| New fields + existing cancer fields | Targeted scope — new columns plus existing cancer-related fields | |
| New fields only | Minimal touch — only ensure new temporal diagnosis columns are sorted | |

**User's choice:** All multi-value fields

---

## Sort Direction

| Option | Description | Selected |
|--------|-------------|----------|
| All ascending (A-Z) | Every multi-value field sorts alphabetically ascending | ✓ |
| Match TABLE-2 convention | Codes ascending, category names descending (matching Phase 111 R/36) | |

**User's choice:** All ascending (A-Z)

**Follow-up: Fix TABLE-2 descending sort**

| Option | Description | Selected |
|--------|-------------|----------|
| Fix TABLE-2 too | Change R/36 cancer_category_names from descending to ascending | ✓ |
| Leave TABLE-2 as-is | Only change Gantt data | |

**User's choice:** Fix TABLE-2 too — all outputs follow the same ascending rule

---

## Claude's Discretion

- Column naming for new temporal diagnosis fields
- Pipeline placement of temporal diagnosis query
- Whether new columns appear in gantt_detail.csv in addition to gantt_episodes.csv

## Deferred Ideas

None — discussion stayed within phase scope
