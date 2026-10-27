---
phase: 190-evidence-map
plan: 01
subsystem: analytic-manual
tags: [evidence-map, crosswalk, leads, decisions, phase191-input]
dependency_graph:
  requires: []
  provides:
    - AM-EVIDENCE-MAP.md (authoritative crosswalk consumed by Phase 191)
    - tools/am_evidence/am_evidence_map.py (reused in Phase 193)
    - am_evidence_20261027.xlsx (draft workbook for team preview)
  affects:
    - Phase 191 (verify existing entries)
    - Phase 192 (draft new content)
    - Phase 193 (produce updated manual)
tech_stack:
  added: [openpyxl (Python)]
  patterns: [evidence-map crosswalk, AM domain taxonomy, ID Registry pattern]
key_files:
  created:
    - .planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md
    - .planning/phases/190-evidence-map/am_source_hashes.txt
    - .planning/phases/190-evidence-map/am_evidence_20261027.xlsx
    - tools/am_evidence/am_evidence_map.py
  modified: []
decisions:
  - T0: Both Word comments extracted from XML; c1 anchor confirmed to span BOTH TR-default and HL-code-fallback bullets
  - T1: ID Registry pattern adopted; DEC-NNN IDs separate from row IDs; S0-FM-09 added after registry-table mismatch fix
  - T5: validate --final passes; round-trip OK; openpyxl export with formula-injection guard
metrics:
  duration_minutes: 90
  completed_date: 2026-10-27
  completed_tasks: 6
  total_tasks: 7
  files_created: 4
---

# Phase 190 Plan 01: Evidence Map Summary

Section-by-section crosswalk from the Analytic Manual (`AnalyticManual_2026.01.30.md`) to repo evidence. Each item has a stable ID, a status, and a graded evidence lead. The map also catalogs 12 repo-only domains and 12 team decisions.

## Row counts by Status

| Status | MANUAL rows | REPO-ONLY rows | Total |
|--------|-------------|----------------|-------|
| FILLED-NEEDS-CHECK | 26 | 0 | 26 |
| EMPTY-REPO-CAN-ANSWER | 15 | 12 | 27 |
| EMPTY-NEEDS-TEAM | 17 | 0 | 17 |
| OUT-OF-SCOPE | 46 | 0 | 46 |
| BLOCKED | 1 | 0 | 1 |
| RETIRED | 0 | 0 | 0 |
| **Total** | **105** | **12** | **117** |

(Note: S0-FM-09 added after initial count; validator confirms 118 rows including S0-FM-09.)

## PROVISIONAL rows

9 MANUAL rows and 3 REPO-ONLY rows carry PROVISIONAL in Notes (Evidence Type = PLANNING-DOC only). These require Phase 191/192 code or config citations before relying on them.

## Evidence Type NONE rows

17 rows with Evidence Type NONE — all EMPTY-NEEDS-TEAM or OUT-OF-SCOPE. No FILLED-NEEDS-CHECK or EMPTY-REPO-CAN-ANSWER row has NONE.

## Leads L1–L9: rows and status

| Lead | Domain | Key Row(s) | Status Summary |
|------|--------|------------|----------------|
| L1 | Source/LNK | S4-SRC-02, S4-SRC-03, S4-SHS-01 | FILLED-NEEDS-CHECK: LNK-in-DEMOGRAPHIC vs ENCOUNTER.SOURCE discrepancy is a Phase 191 lead |
| L2 | Insurance | S4-INS-03, S4-INS-04 | FILLED-NEEDS-CHECK: manual lists 6 tiers; code implements 8-category AMC framework; Tricare placement matches |
| L3 | Cancer Diagnosis Date | S4-DXDT-03, S4-CMNT-02 | FILLED-NEEDS-CHECK: c1 anchor covers both TR-default and HL-code-fallback bullets |
| L4 | Cancer Diagnosis | S4-DX-03, S4-CLS-01 | FILLED-NEEDS-CHECK: 7-day two-encounter rule; code scope (all cancers vs HL) to verify |
| L5 | ADI | S4-ADI-01 through S4-ADI-05 | FILLED-NEEDS-CHECK: all three cleaning rules have code citations; pop-weighted average confirmed |
| L6 | Death | S4-DTH-03, S4-DTH-04, S4-PDE-01 | FILLED-NEEDS-CHECK: 14-day vs 30-day grace period mismatch is the key Phase 191 lead |
| L7 | Distance | S4-DIST-03, S4-DIST-06 | FILLED-NEEDS-CHECK: method (zipcodeR vs haversine) and cutoff (manual uncertain; code=100mi) both differ |
| L8 | Treatment window / relapse | S4-TRT-01 to S4-TRT-04, S4-REL-01 to S4-REL-04, S4-EPI-01 | Mix of EMPTY-NEEDS-TEAM (pending Sharon) and EMPTY-REPO-CAN-ANSWER (episode windows in code) |
| L9 | Survivorship | S4-SRV-01 to S4-SRV-05 | Mix: EMPTY-REPO-CAN-ANSWER (codeset in repo), EMPTY-NEEDS-TEAM (VariableDetails, treatment window) |

## Decision counts by status

| Status | Count |
|--------|-------|
| OPEN | 1 (DEC-001 / D-190-01) |
| CONFIRMED | 11 |
| SUPERSEDED | 0 |
| **Total decisions** | **12** |
| Unattributed candidates | 2 |

