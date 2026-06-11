# Phase 99: Fix gantt_v2 vs gantt_v1 disagreements and bugs - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-06-11
**Phase:** 99-fix-gantt-v2-vs-gantt-v1-disagreements-and-bugs-extraneous-columns-etc
**Areas discussed:** V1 disposition, Column reconciliation, Extraneous columns, Bug scope

---

## V1 Disposition

### Q1: What should happen to v1 (R/51) after Phase 99?

| Option | Description | Selected |
|--------|-------------|----------|
| Deprecate v1 (Recommended) | Remove R/51 or mark it deprecated. R/52 becomes the single canonical export. Eliminates maintenance burden. | ✓ |
| Keep both, align shared columns | Keep R/51 as a 'lite' export but fix shared columns to match v2 formatting. | |
| Merge into single configurable script | One script with a flag controlling which columns are included. | |

**User's choice:** Deprecate v1 (Recommended)
**Notes:** None

### Q2: When deprecating R/51, should it be deleted or kept as reference?

| Option | Description | Selected |
|--------|-------------|----------|
| Delete R/51 entirely | Remove the file. Git history preserves it if ever needed. Clean repo. | ✓ |
| Keep but add deprecation header | Add a comment at top saying 'DEPRECATED: Use R/52 instead'. | |

**User's choice:** Delete R/51 entirely
**Notes:** None

---

## Column Reconciliation

### Q3: Should v2 keep semicolons for multi-value field separators?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep semicolons (Recommended) | Avoids CSV parsing ambiguity since the file itself is comma-delimited. Tableau handles them well. | ✓ |
| Switch to pipes | Even more unambiguous but less familiar. | |
| You decide | Claude picks best separator for Tableau compatibility. | |

**User's choice:** Keep semicolons (Recommended)
**Notes:** None

### Q4: Should v2 keep its NA cleanup behavior?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep v2 cleanup (Recommended) | Empty strings and 'Unlinked' are better for Tableau filters and visual readability. | ✓ |
| Revert to raw NAs | Preserve original data fidelity. | |
| You decide | Claude picks based on Tableau best practices. | |

**User's choice:** Keep v2 cleanup (Recommended)
**Notes:** None

### Q5: Should v2 keep simplified drug names?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep simplified (Recommended) | Cleaner for visualization. Full names still in treatment_episodes.rds. | ✓ |
| Add both columns | Keep drug_names (simplified) and add drug_names_full (original). | |
| You decide | Claude picks based on Gantt chart utility. | |

**User's choice:** Keep simplified (Recommended)
**Notes:** None

### Q6: Should v2 output files be renamed to drop _v2 suffix?

| Option | Description | Selected |
|--------|-------------|----------|
| Rename to drop _v2 (Recommended) | Since v2 is canonical, suffix is noise. gantt_episodes.csv and gantt_detail.csv are cleaner. | ✓ |
| Keep _v2 suffix | Avoids breaking downstream references expecting _v2 filenames. | |
| You decide | Claude picks based on downstream reference count. | |

**User's choice:** Rename to drop _v2 (Recommended)
**Notes:** None

---

## Extraneous Columns

### Q7: Should encounter_ids and ENCOUNTERID be added back to v2?

| Option | Description | Selected |
|--------|-------------|----------|
| Leave them out (Recommended) | Encounter IDs add clutter for visualization. Available in treatment_episodes.rds. | ✓ |
| Add them back | Useful for tracing back to source data. | |
| You decide | Claude decides based on downstream references. | |

**User's choice:** Leave them out (Recommended)
**Notes:** None

### Q8: Should is_hodgkin boolean be added back?

| Option | Description | Selected |
|--------|-------------|----------|
| Leave it out (Recommended) | Redundant with cancer_category. Tableau can filter directly. | |
| Add it back as convenience column | Simple TRUE/FALSE is easier to filter on than matching a string. Trivial to derive. | ✓ |
| You decide | Claude decides based on downstream usage. | |

**User's choice:** Add it back as convenience column
**Notes:** User chose to restore is_hodgkin despite it being derivable from cancer_category, valuing filter convenience.

### Q9: Which v2 enrichment column groups should stay?

| Option | Description | Selected |
|--------|-------------|----------|
| Clinical context | regimen_label, is_first_line -- treatment timeline visualization and filtering. | ✓ |
| Death/Drug info | drug_group, cause_of_death -- mortality analysis overlays. | ✓ |
| Source metadata | medication_name, code_type, source_table, treatment_line, sct_cross_use_flag -- provenance/traceability. | ✓ |
| Immunotherapy context | is_sct_conditioning_context, immuno_confidence -- specialized immunotherapy flags. | |

**User's choice:** Clinical context, Death/Drug info, Source metadata (immunotherapy context excluded)
**Notes:** Immunotherapy columns deemed too specialized for Gantt visualization export. Available in treatment_episodes.rds.

---

## Bug Scope

### Q10: Should pseudo-treatment row metadata be cleaned up?

| Option | Description | Selected |
|--------|-------------|----------|
| Clean up (Recommended) | Set metadata columns to empty string for Death/HL Diagnosis rows. Prevents misleading Tableau filters. | ✓ |
| Leave as-is | NA/FALSE accurately reflects 'not applicable'. | |
| You decide | Claude picks based on Tableau filtering behavior. | |

**User's choice:** Clean up (Recommended)
**Notes:** None

### Q11: How should column count verification work?

| Option | Description | Selected |
|--------|-------------|----------|
| Dynamic count from schema definition (Recommended) | Define expected columns in a vector at top of script. Verification checks against that vector. | ✓ |
| Update hardcoded counts | Just change the numbers to match new column count. | |
| You decide | Claude picks the verification approach. | |

**User's choice:** Dynamic count from schema definition (Recommended)
**Notes:** None

### Q12: Should Phase 99 update all downstream references?

| Option | Description | Selected |
|--------|-------------|----------|
| Update all references (Recommended) | Grep for gantt_*_v2 across codebase and update to gantt_*. Clean break. | ✓ |
| Symlink/alias approach | Output to gantt_*.csv but also write gantt_*_v2.csv as copies. | |
| You decide | Claude determines scope of reference updates. | |

**User's choice:** Update all references (Recommended)
**Notes:** None

### Q13: Should Phase 99 include a validation script?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, create R/99 validation (Recommended) | Following established pattern: R/99 checks column names, row counts, separators, NA handling, schema compliance. | ✓ |
| No separate script | R/88 smoke tests already cover gantt exports. Update those checks instead. | |
| You decide | Claude decides based on R/88 coverage. | |

**User's choice:** Yes, create R/99 validation (Recommended)
**Notes:** None

---

## Claude's Discretion

- Column ordering in final schema
- R/99 validation script check count and granularity
- How is_hodgkin is derived (cancer_category string match or lookup)
- Whether R/52 script itself gets renamed (drop _v2 from filename)

## Deferred Ideas

None -- discussion stayed within phase scope.
