---
phase: 119-fix-death-cause-nhl-flag
plan: 01
subsystem: investigation
tags: [pcornet, death_cause, tumor_registry, naaccr, classify_codes, duckdb, diagnostic]

# Dependency graph
requires:
  - phase: 118-create-csv-death-cause-nhl-flag
    provides: R/102 deceased-set derivation + three-state NHL flag output (the all-blank output this phase fixes)
provides:
  - R/103 read-only cause-of-death signal inventory diagnostic (deceased-set restricted)
  - output/diagnostics/death_cause_source_inventory.csv (produced at HiPerGator runtime)
  - Wave-0 gate: recommendation of which source (DEATH_CAUSE / TR fallback / proxy) R/102 rewrite should read
affects: [119-02-load-death_cause-table, 119-03-rewrite-r102, 119-04-smoke-test]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Read-only 100+ investigation script probing multiple candidate sources before a rewrite (Wave 0 gate)"
    - "NAACCR item #1910 sentinel filtering (0000/7777/7797) before classify_codes()"
    - "TUMOR_REGISTRY_ALL conditional-column guard (has_cod / has_dcause) for UNION ALL BY NAME view"

key-files:
  created:
    - R/103_death_cause_diagnostic.R
  modified: []

key-decisions:
  - "R/103 probes the DEATH_CAUSE CSV directly via file.path(CONFIG$data_dir, ...) rather than PCORNET_PATHS, because PCORNET_PATHS$DEATH_CAUSE only exists after Plan 02 wires the table in"
  - "get_pcornet_table('DEATH_CAUSE') returning NULL is treated as expected-before-Plan-02, setting Source-1 counts to NA rather than erroring"
  - "Deceased-set derivation copied verbatim from R/102 Section 4 (parse_pcornet_date, 1900 sentinel -> NA, filter !is.na(DEATH_DATE)) so the diagnostic set matches the eventual output set exactly"
  - "Underlying-cause-preferred one-per-ID selection (arrange DEATH_CAUSE_TYPE != 'U' then first) for DEATH_CAUSE classification, avoiding a hard 'U' filter that could drop all rows (Pitfall 2)"

patterns-established:
  - "Wave-0 diagnostic gate: structurally verified locally (grep), run + pasted-back by user on HiPerGator to decide downstream source"
  - "Single recommendation line with three mutually exclusive states (SOURCE 1 / TR fallback / PROXY BACKSTOP)"

requirements-completed: [NHLFIX-01]

# Metrics
duration: 8min
completed: 2026-07-10
---

# Phase 119 Plan 01: Cause-of-Death Signal Inventory Diagnostic Summary

**R/103 read-only diagnostic that inventories DEATH_CAUSE table, TR1.CAUSE_OF_DEATH, and TR2/TR3.DCAUSE against the deceased PATID set, classifies each source with classify_codes(), and emits a single recommendation gating the R/102 rewrite.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-07-10
- **Completed:** 2026-07-10
- **Tasks:** 1
- **Files modified:** 1 (created)

## Accomplishments
- Created `R/103_death_cause_diagnostic.R` (325 lines) — a read-only Wave-0 gate that answers "where does a populated cause-of-death signal live?" before any R/102 rewrite.
- Inventories three candidate sources restricted to the deceased set: DEATH_CAUSE table (Source 1), TR1.CAUSE_OF_DEATH (Source 2), TR2/TR3.DCAUSE (Source 3).
- Filters NAACCR sentinels (0000 alive / 7777 cert-unavailable / 7797 uncoded) before classify_codes(), reports per-source non-null / deceased coverage / NHL matches.
- Emits a single-line recommendation (PROCEED WITH SOURCE 1 / FALLBACK TO TUMOR_REGISTRY / PROXY BACKSTOP REQUIRED) and writes `output/diagnostics/death_cause_source_inventory.csv`.
- Touches nothing in the pipeline output — pure investigation, verified by grep that no `death_cause_nhl_flag.csv` write exists.

## Task Commits

1. **Task 1: Create R/103_death_cause_diagnostic.R** - `0382147` (feat)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) committed separately.

## Files Created/Modified
- `R/103_death_cause_diagnostic.R` - Read-only cause-of-death signal inventory diagnostic; deceased-set restricted; DEATH_CAUSE + TUMOR_REGISTRY cause fields; classify_codes() NHL counts; recommendation; inventory CSV.

## Decisions Made
- Probe the DEATH_CAUSE CSV directly with `file.path(CONFIG$data_dir, "DEATH_CAUSE_Mailhot_V1.csv")` + `file.exists()` rather than assuming `PCORNET_PATHS$DEATH_CAUSE` (that entry only appears after Plan 02).
- `get_pcornet_table("DEATH_CAUSE") == NULL` is the expected pre-Plan-02 state; Source-1 counts default to NA rather than erroring.
- Reuse R/102 Section 4 deceased-set derivation verbatim so the diagnostic's patient set is identical to the eventual output set.
- Underlying-cause-preferred (`arrange(DEATH_CAUSE_TYPE != "U")` then `first()`) one-per-ID selection instead of a hard `== "U"` filter, per RESEARCH Pitfall 2.

## Deviations from Plan

None - plan executed exactly as written. (Two SUMMARY-guidance comment lines that referenced the real output filename by name were reworded to "the real death-cause NHL flag output" so a literal grep for that filename returns nothing — cosmetic, keeps the "must not touch real output" guard unambiguous. Not a behavioral change.)

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

**HiPerGator runtime gate (USER ACTION for Plan 03):** This diagnostic is structurally verified locally but must be RUN on HiPerGator by the user:
```
Rscript R/103_death_cause_diagnostic.R
```
The user reviews the console inventory + `output/diagnostics/death_cause_source_inventory.csv` and pastes back which source is populated. That result selects the source for Plan 03's R/102 rewrite.

## Next Phase Readiness
- Plan 02 (load DEATH_CAUSE into PCORNET_TABLES / R/01 spec / R/03 ingest) is unblocked — R/103 is designed to run both before (Source 1 = NA) and after (Source 1 populated) that wiring.
- Plan 03 (R/102 rewrite) is GATED on the user running R/103 on HiPerGator and reporting the recommendation.
- No blockers.

## Self-Check: PASSED
- FOUND: R/103_death_cause_diagnostic.R
- FOUND: commit 0382147

---
*Phase: 119-fix-death-cause-nhl-flag*
*Completed: 2026-07-10*
