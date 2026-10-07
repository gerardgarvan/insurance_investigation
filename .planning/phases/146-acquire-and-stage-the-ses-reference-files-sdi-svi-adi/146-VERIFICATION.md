---
phase: 146-acquire-and-stage-the-ses-reference-files-sdi-svi-adi
verified: 2026-10-01T00:00:00Z
status: human_needed
score: 5/5 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 4/5
  gaps_closed:
    - "svi_2020_zcta_derived.csv committed to repo (commit 0fe53b3, 33120 rows, 16MB, CDC public domain, correct columns ZCTA/RPL_THEMES)"
  gaps_remaining: []
  regressions:
    - "R/116 Coverage Ceilings table still shows PENDING strings at lines 463-464 for the SDI and SVI haircut counts — minor documentation inconsistency flagged in previous report, still present"
human_verification:
  - test: "Confirm neighborhood_atlas_zip9_adi.csv is present on HiPerGator at /blue/erin.mobley-hl.bcu/insurance_investigation/data/reference/"
    expected: "ls -la confirms file exists; R/116 probe has_adi returns TRUE; ADI coverage 75.0% reproducible"
    why_human: "File is 655MB, gitignored, must be scp'd to HiPerGator. Cannot verify remote filesystem from this machine."
---

# Phase 146: Acquire and Stage the SES Reference Files (SDI, SVI, ADI) — Verification Report

**Phase Goal:** Acquire and stage the three absent SES reference files for R/116 — download SDI (ZCTA), derive SVI to ZCTA (CDC publishes no 2020 ZCTA file), and register-and-download ADI (ZIP9) — quantify each geography-mismatch haircut below the 77.7% ZIP ceiling, correct the 68.6% ADI figure to 77.7%, and re-run R/116 so each staged index reports honest sub-ceiling coverage while probe gates still degrade absent indices to NA.

**Requirement IDs:** SES-01, SES-02, SES-03, SES-04 (informal phase labels; not present in .planning/REQUIREMENTS.md as of its last update 2026-07-24, which covers Phases 132-136 only)

**Verified:** 2026-10-01
**Status:** HUMAN NEEDED — automated checks pass 5/5; one item requires HiPerGator confirmation
**Re-verification:** Yes — gap closed after initial verification on 2026-08-17

---

## Requirements Coverage Note

SES-01 through SES-04 appear in PLAN frontmatter for plans 146-01 through 146-06 but are not listed in `.planning/REQUIREMENTS.md`. That file's last update covers Phases 132-136 only; these IDs are informal planning labels created for this phase. This does not affect the verdict — the goal and must-haves are well-specified in plan frontmatter and ROADMAP.md.

---

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | SDI staged at `data/reference/zip5_sdi_reference.csv` with correct columns | VERIFIED | File exists (32,989 rows, 324KB); header = "ZIP5,SDI_score"; R/116 line 66 `SDI_PATH` and line 251 `select(ZIP5, sdi_score = SDI_score)` match exactly |
| 2 | ADI staged (`neighborhood_atlas_zip9_adi.csv`, gitignored) and R/116 wired to it | VERIFIED LOCAL / HUMAN-NEEDED (HiPerGator) | File present locally (655MB); gitignored; R/116 line 67 `ADI_PATH`; line 254 auto-detect join confirmed by PART J 75.0% result |
| 3 | SVI derived file `svi_2020_zcta_derived.csv` committed to repo and R/116 wired | VERIFIED | File committed at 0fe53b3 (2026-08-17); 33,120 data rows; header = "ZCTA,RPL_THEMES,vintage,method,source"; R/116 line 71 `SVI_PATH`; line 286 `select(ZIP5 = ZCTA, svi_score = RPL_THEMES)` |
| 4 | R/116 Coverage Ceilings sheet documents 77.7% ceiling and all indices non-zero | VERIFIED | DISCOVERY.md PART J: RUCA 77.7%, SDI 77.5%, SVI 77.5%, ADI 75.0%; code at lines 455-489 builds the sheet; `best_achievable_pct` row for RUCA = "77.7% (achieved)" |
| 5 | Probe gates degrade absent indices to NA without crashing (R/88 passes) | VERIFIED | PART J records "R/88: PASS"; `has_sdi`, `has_adi`, `has_svi` probes at lines 85-87 gate all downstream reads; 146-06-SUMMARY confirms same |

