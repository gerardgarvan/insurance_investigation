---
phase: 147-read-address-zip5-retract-downstream-artefacts
plan: 04
status: complete
completed: 2026-08-18
---

# 147-04 Summary — Downstream Artefact Retraction

## What was done

Six logical locations annotated across five files (seven notes total). Original text preserved
everywhere. data/reference/README.md updated with post-148 figures pointing to 147-DISCOVERY.md.

## Files modified

### data/reference/README.md (2 retraction notes)
- **Retraction 3** — before "ADI ceiling (Phase 145, corrected 2026-08-17)": notes that
  the 77.7% ceiling was computed without reading ADDRESS_ZIP5.
- **Retraction 5+6** — before "ZIP5-modal imputation tier" section: notes that the zero-row
  figure was an artefact of ADDRESS_ZIP5 never being read; "Branch C" console message corrected
  in utils_address.R; see 147-DISCOVERY.md §4 for updated figures.

### .planning/phases/146-acquire-and-stage-the-ses-reference-files-sdi-svi-adi/146-DISCOVERY.md (2 retraction notes)
- **Retraction 3** — before ADI ceiling paragraph in Part A: 77.7% was ADDRESS_ZIP9 coverage,
  not ZIP availability.
- **Retraction 4** — before Part F (Sentinel-ZIP Frequency): the 157,472 figure is a phantom
  (empty ADDRESS_ZIP9 cells, not sentinel values); actual Tier 3 population in 147-DISCOVERY.md §4.

### .planning/phases/147-read-address-zip5-retract-downstream-artefacts/147-CONTEXT.md (1 retraction note)
- **Retraction 6** — before `<deferred>` section: centroid crosswalk's "0 encounters" basis
  is void; actual Tier 3 population in 147-DISCOVERY.md §4.

### R/utils/utils_address.R (Task 3 — console note corrected)
- `n_approx_with_zip5 == 0` message updated: "sentinel-nulled" text already removed by Plan 2;
  Plan 4 adds the 147-DISCOVERY.md reference and the pre-/post-Phase-147 distinction so
  a future zero is recognizable as a genuine data observation, not a structural artefact.
- `sentinel-nulled` count in file: 0 ✓
- `147-DISCOVERY.md` references in file: 2 ✓

## Notes on missing files

The plan spec referenced `145-DISCOVERY.md` (no such file — Phase 145 has no DISCOVERY.md)
and `146-CONTEXT.md` (no such file — Phase 146's equivalent is `146-DISCOVERY.md`). The
retraction content was placed in the files where the actual conclusions are documented:
- "0 rows have ZIP5 present and ZIP9 missing" → `data/reference/README.md` ZIP5-modal section
- "Branch C sentinel-nulled" → `data/reference/README.md` ZIP5-modal section + utils_address.R
- "77.7% is a hard ceiling" → `data/reference/README.md` ADI ceiling + `146-DISCOVERY.md` Part A
- "D-04 sentinel-ZIP lever, 157,472 rows" → `146-DISCOVERY.md` Part F

## Verification

| Check | Result |
|-------|--------|
| 146-DISCOVERY.md "Superseded by Phase 147" count | 2 ✓ |
| README.md "Superseded by Phase 147" count | 2 ✓ |
| 147-CONTEXT.md "Superseded by Phase 147" count | 2 ✓ |
| README.md "147-DISCOVERY.md" references | 5 ✓ |
| README.md "157,472" / "157472" preserved | 3 ✓ |
| README.md "77.7" preserved | 4 ✓ |
| utils_address.R "sentinel-nulled" count | 0 ✓ |
| utils_address.R "147-DISCOVERY.md" references | 2 ✓ |
