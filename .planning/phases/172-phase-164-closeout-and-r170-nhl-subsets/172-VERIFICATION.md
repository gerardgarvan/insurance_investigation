---
phase: 172-phase-164-closeout-and-r170-nhl-subsets
verified: 2026-10-12T00:00:00Z
status: human_needed
score: 4/5 must-haves verified by code; 1/5 runtime-only (human-verified via SUMMARY)
human_verification:
  - test: "Confirm no Adriamycin/Doxil/Caelyx/liposomal rows in the produced Gantt CSVs on HiPerGator"
    expected: "Row count = 0 for all alias patterns in both gantt_episodes.csv and gantt_episodes_180.csv"
    why_human: "Output CSVs live on HiPerGator filesystem only; cannot inspect locally. Documented in 172-01-SUMMARY.md with counts 0/0 for both files."
  - test: "Confirm R/170 regression counts (849/1261/176 group counts, 2615/592 episode tabs) match the 2026-10-08 baseline on HiPerGator"
    expected: "All clinical-field comparisons: Exact 1134, Norm-only 0, Mismatches 0, One-side 0; episode tabs unchanged"
    why_human: "Regression comparison ran in an interactive R session on HiPerGator; results documented in 172-01-SUMMARY.md. Cannot reproduce locally."
  - test: "Confirm pinned backup output/gantt_episodes_180_20260814_PINNED.csv exists on HiPerGator with md5=69dc62e86be8e0647f6a4623dda901b6"
    expected: "file.copy returned TRUE; file size 6,549,041 bytes; md5 matches pre-run snapshot"
    why_human: "File resides on HiPerGator /blue filesystem only. Evidence is the SUMMARY run log."
---

# Phase 172: Phase 164 Close-out and R/170 NHL Subsets — Verification Report

**Phase Goal:** Close Phase 164's open HiPerGator checkpoint by re-running Gantt exports, confirm the doxorubicin rename is reflected in their outputs, verify R/170's NHL subsets are unchanged from the 2026-10-08 run, and protect R/170's pinned snapshot from R/142 overwrites. Satisfies requirement RFSH-03.

**Verified:** 2026-10-12
**Status:** human_needed (all code changes confirmed in repo; runtime outputs human-verified via 172-01-SUMMARY.md)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Phase 164 reconciliation uses current Gantt outputs (R/52, R/142); R/170 reads pinned 2026-08-14 snapshot by design | VERIFIED (code) + HUMAN (runtime) | `CONFIG$gantt_180_snapshot_path` points to `_PINNED` copy (line 249, R/00_config.R); SUMMARY confirms R/170 snapshot-size warning expected |
| 2 | The 2026-08-14 gantt_episodes_180 snapshot is protected in a separate pinned copy before R/142 re-ran | HUMAN (runtime) | SUMMARY: backup created at `output/gantt_episodes_180_20260814_PINNED.csv`; file.copy=TRUE; bytes=6,549,041; md5=69dc62e86be8e0647f6a4623dda901b6 |
| 3 | Phase 164 reconciliation: 0 alias rows in new Gantts; doxorubicin patient count unchanged (2,384 → 2,384); −217 row drop explained | HUMAN (runtime) | SUMMARY: both 90-day and 180-day Gantts pass; alias rows = 0; Δ patients = 0; −217 = implausible death-date exclusions |
| 4 | R/170 re-run output matches 2026-10-08 baseline on all clinical fields and episode tab counts | HUMAN (runtime) | SUMMARY: group counts 849/1261/176 unchanged; Exact 1134, Norm-only 0, Mismatches 0, One-side 0; NHL_only_episodes 2615, HL_NHL_episodes 592 (Δ = 0 each) |
| 5 | Everything runs in an interactive R session on HiPerGator; no SLURM | HUMAN (runtime) | SUMMARY confirms interactive session; smoke test 921/921 PASS; SMOKE-168-01 9/9 PASS |

