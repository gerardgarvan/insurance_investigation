# 143-DISCOVERY.md

Phase 143 — 180-Day File Enrichment Parity and Review Follow-ups
Discovery document produced by Plan 01, Task 2.
Date: 2026-08-14

---

## D-01 Decision

**Answer: d-01b — Content (run the full enrichment for 180-day episodes).**

Rationale: Phase 142 was triggered by a drug-name problem (Vinblastine duplicate). The colleague
will open the 180-day file to check whether the drug-name issue resolved and how regimens
distribute. A file with `drug_group` blank cannot answer that question. Episode counts alone are
insufficient. The full D-01b path (Plans 02 and 03) executes.

---

## Producer Disposition Table

Determined by `grep -rn "drug_group|code_type|source_table|episode_dx_codes|episode_dx_categories|episode_dx_7day_confirmed" R/ --include="*.R" -l` and reading the assignment lines in each candidate file.

| Script | Columns it produces | Reads episodes RDS via | Writes to | Parameterisable? | Window-dependent logic? |
|---|---|---|---|---|---|
| R/28_episode_classification.R | drug_group, code_type, source_table, episode_dx_codes, episode_dx_categories | `OUTPUT_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")` (line 98) — CONFIG constant, no argument | Same file (in-place readRDS → saveRDS, line 856) | No — takes no path argument; OUTPUT_RDS is a script-level constant, not a parameter | No — no hardcoded `90`, no GAP_THRESHOLD reference found |
| R/52_gantt_v2_export.R | episode_dx_7day_confirmed (Phase 115, lines 421–459) | `EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")` (line 135) — CONFIG constant | Written into export CSV only, not back to RDS | No — same CONFIG-constant path style | No — Phase 115 logic derives from cancer_summary.csv, not episode window |
| R/142_gantt_180_export.R | episode_dx_7day_confirmed (Phase 115 block, lines 298–326) | Reads treatment_episodes_180.rds directly (hardcoded suffix) | Written into 180-day CSV only | Partially — already reads the 180-day RDS; lacks the upstream five columns | No — same Phase 115 logic |

**Scripts confirmed NOT to produce the six enrichment columns (read-only consumers):**

R/100_ruca_rurality_summary.R, R/51_post_death_encounter_investigation.R, R/56_new_tables_from_groupings.R, R/57_drug_grouping_instances.R, R/58_co_administration_analysis.R, R/62_tiered_date_level.R, R/88_smoke_test_comprehensive.R — these scripts read the enrichment columns from the RDS but do not write them.

The CONTEXT.md named R/60–63, R/91, and R/112 as candidates. The grep confirms that
`drug_group`, `code_type`, `source_table`, `episode_dx_codes`, and `episode_dx_categories` are
assigned only in R/28. R/60–63, R/91, and R/112 do not appear in the `-l` output for
assignment-producing patterns on these column names. (They may have written columns in earlier
phases whose logic was later consolidated into R/28.)

---

## Join Key Risk

R/28 joins enrichment onto episodes using `episode_number` as the primary key. Specific line
references:

- **Cancer linkage join key:** `(patient_id, treatment_type, episode_number)` — lines 200, 205,
  212, 247, 253
- **Regimen assignment join key:** `(patient_id, treatment_type, episode_number)` — lines 346, 354
- **Chemo context join key:** `(patient_id, episode_number)` — lines 692, 698
- **Temporal DX join key:** `(patient_id, treatment_type, episode_number)` — line 812

**Risk assessment:** `episode_number` is a within-window sequence number. It is VALID within a
single window's RDS (R/28 runs once per window against that window's own files, so each join is
self-consistent). It is INVALID across windows — episode 2 at 90 days is a different episode at
180 days after consolidation. Because the plan is to parameterise R/28 to accept a different input
RDS (the 180-day RDS), and R/28's joins are all internal to the data it reads, the episode_number
joins are safe: they will operate on the 180-day episode numbering when given the 180-day RDS.

**Alternative join key available:** `episode_start` is present in the episodes table (verified at
line 780 of R/28: `select(patient_id, treatment_type, episode_number, episode_start, episode_stop)`).
For any future cross-window comparison, join on `(patient_id, treatment_type, episode_start)` —
not on `episode_number`.

**Conclusion:** No join-key change is required in R/28 for the 180-day enrichment pass. The
parameterisation approach (pass a different input RDS, get self-consistent episode_number joins)
is safe per the CONTEXT.md D-04 guidance.

---

## 90-Day Fill Rates (parity benchmark)

HiPerGator run required — Rscript not available on Windows dev box. The CONTEXT.md states the
90-day range is 32–66% across the six columns. Exact per-column figures must be obtained on
HiPerGator before Plan 03 acceptance testing.

| Column | Fill Rate (%) |
|---|---|
| drug_group | [HiPerGator run required — CONTEXT.md: 32–66% range] |
| code_type | [HiPerGator run required] |
| source_table | [HiPerGator run required] |
| episode_dx_codes | [HiPerGator run required] |
| episode_dx_categories | [HiPerGator run required] |
| episode_dx_7day_confirmed | [HiPerGator run required] |

