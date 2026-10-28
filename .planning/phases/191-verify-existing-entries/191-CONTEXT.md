# Phase 191: Verify Existing Entries - Context

**Gathered:** 2026-10-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Issue a verdict for every `FILLED-NEEDS-CHECK` and `BLOCKED` item from the Phase 190 evidence map; answer leads L1–L9; answer Amy's comments c0 and c1 and the Insurance "Gerard to confirm" item; log each mismatch as a D-191-NN decision row in AM-EVIDENCE-MAP.md. No manual text and no code changed in this phase.

</domain>

<decisions>
## Implementation Decisions

### Script scope: what the R script does and does not do

- **D-01:** The R script (`R/NNN_am_verification.R`) is a **query runner only**. It executes HiPerGator/DuckDB queries for checks V1\_SOURCE (L1), V2\_INSURANCE (L2), V3\_DXDATE (L3), V4\_DXSCOPE (L4), V5\_ZIPCOVER (the ZIP9/ZIP5 coverage side of L5), and V6\_DEATH (L6). It writes query results to `am_verification_<date>.xlsx` sheets. It does not write verdicts.
- **D-02:** All verdicts — including L5 method, L7 (Distance), L8 (Treatment window), L9 (Survivorship), c0, c1, S4-INS-04 ("Gerard to confirm"), and every other FILLED-NEEDS-CHECK row — are written in **`AM-VERDICTS.md`** in the phase folder. Format per row: map ID, verdict, evidence type, citation (`script:function:line` or workbook sheet), plain-English description of what the code does.
- **D-03:** Query-backed verdicts cite their workbook sheet as the evidence source (e.g., `am_verification_20261027.xlsx:V2_INSURANCE`). Code-reading verdicts cite the script path, function name, and line range directly.
- **D-04:** No verdicts are hard-coded in the R script. Nothing is hand-typed into Excel.

### Verification workbook structure (`am_verification_<date>.xlsx`)

- **D-05:** Sheet names match check IDs used in AM-VERDICTS.md citations: `V1_SOURCE`, `V2_INSURANCE`, `V3_DXDATE`, `V4_DXSCOPE`, `V5_ZIPCOVER`, `V6_DEATH`. Add a `V2b_...` sheet only if a lead genuinely requires a second query.
- **D-06:** Sheet order: KEY (leftmost), V-sheets in sequence, QC, Gaps.
- **D-07:** Each V-sheet begins with a header block: check ID, lead number, map ID(s) covered, query purpose, run date.
- **D-08:** No sheets for code-reading-only leads (L5 method, L7, L8, L9). Counts 1–10 suppressed everywhere. Any ID-level detail goes to `output/internal/` as RDS, never into the workbook.
- **D-09:** A **Gaps sheet** lists items that could not be verified: c0 (BLOCKED — OneFLquestions document not received), L8 (parked pending Sharon), and any other `CANNOT-VERIFY` items.

### Verdict values

- **D-10:** Valid verdict values for AM-VERDICTS.md and the workbook: `MATCH`, `MISMATCH`, `PARTIAL`, `CANNOT-VERIFY`, `BLOCKED`.
- **D-11:** `verdicts-export` (new subcommand in `tools/am_evidence/am_evidence_map.py`) requires **exactly one verdict row** for every `FILLED-NEEDS-CHECK` and `BLOCKED` map ID from AM-EVIDENCE-MAP.md. It fails with a clear error listing any missing IDs. It does not require verdict rows for `EMPTY-*` or `OUT-OF-SCOPE` rows.

### D-191-NN decision rows (mismatches)

- **D-12:** Each `MISMATCH` verdict in AM-VERDICTS.md carries a `Decision ID` column with its `D-191-NN` assignment.
- **D-13:** D-191-NN rows are added to the **AM-MAP-03 Team Decisions table in AM-EVIDENCE-MAP.md** using the same columns and statuses as existing rows (D-190-01 etc.): Status = OPEN, Raised By = "Phase 191 verification", Map Row(s) linked.
- **D-14:** Every new D-191-NN ID is registered in the AM-EVIDENCE-MAP.md ID Registry.
- **D-15:** `verdicts-export` checks that every `MISMATCH` row in AM-VERDICTS.md has a D-191-NN and that the ID exists in the AM-MAP-03 decisions table.
- **D-16:** STATE.md gets a one-line pointer only: "D-191-01..NN open — see AM-EVIDENCE-MAP.md AM-MAP-03." The existing D-190-01, D-190-02, D-193-01 rows in STATE.md are not moved.

### c0 (BLOCKED — OneFLquestions not received)

