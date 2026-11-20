# Headless run: add and build the histology code description phase

## Rules for this run

- You are running non-interactively. Never ask questions or wait for answers.
  Take the documented defaults and record every assumption in the phase
  SUMMARY under "Assumptions (headless run)".
- This is a Windows machine. The data lives on HiPerGator, not here. Never try
  to reach HiPerGator, /blue, /orange or real data. Local runs use
  tests/fixtures only.
- Work on the current git branch. Commit in small steps with clear messages.
  Do not push.
- Do not edit `ICD_CODES$hl_histology` or `ICD_CODES$nhl_histology` in
  `R/00_config.R`, and do not change any cohort rule.
- Do not write ICD-O histology terms from your own knowledge. Descriptions
  must come only from the ICD-O-3 term list file in `phase_inbox/`.

## Inputs (all in `phase_inbox/` in the repo root)

- `NNN-CONTEXT.md` — phase context and decisions D-01 to D-08
- `NNN-01-PLAN.md` — the six-task plan
- `icdo2_to_icdo3_conversion.csv` — ICD-O-2 to ICD-O-3 conversion table
  (933 rows; columns icdo2_hist, icdo2_beh, icdo2_code5, icdo3_hist,
  icdo3_beh, icdo3_code5, site, site_dependent, code_changed)
- The ICD-O-3 histology term list (a spreadsheet or CSV; file name varies)

## What to do

1. **Set up the phase.** Find the next free phase number and the next free
   script number from the existing planning folder and `R/SCRIPT_INDEX.md`.
   Create the phase folder following the repo's existing naming convention,
   move the two drafts into it, and replace every `NNN` with the real numbers.
   Add the phase to the roadmap/state files the same way recent phases were
   added.

2. **Check the term list.** If no ICD-O-3 term list file is present in
   `phase_inbox/`, do steps 1 and 3 only, write the SUMMARY saying the term
   list is missing, and stop. If it is present, inspect it and record in the
   phase folder: column names, how histology and behavior are stored, and
   whether a code has more than one row (preferred term versus synonyms).

3. **Store the reference files.** Move the conversion CSV and the term list to
   the folder where the repo keeps reference inputs (follow the existing
   convention; if there is none, use `data/reference/`). Add path constants to
   `R/00_config.R`. Record source and date for each file in the phase folder.

4. **Build the lookup and `describe_histology()`** in
   `R/utils/utils_cancer.R`, exactly as specified in Tasks 2 and 3 of the
   plan. The function must return one row per input element, in input order.

5. **Write the script** `R/<number>_tr_histology_descriptions.R` as specified
   in Task 4, following the header and structure conventions of the existing
   numbered scripts. It must read `TUMOR_REGISTRY_ALL` through the existing
   connection helpers. Do not run it against real data.

6. **Test locally.** Add unit tests covering every row of the verification
   table in Task 5 that does not need real data, using small in-test vectors
   or fixtures. Run them. Parse-check every R file you touched. Fix failures
   before moving on.

7. **Close out.** Add the script to `R/SCRIPT_INDEX.md`. Write the phase
   SUMMARY with: what was built, test results, the assumptions list, and a
   short "HiPerGator steps" section giving the R console commands to run the
   script on real data (interactive R session, `module load R/4.5`, not
   sbatch), plus what to check in the outputs.

## Stop conditions

- Stop and write the SUMMARY if the term list is missing (step 2), if its
  structure cannot be read reliably, or if tests still fail after three fix
  attempts.
- Do not start any work outside this phase.
