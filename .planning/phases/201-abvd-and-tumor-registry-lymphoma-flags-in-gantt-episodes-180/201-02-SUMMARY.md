---
phase: 201-abvd-and-tumor-registry-lymphoma-flags-in-gantt-180
plan: 02
status: partial — awaiting Task 4 (HiPerGator R/88 run)
completed_tasks: 3 of 5 (Tasks 1, 2, 3 done; Task 4 checkpoint; Task 5 drafted)
commits:
  - 3c1d1f4: "feat(201-02): update R/88 column checks 26->30 and add Section 15bd (ABVD-TR-201)"
  - e221ccd: "chore(201-02): update SCRIPT_INDEX R/142 entry to 30 columns, Phase 201 outputs"
---

# Phase 201 Plan 02 Summary: R/88 smoke-test updates and AC handoff

## Tasks completed locally

### Task 1: Update existing column-count checks

- `15bb [c2]` (line ~7528): `length(gantt_180_hdr_bb) == 26L` → `30L`; label updated to "has 30 columns"; comment `# 30 since Phase 201`.
- `15bc [c1]` (line ~7678): `length(g180_nms) == 26L` → `30L`; label and comment updated.
- Verified: no remaining `26L` column-count check for `gantt_episodes_180` in R/88. The `g180_nms[26L]` position check for `immune_flag_dx` is unchanged (column 26 is still at position 26).

### Task 2: New Section 15bd (ABVD-TR-201)

Inserted before `# SECTION 16: SUMMARY` using the 15bc counter pattern (`p201_chk`, `p201_skip_fn`, `p201_pass/fail/skip`, increments global `passed/failed/skipped`).

Config / unit checks (always run): [a1]–[a6].
Real-data checks: skip all when `gantt_episodes_180.csv` absent; read with `colClasses = "character"`.
Checks implemented: [c1]–[c5], [d1]–[d2], [e1]/[e1b]/[e1c], [e2]–[e4], [f1]–[f3], [g1].
[f3] reports rather than forces FAIL (per plan spec).

Parse: `tools/rcheck.sh parse R/88_smoke_test_comprehensive.R` → 0 failed.
ABVD-TR-201 occurrences: 43.

### Task 3: SCRIPT_INDEX

R/142 entry updated: 30 columns; lists cols 24–26 (Phase 199) and cols 27–30 (Phase 201); notes `output/internal/tr_hl_not_in_gantt_180.csv`.

## Task 4: HiPerGator run (PENDING — checkpoint)

After syncing, run:

```r
module load R/4.5
R --no-save
source("R/88_smoke_test_comprehensive.R", local = new.env(parent = globalenv()))
```

Paste back the 15ba, 15bb, 15bc, 15bd tallies and the overall FAIL count. Expected: all four sections 0 FAIL; no new FAILs beyond the Phase 199 baseline of 9.

---

## Task 5: Handoff note for AC

**[Draft — Gerard sends after Task 4 passes]**

---

Hi AC,

Attached is the regenerated `gantt_episodes_180.csv`. The file now has 30 columns; columns 1–26 are unchanged from the version delivered after Phase 199.

**Four new columns (27–30):**

| Col | Name | Level | Values |
|----:|------|-------|--------|
| 27 | `ever_abvd` | patient | TRUE / FALSE (never blank) |
| 28 | `abvd_episode` | episode row | TRUE / FALSE (never blank) |
| 29 | `tr_hl_dx` | patient | TRUE / FALSE / blank |
| 30 | `tr_nhl_dx` | patient | TRUE / FALSE / blank |

**ABVD definition (`ever_abvd`, `abvd_episode`):**

ABVD = doxorubicin + bleomycin + vinblastine + dacarbazine (all four canonical tokens, re-applied after drug-name canonicalization). AVD (bleomycin dropped) also counts toward these flags. BV+AVD, Nivo+AVD, and ABVD with an added agent (e.g., vincristine, etoposide, rituximab) do not count — those episodes are labeled ABVD_PLUS internally and flagged FALSE. This follows an open team question (D-201-01) where the default is no. `ever_abvd` is constant within patient. `abvd_episode` marks each Chemotherapy episode row; FALSE on all other row types. The initial ABVD treatment date is the earliest `episode_start` where `abvd_episode` is TRUE for that patient.

Quick counts (from the R/142 run): `abvd_episode` TRUE — full ABVD 1,151 episodes, AVD 529 episodes. `ever_abvd` TRUE — 1,525 patients; first chemotherapy episode is ABVD for 1,466 patients.

**Tumor-registry flags (`tr_hl_dx`, `tr_nhl_dx`):**

Derived from TUMOR_REGISTRY_ALL histology (ICD-O-3 4-digit codes). Three states: TRUE = patient in registry with matching histology; FALSE = patient in registry, histology not matched; blank = patient not in any tumor registry table.

HL histology set: ICD-O-3 codes 9650–9667 (the standard `hl_histology` list in use since the start of the project).

NHL histology set: has not been validated against our registry extract (open item D-201-03). The flag ships with that caveat; the QC block prints every lymphoid-range code (9590–9999) seen in registry rows for export patients that falls outside both lists, so the team can review.

Quick counts: `tr_present` (in registry) — 863 patients; `tr_hl_dx` TRUE 600, FALSE 263, blank 7,557; `tr_nhl_dx` TRUE 154, FALSE 709, blank 7,557; both TRUE — 11 patients.

**TR-HL patients not in the file:**

121 patients with a tumor-registry HL histology are absent from `gantt_episodes_180.csv`. All 121 are absent because they are not in `confirmed_hl_cohort.rds` (reason r1 — the cohort-entry step excluded them before the Gantt file is built). Adding them requires a cohort change outside the scope of this phase; we will raise this with the team as a follow-up (D-201-04). An internal file listing these patients and their reason codes has been retained but is not attached.

Please let me know if you have questions.

Best, Gerard

---

## Deviations from Plan

None. Plan executed as written.

## Self-Check

Pending Task 4 (HiPerGator run). Will be completed on continuation.