**Score: 5/5 truths verified**

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `data/reference/zip5_sdi_reference.csv` | SDI ZCTA scores keyed for R/116 ZIP5 join | VERIFIED | 32,989 data rows; columns ZIP5, SDI_score; committed |
| `data/reference/neighborhood_atlas_zip9_adi.csv` | ADI ZIP9-keyed 23-state collation | VERIFIED LOCAL | 655MB, gitignored, present on local disk; HiPerGator transfer not verifiable from here |
| `data/reference/svi_2020_zcta_derived.csv` | Derived ZCTA SVI with ZCTA, RPL_THEMES, vintage, method, source | VERIFIED | Committed at 0fe53b3 (16MB, 33,120 rows); header confirmed correct |
| `R/117_build_svi_zcta.R` | Committed, reproducible SVI derivation (D-02a-i) | VERIFIED | Committed (175 lines; findSVI approach; ZCTA-vs-tract caveat in header) |
| `R/116_encounter_ses_index.R` | Reads all three staged paths; Coverage Ceilings sheet | VERIFIED | All three `*_PATH` variables wired; probe gates at lines 85-87; Coverage Ceilings table built at lines 455-489 |
| `data/reference/README.md` | Documents all three indices with corrected coverage figures | VERIFIED | README updated in commit 759254f; D-01 ZCTA-via-ZIP5, ADI 77.7% ceiling, SVI derived-file explanation all present |
| `.planning/phases/.../146-DISCOVERY.md` | Source facts, decisions D-01/D-02/D-05, PART J real-run results | VERIFIED | All parts A-J present; RUCA 77.7%, SDI 77.5%, SVI 77.5%, ADI 75.0% in PART J |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `zip5_sdi_reference.csv` (ZIP5, SDI_score) | R/116 `select(ZIP5, sdi_score = SDI_score)` | Column-name match | WIRED | Exact match; lines 66, 251 |
| `svi_2020_zcta_derived.csv` (ZCTA, RPL_THEMES) | R/116 `select(ZIP5 = ZCTA, svi_score = RPL_THEMES)` | Column-name match | WIRED | File now present; lines 71, 286 match committed file's header |
| `neighborhood_atlas_zip9_adi.csv` (ZIP9, ADI_NATRANK) | R/116 auto-detect candidate column lists | Column auto-detection | WIRED | Lines 67, 254; PART J confirmed 75.0% ADI |
| R/116 real-run coverage per index | 77.7% ceiling in README / Coverage Ceilings sheet | Each index <= 77.7% and non-zero | VERIFIED (PART J) | RUCA 77.7%, SDI 77.5%, SVI 77.5%, ADI 75.0% |

---

## Data-Flow Trace (Level 4)

R/116 is a read-only investigation script. Data-flow question is whether probe-gated reads load the staged files and produce non-zero coverage.

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| `zip5_sdi_reference.csv` | `sdi_lookup` | `vroom()` at SDI_PATH; `has_sdi` probe guards | Confirmed (32,989 rows; PART J 77.5%) | FLOWING |
| `neighborhood_atlas_zip9_adi.csv` | `adi_lookup` | `vroom()` at ADI_PATH; `has_adi` probe guards | Confirmed via PART J (75.0%) — HiPerGator run | FLOWING (HiPerGator) |
| `svi_2020_zcta_derived.csv` | `svi_lookup` | `vroom()` at SVI_PATH; `has_svi` probe guards | File now committed locally (33,120 rows; PART J 77.5%) | FLOWING |

