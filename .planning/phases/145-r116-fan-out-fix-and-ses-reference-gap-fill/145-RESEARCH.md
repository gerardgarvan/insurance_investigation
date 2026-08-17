# Phase 145: R/116 Fan-Out Fix and SES Reference Gap Fill — Research

**Researched:** 2026-08-17
**Domain:** R pipeline — dplyr join integrity, ZIP9 approximation logic, SES reference documentation
**Confidence:** HIGH (code is already committed and readable; findings are from direct source inspection)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** The fan-out code fix is already committed (commit `0364c89`). Phase 145 does NOT re-implement it. Task 1 is a code audit confirming correctness, followed by a HiPerGator checkpoint that confirms row counts match.

- **D-02:** Scope is investigate first, then decide. Phase 145 includes a static code-read step tracing whether a code path prevents `zip5_modal` from firing even when encounters with `match_type == "interval"` or `"most_recent_before"` have `ZIP9 = NA`. After the HiPerGator checkpoint:
  - If **data-driven** (all unresolved encounters truly have `match_type == "none"`): add a console note and a `data/reference/README.md` entry — no code change.
  - If **code bug**: fix it in `utils_address.R` or R/116 and re-run the HiPerGator checkpoint. Do not assume a direction before the code read + HiPerGator evidence.

- **D-03:** Document in `data/reference/README.md` (not per-file README_*.txt). Sections to add:
  - **SDI:** path = `data/reference/zip5_sdi_reference.csv`, required columns = `ZIP5` (5-digit char), `SDI_score` (numeric 0–100), join key = ZIP5.
  - **SVI:** path = `data/reference/svi_2020_us_by_zcta.csv`, required columns = `ZCTA` (5-digit char), `RPL_THEMES` (composite percentile 0–1; CDC encodes missing as −999 → filter to `>= 0`), join key = ZIP5 (ZCTA ≈ ZIP5).
  - **ADI:** path = `data/reference/neighborhood_atlas_block_group_crosswalk.csv`, required columns = one of `ZIP9/zip9/ADDRESS_ZIP9/zip9_norm/GEOID9/ZIP_PLUS4` and one of `adi_natrank/ADI_NATRANK/natrank`, join key = ZIP9. Acquisition still pending (P-03a from Phase 140).

- **D-04:** One blocking HiPerGator checkpoint after the code audit. User runs R/116 and pastes full console output. Plan branches on the `zip9_source` breakdown (D-02 decision tree). If a fix is needed, the checkpoint is the gate before regenerating final outputs.

### Claude's Discretion

- Whether the ZIP5-modal diagnosis produces an inline code comment, a `README.md` note, or both — follow whichever is clearer given the finding.
- Exact wording of the `data/reference/README.md` additions — mirror the existing ADI entry's style.
- Whether to add a `zip5_modal == 0` console note to `approximate_zip9()` even when it is data-driven — a low-noise warning is acceptable if it aids future debugging.

### Deferred Ideas (OUT OF SCOPE)

- Acquiring the SDI, SVI, or ADI reference files themselves — documentation only.
- Activating Tier 3 centroid (still waiting on licensed ZIP+4 source, per D-01 from Phase 144).
- Patient-level SES rollup, HL-cohort filtering, or any modification to `hl_cohort.csv`.
- Modifying `get_zip9_at_date()` beyond what was already committed in `0364c89`.
</user_constraints>

---

## Summary

Phase 145 is a verification, diagnosis, and documentation phase — no new feature development. The fan-out fix is already committed and the task is to confirm it works on HiPerGator, regenerate clean output files, trace whether the ZIP5-modal zero-rows is a code bug or data characteristic, and add three SES reference file contracts to `data/reference/README.md`.

The fan-out root cause is fully understood: `get_zip9_at_date()` returns one row per distinct `(ID, query_date)` pair, but R/116 was passing raw encounter rows (many duplicates per patient-day) which caused the `anti_join` path to inherit duplicates, making none-rows fan-out in the final `left_join`. The fix uses `distinct(ID, query_date)` before `anti_join`, adds a `stopifnot` asserting no duplicate keys on return, and R/116 declares `relationship = "many-to-one"` with a `stopifnot(nrow(encounter_zip) == nrow(encounters_raw))` assertion.

