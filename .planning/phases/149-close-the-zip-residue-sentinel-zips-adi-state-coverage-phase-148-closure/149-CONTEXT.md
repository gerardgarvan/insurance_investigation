# Phase 149: Close the ZIP Residue — Context

**Gathered:** 2026-08-20
**Status:** Ready for planning
**Source:** PRD Express Path (149-CONTEXT.md)

<domain>
## Phase Boundary

Phase 149 resolves the 12,782-encounter `zip5_no_zip9` residue left after Phase 147 recovered 258,586 encounters by reading `ADDRESS_ZIP5`. The residue decomposes into three known causes:

1. **Invalid placeholder ZIPs** (~850+): `00009` and other ZIPs below `00501` (the lowest real US ZIP) are not caught by `is_sentinel_zip5()`, which only matches five repeated digits.
2. **Out-of-state ZIPs absent from the ADI file** (~11,000): The Neighborhood Atlas ADI file covers only 23 of 50 states; 92 of 153 residue ZIP5s have prefix `7` (AR/LA/OK/TX), none of which are in the current ADI summary.
3. **Genuine remainder** (small): accept as-is.

Phase 149 delivers:
- A widened `is_sentinel_zip5()` that catches sub-`00501` ZIPs
- Complete (or materially wider) ADI state coverage by downloading and ingesting missing states
- Formal closure of Phase 148 (D-01 gate: do not build centroid crosswalk)
- A re-run of R/118, R/115, R/116, and R/88 with before/after reconciliation

Does **not** build a centroid crosswalk. Does not reopen Phase 148.

</domain>

<decisions>
## Implementation Decisions

### Task 1 — Widen is_sentinel_zip5()

- **Enumerate first (read-only):** Before changing the filter, run the probe in §2a of 149-CONTEXT.md: print all `ZIP5` values where `as.integer(ZIP5) < 501` that are not already caught; run the positive control confirming the existing repeated-digit rejection fires at all.
- Record both outputs in `149-DISCOVERY.md` before touching any source file.
- **Filter change:** Replace the single surviving definition in `R/utils/utils_address.R` with the two-class version (repeated digits OR numeric < 501). The exact replacement is specified verbatim in §2b of 149-CONTEXT.md.
- **Delete the dead duplicate:** There are currently two `is_sentinel_zip5 <- function` definitions; the second silently overrides the first. Delete the dead one. `grep -c "^is_sentinel_zip5 <- function" R/utils/utils_address.R` must return 1.
- **`!is.na(zip5) &` guard required:** predicate returns `FALSE` for `NA` (not `NA`), which is what callers inside `filter()` and `if_else()` expect.
- **New test cases** (add to `tests/testthat/test-utils-address.R`): both placeholder classes, plus the `00501` boundary (off-by-one risk), `12345` (Schenectady NY — real), `32611` (Gainesville FL — real), and `NA_character_`. Exact test block in §2c.

### Task 2 — Complete ADI State Coverage

- **Confirm the diagnosis first:** Run the probe in §3a: count how many residue ZIP5s are present in `zip5_adi_summary.csv`, and enumerate 3-digit prefix coverage.
- **States to add** (priority order from residue evidence): AR (716–729), LA (700–714), OK (730–741), TX (750–799), MS (386–397), PR (006–009, `00983` = 366 encounters). Fetch remaining states beyond these if feasible.
- The collated Neighborhood Atlas ZIP9 file is ~478 MB and is gitignored. `scp` it to HiPerGator and confirm it is present **before** the re-run.
- Record in `149-DISCOVERY.md`: states already present, states added, download date, file vintage.
- Rebuild with `Rscript R/118_build_zip5_adi_summary.R`.

### Task 3 — Close Phase 148

- Write the D-01 closure text (exact wording in §4 of 149-CONTEXT.md) to `148-DISCOVERY.md`.
- **Retract the stale zero:** Annotate (do not delete) the `zip5_no_zip9 = 0` entry in `148-DISCOVERY.md` §5 as superseded; it was an artefact from before `477ed7c` when `ADDRESS_ZIP5` was never read.

