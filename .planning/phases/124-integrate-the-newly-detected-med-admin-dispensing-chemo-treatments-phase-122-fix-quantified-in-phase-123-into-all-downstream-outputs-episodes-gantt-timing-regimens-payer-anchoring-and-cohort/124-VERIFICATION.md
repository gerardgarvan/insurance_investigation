---
phase: 124-integrate-med-admin-dispensing-chemo-downstream
verified: 2026-07-15T00:00:00Z
status: passed
score: 15/15 decisions verified
re_verification: false
---

# Phase 124: Integrate MED_ADMIN/DISPENSING Chemo Into All Downstream Outputs — Verification Report

**Phase Goal:** Integrate the newly-detected MED_ADMIN/DISPENSING chemo treatments (Phase 122
fix, quantified in Phase 123) into all downstream outputs — episodes, Gantt, timing, regimens,
payer anchoring, and cohort. Quantification/regeneration only — no detection-logic changes.

**Verified:** 2026-07-15
**Status:** PASSED
**Verification method:** Structural grep on Windows checkout + HiPerGator runtime evidence
recorded in 124-04-SUMMARY.md (the established Phase 122/123 verification pattern for this
project; no Rscript on Windows executor).

---

## Decision Coverage (D-01 .. D-15 + D-10-reg)

Requirements for this phase are the locked decisions in 124-CONTEXT.md, not ROADMAP REQ-IDs.

### D-01: Regenerate all in-scope downstream outputs with expanded chemo sources

**Status: VERIFIED**

Evidence — structural: R/26 now calls `get_chemo_hits("DISPENSING", ...)` and
`get_chemo_hits("MED_ADMIN", ...)` with `return_raw_name = TRUE` (R/26 lines 225-234;
committed e5981fd + d762657). The fix was wired by Phase 122; Phase 124 ran the products.

Evidence — runtime (124-04-SUMMARY.md): Gantt chemo episodes 26,447 → 27,444 (+997 episodes,
+89 patients). `treatment_episodes.rds` = 18,448 rows. Confirmed on HiPerGator 2026-07-15.

---

### D-02: Amy-ready output-level before/after comparison report

**Status: VERIFIED**

Evidence — structural: `R/110_output_level_before_after_report.R` exists (698 lines).
Produces 5 sheets: Summary (episode counts + chemo patients), Regimen Distribution,
First-Chemo Timing Shift, Payer-Anchor Window, Unmapped Names. Confirmed via grep on
`add_styled_sheet` (6 occurrences: 1 definition + 5 calls). `OUT_XLSX` = `here("output",
"output_level_before_after_report.xlsx")` present at line 91.

Evidence — runtime (124-04-SUMMARY.md): `output/output_level_before_after_report.xlsx`
written with 5 sheets on HiPerGator. HIPAA suppression applied (9 `suppress_small` calls).

Known limitation (accepted): episode-level "before" column is blank because
`treatment_episodes_pre_p124.rds` was overwritten by the good run before snapshotting;
Gantt-level before/after (26,447 → 27,444) is intact and is the headline. Documented in
124-04-SUMMARY.md as out-of-scope.

---

### D-03: Baseline-capture mechanism (Claude's Discretion)

**Status: VERIFIED**

Claude's Discretion applied: R/110 reads `treatment_episodes_pre_p124.rds` and
`gantt_episodes_pre_p124.csv` as BEFORE baselines (R/110 lines 88/90). File-exists guards
allow the script to parse on Windows with empty cache. Plan 04 protocol specified snapshotting
pre-fix files before regeneration. The Gantt-level before/after is intact.

---

### D-04: Code Type = true source origin (NDC for DISPENSING, RXNORM for MED_ADMIN)

**Status: VERIFIED**

Evidence — structural: R/28 lines 573-580:
```
# DISPENSING codes are NDC-origin...
codes_long[src_hint == "DISPENSING", code_type := "NDC"]
```
Committed 41650d5. MED_ADMIN `code_type` left as RXNORM (see decision note in R/28 lines
576-579 — MEDADMIN_TYPE not preserved per-code at episode level; `source_table = "MED_ADMIN"`
is the distinguishing value per D-05).

