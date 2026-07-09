# Phase 119: Fix death_cause_nhl_flag - Research

**Researched:** 2026-07-09
**Domain:** PCORnet CDM mortality data model — DEATH vs DEATH_CAUSE tables; NAACCR tumor-registry
cause-of-death fields; pipeline wiring for a new table
**Confidence:** HIGH (data-model structure confirmed against live extract audit files;
PCORnet CDM v6 schema confirmed via data-models-service.research.chop.edu; NAACCR item #1910
confirmed via apps.naaccr.org)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Output has 1,344 deceased patients; `cause_of_death_is_nhl` is blank for every
  row because `DEATH.DEATH_CAUSE` (the column R/102 reads) is not populated in this OneFlorida+
  extract.
- **D-02:** In PCORnet CDM, cause of death lives in a **separate `DEATH_CAUSE` table**, NOT as
  a column inside DEATH. The pipeline loads DEATH but not DEATH_CAUSE. R/102 reads a field that
  isn't there and degrades to NA.
- **D-03:** Approach is **investigate-first**. Priority order: (1) DEATH table — all columns,
  (2) DEATH_CAUSE table CSV, (3) TUMOR_REGISTRY1/2/3 cause/vital fields, (4) DIAGNOSIS proxy.
- **D-04:** "It should find something" — do NOT accept all-blank without exhausting all sources.
- **D-05:** Proxy backstop (deceased + NHL in diagnosis history) is LAST RESORT only; must be
  clearly labeled as proxy if used.
- **D-06:** NHL = `classify_codes() == "Non-Hodgkin Lymphoma"` (ICD-10 C82-C86, C88; ICD-9
  200, 202). Not broadened; Hodgkin (C81) excluded.
- **D-07:** Output contract unchanged: `output/death_cause_nhl_flag.csv`, columns `PATID` +
  `cause_of_death_is_nhl`, three-state (TRUE/FALSE/blank), `write.csv(row.names=FALSE, na="")`.

### Claude's Discretion
- Whether fix lives in R/102 rewrite + loader changes, or a small diagnostic script first.
- Reuse R/35's DEATH-load and field-availability guard pattern.
- Column-name wording if proxy backstop is used (must signal it is a proxy).
- Whether to update R/35 too (same DEATH_CAUSE-column assumption).
- R/88 smoke-test + R/39 registration updates consistent with Phase 116/117/118 precedent.

### Deferred Ideas (OUT OF SCOPE)
- Broadening NHL beyond `classify_codes() == "Non-Hodgkin Lymphoma"`.
- Adding the raw cause code or cause category as extra columns to the output.
</user_constraints>

---

## Summary

The root cause is confirmed by the project's own `output/diagnostics/date_column_regex_audit.csv`:
the extract contains a **separate `DEATH_CAUSE` table** (columns `ID`, `DEATH_CAUSE`,
`DEATH_CAUSE_CODE`, `DEATH_CAUSE_TYPE`, `DEATH_CAUSE_SOURCE`, `DEATH_CAUSE_CONFIDENCE`) which
is never loaded by this pipeline. The `DEATH` table has only five columns
(`ID, DEATH_DATE, DEATH_DATE_IMPUTE, DEATH_SOURCE, DEATH_MATCH_CONFIDENCE, SOURCE`) — no
cause-of-death column at all. R/102 looks for `DEATH_CAUSE` inside `DEATH`, finds nothing, and
produces all-blank output.

The same audit file confirms that the TUMOR_REGISTRY tables carry secondary cause-of-death
signals: `TUMOR_REGISTRY1.CAUSE_OF_DEATH` (a NAACCR ICD field), and
`TUMOR_REGISTRY2.DCAUSE` / `TUMOR_REGISTRY3.DCAUSE` (NAACCR-abbreviated name for the same
concept). The `missing_values_audit.csv` shows `TUMOR_REGISTRY2.DCAUSE` is 93% missing (27/404
rows have a value). `TUMOR_REGISTRY1.CAUSE_OF_DEATH` and `TUMOR_REGISTRY3.DCAUSE` do not appear
in the missingness report, meaning they are either 100% missing or 0% missing (those cases are
excluded from the report). Given TR3 has only 15 rows, and TR1 has 726 rows all with 100% missing
dates, these are likely sparse.

