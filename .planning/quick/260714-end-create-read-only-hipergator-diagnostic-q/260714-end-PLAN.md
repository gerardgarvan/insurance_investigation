---
phase: quick-260714-end
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - R/107_med_admin_dispensing_gap_diagnostic.R
  - R/SCRIPT_INDEX.md
autonomous: true
requirements: [QUICK-260714-END]

must_haves:
  truths:
    - "Running R/107 on HiPerGator prints how many patients and chemo dates MED_ADMIN (MEDADMIN_TYPE=='RX') would add BEYOND the PRESCRIBING RXNORM_CUI baseline, and how many patients would get an earlier first-chemo date."
    - "The script never modifies pipeline logic or overwrites cohort/episode outputs — it only reads DuckDB and writes ONE additive diagnostic CSV to output/."
    - "If DISPENSING/MED_ADMIN/PRESCRIBING or a required column is absent, the script logs a SKIP and continues (no stop()/crash)."
    - "DISPENSING is reported as volume + patient/date footprint only, explicitly flagged as NOT chemo-matchable without an NDC->RxNorm crosswalk (no fabricated chemo match)."
  artifacts:
    - path: "R/107_med_admin_dispensing_gap_diagnostic.R"
      provides: "Read-only MED_ADMIN/DISPENSING chemo-gap sizing diagnostic"
      min_lines: 180
      contains: "MEDADMIN_TYPE"
    - path: "R/SCRIPT_INDEX.md"
      provides: "R/107 row in Post-Renumber Investigations (100+) table"
      contains: "R/107"
  key_links:
    - from: "R/107_med_admin_dispensing_gap_diagnostic.R"
      to: "TREATMENT_CODES$chemo_rxnorm"
      via: "MEDADMIN_CODE %in% TREATMENT_CODES$chemo_rxnorm and RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm"
      pattern: "TREATMENT_CODES\\$chemo_rxnorm"
    - from: "R/107_med_admin_dispensing_gap_diagnostic.R"
      to: "get_hl_patient_ids()"
      via: "cohort restriction (with all-patient context)"
      pattern: "get_hl_patient_ids"
---

<objective>
Create ONE new read-only HiPerGator diagnostic R script (R/107) that SIZES the confirmed
latent bug where DISPENSING and MED_ADMIN silently contribute ZERO chemo treatment
detection because every consumer guards on `"RXNORM_CUI" %in% colnames(...)` — a column
this OneFlorida+ extract lacks in those two tables.

Purpose: Quantify, before deciding whether to fix, how many patients / chemo dates /
earlier-first-chemo-date shifts MED_ADMIN (via MEDADMIN_TYPE=='RX' + MEDADMIN_CODE, which
carries RxNorm CUIs) would add beyond the working PRESCRIBING RXNORM_CUI baseline; and
report DISPENSING's volume/footprint while flagging that its NDC-only coding needs a
crosswalk before any chemo match is possible.

Output: R/107_med_admin_dispensing_gap_diagnostic.R (standalone, read-only), a small
additive diagnostic CSV output/med_admin_dispensing_gap_diagnostic.csv, a console headline,
and a SCRIPT_INDEX.md row. No pipeline logic changed; no cohort/episode file overwritten.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@./CLAUDE.md

