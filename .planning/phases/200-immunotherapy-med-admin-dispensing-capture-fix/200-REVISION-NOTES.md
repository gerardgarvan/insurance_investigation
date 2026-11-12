# Phase 200 — Revision Notes & Handoff
*Saved 2026-11-12 — do not execute plans until CONTEXT.md, 200-01-PLAN.md, 200-02-PLAN.md are
rewritten using this file as the sole source of truth.*

---

## 1. Verbatim consolidated instructions from user (2026-11-12)

> Phase 200 — consolidated instructions (2026-11-12). Apply all of these, update 200-CONTEXT.md /
> 200-01-PLAN.md / 200-02-PLAN.md to match, and show me the revised plans before executing anything on
> HiPerGator.
>
> DECISIONS (record in 200-CONTEXT.md and STATE.md)
> - D-200-01: Gantt episodes capture ALL rituximab / methotrexate / immunotherapy administrations
>   regardless of indication; autoimmune use is identified by the Phase 199 immune_flag, not filtered.
> - D-200-R1: Option A — all rituximab codes are Chemotherapy (J9310-12 precedent; R/170 regimen logic
>   uses treatment_type == "Chemotherapy").
> - D-200-R2: the 8 multivitamin RxNorm codes (QUESTIONABLE_IMMUNO_CODES == "questionable-vitamin")
>   are excluded from the NEW immunotherapy MED_ADMIN/DISPENSING branches only; PRESCRIBING unchanged.
>   Team may revisit.
>
> CODE CHANGES (plan 200-01; plan 200-02 must not edit code)
> 1. R/26 extract_immunotherapy_dates_with_codes(): keep the unstaged diff (get_chemo_hits() for
>    DISPENSING and MED_ADMIN with load_ndc_crosswalk(), ENCOUNTERID = NA_character_), plus:
>    a. Relabel both comments "Phase 199 fix 2026-11-12" -> "Phase 200 fix 2026-11-12".
>    b. immuno_ma_codes <- setdiff(TREATMENT_CODES$immunotherapy_rxnorm,
>         names(QUESTIONABLE_IMMUNO_CODES)[QUESTIONABLE_IMMUNO_CODES == "questionable-vitamin"])
>       and pass immuno_ma_codes to both get_chemo_hits() calls (verified: 19 codes).
>       Comment the reason (D-200-R2).
> 2. R/00_config.R:
>    a. J8610 added to MTX_CODES$hcpcs and TREATMENT_CODES$chemo_hcpcs (comment: PROCEDURES PX_TYPE CH
>       only — chemo_hcpcs is not used for MED_ADMIN/DISPENSING). IMMUNE_DRUG_DEFS$Methotrexate$hcpcs
>       = MTX_CODES$hcpcs (drop the J8610 literal).
>    b. Q5115/Q5119/Q5123 in chemo_hcpcs (remove from immunotherapy_hcpcs if present).
>    c. Rituximab RxNorm CUIs: verify 1719312 and 2049106 in RxNav first; if they are rituximab
>       products, put them in chemo_rxnorm (not immunotherapy_rxnorm). If not verifiable, leave them
>       out and say so.
>    d. Drug names in MEDICATION_LOOKUP_JCODE_SUPPLEMENT (or equivalent) for Q5115/Q5119/Q5123 and any
>       added CUIs -> "Rituximab"; J8610 -> "Methotrexate". Verify by sourcing config in R and checking
>       MEDICATION_LOOKUP[...], not by grep.
> 3. Baseline-comparison blocks: gate the ENTIRE PRE199 block in R/142 and the PRE1921/PRE1922
>    comparison blocks in R/52 and R/170 behind env flags defaulting to off
>    (e.g. Sys.getenv("RUN_PRE199_REGRESSION") == "TRUE"). Not just the row-count stop — the 23-column
>    content check would stop the rerun.
> 4. New read-only tool R/tools/check_immuno_fix_preview.R: counts (patients and dates, <11 suppressed)
>    that the new immunotherapy MED_ADMIN/DISPENSING branches would add, BY triggering_code and BY drug
>    name, with the vitamin codes shown separately (would-be contribution, excluded). Report whether
>    ND-typed hits return the mapped RxNorm CUI or the raw NDC as triggering_code.
> 5. R/88: add checks that (a) extract_immunotherapy_dates_with_codes() has no RXNORM_CUI filter on
>    MED_ADMIN/DISPENSING and calls get_chemo_hits() for both; (b) vitamin codes are not passed to those
>    calls; (c) J8610, Q5115/Q5119/Q5123 in chemo_hcpcs and have MEDICATION_LOOKUP names.
>    Also apply the pending Phase 199 15bc update: (f) immune_flag TRUE implies has_autoimmune_dx TRUE;
>    (g) one direction only: ^brentuximab token implies ever_brentuximab TRUE.
> 6. Parse-check every edited R file. Commit as Phase 200 work.
>
> HIPERGATOR RUN (plan 200-02) — separate logged commands, stop on first error
> Each step: R --no-save -q -e 'source("<script>", local = new.env(parent = globalenv()))' 2>&1 | tee output/logs/p200_<step>_<timestamp>.log
> then grep the log for "^Error|Execution halted" before the next step.
> 0. Preflight: git pull; confirm deployed code (sourced-config checks for codes and names; R/26 has
>    get_chemo_hits in the immunotherapy branches and no RXNORM_CUI filter; baseline flags off).
> 1. R/tools/check_immuno_fix_preview.R — GATE: brentuximab gain must be roughly the 184 MED_ADMIN-code
>    patients from check_199_full_history.R; stop and investigate if < 150. Also stop if ND hits return
>    raw NDCs (drug names would stay blank).
> 2. R/60 drug-name resolution, if any new code lacks a name in MEDICATION_LOOKUP / the RxNorm cache.
> 3. R/26  4. R/28 (default)  5. R/28 with p143_out_suffix = "_180_enriched" (input to R/142)
> 6. R/29  7. R/52  8. R/142  9. R/170
>    Note R/26 writes treatment_episodes_stage1.rds (Phase 197); R/29 writes treatment_episodes.rds.
>    Report per-treatment-type patients and episodes before vs after (from the 90-day and 180-day CSVs).
> 10. R/88  11. R/tools/check_199_full_history.R
>
> SUCCESS CRITERIA
> - R/88: set of failing check labels identical to or a subset of the 2026-11-12 baseline (9 labels:
>   192b filename; is_sct_conditioning_context; immuno_confidence; R/30 Linkage Improvement;
>   SMOKE-165-01 [5] and [11]; 192.2 [h3a] [h3b] [h3c]); AUTOIMMUNE-FLAG-192.2 15bb and IMMUNE-FLAG-199
>   15bc 0 FAIL; new Phase 200 checks 0 FAIL.
> - check_199_full_history.R raw-only patients: brentuximab via MED_ADMIN code -> ~0;
>   brentuximab total raw-only drops substantially from 365; rituximab drops from 409 (report the
>   amount; name-only MED_ADMIN hits may remain); MTX: report change (J8610 is PROCEDURES-only, so
>   little change is expected).
> - Gantt: J8610 / Q5 rows (if any exist in PROCEDURES) appear as Chemotherapy with drug_names
>   Methotrexate / Rituximab.
> - Phase 199 columns rebuilt: rerun R/142 QC block and record new immune_flag / ever_brentuximab counts.
>
> SUMMARY: record all before/after counts, the preview result, decisions D-200-01/R1/R2, and any
> remaining gaps (e.g. name-only MED_ADMIN hits) as backlog items.