These figures are the D-04 parity benchmark: 180-day fill rates must be >= 90-day fill rates
for the episode_dx_* columns (consolidation means more encounters per episode, more chances to
pick up a DX code). A 180-day fill rate materially below the 90-day rate signals a bad join key.

See "HiPerGator verification scripts" section for the R code to execute.

---

## Death Anomaly

HiPerGator run required. Context from CONTEXT.md (Section 3):

- Death episodes: 1,300 at 90 days, 1,299 at 180 days.
- Death is a single event per patient — count should be identical across windows.
- A drop of one means a patient has two death records 90–180 days apart that merged into a single
  episode at the wider window. This is a data-quality problem in the death records.

**Quantification pending HiPerGator run.** The R script to enumerate multi-death patients is in
"HiPerGator verification scripts" below.

Placeholder structure to be filled after HiPerGator run:

- Patients with > 1 death episode at 90 days: [N — run Step 5 on HiPerGator]
- Per-patient date gaps: [list from Step 5 output]
- source_hint values: [list from Step 5 output]
- Affects survival analyses: Yes — a duplicate death date in treatment_episodes.rds will double-count
  the patient in any survival analysis that pivots on death events. Flag for review before any
  survival curve work. Do NOT fix in Phase 143 — this is a data-quality issue that must be
  investigated separately.

---

## Patient Count Reconciliation

HiPerGator run required. Context from CONTEXT.md (Section 4):

- The Phase 142 review's patient-count line was truncated ("90-day: 8,339 unique patients;
  180-day: 8,st one episode…") and the 180-day figure is unverified.
- Proton Therapy held at 93 across windows (invariant — expected).
- Death did not hold (1,300 → 1,299 — anomaly documented above).

Placeholder structure to be filled after HiPerGator run:

- n_distinct(patient_id) at 90d: [run Step 6 — expected ~8,339]
- n_distinct(patient_id) at 180d: [run Step 6]
- Equal: [PASS / FAIL — halt and investigate if FAIL]
- Death episodes: 90d=1,300, 180d=1,299 (ANOMALY — must not be marked as consolidation success)
- Proton Therapy episodes: 90d=93, 180d=93 (expected invariant)
- Per-type episode count comparison: [paste Step 6 table output]

---

## Parameterisation Design

Decision: d-01b — enrichment runs for 180-day episodes.

R/28 is the sole producer of five of the six enrichment columns. It is not parameterisable in
its current form: `OUTPUT_RDS` and `DETAIL_RDS` are script-level constants (lines 98–99), not
function arguments. The script runs as a sourced file (`source("R/28_...", local = new.env(...))`),
so parameterisation means adding top-of-script overrides that callers can inject before sourcing.

### Proposed parameterisation shape for R/28

Add optional override variables at the top of R/28, before the OUTPUT_RDS / DETAIL_RDS
assignments. If the caller sets them before sourcing, R/28 uses the caller's paths; otherwise it
falls back to the CONFIG-constant defaults (preserving existing 90-day behaviour exactly):

```r
# ── Optional caller overrides (set before source("R/28...") to run against a different window) ──
# Default: NULL → use CONFIG$cache$outputs_dir / standard filenames (90-day behaviour)
if (!exists("R28_EPISODES_RDS"))   R28_EPISODES_RDS   <- NULL
if (!exists("R28_DETAIL_RDS"))     R28_DETAIL_RDS     <- NULL
if (!exists("R28_OUT_SUFFIX"))     R28_OUT_SUFFIX     <- ""   # "" = overwrite in place (90-day default)

OUTPUT_RDS <- if (!is.null(R28_EPISODES_RDS)) R28_EPISODES_RDS else
              file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds")
DETAIL_RDS <- if (!is.null(R28_DETAIL_RDS)) R28_DETAIL_RDS else
              file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds")
```

The 180-day caller (R/142 or a new orchestration step) sets:

```r
R28_EPISODES_RDS <- file.path(CONFIG$cache$outputs_dir, "treatment_episodes_180.rds")
R28_DETAIL_RDS   <- file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail_180.rds")
R28_OUT_SUFFIX   <- "_180"
source("R/28_episode_classification.R", local = new.env(parent = globalenv()))
```

### Rules enforced by this design

1. **One definition per column.** drug_group is computed only in R/28. The 180-day pass reuses
   the identical computation, not a copy. No drift is possible.
2. **90-day defaults unchanged.** When R28_EPISODES_RDS is NULL, OUTPUT_RDS resolves to the same
   string as before. Re-running the 90-day path is bit-identical.
3. **Window-dependent logic: none found.** The grep for `\b90\b` and `GAP_THRESHOLD` in R/28
   returned no matches. The enrichment logic (drug lookups, DX joins, regimen detection) does not
   assume a 90-day episode cap. Safe to pass 180-day episodes directly.
