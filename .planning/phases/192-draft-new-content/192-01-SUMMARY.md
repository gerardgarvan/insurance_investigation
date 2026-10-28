---
phase: 192-draft-new-content
plan: "01"
subsystem: am-evidence-tools
tags: [draft-check, validation, pytest, am-evidence-map]
dependency_graph:
  requires:
    - .planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md
    - .planning/phases/191-verify-existing-entries/AM-VERDICTS.md
    - .planning/phases/190-evidence-map/am_source_hashes.txt
  provides:
    - tools/am_evidence/am_evidence_map.py draft-check subcommand
    - tools/am_evidence/tests/test_draft_check.py
    - tools/am_evidence/tests/fixtures/
  affects:
    - Plans 02 and 03 (must write drafts that pass draft-check)
tech_stack:
  added: []
  patterns:
    - TDD RED-GREEN for check_draft()
    - Fixture-injected paths (map_path, manual_path, etc.) for test isolation
key_files:
  created:
    - tools/am_evidence/__init__.py
    - tools/am_evidence/tests/__init__.py
    - tools/am_evidence/tests/test_draft_check.py
    - tools/am_evidence/tests/fixtures/mini_map.md
    - tools/am_evidence/tests/fixtures/mini_verdicts.md
    - tools/am_evidence/tests/fixtures/mini_manual.md
    - tools/am_evidence/tests/fixtures/mini_hashes.txt
    - tools/am_evidence/tests/fixtures/draft_valid.md
    - tools/am_evidence/tests/fixtures/draft_fail_missing_section.md
    - tools/am_evidence/tests/fixtures/draft_fail_missing_repo_domain.md
    - tools/am_evidence/tests/fixtures/draft_fail_no_status.md
    - tools/am_evidence/tests/fixtures/draft_fail_unknown_id.md
    - tools/am_evidence/tests/fixtures/draft_fail_drafted_no_cite.md
    - tools/am_evidence/tests/fixtures/draft_fail_open_missing_s8.md
    - tools/am_evidence/tests/fixtures/draft_fail_confirmed_in_s8.md
  modified:
    - tools/am_evidence/am_evidence_map.py
decisions:
  - "check_draft() accepts injected paths so tests run on fixtures without live repo inputs"
  - "CORRECTION block inner while-loop breaks on BEGIN/END REPO-ONLY markers to avoid swallowing them"
  - "§8 Map ID column (index 3) parsed separately to contribute to EMPTY-REPO-CAN-ANSWER inventory"
  - "Anchor check uses the passed-in manual_path directly, not a repo-relative path from the cite string"
metrics:
  duration_minutes: 11
  completed_date: "2026-10-28"
  tasks_completed: 3
  files_changed: 18
---

# Phase 192 Plan 01: draft-check Subcommand and Grammar Summary

Added `draft-check` to `tools/am_evidence/am_evidence_map.py`: a unit-level validator with run-time inputs, a documented grammar (in 192-01-PLAN.md), and a pytest suite proving each rule.

## Task 0 Findings

### Tool structure (am_evidence_map.py)
- Existing subcommands: `coverage`, `validate`, `export`, `verdicts-export`
- Reusable helpers: `_parse_map()`, `_parse_verdicts()`, `_count_lint_check()`, `_safe_cell()`
- New additions: `_parse_draft()`, `check_draft()`, `cmd_draft_check()`
- No existing functions modified; `draft-check` wired into `main()` argparse

### Hash file format (am_source_hashes.txt)
```
# Source file hashes for Phase 190 evidence map
# Generated: 2026-10-27
SHA-256  <64-hex-chars>  <repo-relative-path>
```
Three entries: `docs/analytic_manual/AnalyticManual_2026.01.30.docx`, `TeamMtgNotes2026.docx`, `VariableDetails.xlsx`.

### Manual section headings in scope (verbatim from manual)
```
## 1. Data Ingest & Change Log
## 3. Variable and Phenotype Decision Log
## 4. Data Cleaning and Harmonization Rules
## 8. Open Questions and Decision Parking Lot
## APPENDIX A. Embedded Working Tables (subsections A1 and A3)
```

### AM-MAP-03 OPEN/CONFIRMED marking
Status column in AM-MAP-03 table; values: `OPEN`, `CONFIRMED`, `SUPERSEDED`. The `_parse_map()` helper already parses this via `team_decisions[*]["status"]`.

