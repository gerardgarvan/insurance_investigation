# Phase 192: Draft New Content - Context

**Gathered:** 2026-10-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Write all new manual text into `AM-DRAFT.md` in this phase folder — every statement tagged to its source. No `.docx` file is touched; that is Phase 193. Scope:
- §0 front matter (factual fields only, from repo sources)
- §1 Data Ingest & Change Log (one row per actual data or reference-file event)
- §2 Cohort (inclusion/exclusion/index-date/observation-window/study-period rules from code)
- §3 Decision Log (one row per CONFIRMED original team decision from AM-MAP-03)
- §4 Data Cleaning — all EMPTY-REPO-CAN-ANSWER domains (manual fields + 12 repo-only domains)
- §5 EHR vs Claims (conservative draft from what the repo shows)
- §6 QA checklist (technical checks annotated with script evidence; sign-off boxes blank)
- §7 / A4 Status Tracker (analysis task rows with status from milestone/phase records)
- §8 Parking Lot (OPEN D-191-NN rows + D-190-01 + open AM-MAP-03 rows + STATE.md parked items)
- §11 Known Limitations (only source-backed limitations; neutral wording; no results)
- §9, §10, Appendix B: guidance text — no changes
- Appendices A1 (data events), A2 (historical cohort definitions), A3 (decision log mirror)

</domain>

<decisions>
## Implementation Decisions

### §8 Mismatch Framing

- **D-01:** §8 uses table rows (Item | Notes | Date added), not prose paragraphs, matching the manual's existing §8 format.
- **D-02:** Each OPEN D-191-NN row is written as: neutral difference statement + a closing question ("Which should the manual record?"). Example: "Manual: deaths dated within 14 days before the last treatment encounter are ignored. Code: grace period is 30 days (utils_death.R:51). Which should the manual record?"
- **D-03:** Notes column holds the decision and map IDs: `D-191-06; S4-DTH-03`. The IDs do not appear in the Item sentence.
- **D-04:** Date added = Phase 191 date (2026-10-28). Existing rows in §8 are not moved or deleted.
- **D-05:** **Only OPEN D-191-NN rows** go to §8. The CONFIRMED row (D-191-08: 100 mi cutoff, DEC-008) is a manual-update-only correction — it goes into §4 (S4-DIST-06) as a tracked correction citing the existing team decision, not as an open question.
- **D-06:** OPEN rows for §8: D-191-01 (claims), D-191-02/03 (TR-first anchor), D-191-04 (7-day scope), D-191-05 (insurance tier count), D-191-06 (death grace window), D-191-07 (distance method). Also: D-190-01 (OneFLquestions document not received), any open AM-MAP-03 rows, and parked items from STATE.md (treatment window/relapse pending Sharon, D-15, D-165-01).

### Repo-only §4 Domains

- **D-07:** All 12 repo-only domains are drafted using the manual's four-field format: Expected Structure / Observed Issues / Cleaning Rules Applied / Unresolved Issues. Domains: SHS (single-health-system care), CHM (chemo detection), NRM (drug-name normalization), REG (regimen labeling), EPI (treatment episodes), ANT (anthracycline exposure), CBC (CBC definition), RUR (rurality), SDI (Social Deprivation Index), DOI (Diagnoses of Interest), CLS (cancer classification), PDE (additional domains to confirm from evidence map).
- **D-08:** 2–5 bullets per subsection, in the manual's terse register. **No counts or results** — rules and definitions only (counts go stale). Every bullet tagged with its map ID: `[S4-CBC-01]`, and cites its source (script:function():line-range, CONFIG key, or decision ID).
- **D-09:** PROVISIONAL rows are confirmed against code first. If code cannot be located, the item goes under Unresolved Issues as "to be confirmed" rather than being drafted as established fact.
- **D-10:** D-191-08 correction (distance cutoff = 100 mi, team-decided DEC-008): drafted as a factual statement in S4-DIST-06 under Cleaning Rules Applied, citing `R/00_config.R:233` and DEC-008. This is not listed as an open question in §8.

### §0 Front Matter

