---
phase: 146-acquire-and-stage-the-ses-reference-files-sdi-svi-adi
verified: 2026-08-17T00:00:00Z
status: passed
score: 5/5 must-haves verified
gaps:
  - truth: "data/reference/svi_2020_zcta_derived.csv exists in the repo"
    status: resolved
    resolved: "2026-08-17 — file downloaded from HiPerGator and committed (commit 0fe53b3, 33120 rows, 16MB, CDC public domain)"
    reason: "File was absent at verification time; user downloaded from HiPerGator and committed directly."
    artifacts:
      - path: "data/reference/svi_2020_zcta_derived.csv"
        issue: "File does not exist on local filesystem; not gitignored (would appear in git status untracked if it existed on HiPerGator only)"
    missing:
      - "Run R/117_build_svi_zcta.R on HiPerGator to produce the CSV, then either commit it (CDC data is public domain — no restriction) or scp it to HiPerGator and document the transfer path in README"
      - "Once produced, confirm ZCTA and RPL_THEMES column names match R/116 SECTION 6 select(ZIP5 = ZCTA, svi_score = RPL_THEMES)"
human_verification:
  - test: "Confirm neighborhood_atlas_zip9_adi.csv is present on HiPerGator at /blue/erin.mobley-hl.bcu/insurance_investigation/data/reference/"
    expected: "ls -la confirms the file exists; R/116 probe has_adi returns TRUE and ADI coverage 75.0% (as recorded in PART J)"
    why_human: "File is 478MB, gitignored, and must be scp'd to HiPerGator. Cannot verify the remote filesystem from this box."
  - test: "Confirm R/117_build_svi_zcta.R was run on HiPerGator and svi_2020_zcta_derived.csv either (a) committed to the repo or (b) exists at /blue/erin.mobley-hl.bcu/insurance_investigation/data/reference/ on HiPerGator"
    expected: "File exists at that path (or in the repo); R/116 SVI_PATH probe finds it; SVI coverage = 77.5% reproducible"
    why_human: "Requires HiPerGator login to verify remote filesystem."
---

# Phase 146: Acquire and Stage the SES Reference Files (SDI, SVI, ADI) — Verification Report

**Phase Goal:** Acquire and stage the three absent SES reference files for R/116 — download SDI (ZCTA), derive SVI to ZCTA (CDC publishes no 2020 ZCTA file), and register-and-download ADI (ZIP9) — quantify each geography-mismatch haircut below the 77.7% ZIP ceiling, correct the 68.6% ADI figure to 77.7%, and re-run R/116 so each staged index reports honest sub-ceiling coverage while probe gates still degrade absent indices to NA.

**Requirement IDs:** SES-01, SES-02, SES-03, SES-04

**Verified:** 2026-08-17
**Status:** GAPS FOUND (1 gap; 4 of 5 must-haves verified)
**Re-verification:** No — initial verification

---

## Requirements Coverage Note

SES-01, SES-02, SES-03, SES-04 appear in PLAN frontmatter across plans 146-01 through 146-06 but are NOT present in `.planning/REQUIREMENTS.md`. REQUIREMENTS.md contains 21 requirements mapped to Phases 132-136 (as of last update 2026-07-24). Either the SES-* IDs are informal planning labels created for this phase, or REQUIREMENTS.md was not updated when this phase was added to the roadmap. This is noted but does not change the goal-achievement verdict — the goal and must-haves are well-specified in the plan frontmatter and ROADMAP.md.

---

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | SDI staged at `data/reference/zip5_sdi_reference.csv` with correct columns | VERIFIED | File exists (32,989 rows); columns ZIP5 + SDI_score confirmed by head; R/116 line 216 `select(ZIP5, sdi_score = SDI_score)` matches exactly |
| 2 | ADI staged (gitignored 478MB file) and R/116 wired to `neighborhood_atlas_zip9_adi.csv` | VERIFIED (local) / HUMAN-NEEDED (HiPerGator) | File present locally (`ls data/reference/`); gitignored at `.gitignore:80`; R/116 line 67 `ADI_PATH <- file.path("data","reference","neighborhood_atlas_zip9_adi.csv")`; R/116 line 254 `select(ZIP9_key = all_of(adi_zip9_col), adi_natrank = all_of(adi_rank_col))`; PART J records ADI 75.0% from real run |
| 3 | SVI derived-file path committed in R/116 as `svi_2020_zcta_derived.csv`; R/117 build script committed | VERIFIED (wiring) / FAILED (file) | R/116 line 70 `SVI_PATH <- file.path("data","reference","svi_2020_zcta_derived.csv")`; R/116 line 286 `select(ZIP5 = ZCTA, svi_score = RPL_THEMES)`; R/117_build_svi_zcta.R exists (175 lines, findSVI D-02a-i); **BUT `svi_2020_zcta_derived.csv` does not exist on the local filesystem and is not gitignored** |
| 4 | R/116 Coverage Ceilings sheet documents 77.7% ceiling and all indices non-zero | VERIFIED | DISCOVERY.md PART J: RUCA 77.7%, SDI 77.5%, SVI 77.5%, ADI 75.0% all pass; R/116 lines 422-425 build the Coverage Ceilings sheet with 77.7% strings; README.md contains "77.7" throughout |
| 5 | R/88 passes; probe gates degrade absent indices to NA without crashing | VERIFIED | PART J records "R/88: PASS — probe gates degrade absent indices to NA without crashing"; 146-06-SUMMARY line confirms same |

