---
phase: 131-update-all-codes-resolved-next-tables-v2-1-new-xlsx-to-include-med-admin-codes-and-also-every-tab-should-have-a-normalized-name-column
plan: "01"
subsystem: reference-xlsx
tags: [xlsx, rxnorm, med-admin, normalized-name, openxlsx2, rxnav]
dependency_graph:
  requires:
    - R/00_config.R (TREATMENT_CODES$chemo_rxnorm, TREATMENT_CODES$immunotherapy_rxnorm, TREATMENT_CODES$supportive_care_rxnorm)
    - R/utils/utils_treatment.R (safe_table, get_chemo_hits pattern)
    - R/105_normalize_supportive_care_meaning.R (RxNav resolution functions)
    - data/reference/all_codes_resolved_next_tables_v2.1_new.xlsx
  provides:
    - R/131_update_xlsx_med_admin_and_normalized_name.R
    - data/reference/all_codes_resolved_next_tables_v2.1.xlsx (updated with normalized_name + MED_ADMIN rows)
  affects:
    - data/reference/rxnorm_ingredient_cache.csv (grown by this script)
    - data/reference/all_codes_resolved_next_tables_v2.1.xlsx (canonical overwrite)
tech_stack:
  added: []
  patterns:
    - openxlsx2 in-place wb_load + add_data + wb_save (from R/105)
    - RxNav REST API (related.json?tty=IN + historystatus.json)
    - DuckDB MED_ADMIN anti-join via safe_table()
    - int_to_col with 3-tier fallback (openxlsx2/openxlsx/base-26)
    - incremental cache flush every 250 resolutions
key_files:
  created:
    - R/131_update_xlsx_med_admin_and_normalized_name.R (615 lines)
  modified: []
decisions:
  - D-05: normalized_name is snake_case on all tabs
  - D-06: Supportive Care renames G2 header only; G3+ values unchanged
  - D-07: RXNORM rows use RxNav IN resolution; non-RXNORM rows copy Meaning verbatim
  - D-08: non-RXNORM rows get Meaning verbatim (CPT/HCPCS, ICD, DRG, Revenue)
  - D-10: workflow writes v2.1_new.xlsx then overwrites v2.1.xlsx after round-trip verify
  - Anti-join fallback: if named TREATMENT_CODES key absent, falls back to tab own RXNORM codes (safe no-op)
metrics:
  duration: "~30 min"
  completed: "2026-07-17"
  tasks: 2
  files: 1
---

# Phase 131 Plan 01: Build R/131 xlsx update script — Summary

R/131_update_xlsx_med_admin_and_normalized_name.R is a HiPerGator-only script that appends MED_ADMIN-exclusive RxNorm CUI rows to the reference xlsx and adds a normalized_name column to all code tabs.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Sections 1-5: setup, load, DuckDB anti-join, cache | 85db4ff | R/131_update_xlsx_med_admin_and_normalized_name.R |
| 2 | Sections 6-9: normalized_name assembly, write, save, round-trip | 85db4ff | R/131_update_xlsx_med_admin_and_normalized_name.R |

Both tasks were implemented atomically in a single 615-line file commit.

## TREATMENT_CODES Keys Discovered (Section 3 discovery print)

The script will print the actual keys at runtime on HiPerGator. Based on direct inspection of R/00_config.R:

- `chemo_rxnorm` — confirmed present at lines 2782-2880
- `immunotherapy_rxnorm` — confirmed present at lines 3408-3438
- `supportive_care_rxnorm` — confirmed present at line 3220

All three named keys exist. The script uses these for MED_ADMIN anti-join universes. No fallback to tab-code-only mode is expected.

## MED_ADMIN Anti-Join Universe

| Tab | TREATMENT_CODES key | Fallback used? |
|-----|--------------------|----|
| Chemotherapy | TREATMENT_CODES$chemo_rxnorm | No |
| Immunotherapy | TREATMENT_CODES$immunotherapy_rxnorm | No |
| Supportive Care | TREATMENT_CODES$supportive_care_rxnorm | No |

## MED_ADMIN Row Counts (Runtime — requires HiPerGator DuckDB connection)

Cannot be determined without running on HiPerGator. The script prints counts at runtime. The DuckDB section is wrapped in `tryCatch` so the script continues to the normalized_name section even if DuckDB is unavailable.

## normalized_name Strategy Per Tab

| Tab | Strategy | Appended column |
|-----|----------|-----------------|
| Chemotherapy | RxNav for RXNORM rows; Meaning verbatim for CPT/HCPCS | Dynamic col J (after 9 existing) |
| Radiation | Meaning verbatim (CPT/HCPCS only) | Dynamic col — overwrite None header if present, else append |
| SCT | Meaning verbatim (CPT/ICD/DRG/Revenue) | Dynamic col — same as Radiation |
| Immunotherapy | RxNav for RXNORM rows; Meaning verbatim for CPT/HCPCS | Dynamic col G (after 6 real cols) |
| Supportive Care | Header renamed G2 only; G3+ data unchanged | G2 header rename |
| Unrelated | RxNav for RXNORM (9,479+ rows); Meaning verbatim for CPT/HCPCS | Dynamic col G (after 6 cols) |

## Key Design Decisions

- int_to_col uses 3-tier fallback (openxlsx2::int2col then openxlsx::int2col then base-26 pure-R) with smoke-test `stopifnot(int_to_col(10) == "J")`
- Radiation/SCT Pitfall 7 handled: if last column header is NA/empty/"None", that column is reused rather than appending another
- Unrelated tab (9,479+ RXNORM rows): cache is checked first, uncached CUIs resolved via RxNav with 250-item flush intervals; ~30-60 min on first run
- Round-trip verify asserts all 8 sheets in exact order and `normalized_name` non-blank on all 6 code tabs before canonical overwrite

## Deviations from Plan

None — plan executed exactly as written.

## Deferred Items (P8)

R/88 has no smoke-test coverage for R/131 itself. A future phase should add a Section 15x to R/88 asserting R/131 contains:
- `safe_table("MED_ADMIN")`
- `int_to_col`
- normalized_name writes (header + data pattern)
- `file.copy(...XLSX_CANONICAL...)` round-trip guard

Explicitly deferred from Phase 131 per plan output spec.

## Self-Check: PASSED

- R/131_update_xlsx_med_admin_and_normalized_name.R exists: FOUND
- Commit 85db4ff exists: FOUND
- 9 SECTION comments: CONFIRMED (grep -c returns 9)
- safe_table("MED_ADMIN"): CONFIRMED
- MEDADMIN_TYPE == "RX": CONFIRMED
- rxnorm_ingredient_cache.csv: CONFIRMED
- wb_load(XLSX_NEW): CONFIRMED
- EXPECTED_SHEETS with all 8 names: CONFIRMED
- resolve_ingredient function: CONFIRMED
- int_to_col/int2col: CONFIRMED (5 matches)
- "normalized_name".*dims.*G2: CONFIRMED (line 520)
- file.copy.*XLSX_CANONICAL: CONFIRMED (line 592)
- stopifnot.*normalized_name: CONFIRMED (line 582)
- Syntax check (Rscript -e "parse(...)"): SYNTAX OK
