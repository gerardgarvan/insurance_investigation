# Phase 192: Draft New Content - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-28
**Phase:** 192-draft-new-content
**Areas discussed:** §8 mismatch framing, Repo-only §4 domains, §0–§3 depth and format, §5 EHR vs Claims

---

## §8 Mismatch Framing

| Option | Description | Selected |
|--------|-------------|----------|
| Neutral statement (recommended) | "The code does X; the manual currently states Y. See D-191-NN." No question mark. | |
| Question to team | "Code does X, manual says Y — which should be authoritative?" | |
| Table row per existing §8 format | Match the manual's existing §8 table structure. | ✓ |

**User's choice:** Table rows (Item | Notes | Date added), but with neutral wording AND a closing question in the Item column — "Manual: [X]. Code: [Y] ([citation]). Which should the manual record?" D-191-NN and map ID go in Notes column. Date added = 2026-10-28. Only OPEN D-191 rows go to §8; CONFIRMED rows (D-191-08) go to §4 as factual corrections.

**Notes:** User clarified that the item sentence should state both sides neutrally before asking the question. The question is not a standalone "which is right?" — it follows the description. Confirmed D-191-08 (100 mi cutoff, DEC-008) is manual-update-only: factual text in §4, not §8.

---

## Repo-only §4 Domains

| Option | Description | Selected |
|--------|-------------|----------|
| Full four-subsections, polished (recommended) | Ready-to-insert, with counts and citations. | |
| Full four-subsections, no counts | 2–5 bullets per field, terse, rules only, tagged and cited. | ✓ |
| Skeleton with placeholders | Headings and bullets only; user fills prose. | |
| Only non-PROVISIONAL domains | Skip REG, REL, TRT. | |

**User's choice:** Full four-field format (Expected Structure / Observed Issues / Cleaning Rules Applied / Unresolved Issues), 2–5 bullets each, terse register, **no counts** (counts go stale; manual is a methods record). Every bullet tagged `[S4-XX-XX]` with source citation. All 12 repo-only domains in scope. PROVISIONAL rows confirmed against code first; if not locatable → Unresolved Issues.

**Notes:** User specified 12 domains: SHS, CHM, NRM, REG, EPI, ANT, CBC, RUR, SDI, DOI, CLS, PDE. CLS and PDE to be confirmed from evidence map.

---

## §0–§3 Depth and Format

### §0 Front Matter

**User's choice:** Draft only fields §0 actually has and that a repo source can answer. Factual fields: data freeze / extract name, analytic version (v3.13), data sources (conservative per D-191-01 status). Team-input fields: `[TEAM INPUT NEEDED]`. Date last updated and document version set in Phase 193. No version-history table.

### §1 Data Ingest & Change Log

**User's choice:** One row per actual data or reference-file event (not code changes): initial extract receipt, DuckDB build(s), DEATH_CAUSE, MED_ADMIN/DISPENSING, LDS_ADDRESS_HISTORY, and external reference files (ADI 2024, NHGIS populations, HRSA ZCTA crosswalk, RUCA/RUCC, SDI, surveillance codeset). Columns as in manual's §1 table; cite phase SUMMARY or file in Notes; dates from source or `[date to confirm]`. Mirrored to Appendix A1.

### §2 Cohort

**User's choice:** Use manual's own fields (Inclusion, Exclusion, Index Date, Observation Window, Study Period) from code with citations. No attrition counts. Historical cohort changes → Appendix A2.

### §3 Decision Log

**User's choice:** One row per CONFIRMED original team decision from AM-MAP-03. D-191 CONFIRMED rows point to original decision — not added as new rows. OPEN rows → §8 only. Mirrored to Appendix A3.

---

## §5 EHR vs Claims

| Option | Description | Selected |
|--------|-------------|----------|
| Draft what's true (recommended) | EHR CDM only; LNK status uncertain; no reconciliation. Open question in §8. | ✓ |
| Leave §5 blank | Note: cannot draft until D-191-01 resolved. | |

**User's choice:** Draft conservatively from what the repo shows: pipeline uses PCORnet CDM (DuckDB), no separate claims dataset loaded or joined. Whether claims-derived records exist within CDM tables (LNK SOURCE, ENC_TYPE/RAW) not determined — cite V1_SOURCE. No EHR-vs-claims reconciliation rules implemented. D-191-01 open question goes to §8: "Does the extract contain claims-derived records (e.g., LNK), and should the manual describe claims as a separate secondary source, as part of the CDM, or as out of scope?"

**Notes:** User explicitly said "without asserting 'EHR only'" — the LNK SOURCE may carry claims-derived records within the CDM.

---

## Sections Not Discussed (User-Supplied Defaults)

- **§6 QA checklist:** annotate technical checks with script evidence (R/88, verification workbook); sign-off boxes blank.
- **§7 / A4 Status tracker:** task rows with status from milestone/phase records; owner only where source names one.
- **§8 Parking lot:** OPEN D-191-NN rows + D-190-01 + open AM-MAP-03 rows + STATE.md parked items.
- **§11 Known limitations:** only source-backed limitations; neutral wording; no results.
- **§9, §10, Appendix B:** guidance text only — no changes.
- **AM-DRAFT.md:** output file; all drafted text with map-ID tags and citations; no `.docx` edits.

---

## Claude's Discretion

- Exact bullet wording (must be factual, terse, neutral, matching manual register)
- Order of repo-only §4 domains within new subsections
- Whether to use sub-bullets for multi-step rules (e.g., address resolution tiers)
- Exact column order within §1/§3/§7 table rows (manual column headers preserved)

## Deferred Ideas

- Code or manual text changes to resolve mismatches — Phase 194 / later milestone
- Sign-off boxes (§6) — biostatistician and MPI scope
- R/88 registration — Phase 194 AM-TEAM-03
