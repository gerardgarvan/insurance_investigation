# Phase 71: Linting Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-02
**Phase:** 71-linting-cleanup
**Areas discussed:** Pipe standardization, object_usage handling, Small violations triage, Execution strategy

---

## Pipe Standardization

| Option | Description | Selected |
|--------|-------------|----------|
| Configure lintr for %>% | Add pipe_consistency_linter(pipe='%>%') to .lintr. Eliminates 3,622 violations with zero code changes. The codebase already uses %>% consistently. | ✓ |
| Convert all to \|> | Replace 629 %>% with \|>. Modernizes to base R pipe but risky — \|> doesn't support dot-placeholder. | |
| Disable pipe_consistency entirely | Set pipe_consistency_linter=NULL. Less principled — doesn't declare project standard. | |

**User's choice:** Configure lintr for %>% (Recommended)
**Notes:** Codebase is 100% %>% (629 occurrences, zero |>). This is a project standard, not an inconsistency.

---

## object_usage Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Disable object_usage_linter | Set to NULL in .lintr. Most R/dplyr projects disable it. Eliminates 2,104 false positives. | ✓ |
| Keep it, add nolint per-line | Preserve linter, annotate 2,000+ lines. High maintenance burden. | |
| Keep it, triage manually | Review all 2,104 violations. Thorough but labor-intensive for known false-positive-heavy linter. | |

**User's choice:** Disable object_usage_linter (Recommended)
**Notes:** Overwhelmingly false positives from tidyverse NSE (unquoted column names like PATID, DX).

---

## Small Violations Triage

### Commented Code (57 violations)

| Option | Description | Selected |
|--------|-------------|----------|
| Remove all commented code | Delete all. Git preserves history. Phase 69 documented everything. | ✓ |
| Review case-by-case | Examine each of 57. Some may be intentional. | |
| Disable the linter | Keep all commented code as-is. | |

**User's choice:** Remove all commented code (Recommended)

### seq_linter (15 violations)

| Option | Description | Selected |
|--------|-------------|----------|
| Fix all 15 | Replace 1:length(x) with seq_along(x). Genuine bug prevention. | ✓ |
| Disable the linter | Not worth fixing. | |

**User's choice:** Fix all 15 (Recommended)

### Remaining Rules (line_length 307, pipe_continuation 30, indentation 27, return 18, object_length 7)

| Option | Description | Selected |
|--------|-------------|----------|
| Fix easy, disable rest | Fix indentation (27) and pipe_continuation (30). Disable return and object_length. Handle line_length separately. | ✓ |
| Fix everything aggressively | Manually fix all 461 violations. | |
| Disable everything remaining | Config away all remaining rules. | |

**User's choice:** Fix what's easy, disable the rest (Recommended)

### Line Length (307 violations)

| Option | Description | Selected |
|--------|-------------|----------|
| Fix obvious, bump to 150 | Fix wrappable lines, raise threshold from 120 to 150. | ✓ |
| Fix all 307 at 120 | Keep 120-char limit, wrap every violation. | |
| Disable line_length_linter | Remove the rule entirely. | |

**User's choice:** Fix obvious, bump limit to 150

---

## Execution Strategy

### Wave Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Two waves | Wave 1: config changes. Wave 2: code fixes. Config first for accurate re-run counts. | ✓ |
| One big wave | All changes in single plan. | |
| Per-rule waves | One plan per rule. Maximum granularity. | |

**User's choice:** Two waves (Recommended)

### Environment

| Option | Description | Selected |
|--------|-------------|----------|
| Edit locally, verify on HiPerGator | Code changes locally, lintr re-run and smoke test on HiPerGator. | ✓ |
| All on HiPerGator | Edit and verify entirely on HPC. | |
| You decide | Claude picks per fix type. | |

**User's choice:** Edit locally, verify on HiPerGator (Recommended)

---

## Claude's Discretion

- Exact order of code fixes within Wave 2
- Which specific long lines to wrap vs leave (within 150-char limit)
- Whether to batch code fixes by rule or by file
- How to structure lintr verification re-run on HiPerGator

## Deferred Ideas

None — discussion stayed within phase scope
