# Phase 130: Registration, Smoke Test, and HiPerGator Runtime - Context

**Gathered:** 2026-07-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire the completed DoI layer into the pipeline's discovery/validation infrastructure and gate its correctness behind a **real, logged HiPerGator runtime pass** on the actual DIAGNOSIS table. This is the **v3.3 definition-of-done**.

**In scope:**
- `R/39_run_all_investigations.R`: register **both** `R/111_doi_classification.R` and `R/112_doi_attribution_report.R` in the `investigation_scripts` vector (dependency order), and add `doi_attribution_report.xlsx` to `expected_xlsx`.
- `R/SCRIPT_INDEX.md`: add two rows to the "Post-Renumber Investigations (100+)" table — R/111 (classification) and R/112 (attribution).
- `R/88_smoke_test_comprehensive.R`: a new DoI section (slot **15w**, following the 15p–15v convention) with structural checks + an IS_LOCAL-gated real-data runtime block, and the running `[N/N]` counter renumbered accordingly.
- HiPerGator runtime confirmation of the DoI layer, executed by the user on the cluster, with logged DoI category counts recorded verbatim in the phase transition/completion notes (the DoD gate).

**Out of scope:**
- Any change to R/111 or R/112 analytic logic (Phases 128/129 own that; this phase is registration + validation only).
- A separate externally-shareable/suppressed workbook (deferred per 129).
- Roadmap prose cleanup of the stale "[30/30]" section number and the "R/111_doi_attribution_report.R" naming slip (governed by decisions here, not by editing ROADMAP prose).

</domain>

<decisions>
## Implementation Decisions

### HiPerGator Runtime Gate (the DoD crux)
- **D-01:** Structure the runtime gate as a **human-verify checkpoint**. Execution writes and **structurally verifies** all code (R/39 edits, SCRIPT_INDEX rows, R/88 section 15w) on Windows — that is the machine-verifiable deliverable. The real-data runtime pass then becomes a **HUMAN-UAT item**: the user runs the smoke test / R/39 on HiPerGator against the real DIAGNOSIS table, and pastes back the logged DoI category counts.
- **D-01a:** The logged DoI category counts (with the clinical-plausibility expectation: **RA dominant; NMO and pemphigus rare**) must be **recorded verbatim in the phase transition/completion notes** — this satisfies DOI-QA-03 and explicitly **resolves the PROJECT.md "Dual-environment verification … ⚠️ Revisit (Phase 126 attested-by-prose only)" flag** with a real log rather than prose attestation. A structural-only pass is insufficient for phase-level DoD; the phase may close with the runtime tracked as a HUMAN-UAT until the user confirms.

