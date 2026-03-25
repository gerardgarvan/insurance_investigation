# Phase 5: Fix Parsing & Investigate HL Diagnosis Gaps - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 05-fix-parsing-of-dates-and-other-possible-parsing-errors-and-investigate-why-not-everyone-has-an-hl-diagnosis
**Areas discussed:** Date parsing diagnosis, HL diagnosis gap investigation, Fix vs report strategy, Other parsing errors scope

---

## Date Parsing Diagnosis

### Q1: Have you seen specific date parsing failures?

| Option | Description | Selected |
|--------|-------------|----------|
| Saw specific failures | Noticed NA dates, warnings, or incorrect values in output | |
| Preventive check | Haven't run it yet on HiPerGator | |
| Both | Saw some issues AND want thorough audit | ✓ |

**User's choice:** Both
**Notes:** User has seen some issues and wants comprehensive audit

### Q2: When date parsing fails, what should happen?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep as NA + log | Leave unparseable as NA, log count and samples | |
| Write diagnostic CSV | Dump all unparseable values to CSV | |
| Both (Recommended) | Keep as NA AND write diagnostic CSV | ✓ |

**User's choice:** Both (Recommended)

### Q3: Scope of date column audit?

| Option | Description | Selected |
|--------|-------------|----------|
| All 9 tables (Recommended) | Systematic audit of every date column across all loaded tables | ✓ |
| Core tables only | Focus on ENROLLMENT, DIAGNOSIS, DEMOGRAPHIC | |
| You decide | Claude picks based on risk | |

**User's choice:** All 9 tables

### Q4: Audit the date column detection regex?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, audit the regex | Compare regex-detected vs known PCORnet date columns | ✓ |
| No, trust the regex | Regex pattern is sufficient | |

**User's choice:** Audit all regex variables (expanded scope beyond just date regex)

---

## HL Diagnosis Gap Investigation

### Q1: What makes you think not everyone has an HL diagnosis?

| Option | Description | Selected |
|--------|-------------|----------|
| Count mismatch | Lower count than expected vs Python pipeline | |
| Missing from filter step | Big drop at has_hodgkin_diagnosis() | |
| Haven't run yet | Cohort extract should be all HL | |
| Specific patients missing | Checked specific IDs | |

**User's choice:** Free text -- "not every person has an HL diagnosis maybe they have diagnosis info is in the tumor tables?"
**Notes:** Key insight that TUMOR_REGISTRY may contain HL evidence not captured by DIAGNOSIS table ICD matching

### Q2: How to handle TR-only patients?

| Option | Description | Selected |
|--------|-------------|----------|
| Include them in cohort | Include if HL evidence in TR even without DIAGNOSIS ICD code | ✓ |
| Report but don't include | Flag but don't change filter chain | |
| Investigate first | Quantify numbers before deciding | |

**User's choice:** Include them in cohort

### Q3: Check beyond ICD codes?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, check histology codes | HISTOLOGY_ICDO3 with HL codes 9650-9667 | ✓ |
| Yes, check all available fields | ICD + histology + cancer type fields | |
| ICD codes only | Expand ICD check to TR but no histology | |

**User's choice:** Yes, check histology codes

### Q4: Add histology codes to config?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add to config (Recommended) | Add ICD_CODES$hl_histology in 00_config.R | ✓ |
| Hardcode in diagnostic | Define inline, config changes later | |
| You decide | Claude picks | |

**User's choice:** Yes, add to config

### Q5: Update has_hodgkin_diagnosis() predicate?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, update the predicate | Modify to check BOTH DIAGNOSIS and TR | ✓ |
| Create new predicate | Separate has_tumor_registry_hl() | |
| You decide | Claude picks | |

**User's choice:** Yes, update the predicate

### Q6: Venn breakdown detail level?

| Option | Description | Selected |
|--------|-------------|----------|
| Full breakdown | DIAGNOSIS-only, TR-only, both. By site. By ICD-9/10/histology | ✓ |
| Summary counts | Just N per source and overlap | |
| You decide | Claude picks | |

**User's choice:** Full breakdown

### Q7: Which TR columns for histology?

