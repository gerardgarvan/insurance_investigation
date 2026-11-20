# Phase 215, Plan 01: SUMMARY

**Status:** local work complete; HiPerGator run PENDING HIPERGATOR (plan stays incomplete in STATE.md).

## What was built
- Phase 215 / script `R/215` (next free after 214); folder `.planning/phases/215-histology-code-descriptions/`; ROADMAP + STATE entries.
- `R/00_config.R`: `CONFIG$icdo3_histology_terms_path`, `CONFIG$icdo2_to_icdo3_path` (under `data/reference/`).
- `R/utils/utils_cancer.R`: `build_histology_lookup()` (pure), `load_histology_lookup()` (cached, reads CONFIG paths), `describe_histology(code, site = NULL, lookup = NULL)`. Returns `length(code)` rows in input order: `raw_code, hist4, behavior, icdo3_code, description, desc_source, match_level`.
- `R/215_tr_histology_descriptions.R`: stacks `HISTOLOGICAL_TYPE` + `MORPH`, describes distinct (code, site) pairs, joins back with row-count guards, extract fallback (<74 chars), writes `output/tr_histology_code_descriptions.csv` and `output/tr_histology_unmatched.csv` (counts 1-10 as `<11`, no IDs).
- `R/88`: one structural check. `R/SCRIPT_INDEX.md` entry. Reference notes: `215-REFERENCE-NOTES.md`.

## Tests
- `tools/rcheck.sh parse` on all 5 changed `.R` files: OK.
- `tools/rcheck.sh test 215`: 31 expectations pass, 0 fail, 1 skipped (real-reference test; xlsx not in `data/reference/` locally, see assumption 1).
- Manual run of `describe_histology` against the real term list and conversion CSV (from `phase_inbox/`): 96503 and 9650 give the same term; 96573 -> 96513, 96603 -> 96593 (`icdo3_via_icdo2_conversion`); 850003 and NA `unmatched`.
- Stubbed local run of the R/215 body (fake registry table, no real data): both CSVs written, guards and reconciliation passed.
- Verification table: "Output length", "Join row count", malformed/NA, conversions covered by unit tests. "Coverage" and R/88 real-data row-count checks are guarded by `stopifnot()` in R/215 and need HiPerGator.

## Assumptions (headless run)
1. The term-list xlsx `Histology3_v27_20260821.xlsx` could not be moved: the permission layer denied `mv` for it. The conversion CSV was moved. Left in `phase_inbox/`; CONFIG points to `data/reference/`. Action: move it to `data/reference/` (or set the path) before syncing. Reference files under `data/` are not committed by this run (rule: never stage `data/`); sync them to HiPerGator manually.
2. Term-list download date unknown; file name date `20260821` and version `v27` recorded as source.
3. Plan Task 5 says 96503 = "Hodgkin lymphoma, NOS"; the file says "Classical Hodgkin lymphoma [SEE HEMATOPOIETIC DATABASE FOR REPORTING]". File wins (no terms from memory).
4. 4-digit lookup picks behavior 3, else lowest behavior digit.
5. 5-digit order: exact ICD-O-3 key, then ICD-O-2 conversion, then 4-digit ICD-O-3 term (the plan listed 4-digit before conversion; changed so a 5-digit ICD-O-2 code is not described by an unrelated-behavior 4-digit term). The 4-digit fallback sets `match_level = "4digit"` instead of a fifth `desc_source` value.
6. Site-dependent codes whose ICD-O-3 key also exists (e.g. 85103, 89300) match ICD-O-3 directly, before conversion.
7. Site columns `SITE_CODE` (TR1) / `SITE` (TR2/3) and `HISTOLOGICAL_TYPE_DESCRIPTION` / `SITE_CODE_DESCRIPTION` are not in any schema probe (names from Phase 84 fixture plans). The script treats them as optional and logs which are present. Site is matched on its first 3 characters (dots removed).
8. Output is one row per `raw_code`; where site changes the resolved description, the modal one (by rows) is shown and `n_variants` counts the variants.
9. Not added to `R/39_run_all_investigations.R` (needs reference files, would stop the full run); not run: R/89 reference manual regeneration (HiPerGator).
10. Out-of-scope items untouched: `ICD_CODES$hl_histology/nhl_histology`, cohort rules, Gantt re-export.

## HiPerGator steps (PENDING HIPERGATOR)
```r
# after syncing the repo and staging both reference files in data/reference/
# module load R/4.5; R --no-save
source("R/215_tr_histology_descriptions.R", local = new.env(parent = globalenv()))
```
Paste back the `[R215]` log lines (about 12) and, if it errors, the error plus about 20 lines.
Check:
- `columns present:` line lists which site and description columns exist (resolves assumption 7).
- `stacked rows reconcile: TRUE`; no `stopifnot` failure.
- `unmatched` count and `output/tr_histology_unmatched.csv` (hand to the team with the HL/NHL list decision, D-07).
- `extract_fallback descriptions at 75 chars: 0`.
- `max length of SITE_CODE_DESCRIPTION` (75 means the same truncation; log for a later phase).
- Optional: `nrow(read.csv("output/tr_histology_code_descriptions.csv"))` equals the distinct-code count in the log.
- Then `source("R/88_smoke_test_comprehensive.R", ...)`: expect the 9 known baseline failures only.
- Regenerate the reference manual (R/89) afterwards.
