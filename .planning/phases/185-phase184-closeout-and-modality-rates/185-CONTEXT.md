# Phase 185: Phase 184 Close-out and Modality Rates - Context

**Gathered:** 2026-10-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Confirm that R/184 has run end-to-end on HiPerGator (Plan 02 checkpoint), pin the dated output workbook path in 185-01-SUMMARY.md, probe the workbook to produce a schema file, write the formal close-out SUMMARY, and mark the v3.11 MILESTONES known-gap entry resolved. No new modeling. No R/184 code changes.

</domain>

<decisions>
## Implementation Decisions

### R184_OUTPUT Pin (CLOSE-01)

- **D-01:** R/184 does NOT set `R184_OUTPUT`. The consumer owns the pin. R/186 defines `R184_OUTPUT` with the exact dated default path (recorded in 185-01-SUMMARY.md), records path and pinned TRUE/FALSE in its KEY sheet, and stops if the file is missing.
- **D-02:** Phase 185's plan records the exact dated workbook filename (e.g. `modality_rate_model_YYYYMMDD.xlsx`) in 185-01-SUMMARY.md so Phase 186's planner can hardcode it as the `R184_OUTPUT` default without guessing.

### RATE-01 Label Convention

- **D-03:** After the HiPerGator run, run `probe_inputs()` on the R/184 workbook and write `.planning/schemas/185_schema_<date>.md`. Phase 186 uses ONLY the sheet names, section headers, and row labels in that probe file — held as named constants. No R/184 Analysis-column patch.
- **D-04:** Phase 186 reads the Rates sheet by exact section header + modality × far row label (one match or stop). The exact section header text ("Annual rates (years 2+) — by modality x far") is locked as a named constant sourced from the 185 schema probe.

### HiPerGator Run and Close-out (CLOSE-01, CLOSE-02)

- **D-05:** R/184 runs as written (no patches before the run). Source command: `source("R/184_modality_rate_model.R", local = new.env(parent = globalenv()))` after `module load R/4.5`.
- **D-06:** Non-convergence cells in Model_Results and QC sheets are labeled (not blank). If the Poisson GEE `geese$error != 0`, the script already stops — this is the non-convergence gate. Any per-modality fallback note is logged in QC.
- **D-07:** Patient counts 1–10 suppressed as `"<11"` throughout; rates displayed only when numerator and denominator both ≥ 11. Already implemented in R/184 via `sup()` and `rate_or_dash()`.

### 185-01-SUMMARY Scope

- **D-08:** Standard close-out SUMMARY template. Additionally records: (a) exact dated workbook filename for Phase 186's `R184_OUTPUT` default, (b) the exact Rates sheet section header text Phase 186 must use for RATE-01, (c) gate values (reproduction gate OR, global Wald chi2/df/p) pasted from the HiPerGator console.

### Claude's Discretion

- Plan structure (one plan vs two) — Claude decides based on whether a pre-run patch to R/184 is needed; D-05 locks no patches, so a single plan is expected.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 184 Artifacts
- `.planning/phases/184-survivorship-modality-rates-and-distance-modality-interaction/184-CONTEXT.md` — Phase 184 locked decisions (corstr, eligibility frame, GEE spec)
- `.planning/phases/184-survivorship-modality-rates-and-distance-modality-interaction/184-01-SUMMARY.md` — Section 0–3 names: run_gee(), year_index_cat, exact-label reader, events RDS pointer
- `.planning/phases/184-survivorship-modality-rates-and-distance-modality-interaction/184-02-PLAN.md` — Full task spec for Sections 4–10; R184_OUTPUT workbook design; HiPerGator run + registration steps

### R/184 Script
- `R/184_modality_rate_model.R` — Full 1581-line script; Rates sheet section headers at lines 1274–1303; saveWorkbook at line 1463

### Schema Probe (written during Phase 185 execution)
- `.planning/schemas/185_schema_<date>.md` — Sheet names, section headers, column names from the actual R/184 workbook. **Task 0 for every Phase 185 and Phase 186 plan must cite this file.** Does not exist until after the HiPerGator run.

### Requirements
- `.planning/REQUIREMENTS.md` — CLOSE-01, CLOSE-02, RATE-01 (lines 13–18)

### Utilities
- `R/utils/utils_schema_probe.R` — `probe_inputs()` function for generating schema files

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/184_modality_rate_model.R` — Complete; runs as-is. No patches required before the HiPerGator run.
- `R/utils/utils_schema_probe.R` — `probe_inputs()`: generates `.planning/schemas/<phase>_schema_<date>.md` from a workbook or RDS. Run on the R/184 workbook after the HiPerGator run.
- `sup()` and `rate_or_dash()` — already in R/184 for `<11` suppression and rate display.

### Established Patterns
- Pin pattern: `pin("R184_P179_RDS", "output/internal/...")` in R/184 SECTION 0 (lines 217–219). R/186 follows this exact pattern for `R184_OUTPUT`.
- Exact-label reader: R/183 lines 548–562 (copied verbatim into R/184 lines 266–288). Phase 186 will use this pattern to read from the R/184 workbook.
- Section headers in Rates sheet written via `add_section_header()` (R/184 line 1203).

### Integration Points
- R/88 smoke test — run after R/184 to confirm 982 checks pass.
- R/39 run-all registration — R/184 and SCRIPT_INDEX.md entries; already planned in 184-02-PLAN.md Task 7.
- ROADMAP.md line ~768 — v3.11 MILESTONES entry for Phase 184 (`[~]`) must be changed to `[x]` and the pending-checkpoint note removed.

</code_context>

<specifics>
## Specific Ideas

- Gate values (reproduction gate OR and global Wald) must be pasted verbatim from the HiPerGator console into 185-01-SUMMARY.md — not recomputed or paraphrased.
- The exact workbook filename (e.g. `modality_rate_model_20261022.xlsx`) must appear in SUMMARY so Phase 186's planner can use it as the `R184_OUTPUT` dated default without listing files.
- The exact Rates sheet section header string ("Annual rates (years 2+) — by modality x far") must be quoted in SUMMARY as the RATE-01 read target — to be confirmed against the actual workbook via the schema probe.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 185-phase184-closeout-and-modality-rates*
*Context gathered: 2026-10-22*
