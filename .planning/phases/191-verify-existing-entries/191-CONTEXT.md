# Phase 191: Verify Existing Entries - Context

**Gathered:** 2026-10-27
**Revised:** 2026-10-27 (two-workbook split, independent re-derivation, per-check specs, c1 scope, lead summary, PARTIAL and already-decided mismatches, Gaps derivation, run steps)
**Status:** Ready for planning

<domain>
## Phase Boundary

Issue a verdict for every `FILLED-NEEDS-CHECK` and `BLOCKED` item from the Phase 190 evidence map; give an overall answer for each lead L1–L9; answer Amy's comments c0 and c1 and the Insurance "Gerard to confirm" item; log each mismatch as a D-191-NN decision row in AM-EVIDENCE-MAP.md. No manual text and no pipeline code changed in this phase. The only new code is the read-only verification script and the `verdicts-export` subcommand.

</domain>

<decisions>
## Implementation Decisions

### Script scope: what the R script does and does not do

- **D-01:** The R script (`R/NNN_am_verification.R`) is a **query runner only**. It runs read-only DuckDB queries on HiPerGator for checks V1_SOURCE (L1), V2_INSURANCE (L2), V3_DXDATE (L3, c1), V4_DXSCOPE (L4), V5_ZIPCOVER (data side of L5) and V6_DEATH (L6), and writes results to `am_verification_<YYYYMMDD>.xlsx`. It does not write verdicts.
- **D-01a — Independent re-derivation:** where a check compares the manual's rule with the pipeline, the script implements the **manual's rule directly from the CDM tables** (not by calling the pipeline function under test) and compares that result with the pipeline's own output. Calling the pipeline function to check itself is circular and does not count as verification.
- **D-02:** All verdicts — including L5 method, L7 (Distance), L8 (Treatment window), L9 (Survivorship), c0, c1, the Insurance "Gerard to confirm" row, and every other FILLED-NEEDS-CHECK row — are written in **`AM-VERDICTS.md`** in the phase folder. Each row: map ID, verdict, evidence type(s), citation(s), what the code does (plain English), what the manual says differently (if anything), Decision ID.
- **D-03:** Citations: query-backed evidence cites the workbook sheet (e.g., `am_verification_20261028.xlsx:V2_INSURANCE`); code-reading evidence cites `path:function():line-range`. A verdict may cite both — c1 and the Insurance confirm row must cite **both** code and their query sheet (V3 and V2 respectively).
- **D-04:** No verdicts are hard-coded in the R script. Nothing is hand-typed into Excel.

### Per-check specification (what each query must produce)

| Check | Lead / map IDs | Must produce |
|-------|----------------|--------------|
| V1_SOURCE | L1 | SOURCE values (normalized `UPPER(TRIM())`) by table — DEMOGRAPHIC, ENCOUNTER, and every other CDM table with a SOURCE column — with row and patient counts, whole extract and HL cohort; LNK counts per table; cohort patients appearing under more than one SOURCE, by table |
| V2_INSURANCE | L2, Insurance confirm row | Same-day payer re-derived under the manual's 6-level hierarchy (Medicaid incl. codes 93/14 or FLM source → Medicare → Private incl. Tricare → Other → Uninsured → missing) vs the pipeline's resolved payer, at patient-day level: agreement rate, full cross-tab, discordant cells by category. Discordant patient-days with IDs → `output/internal/` RDS only |
| V3_DXDATE | L3, c1 | Anchor-date source breakdown (Tumor Registry date vs first HL code date vs other); re-derived anchor under the manual's two-step rule vs `get_hl_any_dx_ids()` anchor: agreement count, distribution of day differences in bands |
| V4_DXSCOPE | L4 | Whether the ≥2 encounters ≥7 days apart rule is applied to non-HL cancer types: counts of non-HL cancer-type assignments that do and do not meet the rule in the pipeline output |
| V5_ZIPCOVER | L5 (data side) | Encounters and patients with ZIP9, ZIP5 only, none; how many receive ADI vs SDI vs imputed values under the pipeline; ZIP5→ZIP9 carry-over counts |
| V6_DEATH | L6 | Deaths dated before the last treatment encounter, by gap band (1–14, 15–30, 31–90, >90 days); how many the 14-day rule removes in the pipeline vs a re-derivation; whether any cohort exclusion uses DEATH_CAUSE (count of patients excluded by it — expected 0) |

### Verification run (HiPerGator)

- **D-20:** The script is written and edited on the local Windows copy, synced to HiPerGator, and run interactively: from the repo directory `module load R/4.5`, `R`, `here::i_am("R/00_config.R")`, `source("R/NNN_am_verification.R")`. No sbatch. The plan includes a human checkpoint for this run; the user pastes the console log tail and copies `am_verification_<date>.xlsx` into the phase folder before verdicts are written.
- **D-21:** The script is standalone: listed in `R/SCRIPT_INDEX.md`, not added to `R/39_run_all_investigations.R` or R/88 unless decided in Phase 194 (AM-TEAM-03). Avoid any script number already used, including the 2026-10-23 standalone `R/190_cbc_encounter_distance.R` if it was added.

