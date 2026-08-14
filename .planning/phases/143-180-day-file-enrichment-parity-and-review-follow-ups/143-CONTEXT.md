# PHASE 143 — 180-Day File: Enrichment Parity and Review Follow-ups

Context spec for the Claude Code CLI. Follows Phase 142, which produced
`gantt_episodes_180.csv` / `gantt_detail_180.csv`.

**Four items, from the Phase 142 output review:**

1. Six enrichment columns are empty in the 180-day file (the substantive item).
2. `Death` episodes dropped 1,300 → 1,299, which should be impossible.
3. The patient-count comparison in the review was truncated and is unverified.
4. The episode rule is now provable from the data and should be written down.

Items 2 and 3 are data-integrity checks and run first — if the patient count is not identical
across windows, the enrichment work is premature.

---

## 0. Rules for the planner

1. **Discover, never assume.** Do not name a script, function, path constant, or column you have
   not confirmed by reading the file. Task 1 is read-only.
2. **Do not assume the enrichment scripts are parameterisable.** Establish it. If they hardcode the
   90-day RDS path, that is the finding, and the fix is a parameter — not a copy of the script.
3. **Do not create `R/60_..._180.R` style duplicates.** Copied enrichment logic will drift from the
   90-day version and silently produce two different definitions of `drug_group`.
4. **Full columns are not the goal.** The 90-day file itself fills these columns at 32–66%. Parity
   with the 90-day fill rate is the target, not 100%.
5. **Row counts and patient counts are invariants.** Widening the window merges episodes. It does
   not create or destroy patients, and it must not change single-event types.

Project conventions that apply:

- Patient key column is `ID`; renamed at load in `R/01`.
- Scripts are numbered under `R/`, orchestrated by `R/39_run_all_investigations.R`, sourced with
  `local = new.env(parent = globalenv())`.
- `R/88` is the comprehensive smoke test and must pass.
- Runs execute on HiPerGator; the Windows dev box has no `Rscript`, so parse checks only.

---

## 1. BLOCKING — what is the 180-day file for?

The answer decides the whole phase and cannot be inferred from the code. Ask the colleague:

> Are you comparing episode **boundaries** — how many episodes, how long, how they consolidate —
> or episode **content** — which drugs and diagnoses fall inside each episode?

| Answer | Decision |
|---|---|
| **Boundaries** | Drop the six columns from the 180-day file entirely (D-01a). Document the schema difference. Phase ends after Tasks 2–4. |
| **Content** | Run the enrichment for 180 days (D-01b). Full phase. |
| **Unsure / both** | Default to running the enrichment. A file with the columns present and populated serves both readings; a file with them blank serves neither. |

**Weight on the default:** `drug_group` is one of the six blank columns, and Phase 142 existed
partly because the colleague reported a *drug name* problem. If they open the 180-day file to check
whether the Vinblastine duplicate resolved and how regimens distribute, the blank space sits
directly on the question they asked. Episode counts alone will not answer it.

---

## 2. Task 1 — Discovery (read-only)

Produce `143-DISCOVERY.md`. No edits.

### 2a. Locate the six enrichment producers

```bash
grep -rn "drug_group\|code_type\|source_table\|episode_dx_codes\|episode_dx_categories\|episode_dx_7day_confirmed" R/ --include=*.R -l
grep -rn "treatment_episodes\.rds\|treatment_episode_detail\.rds" R/ --include=*.R
```

The review names R/60–63, R/91 and R/112. Confirm that list; there may be more or fewer.

### 2b. Classify each producer

Fill this table. Every row needs a disposition.

| Script | Columns it produces | Reads 90-day RDS via | Writes to | Parameterisable? |
|---|---|---|---|---|
| | | hardcoded path / constant / argument | fixed name / constant | yes + how, or no + why |

For each, record specifically:

- Does it take the episodes RDS path as an argument, read a `CONFIG$` constant, or hardcode it?
- Does it write to a fixed output name, or derive one?
- Does any logic depend on the 90-day window itself — a hardcoded `90`, a `GAP_THRESHOLD`
  reference, or an assumption that episodes are at most 90 days long?

That last question is the one that decides whether parameterisation is safe. An enrichment step
that assumes a maximum episode length will silently misbehave on 179-day episodes.

```bash
grep -rn "\b90\b\|GAP_THRESHOLD" R/60*.R R/61*.R R/62*.R R/63*.R R/91*.R R/112*.R
```

### 2c. Record the 90-day fill rates as the parity target

```r
source("R/00_config.R")
g90 <- readr::read_csv("output/gantt_episodes.csv", show_col_types = FALSE)
cols <- c("drug_group","code_type","source_table",
          "episode_dx_codes","episode_dx_categories","episode_dx_7day_confirmed")
fill <- vapply(cols, function(c) mean(!is.na(g90[[c]]) & trimws(g90[[c]]) != ""), numeric(1))
print(round(100 * fill, 1))
```

