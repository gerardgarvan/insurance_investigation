# Phase 147: Read ADDRESS_ZIP5 and Retract Downstream Artefacts — Context

**Gathered:** 2026-08-17
**Status:** Ready for planning
**Source:** Pre-written spec `148-CONTEXT.md` (project root) + discuss-phase

<domain>
## Phase Boundary

Fix `get_zip9_at_date()` to read the `ADDRESS_ZIP5` column that has always been present in the
extract but was never read. The current code derives ZIP5 solely from `ADDRESS_ZIP9` and even
has an incorrect comment stating "No separate ADDRESS_ZIP5 column exists" (utils_address.R line 158).

Reading `ADDRESS_ZIP5` lifts ZIP5 coverage from 50.1% → 96.9% of address records (18,731
additional records gain a usable ZIP5). This makes `zip5_modal` fire for the first time
since Phase 139 and invalidates six documented conclusions in phases 145–147.

**Deliverables:**
1. `147-DISCOVERY.md` — column audit, 2×2 table, 12-row disagreement table, D-02 decision
2. Code fix in `R/utils/utils_address.R` + fixture update + R/88 passing locally
3. HiPerGator re-run: R/115, R/116, R/88 — archive pre-148 outputs, fill before/after table
4. Written retractions in affected phase docs + `data/reference/README.md` update

**Out of scope:** Centroid crosswalk implementation — deferred pending the `zip5_no_zip9` count
from Plan 3. (Numbering note: the pre-written spec at the project root is `148-CONTEXT.md` and the
centroid phase it references as "Phase 147" was never created. This phase is 147; its discovery
file is `147-DISCOVERY.md`. Consider moving `148-CONTEXT.md` into this phase directory as
`147-SPEC.md` so a 148-named file no longer describes a 147 phase.)

</domain>

<decisions>
## Implementation Decisions

### D-01 — Discover before touching code
- Print `names()` of the real address file and record every ZIP-ish column in `147-DISCOVERY.md`
  before modifying `get_zip9_at_date()`. The Phase 139 comment says "No separate ADDRESS_ZIP5
  column exists" — this phase proves it does, and documents the proof.
- Record the raw-column 2×2 (§0 of spec) alongside R/116's pre-approximation `match_type` table
  so the two are never conflated again.

### D-02 — ZIP5 source and precedence (discovery-gated, and the gate is in WAVE 1)
- Provisional coalesce order: `coalesce(normalize_zip5(ADDRESS_ZIP5), normalize_zip5(substr(ADDRESS_ZIP9, 1, 5)))`
  — `ADDRESS_ZIP5` wins the 12 prefix-disagreement rows.
- **Gate:** Plan 1 **Task 2** (a blocking HiPerGator checkpoint, wave 1) prints all 12
  disagreement rows and records them in `147-DISCOVERY.md` **before Plan 2 writes any code**. If a systematic pattern emerges (one transposed digit, a PO-box pairing,
  one source system), note it and confirm or flip the precedence there. 0.061% does not change
  any result, but the undocumented rule becomes an unanswerable question later.
- The D-02 decision and all 12 rows must appear in `147-DISCOVERY.md`.

### D-03 — Where the change goes
- Only `R/utils/utils_address.R`, at the point `get_zip9_at_date()` loads and normalizes the
  address frame. ZIP9 handling is unchanged; only ZIP5 gains a new source.
- Read both `ADDRESS_ZIP5` and `ADDRESS_ZIP9` with explicit `col_types` (character). Do not rely
  on the guesser — it typed `ADDRESS_ZIP9` as `dbl` on the one-row fixture.
- Add a missing-column guard (see canonical_refs spec §3 for exact error message).
- Remove/correct the incorrect comment at line 158 that says "No separate ADDRESS_ZIP5 column exists."
- The Phase 145 `stopifnot` on duplicate `(ID, query_date)` keys stays intact.

### D-04 — Plan wave structure (4 plans)
- **Plan 1 (Wave 1):** Discovery, and it INCLUDES a HiPerGator checkpoint. Task 1 writes
  `147-DISCOVERY.md` from the already-measured 2×2; Task 2 is a blocking human action printing
  `names()` of the real extract (the D-01 audit nobody has ever run) and the 12 disagreement
  rows; Task 3 records both and LOCKS D-02. The checkpoint sits here, not in Plan 3, because
  D-02 is discovery-gated: locking the precedence in Plan 2's code one wave before the
  inspection meant to confirm it would mean re-running R/115 and R/116 if the rows argue for
  flipping it.
- **Plan 2 (Wave 2, depends on Plan 1):** Code fix — `get_zip9_at_date()` updated, incorrect
  comment removed, fixture updated with all four 2×2 cells, `ADDRESS_ZIP5` test added, R/88 passes
  locally (parse checks only on Windows dev box).