**Primary recommendation:** Load the already-delivered `DEATH_CAUSE_Mailhot_V1.csv` table into
the pipeline (it is in the extract — the audit proves its schema exists). Write a diagnostic
script first that checks non-null counts in DEATH_CAUSE and all TUMOR_REGISTRY fields before
rewriting R/102.

---

## Key Facts Confirmed from Extract Audit Files

These are HIGH confidence findings because they come directly from `output/diagnostics/`
files produced by running the pipeline against the real data on HiPerGator.

### Source: `output/diagnostics/date_column_regex_audit.csv`

| Table | Column | Populated? |
|-------|--------|-----------|
| DEATH | ID, DEATH_DATE, DEATH_DATE_IMPUTE, DEATH_SOURCE, DEATH_MATCH_CONFIDENCE, SOURCE | Yes (6 cols, no cause field) |
| DEATH_CAUSE | ID, DEATH_CAUSE, DEATH_CAUSE_CODE, DEATH_CAUSE_TYPE, DEATH_CAUSE_SOURCE, DEATH_CAUSE_CONFIDENCE, SOURCE | Schema confirmed (7 cols) — POPULATION UNKNOWN until diagnostic runs |
| TUMOR_REGISTRY1 | CAUSE_OF_DEATH | Schema confirmed — population UNKNOWN |
| TUMOR_REGISTRY1 | COMBINED_LAST_STATUS | Schema confirmed — population UNKNOWN |
| TUMOR_REGISTRY2 | VITAL | Schema confirmed |
| TUMOR_REGISTRY2 | DCAUSE | Schema confirmed |
| TUMOR_REGISTRY2 | DOD | Date column, 404 rows |
| TUMOR_REGISTRY3 | VITAL | Schema confirmed |
| TUMOR_REGISTRY3 | DCAUSE | Schema confirmed |
| TUMOR_REGISTRY3 | DOD | Date column, 15 rows |

### Source: `output/diagnostics/missing_values_audit.csv`

| Table | Column | N Total | N Present | Pct Present |
|-------|--------|---------|-----------|-------------|
| TUMOR_REGISTRY2 | DCAUSE | 404 | 28 | 6.93% |

All other candidate cause-of-death columns are absent from the missingness report, which the
auditor only populates for columns with >= 1 missing value. This means they are either 100%
missing or 100% present. Given TR1's dates are all 100% missing, `CAUSE_OF_DEATH` is likely
sparse in TR1 too — but we cannot confirm without running the diagnostic on HiPerGator.

---

## PCORnet CDM Mortality Data Model

**Confidence: HIGH** (confirmed via data-models-service.research.chop.edu for PCORnet v6.0;
SAS DDL at github.com/LHSNet/PCORNet-CDM; corroborated by live extract audit)

### DEATH Table (already loaded — 6 columns)

| Column | Type | Notes |
|--------|------|-------|
| PATID (ID in this extract) | char | Patient ID |
| DEATH_DATE | date | Date of death — parsed |
| DEATH_DATE_IMPUTE | char | Which date components were imputed |
| DEATH_SOURCE | char | Source of death record (D=death certificate, L=local EHR, N=NDI, S=SSA, V=VA) |
| DEATH_MATCH_CONFIDENCE | char | E=excellent, F=fair, G=good, N=no match, P=poor |
| SOURCE | char | Partner/site identifier |

**Critical fact:** DEATH has NO cause-of-death column. This is by design in the PCORnet CDM —
cause of death is in a separate table.

### DEATH_CAUSE Table (NOT currently loaded — 7 columns)

| Column | Type | Notes |
|--------|------|-------|
| PATID (ID in this extract) | char | Patient ID — join key to DEATH |
| DEATH_CAUSE | char(8) | ICD cause-of-death code (e.g. "C83.3") — THIS is the field R/102 needs |
| DEATH_CAUSE_CODE | char(2) | Coding system: 09=ICD-9-CM, 10=ICD-10-CM, OT=other, UN=unknown |
| DEATH_CAUSE_TYPE | char(2) | C=contributing, O=other, U=underlying, I=inferred (one record should be U) |
| DEATH_CAUSE_SOURCE | char(2) | Source: D=death cert, L=local EHR, N=NDI, S=SSA, V=VA |
| DEATH_CAUSE_CONFIDENCE | char(2) | E=excellent, F=fair, G=good, N=no match, P=poor |
| SOURCE | char | Partner/site identifier |