<read_first>
- R/103_death_cause_diagnostic.R  — MIRROR THIS EXACTLY for structure: header block; SECTION 1 suppressPackageStartupMessages + source("R/00_config.R"), source("R/utils/utils_duckdb.R"), source("R/utils/utils_dates.R"); SECTION 3 self-bootstrap DuckDB (`USE_DUCKDB <- TRUE; if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()`); graceful `get_pcornet_table()` NULL guards; `close_pcornet_con()` at the end; write.csv(..., row.names = FALSE, na = "").
- R/26_treatment_episodes.R lines 147-202 — the exact chemo-detection guards being sized: PRESCRIBING uses `RXNORM_CUI %in% TREATMENT_CODES$chemo_rxnorm` + `coalesce(RX_ORDER_DATE, RX_START_DATE)`; DISPENSING/MED_ADMIN are gated on `"RXNORM_CUI" %in% colnames(...)` (the guard that drops them in this extract).
- R/00_config.R §3 (lines 226-260) — PCORNET_TABLES includes DISPENSING, MED_ADMIN, PRESCRIBING; patient ID column is `ID` (NOT PATID); `TREATMENT_CODES$chemo_rxnorm` lives at ~line 2581.
- R/01_load_pcornet.R lines 304-348 — DISPENSING_SPEC declares RXNORM_CUI/NDC/DISPENSE_DATE (real CSV lacks RXNORM_CUI + RAW_DISPENSE_MED_NAME); MED_ADMIN_SPEC declares MEDADMIN_CODE, MEDADMIN_TYPE, MEDADMIN_START_DATE, RAW_MEDADMIN_MED_NAME, RXNORM_CUI (real CSV lacks RXNORM_CUI).
- R/utils/utils_treatment.R lines 62-82 — `get_hl_patient_ids()` returns HL cohort IDs (character vector, or character(0) if DIAGNOSIS missing). Auto-sourced via R/00_config.
</read_first>

<interfaces>
Available after `source("R/00_config.R")` + `source("R/utils/utils_duckdb.R")`:

  get_pcornet_table(name)   # duckdb tbl (lazy) or NULL if table absent. Use %>% collect().
  open_pcornet_con()        # idempotent; sets .GlobalEnv$pcornet_con
  close_pcornet_con()
  get_hl_patient_ids()      # character() of HL cohort IDs (auto-sourced from utils_treatment)
  parse_pcornet_date(x)     # -> Date (from utils_dates)
  TREATMENT_CODES$chemo_rxnorm   # character() of chemo RxNorm CUIs, e.g. "3639","11213","67228"
  CONFIG$output_dir              # output/ dir for the diagnostic CSV

Column facts for THIS extract (verified via data profiles + code reading):
  PRESCRIBING: HAS RXNORM_CUI (works). Dates: RX_ORDER_DATE, RX_START_DATE.
  DISPENSING:  NDC only, NO RXNORM_CUI, NO RAW_DISPENSE_MED_NAME. Date: DISPENSE_DATE.
  MED_ADMIN:   NO RXNORM_CUI. Has MEDADMIN_CODE + MEDADMIN_TYPE (RX=71%, ND=22%, rest NI/UN/OT),
               RAW_MEDADMIN_MED_NAME, MEDADMIN_START_DATE (fully populated ~2.39M rows).
               When MEDADMIN_TYPE=='RX', MEDADMIN_CODE holds an RxNorm CUI directly comparable
               to TREATMENT_CODES$chemo_rxnorm.
  Patient ID column is `ID` across ALL tables.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Write R/107 read-only MED_ADMIN/DISPENSING chemo-gap diagnostic</name>
  <files>R/107_med_admin_dispensing_gap_diagnostic.R</files>
  <read_first>R/103_death_cause_diagnostic.R (full — mirror structure verbatim), R/26_treatment_episodes.R lines 147-202, R/00_config.R lines 226-260 + ~2581, R/utils/utils_treatment.R lines 62-82</read_first>
  <action>
Create R/107_med_admin_dispensing_gap_diagnostic.R mirroring R/103's structure exactly.

HEADER (5-field): Purpose (READ-ONLY sizing of the RXNORM_CUI-missing gap in DISPENSING +
MED_ADMIN vs PRESCRIBING baseline; explains WHY: R/26 guards drop these two tables in this
extract), Inputs (DuckDB PRESCRIBING/MED_ADMIN/DISPENSING tables), Outputs
(output/med_admin_dispensing_gap_diagnostic.csv + console), Dependencies (R/00_config.R,
utils_duckdb, utils_dates, utils_treatment, tidyverse), Requirements (quick-260714-end).
Include the R/103-style Note: READ-ONLY, structural-only verification on Windows, full run
HiPerGator only; must NOT touch R/26/R/00_config or overwrite cohort/episode outputs.

SECTION 1 — SETUP: `suppressPackageStartupMessages({ library(dplyr); library(glue); library(stringr); library(lubridate) })`; `source("R/00_config.R")`; `source("R/utils/utils_duckdb.R")`; `source("R/utils/utils_dates.R")`. Defensively `if (!exists("get_hl_patient_ids")) source("R/utils/utils_treatment.R")`. Print a `=== ... Gap Diagnostic ===` banner.

