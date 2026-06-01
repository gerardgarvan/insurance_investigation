# Phase 67: Post-Renumbering Inventory Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-01
**Phase:** 67-cancer-payer-qa-reorganization
**Areas discussed:** Phase repurposing scope, Smoke test placement, Unnumbered scripts, Index sync approach

---

## Phase Repurposing Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Inventory cleanup | Fix 66 collision, sync SCRIPT_INDEX.md, handle unnumbered scripts, create R/archive/ — all post-renumbering cleanup in one pass | ✓ |
| Split: cleanup + archival | Phase 67 = collision/index fixes only. Phase 68 = archival (REORG-04) + unnumbered script handling | |
| Merge with Phase 69 | Skip Phase 67, fold cleanup into Phase 69 (Script Documentation) since you'll be touching every file anyway | |

**User's choice:** Inventory cleanup (Recommended)
**Notes:** Combined approach keeps all post-renumbering cleanup in a single phase rather than splitting across multiple phases.

---

## Smoke Test Placement

| Option | Description | Selected |
|--------|-------------|----------|
| Move to 87 in test decade | 87_smoke_test_full_pipeline.R — it IS a test, and 86_smoke_test_foundation.R is already there. Keeps tests together. | ✓ |
| Keep at 66, renumber duplicate_dates | Bump all_site_duplicate_dates to 67 and shift overlap scripts +1. Tight fit in 60-69 decade (11 scripts for 10 slots). | |
| You decide | Claude picks the best placement based on codebase patterns | |

**User's choice:** Move to 87 in test decade (Recommended)
**Notes:** Smoke test is logically a test script and belongs in 80-89 alongside 86_smoke_test_foundation.R. Frees position 66 for the payer/QA script without cascading renumbers.

---

## Unnumbered Scripts

| Option | Description | Selected |
|--------|-------------|----------|
| Archive all to R/archive/ | These are all one-off diagnostics or helpers. Move to R/archive/ with a README explaining each. Keeps R/ clean. | ✓ |
| Keep as-is | Leave unnumbered in R/. They're clearly ad-hoc by lacking a number prefix. | |
| Number them in 90-99 | Give them numbers. 90-99 decade has 10 scripts (90-99), but some slots remain if we renumber. | |

**User's choice:** Archive all to R/archive/ (Recommended)
**Notes:** All 8 unnumbered scripts are one-off diagnostics or helpers. Archiving satisfies REORG-04. None have source() callers so archival has zero cross-reference impact.

---

## Index Sync Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Regenerate from filesystem | Script reads R/*.R, extracts header comments, rebuilds the entire index. Guaranteed accurate. Phase 66 had a regeneration script. | ✓ |
| Manual patch | Manually correct the mismatched entries. Faster but error-prone with 14+ discrepancies. | |
| You decide | Claude picks the approach based on the number of discrepancies | |

**User's choice:** Regenerate from filesystem (Recommended)
**Notes:** With 14+ discrepancies across cancer and payer/QA decades, manual patching is error-prone. Full regeneration guarantees accuracy.

---

## Gap-Fix Discussion (2026-06-01, post-verification)

**Trigger:** Verification found 3 gaps (5/7 truths verified). `--gaps` flag.

### SCRIPT_INDEX Regeneration (Plan 02)

| Option | Description | Selected |
|--------|-------------|----------|
| Full regen (Recommended) | Re-scan R/*.R filesystem and rebuild entire SCRIPT_INDEX.md from scratch — catches any other drift | ✓ |
| Patch 3 lines | Fix only lines 81-83: rename 67->66, 68->67, add missing 68_overlap_classification.R | |
| You decide | Claude picks the approach based on codebase patterns | |

**User's choice:** Full regen (Recommended)
**Notes:** Same approach as D-06, but plan 01's execution produced wrong numbers. Full regen ensures accuracy.

### Smoke Test Fix (Plan 02)

| Option | Description | Selected |
|--------|-------------|----------|
| Fix array + count | Update payer_expected to list all 10 correct scripts (60-69), change count from 9 to 10 | ✓ |
| Regen all arrays | Rebuild ALL decade arrays from filesystem (not just payer) to catch any other drift | |
| You decide | Claude picks based on verification report findings | |

**User's choice:** Fix array + count
**Notes:** Targeted fix (payer array only). Other decades were not flagged in verification.

---

## Claude's Discretion

- Archive README format and detail level
- Whether to update source() references inside archived scripts
- Smoke test internal self-references after rename
- Order of operations during execution
- ROADMAP success criteria update (9→10 scripts) — mechanical bookkeeping

## Deferred Ideas

- Phase 68 repurposing — could become script documentation prep or additional cleanup
- Cancer decade description accuracy — full regeneration will catch any remaining issues
- Rebuild ALL smoke test decade arrays (not just payer) in a future phase to catch any other drift
