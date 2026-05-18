---
phase: quick
plan: 260518-hvq
type: execute
wave: 1
depends_on: []
files_modified:
  - R/00_config.R
  - R/46_treatment_cross_reference.R
  - .gitignore
autonomous: true
must_haves:
  truths:
    - "TREATMENT_CODES$immunotherapy_drg returns c('018') when R/00_config.R is sourced"
    - "R/43, R/44, R/46 all resolve immunotherapy DRG from config without fallback"
    - "Root directory contains no stale duplicate files (00_config.R, TEMPLATE, .py, .rds)"
  artifacts:
    - path: "R/00_config.R"
      provides: "immunotherapy_drg entry in TREATMENT_CODES list"
      contains: "immunotherapy_drg"
    - path: ".gitignore"
      provides: "Root-level exclusions for .R, .py, .rds files"
  key_links:
    - from: "R/43_treatment_durations.R"
      to: "R/00_config.R"
      via: "TREATMENT_CODES$immunotherapy_drg"
      pattern: "TREATMENT_CODES\\$immunotherapy_drg"
    - from: "R/44_treatment_episodes.R"
      to: "R/00_config.R"
      via: "TREATMENT_CODES$immunotherapy_drg"
      pattern: "TREATMENT_CODES\\$immunotherapy_drg"
---

<objective>
Fix the immunotherapy_drg config gap and clean root-level clutter.

Purpose: TREATMENT_CODES$immunotherapy_drg is referenced by R/43, R/44, and R/46 but does not
exist in R/00_config.R. This means the DRG-based immunotherapy lookup silently returns NULL/no
results. Additionally, the repository root has accumulated stale duplicate files (a copy of
00_config.R, one-off Python scripts, misplaced RDS artifacts) that should be removed.

Output: Config gap fixed, null-safe fallback in R/46 simplified, root clutter deleted, .gitignore
hardened against future root-level accumulation.
</objective>

<context>
@.planning/STATE.md
@R/00_config.R (lines 930-950: DRG section of TREATMENT_CODES)
@R/46_treatment_cross_reference.R (lines 755-780: immunotherapy gap fallback)
@.gitignore
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add immunotherapy_drg to TREATMENT_CODES and remove null-safe fallback</name>
  <files>R/00_config.R, R/46_treatment_cross_reference.R</files>
  <action>
1. In R/00_config.R, insert the immunotherapy_drg vector into the TREATMENT_CODES list
   immediately after the sct_drg entry (after line 947, before the blank line 948).
   Add:
   ```r
   immunotherapy_drg = c(
     "018"    # Chimeric Antigen Receptor (CAR) T-cell Immunotherapy
   ),
   ```
   Place it after the closing paren+comma of sct_drg. Maintain the existing indentation
   style (2-space indent for the element name, 4-space indent for the code value).

2. In R/46_treatment_cross_reference.R, simplify the null-safe fallback block at lines
   ~758-766. Replace:
   ```r
   immuno_drg_config <- if (!is.null(TREATMENT_CODES$immunotherapy_drg)) {
     TREATMENT_CODES$immunotherapy_drg
   } else {
     c("018")
   }
   ```
   With:
   ```r
   immuno_drg_config <- TREATMENT_CODES$immunotherapy_drg
   ```
   Update the preceding comment block (lines ~755-761) to remove the "may not be in
   TREATMENT_CODES" caveat. Replace with a simple note:
   ```r
   # immunotherapy_drg from TREATMENT_CODES (DRG 018 = CAR T-cell immunotherapy)
   immuno_drg_config <- TREATMENT_CODES$immunotherapy_drg
   ```
   Also update line ~487 comment to remove the "may not be in TREATMENT_CODES; handled
   with fallback" note -- change to:
   ```r
   # Note: DRG 018 is T-cell immunotherapy DRG, defined in TREATMENT_CODES$immunotherapy_drg.
   ```

No changes needed to R/43 or R/44 -- they already reference TREATMENT_CODES$immunotherapy_drg
directly and will now get c("018") instead of NULL.
  </action>
  <verify>
    <automated>grep -n "immunotherapy_drg" R/00_config.R && echo "---" && grep -c "is.null.*immunotherapy_drg" R/46_treatment_cross_reference.R | grep -q "^0$" && echo "PASS: no null fallback remains" || echo "FAIL: null fallback still present"</automated>
  </verify>
  <done>