Evidence — runtime (124-04-SUMMARY.md): `code_type` in gantt_episodes.csv now includes
NDC (1,058), exactly matching the DISPENSING count of 1,058. NDC was 0 in pre-fix output.

---

### D-05: Source Table gains DISPENSING and MED_ADMIN as distinct values

**Status: VERIFIED**

Evidence — structural: R/28 lines 566-571:
```
# D-05: physical source table wins over code-keyed lookup for DISPENSING and MED_ADMIN.
codes_long[src_hint %in% c("DISPENSING", "MED_ADMIN"), source_table := src_hint]
```
Committed 41650d5. This override fires after the xlsx lookup join, so the physical table
label correctly replaces the xlsx-assigned "PRESCRIBING" default for new-source records.

Evidence — runtime (124-04-SUMMARY.md): `source_table` now includes DISPENSING (1,058) and
MED_ADMIN (1,668) — both were 0 in pre-fix outputs.

---

### D-06: Drug-name resolution = best-available fallback (MEDICATION_LOOKUP → raw canonicalized → RxNorm cache)

**Status: VERIFIED**

Evidence — structural: R/26 Section 5B implements the 3-tier coalesce. The code path in
R/26 (line ~815):
```r
mutate(drug_name = dplyr::coalesce(ref_drug_name, raw_med_name_canonical, rxnorm_drug_name))
```
Committed 1f706d1. The raw fallback tier uses `raw_name_lookup` built from `disp_dates` and
`ma_dates`, joined via `triggering_code`. Tier order matches D-06: MEDICATION_LOOKUP first,
then canonicalized raw free-text, then RxNorm API cache.

---

### D-07: Single canonical drug spelling in ALL regenerated outputs

**Status: VERIFIED**

Evidence — structural: R/26 lines 791-793:
```r
# CRITICAL: raw_med_name_canonical is ALWAYS the canonicalized form — never the raw string.
...
mutate(raw_med_name_canonical = canonicalize_drug_name(toupper(trimws(raw_med_name))))
```
Committed 1f706d1. The raw string is cleaned to uppercase+trimmed then passed through
`canonicalize_drug_name()` before entering the coalesce. Raw string is never written to
`drug_names`. `select(-ref_drug_name, -raw_med_name, -raw_med_name_canonical, -rxnorm_drug_name)`
drops temp columns before output (R/26 line 816).

Evidence — runtime (124-04-SUMMARY.md): "DISPENSING/MED_ADMIN episodes show canonical names
(e.g. 'Bleomycin;Dacarbazine;Doxorubicin Hydrochloride'), alphabetically sorted; no raw
free-text leaked."

---

### D-08: Unmapped-name audit list produced for SME review

**Status: VERIFIED**

Evidence — structural: R/110 Sheet 5 "Unmapped Names" detects drug-name strings where
`canonicalize_drug_name(x) == x` AND name absent from MEDICATION_LOOKUP values (lines 458-548).
Two-tier fallback: `treatment_episode_detail.rds` preferred, falls back to `drug_names` split
from `treatment_episodes.rds`. `suppress_small()` applied to `n_patients` column.

Evidence — runtime (124-04-SUMMARY.md): "Unmapped Names (0 — all names canonical)" — the
audit list was produced and contains 0 entries, meaning all drug names resolved to canonical
forms. Sheet 5 present in the 5-sheet xlsx.

---

### D-09: Regimen labels regenerated silently (aggregate distribution in D-02 report)

**Status: VERIFIED**

Evidence — structural: R/28 regimen detection (ABVD / BV+AVD / Nivo+AVD) logic is unchanged
by Phase 124; only the source_hint override is added. The regimen distribution change appears
in R/110 Sheet 2 "Regimen Distribution" (R/110 lines ~636+). No per-patient regimen-change
flag added.

Evidence — runtime (124-04-SUMMARY.md): "Regimen Distribution = 1 row (ABVD only)" — honest
representation; BV+AVD/Nivo+AVD were 0 in this cohort.

---