### AM-MAP-02 repo-only domain IDs
12 domains from the `repo_domains` table; domain code extracted from ID pattern `S4-<CODE>-NN`. At plan time: SHS, CHM, NRM, REG, EPI, ANT, CBC, RUR, SDI, DOI, CLS, PDE (from mini fixture: CBC, SHS).

### EMPTY-REPO-CAN-ANSWER inventory
Collected from `main_map + repo_domains` where `status == "EMPTY-REPO-CAN-ANSWER"`. These IDs must appear as a unit ID tag or in `## Not drafted` in the draft.

---

## Grammar Summary (authoritative for Plans 02 and 03)

**Header:** `# AM-DRAFT` + `<!-- commit: <sha> -->` within the first 10 lines.

**Required section headings (verbatim):**
- `## 1. Data Ingest & Change Log`
- `## 3. Variable and Phenotype Decision Log`
- `## 4. Data Cleaning and Harmonization Rules`
- `## 8. Open Questions and Decision Parking Lot`

**Repo-only domain block:** exactly one `<!-- BEGIN REPO-ONLY DOMAINS -->` and one `<!-- END REPO-ONLY DOMAINS -->` inside §4; one `### <Name> {#S4-<CODE>}` block per code in AM-MAP-02, each with four `####` fields, inside the markers.

**Bullet unit:**
```
- [MAP-ID] Statement text.
  STATUS: DRAFTED
  CITE: R/utils/utils_foo.R:function_name():L20-L58
```
`STATUS:` and `CITE:` indented two spaces. DRAFTED/CORRECTION require at least one CITE.

**Table unit:** trailing columns `Map ID | Status | Cite` (removed in Phase 193). Status on the row; Cite as last column value (semicolon-separated).

**Correction directive:**
```
#### CORRECTION <map ID>
- Target: <section> / <map ID>
- Anchor: "<exact text>" (<file>:L<n>)
- Action: REPLACE | INSERT-AFTER | MARK-SUPERSEDED
- Replacement: <text>
- Provenance: <decision IDs>
  STATUS: CORRECTION
  CITE: <citation>
```

**Citation forms:**
| Form | Pattern example |
|------|----------------|
| code/config | `R/utils/utils_cbc.R:build_cbc_events():L20-L58` |
| workbook | `am_verification_20261027.xlsx:S4_DIST` |
| decision | `DEC-008` or `D-191-06` |
| planning doc | `.planning/phases/190-evidence-map/190-01-SUMMARY.md` |
| manual | `docs/analytic_manual/AnalyticManual_2026.01.30.md:L81-L88` |

**§8 table:** `Item | Notes | Date added` (manual columns) + `Map ID | Status | Cite` (draft columns).
- Notes begins with `MISMATCH; ` or `OPEN-DEPENDENCY; ` followed by IDs.
- MISMATCH Item: `"Manual: …. Code: …. Which should the manual record?"`
- Every OPEN D-191 row and DEC-001 (D-190-01) must have exactly one §8 row.
- CONFIRMED D-191 rows must NOT appear in §8; they go in CORRECTION directives.

**Mirrors:** A1 rows equal §1 rows and A3 rows equal §3 rows after whitespace normalization and stripping Map ID prefix differences.

**Stages:**
- `--stage core`: defers repo-only domain block check (`{#S4-*}` blocks inside markers) and §4 EMPTY-REPO-CAN-ANSWER inventory check.
- `--stage full` (default): all checks run.

---

## Rule List with Test Names