---

## 2. Findings from code review (2026-11-12)

### 2a. Vitamin codes — D-200-R2

`QUESTIONABLE_IMMUNO_CODES` is defined in R/00_config.R at **line 2387**.
The 8 "questionable-vitamin" CUIs to exclude from immunotherapy MED_ADMIN/DISPENSING branches:

```
"891815"  "891790"  "1090823"  "1313925"
"1248142" "891716"  "1090824"  "891793"
```

`TREATMENT_CODES$immunotherapy_rxnorm` starts at **R/00_config.R line 3868** and contains 27 CUIs.
After `setdiff(..., vitamin codes)`: **19 codes** remain — this is `immuno_ma_codes`.

Note: if rituximab CUIs (121191, 1719312, 2049106) are moved OUT of `immunotherapy_rxnorm` into
`chemo_rxnorm` as per instruction 2c, the base count changes before the setdiff. The immuno_ma_codes
count will need to be re-confirmed at task execution time. The instruction says "verified: 19 codes"
against the CURRENT config; re-verify after 2c edits.

### 2b. R/26 unstaged diff — current state

`git status R/26_treatment_episodes.R` → modified, NOT staged.
`git diff` confirms the fix is already written locally but not committed:

- Section 4 (DISPENSING): removes RXNORM_CUI guard; calls `get_chemo_hits("DISPENSING", ...)` with
  `load_ndc_crosswalk()` once into `immuno_ndc_crosswalk`; adds `mutate(ENCOUNTERID = NA_character_)`.