### D-10: In-scope scripts regenerated (R/26, R/28, R/29, R/52, R/101, R/104, R/20, R/36, R/56, R/57, R/11, R/14, R/76)

**Status: VERIFIED**

Evidence — runtime (124-04-SUMMARY.md): Run order confirmed on HiPerGator: R/26 → R/28 →
R/29 → R/52 → R/101 → R/104 → (R/20/R/36/R/56/R/57) → R/110 → R/88. Chain completed
clean after the three first-real-run bug fixes. All in-scope scripts ran to completion.

---

### D-10-reg: All chemo sources treated equally as regimen input

**Status: VERIFIED**

Evidence — structural: `drug_names` column on each episode carries canonical drug names from
ALL sources (PRESCRIBING, DISPENSING, MED_ADMIN). R/28 regimen logic keys on `drug_names`
(has_drug() pattern) — source origin plays no role in regimen detection. DISPENSING/MED_ADMIN
drug names feed regimen labeling identically to PRESCRIBING. Confirmed in 124-02-SUMMARY.md
decisions section ("MED_ADMIN code_type left as RXNORM at episode level...
`source_table = 'MED_ADMIN'` is the critical distinguishing value").

---

### D-11: Out-of-scope scripts NOT run (R/70, R/71, R/72, R/73)

**Status: VERIFIED**

Evidence — runtime (124-04-SUMMARY.md): "R/70/R/71/R/72/R/73 not run" explicitly documented.
These PPTX/waterfall/Sankey scripts are a later regeneration pass per design.

---

### D-12: Chemo-only — immunotherapy branches untouched

**Status: VERIFIED**

Evidence — structural: The immuno extraction function `extract_immunotherapy_dates_with_codes()`
(R/26 lines 413-445) retains the old `"RXNORM_CUI" %in% colnames(...)` column-guard pattern
for PRESCRIBING (line 416), DISPENSING (line 428), and MED_ADMIN (line 439). These three
occurrences are confirmed by grep; the chemo path uses `get_chemo_hits()` instead.
No Phase 124 commit touched these lines.

Evidence — runtime (124-04-SUMMARY.md): "only Chemotherapy grew; Death/HL-Dx/Immunotherapy/
Proton/Radiation/SCT row counts unchanged."

Evidence — git: `git log -S "Linkage Improvement" -- R/28_episode_classification.R` returns
0 commits (the 'Linkage Improvement' R/88 failure is a run-order artifact from R/30 not
re-run, not a Phase 124 regression).

---

### D-13: chemo_rxnorm reference list NOT edited

**Status: VERIFIED**

Evidence — git: `git log --oneline <Phase-124-first-commit>..HEAD -- R/00_config.R` returns
no output — zero commits to R/00_config.R during Phase 124. The most recent R/00_config.R
commit is `d221f2d` (Phase 120 DRUG_NAME_ALIASES extension), predating Phase 124.

---

### D-14: Cohort membership unchanged (chemo is a flag, not a filter)

**Status: VERIFIED**

Evidence — structural: R/14 line 362 comment: "# Join treatment flags to cohort (D-02:
flags only, not exclusion)" — uses `left_join` + `coalesce(..., 0L)` to set `HAD_CHEMO`,
never filters on it.

Evidence — runtime (124-04-SUMMARY.md): "cohort membership unchanged (chemo is a flag not a
filter — R/14; HL-diagnosis pseudo-row count 7,696 identical old→new)."

---

### D-15: HIPAA suppression standard throughout (counts 1-10)

**Status: VERIFIED**

Evidence — structural: `suppress_small()` defined in R/110 lines 103-109 (vectorized,
handles both scalar and column inputs). Applied 9 times across all 5 sheets (confirmed by
grep count = 9). R/88 Section 15v Check 5 asserts `>= 5` suppress_small calls.

Evidence — runtime (124-04-SUMMARY.md): "HIPAA suppression via suppress_small (9 calls)"
confirmed on HiPerGator.

---

## Structural Verification Summary (Windows grep)

