# Phase 123: Quantify MED_ADMIN/DISPENSING Fix Impact + Unmatched-NDC Audit - Research

**Researched:** 2026-07-14
**Domain:** R diagnostic scripting, NDC/RxNorm crosswalk, openxlsx2 multi-sheet delivery, regimen
detection
**Confidence:** HIGH (all findings from direct codebase inspection; no external research needed for
this phase)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Construct the "before" state by extending the R/107 diagnostic — compute both sides in
  one cohort-scoped script. `before` = PRESCRIBING-only; `after` = PRESCRIBING + MED_ADMIN
  (`MEDADMIN_TYPE=='RX'`) + NDC-resolved (DISPENSING `NDC` + MED_ADMIN `MEDADMIN_TYPE=='ND'` via
  crosswalk).
- **D-02:** No full pipeline re-run and no toggle-flag plumbing — the diff is source-level and
  deterministic. R/107 already encodes the PRESCRIBING-baseline half; extend it (or a sibling
  script) to add the NDC sources and the after-side.
- **D-03:** Patient & date counts — # patients with any chemo (before vs after) and # distinct chemo
  `(ID, date)` pairs, broken down by contributing source. This is the headline number.
- **D-04:** First-chemo timing shift — # patients gaining an EARLIER first-chemo date under the
  after-set, plus distribution of the shift in days.
- **D-05:** Per-drug/ingredient delta — which chemo ingredients gain the most patients/dates from the
  new sources. Feeds the NDC audit narrative.
- **D-06:** Regimen-label impact — whether new chemo dates change first-line regimen labels (ABVD /
  BV+AVD / Nivo+AVD) for adults 21+. Higher effort than D-03..D-05; researcher/planner to determine
  least-invasive approach.
- **D-07:** Drug-name string match — match unmatched NDCs against the chemo ingredient list using
  `RAW_MEDADMIN_MED_NAME` and dispensing name text.
- **D-08:** Frequency-ranked review — rank unmatched NDCs by patient/row volume.
- **D-09:** RxNav re-query — re-query ~7,739 unresolved NDCs against alternate RxNav endpoints.
  HiPerGator-only (network). Expect a runtime checkpoint mirroring Phase 122's R/108 build.
- **D-10:** Resolved-non-chemo gap check — of ~16,588 resolved NDCs, check whether any resolved to a
  chemo ingredient MISSING from `chemo_rxnorm`. This phase FLAGS gaps; correcting the list is a
  follow-up.
- **D-11:** Single multi-sheet xlsx — one styled workbook, one sheet per concern. Amy-ready. HIPAA
  suppression standard (counts 1-10).
- **D-12:** Quantification only — this phase produces the diff + audit xlsx and stops. Full
  downstream regeneration remains deferred.

### Claude's Discretion

- Whether to extend R/107 in place vs create a sibling diagnostic script (D-01/D-02)
- Exact sheet layout/ordering within the xlsx and styling helpers to reuse
- Whether RxNav re-query (D-09) lands in the crosswalk-builder family (R/108) or a dedicated audit
  script; checkpoint structure for the network step
- Least-invasive method to compute regimen labels on both source sets (D-06)
- Script number / registration (R/39 vs SCRIPT_INDEX-only) and R/88 smoke sections

### Deferred Ideas (OUT OF SCOPE)

- Full downstream regeneration of episodes/Gantt/timing/payer outputs with the fix
- Correcting the `chemo_rxnorm` reference list based on D-10 findings
- Immunotherapy MED_ADMIN/DISPENSING contribution
- Broader audit of other tables for analogous code-column mismatches
</user_constraints>

---

## Summary

Phase 123 is a pure quantification and investigation phase with no new detection logic. It extends
the existing R/107 diagnostic to compute a deterministic before/after diff at source level, uses the
Phase 122 `get_chemo_hits()` helper for the "after" side so the diff matches production exactly, and
audits unmatched NDCs through four methods. The deliverable is one multi-sheet styled xlsx using the
openxlsx2 pattern already established by R/51 and the TABLE scripts.

The highest-effort deliverable is D-06 (regimen-label impact), because regimen detection in R/28
depends on `drug_names` built by R/27 → R/26 → R/28. The least-invasive path to get regimen labels
on both source sets is to apply the regimen detection logic INLINE in the diagnostic script, using
the same `has_drug()` / `has_jcode()` pattern from R/28, rather than re-running the full R/25 →
R/26 → R/27 → R/28 chain. This is feasible because what we need is just the before/after change
count — not a full production output — and the drug-name strings for the "after" set can be derived
from `get_chemo_hits()` triggering_code → MEDICATION_LOOKUP lookup.

The D-09 RxNav re-query must be HiPerGator-only (network calls) and follows the R/108 batch-loop
pattern exactly: httr2 req_retry, 0.1s sleep, progress every 100 NDCs. The alternate endpoints to
try are `ndcproperties.json?id=NDC` and `ndcstatus.json?id=NDC` (which can surface historical NDC
records that the primary `rxcui.json?idtype=NDC` misses).

**Primary recommendation:** Create a sibling script (R/109) rather than editing R/107 in-place.
R/107 is the original read-only diagnostic that documents the pre-fix state; R/109 is the post-fix
quantification. Both are SCRIPT_INDEX-only, no R/39 registration.

---

## R/107 Structure — What Exists Today

R/107 (`R/107_med_admin_dispensing_gap_diagnostic.R`) is the pre-fix diagnostic. Its sections:

