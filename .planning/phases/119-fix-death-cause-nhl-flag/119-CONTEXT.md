# Phase 119: Fix death_cause_nhl_flag - Context

**Gathered:** 2026-07-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix `output/death_cause_nhl_flag.csv` (produced by `R/102_death_cause_nhl_flag.R`, Phase 118)
so its `cause_of_death_is_nhl` column actually carries real values instead of being **100%
blank**. The output contract (one row per deceased patient: `PATID` + a three-state NHL flag)
stays the same — this phase fixes the **source of the signal**, not the file shape.

</domain>

<decisions>
## Implementation Decisions

### Root Cause (confirmed)
- **D-01:** The current output has `PATID` populated for all 1,344 deceased patients but
  `cause_of_death_is_nhl` is **blank for every row** (0 TRUE, 0 FALSE, 1344 blank). Cause: the
  `DEATH` table's `DEATH_CAUSE` field that R/102 (and R/35) read is **not populated / not the
  right source** in this OneFlorida extract.
- **D-02:** In the PCORnet CDM, cause of death lives in a **separate `DEATH_CAUSE` table**
  (columns `DEATH_CAUSE`, `DEATH_CAUSE_CODE`, `DEATH_CAUSE_TYPE`, `DEATH_CAUSE_SOURCE`), NOT as
  a column inside the `DEATH` table. The pipeline currently loads a `DEATH` table but **no
  `DEATH_CAUSE` table** (see `PCORNET_TABLES` in R/00_config.R — 15 tables, DEATH_CAUSE absent).
  So R/102 reads a field that isn't there and degrades everything to NA.

### Approach: Investigate First, Then Implement
- **D-03:** This phase is **investigation-first**. Before rewriting R/102, exhaustively determine
  where a populated cause-of-death / NHL-death signal actually lives in the delivered extract.
  Check, in priority order:
  1. **The `DEATH` table itself** — inspect ALL columns (not just `DEATH_CAUSE`) for any
     cause-of-death, underlying-cause, or vital-status field that IS populated.
  2. **A delivered PCORnet `DEATH_CAUSE` table CSV** — the standard CDM cause-of-death table.
     If a `DEATH_CAUSE_*.csv` exists in the raw data dir, add it to `PCORNET_TABLES` / the
     loader / DuckDB ingest and read real cause codes from it.
  3. **`TUMOR_REGISTRY1/2/3`** — cancer-registry tables commonly carry a cause-of-death and/or
     vital-status field; check these for a populated cause/vital signal.
  4. **DIAGNOSIS / tumor registry** near the death date — as input to the proxy backstop.
- **D-04:** Expectation is that a usable signal EXISTS somewhere — **"it should find something."**
  Do NOT conclude "cause of death unavailable" without exhausting all the sources above. The
  investigation must be thorough (inspect actual column names, non-null counts per candidate
  field, and sample values on HiPerGator).

### Backstop (last resort only)
- **D-05:** ONLY if the investigation truly finds no cause-specific field anywhere: fall back to
  a **diagnosis-history proxy** — flag a deceased patient TRUE when their confirmed cancer
  diagnosis history includes NHL (via `classify_codes()` on DIAGNOSIS). This MUST be clearly
  labeled/documented as a proxy ("NHL in cancer history", not literal cause of death), and is a
  last resort — the primary goal is the real cause-of-death signal.

### Classification & Output Contract (unchanged from Phase 118)
- **D-06:** NHL = `classify_codes(<cause code>) == "Non-Hodgkin Lymphoma"` (ICD-10 C82-C86, C88;
  ICD-9 200, 202). Not broadened. Hodgkin C81 excluded.
- **D-07:** Keep the same output: `output/death_cause_nhl_flag.csv`, columns `PATID` +
  `cause_of_death_is_nhl`, three-state (TRUE / FALSE / blank), deceased patients only,
  `write.csv(row.names = FALSE, na = "")`. Fix what feeds the flag; keep the shape.

