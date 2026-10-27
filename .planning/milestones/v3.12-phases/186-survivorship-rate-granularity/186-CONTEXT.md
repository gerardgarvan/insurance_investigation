# Phase 186: Survivorship Rate Granularity - Context

**Gathered:** 2026-10-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Read the annual (years 2+) and half-year/biannual (years 2+) rate blocks from the Phase 185 pinned R/184 workbook by exact label, stack them into one team-facing table (modality × far × window), and write the result to a dated xlsx. No new patient-year computation. No changes to R/184. All-years blocks go on a secondary sheet. KEY sheet leftmost; UF colours applied.

</domain>

<decisions>
## Implementation Decisions

### D-186-01: Biannual Definition (RATE-02)

- **D-01:** **Biannual = every 6 months (twice yearly).** Reuse the R/184 half-year output — no new follow-up window, no new patient-year calculation.
- **D-02:** This decision is **provisional** pending team confirmation at the next meeting. If the team intends "biannual" to mean every 2 years (biennial), that is a new phase with a new patient-year calculation — not a revision of Phase 186. Phase 186 proceeds on the 6-month interpretation now.
- **Decision owner:** Gerard/team. **Date recorded:** 2026-10-22.

### R/186 Script Architecture (RATE-03)

- **D-03:** New standalone script `R/186_survivorship_rate_granularity.R`. R/184 is not touched — it is executed, versioned v3.11 code; editing it violates CLAUDE.md anti-pattern 7.
- **D-04:** R/186 pins `R184_OUTPUT` to the exact dated workbook filename recorded in `185-01-SUMMARY.md` (not inferred from R/184 source or file listing). Records path and pinned TRUE/FALSE in KEY sheet. Stops with an informative error if the file is missing.
- **D-05:** R/186 reads two blocks from the Rates sheet using the exact-label reader pattern (R/183 lines 548–562, copied verbatim into R/184 lines 266–288):
  - **Annual (years 2+)** — section header from `185_schema_<date>.md`; one row per modality × far level
  - **Half-year / biannual (years 2+)** — section header from `185_schema_<date>.md`; same grain
  - Header strings are taken verbatim from the 185 schema probe — not from this CONTEXT, not from R/184 source. The probe wins if any text differs (watch for em dash —).
- **D-06:** Suppressed values from R/184 (e.g., `"<11"`) are carried into the Phase 186 stacked table **as-is** — R/186 never un-suppresses or recomputes them. R/186 then applies a **complementary suppression pass** on the stacked team table (it can only add suppression, never remove). The pass covers: (a) within each block across `far` levels and against any total row; (b) across windows, because half-year periods nest inside the annual period. Whether R/184 already applies complementary suppression within each block is a code question (grep R/184 for the logic and cite the lines in the plan); regardless, the R/186 pass is additive and safe. A test fixture showing a back-calculable case gets suppressed is required in Task 0's acceptance criteria.
- **D-07:** Output table grain: one row per modality × far × window (annual / biannual). Columns: `modality`, `far`, `window`, `patients`, `patient_years`, `events`, `rate`. This is the primary (years 2+) sheet.
- **D-08:** All-years blocks (annual all-years, half-year all-years) go on a secondary sheet with the same grain and columns.
- **D-09:** Rate unit — the planner **must** check the 185 schema probe to confirm whether R/184 expresses rates as per patient-year or per patient-half-year for the half-year blocks. The unit must be stated explicitly in a `rate_unit` column or in the KEY sheet note. Do not rescale either window unless the probe shows the two windows use different units; if they differ, record the conversion formula in a revision to this CONTEXT before writing any code.
- **D-10:** KEY sheet leftmost. UF blue (#0021A5) applied to header rows; UF orange (#FA4616) for accent rows (e.g., totals or secondary headers). Same convention as R/184.

### Claude's Discretion

- Script section structure within R/186 (e.g., SECTION 0 pin block, SECTION 1 read, SECTION 2 stack, SECTION 3 write) — Claude decides.
- Whether to write a probe call on the output workbook for downstream phases — Claude decides (useful but not required by RATE-02/03).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 185 Artifacts
- `.planning/phases/185-phase184-closeout-and-modality-rates/185-CONTEXT.md` — Phase 185 locked decisions; D-01 through D-11 including pin pattern, exact-label reader, em dash warning, SUMMARY scope
- `185-01-SUMMARY.md` (in phase 185 dir, written during Phase 185 execution) — Contains the exact dated workbook filename for `R184_OUTPUT` default and the exact Rates sheet section header text. **Task 0 for Phase 186 must cite this file for the default path.**

### Schema Probe (written during Phase 185 execution)
- `.planning/schemas/185_schema_<date>.md` — Sheet names, section headers, row labels from the actual R/184 workbook. **Task 0 must cite this file.** The half-year section header string and rate unit are read from here — not from R/184 source, not from this CONTEXT.

### R/184 Script (read-only reference)
- `R/184_modality_rate_model.R` — Lines 1274–1303: Rates sheet section headers; line 1463: saveWorkbook. Do not edit.

### Exact-Label Reader Pattern
- `R/184_modality_rate_model.R` lines 266–288 (copied from R/183 lines 548–562) — Copy this verbatim into R/186 for reading blocks from the pinned workbook.

### Requirements
- `.planning/REQUIREMENTS.md` — RATE-02, RATE-03

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Exact-label reader: `R/184_modality_rate_model.R` lines 266–288 — copy verbatim; checks one match or stops with available labels printed.
- Pin pattern: R/184 SECTION 0 lines 217–219 — `pin("R184_OUTPUT", "output/...")` with `pinned TRUE/FALSE` logged to KEY.
- `sup()` / `rate_or_dash()` — already in R/184; not needed in R/186 (carry suppressed strings as-is from the workbook).
- `R/utils/utils_schema_probe.R` — `probe_inputs()` for optional output workbook probe.

### Established Patterns
- Script is a reader + stacker only. No modeling, no patient-level computation. Structure mirrors R/184 SECTION 0 (pin) → SECTION 1 (read) → SECTION 2 (transform/stack) → SECTION 3 (write workbook).
- `here()` for all paths; no `setwd()`.

### Integration Points
- R/186 output workbook is the input for Phase 188 (echo rate since anthracycline) if Phase 188 needs the biannual window rates. Pin `R186_OUTPUT` at Phase 186 close so Phase 188 can read it.

</code_context>

<specifics>
## Specific Requirements

- "Biannual" = twice yearly (6-month windows). If team feedback changes this to "biennial" (every 2 years), open a new phase — do not revise R/186.
- R/184 half-year blocks are labeled something like "Half-year rates (years 2+)" and "Half-year rates (all years)" on the Rates sheet — exact strings come from the 185 schema probe, not from memory.
- Rate unit ambiguity: check the probe and settle this before writing code. If units are per patient-half-year rather than per patient-year, note it in KEY so the team interprets the table correctly.
- Annual values in the output must match the Phase 185 pinned workbook to the last digit (carried verbatim, not recomputed).

</specifics>

<deferred>
## Deferred Ideas

- If team confirms "biannual" means every 2 years (biennial), open a new phase with a new patient-year window calculation — Phase 186 is not revised.
- Anthracycline as a covariate in modality rate models (parked per STATE.md, candidate for v3.13).

</deferred>

---

*Phase: 186-survivorship-rate-granularity*
*Context gathered: 2026-10-22*