The ZIP5-modal zero-rows most likely reflects a data characteristic: if every unresolved encounter has `match_type == "none"` (no address record exists at all for that patient-date), then `n_to_approx == 0` and `approximate_zip9()` early-exits at line 446–448 without building the `zip5_lookup` table. This is an innocent data-driven outcome, but must be confirmed by inspecting the `zip9_source` breakdown in the HiPerGator console output.

**Primary recommendation:** Plan one code-audit task (static read of the committed fix), one blocking HiPerGator checkpoint (paste console output to verify row counts and `zip9_source` breakdown), one conditional fix-or-document task (based on the D-02 decision tree), and one `data/reference/README.md` documentation task.

---

## Architecture Patterns

### Fan-Out Fix — Already Committed

The committed fix in `get_zip9_at_date()` (lines 201–241, commit `0364c89`):

1. **`uncovered` now uses `distinct(ID, query_date)` instead of raw `queries`** (line 209–211). This ensures the anti_join path never inherits duplicate query rows.
2. **`stopifnot` added after `bind_rows`** (lines 235–236): asserts `!any(duplicated(matched[c("ID", "query_date")]))` — will abort at runtime if any future code path reintroduces duplicates.
3. **Return path also uses `distinct(ID, query_date)`** (line 239): final `left_join` is on distinct keys, preserving the function's documented contract ("one row per DISTINCT (ID, query_date)").

The committed fix in R/116 SECTION 5 (lines 144–152):

- `relationship = "many-to-one"` in the `left_join` (line 148): explicitly asserts the join direction — one resolved ZIP maps to many encounters, never the reverse.
- `stopifnot(nrow(encounter_zip) == nrow(encounters_raw))` (line 151–152): hard abort if row count inflates; anchored to `encounters_raw`, not `zip_resolved`.

Both fixes are structurally sound. The code audit task should confirm:
- `uncovered` is built from `distinct(ID, query_date)` (not raw `queries`)
- The `stopifnot` on `matched` is present and uses the correct column pair
- R/116's `relationship = "many-to-one"` is not relying on `many-to-many` anywhere in SECTION 5
- No other call site of `get_zip9_at_date()` in the repo bypasses these guards

### ZIP5-Modal Early-Exit Path

`approximate_zip9()` lines 440–448:

```r
n_to_approx <- result_tbl %>%
  filter(is.na(ZIP9), !is.na(match_type), match_type != "none") %>%
  nrow()

if (n_to_approx == 0) {
  return(.classify_zip9_source(result_tbl, .empty_zip5_lookup(), unavailable = FALSE))
}
```

This early-exit fires when **every row with `ZIP9 = NA` also has `match_type == "none"`**. When this happens:
- `.classify_zip9_source()` is called with an empty `zip5_lookup`
- `zip9_source` is classified as `"none"` for all unresolved rows (via `match_type == "none"` branch in the `case_when`)
- `zip5_modal` never appears in the output breakdown — zero rows, by design

The "innocent explanation" (from CONTEXT.md specifics) is that the HL cohort's encounters with no matching address record all land in `match_type == "none"`, meaning `get_zip9_at_date()` found no record at all for those patients on those dates. There is no ZIP5 to look up. The ZIP5-modal tier is not reachable.

**What evidence confirms this is data-driven (not a bug):**
- HiPerGator `zip9_source` breakdown shows `none` rows but zero `zip5_no_zip9` rows
- OR: `zip5_no_zip9` rows exist but `zip5_modal` is still zero (would be a different, legitimate data outcome — the ZIP5 exists in LDS but all records for that ZIP5 have no ZIP9)

**What evidence would indicate a bug:**
- Rows with `match_type %in% c("interval", "most_recent_before")` and `ZIP9 = NA` exist in the pre-`approximate_zip9()` output, but `n_to_approx` was somehow computed as 0
- This would require a filter mismatch: e.g., `is.na(ZIP9)` evaluating unexpectedly, or `match_type` having a different value than expected

