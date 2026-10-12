---
plan: 172-01
phase: 172-phase-164-closeout-and-r170-nhl-subsets
status: partial
run_date: 2026-10-12
---

# 172-01 Summary — Phase 164 Closeout + R/170 Regression

## Task 1: Prepare check script (auto) — COMPLETE

**Script written:** `scratch/172_closeout_checks.R`

**Static findings from code:**

| Item | Finding |
|------|---------|
| R/52 filename | `R/52_gantt_v2_export.R` |
| R/52 outputs | `output/gantt_episodes.csv`, `output/gantt_detail.csv` |
| R/142 outputs | `output/gantt_episodes_180.csv`, `output/gantt_detail_180.csv` |
| Overwrite risk | **YES** — `CONFIG$gantt_180_snapshot_path` was `output/gantt_episodes_180.csv` — same file R/142 writes |
| R/170 QC output | `output/internal/nhl_gantt_subsets_<YYYYMMDD>.xlsx` (sheets: KEY, NHL_only_episodes, HL_NHL_episodes, QC) |
| Bug fixed | `CUTOFF_DATE` not defined in standalone R/52 / R/142 runs → added env-var definition to both scripts (commit 43a02b1) |

---

## Task 2: HiPerGator run — COMPLETE (2026-10-12)

### Step 1 — Alias grep

All adriamycin/liposomal DRUG_NAME_ALIASES confirmed present in R/00_config.R (22 matching lines including inline comments and the 7 active alias entries). ✅

### Step 2 — Snapshot identity (before R/142)

```
path  : /blue/erin.mobley-hl.bcu/insurance_investigation/output/gantt_episodes_180.csv
bytes : 6,549,041  ← matches pinned
md5   : 69dc62e86be8e0647f6a4623dda901b6  ← matches pinned
```
✅ Snapshot was intact going into the run.

### Snapshot protection

Backup created at `output/gantt_episodes_180_20260814_PINNED.csv` (file.copy returned TRUE).

`CONFIG$gantt_180_snapshot_path` permanently re-pointed to the `_PINNED` copy in R/00_config.R during Task 3 (commit below). R/170 will always read the frozen August 2026 snapshot regardless of future R/142 re-runs.

### Step 7 — Snapshot identity (after R/142)

```
bytes : 6,513,241  ← changed (R/142 wrote new file)
md5   : 0af7c8c56ddfd3821487f1fb3b4e9cc9
```
Original path overwritten by R/142 — expected. Pinned backup preserved. ✅

---

## Phase 164 Reconciliation

### 90-day Gantt (`gantt_episodes.csv`)

| Check | Result |
|-------|--------|
| Rows with Adriamycin/Doxil/Caelyx/liposom (expect 0) | **0** ✅ |
| Rows with "Doxorubicin" (expect > 0) | 4,070 ✅ |
| Distinct patients old vs new | 2,384 → 2,384 (Δ = 0) ✅ |
| Row count old → new | 27,443 → 27,226 (Δ = −217) |
| Row drop explained by | 217 implausible death dates excluded by resolve_death_date (grace=30) — not dox collapse |

**90-day verdict: PASS** — rename fully applied; patient count preserved.

### 180-day Gantt (`gantt_episodes_180.csv`)

| Check | Result |
|-------|--------|
| Rows with Adriamycin/Doxil/Caelyx/liposom (expect 0) | **5** ❌ |
| Rows with "Doxorubicin" (expect > 0) | 2,649 |
| Distinct patients old vs new | 2,384 → 2,381 (Δ = −3) ❌ |
| Row count old → new | 22,210 → 21,993 (Δ = −217) |

**180-day verdict: FAIL** — 5 alias rows remain in the new Gantt; patient count unexpectedly dropped by 3.

