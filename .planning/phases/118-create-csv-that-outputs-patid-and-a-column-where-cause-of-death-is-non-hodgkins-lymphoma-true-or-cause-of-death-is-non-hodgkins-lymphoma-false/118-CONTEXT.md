# Phase 118: Cause-of-Death NHL Flag CSV - Context

**Gathered:** 2026-07-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce a **CSV** with one row per **deceased patient** carrying:
1. `PATID` — the patient identifier, and
2. a column indicating whether that patient's **cause of death classifies as Non-Hodgkin
   lymphoma (NHL)**.

The cause of death comes from the DuckDB `DEATH` table's `DEATH_CAUSE` (an ICD code),
classified with the project's existing NHL definition. This is a small, standalone
data-export script — no visualization, no changes to existing pipeline outputs.

</domain>

<decisions>
## Implementation Decisions

### Row Scope
- **D-01:** One row per **deceased patient** — patients with a valid `DEATH_DATE` in the
  `DEATH` table. Follow R/35's death-data derivation: parse `DEATH_DATE` via
  `parse_pcornet_date()`, treat year 1900 as a sentinel → NA, drop NA dates, and aggregate
  to one death record per patient (`group_by(ID)`, earliest `DEATH_DATE`).
- **D-02:** Alive patients / patients with no death record are NOT included (excluded, not FALSE).

### NHL Flag Value (three states — NOT strictly boolean)
- **D-03:** The flag column has three possible values:
  - `TRUE`  — cause of death classifies as Non-Hodgkin Lymphoma
  - `FALSE` — cause of death is a different, coded cause
  - `NA` / blank — cause of death is missing/uncoded (`DEATH_CAUSE` empty or NA)
- **D-04:** This three-state choice is deliberate: `DEATH_CAUSE` is frequently uncoded
  (see R/35 completeness profiling), so collapsing "missing" into FALSE would misrepresent
  the data. The blank/NA state must be distinguishable from a real FALSE.

### NHL Definition
- **D-05:** "Non-Hodgkin lymphoma" = the project's existing classification: a code whose
  category (via `classify_codes()` / `CANCER_SITE_MAP`) is exactly **"Non-Hodgkin Lymphoma"**.
  That is ICD-10 `C82, C83, C84, C85, C86, C88` and ICD-9 `200, 202`.
- **D-06:** Do NOT broaden to C96/C91 or other lymphoid/hematopoietic codes — stay consistent
  with the rest of the pipeline's NHL category. Hodgkin (C81) is NOT NHL.
- **D-07:** Match `DEATH_CAUSE` using the same normalization the classifier expects (ICD-10
  prefix logic; ICD-9 fallback). Reuse `classify_codes()` rather than hand-rolling a code list.

### Claude's Discretion
- Output file name (suggested `death_cause_nhl_flag.csv`) and NHL column name (suggested
  `cause_of_death_is_nhl`).
- Script placement: a new standalone "100+" investigation script (e.g. `R/102_*`) reading
  the `DEATH` table directly, mirroring R/35's DEATH-load pattern. Self-bootstrap the DuckDB
  connection (`USE_DUCKDB <- TRUE; open_pcornet_con()` guarded by `exists()`) like R/28-R/36
  and the just-fixed R/27.
- Whether `PATID` column is literally named `PATID` or `ID`/`patient_id` — match whatever the
  consumer expects; `PATID` is the requested header, so default to emitting the column as `PATID`.
- Whether to register in `R/39_run_all_investigations.R` and add an `R/88` smoke-test section
  (follow the Phase 116/117 precedent — likely yes).
- CSV convention: `write.csv(..., row.names = FALSE, na = "")` (blank cells for the NA state),
  consistent with the project's other CSV exports.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Death Data
- `R/35_death_cause_quality.R` — canonical DEATH-table load + `DEATH_CAUSE`/`DEATH_CAUSE_CODE`
  field-availability guard (D-78-01), date-sentinel handling, patient-level aggregation. The
  new script should mirror this load pattern.
