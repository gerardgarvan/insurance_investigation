# Phase 120: Normalize Supportive Care "Meaning" - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-10
**Phase:** 120-in-all-codes-resolved-next-tables-v2-1-tab-supportive-care-normalize-meaning-into-a-new-column-to-disambiguate-dosage-spelling-variants-and-generic-names
**Areas discussed:** Normalized value content, Output target, Normalization method, Brand/combo handling, RxNorm data source, Fallback, Column name

---

## Normalized value content

| Option | Description | Selected |
|--------|-------------|----------|
| Generic ingredient only | Strip dose/formulation/brand → bare ingredient; collapse salts (dexamethasone phosphate → dexamethasone) | ✓ |
| Ingredient + salt/ester | Keep chemically distinct salts separate | |
| Ingredient + route | Canonical ingredient plus route (oral vs injection) | |

**User's choice:** Generic ingredient only
**Notes:** Maps to RxNorm IN (ingredient) concept, not PIN — consistent with generic-only collapse.

---

## Output target

| Option | Description | Selected |
|--------|-------------|----------|
| New output workbook/CSV | Leave reference untouched, write enriched copy | |
| Modify reference xlsx in place | Add column directly to Supportive Care tab in the reference file | ✓ |
| Both | Enriched copy AND reference update | |

**User's choice:** Modify reference xlsx in place
**Notes:** Risk flagged — 5 scripts read the workbook. Planner must confirm no reader breaks on an extra trailing column (R/55 iterates all sheets incl. Supportive Care).

---

## Normalization method

| Option | Description | Selected |
|--------|-------------|----------|
| Rule-based parse + alias map | Strip dose/form tokens + brand→generic alias, extend canonicalize_drug_name | |
| Curated lookup table | Hand-map ~171 codes to canonical name | |
| RxNorm ingredient mapping | Map RXCUI → official RxNorm ingredient concept | ✓ |

**User's choice:** RxNorm ingredient mapping
**Notes:** No RxNorm asset exists in repo. Data source resolved in follow-up (RxNav API + cache).

---

## Brand/combination handling

| Option | Description | Selected |
|--------|-------------|----------|
| Brand→generic, flag combos | Zofran→ondansetron; combos keep combined label | ✓ |
| Brand→generic, split combos | Brands→generic; combos → primary ingredient only | |
| Keep brands as-is | Only strip dose/formulation; Zofran stays separate | |

**User's choice:** Brand→generic, flag combos

---

## RxNorm data source (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| RxNav REST API + cache | Call RxNav rxcui→IN once, cache to bundled CSV, offline thereafter | ✓ |
| Bundle RxNorm subset | Prepare/commit RXCUI→ingredient lookup, fully offline | |
| Rule-based parse (no RxNorm) | Skip RxNorm; parse Meaning + alias | |

**User's choice:** RxNav REST API + cache
**Notes:** First run needs internet (login node / local box, not compute node); cache to data/reference/.

---

## Fallback when unresolved (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| Rule-based parse fallback | Strip dose/form + brand→generic; combos combined label; every row gets a value | ✓ |
| Leave blank | Blank when unresolved for manual review | |
| Copy original Meaning | Raw Meaning text unchanged | |

**User's choice:** Rule-based parse fallback

---

## Column name (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| Normalized Meaning | Mirrors existing "Meaning" header | ✓ |
| Generic Name | Emphasizes generic ingredient | |
| Canonical Ingredient | Emphasizes RxNorm ingredient normalization | |

**User's choice:** Normalized Meaning

## Claude's Discretion

- Exact formulation/dose stop-word list and brand→generic alias entries (built from the 171 rows).
- RxNav cache file name/format.
- Reuse vs extend of canonicalize_drug_name() for the fallback.

## Deferred Ideas

- Normalizing Meaning on the other tabs (Chemotherapy, Radiation, SCT, Immunotherapy, Unrelated).
- Per-ingredient rollup summary tables (records/patients by Normalized Meaning).
