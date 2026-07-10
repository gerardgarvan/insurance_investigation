---
phase: 119-fix-death-cause-nhl-flag
verified: 2026-07-09T00:00:00Z
status: human_needed
score: 6/6 must-have requirements structurally verified (1 runtime item gated to HiPerGator)
human_verification:
  - test: "On HiPerGator, rebuild DuckDB then run R/102 and inspect output/death_cause_nhl_flag.csv"
    expected: "cause_of_death_is_nhl column has non-zero TRUE and/or FALSE values (not 100% blank); R/102 console reports non-zero TRUE/FALSE tallies"
    why_human: "Requires real PCORnet data + DuckDB file, absent on the Windows-local verification host. This is the actual goal payoff and is the explicit user-gated runtime check (matches phase 116/117/118 precedent)."
  - test: "On HiPerGator, run R/103_death_cause_diagnostic.R"
    expected: "Console prints per-source non-null counts + deceased-set coverage + classify_codes NHL matches for DEATH_CAUSE / TR1.CAUSE_OF_DEATH / TR2-3.DCAUSE, plus a single RECOMMENDATION line; writes output/diagnostics/death_cause_source_inventory.csv"
    why_human: "Read-only diagnostic requires the DuckDB PCORnet tables; runtime output is HiPerGator-only."
  - test: "On HiPerGator, run R/01 (force_reload=TRUE) then R/03, then get_pcornet_table(\"DEATH_CAUSE\") %>% collect() %>% nrow()"
    expected: "Returns > 0 rows; DuckDB now contains 16 tables so R/88 IS_LOCAL count check passes"
    why_human: "DuckDB rebuild + row count require the real CSV and HiPerGator filesystem."
---

# Phase 119: Fix death_cause_nhl_flag Verification Report

**Phase Goal:** `output/death_cause_nhl_flag.csv` carries REAL TRUE/FALSE values (not 100% blank) by sourcing cause of death from the separate PCORnet CDM `DEATH_CAUSE` table instead of the non-existent `DEATH.DEATH_CAUSE` column.

**Verified:** 2026-07-09 (structural, Windows-local — no data/DuckDB per phase 116/117/118 precedent)
**Status:** human_needed — all structural must-haves VERIFIED; the single runtime payoff (actual TRUE/FALSE tallies) is user-gated on HiPerGator.
**Re-verification:** No — initial verification.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 1 | R/103 read-only diagnostic inventories every candidate cause source over the deceased set | ✓ VERIFIED | R/103 SECTION 4 derives `deceased_ids`; SECTION 5 `get_pcornet_table("DEATH_CAUSE")` + `intersect(dc$ID, deceased_ids)`; SECTION 6 TR1.CAUSE_OF_DEATH + TR2/3.DCAUSE; SECTION 7 RECOMMENDATION line; SECTION 8 writes inventory CSV. 326 lines, no ggplot, does not touch death_cause_nhl_flag.csv. |
| 2 | DEATH_CAUSE table loaded via 5-touch-point recipe | ✓ VERIFIED | R/00_config.R:242 `"DEATH_CAUSE"` in PCORNET_TABLES; PCORNET_PATHS default pattern + Phase 119 comment (256-257); R/01:231-239 DEATH_CAUSE_SPEC (7 char cols); R/01:418 `DEATH_CAUSE = DEATH_CAUSE_SPEC`; R/03 auto-ingests via `TABLES_TO_INGEST <- PCORNET_TABLES` (unchanged, confirmed); R/88 count 15->16. |
| 3 | R/102 reads underlying cause from DEATH_CAUSE and classifies three-state, output contract preserved | ✓ VERIFIED | R/102 Section 4b `get_pcornet_table("DEATH_CAUSE")`, type_rank U/C/other, `left_join(..., by="ID")`; Section 5 `case_when` NA/TRUE/FALSE via `classify_codes() == "Non-Hodgkin Lymphoma"`; Section 6 `transmute(PATID=ID, cause_of_death_is_nhl)` + `write.csv(..., row.names=FALSE, na="")` to death_cause_nhl_flag.csv. DEATH-table cause read removed (negative pattern gone). |
| 4 | Labeled proxy backstop (D-05) off by default; R/35 stale assumption corrected | ✓ VERIFIED | R/102 Section 5b `USED_PROXY_BACKSTOP <- FALSE`, fires only `if (n_coded == 0)`, DIAGNOSIS-history proxy clearly labeled + D-05. R/35:64-70 Phase 119 CORRECTION comment + `get_pcornet_table("DEATH_CAUSE")` (Option A full correction), 5-sheet xlsx / death_cause_quality.xlsx output preserved (8 wb references intact). |
| 5 | Registered in R/39, validated by R/88 Section 15p, indexed in R/SCRIPT_INDEX.md | ✓ VERIFIED | R/39:192-193 R/103 before R/102, both present; R/88 Section 15p (2206-2324) with 14 checks + honest else-branch; SCRIPT_INDEX.md:148-149 R/102 Phase 119 note + R/103 row, count "4 (" at :202. |
| 6 | Output CSV carries REAL TRUE/FALSE values (not 100% blank) | ? UNCERTAIN | Requires HiPerGator runtime with real DEATH_CAUSE data + DuckDB rebuild. All code paths that produce this are structurally correct and wired; the actual tally is the gated user action. |

