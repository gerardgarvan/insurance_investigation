# Phase 136: Confirm Loose Ends - Context

**Gathered:** 2026-07-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Resolve the code review's two flagged unknowns with a documented finding each — and a code
fix if CONFIRM-02 finds real data loss. No new features, no architectural rewrites.

</domain>

<decisions>
## Implementation Decisions

### CONFIRM-01: Missing Function Definitions

- **D-01:** Extract `clean_multi_value()` and `union_field()` into a new `R/utils_format.R`
  module. Update `R/52_gantt_v2_export.R`, `R/101_gantt_lifespan_collapse.R`, and
  `R/104_gantt_entire_history.R` to `source()` from `utils_format.R` instead of carrying
  inline copies. The three-way verbatim duplication is eliminated; the canonical location
  becomes `utils_format.R`.
- **D-02:** `suppress_small()` stays inline in `R/106_zip_change_frequency.R` — it is only
  called within that script (3 call sites, all in R/106). Moving it to a utils module would
  add indirection without benefit.
- **D-03:** The CONFIRM-01 finding (canonical locations, load-path confirmation) is recorded
  by marking `CONFIRM-01` as resolved in `REQUIREMENTS.md` with a one-line finding note.

### CONFIRM-02: date_range_max Bound

- **D-04:** If investigation confirms Apr–Sep 2025 encounters/deaths are being dropped,
  change `CONFIG$analysis$date_range_max` from `as.Date("2025-03-31")` to `Sys.Date()`.
  Rationale: this upper bound is intended to catch gross outliers and sentinel dates, not to
  enforce the data-source cutoff (which is governed by the extract itself). Making it dynamic
  prevents future extracts from requiring a config change.
- **D-05:** Add a comment at the `date_range_max` definition in `R/00_config.R` (and at its
  use in `R/01`) explaining the intent: upper bound catches future-year sentinels; data
  source cutoff is enforced by the extract, not this config value.
- **D-06:** If investigation finds no data is actually being dropped (e.g., R/01's validation
  only flags and doesn't filter, or the logic path doesn't apply to the affected tables),
  document that finding in `REQUIREMENTS.md` instead and leave the value unchanged.
- **D-07:** The CONFIRM-02 finding is recorded by marking `CONFIRM-02` as resolved in
  `REQUIREMENTS.md` with a one-line note on whether data was being dropped and what changed.

### Claude's Discretion

- Structure of `utils_format.R` (roxygen2 header style, internal vs exported, parameter
  names) — follow existing utils module conventions in the repo.
- Whether to add a smoke-test call that verifies `utils_format.R` loads correctly from every
  consumer — use judgment based on test infrastructure already in place.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Function definitions (CONFIRM-01)
- `R/52_gantt_v2_export.R` lines 772–815 — canonical (origin) definitions of
  `clean_multi_value()` and `union_field()`; consumers R/101 and R/104 copied verbatim from here
- `R/101_gantt_lifespan_collapse.R` lines 102–131 — inline copies + call sites
- `R/104_gantt_entire_history.R` lines 80–158 — inline copies + call sites
- `R/106_zip_change_frequency.R` lines 191–196 — inline `suppress_small()` definition and
  lines 344, 347, 388 — call sites (stays here)

### Date validation (CONFIRM-02)
- `R/00_config.R` lines 2815–2816 — `date_range_min` / `date_range_max` definitions
- `R/01_load_pcornet_data.R` lines 581–594 — date validation logic that reads the config
  bounds and flags out-of-range dates

### Requirements
- `.planning/REQUIREMENTS.md` §"Confirm Loose Ends (CONFIRM)" — CONFIRM-01 and CONFIRM-02
  acceptance criteria; update these entries to resolved once findings are documented

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `R/utils_*.R` modules — existing pattern for shared utility functions; `utils_format.R`
  should follow the same header/source() convention as `utils_cancer.R`, `utils_payer.R`,
  etc.
- `R/52_gantt_v2_export.R:772` — origin definition of `clean_multi_value()`; treat this as
  the authoritative implementation when creating `utils_format.R`

### Established Patterns
- All utils modules are `source()`d explicitly at the top of each consumer script
- Existing utils have roxygen-style block comments above each function
- In-place modifications to `R/00_config.R` are hardened (per PATTERN-F); `Sys.Date()`
  change is a safe assignment, not a regex rewrite

### Integration Points
- `R/52`, `R/101`, `R/104`: remove inline definitions, add `source(here("R/utils_format.R"))`
  at their respective source-block headers
- `R/00_config.R`: single-line change to `date_range_max`
- `R/01`: add explanatory comment alongside the validation block

</code_context>

<specifics>
## Specific Ideas

- No specific UI or UX requirements — this is a pure investigation + code cleanup phase.
- The `utils_format.R` name is the user's accepted choice; do not rename to `utils_string.R`
  or similar without re-asking.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 136-confirm-loose-ends*
*Context gathered: 2026-07-25*
