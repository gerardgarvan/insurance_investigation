---
phase: quick-261112-tfm
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - R/142_gantt_180_export.R
  - R/88_smoke_test_comprehensive.R
  - .planning/phases/200-immunotherapy-med-admin-dispensing-capture-fix/200-02-SUMMARY.md
autonomous: true
requirements: []
must_haves:
  truths:
    - "R/142 saves immune_flag_dx_ids.rds containing the patient_ids where has_immune_flag_dx is TRUE"
    - "R/88 [f2] uses immune_flag_dx_ids.rds for has_aim_dx, not has_autoimmune_dx"
    - "R/88 [f2] skips gracefully with a message if the RDS is absent"
    - "R/88 [f2] prints a suppressed count (<11 for 1–10) on FAIL"
    - "200-02-SUMMARY.md records the root cause and correction"
  artifacts:
    - path: "R/142_gantt_180_export.R"
      provides: "Save immune_flag_dx_ids.rds after the immune_flag_exposure_ids.rds save block"
    - path: "R/88_smoke_test_comprehensive.R"
      provides: "[f2] block using immune_flag_dx_ids.rds"
    - path: ".planning/phases/200-immunotherapy-med-admin-dispensing-capture-fix/200-02-SUMMARY.md"
      provides: "Root-cause note appended"
  key_links:
    - from: "R/142_gantt_180_export.R"
      to: "CONFIG$cache$outputs_dir/immune_flag_dx_ids.rds"
      via: "saveRDS after the immune_flag_exposure_ids.rds local() block"
    - from: "R/88_smoke_test_comprehensive.R"
      to: "CONFIG$cache$outputs_dir/immune_flag_dx_ids.rds"
      via: "readRDS in [f2] local() block"
---

<objective>
Fix R/88 IMMUNE-FLAG-199 [f2] check to use the IMMUNE_FLAG_DX_CODES-derived patient set
(284 pts) instead of the broader has_autoimmune_dx proxy (433 pts), eliminating the false
FAIL for patients who have a Rituximab/MTX Gantt token but only a broader autoimmune code.

Purpose: The check was correct in intent but wrong in input. has_autoimmune_dx covers all
433 AUTOIMMUNE_DX_CODES patients; the immune flag requires IMMUNE_FLAG_DX_CODES membership
(284 pts). Using the wrong set creates spurious violations.

Output: immune_flag_dx_ids.rds persisted by R/142; [f2] in R/88 reads it; 200-02-SUMMARY
updated.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
</execution_context>

<context>
@.planning/STATE.md
@R/142_gantt_180_export.R
@R/88_smoke_test_comprehensive.R
</context>

<tasks>

<task type="auto">
  <name>Task 1: Save immune_flag_dx_ids.rds from R/142 Section 4C3</name>
  <files>R/142_gantt_180_export.R</files>
  <action>
Verification step (already done by planner): has_aim_dx in [f2] is confirmed to use
has_autoimmune_dx at line 7745 — the fix is valid.

In R/142_gantt_180_export.R, after the existing local() block that saves
immune_flag_exposure_ids.rds (which ends near line 824 with the message call), add a new
standalone save of immune_flag_dx_ids.rds.

The source column `has_immune_flag_dx` is available in `ep_imm` within the Section 4C3
block (it is joined from imm_full at lines 749-753; ep_imm is defined at that scope).

After line ~824 (the end of the immune_flag_exposure_ids.rds local()), add:

```r
  # Save patient-level IMMUNE_FLAG_DX qualifying-dx IDs for R/88 [f2] check (fix [f2] FAIL)
  local({
    dx_ids <- ep_imm$patient_id[isTRUE(ep_imm$has_immune_flag_dx) |
                                  ep_imm$has_immune_flag_dx %in% TRUE]
    dx_ids <- unique(dx_ids)
    out_rds <- file.path(CONFIG$cache$outputs_dir, "immune_flag_dx_ids.rds")
    saveRDS(dx_ids, out_rds)
    message(glue("  Saved immune_flag_dx_ids.rds: {length(dx_ids)} patients -> {out_rds}"))
  })
```