**For NHL classification:** Filter on `DEATH_CAUSE_TYPE == "U"` (underlying cause) or take
`first()` after arranging by type. Pass `DEATH_CAUSE` to `classify_codes()`. The column already
holds ICD codes; no additional normalization is needed.

**File naming pattern:** `DEATH_CAUSE_Mailhot_V1.csv` (follows the project convention of
`{TABLE}_Mailhot_V1.csv`).

### NAACCR Cause-of-Death Fields in TUMOR_REGISTRY

The TUMOR_REGISTRY tables are NAACCR-formatted. Relevant fields confirmed in this extract:

| Table | Column | NAACCR Item | Description | Population |
|-------|--------|-------------|-------------|-----------|
| TUMOR_REGISTRY1 | CAUSE_OF_DEATH | #1910 | ICD-coded cause of death from death certificate | UNKNOWN — diagnostic needed |
| TUMOR_REGISTRY1 | COMBINED_LAST_STATUS | #1762 | Vital status (0=dead, 1=alive) combined from all follow-up | UNKNOWN |
| TUMOR_REGISTRY2 | DCAUSE | #1910 | Same as CAUSE_OF_DEATH (abbreviated column name) | 6.93% present (28/404 rows) |
| TUMOR_REGISTRY2 | VITAL | #1760 | Vital status (0=dead, 1=alive) | UNKNOWN |
| TUMOR_REGISTRY3 | DCAUSE | #1910 | Same as CAUSE_OF_DEATH | UNKNOWN |
| TUMOR_REGISTRY3 | VITAL | #1760 | Vital status (0=dead, 1=alive) | UNKNOWN |

NAACCR item #1910 (`causeOfDeath`): 4-character field using ICD-7, -8, -9, or -10 codes.
Special values: 0000 = patient alive, 7777 = death cert unavailable, 7797 = cert available but
cause not coded. Source: apps.naaccr.org/data-dictionary/data-dictionary/version=24/data-item-view/item-number=1910/

NAACCR item #1760 (`vitalStatus`): Single digit. 0 = Dead, 1 = Alive. Cannot be passed to
`classify_codes()` — it confirms death but does not identify cause.

**TUMOR_REGISTRY coverage of the 1,344 deceased patients is likely very small:** TR2 has only
404 total rows (all tumors, not just deceased), TR3 has 15. They are minority-site registries.
The main TR1 with 726 rows has 100% missing dates — likely date fields are masked, not the
coded fields like `CAUSE_OF_DEATH`. The diagnostic script must check non-null counts for
`CAUSE_OF_DEATH` in TR1 explicitly.

---

## Priority Order for the Diagnostic Script

The diagnostic script (`R/103_death_cause_diagnostic.R`) runs on HiPerGator and prints the
answer before any rewrite of R/102. The planner should treat this as the first wave.

| Priority | Source | Column | Action if Populated |
|----------|--------|--------|---------------------|
| 1 (PRIMARY) | DEATH_CAUSE table | DEATH_CAUSE | Load table, filter DEATH_CAUSE_TYPE=="U", classify → done |
| 2 | TUMOR_REGISTRY1 | CAUSE_OF_DEATH | Join TR1 to deceased PATID set, classify CAUSE_OF_DEATH |
| 3 | TUMOR_REGISTRY2/3 | DCAUSE | Join TR2/TR3 to deceased PATID set, classify DCAUSE |
| 4 (LAST RESORT) | DIAGNOSIS | DX | Flag if deceased patient has NHL DX in confirmed cancer history |

---

## How to Add DEATH_CAUSE Table to This Pipeline

**Confidence: HIGH** (from reading R/00_config, R/01_load_pcornet, R/03_duckdb_ingest directly)

There are exactly 5 touch-points for adding a new PCORnet table. All follow the established
pattern for how `DEATH` was added in Phase 57 and `DISPENSING` + `MED_ADMIN` in Phase 9.

### Touch-point 1: R/00_config.R — PCORNET_TABLES vector (~line 225)

Add `"DEATH_CAUSE"` to the `PCORNET_TABLES` character vector. This vector drives both
PCORNET_PATHS and downstream loops. Count changes from 15 to 16.