| Option | Description | Selected |
|--------|-------------|----------|
| HISTOLOGY_ICDO3 only | Check primary histology field in TR1 | |
| HISTOLOGY_ICDO3 + SITE_ICDO3 | Also verify lymph node site | |
| Check all 3 TR tables | Look for histology fields in TR1, TR2, TR3 | ✓ |

**User's choice:** Check all 3 TR tables

### Q8: Verify extract scope?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, verify extract scope | Check if all DEMOGRAPHIC patients should have HL | ✓ |
| Assume all are HL | Extract should only contain HL patients | |
| Don't assume | Some might be non-HL controls | |

**User's choice:** Yes, verify extract scope

---

## Fix vs Report Strategy

### Q1: What should this phase produce?

| Option | Description | Selected |
|--------|-------------|----------|
| Diagnostic script + fixes | New 07_diagnostics.R AND fixes to existing scripts | ✓ |
| Diagnostic script only | Just the diagnostic, fixes later | |
| Fixes only | Skip diagnostic, directly fix known issues | |

**User's choice:** Diagnostic script + fixes

### Q2: Diagnostic script lifecycle?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep as reusable | Permanent 07_diagnostics.R for ongoing data quality | ✓ |
| Run once, archive | One-time tool, move to archive after | |
| You decide | Claude picks | |

**User's choice:** Keep as reusable

### Q3: Diagnostic output location?

| Option | Description | Selected |
|--------|-------------|----------|
| output/diagnostics/ | New subfolder with CSVs and text summary | |
| Console only | Print to R console via message() | |
| Both (Recommended) | Console summary AND saved CSVs | ✓ |

**User's choice:** Both (Recommended)

### Q4: Fix target?

| Option | Description | Selected |
|--------|-------------|----------|
| Fix existing scripts directly | Update utils_dates.R, 00_config.R, 03_cohort_predicates.R, 01_load_pcornet.R | ✓ |
| Fix in diagnostic, patch later | Corrected logic in 07_diagnostics.R first | |
| Both -- fix + verify | Fix scripts AND have diagnostic verify | |

**User's choice:** Fix existing scripts directly

### Q5: Rebuild cohort after fixes?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, rebuild cohort | Re-run full pipeline to produce updated hl_cohort.csv | ✓ |
| No, fixes only | Just fix code, user rebuilds on HiPerGator | |
| You decide | Claude decides based on environment | |

**User's choice:** Yes, rebuild cohort

---

## Other Parsing Errors Scope

### Q1: Data quality concerns beyond dates?

| Option | Description | Selected |
|--------|-------------|----------|
| Column type mismatches | Verify readr specs match actual data | |
| Missing/extra columns | Compare expected vs actual columns | |
| All of the above + encoding | Types + columns + encoding issues | ✓ |
| You decide | Claude picks most likely issues | |

**User's choice:** All of the above + encoding

### Q2: Site-level completeness analysis?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, site-level audit | Completeness by site per table | |
| Basic site counts only | Row and patient counts per site | |
| Skip site analysis | Focus on parsing errors only | ✓ |

**User's choice:** Skip site analysis

### Q3: Numeric range checks?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, range checks | Flag impossible values with counts and samples | ✓ |
| No, trust the specs | If readr accepted it, it's fine | |
| You decide | Claude picks risky columns | |

**User's choice:** Yes, range checks

### Q4: Audit TUMOR_REGISTRY column types?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, audit TR column types | Check all 314+ TR1 and 140+ TR2/TR3 columns | ✓ |
| No, character is fine | Loading as character is intentional | |
| Just date columns in TR | Only check date detection in TR | |

**User's choice:** Yes, audit TR column types

### Q5: Payer audit scope?

| Option | Description | Selected |
|--------|-------------|----------|
| Out of scope | Payer validated in Phase 2 | |
| Light check only | Quick sanity on unexpected mapping results | |
| Include payer audit | Full audit -- prefix rules, dual-eligible, Python comparison | ✓ |

**User's choice:** Include payer audit

---

## Claude's Discretion

- Exact Venn breakdown format (console table vs structured output)
- Which TR columns to scan for histology (explore actual column names)
- Plausible numeric ranges for range checks
- Diagnostic script section ordering
- Cohort rebuild approach

## Deferred Ideas

None -- discussion stayed within phase scope