Place it inside the Section 4C3 block (before the label-counts section) so ep_imm is in
scope. Do not alter any existing code.
  </action>
  <verify>
grep -n "immune_flag_dx_ids" R/142_gantt_180_export.R
# Must show at least one saveRDS line.
  </verify>
  <done>immune_flag_dx_ids.rds save block present in Section 4C3 of R/142; uses ep_imm$has_immune_flag_dx</done>
</task>

<task type="auto">
  <name>Task 2: Fix R/88 [f2] to use immune_flag_dx_ids.rds</name>
  <files>R/88_smoke_test_comprehensive.R</files>
  <action>
Replace the [f2] local() block (lines ~7739-7755) with the corrected version below.

Current code at line 7739-7755:
```r
    # (f2) one-direction completeness: Gantt token + qualifying dx => immune_flag TRUE
    local({
      g180_pt_f2 <- g180_dat |>
        dplyr::group_by(patient_id) |>
        dplyr::summarise(
          imm_flag   = any(immune_flag == "TRUE"),
          has_aim_dx = any(has_autoimmune_dx %in% "TRUE"),
          has_token  = any(vapply(
            strsplit(drug_names, ";", fixed = TRUE),
            function(toks) any(grepl("^rituximab|^methotrexate", trimws(toks), ignore.case = TRUE)),
            logical(1)
          )),
          .groups = "drop"
        )
      p199_chk("IMMUNE-FLAG-199 [f2] Gantt token + qualifying dx => immune_flag TRUE (completeness)",
        all(!(g180_pt_f2$has_token & g180_pt_f2$has_aim_dx) | g180_pt_f2$imm_flag))
    })
```

Replace with:
```r
    # (f2) one-direction completeness: Gantt token + qualifying dx => immune_flag TRUE
    # Qualifying dx = IMMUNE_FLAG_DX_CODES patients (284 pts), NOT broader has_autoimmune_dx (433 pts).
    # Reads immune_flag_dx_ids.rds saved by R/142 Section 4C3. SKIPs if absent.
    local({
      dx_rds <- file.path(CONFIG$cache$outputs_dir, "immune_flag_dx_ids.rds")
      if (!file.exists(dx_rds)) {
        message("  SKIP [f2]: immune_flag_dx_ids.rds not found — rerun R/142 first")
      } else {
        immune_flag_dx_pts <- readRDS(dx_rds)
        g180_pt_f2 <- g180_dat |>
          dplyr::group_by(patient_id) |>
          dplyr::summarise(
            imm_flag   = any(immune_flag == "TRUE"),
            has_aim_dx = any(patient_id[1L] %in% immune_flag_dx_pts),
            has_token  = any(vapply(
              strsplit(drug_names, ";", fixed = TRUE),
              function(toks) any(grepl("^rituximab|^methotrexate", trimws(toks), ignore.case = TRUE)),
              logical(1)
            )),
            .groups = "drop"
          )
        violators <- g180_pt_f2[g180_pt_f2$has_token & g180_pt_f2$has_aim_dx & !g180_pt_f2$imm_flag, ]
        n_viol <- nrow(violators)
        n_viol_str <- if (n_viol >= 1 && n_viol <= 10) "<11" else as.character(n_viol)
        if (n_viol > 0) {
          message(glue("  FAIL [f2]: {n_viol_str} patients have token + qualifying dx but immune_flag FALSE"))
        }
        p199_chk("IMMUNE-FLAG-199 [f2] Gantt token + qualifying dx (IMMUNE_FLAG_DX_CODES) => immune_flag TRUE (completeness)",
          n_viol == 0L)
      }
    })
```

Note: `has_aim_dx = any(patient_id[1L] %in% immune_flag_dx_pts)` works because patient_id
is constant within a group_by(patient_id) summarise, so `patient_id[1L]` is the group key.
  </action>
  <verify>
