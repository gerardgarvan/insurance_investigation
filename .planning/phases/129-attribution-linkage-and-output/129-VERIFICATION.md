---
phase: 129-attribution-linkage-and-output
verified: 2026-07-15T00:00:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "Run R/112 on HiPerGator against real DIAGNOSIS table"
    expected: "doi_attribution_report.xlsx written with 4 sheets; row counts logged; ±30/±90/±180 sensitivity values populated with real pair/patient counts"
    why_human: "No R runtime in this Windows environment; DuckDB data not local. Structural verification is complete; runtime pass is explicitly deferred to Phase 130."
---

# Phase 129: Attribution Linkage and Output — Verification Report

**Phase Goal:** Drug co-occurrence linkage is produced with honest three-state attribution semantics, HIPAA suppression applied, and co-occurrence language enforced throughout all four output sheets
**Verified:** 2026-07-15
**Status:** PASSED (with one scoped human-verification item for Phase 130)
**Re-verification:** No — initial verification

---

## HIPAA Suppression Reconciliation (Mandatory Investigation Point)

The ROADMAP.md Phase 129 design constraints and Success Criterion #3 specify:
- Design constraint: "HIPAA suppression: `suppress_small()` (threshold 11L) applied to every `n_patients` and `n_encounters` column in Sheet 3 before xlsx write"
- SC#3: "Every count column (n_patients, n_encounters) in Sheet 3 passes through `suppress_small()` before write — cells with values 1-10 appear as `<11`, never as raw integers"

The delivered script carries zero `suppress_small()` function calls. This is not an unreconciled deviation — it is a formally documented decision with a clear audit trail:

- **Phase 127 D-07** (`.planning/phases/127-code-set-and-infrastructure-centralization/127-CONTEXT.md`, line 31): "DoI outputs are internal investigation outputs — raw counts, NO automated HIPAA small-cell suppression. Manual suppression applied before any external sharing. This relaxes DOI-OUT-02 — the R/111 output should carry an 'internal-only; suppress manually before sharing' note rather than running `suppress_small()`. Recorded here in Phase 127 because it changes what Phase 129 builds; REQUIREMENTS.md DOI-OUT-02 updated to match."
- **REQUIREMENTS.md DOI-OUT-02** (updated per D-07): "DoI outputs are internal investigation outputs — raw counts, NO automated small-cell suppression; each output carries an 'internal-only; suppress manually before external sharing' note (relaxed per Phase 127 D-07, consistent with the v3.1 internal-investigation pattern)"
- **Phase 129 CONTEXT.md D-01**: "RAW counts, NO automated small-cell suppression. All four sheets carry raw `n_patients` / `n_encounters`, and every sheet carries an 'INTERNAL-ONLY: raw counts, no automated small-cell suppression — suppress manually before external sharing' note. This follows DOI-OUT-02 and Phase 127 D-07... ⚠ SUPERSEDES stale roadmap text."

**Assessment:** The phase goal statement in ROADMAP.md says "HIPAA suppression applied." This wording is stale — it predates D-07 and was not updated when DOI-OUT-02 was revised. The formal requirement (DOI-OUT-02, as amended by Phase 127 D-07) and the phase CONTEXT.md both govern. The substitution — raw counts + mandatory internal-only note on every sheet — is the authorized implementation. The goal statement's "HIPAA suppression applied" should be read in light of the amendment: the HIPAA risk is mitigated by the internal-only note and manual-suppression requirement, not by automated `suppress_small()`.

