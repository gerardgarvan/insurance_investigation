# Phase 153: Patient ZIP Calendar and Best-ZIP Selection — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-17
**Phase:** 153-patient-zip-calendar-and-best-zip-selection
**Areas discussed:** D-02 (which patient ZIP), D-04 (scope of rule 3), Calendar source, ZIP9 vs ZIP5 ranking priority

---

## D-02 — Which patient ZIP

| Option | Description | Selected |
|--------|-------------|----------|
| Time-varying: ZIP from address history at encounter date | Most clinically meaningful; what AM rule 3 implies | ✓ |
| Static: single per-patient ZIP (index date or most recent) | Simpler but misses address changes over multi-year cohort | |
| Both: time-varying + index-date ZIP with agreement rate | Comparative; adds complexity | |

**User's choice:** Time-varying (address history at encounter date)
**Notes:** Consistent with MILESTONE recommendation and AM rule 3 intent.

---

## D-04 — Scope of rule 3

| Option | Description | Selected |
|--------|-------------|----------|
| Patient side only — count blank facility ZIPs, report, don't impute | Rule 3 = fill missing patient ZIP only; missing facility ZIP is a separate data quality issue | ✓ |
| Both sides — apply nearest-in-time to facility ZIP too | Not viable without a facility registry | |
| Exclude those encounters from all outputs | Loses data; misleading waterfall | |

**User's choice:** Patient side only
**Notes:** Missing facility ZIP → `facility_zip_missing` in `distance_status`. Count and report in completeness waterfall.

---

## Calendar source

| Option | Description | Selected |
|--------|-------------|----------|
| Address history only | Build calendar from LDS_ADDRESS_HISTORY only | ✓ |
| Supplement with ENCOUNTER ZIP for patients with no address history | Mixing facility ZIP into patient calendar corrupts distance calculation | |
| You decide | — | |

**User's choice:** Address history only
**Notes:** ENCOUNTER.FACILITY_LOCATION is never added to the patient calendar.

---

## ZIP9 vs ZIP5 ranking priority

| Option | Description | Selected |
|--------|-------------|----------|
| ZIP9 always beats ZIP5 even when ZIP5 is temporally closer | Single flat arrange() per Appendix A | |
| Temporal proximity beats precision tier | In-range ZIP5 beats out-of-range ZIP9 | |
| Only rank ZIP9 > ZIP5 when both are in-range | Two-zone ranking; out-of-range: nearest by days_offset only | ✓ |

**User's choice:** Two-zone ranking

**Follow-up — out-of-range candidates:**

| Option | Description | Selected |
|--------|-------------|----------|
| Nearest \|days_offset\| only, ignore ZIP9/ZIP5 tier | Temporal proximity is the only signal when no period covers the encounter | ✓ |
| Nearest \|days_offset\|, tie-break by ZIP9 > ZIP5 | Prefer ZIP9 on ties | |

**Notes:** In-range: rank ZIP9 > ZIP5; out-of-range: rank by `|days_offset|` only; ties in either zone: prefer earlier period (D-03). The Appendix A `arrange()` must be revised to implement this two-zone logic.

---

## Claude's Discretion

- Internal variable naming and pipe style
- Whether `build_patient_zip_calendar()` memoizes the address-history read
- Exact column widths in xlsx output
- Implementation detail of the two-zone arrange (any clean equivalent acceptable)

## Deferred Ideas

None.
