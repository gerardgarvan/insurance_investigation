# Phase 164 — Generic drug naming: Doxorubicin (not Adriamycin) across Gantt charts

## Goal
Every treatment-episode Gantt chart labels the anthracycline as **Doxorubicin**.
"Adriamycin" never appears as a drug label, legend entry, facet, or color key in
any rendered chart or its backing data. Neither do any of its brand, salt, or
liposomal variants.

## Background
Adriamycin is a brand name for doxorubicin hydrochloride. Raw CDM fields
(PRESCRIBING.RAW_RX_MED_NAME, MED_ADMIN raw names, RXNORM/HCPCS descriptions)
carry both brand and generic strings. As a result, one drug can appear as two
separate Gantt rows or colors. This is the same failure mode as the
Vinblastine / Vinblastine Sulfate duplication.

## Scope
- IN: drug-name normalization upstream of all Gantt-chart scripts. That covers
  the 90-day and the 180-day episode windows, plus any per-regimen or per-cohort
  variants.
- IN: re-rendering every affected Gantt output.
- OUT: changing regimen abbreviations. "ABVD" stays ABVD (see D-2).
- OUT: non-Gantt tables, unless they share the same normalized drug column. If
  they do, they inherit the fix automatically and get listed in the summary.

## Decisions
- **D-1 (canonical form):** Map to the bare generic name `Doxorubicin`, title
  case. Salt and formulation suffixes are dropped: "Doxorubicin HCl",
  "Doxorubicin Hydrochloride", "Adriamycin PFS", "Adriamycin RDF" →
  `Doxorubicin`. This follows the Vinblastine precedent of one name per drug.
- **D-2 (regimen labels):** Regimen names such as "ABVD" are left unchanged.
  They are standard abbreviations, not drug labels.
- **D-3 (liposomal doxorubicin) — RESOLVED, option (b):** Liposomal doxorubicin
  (Doxil/Caelyx; HCPCS J9001 and related codes) collapses into `Doxorubicin`.
  No separate liposomal label appears in any Gantt chart.
- **D-4 (where the fix lives):** The fix is a single mapping applied once, at the
  point where drug names are first derived. Chart scripts must not do their own
  string replacement. If a normalization helper or lookup already exists (e.g.,
  from the Vinblastine fix), extend it.

## Exit criteria
1. A repo-wide grep of chart-feeding data and Gantt script outputs finds zero
   case-insensitive matches for `adriamycin|doxil|caelyx|liposom` in drug-label
   columns.
2. Every Gantt chart is re-rendered from a real HiPerGator run and visually
   confirmed. Doxorubicin appears as a single row/color per patient-episode.
3. The count of patients with doxorubicin is unchanged before vs. after. Any
   drop in episode or drug rows is fully explained by merged duplicates, either
   from brand/generic overlap or from liposomal/conventional overlap.