```r
PCORNET_TABLES <- c(
  # ... existing 15 tables ...
  "DEATH",           # Phase 57
  "DEATH_CAUSE"      # Phase 119: cause-of-death classification
)
```

### Touch-point 2: R/00_config.R — PCORNET_PATHS override (if needed)

The default path is `file.path(CONFIG$data_dir, "DEATH_CAUSE_Mailhot_V1.csv")`.
No override is needed unless the file has a non-standard name. Check the actual filename
on HiPerGator first (in the diagnostic script).

### Touch-point 3: R/01_load_pcornet.R — column type spec

Add `DEATH_CAUSE_SPEC` near the DEATH_SPEC block (~line 210) and add it to `TABLE_SPECS`.
All DEATH_CAUSE columns are character. No date columns, no numeric columns.

```r
DEATH_CAUSE_SPEC <- cols(
  ID                    = col_character(),
  DEATH_CAUSE           = col_character(),
  DEATH_CAUSE_CODE      = col_character(),
  DEATH_CAUSE_TYPE      = col_character(),
  DEATH_CAUSE_SOURCE    = col_character(),
  DEATH_CAUSE_CONFIDENCE = col_character(),
  SOURCE                = col_character()
)
```

Then add to `TABLE_SPECS`:
```r
TABLE_SPECS <- list(
  # ... existing entries ...
  DEATH_CAUSE = DEATH_CAUSE_SPEC   # Phase 119
)
```

### Touch-point 4: R/03_duckdb_ingest.R — TABLES_TO_INGEST

`TABLES_TO_INGEST <- PCORNET_TABLES` already picks up whatever is in PCORNET_TABLES. No code
change needed in R/03 itself — adding DEATH_CAUSE to PCORNET_TABLES automatically includes it.

DEATH_CAUSE does NOT have an ENCOUNTERID column, so no change to `TABLES_WITH_ENCOUNTERID`.

### Touch-point 5: R/88_smoke_test_comprehensive.R — table count assertion (~line 3471)

There is a DuckDB table-count assertion `length(tables_found) == 15` gated behind `IS_LOCAL`.
If DEATH_CAUSE is added to the real DuckDB but the fixture DuckDB (used locally) is not
updated, the local assertion will fail. Options:
- Update the local fixture to include DEATH_CAUSE (preferred for correctness)
- Update the assertion to `== 16` and note that local fixture needs updating
- Add a separate Phase 119 smoke-test section (Section 15p) that checks R/103 and R/102

The existing DEATH_CAUSE_MAP validation in R/88 (Section ~line 698) is unrelated — it validates
the ICD-to-cause-category lookup constant, not the table.

---

## Diagnostic Script Spec (R/103_death_cause_diagnostic.R)

The planner should task a Wave 0 or Wave 1 script that produces a console report answering
exactly the questions the implementation decision depends on. The script should NOT modify any
outputs — it is read-only investigation.

### What to check and report

```
=== Phase 119 Diagnostic: Cause-of-Death Signal Inventory ===

--- Source 1: DEATH_CAUSE table ---
  CSV exists at PCORNET_PATHS$DEATH_CAUSE? [YES/NO]
  If YES:
    Row count: N
    Non-null DEATH_CAUSE: N (pct%)
    DEATH_CAUSE_TYPE distribution: U=N, C=N, O=N, I=N, NA=N
    Rows with DEATH_CAUSE_TYPE=="U": N
    PATIDs with underlying cause that match deceased set: N / 1344
    Sample DEATH_CAUSE values (first 10): ...
    classify_codes() on populated DEATH_CAUSE -> NHL count: N
    classify_codes() on populated DEATH_CAUSE -> non-NHL count: N
    classify_codes() on populated DEATH_CAUSE -> NA/unclassified: N

--- Source 2: TUMOR_REGISTRY1.CAUSE_OF_DEATH ---
  Column exists? [YES — confirmed by audit]
  Non-null count: N (pct% of 726 TR1 rows)
  PATIDs matching deceased set: N / 1344
  Sample values (first 10): ...
  classify_codes() NHL matches: N

--- Source 3: TUMOR_REGISTRY2/3.DCAUSE ---
  TR2.DCAUSE non-null: 28/404 (6.93% — from audit)
  TR3.DCAUSE non-null: N (check needed)
  TR2/TR3 PATIDs matching deceased set: N / 1344
  classify_codes() NHL matches: N

--- Coverage Summary ---
  Source 1 (DEATH_CAUSE): covers N of 1344 deceased patients
  Source 2 (TR1.CAUSE_OF_DEATH): covers N of 1344 deceased patients
  Source 3 (TR2/3.DCAUSE): covers N of 1344 deceased patients
  Union coverage: N of 1344 deceased patients

--- Recommendation ---
  [PROCEED WITH SOURCE 1] / [FALLBACK TO TR SOURCE] / [PROXY BACKSTOP REQUIRED]
```

