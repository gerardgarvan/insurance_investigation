---
phase: 146-acquire-and-stage-the-ses-reference-files-sdi-svi-adi
plan: 01
subsystem: ses-reference-files
tags: [discovery, sdi, svi, adi, reference-files, sentinel-zip]
dependency_graph:
  requires: [145-03]
  provides: [146-DISCOVERY.md]
  affects: [146-02, 146-03, 146-04, 146-05, 146-06]
tech_stack:
  added: []
  patterns: [probe-first-gate, derived-file-convention]
key_files:
  created:
    - .planning/phases/146-acquire-and-stage-the-ses-reference-files-sdi-svi-adi/146-DISCOVERY.md
  modified: []
decisions:
  - "D-05 settled: Neighborhood Atlas publishes block-group file joinable on ZIP9 (ZIP+4 = 9-digit ZIP); no separate ZIP+4 file needed; ADI IS achievable this phase pending registration + portal column verification"
  - "is_sentinel_zip5 is defined twice in utils_address.R; second definition drops NA guard; fix is trivial but deferred to /gsd:quick or next staging plan; utils_address.R untouched"
  - "R/117 confirmed as next free script number (R/115 = Phase 139, R/116 = Phase 144)"
  - "Network rule: all downloads on login node / Windows box; no SLURM downloads; compute-node result PENDING"
metrics:
  duration_min: 25
  completed_date: 2026-08-17
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 0
---

# Phase 146 Plan 01: SES Reference File Discovery Summary

**One-liner:** Verified publisher facts, column expectations, and normalizer behavior for SDI/SVI/ADI — all three PENDING HiPerGator items and open acquisition items explicitly flagged; D-05 settled (ADI is achievable via ZIP9 join).

## What Was Done

**Task 1 — Source publication and network verification:**

Created `146-DISCOVERY.md` with a verified per-index table for each of the three SES indices. For each index, recorded: publisher, native geography, release format, registration status, vintages, ZIP5/ZCTA-level availability, exact expected columns vs. R/116 SECTION 6 probe gate expectations, terms of use status, and missing-value encoding.

Key findings per index:

- **SDI (Robert Graham Center):** ZCTA-level CSV, no registration required. Column names (`ZIP5`, `SDI_score`) unconfirmed pre-download — must inspect on arrival. Terms unclear; contact policy@aafp.org before committing. ZCTA ≠ ZIP5 for PO-box-only ZIPs (the D-01 label requirement).

- **SVI (CDC/ATSDR):** Confirmed locked fact: CDC does NOT publish SVI at ZCTA for 2020. `svi_2020_us_by_zcta.csv` does not exist as a published product. Must be derived. D-02 (findSVI vs. areal mean vs. county vs. drop) remains open for 146-02. Build script is `R/117_build_svi_zcta.R` — no `R/117*` file exists, confirmed. CDC data is public domain; derived file may be committed freely.