| Section | What it does |
|---------|-------------|
| 1 | Setup: dplyr, glue, stringr, lubridate; sources R/00_config.R, utils_duckdb, utils_dates, utils_treatment |
| 2 | Constants: `CHEMO_RXNORM <- TREATMENT_CODES$chemo_rxnorm`; `suppress_small()` HIPAA helper (suppresses n 1-10 to NA) |
| 3 | Self-bootstrap DuckDB: `USE_DUCKDB <- TRUE; if (!exists("pcornet_con")) open_pcornet_con()` |
| 4 | Cohort scope: `get_hl_patient_ids()` → `hl_ids` (9,282); `filter_to_cohort()` helper |
| 5 | PRESCRIBING baseline: `RXNORM_CUI %in% CHEMO_RXNORM`; emits `rx_patients`, `rx_pairs`, `rx_first_date` |
| 6a | MED_ADMIN RX-typed chemo: `MEDADMIN_TYPE=='RX' & MEDADMIN_CODE %in% CHEMO_RXNORM` |
| 6b | Increment beyond PRESCRIBING: `setdiff()` for new patients; `anti_join()` for new pairs; earlier-first-date via `inner_join` of min-dates |
| 6c | MED_ADMIN ND volume (footprint only — no crosswalk at time of writing) |
| 7 | DISPENSING footprint (NDC only — no chemo match) |
| 8 | HEADLINE console summary + `write.csv()` → `output/med_admin_dispensing_gap_diagnostic.csv` |

**What R/107 does NOT do (gaps for R/109 to add):**
- Does not use `load_ndc_crosswalk()` / `get_chemo_hits()` (written before Phase 122 fix)
- Does not compute the "after" set (PRESCRIBING + MED_ADMIN-RX + NDC-resolved sources combined)
- Does not compute per-ingredient delta (D-05)
- Does not compute timing-shift distribution in days (D-04 has only the "68 patients" count)
- Does not write xlsx (writes CSV)
- Does not do any NDC audit

**Column layout confirmed (from R/107 Section 6a guard):**
```r
required_ma_cols <- c("MEDADMIN_TYPE", "MEDADMIN_CODE", "MEDADMIN_START_DATE")
```
MED_ADMIN also has `RAW_MEDADMIN_MED_NAME` (confirmed in 122-CONTEXT.md code_context).

---

## get_chemo_hits() — Exact Signature and Contract

Defined in `R/utils/utils_treatment.R` (lines 163-246). Auto-sourced by `R/00_config.R`.

```r
get_chemo_hits <- function(table_name, chemo_rxnorm, ndc_crosswalk = NULL)
```

**Returns:** `tibble(ID, treatment_date, triggering_code)` with `distinct()` rows. Returns `NULL`
(not error) when table or required columns are absent.

**ENCOUNTERID is deliberately omitted** from the return. Callers that need it add it after (see
R/26, which does `mutate(ENCOUNTERID = NA_character_)`).

**Three table branches:**

| table_name | Detection path | ndc_crosswalk required? |
|-----------|----------------|------------------------|
| `"PRESCRIBING"` | `RXNORM_CUI %in% chemo_rxnorm` | No |
| `"DISPENSING"` | `NDC` → `normalize_ndc()` → crosswalk lookup → filter to `chemo_rxnorm` | YES — returns NULL if absent |
| `"MED_ADMIN"` | RX-typed: `MEDADMIN_CODE %in% chemo_rxnorm`; ND-typed: crosswalk lookup | Crosswalk for ND-typed only; RX-typed always runs |

**Per-source and per-ingredient breakdown:** The returned tibble carries `triggering_code` (= RxCUI
for PRESCRIBING and MED_ADMIN-RX; = resolved RxCUI from crosswalk for DISPENSING and MED_ADMIN-ND).
A `group_by(triggering_code) %>% summarise(n_patients = n_distinct(ID), n_dates = n())` on the
result gives the per-ingredient delta. Map `triggering_code → ingredient name` via
`MEDICATION_LOOKUP[triggering_code]` or the `DRUG_NAME_ALIASES`-normalized name.

**`load_ndc_crosswalk()` signature:**
```r
load_ndc_crosswalk <- function()  # no args
# Returns named character vector (NDC 11-digit -> RxCUI) or character(0) if file absent
# File: here("data", "reference", "ndc_rxnorm_crosswalk.rds")
```

**`normalize_ndc()` signature:**
```r
normalize_ndc <- function(ndc)  # vectorized
# str_remove_all(ndc, "-") |> str_pad(width = 11, side = "left", pad = "0")
```

---

## Before/After Diff Construction

**Recommendation: Create R/109 as a sibling diagnostic (not edit R/107).** R/107 is the historical
pre-fix record (read-only sizing of the bug). R/109 is the post-fix quantification. Both registered
in SCRIPT_INDEX-only, neither in R/39.

**The diff is constructed from three independent source tibbles, then unioned for the "after" set:**

```r
# Load crosswalk once
ndc_crosswalk <- load_ndc_crosswalk()
chemo_rxnorm  <- TREATMENT_CODES$chemo_rxnorm

# Before set: PRESCRIBING only
hits_rx  <- get_chemo_hits("PRESCRIBING", chemo_rxnorm)           # triggering_code = RxCUI

# After set: all three sources unioned
hits_ma  <- get_chemo_hits("MED_ADMIN",   chemo_rxnorm, ndc_crosswalk)  # RX-typed + ND-typed
hits_dp  <- get_chemo_hits("DISPENSING",  chemo_rxnorm, ndc_crosswalk)  # NDC-resolved

# Cohort-scope each
hits_rx_coh <- hits_rx %>% filter(ID %in% hl_ids)
hits_ma_coh <- hits_ma %>% filter(ID %in% hl_ids)
hits_dp_coh <- hits_dp %>% filter(ID %in% hl_ids)

# Before union
before <- hits_rx_coh %>% distinct(ID, treatment_date)

# After union (PRESCRIBING + MED_ADMIN + DISPENSING)
after <- bind_rows(
  hits_rx_coh %>% mutate(source = "PRESCRIBING"),
  hits_ma_coh %>% mutate(source = "MED_ADMIN"),
  hits_dp_coh %>% mutate(source = "DISPENSING")
) %>% distinct(ID, treatment_date)
```

**D-03 (patient & date counts):** `n_distinct(before$ID)` vs `n_distinct(after$ID)`;
`nrow(before)` vs `nrow(after)`. Per-source breakdown: apply `group_by(source)` before `distinct`.

