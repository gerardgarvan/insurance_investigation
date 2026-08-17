# Phase 145: R/116 Fan-Out Fix and SES Reference Gap Fill — Context

**Gathered:** 2026-08-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Four deliverables, all arising from the Phase 144 HiPerGator run observations:

1. **Fan-out fix verification** — The code fix is already committed (commit `0364c89`):
   `get_zip9_at_date()` now uses `distinct(ID, query_date)` before the `anti_join`, adds
   a `stopifnot` asserting no duplicate `(ID, query_date)` keys on return, and R/116 now
   declares `relationship = "many-to-one"` with its row-count assertion anchored to
   `encounters_raw`. Phase 145 verifies this on HiPerGator: the corrected R/116 run should
   produce the same number of output rows as input encounters (no fan-out).

2. **Corrected RDS and summary workbook** — After HiPerGator verification, regenerate
   `output/encounter_ses_index_YYYYMMDD.rds` and `output/encounter_ses_index_summary_YYYYMMDD.xlsx`
   with the fixed code. The old (inflated) output files should be replaced.

3. **ZIP5-modal tier diagnosis** — Phase 144 observed `zip5_modal` firing zero rows in the
   `zip9_source` breakdown. This phase investigates the cause: read the code path statically,
   then observe the HiPerGator run's `zip9_source` breakdown to determine whether the zero is
   a code bug or a data characteristic. The plan includes a conditional: if a bug is found,
   fix it; if it's data-driven (all non-direct-match encounters have `match_type == "none"`),
   document it.

4. **SES reference column contracts** — Add a section to `data/reference/README.md` for each
   of the three absent index files (SDI, SVI, ADI), documenting expected file path, expected
   column names, join key, and how R/116's probe gate interprets them. RUCA is already present
   and working, so it does not need a new section.

**In scope:**
- Static code analysis of the `approximate_zip9()` → `zip5_modal` path
- HiPerGator verification run of R/116 (blocking checkpoint — requires the user to run
  `Rscript R/116_encounter_ses_index.R` and paste the console output)
- Regeneration of corrected output files
- `data/reference/README.md` update: SDI, SVI, ADI sections
- A bug fix in `utils_address.R` or R/116 IFF the diagnosis finds one

**Out of scope:**
- Acquiring the SDI, SVI, or ADI reference files themselves — documentation only
- Activating Tier 3 centroid (still waiting on licensed ZIP+4 source, per D-01 from Phase 144)
- Patient-level SES rollup, HL-cohort filtering, or any modification to `hl_cohort.csv`
- Modifying `get_zip9_at_date()` beyond what was already committed in `0364c89`

</domain>

<decisions>
## Implementation Decisions

### Fan-out fix status
- **D-01:** The fan-out code fix is **already committed** (commit `0364c89`). Phase 145 does
  NOT re-implement it. The plan's Task 1 is a code audit confirming the fix is correct
  (reading `get_zip9_at_date()` and R/116 SECTION 5), followed by a HiPerGator checkpoint
  that confirms row counts match.

### ZIP5-modal investigation approach
- **D-02:** Scope is **investigate first, then decide**. Phase 145 includes a static code-read
  step that traces whether there is a code path that prevents `zip5_modal` from firing even
  when encounters with `match_type == "interval"` or `"most_recent_before"` have `ZIP9 = NA`.
  After the HiPerGator checkpoint reports the `zip9_source` breakdown, if `zip5_modal == 0`
  persists, Phase 145 determines the cause:
  - If **data-driven** (all unresolved encounters truly have `match_type == "none"`): add a
    console note and a `data/reference/README.md` entry explaining this is expected and not
    a code defect. No code change.
  - If **code bug** (a logic error prevents the modal tier from firing for legitimately
    resolvable rows): fix it in `utils_address.R` or R/116 (whichever is the defect site)
    and re-run the HiPerGator checkpoint.
  **Do not assume a direction before the code read + HiPerGator evidence.**

