# Phase 200: Immunotherapy MED_ADMIN/DISPENSING Capture Fix - Research

**Researched:** 2026-11-12
**Domain:** R/26 treatment capture, R/00_config.R code lists, Gantt episode pipeline
**Confidence:** HIGH — all findings from working-tree source, no external lookups required

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-200-01:** Gantt treatment episodes capture ALL rituximab / methotrexate / immunotherapy administrations regardless of indication. Patients whose rituximab or MTX use may be for an autoimmune condition are identified by `immune_flag` / `immune_flag_dx` (Phase 199). No indication-based filtering in R/26 or downstream.
- **D-200-04:** Rerun order: R/26 → R/28 → R/29 → R/52 → R/142 → R/170 → R/88 → `R/tools/check_199_full_history.R`.
- **D-200-05:** Before/after checkpoint paste-backs: (a) pre-dedup count table from R/26, (b) final row count from R/28, (c) check_199_full_history.R raw-only counts after the fix.

### Claude's Discretion
- **D-200-02 (OPEN):** Placement of Q5115/Q5119/Q5123 and additional rituximab RxNorm CUIs in R/00_config.R. Research resolves this below.
- **D-200-03 (OPEN):** Placement of J8610 (oral MTX). Research resolves this below.

### Deferred Ideas (OUT OF SCOPE)
- None listed in CONTEXT.md.
- Changes to `immune_flag`, `ever_brentuximab`, `immune_flag_dx` (Phase 199 scope).
- Changes to `has_autoimmune_dx` / `first_autoimmune_dx_date` (Phase 192.1 scope).
- Indication-based filtering of rituximab / MTX.
</user_constraints>

---

## Summary

The core R/26 bug fix is **already committed in the Phase 199 working tree** (commit 5df0fb6 / 45b5609). `extract_immunotherapy_dates_with_codes()` now calls `get_chemo_hits()` for both DISPENSING and MED_ADMIN, mirroring the chemo path. The Phase 199 working tree also already added Q5115/Q5119/Q5123 to `TREATMENT_CODES$immunotherapy_hcpcs`, the three rituximab RxNorm CUIs (121191, 1719312, 2049106) to `TREATMENT_CODES$immunotherapy_rxnorm`, and J8610 to `IMMUNE_DRUG_DEFS$Methotrexate$hcpcs`. What Phase 200 must do is verify this state is correct and complete, resolve D-200-02 and D-200-03 for the TREATMENT_CODES path (not just IMMUNE_DRUG_DEFS), and execute the rerun chain.

**Primary recommendation:** No new code-list changes are needed beyond what Phase 199 already committed. The plan's main tasks are: (1) verify and document the working-tree state against each open decision, (2) run the rerun chain on HiPerGator, (3) collect before/after checkpoint paste-backs.

---

## D-200-02 Resolution: Rituximab biosimilar HCPCS and RxNorm CUIs

### Current state in working tree

**Q5115 / Q5119 / Q5123 (biosimilar HCPCS):**
- Already in `TREATMENT_CODES$immunotherapy_hcpcs` (R/00_config.R lines 3862–3864). Added by Phase 199.
- NOT in `TREATMENT_CODES$chemo_hcpcs`. Intentional — see below.
- In `IMMUNE_DRUG_DEFS$Rituximab$hcpcs` (line 868). Used only by `check_199_full_history.R` / `get_drug_exposure_ids()`.

**Rituximab RxNorm CUIs (121191, 1719312, 2049106):**
- Already in `TREATMENT_CODES$immunotherapy_rxnorm` (R/00_config.R lines 3898–3900). Added by Phase 199.
- NOT in `TREATMENT_CODES$chemo_rxnorm`. Intentional — see below.
- `RITUXIMAB_CODES$rxnorm` = c("121191") only (line 742); the two additional product CUIs live directly in `immunotherapy_rxnorm`.

