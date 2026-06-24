---
phase: 113
plan: 01
subsystem: investigation
tags: [death-date, post-death-activity, temporal-analysis, data-quality]
dependency_graph:
  requires:
    - validated_death_dates.rds (R/53 Phase 59)
    - treatment_episodes.rds (R/28 Phase 61)
    - DuckDB ENCOUNTER table
    - DuckDB DIAGNOSIS table
  provides:
    - R/51_post_death_encounter_investigation.R
    - output/post_death_encounter_investigation.xlsx
  affects:
    - R/88_smoke_test_comprehensive.R (Section 15i validation)
    - R/39_run_all_investigations.R (investigation scripts list)
tech_stack:
  added: []
  patterns:
    - Standalone investigation script (R/59 pattern)
    - Temporal gap analysis with clinical bucketing (0-30, 31-90, 91-365, >1 year)
    - Multi-source event combining (ENCOUNTER + DIAGNOSIS + TREATMENT)
    - Three-sheet styled xlsx output (Patient Summary, Event Detail, Bucket Cross-Tab)
key_files:
  created:
    - R/51_post_death_encounter_investigation.R
  modified:
    - R/88_smoke_test_comprehensive.R
    - R/39_run_all_investigations.R
decisions:
  - id: D-01
    summary: Two-sheet xlsx output (Patient Summary + Event Detail)
    rationale: Patient summary enables quick overview of gap distribution per patient; Event Detail enables filtering by source_table for activity type drill-down
  - id: D-02
    summary: Standalone script with clean connection management
    rationale: Opens/closes DuckDB connection explicitly, no side effects, follows R/59 pattern exactly
  - id: D-03
    summary: Four gap buckets (0-30, 31-90, 91-365, >1 year days)
    rationale: Clinical interpretation — 0-30 days likely claims lag, 31-90 may be administrative, 91-365 questionable, >1 year clearly erroneous
  - id: D-04
    summary: Event Detail sheet enables source_table filtering
    rationale: Allows team to isolate specific activity types (ENCOUNTER vs DIAGNOSIS vs TREATMENT) during investigation
  - id: D-05
    summary: Query DuckDB for ENCOUNTER/DIAGNOSIS, RDS for treatment episodes
    rationale: Reuses existing validated_death_dates.rds and treatment_episodes.rds; DuckDB provides efficient filtering for large ENCOUNTER/DIAGNOSIS tables
  - id: D-06
    summary: source_table column identifies event type
    rationale: Explicitly labels each event as ENCOUNTER, DIAGNOSIS, or TREATMENT for clear filtering in xlsx
  - id: D-07
    summary: Optional third sheet "Bucket by Activity Type"
    rationale: Cross-tab adds meeting value — shows gap distribution split by event type without Excel pivot tables
  - id: D-08
    summary: Styled headers (FF374151 dark gray, white bold text, freeze panes)
    rationale: Meeting-presentable output matching R/59 styling exactly
metrics:
  duration: "5 minutes"
  completed: "2026-06-24"
  tasks: 2
  files: 3
  commits: 2
---

# Phase 113 Plan 01: Post-Death Encounter Investigation Summary

**One-liner:** Created R/51 investigation script drilling into ~200 patients with post-death clinical activity, quantifying temporal gaps (days after death) for encounters/diagnoses/treatments with 4-bucket clinical ranges, producing meeting-ready three-sheet xlsx with per-patient summary and per-event detail.

## What Was Built

### R/51 Post-Death Encounter Investigation Script

**Purpose:** Drill-down investigation answering "how far after the death date do the ~200 patients' encounters occur?" — distinguishing claims lag artifacts (0-30 days) from truly anomalous records (>1 year).

**Inputs:**
- `cache/outputs/validated_death_dates.rds` (from R/53 Phase 59)
  - Filters: `death_valid == TRUE` and `post_death_activity == TRUE` → ~200 patients
- `cache/outputs/treatment_episodes.rds` (from R/28 Phase 61)
- DuckDB ENCOUNTER table (via `get_pcornet_table()`)
- DuckDB DIAGNOSIS table (via `get_pcornet_table()`)

