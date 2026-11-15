---
phase: 204-med-admin-name-based-capture
verified: 2026-11-14
status: passed_with_caveat
---

# Phase 204 Verification (HiPerGator run 2026-11-14)

## Results

- New by name (MED_ADMIN): Doxorubicin 137 records / 39 pts; Methotrexate 69 / 14; Rituximab 65 / 29; Brentuximab ~26 / <11; Nivolumab ~21 / <11; Pembrolizumab <11.
- Supportive care (pegfilgrastim) excluded.
- QC (MCAP-05): all 8 matched raw name strings are true matches (case variants only).
- Episodes (90d): 19,285 -> 19,324.
- Gantt 180 vs pre-204 (built with PRE-205 R/28 and R/142, so only 204 is measured): rows 22,520 -> 22,548; Chemotherapy patients 4,502 -> 4,514 (episodes 8,194 -> 8,222); all other types unchanged. `abvd_class` counts, `ever_abvd` (1,230), first-chemo ABVD (1,176), `immune_flag` (98), `ever_brentuximab` (954) unchanged.

## Caveats

- The in-R/26 MCAP-03 regression block ran before R/52 / R/142 rebuilt the Gantt CSVs, so it always passed and proved nothing. Replaced by standalone `R/204_gantt_before_after.R` (run after R/142). **PENDING HIPERGATOR:** run it to reproduce the comparison above.
- Plan 204-03 (R/88 SMOKE-204-01 structural checks, MCAP-04) was never executed; no R/88 section exists. Phase marked complete on the strength of the HiPerGator results; the R/88 section is an open follow-up.
- Token-level gap persists (Rituximab Gantt 478 vs raw 772; Brentuximab 776 vs 954). Remaining gap is drug-name attribution on episodes (only 54.6% of treatment episodes carry `drug_names`), not missed administrations. Input to Phase 205 scope.
