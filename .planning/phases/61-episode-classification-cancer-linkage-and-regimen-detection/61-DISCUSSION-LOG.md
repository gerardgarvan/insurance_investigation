# Phase 61: Episode Classification - Cancer Linkage & Regimen Detection - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-05-30
**Phase:** 61-episode-classification-cancer-linkage-and-regimen-detection
**Areas discussed:** Cancer linkage fallback, Regimen matching rules, Output structure

---

## Cancer Linkage Fallback

### Temporal fallback direction

| Option | Description | Selected |
|--------|-------------|----------|
| Closest before episode start | Find nearest DIAGNOSIS record with DX_DATE <= episode_start within 30 days. Clinically: diagnosis precedes treatment. | ✓ |
| Closest in either direction | Find nearest DIAGNOSIS record within +/-30 days of episode_start, regardless of before/after. | |
| You decide | Claude picks the most clinically appropriate approach during planning. | |

**User's choice:** Closest before episode start
**Notes:** None

### Tiebreaking strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Closest date wins | Pick diagnosis with DX_DATE nearest to episode_start. If same date, prefer HL (C81) since this is an HL study. | ✓ |
| All diagnoses within window | Keep ALL diagnoses within 30-day window as comma-separated cancer_category (similar to current patient-level but encounter-scoped). | |
| You decide | Claude decides based on clinical patterns found in the data. | |

**User's choice:** Closest date wins
**Notes:** None

### Diagnosis source

| Option | Description | Selected |
|--------|-------------|----------|
| DIAGNOSIS only | TUMOR_REGISTRY has no ENCOUNTERID and limited DX_DATE granularity. Use only for confirmed_hl_cohort.rds but not encounter-level linkage. | ✓ |
| Both DIAGNOSIS + TUMOR_REGISTRY | Use TUMOR_REGISTRY as temporal fallback when DIAGNOSIS has no match. May increase linkage rate but lower precision. | |
| You decide | Claude evaluates data coverage during implementation. | |

**User's choice:** DIAGNOSIS only
**Notes:** None

---

## Regimen Matching Rules

### Matching granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Episode level | Check drug_names column of full episode. Simpler, avoids cycle boundary detection. ABVD episode just needs all 4 drugs present. | ✓ |
| 28-day cycle windows | Subdivide each episode into 28-day windows and match drugs per window. More precise but complex. | |
| You decide | Claude decides based on data structure feasibility. | |

**User's choice:** Episode level
**Notes:** None

### Dropped-agent tolerance

| Option | Description | Selected |
|--------|-------------|----------|
| Bleomycin only | Only bleomycin can be dropped from ABVD (per RATHL trial). AVD = ABVD variant. | ✓ |
| Any 1 of 4 agents | Any single ABVD agent can be dropped and still counts as ABVD. More permissive. | |
| You decide | Claude decides based on clinical literature. | |

**User's choice:** Bleomycin only
**Notes:** None

### Drug name matching strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Base ingredient matching | Match on base ingredient substrings (str_detect). Handles formulation variants. | |
| Exact drug name list | Define explicit lists of accepted drug name strings per agent. | |
| You decide | Claude picks matching strategy based on drug_name_lookup.rds contents. | ✓ |

**User's choice:** You decide
**Notes:** Claude has discretion on string matching strategy

---

## Output Structure

### Script architecture

| Option | Description | Selected |
|--------|-------------|----------|
| New standalone R/61 | New R/61_episode_classification.R that loads and enriches treatment_episodes.rds. Clean separation like R/62. | ✓ |
| Modify R/44a in-place | Add regimen detection and cancer linkage directly into episode calculation pipeline. | |
| You decide | Claude picks based on code complexity and downstream impact. | |

**User's choice:** New standalone R/61
**Notes:** None

### Audit output

| Option | Description | Selected |
|--------|-------------|----------|
| RDS + audit xlsx | Enrich RDS AND produce styled xlsx with linkage method distribution, cancer category frequency, regimen distribution. | ✓ |
| RDS only | Just modify treatment_episodes.rds. No standalone report. | |
| You decide | Claude decides based on data validation needs. | |

**User's choice:** RDS + audit xlsx
**Notes:** None

---

## Claude's Discretion

- Drug name string matching strategy (base ingredient substrings vs explicit name lists)
- Column ordering for new columns in treatment_episodes.rds
- Audit xlsx sheet count, styling, and column layout
- Console logging detail level
- Edge case handling: BV+AVD when both brentuximab AND bleomycin appear in same episode
- Whether to also produce CSV alongside audit xlsx

## Deferred Ideas

None -- discussion stayed within phase scope