### SES reference documentation location
- **D-03:** Document in **`data/reference/README.md`** (not per-file README_*.txt). The
  existing README already has the ADI crosswalk schema from Phase 140. Add three new
  sections — one each for SDI, SVI, and ADI (update or replace the Phase 140 ADI entry if
  it is already there, to avoid duplication):
  - **SDI (Robert Graham Center):** path = `data/reference/zip5_sdi_reference.csv`,
    required columns = `ZIP5` (5-digit char), `SDI_score` (numeric 0–100), join key = ZIP5.
  - **SVI (CDC Social Vulnerability Index 2020):** path = `data/reference/svi_2020_us_by_zcta.csv`,
    required columns = `ZCTA` (5-digit char), `RPL_THEMES` (composite percentile 0–1; CDC
    encodes missing as −999 → filter to `>= 0`), join key = ZIP5 (ZCTA ≈ ZIP5, approximate).
  - **ADI (Neighborhood Atlas):** path = `data/reference/neighborhood_atlas_block_group_crosswalk.csv`,
    required columns = one of `ZIP9/zip9/ADDRESS_ZIP9/zip9_norm/GEOID9/ZIP_PLUS4` (any
    accepted) and one of `adi_natrank/ADI_NATRANK/natrank`, join key = ZIP9. Acquisition
    still pending (P-03a from Phase 140 — see Phase 140 D-02 decision).

### HiPerGator checkpoint placement
- **D-04:** The plan includes **one blocking HiPerGator checkpoint** after the code audit
  (Task 1) is done. At the checkpoint, the user runs R/116 and pastes the full console
  output. The plan then branches on the `zip9_source` breakdown (D-02 decision tree). If
  a fix is needed, the checkpoint is the gate before regenerating final outputs.

### Claude's Discretion
- Whether the ZIP5-modal diagnosis produces an inline code comment, a `README.md` note,
  or both — follow whichever is clearer given the finding.
- Exact wording of the `data/reference/README.md` additions (column type specs, notes
  on missing values) — mirror the existing ADI entry's style.
- Whether to add a `zip5_modal == 0` console note to `approximate_zip9()` even when it
  is data-driven — a low-noise warning is acceptable if it aids future debugging.

</decisions>

<specifics>
## Specific Ideas

- The fan-out magnitude was 1,950,696 → 2,210,904 rows (13.3% inflation) in the Phase 144
  run. After the fix, the output should have ≤ 1,950,696 rows (exact count depends on how
  many same-day multi-encounter patients exist — each patient-day collapses to one
  zip_resolved row, then fans back out to N encounter rows via the `many-to-one` join).
  A `stopifnot` already asserts `nrow(encounter_zip) == nrow(encounters_raw)`, which will
  catch any residual fan-out at runtime.

- The `zip5_modal` zero rows: the most likely innocent explanation is that
  `approximate_zip9()` at line 442–448 early-exits if `n_to_approx == 0`. `n_to_approx`
  counts rows where `is.na(ZIP9) & match_type != "none"`. If every unresolved encounter
  has `match_type == "none"` (no covering address record at any date), the function
  never builds the `zip5_lookup` table. This is data-driven if the HL cohort's address
  history has no ZIP5-only records — unlikely given Phase 139's observations — or if the
  encounter dates all fall outside every address period. The static code read in Task 1
  should confirm this path exists and describe what evidence to look for in the HiPerGator
  output (specifically: the `zip9_source` breakdown and the raw count of match_type by
  category before approximation).

- RUCA is already working (the file is present). Its `data/reference/README.md` entry is
  already documented from Phase 116/100. Do not add a new RUCA section — only add SDI,
  SVI, and ADI.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Fan-out fix (already committed — read to verify, not re-implement)
- `R/utils/utils_address.R` — lines 201–236: the `distinct()` + `stopifnot` fix in
  `get_zip9_at_date()`. Read the full `get_zip9_at_date()` function (lines 111–244).
- `R/116_encounter_ses_index.R` — SECTION 5 (lines 128–155): the corrected join with
  `relationship = "many-to-one"` and the `stopifnot` anchored to `encounters_raw`.

### ZIP5-modal path to audit
- `R/utils/utils_address.R` — `approximate_zip9()` (lines 415–612), specifically lines
  440–448 (the `n_to_approx` early-exit) and lines 483–515 (the `zip5_lookup` build).
- `.classify_zip9_source()` (lines 278–345): the `case_when` that assigns `"zip5_modal"`.

### SES reference documentation target
- `data/reference/README.md` — The file to update. Read the existing content before
  adding new sections, to match style and avoid duplicating the Phase 140 ADI entry.

### Phase 144 context (phase that produced R/116)
- `.planning/phases/144-centroid-zip9-imputation-zip9-level-sdi-and-areal-mean-sdi/144-CONTEXT.md`
  — D-01 (centroid inert), D-05 (probe-first gates), D-06 (output grain), D-07 (encounter
  pull scoping). These decisions are locked and carry forward to Phase 145.

### Phase 140 decisions (ADI acquisition status)
- `.planning/STATE.md` — Phase 140 Decisions section: P-03a (Neighborhood Atlas crosswalk
  acquisition) remains deferred — "not available." ADI will stay null until the file is staged.

</canonical_refs>