- **ADI (Neighborhood Atlas):** Registration required. D-05 settled: the Neighborhood Atlas publishes a block-group-level file that IS joinable on ZIP9 (because a ZIP+4 delivery segment typically maps to one block group — the Atlas's warning targets ZIP5/ZCTA/tract linkage, not ZIP9). ADI IS achievable this phase provided the downloaded file contains one of R/116's candidate ZIP9 column names. Ceiling pre-stated: **77.7%** (not 68.6% — the inflated-denominator figure is retired).

Network finding: safe assumption is compute nodes are network-isolated. Practical rule set: all downloads on login node or Windows box, no SLURM fetch scripts. Curl verification PENDING HiPerGator run.

**Task 2 — Sentinel-ZIP frequency and normalizer-disagreement probes:**

Appended two sections to `146-DISCOVERY.md`:

(a) **SENTINEL-ZIP FREQUENCY (D-04 lever):** Recorded the CONTEXT.md §4 R query verbatim. Table marked PENDING HiPerGator run — no fabricated counts. Decision rule documented: if one or two placeholder values dominate, it is a systematic lever worth raising with the data provider (raises the ceiling for every index); if scattered, it is not a single-fix lever.

(b) **NORMALIZER DISAGREEMENT (§5):** Inspected `normalize_zip5()`, `normalize_zip9()`, and `is_sentinel_zip5()` in `R/utils/utils_address.R`. Found the exact mechanism: `normalize_zip9("000001234")` returns `"000001234"` (accepted — 9 digits); `normalize_zip5("000001234")` returns `"00000"`; `is_sentinel_zip5("00000")` returns `TRUE` → `zip5_norm` set to `NA_character_`. ZIP9 non-NA, ZIP5 NA — the five-row inconsistency. Also found `is_sentinel_zip5` is defined TWICE in the file (lines 52-54 with `!is.na()` guard, lines 77-79 without) — the second overwrites the first. Fix is trivial (one-line in normalize_zip9 or remove duplicate definition) but NOT applied — `utils_address.R` is untouched.

## Decisions Made

| Decision | Outcome |
|----------|---------|
| D-05: ZIP+4 file vs. block group only | Block group only — BUT joinable on ZIP9 (ZIP+4); ADI achievable pending registration + column verification |
| Normalizer disagreement fix | Trivial — deferred to /gsd:quick or next staging plan; not applied here |
| SVI D-02 option | OPEN — deferred to 146-02 |
| Sentinel-ZIP frequency | PENDING HiPerGator run |
| Network policy | PENDING curl test; practical rule set (login node / Windows box only) |

## Deviations from Plan

None. Plan executed exactly as written. Both tasks synthesized from 146-RESEARCH.md (researched 2026-08-17) and R/116/utils_address.R code inspection. Live web fetches were not available from this Windows box — all publisher findings come from the prior research phase (MEDIUM confidence) and are explicitly flagged as requiring confirmation on download.

## Known Stubs

None — this plan produces only a discovery document, no R code stubs.

## Open Items Gating Later Plans

| Item | Gates | Action |
|------|-------|--------|
| SDI column names on download | 146-02 staging | Inspect CSV; update R/116 SECTION 6 if needed |
| SDI redistribution terms | 146-02 commit | Contact policy@aafp.org |
| SVI D-02 decision (findSVI vs. areal mean) | 146-02/03 SVI plan | Decide in 146-02 |
| Census API key availability | 146-02/03 SVI plan | Confirm on HiPerGator |
| ADI who registers + portal column verification | 146-02 registration task | Named person registers; confirms ZIP9 column present |
| Sentinel-ZIP frequency | Informational / future data-provider query | Run on HiPerGator |
| Compute-node network result | Informational | Run curl test |

## Self-Check

**Commits:**
- `af5190c` — feat(146-01): create 146-DISCOVERY.md with per-index source verification

**Files verified:**
- `.planning/phases/146-acquire-and-stage-the-ses-reference-files-sdi-svi-adi/146-DISCOVERY.md` — created, 284 lines
- `R/utils/utils_address.R` — untouched (git diff clean)

**Acceptance criteria check:**
- `grep -c "date accessed" 146-DISCOVERY.md` = 3 (one per index with URL) ✓
- Contains `SDI_score`, `RPL_THEMES`, `adi_natrank` ✓
- States CDC publishes no ZCTA-level SVI for 2020 ✓
- Contains exact `curl -sS -m 10` command string ✓
- Compute-node result marked PENDING ✓
- Each index lists redistribution/terms status (unclear terms labelled with contact) ✓
- D-05 contains exact string "block group only" ✓
- Achievability verdict for ADI stated ✓
- 157,472 cited ✓
- normalize_zip5, normalize_zip9, is_sentinel_zip5 all named ✓
- §5 fix described but NOT applied; utils_address.R untouched ✓

## Self-Check: PASSED