### Key R pattern for the diagnostic

```r
# Self-bootstrap DuckDB (pattern from R/102, R/27)
USE_DUCKDB <- TRUE
if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()

# Check DEATH_CAUSE table availability
dc_tbl <- get_pcornet_table("DEATH_CAUSE")
if (is.null(dc_tbl)) {
  message("DEATH_CAUSE table NOT in DuckDB — CSV may not have been loaded")
} else {
  dc_raw <- dc_tbl %>% collect()
  # ... profile columns
}

# Get deceased PATID set (from DEATH table)
deceased_ids <- get_pcornet_table("DEATH") %>%
  collect() %>%
  mutate(DEATH_DATE = parse_pcornet_date(DEATH_DATE)) %>%
  filter(!is.na(DEATH_DATE), year(DEATH_DATE) != 1900L) %>%
  pull(ID) %>% unique()

# Check TUMOR_REGISTRY cause fields via TUMOR_REGISTRY_ALL view
tr_all <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>% collect()
# CAUSE_OF_DEATH is in TR1 only; DCAUSE is in TR2/TR3
```

---

## Architecture Patterns

### Adding a New Table: Exact Edit Sequence

1. Edit `R/00_config.R`: add `"DEATH_CAUSE"` to `PCORNET_TABLES` vector
2. Edit `R/01_load_pcornet.R`: add `DEATH_CAUSE_SPEC` cols() definition + add to `TABLE_SPECS`
3. Run `R/01_load_pcornet.R` (force_reload=TRUE) to create `DEATH_CAUSE.rds` in cache
4. Run `R/03_duckdb_ingest.R` to rebuild DuckDB with DEATH_CAUSE table
5. Edit `R/102_death_cause_nhl_flag.R`: change source of `DEATH_CAUSE` from DEATH table to
   DEATH_CAUSE table (or TUMOR_REGISTRY field, depending on diagnostic results)
6. Edit `R/88_smoke_test_comprehensive.R`: update table count or add Phase 119 section

**File naming convention (HIGH confidence from R/00_config.R ~line 223):**
All tables follow `{TABLE}_Mailhot_V1.csv`. The DEATH_CAUSE file is expected at:
`DEATH_CAUSE_Mailhot_V1.csv` in `CONFIG$data_dir`.

### R/102 Fix Pattern (after diagnostic)

**Case A — DEATH_CAUSE table is populated:**

```r
# Replace the DEATH table cause read with DEATH_CAUSE table read
death_cause_raw <- get_pcornet_table("DEATH_CAUSE") %>%
  collect() %>%
  filter(DEATH_CAUSE_TYPE == "U" | is.na(DEATH_CAUSE_TYPE)) %>%  # underlying cause first
  group_by(ID) %>%
  summarise(DEATH_CAUSE = first(DEATH_CAUSE[DEATH_CAUSE_TYPE == "U"],
                                default = first(DEATH_CAUSE)), .groups = "drop")

death_data <- death_data %>%
  left_join(death_cause_raw, by = "ID")
```

**Case B — Only TUMOR_REGISTRY fields are populated:**

```r
# Use TUMOR_REGISTRY_ALL view; coalesce CAUSE_OF_DEATH (TR1) and DCAUSE (TR2/TR3)
tr_cause <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>%
  collect() %>%
  mutate(
    cause_code = coalesce(
      if ("CAUSE_OF_DEATH" %in% names(.)) CAUSE_OF_DEATH else NA_character_,
      if ("DCAUSE" %in% names(.)) DCAUSE else NA_character_
    )
  ) %>%
  filter(!is.na(cause_code) & trimws(cause_code) != "" &
         !cause_code %in% c("0000", "7777", "7797")) %>%
  group_by(ID) %>%
  summarise(DEATH_CAUSE = first(cause_code), .groups = "drop")

death_data <- death_data %>% left_join(tr_cause, by = "ID")
```