4. **episode_number join safety.** R/28's joins operate internally on the RDS it reads. When given
   the 180-day RDS, episode_number refers to 180-day episode numbering throughout — no cross-window
   mismatch.

### R/52 — episode_dx_7day_confirmed

R/52 computes `episode_dx_7day_confirmed` at export time from `cancer_summary.csv` (Phase 115
logic, lines 421–459). R/142 already has the identical Phase 115 block (lines 298–326). This
column requires no R/28 parameterisation — it is computed by the exporter, not stored in the RDS.
R/142's existing Phase 115 block will populate it once R/28's enrichment runs first.

### What Plan 02 must do

1. Add the override-variable block to R/28 (top of script, before OUTPUT_RDS assignment).
2. Add an orchestration call in R/142 (or a new R/143_enrich_180.R) that sets the overrides and
   sources R/28.
3. Verify 90-day output is bit-identical before and after the R/28 change.
4. Run the D-04 fill-rate parity check (Step 4 script below) to confirm 180-day columns populate.

---

## HiPerGator verification scripts

The following R scripts could not be run on the Windows dev box (no Rscript). Execute these on
HiPerGator and paste results back into the relevant sections above.

### Step 4 — 90-day fill rates

```r
# Run on HiPerGator. Paste output into "90-Day Fill Rates" table above.
source("R/00_config.R")
g90 <- readr::read_csv("output/gantt_episodes.csv", show_col_types = FALSE)
cols <- c("drug_group", "code_type", "source_table",
          "episode_dx_codes", "episode_dx_categories", "episode_dx_7day_confirmed")
fill <- vapply(cols, function(c) mean(!is.na(g90[[c]]) & trimws(g90[[c]]) != ""), numeric(1))
cat("90-day fill rates:\n")
print(round(100 * fill, 1))
```

### Step 5 — Death anomaly

```r
# Run on HiPerGator. Paste output into "Death Anomaly" section above.
source("R/00_config.R")
ep90 <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))
d90  <- dplyr::filter(ep90, treatment_type == "Death")

multi <- d90 %>%
  dplyr::count(patient_id, name = "n_death_episodes") %>%
  dplyr::filter(n_death_episodes > 1)
cat(sprintf("Patients with > 1 death episode at 90d: %d\n", nrow(multi)))
print(multi)

det90 <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds"))
det90 %>%
  dplyr::filter(treatment_type == "Death", patient_id %in% multi$patient_id) %>%
  dplyr::arrange(patient_id, treatment_date) %>%
  dplyr::select(patient_id, treatment_date, triggering_code, ENCOUNTERID, source_hint) %>%
  print(n = Inf)
```

### Step 6 — Patient count reconciliation

```r
# Run on HiPerGator. Paste output into "Patient Count Reconciliation" section above.
source("R/00_config.R")
ep90  <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))
ep180 <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes_180.rds"))

n90  <- dplyr::n_distinct(ep90$patient_id)
n180 <- dplyr::n_distinct(ep180$patient_id)
cat(sprintf("patients: %d at 90d, %d at 180d\n", n90, n180))
if (n90 != n180) warning("FAIL: patient count changed between windows — investigate before enrichment")

dplyr::full_join(
  dplyr::count(ep90,  treatment_type, name = "n_ep_90"),
  dplyr::count(ep180, treatment_type, name = "n_ep_180"),
  by = "treatment_type"
) %>%
  dplyr::mutate(pct_change = round(100 * (n_ep_180 - n_ep_90) / n_ep_90, 1)) %>%
  print()
```

### Step 4b — Post-enrichment parity check (run after Plan 02 executes)

```r
# D-04 acceptance test. Run after R/28 enrichment of the 180-day RDS.
source("R/00_config.R")
g90  <- readr::read_csv("output/gantt_episodes.csv",     show_col_types = FALSE)
g180 <- readr::read_csv("output/gantt_episodes_180.csv", show_col_types = FALSE)
cols <- c("drug_group", "code_type", "source_table",
          "episode_dx_codes", "episode_dx_categories", "episode_dx_7day_confirmed")

fillrate <- function(d, c) mean(!is.na(d[[c]]) & trimws(d[[c]]) != "")
cmp <- data.frame(
  column   = cols,
  fill_90  = round(100 * vapply(cols, function(c) fillrate(g90,  c), numeric(1)), 1),
  fill_180 = round(100 * vapply(cols, function(c) fillrate(g180, c), numeric(1)), 1)
)
cmp$delta <- cmp$fill_180 - cmp$fill_90
print(cmp)
if (any(cmp$fill_180 == 0)) {
  warning("FAIL: one or more 180-day columns are still zero — enrichment did not populate them")
} else {
  message("PASS: all six enrichment columns populated in 180-day file")
}
# Expected direction for episode_dx_* columns: fill_180 >= fill_90
# A materially lower 180-day rate signals a bad join key (cross-window episode_number misuse)
```