| Rule | Test class | Fixture |
|------|-----------|---------|
| Valid draft passes full stage | TestValidDraft::test_full_stage_passes | draft_valid.md |
| Valid draft passes core stage | TestValidDraft::test_core_stage_passes | draft_valid.md |
| Missing section heading | TestMissingSection | draft_fail_missing_section.md |
| Missing repo-only domain block [full] | TestMissingRepoDomain | draft_fail_missing_repo_domain.md |
| Bullet unit has no STATUS | TestUnitNoStatus | draft_fail_no_status.md |
| Map ID tag not in registry | TestUnknownMapId | draft_fail_unknown_id.md |
| DRAFTED unit has no CITE | TestDraftedNoCite | draft_fail_drafted_no_cite.md |
| OPEN D-191 missing from §8 | TestOpenMissingFromS8 | draft_fail_open_missing_s8.md |
| CORRECTION directive with OPEN item | TestConfirmedInS8 | draft_fail_confirmed_in_s8.md |
| All failures collected, not abort-on-first | TestCollectAllFailures | draft_fail_no_status.md |
| core stage skips repo-only domain check | TestStageCore::test_core_does_not_fail_on_missing_repo_domain | draft_fail_missing_repo_domain.md |
| core stage still enforces section headings | TestStageCore::test_core_still_fails_on_missing_section | draft_fail_missing_section.md |
| _parse_map() still works | TestExistingSubcommandsUnchanged::test_parse_map_still_works | mini_map.md |
| _parse_verdicts() still works | TestExistingSubcommandsUnchanged::test_parse_verdicts_still_works | mini_verdicts.md |
| check_draft() function exists | TestExistingSubcommandsUnchanged::test_check_draft_function_exists | — |

---

## Helpers Shared with Existing Subcommands

| Helper | Reused from | Used by draft-check for |
|--------|-------------|------------------------|
| `_parse_map()` | validate, export, verdicts-export | Map ID registry, repo-only domains, OPEN/CONFIRMED decisions |
| `_parse_verdicts()` | verdicts-export | OPEN/CONFIRMED decision set (verdicts_data optional) |
| `_count_lint_check()` | verdicts-export | Count-lint scan of draft text |

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] CORRECTION block consumed BEGIN-REPO-ONLY markers**
- **Found during:** Task 2 GREEN
- **Issue:** The CORRECTION directive inner parser had `elif dl.startswith("<!--"): pass`, which consumed the `<!-- BEGIN REPO-ONLY DOMAINS -->` marker without registering it in the outer loop. Result: `marker_begin_count` was 0 even when the marker was present.
- **Fix:** Added explicit guard: `elif dl.startswith("<!-- BEGIN REPO-ONLY") or dl.startswith("<!-- END REPO-ONLY"): break` to let the outer loop handle these markers.
- **Files modified:** `tools/am_evidence/am_evidence_map.py`

**2. [Rule 1 - Bug] Not-drafted regex missed SA1/SA3 IDs**
- **Found during:** Task 2 GREEN
- **Issue:** `re.findall(r"\b(S\d{1,2}-[A-Z]{2,6}-\d{2})\b", stripped)` did not match `SA1-LOG-01` or `SA3-DEC-01` (Appendix IDs starting with `SA`).
- **Fix:** Changed pattern to `r"\b(S[AB]?\d{1,2}-[A-Z]{2,6}-\d{2})\b"`.
- **Files modified:** `tools/am_evidence/am_evidence_map.py`

**3. [Rule 1 - Bug] §8 Map ID column not included in EMPTY-REPO-CAN-ANSWER inventory**
- **Found during:** Task 2 GREEN
- **Issue:** `S8-PRK-01` (EMPTY-REPO-CAN-ANSWER) appeared only in §8 table's Map ID column; the inventory check missed it.
- **Fix:** Added `row_map_ids` extraction from §8 row cells[3] and merged into `all_unit_ids`.
- **Files modified:** `tools/am_evidence/am_evidence_map.py`

**4. [Rule 1 - Bug] CORRECTION anchor check used repo-relative file path rather than manual_path**
- **Found during:** Task 2 GREEN
- **Issue:** Anchor validation was resolving the cite file path relative to repo root, but correction directives in the fixture used a short filename (`mini_manual.md:L19`). The check should verify the anchor against `manual_path` directly, since all corrections target the analytic manual.
- **Fix:** Simplified anchor check to use `manual_lines` (from `manual_path`) without re-resolving a file from the cite string.
- **Files modified:** `tools/am_evidence/am_evidence_map.py`

---

## Known Stubs

None. `check_draft()` is fully implemented for the grammar specified in 192-CONTEXT D-26. Plans 02 and 03 will write AM-DRAFT.md against this grammar.

## Self-Check: PASSED

All listed files found. Both commits (7253b7b, 022681a) confirmed in git log. pytest 21/21 pass. `validate` exits 0 on real map. `draft-check` exits 1 with FAIL message when draft is absent.
