---
phase: 200
name: immunotherapy-med-admin-dispensing-capture-fix
status: planned
milestone: cross-milestone
depends_on: [Phase 199 complete]
tags: [immunotherapy, rituximab, methotrexate, r26, chemo-lists, treatment-capture]
created: 2026-11-12
revised: 2026-11-12
---

# Phase 200: Immunotherapy MED_ADMIN/DISPENSING Capture Fix - Context

**Gathered:** 2026-11-12  
**Revised:** 2026-11-12 (consolidated instructions; all open decisions resolved)  
**Status:** Ready for execution (200-01 then 200-02)

<domain>
## Phase Boundary

Fix treatment capture in `extract_immunotherapy_dates_with_codes()` (R/26) and extend the chemo
treatment code lists to include rituximab biosimilar HCPCS, oral MTX, and rituximab RxNorm CUIs;
exclude multivitamin RxNorm codes from the new immunotherapy MED_ADMIN/DISPENSING branches; gate
all pre-Phase-200 baseline-comparison blocks behind env flags; add R/88 smoke checks for the fix.
Then rerun the downstream pipeline chain through R/142 and R/170 on HiPerGator.

**Scope:**
1. R/26 `extract_immunotherapy_dates_with_codes()` — replace broken RXNORM_CUI guards with
   `get_chemo_hits()` calls for DISPENSING and MED_ADMIN; pass `immuno_ma_codes` (immunotherapy
   RxNorm CUIs minus 8 multivitamin CUIs, D-200-R2); relabel comments as Phase 200 (not Phase 199).
2. R/00_config.R:
   a. Add J8610 to `MTX_CODES$hcpcs` and `TREATMENT_CODES$chemo_hcpcs`; remove redundant J8610
      literal from `IMMUNE_DRUG_DEFS$Methotrexate$hcpcs`.
   b. Move Q5115/Q5119/Q5123 from `immunotherapy_hcpcs` to `chemo_hcpcs` (D-200-R1).
   c. Conditionally move rituximab RxNorm CUIs (121191, 1719312, 2049106) from `immunotherapy_rxnorm`
      to `chemo_rxnorm` if RxNav confirms they are rituximab products (D-200-R1).
   d. Add drug names to `MEDICATION_LOOKUP_JCODE_SUPPLEMENT`; verify by sourcing config in R.
3. Gate ENTIRE PRE199 save+comparison block in R/142 and PRE1922 comparison blocks in R/52 and
   R/170 behind env flags defaulting to off.
4. Write read-only tool `R/tools/check_immuno_fix_preview.R` — counts patients and dates by
   triggering_code and drug name that the new branches would add; shows vitamin codes separately.
5. Update R/88 Section 15bc: change [g] to one-direction; add [f] (immune_flag → autoimmune_dx);
   add Phase 200 checks 5a/5b/5c.
6. Parse-check all edited files; commit as Phase 200 work.
7. Rerun R/26 → R/28 → R/29 → R/52 → R/28 (180-enriched) → R/142 → R/170 → R/88 →
   check_199_full_history.R on HiPerGator (200-02).

**Out of scope:**
- Changes to `immune_flag`, `ever_brentuximab`, or `immune_flag_dx` columns (Phase 199).
- Changes to `has_autoimmune_dx` / `first_autoimmune_dx_date` (Phase 192.1).
- Indication-based filtering of rituximab/MTX (D-200-01: not done).

</domain>

<decisions>
## Implementation Decisions

### D-200-01 (Team Decision, 2026-11-12) — No indication-based filtering
Gantt treatment episodes capture ALL rituximab / methotrexate / immunotherapy administrations
regardless of clinical indication. Patients whose rituximab or MTX use may be for an autoimmune
condition are identified by the Phase 199 `immune_flag` column (with `immune_flag_dx`), and are
NOT removed from the timelines. No indication-based filtering is applied in R/26 or any downstream
script.

### D-200-R1 (Resolved, 2026-11-12) — All rituximab codes = Chemotherapy (Option A)
All rituximab HCPCS and RxNorm CUIs are classified as Chemotherapy. J9310–J9312 precedent;
R/170 regimen logic uses `treatment_type == "Chemotherapy"`. Resolves former D-200-02 (OPEN).
- Q5115/Q5119/Q5123 → `chemo_hcpcs` (remove from `immunotherapy_hcpcs`).
- 121191, 1719312, 2049106 → `chemo_rxnorm` (remove from `immunotherapy_rxnorm`), conditional on
  RxNav confirmation that 1719312 and 2049106 are rituximab products (confirmed by existing config
  comments; RxNav check in 200-02 preflight).
- Former line-722 warning ("Adding rituximab CUIs to chemo_rxnorm would inflate counts...") is
  superseded by D-200-R1.