**Verdict:** The D-01 decision is legitimate, formally documented across three planning artifacts, and satisfies the authoritative DOI-OUT-02 requirement as amended. This is not a gap.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A new script R/112_doi_attribution_report.R exists and is classification-independent (R/111 unchanged) | VERIFIED | File exists at 658 lines; `git status R/111_doi_classification.R` shows no modification |
| 2 | Rituximab/MTX administrations are read from treatment_episode_detail.rds, filtered to RITUXIMAB_CODES \| MTX_CODES on triggering_code | VERIFIED | Lines 101-123: flat `rituximab_mtx_codes` vector built from all 4 code-list components; `filter(triggering_code %in% rituximab_mtx_codes)` |
| 3 | Dated HL-diagnosis DuckDB pull retains DX_DATE and is native-filtered (DX_TYPE-gated, hl_icd10/hl_icd9) before collect() | VERIFIED | Lines 149-161: `filter((DX_TYPE == "10" & DX %in% ICD_CODES$hl_icd10) \| (DX_TYPE == "09" & DX %in% ICD_CODES$hl_icd9)) %>% select(ID, DX_DATE) %>% collect()` |
| 4 | Two-tier linkage: ENCOUNTERID equi-join (tier 1) then ±DOI_ATTRIBUTION_WINDOW_DAYS PATID window (tier 2) | VERIFIED | Lines 191-243: tier1 `inner_join(..., by = "ENCOUNTERID")`; tier2 `inner_join(..., by = "ID") %>% filter(abs(as.integer(DX_DATE - treatment_date)) <= DOI_ATTRIBUTION_WINDOW_DAYS)`; named constant used throughout (no literal 90) |
| 5 | attribution_method column carries exactly encounter_id / temporal_window / none | VERIFIED | Lines 201, 235, 267: each tier and the unmatched set assigned the correct string literal; line 279 states the contract explicitly |
| 6 | likely_non_lymphoma_directed is three-state TRUE / FALSE / NA; NA fires when dated HL dx falls within ±window; NA never coerced to FALSE | VERIFIED | Lines 337-340: `case_when(attribution_method == "none" ~ FALSE, hl_active_in_window == TRUE ~ NA, TRUE ~ TRUE)`; `hl_active_in_window` tests `hl_dx_dated` dates against `DOI_ATTRIBUTION_WINDOW_DAYS`; logical NA used (not character); intermediate column dropped (line 344) |
| 7 | No column or prose uses `_for_` causal language | VERIFIED | `grep -c "_for_" R/112_doi_attribution_report.R` = 1; the single match is a documentation comment on line 405 ("NO column contains `_for_`") — not a column name or causal language. Zero executable `_for_` patterns. |

**Score:** 7/7 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `R/112_doi_attribution_report.R` | Attribution engine + 4-sheet workbook builder; min 120 lines; contains DOI_ATTRIBUTION_WINDOW_DAYS | VERIFIED | 658 lines; `DOI_ATTRIBUTION_WINDOW_DAYS` appears 17 times; `addWorksheet` / `add_worksheet` appears 4 times; contains all required sections 1-8 |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| R/112_doi_attribution_report.R | treatment_episode_detail.rds | `readRDS + filter triggering_code %in% c(RITUXIMAB_CODES..., MTX_CODES...)` | VERIFIED | Lines 93, 114-122: read and filtered; `triggering_code` pattern confirmed |
| R/112_doi_attribution_report.R | doi_encounters.rds | ENCOUNTERID equi-join then PATID temporal window | VERIFIED | Lines 91, 192-210, 228-243: read and linked via both tiers |
| R/112_doi_attribution_report.R | DIAGNOSIS (DuckDB) | Native DX_TYPE + hl_icd10/hl_icd9 filter, retain DX_DATE, before collect() | VERIFIED | Lines 149-155: filter-then-select-then-collect ordering confirmed; `hl_icd10` and `hl_icd9` patterns confirmed |
| R/112_doi_attribution_report.R | doi_attribution_report.xlsx | openxlsx2 `wb_workbook()` -> 4 worksheets -> `wb$save()` | VERIFIED | Lines 585-636: exactly 4 `add_worksheet` calls; `wb$save(OUT_XLSX)` inside `tryCatch`; `OUT_XLSX` bound to `doi_attribution_report.xlsx` filename |
| R/112_doi_attribution_report.R Metadata sheet | DOI_ATTRIBUTION_WINDOW_DAYS + sensitivity | ±30/±90/±180 comparison recompute via `count_window_matches` | VERIFIED | Lines 472-501: `count_window_matches` helper recomputes at `30L`, `DOI_ATTRIBUTION_WINDOW_DAYS`, `180L`; `sens_90` uses named constant (line 480) |

---

### Data-Flow Trace (Level 4)

R/112 is a non-rendering R script — its "output" is a file write and in-memory frames, not a UI component. Level 4 data-flow applies to the xlsx write path.

| Data Variable | Source | Produces Real Data | Status |
|---------------|--------|--------------------|--------|
| `doi_drug_links` (all 4 sheets) | Derived from `doi_enc` + `drug_admins` + `hl_dx_dated` via two-tier join + case_when | Yes — all derivations reference upstream .rds inputs; no hardcoded empty values | FLOWING |
| `df_patient_prevalence` | `doi_drug_links %>% filter/group_by/summarise` | Yes — real aggregation from linked frame | FLOWING |
| `df_encounter_cooccurrence` | `doi_drug_links %>% filter/select` | Yes — detail rows from linked frame | FLOWING |
| `df_drug_doi_summary` | `doi_drug_links %>% filter/group_by/summarise` | Yes — real aggregation from linked frame | FLOWING |
| `df_metadata` | `drug_admins`, `doi_drug_links`, `count_window_matches()` | Yes — counts derived from real data frames; no hardcoded empty values | FLOWING |