### Task 4 — Re-run and Reconcile

- Archive outputs before re-running (bash loop in §5 of 149-CONTEXT.md): rename `*_pre14*.*`-excluding files to `*_pre149.*`.
- Run order: `R/118_build_zip5_adi_summary.R` → `R/115_zip_stability_counts.R` → `R/116_encounter_ses_index.R` → `R/88_smoke_test_comprehensive.R`.
- Record before/after `zip9_source` breakdown in `149-DISCOVERY.md`.
- **Four invariants must hold** (verbatim stopifnot in §5): row count = 1,950,696; `zip9_observed` = 1,516,469; `none` = 158,699; `zip5_no_zip9` < 12,782. The last is the positive control — without it, a no-op run passes everything else.

### General Rules (Locked)

- Enumerate before widening: every ZIP5 newly rejected must be confirmed invalid before the filter changes.
- `12345` (Schenectady NY) and `00501` (Holtsville NY) are **real ZIPs** — not sentinels.
- Do not build a centroid crosswalk.
- Do not report out-of-state ZIPs (1.24 patients/ZIP5) as a data-quality defect.
- Windows dev box has no `Rscript`; HiPerGator for real runs.
- Archive dated outputs before re-running (same-date filenames overwrite).
- Patient key is `ID` in the extract, `PATID` after R/116's rename.
- `R/88` must pass.

### Claude's Discretion

- Wave assignment and plan splitting (single plan is fine if tasks are sequential and small).
- Exact DISCOVERY.md formatting beyond the content requirements above.
- Whether to split the archive bash script into a separate plan or inline it.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase context and task specifications
- `149-CONTEXT.md` — Full task specs, exact code blocks, anti-patterns table, acceptance criteria (§6)

### Prior phase context
- `.planning/phases/147-read-address-zip5-retract-downstream-artefacts/` — Phase 147 that introduced `ADDRESS_ZIP5` reading and created the current `zip9_source` breakdown
- `output/encounter_ses_index_20260820.rds` — The post-147 output; baseline for before/after reconciliation

### Source files to modify
- `R/utils/utils_address.R` — Contains `is_sentinel_zip5()` (currently two definitions; one must be deleted)
- `tests/testthat/test-utils-address.R` — Unit tests for address utilities

### Source files to run
- `R/118_build_zip5_adi_summary.R` — Rebuilds `zip5_adi_summary.csv` from the wider ZIP9 file
- `R/115_zip_stability_counts.R` — ZIP stability counts
- `R/116_encounter_ses_index.R` — Encounter SES index (produces the `zip9_source` breakdown)
- `R/88_smoke_test_comprehensive.R` — Must pass

### Discovery artifacts to write
- `149-DISCOVERY.md` — New file; records enumeration results, state coverage, before/after table
- `148-DISCOVERY.md` — Existing file; D-01 closure text and retraction annotation go here

### Reference data
- `data/reference/zip5_adi_summary.csv` — ADI ZIP5 summary (rebuilt by R/118); currently covers 23 states

</canonical_refs>

<specifics>
## Specific Ideas

- The `is_sentinel_zip5()` replacement is specified verbatim in §2b of 149-CONTEXT.md — copy it exactly, including the comment block.
- The unit test block is specified verbatim in §2c — copy it exactly.
- The archive bash loop is specified in §5 — use it as-is.
- The four `stopifnot()` invariants are specified verbatim in §5 — include all four.
- D-01 closure text for `148-DISCOVERY.md` is given verbatim in §4 — copy it exactly.

</specifics>

<deferred>
## Deferred Ideas

- Centroid crosswalk (Phase 148 D-01 explicitly closed without building it).
- Block-group tier population (deferred from Phase 140).
- Any further SES imputation beyond what Phase 149 delivers.

</deferred>

---

*Phase: 149-close-the-zip-residue-sentinel-zips-adi-state-coverage-phase-148-closure*
*Context gathered: 2026-08-20 via PRD Express Path (149-CONTEXT.md)*