**Score:** 5/6 truths structurally VERIFIED; truth 6 (the runtime payoff) is user-gated (UNCERTAIN by design, not a gap).

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `R/103_death_cause_diagnostic.R` | Read-only cause-source inventory | ✓ VERIFIED | 326 lines; all Plan 01 acceptance greps pass; write.csv to death_cause_source_inventory.csv (na="", row.names=FALSE); no ggplot; does not touch real output. |
| `R/00_config.R` | DEATH_CAUSE in PCORNET_TABLES + path | ✓ VERIFIED | Line 242 entry, valid vector (closing `)` at 243), Phase 119 filename comment. Note: header comment line 18 still says "14 tables" (pre-existing stale doc, not a Plan 02 target line). |
| `R/01_load_pcornet.R` | DEATH_CAUSE_SPEC + TABLE_SPECS entry | ✓ VERIFIED | 7 col_character() cols; `DEATH = DEATH_SPEC,` comma added; `DEATH_CAUSE = DEATH_CAUSE_SPEC` final entry. |
| `R/102_death_cause_nhl_flag.R` | DEATH_CAUSE-sourced NHL flag + proxy | ✓ VERIFIED | All Plan 03 acceptance greps pass; negative `all_of(death_cause_col)` absent. |
| `R/35_death_cause_quality.R` | Corrected source reference | ✓ VERIFIED | Phase 119 correction + get_pcornet_table("DEATH_CAUSE"); xlsx shape intact. |
| `R/39_run_all_investigations.R` | R/103 registered | ✓ VERIFIED | Lines 192-193. |
| `R/88_smoke_test_comprehensive.R` | Section 15p + count 16 | ✓ VERIFIED | Section 15p (14 checks); IS_LOCAL count == 16 (line 3593); production >= 13 unchanged (3634). |
| `R/SCRIPT_INDEX.md` | R/103 row + count bump | ✓ VERIFIED | Rows 148-149, count 4 at line 202. |
| `output/diagnostics/death_cause_source_inventory.csv` | Runtime artifact | ? UNCERTAIN | Written only at HiPerGator runtime (gated). |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| R/103 | DEATH_CAUSE + TR view + deceased set | get_pcornet_table + classify_codes | ✓ WIRED | Pattern `get_pcornet_table("DEATH` present; intersect on deceased_ids. |
| R/00_config PCORNET_TABLES | R/03 TABLES_TO_INGEST | auto-pickup | ✓ WIRED | R/03 uses `TABLES_TO_INGEST <- PCORNET_TABLES` (no edit needed, confirmed). |
| R/01 TABLE_SPECS | DEATH_CAUSE DuckDB table | DEATH_CAUSE = DEATH_CAUSE_SPEC | ✓ WIRED | Present at R/01:418. |
| R/102 deceased set | DEATH_CAUSE codes | left_join by "ID" | ✓ WIRED | Section 4b `left_join(death_cause_by_patient, by="ID")`. |
| R/102 DEATH_CAUSE code | cause_of_death_is_nhl | classify_codes == NHL three-state | ✓ WIRED | Section 5 case_when. |
| R/88 Section 15p | R/102 + R/103 + config | readLines + grepl | ✓ WIRED | 14 checks, negative check `!grepl(all_of(death_cause_col))` matches R/102 reality. |