---

## Behavioral Spot-Checks

R scripts require HiPerGator runtime. Static checks only.

| Behavior | Check | Result | Status |
|----------|-------|--------|--------|
| SDI CSV has correct columns | `head -1 zip5_sdi_reference.csv` | "ZIP5,SDI_score" | PASS |
| SVI CSV committed and correct columns | `head -1 svi_2020_zcta_derived.csv` | "ZCTA,RPL_THEMES,vintage,method,source" | PASS |
| SVI CSV row count | `wc -l` = 33,121 (33,120 data rows) | Matches commit message claim | PASS |
| R/116 SVI_PATH points to derived filename | grep R/116 line 71 | `svi_2020_zcta_derived.csv` | PASS |
| R/116 SVI select() matches file header columns | grep R/116 line 286 | `select(ZIP5 = ZCTA, svi_score = RPL_THEMES)` | PASS |
| ADI gitignored | grep .gitignore | Present at line 80 | PASS |
| ADI present locally | `ls -la` | 655MB, exists | PASS |
| Coverage Ceilings PENDING strings | grep R/116 lines 463-464 | Still "PENDING HiPerGator run" for SDI/SVI haircuts | WARNING (see anti-patterns) |

---

## Anti-Patterns Found

| File | Line(s) | Pattern | Severity | Impact |
|------|---------|---------|----------|--------|
| `R/116_encounter_ses_index.R` | 454, 463, 464 | `best_achievable_pct` values for SDI and SVI still say "PENDING HiPerGator run" rather than the actual PART J figures (SDI 77.5%, SVI 77.5%) | INFO | No runtime impact — these strings appear only in the Coverage Ceilings worksheet output. A quick edit to replace with "<=77.7% (77.5% achieved — PART J 2026-08-17 run)" would close this. Not a blocker. |

No TODO/FIXME stubs in production code paths. Probe gates correctly degrade absent files to NA.

---

## Human Verification Required

### 1. neighborhood_atlas_zip9_adi.csv on HiPerGator

**Test:** On HiPerGator, run `ls -la /blue/erin.mobley-hl.bcu/insurance_investigation/data/reference/neighborhood_atlas_zip9_adi.csv`
**Expected:** File exists (478-655MB); `R/116` probe `has_adi` returns TRUE; ADI coverage 75.0% reproducible
**Why human:** File is 655MB, gitignored; must be scp'd to HiPerGator. Cannot verify the remote filesystem from this machine.

---

## Re-verification Summary

**Gap closed:** `svi_2020_zcta_derived.csv` was committed to the repo at commit `0fe53b3` on 2026-08-17 with correct header (ZCTA,RPL_THEMES,vintage,method,source) and 33,120 data rows. The file is CDC public domain (US government data, no redistribution restriction). The previous report's sole blocking gap is resolved.

**Regression noted (INFO only):** R/116 Coverage Ceilings table still shows "PENDING HiPerGator run" text in the `best_achievable_pct` column for SDI and SVI rows (lines 463-464). The actual PART J figures (SDI 77.5%, SVI 77.5%) are available and could replace these strings. Not a runtime blocker.

**Remaining human item:** The ADI file (gitignored, 655MB) must be confirmed on HiPerGator. The local file exists; PART J recorded 75.0% ADI from a real HiPerGator run, which is strong evidence it was present there at run time. This item is flagged as confirmatory, not a gap.

**Phase goal achievement:** All five observable truths verified. Three reference files staged (SDI committed, SVI committed, ADI present locally and confirmed by PART J). R/116 wired to all three with correct column mappings. Probe gates confirmed. Coverage Ceilings sheet built in code. 77.7% ceiling documented and all achieved figures below it. Phase goal is achieved.

---

_Verified: 2026-10-01_
_Verifier: Claude (gsd-verifier) — re-verification after gap closure_
