# Phase 26: Overlap Classification and Recommendations - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-22
**Phase:** 26-overlap-classification-and-recommendations
**Areas discussed:** Missing field treatment, Classification thresholds, Recommendation logic, Same-week comparison

---

## Missing Field Treatment

### Q1: Both-NA handling

| Option | Description | Selected |
|--------|-------------|----------|
| Both NA = match | Treats shared absence as agreement. Simpler logic, higher Identical rates. | ✓ |
| Both NA = ignore field | Exclude field from match count. Changes denominator per pair. | |
| Both NA = mismatch | Conservative — only actual matching values count. Lower Identical rates. | |

**User's choice:** Both NA = match
**Notes:** None

### Q2: One-sided NA handling

| Option | Description | Selected |
|--------|-------------|----------|
| One NA = mismatch | Absence vs presence is a real difference. Standard approach. | ✓ |
| One NA = ignore field | Don't count field at all. Reduces denominator, may inflate Identical rate. | |

**User's choice:** One NA = mismatch
**Notes:** None

### Q3: Payer sentinel normalization

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, normalize first | Convert NI/UN/OT/99/9999/empty to NA before comparing. Consistent with Phase 19. | ✓ |
| No, compare raw values | NI vs UN would be mismatch even though both mean "missing". More granular but noisier. | |

**User's choice:** Yes, normalize first
**Notes:** Consistent with Phase 19 `is_missing_payer()` definition

---

## Classification Thresholds

### Q1: Identical / Partial / Distinct cutoffs

| Option | Description | Selected |
|--------|-------------|----------|
| 5=Identical, 1-4=Partial, 0=Distinct | All match = Identical, zero = Distinct, anything between = Partial. Simple. | ✓ |
| 5=Identical, 3-4=Partial, 0-2=Distinct | Majority rule: 3+ matches needed for Partial. | |
| 5=Identical, 2-4=Partial, 0-1=Distinct | Middle ground: 2+ matches for Partial. | |

**User's choice:** 5=Identical, 1-4=Partial, 0=Distinct
**Notes:** None

### Q2: Match count granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, include match count | Label + count: "Partial (3/5)". Analyst can drill into granularity. | ✓ |
| Label only | Just Identical/Partial/Distinct. Simpler, less noise. | |

**User's choice:** Yes, include match count
**Notes:** None

---

## Recommendation Logic

### Q1: Recommendation thresholds

| Option | Description | Selected |
|--------|-------------|----------|
| >=70% Identical = deduplicate | >=70% safe. 30-69% mixed. <30% retain all. | ✓ |
| >=80% Identical = deduplicate | Stricter: >=80% safe. 50-79% mixed. <50% retain all. | |
| You decide | Claude picks based on data distribution. | |

**User's choice:** >=70% Identical = deduplicate
**Notes:** None

### Q2: Preferred source in recommendations

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, include preferred source | Suggest which source to keep based on payer completeness. Actionable. | ✓ |
| No, just classify | Only state deduplicate or retain. Let analyst choose source. | |

**User's choice:** Yes, include preferred source
**Notes:** None

---

## Same-Week Comparison

### Q1: DISCHARGE_DATE inclusion

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude DISCHARGE_DATE | Compare only 4 fields for same-week. Different admit dates = likely different discharge. | ✓ |
| Include DISCHARGE_DATE | Keep all 5 fields. May inflate Distinct rate. | |
| You decide | Claude picks based on analytical sense. | |

**User's choice:** Exclude DISCHARGE_DATE
**Notes:** None

### Q2: Classification labels for same-week

| Option | Description | Selected |
|--------|-------------|----------|
| Same labels, note basis | Identical/Partial/Distinct with "basis" column noting field count. Same vocabulary. | ✓ |
| Different labels for same-week | Near-Identical / Near-Partial / Near-Distinct. More explicit but adds terminology. | |

**User's choice:** Same labels, note basis
**Notes:** None

---

## Claude's Discretion

- Join strategy for reading Phase 25 CSVs and extracting comparison fields from ENCOUNTER
- Console summary formatting and verbosity
- CSV column naming and ordering
- Preferred source computation method

## Deferred Ideas

None — discussion stayed within phase scope
