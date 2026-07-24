# Phase 132: Crash Fixes - Context

**Gathered:** 2026-07-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Six R scripts (`R/74_generate_documentation.R`, `R/81_parity_test_cohort.R`, `R/82_benchmark_cohort.R`, `R/83_generate_speedup_report.R`, `R/84_test_durations.R`, `R/85_test_episodes.R`) currently abort immediately on a stray bare `n` token left in by an editor, and `R/84` additionally crashes on an unqualified `walk()` call once past that point. This phase makes all six scripts run past their former abort points and execute their intended logic. It does NOT fix any other bugs in these scripts (tracked separately in REVIEW-FUT-08/09 backlog) — only the two specific crash points named in CRASH-01/CRASH-02.

</domain>

<decisions>
## Implementation Decisions

### Scope correction (locked — not a discretion item)
- The source review undercounts the bare-`n` occurrences: it says "three occurrences in `84`/`85`" but there are actually **6 total** — 3 in `R/84` alone (lines 36, 49, 320) and 3 in `R/85` alone (lines 34, 47, 319), each following the same pattern (`n # ===...` glued onto a section-divider comment). All 6 must be removed, not 3. `R/74`, `R/81`, `R/82`, `R/83` each have exactly 1 occurrence (lines 34, 52, 40, 28 respectively), all immediately after their `source("R/00_config.R")` call.
- Fix mechanic for the bare `n`: delete each occurrence outright (the `n` token itself, leaving the `# ===...` divider comment intact) — do not comment it out, do not leave a blank line marker.

### walk() fix in R/84 — attach library(purrr), don't qualify call sites
- R/84 has 7 unqualified `walk(message)` calls (lines 169, 186, 195, 205, 219, 231, 279), none of them qualified, and `library(purrr)` is not attached anywhere in the file (only `dplyr`, `glue`, `tidyr` in its `suppressPackageStartupMessages({...})` block, lines 28-32).
- Codebase convention strongly favors `library(purrr)` at top + bare `walk()`/`map()` calls: 11 files attach `library(purrr)` explicitly (R/01, R/11, R/25, R/26, R/27, R/63, R/72, R/105, R/108, R/109, archive/treatment_cross_reference.R) with 14 bare call sites codebase-wide, vs. only 7 qualified `purrr::` call sites (R/26:142, R/85:218/228, R/98:237/240/245/283).
- **Decision:** add `library(purrr)` to R/84's `suppressPackageStartupMessages({...})` block, matching the dominant codebase convention, rather than qualifying all 7 call sites with `purrr::`. Sibling script R/85 already does it the qualified way (`purrr::walk()` at lines 218, 228) — that's fine as-is, don't change R/85's working calls to match R/84's fix; each file keeps its own resolved style.

### Claude's Discretion
- Whether to also add real execution/regression coverage for these 6 scripts to R/88 (currently R/88's "Test decade (80-88)" and "Output decade (70-76)" sections only do `file.exists()` checks on `81`-`85` and `74` — nothing sources or runs them, so nothing in the automated smoke suite would have caught these crashes or would catch a future regression of the same kind). Prior bug-fix phases in this codebase (108 "Fix warnings", 99 "Gantt v1/v2 consolidation") established a pattern of adding matching validation coverage alongside a fix, not just patching silently — planner/researcher should weigh that precedent, but the user did not lock a decision on this for Phase 132 specifically.
- How verification is actually performed: whether these 6 scripts can be run locally against test fixtures / cached `.rds` outputs (R/84 reads `cache/outputs/treatment_durations.rds` from R/25; R/85 similarly reads a treatment_episodes cache; R/83 reads a benchmark CSV produced by R/82) to confirm "runs without crashing" on this Windows dev machine, or whether some/all require HiPerGator's real data/environment. Not resolved with the user — research phase should determine what's actually runnable locally before the plan commits to a verification method.
- Whether the fix commits are batched (one commit for all 6 scripts) or per-script — no user preference expressed; follow whatever granularity is normal for this repo's atomic-commit convention.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- None needed — each fix is a 1-2 line mechanical change (delete a stray token, add a `library()` call) in each target file. No new utility functions required.

### Established Patterns
- Section-divider comment format (`# ===...` bars) used consistently as a header convention across all R/ scripts — confirms the stray `n` is an artifact glued onto this divider pattern, not deliberate code.
- `suppressPackageStartupMessages({ library(...) ... })` block at the top of scripts is the standard place library attachments belong (see R/84 lines 28-32) — `library(purrr)` should be added inside that same block, alongside `dplyr`/`glue`/`tidyr`.
- Bug-fix phases in this codebase (Phase 108, Phase 99) consistently pair the fix with an R/88 smoke-test section or a new R/9X validation script — see Phase 108's D-15 equivalent and Phase 99's D-15 ("Create R/99 validation script following established pattern R/95, R/96").

### Integration Points
- R/88_smoke_test_comprehensive.R Section "[9/29] Output decade (70-76)" (R/88:292-307) lists `"74_generate_documentation.R"` in its `output_scripts` vector (R/88:297) — existence-check only.
- R/88_smoke_test_comprehensive.R Section "[10/29] Test decade (80-88)" (R/88:312-324) lists `"81_parity_test_cohort.R"`, `"82_benchmark_cohort.R"`, `"83_generate_speedup_report.R"`, `"84_test_durations.R"`, `"85_test_episodes.R"` in its `test_scripts` vector (R/88:315-317) — existence-check only.
- R/83 depends on a benchmark CSV that R/82 produces — if local execution verification is pursued, R/82 needs to run (or a fixture CSV needs to exist) before R/83 can be exercised.

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond what's captured above — the review and roadmap already fully specify the two crash mechanics (stray `n`, unqualified `walk()`). User elected to skip further discussion since the fixes are mechanical and already locked by REQUIREMENTS.md (CRASH-01, CRASH-02) and ROADMAP.md's Phase 132 design constraints.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (The ~80 per-script Low/Med findings in these same scripts, e.g. R/74's output-filename mismatch or R/80's header/implementation mismatch, are already tracked in REVIEW-FUT-08/09 per REQUIREMENTS.md and are explicitly out of scope for this phase.)

</deferred>

---

*Phase: 132-crash-fixes*
*Context gathered: 2026-07-24*