- Section 5 (MED_ADMIN): removes RXNORM_CUI guard; calls `get_chemo_hits("MED_ADMIN", ...)` with
  `immuno_ndc_crosswalk`; adds `mutate(ENCOUNTERID = NA_character_)`.
- Both comments currently read "Phase 199 fix 2026-11-12" — must be relabelled "Phase 200 fix 2026-11-12".
- A pre-dedup count checkpoint by triggering_code+source is added after the MED_ADMIN block.

The fix does NOT yet apply the vitamin exclusion (`immuno_ma_codes`). That is a NEW addition required
by D-200-R2. The local diff passes `TREATMENT_CODES$immunotherapy_rxnorm` directly; the plan must
change both calls to pass `immuno_ma_codes` instead.

### 2c. get_chemo_hits() — confirmed behaviour

Defined in **R/utils/utils_treatment.R lines 181–291**.
- Accepts any rxnorm CUI vector (parameter named `chemo_rxnorm` but not hard-wired).
- DISPENSING path (lines 205–225): requires NDC column; maps NDC→RxCUI via ndc_crosswalk; filters
  `rxcui %in% chemo_rxnorm`. Returns `tibble(ID, treatment_date, triggering_code)` or NULL.
- MED_ADMIN path (lines 227–291): RX-typed rows — `MEDADMIN_CODE %in% chemo_rxnorm`; ND-typed rows —
  NDC crosswalk → rxcui. triggering_code for ND hits is the **resolved RxCUI**, not the raw NDC
  (line 278: `triggering_code = rxcui`). ENCOUNTERID is NOT returned — callers must add it.
- PRESCRIBING path: uses RXNORM_CUI directly — not affected by this fix.

NDC crosswalk (R/108_build_ndc_rxnorm_crosswalk.R): harvests ALL distinct NDCs from DISPENSING
and MED_ADMIN (MEDADMIN_TYPE=="ND"), regardless of drug class (lines 101–144). Coverage is whatever
NDCs exist in those tables. It is NOT restricted to chemo drugs — immunotherapy NDCs (brentuximab,
rituximab, etc.) are included if they appear in those tables with NDC-coded rows.

**Key for check_immuno_fix_preview.R:** ND hits return mapped RxNorm CUI as triggering_code (not raw
NDC). The preview tool must report this explicitly so Gerard can confirm drug names will resolve.

### 2d. Rituximab RxNorm CUIs — instruction 2c

Three CUIs currently in `TREATMENT_CODES$immunotherapy_rxnorm` (R/00_config.R lines 3897–3900):
- `"121191"` — comment: "Rituximab ingredient CUI (Rituxan/Truxima/Ruxience/Riabni)" — also in
  `RITUXIMAB_CODES$rxnorm` (line 742).
- `"1719312"` — comment: "Rituximab 10 MG/ML Injectable Solution"
- `"2049106"` — comment: "Rituximab-abbs (Truxima) branded CUI"

Instruction: verify 1719312 and 2049106 in RxNav; if confirmed as rituximab products, move to
`chemo_rxnorm` (R/00_config.R line 3237). Cannot verify from Windows — this is a plan task requiring
HiPerGator internet access or manual RxNav lookup. The plan task must be conditional: if confirmed
rituximab → move all three CUIs (121191 also, for consistency with D-200-R1) to chemo_rxnorm and
remove from immunotherapy_rxnorm; if not verifiable → leave out and document.

Existing warning at line 722: "Adding rituximab CUIs to chemo_rxnorm would inflate chemo-detection
counts and corrupt ABVD / BV+AVD regimen identification." D-200-R1 resolves this: all rituximab is
Chemotherapy, so moving CUIs to chemo_rxnorm is now intentional and consistent.

### 2e. R/00_config.R — Q5115/Q5119/Q5123 current location

Currently in `immunotherapy_hcpcs` (R/00_config.R lines 3862–3864). Per D-200-R1, must move to
`chemo_hcpcs` (definition starts at line 3140). J9310/J9311/J9312 are in chemo_hcpcs at lines 3213–3215.
Also need DRUG_GROUPINGS entries for Q5115/Q5119/Q5123 = "Chemotherapy" (after J9312 at ~line 2057).