**D-04 (first-chemo timing shift):**
```r
before_first <- hits_rx_coh %>% group_by(ID) %>% summarise(first_before = min(treatment_date))
after_first  <- after_labeled %>% group_by(ID) %>% summarise(first_after  = min(treatment_date))
shift_df <- inner_join(before_first, after_first, by = "ID") %>%
  filter(first_after < first_before) %>%
  mutate(shift_days = as.numeric(first_before - first_after))
# n_distinct(shift_df$ID) = patients with earlier first-chemo
# Distribution: quantile(shift_df$shift_days, probs = c(0, .25, .5, .75, 1))
```

**D-05 (per-drug/ingredient delta):**
```r
# Map triggering_code (RxCUI) -> ingredient name
# Use MEDICATION_LOOKUP[triggering_code] or names from chemo_rxnorm with comments
ingredient_before <- hits_rx_coh %>%
  group_by(triggering_code) %>%
  summarise(n_pts_before = n_distinct(ID), n_dates_before = n())

ingredient_after <- bind_rows(hits_rx_coh, hits_ma_coh, hits_dp_coh) %>%
  group_by(triggering_code) %>%
  summarise(n_pts_after = n_distinct(ID), n_dates_after = n())

ingredient_delta <- full_join(ingredient_before, ingredient_after, by = "triggering_code") %>%
  mutate(
    delta_pts   = coalesce(n_pts_after,   0L) - coalesce(n_pts_before,   0L),
    delta_dates = coalesce(n_dates_after, 0L) - coalesce(n_dates_before, 0L)
  ) %>%
  arrange(desc(delta_pts))
```

---

## D-06: Regimen-Label Impact — Least-Invasive Approach

**Regimen detection lives in R/28_episode_classification.R**, Section 5 (lines 287-443).

The full production path is: `R/25` (extract dates) → `R/26` (episode boundaries + drug_names via
R/27 join) → `R/28` (regimen_label using `has_drug()` on drug_names + `has_jcode()` fallback).

**Regimen detection requires `drug_names`** — a comma-separated string of canonical drug names per
episode, built by joining the chemo hits to `MEDICATION_LOOKUP` / `R/27` drug_name cache.

**Least-invasive approach (recommended for D-06):** Apply regimen detection inline in R/109 using
only ingredient name lookup and the existing `has_drug()` logic pattern, without re-running R/25/26:

1. From the "before" and "after" chemo-hit tibbles, group by `(ID, episode_number)` using the same
   90-day gap window logic from R/25 (`assign_episode_ids()`). This is self-contained and does not
   require loading treatment_episodes.rds.
2. For each episode, map `triggering_code → drug_name` via `MEDICATION_LOOKUP[triggering_code]`.
   For codes not in MEDICATION_LOOKUP, fall back to the RxNorm comments in `chemo_rxnorm`
   (e.g., "3639" maps to "Doxorubicin Hydrochloride" in MEDICATION_LOOKUP).
3. Collapse drug names per episode as a comma-separated string, apply the same
   `has_drug(drug_names, "doxorubicin")` / `has_drug(drug_names, "bleomycin")` / etc. pattern
   from R/28 Section 5b.
4. Apply the `case_when` regimen label rules from R/28 Section 5d verbatim.
5. Filter to adults 21+ using DEMOGRAPHIC.BIRTH_DATE joined by ID (query via `get_pcornet_table`).
6. Compare before-regimen-label counts vs after-regimen-label counts.

**What we are reporting for D-06:** Not a full per-patient regimen table. Rather:
- N patients labeled ABVD / BV+AVD / Nivo+AVD before vs after
- N patients whose regimen label CHANGES due to new dates entering or shifting first-chemo date
- Adult 21+ filter applied

**Effort estimate:** MEDIUM — requires re-implementing `assign_episode_ids()` logic or importing it
from R/25. The alternative (much lighter) is to read the existing `cache/outputs/treatment_episodes.rds`,
join the new source hits, and see whether any patient's first chemo date shifts enough to change
their regimen label. This avoids re-running R/25/26 entirely and is the real "least-invasive" path:

```r
# Option A (recommended — minimal effort):
episodes <- readRDS(here("cache", "outputs", "treatment_episodes.rds"))
# episodes already has regimen_label (from prior R/28 run)
# Join new source patients; check: does any patient in hits_ma_coh or hits_dp_coh
# have a new EARLIER date that predates their episode_start?
# If yes → flag those patients; their regimen may change on full re-run
# This is an UPPER BOUND on regimen label impact, not exact — note this explicitly in the xlsx
```

Option A is recommended for Phase 123 because it avoids the full R/25/26 execution chain on
HiPerGator, meets D-12 ("quantification only"), and is explicitly labeled as an upper bound
estimate in the deliverable.

---

## NDC Audit Universe and Audit Methods

**Source:** `output/ndc_rxnorm_crosswalk_audit.csv`

**Column structure (verified by reading file):**
```
"NDC","rxcui","lookup_status"
"16714097701","1808222","matched"
"16729029783",,"miss"
```
Three columns: NDC (11-digit no-hyphen), rxcui (blank when miss), lookup_status ("matched" / "miss").

**Universe numbers (from 122-VERIFICATION.md):**
- 24,327 distinct NDCs queried
- 16,588 matched to RxCUI ("matched")
- 7,739 no RxCUI ("miss")
- 126 of the matched NDCs map to a chemo RxCUI; cover 42 of 97 chemo ingredients

**D-07 (drug-name string match):** Join unmatched NDCs back to MED_ADMIN (where `MEDADMIN_TYPE=='ND'`)
to get `RAW_MEDADMIN_MED_NAME`. DISPENSING has no drug name text column in this extract
(confirmed in 122-CONTEXT.md: "no `RAW_DISPENSE_MED_NAME`"). So drug-name match applies to
MED_ADMIN-ND only. Match lowercased `RAW_MEDADMIN_MED_NAME` against:
- `names(TREATMENT_CODES$chemo_rxnorm)` → no; chemo_rxnorm is a character vector of CUIs (no names)
- MEDICATION_LOOKUP values (the canonical drug names)
- `DRUG_NAME_ALIASES` keys (lowercased variant names)
- `canonicalize_drug_name(RAW_MEDADMIN_MED_NAME)` → if result matches a MEDICATION_LOOKUP value

