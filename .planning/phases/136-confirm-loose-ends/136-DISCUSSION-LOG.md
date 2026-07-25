# Phase 136: Confirm Loose Ends - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-25
**Phase:** 136-confirm-loose-ends
**Areas discussed:** CONFIRM-01 response, CONFIRM-02 corrected bound, Findings documentation format

---

## CONFIRM-01 Response

| Option | Description | Selected |
|--------|-------------|----------|
| Document only | Record file/line for each definition in code comments and a REQUIREMENTS note. Duplication stays as-is. | |
| Extract + document | Move clean_multi_value + union_field into utils_format.R, update R/52/R/101/R/104 to source it. suppress_small stays in R/106 (only used there). | ✓ |
| Document + cross-references | Keep inline copies, add comment pointing to canonical definition. No utils module. | |

**User's choice:** Extract + document
**Notes:** suppress_small stays in R/106 because it is only called within that single script; moving it to a utils module would add indirection without benefit.

---

## CONFIRM-02 Corrected Bound

| Option | Description | Selected |
|--------|-------------|----------|
| 2025-09-15 (exact extract cutoff) | Match the documented 20250915 cutoff precisely. | |
| 2025-12-31 (end of extract year) | Round up to year-end for a small safety margin. | |
| Sys.Date() (dynamic) | Never needs updating; data cutoff is enforced by the extract, not this bound. | ✓ |

**User's choice:** Sys.Date()
**Notes:** Add a comment explaining the intent — this upper bound is for catching gross outlier/sentinel dates; the actual data source cutoff is enforced by the extract itself.

---

## Findings Documentation Format

| Option | Description | Selected |
|--------|-------------|----------|
| Code comments only | Findings live in changed scripts only. | |
| REQUIREMENTS.md update | Mark CONFIRM-01 and CONFIRM-02 resolved with one-line finding notes. | ✓ |
| Dedicated findings doc | Write CONFIRM-FINDINGS.md with full investigation details. | |

**User's choice:** REQUIREMENTS.md update
**Notes:** Consistent with how all other v3.4 requirements track completions.

---

## Deferred Ideas

None surfaced during discussion.