The static code read should also confirm the column `ZIP9` in `result_tbl` is the same column that `get_zip9_at_date()` returns (line 197: `ZIP9 = zip9_norm`). If the column rename was incomplete, `is.na(ZIP9)` would compute on the wrong column. The committed code shows `ZIP9 = zip9_norm` in all three result-building steps (interval_hits, fallback_hits, none_rows), so this is not the bug.

### `.classify_zip9_source()` — Case_When Order

The `case_when` in `.classify_zip9_source()` (lines 288–295):

```r
zip9_source = case_when(
  !is.na(ZIP9)         ~ "zip9_observed",
  is.na(match_type)    ~ "invalid_input",
  match_type == "none" ~ "none",
  unavailable          ~ "reference_unavailable",
  !is.na(modal_zip9)   ~ "zip5_modal",
  TRUE                 ~ ".needs_centroid_check"
)
```

When `n_to_approx == 0`, `approximate_zip9()` passes `unavailable = FALSE` to `.classify_zip9_source()`. The `unavailable` branch is skipped. Rows with `match_type == "none"` are classified as `"none"`. Rows with `!is.na(ZIP9)` are classified as `"zip9_observed"`. The `modal_zip9` column comes from the `left_join` with `zip5_lookup`; since `zip5_lookup` is empty, `modal_zip9` is `NA` for all rows, so no rows reach `"zip5_modal"`. This is correct, not a bug.

### SES Reference README Style

The existing `data/reference/README.md` style (confirmed by reading the file):
- H2 heading with the index name and phase tag in parentheses
- **Expected path:** line
- **Purpose:** line
- **Source:** URL with access notes
- **Expected columns:** bulleted list with flexible column-name alternatives
- **Status:** final line noting current availability

The ADI/Neighborhood Atlas entry at lines 10–71 is the template to follow. The Phase 145 additions for SDI, SVI, and ADI should match this structure, noting:
- For ADI: the existing Phase 140 entry at line 10 is for the *block-group crosswalk* (used by R/115). The ADI entry requested in D-03 is for the *patient-level ADI index* (used by R/116). Check whether these are the same file or different. If R/116's probe gate probes a different path, it needs its own section. CONTEXT.md says R/116 probes `data/reference/neighborhood_atlas_block_group_crosswalk.csv` for ADI columns — this is the SAME file as Phase 140's section. Confirm in R/116's SECTION 6 code before writing to avoid duplication.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Asserting join doesn't fan-out | Custom pre/post row-count check only | `relationship = "many-to-one"` in dplyr `left_join` + `stopifnot(nrow(out) == nrow(in))` — already committed |
| Checking for duplicate join keys | Manual `group_by + count + filter(n > 1)` | `!any(duplicated(df[c("col1","col2")]))` — already in the committed `stopifnot` |

---

## Common Pitfalls

### Pitfall 1: Confusing the two `uncovered` variable types before vs. after the fix

**What goes wrong:** Before the fix, `queries` passed to `anti_join` was NOT deduplicated — it contained one row per original input element (potentially many encounters per patient-day). After the fix, `uncovered` is `queries %>% distinct(ID, query_date)`. If a code audit reads the pre-fix version by accident (e.g., from git history), it will appear correct because the variable name did not change.

**How to avoid:** Always read from HEAD (commit `0364c89` or later). Confirm `distinct(ID, query_date)` is present at line 209–211 before asserting the fix is correct.

### Pitfall 2: Treating `zip5_modal == 0` as a definitive bug without the HiPerGator data

**What goes wrong:** Inferring a code defect from zero `zip5_modal` rows without verifying whether `n_to_approx > 0` in the actual run.

**How to avoid:** The HiPerGator checkpoint must report the raw `match_type` breakdown from the `zip_resolved` table BEFORE `approximate_zip9()` — or at minimum confirm whether any `match_type %in% c("interval", "most_recent_before")` rows have `ZIP9 = NA`. If zero such rows exist, `n_to_approx = 0` is correct and `zip5_modal = 0` is expected.

