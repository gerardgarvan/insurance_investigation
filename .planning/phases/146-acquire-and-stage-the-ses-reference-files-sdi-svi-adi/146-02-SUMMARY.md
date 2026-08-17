---
plan: 146-02
phase: 146-acquire-and-stage-the-ses-reference-files-sdi-svi-adi
status: complete
completed: 2026-08-17
self_check: PASSED
---

## What Was Built

Resolved all three human-gated decisions that gate Wave 3+ staging, and documented
all outcomes in `146-DISCOVERY.md` Part H.

## Decisions Recorded

**D-02 (SVI method) — RESOLVED: D-02a-i (findSVI)**
- findSVI CRAN package computes ZCTA SVI directly from 2020 ACS; no tract-to-ZCTA aggregation
- Output contract: ZCTA + RPL_THEMES + vintage/method/source; NO svi_areal_coverage column
- ZCTA-vs-tract percentile caveat recorded (must appear in method column and README)
- Census API key: pending registration at api.census.gov (owner: Gerard)

**ADI registration — BLOCKED (owner: Gerard, 2026-08-17)**
- Registration at neighborhoodatlas.medicine.wisc.edu not yet completed
- Full checklist at `PHASE_146_REGISTRATION_CHECKLIST.txt` (repo root)
- ADI staging deferred until registration complete and ZIP9 column confirmed

**Per-index commit-to-repo verdicts — CONFIRMED (user 2026-08-17)**
- SDI: YES
- SVI (derived): YES (CDC public domain)
- ADI: YES (pending terms review after registration; revert to .gitignore + scp if restricted)

## Commits

- Task 1 (D-02 decision): `53a86a8`
- Task 2 (ADI/commit verdicts): see git log

## Key Files Modified

- `.planning/phases/146-.../146-DISCOVERY.md` — Part H decisions appended
- `PHASE_146_REGISTRATION_CHECKLIST.txt` — created in repo root

## Deferred Items (blocking Wave 3+)

| Item | Owner | Blocking |
|------|-------|---------|
| Census API key registration | Gerard | Wave 4 (146-04 SVI build) |
| ADI portal registration + download | Gerard | Wave 4 (146-04, ADI path) |
| SDI download (URL + columns + vintage) | Gerard | Wave 3 (146-03) |

Wave 3 (SDI staging) can proceed once Gerard downloads the SDI file from
graham-center.org and reports raw column names. See checklist Step 2.