### R/88 Smoke-Test Section
- **D-02:** New section slot is **15w** (the roadmap's "Section [30/30]" is **stale** — R/88 already runs to `[43/43]` with lettered sub-sections 15p–15v for recent phases). Bump the running `[N/N]` counter to match. Include the **IS_LOCAL-gated runtime block** (mirroring the established gate patterns: 15p L2301-2315, 15s L2570-2573, 15t L2707 fixture-runtime).
- **D-03:** Validate **both** grains: R/111's `.rds` artifacts (`doi_encounters.rds`, `doi_patients.rds` — existence + column validation) **and** R/112's `doi_attribution_report.xlsx` (existence + expected sheets/columns). Must include the **mutual-exclusivity hard-stop** assertion (DOI_CODE_MAP keys vs `CANCER_SITE_MAP` / `ICD9_CANCER_SITE_MAP` — zero key-collision tolerance) plus `DOI_CODE_MAP` existence & length ≥ 20, `is_doi_code()` / `classify_doi_codes()` functional spot-checks, and `utils_doi.R` + `R/111` + `R/112` file existence.
- **D-03a (Claude's Discretion):** The **exact final check list** is delegated to the planner/executor — mirror Section **15v**'s structure (~13–14 checks). The must-include items in D-03 are the floor, not the ceiling.

### R/39 + SCRIPT_INDEX Registration
- **D-04:** Register **both** scripts in `investigation_scripts`, **R/111 before R/112** (R/111 emits the `.rds` that R/112 consumes — dependency order is mandatory so an end-to-end R/39 run produces R/112's inputs first).
- **D-05:** Add **only** `doi_attribution_report.xlsx` to `expected_xlsx` (R/111 emits `.rds` only — it has no xlsx output, so it does not belong in the xlsx pre-render check).
- **D-06:** Two new SCRIPT_INDEX rows in the "Post-Renumber Investigations (100+)" table (currently ends at R/110): R/111 = DoI classification (.rds producer), R/112 = DoI attribution (4-sheet xlsx). Descriptions must use co-occurrence language and name the correct roles — **R/111 = classification, R/112 = attribution** (corrects the roadmap naming slip, per 129 D-04).

### Fixture-Based Local Confidence
- **D-07:** Local smoke checks against the Phase-127 DoI fixtures (one ICD-9 + one ICD-10 DoI patient, DOI-QA-04) assert **schema-validity + non-empty output + three-state flag present** — NOT hardcoded exact hit-count numbers. Exact DoI category counts are reserved for the **HiPerGator runtime log** on real data (D-01a). Rationale: robust to fixture edits; the real-data counts are the ones that carry clinical meaning.

### Claude's Discretion
- Exact final R/88 15w check list and wording (mirror 15v) — D-03a.
- Exact `investigation_scripts` vector position and inline comment wording for R/111/R/112 (as long as R/111 precedes R/112) — D-04.
- SCRIPT_INDEX row prose (as long as roles are correct per D-06).
- Whether the HUMAN-UAT runtime block is invoked via `R/88` alone or `R/39` end-to-end on the cluster — either is acceptable as long as real DIAGNOSIS counts are logged (D-01a).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative requirements & cross-phase decisions
- `.planning/REQUIREMENTS.md` — **DOI-QA-01** (R/39 registration + SCRIPT_INDEX row), **DOI-QA-02** (R/88 DoI section incl. mutual-exclusivity hard-stop), **DOI-QA-03** (logged HiPerGator runtime = DoD gate). DOI-QA-04 already Complete (Phase 127 fixtures).
- `.planning/ROADMAP.md` §"Phase 130" — design constraints + success criteria. **NOTE two stale items:** the "Section [30/30]" number (actual R/88 runs to `[43/43]`; new slot is 15w — D-02) and the "R/111_doi_attribution_report.R" naming (R/111 = classification, R/112 = attribution — D-06).
- `.planning/phases/129-attribution-linkage-and-output/129-CONTEXT.md` — **D-04** (R/112 attribution / R/111 classification naming correction), **D-01** (raw counts / no suppress_small — smoke checks must NOT expect suppression).
- `.planning/phases/127-code-set-and-infrastructure-centralization/127-CONTEXT.md` — DOI_CODE_MAP structure, mutual-exclusivity rationale, D-07 raw counts.
- `.planning/phases/128-doi-classification/128-01-SUMMARY.md` — `doi_encounters.rds` columns: `ID, ENCOUNTERID, DX_DATE, doi_code, doi_category, paraneoplastic_flag, in_hl_cohort`.
- `.planning/phases/128-doi-classification/128-02-SUMMARY.md` — `doi_patients.rds` columns: `ID, has_any_doi, doi_categories, doi_first_date, doi_last_date, n_doi_encounters, in_hl_cohort`.
- `.planning/phases/129-attribution-linkage-and-output/129-01-SUMMARY.md` + `129-02-SUMMARY.md` — `doi_attribution_report.xlsx` 4-sheet structure (Patient Prevalence, Encounter Co-occurrence, Drug×DoI Summary, Metadata) for the R/88 xlsx validation.

### Code to modify (the three registration targets)
- `R/39_run_all_investigations.R` — `investigation_scripts` vector (L176-197, add R/111 then R/112); `expected_xlsx` (L276-287, add `doi_attribution_report.xlsx`).
- `R/SCRIPT_INDEX.md` — "Post-Renumber Investigations (100+)" table (§L140; table body ends at R/110, L156); summary tally line L209.
- `R/88_smoke_test_comprehensive.R` — add section **15w** after 15v; the `[N/N]` running counter (last is `[43/43]`, see L4239) must be renumbered; SUMMARY section (~L4356) SMOKE-line list (L4482-4488) gets a new `SMOKE-130-01` entry.

### Code to read/reuse (patterns)
- `R/88_smoke_test_comprehensive.R` §15t (L2598-2708) — closest template: STRUCTURAL greps pass locally + `if (IS_LOCAL)` fixture-runtime check; §15p (L2301-2315) & §15s (L2570-2573) — `if (!IS_LOCAL && file.exists(...))` HiPerGator-only real-data gate; §15v (L~4... "SMOKE-124-01") — the ~13-check pattern to mirror (D-03a); Section 32/33 (L4151/L4232) — DuckDB + fixture-schema local validation idioms; ENV-01 (L1237-1252) — `IS_LOCAL` flag definition.
- `R/111_doi_classification.R` — classification producer (writes the two `.rds`); confirm output paths/columns for the R/88 checks.
- `R/112_doi_attribution_report.R` — attribution producer (writes `doi_attribution_report.xlsx`); confirm sheet names/columns for the R/88 xlsx check.
- `R/00_config.R` — `DOI_CODE_MAP` (Section 4c), `CANCER_SITE_MAP` / `ICD9_CANCER_SITE_MAP` (for the no-overlap assertion), `IS_LOCAL` flag, `ICD_CODES`.
- `R/utils/utils_doi.R` — `is_doi_code()`, `classify_doi_codes()` (functional spot-check targets).
- Recent R/39 comment style for registered investigations (L190-196) — mirror for the R/111/R/112 comment lines.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Established R/88 IS_LOCAL-gate patterns (D-02 refs) — three variants: structural-only, `if (!IS_LOCAL && file.exists())` HiPerGator real-data, and `if (IS_LOCAL)` fixture-runtime. Section 15w picks from these per D-03/D-07.
- The `check(<label>, <predicate>)` helper drives every R/88 check and the pass/fail tally — reuse verbatim.
- R/39 `run_script()` loop + `results` accumulator — R/111/R/112 slot straight into the existing `investigation_scripts` vector.

### Established Patterns
- Recent phases append a lettered sub-section to Section 15 (15p…15v) + bump the `[N/N]` counter + add a `SMOKE-<phase>-01` line to the SUMMARY block. Section 15w follows identically.
- One-off diagnostics (R/107–R/110) are deliberately NOT wired into R/39; production investigations (R/100–R/106) ARE. R/111/R/112 are production → wired in (D-04).
- Dual-environment: structural grep/parse gates locally, real-data runtime confirmed on HiPerGator (the decision this phase finally backs with a log — D-01a).

### Integration Points
- Inputs already produced: `doi_encounters.rds`, `doi_patients.rds` (R/111), `doi_attribution_report.xlsx` (R/112).
- Modifies: R/39, R/SCRIPT_INDEX.md, R/88 (registration/validation only — no analytic-logic changes).
- DoD hand-off: the HiPerGator runtime log (HUMAN-UAT) closes v3.3.

</code_context>

<specifics>
## Specific Ideas

- The roadmap for Phase 130 carries two stale references that MUST be corrected in implementation, not copied: "Section [30/30]" (→ 15w, counter now past 43) and "R/111_doi_attribution_report.R" (→ R/111 classification, R/112 attribution). Both are documented above (D-02, D-06) so downstream agents don't propagate them.
- The clinical-plausibility expectation for the runtime log: **RA dominant; NMO and pemphigus rare**. This is the SME sanity signal that makes the logged counts meaningful, not just a green checkmark.
- The mutual-exclusivity hard-stop (DoI keys vs cancer-map keys) is the single most important smoke assertion — it is the guardrail that keeps the DoI layer from silently double-counting oncology codes.

</specifics>

<deferred>
## Deferred Ideas

- **Roadmap prose cleanup** (the "[30/30]" and "R/111_doi_attribution_report.R" wording) — governed by decisions here; ROADMAP prose left as-is intentionally.
- **Externally-shareable suppressed workbook** — deferred from Phase 129; produced manually before sharing per the internal-only note.

None — discussion stayed within the registration + validation + runtime-gate boundary.

</deferred>

---

*Phase: 130-registration-smoke-test-and-hipergator-runtime*
*Context gathered: 2026-07-16*