```r
# String match: does any canonical drug name appear as a substring of RAW_MEDADMIN_MED_NAME?
chemo_names <- unique(MEDICATION_LOOKUP[MEDICATION_LOOKUP %in% values_of_chemo_codes])
# Or build from DRUG_NAME_ALIASES + the chemo ingredient strings
str_detect(tolower(raw_name), paste(tolower(chemo_names), collapse = "|"))
```

**D-08 (frequency ranking):** Join unmatched NDC list to both DISPENSING and MED_ADMIN-ND; count
`(ID, NDC)` pairs per NDC; rank descending. Include `RAW_MEDADMIN_MED_NAME` where available.
Output: top-N table (N = 25 or 50) with NDC, raw_name, n_patients (HIPAA-suppressed), n_rows.

**D-09 (RxNav alternate endpoint re-query):** HiPerGator-only network step. Two alternate endpoints
to try for each of the 7,739 unresolved NDCs:
1. `ndcproperties.json?id={NDC}` — returns product properties including `ndcItem.rxcui` (if any)
2. `ndcstatus.json?id={NDC}` — returns historical status, may include `ndcHistory` with a
   `rxcui` field for retired/remapped NDCs

**RxNav API shapes (from R/108 pattern + NLM docs):**
```
GET https://rxnav.nlm.nih.gov/REST/ndcproperties.json?id=00069306030
  Response: { "ndcItem": { "rxcui": "3639", "ndc11": "00069306030", ... } } or {}

GET https://rxnav.nlm.nih.gov/REST/ndcstatus.json?id=00069306030
  Response: { "ndcStatus": { "status": "ACTIVE", "rxcui": "3639" } } or missing rxcui
```

Both endpoints follow the same httr2 req_retry / 0.1s sleep / NA-on-failure pattern as R/108's
`lookup_ndc_to_rxcui()`. The planner should structure D-09 as:
- A new batch-loop function `lookup_ndc_alternate()` that tries `ndcproperties` first, then
  `ndcstatus` as fallback
- Returns first non-NA RxCUI found, or NA if both fail
- Write output to `output/ndc_rxnorm_crosswalk_audit_requery.csv` (new file, not overwrite)

**D-10 (resolved-non-chemo gap check):** For the 16,588 matched NDCs, join their rxcui to
`TREATMENT_CODES$chemo_rxnorm`. NDCs whose rxcui is NOT in `chemo_rxnorm` are the resolved-but-non-chemo
population. Within that population, some RxCUIs may map to a chemo ingredient we simply don't have
in `chemo_rxnorm` (e.g., an oral chemo agent added post-Phase 40). Detect by:
- Getting the preferred drug name for each such RxCUI via `MEDICATION_LOOKUP[rxcui]` (if present)
  or via the RxNav `rxcui/{rxcui}/properties.json` endpoint offline lookup
- Flagging any that match known chemo drug name patterns (could use `canonicalize_drug_name`)
- Phase 123 output: a table of candidate gap RxCUIs + drug names for SME review

---

## chemo_rxnorm Reference Shape

`TREATMENT_CODES$chemo_rxnorm` (in R/00_config.R, Section 7, starting line 2581) is a **plain
character vector** of RxNorm CUI strings. It has **no names** — no ingredient name annotations on
the vector itself.

**97 chemo ingredients** mentioned in VERIFICATION.md means 97 distinct IN-level concepts. The
actual vector has many more entries (dose-form-specific CUIs for the same ingredient): for example,
doxorubicin appears as "3639" (base CUI), "1799305" (IV infusion), "1790099" (liposomal 2mg/mL),
"1790103" (10mg injection), and others.

**To map triggering_code (RxCUI) to ingredient name:**
1. `MEDICATION_LOOKUP[triggering_code]` — covers chemo CUIs that are in the treatment codes
   reference Excel. Returns the canonical display name (e.g., "Doxorubicin Hydrochloride").
2. Fallback: the code comment in R/00_config.R (e.g., `# 3639: Doxorubicin`) — these are embedded
   in the source but not machine-readable at runtime.
3. RxNav `rxcui/{cui}/properties.json` for ingredient-level name lookup — but this requires network
   access (HiPerGator-only).

**Practical approach for D-05 and D-10 in R/109:** Group by `triggering_code`; join to
`MEDICATION_LOOKUP` for display name; for unmatched codes emit the raw CUI.

---

## xlsx Delivery Pattern (D-11)

**Library:** `openxlsx2` (used throughout — R/51, R/100, R/25, R/26, R/28, etc.). NOT `writexl`.

**Pattern established in R/51_post_death_encounter_investigation.R:**

```r
library(openxlsx2)
wb <- wb_workbook()

# Per sheet (title at row 1, subtitle at row 2, data at row 4):
wb$add_worksheet("Sheet Name")
wb$add_data(sheet = "Sheet Name", x = title_string, start_row = 1, start_col = 1)
wb$add_font(sheet = "Sheet Name", dims = "A1", name = "Calibri", size = 16, bold = TRUE,
            color = wb_color("FF1F2937"))
wb$merge_cells(sheet = "Sheet Name", dims = "A1:K1")

wb$add_data(sheet = "Sheet Name", x = data_frame, start_row = 4, start_col = 1)
wb$add_fill(sheet = "Sheet Name", dims = "A4:K4", color = wb_color("FF374151"))
wb$add_font(sheet = "Sheet Name", dims = "A4:K4", name = "Calibri", size = 11, bold = TRUE,
            color = wb_color("FFFFFFFF"))
wb$freeze_pane(sheet = "Sheet Name", firstActiveRow = 5)
wb$set_col_widths(sheet = "Sheet Name", cols = 1:K, widths = c(...))

wb$save(OUTPUT_XLSX)
```

