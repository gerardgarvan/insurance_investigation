# Phase 192: Draft New Content - Context

**Gathered:** 2026-10-28
**Revised:** 2026-10-28 (evidence precedence, §8 entry types, correction handoff, OPEN-decision handling in §2/§4, domain definitions for CLS/PDE, insufficient-evidence rule, draft-check gate)
**Status:** Ready for planning

<domain>
## Phase Boundary

Write all new and corrected manual text into `AM-DRAFT.md` in this phase folder, every statement tagged to its source. No `.docx` file is touched; that is Phase 193. Scope:
- §0 front matter (factual fields only, from repo sources)
- §1 Data Ingest & Change Log (one row per data or reference-file event)
- §2 Cohort (inclusion/exclusion/index date/observation window/study period, as implemented)
- §3 Decision Log (one row per CONFIRMED original team decision from AM-MAP-03)
- §4 Data Cleaning — EMPTY-REPO-CAN-ANSWER manual items, the 12 repo-only domains, and corrections for CONFIRMED D-191 rows
- §5 EHR vs Claims (conservative draft)
- §6 QA checklist (technical checks annotated with script evidence; sign-off boxes blank)
- §7 / A4 Status Tracker
- §8 Parking Lot
- §11 Known Limitations
- Appendices A1 (mirrors §1), A2 (historical cohort definitions), A3 (mirrors §3)
- §9, §10, Appendix B: guidance text — no changes

</domain>

<decisions>
## Implementation Decisions

### Evidence precedence (applies to every drafted statement)

- **D-22:** Before drafting a claim, open the cited source and confirm it supports that specific claim. Precedence:
  1. Current executable code establishes implemented behavior.
  2. Config establishes a configured value, only once a code path that reads it is cited.
  3. CONFIRMED team decisions (AM-MAP-03) establish intended policy.
  4. Phase SUMMARY/CONTEXT documents establish history, not current behavior; they never override current code.
  5. AM-EVIDENCE-MAP.md and AM-VERDICTS.md are indexes to the sources above, not proof on their own.
- **D-22a:** Citations use a stable identifier plus a line range: `path:function()` or `path:CONFIG_KEY`, then `:Lnn-Lnn` checked against the current repo revision. Record the commit hash at the top of AM-DRAFT.md.
- **D-22b:** Where sources disagree, do not reconcile them silently. Describe current code, mark the unit `OPEN-QUESTION-SEE-§8`, and add a §8 entry.

### Handling OPEN D-191 decisions elsewhere in the draft

- **D-27:** Where a drafted section touches a matter with an OPEN D-191 row (e.g., index-date rule D-191-02/03 in §2; 7-day scope D-191-04 in §2 and §4; insurance tiers D-191-05; death grace window D-191-06; distance method D-191-07), the draft describes what the code currently does, flags the unit `OPEN-QUESTION-SEE-§8`, and does not present that behavior as the agreed rule. Existing manual text on these items is left as is; no correction is drafted until the team decides.

### §8 Parking Lot

- **D-01:** §8 uses the manual's existing table (Item | Notes | Date added). No prose paragraphs.
- **D-23:** Two entry types, recorded as a leading tag in Notes:
  - `MISMATCH` — manual vs code. Item wording: "Manual: [manual statement]. Code: [what the code does] ([citation]). Which should the manual record?"
  - `OPEN-DEPENDENCY` — missing input or pending decision with no code discrepancy (D-190-01; treatment window and relapse pending Sharon). Item wording: a factual description of what is pending and from whom; no manual-vs-code template.
- **D-03:** Notes holds the type tag and IDs, e.g. `MISMATCH; D-191-06; S4-DTH-03`. IDs do not appear in the Item sentence.
- **D-04:** Date added = the date of the source record (D-191 verdict date; D-190-01 date; STATE.md entry date). Existing §8 rows are not moved or deleted.
- **D-05:** Only OPEN rows go to §8. CONFIRMED D-191 rows are corrections drafted in their §4 location (D-24), not questions.
- **D-06:** Candidate §8 rows: OPEN D-191 rows as recorded in AM-VERDICTS.md/AM-MAP-03 (take the list from the live files, not from this context); D-190-01; any other OPEN AM-MAP-03 rows; STATE.md parked items. Before listing a STATE.md item (e.g., D-15, D-165-01), confirm it is still open in STATE.md and AM-MAP-03; drop it if resolved.
- **D-23a:** Deduplicate items that appear in more than one source (AM-MAP-03, STATE.md, AM-VERDICTS.md); keep one row and list all IDs in Notes.

