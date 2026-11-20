# Phase 215: reference file notes

## Term list: `Histology3_v27_20260821.xlsx`
- Source: NAACCR V27 Histology3 term list (file name carries `v27` and `20260821`). Staged from `phase_inbox/` on 2026-11-20; exact download date not recorded in the file.
- One sheet `Histology3`, 7,823 rows, 4 columns, all read as text: `Value` (4-digit histology), `strHistologyBehaviour` (1 digit; values 0,1,2,3,6,9), `Preferred` (TRUE/FALSE), `label` (term).
- Histology and behavior are separate columns (not `9650/3`). Key = `Value` + `strHistologyBehaviour`.
- A code has several rows: 1,223 rows `Preferred = TRUE` (exactly one per Value+behavior key, 0 keys without a preferred row), 6,600 synonyms.
- Rule used: keep `Preferred == TRUE`. 4-digit lookup (867 histologies): behavior 3 row if present, else lowest behavior digit.
- Labels are up to 232 characters and many carry a suffix such as `[SEE HEMATOPOIETIC DATABASE FOR REPORTING]`; kept as published.
- Observed vs plan table: preferred term for 9650/3 is "Classical Hodgkin lymphoma [...]", not "Hodgkin lymphoma, NOS". Tests assert the file's value, not the plan wording.

## Conversion: `icdo2_to_icdo3_conversion.csv`
- Source: NAACCR V27 edits metafile `CONV2TO3`, exported 2026-11-20 (per CONTEXT).
- 933 rows, 9 columns (`icdo2_hist, icdo2_beh, icdo2_code5, icdo3_hist, icdo3_beh, icdo3_code5, site, site_dependent, code_changed`), all text. `site` is a 3-character topography (e.g. `C73`), empty for non-site rows.
- 31 ICD-O-2 codes repeat in the file; site-dependent codes: 85103, 89300, 89301, 89303, 97313. Every repeated code has a non-site row.
- 96573 -> 96513 and 96603 -> 96593 confirmed in the file.

## Location
- Intended: `data/reference/` (repo convention). Conversion CSV moved there. The term-list xlsx is still in `phase_inbox/` because the move was blocked by the run's permissions (see SUMMARY).
