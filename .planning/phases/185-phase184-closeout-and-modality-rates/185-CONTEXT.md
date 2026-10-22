# Phase 185: Phase 184 Close-out and Modality Rates - Context

**Gathered:** 2026-10-22 (revised 2026-10-22 after review)
**Status:** Ready for planning

<domain>
## Phase Boundary

Confirm that R/184 has run end-to-end on HiPerGator (Plan 02 checkpoint), pin the dated output workbook path in 185-01-SUMMARY.md, probe the workbook to produce a schema file, write the formal close-out SUMMARY, and mark the v3.11 MILESTONES known-gap entry resolved. No new modeling. No R/184 code changes.

</domain>

<decisions>
## Implementation Decisions

### R184_OUTPUT Pin (CLOSE-01)

- **D-01:** R/184 does NOT set `R184_OUTPUT`. The consumer owns the pin. R/186 defines `R184_OUTPUT` with the exact dated default path (recorded in 185-01-SUMMARY.md), records path and pinned TRUE/FALSE in its KEY sheet, and stops if the file is missing.
- **D-02:** Phase 185's plan records the exact dated workbook filename in 185-01-SUMMARY.md so Phase 186's planner can hardcode it as the `R184_OUTPUT` default without guessing. The filename is copied from the HiPerGator console output of the run — not inferred from the `saveWorkbook()` call or any example in this file.

### RATE-01 Label Convention

- **D-03:** After the HiPerGator run, run `probe_inputs()` on the R/184 workbook and write `.planning/schemas/185_schema_<date>.md`. Phase 186 uses ONLY the sheet names, section headers, and row labels in that probe file — held as named constants. No R/184 Analysis-column patch.
- **D-04:** Phase 186 reads the Rates sheet by exact section header + modality × far row label (one match or stop). The header string is taken verbatim from `185_schema_<date>.md`, not from this CONTEXT or from R/184 source. The text quoted in Specifics is provisional; if the probe differs, the probe wins. Watch the em dash (—) in the header: the match must use the character exactly as the probe records it.
- **D-05:** RATE-01 check in this phase: confirm the annual-rates block exists on the Rates sheet and has one row per modality × far level. Record the row count in SUMMARY.

### HiPerGator Run and Close-out (CLOSE-01, CLOSE-02)

- **D-06:** R/184 runs as written (no patches before the run). Source command: `source("R/184_modality_rate_model.R", local = new.env(parent = globalenv()))` after `module load R/4.5`.
- **D-07:** Non-convergence handling. The planner confirms from R/184 source whether the `geese$error != 0` stop is global (one failed fit halts the script) or per-modality, and states which in the plan. Either way, Phase 185 does no fallback refitting (no new modeling): if any GEE fit fails, the run is a failed checkpoint, close-out stops, and the failure (modality, error code, console text) is recorded in SUMMARY as a deviation for a follow-up decision. Per-modality fallback notes already written by R/184 to the QC sheet are reported as-is.
- **D-08:** Patient counts 1–10 suppressed as `"<11"` throughout; rates displayed only when numerator and denominator both ≥ 11. Already implemented in R/184 via `sup()` and `rate_or_dash()`.
- **D-09:** Reproduction gate. Close-out requires the R/184 reproduction gate to pass: OR and both CI bounds within 0.005 of the pinned reference, with NA checked before comparing. A gate failure blocks close-out and is recorded as a deviation; Phase 186 does not start on a failed run.

### 185-01-SUMMARY Scope

- **D-10:** Standard close-out SUMMARY template. Additionally records: (a) exact dated workbook filename for Phase 186's `R184_OUTPUT` default, (b) the exact Rates sheet section header text from the schema probe for RATE-01, (c) gate values (reproduction gate OR and CI bounds, global Wald chi2/df/p) pasted verbatim from the HiPerGator console, (d) the D-05 row count, (e) the actual R/88 check count.
- **D-11:** Gate values in SUMMARY are documentation only. They are never typed into R/186 or any later script; downstream code reads reference values by exact label from the pinned workbook at run time.

### Claude's Discretion

- Plan structure (one plan vs two) — Claude decides based on whether a pre-run patch to R/184 is needed; D-06 locks no patches, so a single plan is expected.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 184 Artifacts
- `.planning/phases/184-survivorship-modality-rates-and-distance-modality-interaction/184-CONTEXT.md` — Phase 184 locked decisions (corstr, eligibility frame, GEE spec)
- `.planning/phases/184-survivorship-modality-rates-and-distance-modality-interaction/184-01-SUMMARY.md` — Section 0–3 names: run_gee(), year_index_cat, exact-label reader, events RDS pointer
- `.planning/phases/184-survivorship-modality-rates-and-distance-modality-interaction/184-02-PLAN.md` — Full task spec for Sections 4–10; R184_OUTPUT workbook design; HiPerGator run + registration steps
- Phase 184 files are read-only (CLAUDE.md anti-pattern 7). Close-out is written in the Phase 185 folder.

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
- R/88 smoke test — run after R/184; pass condition is ALL CHECKS PASSED. Record the actual count in SUMMARY (982 was the Phase 182.1 baseline; the count may be higher if 184-02 added a SMOKE section).
- Registration — 184-02-PLAN.md Task 7 planned R/184 entries in R/39 and SCRIPT_INDEX.md, but Plan 02 was never formally closed. Phase 185 greps R/39, R/88 and R/SCRIPT_INDEX.md for R/184 and reports what is present. If anything is missing, record it in SUMMARY and hand it to Phase 189 (REG-01); Phase 185 does not register scripts.
- ROADMAP.md (~line 768) — change Phase 184 from `[~]` to `[x]` and remove the pending-checkpoint note.
- MILESTONES.md — keep the v3.11 "Known gap" line for history and append "Resolved by Phase 185 (YYYY-MM-DD)." Do not delete it.

</code_context>

<specifics>
## Specific Ideas

- Gate values (reproduction gate OR and CI bounds, global Wald) must be pasted verbatim from the HiPerGator console into 185-01-SUMMARY.md — not recomputed or paraphrased.
- The exact workbook filename (as printed by the run, e.g. a dated `modality_rate_model_<date>.xlsx`) must appear in SUMMARY so Phase 186's planner can use it as the `R184_OUTPUT` dated default without listing files.
- Provisional RATE-01 read target: "Annual rates (years 2+) — by modality x far". Confirm against the schema probe; the probe's text is what SUMMARY quotes and what Phase 186 uses (D-04).

</specifics>

<deferred>
## Deferred Ideas

- Fallback refit for any modality whose GEE fails to converge — not in Phase 185 (D-07). Decide after the run if needed.
- Registering R/184 if the registration grep finds it missing — Phase 189 (REG-01).

</deferred>

---

*Phase: 185-phase184-closeout-and-modality-rates*
*Context gathered: 2026-10-22*
