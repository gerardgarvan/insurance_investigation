# Phase 22: Generalize Phase 20 to All Sites - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-14
**Phase:** 22-generalize-phase-20-to-all-sites
**Areas discussed:** Investigation scope, Output structure, Recommendation logic, Script design

---

## Investigation Scope

### Patient Population

| Option | Description | Selected |
|--------|-------------|----------|
| All patients per site | Same approach as Phase 20 — use all patients from DEMOGRAPHIC.SOURCE per site. Gives the fullest picture of data quality. | ✓ |
| HL cohort only | Same approach as Phase 21 — restrict to HL cohort patients. Smaller analysis. | |
| Both | Run both all-patients and HL-cohort breakdowns in the same script. | |

**User's choice:** All patients per site
**Notes:** Consistent with Phase 20's data quality investigation intent (D-06).

### Site Identification

| Option | Description | Selected |
|--------|-------------|----------|
| DEMOGRAPHIC.SOURCE | Patient's home site, same as Phase 20. Then look at ENCOUNTER.SOURCE within encounters for cross-site detection. | ✓ |
| ENCOUNTER.SOURCE | Group encounters directly by ENCOUNTER.SOURCE, ignoring patient home site. Simpler but loses home/visiting distinction. | |
| You decide | Claude picks based on code clarity. | |

**User's choice:** DEMOGRAPHIC.SOURCE
**Notes:** Natural extension of Phase 20's pattern — patients "belong" to their DEMOGRAPHIC.SOURCE site.

---

## Output Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Same 3+1 CSVs + cross-site summary | Mirror Phase 20's 3 CSVs but with SITE column, plus cross-site summary CSV. 4-5 files. Consistent with both prior phases. | ✓ |
| Aggregate only + cross-site summary | Skip patient/date detail CSVs. Just aggregate + summary. 2 files. | |
| You decide | Claude structures output for best informativeness. | |

**User's choice:** Same 3+1 CSVs + cross-site summary
**Notes:** Full detail preserved with SITE column added. `all_site_` prefix.

---

## Recommendation Logic

| Option | Description | Selected |
|--------|-------------|----------|
| Per-site recommendations | For each DEMOGRAPHIC.SOURCE site, identify which ENCOUNTER.SOURCE provides best payer data when multi-source duplicates exist. | ✓ |
| Global recommendation only | Single recommendation across all sites combined. | |
| Numbers only, no recommendation | Report rates and let user decide. | |

**User's choice:** Per-site recommendations
**Notes:** Each site gets its own source preference based on its own multi-source encounter payer completeness.

---

## Script Design

| Option | Description | Selected |
|--------|-------------|----------|
| New standalone script | New R/21_all_site_duplicate_dates.R. Phase 20's script stays unchanged. Same pattern as Phase 21. | ✓ |
| Modify Phase 20 script | Refactor R/19_flm_duplicate_dates.R to handle all sites. | |
| You decide | Claude picks cleanest approach. | |

**User's choice:** New standalone script
**Notes:** Follows the established pattern: Phase 21 created a new R/20 to generalize Phase 19's R/18.

---

## Claude's Discretion

- CSV column structures and additional columns beyond Phase 20's set
- Console logging format and per-site summary compactness
- Per-site iteration vs group_by approach
- Handling sites with zero duplicates or zero multi-source encounters
- Cross-site summary CSV columns and sort order

## Deferred Ideas

None — discussion stayed within phase scope
