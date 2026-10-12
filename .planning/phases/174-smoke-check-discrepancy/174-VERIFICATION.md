---
phase: 174-smoke-check-discrepancy
verified: 2026-10-12T00:00:00Z
status: passed
score: 5/5 must-haves verified
gaps:
  - truth: "STATE.md records Phase 174 status and the new R/88 baseline total"
    status: resolved
    reason: "STATE.md updated: Current focus advanced to Phase 175, Phase 174 close-out note added with 963 baseline, FAIL==0 confirmed."
    artifacts:
      - path: ".planning/STATE.md"
        issue: "Phase field still reads 'Phase: 174 (smoke-check-discrepancy) — EXECUTING'; no mention of 963 baseline"
    missing:
      - "Update STATE.md: phase status → complete, current focus → Phase 175, R/88 baseline total → 963"
---

# Phase 174: Smoke-Check Discrepancy Verification Report

**Phase Goal:** Make R/88's final summary trustworthy — PASS == total with FAIL == 0 on HiPerGator, where every check is counted once and failures are counted as failures. Resolve the 920/921 discrepancy.
**Verified:** 2026-10-12
**Status:** gaps_found — one housekeeping gap (STATE.md not updated); core code changes verified
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | 920 vs 921 cause established from actual HiPerGator output | VERIFIED | SUMMARY documents "ALL 920 CHECKS PASSED" footer + "character(0)" FAIL lines from Task 0; identifies IS_LOCAL asymmetry (local 4 ENV checks, production 3) as the source of the 1-check difference |
| 2 | Every check updates global passed/failed exactly once — sections 135, 137, 138, 139, 144 fixed | VERIFIED | Commit d48030c; `.p135_check` (line 4665-4669) and `check_137` (line 4830-4834) now use `passed <<-`/`failed <<-`; `check_138/139/144` had unconditional `passed <<-` removed (3 deletions in diff) and now increment only in pass branch |
| 3 | Production branch checks cache_dir under /blue/ with a guard, so NULL/missing FAILS | VERIFIED | Line 1295-1298: `check("Production mode: cache_dir in /blue/", !is.null(CONFIG$cache$cache_dir) && grepl("^/blue/", CONFIG$cache$cache_dir))`; production branch now has 4 checks (grepped: 4 "Production mode:" lines at 1284, 1288, 1292, 1296) |
| 4 | Acceptance is PASS == total and FAIL == 0; total computed dynamically (not pre-set) | VERIFIED | Line 6730: `total <- passed + failed`; footer at 6731-6735 prints `ALL {total} CHECKS PASSED` when `failed == 0`; SUMMARY records 963 confirmed on HiPerGator (920 + 28 §135 + 14 §137 + 1 cache_dir = 963) |
| 5 | STATE.md updated with Phase 174 status and new R/88 baseline total | FAILED | STATE.md still reads "Phase: 174 (smoke-check-discrepancy) — EXECUTING", "Current focus: Phase 174", and the only baseline reference is "ALL 920 R/88 CHECKS PASSED" in Phase 173's close-out note. No mention of 963. |