**HIPAA suppression:** Already implemented as `suppress_small(n)` in R/107 (lines 101-104).
Returns `NA_integer_` for any patient count between 1 and 10 inclusive. This function should be
copied verbatim into R/109.

**Confirmed styling constants (from R/51):**
- Header fill: `wb_color("FF374151")` (dark gray)
- Header font: Calibri 11 bold white `wb_color("FFFFFFFF")`
- Title font: Calibri 16 bold dark `wb_color("FF1F2937")`
- Subtitle font: Calibri 10 gray `wb_color("FF6B7280")`
- Number format for counts: `"#,##0"`
- Data starts at row 4; freeze at row 5

**R/100 (RUCA) also uses a `add_styled_sheet()` DRY wrapper** — the planner may recommend this
pattern for R/109 if there are 6+ sheets.

---

## Registration Conventions

**R/107 and R/108 precedent:** Both are SCRIPT_INDEX-only (one-time diagnostics), NOT wired into
R/39, NOT covered by R/88 structural sections.

**Recommendation for R/109:** Same treatment — SCRIPT_INDEX-only, no R/39 registration. These are
quantification/audit scripts, not repeatable pipeline steps.

**For D-09 (RxNav re-query):** The alternate-endpoint re-query can be structured as:
- Option A: A new standalone script (R/109b or R/110) mirroring R/108's build pattern
- Option B: An internal function in R/109 behind an `IS_LOCAL`-gated section that skips on Windows
  and runs on HiPerGator

Option B is preferred for Phase 123 because D-09 is one of several audit steps, not a standalone
crosswalk build. Structure the HiPerGator network section with the same IS_LOCAL guard:
```r
if (!IS_LOCAL) {
  # D-09: RxNav alternate-endpoint re-query (HiPerGator only)
  ...
} else {
  message("  [D-09] Skipped in local mode (requires network). Run on HiPerGator.")
}
```

**R/88 smoke section:** The next available section suffix is **15u** (after 15t = Phase 122).
For consistency with prior phases, a 14-check Section 15u smoke test in R/88 is RECOMMENDED but
optional (the R/107/R/108 precedent shows SCRIPT_INDEX-only registration is acceptable for
one-time diagnostics). Given the xlsx output and complexity of R/109, adding Section 15u is
appropriate and follows the pattern for all 100+ scripts since Phase 113.

**Section suffix sequence:**
- 15r = Phase 120 (Supportive Care)
- 15s = Phase 121 (ZIP change)
- 15t = Phase 122 (MED_ADMIN/DISPENSING fix)
- 15u = Phase 123 (this phase)

---

## DuckDB Access Pattern

Confirmed from R/107 and R/108:

```r
USE_DUCKDB <- TRUE
if (!exists("pcornet_con", envir = .GlobalEnv)) {
  open_pcornet_con()
}
```

`open_pcornet_con()` is idempotent (defined in `R/utils/utils_duckdb.R`, auto-sourced by
`R/00_config.R`). `get_pcornet_table("TABLE_NAME")` returns a `tbl_dbi` lazy object;
`collect()` materializes it. On Windows with local fixtures, tables may be empty or missing —
the `safe_table()` pattern (in utils_treatment.R) degrades gracefully.

`close_pcornet_con()` at script end (R/107 line 443). R/109 should follow this pattern.

---

## Architecture Patterns

### Recommended Project Structure for R/109

```
R/109_med_admin_dispensing_fix_impact_audit.R
  Section 1: Setup + libraries (dplyr, glue, openxlsx2, httr2, here, lubridate)
  Section 2: Constants (CHEMO_RXNORM, suppress_small, OUTPUT_XLSX path)
  Section 3: Self-bootstrap DuckDB
  Section 4: Cohort scope (get_hl_patient_ids → hl_ids)
  Section 5: Chemo source extraction
    5a. Before set: get_chemo_hits("PRESCRIBING", ...) — cohort-scoped
    5b. After set: get_chemo_hits("MED_ADMIN", ...) + get_chemo_hits("DISPENSING", ...) — cohort-scoped
    5c. Source-level tagging (mutate source = "PRESCRIBING"/"MED_ADMIN"/"DISPENSING")
  Section 6: D-03 — Patient and date counts by source (before vs after)
  Section 7: D-04 — First-chemo timing shift distribution
  Section 8: D-05 — Per-ingredient delta (triggering_code → MEDICATION_LOOKUP name)
  Section 9: D-06 — Regimen-label impact (episodes.rds join — upper-bound estimate)
    9a. Load treatment_episodes.rds
    9b. Join new source patients; compare first-chemo dates
    9c. Flag patients whose first-chemo date would shift
    9d. Apply adult filter (age >= 21 at episode_start via DEMOGRAPHIC)
  Section 10: NDC audit universe (read ndc_rxnorm_crosswalk_audit.csv)
  Section 11: D-07 — Drug-name string match (RAW_MEDADMIN_MED_NAME)
  Section 12: D-08 — Frequency-ranked review (top-N unmatched NDCs)
  Section 13: D-09 — RxNav alternate-endpoint re-query (IS_LOCAL-gated)
  Section 14: D-10 — Resolved-non-chemo gap check
  Section 15: Build and write multi-sheet xlsx (openxlsx2)
  Section 16: Close DuckDB connection
```

### Sheet Layout for the xlsx (D-11)

| Sheet | Content | Key columns |
|-------|---------|-------------|
| 1. Before-After Summary | D-03 headline counts | source, n_patients_before, n_patients_after, n_dates_before, n_dates_after, delta_patients, delta_dates |
| 2. Timing Shift | D-04 first-chemo shift | n_patients_earlier, shift_days_median, shift_days_p25, shift_days_p75, shift_days_max |
| 3. Per-Ingredient Delta | D-05 by ingredient | triggering_code, drug_name, n_pts_before, n_pts_after, delta_pts, n_dates_before, n_dates_after, delta_dates |
| 4. Regimen Impact | D-06 label changes | regimen_label, n_episodes_before, n_episodes_after, delta (adults 21+, upper bound) |
| 5. Unmatched NDC Top-N | D-08 frequency rank | NDC, raw_med_name, n_patients (suppressed), n_rows, rank |
| 6. NDC String Match | D-07 name-matching hits | NDC, raw_med_name, matched_ingredient, match_method |
| 7. RxNav Requery Results | D-09 alternate-endpoint | NDC, rxcui_primary (miss), rxcui_alternate, endpoint_used, chemo_match |
| 8. Resolved-Gap Findings | D-10 chemo_rxnorm gaps | rxcui, drug_name, n_ndc_entries, in_chemo_rxnorm (FALSE = gap), flag |

