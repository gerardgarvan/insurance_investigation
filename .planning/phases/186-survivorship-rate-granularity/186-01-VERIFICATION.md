---
phase: 186-survivorship-rate-granularity
verified: 2026-10-22T21:30:00Z
status: passed
score: 7/7 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 6/7
  gaps_closed:
    - "RATE-01 orphaned: 186-01-PLAN.md requirements frontmatter updated to [RATE-01, RATE-02, RATE-03]; RATE-01 marked [x] in REQUIREMENTS.md. Verified by re-reading both files."
  gaps_remaining: []
  regressions: []
---

# Phase 186: Survivorship Rate Granularity Verification Report

**Phase Goal:** Build a reader+stacker that pins the Phase 184/185 output workbook, reads annual and half-year rate blocks, stacks into one long team-facing table per modality x far x window x half, applies complementary suppression, and writes a dated xlsx with Primary (years 2+), Secondary (all-years), and KEY sheets in UF colours.

**Verified:** 2026-10-22
**Status:** passed
**Re-verification:** Yes — after RATE-01 gap closure (planning artifact fix; no code changes)

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Team can compare annual and biannual rates per modality in one table, one row per modality x far x window x half | VERIFIED | primary_tbl: 84 rows (28 annual + 56 biannual); unique key asserted via `anyDuplicated`; schema probe confirms 85 rows in Primary sheet (1 section header + data) |
| 2 | Annual-window values match pinned R/184 workbook to last digit; checked in code | VERIFIED | `annual_snapshot` kept pre-pass; re-read of annual block after pass; cell-by-cell character comparison; SUMMARY confirms "112 identical, 0 added suppression"; stop() on any mismatch |
| 3 | Biannual-window values are R/184 half-year (years 2+) block, carried verbatim | VERIFIED | `read_rates_block(r184_output_path, HALF_HDR)` reads by exact header; all values coerced to character; no recomputation |
| 4 | Suppressed cells from R/184 appear as-is; no re-suppression or back-calculation | VERIFIED | Rule 0 of `apply_complementary_suppression`: helper only adds suppression, never removes it; fixture (c) asserts identical() on no-suppression table |
| 5 | No small count recoverable by arithmetic; complementary suppression applied | VERIFIED | Rules 1-3 implemented and iterated until stable; fixtures (a)-(d) self-check; applied to both primary_tbl and secondary_tbl; SUMMARY: primary 0 cells changed, secondary events=1 rate=1 changed; visual check confirmed Rule 1 fired correctly |
| 6 | Rate unit (per patient-year) stated on KEY; no rescaling applied | VERIFIED | D-09 guard at lines 151-162; `rate_unit <- "per patient-year"`; KEY rows "rate unit" and "rate unit note" confirmed by schema probe (24 KEY rows); no multiply/divide on rate column in script |
| 7 | KEY leftmost; all-years on Secondary; UF colours applied | VERIFIED | Schema probe: `sheets (in order): KEY \| Primary \| Secondary`; `addWorksheet` order in script: KEY (line 634), Primary (698), Secondary (707); `UF_BLUE = "#0021A5"`, `UF_ORANGE = "#FA4616"` at lines 611-612 |