### Corrections to existing manual text (Phase 193 handoff)

- **D-24:** Every correction to existing manual text is written in AM-DRAFT.md as a structured directive:
  - Target: section and map ID
  - Existing text anchor: the exact current text, quoted from `AnalyticManual_2026.01.30.md` with its line number
  - Action: `REPLACE` / `INSERT-AFTER` / `MARK-SUPERSEDED`
  - Replacement text
  - Provenance: decision ID(s) and source citation
  Status flag `CORRECTION`. Phase 193 applies these as tracked changes; nothing is applied here.
- **D-10:** D-191-08 (distance cutoff, team-decided under DEC-008, 2026-10-08): directive for S4-DIST-06 — REPLACE the Unresolved Issues wording on 120 vs 200 mi with the confirmed 100 mi cutoff under Cleaning Rules Applied, citing the code path that reads `CONFIG$far_from_care_cutoff_mi` and DEC-008. Under the manual's append-and-date rule, the old wording is shown as a tracked deletion in Phase 193, not removed silently.

### Repo-only §4 domains

- **D-07:** All 12 repo-only domains are drafted in the manual's four-field format (Expected Structure / Observed Issues / Cleaning Rules Applied / Unresolved Issues):
  SHS (single-health-system care flag), CHM (chemo detection across PRESCRIBING / MED_ADMIN / DISPENSING), NRM (drug-name normalization), REG (first-line regimen labeling), EPI (treatment episodes, 90/180-day), ANT (anthracycline exposure), CBC (CBC definition), RUR (rurality, RUCA/RUCC), SDI (Social Deprivation Index), DOI (rituximab/methotrexate diagnoses of interest), CLS (HL vs NHL classification), PDE (post-death encounters).
  Map IDs and sources come from the AM-MAP-02 rows in AM-EVIDENCE-MAP.md.
- **D-08:** 2–5 bullets per field, terse register, rules and definitions only — no counts or results. Every bullet carries its map ID tag (`[S4-CBC-01]`) and a citation per D-22a.
- **D-25 (insufficient evidence):** Never invent Observed Issues, rules, dates, decisions or outcomes to fill the template. A field with no source reads "Not documented in available sources." with status `TEAM-INPUT-NEEDED`. PROVISIONAL rows from Phase 190 are confirmed against code first; if code cannot be located, the item goes under Unresolved Issues as "Rule to be confirmed against code — see [map ID]."

### §0 Front Matter

- **D-11:** Draft only §0's existing fields, each from a source:
  - Data freeze: record separately the extract name and its receipt or freeze date, and the DuckDB build date, each labelled; never treat a build date as the freeze date. Unknown → `[date to confirm]`.
  - Analytic version: v3.13.
  - Data sources: existing text unchanged; the D-191-01 question goes to §8.
  - Project title, grant number, PIs, analytic lead: only if TeamMtgNotes or repo docs state them; otherwise `[TEAM INPUT NEEDED]`.
  - Date last updated and document version: set in Phase 193.
  - No new fields; no version-history table.

### §1 Data Ingest & Change Log (and A1)

- **D-12:** One row per data or reference-file event (not code changes): extract receipt, DuckDB build(s), re-extracts or added tables (DEATH_CAUSE, MED_ADMIN/DISPENSING), LDS_ADDRESS_HISTORY, external reference files (Neighborhood Atlas ADI 2024, NHGIS block-group populations, HRSA ZCTA crosswalk, RUCA/RUCC, SDI, surveillance codeset from VariableDetails.xlsx).
- **D-12a:** Event type is stated per row: `RECEIVED` (file or extract obtained), `INTEGRATED` (first used by the pipeline), or `REBUILT` (DuckDB rebuilt from the same or new inputs). A single file may have a RECEIVED and an INTEGRATED row only where sources date both.
- **D-13:** Manual's column headers; source cited in Notes. Dates only where a source gives one, with the date type stated; otherwise `[date to confirm]`. Rows mirrored to A1.