### Anti-Patterns to Avoid

- **Do NOT use `treatment_episodes.rds` for D-05 ingredient counting** — the triggering_code in
  episodes has been through R/28's drug_group mapping and may not preserve per-source RxCUI
  granularity. Use the raw `get_chemo_hits()` output directly.
- **Do NOT overwrite `output/ndc_rxnorm_crosswalk_audit.csv`** — write D-09 results to a new file
  (e.g., `output/ndc_rxnorm_crosswalk_requery.csv`).
- **Do NOT attempt a full pipeline re-run (R/25 → R/26 → R/28)** for D-06. The episodes.rds
  join is faster, produces an upper-bound estimate, and satisfies D-12 ("quantification only").
- **Do NOT register R/109 in R/39** — it is a one-time diagnostic, same as R/107/R/108.

---

## Common Pitfalls

### Pitfall 1: Before Set vs Production "Before"
**What goes wrong:** Using `get_chemo_hits("PRESCRIBING", ...)` for the "before" set gives the
right rows, but the counts may differ from historical R/107 output if the data was re-ingested or
the cohort changed.
**How to avoid:** Note in the xlsx that "before" is defined at extraction time (2026-07-14
HiPerGator run) and the R/107 CSV is the authoritative pre-fix baseline. R/109 computes the same
numbers as R/107 for validation, then adds the after-set on top.

### Pitfall 2: treatment_date Parsing for MED_ADMIN
**What goes wrong:** `MEDADMIN_START_DATE` is a character in the PCORnet CSVs and may require
`parse_pcornet_date()` before date comparisons.
**How to avoid:** `get_chemo_hits()` does NOT parse dates — it returns `treatment_date` as
whatever type the table has (likely character). R/109 must call `parse_pcornet_date(treatment_date)`
after `collect()` for MED_ADMIN and DISPENSING rows, matching R/107 Section 6a pattern (line 249).

### Pitfall 3: MED_ADMIN RX-typed vs ND-typed Double-Counting
**What goes wrong:** Both `get_chemo_hits("MED_ADMIN", ..., crosswalk)` RX path and ND path can
hit the same patient for different triggering_codes. The union of both is correct (they represent
different administrations), but make sure `distinct(ID, treatment_date)` deduplication is applied
to the combined MED_ADMIN output before merging with DISPENSING.
**How to avoid:** `get_chemo_hits()` already returns `dplyr::bind_rows(rx_hits, nd_hits)` for
MED_ADMIN — the two paths are unioned inside the function. The caller does not need to union them
separately.

### Pitfall 4: Adult Filter for D-06
**What goes wrong:** DEMOGRAPHIC uses `ID` (not PATID) — consistent with the rest of the pipeline.
`BIRTH_DATE` may need `parse_pcornet_date()`.
**How to avoid:** Use `get_pcornet_table("DEMOGRAPHIC") %>% select(ID, BIRTH_DATE) %>% collect()`.
Age at episode_start = `floor(interval(BIRTH_DATE, episode_start) / years(1))`.

### Pitfall 5: D-09 Rate Limiting
**What goes wrong:** 7,739 NDCs × 2 endpoints = up to ~15,478 API calls. At 0.1s sleep = ~26
minutes minimum. If the alternate endpoints return a 429, the retry logic from R/108 handles it,
but this must be explicitly included.
**How to avoid:** Reuse `lookup_ndc_to_rxcui()` from R/108 as a template; substitute the alternate
URL. Include the `req_retry(max_tries = 3, is_transient = ~ resp_status(.x) %in% c(429L, 503L, 504L))`
guard verbatim.

### Pitfall 6: chemo_rxnorm Is a Named-Vector-of-CUIs With No Ingredient Labels at Runtime
**What goes wrong:** `TREATMENT_CODES$chemo_rxnorm` is a plain character vector. The ingredient
names appear only as source-code comments (e.g., `"3639", # Doxorubicin`). There is no names()
attribute to pull.
**How to avoid:** Use `MEDICATION_LOOKUP[triggering_code]` for display names. For CUIs not in
MEDICATION_LOOKUP (some dose-specific entries may be missing), emit the raw CUI string and note
"unresolved" in the xlsx.

### Pitfall 7: R/109 Windows-Only Structural Test
**What goes wrong:** DuckDB queries, NDC crosswalk load, and RxNav re-query all fail locally on
Windows (no real data, no Rscript on this executor).
**How to avoid:** Follow the R/107 precedent: structural-only verification on Windows (grep checks
in R/88 Section 15u), runtime deferred to HiPerGator. The IS_LOCAL guard in R/00_config.R handles
the environment split.

---

## Code Examples

### D-03: Source-Level Counts (Verified Pattern)