### 2f. R/00_config.R — MEDICATION_LOOKUP_JCODE_SUPPLEMENT

Defined at **R/00_config.R lines 2871–2884**. Currently contains J9000, J9001, J9040, J9042, J9130,
J9299, J9360. Must add: Q5115→"Rituximab", Q5119→"Rituximab", Q5123→"Rituximab", J8610→"Methotrexate",
and any moved CUIs (121191→"Rituximab", 1719312→"Rituximab", 2049106→"Rituximab") if they end up in
chemo_rxnorm and lack names from the R/60/R/27 RxNorm cache.
Instruction: verify by sourcing config in R and checking `MEDICATION_LOOKUP["Q5115"]` etc. — not by
grep. This is a checkpoint step in 200-02 preflight.

### 2g. PRE199 baseline block — R/142

**R/142_gantt_180_export.R lines 863–902** is the entire PRE199 save+comparison block.
- Lines 863–877: save baseline (keep-if-exists guard).
- Lines 879–881: `write.csv(episodes_export, OUTPUT_EPISODES, ...)` — this is BETWEEN save and compare;
  it must remain OUTSIDE the gate.
- Lines 883–903: Phase 199 regression comparison (reads baseline vs new output; two stopifnot calls
  plus a multiset stop). THE ENTIRE BLOCK from 883 to 903 must be gated.
- The save block (863–877) must ALSO be gated — otherwise it copies the pre-Phase-200 file as the
  baseline and then the gated comparison block skips it, but on the next run with the flag on, the
  baseline would be the Phase 200 output (wrong).

Env flag: `Sys.getenv("RUN_PRE199_REGRESSION") == "TRUE"` (defaulting to off).
Gate both the save block AND the comparison block. The write.csv at line 879 stays ungated.

Structure after edit:
```r
if (Sys.getenv("RUN_PRE199_REGRESSION") == "TRUE") {
  # lines 863-877: save baseline
}
write.csv(episodes_export, OUTPUT_EPISODES, ...)   # line 879 — always runs
...
if (Sys.getenv("RUN_PRE199_REGRESSION") == "TRUE") {
  # lines 883-903: comparison block
}
```

### 2h. PRE1922 baseline blocks — R/52 and R/170

**R/52_gantt_v2_export.R:**
- Lines 812–834: `save_pre1922()` function definition.
- Lines 835–838: `pre1922_90`/`pre1922_180` paths + two `save_pre1922()` calls.
  Gate only the two call sites (lines 837–838) behind env flag `RUN_PRE1922_REGRESSION`.
  The function definition (812–834) can remain — it's inert if not called.

**R/170_nhl_gantt_subsets.R:**
- Lines 894–965: the entire section 4.5 block `{ ... }` including the for-loop, all three sub-checks
  (orig_match stop at 933, autoimmune flag stop at 947, date stop at 960), and the closing `}` at 965.
  Gate the ENTIRE block behind `Sys.getenv("RUN_PRE1922_REGRESSION") == "TRUE"`.
  - Line 919 stop (baseline not found): also inside the block — will be bypassed.
  - Lines 947, 960: content regression stops — also inside the block — bypassed when flag is off.

Instruction says "PRE1921/PRE1922" — there is no PRE1921 in the code. The name is PRE1922 in both
R/52 and R/170. Use env flag `RUN_PRE1922_REGRESSION` for both.

### 2i. R/88 Section 15bc — existing checks and required changes

Section 15bc defined at **R/88_smoke_test_comprehensive.R line 7627**.

**Existing check [g] (lines 7730–7744):** `ever_brentuximab TRUE IFF brentuximab token in drug_names`
— BIDIRECTIONAL. The final assertion is `all(g180_pt2$bren_flag == g180_pt2$has_bren)`.
Must be changed to ONE DIRECTION ONLY: brentuximab token in drug_names → ever_brentuximab TRUE.
New assertion: `all(!g180_pt2$has_bren | g180_pt2$bren_flag)` (token present implies flag TRUE;
flag TRUE without token is now allowed — name-only MED_ADMIN detections).
Label must change from "[g] ever_brentuximab TRUE iff brentuximab token present (both directions)"
to "[g] brentuximab token in drug_names implies ever_brentuximab TRUE (one direction)".