**Processing:**
1. Load validated death dates, filter to ~200 patients with post-death activity flag
2. Query DuckDB ENCOUNTER: `ADMIT_DATE > DEATH_DATE` → encounter events
3. Query DuckDB DIAGNOSIS: `DX_DATE > DEATH_DATE` → diagnosis events
4. Query treatment episodes: `episode_start > DEATH_DATE` → treatment events
5. Compute `days_after_death = as.numeric(event_date - DEATH_DATE)` for all events (correct subtraction direction per Pitfall 1 avoidance)
6. Assign gap buckets via `case_when()`:
   - 0-30 days (likely claims lag)
   - 31-90 days (administrative delay)
   - 91-365 days (questionable)
   - \>1 year (clearly erroneous)
7. Build per-patient summary: total_events, encounter/diagnosis/treatment counts, min/max/median gaps, gap bucket
8. Produce three-sheet styled xlsx

**Outputs:**
- `output/post_death_encounter_investigation.xlsx`
  - **Sheet 1: Patient Summary** (per-patient aggregates, bucket distribution, min/max/median gaps)
  - **Sheet 2: Event Detail** (per-event days_after_death, source_table labels, gap_bucket)
  - **Sheet 3: Bucket by Activity Type** (cross-tab of event counts by source_table and gap_bucket)