```r
# Source: R/107_med_admin_dispensing_gap_diagnostic.R Sections 5-7 + utils_treatment.R
ndc_crosswalk <- load_ndc_crosswalk()
hits_rx <- get_chemo_hits("PRESCRIBING", CHEMO_RXNORM)
hits_ma <- get_chemo_hits("MED_ADMIN",   CHEMO_RXNORM, ndc_crosswalk)
hits_dp <- get_chemo_hits("DISPENSING",  CHEMO_RXNORM, ndc_crosswalk)

# Cohort-scope
hits_rx_coh <- hits_rx %>% filter(ID %in% hl_ids) %>%
  mutate(treatment_date = parse_pcornet_date(treatment_date))
hits_ma_coh <- hits_ma %>% filter(ID %in% hl_ids) %>%
  mutate(treatment_date = parse_pcornet_date(treatment_date))
hits_dp_coh <- hits_dp %>% filter(ID %in% hl_ids) %>%
  mutate(treatment_date = parse_pcornet_date(treatment_date))

before <- hits_rx_coh %>% distinct(ID, treatment_date)
after  <- bind_rows(
  hits_rx_coh %>% mutate(chemo_source = "PRESCRIBING"),
  hits_ma_coh %>% mutate(chemo_source = "MED_ADMIN"),
  hits_dp_coh %>% mutate(chemo_source = "DISPENSING")
)

# Per-source counts
source_counts <- after %>%
  group_by(chemo_source) %>%
  summarise(n_patients = suppress_small(n_distinct(ID)),
            n_id_date_pairs = n_distinct(paste(ID, treatment_date)))
```

### xlsx Workbook Initialization (Verified Pattern from R/51)

```r
# Source: R/51_post_death_encounter_investigation.R Section 10
library(openxlsx2)
wb <- wb_workbook()

add_sheet <- function(wb, sheet_name, title, data, ncols) {
  wb$add_worksheet(sheet_name)
  wb$add_data(sheet = sheet_name, x = title, start_row = 1, start_col = 1)
  wb$add_font(sheet = sheet_name, dims = "A1",
              name = "Calibri", size = 16, bold = TRUE, color = wb_color("FF1F2937"))
  wb$merge_cells(sheet = sheet_name, dims = glue("A1:{LETTERS[ncols]}1"))
  wb$add_data(sheet = sheet_name, x = data, start_row = 4, start_col = 1)
  wb$add_fill(sheet = sheet_name, dims = glue("A4:{LETTERS[ncols]}4"),
              color = wb_color("FF374151"))
  wb$add_font(sheet = sheet_name, dims = glue("A4:{LETTERS[ncols]}4"),
              name = "Calibri", size = 11, bold = TRUE, color = wb_color("FFFFFFFF"))
  wb$freeze_pane(sheet = sheet_name, firstActiveRow = 5)
  wb
}
wb$save(OUTPUT_XLSX)
```

### RxNav Alternate-Endpoint Lookup (D-09, Verified Pattern from R/108)

```r
# Source: R/108_build_ndc_rxnorm_crosswalk.R Section 4 — adapted for alternate endpoints
lookup_ndc_alternate <- function(ndc, sleep_sec = 0.1) {
  for (endpoint in c("ndcproperties", "ndcstatus")) {
    url <- glue("https://rxnav.nlm.nih.gov/REST/{endpoint}.json?id={ndc}")
    result <- tryCatch({
      resp <- httr2::request(url) |>
        httr2::req_timeout(10) |>
        httr2::req_retry(max_tries = 3,
          is_transient = ~ httr2::resp_status(.x) %in% c(429L, 503L, 504L)) |>
        httr2::req_perform()
      data <- httr2::resp_body_json(resp)
      # ndcproperties: data$ndcItem$rxcui
      # ndcstatus:     data$ndcStatus$rxcui
      rxcui <- data[[if (endpoint == "ndcproperties") "ndcItem" else "ndcStatus"]][["rxcui"]]
      if (!is.null(rxcui) && nchar(rxcui) > 0) rxcui else NA_character_
    }, error = function(e) NA_character_)
    Sys.sleep(sleep_sec)
    if (!is.na(result)) return(list(rxcui = result, endpoint = endpoint))
  }
  list(rxcui = NA_character_, endpoint = NA_character_)
}
```

---

## Standard Stack

### Core (confirmed from codebase inspection)

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| dplyr | 1.2.0+ | Data manipulation | All pipeline scripts |
| glue | 1.8.0 | String interpolation | Logging messages |
| openxlsx2 | (project std) | Multi-sheet xlsx write | Established pattern in R/51, R/100 |
| httr2 | (project std) | RxNav API calls | Used in R/108, R/27, R/105 |
| here | 1.0.2 | Project-relative paths | All 100+ scripts |
| lubridate | 1.9.3+ | Date arithmetic (D-04 shift days) | Pipeline standard |
| stringr | 1.5.1+ | String match for D-07 | Pipeline standard |
| purrr | 1.0.2+ | map over NDC batch | Used in R/108 |

All auto-sourced from `R/00_config.R` or part of tidyverse. No new packages required.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Rscript | Runtime execution | Windows: No; HiPerGator: Yes | 4.4.2 (HPC) | HiPerGator runtime checkpoint |
| DuckDB PCORnet | D-03..D-09 | Windows: No (fixtures only); HiPerGator: Yes | — | Structural test only on Windows |
| `data/reference/ndc_rxnorm_crosswalk.rds` | D-03 after-set, D-09 | Committed to git | — | load_ndc_crosswalk() degrades gracefully |
| `output/ndc_rxnorm_crosswalk_audit.csv` | D-07..D-10 | In repo (HiPerGator run) | 24,327 rows | Required — must exist before R/109 runs |
| `cache/outputs/treatment_episodes.rds` | D-06 | HiPerGator only | — | D-06 section skipped locally |
| RxNav API (network) | D-09 | HiPerGator only | — | IS_LOCAL guard skips D-09 |

**Missing dependencies with no fallback:**
- `output/ndc_rxnorm_crosswalk_audit.csv` must exist (produced by R/108 on HiPerGator, already in
  repo per 122-VERIFICATION.md).

