---
phase: 123-quantify-med-admin-dispensing-fix-impact
verified: 2026-07-14T20:00:00Z
status: passed
score: 12/12 must-haves verified
re_verification: false
---

# Phase 123: Quantify MED_ADMIN/DISPENSING Fix Impact + Unmatched-NDC Audit — Verification Report

**Phase Goal:** Quantify how much the Phase 122 MED_ADMIN/DISPENSING chemo-detection fix changes treatment outputs via a source-level before/after diff, AND investigate whether unmatched NDCs are missing real chemo — delivered as a single multi-sheet xlsx. Quantification only (no downstream regeneration).

**Verified:** 2026-07-14T20:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | R/109 exists as a NEW sibling script; R/107 and R/108 are unchanged | VERIFIED | `R/109_med_admin_dispensing_fix_impact_audit.R` present (863 lines); `git diff` shows R/107, R/108, R/39 untouched |
| 2 | R/109 computes before (PRESCRIBING-only) and after (all sources) using the production `get_chemo_hits()` path | VERIFIED | Lines 169-208: `get_chemo_hits("PRESCRIBING")`, `get_chemo_hits("MED_ADMIN", ..., ndc_crosswalk)`, `get_chemo_hits("DISPENSING", ..., ndc_crosswalk)` with explicit comment that MED_ADMIN RX+ND union is internal to the function |
| 3 | D-03 patient & date counts by source produced | VERIFIED | Runtime log: 817 pts / 5,265 pairs before; 2,145 pts / 19,027 pairs after; delta +1,328 pts / +13,762 dates; `df_before_after_summary` and `df_source_counts` assigned |
| 4 | D-04 first-chemo timing shift produced | VERIFIED | Runtime log: 89 patients gained an earlier date; median 155d, p25 15d, p75 660d, max 3,202d; `df_timing_shift` assigned; `first_after < first_before` pattern confirmed in source |
| 5 | D-05 per-ingredient delta produced | VERIFIED | Runtime log: 94 distinct ingredients with before/after counts; `df_ingredient_delta` assigned with `MEDICATION_LOOKUP[triggering_code]` mapping; HIPAA suppression applied via vectorized `suppress_small()` across count columns |
| 6 | D-06 regimen-label impact guarded by `file.exists(EPISODES_RDS)` with no R/25/26/28 re-run | VERIFIED | Runtime log confirms treatment_episodes.rds absent on HiPerGator at run time — skip message logged as designed; empty `df_regimen_impact` assigned; R/88 Check 8 confirms `!grepl('source("R/2[568]', r109_text)`; Regimen Impact sheet present in xlsx (skip-note content) |
| 7 | D-07 drug-name string match against MED_ADMIN `RAW_MEDADMIN_MED_NAME` produced | VERIFIED | Runtime log: 88 unmatched NDCs with chemo-ingredient name hit; `df_ndc_string_match` assigned; `any_of()` guard for optional column present (commit `4f83b3f`); DISPENSING no-name-text documented in comment |
| 8 | D-08 top-50 frequency-ranked unmatched NDCs produced | VERIFIED | Runtime log: 50 NDCs in top-50 table; `df_ndc_freq_ranked` assigned; `N <- 50L` and `arrange(desc(n_rows))` confirmed; explicit size-1 `na.omit()` guard present (commit `038ba2a`) |
| 9 | D-09 IS_LOCAL-gated RxNav alternate-endpoint re-query writes a NEW CSV without overwriting the audit CSV | VERIFIED | Runtime log: 7,739 NDCs queried via `ndcproperties`/`ndcstatus`; 0 recovered / 0 chemo; `output/ndc_rxnorm_crosswalk_requery.csv` written on HiPerGator; R/88 Check 11 confirms no write to `ndc_rxnorm_crosswalk_audit.csv` |
| 10 | D-10 resolved-non-chemo gap check flags candidate gaps without modifying `chemo_rxnorm` | VERIFIED | Runtime log: 4,245 resolved-non-chemo RxCUIs checked; 5 flagged as `CANDIDATE_CHEMO_GAP`; `TREATMENT_CODES$chemo_rxnorm` not modified; R/88 Check 12 confirms both conditions |
| 11 | D-11 single multi-sheet styled xlsx delivered at `output/med_admin_dispensing_fix_impact.xlsx` | VERIFIED | Runtime log: exit code 0; xlsx written (298,458 bytes); 9 sheets logged: Before-After Summary, Source Counts, Timing Shift, Per-Ingredient Delta, Regimen Impact, Unmatched NDC Top-N, NDC String Match, RxNav Requery Results, Resolved-Gap Findings; R/51-verbatim styling constants (`FF374151`, `FFFFFFFF`, `FF1F2937`) confirmed in source |
| 12 | D-12 quantification only — no downstream regeneration; SCRIPT_INDEX-only; R/39 untouched | VERIFIED | R/SCRIPT_INDEX.md row present with count bumped 9 -> 10; R/39 unchanged (git diff empty); REGISTRATION NOTE comment in R/109 header states "NOT wired into R/39" |