- **D-11:** Draft only fields that §0 actually has and that a repo source can answer: data freeze / extract name + DuckDB build date (cite source), analytic version (v3.13), data sources (per Phase 191 verdict on S0-FM-04 — if D-191-01 is OPEN, leave existing text and list in §8). Fields that require team input (project title, grant number, PIs, analytic lead) are filled only if TeamMtgNotes or repo docs state them; otherwise `[TEAM INPUT NEEDED]`. Date last updated and document version are set in Phase 193. No version-history table (the manual doesn't have one).

### §1 Data Ingest & Change Log

- **D-12:** One row per actual **data or reference-file event** (not code changes). Events to include: initial extract receipt, DuckDB build(s), any re-extract or added table (DEATH_CAUSE, MED_ADMIN/DISPENSING), LDS_ADDRESS_HISTORY, external reference files (Neighborhood Atlas ADI 2024, NHGIS block-group populations, HRSA ZCTA crosswalk, RUCA/RUCC, SDI, surveillance codeset from VariableDetails.xlsx).
- **D-13:** Columns as in the manual's §1 table. Each row cites the phase SUMMARY or file in Notes. Dates only where a source gives one; otherwise `[date to confirm]`. Same rows mirrored to Appendix A1.

### §2 Cohort

- **D-14:** Use the manual's own fields — Inclusion, Exclusion, Index Date, Observation Window, Study Period — each derived from code (`get_hl_any_dx_ids()`, `CONFIG` date range) with script:function():line-range citation. No attrition counts in §2 (rules only). Historical cohort definition changes (C81-only → C81 + 201.x, 7-day confirmation added) go in Appendix A2 table with dates.

### §3 Decision Log

- **D-15:** One row per CONFIRMED original team decision from AM-MAP-03, in the manual's columns (Construct, Initial plan, Issue identified, Decision made, Rationale, Date, Affected analyses). D-191 CONFIRMED rows point to the original decision already listed — they are not added as new rows. OPEN rows go to §8 only. Same rows mirrored to Appendix A3.

### §5 EHR vs Claims

- **D-16:** Draft §5 conservatively from what the repo shows: (a) data come from the OneFlorida+ PCORnet CDM extract (DuckDB); the pipeline does not load or join a separate claims dataset. (b) Whether claims-derived records are present within CDM tables (via LNK SOURCE, ENC_TYPE/RAW fields) has not been determined; cite V1_SOURCE results. (c) No EHR-vs-claims reconciliation rules are implemented. Then the D-191-01 open question goes to §8 — reworded as: "Does the extract contain claims-derived records (e.g., LNK), and should the manual describe claims as a separate secondary source, as part of the CDM, or as out of scope?"

### §6 QA Checklist

- **D-17:** Annotate technical checks with script evidence (R/88 results, verification workbook `am_verification_20261027.xlsx`). All sign-off boxes left blank — filled by biostatistician and MPI, not in this phase.

### §7 / A4 Status Tracker

- **D-18:** Rows for analysis tasks (Aim 1: treatment, Aim 2: survivorship care, Rad onc subgroup) with status taken from milestone/phase records. Owner is filled only where a source names one; otherwise left blank.

### §8 Parking Lot

- **D-19:** Rows in the §8 table per D-01–D-06. Also include parked items from STATE.md: treatment window pending Sharon, relapse definition pending Sharon, D-15 (treatment-window rules), D-165-01.

### §11 Known Limitations

- **D-20:** Draft only limitations supported by a source (care outside the system, LNK/claims status, insurance missingness, straight-line ZIP-centroid distance, ZIP9 imputation, death capture). Neutral wording, no results. If a limitation was documented in a phase SUMMARY or team meeting, cite it.

### AM-DRAFT.md Structure

- **D-21:** `AM-DRAFT.md` mirrors the manual's section numbering. Each drafted block carries: the map ID tag `[S4-XX-XX]`, the source citation (script:function():line-range or CONFIG key or decision ID), and a `STATUS:` flag (`DRAFTED`, `TEAM-INPUT-NEEDED`, or `OPEN-QUESTION-SEE-§8`). All 12 repo-only §4 domains appear as new subsections. No `.docx` is touched.

### Claude's Discretion

- Exact wording of each drafted bullet, as long as it is factual, terse, neutral, and matches the manual's register.
- Order of repo-only §4 domains within the new subsections.
- Whether to use sub-bullets within a field if a rule has multiple steps (e.g., address resolution tiers).
- Exact column order within §1 / §3 / §7 table rows, as long as the manual's column headers are preserved.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 191 artifacts (primary inputs)
- `.planning/phases/191-verify-existing-entries/AM-VERDICTS.md` — all verdicts and D-191-NN rows; OPEN vs CONFIRMED status; Lead Summary
- `.planning/phases/191-verify-existing-entries/am_verification_20261027.xlsx` — query workbook (V1_SOURCE … V6_DEATH)
- `.planning/phases/191-verify-existing-entries/191-CONTEXT.md` — D-01 through D-22 decisions (evidence types, workbook format, per-check specs)

### Phase 190 artifacts (evidence map)
- `.planning/phases/190-evidence-map/AM-EVIDENCE-MAP.md` — all map IDs, statuses (EMPTY-REPO-CAN-ANSWER, FILLED-NEEDS-CHECK, etc.), AM-MAP-03 team decisions table, ID Registry
- `.planning/phases/190-evidence-map/190-CONTEXT.md` — D-190-01 interim handling, domain scope

### Manual source files
- `docs/analytic_manual/AnalyticManual_2026.01.30.md` — §0–§11 current text; §8 existing table format; sign-off boxes

### Requirements and roadmap
- `.planning/REQUIREMENTS.md` — AM-FILL-01 through AM-FILL-04
- `.planning/ROADMAP.md` §Phase 192 — success criteria
- `.planning/STATE.md` — parked items (treatment window/relapse, D-15, D-165-01)

### Code under review (for §4 repo-only domain drafting)
- `R/169_single_source_care.R` — SHS flag
- `R/utils/utils_treatment.R` `get_chemo_hits()` — CHM
- `R/00_config.R` `MEDICATION_LOOKUP` — NRM (drug-name normalization)
- Phase 61 SUMMARY — REG (first-line regimens)
- `R/142_gantt_180_export.R`, Phase 164 SUMMARY — EPI (treatment episodes)
- `R/utils/utils_anthracycline_echo.R`, Phase 187–188 SUMMARYs — ANT
- `R/utils/utils_distance_cbc.R` `build_cbc_events()` — CBC
- Phase 116 SUMMARY — RUR (rurality)
- Phase 144 SUMMARY — SDI
- Phase 127–128 SUMMARYs, `R/utils/utils_doi.R` — DOI

### Output privacy rules
- `CLAUDE.md` §Outputs and privacy — counts 1–10 as `"<11"`, no patient IDs; only in `output/internal/`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AM-EVIDENCE-MAP.md` — all map IDs and their statuses are the authoritative item list; AM-MAP-03 holds team decisions to populate §3
- `AM-VERDICTS.md` — OPEN vs CONFIRMED status for each D-191-NN row; determines §8 vs §4 routing

### Established Patterns
- Map ID tags `[S4-XX-XX]` used throughout Phase 191 verdicts — same convention in AM-DRAFT.md
- Four-field §4 domain format established in the existing manual: Expected Structure / Observed Issues / Cleaning Rules Applied / Unresolved Issues
- UF colours `#0021A5` / `#FA4616`, KEY leftmost (applies to Phase 193 workbook, not AM-DRAFT.md)

### Integration Points
- `AM-DRAFT.md` → consumed by Phase 193 planner to insert content as Word tracked changes
- D-191-NN Decision IDs → Phase 194 cover email (OPEN rows only, already attributed in §8)
- D-190-01 (OneFLquestions OPEN) → §8 parking lot in AM-DRAFT.md

</code_context>

<specifics>
## Specific Ideas

- **§4 CONFIRMED correction (D-191-08):** the 100 mi distance cutoff belongs in §4 S4-DIST-06 Cleaning Rules Applied as factual text (`CONFIG$far_from_care_cutoff_mi = 100`, `R/00_config.R:233`, DEC-008, 2026-10-08), not in §8. The manual's "Unresolved Issues" wording about 120/200 mi is replaced by the factual statement.
- **§5 claims wording:** never assert "EHR only" — say "the pipeline does not load or join a separate claims dataset." The LNK SOURCE may carry claims-derived records within the CDM; V1_SOURCE results bear on this.
- **§8 item wording pattern:** "Manual: [what manual says]. Code: [what code does] ([citation]). Which should the manual record?" — Notes column: `D-191-NN; S4-XX-XX`.
- **PROVISIONAL domains confirmed against code:** before drafting REG (regimens), EPI (episodes), or ANT (anthracycline), the planner should verify the implementing script exists and the function signature is as documented in the phase SUMMARY. If the code cannot be located, Unresolved Issues entry: "Rule to be confirmed against code — see [map ID]."
- **12 repo-only domains:** the user specified SHS, CHM, NRM, REG, EPI, ANT, CBC, RUR, SDI, DOI, CLS, PDE. CLS (cancer classification) and PDE should be confirmed against AM-EVIDENCE-MAP.md for their exact map IDs and source citations before drafting.

</specifics>

<deferred>
## Deferred Ideas

- Changing code or manual text to resolve mismatches — team decides (Phase 194); implementation in a later milestone.
- Sign-off boxes (§6) — filled by biostatistician and MPI, not in scope for this milestone.
- R/88 registration of verification script — decided in Phase 194 (AM-TEAM-03).

</deferred>

---

*Phase: 192-draft-new-content*
*Context gathered: 2026-10-28*