These percentages are the benchmark in D-04. Record them in `143-DISCOVERY.md`.

---

## 3. Task 2 — Death anomaly (run before the enrichment work)

`Death` episodes: 1,300 at 90 days, 1,299 at 180 days.

Death is a single event per patient. The count should be **identical** across windows. A drop of one
means a patient has two death records 90–180 days apart that merged into a single episode at the
wider window — which is a data-quality problem in the death records, not a consolidation success.

```r
source("R/00_config.R")
ep90 <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))
d90  <- dplyr::filter(ep90, treatment_type == "Death")

# Patients with more than one death episode at 90 days
multi <- d90 %>%
  dplyr::count(patient_id, name = "n_death_episodes") %>%
  dplyr::filter(n_death_episodes > 1)
print(multi)

# The underlying dates for those patients
det90 <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds"))
det90 %>%
  dplyr::filter(treatment_type == "Death", patient_id %in% multi$patient_id) %>%
  dplyr::arrange(patient_id, treatment_date) %>%
  dplyr::select(patient_id, treatment_date, triggering_code, ENCOUNTERID, source_hint) %>%
  print(n = Inf)
```

Record in `143-DISCOVERY.md`: how many patients have multiple death dates, what the gaps are, and
which source each date came from (`source_hint`). Two death dates for one patient usually means two
source tables disagree, or a death date and a death-related encounter both matched the trigger.

**Do not fix it in this phase.** Report it, and flag whether it affects survival analyses elsewhere
in the pipeline — a duplicate death date is a larger problem than a Gantt column.

`Death` and `Proton Therapy` should both be invariant across windows. `Proton Therapy` held at 93;
`Death` did not. Add both as assertions in D-05.

---

## 4. Task 3 — Patient count reconciliation

The review's patient-count line was truncated (`"90-day: 8,339 unique patients; 180-day: 8,st one
episode…"`) and the 180-day figure is unverified.

```r
ep90  <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"))
ep180 <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episodes_180.rds"))

n90  <- dplyr::n_distinct(ep90$patient_id)
n180 <- dplyr::n_distinct(ep180$patient_id)
cat(sprintf("patients: %d at 90d, %d at 180d\n", n90, n180))
stopifnot("patient count changed between windows" = n90 == n180)

# Per-type invariants
dplyr::full_join(
  dplyr::count(ep90,  treatment_type, name = "n_ep_90"),
  dplyr::count(ep180, treatment_type, name = "n_ep_180"),
  by = "treatment_type"
) %>%
  dplyr::mutate(pct_change = round(100 * (n_ep_180 - n_ep_90) / n_ep_90, 1)) %>%
  print()
```

A patient count that moves means a filter changed, not the window. Halt and investigate.

---

## 5. Task 4 — Enrichment parity (D-01b path only)

### D-02 · Parameterise, do not duplicate

For each producer identified in Task 1b, add an episodes-source parameter and an output suffix.
The 90-day call keeps its current defaults so nothing about the existing pipeline changes:

```r
# example shape — adapt to each script's actual structure
enrich_episodes <- function(
    episodes_rds = file.path(CONFIG$cache$outputs_dir, "treatment_episodes.rds"),
    detail_rds   = file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds"),
    out_suffix   = ""            # "" for 90-day, "_180" for the 180-day pass
) {
  ...
  out_path <- file.path(CONFIG$cache$outputs_dir,
                        sprintf("episode_enrichment%s.rds", out_suffix))
  ...
}
```

Rules:

- **One definition per column.** If `drug_group` is computed in two places after this change, the
  change is wrong.
- Defaults reproduce current 90-day behaviour exactly. Verify by re-running the 90-day path and
  diffing the output against the pre-change file.
- If Task 2b found window-dependent logic in a producer, fix or parameterise that too — do not
  simply pass a different RDS to a function that assumes 90-day episodes.

### D-03 · Wire the 180-day pass into the export

`R/142_gantt_180_export.R` gains the enrichment join, mirroring `R/52`. Same column order, same
semicolon separator.

### D-04 · Fill-rate parity is the acceptance test, not fullness

```r
g90  <- readr::read_csv("output/gantt_episodes.csv",     show_col_types = FALSE)
g180 <- readr::read_csv("output/gantt_episodes_180.csv", show_col_types = FALSE)
cols <- c("drug_group","code_type","source_table",
          "episode_dx_codes","episode_dx_categories","episode_dx_7day_confirmed")

fillrate <- function(d, c) mean(!is.na(d[[c]]) & trimws(d[[c]]) != "")
cmp <- data.frame(
  column   = cols,
  fill_90  = round(100 * vapply(cols, function(c) fillrate(g90,  c), numeric(1)), 1),
  fill_180 = round(100 * vapply(cols, function(c) fillrate(g180, c), numeric(1)), 1)
)
cmp$delta <- cmp$fill_180 - cmp$fill_90
print(cmp)
stopifnot("enrichment did not populate the 180-day file" = all(cmp$fill_180 > 0))
```

