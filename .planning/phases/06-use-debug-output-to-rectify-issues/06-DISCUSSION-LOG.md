# Phase 6: Use Debug Output to Rectify Issues - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 06-use-debug-output-to-rectify-issues
**Areas discussed:** Issue triage, Fix approach, Validation strategy, Cohort rebuild scope

---

## Issue Triage

### Q1: Which diagnostic findings warrant code fixes?

| Option | Description | Selected |
|--------|-------------|----------|
| Fix everything fixable | Any issue that CAN be fixed in code should be. Only document truly unfixable data-level problems. | Y |
| Focus on pipeline-breaking | Only fix issues that break the cohort build or produce wrong results. | |
| Fix what affects cohort | Fix date parsing and HL identification issues that change the final cohort only. | |

**User's choice:** Fix everything fixable
**Notes:** None

### Q2: What to do with "Neither" HL source patients?

| Option | Description | Selected |
|--------|-------------|----------|
| Flag and exclude | Remove from cohort, write to separate CSV audit trail. | Y |
| Flag but keep | Keep in cohort with HL_SOURCE = 'None' column. | |
| You decide | Claude picks most clinically appropriate approach. | |

**User's choice:** Flag and exclude
**Notes:** None

### Q3: Date parsing failures -- expand parser?

| Option | Description | Selected |
|--------|-------------|----------|
| Expand parser | Add new date formats discovered by diagnostics. Minimize character-type date columns. | Y |
| Current parser is fine | 4-format chain covers main cases. Remaining failures are genuinely missing/garbage. | |
| Depends on failure rate | Expand only if >5% of column values fail to parse. | |

**User's choice:** Expand parser
**Notes:** None

### Q4: Payer mapping audit reconciliation

| Option | Description | Selected |
|--------|-------------|----------|
| Exact match target | Investigate every discrepancy until R and Python counts match exactly. | |
| Within 5% is fine | Accept if category counts are within 5% of Python reference. | |
| Document differences | Document R vs Python counts side-by-side. Exact parity not required. | Y |

**User's choice:** Document differences
**Notes:** None

### Q5: TUMOR_REGISTRY column type mismatches

| Option | Description | Selected |
|--------|-------------|----------|
| Update specs | Add explicit col_double() or col_date() for all flagged columns in TABLE_SPECS. | Y |
| Only critical columns | Only fix types for columns actually used in the pipeline. | |
| You decide | Claude determines which column type changes are worth making. | |

**User's choice:** Update specs
**Notes:** None

### Q6: Encoding issues

| Option | Description | Selected |
|--------|-------------|----------|
| Strip during load | Add encoding cleanup to load_pcornet_table(). | |
| Flag only | Document encoding issues but don't change the loader. | Y |
| You decide | Claude determines based on impact. | |

**User's choice:** Flag only
**Notes:** None

### Q7: Column detection regex

| Option | Description | Selected |
|--------|-------------|----------|
| Expand regex | Add any missed date columns to regex pattern. | Y |
| Only if pipeline uses them | Only expand for date columns used downstream. | |
| You decide | Claude determines based on audit results. | |

**User's choice:** Expand regex
**Notes:** None

### Q8: Numeric range issues

| Option | Description | Selected |
|--------|-------------|----------|
| Clean invalid values | Set clearly invalid values to NA. | |
| Flag but keep raw | Add validation column but preserve original value. | Y |
| Just document | Document counts only, don't modify data. | |

**User's choice:** Flag but keep raw
**Notes:** None

### Q9: Missing value columns

| Option | Description | Selected |
|--------|-------------|----------|
| Purely informational | Missing values are expected in PCORnet data. Just document. | |
| Investigate high-miss columns | For >50% missing, investigate parsing vs. genuinely absent. Fix if parsing issue. | Y |
| You decide | Claude determines based on cohort-critical fields. | |

**User's choice:** Investigate high-miss columns
**Notes:** None

---

## Fix Approach

### Q10: Where should fixes live?

| Option | Description | Selected |
|--------|-------------|----------|
| Patch existing scripts | Fix directly in existing pipeline scripts. No separate fix step. | Y |
| Dedicated fix script | Create 08_apply_fixes.R that runs after diagnostics. | |
| Both | Permanent improvements in existing scripts, one-time patches in dedicated script. | |

**User's choice:** Patch existing scripts
**Notes:** None

### Q11: Fix trigger -- diagnostics-driven or preemptive?

| Option | Description | Selected |
|--------|-------------|----------|
| Run diagnostics first | User runs diagnostics on HiPerGator, shares output, Claude writes targeted fixes. | Y |
| Preemptive fixes | Claude writes fixes now based on known patterns. | |
| Hybrid | Preemptive for known issues + fix template for data-driven corrections. | |

**User's choice:** Run diagnostics first
**Notes:** None

### Q12: How to share diagnostic output?

