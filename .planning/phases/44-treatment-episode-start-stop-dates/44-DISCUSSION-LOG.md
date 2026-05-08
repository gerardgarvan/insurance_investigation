# Phase 44: Treatment Episode Start/Stop Dates - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-07
**Phase:** 44-treatment-episode-start-stop-dates
**Areas discussed:** Historical date handling, Output structure, Episode date columns

---

## Historical Date Handling

### Q1: How should historical dates appear in per-episode output?

| Option | Description | Selected |
|--------|-------------|----------|
| Flag + include | Include as episodes but add boolean historical_flag column. Episodes with all dates before 2012 get flagged. Start=stop=that date, length=0. | ✓ |
| Separate output | Split into two outputs: modern episodes (2012-2025) and historical single-date records. | |
| Just include, no flag | Treat identically to any other 1-date episode. No special column. | |

**User's choice:** Flag + include (Recommended)
**Notes:** None

### Q2: What year cutoff defines 'historical'?

| Option | Description | Selected |
|--------|-------------|----------|
| Before 2012 | Matches OneFlorida+ data extraction period start | ✓ |
| Before 2000 | Catches clearly old records but misses early 2000s | |
| You decide | Let Claude pick based on data distribution | |

**User's choice:** Before 2012 (Recommended)
**Notes:** None

---

## Output Structure

### Q3: How should per-episode output relate to Phase 43's existing per-patient output?

| Option | Description | Selected |
|--------|-------------|----------|
| New per-episode output alongside | Keep Phase 43 unchanged. Add NEW output with one row per patient per episode. Phase 43 = summary view, Phase 44 = detail view. | ✓ |
| Replace Phase 43 output | Modify R/43 to output per-episode rows. Summary derivable from detail. | |
| Add episode columns to existing | Widen Phase 43 output with episode_1_start, episode_1_stop, etc. Gets messy with variable counts. | |

**User's choice:** New per-episode output alongside (Recommended)
**Notes:** None

### Q4: New script or extend R/43?

| Option | Description | Selected |
|--------|-------------|----------|
| New script R/44 | Separate script, can reuse Phase 43 extraction functions | ✓ |
| Extend R/43 | Add per-episode output to existing R/43. Keeps related logic together. | |

**User's choice:** New script R/44 (Recommended)
**Notes:** None

---

## Episode Date Columns

### Q5: What columns per episode row?

| Option | Description | Selected |
|--------|-------------|----------|
| Core + date count + historical flag | patient_id, treatment_type, episode_number, episode_start, episode_stop, episode_length_days, distinct_dates_in_episode, historical_flag | ✓ |
| Core + source info | Same plus source tables column listing contributing sources | |
| Core + gap info | Same plus days_since_prev_episode gap column | |
| All of the above | Maximum detail: date count, historical flag, source tables, gap | |

**User's choice:** Core + date count + historical flag (Recommended)
**Notes:** None

---

## Claude's Discretion

- How to share date extraction logic between R/43 and R/44
- xlsx sheet organization
- Console summary statistics output

## Deferred Ideas

None — discussion stayed within phase scope
