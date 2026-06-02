# Phase 71: Linting Cleanup - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 71 reduces lintr violations from the 6,187 baseline (Phase 70) to <50 manageable items. This is achieved through two mechanisms: (1) .lintr configuration changes to eliminate false positives and declare project standards, and (2) code fixes for genuine quality issues. The phase does NOT introduce new linting rules or change code behavior — only removes violations and improves code hygiene.

</domain>

<decisions>
## Implementation Decisions

### Pipe Standardization
- **D-01:** Configure `pipe_consistency_linter(pipe='%>%')` in .lintr to declare magrittr pipe as the project standard. The codebase is 100% `%>%` (629 occurrences, zero `|>`). This eliminates 3,622 violations with a config change — no code modifications.

### object_usage_linter
- **D-02:** Disable `object_usage_linter` (set to NULL in .lintr). The 2,104 violations are overwhelmingly false positives from tidyverse/dplyr unquoted column references (PATID, DX, ENCOUNTERID, etc.). This linter is unreliable with NSE-heavy code and most tidyverse R projects disable it.

### Commented Code
- **D-03:** Remove all commented-out code blocks (57 violations). Phase 69 documented all scripts with header blocks and inline comments — commented code no longer serves as documentation. Git history preserves anything removed.

### seq_linter
- **D-04:** Fix all 15 `seq_linter` violations by replacing `1:length(x)` with `seq_along(x)` and `1:nrow(df)` with `seq_len(nrow(df))`. Genuine bug prevention — `1:0` produces `c(1, 0)` instead of empty vector.

### Mechanical Code Fixes
- **D-05:** Fix all `indentation_linter` (27) and `pipe_continuation_linter` (30) violations. These are mechanical, low-risk fixes.

### Line Length
- **D-06:** Bump `line_length_linter` threshold from 120 to 150 characters. Fix lines that are obviously wrappable (long strings, unnecessary chains) while keeping the raised limit for the remainder. R pipelines are often more readable as longer lines than wrapped alternatives.

### Disabled Rules
- **D-07:** Disable `return_linter` (18 violations). Explicit `return()` is a style preference, not a bug. The codebase uses explicit returns in utility functions — consistent within itself.
- **D-08:** Disable `object_length_linter` (7 violations). PCORnet-derived variable names are naturally long (e.g., `treatment_episode_classification`). Truncating them would reduce readability.

### Execution Strategy
- **D-09:** Two-wave execution. Wave 1: All .lintr configuration changes (D-01, D-02, D-06, D-07, D-08). Wave 2: All code fixes (D-03, D-04, D-05, plus line wrapping from D-06). Config changes first so re-running lintr after code fixes shows the true remaining count.
- **D-10:** Edit code locally, verify on HiPerGator. Code changes made locally (commented code removal, seq fixes, indentation), then transferred to HiPerGator for lintr re-run and smoke test verification.

### Claude's Discretion
- Exact order of code fixes within Wave 2
- Which specific long lines to wrap vs leave (within the 150-char limit)
- Whether to batch code fixes by rule or by file
- How to structure the lintr verification re-run on HiPerGator

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Lintr Baseline
- `.planning/phases/70-automated-formatting/70-LINT-BASELINE.md` — Starting baseline: 6,187 violations, 9 rules, 71 files. Per-rule breakdown with percentages for prioritization.

### Configuration
- `.lintr` — Current lintr configuration (object_name_linter disabled, line_length_linter(120), R/archive/ excluded). Phase 71 modifies this file.
- `.planning/phases/70-automated-formatting/70-CONTEXT.md` — Phase 70 decisions on lintr configuration approach (D-05, D-06, D-07)

### Requirements
- `.planning/REQUIREMENTS.md` — SAFE-05 (lintr configured with project .lintr file)

### Script Inventory
- `R/SCRIPT_INDEX.md` — Canonical listing of all 67 numbered scripts + 8 utils + 8 archived

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.lintr` config file from Phase 70 — base configuration to extend with new rules
- `.git-blame-ignore-revs` from Phase 70 — styler formatting commit already listed; Phase 71 bulk fix commits should also be added

### Established Patterns
- Codebase uses `%>%` exclusively (629 occurrences, zero `|>`) — magrittr pipe is the project standard
- PCORnet column names are ALLCAPS (PATID, ENCOUNTERID, DX, PX) — heavily used in unquoted dplyr contexts
- Header blocks use `# ==============` box-style borders (Phase 69 standard) — must not be flagged as commented code
- Section headers use `# SECTION N: TITLE ----` format — must not be flagged as commented code
- Explicit `return()` used in utility functions in R/utils/ — consistent internal pattern

### Integration Points
- .lintr modifications affect all future lintr runs — config changes are the persistent deliverable
- Smoke test (R/87_smoke_test_full_pipeline.R) must pass after all code fixes
- Wave 1 config changes should be committed separately from Wave 2 code changes for clean git history

</code_context>

<specifics>
## Specific Ideas

No specific requirements — standard lint cleanup with decisions captured above.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 71-linting-cleanup*
*Context gathered: 2026-06-02*
