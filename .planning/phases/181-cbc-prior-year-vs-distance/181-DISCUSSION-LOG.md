# Phase 181: CBC Prior-Year vs Distance — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-14
**Phase:** 181-cbc-prior-year-vs-distance
**Areas discussed:** Prior-year definition, Phase 180 memo numbers, QC sheet content, Memo structure

---

## Prior-Year Definition

| Option | Description | Selected |
|--------|-------------|----------|
| Working assumption — use max year_index, note pending in KEY | Proceed with max year_index; add KEY note that Erin/Ray confirmation is pending | ✓ |
| Confirmed by Erin/Ray — max year_index is final | Remove pending caveat | |
| Different definition | e.g., calendar year or most recent year with ≥1 encounter | |

**User's choice:** Working assumption, not confirmed by Erin/Ray. "Prior year" = each patient's most recent fully observed follow-up year (max year_index in Phase 179 RDS). Primary = patients whose most recent full year is year_index ≥ 2; secondary = all patients. KEY and memo label it "working definition — confirm with Erin/Ray."

**Notes:** Also report a sensitivity using the year immediately before the CDM cutoff for patients followed to the cutoff (common calendar-window definition), so the team can compare if they meant a fixed calendar year.

---

## Phase 180 Memo Numbers

| Option | Description | Selected |
|--------|-------------|----------|
| From actual Phase 180 run — I'll confirm group labels | Numbers are real; specify group mapping | |
| Placeholder — script pulls from Phase 180 RDS/xlsx at runtime | Generated, not hand-coded | |
| From actual run: single-source = 0.754, multi-source = 1.068 | | |
| From actual run: single-source = 1.068, multi-source = 0.754 | | |

**User's choice:** From actual Phase 180 run (output/cbc_missing_capture_<date>.xlsx, committed). Do NOT hard-code numbers — memo reads every Phase 179/180 number from those workbooks by exact label at runtime. Take group assignment (single_source_care_post = 1 vs = 0) from the MISS-04 sheet directly; if reversed from the expected mapping, say so plainly because interpretation changes. Note in memo that "out of system" = outside the OneFlorida+ network.

---

## QC Sheet Content

| Option | Description | Selected |
|--------|-------------|----------|
| Row counts + suppression log + reproducibility hash | N counts, suppressed cells, checksum of input RDS | |
| Row counts + suppression log + prior-year definition note | N counts, suppressed cells, working-definition caveat | |
| Row counts + suppression log only | Minimal | |
| You decide — follow Phase 180 QC sheet as precedent | Mirror Phase 180 | |

**User's choice:** Specific QC rows defined:
- Input files (Phase 179 RDS name, Phase 180 workbook name) and run date
- Patients in Phase 179 RDS; with exposure; missing exposure (excluded); in primary (most recent year ≥ 2) and secondary sets
- Reconciliation: 2×2 cells sum to analytic N — TRUE/FALSE for each set
- Expected cell counts and which test was used (chi-squared vs Fisher) and why
- Check that "prior year" chosen equals each patient's max year_index — TRUE/FALSE
- Count of cells suppressed (<11) per sheet
- Sensitivity N (CDM-cutoff definition) vs primary N

---

## Memo Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Headed sections, narrative paragraphs, ~1 page | Five labeled sections, 2-4 sentences each | |
| Headed sections with tight bullet lists, ~1 page | Five sections, 2-4 bullets each | |
| Short prose intro + numbered elements, ~1 page | One-paragraph context + five numbered items | |
| You decide — optimize for Amy/Erin | Choose format for clinical researchers | ✓ |

**User's choice:** Short headed sections with bullets under each, neutral language, one page. Six sections:
1. Question and definitions
2. Prior-year result (2×2 rates, OR, CI, test; primary and secondary)
3. Relationship to earlier analyses (Phase 165 vs Phase 179 OR comparison)
4. Robustness (missing-distance bounds; note not-far bound CI crosses 1)
5. Capture check (37.4% shrinkage; single-system split with groups named; "consistent with", not proof)
6. Decisions needed (D-15, confirm prior-year definition)

No patient-level data; counts 1–10 as "<11".

---

## Claude's Discretion

- Minor workbook formatting (column widths, freeze panes)
- Exact wording of neutral-language sentences within the memo's structure
- chi-sq vs Fisher branch at runtime based on expected cell counts

## Deferred Ideas

None.