- **Plan 3 (Wave 3, depends on Plan 2) — HUMAN-ACTION CHECKPOINT:** HiPerGator re-run —
  archive `*_pre148.*` outputs (by glob, not hardcoded names), run R/115 → R/116 → R/88 in that
  order, fill the before/after table. Record `zip5_no_zip9` (Tier 3's actual population). The
  12 disagreement rows are NOT re-printed here — Plan 1 Task 2 already did that.
- **Plan 4 (Wave 4, depends on Plan 3):** Retraction — annotate six locations (seven notes
  across five files), update `data/reference/README.md`, and correct the Branch C console note
  in `utils_address.R`. That last edit is to CODE, so `R/utils/utils_address.R` is declared in
  Plan 4's `files_modified` — it would otherwise be an undeclared write.

### D-05 — Retraction format
- Dated header note only. At the top of each affected section, add:
  `**[2026-08-17] Superseded by Phase 147 — see 147-DISCOVERY.md.** [one-line summary]`
- Preserve original text exactly. Do not delete, strike through, or rewrite.
- Six logical locations produce SEVEN notes across FIVE files: locations 3 and 4 each span two
  files (a document plus, respectively, the console note in `utils_address.R` and the README).
  Do not try to make the counts equal — they measure different things.
- Affected locations (all six from spec §1):
  1. Phase 145 `145-DISCOVERY.md` — D-02 diagnostic "0 rows have ZIP5 present and ZIP9 missing"
  2. Phase 145 `145-DISCOVERY.md` — Branch C cause "sentinel-nulled" → was unread column
  3. Phase 145 console note + `data/reference/README.md` — "`zip5_modal` fires zero rows, expected"
  4. Phase 146 `146-CONTEXT.md` §0 and README — "77.7% is a hard ceiling"
  5. Phase 146 §4 — "D-04 sentinel-ZIP lever, 157,472 rows" (phantom population)
  6. Phase 147 (this phase's own directory) §0 — "Centroid crosswalk resolves 0 encounters"

### D-06 — Re-run order and archiving
- Run R/115 first (it was delivered to Erin/Amy on old ZIP5). Archive existing workbook as
  `*_pre148.xlsx` before re-running.
- Run R/116 second. Archive existing `encounter_ses_index_20260817.{rds,xlsx}` as `*_pre148.*`.
- Run R/88 last.
- Expected: `zip9_observed` unchanged at 1,516,469; `none` unchanged at 158,699. If either
  moves, that is a defect in this change, not a finding.

### Claude's Discretion
- Exact wording of the retraction notes (beyond the format template above)
- Whether to add an inline comment in `get_zip9_at_date()` explaining the coalesce precedence
  decision and why `ADDRESS_ZIP5` wins (recommended: yes, reference D-02 and `147-DISCOVERY.md`)
- Exact fixture row count — spec requires all four 2×2 cells; exact patient IDs, dates,
  and address values are Claude's to choose

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary spec (read first)
- `148-CONTEXT.md` — Full phase spec: measurement (§0), what it invalidates (§1), planner rules
  (§2), the change (§3), re-measure protocol (§4), update targets (§5), acceptance criteria (§6),
  anti-patterns (§7), reporting requirements (§8). This is the authoritative source.

### Code to modify
- `R/utils/utils_address.R` — `get_zip9_at_date()` (lines 111–244): the load block (lines 115–134),
  the `mutate()` at lines 151–173 (specifically lines 153–162 where ZIP5 is derived). The
  incorrect comment at line 158 must be removed. The missing-column guard goes into the ID-check
  block (lines 138–140 area). Also read `normalize_zip5()` (line 46) and `normalize_zip5_raw()` (line 62).
- `R/utils/utils_address.R` — Branch C console note to remove (search for "sentinel-nulled"
  or "Branch C" — the comment in `approximate_zip9()` that states the wrong cause).

### Fixture to update
- `tests/fixtures/LDS_ADDRESS_HISTORY_Mailhot_V1.csv` — Currently one row, three columns, no
  `ADDRESS_ZIP5`. Must be extended to carry all four 2×2 cells from spec §0. Read before editing.

### Test files
- `tests/testthat/test-utils-address.R` — Existing tests for `get_zip9_at_date()`. A new test
  asserting a ZIP5-only record (ADDRESS_ZIP5 present, ADDRESS_ZIP9 absent) returns a non-NA ZIP5
  must be added here.

### Scripts to re-run
- `R/115_zip_stability_counts.R` — First re-run target. Archive output before running.
- `R/116_encounter_ses_index.R` — Second re-run target. Archive output before running.
- `R/88_smoke_test_comprehensive.R` — Final verification.

### Phase docs with conclusions to retract
- `.planning/phases/145-r116-fan-out-fix-and-ses-reference-gap-fill/145-DISCOVERY.md` — D-02
  diagnostic and Branch C note.
- `.planning/phases/146-acquire-and-stage-the-ses-reference-files-sdi-svi-adi/146-CONTEXT.md` —
  §0 (77.7% ceiling) and §4 (D-04 sentinel phantom).
- `data/reference/README.md` — 77.7% ceiling note + "`zip5_modal` zero rows" note.

### Prior phase context (for understanding what's locked)
- `.planning/phases/145-r116-fan-out-fix-and-ses-reference-gap-fill/145-CONTEXT.md` — D-01
  through D-04 decisions. The fan-out `stopifnot` stays.
- `.planning/phases/139-zip9-approximation/139-CONTEXT.md` (if it exists) or Phase 139 plan
  files — `zip5_modal` tier was built here and has never fired. After this phase it should fire.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `normalize_zip5(zip9_clean)` (line 46): strips non-digits, rejects non-5-char results. Already
  handles NA input. Use this on `ADDRESS_ZIP5` directly.
- `normalize_zip5_raw(zip, pad4)` (line 62): for bare ZIP5 strings. Still needed as fallback for
  the 291 ZIP9-only records.
- `is_sentinel_zip5()`: sentinel rejection stays in place, applied after coalesce.

### Established Patterns
- Column loading: `vroom::vroom(addr_path, col_types = vroom::cols(.default = "c"))` already
  loads everything as character. The `col_types` call does not need to change — `.default = "c"`
  already forces `ADDRESS_ZIP5` to character when the column exists.
- Missing-column guard pattern: existing `if (!"ID" %in% names(addr_raw))` block (line 138).
  Mirror this pattern for the `ADDRESS_ZIP5` + required columns guard.
- Test injection seam: `addr_full = NULL` parameter on `get_zip9_at_date()` (line 111). Fixture
  is passed via this seam — already works, just needs more rows.

### Integration Points
- `get_zip9_at_date()` is called by R/115 and R/116. Both will automatically use the new ZIP5
  source after the fix — no changes needed in those scripts.
- `approximate_zip9()` consumes `get_zip9_at_date()` output. Its `zip5_modal` tier (lines 483–515)
  requires a non-NA ZIP5 to build the lookup table. After this fix, it will receive one for
  18,731 previously-invisible records.

</code_context>

<specifics>
## Specific Ideas

- The 2×2 measurement from spec §0 (must appear in `147-DISCOVERY.md`):

  | ADDRESS_ZIP5 | ADDRESS_ZIP9 | records | share | |
  |---|---|---|---|---|
  | yes | yes | 19,741 | 49.3% | |
  | **yes** | **no** | **18,731** | **46.8%** | **invisible to current code** |
  | no | yes | 291 | 0.7% | ZIP5 recoverable from ZIP9 prefix |
  | no | no | 1,242 | 3.1% | genuinely unusable |
  | | | 40,005 | | |

- Before/after table to be filled in Plan 3 (from spec §4):

  | | pre-148 | post-148 |
  |---|---|---|
  | `zip9_observed` | 1,516,469 (77.7%) | _to measure_ |
  | `zip5_modal` | 0 | _to measure_ |
  | `zip5_centroid` | 0 | 0 (no crosswalk staged) |
  | `zip5_no_zip9` | 0 | _to measure — Tier 3's true population_ |
  | `no_zip5` | 275,528 (14.1%) | _to measure_ |
  | `none` | 158,699 (8.1%) | _must stay 158,699_ |
  | RUCA coverage | 77.7% | _to measure_ |
  | SDI coverage | 0% (not staged) | 0% |

- R/115 was delivered to Erin and Amy on the old ZIP5 — re-issuing it is part of this phase's
  output, not optional.
- Phase 147's own `§0` note must be added: "Centroid crosswalk resolves 0 encounters — Void.
  Its population is about to change after Phase 147 (this phase) re-runs."

</specifics>

<deferred>
## Deferred Ideas

> **[2026-08-17] Superseded by Phase 147 — see 147-DISCOVERY.md.** The "0 encounters"
> figure that motivated the centroid crosswalk scope is void: Tier 3's population
> (`zip5_no_zip9`) was 0 only because Tier 2 (`zip5_modal`) had no ZIP5 keys to match on.
> After the Phase 147 fix, the actual Tier 3 population is recorded in 147-DISCOVERY.md §4.
> Phase 147's centroid crosswalk scope depends on that new figure.

- Centroid crosswalk implementation — explicitly on hold until Plan 3 reveals `zip5_no_zip9`
  (Tier 3's actual population). If that count is negligible, the centroid crosswalk may not
  be worth pursuing. Decision deferred to Phase 147's original goal after re-run.
- Adjusting the `approximate_zip9()` early-exit logic for `n_to_approx == 0` — out of scope;
  the tier should work correctly now that ZIP5 is sourced properly.

</deferred>

---

*Phase: 147-read-address-zip5-retract-downstream-artefacts*
*Context gathered: 2026-08-17*