**Root cause hypothesis:** R/142 reads `treatment_episodes_180_enriched.rds` (not the same source as R/52's `treatment_episodes.rds`). That enriched RDS may have been built from a pipeline stage that bypasses or predates the `canonicalize_drug_name` application, or has a separate drug-name fill path. The 5 rows and −3 patient discrepancy need investigation before Phase 164 can be closed.

---

## R/164 Baseline Counts

R/164 read `treatment_episode_detail.rds` (modified 2026-10-08). All 24,404 doxorubicin rows already read as "Doxorubicin" — no liposomal variants — with the warning:
> "All doxorubicin tokens are already 'Doxorubicin'. The RDS may postdate the Phase 164 alias change; restore a pre-change copy before trusting this baseline."

The RDS was updated in a prior run so this baseline cannot be used as a pre-rename reference. Noted but not blocking.

---

## R/170 Regression

R/170 ran against `output/gantt_episodes_180.csv` (the NEW, post-R/142 file — 21,993 rows), not the pinned snapshot. The snapshot size/MD5 warnings are **expected** because `CONFIG$gantt_180_snapshot_path` pointed at the overwritten file during this session (permanently fixed for future runs in Task 3).

### QC field comparison (old 20261008 vs new 20261012)

| Section | All fields | Match |
|---------|-----------|-------|
| (a) Group counts (G1 strict/loose, G2) | 849 / 1261 / 176 | ✅ All OK |
| (b/c) Match counts G1 + G2 | Sheet matched/unmatched, gantt matched/unmatched | ✅ All OK |
| (i) drug_names cross-check | Exact 1134, Norm-only 0, Mismatches 0, One-side 0 | ✅ All OK |
| (g) Duplicates | 0 chemo, 0 sheet | ✅ All OK |
| (h) Unexpected values | 0 | ✅ All OK |
| Snapshot size/MD5 | DIFF | ⚠️ Expected — R/170 read overwritten file |

**R/170 QC regression: PASS on all clinical fields.**

### Episode tab row counts (new run reads new Gantt)

| Tab | Old (20261008) | New (20261012) | Δ |
|-----|---------------|----------------|---|
| NHL_only_episodes | 2,615 | 2,598 | −17 |
| HL_NHL_episodes | 592 | 591 | −1 |

Differences reflect the new Gantt inputs (fewer rows after death exclusions and 3-patient drop), not a regression in the NHL subset logic. Group counts (849/1261/176) are identical.

### R/170 tests

`test-170-nhl-gantt-subsets.R`: **FAIL 0 | WARN 3 | SKIP 0 | PASS 40**

3 warnings = snapshot size/MD5 mismatch (expected — same root cause as above, fixed in Task 3).

---

## Smoke test

`R/88_smoke_test_comprehensive.R`: **ALL 921 CHECKS PASSED** ✅

SMOKE-168-01: 9/9 PASS

---

## Task 5 of 164-01-PLAN.md (HiPerGator run + reconciliation)

**Status: OPEN** — 90-day Gantt passes all Phase 164 checks. 180-day Gantt has 5 residual alias rows and an unexplained −3 patient drop. Phase 164 cannot be closed until the 180-day source is investigated.

---

## Open Items / Next Steps

1. **Investigate 5 residual alias rows in `gantt_episodes_180.csv`** — identify which upstream RDS or code path in R/142 bypasses `canonicalize_drug_name`. Likely `treatment_episodes_180_enriched.rds` was built before or via a path that doesn't apply the aliases.
2. **Explain −3 patient drop in 180-day patient count** — may be the same 5 rows collapsing patients, or a separate issue.
3. Once 180-day is clean, re-run this phase closeout to close RFSH-03.

---

## Artifacts produced this run

- `scratch/172_closeout_checks.R` — read-only check script
- `output/gantt_episodes_180_20260814_PINNED.csv` — protected pinned snapshot (HiPerGator only)
- `output/gantt_episodes_pre172.csv` — pre-run 90-day Gantt copy (HiPerGator only)
- `output/gantt_episodes_180_pre172.csv` — pre-run 180-day Gantt copy (HiPerGator only)
- `output/gantt_episodes.csv` — updated 90-day Gantt (rename applied ✅)
- `output/gantt_episodes_180.csv` — updated 180-day Gantt (rename partially applied — 5 rows remain ❌)
- `output/internal/nhl_gantt_subsets_20261012.xlsx` — new R/170 run

## Files committed this run

- `R/52_gantt_v2_export.R` — added `CUTOFF_DATE` definition (bug fix)
- `R/142_gantt_180_export.R` — added `CUTOFF_DATE` definition (bug fix)
- `R/00_config.R` — re-pointed `gantt_180_snapshot_path` to `_PINNED` copy permanently
- `scratch/172_closeout_checks.R` — new check script

## RFSH-03 status: OPEN

Phase 164 Task 5 not closed — 180-day rename incomplete. RFSH-03 remains open.
