# Phase 155: Binary Indicator and Cutoff Memo — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-18
**Phase:** 155-binary-indicator-and-cutoff-memo
**Areas discussed:** E_binary_by_cutoff sheet design, Sensitivity harness format (155-03), Memo content and literature sources (155-02), Dotted cutoff lines in PNGs

---

## E_binary_by_cutoff Sheet Design

| Option | Description | Selected |
|--------|-------------|----------|
| Both encounter and patient rows | Two row-groups stacked; mirrors A_distribution_summary | ✓ |
| Encounter-level only | Simpler; patient-level via rds only | |
| Patient-level only | Clinically relevant grain | |

**User's choice:** Both encounter and patient rows

| Option | Description | Selected |
|--------|-------------|----------|
| Live cutoff only | Sheet regenerated when CONFIG updated; harness handles comparison | ✓ |
| All candidate_cutoffs_mi side-by-side | Multi-column; overlaps 155-03 | |

**User's choice:** Live cutoff only

| Option | Description | Selected |
|--------|-------------|----------|
| payer_category_9 | 9-category canonical payer variable | ✓ |
| payer_category_primary | Primary-payer tiered resolution | |
| You decide | Claude picks from AM Insurance domain | |

**User's choice:** payer_category_9

---

## Sensitivity Harness Format (155-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Extra sheet in existing workbook (F_sensitivity_cutoffs) | Always present; one row per candidate cutoff | ✓ |
| Separate xlsx file | Shareable separately but adds a second file | |
| Standalone script | Keeps R/122 narrow but adds a new script | |

**User's choice:** Extra sheet in existing workbook

| Option | Description | Selected |
|--------|-------------|----------|
| CONFIG$distance_candidate_cutoffs_mi (default c(30, 50)) | Re-uses validated config vector | ✓ |
| Fixed hard-coded sweep | More values by default | |
| Both config + additional literature values | Requires hard-coding extra values | |

**User's choice:** CONFIG$distance_candidate_cutoffs_mi

| Option | Description | Selected |
|--------|-------------|----------|
| Always | Sheet present regardless of cutoff setting | ✓ |
| Only when distance_cutoff_mi is NA | Omitted once cutoff chosen | |

**User's choice:** Always

---

## Memo Content and Literature Sources (155-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Leave placeholders | [CITE: HL access literature] — Amy/Erin fill in | ✓ |
| Illustrative text citing NCI/CMS rural designations | No specific paper pinned | |
| Agent researches and inserts actual citations | Risk of fabricated DOIs | |

**User's choice:** Leave placeholders

| Option | Description | Selected |
|--------|-------------|----------|
| payer_category_9 | Consistent with E_binary_by_cutoff | ✓ |
| 4-group rollup | Easier to read; requires new rollup step | |

**User's choice:** payer_category_9

| Option | Description | Selected |
|--------|-------------|----------|
| Shape only (single cutoff vs. categorical bands) | Consistent with milestone spec | ✓ |
| Recommend a specific value with rationale | Presupposes a value Gerard/Claude shouldn't decide | |

**User's choice:** Shape only

---

## Dotted Cutoff Lines in PNGs

| Option | Description | Selected |
|--------|-------------|----------|
| Pass candidate_cutoffs_mi to plot_distance_hist() | Wire deferred comment at R/122:1146 | ✓ |
| Only when distance_cutoff_mi is set | Lines at live cutoff only | |
| No — keep PNGs as Phase 154 | Defer until team sets cutoff | |

**User's choice:** Pass candidate_cutoffs_mi — dotted lines at all candidates (30, 50 mi default)

---

## Deferred Ideas

- Actual cutoff value selection (D-06) — pending Amy/Erin decision after memo review
- Drive-time proxy computation — future phase
- Wiring far_from_care into main modeling pipeline — awaits team decision
