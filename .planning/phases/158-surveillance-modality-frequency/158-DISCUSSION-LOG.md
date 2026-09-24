# Phase 158: Surveillance Modality Frequency - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-24
**Phase:** 158-surveillance-modality-frequency
**Areas discussed:** Stress echo classification (D-1), End of follow-up for person-years (D-3)

---

## D-1: Stress echo classification (93350–93352)

| Option | Description | Selected |
|--------|-------------|----------|
| Echocardiogram only | Default from brief — count stress echo only under Echocardiogram | |
| Stress test only | Count under Stress test modality only | |
| Both | Count under both Echocardiogram and Stress test | ✓ |

**User's choice:** Both modalities.

**Notes:** A stress echo answers two distinct clinical questions simultaneously — it measures heart pumping function (the anthracycline cardiotoxicity question) and is also a stress test (the chest-radiation heart disease question). Omitting it from either modality undercounts each. Counting it under both is safe because modality counts are never added together. The KEY sheet must include a note that modality counts are not additive.

---

## D-3: End of follow-up for person-years

| Option | Description | Selected |
|--------|-------------|----------|
| min(death, last encounter) | Truncate follow-up at the earlier of death or last encounter of any type, capped at extract cutoff | ✓ |
| Death date only | Use death date or extract cutoff if alive | |
| Extract cutoff 2025-09-15 | Fixed end date for all patients | |

**User's choice:** min(death date, last encounter date of any type), capped at 2025-09-15.

**Notes:** OneFlorida is not a closed claims population. A patient who leaves the system still has records up to their last encounter, but would appear to accumulate denominator time all the way to the extract cutoff — artificially deflating events per person-year. Using last encounter of any type (not HL-only or treatment-only) avoids this. If death date is NULL, use last encounter date capped at 2025-09-15.

---

## Defaults accepted without discussion

### D-2: TSH vs Thyroid function modality name
**Decision (default):** Rename to "Thyroid function"; retain TSH-only sub-count within the modality row.
**Rationale given:** Free T4 is rarely ordered without TSH, so the sub-count will barely differ from the full modality count. The rename is more clinically descriptive.

### D-4: CBC component fallback
**Decision (default):** Include WBC (6690-2) + Hgb (718-7) + PLT (777-3) same-day proxy in sensitivity tier only; never pooled into primary counts.

### D-5: Plausible-verify codes
**Decision (default):** Include BH3xY0Z and ICD-10-PCS `B24*` prefix codes; flag as "Plausibility: verify" in KEY sheet. Volume expected to be small (inpatient PCS); A_code_presence will surface whether they matter.

---

## Claude's Discretion

- Script structure and section headers (follow R/111 pattern)
- Next free R/ script number (executor confirms at runtime)
- DuckDB vs in-memory for `get_hl_any_dx_ids()` denominator query (DuckDB preferred for consistency)

## Deferred Ideas

- Guideline adherence analysis (Phase 159 or later)
- Uncoded modalities (BMP/LFT/CMP/lipids/DEXA) pending lab crosswalk
- SURV-06 join to treatment exposure — out of scope; `.rds` designed to enable it
