# Phase 117: Lifespan Gantt (Collapsed Across Time) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-09
**Phase:** 117-make-a-lifespan-gannt-that-collapses-across-all-time-but-still-keeps-treatment-type-etc-sepearate
**Areas discussed:** Output artifact, Time origin, Aggregation grain, Dimensions kept separate

---

## Output artifact

| Option | Description | Selected |
|--------|-------------|----------|
| Rendered chart (R → image) | New R/ggplot script rendering the Gantt to PNG/PDF | |
| New CSV for Tableau | New CSV export with the collapsed data, build visual in Tableau | ✓ |
| Both CSV + R chart | Collapsed CSV plus a rendered R image | |

**User's choice:** New CSV for Tableau
**Notes:** Matches existing project convention (gantt_episodes.csv / gantt_detail.csv → Tableau). No in-R rendering exists in the project.

---

## Time origin (t=0)

| Option | Description | Selected |
|--------|-------------|----------|
| Days since HL diagnosis | Align every patient to first_hl_dx_date | |
| Age axis (age_at_episode) | x-axis = patient age | |
| Days since first treatment | Align to earliest treatment start | |
| Other (free text) | — | ✓ |

**User's choice:** "collapsed just means we are combining every episode by treatment type"
**Notes:** Key reframe — "collapse across all time" does NOT mean a relative/normalized time axis. It means merging episodes of the same treatment type. Follow-up clarified: **per patient, earliest to latest date.** Calendar dates preserved.

---

## Aggregation grain

(Resolved via the time-origin follow-up rather than a separate menu.)

| Option | Description | Selected |
|--------|-------------|----------|
| Per patient — merge episodes per treatment type | One bar per patient per treatment_type, min start → max stop | ✓ |
| Across whole cohort — one bar per treatment type | Collapse all patients into a single summary bar per type | |

**User's choice:** Per patient, earliest to latest date
**Notes:** Span = min(episode_start) → max(episode_stop) across that patient's episodes of the type.

---

## Dimensions kept separate

| Option | Description | Selected |
|--------|-------------|----------|
| cancer_category | Separate bars per patient × type × cancer_category | |
| is_hodgkin | Keep Hodgkin vs non-Hodgkin as a lane | |
| Nothing else — treatment_type only | Collapse purely to one bar per patient per treatment_type | ✓ |
| 7-day confirmed status | Keep confirmed vs unconfirmed separate | |

**User's choice:** Nothing else — treatment_type only
**Notes:** All other fields become unioned/deduped semicolon multi-value attributes within the single bar.

---

## Pseudo-rows (Death / HL Diagnosis)

| Option | Description | Selected |
|--------|-------------|----------|
| Include them | Keep Death and HL Diagnosis single-date rows as anchors | |
| Treatment types only | Exclude Death and HL Diagnosis pseudo-rows | ✓ |

**User's choice:** Treatment types only
**Notes:** Only real treatment types get collapsed bars.

## Claude's Discretion

- Output file name (suggested gantt_lifespan.csv)
- Script location (new 100+ standalone script vs section in R/52) and input source (gantt_episodes.csv vs treatment_episodes.rds)
- Aggregation rules for numeric/boolean helper columns (episode_length_days span, distinct_dates, is_hodgkin, age_at_episode, episode_number)
- Whether to register in R/39 and add an R/88 smoke-test section (Phase 116 precedent)

## Deferred Ideas

- Relative/normalized time axis (align to diagnosis/age/first-treatment)
- Rendering the Gantt as an R image
- Keeping cancer_category / is_hodgkin / 7-day-confirmed as separate collapse dimensions