**J9310 / J9311 / J9312 (Rituximab IV, SC, Truxima — original codes):**
- Already in `TREATMENT_CODES$chemo_hcpcs` (lines 3213–3215) AND `DRUG_GROUPINGS` classified as "Chemotherapy" (lines 2055–2057).
- These entered `chemo_hcpcs` in Phase 39 and have never been moved.

### Why biosimilar HCPCS go in immunotherapy_hcpcs, not chemo_hcpcs

The comment block at R/00_config.R lines 721–726 (DOI-CODE-03) states explicitly: adding rituximab CUIs to `chemo_rxnorm` inflates chemo-detection counts and corrupts ABVD / BV+AVD regimen identification. The same logic applies to HCPCS:

- `chemo_hcpcs` feeds `extract_chemo_dates_with_codes()` → episodes with `treatment_type = "Chemotherapy"`. Adding Q5 codes there would create "Chemotherapy" Gantt bars for rituximab-only patients, corrupting regimen ID exactly as the comment warns.
- `immunotherapy_hcpcs` feeds `extract_immunotherapy_dates_with_codes()` → `treatment_type = "Immunotherapy"`. This is correct: rituximab biosimilars are not chemotherapy agents.
- J9310/J9311/J9312 being in `chemo_hcpcs` appears to be an earlier omission that pre-dates the classification split (they appear in both DRUG_GROUPINGS as "Chemotherapy" and are classified at line 2055). They are NOT being changed in this phase — moving them would itself corrupt existing episode comparisons and is out of scope (D-200-01).

**Decision for D-200-02:** Q5115/Q5119/Q5123 belong in `immunotherapy_hcpcs` only. The three rituximab RxNorm CUIs belong in `immunotherapy_rxnorm` only. Both are already correctly placed in the working tree. No changes needed to `chemo_hcpcs` or `chemo_rxnorm`.

**Impact on regimen ID:** None. The chemo path never sees Q5 codes or the new CUIs.

### DRUG_GROUPINGS gap for Q5 codes

Q5115/Q5119/Q5123 are absent from `DRUG_GROUPINGS`. That dict drives `drug_name` label assignment (Tier 1 reference lookup via `MEDICATION_LOOKUP`), not `treatment_type`. Because Q5 codes are detected in the immunotherapy path, `treatment_type` will be "Immunotherapy" regardless. The `drug_name` column will fall through to Tier 2 (MED_ADMIN free-text canonical) or Tier 3 (RxNorm cache). If the RxNorm cache resolves to "Rituximab" via ingredient CUI 121191, `canonicalize_drug_name()` should produce the canonical label. This is acceptable for Phase 200; a DRUG_GROUPINGS backfill for Q5 codes can be added in a future phase if drug_name NAs are reported. Note in the plan as a known gap, not a blocker.

---

## D-200-03 Resolution: J8610 (oral methotrexate 2.5 mg)

### Current state in working tree

- `MTX_CODES$hcpcs` = c("J9250", "J9260") — injection codes only (lines 748–749).
- `IMMUNE_DRUG_DEFS$Methotrexate$hcpcs` = c(MTX_CODES$hcpcs, "J8610") — J8610 already added here by Phase 199 (line 873). This covers `check_199_full_history.R` / `get_drug_exposure_ids()`.
- `TREATMENT_CODES$chemo_hcpcs`: J9250 and J9260 are present (lines 3194–3195). J8610 is NOT present.
- `TREATMENT_CODES$immunotherapy_hcpcs`: J8610 is NOT present.

### Which list should receive J8610

MTX is classified as "Chemotherapy" in DRUG_GROUPINGS (J9250/J9260 → "Chemotherapy" at lines 2032–2033) and MEDICATION_LOOKUP codes. Methotrexate episodes in the Gantt appear as `treatment_type = "Chemotherapy"`. J8610 (oral MTX 2.5 mg) is the same drug as J9250/J9260 — just a different route.

Adding J8610 to `TREATMENT_CODES$chemo_hcpcs` is therefore consistent with the existing classification and correct. It does NOT affect ABVD/BV+AVD regimen identification because methotrexate is not part of either regimen.