**Score:** 12/12 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/109_med_admin_dispensing_fix_impact_audit.R` | New sibling script, Sections 1-16, all D-03..D-11 | VERIFIED | 863 lines; all 16 sections present; passes all 14 R/88 Section 15u structural checks |
| `R/88_smoke_test_comprehensive.R` | Section 15u with 14 Phase 123 checks + SMOKE-123-01 | VERIFIED | Section 15u at line 2728; 14 `check(` calls tagged `(Phase 123)`; SMOKE-123-01 summary line at line 4395; positioned after Section 15t, before Section 15g |
| `R/SCRIPT_INDEX.md` | R/109 row in 100+ table; count = 10 | VERIFIED | R/109 row present with phase column `123`; footer reads "Post-renumber investigations (100+): 10"; R/107 and R/108 rows unchanged |
| `output/med_admin_dispensing_fix_impact.xlsx` | Multi-sheet styled workbook, 9 sheets, 298 KB | VERIFIED | File present on Windows checkout (glob match); runtime log confirms 298,458 bytes, 9 sheets, all D-03..D-10 data frames written |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| R/109 after-set extraction | `get_chemo_hits()` in utils_treatment.R | `get_chemo_hits("PRESCRIBING" / "MED_ADMIN" / "DISPENSING", CHEMO_RXNORM, ndc_crosswalk)` | WIRED | Three calls at lines 169-171; runtime produced real counts (2,145 patients after) |
| R/109 D-06 regimen impact | `cache/outputs/treatment_episodes.rds` | `readRDS` guarded by `file.exists(EPISODES_RDS)` | WIRED | Guard present at runtime; skip branch executed correctly; empty tibble assigned |
| R/109 NDC audit | `output/ndc_rxnorm_crosswalk_audit.csv` | `read.csv(NDC_AUDIT_CSV, colClasses = "character")` guarded by `file.exists(NDC_AUDIT_CSV)` | WIRED | Runtime log: 24,327 total / 16,588 matched / 7,739 miss |
| R/109 D-09 re-query | RxNav `ndcproperties.json` / `ndcstatus.json` | IS_LOCAL-gated `httr2` batch loop | WIRED | Runtime log: 7,739 NDCs x 2 endpoints; 0 recovered; loop completed; requery CSV written |
| R/109 xlsx assembly | `output/med_admin_dispensing_fix_impact.xlsx` | `wb_workbook()` + 8 `wb$add_worksheet()` + `wb$save(OUTPUT_XLSX)` wrapped in `tryCatch` | WIRED | Runtime log confirms write (298,458 bytes) |
| R/88 Section 15u | `R/109_med_admin_dispensing_fix_impact_audit.R` | `readLines` + 14 `grepl` structural checks | WIRED | Runtime log: 14/14 PASS in Section 15u |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `R/109` D-03 | `df_before_after_summary`, `df_source_counts` | DuckDB PRESCRIBING / MED_ADMIN / DISPENSING via `get_chemo_hits()` | Yes — 817/2,145 patients; 5,265/19,027 (ID,date) pairs | FLOWING |
| `R/109` D-04 | `df_timing_shift` | Same DuckDB extraction; `inner_join` on `first_before` vs `first_after` | Yes — 89 patients; median 155d shift | FLOWING |
| `R/109` D-05 | `df_ingredient_delta` | `MEDICATION_LOOKUP[triggering_code]` for drug names; DuckDB for counts | Yes — 94 ingredients | FLOWING |
| `R/109` D-06 | `df_regimen_impact` | `treatment_episodes.rds` (absent on HiPerGator at run time) | N/A — intentional skip per D-06/D-12; empty tibble with note | FLOWING (guarded skip by design) |
| `R/109` D-07 | `df_ndc_string_match` | MED_ADMIN `RAW_MEDADMIN_MED_NAME` via DuckDB; `ndc_rxnorm_crosswalk_audit.csv` | Yes — 88 hits | FLOWING |
| `R/109` D-08 | `df_ndc_freq_ranked` | DuckDB DISPENSING + MED_ADMIN ND row counts; `ndc_rxnorm_crosswalk_audit.csv` | Yes — top-50 frequency table | FLOWING |
| `R/109` D-09 | `df_ndc_requery` | RxNav alternate endpoints (ndcproperties/ndcstatus) via httr2 | Yes — 7,739 NDCs queried; 0 recovered (definitive result) | FLOWING |
| `R/109` D-10 | `df_resolved_gap` | `ndc_rxnorm_crosswalk_audit.csv` matched population; `MEDICATION_LOOKUP` for name lookup | Yes — 4,245 checked; 5 flagged | FLOWING |
| `output/med_admin_dispensing_fix_impact.xlsx` | All 9 sheets | All df_* objects above written via `add_styled_sheet()` | Yes — 298 KB written | FLOWING |

---

### Behavioral Spot-Checks

Cannot run R on this machine (Windows, no Rscript). The HiPerGator runtime log is used as authoritative behavioral evidence:

| Behavior | Evidence from Runtime Log | Status |
|----------|--------------------------|--------|
| Cohort scopes to 9,282 HL patients | "Found 9,282 patients with HL diagnosis" at Section 4 | PASS |
| Before set = PRESCRIBING-only | "Before (PRESCRIBING only): 817 patients, 5,265 (ID,date) pairs" | PASS |
| After set adds MED_ADMIN + DISPENSING | "After (all sources): 2,145 patients, 19,027 (ID,date) pairs" | PASS |
| D-04 timing shift detected | "89 patients gained an earlier first-chemo date" | PASS |
| D-06 graceful skip when episodes.rds absent | Skip message logged; Regimen Impact sheet written with note | PASS |
| D-09 runs full 7,739-NDC re-query on HiPerGator | "Progress: 7700/7739" then "Complete: 0 NDCs recovered" | PASS |
| D-09 writes requery CSV, not overwriting audit CSV | "Results written to output/ndc_rxnorm_crosswalk_requery.csv"; audit CSV confirmed PRESENT and unchanged | PASS |
| D-10 flags 5 candidate gaps | "5 have MEDICATION_LOOKUP entries (potential chemo_rxnorm gaps — SME review needed)" | PASS |
| xlsx written (D-11) | Exit code 0; "Wrote deliverable xlsx"; 298,458 bytes confirmed by output check | PASS |
| R/88 Section 15u 14/14 PASS | "[Phase 123] ... PASS" x14; SMOKE-123-01 line printed | PASS |
| Overall R/88 1/682 FAIL is pre-existing | FAIL is R/102 DEATH_CAUSE guard (Phase 118/119); Section 15u = 0 failures | PASS |

---

### Requirements Coverage

Phase 123 has no formal requirement IDs in ROADMAP.md. The authoritative spec is the D-01..D-12 decisions in CONTEXT.md. All are accounted for:

| Decision | Description | Status | Evidence |
|----------|-------------|--------|----------|
| D-01 | "Before" = PRESCRIBING-only; "after" = PRESCRIBING + MED_ADMIN-RX + NDC-resolved DISPENSING/MED_ADMIN-ND | SATISFIED | R/109 lines 169-208; runtime confirms correct source breakdown |
| D-02 | Deterministic source-level diff; no toggle-flag plumbing; R/107/R/108 unchanged | SATISFIED | Sibling script only; git diff confirms R/107/R/108 untouched |
| D-03 | Patient & date counts by source | SATISFIED | Runtime: +1,328 patients / +13,762 dates by source |
| D-04 | First-chemo timing shift | SATISFIED | Runtime: 89 patients earlier; full distribution computed |
| D-05 | Per-drug/ingredient delta | SATISFIED | 94 ingredients; MEDICATION_LOOKUP names; HIPAA-suppressed |
| D-06 | Regimen-label impact — upper bound, episodes.rds join, no R/25/26/28 re-run | SATISFIED | Guard worked correctly; D-06 sheet present in xlsx with skip note; follow-up deferred |
| D-07 | Drug-name string match on unmatched NDCs | SATISFIED | 88 hits via RAW_MEDADMIN_MED_NAME; DISPENSING no-name note |
| D-08 | Frequency-ranked top-N review | SATISFIED | Top-50 table in xlsx |
| D-09 | RxNav alternate-endpoint re-query (IS_LOCAL-gated) | SATISFIED | 7,739 NDCs x 2 endpoints; 0 recovered; requery CSV written |
| D-10 | Resolved-non-chemo gap check (flags only; list unchanged) | SATISFIED | 5 CANDIDATE_CHEMO_GAP flagged; `chemo_rxnorm` not modified |
| D-11 | Single multi-sheet styled xlsx | SATISFIED | 298 KB, 9 sheets, R/51-verbatim styling |
| D-12 | Quantification only; no downstream regeneration; SCRIPT_INDEX-only | SATISFIED | R/39 untouched; R/SCRIPT_INDEX.md count = 10 |

---

### Anti-Patterns Found

| File | Pattern | Severity | Assessment |
|------|---------|----------|------------|
| R/109 Section 15 `df_regimen_impact` | Empty tibble with skip note | INFO | Intentional per D-06/D-12: guard fires when `treatment_episodes.rds` absent; sheet written with explicit skip annotation; not a stub |
| R/109 `df_ndc_requery` | 0-row result (0 NDCs recovered) | INFO | Real runtime result, not a placeholder; definitive finding that alternate endpoints add no coverage |

No blockers or warnings. The only "empty" data frames are the result of intentional, guarded design decisions that produce real (if null) runtime findings.

---

### Runtime Bug-Fixes Noted

Three dplyr/dbplyr bugs were discovered during the HiPerGator run and fixed atomically (structural checks on Windows cannot detect lazy-table edge cases):

1. **`suppress_small()` not vectorized** (`52144c2`) — Plan 01 wrote `&&` / `NA_integer_` scalar form; `across()` in D-05 passes vectors. Fixed by switching to `ifelse()` and `&`. The final source at line 116 reflects the fix.

2. **`any_of()` guard missing for optional `RAW_MEDADMIN_MED_NAME` column** (`4f83b3f`) — D-08 `select()` failed when column absent in lazy DuckDB table. Fixed with `any_of(c(raw_med_name = "RAW_MEDADMIN_MED_NAME"))` at line 533.

3. **`first(na.omit())` all-NA group crash** (`038ba2a`) — D-08 frequency summarise returned length-0 for groups where every `raw_med_name` is NA (DISPENSING-only NDCs). Fixed with explicit size-1 guard documented at lines 554-555.

All three fixes were committed before the run completed and are present in the current source. The plan's structural acceptance criteria (grep-based, Windows) correctly passed after these fixes.

---

### Human Verification Required

None required beyond what the HiPerGator runtime log already confirms. The following items are follow-ups, not verification gaps:

1. **D-06 regimen impact sheet** — Currently contains a skip note (treatment_episodes.rds absent). To populate: run `R/26_treatment_episodes.R` on HiPerGator, then re-run R/109. This is a known deferred follow-up per D-06/D-12, not a gap.

2. **D-10 SME review** — 5 candidate `chemo_rxnorm` gaps flagged. SME review and any correction to the reference list are a separate follow-up. This phase flags only, per D-10.

3. **Full downstream regeneration** — episodes/Gantt/timing/payer outputs with the Phase 122 fix applied remain deferred (D-12).

---

### Gaps Summary

No gaps. All 12 observable truths are verified. All D-01..D-12 decisions are satisfied. The phase goal — a quantified before/after diff (+1,328 patients / +13,762 chemo dates) plus a four-method unmatched-NDC audit packaged into a single multi-sheet xlsx — is fully achieved.

The single pre-existing R/88 failure (1/682 = R/102 DEATH_CAUSE guard from Phase 118/119) is unrelated to Phase 123 and was present before this phase began.

---

_Verified: 2026-07-14T20:00:00Z_
_Verifier: Claude (gsd-verifier)_