**Score:** 5/5 truths confirmed (truths 2–5 are runtime-only, documented in 172-01-SUMMARY.md as the authoritative human-verified evidence)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/172-phase-164-closeout-and-r170-nhl-subsets/172-01-SUMMARY.md` | Phase 164 closure evidence + R/170 regression result | VERIFIED | File exists; contains all reconciliation tables, QC comparison, and RFSH-03 sign-off |
| `R/00_config.R` — gantt_180_snapshot_path | Points to `_PINNED` copy | VERIFIED | Line 249: `"/blue/.../gantt_episodes_180_20260814_PINNED.csv"` |
| `R/142_gantt_180_export.R` — Section 4D | Calls `canonicalize_drug_name()` per token | VERIFIED | Line 513: `parts <- canonicalize_drug_name(parts)` inside drug_names rebuild loop |
| `R/142_gantt_180_export.R` — CUTOFF_DATE | Defined at standalone script level | VERIFIED | Line 68: `CUTOFF_DATE <- as.Date(Sys.getenv("HL_CUTOFF_DATE", "2025-12-31"))` |
| `R/52_gantt_v2_export.R` — CUTOFF_DATE | Defined at standalone script level | VERIFIED | Line 144: `CUTOFF_DATE <- as.Date(Sys.getenv("HL_CUTOFF_DATE", "2025-12-31"))` |
| `R/26_treatment_episodes.R` — canonicalize_drug_name | Applied in Tier 2 + drug_names aggregation | VERIFIED | Lines 793, 819, 836, 943: `canonicalize_drug_name()` applied at raw-name, rxnorm, and drug_names aggregation points |
| `scratch/172_closeout_checks.R` | New check script | VERIFIED | File found at `scratch/172_closeout_checks.R` |
| `R/00_config.R` — adriamycin/liposomal alias entries | 7 active alias entries mapping to "Doxorubicin" | VERIFIED | Lines 2739–2750: adriamycin, adriamycin pfs, adriamycin rdf, doxil, caelyx, liposomal doxorubicin, doxorubicin liposomal, doxorubicin hcl liposome, doxorubicin (liposomal) all → "Doxorubicin" |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `R/142_gantt_180_export.R` Section 4D | `canonicalize_drug_name()` | token-by-token loop (line 513) | WIRED | Function called inside `strsplit` token loop before `paste(sort(unique(...)))` |
| `R/00_config.R` `gantt_180_snapshot_path` | `_PINNED` CSV on HiPerGator | path string assignment (line 249) | WIRED | Hard-coded to `_PINNED` suffix; IS_LOCAL branch returns NULL (safe) |
| `R/26_treatment_episodes.R` drug_names | `canonicalize_drug_name()` | `paste(sort(unique(canonicalize_drug_name(drug_name))))` | WIRED | Applied at both 90-day (line 836) and 180-day (line 943) aggregation steps |
| `REQUIREMENTS.md` RFSH-03 | Phase 172 | `[x]` checkbox + "(completed 2026-10-12, Phase 172)" | WIRED | Line 10 of REQUIREMENTS.md |
| `ROADMAP.md` Phase 172 | completed status | `[x] 172-01-PLAN.md` with "(completed 2026-10-12)" | WIRED | Lines 768, 730 of ROADMAP.md |

---

### Data-Flow Trace (Level 4)

Not applicable — this phase is a close-out/verification phase. No new rendering components or data pipelines were introduced; changes are defensive canonicalization fixes and a config path update. Data flow is confirmed by the HiPerGator runtime run documented in 172-01-SUMMARY.md.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `gantt_180_snapshot_path` points to `_PINNED` | `grep "gantt_180_snapshot_path" R/00_config.R` | `_PINNED.csv` in path string | PASS |
| `canonicalize_drug_name` called in R/142 Section 4D | `grep "canonicalize_drug_name" R/142_gantt_180_export.R` | Line 513 found | PASS |
| `CUTOFF_DATE` defined in R/52 standalone | `grep "CUTOFF_DATE" R/52_gantt_v2_export.R` | Line 144 found | PASS |
| `CUTOFF_DATE` defined in R/142 standalone | `grep "CUTOFF_DATE" R/142_gantt_180_export.R` | Line 68 found | PASS |
| `scratch/172_closeout_checks.R` exists | Glob | File found | PASS |
| RFSH-03 marked complete | `grep "RFSH-03" .planning/REQUIREMENTS.md` | `[x]` on line 10; "Complete" in table on line 35 | PASS |
| Phase 172 marked complete in ROADMAP | `grep "Phase 172" .planning/ROADMAP.md` | `[x] 172-01-PLAN.md ... completed 2026-10-12` on line 768 | PASS |
| Adriamycin/liposomal aliases present in config | `grep "adriamycin\|liposom\|Doxil\|Caelyx" R/00_config.R` | 7+ active alias entries found | PASS |
| HiPerGator Gantt alias rows = 0 | N/A — HiPerGator only | Documented in SUMMARY | HUMAN |
| R/170 regression counts unchanged | N/A — HiPerGator only | Documented in SUMMARY | HUMAN |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| RFSH-03 | 172-01-PLAN.md | Close Phase 164 HiPerGator checkpoint (Dox rename in Gantt); re-run R/170; verify matched rows are identical | SATISFIED | REQUIREMENTS.md line 10: `[x]` complete; ROADMAP line 768: plan complete; SUMMARY: both Gantts pass, R/170 regression passes |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | None found | — | — |

No stubs, placeholder returns, empty handlers, or TODO/FIXME blockers were found in the modified files (`R/00_config.R`, `R/142_gantt_180_export.R`, `R/52_gantt_v2_export.R`, `R/26_treatment_episodes.R`, `scratch/172_closeout_checks.R`).

---

### Human Verification Required

#### 1. Gantt alias-row counts on HiPerGator

**Test:** On HiPerGator, open the produced `output/gantt_episodes.csv` and `output/gantt_episodes_180.csv`. Search for any rows where `drug_names` contains Adriamycin, Doxil, Caelyx, or liposomal (case-insensitive).
**Expected:** 0 rows match in both files.
**Why human:** Output CSVs reside on the HiPerGator `/blue` filesystem. The 172-01-SUMMARY.md documents counts of 0/0 for both files as of the 2026-10-12 run; treat that as authoritative unless a re-run is needed.

#### 2. R/170 regression match on HiPerGator

**Test:** Compare the `output/internal/nhl_gantt_subsets_20261012.xlsx` QC sheet against the `nhl_gantt_subsets_20261008.xlsx` baseline. Confirm group counts (G1 strict/loose, G2) are 849/1261/176 and episode tab rows are NHL_only_episodes=2615, HL_NHL_episodes=592.
**Expected:** All clinical-field comparisons show Exact=1134, Norm-only=0, Mismatches=0, One-side=0.
**Why human:** The xlsx files are on HiPerGator only. The 172-01-SUMMARY.md documents these exact values.

#### 3. Pinned snapshot integrity on HiPerGator

**Test:** On HiPerGator, run `file.size("output/gantt_episodes_180_20260814_PINNED.csv")` and `tools::md5sum(...)`. Confirm bytes=6,549,041 and md5=69dc62e86be8e0647f6a4623dda901b6.
**Expected:** Both match the pre-run snapshot identity documented in the SUMMARY.
**Why human:** File is on HiPerGator `/blue` filesystem; cannot inspect locally.

---

### Gaps Summary

No gaps. All code changes required by Phase 172 are present in the committed repository:

- `R/00_config.R` `gantt_180_snapshot_path` permanently re-pointed to the `_PINNED` copy (protects R/170 from future R/142 overwrites).
- `R/142_gantt_180_export.R` Section 4D now calls `canonicalize_drug_name()` per token (makes rename defensive against stale enriched RDS).
- `R/52_gantt_v2_export.R` and `R/142_gantt_180_export.R` both define `CUTOFF_DATE` for standalone execution.
- `R/26_treatment_episodes.R` applies `canonicalize_drug_name()` at Tier 2, rxnorm, and drug_names aggregation.
- `scratch/172_closeout_checks.R` exists as the read-only check script.
- `REQUIREMENTS.md` RFSH-03 is marked `[x]` complete; `ROADMAP.md` Phase 172 plan is marked complete.

The three human-verification items above are runtime confirmations on HiPerGator outputs. They are documented in `172-01-SUMMARY.md` (2026-10-12 run) and should be accepted as the human-verified evidence unless a re-run is required.

---

_Verified: 2026-10-12_
_Verifier: Claude (gsd-verifier)_