**Expected direction:** 180-day fill rates should be **greater than or equal to** the 90-day rates
for the episode-level aggregates (`episode_dx_*`). Consolidation puts more encounters inside each
episode, so an episode has more chances to pick up a diagnosis code. A 180-day fill rate materially
*below* the 90-day rate means the join key is wrong — most likely joining on episode number, which
is not stable across windows.

**Join on `(patient_id, treatment_type, episode_start)` or on encounter ids — never on
`episode_number` alone.** Episode 2 at 90 days is not episode 2 at 180 days. This is the single most
likely way this task produces a plausible-looking but wrong file.

### D-01a · Alternative if the answer in §1 was "boundaries"

Drop the six columns from both 180-day CSVs and write a companion
`output/gantt_180_README.txt` stating:

```
gantt_episodes_180.csv / gantt_detail_180.csv

Episode boundaries recomputed at a 180-day window. Six enrichment columns present in the
90-day files are omitted here: drug_group, code_type, source_table, episode_dx_codes,
episode_dx_categories, episode_dx_7day_confirmed. These are produced by downstream
enrichment steps that run against the 90-day episodes only. Compare episode counts,
durations and consolidation against gantt_episodes.csv; use the 90-day file for
drug-group and diagnosis content.
```

Omitting a column and documenting it is honest. A present-but-empty column is not — it reads as
data loss and breaks any filter or group-by on the field.

---

## 6. Task 5 — Document the episode rule

The 142 output settles a question that was previously ambiguous. Chemotherapy episode length:

| Window | Max | Median |
|---|---|---|
| 90-day | 89 | 56 |
| 180-day | 179 | 100 |

Both maxima sit exactly one day under the threshold. That is only possible under a **window
measured from episode start**; a gap-between-doses rule produces episodes of unbounded length.

Write this into the companion README and, if any workbook accompanies these files, into a `KEY`
sheet placed as the leftmost tab:

```
Episode definition: an episode covers up to N days from its first treatment date. A treatment
date falling N or more days after the episode start begins a new episode. Episodes therefore
never exceed N-1 days in length. This is a fixed window from episode start, NOT a rule about
the gap between consecutive treatments — under a gap rule an episode could span years.
N = 90 in gantt_episodes.csv and 180 in gantt_episodes_180.csv.
```

Add the corresponding sentence to `CONTEXT.md` D-01 in the Phase 142 folder, replacing the asserted
version with one that cites the observed maxima as evidence.

---

## 7. Acceptance criteria

- [ ] `143-DISCOVERY.md` exists with the producer disposition table, the 90-day fill rates, and the
      death-anomaly findings, each citing file and line.
- [ ] Patient count identical across windows; `Death` and `Proton Therapy` episode counts identical.
- [ ] The multi-death-date patients are enumerated with their dates and `source_hint` values, and a
      recommendation is recorded on whether it affects survival analyses.
- [ ] **Either** the six columns are populated in the 180-day file at fill rates at or above the
      90-day rates, **or** they are removed and documented in a companion README — not left blank.
- [ ] No enrichment column is computed in more than one place.
- [ ] The 90-day outputs are byte-identical to their pre-change versions apart from the Phase 142
      drug-name fix.
- [ ] Enrichment joins do not use `episode_number` as a key.
- [ ] Episode-definition text present in the README and any KEY sheet.
- [ ] `R/88` passes; `R/39` runs clean.

---

## 8. Anti-patterns

| Do not | Because |
|---|---|
| Copy `R/60` to `R/60_180` and change the paths | Two definitions of `drug_group` that will drift |
| Join enrichment on `episode_number` | Episode 2 at 90 days is a different episode at 180 days |
| Treat "all columns full" as the goal | The 90-day file fills these at 32–66%; parity is the target |
| Leave the columns present and blank | Indistinguishable from missing data; breaks filters silently |
| Report the `Death` −1 as successful consolidation | Death is one event per patient; the drop is a data-quality signal |
| Quote the review's patient-count line | It was truncated mid-number and the 180-day figure is unverified |
| Pass a 180-day RDS to a producer that assumes ≤90-day episodes | Silent misbehaviour on long episodes; check first (Task 2b) |
| Change any 90-day default while parameterising | The existing pipeline must be bit-identical afterwards |

---

## 9. Reply to the colleague

Once Tasks 2–4 are done, the answer is short:

- Episode counts by treatment type at both windows, with the consolidation concentrated in
  Chemotherapy (−27%) and Immunotherapy (−28%) and single-event types unchanged.
- Patient count identical across windows.
- Whether the enrichment columns are now populated, or removed with the reason.
- One sentence on what "180-day episodes" means — a 180-day cap from episode start, not a gap rule,
  evidenced by the 179-day maximum.
- A flag on the duplicate death dates, since that touches more than this file.
