# Phase 182: Facility ZIP Recovery — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-14
**Phase:** 182-facility-zip-recovery
**Areas discussed:** Disambiguation rule, FACILITYID pull scope, Diagnostic workbook structure, Recovery report format

---

## Disambiguation Rule

| Option | Description | Selected |
|--------|-------------|----------|
| Exactly 1 distinct ZIP5 | Fill only when all non-missing encounters for that FACILITYID agree on one ZIP5 | |
| Majority ZIP5 + note | Fill with modal ZIP5 if > 50% share | |
| User-specified rule | SOURCE + FACILITYID key; Tier 1: 1 distinct ZIP5, ≥ 3 supporting; Sensitivity: modal ≥ 95%, ≥ 10 supporting | ✓ |

**User's choice:** Key = `SOURCE + FACILITYID` (not FACILITYID alone — IDs aren't unique across OneFlorida+ partners). Tier 1: exactly one distinct normalized ZIP5, ≥ 3 supporting encounters. Sensitivity tier: modal ZIP5 ≥ 95% share, ≥ 10 supporting — reported but not applied to the primary re-run RDS. No fuzzy text matching on FACILITY_LOCATION strings.

**Notes:** FACILITY_LOCATION is the facility ZIP itself in PCORnet (not a name/address string). If it has a value, it's either parseable by the existing normalizer or genuinely missing. Text-matching location strings across encounters is explicitly out of scope.

---

## FACILITYID Pull Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Add to R/122 encounter pull | Expand Section 3 dplyr::select(); build lookup inline | |
| Build fill lookup in a helper utility | New utils_facility_zip.R; sourced by R/122 | ✓ |
| You decide | Claude picks | |

**User's choice:** New helper `build_facility_zip_lookup()` in `R/utils/utils_facility_zip.R`, sourced by R/122. FACILITYID and SOURCE added to the R/122 Section 3 encounter pull. Fill step guarded by `CONFIG$facility_zip_fill` toggle (default TRUE). New dated RDS produced; 20261013-era RDS never overwritten.

**Notes:** For zip_not_in_db: first diagnose which side fails (patient vs facility) and why (format vs not-in-table). Format issues route through existing normalizers. Valid ZIPs absent from centroid table: check Phase 144/148 crosswalk coverage first; if not covered, leave unfilled and list. Do not add centroids from an undocumented source.

---

## Diagnostic Workbook Structure

(Captured in the FACILITYID pull scope answer)

**User's choice:** Five sheets — KEY · A_status_summary · B_facility_table · C_zip_not_in_db · QC.
- KEY: inputs, toggle, fill rule, counts recovered by tier, remaining missing by reason.
- A_status_summary: encounters/patients by distance_status before vs after; zip_not_in_db by side/cause.
- B_facility_table: SOURCE, FACILITYID, n missing, distinct ZIPs, candidate ZIP, supporting n, fill status.
- C_zip_not_in_db: facility-side ZIPs with counts; patient-side as ZIP3 + count only.
- QC: before/after totals reconcile; no computed→other flips; suppression count.
- Nice-to-have (Claude's discretion): facility ZIP stability by year.

---

## Recovery Report Format

| Option | Description | Selected |
|--------|-------------|----------|
| Markdown in phase directory | 182-RECOVERY.md, consistent with Phase 181 MEMO.md | |
| Sheet inside workbook | RECOVERY sheet in diagnostic workbook | |
| Both | Markdown + numbers in workbook KEY | ✓ |

**User's choice:** Script-generated 182-RECOVERY.md into output/, then copied to phase directory after review. Key numbers also in workbook KEY. Required content: encounters/patients recovered by tier; remaining missing by reason; zip_not_in_db diagnosis; Phase 179 OR before vs after; Phase 180 bounds/branch/capture-% change; whether any locked decision branch changed. Neutral language, counts 1–10 as `<11`.

**Notes:** R/179 and R/180 re-run via explicit path override (`R179_R122_RDS`), not auto-latest pickup. Phase 181 memo already sent — R/181 re-run is out of scope. All before/after comparison numbers read from workbooks by exact label at runtime (not hard-coded). All pinned paths recorded in Phase 182 KEY and SUMMARY.

---

## Claude's Discretion

- Whether to store `facility_zip_source` in the RDS or only in the workbook.
- Minor workbook formatting (column widths, freeze panes) — follow Phase 179/180/181 precedent.
- Whether to implement facility ZIP stability by year (D-19) — only if it fits cleanly.

## Deferred Ideas

None — discussion stayed within phase scope.