grep -n "immune_flag_dx_ids\|immune_flag_dx_pts\|has_autoimmune_dx.*TRUE.*f2\|SKIP \[f2\]" R/88_smoke_test_comprehensive.R | head -20
# Must show immune_flag_dx_ids.rds reference; must NOT show has_autoimmune_dx in the [f2] block.
# To confirm has_autoimmune_dx is gone from [f2]:
grep -n "has_autoimmune_dx" R/88_smoke_test_comprehensive.R | grep -n "7739\|7740\|7741\|7742\|7743\|7744\|7745\|7746\|7747\|7748\|7749\|7750\|7751\|7752\|7753\|7754"
# Should return nothing.
  </verify>
  <done>
[f2] block reads immune_flag_dx_ids.rds; has_autoimmune_dx not present in [f2] block;
SKIP message present; violator count uses small-cell suppression; check label updated.
  </done>
</task>

<task type="auto">
  <name>Task 3: Append root-cause note to 200-02-SUMMARY.md and commit</name>
  <files>.planning/phases/200-immunotherapy-med-admin-dispensing-capture-fix/200-02-SUMMARY.md</files>
  <action>
Read the file first. Append the following section at the end (before any trailing newline):

```
## Post-Summary Fix: [f2] qualifying-dx correction (2026-11-12)

IMMUNE-FLAG-199 [f2] initially failed (20 PASS / 1 FAIL) because it used `has_autoimmune_dx`
(broader AUTOIMMUNE_DX_CODES set, 433 pts) as the qualifying-dx proxy instead of the narrower
IMMUNE_FLAG_DX_CODES set (284 pts). Patients with a Rituximab/MTX Gantt token and only a
broader autoimmune code (e.g., ICD-9 696.0 psoriasis) are correctly NOT flagged, but [f2]
wrongly counted them as violations.

Correction:
- R/142 Section 4C3 now saves `immune_flag_dx_ids.rds` (patient_ids where
  `has_immune_flag_dx` is TRUE, derived from IMMUNE_FLAG_DX_CODES).
- R/88 [f2] reads that RDS; SKIPs with a message if absent; uses the narrower set for
  `has_aim_dx`; prints a small-cell-suppressed count on FAIL.
```

Then commit:
```
git add R/142_gantt_180_export.R R/88_smoke_test_comprehensive.R \
  .planning/phases/200-immunotherapy-med-admin-dispensing-capture-fix/200-02-SUMMARY.md \
  .planning/quick/261112-tfm-fix-r-88-f2-check-to-use-immune-flag-dx-/261112-tfm-PLAN.md
git commit -m "fix(88): IMMUNE-FLAG-199 [f2] use immune_flag_dx_ids.rds not has_autoimmune_dx"
git push
```
  </action>
  <verify>
git log --oneline -1
# Must show the fix(88) commit message.
  </verify>
  <done>200-02-SUMMARY.md has the root-cause section; all three changed files committed and pushed.</done>
</task>

</tasks>

<verification>
After Tasks 1–3 complete on the local machine (no R run needed here):

1. `grep -n "immune_flag_dx_ids" R/142_gantt_180_export.R` — shows saveRDS line in Section 4C3.
2. `grep -n "immune_flag_dx_ids\|SKIP \[f2\]" R/88_smoke_test_comprehensive.R` — shows RDS reference and SKIP guard.
3. `grep -c "has_autoimmune_dx" R/88_smoke_test_comprehensive.R` — count is unchanged from before (the autoimmune-dx references in other checks still exist; only the [f2] block no longer references it).
4. `git log --oneline -1` — shows the fix commit.

HiPerGator confirmation (ask Gerard to run after rerunning R/142 first):
  source("R/88_smoke_test_comprehensive.R", local = new.env(parent = globalenv()))
  Expected: "PASS IMMUNE-FLAG-199 [f2]" in the output (21/21 PASS in Section 15bc).
</verification>

<success_criteria>
- R/142 saves immune_flag_dx_ids.rds with IMMUNE_FLAG_DX_CODES patient_ids
- R/88 [f2] uses that RDS; SKIP message if absent; prints suppressed count on FAIL
- has_autoimmune_dx no longer appears in the [f2] block
- 200-02-SUMMARY.md has the root-cause paragraph
- Committed and pushed
</success_criteria>

<output>
No SUMMARY.md needed for quick tasks. Changes are self-documenting in 200-02-SUMMARY.md and the commit message.
</output>
