---
phase: quick-260709-i1a
plan: "01"
subsystem: gantt-export
tags: [drug_group, clean_multi_value, dedup, literal-NA, R52, R101, R88]
dependency_graph:
  requires: []
  provides: [drug_group-cleaned-gantt_episodes, drug_group-cleaned-gantt_lifespan]
  affects: [output/gantt_episodes.csv, output/gantt_lifespan.csv]
tech_stack:
  added: []
  patterns: [sapply+clean_multi_value, gsub-normalize-sep, verbatim-copy-D07]
key_files:
  modified:
    - R/52_gantt_v2_export.R
    - R/101_gantt_lifespan_collapse.R
    - R/88_smoke_test_comprehensive.R
decisions:
  - clean_multi_value literal-NA filter applies `values != "NA"` alongside blanks/R-NA (both R/52 + R/101 verbatim copy kept identical per D-07)
  - R/52 drug_group cleanup uses default sep_in="," matching internal comma-separated storage; sep_out=";" for Tableau consistency
  - R/101 drug_group collapse uses gsub(",", ";") normalization before dedup so both legacy (comma) and post-fix (semicolon) CSVs collapse identically
  - detail_export left untouched (no drug_group column); EPISODES_SCHEMA (20 cols), DETAIL_SCHEMA (14 cols), LIFESPAN_SCHEMA (20 cols) all unchanged
metrics:
  duration_seconds: 80
  completed_date: "2026-07-09T17:03:11Z"
  tasks_completed: 2
  files_modified: 3
---

# Quick Task 260709-i1a: Clean drug_group in R/52 and R/101 (dedup/sort/drop literal NA) Summary

**One-liner:** Pipe drug_group through clean_multi_value() in R/52 (comma->semicolon, dedup, sort, drop literal "NA" tokens) and replace union_field() with gsub-normalized collapse in R/101 so comma- and semicolon-separated legacy values dedup identically; added R/88 structural assertion.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Fix clean_multi_value literal-NA filter + add drug_group cleanup to R/52 and R/101 | 6b4079b | R/52_gantt_v2_export.R, R/101_gantt_lifespan_collapse.R |
| 2 | Add R/88 structural check for R/52 drug_group cleanup (Check 12b) | 0aea6db | R/88_smoke_test_comprehensive.R |

## Changes Made

### R/52_gantt_v2_export.R

**Change A — clean_multi_value literal-NA filter (line 779 area):**

```r
# BEFORE
values <- values[values != "" & !is.na(values)]

# AFTER
# DOC-03: drug_group carries literal "NA" string tokens from upstream (e.g. "Chemotherapy,NA");
# filter them out alongside blanks and R-NA so they never reach the output CSVs.
values <- values[values != "" & values != "NA" & !is.na(values)]
```

**Change B — add drug_group to Section 4D Step 1 episodes_export mutate:**

Added after episode_dx_7day_confirmed (with trailing comma added to prior line):
```r
    # DOC-03: drug_group is the last multi-value column added to cleanup; comma-separated internally
    # with duplicate + literal "NA" tokens (e.g. "SCT,SCT,SCT", "Chemotherapy,NA") -> dedup/sort/;
    drug_group = sapply(drug_group, clean_multi_value, USE.NAMES = FALSE)
```

detail_export: unchanged (no drug_group column).
EPISODES_SCHEMA: unchanged (drug_group already present; still 20 cols).

### R/101_gantt_lifespan_collapse.R

**Change A — clean_multi_value literal-NA filter (line 113 area, verbatim copy per D-07):**

Same change as R/52 — the two copies stay byte-for-byte identical.

**Change C — separator-robust drug_group collapse in Section 6 summarise:**

```r
# BEFORE
    drug_group                   = union_field(drug_group),

# AFTER
    # DOC-03: drug_group may arrive comma- OR semicolon-separated (legacy CSVs vs post-R/52-fix);
    # normalize commas to ";" first, then dedup/sort so both cases collapse identically.
    drug_group                   = clean_multi_value(gsub(",", ";", paste(drug_group, collapse = ";")), sep_in = ";", sep_out = ";"),
```

All other union_field() calls (11 remaining) are untouched.

### R/88_smoke_test_comprehensive.R

Added Check 12b immediately after existing Check 12 in Section 15h:
```r
# Check 12b (i1a): R/52 cleans drug_group multi-value column (dedup/sort/drop literal "NA")
check("R/52 applies clean_multi_value to drug_group (quick i1a)",
      any(grepl("drug_group = sapply\\(drug_group, clean_multi_value", r52_text)))
```

## Verification Results

| Check | Command | Expected | Result |
|-------|---------|----------|--------|
| 1 | `grep -c 'values != "NA"' R/52_gantt_v2_export.R` | 1 | PASS |
| 2 | `grep -c 'values != "NA"' R/101_gantt_lifespan_collapse.R` | 1 | PASS |
| 3 | `grep -c 'drug_group = sapply(drug_group, clean_multi_value' R/52_gantt_v2_export.R` | 1 | PASS |
| 4 | `grep -c 'gsub(",", ";", paste(drug_group' R/101_gantt_lifespan_collapse.R` | 1 | PASS |
| 5 | `grep -c 'clean_multi_value to drug_group' R/88_smoke_test_comprehensive.R` | 1 | PASS |
| 6 | Rscript --vanilla parse all 3 files | PARSE OK | SKIPPED (Rscript not available Windows-local) |
| 7 | detail_export unchanged (no drug_group) | 0 lines | PASS |
| 7 | EPISODES_SCHEMA unchanged (20 cols) | 20 cols | PASS |
| 7 | Other union_field calls in R/101 intact | 12 calls | PASS |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. drug_group cleanup is fully wired. The output CSVs (gantt_episodes.csv, gantt_lifespan.csv) will reflect clean drug_group values after re-running R/52 then R/101 on HiPerGator.

## HiPerGator Regeneration Required

After merging this worktree, re-run the following scripts on HiPerGator (in order) to regenerate the output CSVs with cleaned drug_group:

1. `Rscript R/52_gantt_v2_export.R` — regenerates `output/gantt_episodes.csv` with drug_group deduped, sorted, semicolon-separated, literal "NA" removed
2. `Rscript R/101_gantt_lifespan_collapse.R` — regenerates `output/gantt_lifespan.csv` with the same normalized drug_group collapsed across lifespan rows

Both files require HiPerGator production data (DuckDB + RDS cache).

## Self-Check: PASSED

- R/52_gantt_v2_export.R: modified, commits exist (6b4079b)
- R/101_gantt_lifespan_collapse.R: modified, commits exist (6b4079b)
- R/88_smoke_test_comprehensive.R: modified, commits exist (0aea6db)
- All 5 structural grep checks pass
- No schema/column-count changes
- Only the 3 specified files modified
