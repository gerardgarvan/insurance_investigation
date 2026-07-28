# Phase 139: ZIP9 Approximation - Context

**Gathered:** 2026-07-28
**Status:** Ready for planning

<domain>
## Phase Boundary

A **ZIP9 approximation utility** that extends the Phase 137 address lookup infrastructure.
When `get_zip9_at_date()` returns a row with `ZIP9 = NA` (patient has a ZIP5 in their
address record but no valid 9-digit ZIP9), this phase delivers `approximate_zip9()` —
a function that fills in a best-guess ZIP9 by finding the modal ZIP9 for that ZIP5 across
all of `LDS_ADDRESS_HISTORY`.

**In scope:**
- A new function `approximate_zip9(result_tbl)` added to `R/utils/utils_address.R`
- It accepts the tibble produced by `get_zip9_at_date()` and returns the same 5-column
  schema with ZIP9 filled in and `match_type` updated for approximated rows
- Two new `match_type` values: `"zip5_modal"` (approximation succeeded) and
  `"zip5_only"` (ZIP5 exists but no ZIP9 could be found even in the full LDS file)
- Rows with `match_type = "none"` (no address record at all) are left as-is — no ZIP5
  anchor means no approximation is possible

**Out of scope:**
- Any SES index computation (ADI/SVI/SDI) — future phase
- Writing a validation script R/115 — function-only delivery in this phase
- Using an external ZIP5→ZIP9 crosswalk (USPS, HUD, Census) — cohort-internal modal only

</domain>

<decisions>
## Implementation Decisions

### Trigger condition
- **D-01:** Approximation applies whenever `ZIP9 = NA` in the `get_zip9_at_date()` result
  tibble, regardless of `match_type`. This covers the case where a patient has an address
  record (interval or most_recent_before match) but the `ADDRESS_ZIP9` field normalized to
  NA (ZIP5-only address).
- **D-02:** Rows with `match_type = "none"` (no address record at all) are excluded from
  approximation and remain `ZIP9 = NA`. No ZIP5 anchor → nothing to approximate from.

### Approximation method
- **D-03:** Approximation source: **modal ZIP9 from full `LDS_ADDRESS_HISTORY`** — for
  each distinct ZIP5 in the file, find the most frequent valid (non-NA) ZIP9 across all
  records (all patients, all address rows).
- **D-04:** Tie-break when multiple ZIP9s share the same modal frequency for a ZIP5:
  select the one with the most recent `ADDRESS_PERIOD_START`. Consistent with Phase 137
  D-04 (same tie-break used in `get_zip9_at_date()`).
- **D-05:** The ZIP5→modal-ZIP9 lookup is built from the **full** `LDS_ADDRESS_HISTORY`,
  not just the patients in the input tibble. Larger sample = more stable modal estimate.

### Output form
- **D-06:** Delivered as `approximate_zip9(result_tbl)` added to `R/utils/utils_address.R`.
  Returns the same 5-column tibble schema (`ID`, `query_date`, `ZIP9`, `ZIP5`,
  `match_type`) so callers can chain:
  ```r
  get_zip9_at_date(ids, dates) |> approximate_zip9()
  ```
- **D-07:** New `match_type` values introduced by this function:
  - `"zip5_modal"` — ZIP9 was successfully approximated from the modal ZIP9 for this ZIP5
    across LDS_ADDRESS_HISTORY
  - `"zip5_only"` — ZIP5 exists but ALL records in LDS_ADDRESS_HISTORY for this ZIP5 have
    no valid ZIP9 (every ADDRESS_ZIP9 normalizes to NA); ZIP9 remains NA
- **D-08:** Probe-first gate: if `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` is absent from
  `CONFIG$data_dir`, log a console warning and return the input tibble unchanged (no crash,
  no `stop()`). Consistent with Phase 137 D-08 and R/106's gate.

### Claude's Discretion
- Exact internal variable names within `approximate_zip9()`
- Whether to cache the ZIP5→modal-ZIP9 lookup table within the function call or recompute
  each time (load on demand — consistent with D-06 from Phase 137)
- Whether to log diagnostic counts (rows approximated, rows still NA, rows unchanged) to
  console as a side effect of the function call, or leave that to callers

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Core source file (extend this)
- `R/utils/utils_address.R` — Add `approximate_zip9()` here. Read the full file to
  understand existing function signatures, coding style, and the 5-column tibble contract.

### Phase 137 context (locked decisions this phase extends)
- `.planning/phases/137-read-zip9-temporal-assignment/137-CONTEXT.md` — D-01 through
  D-11 define `get_zip9_at_date()`'s contract. `approximate_zip9()` must be a compatible
  extension (same tibble schema, same match_type string conventions).

### Reference patterns for probe-first gate and modal tie-break
- `R/106_zip_change_frequency.R` — Probe-first gate pattern (lines ~130-140) and modal
  ZIP9 / tie-break logic (lines ~595-615). The same modal + recency tie-break logic used
  there should be replicated in `approximate_zip9()`.
- `R/114_zip9_temporal_lookup.R` — Probe-first gate pattern for `LDS_ADDRESS_HISTORY`.

No external specs — requirements fully captured in decisions above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `normalize_zip9()`, `normalize_zip5()`, `normalize_zip5_raw()` in `R/utils/utils_address.R`
  — use these inside `approximate_zip9()` for ZIP normalization; do not duplicate.
- Modal + recency tie-break pattern: `R/106_zip_change_frequency.R` lines ~595-615 —
  `group_by(zip5) |> count(zip9) |> slice_max(n) |> slice_max(ADDRESS_PERIOD_START)`.
  Replicate this logic for building the ZIP5→modal-ZIP9 lookup table.

### Established Patterns
- Probe-first gate: check file existence before loading, log warning and return gracefully
  if absent. See R/106 and R/114.
- Load on demand: `approximate_zip9()` loads `LDS_ADDRESS_HISTORY` fresh each call (no
  caching at the function level). Consistent with Phase 137 D-06.
- `match_type` as a string column with documented values: "interval", "most_recent_before",
  "none" (Phase 137). This phase extends with "zip5_modal" and "zip5_only".

### Integration Points
- Callers chain: `get_zip9_at_date(ids, dates) |> approximate_zip9()`
- `R/00_config.R` auto-loads `utils_address.R` — `approximate_zip9()` is automatically
  available to all scripts once added to that file.

</code_context>

<specifics>
## Specific Ideas

No specific references or "I want it like X" moments from discussion — standard approach.

</specifics>

<deferred>
## Deferred Ideas

- R/115 validation script — considered but not included in this phase's scope. If a
  diagnostics sheet (rows approximated, rows zip5_only, rows still none) is needed, scope
  it as a future investigation script.
- External crosswalk (USPS/HUD/Census ZIP5→ZIP9) — deferred; cohort-internal modal is
  sufficient for now.
- ADI/SVI/SDI SES index computation — explicitly future phase.

</deferred>

---

*Phase: 139-zip9-approximation*
*Context gathered: 2026-07-28*