- **D-17:** c0 (map ID `S4-CMNT-01`) gets a verdict row in AM-VERDICTS.md with verdict = `BLOCKED`, citing "OneFLquestions document not received (D-190-01 OPEN)".
- **D-18:** c0 is also listed on the Gaps sheet of the verdict workbook.
- **D-19:** This counts as answering AM-VER-02 for c0: the answer is "BLOCKED — recorded."

### Claude's Discretion

- Script number assignment (NNN in `R/NNN_am_verification.R`) — Claude picks the next free number in SCRIPT_INDEX.md.
- Exact column order within AM-VERDICTS.md rows — Claude decides, as long as map ID, verdict, evidence type, citation, and description are all present.
- Whether to use a Python script or manual entry to write D-191-NN rows into AM-EVIDENCE-MAP.md — Claude picks the approach with fewer error-prone steps.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 190 artifacts (primary inputs)
- `.planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md` — authoritative item list; all FILLED-NEEDS-CHECK and BLOCKED map IDs; stable ID registry; AM-MAP-03 decisions table to be extended with D-191-NN
- `.planning/phases/190-evidence-map/am_evidence_20261027.xlsx` — draft evidence workbook (read-only in Phase 191)
- `.planning/phases/190-evidence-map/190-CONTEXT.md` — ID scheme, D-190-01 interim handling, column names and formats

### Requirements and roadmap
- `.planning/REQUIREMENTS.md` — AM-VER-01, AM-VER-02, AM-VER-03, AM-VER-04 acceptance criteria
- `.planning/ROADMAP.md` §Phase 191 — success criteria (all four must be TRUE)
- `.planning/STATE.md` — leads L1–L9 table; open decisions table

### Tool to extend
- `tools/am_evidence/am_evidence_map.py` — add `verdicts-export` subcommand here; existing subcommands: `coverage`, `validate`, `export`

### Manual source files
- `docs/analytic_manual/AnalyticManual_2026.01.30.md` — readable extraction; c0/c1 anchor text
- `docs/analytic_manual/VariableDetails.xlsx` Surveillance Strategy sheet — L9 evidence

### Output privacy rules
- `CLAUDE.md` §Outputs and privacy — counts 1–10 as `"<11"`, no patient IDs in workbooks

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tools/am_evidence/am_evidence_map.py` — existing tool with `coverage`, `validate`, `export`; `verdicts-export` is added here as a new subcommand
- `R/utils/utils_duckdb.R` — `open_pcornet_con()` / `close_pcornet_con()` / `duck_query()` — use these for all DuckDB queries; never hold connection across helpers
- `R/SCRIPT_INDEX.md` — verification script must be listed here (AM-VER-04 / AM-TEAM-03)

### Established Patterns
- Workbooks: KEY sheet leftmost, UF colours `#0021A5` / `#FA4616`, counts 1–10 as `"<11"`, no patient IDs — verdict workbook follows same pattern
- Decision IDs: `D-NNN-NN` format, registered in ID Registry — D-191-NN rows follow same pattern
- No verdicts typed into Excel; no results hard-coded in R — separation enforced by `verdicts-export` completeness check

### Integration Points
- `AM-VERDICTS.md` (new in Phase 191) → consumed by `verdicts-export` → `am_verification_<date>.xlsx`
- D-191-NN rows appended to AM-MAP-03 in AM-EVIDENCE-MAP.md → consumed by Phase 192 for §8 parking lot
- `am_verification_<date>.xlsx` → cited by Phase 192 when drafting verified sections

</code_context>

<specifics>
## Specific Ideas

- **AM-VERDICTS.md** is a new file in `.planning/phases/191-verify-existing-entries/`. It is the single source of truth for all verdicts. Its rows drive the workbook via `verdicts-export`; it is not a draft — it is the authoritative document.
- **`verdicts-export` failure behaviour:** lists every FILLED-NEEDS-CHECK/BLOCKED map ID that lacks a verdict row, and every MISMATCH row that lacks a D-191-NN. Exits non-zero so the user knows the workbook is incomplete.
- **L5 split:** V5\_ZIPCOVER sheet covers the ZIP9/ZIP5 coverage query. The L5 method verdict (whether the ADI imputation method in the manual matches the code) is a code-reading item and goes in AM-VERDICTS.md only — no V-sheet for it.
- **c1 and S4-INS-04:** both are code-reading items. c1 cites `get_hl_any_dx_ids()` in `R/utils/utils_treatment.R` and Phase 133. S4-INS-04 cites the payer hierarchy in `R/00_config.R` and Phase 35–37.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 191-verify-existing-entries*
*Context gathered: 2026-10-27*