### §2 Cohort (and A2)

- **D-14:** Manual's fields — Inclusion, Exclusion, Index Date, Observation Window, Study Period — each from code (`get_hl_any_dx_ids()`, CONFIG date range) with citation. Rules only, no attrition counts. Index Date and the 7-day confirmation rule are subject to D-27.
- **D-14a:** Historical definition changes (C81-only → C81 + 201.x; 7-day confirmation added) go in the A2 table. Each date states its type (`decided`, `implemented`, `effective`) and source; otherwise `[date to confirm]`.

### §3 Decision Log (and A3)

- **D-15:** One row per CONFIRMED original team decision from AM-MAP-03, in the manual's columns (Construct, Initial plan, Issue identified, Decision made, Rationale, Date, Affected analyses). D-191 CONFIRMED rows are not added separately; they point to the original decision already listed. Unattributed candidates from Phase 190 are excluded. Rows mirrored to A3.

### §5 EHR vs Claims

- **D-16:** Three separate statements, none implying the other:
  (a) Dataset loading: the pipeline reads the OneFlorida+ PCORnet CDM extract (DuckDB) and does not load or join a separate claims dataset.
  (b) Record provenance: whether claims-derived records are present within the CDM tables (e.g., LNK SOURCE, ENC_TYPE, RAW fields) has not been determined; cite V1_SOURCE.
  (c) Reconciliation: no EHR-vs-claims reconciliation rules are implemented.
  Never state or imply "EHR only." The D-191-01 question goes to §8, worded: "Does the extract contain claims-derived records (e.g., LNK), and should the manual describe claims as a separate secondary source, as part of the CDM, or as out of scope?" If D-191-01's decision text in AM-MAP-03 says "claims not implemented," update it to this wording first.

### §6 QA Checklist

- **D-17:** Technical checks annotated with script evidence (R/88 results; `am_verification_<date>.xlsx`), using only these terms: `Executed`, `Passed`, `Failed`, `Not verified`. Review and approval items read `Not signed off`. Sign-off boxes stay blank. Script evidence is never described as investigator or clinical approval.

### §7 / A4 Status Tracker

- **D-18:** Rows for analysis tasks (Aim 1 treatment, Aim 2 survivorship care, rad onc subgroup) with status from milestone/phase records, worded as delivery status (e.g., "Workbook delivered 2026-10-09 (Phase 165)"), not as approval. Owner only where a source names one.

### §11 Known Limitations

- **D-20:** Only source-backed limitations (care outside the system, LNK/claims status, insurance missingness, straight-line ZIP-centroid distance, ZIP9 imputation, death capture). Neutral wording; no results; each cited.

### AM-DRAFT.md structure and validation

- **D-21:** AM-DRAFT.md mirrors the manual's numbering. Status flags apply to the smallest content unit (bullet, table row, or field): `DRAFTED`, `CORRECTION`, `TEAM-INPUT-NEEDED`, `OPEN-QUESTION-SEE-§8`. Each unit carries its map ID tag (where one exists) and citation.
- **D-26:** Add a `draft-check` subcommand to `tools/am_evidence/am_evidence_map.py`. It fails (non-zero, listing every failure) unless:
  - every manual section heading in scope is present; all 12 repo-only domain blocks are present
  - every EMPTY-REPO-CAN-ANSWER map ID appears in the draft or is listed with a reason in a `## Not drafted` section
  - every unit has a valid status flag; every map ID tag exists in the map; every DRAFTED/CORRECTION unit has a citation
  - every OPEN D-191 row and D-190-01 appears in §8; no CONFIRMED D-191 row appears in §8; every CONFIRMED D-191 row has a CORRECTION directive
  - every CORRECTION directive's anchor text is found verbatim at the stated line of `AnalyticManual_2026.01.30.md`
  - A1 rows equal §1 rows and A3 rows equal §3 rows
  - count lint (numbers 1–10 next to patients/encounters/rows/records/n=) is clean
  - the source .docx/.xlsx hashes match `am_source_hashes.txt`