### R/35 Update

R/35 has the same `DEATH_CAUSE`-column-inside-DEATH assumption. After the fix is confirmed,
R/35 should be updated to either read from DEATH_CAUSE table or note the field is in a separate
table. At minimum, add a comment.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| ICD-code NHL detection | Custom regex or code list | `classify_codes()` (utils_cancer.R) |
| Date parsing | lubridate ymd/mdy/dmy guessing | `parse_pcornet_date()` (utils_dates.R) |
| DuckDB connection bootstrap | New connection pattern | `open_pcornet_con()` + `get_pcornet_table()` guard (R/27 pattern) |
| Death patient set | Custom DEATH-table read | Reuse R/35's block verbatim |
| DEATH_CAUSE table ICD normalization | Custom dot-stripping | `classify_codes()` already normalizes |

---

## Common Pitfalls

### Pitfall 1: DEATH_CAUSE CSV Not in the Extract
**What goes wrong:** Assuming the CSV exists at `DEATH_CAUSE_Mailhot_V1.csv` without verifying.
The audit confirms the schema (the script that produced the audit must have seen the file), but
the `date_column_regex_audit.csv` was produced by the R/06 diagnostic which scanned the data
directory. If the file exists, the loader change is straightforward.
**Prevention:** The diagnostic script (R/103) checks `file.exists(PCORNET_PATHS$DEATH_CAUSE)`
before any other step.

### Pitfall 2: DEATH_CAUSE_TYPE Filter Drops All Rows
**What goes wrong:** Filtering `DEATH_CAUSE_TYPE == "U"` (underlying) when the data provider
populated all rows with type "C" (contributing) or left DEATH_CAUSE_TYPE empty.
**Prevention:** Diagnostic reports `DEATH_CAUSE_TYPE` distribution. In R/102 fix, use
`first()` after sorting by type priority (U first, then C, then others) rather than hard filter.

### Pitfall 3: NAACCR Cause Codes Have Special Sentinel Values
**What goes wrong:** `classify_codes("0000")` or `classify_codes("7797")` returns NA — correct
behavior — but the caller misinterprets NA as "no cause found" rather than "patient was alive"
or "certificate unavailable".
**Prevention:** Filter out NAACCR sentinels before calling `classify_codes()`:
```r
filter(!cause_code %in% c("0000", "7777", "7797"))
```

### Pitfall 4: PATID Join Key Mismatch (ID vs PATID)
**What goes wrong:** DEATH_CAUSE table in this extract uses `ID` (not `PATID`) as the patient
column, matching the rest of the extract. The PCORnet CDM specification uses `PATID`, but this
site uses `ID`. R/102 already uses `ID`; keep that pattern.
**Prevention:** DEATH_CAUSE_SPEC uses `ID = col_character()`. The join is `by = "ID"` throughout.

### Pitfall 5: TUMOR_REGISTRY_ALL View UNION Drops Non-Common Columns
**What goes wrong:** `TUMOR_REGISTRY_ALL` uses `UNION ALL BY NAME` (DuckDB syntax). If
`CAUSE_OF_DEATH` exists in TR1 but not TR2/TR3, and `DCAUSE` exists in TR2/TR3 but not TR1,
the unified view contains BOTH columns but with NULLs for the table that doesn't have them.
This is correct behavior, but the code must handle both columns conditionally.
**Prevention:** Check which columns exist before selecting:
```r
tr_raw <- get_pcornet_table("TUMOR_REGISTRY_ALL") %>% collect()
has_cod   <- "CAUSE_OF_DEATH" %in% names(tr_raw)
has_dcause <- "DCAUSE" %in% names(tr_raw)
```

### Pitfall 6: DuckDB Table Count Assertion in R/88
**What goes wrong:** Adding DEATH_CAUSE to PCORNET_TABLES bumps the count from 15 to 16. The
R/88 smoke test at ~line 3471 asserts `length(tables_found) == 15` for `IS_LOCAL` mode. If the
local fixture DuckDB is not updated, this check fails.
**Prevention:** Either update the local DuckDB fixture, change the assertion to 16, or note
the assertion needs updating in the Phase 119 plan.

