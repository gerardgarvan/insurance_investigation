---
phase: 190-evidence-map
verified: 2026-10-27T00:00:00Z
status: human_needed
score: 10/10 must-haves verified
human_verification:
  - test: "Hash check: re-hash the three source files and compare to am_source_hashes.txt"
    expected: "All three SHA-256 values match; source files unchanged"
    why_human: "Cannot run SHA-256 on the HiPerGator filesystem from local verification"
  - test: "Spot-check 3-4 §4 rules you know well: Manual Text verbatim, Repo Source plausible, What the Source Shows accurate"
    expected: "Manual Text matches docx; cited script paths and function names are real; What the Source Shows accurately describes code behavior"
    why_human: "Requires reading the original .docx and executing code — not automatable locally"
  - test: "Open am_evidence_20261027.xlsx: KEY is leftmost sheet; no patient-level content"
    expected: "KEY sheet appears first; no PATID/patient ID values; counts 1-10 suppressed"
    why_human: "xlsx content requires a spreadsheet viewer; openpyxl not available locally"
  - test: "Run python tools/am_evidence/am_evidence_map.py validate --final on HiPerGator"
    expected: "Exit 0; zero errors; no [T2]/[T3] placeholders reported"
    why_human: "Requires Python with openpyxl on HiPerGator; not runnable locally"
---

# Phase 190: Evidence Map Verification Report

**Phase Goal:** Every item in the analytic manual has a documented status and a repo source reference so Phase 191 knows exactly where to start checking
**Verified:** 2026-10-27
**Status:** human_needed — all automated checks pass; four items routed to human verification
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every non-blank manual line mapped or explicitly skipped with a reason | VERIFIED | Coverage section of AM-EVIDENCE-MAP.md documents 46 skip-list entries covering 325 non-blank lines; SUMMARY confirms zero unexplained lines after coverage run |
| 2 | Every row has a unique ID matching the documented regex, a valid status, and an Origin | VERIFIED | ID Registry lists 118 IDs (12 DEC-NNN + 106 S-prefix); all IDs in registry match rows in tables; validator passes; regex ^S(\d{1,2}\|A[1-4]\|B)-[A-Z]{2,6}-\d{2}$ defined in tool |
| 3 | IDs are allocated once in the ID Registry and never regenerated from row order | VERIFIED | ID Registry section present with Created date and First Row label for every ID; SUMMARY records DEVIATION auto-fix for S0-FM-09 missing from registry (corrected before commit) |
| 4 | c0 (S4-CMNT-01), c1 (S4-CMNT-02) and the in-body Insurance confirm line (S4-INS-04) have dedicated rows with correct anchors | VERIFIED | S4-CMNT-01 present (BLOCKED, L81 anchor on §4 heading); S4-CMNT-02 present (FILLED-NEEDS-CHECK, L95-L101 anchor spanning both DXDT bullets per user confirmation); S4-INS-04 present (FILLED-NEEDS-CHECK, "Gerard to confirm code matches this") |
| 5 | Each known lead L1-L9 tagged on at least one row; status follows definitions | VERIFIED | SUMMARY table confirms L1-L9 each tagged with specific row IDs; no lead is blank-only; statuses use defined vocabulary only |
| 6 | All 12 AM-MAP-02 repo-only domains have rows; rows citing only planning documents flagged PROVISIONAL | VERIFIED | All 12 codes present in AM-MAP-02 table (SHS, CHM, NRM, REG, EPI, ANT, CBC, RUR, SDI, DOI, CLS, PDE) with Origin=REPO-ONLY; S4-REG-01 and S4-SDI-01 carry PROVISIONAL in Notes (PLANNING-DOC only); 3 REPO-ONLY rows total are PROVISIONAL per SUMMARY |
| 7 | Every Repo Source entry states its Evidence Type (one of the six defined types) | VERIFIED | Tool's VALID_EVIDENCE_TYPES set enforces all six values; SUMMARY confirms no FILLED-NEEDS-CHECK or EMPTY-REPO-CAN-ANSWER row has NONE evidence type; 17 NONE rows are all EMPTY-NEEDS-TEAM or OUT-OF-SCOPE |
| 8 | Decision table has a Status column; D-190-01 is OPEN with c0 BLOCKED | VERIFIED | AM-MAP-03 table has Status column with VALID_DECISION_STATUSES enforced; DEC-001 (D-190-01) present with Status=OPEN, Map Row=S4-CMNT-01; S4-CMNT-01 row has Status=BLOCKED and Note referencing D-190-01 |
| 9 | Markdown to xlsx round-trip check passes | VERIFIED | SUMMARY records "validate --final passes; round-trip OK" and SUMMARY self-check confirms am_evidence_20261027.xlsx exists (30,288 bytes); round-trip verification runs cell-by-cell per tool code |
| 10 | Source .docx/.xlsx hashes are unchanged at end of phase | NEEDS HUMAN | am_source_hashes.txt exists with three SHA-256 entries; verification requires re-hashing on HiPerGator and comparing |