Adding J8610 to `MTX_CODES$hcpcs` (the reference vector at line 748) is optional — MTX_CODES is consumed only by IMMUNE_DRUG_DEFS. If J8610 is added to MTX_CODES, IMMUNE_DRUG_DEFS picks it up automatically via `c(MTX_CODES$hcpcs, "J8610")` and the "J8610" literal becomes redundant. The cleaner approach is to add J8610 to MTX_CODES$hcpcs and remove the literal from IMMUNE_DRUG_DEFS, so MTX_CODES remains the single source of truth for all MTX HCPCS codes.

**Decision for D-200-03:**
1. Add `"J8610"` to `MTX_CODES$hcpcs` (line ~748) with comment `# Methotrexate oral 2.5 mg (Phase 200)`.
2. Add `"J8610"` to `TREATMENT_CODES$chemo_hcpcs` (consistent with J9250/J9260 chemo classification).
3. Remove the literal `"J8610"` from `IMMUNE_DRUG_DEFS$Methotrexate$hcpcs` — it will now flow in via `MTX_CODES$hcpcs`. (This keeps the reference clean; the stopifnot guard at line 883 is unaffected.)

---

## Standard Stack

No new libraries. The pipeline uses:

| Component | Location | Purpose |
|-----------|----------|---------|
| `get_chemo_hits()` | R/26 | DISPENSING (NDC crosswalk) + MED_ADMIN (MEDADMIN_CODE/TYPE) matching — already applied to immunotherapy path |
| `load_ndc_crosswalk()` | R/26 / utils | NDC→RxNorm lookup used by both paths |
| `TREATMENT_CODES$immunotherapy_hcpcs/rxnorm` | R/00_config.R | Code lists consumed by `extract_immunotherapy_dates_with_codes()` |
| `MTX_CODES`, `RITUXIMAB_CODES`, `IMMUNE_DRUG_DEFS` | R/00_config.R | Reference vectors for DoI attribution and immune flag detection |
| `check_199_full_history.R` | R/tools | Read-only validation; raw-only counts should drop to near zero after fix |

---

## Architecture Patterns

### Treatment type assignment

`treatment_type` is assigned by the extraction function dispatcher in `extract_dates_with_codes()` (R/26 line ~749): every row returned by `extract_immunotherapy_dates_with_codes()` gets `treatment_type = "Immunotherapy"`. This is NOT driven by `DRUG_GROUPINGS`. DRUG_GROUPINGS drives only the `drug_name` label (Tier 1 of the three-tier resolution).

### Code list hierarchy

```
RITUXIMAB_CODES$hcpcs        — J9310/J9311/J9312 (original codes; J9312 = Truxima)
TREATMENT_CODES$chemo_hcpcs  — includes J9310/J9311/J9312 (Phase 39, pre-split)
TREATMENT_CODES$immunotherapy_hcpcs — Q5115/Q5119/Q5123 (Phase 199)
IMMUNE_DRUG_DEFS$Rituximab$hcpcs — J9310/J9311/J9312 + Q5115/Q5119/Q5123 (Phase 199)

MTX_CODES$hcpcs              — J9250/J9260 (+ J8610 after Phase 200)
TREATMENT_CODES$chemo_hcpcs  — J9250/J9260 (+ J8610 after Phase 200)
IMMUNE_DRUG_DEFS$Methotrexate$hcpcs — c(MTX_CODES$hcpcs) after J8610 added to MTX_CODES
```

### Rerun chain

```
R/26 (treatment episodes) →
R/28 (episode builder) →
R/29 (episode summary) →
R/52 (Gantt 90-day) →
R/142 (Gantt 180-day) →
R/170 (NHL subsets) →
R/88 (smoke checks) →
R/tools/check_199_full_history.R (validation)
```