### Data-Flow Trace (Level 4)

Cause data variable is `DEATH_CAUSE`, sourced from `get_pcornet_table("DEATH_CAUSE")` (real DuckDB table, wired in Plan 02) — NOT hardcoded empty. The only static fallback is the explicit `is.null(dc_tbl)` guard emitting an empty tibble with a WARNING to rebuild DuckDB, which is correct defensive behavior, not a stub. Whether the source produces non-empty rows is the HiPerGator-gated runtime question (human_verification item 1/3). Structurally: FLOWING (real query, no hardcoded empties in the success path).

### Behavioral Spot-Checks

Step 7b SKIPPED (no runnable entry points without HiPerGator DuckDB data; all R scripts require the PCORnet extract). Runtime behavior routed to human_verification.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| NHLFIX-01 | 119-01 | R/103 diagnostic over deceased set | ✓ SATISFIED (structural) | R/103 full impl; runtime output gated. |
| NHLFIX-02 | 119-02 | DEATH_CAUSE loaded 5-touch-point, count 15->16 | ✓ SATISFIED | config + spec + R/03 auto + R/88 count 16. |
| NHLFIX-03 | 119-03 | R/102 reads DEATH_CAUSE (not DEATH col), underlying pref, three-state | ✓ SATISFIED | R/102 Section 4b/5 + negative pattern gone. |
| NHLFIX-04 | 119-03 | Labeled proxy backstop off by default + R/35 corrected | ✓ SATISFIED | Section 5b + R/35:64-98. |
| NHLFIX-05 | 119-04 | R/103 in R/39 + SCRIPT_INDEX documents (count 3->4) | ✓ SATISFIED | R/39:192-193 + SCRIPT_INDEX 148-149/202. |
| SMOKE-119-01 | 119-04 | R/88 Section 15p structural + gated runtime check | ✓ SATISFIED | Section 15p 14 checks incl. gated runtime. |

All 6 declared requirement IDs accounted for. REQUIREMENTS.md maps exactly NHLFIX-01..05 + SMOKE-119-01 to Phase 119 — no orphaned requirements.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| R/00_config.R | 18 | Header comment says "14 tables" (pre-existing, not updated) | ℹ️ Info | Cosmetic doc drift; not on a Plan 02 target line (Plan 02 targeted a "15 tables" count comment which did not exist near PCORNET_TABLES). Line 221 correctly documents DEATH_CAUSE. Does not affect goal. |

No TODO/FIXME/PLACEHOLDER, no empty-return stubs, no hardcoded-empty data in success paths across R/102 and R/103.

### Human Verification Required

1. **Runtime NHL tallies (goal payoff)** — On HiPerGator: rebuild DuckDB (R/01 force_reload + R/03), run R/102, confirm output/death_cause_nhl_flag.csv has non-zero TRUE and/or FALSE (not 100% blank).
2. **R/103 diagnostic run** — Confirms which source is populated; writes death_cause_source_inventory.csv.
3. **DEATH_CAUSE load** — `get_pcornet_table("DEATH_CAUSE") %>% collect() %>% nrow()` > 0 and DuckDB reports 16 tables.

### Gaps Summary

No structural gaps. Every code change the phase promised exists, is substantive, is wired, and is guarded by the R/88 Section 15p smoke checks whose assertions match the actual R/102/R/103 source (including the negative check). The single remaining item — the real TRUE/FALSE values in the output CSV — is intentionally gated to HiPerGator per the phase 116/117/118 precedent and the CRITICAL ENVIRONMENT CONSTRAINT; it is reported as human_verification, not a gap.

---

_Verified: 2026-07-09_
_Verifier: Claude (gsd-verifier)_
