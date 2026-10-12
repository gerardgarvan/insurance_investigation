---
phase: 174
name: Smoke-Check Discrepancy
milestone: v3.9
---

# Phase 174 Context: Smoke-Check Discrepancy

## Phase Goal
R/88 PASS count equals total check count, OR a written explanation of the gap is present in the phase SUMMARY.

## Root Cause (Investigated)

The 920 PASS / 921 total discrepancy is caused by the `IS_LOCAL` conditional block in R/88 (lines ~1259–1293):

**Local mode** (`IS_LOCAL = TRUE`): 4 environment checks
1. "Local mode: data_dir points to tests/fixtures"
2. "Local mode: DuckDB path in tempdir()"
3. "Local mode: cache_dir in tempdir()"
4. "Local mode: 1 thread configured"

**Production/HiPerGator mode** (`IS_LOCAL = FALSE`): 3 environment checks
1. "Production mode: data_dir points to /orange/"
2. "Production mode: DuckDB path in /blue/"
3. "Production mode: thread count >= 1"

Result: local runs produce 921, HiPerGator runs produce 920. The difference is by design (each environment validates different path constraints), not a bug.

## Secondary Issues (Not Causing the 920/921 Gap, But Notable)

1. **Sections 135 and 137** use checker functions (`.p135_check`, `check_137`) that increment only section-level counters (`p135_pass`, `p137_pass`) but NOT global `passed`/`failed`. These 25+14=39 checks are invisible to the global total. This was pre-existing behavior from when those sections were written.

2. **Sections 138, 139, 144** use checker functions where `passed <<- passed + 1L` runs unconditionally (both on pass AND fail), double-counting failures. Known pattern but not the cause of 920/921.

## Resolution Options

**Option A — Document** (recommended): Write a clear explanation in SUMMARY that the 920/921 gap is by-design: IS_LOCAL adds 1 extra local-mode check (cache_dir in tempdir) that has no production equivalent, so local=921 and HiPerGator=920 are both correct for their environments.

**Option B — Fix**: Add a 4th production check to the `else` branch (e.g., "Production mode: cache_dir in /blue/") to equalize counts at 921 on both sides.

## Success Criteria
1. R/88 PASS count equals total check count (option B), OR a written explanation is in SUMMARY (option A)
2. R/88 run on HiPerGator confirms the result
3. ROADMAP.md Phase 174 ticked only after HiPerGator confirmation

## Key Files
- `R/88_smoke_test_comprehensive.R` — lines 1259–1293 (IS_LOCAL conditional block)
- `.planning/phases/174-smoke-check-discrepancy/` — this phase
- `.planning/ROADMAP.md` — Phase 174 entry

## Prior Art
- Phase 173 SUMMARY: "920 PASS" on HiPerGator
- Phase 170 SUMMARY: "921 PASS" (local/offline run)
- Milestone audit: gap documented as code-structural (921) vs HiPerGator runtime (920)