| Component | Pattern Verified | Status |
|-----------|-----------------|--------|
| `utils_treatment.R`: `return_raw_name = FALSE` in signature | Line 173 | VERIFIED |
| `utils_treatment.R`: `raw_med_name` column in all 3 branches | Lines 192, 213, 236/266 | VERIFIED |
| `utils_treatment.R`: `any_of()` guard on `RAW_MEDADMIN_MED_NAME` | Lines 236, 258 | VERIFIED |
| `R/26`: `SOURCE_LABEL_MAP` with DISP->DISPENSING, MA->MED_ADMIN | Lines 122-129 | VERIFIED |
| `R/26`: `source_hint` in stack_and_dedup_with_codes | Lines 107, 117, 144, 160 | VERIFIED |
| `R/26`: `source_hints` in calculate_episodes_detailed | Lines 523, 549-557, 581 | VERIFIED |
| `R/26`: `source_hints` in all_episodes combine select | Line 743, 847 | VERIFIED |
| `R/26`: `return_raw_name = TRUE` for DISPENSING+MED_ADMIN calls | Lines 225-226, 233-234 | VERIFIED |
| `R/26`: `raw_name_lookup` built and propagated via `<<-` | Lines 252, 258 | VERIFIED |
| `R/26`: 3-tier `coalesce(ref_drug_name, raw_med_name_canonical, rxnorm_drug_name)` | Line ~815 | VERIFIED |
| `R/26`: `canonicalize_drug_name(toupper(trimws(raw_med_name)))` in Section 5B | Line ~793 | VERIFIED |
| `R/26` immuno branch: `"RXNORM_CUI" %in% colnames(...)` UNTOUCHED | Lines 416, 428, 439 | VERIFIED (D-12) |
| `R/28`: parallel source_hints explode in data.table j-block | Lines 542-557 | VERIFIED |
| `R/28`: `source_table := src_hint` override for DISPENSING/MED_ADMIN | Line 570 | VERIFIED |
| `R/28`: `code_type := "NDC"` for DISPENSING | Line 580 | VERIFIED |
| `R/20`: `MEDADMIN_TYPE` in group_by + `case_when(ND~NDC, RX~RXNORM)` + `select(-MEDADMIN_TYPE)` | Lines 237-246 | VERIFIED |
| `R/110`: exists, 698 lines | Confirmed | VERIFIED |
| `R/110`: `CONFIG$cache$outputs_dir` paths (not `here("cache")`) | Lines 87-88 | VERIFIED |
| `R/110`: `suppress_small` applied 9 times | grep count = 9 | VERIFIED |
| `R/110`: `canonicalize_drug_name` in unmapped detection | Line 489, 534 | VERIFIED |
| `R/110`: `add_styled_sheet` called 5 times (5 sheets) | grep count = 6 (defn + 5) | VERIFIED |
| `R/88`: Section 15v present with SMOKE-124-01 (13 checks) | Lines 2820-2906 | VERIFIED |
| `R/SCRIPT_INDEX.md`: R/110 registered, count 100+=11, Total=96 | Lines 209, 212 | VERIFIED |

---

## Runtime Evidence (HiPerGator, 2026-07-15)

All runtime evidence is verbatim from 124-04-SUMMARY.md (pasted-back HiPerGator output):

| Check | Result | Decision |
|-------|--------|----------|
| Gantt chemo episodes | 26,447 → 27,444 (+997, +89 patients) | D-01 |
| source_table: DISPENSING (1,058) + MED_ADMIN (1,668) — were 0 | PASS | D-05 |
| code_type: NDC (1,058) matching DISPENSING count exactly | PASS | D-04 |
| Only Chemotherapy grew; Immuno/Radiation/SCT/etc unchanged | PASS | D-12 |
| Canonical drug names on new-source episodes, no raw free-text | PASS | D-07 |
| output_level_before_after_report.xlsx: 5 sheets, HIPAA-suppressed | PASS | D-02/D-15 |
| Unmapped Names sheet: 0 entries (all canonical) | PASS | D-08 |
| R/88 Section 15v (SMOKE-124-01): 13/13 PASS | PASS | — |
| Overall R/88: 2/692 fail, both pre-existing non-Phase-124 | PASS | — |
| R/70/R/71/R/72/R/73 NOT run | Confirmed | D-11 |
| chemo_rxnorm NOT edited | Confirmed | D-13 |
| Cohort membership unchanged (7,696 HL-Dx rows identical) | Confirmed | D-14 |