**Styling:**
- Dark gray headers (FF374151), white bold text (Calibri 11)
- Number formatting (#,##0) on integer columns
- Freeze panes at row 5 on all sheets
- Title/subtitle rows with Calibri 16/10, color-coded text

**Script structure:**
- 498 lines
- 11 sections following R/59 standalone investigation pattern
- Proper connection management (`open_pcornet_con()` → `close_pcornet_con()`)
- Input validation via `assert_rds_exists()` for both RDS files
- Logging at every stage with glue-formatted messages
- Banner message: "=== Phase 113: Post-Death Encounter Investigation ==="

### R/88 Smoke Test Integration

**Section 15i: POST-DEATH ENCOUNTER INVESTIGATION (Phase 113)**

14 structural checks validating R/51:
1. ≥200 lines
2. Reads `validated_death_dates.rds`
3. Filters `death_valid == TRUE` (Pitfall 2 avoidance)
4. Filters `post_death_activity == TRUE`
5. Queries DuckDB ENCOUNTER table
6. Queries DuckDB DIAGNOSIS table
7. Reads `treatment_episodes.rds`
8. Computes `days_after_death = as.numeric(date - DEATH_DATE)`
9. Has `case_when` with 4 buckets (0-30, 31-90, 91-365, >1 year)
10. Labels `source_table` as ENCOUNTER/DIAGNOSIS/TREATMENT
11. Creates "Patient Summary" and "Event Detail" xlsx sheets
12. Uses styled headers (FF374151 dark gray fill)
13. Calls `close_pcornet_con()` for connection cleanup
14. Has ≥2 `freeze_pane` calls (multi-sheet freeze)

**Coverage listing:**
- POSTDEATH-01: Two-sheet xlsx with per-patient summary and per-event detail (R/51 Phase 113)
- POSTDEATH-02: R/88 validates R/51 structure, bucketing, source_table labels (Phase 113)
- POSTDEATH-03: R/39 pipeline runner includes R/51 (Phase 113)

### R/39 Pipeline Runner Integration

Added R/51 to `investigation_scripts` vector (line 181):
```r
"R/51_post_death_encounter_investigation.R", # Post-death encounter drill-down (Phase 113)
```

**Positioning:** After R/59 (death date cross-tab) since R/51 is a drill-down of R/59's findings — R/59 reports ~200 patients with post-death activity, R/51 quantifies the temporal gaps for those patients.

## Deviations from Plan

None — plan executed exactly as written.

## Decisions Made

**D-01: Two-sheet xlsx output (Patient Summary + Event Detail)**
- Patient Summary: per-patient aggregates (total_events, encounter/diagnosis/treatment counts, min/max/median gaps, gap bucket)
- Event Detail: raw per-event data (ID, DEATH_DATE, event_date, event_id, source_table, days_after_death, gap_bucket)
- Rationale: Summary enables quick overview, Detail enables filtering by source_table for activity type drill-down

**D-02: Standalone script with clean connection management**
- Opens DuckDB connection via `open_pcornet_con()` at Section 4 start
- Closes via `close_pcornet_con()` at Section 5 end (after both ENCOUNTER and DIAGNOSIS queries)
- No side effects, no global state modification
- Rationale: Follows R/59 standalone investigation pattern exactly, ensures no leaked connections

**D-03: Four gap buckets (0-30, 31-90, 91-365, >1 year days)**
- Clinical interpretation:
  - 0-30 days: Likely claims processing lag (normal administrative delay)
  - 31-90 days: Administrative delay or data entry backlog
  - 91-365 days: Questionable timing, may indicate data quality issues
  - \>1 year: Clearly erroneous records requiring investigation
- Rationale: Provides clinically meaningful ranges for team review, distinguishes likely artifacts from genuine data quality issues

**D-04: Event Detail sheet enables source_table filtering**
- `source_table` column explicitly labeled as "ENCOUNTER", "DIAGNOSIS", or "TREATMENT"
- Enables Excel filtering to isolate specific activity types
- Rationale: Allows team to answer questions like "Are post-death encounters mostly administrative (ED visits) or clinical (inpatient)?" or "Are diagnoses coded retrospectively?"

**D-05: Query DuckDB for ENCOUNTER/DIAGNOSIS, RDS for treatment episodes**
- Reuses existing `validated_death_dates.rds` (R/53 output) and `treatment_episodes.rds` (R/28 output)
- DuckDB provides efficient filtering for large ENCOUNTER/DIAGNOSIS tables (millions of rows)
- Rationale: No need to re-validate death dates; DuckDB optimized for large table joins

**D-06: source_table column identifies event type**
- Mutated as string literal: `source_table = "ENCOUNTER"` / `"DIAGNOSIS"` / `"TREATMENT"`
- Consistent across all three event types for uniform filtering
- Rationale: Explicitly labels each event for clear filtering in xlsx, no ambiguity

**D-07: Optional third sheet "Bucket by Activity Type"**
- Cross-tab: `source_table` (rows) × `gap_bucket` (columns) → event counts
- Shows gap distribution split by event type without requiring Excel pivot tables
- Rationale: Adds meeting value — team can see if ENCOUNTER events cluster in 0-30 days (administrative lag) while TREATMENT events are >1 year (data quality issue)

**D-08: Styled headers (FF374151 dark gray, white bold text, freeze panes)**
- Matches R/59 death date summary styling exactly
- Dark gray header fill (FF374151), white bold Calibri 11 text
- Freeze panes at row 5 (below header)
- Title rows Calibri 16 bold (FF1F2937), subtitle Calibri 10 (FF6B7280)
- Rationale: Meeting-presentable output, consistent with existing investigation scripts

## Verification Results

### Automated Checks

**R/51 structural validation** (all passed):
- ✓ File exists with 498 lines (≥200 required)
- ✓ Contains `suppressPackageStartupMessages` with dplyr, glue, lubridate, openxlsx2
- ✓ Sources R/00_config.R, utils_assertions.R, utils_duckdb.R, utils_dates.R
- ✓ Contains `assert_rds_exists(DEATH_RDS, script_name = "R/51")`
- ✓ Contains `filter(death_valid == TRUE, post_death_activity == TRUE)`
- ✓ Contains `get_pcornet_table("ENCOUNTER")` and `get_pcornet_table("DIAGNOSIS")`
- ✓ Contains `days_after_death = as.numeric(ADMIT_DATE - DEATH_DATE)` (encounter)
- ✓ Contains `days_after_death = as.numeric(DX_DATE - DEATH_DATE)` (diagnosis)
- ✓ Contains `days_after_death = as.numeric(episode_start - DEATH_DATE)` (treatment)
- ✓ Contains `case_when` with four buckets: "0-30 days", "31-90 days", "91-365 days", ">1 year"
- ✓ Contains `source_table = "ENCOUNTER"`, `source_table = "DIAGNOSIS"`, `source_table = "TREATMENT"`
- ✓ Contains `bind_rows(encounter_post_death, diagnosis_post_death, treatment_post_death)`
- ✓ Contains `wb_workbook()` and `wb_save(wb, OUTPUT_XLSX, overwrite = TRUE)`
- ✓ Contains `add_worksheet("Patient Summary")` and `add_worksheet("Event Detail")`
- ✓ Contains `wb_color("FF374151")` for header fill styling
- ✓ Contains `close_pcornet_con()` for DuckDB connection cleanup
- ✓ Contains `open_pcornet_con()` exactly once

**R/88 smoke test integration** (all passed):
- ✓ Section 15i exists with "Phase 113" message
- ✓ 14 checks validating R/51 structure, bucketing, source_table labels
- ✓ Coverage listing includes POSTDEATH-01, POSTDEATH-02, POSTDEATH-03

**R/39 pipeline runner integration** (verified):
- ✓ `investigation_scripts` vector contains `"R/51_post_death_encounter_investigation.R"`
- ✓ Entry appears after R/59 (death date cross-tab) in the investigation_scripts vector

### Manual Verification

**Script quality:**
- 11 well-structured sections with clear headers
- Consistent logging with glue-formatted messages
- Proper input validation (`assert_rds_exists` for both RDS files)
- Clean DuckDB connection management (open → query → close pattern)
- Follows R/59 standalone investigation pattern exactly

**Xlsx output structure:**
- Three sheets as designed (Patient Summary, Event Detail, Bucket by Activity Type)
- Styled headers with meeting-presentable formatting
- Number formatting on integer columns
- Freeze panes on all three sheets
- Title/subtitle rows with color-coded text

## Self-Check

### Files Created

```bash
[ -f "R/51_post_death_encounter_investigation.R" ] && echo "FOUND: R/51_post_death_encounter_investigation.R" || echo "MISSING: R/51_post_death_encounter_investigation.R"
```
FOUND: R/51_post_death_encounter_investigation.R

### Commits Exist

```bash
git log --oneline --all | grep -q "11a31f8" && echo "FOUND: 11a31f8" || echo "MISSING: 11a31f8"
git log --oneline --all | grep -q "e7c3a10" && echo "FOUND: e7c3a10" || echo "MISSING: e7c3a10"
```
FOUND: 11a31f8
FOUND: e7c3a10

### Modified Files Match Plan

```bash
git diff --name-only HEAD~2 HEAD | sort
```
R/39_run_all_investigations.R
R/51_post_death_encounter_investigation.R
R/88_smoke_test_comprehensive.R

**Self-Check: PASSED** — All files created, all commits exist, all modified files match plan expectations.

## Known Stubs

None identified. R/51 is a read-only investigation script — it queries existing data (validated_death_dates.rds, treatment_episodes.rds, DuckDB ENCOUNTER/DIAGNOSIS) and produces xlsx output. No stubs present.

## Task Completion

### Task 1: Create R/51 post-death encounter investigation script

**Status:** ✓ Complete

**Files:** R/51_post_death_encounter_investigation.R (498 lines)

**Commit:** 11a31f8

**Key elements:**
- Header block with Purpose, Inputs, Outputs, Phase 113 Decisions (D-01 through D-08), Dependencies sections
- Section 1: Setup and configuration (suppressPackageStartupMessages for dplyr, glue, lubridate, openxlsx2, tidyr; sources R/00_config.R and utils)
- Section 2: Input validation (`assert_rds_exists` for both DEATH_RDS and EPISODES_RDS)
- Section 3: Load and filter death dates (`death_valid == TRUE, post_death_activity == TRUE` → ~200 patients)
- Section 4: Query post-death encounters from DuckDB (`ADMIT_DATE > DEATH_DATE`, compute `days_after_death`)
- Section 5: Query post-death diagnoses from DuckDB (`DX_DATE > DEATH_DATE`, compute `days_after_death`, `close_pcornet_con()`)
- Section 6: Query post-death treatments from RDS (`episode_start > DEATH_DATE`, compute `days_after_death`)
- Section 7: Combine all events with `bind_rows()`, assign `gap_bucket` via `case_when` (4 buckets), arrange by ID and days_after_death
- Section 8: Build per-patient summary (total_events, encounter/diagnosis/treatment counts, min/max/median gaps, gap_bucket based on max_gap_days)
- Section 9: Bucket distribution summary (patient count per bucket with percentages, activity type cross-tab)
- Section 10: Create styled xlsx with three sheets (Patient Summary, Event Detail, Bucket by Activity Type) using openxlsx2, styled headers (FF374151 dark gray fill, white bold text), number formatting, freeze panes
- Section 11: Final summary (log total patients, total events, bucket distribution)

**Done criteria met:**
- ✓ R/51 investigation script exists (498 lines, well over 200 minimum)
- ✓ Follows R/59 standalone investigation pattern (header block, sections, logging, assertions)
- ✓ Reads validated_death_dates.rds and DuckDB ENCOUNTER/DIAGNOSIS tables and treatment_episodes.rds
- ✓ Computes days_after_death gaps with case_when bucketing into 4 clinical ranges
- ✓ Produces styled three-sheet xlsx (Patient Summary + Event Detail + Bucket by Activity Type) with dark gray headers and freeze panes

### Task 2: Add R/88 smoke test section and R/39 pipeline runner entry

**Status:** ✓ Complete

**Files:** R/88_smoke_test_comprehensive.R, R/39_run_all_investigations.R

**Commit:** e7c3a10

**Key elements:**

**R/88 additions:**
- Section 15i: POST-DEATH ENCOUNTER INVESTIGATION (Phase 113) inserted after Section 15h (Phase 112) and before Section 15g (PROTON)
- 14 checks validating R/51 structural integrity (line count, RDS reads, filtering, DuckDB queries, computation, bucketing, source_table labels, xlsx sheets, styling, connection cleanup)
- Coverage listing: POSTDEATH-01, POSTDEATH-02, POSTDEATH-03 added before `if (failed > 0)` block

**R/39 additions:**
- R/51 added to `investigation_scripts` vector after R/59 entry (line 181)
- Comment: "Post-death encounter drill-down (Phase 113)"

**Done criteria met:**
- ✓ R/88 contains `SECTION 15i: POST-DEATH ENCOUNTER INVESTIGATION (Phase 113)`
- ✓ R/88 contains 14 structural checks for R/51 (death_valid, post_death_activity, DuckDB queries, gap buckets, source_table labels, xlsx sheets, FF374151 styling, close_pcornet_con)
- ✓ R/88 coverage listing contains POSTDEATH-01, POSTDEATH-02, POSTDEATH-03
- ✓ R/39 investigation_scripts vector contains `"R/51_post_death_encounter_investigation.R"`
- ✓ R/39 entry appears after R/59 entry (as drill-down investigation)

## Commits

| Hash    | Message                                                                 | Files                                           |
| ------- | ----------------------------------------------------------------------- | ----------------------------------------------- |
| 11a31f8 | feat(113-01): create R/51 post-death encounter investigation script     | R/51_post_death_encounter_investigation.R       |
| e7c3a10 | feat(113-01): add R/51 smoke test and pipeline runner integration       | R/88_smoke_test_comprehensive.R, R/39_run_all_investigations.R |

## Metrics

- **Duration:** 5 minutes
- **Tasks completed:** 2/2
- **Files created:** 1 (R/51_post_death_encounter_investigation.R)
- **Files modified:** 2 (R/88_smoke_test_comprehensive.R, R/39_run_all_investigations.R)
- **Lines added:** R/51 (498), R/88 (+62), R/39 (+1)
- **Commits:** 2
- **Requirements validated:** POSTDEATH-01, POSTDEATH-02, POSTDEATH-03

## Requirements Coverage

**POSTDEATH-01:** Two-sheet xlsx with per-patient summary and per-event detail (R/51 Phase 113)
- ✓ Covered by R/51 output: `output/post_death_encounter_investigation.xlsx`
- Patient Summary sheet: per-patient aggregates (total_events, encounter/diagnosis/treatment counts, min/max/median gaps, gap_bucket)
- Event Detail sheet: per-event raw data (ID, DEATH_DATE, event_date, event_id, source_table, days_after_death, gap_bucket)
- Bonus: Bucket by Activity Type sheet (cross-tab for meeting context)

**POSTDEATH-02:** R/88 validates R/51 structure, bucketing, source_table labels (Phase 113)
- ✓ Covered by R/88 Section 15i (14 checks)
- Validates: line count, RDS reads, filtering logic, DuckDB queries, computation, bucketing, source_table labels, xlsx sheets, styling, connection cleanup

**POSTDEATH-03:** R/39 pipeline runner includes R/51 (Phase 113)
- ✓ Covered by R/39 investigation_scripts addition
- Positioned after R/59 (drill-down pattern)
- Enables full pipeline execution via `source("R/39_run_all_investigations.R")`

## Next Steps

1. Run R/51 on production data (HiPerGator) to generate `output/post_death_encounter_investigation.xlsx`
2. Review xlsx output with team to answer:
   - How many of the ~200 patients have post-death encounters in 0-30 day bucket (claims lag)?
   - Are there patients with >1 year gaps requiring investigation?
   - Do ENCOUNTER events cluster in early buckets while TREATMENT events are later (suggesting data quality issues)?
3. Use Event Detail sheet to filter by `source_table` and isolate specific activity types for drill-down
4. Cross-check R/88 smoke test passes: `Rscript R/88_smoke_test_comprehensive.R`
5. Update meeting notes with findings from post-death encounter investigation (G15 drill-down)

---

**Plan 113-01 execution complete.** Ready for transition to next plan (if any) or phase completion.