SECTION 2 — CONSTANTS + HIPAA: `CHEMO_RXNORM <- TREATMENT_CODES$chemo_rxnorm`.
`OUTPUT_CSV <- file.path(CONFIG$output_dir, "med_admin_dispensing_gap_diagnostic.csv")`.
Define a HIPAA helper `suppress_small <- function(n) if (!is.na(n) && n >= 1 && n <= 10) NA_integer_ else n` (project convention: suppress patient counts 1-10 in any persisted/printed per-group breakdown). Apply it to the persisted CSV's patient-count fields and to any per-group printed patient counts.

SECTION 3 — SELF-BOOTSTRAP DUCKDB: `USE_DUCKDB <- TRUE; if (!exists("pcornet_con", envir = .GlobalEnv)) open_pcornet_con()`.

SECTION 4 — COHORT SCOPE: `hl_ids <- get_hl_patient_ids()` (report `length(hl_ids)`). Report all-patient counts as context throughout too. All "cohort" metrics filter `ID %in% hl_ids`; all "all-patient" metrics do not. If `length(hl_ids) == 0`, log a warning and fall back to all-patient scope for cohort fields (do not crash).

SECTION 5 — PRESCRIBING BASELINE (the "already captured" set): guard `pr <- get_pcornet_table("PRESCRIBING")`; if NULL or `!("RXNORM_CUI" %in% colnames(pr))`, log SKIP and set baseline sets empty. Else filter `RXNORM_CUI %in% CHEMO_RXNORM`, `mutate(treatment_date = coalesce(RX_ORDER_DATE, RX_START_DATE))`, drop NA dates, collect. Parse dates with parse_pcornet_date. Build: `rx_patients` (distinct ID), `rx_pairs` (distinct ID+date), and `rx_first_date` (per-ID min treatment_date). Report cohort-scoped and all-patient patient/pair counts.