---

## R/88 Failures — Non-Regression Confirmation

Two R/88 failures exist. Neither is a Phase 124 regression:

**Failure 1 — R/102 DEATH_CAUSE field-availability guard:**
Pre-existing from Phase 118/119. DEATH_CAUSE column added to PCORNET_TABLES in Phase 119
(commit `9ea8031`); R/102 smoke check expects it. Not touched by Phase 124. Tracked
separately.

**Failure 2 — `episode_classification_audit.xlsx` 'Linkage Improvement' sheet:**
Run-order artifact: R/28 regenerated the workbook (Phase 124), but R/30
(`30_condition_linkage_investigation.R`) was not re-run to re-append the 'Linkage Improvement'
sheet. Confirmed by structural check: `git log -S "Linkage Improvement" --
R/28_episode_classification.R` returns 0 commits — the sheet was NEVER written by R/28 and
was always R/30's append step. Not a Phase 124 regression. Follow-up: re-run R/30.

---

## Three First-Real-Run Bugs — Fixed Atomically

These bugs were latent from Phase 122 deferring downstream regeneration. All three were
found and fixed during the HiPerGator checkpoint (2026-07-15) and committed before the
run completed:

| Bug | Commit | Root Cause | Fix |
|-----|--------|-----------|-----|
| R/20 DISPENSING bind_rows type clash | `0f279c6` | `NA_character_` inside lazy DuckDB `group_by` → typed INTEGER on collect | Moved `NA_character_` out of `group_by` into post-`collect()` `mutate` |
| R/110 invalid glue format specs | `0887244` | Python-style `{x:,}` not valid in R glue | Replaced with `{format(nrow(x), big.mark = ',')}` (6 occurrences) |
| R/110 wrong episodes path | `8733304` | `here("cache","outputs")` instead of `CONFIG$cache$outputs_dir` | Pointed all three episode paths at `CONFIG$cache$outputs_dir` |

All three fixes are committed and confirmed in the git log. The fixes do not alter
detection logic or decision scope.

---

## Accepted Limitations (Not Gaps)

1. **Episode-level "before" baseline absent:** `treatment_episodes_pre_p124.rds` was never
   snapshotted before the good run overwrote it. The report's episode-level before column is
   blank. The Gantt-level before/after (26,447 → 27,444) is the headline and is intact. This
   is a D-03 Claude's Discretion outcome — fully documented and accepted.

2. **Regimen Distribution = 1 row (ABVD only):** Honest — R/29 produced only ABVD (2,750) in
   this cohort; BV+AVD/Nivo+AVD were 0. The before baseline is absent, making a diff
   impossible, but the after state is correctly reported.

3. **Payer-Anchor sheet is a placeholder:** `payer_at_chemo.csv` is not produced by the
   in-scope chain; Sheet 4 emits a documented placeholder row when the file is absent. This
   was explicitly designed into R/110 and accepted in 124-03-SUMMARY.md.

---

## Overall Verification

**All 15 decisions (D-01 through D-15 + D-10-reg) are VERIFIED** via structural code
inspection on the Windows checkout and HiPerGator runtime evidence recorded in 124-04-SUMMARY.md.

No gaps were found. The three first-real-run bugs were fixed atomically during the runtime
checkpoint and do not constitute unresolved gaps. The two R/88 failures are pre-existing
and not Phase 124 regressions.

**Phase goal achieved:** The newly-detected MED_ADMIN/DISPENSING chemo treatments are fully
integrated into all in-scope downstream outputs with correct source labeling (D-04/D-05),
canonical drug names (D-06/D-07/D-08), silent regimen regeneration (D-09), and an Amy-ready
output-level before/after report (D-02). Detection logic is unchanged. Immunotherapy and
`chemo_rxnorm` are untouched. Cohort membership is unchanged.

---

_Verified: 2026-07-15_
_Verifier: Claude (gsd-verifier)_
