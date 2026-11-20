# Phase NNN: Histology Code Descriptions — CONTEXT

**Status:** Draft (written 2026-11-20, outside the repo; phase number and script number to be assigned)
**Repo:** /blue/erin.mobley-hl.bcu/insurance_investigation

## Goal

Give every tumor-registry histology code a complete, standard description, so
registry rows can be read and reviewed without looking codes up by hand.

## Why this phase exists

Findings from the 2026-11-20 review of the tumor registry rows for the Gantt
patients (both-flag and neither-flag groups):

1. `HISTOLOGICAL_TYPE_DESCRIPTION` in TUMOR_REGISTRY1 is truncated at 75
   characters. 664 rows sit at exactly 75 characters and 51 at 74.
2. The truncation is in the delivered raw file
   (`/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915/TUMOR_REGISTRY1_Mailhot_V1.csv`),
   not in the DuckDB ingest or the R pipeline. The full text cannot be
   recovered from this delivery.
3. TUMOR_REGISTRY2 and TUMOR_REGISTRY3 carry the code in `MORPH`. Whether they
   carry any description column has not been checked.
4. The registry holds many histologies besides HL and NHL (carcinomas,
   sarcomas, CNS tumors, melanoma, leukemias), so the lookup has to cover all
   codes, not only the lymphoma lists.
5. Some rows use older ICD-O-2 codes that are not in ICD-O-3 (for example
   9657, 9658, 9660, 9666).

## What is already known about the codes

- Code column: `HISTOLOGICAL_TYPE` (TR1), `MORPH` (TR2/TR3); both present in
  `TUMOR_REGISTRY_ALL` (see `build_tr_lymphoma_flags()` in
  `R/utils/utils_cancer.R`).
- Usual format is 5 characters: 4-digit histology + 1-digit behavior
  (`96503` = 9650/3).
- Observed exceptions: 4-character codes with no behavior digit (`9650`), one
  6-character value (`850003`), and missing values.
- Existing flag logic matches on `substr(code, 1, 4)`.

## Inputs

| Input | Location | Notes |
|---|---|---|
| Registry rows | `TUMOR_REGISTRY_ALL` in the project DuckDB | via `get_pcornet_table()` |
| ICD-O-3 term list | To be downloaded (see D-02) | code + behavior + full term |
| ICD-O-2 to ICD-O-3 conversion | `icdo2_to_icdo3_conversion.csv` | 933 rows, exported 2026-11-20 from the NAACCR V27 edits metafile (`CONV2TO3` table); 5 codes are site-dependent |

## Decisions

- **D-01 Scope of codes.** All histology codes found in `TUMOR_REGISTRY_ALL`,
  for all patients, not only HL/NHL and not only Gantt patients.
- **D-02 Source of descriptions (to confirm).** Recommended: the official
  ICD-O-3 histology term list published by SEER/NAACCR, saved as a reference
  file in the repo. The in-extract description is used only as a fallback and
  is labelled as such.
- **D-03 Join key.** Histology (4 digits) + behavior (1 digit) when the
  behavior digit is present; histology only when it is not. The lookup returns
  the preferred term for the code.
- **D-04 ICD-O-2 codes.** A code with no ICD-O-3 match is converted with the
  conversion table and described by its ICD-O-3 equivalent. The original code
  is kept; the converted code is added as a separate column.
- **D-05 Site-dependent conversions.** For the 5 ICD-O-2 codes whose
  conversion depends on primary site, use the site-specific row when the
  registry site matches, otherwise the non-site row. Never let the join add
  rows.
- **D-06 Malformed codes.** Codes that are not 4 or 5 digits (for example
  `850003`) are not silently repaired. They are reported as unmatched with the
  raw value.
- **D-07 No change to cohort logic.** `ICD_CODES$hl_histology` and
  `ICD_CODES$nhl_histology` are not edited in this phase. Additions to those
  lists (9657, 9658, 9660, 9666, 9675, 9715, 9735, and the CLL/SLL question)
  are a separate team decision.
- **D-08 Description provenance.** Every described row records where its
  description came from: `icdo3`, `icdo3_via_icdo2_conversion`,
  `extract_fallback`, or `unmatched`.

## Deliverables

1. Reference file: ICD-O-3 code/term lookup, stored with the other reference
   inputs, with its download date and source recorded.
2. Reference file: `icdo2_to_icdo3_conversion.csv` added to the same place.
3. Utility: `describe_histology()` in `R/utils/utils_cancer.R`.
4. Script `R/NNN_tr_histology_descriptions.R` producing:
   - `output/tr_histology_code_descriptions.csv` — one row per distinct code
     in the registry: code, histology, behavior, converted code, description,
     description source, rows, patients, by SOURCE.
   - `output/tr_histology_unmatched.csv` — codes with no description.
5. `R/SCRIPT_INDEX.md` entry; reference manual regenerated (R/89).

## Out of scope

- Editing the HL/NHL histology lists or cohort rules (D-07).
- Site code descriptions (`SITE_CODE_DESCRIPTION` may have the same 75-character
  limit; check and log, fix in a later phase if needed).
- Requesting a corrected extract from the data provider.

## Open questions

1. Phase number and script number.
2. Confirm D-02: which ICD-O-3 term list file, and where reference inputs are
   kept in the repo.
3. Do TR2/TR3 have any description column worth using as a fallback?
4. Should the Gantt review data frames (both-flag, neither-flag) be re-exported
   with the full descriptions as part of this phase, or left to an ad hoc run?
