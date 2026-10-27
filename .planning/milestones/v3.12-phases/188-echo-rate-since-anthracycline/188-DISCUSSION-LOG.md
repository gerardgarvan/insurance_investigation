# Phase 188: Echo Rate Since Anthracycline - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-22
**Phase:** 188-echo-rate-since-anthracycline
**Areas discussed:** Echo event source, Reconciliation column design, Phase 166 comparison table structure, Output workbook layout

---

## Echo Event Source

| Option | Description | Selected |
|--------|-------------|----------|
| survivorship_dated_events RDS from R/166 | Same file R/167 uses; modality-filtered; pinned | ✓ |
| patient-modality RDS from R/147 | Patient-level counts, not encounter dates — wrong grain | |
| Re-query DuckDB | Duplicates R/166 logic; more complexity | |

**User's choice:** Use same echo events R/166 used for anthracycline-to-echo timing, so ECHO-02 compares like with like. Source must include all echo dates (pre- and post-dose). Pin via `R188_DATED_EVENTS`, not file.mtime(). Patient set from R/187 output. Echoes after `follow_end` counted on QC.

**Notes:** R/167 currently picks dated_events by `sort(..., decreasing=TRUE)[1L]` — the anti-pattern. R/188 must pin explicitly. Schema probe required before planning.

---

## Reconciliation Column Design

| Option | Description | Selected |
|--------|-------------|----------|
| Patient-grain column in internal RDS + QC sheet aggregate | Per-patient count stored internally; aggregate only in workbook | ✓ |
| Aggregate-only in QC sheet | Simpler but patient-level count unrecoverable | |
| Separate per-patient QC sheet in workbook | Exposes patient-level data in output/ — violates privacy rule | |

**User's choice (n_echoes_before_or_on_last_dose):** Patient-grain in internal RDS + aggregate on QC sheet.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — n_echoes_after_follow_end in internal RDS + QC | Makes edge case explicit and auditable | ✓ |
| No — only n_echoes_before_or_on_last_dose needed | Simpler; ECHO-01/02 don't require it | |

**User's choice (n_echoes_after_follow_end):** Yes, include in both internal RDS and QC sheet.

---

## Phase 166 Comparison Table Structure (ECHO-02)

| Option | Description | Selected |
|--------|-------------|----------|
| anchor, n_patients, n_echoes_post, person_years, rate_per_py + delta row | Side-by-side comparison with numeric delta | ✓ (modified) |
| Patient-level shift counts only | Less granular | |
| Full per-patient crosstab | Patient-level in internal RDS; aggregate delta on QC | |

**User's choice:** Option 1 columns with three changes: (a) Phase 166 row labeled by its actual anchor from `166-03-SUMMARY.md`, not "first dose"; (b) Phase 166 values read by exact label from Phase 166's pinned output — never recomputed; (c) add a row showing patients whose anchor date differs between definitions. Own sheet: "Anchor Comparison".

| Option | Description | Selected |
|--------|-------------|----------|
| Own sheet: 'Anchor Comparison' | Dedicated sheet for ECHO-02 | ✓ |
| QC sheet (same as reconciliation) | Mixed concerns | |
| KEY sheet narrative + inline numbers | Harder to parse | |

**User's choice:** Own sheet, name exactly "Anchor Comparison".

**Notes — D-08a finding:** Phase 166's `last_dose_firstline_dt` equals `last_dose_ever_dt` in this extract because `first_line` was absent from the 180-day file. Delta row will show zero or near-zero patient/echo shifts. Do not assume zeros — read Phase 166 values from its output. KEY explains the D-08a equivalence and names any non-anchoring differences that produce nonzero delta.

---

## Output Workbook Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Aggregate summary only — one row | Population-level rate; patient detail stays internal | ✓ |
| Per-patient rate table in workbook | Patient-level in output/ — violates privacy rule | |
| Stratified by clinical variable | Adds texture; may require suppression | |

**User's choice (Rates sheet):** One aggregate row: n_patients, total_echoes_post, total_person_years, rate_per_py.

| Option | Description | Selected |
|--------|-------------|----------|
| KEY / Rates / Anchor Comparison / QC (four sheets) | Clean separation | ✓ |
| KEY / Rates / QC (three sheets, reconciliation on QC) | Mixed concerns | |
| KEY / Rates (two sheets) | Too compact | |

**User's choice (sheet order):** KEY, Rates, Anchor Comparison, QC — exactly in this order.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — encounter-grain in output/internal/ | REQUIREMENTS scope it here; all echoes for exposed patients | ✓ (modified) |
| No — defer to Phase 189 | Not needed for rate computation | |

**User's choice (days_since_last_anthracycline_dose):** All echoes for exposed patients in encounter-grain internal RDS: ID, echo_date, days_since_last_anthracycline_dose (negative/zero for pre/on-dose), window_label (on_or_before_last_dose / after_last_dose / after_follow_end). Patient-grain counts derived from this file.

---

## Claude's Discretion

- Section structure within R/188
- Whether to probe the output workbook for downstream phases

## Deferred Ideas

None — discussion stayed within phase scope.