Note: All four data frames will have zero rows on Windows (no .rds inputs available), but the code paths are structurally correct and will produce real rows at HiPerGator runtime. `tryCatch` on `wb$save()` prevents hard failure on Windows.

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — no R runtime in this Windows environment; no DuckDB data available locally. Structural/static verification is complete per phase charter. Runtime gate is Phase 130 (HiPerGator).

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| DOI-ATTR-01 | 129-01-PLAN.md | Two-tier ENCOUNTERID-then-±90-day-PATID linkage with `DOI_ATTRIBUTION_WINDOW_DAYS` | SATISFIED | Tier 1 ENCOUNTERID join (line 192); Tier 2 PATID window with named constant (lines 228-243) |
| DOI-ATTR-02 | 129-01-PLAN.md | Three-state `likely_non_lymphoma_directed` (TRUE/FALSE/NA); NA = HL also active in window; no NA→FALSE coercion | SATISFIED | `case_when` at lines 337-340; NA used directly as logical; no `replace_na` or `coalesce` collapses NA |
| DOI-ATTR-03 | 129-01-PLAN.md | `attribution_method` column (encounter_id/temporal_window/none); all column names use co-occurrence language; no `_for_` | SATISFIED | Three values assigned correctly; zero executable `_for_` patterns in column names |
| DOI-OUT-01 | 129-02-PLAN.md | 4-sheet Tableau-ready xlsx (Patient Prevalence, Encounter Co-occurrence w/ attribution_method, Drug x DoI Summary, Metadata) | SATISFIED | Exactly 4 `add_worksheet` calls with correct sheet names (lines 588, 598, 608, 618); `attribution_method` in df_encounter_cooccurrence (line 418) |
| DOI-OUT-02 | 129-02-PLAN.md | Raw counts; NO `suppress_small`; exact internal-only note on every sheet | SATISFIED | 0 non-comment `suppress_small` calls; `internal_only_note` defined at line 379 with exact string; referenced in `make_subtitle()` applied to all 4 sheets |
| DOI-OUT-03 | 129-02-PLAN.md | Metadata documents ±90 window + ±30/±180 sensitivity; CAVEATS footnote on every sheet | SATISFIED | `count_window_matches` at 30L/DOI_ATTRIBUTION_WINDOW_DAYS/180L (lines 479-481); `caveats_footnote` written as footer on every sheet via `add_styled_sheet` (line 565) |

**Orphaned requirements check:** `DOI-QA-01`, `DOI-QA-02`, `DOI-QA-03` are mapped to Phase 130 (pending) — not orphaned here. All six Phase 129 requirement IDs are accounted for.

---

### Anti-Patterns Found

| File | Line(s) | Pattern | Severity | Impact |
|------|---------|---------|----------|--------|
| R/112_doi_attribution_report.R | 370, 428, 523 | `suppress_small` appears 3 times | INFO | All three occurrences are in documentation comments (`# no suppress_small per D-01`), not function calls. Verified by reading each line. Zero executable suppress_small calls. |
| R/112_doi_attribution_report.R | 405 | `_for_` appears once | INFO | Documentation comment: `# NO column contains "_for_"`. Not a column name. Zero executable `_for_` patterns. |

No blockers. No stubs. No hardcoded empty returns in data paths.

---

### Human Verification Required

#### 1. HiPerGator Runtime Gate

**Test:** Run `Rscript R/112_doi_attribution_report.R` on HiPerGator against the real PCORnet DIAGNOSIS table and the real .rds inputs from Phases 126-128.
**Expected:** Script completes without error; `doi_attribution_report.xlsx` is written to `CONFIG$cache$outputs_dir`; logged messages show non-zero row counts for `hl_dx_dated`, `drug_admins`, `doi_drug_links`, and all four df_ frames; `df_metadata` shows real pair/patient counts for ±30/±90/±180 sensitivity rows.
**Why human:** No R runtime or DuckDB data in this Windows environment. This is the Phase 130 definition-of-done gate per ROADMAP.md. Structural verification is complete; this item belongs to Phase 130.

---

### Gaps Summary

No gaps identified. All seven observable truths are verified. All six requirement IDs (DOI-ATTR-01/02/03, DOI-OUT-01/02/03) are satisfied by the code as written. The HIPAA suppression question is resolved by a formally documented decision chain (Phase 127 D-07 → DOI-OUT-02 amendment → Phase 129 CONTEXT.md D-01) — not a gap.

The one human-verification item (HiPerGator runtime) is a Phase 130 concern by explicit design; it does not block Phase 129's status.

---

_Verified: 2026-07-15_
_Verifier: Claude (gsd-verifier)_