SECTION 6 — MED_ADMIN INCREMENTAL: guard `ma <- get_pcornet_table("MED_ADMIN")`; NULL -> SKIP. Require columns MEDADMIN_TYPE, MEDADMIN_CODE, MEDADMIN_START_DATE (log SKIP for any missing, don't crash). Filter `MEDADMIN_TYPE == "RX" & MEDADMIN_CODE %in% CHEMO_RXNORM & !is.na(MEDADMIN_START_DATE)`, collect, parse MEDADMIN_START_DATE. Report: n matching administrations (rows), distinct chemo RxNorm codes (`n_distinct(MEDADMIN_CODE)`), distinct patients (ID), distinct (ID+date) pairs — both cohort and all-patient.
Then INCREMENT beyond PRESCRIBING (cohort-scoped): patients in MED_ADMIN-chemo NOT in `rx_patients` (`setdiff`); (ID,date) pairs in MED_ADMIN NOT in `rx_pairs` (anti-join on ID+date); earliest-date shifts = count of patients whose MED_ADMIN chemo min-date < their `rx_first_date` (join on ID, compare; patients with no PRESCRIBING baseline count as new-patient adds, tabulate separately).
Separately report the `MEDADMIN_TYPE == "ND"` chemo-relevant volume as a distinct "would need NDC crosswalk" line: count rows/patients where MEDADMIN_TYPE=="ND" (do NOT match against chemo_rxnorm — ND codes are NDC, not RxNorm; report volume only).

SECTION 7 — DISPENSING FOOTPRINT (NO chemo match — NDC only, no in-repo crosswalk): guard `dp <- get_pcornet_table("DISPENSING")`; NULL -> SKIP. Collect cohort-scoped rows. Report total DISPENSING rows, distinct patients (ID), distinct DISPENSE_DATEs — cohort and all-patient. Emit an explicit line: "DISPENSING chemo-specific matching NOT possible without an NDC->RxNorm crosswalk (this extract has NDC only, no RXNORM_CUI, no crosswalk in-repo)." Do NOT fabricate any chemo match for DISPENSING.

SECTION 8 — CONSOLE HEADLINE + CSV: Print the required headline (HIPAA-suppressed values):
`message(glue("HEADLINE: MED_ADMIN would add {n_new_patients} patients / {n_new_dates} chemo dates beyond PRESCRIBING; {n_earlier} patients would get an earlier first-chemo date."))`.
Build a tibble with one row per source ("PRESCRIBING_baseline", "MED_ADMIN_RX_increment", "MED_ADMIN_ND_volume", "DISPENSING_footprint") plus columns: scope ("cohort"/"all"), n_rows, n_patients (HIPAA-suppressed), n_id_date_pairs, n_distinct_codes, note. Write with `write.csv(..., row.names = FALSE, na = "")`. `close_pcornet_con()`. Final `message("Done. (quick-260714-end -- MED_ADMIN/DISPENSING chemo-gap sizing diagnostic)")`.

REGISTRATION CHOICE (state explicitly in a header comment): This is a ONE-OFF sizing
diagnostic, NOT a recurring investigation — DO NOT wire into R/39 and DO NOT add an R/88
section. Registration is limited to the SCRIPT_INDEX.md row (Task 2).
  </action>
  <verify>
    <automated>
STRUCTURAL ONLY (Windows executor has no Rscript; local fixtures lack the real column layout). Run these grep/scan checks:
1. `grep -c 'TREATMENT_CODES\$chemo_rxnorm' R/107_med_admin_dispensing_gap_diagnostic.R` >= 2 (MED_ADMIN + PRESCRIBING matches).
2. `grep -q 'MEDADMIN_TYPE == "RX"' R/107_...R` AND `grep -q 'MEDADMIN_CODE %in%' R/107_...R` (RX-coded MED_ADMIN chemo match).
3. `grep -q 'MEDADMIN_TYPE == "ND"' R/107_...R` (separate ND crosswalk-needed volume line).
4. `grep -q 'coalesce(RX_ORDER_DATE, RX_START_DATE)' R/107_...R` (PRESCRIBING baseline dates).
5. `grep -q 'NDC' R/107_...R` AND `grep -qi 'crosswalk' R/107_...R` (DISPENSING flagged, not matched).
6. `grep -q 'get_hl_patient_ids' R/107_...R` (cohort scope) AND presence of all-patient context.
7. `grep -q 'suppress' R/107_...R` (HIPAA 1-10 suppression helper).
8. `grep -q 'if (!exists("pcornet_con"' R/107_...R` AND `grep -q 'close_pcornet_con' R/107_...R` (self-bootstrap + teardown).
9. `grep -q 'HEADLINE:' R/107_...R` (required console headline).
10. `grep -q 'write.csv' R/107_...R` AND `grep -q 'na = ""' R/107_...R` (additive CSV).
11. NO `stop(` on a missing-table/column path (guards use message + skip, not stop).
12. Paren/brace balance: run a state-machine scan (as in Phases 119-120) — total `(` == `)` and `{` == `}` across the file (string/comment-aware if the harness supports it).
    </automated>
  </verify>
  <done>
R/107 exists (>=180 lines), sources R/00_config + utils_duckdb/dates, self-bootstraps and
tears down DuckDB, computes PRESCRIBING baseline + MED_ADMIN RX increment (new patients,
new ID+date pairs, earlier-first-date shifts) + MED_ADMIN ND volume + DISPENSING footprint
(flagged, not matched), applies HIPAA 1-10 suppression, prints the HEADLINE, writes an
additive CSV, and touches NO pipeline logic. All 12 structural checks pass. Balanced parens/braces.
  </done>
</task>

<task type="auto">
  <name>Task 2: Register R/107 in SCRIPT_INDEX.md (diagnostic row only)</name>
  <files>R/SCRIPT_INDEX.md</files>
  <read_first>R/SCRIPT_INDEX.md lines 140-152 (Post-Renumber Investigations table) and lines 205 (count line)</read_first>
  <action>
Add ONE row to the "Post-Renumber Investigations (100+)" table (after the R/106 row, ~line 152):
`| `R/107_med_admin_dispensing_gap_diagnostic.R` | Read-only diagnostic sizing the chemo treatment-detection loss caused by DISPENSING and MED_ADMIN lacking RXNORM_CUI in this extract. Establishes the PRESCRIBING RXNORM_CUI baseline, then quantifies MED_ADMIN's incremental contribution via MEDADMIN_TYPE=='RX' + MEDADMIN_CODE (RxNorm CUIs) — new patients, new (ID,date) pairs, and earlier-first-chemo-date shifts beyond the baseline — plus the MEDADMIN_TYPE=='ND' volume that would need an NDC->RxNorm crosswalk. Reports DISPENSING volume/patient/date footprint only (NDC-only; no crosswalk in-repo, so no chemo match). HIPAA-suppresses patient counts 1-10. Writes output/med_admin_dispensing_gap_diagnostic.csv. NOT wired into R/39 (one-off sizing diagnostic). | quick-260714-end |`
Update the Script Count line (~line 205): change "Post-renumber investigations (100+): 7" to 8, extend the parenthetical list with "R/107 MED_ADMIN/DISPENSING chemo-gap sizing", and update "Total: 93" -> "94".
Do NOT modify R/39 or R/88.
  </action>
  <verify>
    <automated>
1. `grep -q 'R/107_med_admin_dispensing_gap_diagnostic.R' R/SCRIPT_INDEX.md` (row added).
2. `grep -q 'Post-renumber investigations (100+):\*\* 8' R/SCRIPT_INDEX.md` OR grep confirms the count moved 7->8.
3. `grep -q 'Total:\*\* 94' R/SCRIPT_INDEX.md` (total 93->94).
4. `grep -c 'R/39' R/SCRIPT_INDEX.md` unchanged w.r.t. R/107 (no R/39 wiring claim).
    </automated>
  </verify>
  <done>SCRIPT_INDEX.md has the R/107 diagnostic row; 100+ count 7->8; Total 93->94; no R/39/R/88 changes.</done>
</task>

</tasks>

<verification>
Executor verification is STRUCTURAL ONLY. This Windows executor has NO Rscript, and the
local DuckDB fixtures do NOT reflect the real column layout of this OneFlorida+ extract
(DISPENSING/MED_ADMIN really lack RXNORM_CUI here). The executor therefore proves correctness
via grep pattern checks + a paren/brace balance state-machine scan (the same approach used in
Phases 119-120), NOT by running the script.

The USER runs R/107 on HiPerGator and confirms at runtime:
1. The script sources cleanly, bootstraps DuckDB, and completes without stop()/crash.
2. PRESCRIBING baseline patient/date counts are non-zero (sanity: PRESCRIBING has RXNORM_CUI).
3. MED_ADMIN RX-coded chemo match returns the increment (new patients, new ID+date pairs,
   earlier-first-date shifts) — expected to be substantial (~1.7M RX-coded administrations exist).
4. The MEDADMIN_TYPE=='ND' volume line prints (crosswalk-needed, unmatched).
5. DISPENSING footprint prints with the explicit "needs NDC->RxNorm crosswalk" flag and NO
   fabricated chemo match.
6. The HEADLINE line prints filled-in numbers.
7. output/med_admin_dispensing_gap_diagnostic.csv is written and no cohort/episode file changed.
8. Per-group patient counts of 1-10 appear as blank (HIPAA suppression) in the CSV/console.
</verification>

<success_criteria>
- R/107_med_admin_dispensing_gap_diagnostic.R created: read-only, self-bootstrapping,
  graceful column/table guards (no stop), HIPAA 1-10 suppression, additive CSV + headline.
- PRESCRIBING baseline, MED_ADMIN RX increment (new patients / new ID+date pairs / earlier
  first-date shifts), MED_ADMIN ND volume, and DISPENSING footprint all computed per spec.
- DISPENSING explicitly flagged as needing an NDC->RxNorm crosswalk — no fabricated match.
- Cohort-scoped (get_hl_patient_ids) with all-patient context reported.
- NOT wired into R/39 or R/88 (choice stated in header); SCRIPT_INDEX.md row added, counts updated.
- All structural checks + paren/brace balance pass.
</success_criteria>

<output>
After completion, create `.planning/quick/260714-end-create-read-only-hipergator-diagnostic-q/260714-end-SUMMARY.md`
</output>