### Claude's Discretion

- Wording of each bullet, within D-08 and D-22.
- Order of repo-only domains within §4.
- Sub-bullets for multi-step rules (e.g., address resolution tiers).
- Column order within §1/§3/§7 rows, keeping the manual's headers.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 191 artifacts
- `.planning/phases/191-verify-existing-entries/AM-VERDICTS.md` — verdicts, D-191-NN IDs, Lead Summary
- `.planning/phases/191-verify-existing-entries/am_verification_<date>.xlsx` — query workbook (cite by sheet)
- `.planning/phases/191-verify-existing-entries/191-01-NOTES.md` — code-path findings
- `.planning/phases/191-verify-existing-entries/191-CONTEXT.md`

### Phase 190 artifacts
- `.planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md` — map IDs, statuses, AM-MAP-02 repo-only rows, AM-MAP-03 decisions (OPEN/CONFIRMED), ID Registry
- `.planning/phases/190-evidence-map/am_source_hashes.txt`

### Manual source files
- `docs/analytic_manual/AnalyticManual_2026.01.30.md` — current text and line numbers for correction anchors; §8 table format
- `docs/analytic_manual/TeamMtgNotes2026.md`, `docs/analytic_manual/VariableDetails.xlsx`

### Requirements and roadmap
- `.planning/REQUIREMENTS.md` — AM-FILL-01..04
- `.planning/ROADMAP.md` §Phase 192
- `.planning/STATE.md` — parked items

### Code to locate and confirm for §4 repo-only domains (starting points; confirm actual locations)
- SHS: `R/169_single_source_care.R`
- CHM: `get_chemo_hits()` (locate defining file); Phases 122–124
- NRM: `MEDICATION_LOOKUP` in `R/00_config.R`; Phases 114, 164
- REG: Phase 61 code
- EPI: `R/142_gantt_180_export.R`; Phases 142, 164
- ANT: anthracycline code (Phases 166, 187, 188)
- CBC: `build_cbc_events()` in `R/utils/utils_distance_cbc.R`
- RUR: Phase 116 code
- SDI: Phase 144 code
- DOI: `DOI_CODE_MAP`, `R/utils/utils_doi.R`; Phases 127–130
- CLS: HL vs NHL classification code (`utils_cancer.R` or as located); Phases 87, 105
- PDE: post-death encounter code; Phases 62, 113

### Output privacy rules
- `CLAUDE.md` §Outputs and privacy

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tools/am_evidence/am_evidence_map.py` — existing `coverage`, `validate`, `export`, `verdicts-export`; `draft-check` added here (D-26)
- AM-EVIDENCE-MAP.md and AM-VERDICTS.md — routing of OPEN vs CONFIRMED decisions

### Established Patterns
- Map ID tags `[S4-XX-NN]`; four-field §4 format; append-and-date rule for manual edits

### Integration Points
- AM-DRAFT.md → Phase 193 (DRAFTED units inserted; CORRECTION directives applied as tracked changes)
- §8 OPEN rows → Phase 194 cover email

</code_context>

<specifics>
## Specific Ideas

- **§8 wording:** MISMATCH rows use the manual-vs-code template; OPEN-DEPENDENCY rows are plain factual statements.
- **§5:** never "EHR only."
- **S4-DIST-06:** CORRECTION directive per D-10, with the exact current 120/200 mi wording as the anchor.
- **CLS and PDE:** confirm map IDs and sources in AM-MAP-02 before drafting; D-25 applies if code cannot be located.

</specifics>

<deferred>
## Deferred Ideas

- Resolving OPEN mismatches in code or manual — team decides (Phase 194); later milestone.
- Sign-off boxes (§6) — biostatistician and MPI.
- R/88 registration of the verification script — Phase 194 (AM-TEAM-03).

</deferred>

---

*Phase: 192-draft-new-content*
*Context gathered: 2026-10-28*
