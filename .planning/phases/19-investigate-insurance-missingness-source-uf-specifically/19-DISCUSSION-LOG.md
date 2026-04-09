# Phase 19: Investigate Insurance Missingness Source UF Specifically - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-09
**Phase:** 19-investigate-insurance-missingness-source-uf-specifically
**Areas discussed:** Missingness definition, Investigation scope, Output & deliverables, Root cause hypotheses

---

## Missingness Definition

### Q1: What does 'missing insurance' mean for this investigation?

| Option | Description | Selected |
|--------|-------------|----------|
| PAYER_TYPE fields empty/sentinel | Focus on PAYER_TYPE_PRIMARY being NA, NI, UN, OT, or empty on encounter records | ✓ |
| No enrollment records at all | Focus on patients who appear in DEMOGRAPHIC/ENCOUNTER but have zero rows in ENROLLMENT | |
| Both encounter + enrollment gaps | Investigate both: encounters with missing PAYER_TYPE AND patients with no enrollment records | |

**User's choice:** PAYER_TYPE fields empty/sentinel (Recommended)
**Notes:** Direct insurance variable missingness on encounters

### Q2: Should we also track PAYER_TYPE_SECONDARY missingness?

| Option | Description | Selected |
|--------|-------------|----------|
| Both PRIMARY and SECONDARY | Track missingness on both fields | ✓ |
| PRIMARY only | Keep it simple: only look at PAYER_TYPE_PRIMARY | |

**User's choice:** Both PRIMARY and SECONDARY (Recommended)

### Q3: How should sentinel codes (NI, UN, OT) be treated?

| Option | Description | Selected |
|--------|-------------|----------|
| Count as missing | NI, UN, OT are functionally missing insurance | ✓ |
| Separate category | Distinguish true NA/empty from sentinel codes | |
| Only NA/empty counts | Exclude sentinel codes from missingness definition | |

**User's choice:** Count as missing (Recommended)

### Q4: Should 99/9999 ('Unavailable') also count as missing?

| Option | Description | Selected |
|--------|-------------|----------|
| Count as missing | 99/9999 is 'Unavailable' — effectively no usable insurance info | ✓ |
| Separate from missing | 99/9999 maps to 'Unavailable' which is a valid code | |

**User's choice:** Count as missing (Recommended)

---

## Investigation Scope

### Q5: UF-only deep dive or UF-vs-all-sites comparison?

| Option | Description | Selected |
|--------|-------------|----------|
| UF vs all sites comparison | Compare UF's missingness rates against all other sites | |
| UF-only deep dive | Focus exclusively on UF patients | ✓ |
| All sites profiled, UF highlighted | Full missingness profile for every site with UF highlighted | |

**User's choice:** UF-only deep dive

### Q6: Which UF patients should be examined?

| Option | Description | Selected |
|--------|-------------|----------|
| All UF patients in cohort | Every UFH patient in HL cohort — compare missing vs valid payer | ✓ |
| Only UF patients with missing payer | Narrow to just UFH patients where payer is missing | |
| All UF patients in raw data | Go beyond the cohort — all UFH patients in raw tables | |

**User's choice:** All UF patients in cohort (Recommended)

### Q7: Should the investigation break down by time period?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, by year | Break down payer missingness by encounter year | |
| Yes, by encounter type | Break down by ENC_TYPE | |
| Both year and encounter type | Cross-tabulate by year AND encounter type | |
| No time/type breakdown | Just total counts | |

**User's choice:** Free text — "year encounter type and anything else research reveals as worth looking into"
**Notes:** User wants all dimensions explored, researcher discretion on additional breakdowns

---

## Output & Deliverables

### Q8: What should the investigation produce?

| Option | Description | Selected |
|--------|-------------|----------|
| R script + CSV output | New diagnostic R script producing CSV files | ✓ |
| R script + PPTX slides | Script plus new PPTX slides visualizing patterns | |
| R script + CSV + console summary | Both CSV audit files AND console summary report | |

**User's choice:** R script + CSV output (Recommended)

### Q9: Where should CSV output go?

| Option | Description | Selected |
|--------|-------------|----------|
| output/tables/ | Same directory as existing analysis outputs | ✓ |
| output/audit/ | New subdirectory for audit/investigation outputs | |
| You decide | Claude picks best location | |

**User's choice:** output/tables/ (Recommended)

### Q10: Standalone or integrated into pipeline?

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone diagnostic | Run independently, sources own dependencies | ✓ |
| Part of pipeline | Integrate into numbered pipeline sequence | |

**User's choice:** Standalone diagnostic (Recommended)

---

## Root Cause Hypotheses

### Q11: What do you suspect is driving UF missingness?

| Option | Description | Selected |
|--------|-------------|----------|
| Data submission gap | UF may not submit payer data in certain encounter types or time periods | ✓ |
| Encounter coding patterns | UF may code encounters differently | |
| Not sure — investigate all | No strong hypothesis, explore all dimensions | |
| Enrollment table sparsity | UF patients may have encounters but no enrollment records | |

**User's choice:** Data submission gap

### Q12: Specific patterns already noticed?

| Option | Description | Selected |
|--------|-------------|----------|
| High 'Missing' rate in PPTX | UF contributes disproportionately to Missing payer | |
| Specific years affected | Missingness concentrated in certain years | |
| No specific observation yet | First look at UF-specific data | ✓ |
| Compared to Python pipeline | Python pipeline shows different UF payer rates | |

**User's choice:** No specific observation yet

### Q13: Raw or derived level investigation?

| Option | Description | Selected |
|--------|-------------|----------|
| Both raw and derived | Check raw PAYER_TYPE fields AND derived PAYER_CATEGORY_PRIMARY | ✓ |
| Raw encounter fields only | Focus on source data before harmonization | |
| Derived payer_summary only | Focus on end result after harmonization | |

**User's choice:** Both raw and derived (Recommended)

---

## Claude's Discretion

- Exact CSV file names and column structures
- Additional breakdown dimensions beyond year and encounter type
- Console logging format and verbosity
- Script number assignment
- How to identify UFH patients (SOURCE column matching)

## Deferred Ideas

None — discussion stayed within phase scope