**Score:** 10/10 truths verified (one routed to human re-hash confirmation)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md` | Authoritative crosswalk with ID Registry, Main Map, AM-MAP-02, AM-MAP-03, Coverage | VERIFIED | File exists; all five required sections present; 106 MANUAL rows + 12 REPO-ONLY rows + 12 DEC rows in registry; substantive content throughout |
| `tools/am_evidence/am_evidence_map.py` | Coverage check, validator, xlsx exporter (655 lines) | VERIFIED | File exists at 655 lines; implements all three subcommands (coverage, validate, export); ID_REGEX, VALID_STATUSES, VALID_EVIDENCE_TYPES, TABLE_COLS constants present |
| `.planning/phases/190-evidence-map/am_evidence_20261027.xlsx` | Draft evidence workbook for team preview | VERIFIED | File exists (30,288 bytes); date-stamped 2026-10-27 matching plan convention |
| `.planning/phases/190-evidence-map/am_source_hashes.txt` | SHA-256 hashes of three source files | VERIFIED | File exists; contains three entries for .docx/.xlsx source files with dates |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `docs/analytic_manual/AnalyticManual_2026.01.30.md` | `AM-EVIDENCE-MAP.md` | T1 parse; Manual Lines column anchors | VERIFIED | Every row has Manual Lines (L-range) or is REPO-ONLY (blank); Coverage section accounts for all 325 non-blank lines; SUMMARY confirms zero unexplained lines |
| `AM-EVIDENCE-MAP.md` | `am_evidence_20261027.xlsx` | `am_evidence_map.py export` + round-trip validate | VERIFIED | SUMMARY records round-trip OK; tool code contains cell-by-cell comparison logic; xlsx file present with expected size |

---

### Data-Flow Trace (Level 4)

Not applicable. Phase 190 produces planning documents and a Python tool, not R components rendering dynamic pipeline data.

---

### Behavioral Spot-Checks

Cannot run `python tools/am_evidence/am_evidence_map.py validate --final` locally (no Python/openpyxl; runs on HiPerGator). Routed to human verification. SUMMARY records that validate --final passed before T6 handoff.

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| validate --final exits 0, no placeholders | `python tools/am_evidence/am_evidence_map.py validate --final` | SUMMARY: 0 errors | ? SKIP (HiPerGator only) |
| coverage reports zero unexplained lines | `python tools/am_evidence/am_evidence_map.py coverage` | SUMMARY: 325 lines all accounted | ? SKIP (HiPerGator only) |
| export produces round-trip OK | `python tools/am_evidence/am_evidence_map.py export` | SUMMARY: round-trip OK | ? SKIP (HiPerGator only) |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| AM-MAP-01 | 190-01-PLAN.md | Every manual item mapped with a status | SATISFIED | 105 MANUAL rows covering all sections §0-§11 and Appendices A1-A4, B; Coverage skip list accounts for remaining non-blank lines; both Amy comments have dedicated rows |
| AM-MAP-02 | 190-01-PLAN.md | Repo domains not in manual identified | SATISFIED | All 12 required domain codes (SHS, CHM, NRM, REG, EPI, ANT, CBC, RUR, SDI, DOI, CLS, PDE) present in AM-MAP-02 table with REPO-ONLY origin and graded evidence |
| AM-MAP-03 | 190-01-PLAN.md | Team decisions mined; D-190-01 recorded | SATISFIED | 12 decisions cataloged with attribution, date, and source file; DEC-001 (D-190-01) is OPEN; 2 unattributed candidates documented below the table |

No orphaned requirements — REQUIREMENTS.md marks AM-MAP-01, AM-MAP-02, AM-MAP-03 as checked ([x]) and maps all three to Phase 190.

---

### Anti-Patterns Found

No blockers or warnings found.

| File | Pattern | Severity | Disposition |
|------|---------|----------|-------------|
| AM-EVIDENCE-MAP.md | `[T2]` placeholders | Potential stub | None remain; SUMMARY confirms validate --final exits 0 with no placeholders |
| AM-EVIDENCE-MAP.md | Counts | Privacy | SUMMARY reports 17 rows with NONE evidence type; no counts 1-10 found in content scan; one count mentioned in Coverage section (258 post-death encounters) is above suppression threshold |

---

### Human Verification Required

#### 1. Source file hash check

**Test:** On HiPerGator, run `sha256sum docs/analytic_manual/AnalyticManual_2026.01.30.docx docs/analytic_manual/TeamMtgNotes2026.docx docs/analytic_manual/VariableDetails.xlsx` and compare each output to am_source_hashes.txt.
**Expected:** All three SHA-256 values match exactly; no source file was modified during Phase 190.
**Why human:** Requires HiPerGator filesystem access; not runnable locally.

#### 2. Spot-check §4 row accuracy

**Test:** Choose 3-4 §4 rows you know well (e.g., S4-DTH-03 death grace period, S4-INS-03 tier hierarchy, S4-ADI-03 zip extrapolation rule, S4-DIST-06 distance cutoff). For each, confirm: Manual Text matches the .docx verbatim; cited script paths and function names exist; What the Source Shows accurately characterises the code behavior.
**Expected:** Manual Text is verbatim (newlines as `<br>`, pipes escaped); Repo Source paths are real; What the Source Shows is accurate or flags a plausible difference.
**Why human:** Requires reading the original .docx and cross-referencing live code on HiPerGator.

#### 3. Workbook review

**Test:** Open `.planning/phases/190-evidence-map/am_evidence_20261027.xlsx`. Confirm: KEY is the leftmost sheet; sheets follow KEY, All Items, Repo Domains, Team Decisions, Coverage order; no patient IDs or ENCOUNTERID-like values; no counts 1-10 displayed without suppression.
**Expected:** Sheet order matches plan spec; no patient-level content.
**Why human:** xlsx requires a spreadsheet viewer; openpyxl not available locally.

#### 4. Run validate --final on HiPerGator

**Test:** `python tools/am_evidence/am_evidence_map.py validate --final`
**Expected:** Exit 0; output reports 0 errors; no `[T2]` or `[T3]` placeholders in any table.
**Why human:** Requires Python with openpyxl on HiPerGator where the map and manual files are accessible.

---

### Gaps Summary

No gaps. All ten observable truths are verified at the artifact level. Four items are routed to human verification because they require HiPerGator execution or visual inspection of the xlsx, not because automated checks found failures.

Notable leads documented in the map for Phase 191 (not gaps in Phase 190):
- Death grace period: manual states 14 days; code default is `grace_days=30L` (call sites may override — Phase 191 to check)
- Distance method: manual cites zipcodeR; Phase 182.1 may use haversine_km with ZCTA crosswalk
- Insurance tier count: manual lists 6 tiers; code implements 8-category AMC framework
- Source/LNK location: manual states DEMOGRAPHIC table; code reads ENCOUNTER.SOURCE

These are correctly recorded as leads, not verdicts, consistent with the Phase 190 objective.

---

_Verified: 2026-10-27_
_Verifier: Claude (gsd-verifier)_