**New check [f] (pending Phase 199 15bc update):** immune_flag TRUE implies has_autoimmune_dx TRUE.
Currently no such check exists in Section 15bc. This is a new check to add. It reads
`gantt_episodes_180.csv`, groups by patient_id, and asserts:
`all(!g180_pt$imm_flag | g180_pt$has_autoimmune)` where `has_autoimmune` comes from the
`has_autoimmune_dx` column. Insert before or after existing [f] (the rituximab/methotrexate
drug-token check at lines 7714–7727).

**New checks for Phase 200 (instruction 5a/5b/5c):**
To be added in a new sub-section of 15bc (or immediately after 15bc closes):
- (5a) `extract_immunotherapy_dates_with_codes()` body has no `RXNORM_CUI` guard for
  DISPENSING or MED_ADMIN; has `get_chemo_hits("DISPENSING", ...)` and `get_chemo_hits("MED_ADMIN", ...)`.
- (5b) The function body references `immuno_ma_codes` (not raw `immunotherapy_rxnorm`) in those calls.
  Grep pattern: `get_chemo_hits.*immuno_ma_codes`.
- (5c) `J8610` and `Q5115`/`Q5119`/`Q5123` are in `chemo_hcpcs`; `MEDICATION_LOOKUP["J8610"]` and
  `MEDICATION_LOOKUP["Q5115"]` are non-NA/non-blank.

**Section 15bc summary message** (line 7785) must be updated to describe Phase 200 additions.

### 2j. R/26 — existing pre-dedup checkpoint in unstaged diff

The unstaged diff adds a pre-dedup count block after the MED_ADMIN section that prints rows by
`triggering_code + src`. This is the checkpoint for instruction D-200-05. It is RETAINED as-is;
the plan must NOT replace it with the per-type episode/patient counts (those come from R/28, not R/26).

### 2k. R/28 second pass — exact invocation

From R/143_02_checkpoint_verify.R lines 63–69:
```r
options(
  p143_episodes_rds = file.path(CONFIG$cache$outputs_dir, "treatment_episodes_180.rds"),
  p143_detail_rds   = file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail_180.rds"),
  p143_out_suffix   = "_180_enriched"
)
source("R/28_episode_classification.R", local = new.env(parent = globalenv()))
options(p143_episodes_rds = NULL, p143_detail_rds = NULL, p143_out_suffix = NULL)
```
R/26 writes both `treatment_episodes_stage1.rds` (90-day, default R/28 input) AND
`treatment_episodes_180.rds` + `treatment_episode_detail_180.rds` (Section 5C of R/26, lines 902–).
R/142 reads `treatment_episodes_180_enriched.rds` (the second R/28 pass output).

### 2l. R/60 — drug-name resolution

R/60 builds/extends the RxNorm CUI name cache. If moved CUIs (121191, 1719312, 2049106) lack names
in MEDICATION_LOOKUP after config changes, R/60 should be run to fetch names from the RxNorm API.
This is step 2 of the 200-02 run, conditional on the preflight finding blank names.

### 2m. HiPerGator log pattern

Each script is run as a separate shell command:
```
R --no-save -q -e 'source("<script>", local = new.env(parent = globalenv()))' 2>&1 | tee output/logs/p200_<step>_<timestamp>.log
```
Then: `grep -E "^Error|Execution halted" output/logs/p200_<step>_<timestamp>.log`
Stop on first non-empty grep result. The timestamp can be provided by Gerard as a fixed string per
session (e.g., `20261112_1600`) to avoid shell expansion issues.

### 2n. Success criteria — R/88 known failing labels (2026-11-12 baseline of 9)

The 9 existing FAILs that may persist after Phase 200:
1. 192b filename check
2. is_sct_conditioning_context
3. immuno_confidence
4. R/30 Linkage Improvement
5. SMOKE-165-01 [5]
6. SMOKE-165-01 [11]
7. 192.2 [h3a]
8. 192.2 [h3b]
9. 192.2 [h3c]

Sections 15bb (AUTOIMMUNE-FLAG-192.2) and 15bc (IMMUNE-FLAG-199) must have 0 FAIL.
New Phase 200 checks (5a/5b/5c/[f] update/[g] update) must have 0 FAIL.

---

*Written 2026-11-12 — context at ~80%. Next session: rewrite 200-CONTEXT.md, 200-01-PLAN.md,
200-02-PLAN.md using this file as the sole reference. Do not re-read code files; all relevant
findings are captured above.*