| Option | Description | Selected |
|--------|-------------|----------|
| Paste console output | Copy-paste message() output from RStudio. | |
| Share CSV files | Copy diagnostic CSVs from HiPerGator and share file paths. | Y |
| Both | Paste console summary + share specific CSVs for detail. | |

**User's choice:** Share CSV files
**Notes:** None

### Q13: Should Claude see sample raw data rows?

| Option | Description | Selected |
|--------|-------------|----------|
| Diagnostic summaries only | Claude works from diagnostic CSVs only. | |
| Sample rows too | User also shares sample rows from raw CSVs for tricky issues. | Y |
| You decide per issue | Start with summaries, provide samples on request. | |

**User's choice:** Sample rows too
**Notes:** None

### Q14: Iteration strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Iterate until clean | Multiple rounds until diagnostic output is satisfactory. | Y |
| Single batch | One round of fixes, verify on HiPerGator. | |
| Two rounds max | Initial batch + one refinement round. | |

**User's choice:** Iterate until clean
**Notes:** None

### Q15: Fix batching

| Option | Description | Selected |
|--------|-------------|----------|
| All at once | Apply all fixes across files simultaneously. | |
| One file at a time | Fix one script, verify, then next. | |
| Group by issue type | Batch by category (date, col_type, payer). | Y |

**User's choice:** Group by issue type
**Notes:** None

---

## Validation Strategy

### Q16: Verification method

| Option | Description | Selected |
|--------|-------------|----------|
| Full re-run | Re-run 07_diagnostics.R after each fix batch. | |
| Targeted checks | Run only relevant diagnostic section per fix. | |
| Full at end, targeted per batch | Quick targeted checks per batch, full re-run at end. | Y |

**User's choice:** Full at end, targeted per batch
**Notes:** None

### Q17: Section-level runs for diagnostics?

| Option | Description | Selected |
|--------|-------------|----------|
| Add section flags | Add DIAGNOSTIC_SECTIONS config variable for targeted runs. | |
| Whole script is fine | 07_diagnostics.R runs fast enough on HiPerGator. | Y |
| You decide | Claude determines based on complexity and runtime. | |

**User's choice:** Whole script is fine
**Notes:** None

### Q18: "Clean enough" threshold

| Option | Description | Selected |
|--------|-------------|----------|
| Zero parse failures | All date columns parse as Date type, no character leftovers. | |
| Reasonable improvement | Significant reduction vs. baseline. Some residual NAs fine. | |
| All issues explained | Every remaining issue has an explanation. No unexplained anomalies. | Y |

**User's choice:** All issues explained
**Notes:** None

### Q19: Summary report format

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, markdown report | Create data quality summary markdown in output/. | |
| Yes, CSV summary | CSV with issue_type, count_before, count_after, status, notes. | Y |
| No separate report | Diagnostic CSVs + console output are sufficient. | |

**User's choice:** Yes, CSV summary
**Notes:** None

---

## Cohort Rebuild Scope

### Q20: Pipeline rebuild scope

| Option | Description | Selected |
|--------|-------------|----------|
| Full end-to-end | Re-run entire pipeline from loading through visualization. | Y |
| Up to cohort only | Rebuild through 04_build_cohort.R only. | |
| Depends on what changed | Rebuild from the earliest changed script onward. | |

**User's choice:** Full end-to-end
**Notes:** None

### Q21: Update diagnostics script?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, keep in sync | Update 07_diagnostics.R if fixes change column names, structure, or detection logic. | Y |
| No, diagnostics are stable | 07_diagnostics.R audits generically, shouldn't need changes. | |

**User's choice:** Yes, keep in sync
**Notes:** None

### Q22: Exclusion CSV for "Neither" patients

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, separate CSV | Write to output/cohort/excluded_no_hl_evidence.csv with ID, SOURCE, reason. | Y |
| Include in diagnostics | Already captured in hl_identification_detail.csv. | |
| Both | Separate exclusion CSV AND diagnostics. | |

**User's choice:** Yes, separate CSV
**Notes:** None

### Q23: HL_SOURCE column in rebuilt cohort

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add HL_SOURCE | Column showing 'DIAGNOSIS only', 'TR only', 'Both'. | Y |
| No, not needed | How patients were identified is captured in diagnostics. | |
| You decide | Claude determines based on downstream script needs. | |

**User's choice:** Yes, add HL_SOURCE
**Notes:** None

---

## Claude's Discretion

- Specific date format patterns to add to parse_pcornet_date() (depends on diagnostics)
- Which col_types to change for TUMOR_REGISTRY columns (depends on type audit)
- Exact regex additions for date column detection
- Plausible numeric ranges for validation columns
- Structure of data quality summary CSV
- How to implement HL_SOURCE column in cohort build

## Deferred Ideas

None -- discussion stayed within phase scope
