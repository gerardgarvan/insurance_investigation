# Phase 194: Reference Manual Regeneration - Context

**Gathered:** 2026-11-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Regenerate REFERENCE_MANUAL.md (built by R/89_generate_reference_manual.R) so it
accurately documents every current script, utils module and config constant.
Documentation only: no change to analytic logic or outputs of any production script.

</domain>

<problems>
## Problems in the 2026-06-02 version

- Purpose / source() Deps / Inputs / Outputs are "Not documented" for every script
  (R/89 is not finding header metadata in the format it expects)
- Script list stops at R/99; R/100+ scripts (e.g. R/103, R/115, R/122, R/147) and
  newer utils (utils_address.R, utils_surveillance.R) are missing
- Decade grouping (00-09 ... 90-99) has no category for three-digit scripts
- Stale / inconsistent facts:
  - "8 utils modules" in prose, 10 in the table
  - DuckDB described as optional (all queries now go through DuckDB)
  - PCORNET_TABLES = 14 (the extract has 22 CDM tables)
  - module load R/4.4.2 (now R/4.5)
  - project path /blue/erin.mobley-hl.bcu/R (repo is
    /blue/erin.mobley-hl.bcu/insurance_investigation)
  - run order omits R/39_run_all_investigations.R
  - onboarding implies batch runs; pipeline is run interactively in an R session

</problems>

<decisions>
## Implementation Decisions

### Locked
- R/89 discovers scripts and utils via list.files() - no hardcoded script list
- "Key Functions" for utils derived from function definitions in each file
- Three-digit scripts get a stage grouping (by number range or a Stage header tag)
- Narrative sections (architecture, run order, config constants, onboarding)
  corrected against current R/00_config.R and the R/39 run order
- Config constant sizes computed from the live objects, not typed in
- **Header approach: (a) teach R/89 to read the dominant existing format.**
  Audit (194-01-AUDIT.md § Inventory) found 100% of production scripts are
  PARSEABLE or USABLE with the five-field banner already in place. No repo-wide
  header additions needed. Only R/89 itself changes.

### Open - decide before planning
*(empty — all pre-planning decisions resolved)*

### Claude's Discretion
- Optional "Analytic Manual cross-reference" column linking scripts to AM decision
  IDs (D-191-01..07, DEC-002, DEC-008, etc.)
- Exact markdown layout of regenerated tables

</decisions>

<verification>
## Done When

- Rscript R/89_generate_reference_manual.R runs cleanly
- No "Not documented" cells for production scripts
- Every R/*.R and R/utils/*.R file appears exactly once
- Constant sizes match length()/nrow() of the live objects
- R/88 smoke test still passes

</verification>

<deferred>
## Deferred Ideas

None yet.

</deferred>

---

*Phase: 194-reference-manual-regeneration*
*Context gathered: 2026-11-05 (manual entry, discuss-phase skipped)*
