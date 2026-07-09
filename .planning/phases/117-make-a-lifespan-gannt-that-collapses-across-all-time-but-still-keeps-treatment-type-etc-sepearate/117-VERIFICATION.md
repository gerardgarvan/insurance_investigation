---
phase: 117-make-a-lifespan-gannt-that-collapses-across-all-time-but-still-keeps-treatment-type-etc-sepearate
verified: 2026-07-09T00:00:00Z
status: human_needed
score: 6/6 must-haves verified
human_verification:
  - test: "Run R/101 on HiPerGator after a full R/39/R/52 run. Confirm output/gantt_lifespan.csv is produced with fewer rows than gantt_episodes.csv."
    expected: "File exists, row count < gantt_episodes.csv row count, zero rows have treatment_type in c('Death','HL Diagnosis')"
    why_human: "Requires real PCORnet data on HiPerGator. No output CSV is accessible locally."
  - test: "Spot-check one patient x treatment_type in gantt_lifespan.csv against the underlying rows in gantt_episodes.csv."
    expected: "episode_start == min of underlying episode_start values, episode_stop == max, episode_count == number of merged rows, multi-value fields are the unioned/deduped/sorted union of underlying cell values"
    why_human: "Requires real data to enumerate underlying episodes for a given patient x treatment_type pair."
  - test: "Run the full R/88 smoke test on HiPerGator. Section 15n should pass all 14 checks."
    expected: "All 14 checks in Section 15n report PASS. (The run may abort earlier at the known classify_codes production gate per Phase 116 precedent; Section 15n can be sourced in isolation to confirm.)"
    why_human: "R/88 loads CONFIG and sourced scripts that require the HiPerGator environment and real PCORnet data."
---

# Phase 117: Lifespan Gantt Collapse Verification Report

**Phase Goal:** A new "lifespan" Gantt CSV (`output/gantt_lifespan.csv`) collapses the per-episode Gantt export into one row per patient_id x treatment_type, spanning each patient's earliest episode_start to latest episode_stop (calendar dates preserved, not normalized). Multi-value metadata is unioned/deduped/sorted (reusing R/52 `clean_multi_value`), Death and HL Diagnosis pseudo-rows excluded, produced by a new standalone script R/101 registered in R/39, smoke-tested in R/88, and indexed in R/SCRIPT_INDEX.md.

**Verified:** 2026-07-09
**Status:** HUMAN_NEEDED — all structural (local) checks PASS; runtime validation deferred to HiPerGator per established Phase 116 precedent.
**Re-verification:** No — initial verification.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A new CSV `output/gantt_lifespan.csv` is produced with one row per patient_id x treatment_type | ✓ VERIFIED (structural) | R/101 line 281: `write.csv(lifespan_export, OUTPUT_LIFESPAN, row.names = FALSE, na = "")`. `OUTPUT_LIFESPAN` resolves to `file.path(CONFIG$output_dir, "gantt_lifespan.csv")`. Runtime confirmation is HiPerGator-only. |
| 2 | Each collapsed row spans min(episode_start) to max(episode_stop) across all merged episodes of that treatment type | ✓ VERIFIED | R/101 lines 198-199: `episode_start = min(episode_start, na.rm = TRUE)`, `episode_stop = max(episode_stop, na.rm = TRUE)` inside `group_by(patient_id, treatment_type) %>% summarise(...)` |
| 3 | treatment_type is the ONLY grouping dimension besides patient_id (D-06) | ✓ VERIFIED | R/101 line 195: `group_by(patient_id, treatment_type)`. No other field in `group_by`. cancer_category, is_hodgkin, and 7-day status computed as summarised/derived attributes, not keys. |
| 4 | Death and HL Diagnosis pseudo-rows are excluded from the collapsed output (D-08) | ✓ VERIFIED | R/101 lines 166-167: `filter(!treatment_type %in% c("Death", "HL Diagnosis"))` applied before `group_by`. Line 179 adds a defensive `stopifnot` confirming zero pseudo-rows remain. Final summary (line 293) also asserts `n_pseudo_rows == 0`. |
| 5 | Multi-value fields are unioned, deduped, sorted, and semicolon-separated (D-07) | ✓ VERIFIED | R/101 lines 106-128: `clean_multi_value()` copied verbatim from R/52 (uses `sort(unique())`, drops blanks, sep_out=";"). `union_field()` helper pastes group values with ";" then calls `clean_multi_value(sep_in=";", sep_out=";")` — correctly handles already-semicolon-separated input. Applied to all 11 multi-value fields. |
| 6 | The new script is registered in R/39 investigation runner, smoke-tested in R/88, and indexed in R/SCRIPT_INDEX.md | ✓ VERIFIED | R/39 line 191: `"R/101_gantt_lifespan_collapse.R"` in `investigation_scripts` vector (valid syntax — it is the last element, no trailing comma needed). R/88 lines 2027-2097: `SECTION 15n` with 14 structural checks. R/SCRIPT_INDEX.md line 147: row in Post-Renumber Investigations (100+) table. |