---

## Code Examples

### Pattern: Standalone script + DuckDB self-bootstrap (from R/102, established)
```r
# Source: R/102_death_cause_nhl_flag.R lines 79-82
USE_DUCKDB <- TRUE
if (!exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}
```

### Pattern: DEATH table load + date sentinel (from R/102 Section 4)
```r
death_raw <- get_pcornet_table("DEATH") %>% collect()
death_data <- death_raw %>%
  mutate(DEATH_DATE = parse_pcornet_date(DEATH_DATE)) %>%
  mutate(DEATH_DATE = if_else(year(DEATH_DATE) == 1900L, as.Date(NA), DEATH_DATE)) %>%
  filter(!is.na(DEATH_DATE))
```

### Pattern: classify_codes() NHL detection (from R/102 Section 5)
```r
# Source: R/utils/utils_cancer.R
cause_category = if_else(
  cause_missing,
  NA_character_,
  classify_codes(DEATH_CAUSE)
),
cause_of_death_is_nhl = case_when(
  cause_missing                  ~ NA,
  cause_category == NHL_CATEGORY ~ TRUE,
  TRUE                           ~ FALSE
)
```

### Pattern: NAACCR sentinel filtering (new for Phase 119)
```r
# Filter NAACCR cause sentinels before passing to classify_codes()
# 0000 = patient alive, 7777 = cert unavailable, 7797 = cert available but uncoded
NAACCR_DEATH_SENTINELS <- c("0000", "7777", "7797")
tr_cause <- tr_raw %>%
  filter(
    !is.na(cause_code),
    trimws(cause_code) != "",
    !cause_code %in% NAACCR_DEATH_SENTINELS
  )
```

---

## Environment Availability

Step 2.6 is SKIPPED for the local research environment. The implementation runs on HiPerGator
where the data lives. The diagnostic script (R/103) must run there. No new external tools are
needed — the fix uses the existing pipeline stack.

The one environment question is whether `DEATH_CAUSE_Mailhot_V1.csv` exists in `CONFIG$data_dir`
on HiPerGator. The audit CSV confirms the DEATH_CAUSE schema was observed (it appears in
`date_column_regex_audit.csv` which is generated by scanning actual files), which is HIGH
confidence evidence the file was present when the audit ran.

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|-----------------|--------|
| R/102 reads DEATH.DEATH_CAUSE (Phase 118) | Read DEATH_CAUSE table (separate PCORnet CDM table) | Correct — DEATH has no cause column per CDM spec |
| Assume DEATH has cause-of-death column | DEATH_CAUSE is a separate table linked via PATID (ID) | DEATH_CAUSE table already in the extract |
| R/35 profiles DEATH.DEATH_CAUSE | R/35 should also be updated to reference correct source | Avoids repeated future confusion |

---

## Validation Architecture

The existing R/88 Phase 118 section (Section 15o, ~line 2134) checks R/102 structurally.
Phase 119 should add a **Section 15p** to R/88 that validates:

1. R/103 diagnostic script exists (if written)
2. R/102 no longer reads cause from DEATH table (negative check: `!grepl('get_pcornet_table.*DEATH.*DEATH_CAUSE', r102_text)`)
3. R/102 reads from DEATH_CAUSE table or TR source (positive check)
4. Output `death_cause_nhl_flag.csv` has non-zero TRUE or FALSE count (runtime check, HiPerGator only)
5. DEATH_CAUSE appears in PCORNET_TABLES (if table-loading path is taken)

If DEATH_CAUSE table is added to the pipeline, the DuckDB table count assertion at ~line 3471
must be updated from `== 15` to `== 16`.

---

## Open Questions

1. **Is DEATH_CAUSE populated in this extract?**
   - What we know: The schema exists (confirmed by audit). The file `DEATH_CAUSE_Mailhot_V1.csv`
     was almost certainly present when the audit ran.
   - What's unclear: Non-null count of `DEATH_CAUSE`. May be 0% (table delivered empty) or
     populated. Most PCORnet sites provide this table but population varies.
   - Recommendation: The diagnostic script answers this in under 1 minute of HiPerGator runtime.