**Score:** 7/7 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/186_survivorship_rate_granularity.R` | Reader+stacker script; pins R184_OUTPUT; reads 4 blocks; stacks; complementary suppression; writes dated xlsx | VERIFIED | 726 lines (> 150 minimum); all acceptance criteria grep checks pass; commits 08d4f05 and 95aab6a |
| `output/survivorship_rate_granularity_<date>.xlsx` | KEY (leftmost) + Primary (years 2+) + Secondary (all-years) | VERIFIED | `output/survivorship_rate_granularity_20261022.xlsx` confirmed by SUMMARY Task 5 and schema probe `186_schema_20261022.md` |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `R/186_survivorship_rate_granularity.R` | `output/modality_rate_model_20261022.xlsx` (R184_OUTPUT pin) | `Sys.getenv("R184_OUTPUT", R184_OUTPUT_DEFAULT)` + `here::here()` | VERIFIED | Lines 37-39; constant `R184_OUTPUT_DEFAULT = "output/modality_rate_model_20261022.xlsx"`; file.exists stop() guard at line 46 |
| Annual block read | Primary sheet window='annual' | section header `"Annual rates (years 2+) — by modality x far"` (em dash as `—` in code) | VERIFIED | `ANNUAL_HDR` at line 60; `read_rates_block(r184_output_path, ANNUAL_HDR)` at line 120; `window = "annual"` in `build_annual_long` at line 233 |
| Half-year block read | Primary sheet window='biannual' | section header `"Half-year rates (years 2+)"` | VERIFIED | `HALF_HDR` at line 63; `read_rates_block(r184_output_path, HALF_HDR)` at line 135; `window = "biannual"` in `build_half_long` at line 250 |
| `apply_complementary_suppression` | `primary_tbl_final` and `secondary_tbl` | called at lines 531 and 600 | VERIFIED | Function defined at line 348; applied to primary (line 531) and secondary (line 600) — 3 occurrences (definition + 2 applications) |
| `annual_snapshot` / annual match check | stop() on mismatch | re-reads annual block after complementary pass and compares cell-by-cell | VERIFIED | Lines 540-578; SUMMARY confirms 0 mismatches |

---

### Data-Flow Trace (Level 4)

Script is a reader-stacker: data flows from pinned xlsx on disk through in-memory tibbles to output xlsx. No database queries, no patient-level state.

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| `primary_tbl_final` | `annual_raw`, `half_raw` | `openxlsx::read.xlsx(r184_output_path, sheet="Rates", colNames=FALSE)` | Yes — reads actual R/184 workbook on disk | FLOWING |
| `secondary_tbl` | `annual_all_raw`, `half_all_raw` | Same Rates sheet, different section headers | Yes | FLOWING |
| `key_data` | Run-time metadata + computed results | `Sys.Date()`, `Sys.info()`, computed `nested`, `changed`, `annual_match_note` | Yes — all populated at run time | FLOWING |

---

### Behavioral Spot-Checks

Script requires HiPerGator + R/4.5 + the pinned workbook. No R on local Windows. All spot-checks from the completed HiPerGator Task 5 run (2026-10-22).

| Behavior | Evidence | Status |
|----------|----------|--------|
| All four fixtures pass without stopifnot error | SUMMARY: "All four PASSED." | PASS |
| Script writes dated xlsx without stop() | SUMMARY: output path confirmed | PASS |
| 84 primary rows (28 annual + 56 biannual) | SUMMARY: "primary_tbl: 84 rows. Key unique: OK." | PASS |
| Nesting check: 27 testable, 27 matched; nested=TRUE | SUMMARY: confirmed | PASS |
| Annual match check: 0 mismatches | SUMMARY: "112 identical, 0 added suppression" | PASS |
| Secondary suppression: events=1, rate=1 changed; Rule 1 fired correctly | SUMMARY: confirmed; "Visual check: KEY is leftmost tab. No rate shown next to a suppressed cell" | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| RATE-01 | 186-01-PLAN.md | Patient-level count and rate per modality at annual window, read from verified R/184 by exact label; no recomputation drift | SATISFIED | Annual block read by exact section header `ANNUAL_HDR`; cell-by-cell match check (lines 539-578) asserts every output annual cell equals R/184 or was added-suppressed; "112 identical, 0 added suppression"; REQUIREMENTS.md `[x]`; 186-01-PLAN.md requirements field confirmed `[RATE-01, RATE-02, RATE-03]` |
| RATE-02 | 186-01-PLAN.md | Biannual definition resolved via D-186-01 and implemented | SATISFIED | D-186-01 recorded in CONTEXT.md; 56 biannual rows (14 modalities x 2 far x 2 halves); KEY row "biannual definition = every 6 months (twice yearly); D-186-01"; REQUIREMENTS.md `[x]` |
| RATE-03 | 186-01-PLAN.md | Single team table; columns patients/events/patient-years/rate; KEY leftmost; UF colours; suppression applied | SATISFIED | primary_tbl_final uses team-facing columns (no `_sup` in writeData calls); KEY leftmost per schema probe; UF_BLUE/UF_ORANGE applied; complementary suppression applied; REQUIREMENTS.md `[x]` |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `R/186_survivorship_rate_granularity.R` | 59 | Literal em dash in a code comment | Info | Comment only; not in any string constant that is parsed or written to a file. The string constants `ANNUAL_HDR`, `ANNUAL_ALL_HDR`, and `DASH` all correctly use `—` via escape or `paste0`. No sync risk. |

No blockers. No TODO/FIXME/placeholder comments. No `return null` / `return []` stubs. No `setwd()`. No `output/internal/` writes. No `_sup` column names in `writeData` calls.

---

### Human Verification

No outstanding human verification items. The Secondary sheet visual check (no rate shown next to a suppressed cell) was confirmed in SUMMARY Task 5: "Visual check: KEY is leftmost tab. No rate shown next to a suppressed cell (secondary had 1 event cell suppressed; corresponding rate also suppressed — Rule 1 fired correctly on second pass)."

---

_Verified: 2026-10-22_
_Verifier: Claude (gsd-verifier)_