Each script is run as: `source("R/<NNN>_<script>.R", local = new.env(parent = globalenv()))`

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| NDC→RxNorm matching for DISPENSING | Custom NDC lookup | `get_chemo_hits()` with `load_ndc_crosswalk()` — already handles this |
| MEDADMIN_CODE/TYPE matching | Custom MA filter | `get_chemo_hits()` RX/ND type dispatch — already handles this |

---

## Common Pitfalls

### Pitfall 1: Assuming IMMUNE_DRUG_DEFS covers TREATMENT_CODES

IMMUNE_DRUG_DEFS is used exclusively by `get_drug_exposure_ids()` → `check_199_full_history.R`. It does NOT feed `extract_immunotherapy_dates_with_codes()`. The Gantt episode path reads `TREATMENT_CODES$immunotherapy_hcpcs` and `TREATMENT_CODES$immunotherapy_rxnorm`. Both paths must be updated independently.

**Warning sign:** J8610 in IMMUNE_DRUG_DEFS but not in TREATMENT_CODES$chemo_hcpcs means oral MTX appears in the immune flag check but not in the Gantt chemo episodes.

### Pitfall 2: J9312 is Truxima in RITUXIMAB_CODES but Q5119/Q5123 are the other two biosimilars

RITUXIMAB_CODES$hcpcs currently lists J9312 as "Rituximab biosimilar (Truxima)". But Q5115 is ALSO Truxima (rituximab-abbs), Q5119 is Ruxience, Q5123 is Riabni. J9312 and Q5115 are both Truxima billing codes — one is the product-level J-code, the other the biosimilar Q-code. This duplication is intentional: different payers and facilities use different codes for the same biosimilar. No de-duplication is needed at the code-list level; episode deduplication handles date collisions.

### Pitfall 3: Closing DuckDB connection mid-block

`get_chemo_hits()` calls `get_pcornet_table()` which may invoke `open_pcornet_con()`. Never call `duck_query()` or any other `open_pcornet_con()` trigger between the start and end of R/26's extraction block. The existing code structure already handles this correctly; do not add new intermediate queries.

### Pitfall 4: DRUG_GROUPINGS missing Q5 codes → drug_name may be NA for biosimilar encounters

If Q5115/Q5119/Q5123 hits from PROCEDURES survive into episode detail but are not in MEDICATION_LOOKUP (Tier 1) and the MED_ADMIN free-text (Tier 2) is blank, `drug_name` falls to Tier 3 (RxNorm cache). If the cache pre-dates Phase 199, these codes may resolve to NA. This will show as NA drug_name in Gantt bars, not a crash. Flag in plan as a known gap; resolution is a future phase backfill of DRUG_GROUPINGS or rerunning R/60 after Phase 200.

---

## State of the Art (Working Tree)

| Item | Before Phase 199 | After Phase 199 (current) | Phase 200 adds |
|------|-----------------|--------------------------|---------------|
| DISPENSING in immunotherapy path | RXNORM_CUI guard → always NULL | `get_chemo_hits()` NDC crosswalk | nothing (already done) |
| MED_ADMIN in immunotherapy path | RXNORM_CUI guard → always NULL | `get_chemo_hits()` RX/ND dispatch | nothing (already done) |
| Q5115/Q5119/Q5123 | absent | in `immunotherapy_hcpcs` | nothing |
| Rituximab RxNorm CUIs | absent from immunotherapy_rxnorm | 121191/1719312/2049106 added | nothing |
| J8610 | absent everywhere | in IMMUNE_DRUG_DEFS only | add to MTX_CODES + chemo_hcpcs |
| IMMUNE_DRUG_DEFS | absent | Phase 199 structure | simplify J8610 ref |

---

## Open Questions

