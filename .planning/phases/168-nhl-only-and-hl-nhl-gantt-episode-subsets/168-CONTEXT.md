# Phase 168: NHL-Only and HL+NHL Gantt Episode Subsets — Context

**Gathered:** 2026-10-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce two filtered views of `gantt_episodes_180` — one for strict NHL-only patients (Group 1) and one for HL+NHL patients (Group 2) — each joined to columns E-J of the team's chemo-combos sheet. Deliver as an Excel workbook (KEY, two episode tabs, QC) plus two matching CSVs. HiPerGator-only run.

</domain>

<decisions>
## Implementation Decisions

### CSV Output (D-168-CSV)
- **D-01:** Write CSVs alongside the workbook — same data frames, cannot disagree with workbook tabs.
- **D-02:** Filenames: `nhl_only_episodes_<YYYYMMDD>.csv` and `hl_nhl_episodes_<YYYYMMDD>.csv`.
- **D-03:** All outputs (workbook and CSVs) written to `output/internal/` — they contain patient IDs and are internal by design. Only QC aggregate counts are non-internal.

### "x" Value Matching (milestone-level, closed)
- **D-04:** Matching is case-insensitive and whitespace-trimmed — "X", " x " all count.
- **D-05:** Any non-blank, non-"x" value in columns E (`Definitely HL`), F (`Definitely NHL`), or J (`HL and NHL`) is logged in QC as an unexpected value for the team to inspect (e.g., "x?", "yes"). These rows are NOT silently dropped.

### drug_names Cross-Check QC Format (D-168-DRUGNAMES)
- **D-06:** Normalize both sides before comparing: lowercase → trim → split on the multi-value separator → sort list → rejoin. This prevents order-only differences (e.g., "ABVD in different order") or whitespace from showing as mismatches.
- **D-07:** QC reports three counts: (a) exact matches, (b) matches only after normalization, (c) real mismatches.
- **D-08:** Real mismatches listed one row each in QC: `patient_id`, `episode_number`, sheet drug_names value, Gantt drug_names value. Count alone is insufficient — each mismatch points to a join or version problem.

### Suppression
- **D-09:** No `suppress_small()` on episode tabs or CSVs — every row is a patient episode (already patient-level). QC aggregate counts are the only candidates for suppression review; apply project standard if counts < 11 appear in aggregate cells.

### Workbook & Script Conventions
- **D-10:** Use `openxlsx` (not openxlsx2) — matches Phase 167 / R/169 convention.
- **D-11:** KEY sheet leftmost, then `NHL_only_episodes`, then `HL_NHL_episodes`, then `QC`.
- **D-12:** Column E-J header names preserved exactly as in the source sheet.

### Plan Structure
- **D-13:** Plans must end with a HiPerGator run step and a team review step. The chemo-combos file exists only at `/blue/erin.mobley-hl.bcu/` — local runs skip silently via the probe-first gate (log + early return).
- **D-14:** The plan must confirm from the August 2026-08-14 gantt snapshot CSV: the Gantt ID column name, episode-number column name, the column and value used to restrict to chemo rows (e.g., whether there is a `drug_group`, `code_type`, or similar filter), and whether episode numbers are scoped across all treatment types or within each type. Do not assume — read from the file.

### Already-Closed Roadmap Decisions (not to re-open)
- D-168-01: Join against 2026-08-14 `gantt_episodes_180.csv` snapshot (pre-rename); post-rename version not included.
- D-168-02: One workbook, two episode tabs (not separate workbooks).
- D-168-03: QC reports both strict Group 1 count and loose count (any `Definitely NHL` = x).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Group Definitions (locked in roadmap)
- `.planning/ROADMAP.md` §"Phase 168: NHL-Only and HL+NHL Gantt Episode Subsets" — Group 1 strict definition, Group 2 definition, join grain, QC content requirements, probe-first gate spec, output column list

### Gantt Schema
- `R/142_gantt_180_export.R` — defines `gantt_episodes_180.csv` schema (20 columns); planner must read to confirm episode-number and chemo-row filter columns before writing tasks

### Script Conventions
- `R/169_single_source_care.R` — reference for openxlsx workbook structure, KEY-sheet pattern, probe-first gate pattern, `output/internal/` placement

### Config
- `R/00_config.R` — `CONFIG$chemo_combos_path`, `CONFIG$gantt_180_snapshot_path`, `CONFIG$output_dir`; planner must confirm these keys exist or add them

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/169_single_source_care.R` SECTION 4-5: openxlsx workbook build pattern with KEY sheet, named tabs, `setColWidths`, `createStyle` — reuse directly
- `R/00_config.R` probe-first gate pattern: check file exists, log and `invisible(NULL)` if absent — used in multiple recent scripts
- `R/142_gantt_180_export.R` lines ~631+: reads `gantt_episodes_180.csv` with `col_types = cols(.default = col_character())` — reuse this safe read pattern

### Established Patterns
- Multi-value field separator is semicolon (D-02 in R/142: `clean_multi_value` / `D-03: semicolons`)
- `suppress_small()` threshold = 11 (project standard); not applied to episode rows, only aggregate QC cells if any appear
- `run_date <- format(Sys.Date(), "%Y%m%d")` for output filename datestamping
- Script header block: Purpose, Inputs, Outputs, Requirements, Phase, Plan, INTERNAL flag

### Integration Points
- `CONFIG$chemo_combos_path` — needs to exist in `R/00_config.R` (may need adding)
- `CONFIG$gantt_180_snapshot_path` — needs to exist (may need adding; roadmap specifies pinned to 2026-08-14 CSV)
- Output lands in `output/internal/` alongside other internal-flagged workbooks from recent phases

</code_context>

<specifics>
## Specific Requirements

- drug_names normalization: lowercase → trim → split on semicolon separator → sort → rejoin before comparing
- Three-count drug_names QC structure: exact matches / matches-after-normalizing / real mismatches
- Real mismatch rows: `patient_id`, `episode_number`, sheet value, Gantt value — side-by-side
- CSV filenames are explicit: `nhl_only_episodes_<YYYYMMDD>.csv` and `hl_nhl_episodes_<YYYYMMDD>.csv`
- QC counts for: IDs per group, matched/unmatched periods each direction, duplicate period keys, group overlap (expected 0 — sanity check), non-"x" unexpected values in E/F/J, gantt snapshot version (row count + checksum)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 168-nhl-only-and-hl-nhl-gantt-episode-subsets*
*Context gathered: 2026-10-08*
