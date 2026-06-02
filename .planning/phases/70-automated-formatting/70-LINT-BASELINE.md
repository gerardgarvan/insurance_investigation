# Lint Baseline Report (Phase 70)

**Generated:** 2026-06-02
**Configuration:** .lintr (object_name_linter disabled, line_length_linter(120))
**Scope:** R/ directory excluding R/archive/ (67 numbered scripts + 8 utils = 75 files; 71 had violations)

## Summary

| Metric | Count |
|--------|-------|
| Total violations | 6,187 |
| Files affected | 71 |
| Unique rules triggered | 9 |

## Rules by Frequency

| Rank | Linter | Count | % of Total |
|------|--------|-------|------------|
| 1 | pipe_consistency_linter | 3,622 | 58.5% |
| 2 | object_usage_linter | 2,104 | 34.0% |
| 3 | line_length_linter | 307 | 5.0% |
| 4 | commented_code_linter | 57 | 0.9% |
| 5 | pipe_continuation_linter | 30 | 0.5% |
| 6 | indentation_linter | 27 | 0.4% |
| 7 | return_linter | 18 | 0.3% |
| 8 | seq_linter | 15 | 0.2% |
| 9 | object_length_linter | 7 | 0.1% |

## Configuration Verification

- [x] object_name_linter: Disabled (0 violations -- PCORnet ALLCAPS columns excluded)
- [x] line_length_linter: Set to 120 characters (307 violations at 120-char threshold)

## Notes for Phase 71

- **Top 2 rules account for 92.5% of all violations** (pipe_consistency + object_usage)
- `pipe_consistency_linter` (3,622): Likely mix of `%>%` and `|>` pipe operators -- batch-fixable with find/replace
- `object_usage_linter` (2,104): Variables defined but not used, or used but not visible to lintr's static analysis (common with PCORnet column references in dplyr pipelines)
- `line_length_linter` (307): Lines exceeding 120 characters -- may need manual wrapping
- Rules with <30 violations (commented_code, pipe_continuation, indentation, return, seq, object_length) can be fixed individually or selectively disabled
- Total violation count (6,187) is the starting baseline for Phase 71 cleanup

---
*Phase: 70-automated-formatting*
*Generated: 2026-06-02*
