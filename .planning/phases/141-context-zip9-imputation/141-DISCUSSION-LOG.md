# Phase 141: CONTEXT-zip9-imputation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-13
**Phase:** 141-context-zip9-imputation
**Areas discussed:** Call site, Output disposition, QC/reporting, Done criteria

---

## Call site — where in the pipeline

| Option | Description | Selected |
|--------|-------------|----------|
| R/115 only (zip stability workbook) | Narrowest scope; unblocks workbook release | ✓ |
| Main cohort build (R/39 or equivalent) | Widest impact; all downstream scripts benefit | |
| Both R/115 and main cohort build | Two wiring points | |
| New dedicated script (e.g. R/116) | Standalone script writing RDS for consumers | |

**User's choice:** R/115 only  
**Notes:** User asked for recommendation first. Claude recommended R/115 only on grounds that (a) Phase 140 finalized ZIP assignment design for the workbook specifically, (b) main cohort build wiring is only load-bearing when SES linkage is scoped, and (c) a new R/116 script has no consumer yet. User agreed.

---

## Output disposition — what happens to imputed ZIPs

| Option | Description | Selected |
|--------|-------------|----------|
| In-memory only, used within the R/115 run | Simplest; nothing written to disk | |
| Written to RDS alongside the workbook | Inspectable, reloadable; consistent with project caching | ✓ |
| You decide | Claude picks based on existing R/115 caching patterns | |

**User's choice:** Written to RDS alongside the workbook  
**Notes:** Consistent with the project's established RDS caching convention.

---

## QC / reporting — imputation diagnostics

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — add a QC row in the workbook | Named row: zip5_modal / zip5_only / unchanged counts | ✓ |
| Console log only | Rely on approximate_zip9()'s existing console diagnostics | |
| Defer — not in this phase | Minimal wiring only; diagnostics future concern | |

**User's choice:** Yes — add a QC row in the workbook  
**Notes:** Consistent with how other coverage stats are surfaced in R/115.

---

## Scope boundary — what counts as done

| Option | Description | Selected |
|--------|-------------|----------|
| approximate_zip9() wired + workbook re-issued | xlsx regenerated with imputed ZIPs; re-issue is exit criterion | ✓ |
| Wiring only — workbook re-run is a separate step | Code change only; human runs R/115 separately | |
| Wiring + updated validation curves | Validation curves also updated post-imputation | |

**User's choice:** approximate_zip9() wired into R/115 + workbook re-issued  
**Notes:** Phase is complete when a real HiPerGator run regenerates the xlsx with imputed ZIPs feeding completeness figures.

---

## Claude's Discretion

- Exact location within R/115 where the call is inserted
- RDS filename and write location (follow existing R/115 conventions)
- Whether QC row is one row per zip9_source value or a single summarized row

## Deferred Ideas

- Wiring into main cohort build — future phase when SES linkage is scoped
- Updating A-06 / encounter-anchored validation curves after imputation
- Standalone R/116 imputation script