D-190-01 (location of OneFLquestions document) is OPEN. S4-CMNT-01 is BLOCKED pending that document.

## Comment extraction result (XML vs .md)

Both comments extracted from `word/comments.xml`:

- c0 (S4-CMNT-01): author=Crisp, Amy; date=2026-10-23T13:35:00Z; text="Reference OneFLquestions document to ensure everything has made it into here."; anchor="Data Cleaning and Harmonization Rules" (§4 heading, L81). The pandoc `.md` renders the anchor inline.
- c1 (S4-CMNT-02): author=Crisp, Amy; date=2026-10-23T13:31:00Z; text="Gerard to confirm this is what's in the code."; anchor spans BOTH "Use diagnosis date from Tumor Registry as default." AND "If no diagnosis date: use first date with HL diagnosis code" (L95-L101). User confirmed this is the correct full anchor.

The `.md` extraction contains the comment spans inline; the XML is authoritative for anchor boundaries.

## Coverage

- 325 non-blank manual lines; all accounted for.
- Coverage skip list: 46 entries covering table separator rows, blank placeholder bullets, section headings represented by their section rows, and Appendix A/B guidance boilerplate.
- Comment anchors documented in Coverage section of the map.

## Visible manual-vs-repo differences (leads for Phase 191, not verdicts)

1. **Death grace period (L6 / S4-DTH-03):** Manual says 14 days prior; `utils_death.R: resolve_death_date()` default is `grace_days = 30L`. The parameter is configurable so 14 may be the value actually used at call sites — Phase 191 must check call sites.
2. **Distance method (L7 / S4-DIST-03):** Manual cites `zipcodeR` package; Phase 182.1 may have shifted to `haversine_km()` with ZCTA crosswalk. Phase 191 to confirm which function is in active use.
3. **Distance cutoff (L7 / S4-DIST-06):** Manual is uncertain (120 vs 200 mi); team decided 100 miles (10/13/2026 meeting, doi.org/10.1182/blood-2023-182477). Manual needs updating in Phase 192.
4. **Insurance tier count (L2 / S4-INS-03):** Manual lists 6 tiers; code implements 8-category AMC framework (includes "Other govt"). Manual's rule 3 explicitly includes Tricare in Private; code config does the same. Tier labeling difference to clarify in Phase 191.
5. **Source/LNK location (L1 / S4-SRC-02):** Manual states LNK is only in DEMOGRAPHIC table; code reads SOURCE from ENCOUNTER. Whether this is the same field or a different one requires Phase 191 verification.
6. **CHM detection (S4-CHM-01 REPO-ONLY):** Phase 122 found MED_ADMIN/DISPENSING RxNorm_CUI mismatch adding 1,139 patients. This bug fix is not reflected in the manual.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 2 - Missing functionality] Decision IDs not tracked in `all_ids_in_tables`**
- Found during: T1 validate run
- Issue: Parser only tracked main_map and repo_domains IDs; DEC-NNN IDs in AM-MAP-03 were in the registry but not in `all_ids_in_tables`, causing 12 false "registry but not in table" errors.
- Fix: Added `result["all_ids_in_tables"].add(cells[0])` to the team_decisions parser block.
- Files modified: tools/am_evidence/am_evidence_map.py
- Commit: 82d207b → d41aad7 (fixed inline during T1 commit)

**2. [Rule 1 - Bug] S0-FM-09 missing from ID Registry**
- Found during: T1 validate run
- Issue: Main table had S0-FM-09 (Team roles row) but the ID Registry was missing it; registry had S0-FM-07/S0-FM-08 labels misaligned with table.
- Fix: Corrected registry to add S0-FM-09 and realign FM-07/FM-08 labels to match table IDs.
- Files modified: AM-EVIDENCE-MAP.md
- Commit: 82d207b (fixed before commit)

**3. [Rule 1 - Bug] Two section headings (L3, L40) uncovered in initial coverage run**
- Found during: T1 coverage check
- Issue: `## 0. Front Matter` (L3) and `## 2. Cohort Construction History` (L40) were non-blank lines not covered by any row's Manual Lines or skip list.
- Fix: Added both to the Coverage skip list with reason "Section heading already represented by section rows."
- Files modified: AM-EVIDENCE-MAP.md
- Commit: 82d207b (fixed before commit)

### Plan text superseded

Plan text for S4-CMNT-02 stated the c1 anchor was "anchored on 'If no diagnosis date: use first date with HL diagnosis code'" — a pre-pandoc assumption. User confirmed from pandoc output that c1 spans BOTH bullets. The map and this summary reflect the corrected anchor.

## Known Stubs

None. All rows have substantive evidence citations or explicit EMPTY-NEEDS-TEAM/OUT-OF-SCOPE status with documented reasons. No placeholder text remains (validate --final: 0 errors).

## Self-Check

Files verified:
- `.planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md` — exists
- `.planning/phases/190-evidence-map/am_source_hashes.txt` — exists
- `.planning/phases/190-evidence-map/am_evidence_20261027.xlsx` — exists
- `tools/am_evidence/am_evidence_map.py` — exists

Commits verified:
- 09095c7 — T0 hashes
- 82d207b — T1+T2 map + tool
- d41aad7 — T3+T4+T5 xlsx

## Self-Check: PASSED
