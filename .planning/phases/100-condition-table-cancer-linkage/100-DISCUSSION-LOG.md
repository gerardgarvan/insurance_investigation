# Phase 100: CONDITION Table Cancer Linkage - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-12
**Phase:** 100-condition-table-cancer-linkage
**Areas discussed:** Code filtering, Matching approach, Improvement report

---

## Code Filtering

### CONDITION_TYPE Values

| Option | Description | Selected |
|--------|-------------|----------|
| ICD-10 + ICD-9 only | Only CONDITION_TYPE '09' and '10'. Maps directly through existing classify_codes(). | ✓ |
| All available types | Include SNOMED CT, ICD-11, etc. Would require new mapping logic. | |

**User's choice:** ICD-10 + ICD-9 only
**Notes:** Clean approach — reuses existing classify_codes() without new code system handling.

### CONDITION_STATUS/SOURCE Filtering

| Option | Description | Selected |
|--------|-------------|----------|
| No filtering | Include all CONDITION rows regardless of status/source. Maximizes coverage. | ✓ |
| Active conditions only | Filter to active/current conditions. More conservative. | |
| You decide | Claude picks based on data. | |

**User's choice:** No filtering
**Notes:** Tier 3 last-resort approach — any cancer condition is useful signal.

---

## Matching Approach

### Match Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror DIAGNOSIS cascade | Same 2-step: ENCOUNTERID match first, temporal fallback (ONSET_DATE within 30d). | ✓ |
| Patient-level match | Any cancer CONDITION for the patient. Maximum linkage, weakest clinical connection. | |
| ENCOUNTERID only | Most conservative — skips temporal fallback within CONDITION. | |

**User's choice:** Mirror DIAGNOSIS cascade
**Notes:** Produces `condition_encounter` and `condition_date` link methods. Consistent with existing Tier 1/2 logic.

### Temporal Date Column

| Option | Description | Selected |
|--------|-------------|----------|
| ONSET_DATE | Date condition began. Clinically analogous to DX_DATE. | ✓ |
| REPORT_DATE | Date condition was reported/recorded. | |
| Earliest of both | Widest net for temporal matching. | |

**User's choice:** ONSET_DATE
**Notes:** Directly analogous to DX_DATE in DIAGNOSIS temporal fallback.

---

## Improvement Report

### Report Location

| Option | Description | Selected |
|--------|-------------|----------|
| New sheet in audit xlsx | Add 'Linkage Improvement' sheet to existing workbook. | ✓ |
| Standalone xlsx | Separate file — easier to share independently. | |
| Console + xlsx sheet | Console log during execution plus xlsx sheet. | |

**User's choice:** New sheet in audit xlsx
**Notes:** Keeps all classification audit data in one workbook.

### Detail Level

| Option | Description | Selected |
|--------|-------------|----------|
| Aggregate + by treatment type | Overall before/after plus breakdown by treatment type. | ✓ |
| Aggregate only | Just overall before/after counts. | |
| Full per-episode breakdown | Aggregate plus per-episode sheet. | |

**User's choice:** Aggregate + by treatment type
**Notes:** Shows which treatment types benefit most from CONDITION linkage.

---

## Non-Destructive Constraint (User-Initiated)

User raised critical constraint: "I just want to make sure this doesn't affect any existing datasets reports etc. we don't know what we will do with CONDITION table."

### Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Additive only | CONDITION tier only touches unlinked episodes, all existing outputs unchanged. | |
| Even more conservative | CONDITION results logged/reported but NOT merged into treatment_episodes.rds. Separate analysis only. | ✓ |

**User's choice:** Investigation report only — no data modification
**Notes:** This fundamentally reframes Phase 100 as an investigation phase, not a production integration.

### Script Location

| Option | Description | Selected |
|--------|-------------|----------|
| New standalone script | Separate R script, keeps R/28 untouched. | ✓ |
| New section in R/28 | Add analysis section to existing script. | |

**User's choice:** New standalone script
**Notes:** R/28 stays completely untouched. New script reads existing outputs.

---

## Claude's Discretion

- Script numbering
- Console logging verbosity
- Whether to include would-be cancer category distribution in report
- Smoke test additions

## Deferred Ideas

None — discussion stayed within phase scope
