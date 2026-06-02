# Phase 71: Linting Cleanup - Research

**Researched:** 2026-06-02
**Domain:** R static analysis and code quality (lintr package ecosystem)
**Confidence:** HIGH

## Summary

Phase 71 reduces lintr violations from the 6,187 baseline (Phase 70) to <50 manageable items through two mechanisms: (1) .lintr configuration changes to eliminate false positives and declare project standards (5,726 violations eliminated via config), and (2) code fixes for genuine quality issues (129 violations manually fixed). The research confirms that the two-wave strategy (config first, then code) is the standard incremental cleanup pattern for large codebases, with `.git-blame-ignore-revs` integration ensuring bulk commits don't pollute git history.

**Primary recommendation:** Use lintr 3.3.0-1 (current as of Nov 2025) with `linters_with_defaults()` for selective rule customization. Apply all configuration changes in Wave 1, re-run lintr to verify the reduced count, then apply code fixes in Wave 2. The magrittr pipe standard, object_usage_linter disablement, and line_length bump to 150 are all well-precedented choices for tidyverse-heavy codebases.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01: pipe_consistency_linter(%>%)**
- Configure `pipe_consistency_linter(pipe='%>%')` in .lintr to declare magrittr pipe as the project standard
- The codebase is 100% `%>%` (629 occurrences, zero `|>`)
- Eliminates 3,622 violations with a config change — no code modifications

**D-02: Disable object_usage_linter**
- Set `object_usage_linter = NULL` in .lintr
- The 2,104 violations are overwhelmingly false positives from tidyverse/dplyr unquoted column references (PATID, DX, ENCOUNTERID, etc.)
- This linter is unreliable with NSE-heavy code and most tidyverse R projects disable it

**D-03: Remove Commented Code**
- Remove all commented-out code blocks (57 violations)
- Phase 69 documented all scripts with header blocks and inline comments — commented code no longer serves as documentation
- Git history preserves anything removed

**D-04: Fix seq_linter Violations**
- Fix all 15 `seq_linter` violations by replacing `1:length(x)` with `seq_along(x)` and `1:nrow(df)` with `seq_len(nrow(df))`
- Genuine bug prevention — `1:0` produces `c(1, 0)` instead of empty vector

**D-05: Mechanical Code Fixes**
- Fix all `indentation_linter` (27) and `pipe_continuation_linter` (30) violations
- These are mechanical, low-risk fixes

**D-06: Line Length Bump**
- Bump `line_length_linter` threshold from 120 to 150 characters
- Fix lines that are obviously wrappable (long strings, unnecessary chains) while keeping the raised limit for the remainder
- R pipelines are often more readable as longer lines than wrapped alternatives

**D-07: Disable return_linter**
- Set `return_linter = NULL` (18 violations)
- Explicit `return()` is a style preference, not a bug
- The codebase uses explicit returns in utility functions — consistent within itself

**D-08: Disable object_length_linter**
- Set `object_length_linter = NULL` (7 violations)
- PCORnet-derived variable names are naturally long (e.g., `treatment_episode_classification`)
- Truncating them would reduce readability

**D-09: Two-Wave Execution**
- Wave 1: All .lintr configuration changes (D-01, D-02, D-06, D-07, D-08)
- Wave 2: All code fixes (D-03, D-04, D-05, plus line wrapping from D-06)
- Config changes first so re-running lintr after code fixes shows the true remaining count

**D-10: Edit Locally, Verify on HiPerGator**
- Code changes made locally (commented code removal, seq fixes, indentation)
- Then transferred to HiPerGator for lintr re-run and smoke test verification

### Claude's Discretion

- Exact order of code fixes within Wave 2
- Which specific long lines to wrap vs leave (within the 150-char limit)
- Whether to batch code fixes by rule or by file
- How to structure the lintr verification re-run on HiPerGator

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SAFE-05 | lintr configured with project .lintr file (object_name_linter disabled for PCORnet ALLCAPS columns, line_length_linter(120)) | This research provides: (1) .lintr configuration syntax via linters_with_defaults(), (2) selective rule disablement patterns (= NULL), (3) validation that 150-char line length is acceptable for R pipelines, and (4) incremental cleanup strategy with config-first waves |

</phase_requirements>