**Diagnostic addition for the plan:** Include an explicit console step (either in R/116 or as a standalone diagnostic command) that prints `table(zip_resolved_pre_approx$match_type, is.na(zip_resolved_pre_approx$ZIP9))` before the pipe to `approximate_zip9()`. This directly shows whether approximable rows exist.

### Pitfall 3: Adding a second ADI section to README.md when one already exists

**What goes wrong:** Phase 140 already added a comprehensive ADI block-group crosswalk entry (lines 10–71). Adding a new ADI section for Phase 145 without checking whether it's the same file creates duplicate/conflicting contracts for the same path.

**How to avoid:** Read the existing Phase 140 section and R/116 SECTION 6's probe logic. If R/116 probes the same path (`neighborhood_atlas_block_group_crosswalk.csv`) for ADI columns, extend or update the Phase 140 section rather than creating a new one. If R/116 probes a different path for `adi_natrank`, add a new section clearly distinguishing the two.

### Pitfall 4: Using R/116's PATID column vs. ID column mismatch

**What goes wrong:** `get_zip9_at_date()` returns column `ID` but R/116 feeds `PATID` as the ids argument. The join in SECTION 5 renames via `dplyr::rename(PATID = ID, ADMIT_DATE = query_date)`. If a future edit modifies the rename or the `encounters_raw` column name, the join silently produces no rows.

**How to avoid:** The code audit should confirm the rename is present at line 146 and that `encounters_raw$PATID` is the correct column name from the ENCOUNTER CDM table (it is — PCORnet CDM uses `PATID` in ENCOUNTER).

---

## Code Examples

### Fan-Out Fix — Key Lines in `get_zip9_at_date()` (already committed)

```r
# Source: R/utils/utils_address.R lines 209-241 (commit 0364c89)

# BEFORE fix: uncovered <- queries %>% anti_join(covered, ...)
# AFTER fix:
uncovered <- queries %>%
  distinct(ID, query_date) %>%
  anti_join(covered, by = c("ID", "query_date"))

# ... build fallback_hits and none_rows as before ...

matched <- bind_rows(interval_hits, fallback_hits, none_rows)

stopifnot("get_zip9_at_date: matched has duplicate (ID, query_date) keys" =
            !any(duplicated(matched[c("ID", "query_date")])))

queries %>%
  distinct(ID, query_date) %>%
  left_join(matched, by = c("ID", "query_date")) %>%
  arrange(ID, query_date)
```

### R/116 Row-Count Guard (already committed)

```r
# Source: R/116_encounter_ses_index.R lines 144-152 (commit 0364c89)
encounter_zip <- encounters_raw %>%
  left_join(
    zip_resolved %>% dplyr::rename(PATID = ID, ADMIT_DATE = query_date),
    by = c("PATID", "ADMIT_DATE"),
    relationship = "many-to-one"
  )

stopifnot("ZIP resolution fanned out -- zip_resolved has duplicate (PATID, ADMIT_DATE) keys" =
            nrow(encounter_zip) == nrow(encounters_raw))
```

### Diagnostic Command for ZIP5-Modal Investigation

```r
# Paste into R/116 just before the pipe to approximate_zip9(), or run interactively
# after get_zip9_at_date() returns:
message("--- match_type x ZIP9-missing breakdown (pre-approximation) ---")
print(table(zip_pre_approx$match_type, is.na(zip_pre_approx$ZIP9), 
            dnn = c("match_type", "ZIP9_is_NA"), useNA = "ifany"))
# If row where ZIP9_is_NA == TRUE and match_type != "none" has count > 0,
# n_to_approx > 0 and zip5_modal SHOULD fire if the lookup has data.
# If that cell is 0, zip5_modal == 0 is expected (data-driven).
```

### SES Reference README Section Style (mirror of Phase 140 ADI entry)