1. **J9310/J9311/J9312 in chemo_hcpcs — intentional or Phase 39 omission?**
   - What we know: They were added to `chemo_hcpcs` in Phase 39 (pre-immunotherapy split) and appear in DRUG_GROUPINGS as "Chemotherapy". They are NOT in `immunotherapy_hcpcs`. This means rituximab episodes from PROCEDURES are classified as "Chemotherapy" via the chemo path, while biosimilar (Q5) episodes from PROCEDURES are "Immunotherapy" via the immunotherapy path.
   - What's unclear: Whether the team intends J9310/J9311/J9312 to remain as "Chemotherapy" or should be moved to "Immunotherapy". The CONTEXT.md note at line 25 says "J9310 precedent means rituximab is classified as Chemotherapy in the pipeline (see R/00_config.R line 2055)" which confirms intent.
   - Recommendation: Leave J9310/J9311/J9312 in `chemo_hcpcs` as-is. This is the documented team intent per CONTEXT.md.

2. **drug_name resolution for Q5 biosimilar codes**
   - What we know: DRUG_GROUPINGS and MEDICATION_LOOKUP do not contain Q5115/Q5119/Q5123.
   - What's unclear: Whether the RxNorm cache (drug_name_lookup.rds) covers these Q-codes or will return NA.
   - Recommendation: Note as known gap in plan. After rerun, check the drug_name column in the immunotherapy episode detail for Q5 triggering_codes. If NA, schedule a future-phase fix.

---

## Environment Availability

Step 2.6: SKIPPED for local Windows machine. All execution is on HiPerGator. Standard module load pattern applies:

```r
module load R/4.5
R --no-save
source("R/26_treatment_episodes.R", local = new.env(parent = globalenv()))
```

---

## Validation Architecture

### Phase Requirements → Test Map

| Req | Behavior | Test Type | Command | Notes |
|-----|----------|-----------|---------|-------|
| Fix bug | DISPENSING + MED_ADMIN now matched via get_chemo_hits() | smoke | R/88 Section 15bb | already implemented |
| Code lists | Q5115/Q5119/Q5123 in immunotherapy_hcpcs | read source | grep R/00_config.R | already present |
| Code lists | 121191/1719312/2049106 in immunotherapy_rxnorm | read source | grep R/00_config.R | already present |
| Code lists | J8610 in MTX_CODES + chemo_hcpcs | read source after edit | grep R/00_config.R | Phase 200 adds this |
| Count drop | check_199_full_history.R raw-only counts near zero | manual checkpoint | see D-200-05 | HiPerGator paste-back |
| Episode chain | R/28 final row count after rerun | manual checkpoint | see D-200-05 | HiPerGator paste-back |

### R/88 Coverage

R/88 Section 15bb (committed in Phase 199) already checks the Phase 199 immune/brentuximab columns. The plan must confirm that the existing Section 15bb checks are sufficient for Phase 200 or note what additional checks are needed.

---

## Sources

### Primary (HIGH confidence)
- `R/00_config.R` lines 718–884 — RITUXIMAB_CODES, MTX_CODES, IMMUNE_DRUG_DEFS definitions; DOI-CODE-03 comment
- `R/00_config.R` lines 3140–3901 — TREATMENT_CODES list (chemo_hcpcs, chemo_rxnorm, immunotherapy_hcpcs, immunotherapy_rxnorm)
- `R/00_config.R` lines 2032–2057 — DRUG_GROUPINGS classifications for J9250/J9260/J9310/J9311/J9312
- `R/26_treatment_episodes.R` lines 388–488 — `extract_immunotherapy_dates_with_codes()` working-tree state
- `.planning/phases/200-immunotherapy-med-admin-dispensing-capture-fix/200-CONTEXT.md` — all locked decisions

---

## Metadata

**Confidence breakdown:**
- Bug fix state: HIGH — grep-confirmed in working tree
- D-200-02 resolution: HIGH — derived from explicit code-list structure and DOI-CODE-03 comment
- D-200-03 resolution: HIGH — derived from MTX_CODES / TREATMENT_CODES structure
- Rerun chain: HIGH — matches CONTEXT.md D-200-04
- DRUG_GROUPINGS gap for Q5: MEDIUM — need HiPerGator run to confirm drug_name behavior

**Research date:** 2026-11-12
**Valid until:** Until working tree changes (stable — no fast-moving external dependencies)
