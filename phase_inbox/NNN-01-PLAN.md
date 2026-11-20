# Phase NNN, Plan 01: Histology Code Descriptions — PLAN

**Depends on:** NNN-CONTEXT.md (decisions D-01 to D-08)
**Run mode:** interactive R session on HiPerGator (`module load R/4.5`, then `R`), not sbatch

## Tasks

### Task 1 — Add the reference files

1. Download the ICD-O-3 histology term list (SEER/NAACCR ICD-O-3 coding
   materials) and save it with the repo's reference inputs.
2. Copy `icdo2_to_icdo3_conversion.csv` to the same folder.
3. Record for each file: source, version, download date.
4. Inspect the term list before coding against it: column names, how
   histology and behavior are stored (`9650/3` versus separate columns), and
   whether a code has several rows (preferred term, synonyms, related terms).

**Done when:** both files are in the repo and their structure is written down
in the phase folder.

### Task 2 — Build the lookup

1. Read the term list as character.
2. Keep one row per histology + behavior: the preferred term. If the file
   marks term type, filter on it; if not, document the rule used.
3. Build a second lookup at 4-digit histology level for codes with no
   behavior digit (D-03).
4. Add path constants for both reference files to `R/00_config.R`.

**Done when:** the 5-digit lookup has no duplicate keys and the 4-digit lookup
has no duplicate keys.

### Task 3 — `describe_histology()` in `R/utils/utils_cancer.R`

Signature:

```r
describe_histology(code, site = NULL)
```

Returns a tibble, one row per input element, in input order:
`raw_code`, `hist4`, `behavior`, `icdo3_code`, `description`, `desc_source`.

Logic, in order:

1. Normalize: trim, drop a `/`, keep as character.
2. Valid shapes are 4 digits or 5 digits. Anything else is `unmatched` (D-06).
3. Try the ICD-O-3 lookup (5-digit key, else 4-digit key) -> `icdo3`.
4. If no match, convert with the ICD-O-2 table, then look up the converted
   code -> `icdo3_via_icdo2_conversion` (D-04). Use the site-specific row when
   `site` is supplied and matches; otherwise the non-site row (D-05).
5. Otherwise `unmatched`.

The function must return exactly `length(code)` rows.

**Done when:** unit checks in Task 5 pass.

### Task 4 — Script `R/NNN_tr_histology_descriptions.R`

1. Load `ID`, `SOURCE`, `HISTOLOGICAL_TYPE`, `MORPH`, the site column, and
   `HISTOLOGICAL_TYPE_DESCRIPTION` (if present) from `TUMOR_REGISTRY_ALL`
   using `open_pcornet_con()` / `get_pcornet_table()`.
2. Stack the two code columns into one `raw_code` column, as
   `build_tr_lymphoma_flags()` does.
3. Apply `describe_histology()`.
4. For rows still `unmatched`, fall back to the extract description when one
   exists and is under 74 characters -> `extract_fallback` (D-02, D-08).
5. Write `output/tr_histology_code_descriptions.csv`: one row per distinct
   `raw_code`, with rows, distinct patients, and counts by SOURCE.
6. Write `output/tr_histology_unmatched.csv`.
7. Log: number of distinct codes, share described by each `desc_source`,
   number unmatched, and the maximum length of `SITE_CODE_DESCRIPTION`.

**Done when:** both files are written and the log totals reconcile with the
row count of the stacked code table.

### Task 5 — Verification

| Check | Expected |
|---|---|
| `describe_histology("96503")` | Hodgkin lymphoma, NOS; source `icdo3` |
| `describe_histology("9650")` | same description via 4-digit lookup |
| `describe_histology("96573")` | converted to `96513`; source `icdo3_via_icdo2_conversion` |
| `describe_histology("96603")` | converted to `96593` |
| `describe_histology("850003")` | `unmatched`, raw value preserved |
| `describe_histology(NA)` | one row, `unmatched` |
| Output length | equals input length for a vector with repeats and NAs |
| Join on registry rows | row count before = row count after |
| Descriptions | none end at exactly 75 characters because of truncation |
| Coverage | every distinct registry code is described or listed in the unmatched file |

Add the row-count and coverage checks to `R/88_smoke_test_comprehensive.R`.

### Task 6 — Close-out

1. Add the script to `R/SCRIPT_INDEX.md` and to
   `R/39_run_all_investigations.R` if it should run with the full pipeline.
2. Regenerate the reference manual (R/89).
3. Record in the phase folder: counts by `desc_source`, the unmatched list,
   and the `SITE_CODE_DESCRIPTION` length finding.
4. Hand the unmatched list and the list of converted ICD-O-2 codes to the team
   alongside the pending HL/NHL list decision (D-07).

## Risks

- **Term list has several rows per code.** Picking the wrong one gives a
  synonym instead of the preferred term. Mitigation: Task 1 step 4 and the
  duplicate-key check in Task 2.
- **Behavior digit not in the term list.** Registries can record a behavior
  the list does not pair with that histology. Mitigation: fall back to the
  4-digit description and flag it in `desc_source`.
- **Site-dependent conversions duplicating rows.** Mitigation: D-05 and the
  row-count check.
- **Conversion table direction.** It maps ICD-O-2 to ICD-O-3 only. A code that
  is absent from it is not invalid; it may be an ICD-O-3-only code.

## Not in this plan

- Changes to `ICD_CODES$hl_histology` / `ICD_CODES$nhl_histology`.
- Re-export of the Gantt file.