### Claude's Discretion
- Whether the fix lives in R/102 (rewrite its source) plus loader changes (R/00_config
  `PCORNET_TABLES`, R/01, R/03) if a new table must be loaded, or in a small diagnostic script
  first. Reuse R/35's DEATH-load and the field-availability guard pattern.
- Column-name / label wording if the proxy backstop is used (must signal it's a proxy).
- Whether to update R/35 too (it has the same DEATH_CAUSE-column assumption) — at minimum note it.
- R/88 smoke-test + R/39 registration updates consistent with the Phase 116/117/118 precedent.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The Broken Script + Its Assumptions
- `R/102_death_cause_nhl_flag.R` — the script to fix; reads `DEATH.DEATH_CAUSE` (empty), degrades to all-NA.
- `R/35_death_cause_quality.R` — same DEATH_CAUSE-column assumption; its completeness profiling
  (run on HiPerGator) is the fastest confirmation that DEATH_CAUSE is empty. Reuse/extend for the investigation.

### Data Loading (where a new table would be wired in)
- `R/00_config.R` — `PCORNET_TABLES` (~line 225, currently 15 tables, no DEATH_CAUSE),
  `PCORNET_PATHS`, `CONFIG$data_dir`; `CANCER_SITE_MAP` / `ICD9_CANCER_SITE_MAP` (NHL codes);
  `DEATH_CAUSE_MAP` (~line 983, ICD→cause category, reference).
- `R/01_load_pcornet.R` — table loading; where a DEATH_CAUSE table would be added.
- `R/03_duckdb_ingest.R` — DuckDB ingest of the loaded tables.

### Cancer Registry (candidate cause/vital source)
- `R/00_config.R` TUMOR_REGISTRY handling; `open_pcornet_con()` creates a `TUMOR_REGISTRY_ALL`
  view (utils_duckdb.R ~line 140) unioning TR1/TR2/TR3 — useful for inspecting registry fields.

### NHL Classification
- `R/utils/utils_cancer.R` — `classify_codes()`.
- `R/utils/utils_icd.R` — `normalize_icd()`.

### Precedent / Prior Context
- `.planning/phases/118-*/118-CONTEXT.md` — original three-state design (D-01..D-07) this phase preserves.
- `R/27_drug_name_resolution.R` — guarded self-bootstrap DuckDB pattern for a standalone script.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- R/35 DEATH-load block + DEATH_CAUSE/DEATH_CAUSE_CODE field-availability guard (D-78-01) — extend to inspect all DEATH columns and, if found, the DEATH_CAUSE table.
- `classify_codes()` — NHL determination, unchanged.
- `TUMOR_REGISTRY_ALL` DuckDB view — one-stop query surface for registry vital/cause fields.
- Guarded self-bootstrap (`USE_DUCKDB <- TRUE; if (!exists("pcornet_con", ...)) open_pcornet_con()`).

### Established Patterns
- Standalone "100+" investigation script (R/100/101/102); field-availability guards; write.csv(na="").
- Adding a PCORnet table: extend PCORNET_TABLES + PCORNET_PATHS (R/00_config) + loader (R/01) + ingest (R/03).

### Integration Points
- Fix feeds `output/death_cause_nhl_flag.csv`; downstream contract unchanged.
- If a new table is loaded, R/01/R/03/R/88 (table-count checks) may need updates.

</code_context>

<specifics>
## Specific Ideas

- The output already proves the shape/logic work (1,344 deceased rows, correct PATID, correct
  three-state plumbing) — only the input field is empty. The fix is about finding a populated source.
- "It should find something": treat all-blank as unacceptable. The investigation is the core of
  this phase; the code change is small once the right field is located.

</specifics>

<deferred>
## Deferred Ideas

- Broadening NHL beyond classify_codes()=="Non-Hodgkin Lymphoma" — still out of scope.
- Adding the raw cause code / cause category as extra columns — possible follow-up once a real
  source is found, but the requested contract is PATID + the NHL flag.

</deferred>

---

*Phase: 119-fix-death-cause-nhl-flag*
*Context gathered: 2026-07-09*