**Score: 4/5 truths verified**

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/88_smoke_test_comprehensive.R` | Corrected global counters; guarded production cache_dir check | VERIFIED | Contains "Production mode: cache_dir in /blue/" at line 1296; `passed <<-`/`failed <<-` present in all five section checker functions; commit d48030c is the only post-Phase-173 change to this file |
| `.planning/phases/174-smoke-check-discrepancy/174-01-SUMMARY.md` | Root cause, counter fixes, before/after totals, HiPerGator confirmation | VERIFIED | Documents root cause (IS_LOCAL asymmetry + §135/§137 not reaching global counters), per-section counter table, before=920/after=963, arithmetic, and FAIL=0 confirmation |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `.p135_check` | global `passed`/`failed` | `passed <<- passed + 1L` / `failed <<- failed + 1L` in function body | WIRED | Lines 4665-4669; confirmed by git diff adding these two lines |
| `check_137` | global `passed`/`failed` | `passed <<- passed + 1L` / `failed <<- failed + 1L` in function body | WIRED | Lines 4830-4834 |
| `check_138` | global `passed`/`failed` | conditional `passed <<-` (pass) / `failed <<-` (fail) | WIRED | Lines 4907-4912; old unconditional `passed <<-` removed |
| `check_139` | global `passed`/`failed` | conditional `passed <<-` (pass) / `failed <<-` (fail) | WIRED | Lines 4974-4979 |
| `check_144` | global `passed`/`failed` | conditional `passed <<-` (pass) / `failed <<-` (fail) | WIRED | Lines 5047-5052 |
| footer `total` | `passed + failed` | `total <- passed + failed` | WIRED | Line 6730; dynamic computation, not pre-set |
| production branch | cache_dir check | 4th `check()` call in `else` block | WIRED | Lines 1295-1298; grep confirms 4 "Production mode:" lines |

---

### Counter Fix Detail

The PLAN identified five sections with broken counter behaviour. All five are verified fixed:

| Section | Checker fn | Old behaviour | New behaviour | Calls |
|---------|-----------|---------------|---------------|-------|
| 135 | `.p135_check` | Never updated globals (only section counters) | `passed <<-` on pass, `failed <<-` on fail | 28 (24 direct + 1 loop over 4 files) |
| 137 | `check_137` | Never updated globals (only section counters) | `passed <<-` on pass, `failed <<-` on fail | 14 |
| 138 | `check_138` | Unconditional `passed <<- passed + 1L` (failures counted as passes) | Conditional: pass branch only | 12 |
| 139 | `check_139` | Unconditional `passed <<- passed + 1L` (failures counted as passes) | Conditional: pass branch only | 14 |
| 144 | `check_144` | Unconditional `passed <<- passed + 1L` (failures counted as passes) | Conditional: pass branch only | 22 |

Note on §135 call count: grep `-c` returns 25 source lines, but line 4740 is inside a `for` loop over 4 files, so the runtime call count is 28. The SUMMARY's "28" is correct.

---

### Generic `check()` Function

The generic `check()` uses `if (condition)` not `isTRUE(condition)`. The PLAN permitted leaving it unchanged if Task 1 found it did not silently pass logical(0)/NA — in R, `if (logical(0))` and `if (NA)` both throw errors rather than passing silently, satisfying the "fail rather than pass silently" requirement. This is correct.

---

### Arithmetic Verification

| Metric | Value |
|--------|-------|
| Before (Task 0 HiPerGator footer) | ALL 920 CHECKS PASSED |
| §135 checks added to global | +28 |
| §137 checks added to global | +14 |
| cache_dir check added | +1 |
| §138/139/144 net change to total | 0 (all passing on HiPerGator) |
| Predicted after | 963 |
| Actual after (SUMMARY Task 3) | ALL 963 CHECKS PASSED |
| FAIL lines after | character(0) |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| SMOKE-174-01 | 174-01-PLAN.md | R/88 final summary trustworthy: PASS == total, FAIL == 0, every check counted once | SATISFIED | All five section checkers fixed; footer computed dynamically; HiPerGator confirms 963/963 per SUMMARY |

---

### Anti-Patterns Found

None in `R/88_smoke_test_comprehensive.R` relevant to the phase goal. The section-level checkers that used `passed <- passed + 1L` (single arrow) at top-level code (lines 3307-4439) are in sections 30-31, running at script top-level where `<-` and `<<-` are equivalent — these are not bugs.

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — no runnable entry point on the local machine (no R interpreter; the only valid run is interactive R on HiPerGator). The SUMMARY documents the HiPerGator run result (2026-10-12, ALL 963 CHECKS PASSED, FAIL=character(0)).

---

### Human Verification Required

None. The HiPerGator run was performed and documented in 174-01-SUMMARY.md. The only gap (STATE.md) is a housekeeping edit verifiable by inspection.

---

### Gaps Summary

One gap blocks a clean close-out: **STATE.md was not updated** after Phase 174 completed. The file still shows the phase as executing, references the pre-fix baseline of 920, and does not record the new baseline of 963. The PLAN explicitly required updating STATE.md in Task 5.

All code changes are verified correct. The core goal — trustworthy R/88 summary where PASS == total and FAIL == 0 — is achieved in the codebase. The gap is administrative only and does not affect R/88's correctness on HiPerGator.

**To close:** Update `.planning/STATE.md` to reflect Phase 174 complete, advance current focus to Phase 175, and record the R/88 baseline as 963.

---

_Verified: 2026-10-12_
_Verifier: Claude (gsd-verifier)_