```markdown
## [Index Name] ([Source Organization]) (Phase 145)

**Expected path:** `data/reference/[filename].csv`

**Purpose:** [what R/116 uses it for — which SECTION, what column it produces]

**Source:** [URL]. [access notes].

**Expected columns:**
- Join key: `[column_name]` ([type, description])
- Value: `[column_name]` ([type, range, missing-value encoding])

**R/116 probe gate:** R/116 SECTION 6 checks `file.exists([path])`. If absent,
`[variable]_tier_status` reads `"not available (file not found)"` and the
corresponding output column is `NA_[type]_` for all rows.

**Status as of [date]:** Not staged.
```

---

## Open Questions

1. **Does R/116's ADI probe gate probe the same file as Phase 140's block-group crosswalk?**
   - What we know: D-03 says ADI path = `data/reference/neighborhood_atlas_block_group_crosswalk.csv` and join key = ZIP9. Phase 140's README section covers the same path.
   - What's unclear: Whether R/116 SECTION 6 probes for `adi_natrank` specifically within that same file, or whether it expects a separate flat ADI file.
   - Recommendation: Read R/116 SECTION 6 (lines 157–end of section) before writing the README entry. If it's the same file, update/extend the Phase 140 section rather than duplicating. The plan task should explicitly say "read R/116 SECTION 6 probe logic before writing."

2. **What is the exact Phase 144 run's `zip9_source` breakdown?**
   - What we know: Phase 144 observed `zip5_modal` fired zero rows.
   - What's unclear: Whether any `match_type %in% c("interval", "most_recent_before")` rows with `ZIP9 = NA` existed at all (i.e., whether `n_to_approx` was truly 0 or something else suppressed zip5_modal).
   - Recommendation: The HiPerGator checkpoint must print both the `zip9_source` breakdown AND the pre-approximation `match_type x ZIP9_is_NA` crosstab. The plan should include this diagnostic as a required output of the checkpoint.

3. **Expected row count after the fan-out fix**
   - What we know: Input was 1,950,696 encounters; inflated output was 2,210,904. After the fix, `nrow(encounter_zip) == nrow(encounters_raw)` must hold.
   - What's unclear: The exact `encounters_raw` count depends on the HiPerGator run's ENCOUNTER CDM content (cohort filter may vary slightly). The `stopifnot` will catch any remaining inflation regardless.
   - Recommendation: Document the expected row count in the plan's checkpoint verification section as "must equal the `encounters_raw` count logged earlier in the R/116 console output."

---

## Environment Availability

Step 2.6: SKIPPED for code tasks (no new external dependencies — all changes are to already-installed R packages and existing file paths).

HiPerGator dependency note: The blocking checkpoint requires the user to run `Rscript R/116_encounter_ses_index.R` on HiPerGator. This is not an environment Claude can access; it is a human-action checkpoint.

---

## Sources

### Primary (HIGH confidence)
- `R/utils/utils_address.R` lines 111–244 (`get_zip9_at_date()`) — direct source read, commit `0364c89`
- `R/utils/utils_address.R` lines 278–355 (`.classify_zip9_source()`) — direct source read
- `R/utils/utils_address.R` lines 415–519 (`approximate_zip9()` through `zip5_lookup` build) — direct source read
- `R/116_encounter_ses_index.R` lines 128–155 (SECTION 5, corrected join) — direct source read
- `data/reference/README.md` lines 1–71 — direct source read, style baseline for new sections
- `.planning/phases/145-r116-fan-out-fix-and-ses-reference-gap-fill/145-CONTEXT.md` — all locked decisions

### Secondary (MEDIUM confidence)
- `.planning/STATE.md` — Phase 140 decision log for P-03a (ADI acquisition deferred) and Phase 144 context

---

## Metadata

**Confidence breakdown:**
- Fan-out fix correctness: HIGH — code is committed and readable; the `distinct()` + `stopifnot` pattern is unambiguous
- ZIP5-modal diagnosis: HIGH for code path analysis; MEDIUM for data-driven vs. bug determination (requires HiPerGator evidence)
- SES reference contracts: HIGH for SDI/SVI (per D-03 locked spec); MEDIUM for ADI (depends on R/116 SECTION 6 probe logic, not yet read in full)
- README style matching: HIGH — existing entry read directly

**Research date:** 2026-08-17
**Valid until:** Stable (no external dependencies; all findings from committed code)