**Score: 4/5 truths verified** (Truth 3 partially failed: wiring and build script correct, but the CSV file itself is absent locally and unconfirmed on HiPerGator)

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `data/reference/zip5_sdi_reference.csv` | SDI ZCTA scores keyed for R/116 ZIP5 join | VERIFIED | 32,989 data rows; columns ZIP5, SDI_score; committed to repo |
| `data/reference/neighborhood_atlas_zip9_adi.csv` | ADI ZIP9-keyed 23-state collation | VERIFIED LOCAL | 478MB, gitignored, present on local disk; HiPerGator transfer required for R/116 to use it |
| `data/reference/svi_2020_zcta_derived.csv` | Derived ZCTA SVI with ZCTA, RPL_THEMES, vintage, method, source | MISSING | File does not exist locally; not gitignored; build script R/117 is committed but the Census API run has not been committed back |
| `R/117_build_svi_zcta.R` | Committed, reproducible SVI derivation (D-02a-i) with recorded method | VERIFIED | 175 lines; findSVI approach; ZCTA-vs-tract caveat documented in file header |
| `R/116_encounter_ses_index.R` | Reads staged SVI derived path + reconciled columns; Coverage Ceilings sheet | VERIFIED | SVI_PATH = svi_2020_zcta_derived.csv (line 70); select(ZIP5 = ZCTA, svi_score = RPL_THEMES) (line 286); 77.7% ceiling sheet built in code |
| `data/reference/README.md` | Corrected SVI (derived), SDI (D-01), ADI 77.7% ceiling documentation | VERIFIED | README documents all three indices accurately; D-01 ZCTA-via-ZIP5 label present; ADI 77.7% ceiling section present; SVI derived-file explanation present with ZCTA-vs-tract caveat |
| `.planning/phases/.../146-DISCOVERY.md` | Source facts, network result, decisions D-01/D-02/D-05, PART J real-run results | VERIFIED | All parts A-J present; RUCA 77.7%, SDI 77.5%, SVI 77.5%, ADI 75.0% recorded in PART J |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `data/reference/zip5_sdi_reference.csv` (ZIP5, SDI_score) | R/116 SECTION 6 `select(ZIP5, sdi_score = SDI_score)` | Column-name match | WIRED | Exact match: file has ZIP5 + SDI_score; R/116 line 216 selects them |
| `data/reference/svi_2020_zcta_derived.csv` (ZCTA, RPL_THEMES) | R/116 SECTION 6 `select(ZIP5 = ZCTA, svi_score = RPL_THEMES)` | Column-name match | WIRED IN CODE / FILE ABSENT | R/116 line 286 is correct; file does not exist locally |
| `data/reference/neighborhood_atlas_zip9_adi.csv` (ZIP9, ADI_NATRANK) | R/116 SECTION 6 auto-detect candidate lists | Column auto-detection | WIRED | R/116 line 254; ZIP9 and ADI_NATRANK both in candidate lists; PART J confirmed 75.0% ADI |
| R/116 real-run coverage per index | 77.7% ceiling in README / Coverage Ceilings sheet | Each index <= 77.7% and non-zero | VERIFIED (PART J) | RUCA 77.7%, SDI 77.5%, SVI 77.5%, ADI 75.0% — all pass |

---

## Data-Flow Trace (Level 4)

R/116 is a read-only investigation script — it reads staged CSVs and joins to encounter RDS. The relevant data-flow question is whether the probe-gated reads actually load the staged files.

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| `zip5_sdi_reference.csv` | `sdi_lookup` | `vroom()` at SDI_PATH; `has_sdi` probe guards | CONFIRMED (32,989 rows staged; PART J 77.5%) | FLOWING |
| `neighborhood_atlas_zip9_adi.csv` | `adi_lookup` | `vroom()` at ADI_PATH; `has_adi` probe guards | CONFIRMED via PART J (75.0%) — file present on HiPerGator for that run | FLOWING (HiPerGator run) |
| `svi_2020_zcta_derived.csv` | `svi_lookup` | `vroom()` at SVI_PATH; `has_svi` probe guards | File absent locally; PART J reports 77.5% — run was done on HiPerGator | FLOWING (HiPerGator only; file not committed back) |