2. **Is TR1.CAUSE_OF_DEATH populated?**
   - What we know: Column exists (audit confirmed). TR1 has 726 rows. All TR1 date fields are
     100% null — but coded fields like `CAUSE_OF_DEATH` are not necessarily null.
   - What's unclear: Non-null count. The missingness audit only showed columns with partial
     missingness; TR1.CAUSE_OF_DEATH either appears there (and was missed by grep) or is 0%
     or 100% missing.
   - Recommendation: Diagnostic script checks `sum(!is.na(tr1$CAUSE_OF_DEATH))`.

3. **Will the DEATH_CAUSE-to-deceased-PATID join have good coverage?**
   - What we know: 1,344 deceased patients. DEATH_CAUSE could have 0 to N rows.
   - What's unclear: How many of the 1,344 have a corresponding DEATH_CAUSE record.
   - Recommendation: Diagnostic script reports `n_distinct(DEATH_CAUSE_patids intersect deceased)`.

---

## Sources

### Primary (HIGH confidence)
- `output/diagnostics/date_column_regex_audit.csv` — live extract audit confirming DEATH_CAUSE
  table schema and TUMOR_REGISTRY cause/vital columns
- `output/diagnostics/missing_values_audit.csv` — live extract audit confirming
  TUMOR_REGISTRY2.DCAUSE is 6.93% present (28/404)
- [data-models-service.research.chop.edu/models/pcornet/6.0.0](https://data-models-service.research.chop.edu/models/pcornet/6.0.0) — PCORnet CDM v6.0
  table schema (DEATH: 5 columns; DEATH_CAUSE: 6 columns including DEATH_CAUSE_CONFIDENCE)
- [github.com/LHSNet/PCORNet-CDM SAS DDL](https://github.com/LHSNet/PCORNet-CDM/blob/master/PCORNet-CDM-v3/sas/create-sas-tables/Create_CDM_SAS_tables.sas) — confirms DEATH_CAUSE as separate table,
  lists all column names
- [apps.naaccr.org item #1910](https://apps.naaccr.org/data-dictionary/data-dictionary/version=24/data-item-view/item-number=1910/) — NAACCR Cause of Death field (ICD-coded,
  4 chars, XML name `causeOfDeath`; sentinel values 0000/7777/7797)
- [apps.naaccr.org item #1760](https://apps.naaccr.org/data-dictionary/data-dictionary/version=24/data-item-view/item-number=1760/) — NAACCR Vital Status field (0=Dead, 1=Alive)
- R/00_config.R, R/01_load_pcornet.R, R/03_duckdb_ingest.R, R/88_smoke_test_comprehensive.R
  (read directly — loader patterns, table count assertions)

### Secondary (MEDIUM confidence)
- [PCORnet CDM v7.0 specification](https://pcornet.org/wp-content/uploads/2025/01/PCORnet-Common-Data-Model-v70-2025_01_23.pdf) — referenced but PDF binary; v6 schema service is the actual source used
- DEATH_CAUSE_TYPE values (U/C/O/I) from data-models-service description of the field:
  "There should be only one underlying cause of death [U]" — partially documented

### Tertiary (LOW confidence)
- DEATH_CAUSE_CODE values (09/10/OT/UN) — inferred from PCORnet CDM v6.0 service description
  of the field; not formally verified against v7.0 value set appendix

---

## Metadata

**Confidence breakdown:**
- PCORnet CDM data model (DEATH vs DEATH_CAUSE separation): HIGH — confirmed by PCORnet v6
  schema service and live extract audit
- Candidate column inventory (DEATH_CAUSE, CAUSE_OF_DEATH, DCAUSE, VITAL): HIGH — from live
  `date_column_regex_audit.csv`
- NAACCR item definitions (#1910, #1760): HIGH — from official NAACCR data dictionary v24
- Population/non-null counts: MEDIUM for DCAUSE (6.93% from audit); LOW/UNKNOWN for DEATH_CAUSE
  table and TR1.CAUSE_OF_DEATH (diagnostic needed)
- Loader wiring (5-touch-point recipe): HIGH — read directly from pipeline source files
- DEATH_CAUSE_TYPE value set (U/C/O/I): MEDIUM — partially documented in schema service

**Research date:** 2026-07-09
**Valid until:** 2026-08-09 (stable — PCORnet CDM v6/v7 schema is frozen; pipeline loader
patterns change only when new phases add tables)