**Score:** 6/6 truths verified (structural); runtime truths 1 and partial-6 deferred to HiPerGator.

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/101_gantt_lifespan_collapse.R` | Standalone collapse script; >= 150 lines; group_by patient_id x treatment_type | ✓ VERIFIED | 314 lines. All key patterns present (see Acceptance Criteria section below). |
| `R/39_run_all_investigations.R` | `101_gantt_lifespan_collapse` in investigation_scripts vector | ✓ VERIFIED | Line 191. R/100 line 190 ends with a comma; R/101 line 191 is the terminal entry with no trailing comma — valid R vector syntax. |
| `R/88_smoke_test_comprehensive.R` | Section 15n with checks referencing LIFESPAN-01..LIFESPAN-04 | ✓ VERIFIED | Lines 2027-2097. Section 15n header at line 2028. 14 checks (checks 1-14 verified by inspection). `r101_exists` if/else guard at line 2038/2094. Else-branch registers checks 2-14 as FALSE if script is absent. Summary block at lines 3658-3662 includes all five message lines. |
| `R/SCRIPT_INDEX.md` | Row for `R/101_gantt_lifespan_collapse.R` in Post-Renumber Investigations (100+) | ✓ VERIFIED | Line 147. Full description matches plan spec. Tagged Phase 117. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `R/101_gantt_lifespan_collapse.R` | `output/gantt_episodes.csv` | `read.csv` input | ✓ WIRED | Line 68: `INPUT_EPISODES <- file.path(CONFIG$output_dir, "gantt_episodes.csv")`. Line 139: `read.csv(INPUT_EPISODES, ...)`. Defensive `file.exists` check at line 72. |
| `R/101_gantt_lifespan_collapse.R` | `output/gantt_lifespan.csv` | `write.csv` output with `row.names=FALSE, na=""` | ✓ WIRED | Line 69: `OUTPUT_LIFESPAN <- file.path(CONFIG$output_dir, "gantt_lifespan.csv")`. Line 281: `write.csv(lifespan_export, OUTPUT_LIFESPAN, row.names = FALSE, na = "")`. |
| `R/101_gantt_lifespan_collapse.R` | collapse grain | `group_by` then `summarise` min/max/union | ✓ WIRED | Lines 194-235: `group_by(patient_id, treatment_type) %>% summarise(episode_start = min(...), episode_stop = max(...), ...)` followed by `mutate(episode_length_days, is_hodgkin)`. |

---

### Data-Flow Trace (Level 4)

R/101 is a pure data-export script (no rendering), so Level 4 traces the data from source CSV through transformation to output CSV.

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `R/101_gantt_lifespan_collapse.R` | `lifespan_export` | `read.csv(INPUT_EPISODES)` from `gantt_episodes.csv` | Yes — reads real CSV produced by R/52; no hardcoded rows or static fallbacks | ✓ FLOWING (structural) |

No hardcoded empty arrays, no `return([])`, no static JSON. The script stops with an informative error if the input file is missing rather than silently returning empty data.

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — R/101 requires `output/gantt_episodes.csv` (produced by R/52 on HiPerGator with real PCORnet data). No runnable entry point is available locally on Windows without the raw data. This matches the Phase 116 precedent.

---

### Acceptance Criteria Verification (from PLAN Task 1)

| Criterion | Status | Evidence (line numbers in R/101) |
|-----------|--------|----------------------------------|
| File exists, >= 150 lines | ✓ PASS | 314 lines |
| `group_by(patient_id, treatment_type)` present | ✓ PASS | Line 195 |
| `filter(!treatment_type %in% c("Death", "HL Diagnosis"))` present | ✓ PASS | Lines 166-167 |
| `min(episode_start` and `max(episode_stop` present | ✓ PASS | Lines 198-199 |
| `episode_count` present | ✓ PASS | Line 203 |
| `clean_multi_value` present (D-07) | ✓ PASS | Lines 106-120 (verbatim copy from R/52 lines 772-786) |
| `str_detect(cancer_category, "Hodgkin") & !str_detect(cancer_category, "Non-Hodgkin")` present | ✓ PASS | Lines 233-234 |
| `LIFESPAN_SCHEMA` vector AND `identical(colnames(` schema check | ✓ PASS | Lines 84-93 (schema), line 267 (identical check) |
| Reads `gantt_episodes.csv` and writes `gantt_lifespan.csv` via `file.path(CONFIG$output_dir, ...)` | ✓ PASS | Lines 68-69 |
| `write.csv(` ... `row.names = FALSE, na = ""` | ✓ PASS | Line 281 |
| `source("R/00_config.R")` present | ✓ PASS | Line 59 |
| 7+ `# SECTION ... ----` markers | ✓ PASS | 8 markers (SECTION 1-8) |
| No `library(ggplot2)` / `ggsave` / `geom_` (D-01) | ✓ PASS | Grep confirms zero matches |
| No `open_pcornet_con` / `get_pcornet_table` | ✓ PASS | Grep confirms zero matches |

---

### Requirements Coverage

The PLAN frontmatter declares requirements LIFESPAN-01, LIFESPAN-02, LIFESPAN-03, LIFESPAN-04, and SMOKE-117-01. These IDs appear in ROADMAP.md (Phase 117 header) and in R/88's Section 15n and summary block — but they do NOT appear as defined requirements in `.planning/REQUIREMENTS.md`.

REQUIREMENTS.md was updated through Phase 116 (last line: `*Last updated: 2026-07-06 -- Phase 116 RUCA-06 and SMOKE-116-01 requirements added*`). Phase 117 requirement IDs were not added.

| Requirement | Source | Description | Status | Evidence |
|-------------|--------|-------------|--------|----------|
| LIFESPAN-01 | ROADMAP.md / PLAN frontmatter | R/101 produces output/gantt_lifespan.csv from gantt_episodes.csv | ✓ SATISFIED | R/101 lines 68-69, 281; R/88 checks 4 and 5 |
| LIFESPAN-02 | ROADMAP.md / PLAN frontmatter | Collapse = one row per patient_id x treatment_type, min(start)->max(stop) | ✓ SATISFIED | R/101 lines 195-199; R/88 checks 6 and 8 |
| LIFESPAN-03 | ROADMAP.md / PLAN frontmatter | Death + HL Diagnosis pseudo-rows excluded | ✓ SATISFIED | R/101 lines 166-167, 179; R/88 check 7 |
| LIFESPAN-04 | ROADMAP.md / PLAN frontmatter | Multi-value fields unioned/deduped/sorted via clean_multi_value | ✓ SATISFIED | R/101 lines 106-128, 209-219; R/88 check 9 |
| SMOKE-117-01 | ROADMAP.md / PLAN frontmatter | R/88 validates Phase 117 structural integrity (14 checks) | ✓ SATISFIED | R/88 lines 2027-2097 (14 checks, r101_exists guard, else-branch) |

**ORPHANED (documentation gap, not a code gap):** LIFESPAN-01 through LIFESPAN-04 and SMOKE-117-01 are not present in `.planning/REQUIREMENTS.md`. The pattern established in Phase 116 was to add a section to REQUIREMENTS.md for each phase's requirement IDs. Phase 117 did not follow this pattern. The requirements exist in ROADMAP.md and are functionally implemented — the gap is documentation only. Adding a Phase 117 section to REQUIREMENTS.md would bring it into parity with Phase 116.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | — | — | — | — |

Checks run: TODO/FIXME/PLACEHOLDER comments, `return null` / `return []` / empty implementations, hardcoded empty data, props with empty values. None present in R/101. No DuckDB connection opened. No ggplot. No `setwd()`.

The SUMMARY.md notes that a comment mentioning "ggplot" in a negative context was reworded during development to avoid a false-positive in R/88 check 13. The current file contains no ggplot reference of any kind — this was handled correctly.

---

### Human Verification Required

#### 1. Runtime CSV Production

**Test:** On HiPerGator, after sourcing R/52 to produce `output/gantt_episodes.csv`, source R/101. Confirm `output/gantt_lifespan.csv` is written.

**Expected:** File exists. Row count is less than `nrow(gantt_episodes.csv)` (collapsed). The console summary shows "Pseudo-rows in output: 0 (must be 0)". All `treatment_type` values in the output are real treatment categories (Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care, Proton Therapy, etc.) — none are "Death" or "HL Diagnosis".

**Why human:** Requires real PCORnet data and the full R/52 pipeline to have run first. No local data available.

#### 2. Spot-Check Collapse Accuracy

**Test:** Pick one patient_id x treatment_type combination from `gantt_lifespan.csv`. Filter `gantt_episodes.csv` for that patient_id x treatment_type. Manually verify collapse correctness.

**Expected:** `episode_start` in lifespan row == minimum `episode_start` across matching episode rows. `episode_stop` == maximum `episode_stop`. `episode_count` == number of matching rows. `episode_length_days` == as.integer(lifespan_episode_stop - lifespan_episode_start). A multi-value field (e.g. `drug_names`) in the lifespan row == the sorted, deduped, semicolon-joined union of all values from matching episode rows.

**Why human:** Requires real data to enumerate specific episodes per patient x treatment_type.

#### 3. R/88 Section 15n Full Pass

**Test:** On HiPerGator, source R/88 (or source Section 15n in isolation). Confirm all 14 Phase 117 checks pass.

**Expected:** Console output includes 14 PASS lines for Section 15n checks. Summary block prints all five LIFESPAN-01..SMOKE-117-01 message lines.

**Why human:** R/88 depends on CONFIG and sourced pipeline scripts unavailable locally. Per Phase 116 precedent, the full R/88 run may abort before Section 15n at the classify_codes production gate; Section 15n can be verified by sourcing it in isolation after loading the config.

---

### Gaps Summary

No structural gaps. All six must-have truths are verified against the actual codebase. All four artifacts exist, are substantive (not stubs), and are wired. All three key links are present. No anti-patterns found.

One documentation gap is noted (REQUIREMENTS.md not updated for Phase 117 IDs) — this is cosmetic and does not affect goal achievement or code correctness.

Three runtime validations are legitimately deferred to HiPerGator per the Phase 116 precedent documented in the PLAN's `<verification>` section. Structural verification passes completely on Windows without the raw data.

---

_Verified: 2026-07-09_
_Verifier: Claude (gsd-verifier)_