- `R/53_death_date_validation.R` — death-date validation / impossible-death handling (reference).
- `R/00_config.R` — `DEATH_CAUSE_MAP` (~line 983, ICD → human-readable cause categories;
  reference only) and `CANCER_SITE_MAP` / `ICD9_CANCER_SITE_MAP` (NHL = C82-C86, C88 / 200, 202).

### NHL Classification
- `R/utils/utils_cancer.R` — `classify_codes()` (maps ICD codes → cancer category names,
  including "Non-Hodgkin Lymphoma"). Primary reuse for D-05/D-07.
- `R/utils/utils_icd.R` — `normalize_icd()` (code normalization if needed before classify).

### Conventions & Precedent
- `R/27_drug_name_resolution.R` — self-bootstrap pattern (`USE_DUCKDB <- TRUE` +
  guarded `open_pcornet_con()`) for a standalone DuckDB-using script.
- `R/100_ruca_rurality_summary.R`, `R/101_gantt_lifespan_collapse.R` — recent standalone
  "100+" investigation scripts (structure, header, output-path conventions).
- `R/39_run_all_investigations.R` — pipeline runner registration precedent.
- `R/88_smoke_test_comprehensive.R` — structural smoke-test section precedent (15m/15n).
- `R/SCRIPT_INDEX.md` — Post-Renumber Investigations (100+) table row.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- R/35 DEATH-table load block (lines ~62-117): DuckDB open, `get_pcornet_table("DEATH")`,
  `DEATH_CAUSE`/`DEATH_CAUSE_CODE` availability guard, 1900-sentinel handling, per-patient
  aggregation. Copy this for the row set.
- `classify_codes()` (utils_cancer): the NHL determination — `classify_codes(DEATH_CAUSE) == "Non-Hodgkin Lymphoma"`.
- Guarded self-bootstrap (`if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()`) from R/27.

### Established Patterns
- Standalone "100+" investigation script (R/100, R/101): sourced `R/00_config.R`, RStudio
  section headers, `CONFIG$output_dir` paths, `write.csv(row.names = FALSE, na = "")`.
- Field-availability guard for `DEATH_CAUSE` vs `DEATH_CAUSE_CODE` (R/35 D-78-01) — reuse so
  the script degrades gracefully if the cause field is absent (then all rows are NA state).

### Integration Points
- New script reads DuckDB `DEATH` table → derives deceased set → classifies `DEATH_CAUSE` →
  writes `output/death_cause_nhl_flag.csv` (PATID + 3-state NHL column).
- Optional: register in `R/39` and add an `R/88` structural section (Phase 116/117 precedent).
- No changes to existing outputs or the Gantt pipeline.

</code_context>

<specifics>
## Specific Ideas

- The three-state flag (TRUE / FALSE / NA) is the key nuance: given how sparse `DEATH_CAUSE`
  coding is, a strict boolean would falsely imply most deceased patients did NOT die of NHL,
  when in fact their cause is simply unrecorded.
- NHL here is the cause-of-death code classification, distinct from the patient's cancer
  diagnosis history — a patient can be an HL-cohort member yet have an NHL (or unrelated)
  cause of death.

</specifics>

<deferred>
## Deferred Ideas

- Broadening NHL to C96/C91/other lymphoid-hematopoietic codes — considered, declined (D-06).
- Including alive patients or the full HL cohort with FALSE — considered, declined (D-02).
- Adding the cause-of-death category label or raw `DEATH_CAUSE` code as extra columns — out of
  scope for this phase (the request is PATID + the NHL flag); could be a follow-up if useful.

</deferred>

---

*Phase: 118-create-csv-that-outputs-patid-and-a-column-where-cause-of-death-is-non-hodgkins-lymphoma...*
*Context gathered: 2026-07-09*