TREATMENT_CODES$immunotherapy_drg = c("018") exists in R/00_config.R. R/46 no longer has the
null-safe if/else fallback. R/43 and R/44 references to TREATMENT_CODES$immunotherapy_drg
will now resolve to c("018") instead of NULL.
  </done>
</task>

<task type="auto">
  <name>Task 2: Delete root-level clutter and harden .gitignore</name>
  <files>.gitignore</files>
  <action>
1. Delete these 6 untracked root-level files (all confirmed untracked via git status):
   - 00_config.R (identical copy of R/00_config.R, line-ending differences only)
   - 22_multi_source_overlap_detection_TEMPLATE.R (stale template, diverged from R/22)
   - csv_to_xlsx.py (one-off conversion script with hardcoded /mnt/user-data paths)
   - extract_pptx.py (one-off PPTX extraction utility, not part of pipeline)
   - unmatched_codes_classified.rds (misplaced copy -- canonical location is output/)
   - unmatched_ndc_classified.rds (misplaced copy -- canonical location is output/)

   Use `rm` for each file. Do NOT delete:
   - OneFLQuestions.docx (active reference document per STATE.md decisions)
   - QuantAnalysisMtgNotes_ZoomAI.docx (active reference document per STATE.md decisions)
   - R/date_range_check.R (ad-hoc diagnostic, lives correctly in R/)

2. Add root-level exclusions to .gitignore to prevent future accumulation. After the
   existing "Root-level diagnostic/output artifacts" section (after line 28), add:
   ```
   /*.R
   /*.py
   /*.rds
   /*.docx
   ```
   This prevents any future root-level R scripts, Python scripts, RDS files, or Word
   documents from being accidentally tracked. All R scripts belong in R/, all outputs
   belong in output/, and docx reference documents are consumed at plan time (not runtime).

3. Verify the output/ directory still has the canonical copies of the RDS files by checking
   that the scripts reference output/ paths (already confirmed -- R/39 writes to
   file.path(CONFIG$output_dir, "unmatched_codes_classified.rds")).
  </action>
  <verify>
    <automated>test ! -f 00_config.R && test ! -f csv_to_xlsx.py && test ! -f extract_pptx.py && test ! -f unmatched_codes_classified.rds && test ! -f unmatched_ndc_classified.rds && test ! -f 22_multi_source_overlap_detection_TEMPLATE.R && echo "PASS: all root clutter removed" || echo "FAIL: some files remain"</automated>
  </verify>
  <done>
Six root-level clutter files deleted. .gitignore updated with /*.R, /*.py, /*.rds, /*.docx
rules to prevent future accumulation. OneFLQuestions.docx and QuantAnalysisMtgNotes_ZoomAI.docx
retained as active reference documents (now gitignored to keep repo clean).
  </done>
</task>

</tasks>

<verification>
1. `grep "immunotherapy_drg" R/00_config.R` shows the new TREATMENT_CODES entry
2. `grep -c "is.null.*immunotherapy_drg" R/46_treatment_cross_reference.R` returns 0
3. `ls *.R *.py *.rds 2>/dev/null` returns nothing (root clutter gone)
4. `grep "/*.R" .gitignore` shows the new exclusion rule
5. R syntax check: `Rscript -e "tryCatch(source('R/00_config.R'), error=function(e) stop(e))"` -- would succeed on HiPerGator (cannot run locally without data paths)
</verification>

<success_criteria>
- TREATMENT_CODES$immunotherapy_drg = c("018") defined in R/00_config.R
- R/46_treatment_cross_reference.R uses TREATMENT_CODES$immunotherapy_drg directly (no fallback)
- Zero root-level .R, .py, .rds files remain
- .gitignore prevents future root-level accumulation of .R, .py, .rds, .docx files
</success_criteria>

<output>
After completion, create `.planning/quick/260518-hvq-fix-immunotherapy-drg-config-gap-and-rem/260518-hvq-SUMMARY.md`
</output>
