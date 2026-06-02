# Phase 70: Automated Formatting - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-06-01
**Phase:** 70-automated-formatting
**Areas discussed:** Comment & header safety, Commit strategy, lintr rule tuning, Archive handling

---

## Comment & Header Safety

| Option | Description | Selected |
|--------|-------------|----------|
| Dry-run + diff review | Run styler in dry-run mode first, capture the diff, and scan for comment changes before applying. Gives a chance to spot header/section damage before committing. | |
| Trust styler defaults | styler preserves comment text and only adjusts code formatting. Apply directly -- risk of comment damage is low since headers use standalone comment lines. | |
| Manual pre-check | Manually inspect a sample of scripts after formatting to verify headers and section markers survived. | |

**User's choice:** Dry-run + diff review (Recommended)
**Notes:** None

### Follow-up: Response to comment changes

| Option | Description | Selected |
|--------|-------------|----------|
| Fix and rerun | Adjust .stylerignore or styler config to exclude problematic patterns, then rerun. | |
| Accept minor shifts | Accept cosmetic changes; only block if content or structure is lost. | |
| You decide | Claude assesses whether changes are harmless alignment tweaks or structural damage. | |

**User's choice:** You decide
**Notes:** Claude has discretion to assess comment changes as harmless vs structural

---

## Commit Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Single commit | One commit for all styler changes. Standard practice -- git blame has --ignore-revs to skip formatting commits. | |
| Per-decade commits | One commit per decade. More granular rollback but 8+ commits for a mechanical change. | |
| Two commits: code + config | First commit creates .stylerignore and config. Second applies formatting. | |

**User's choice:** Single commit (Recommended)
**Notes:** None

### Follow-up: .git-blame-ignore-revs

| Option | Description | Selected |
|--------|-------------|----------|
| Yes | Create .git-blame-ignore-revs file. Standard practice; GitHub supports it natively. | |
| No | Skip -- not worth the overhead. | |

**User's choice:** Yes (Recommended)
**Notes:** None

---

## lintr Rule Tuning

| Option | Description | Selected |
|--------|-------------|----------|
| Start with defaults + 2 overrides | Use lintr defaults, disable object_name_linter, set line_length(120). Run baseline, then evaluate. | |
| Aggressive tuning upfront | Pre-disable rules likely to produce noise for PCORnet analysis code. | |
| Minimal config | Only the two required rules. Maximum strictness. | |

**User's choice:** Start with defaults + 2 overrides (Recommended)
**Notes:** None

### Follow-up: Baseline recording format

| Option | Description | Selected |
|--------|-------------|----------|
| Summary count + breakdown by rule | Total count and top-N rules by frequency. Gives Phase 71 a clear target. | |
| Full lint report saved to file | Complete lintr output (file, line, rule, message) saved as work list. | |
| Count only | Just the total number. Phase 71 runs its own full lint. | |

**User's choice:** Summary count + breakdown by rule (Recommended)
**Notes:** None

---

## Archive Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Exclude from both | Add R/archive/ to .stylerignore and exclude from lintr. Deprecated scripts don't inflate baseline. | |
| Format but don't lint | Apply styler for consistency but exclude from lintr baseline. | |
| Include in both | Treat archive scripts the same as active scripts. | |

**User's choice:** Exclude from both (Recommended)
**Notes:** None

---

## Claude's Discretion

- Exact .lintr syntax and configuration format
- Whether to use `styler::style_dir()` or `styler::style_file()` for application
- How to structure the lint baseline output
- Whether additional files beyond R scripts need .stylerignore entries
- Wave/plan structure for execution
- Assessment of dry-run comment changes (harmless vs structural)

## Deferred Ideas

None -- discussion stayed within phase scope