**Missing dependencies with fallback:**
- Rscript / DuckDB / RxNav / treatment_episodes.rds → all have IS_LOCAL-gated fallbacks.

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on Phase 123 |
|-----------|-------------------|
| tidyverse only (dplyr, no data.table) | R/109 must use dplyr. No `data.table` or `DT[i,j,by]` syntax. |
| Named predicates (`has_*`, `with_*`, `exclude_*`) | Not applicable to diagnostic scripts, but helper functions should be named descriptively. |
| here() for paths | All file references: `here("data", "reference", "...")`, `here("cache", "outputs", "...")`. |
| RStudio / HiPerGator runtime | No Rscript on Windows executor. Structural testing only locally; runtime on HiPerGator. |
| Self-bootstrap DuckDB | `USE_DUCKDB <- TRUE; if (!exists("pcornet_con")) open_pcornet_con()`. |
| HIPAA suppression standard | Patient counts 1-10 suppressed (NA) in all output. Use `suppress_small()`. |
| openxlsx2 for xlsx | NOT writexl. Use `wb_workbook()`, `$add_worksheet()`, `$add_data()`, `$save()`. |
| GSD workflow enforcement | This research is the required precursor step; no direct file edits before planning. |

---

## Open Questions

1. **D-06 regimen-label impact: does treatment_episodes.rds exist on HiPerGator post-Phase 122?**
   - What we know: treatment_episodes.rds is produced by R/26 and consumed by R/28. Phase 122
     patched R/26, so the last HiPerGator run of R/26 post-fix should have updated it.
   - What's unclear: Whether the user has re-run R/26 on HiPerGator since the Phase 122 fix.
   - Recommendation: Add a `file.exists(EPISODES_RDS)` guard in D-06 section; if absent, log
     "episodes.rds not found — D-06 skipped; re-run R/26 on HiPerGator to enable" and continue.

2. **D-09: Are `ndcproperties` and `ndcstatus` the right alternate endpoints?**
   - What we know: The primary lookup used `rxcui.json?idtype=NDC`. The NLM RxNav API also
     provides `ndcproperties.json?id={NDC}` (returns package-level NDC info including rxcui) and
     `ndcstatus.json?id={NDC}` (returns current/historical status with rxcui).
   - What's unclear: Whether these endpoints have better coverage for the specific 7,739 misses
     (which may be comorbidity drugs, not chemo at all).
   - Recommendation: Try both endpoints in D-09; if coverage is low (<5% recovery), note in xlsx
     that the misses are likely non-chemo medications and this confirms D-07/D-08 findings.

3. **D-07 string match: Does DISPENSING have any name text for drug-name matching?**
   - What we know: 122-CONTEXT.md confirms DISPENSING has "no `RAW_DISPENSE_MED_NAME`". Only
     MED_ADMIN has `RAW_MEDADMIN_MED_NAME`.
   - Recommendation: D-07 string match applies to MED_ADMIN-ND only. Note this in the xlsx with
     "DISPENSING: no drug name text available in this extract."

4. **Sheet count: 8 sheets in the xlsx — is that manageable for Amy?**
   - What we know: D-11 says "single multi-sheet xlsx". Eight sheets is achievable but could be
     consolidated (e.g., merge D-07 + D-08 into one "NDC String Audit" sheet).
   - Recommendation: Planner to decide whether to consolidate D-07+D-08 into one sheet and D-09+D-10
     into one sheet (reducing to 6 sheets total). Both options are fine; this is Claude's discretion.

---

## Sources

### Primary (HIGH confidence)
- Direct codebase inspection: `R/107_med_admin_dispensing_gap_diagnostic.R` — full section-by-section
  read; all structural findings verified from source
- Direct codebase inspection: `R/utils/utils_treatment.R` — `get_chemo_hits()`, `load_ndc_crosswalk()`,
  `normalize_ndc()` signatures verified line-by-line
- Direct codebase inspection: `R/108_build_ndc_rxnorm_crosswalk.R` — lookup pattern, httr2 retry,
  batch loop verified
- Direct codebase inspection: `R/00_config.R` — `TREATMENT_CODES$chemo_rxnorm` (char vector, no
  names attribute); `DRUG_NAME_ALIASES`; `canonicalize_drug_name()`; `MEDICATION_LOOKUP`
- Direct codebase inspection: `R/28_episode_classification.R` — regimen detection logic (has_drug,
  has_jcode, case_when regimen labels) verified
- Direct codebase inspection: `R/51_post_death_encounter_investigation.R` — openxlsx2 multi-sheet
  styling pattern (wb_workbook, add_worksheet, header colors, freeze_pane)
- `.planning/phases/122-*/122-VERIFICATION.md` — runtime numbers (24,327 NDCs / 16,588 matched /
  7,739 miss / 126 chemo NDCs / 42 of 97 ingredients)
- `.planning/phases/123-*/123-CONTEXT.md` — authoritative decision set D-01..D-12
- `output/ndc_rxnorm_crosswalk_audit.csv` — column structure verified (NDC, rxcui, lookup_status)
- `R/88_smoke_test_comprehensive.R` — section suffix sequence verified (15r=120, 15s=121, 15t=122 →
  15u=123 next)
- `R/SCRIPT_INDEX.md` — registration convention (SCRIPT_INDEX-only for R/107, R/108)

### Secondary (MEDIUM confidence)
- NLM RxNav API endpoint documentation — `ndcproperties.json` and `ndcstatus.json` endpoint shapes
  inferred from R/108 pattern + NLM REST API naming conventions. Not directly verified against live
  API (network access unavailable on Windows).

---

## Metadata

**Confidence breakdown:**
- R/107 structure and extension approach: HIGH — read full source
- get_chemo_hits() signature/contract: HIGH — read full source
- xlsx delivery pattern: HIGH — read full R/51 source
- openxlsx2 styling constants: HIGH — extracted from R/51 line-by-line
- Regimen detection call path (R/28): HIGH — read source; confirmed case_when pattern
- D-09 alternate RxNav endpoints: MEDIUM — inferred from R/108 pattern; endpoint names from NLM
  REST API convention not verified live
- Registration convention (SCRIPT_INDEX-only): HIGH — confirmed from R/107/R/108 entries in
  SCRIPT_INDEX.md
- Section 15u suffix: HIGH — confirmed by reading R/88 section markers

**Research date:** 2026-07-14
**Valid until:** Stable — no external dependencies. The codebase findings are locked to the current
repo state. Re-verify only if R/107, utils_treatment.R, or R/00_config.R change before planning.