### Two workbooks (kept separate)

- **D-05:** **Query workbook** `am_verification_<YYYYMMDD>.xlsx` — written by the R script on HiPerGator. Sheets: KEY (leftmost), V1_SOURCE … V6_DEATH, QC. Add a `V2b_...` sheet only if a lead genuinely needs a second query. Each V-sheet starts with a header block: check ID, lead, map ID(s), query purpose, run date. Counts 1–10 suppressed with complementary suppression; ID-level detail goes to `output/internal/` RDS only. The R script never writes verdicts into it, and `verdicts-export` never writes to it.
- **D-06:** **Verdict workbook** `am_verdicts_<YYYYMMDD>.xlsx` — written by `verdicts-export` (Python, local Windows) into the phase folder from AM-VERDICTS.md + AM-EVIDENCE-MAP.md. Sheets: KEY (leftmost), Verdicts (one row per FILLED-NEEDS-CHECK/BLOCKED map ID), Lead Summary (L1–L9), Decisions (D-191-NN rows), Gaps. UF colours; safe to share with the team.
- **D-08:** No V-sheets for code-reading-only items (L5 method, L7, L8, L9).
- **D-09:** The **Gaps** sheet is generated, not hand-listed: every map ID whose verdict is `BLOCKED` or `CANNOT-VERIFY`, plus every lead whose overall answer is incomplete. c0 will appear here as BLOCKED. L8 appears only if it has a FILLED-NEEDS-CHECK row that cannot be verified; L8 rows that are `EMPTY-NEEDS-TEAM` in the map are out of Phase 191 scope and go to Phase 192/§8.

### Verdict values and evidence types

- **D-10:** Verdict values: `MATCH`, `MISMATCH`, `PARTIAL`, `CANNOT-VERIFY`, `BLOCKED`.
- **D-10a:** Evidence types in AM-VERDICTS.md: `CODE`, `CONFIG`, `QUERY` (workbook sheet), `PLANNING-DOC`, `TEAM-DECISION`. A `MATCH` must rest on `CODE`, `CONFIG` or `QUERY`, not on `PLANNING-DOC` alone.
- **D-11:** `verdicts-export` requires **exactly one verdict row** for every `FILLED-NEEDS-CHECK` and `BLOCKED` map ID in AM-EVIDENCE-MAP.md, and a Lead Summary entry for each of L1–L9. It fails with a list of missing or duplicate IDs. No verdict rows are required for `EMPTY-*` or `OUT-OF-SCOPE` rows.

### Lead summary

- **D-22:** AM-VERDICTS.md has a `## Lead Summary` section with one entry per lead L1–L9: overall answer in one or two sentences, the map IDs it rests on, and whether it is complete. A lead whose map rows are all `EMPTY-*` gets "No FILLED-NEEDS-CHECK rows; carried to Phase 192" rather than a verdict.

### D-191-NN decision rows

- **D-12:** Every `MISMATCH` and every `PARTIAL` verdict carries a `D-191-NN` in its Decision ID column (a PARTIAL also leaves something for the team to settle).
- **D-13:** D-191-NN rows are added to the **AM-MAP-03 Team Decisions table in AM-EVIDENCE-MAP.md** with the existing columns: Raised By = "Phase 191 verification", Map Row(s) linked.
- **D-13a — Already-decided mismatches:** where the manual is out of date but the team has already made the decision (e.g., the >100 mi distance cutoff locked 2026-10-08), the D-191-NN row has Status = `CONFIRMED`, Decided By and Date from the existing decision, Original ID set to that decision's ID, and Notes "Manual update only; no new team decision needed." Only genuinely open questions get Status = `OPEN`. This keeps the Phase 194 email to the team limited to real questions.
- **D-14:** Every new D-191-NN ID is registered in the AM-EVIDENCE-MAP.md ID Registry; `validate` must still pass.
- **D-15:** `verdicts-export` checks that every MISMATCH/PARTIAL row has a D-191-NN and that the ID exists in the AM-MAP-03 table.
- **D-16:** STATE.md gets a one-line pointer only: "D-191-01..NN — see AM-EVIDENCE-MAP.md AM-MAP-03 (n open, n manual-update-only)." Existing D-190-01, D-190-02, D-193-01 rows in STATE.md are not moved.

### c0 (BLOCKED — OneFLquestions not received)

- **D-17:** c0 (`S4-CMNT-01`) gets a verdict row with verdict = `BLOCKED`, citing "OneFLquestions document not received (D-190-01 OPEN)".
- **D-18:** c0 appears on the Gaps sheet of the **verdict workbook** (generated per D-09).
- **D-19:** This answers AM-VER-02 for c0: "BLOCKED — recorded."

### Claude's Discretion