### D-200-R2 (Resolved, 2026-11-12) — Exclude multivitamin RxNorm codes from new MED_ADMIN/DISPENSING branches
The 8 "questionable-vitamin" CUIs in `QUESTIONABLE_IMMUNO_CODES` (R/00_config.R line 2387)
are excluded from the NEW immunotherapy MED_ADMIN and DISPENSING branches only. PRESCRIBING
is unchanged. The filtered code vector is called `immuno_ma_codes`:
```r
immuno_ma_codes <- setdiff(
  TREATMENT_CODES$immunotherapy_rxnorm,
  names(QUESTIONABLE_IMMUNO_CODES)[QUESTIONABLE_IMMUNO_CODES == "questionable-vitamin"]
)
```
Starting count: 27 CUIs in `immunotherapy_rxnorm`. After setdiff with 8 vitamin codes: **19 codes**
(verified against current config; re-confirm after 2c rituximab CUI move — count may differ if 3
rituximab CUIs are moved out of `immunotherapy_rxnorm` before the setdiff). Team may revisit.
Resolves former D-200-03 (OPEN).

### D-200-04 (Rerun chain order)
R/26 → R/28 (default) → R/29 → R/52 → R/28 (180-enriched, options set) → R/142 → R/170 → R/88 →
`R/tools/check_199_full_history.R`. See 200-02 for exact HiPerGator commands.

### D-200-05 (Before/after counts)
Report per-treatment-type patients and episodes before vs after (from 90-day and 180-day CSVs).
Run `R/tools/check_immuno_fix_preview.R` before the main chain as a gate check.

</decisions>

<canonical_refs>
## Canonical References

All relevant code findings are captured in
`.planning/phases/200-immunotherapy-med-admin-dispensing-capture-fix/200-REVISION-NOTES.md`
(written 2026-11-12). Downstream agents MUST read that file rather than re-reading code.

### Key line numbers (from 2026-11-12 review — verify before editing)
- `QUESTIONABLE_IMMUNO_CODES`: R/00_config.R line 2387
- `TREATMENT_CODES$immunotherapy_rxnorm`: R/00_config.R line 3868 (27 CUIs)
- `MEDICATION_LOOKUP_JCODE_SUPPLEMENT`: R/00_config.R lines 2871–2884
- `DRUG_GROUPINGS` (J9312 entry): R/00_config.R ~line 2057
- `MTX_CODES`: R/00_config.R lines 747–756
- `IMMUNE_DRUG_DEFS$Methotrexate$hcpcs`: R/00_config.R ~line 873
- `TREATMENT_CODES$chemo_hcpcs` (J9310–J9312 at ~3213–3215): R/00_config.R line 3140
- `TREATMENT_CODES$immunotherapy_hcpcs` (Q5115/Q5119/Q5123 at ~3862–3864): R/00_config.R line 3851
- `TREATMENT_CODES$chemo_rxnorm` (target for rituximab CUIs): R/00_config.R line 3237
- R/142 PRE199 save block: lines 863–877; write.csv: line 879; comparison block: lines 883–903
- R/52 save_pre1922 function: lines 812–834; call sites: lines 837–838
- R/170 section 4.5 block: lines 894–965
- R/88 Section 15bc: defined at line 7627; [g] check: lines 7730–7744; [f] check area: lines 7714–7727; summary: line 7785
- `get_chemo_hits()`: R/utils/utils_treatment.R lines 181–291

</canonical_refs>

<code_context>
## Existing Code Insights

### get_chemo_hits() behaviour (do not re-read utils_treatment.R)
- DISPENSING path: maps NDC → RxCUI via ndc_crosswalk; filters rxcui %in% rxnorm_vector.
- MED_ADMIN path: RX-typed rows → MEDADMIN_CODE %in% rxnorm_vector; ND-typed rows → NDC crosswalk
  → rxcui. ND triggering_code = **resolved RxCUI** (not raw NDC) — line 278.
- Returns tibble(ID, treatment_date, triggering_code) or NULL. ENCOUNTERID NOT returned — callers
  must add `mutate(ENCOUNTERID = NA_character_)`.
- NDC crosswalk (R/108): harvests ALL NDCs from DISPENSING and MED_ADMIN regardless of drug class.

### R/26 unstaged diff (2026-11-12 state)
- DISPENSING and MED_ADMIN branches already converted to get_chemo_hits() with load_ndc_crosswalk().
- Comments read "Phase 199 fix 2026-11-12" — must be updated to "Phase 200 fix 2026-11-12".
- Both calls currently pass `TREATMENT_CODES$immunotherapy_rxnorm` directly — must switch to
  `immuno_ma_codes` (D-200-R2).
- Pre-dedup count checkpoint by triggering_code+source is already present after MED_ADMIN block —
  retain as-is.

### R/142 PRE199 block structure
Save block (863–877) + write.csv (879, ungated) + comparison block (883–903).
Both save and comparison must be gated; write.csv stays outside the gate.

</code_context>

---

*Phase: 200-immunotherapy-med-admin-dispensing-capture-fix*  
*Context revised: 2026-11-12 — sole source of truth is 200-REVISION-NOTES.md*