---

## Behavioral Spot-Checks

The R scripts require HiPerGator runtime (DuckDB + PCORnet CSVs). Spot-checks limited to static verification.

| Behavior | Check | Result | Status |
|----------|-------|--------|--------|
| SDI CSV has correct columns | `head -1 data/reference/zip5_sdi_reference.csv` | "ZIP5,SDI_score" | PASS |
| SDI CSV row count matches staging report | `wc -l` = 32,990 (32,989 data rows) | Matches PART I claim of 32,989 rows | PASS |
| R/116 SVI_PATH points to derived file name | `grep SVI_PATH R/116_encounter_ses_index.R` | `svi_2020_zcta_derived.csv` at line 70 | PASS |
| R/116 SVI select() matches derived file columns | grep R/116 | `select(ZIP5 = ZCTA, svi_score = RPL_THEMES)` at line 286 | PASS |
| ADI gitignored | grep `.gitignore` | `data/reference/neighborhood_atlas_zip9_adi.csv` at line 80 | PASS |
| R/117 build script substantive (>30 lines) | wc -l | 175 lines | PASS |
| svi_2020_zcta_derived.csv absent locally | ls | FILE NOT PRESENT | FLAG — see gap |

---

## Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| `data/reference/svi_2020_zcta_derived.csv` | File absent (not produced and committed) | WARNING | R/116 SVI probe will silently return `svi_score = NA` for all rows on any machine that has not independently run R/117. The PART J result was produced on HiPerGator; reproducing it requires either committing the file or manually running R/117 on HiPerGator. |
| `R/116_encounter_ses_index.R` lines 423-424 | Coverage Ceilings sheet still shows "PENDING HiPerGator run" strings for SDI and SVI haircuts | INFO | PART J recorded coverage numbers, but the in-code strings at lines 423-424 still say "PENDING". Not a runtime error — just a documentation inconsistency in the workbook output. |

No TODO/FIXME stubs found in production code paths. Probe gates correctly degrade absent files to NA without crashing.

---

## Human Verification Required

### 1. svi_2020_zcta_derived.csv on HiPerGator

**Test:** On HiPerGator, run `ls -la /blue/erin.mobley-hl.bcu/insurance_investigation/data/reference/svi_2020_zcta_derived.csv`
**Expected:** File exists; `head -1` returns "ZCTA,RPL_THEMES,vintage,method,source"
**Why human:** File absent locally; must verify it exists on HiPerGator from the session that produced the PART J SVI 77.5% result. If it does not exist there either, R/117 must be re-run with a valid Census API key.

### 2. neighborhood_atlas_zip9_adi.csv on HiPerGator

**Test:** On HiPerGator, run `ls -la /blue/erin.mobley-hl.bcu/insurance_investigation/data/reference/neighborhood_atlas_zip9_adi.csv`
**Expected:** 478MB file present; R/116 run can find it at the path coded in R/116 line 67
**Why human:** Gitignored 478MB file requires scp transfer; cannot verify remote filesystem from Windows.

---

## Gaps Summary

One gap blocks full goal achievement in a reproducible sense.

**Gap:** `data/reference/svi_2020_zcta_derived.csv` was produced on HiPerGator (evidenced by PART J recording SVI 77.5%) but was never committed to the repo and is not gitignored. Any re-run — by another team member, on a different machine, or after a fresh clone — will have the SVI probe degrade to NA without warning, because the file will simply be absent and `has_svi` will be FALSE.

The fix is one of:
1. Commit the file. CDC data is US government public domain (no redistribution restriction, confirmed in DISCOVERY.md PART A Index 2). The file can and should be committed.
2. If the file is too large, gitignore it and document the scp transfer path and the R/117 re-run procedure in README (similar to the ADI treatment).

The PART J result stands as evidence that the join worked on HiPerGator. The gap is about whether the phase goal — "staged so R/116 can join" — is durably met, or only transiently met for one HiPerGator session. For the DISCOVERY.md PART J to serve as the phase acceptance criterion, the file must either be in the repo or durably staged on HiPerGator.

The R/116 Coverage Ceilings sheet text also still shows "PENDING HiPerGator run" strings for SDI/SVI haircuts (lines 423-424), a minor documentation inconsistency that the next `/gsd:quick` should update with the actual PART J figures.

---

_Verified: 2026-08-17_
_Verifier: Claude (gsd-verifier)_