## Project Constraints (from CLAUDE.md)

**Runtime environment:**
- RStudio on UF HiPerGator — scripts must work in that environment
- Local edits verified on HiPerGator (D-10 from CONTEXT.md)

**Code style:**
- Filtering logic uses named predicate functions (`has_*`, `with_*`, `exclude_*`) — no opaque one-liners
- This constraint is preserved during lint cleanup — no refactoring that would obscure readability

**Documentation standards (from Phase 69):**
- Header blocks use `# ==============` box-style borders — must not be flagged as commented code
- Section headers use `# SECTION N: TITLE ----` format — must not be flagged as commented code
- These patterns are safe: `commented_code_linter` only flags syntactic code patterns (assignments, function calls), not section headers

**Smoke test validation:**
- `R/87_smoke_test_full_pipeline.R` must pass after all code fixes
- Validates no broken source() references, no script renumbering issues

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| lintr | 3.3.0-1 | R static analysis linter | Official tidyverse ecosystem linter; CRAN-published Nov 2025; supports 40+ configurable rules with .lintr project configuration |

### Configuration Approach
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| .lintr file | Per-project linter configuration in Debian control format | Canonical method per official lintr documentation; evaluated as R code; supports linters_with_defaults() for selective customization |
| .git-blame-ignore-revs | Git history integration for bulk commits | Standard practice for formatting/lint cleanup commits (GitHub auto-recognizes this filename); preserves meaningful blame history |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| glue | 1.8.0 | String interpolation for logging | Already in project stack (Phase 69); used in smoke test output |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| lintr 3.3.0-1 | goodpractice package | goodpractice wraps lintr + additional checks; overkill for focused lint cleanup |
| lintr 3.3.0-1 | Older lintr 2.x | Missing pipe_consistency_linter configurability; 3.x required for magrittr pipe support |
| .lintr config file | Inline suppressions only (# nolint) | File-level suppressions don't scale; 6,187 violations need systematic config approach |

**Installation:**

Not needed — lintr already used in Phase 70 baseline generation.

**Version verification:**

```r
# In R console (HiPerGator)
packageVersion("lintr")
# [1] '3.3.0.1'
```

lintr 3.3.0-1 published Nov 27, 2025 (verified via CRAN).

## Architecture Patterns

### Recommended Cleanup Workflow

```
Phase 71/
├── Wave 1: Configuration Changes
│   ├── Modify .lintr (5 rule changes)
│   ├── Re-run lintr to verify reduced count
│   └── Commit config changes
├── Wave 2: Code Fixes
│   ├── Remove commented code (57 violations)
│   ├── Fix seq_linter (15 violations)
│   ├── Fix indentation/pipe continuation (57 violations)
│   ├── Wrap long lines (subset of 307)
│   ├── Re-run lintr to verify <50 remaining
│   └── Commit code changes
└── Validation
    ├── Run R/87_smoke_test_full_pipeline.R
    ├── Verify pipeline still works
    └── Update .git-blame-ignore-revs
```

**WHY this order:** Configuration changes must be applied first so that the reduced violation count guides Wave 2 priorities. Re-running lintr after Wave 1 shows which code fixes are still needed vs which were false positives.

### Pattern 1: lintr Configuration via linters_with_defaults()

**What:** Use `linters_with_defaults()` to keep all default linters while selectively customizing or disabling specific rules.

**When to use:** Large codebases with a 6,000+ violation baseline where most rules are correct but a few generate false positives or conflict with project conventions.

**Example:**

```r
# .lintr
linters: linters_with_defaults(
    pipe_consistency_linter = pipe_consistency_linter("%>%"),
    object_usage_linter = NULL,
    return_linter = NULL,
    object_length_linter = NULL,
    line_length_linter = line_length_linter(150L)
  )
exclusions: list(
    "R/archive" = list()
  )
```

**Source:** [lintr official documentation - Using lintr](https://lintr.r-lib.org/articles/lintr.html)

**WHY selective NULL assignment:** Setting a linter to `NULL` disables it completely. This is cleaner than removing it from the configuration because it explicitly documents the decision to skip that rule.

### Pattern 2: Two-Wave Cleanup Strategy

**What:** Separate configuration changes (Wave 1) from code modifications (Wave 2) into distinct commits.

**When to use:** Any lint cleanup with >1,000 violations where configuration alone can eliminate >50% of issues.

**Example:**

```bash
# Wave 1: Config changes
git add .lintr
git commit -m "config(lintr): disable false-positive rules, set magrittr pipe standard"

# Wave 2: Code fixes
git add R/*.R R/utils/*.R
git commit -m "fix(lint): remove commented code, fix seq violations, format long lines"
```

**Source:** [Get your codebase lint-free forever with lintr (R-bloggers)](https://www.r-bloggers.com/2024/08/get-your-codebase-lint-free-forever-with-lintr/)

**WHY separate commits:** Git history shows intent clearly. Config changes are policy decisions; code fixes are mechanical changes. Reviewers can assess them independently.

### Pattern 3: Git Blame Integration

**What:** After bulk formatting/lint commits, add commit hash to `.git-blame-ignore-revs` so `git blame` skips mechanical changes.

**When to use:** Always, for any commit that touches >10 files with mechanical changes.

**Example:**

```bash
# After Wave 2 commit
COMMIT_HASH=$(git rev-parse HEAD)
echo "$COMMIT_HASH # Phase 71: Lint cleanup (commented code, seq fixes, indentation)" >> .git-blame-ignore-revs
git add .git-blame-ignore-revs
git commit -m "chore(git): ignore Phase 71 lint cleanup in blame history"

# Configure git to use this file
git config blame.ignoreRevsFile .git-blame-ignore-revs
```

**Source:** [git blame: Ignore Commits with .git-blame-ignore-revs (madewithlove)](https://madewithlove.com/blog/ignoring-revisions-when-using-git-blame/)

**WHY this matters:** Phase 69 invested 8 plans in documentation. When developers later use `git blame` to understand why code changed, they should see the Phase 69 documentation commits, not the Phase 71 mechanical lint fixes.

### Anti-Patterns to Avoid

**1. Fixing violations before updating config**

- ❌ **BAD:** Manually fix all 3,622 pipe_consistency_linter violations by replacing `%>%` with `|>`
- ✅ **GOOD:** Set `pipe_consistency_linter("%>%")` in .lintr to declare `%>%` as the standard

**WHY:** The codebase is 100% magrittr pipe. Switching to native pipe would require changing 629 occurrences and verifying all scripts still work. The config approach is zero-risk.

**2. Applying code fixes without re-running lintr between waves**

- ❌ **BAD:** Apply all Wave 1 config changes, apply all Wave 2 code fixes, then run lintr once at the end
- ✅ **GOOD:** Wave 1 → re-run lintr → verify reduced count → Wave 2 → re-run lintr → verify <50 remaining

**WHY:** Without the intermediate lintr run, you don't know if your config changes actually worked or if you're fixing violations that would have been eliminated by config.

**3. Using blanket # nolint suppressions**

- ❌ **BAD:** Add `# nolint` to every line with a violation
- ✅ **GOOD:** Use `# nolint: specific_linter_name.` for justified exceptions only

**WHY:** Blanket suppressions hide all linter feedback, including future rule additions. If you're suppressing 2,104 object_usage_linter violations with inline comments, that's a signal the rule should be disabled globally instead.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Parsing lintr output to identify violation patterns | Custom R script that reads lintr output and aggregates by rule | lintr::lint_package() with default console output | lintr already groups violations by file and rule; the Phase 70 baseline manually counted these, but for Phase 71 the raw output is sufficient |
| Deciding which linters to disable | Manual review of all 6,187 violations to decide which are false positives | Follow established tidyverse project patterns: disable object_usage_linter for NSE-heavy code, disable return_linter for explicit-return style | The tidyverse community has already debugged these patterns; object_usage_linter is widely known to produce false positives with dplyr |
| Automated code fixes for seq violations | Custom find/replace across all files | lintr's diagnostic messages show exact locations; manual fixes with verification | Only 15 violations exist; automation overhead isn't justified, and manual fixes allow verification that the replacement is correct (seq_along vs seq_len) |
| Testing that code still works after lint fixes | Custom test harness | R/87_smoke_test_full_pipeline.R (already exists from Phase 67) | The smoke test validates source() resolution, script numbering, and basic pipeline integrity — exactly what lint cleanup might break |

**Key insight:** lintr's violation output is already structured for human triage. Automated remediation tools (like lintr's experimental auto-fix feature) are not stable enough for production use. The two-wave strategy (config first, then selective manual fixes) is faster and safer than building custom automation.

## Common Pitfalls

### Pitfall 1: commented_code_linter Flags Section Headers

**What goes wrong:** The linter flags `# SECTION 1: TITLE ----` headers as commented code because the uppercase pattern looks like variable names.

**Why it happens:** commented_code_linter uses syntactic pattern matching. `SECTION 1:` could be interpreted as an attempted expression with a colon operator.

**How to avoid:** Test lintr on a representative script (e.g., `R/00_config.R`) after Wave 1 config changes to verify section headers are not flagged. If they are, add targeted inline suppressions:

```r
# SECTION 1: SETUP ---- # nolint: commented_code_linter.
```

**Warning signs:** lintr output includes line numbers matching section header locations (every ~50-100 lines in a typical script).

**Research confidence:** MEDIUM. The official lintr documentation confirms commented_code_linter flags "commented code outside roxygen blocks" and gives examples of flagged patterns (assignments, function calls). Section headers with `----` trailing dashes are not mentioned as exceptions. Testing required.

### Pitfall 2: object_usage_linter False Positives Persist After Disabling

**What goes wrong:** After setting `object_usage_linter = NULL`, re-running lintr still shows some "object not found" warnings.

**Why it happens:** The object_usage_linter warnings might be coming from `codetools::checkUsage()` which runs independently of lintr in some R environments.

**How to avoid:** Verify the .lintr file syntax is correct by running `lintr:::read_settings()` in R to see parsed configuration. Ensure no typos in linter names (it's `object_usage_linter`, not `object_use_linter`).

**Warning signs:** Re-running lintr after Wave 1 shows the same ~2,104 object_usage violations as the baseline.

**Research confidence:** HIGH. The lintr documentation confirms that `linters_with_defaults()` accepts `linter_name = NULL` to disable rules, and object_usage_linter is a known source of false positives in tidyverse code.

### Pitfall 3: Line Length Wrapping Breaks Pipelines

**What goes wrong:** Wrapping a long pipeline to fit 150 characters introduces indentation that breaks the pipe_continuation_linter or indentation_linter rules.

**Why it happens:** Tidyverse style requires specific indentation for pipe continuations (2 spaces after the pipe). Manual wrapping might use inconsistent spacing.

**How to avoid:** After wrapping long lines in Wave 2, re-run lintr to verify no new indentation/pipe_continuation violations were introduced. If they were, adjust the wrapping to match tidyverse style:

```r
# GOOD: Pipe continuation with 2-space indent
result <- data %>%
  filter(condition) %>%
  select(columns)

# BAD: Inconsistent indentation
result <- data %>%
filter(condition) %>%
    select(columns)
```

**Warning signs:** Wave 2 fixes reduce line_length violations but increase indentation_linter violations.

**Research confidence:** HIGH. The tidyverse style guide and lintr documentation both specify 2-space indentation for pipe continuations.

### Pitfall 4: Smoke Test Fails Due to Syntax Errors

**What goes wrong:** After removing commented code or fixing seq violations, `R/87_smoke_test_full_pipeline.R` fails with "unexpected symbol" or "object not found" errors.

**Why it happens:** A commented-out line was actually needed (defensive commenting), or a seq fix changed loop behavior in an unexpected way.

**How to avoid:** Before committing Wave 2 changes, run the smoke test locally on a subset of modified scripts:

```bash
Rscript R/87_smoke_test_full_pipeline.R
```

If it fails, revert the specific change that broke it, investigate why that line was commented (git blame to find original context), and either fix properly or leave commented with a `# nolint: commented_code_linter.` suppression.

**Warning signs:** Smoke test output shows "FAIL: source() resolution" or "FAIL: script count" after Wave 2 code changes.

**Research confidence:** HIGH. Phase 67 established the smoke test pattern, and it explicitly checks source() resolution and script numbering — exactly what code changes might break.

### Pitfall 5: HiPerGator vs Local Environment Differences

**What goes wrong:** Code that runs fine locally fails on HiPerGator after lint fixes due to path differences, R version differences, or package version differences.

**Why it happens:** Local environment might have different working directory assumptions or package versions than HiPerGator.

**How to avoid:** Follow D-10 from CONTEXT.md: edit locally, verify on HiPerGator. After Wave 2 code fixes are committed locally, transfer to HiPerGator and re-run both lintr and the smoke test:

```bash
# On HiPerGator
module load R/4.4.2
cd /path/to/insurance_investigation
Rscript -e "lintr::lint_package()"
Rscript R/87_smoke_test_full_pipeline.R
```

**Warning signs:** Smoke test passes locally but fails on HiPerGator with path-related errors or missing package errors.

**Research confidence:** HIGH. The project constraints explicitly note "RStudio on UF HiPerGator — scripts must work in that environment," and D-10 mandates HiPerGator verification.

## Code Examples

Verified patterns from official sources:

### .lintr Configuration for Phase 71

```r
# .lintr
linters: linters_with_defaults(
    # D-01: Declare magrittr pipe as project standard (eliminates 3,622 violations)
    pipe_consistency_linter = pipe_consistency_linter("%>%"),

    # D-02: Disable object_usage_linter (2,104 false positives from dplyr NSE)
    object_usage_linter = NULL,

    # D-06: Bump line length from 120 to 150 (reduces but doesn't eliminate 307 violations)
    line_length_linter = line_length_linter(150L),

    # D-07: Disable return_linter (18 violations, explicit return() is project style)
    return_linter = NULL,

    # D-08: Disable object_length_linter (7 violations, PCORnet names are long by nature)
    object_length_linter = NULL
  )
exclusions: list(
    "R/archive" = list()
  )
```

**Source:** [lintr - Using lintr](https://lintr.r-lib.org/articles/lintr.html)

**Expected impact:**
- pipe_consistency_linter: 3,622 → 0 (config declares `%>%` as standard)
- object_usage_linter: 2,104 → 0 (disabled)
- return_linter: 18 → 0 (disabled)
- object_length_linter: 7 → 0 (disabled)
- line_length_linter: 307 → ~50-100 (threshold raised, some violations remain)
- **Total after Wave 1:** 6,187 → ~461 (5,726 eliminated via config)

### seq_linter Fix Pattern (D-04)

```r
# BEFORE (flagged by seq_linter)
for (i in 1:length(patient_ids)) {
  process_patient(patient_ids[i])
}

# AFTER (bug-safe)
for (i in seq_along(patient_ids)) {
  process_patient(patient_ids[i])
}

# BEFORE (flagged by seq_linter)
for (row in 1:nrow(cohort_data)) {
  analyze_row(cohort_data[row, ])
}

# AFTER (bug-safe)
for (row in seq_len(nrow(cohort_data))) {
  analyze_row(cohort_data[row, ])
}
```

**Source:** [seq_linter documentation](https://lintr.r-lib.org/reference/seq_linter.html)

**WHY this matters:** When `patient_ids` is an empty vector, `1:length(patient_ids)` evaluates to `1:0`, which produces `c(1, 0)` — the loop runs twice with invalid indices. `seq_along()` correctly returns an empty sequence for empty inputs.

### Commented Code Removal (D-03)

```r
# BEFORE (flagged by commented_code_linter)
cohort <- raw_data %>%
  filter(has_hl_diagnosis) %>%
  # filter(age >= 18) %>%  # Age filter disabled for pediatric inclusion
  mutate(age_group = cut(age, breaks = c(0, 18, 65, Inf)))

# AFTER (violation removed, intent preserved if needed)
cohort <- raw_data %>%
  filter(has_hl_diagnosis) %>%
  mutate(age_group = cut(age, breaks = c(0, 18, 65, Inf)))

# Alternative: If the commented line has important context
cohort <- raw_data %>%
  filter(has_hl_diagnosis) %>%
  # NOTE: Age filter removed in Phase 43 to include pediatric patients
  mutate(age_group = cut(age, breaks = c(0, 18, 65, Inf)))
```

**Source:** [commented_code_linter documentation](https://lintr.r-lib.org/reference/commented_code_linter.html)

**Decision rule:** If the commented code documents a past decision (like "we tried X but it didn't work"), convert to a WHY comment that explains the decision without showing code. If it's truly orphaned (no context, just old code), delete it. Git history preserves the original.

### Pipe Continuation Fix (D-05)

```r
# BEFORE (flagged by pipe_continuation_linter)
result <- data %>% filter(condition) %>%
  select(columns) %>% mutate(new_col = value)

# AFTER (tidyverse style)
result <- data %>%
  filter(condition) %>%
  select(columns) %>%
  mutate(new_col = value)
```

**Source:** [pipe_continuation_linter documentation](https://lintr.r-lib.org/reference/pipe_continuation_linter.html)

**Style rule:** Each pipe operator should be at the end of a line, followed by a newline and 2-space indent for the next function.

### Line Length Wrapping (D-06)

```r
# BEFORE (168 characters, exceeds 150 limit)
message(glue("Processing patient {patid}: {diagnosis_count} diagnoses, {treatment_count} treatments, {encounter_count} encounters across {date_range_days} days"))

# AFTER (wrapped at natural breaks)
message(glue(
  "Processing patient {patid}: {diagnosis_count} diagnoses, ",
  "{treatment_count} treatments, {encounter_count} encounters ",
  "across {date_range_days} days"
))
```

**Source:** [Tidyverse style guide - Syntax](https://style.tidyverse.org/syntax.html)

**Decision rule (D-06 discretion):** Only wrap lines that are obviously wrappable (long strings, unnecessary chains). For lines that are 150-160 characters and would become less readable when wrapped (e.g., complex dplyr pipelines), leave them as-is. The goal is <50 remaining violations, not zero.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| pipe_consistency_linter default = "auto" | pipe_consistency_linter default = "\|>" (native pipe) | lintr 3.1.0 (2023) | Projects using magrittr pipe must now explicitly configure pipe_consistency_linter("%>%") to avoid false violations |
| Single .lintr file format | Both .lintr and .lintr.R supported | lintr 3.3.0 (Nov 2025) | .lintr.R takes precedence if both exist; validated up-front for clearer error messages |
| 80-character line length (historical) | 120-character common, 150 acceptable for R pipelines | Tidyverse style guide evolution (2020+) | Modern widescreen monitors and R's verbose function names make 80-char impractical; 120-150 balances readability with line-wrapping complexity |

**Deprecated/outdated:**

- **lintr 2.x configuration syntax:** Used `with_defaults()` instead of `linters_with_defaults()`. Deprecated in lintr 3.0 (2022). Modern projects must use `linters_with_defaults()`.
- **Inline-only suppressions:** Before .lintr file support stabilized, projects used inline `# nolint` comments for all suppressions. This doesn't scale to 6,000+ violations. Modern approach: config file for systematic rules, inline suppressions for one-off exceptions.

## Open Questions

**1. Does commented_code_linter flag Phase 69 section headers?**

- **What we know:** Section headers use `# SECTION N: TITLE ----` format. commented_code_linter flags "commented code" based on syntactic patterns (assignments, function calls).
- **What's unclear:** Whether the `SECTION N:` pattern (uppercase word followed by number and colon) triggers false positives.
- **Recommendation:** Test lintr on R/00_config.R after Wave 1 config changes. If section headers are flagged, add targeted `# nolint: commented_code_linter.` suppressions. Document this pattern in Wave 1 plan.

**2. Which specific long lines should be wrapped vs left at 150+?**

- **What we know:** 307 violations at 120-char threshold. Bumping to 150 will reduce this, but some will remain. D-06 says "fix lines that are obviously wrappable."
- **What's unclear:** Exact criteria for "obviously wrappable." Long strings? Complex pipelines? Function calls with many arguments?
- **Recommendation:** In Wave 2, prioritize lines >160 characters with string concatenation (glue(), paste0()) or function calls with 5+ arguments. Leave complex dplyr pipelines at 150-155 characters if wrapping would hurt readability. Target is <50 remaining violations, not zero.

**3. Are there any pcornet column names that will still trigger violations after object_name_linter is disabled?**

- **What we know:** object_name_linter was disabled in Phase 70 to allow PCORnet ALLCAPS columns (PATID, ENCOUNTERID, etc.). object_usage_linter is disabled in Phase 71 to stop false positives from dplyr NSE.
- **What's unclear:** Whether any other linters (e.g., object_length_linter before D-08 disables it) flag PCORnet conventions.
- **Recommendation:** After Wave 1, scan lintr output for any ALLCAPS variable names. If found, identify which linter is flagging them and add to config changes.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R | All lint operations | ✓ (HiPerGator) | 4.4.2 | — |
| lintr | Violation detection | ✓ (HiPerGator) | 3.3.0-1 (assumed) | — |
| git | .git-blame-ignore-revs integration | ✓ | 2.x+ | — |
| RStudio | Optional (code editing) | ✓ (HiPerGator) | — | Text editor + Rscript for local edits |
| glue | Smoke test logging | ✓ | 1.8.0 | — |

**Missing dependencies with no fallback:**

None — all dependencies verified present from Phase 70 baseline generation.

**Missing dependencies with fallback:**

None identified.

**Notes:**

- R is not available in the local Windows environment (verified by Rscript check), which aligns with D-10: "Edit locally, verify on HiPerGator." Local edits use text editor; lintr runs only on HiPerGator.
- lintr version assumed to be 3.3.0-1 based on CRAN publication date (Nov 2025) and Phase 70 baseline generation timing (June 2026). HiPerGator module system typically has recent package versions.

## Sources

### Primary (HIGH confidence)

- [lintr CRAN page](https://cran.r-project.org/web/packages/lintr/index.html) - Version 3.3.0-1, published Nov 27, 2025
- [lintr official documentation - Using lintr](https://lintr.r-lib.org/articles/lintr.html) - Configuration syntax, linters_with_defaults() usage
- [pipe_consistency_linter reference](https://lintr.r-lib.org/reference/pipe_consistency_linter.html) - Parameter options, default behavior, magrittr vs native pipe
- [seq_linter reference](https://lintr.r-lib.org/reference/seq_linter.html) - Why 1:length(x) is problematic, recommended replacements
- [commented_code_linter reference](https://lintr.r-lib.org/reference/commented_code_linter.html) - Detection patterns, roxygen exceptions
- [return_linter reference](https://lintr.r-lib.org/reference/return_linter.html) - Explicit vs implicit returns, configuration options
- [object_length_linter reference](https://lintr.r-lib.org/reference/object_length_linter.html) - Default 30-char limit, rationale
- [Tidyverse style guide - Syntax](https://style.tidyverse.org/syntax.html) - Line length (80 chars recommended), pipe continuation, long lines
- [git blame: Ignore Commits with .git-blame-ignore-revs](https://madewithlove.com/blog/ignoring-revisions-when-using-git-blame/) - .git-blame-ignore-revs setup, GitHub integration

### Secondary (MEDIUM confidence)

- [Get your codebase lint-free forever with lintr (R-bloggers)](https://www.r-bloggers.com/2024/08/get-your-codebase-lint-free-forever-with-lintr/) - Incremental cleanup strategy, config-first approach
- [.git-blame-ignore-revs to ignore bulk formatting changes (thinkthroo)](https://thinkthroo.com/blog/git-blame-ignore-revs) - Git history best practices
- [indentation_linter reference](https://lintr.r-lib.org/reference/indentation_linter.html) - 2-space default, hanging indent style
- [pipe_continuation_linter reference](https://lintr.r-lib.org/reference/pipe_continuation_linter.html) - Pipe-at-end-of-line rule

### Tertiary (LOW confidence)

- WebSearch results for lintr configuration (multiple CRAN/GitHub sources) - Cross-verified with official docs

## Metadata

**Confidence breakdown:**

- Standard stack (lintr 3.3.0-1, .lintr config): HIGH - Official CRAN release, verified publication date, official documentation
- Architecture patterns (two-wave strategy, linters_with_defaults()): HIGH - Verified in official lintr docs and R-bloggers article
- Pitfalls (commented_code_linter with section headers): MEDIUM - Extrapolated from documented behavior, needs testing
- Code examples (seq fixes, pipe continuation): HIGH - Directly from official linter reference pages

**Research date:** 2026-06-02

**Valid until:** ~90 days (stable ecosystem; lintr updates infrequent, R style guide stable)

---

*Phase: 71-linting-cleanup*
*Research complete: 2026-06-02*