- Script number (next free in SCRIPT_INDEX.md, per D-21).
- Column order within AM-VERDICTS.md rows, as long as all D-02 fields are present.
- How D-191-NN rows are written into AM-EVIDENCE-MAP.md (Python helper preferred over hand edits; `validate` must pass afterwards).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 190 artifacts (primary inputs)
- `.planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md` — authoritative item list; FILLED-NEEDS-CHECK and BLOCKED map IDs; What the Source Shows leads; ID Registry; AM-MAP-03 table to extend
- `.planning/phases/190-evidence-map/am_evidence_20261027.xlsx` — draft evidence workbook (read-only)
- `.planning/phases/190-evidence-map/190-CONTEXT.md` and `190-01-SUMMARY.md` — ID scheme, statuses, D-190-01 interim handling, PROVISIONAL rows

### Requirements and roadmap
- `.planning/REQUIREMENTS.md` — AM-VER-01..04
- `.planning/ROADMAP.md` §Phase 191 — success criteria
- `.planning/STATE.md` — leads L1–L9, open decisions

### Code under verification (minimum)
- `R/36_tiered_same_day_payer.R` and `R/00_config.R` payer mapping — L2, Insurance confirm row
- `R/utils/utils_treatment.R` `get_hl_any_dx_ids()`; Phase 133 SUMMARY — L3, c1
- 7-day confirmation logic (Phases 104, 110) — L4
- `R/utils/utils_address.R` (`approximate_zip9()`, centroid crosswalk), ADI/SDI build scripts — L5
- Death validation and DEATH_CAUSE flag code (Phases 62, 118, 119) — L6
- `R/122_encounter_distance.R`, `haversine_km()`, `get_zip_centroid()`, `CONFIG$far_from_care_cutoff_mi`; Phase 165 decision — L7
- Episode/Gantt code (Phases 142, 164) — L8
- R/147, `utils_surveillance.R`, `docs/analytic_manual/VariableDetails.xlsx` Surveillance Strategy — L9
- `R/169_single_source_care.R` — L1

### Tool to extend
- `tools/am_evidence/am_evidence_map.py` — add `verdicts-export`; existing: `coverage`, `validate`, `export`

### Manual source files
- `docs/analytic_manual/AnalyticManual_2026.01.30.md` — c0/c1 anchors

### Output privacy rules
- `CLAUDE.md` §Outputs and privacy — counts 1–10 as `"<11"`, no patient IDs in workbooks

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/utils/utils_duckdb.R` — `open_pcornet_con()` / `close_pcornet_con()`; use the `opened_here` pattern (as in R/169) so the script never closes a connection it did not open
- `suppress_small()` — display suppression for all counts
- `R/SCRIPT_INDEX.md` — verification script listed here

### Established Patterns
- Workbooks: KEY leftmost, UF colours `#0021A5` / `#FA4616`, counts 1–10 as `"<11"` with complementary suppression, no patient IDs
- Decision IDs `D-NNN-NN`, registered in the ID Registry
- Verdicts live only in markdown; workbooks are generated

### Integration Points
- `R/NNN_am_verification.R` → `am_verification_<date>.xlsx` (HiPerGator) → copied to phase folder → cited in AM-VERDICTS.md
- `AM-VERDICTS.md` + `AM-EVIDENCE-MAP.md` → `verdicts-export` → `am_verdicts_<date>.xlsx`
- D-191-NN rows in AM-MAP-03 → Phase 192 (§8 parking lot) and Phase 194 (team questions: OPEN rows only)

</code_context>

<specifics>
## Specific Ideas

- **c1 scope:** Amy's comment c1 spans **both** Cancer Diagnosis Date rules — "Use diagnosis date from Tumor Registry as default" and "If no diagnosis date: use first date with HL diagnosis code". The c1 verdict must address both steps (TR default, then first-HL-code fallback), citing `get_hl_any_dx_ids()` and V3_DXDATE.
- **Insurance confirm row:** cite `R/36_tiered_same_day_payer.R` (where resolution happens), the `R/00_config.R` mapping, Phases 35–37, and V2_INSURANCE. Record tier count, Medicaid 93/14 and FLM handling, and Tricare placement as found.
- **L7 is a lead, not a verdict:** the brief flagged it as a likely mismatch; Phase 191 confirms from code and the 2026-10-08 team decision. The expected outcome is a MISMATCH with a CONFIRMED D-191 row (manual update only) per D-13a.
- **L5 split:** V5_ZIPCOVER covers the data side; the method verdict (manual's ADI rules vs the ADI-with-ZIP9 / SDI-with-ZIP5 team decision and the imputation code) is code-reading only.
- **`verdicts-export` failure output:** lists missing/duplicate verdict rows, missing Lead Summary entries, MISMATCH/PARTIAL rows without a D-191-NN, and D-191-NN IDs not found in AM-MAP-03; exits non-zero.

</specifics>

<deferred>
## Deferred Ideas

- Changing code or manual text to resolve mismatches — team decides (Phase 194); implementation in a later milestone.

</deferred>

---

*Phase: 191-verify-existing-entries*
*Context gathered: 2026-10-27*
