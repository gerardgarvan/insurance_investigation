---
phase: 197
name: phase-b-pipeline-hardening
milestone: cross-milestone
status: in_progress
started: 2026-11-11
---

# Phase 197 — Phase B: Pipeline Hardening

## Scope

Harden pipeline mechanics discovered by the 2026-11-10 dependency audit and Phase 196-A close-out.
No delivered number changes. Regression checks required before each file is reissued.

## Source Documents

- `.planning/audits/2026-11-10-dependency-audit.md` (evidence base)
- `output/dep_map/` latest `_vN` set (run-order, duplicate-writer, unpinned-pick reports)
- `.planning/phases/196-phase-a-delivered-output-fixes/196-SUMMARY.md` (Phase B backlog)

## Ground Rules (apply to every task)

1. No change to any delivered number. Where a change could alter outputs, add a regression check
   against the latest delivered file and list it for Gerard to run.
2. No long scripts (DuckDB at scale, MICE, R/165, R/183 full runs). Parse checks and
   dep_map.R runs are allowed.
3. One commit per task; message prefix `fix(197-NN)` / `refactor(197-NN)` / `docs(197)`.
4. Record decisions as D-197-NN in this file and in relevant script KEY sections.
5. Use existing project conventions: CONFIG paths, build_output_path(), R/utils/ modules, message() logging.
6. CLAUDE.md anti-patterns apply throughout.

## Out of Scope (Phase C backlog)

- R/56 defining `message()` scope guard
- Hard-coded absolute paths in R/161 and R/122a
- Consolidated suppression util (10 `sup()` copies)
- Em-dash cleanup (R/188 `"-"` vs `"—"`)
- R/02 enrollment-completeness % bug
- LNK payer partner investigation
- R/48 Comparison TOTAL row

## Decisions

### D-197-01: treatment_episodes.rds — single owner

**Decision:** R/29 is the sole final writer of `treatment_episodes.rds`.
R/26 writes an intermediate named `treatment_episodes_stage1.rds` (or uses a different internal name).
All downstream readers (R/142, R/100, R/110, R/109, R/143_02, R/28) require R/29 to have run.

**Why:** R/26 creates the initial frame (episode_start, episode columns) needed by R/53;
R/29 adds is_first_line after R/53 produces validated_death_dates.rds.
Having both write the same filename causes silent data loss if R/26 runs last.

**How to apply:** R/26 writes `treatment_episodes_stage1.rds`; R/29 reads it, adds is_first_line,
writes `treatment_episodes.rds`. SCRIPT_INDEX documents this sequence. Downstream readers
get a column-existence assert for `is_first_line` as an early-warning guard.

### D-197-02 through D-197-NN

Additional decisions recorded inline in each plan's SUMMARY and in the KEY sheet of
the script that owns each decision.
