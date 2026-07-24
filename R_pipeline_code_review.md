# R Pipeline Code Review — HiPerGator "Insurance Investigation"

**Reviewed:** 2026-07-23 · **Scope:** all R code in Google Drive (≈115 pipeline scripts `00`–`112`, plus the 14 `utils_*.R` helper modules) · **Codebase:** PCORnet CDM oncology pipeline for a Hodgkin lymphoma (HL) cohort.

---

## Executive summary

The pipeline is large, well-documented, and mostly sound in its core logic. The review found no evidence of systematic analytic failure, but it did surface a handful of **defects that either crash a script outright or silently publish wrong numbers**, plus a set of recurring patterns worth fixing once across the codebase.

The most urgent items:

- **Six scripts abort immediately** on a stray `n` token left in by an editor (`74`, `81`, `82`, `83`, `84`, `85`). One-character fix each, but each script currently does nothing.  
- **One published-output bug**: `46_cancer_summary_table.R` inflates every "Total Records" figure by the per-code patient count.  
- **One silently-inert clinical feature**: `28_episode_classification.R` filters on a treatment-type string (`"Stem Cell Transplant"`) that never matches the value the rest of the pipeline uses (`"SCT"`), so the entire SCT-conditioning-context analysis is always empty.  
- **A data-integrity gap in the DuckDB ingest** (`03`) that can promote a database silently missing tables while reporting "13/13 passed."  
- **A shared anchor-date bug** in `47_cancer_summary_refined.R` that can corrupt or drop each patient's `first_hl_dx_date` — the value `48` and `49` both depend on.  
- **A repeated same-week overlap bug** (`67`→`68` and again `95`→`96`) that scrambles the source/date pairing in the detail files and breaks the downstream classification join.  
- Several **tests and validators that cannot fail** and therefore give false assurance (`81`, `82`/`83`, `88`, `96_validate_payer_dt`, `98_validate_r28_migration`).

Nothing here suggests the analysis needs to be thrown out — most defects are localized and have concrete one-to-few-line fixes. But the "green tests" caveat matters: several of the smoke tests and migration validators pass regardless of whether the thing they check is actually correct, so passing CI is not currently strong evidence.

> **Two loose ends to confirm.** (1) `suppress_small()`, `clean_multi_value()`, and `union_field()` — used by the HIPAA-suppression and multi-value scripts — were **not found in any of the 14 `utils_*.R` modules**. They're presumably defined in `00_config.R` or inline in a script (`clean_multi_value` is referenced as "reused from R/52"); worth confirming they actually load. (2) The `utils` folder in Drive contains a couple of modules the SCRIPT\_INDEX didn't list (`utils_doi.R`, `utils_dt.R`, `utils_xlsx_lookups.R`), which is fine — just noting the index is slightly stale.

---

## Critical / high-severity findings (fix first)

| \# | Script(s) | Issue | Fix |
| :---- | :---- | :---- | :---- |
| 1 | `74`, `81`, `82`, `83`, `84`, `85` | A stray bare `n` on its own line right after `source("R/00_config.R")` throws `object 'n' not found` and **aborts the whole script** before any work runs. (`84`/`85` contain it three times.) Editor artifact. | Delete the stray `n` line in each file. |
| 2 | `28_episode_classification.R` | `filter(treatment_type == "Stem Cell Transplant")` — every other script labels this type `"SCT"`, so this matches nothing: `sct_dates` is always empty, `is_sct_conditioning_context` is always FALSE, `days_to_nearest_sct` always NA. The Phase-93 SCT-conditioning feature is completely inert. | Change to `treatment_type == "SCT"`. |
| 3 | `03_duckdb_ingest.R` | A table that fails to write (missing RDS → `next`, or write/assert error → inner `tryCatch` returns FALSE) does **not** abort; verification only iterates over tables that *did* ingest, so `all_ok` stays TRUE and the atomic swap promotes a DB silently missing tables. The final summary is hardcoded `"{n}/{n} tables passed"` (always 13/13). | `stop()` on any table failure before the swap (discard the `.tmp`); assert `setequal(ingested, expected)` before promotion; report the real counts. |
| 4 | `46_cancer_summary_table.R` | `total_records` is computed by left-joining a per-**code** record count onto a patient-**code** grain frame and then `sum()`\-ing, so each code's records are multiplied by its patient count. **Every "Total Records" figure (and the TOTAL row) is overstated.** | Collapse to distinct code-level counts before summing (e.g. aggregate `dx_record_counts` by category directly, not through the patient-grain frame). |
| 5 | `47_cancer_summary_refined.R` | `first_hl_dx_date = min(DX_DATE)` is computed **before** sentinel cleaning, and only exact year `1900` is nullified afterward. A patient with a real HL date plus a `1900-01-01` placeholder gets `min = 1900` → nullified → **loses their anchor entirely** and drops out of all downstream pre/post analysis; a `1901–1909` sentinel survives as the anchor. `48` and `49` both inherit this. | Filter `DX_DATE >= 1910-01-01` (using the same `SENTINEL_CUTOFF` as `48`/`49`) **before** the `min()`; drop the post-hoc `== 1900` nullify. |
| 6 | `67`→`68` and `95`→`96` | Same-week overlap: after `source_1/source_2 <- pmin/pmax(...)`, the code does **not** swap `admit_date_1/2` to match, so for \~half of pairs the (source, date) correspondence is scrambled in the `*_same_week_detail*.csv`. `68`/`96` then `left_join` back to ENCOUNTER on `(ID, date, source)` and get NA → those pairs are misclassified (pushed to Distinct/Partial) and near-duplicate pairs are undercounted by `distinct()`. | Reorder the two `(date, source)` tuples as a unit (or build `source_combo` for grouping while leaving `source_1/2` bound to their original dates). |
| 7 | `89_generate_reference_manual.R` | `parse_script_header()` sets `header_end` to the **2nd** `# ===` bar, but headers wrap the title in bars at lines 1 and 3, so only the 3 title lines are captured. Every Purpose/Inputs/Outputs/Dependencies/Requirements field parses as "Not documented" → the generated manual is content-empty. | Anchor `header_end` to the closing bar of the field block (3rd `===` / first non-comment line). |
| 8 | `101_gantt_lifespan_collapse.R` | In one `summarise()`, `episode_start = min(episode_start)` runs first and shadows the column, so `age_at_episode = age_at_episode[which.min(episode_start)]` always resolves to index `1` — the first row in input order, **not** the earliest-start episode. Wrong age whenever a group's first input row isn't its earliest start. | Compute `age_at_episode` before reassigning `episode_start`, or index against a separately-named min. |

---

## Cross-cutting patterns (each appears in several scripts)

**A. Record-count vs. distinct-patient confusion.** Columns labeled "Patients" or "Total Records" are produced by summing per-code counts across codes/categories, so patients (or records) seen under multiple codes are counted repeatedly. Appears in `23`, `33` (CODE-03 summary), `43`/`44` (TOTAL rows), `46` (finding \#4 — the one that actually corrupts a published number), `50` (grand total), `91`, `100` (Sheet 1). Most are cosmetic-to-moderate; `46` is the high-severity one. Fix by de-duplicating to the intended grain (`n_distinct(ID)` / distinct code) before totaling.

**B. Dotted-vs-undotted and case normalization drift.** `13_survivorship_encounters.R` matches HL codes **dotted-only**, while `10`/`14` deliberately match both dotted and undotted (`C8100`) — so at an undotted-coding site, patients enter the cohort but their survivorship levels silently collapse to zero. `42_build_code_descriptions.R` keeps dotted keys (`"Z51.11"`) that never match dot-stripped consumers. `utils_cancer.R` (`classify_codes`/`is_cancer_code`) and `utils_doi.R` **don't `toupper()`**, unlike `utils_icd.R::normalize_icd()` — a lowercase code passes the DoI gate but classifies to NA. Standardize all code matching on one normalizer (strip **all** dots \+ `toupper` \+ dotted/undotted union).

**C. `^[CD]` neoplasm filter over-includes D50–D89.** `40`, `43`, `44`, `46` filter neoplasms with `str_detect(DX, "^[CD]")`, which admits anemias/cytopenias/neutropenia (D50–D89) — common in HL/chemo patients — into an "Unclassified" neoplasm bucket. `45` already uses the correct `is_cancer_code()`. Use `"^C|^D[0-4]"` or route through `is_cancer_code()` everywhere.

**D. External-API "transient error" treated as a permanent miss.** `21_investigate_unmatched.R` has **no retry/backoff at all** (unlike `22`, which uses `httr2::req_retry`), so a 429/503 becomes a permanent `error:` status. `27`, `105`, and `108` **retry only 429/503/504** and cache timeouts/500/502 as genuine "not found," permanently poisoning the cache / dropping codes from a one-time crosswalk build. Classify error-vs-miss separately, retry transport errors, and don't persist transient failures.

**E. Tests and validators that cannot fail (false green).** `81` `coerce_types()` normalizes DuckDB→RDS types *before* `waldo::compare()`, masking real type divergence; `82`/`83` chase a "≥3× on 3 of 5 scripts" target while `82` benchmarks only **one** script (structurally unreachable); `88` folds dozens of skipped/`check(..., TRUE)` no-ops into the pass count and has an inverted `cause_of_death` "drop" check that passes on presence; `96_validate_payer_dt.R`'s FLM-override test uses a fixture that's already Medicaid, so the override could be a no-op and still pass; `98_validate_r28_migration.R` compares the output file to a baseline copied from itself, so re-running without regenerating passes trivially. Net: **a passing smoke/validation run is currently weak evidence.** Separate skip counters from pass counters; use fixtures/tolerances that force the checked behavior to actually matter.

**F. In-place `00_config.R` rewriting is fragile.** `21`, `22`, `50`, and `98` programmatically edit `R/00_config.R` with regex that only handles multi-line `c(` blocks and can be broken by a `"` inside a comment; failures are swallowed by a parse/source guard, so **newly-discovered codes are silently never added**. Move to a data-driven config (a CSV/RDS the config reads) instead of source-mutation.

**G. Silent `NA`/sentinel/impossible-date gaps.** `53_death_date_validation.R` (the impossible-date gatekeeper) has **no death-before-birth check** and emits negative `age_at_death` unflagged; `14` can produce `Inf` enrollment durations from `min/max(..., na.rm=TRUE)` on all-NA; `31` doesn't sentinel-guard `episode_start`; `93` drops NA treatment flags out of the "no-treatment" group. Add the missing guards / use the NA-safe `min_or_na`/`max_or_na` helpers consistently.

**H. Grain mislabels (episode vs. encounter vs. patient-date).** `56` (`encounter_count` is actually episode count), `57_explore_dx_deduplication` (same), `62` (`date_tier_detail` is patient×type×episode×date, not "one row per patient per date," so summary double-counts concurrent-treatment dates), `67` (`n_total_encounters` double-counts dates used in both roles). Rename columns or aggregate to the documented grain.

---

## Findings by area (medium / low detail)

### Foundation & config (`00`–`03`)

- `00_config.R` — **Med:** rituximab J-codes `J9310/J9311/J9312` are in `chemo_hcpcs` **and** `DRUG_GROUPINGS` Chemotherapy, contradicting the DoI design that keeps rituximab out of chemo (double-classifies the DoI drug). **Med:** `date_range_max = 2025-03-31` but the data extract is `20250915` — valid Apr–Sep 2025 encounters/deaths get flagged out-of-range and dropped by `01`'s validation. **Med:** utils are auto-sourced from a **relative** `"R/utils"` path and an empty result only `warning()`s (should `stop()`), so a wrong SLURM cwd silently loads zero helpers and fails later with opaque errors. Low: case-sensitive `"\\.R$"` source pattern; `supportive_care_*` name-split mis-buckets in `LOOKUP_TABLES_DT`; stale count comments; a few invalid/placeholder codes (`C81.xA` remission codes, HCPCS `224576`, `tsh_hcpcs`).  
- `01_load_pcornet.R` — **Med:** the date-column regex catches `DEATH_DATE_IMPUTE` (a B/D/M/N/Y flag), which `parse_pcornet_date()` silently turns all-NA, destroying the flag. Low: cache staleness keyed on mtime only; tables always materialized even in DuckDB mode (contradicts header).  
- `02_harmonize_payer.R` — Med/Low: `detect_dual_eligible` tests "secondary missing → 0" before "has dual code → 1," so a primary-dual/blank-secondary patient is wrongly marked non-dual; dual `14x` codes can fall through the first-digit prefix to "Medicare." Low: header says it reads ENROLLMENT but it reads ENCOUNTER.  
- `03_duckdb_ingest.R` — see finding \#3. Also **Med:** the `file.remove` \+ `file.rename` swap opens a no-DB window and the rename return is unchecked (POSIX rename already overwrites atomically).

### Cohort (`10`–`14`)

- `10` — Low: `has_hodgkin_diagnosis` left-joins a lazy `tbl_dbi` into a local frame (needs `collect()`/`copy=TRUE`); it and `exclude_missing_payer` are effectively dead code (14 re-implements HL inline), a drift risk.  
- `11` — **Med:** `str_detect(PX, ...)` used **inside lazy DuckDB filters** for ICD-10-PCS chemo/radiation dates, whereas `10` deliberately materializes first to avoid a documented DuckDB translation gap — if the gap is real, first-treatment dates silently miss PCS-only patients.  
- `12` — clean.  
- `13` — **Med:** dotted-only HL match (pattern B above).  
- `14` — **Med:** the final `hl_cohort` retains `HL_VERIFIED == 0` ("Neither") patients (only enrollment is filtered), so any consumer treating it as "HL patients" without filtering `HL_VERIFIED == 1` includes non-HL subjects. Low: non-NA-safe `min/max` → possible `Inf` durations.

### Treatment analysis (`20`–`29`)

- `20` — **Med:** Immunotherapy `detect_unknown_codes()` compares full 7-char PX against CAR-T **prefixes** with `%in%`, so no known CAR-T code is ever excluded (re-emits already-counted codes as "unknown").  
- `21` — **Med:** no API retry/backoff (pattern D). Low: brittle positional NLM JSON parse; 773xx radiation codes fall through to "Unrelated."  
- `22` — **Med (silent data loss):** queries `RXNORM_CUI` on DISPENSING and MED\_ADMIN where that column doesn't exist; errors are swallowed → those sources contribute nothing. **Med:** checkpoint inhibitors (nivolumab/pembrolizumab) are in both the chemo and immuno regex, and `case_when` checks chemo first → always classified Chemotherapy. **Med:** `left_join` by `code` only can fan out if a code exists under two `code_type`s.  
- `25` — **Med:** episode splitting uses a window-from-start (`date[i] - episode_start >= 90d`) but the file's own WHY-comment says "gaps \>90 days," so a continuous \~6-month ABVD course is chopped into multiple "episodes." **Med:** Proton Therapy missing from `TREATMENT_TYPE_COLORS` → `wb_color(NULL)` hard-errors if config includes Proton. Low: TR dates parsed with base `as.Date`, not `parse_pcornet_date`.  
- `26` — **Med:** `source_hints` (built from `distinct(code, hint)`, can be \>1/code) is pasted alongside `triggering_codes` (1/code); the comma-lists misalign whenever a code comes from both an encounter-bearing and a MED\_ADMIN/DISPENSING source, and `28` then nulls the whole episode's source hint — defeating the Phase-124 override.  
- `27` — Low: retries only 429/503/504 (pattern D).  
- `28` — see finding \#2. Low: temporal-fallback tie-break can prefer a nearer non-Hodgkin code over a Hodgkin one.  
- `29` — Low: patients with missing/unparseable birth dates get `age = NA`, silently failing `>= 21` and dropping from first-line eligibility.

### Investigations (`30`–`39`)

- `30`, `32`, `36` — clean.  
- `33` — **Med:** CODE-03 `Patient_Count` counts diagnosis **records**, not distinct patients (log uses `n_distinct(ID)`, xlsx disagrees). Low: `sct_proc` filter ignores `PX_TYPE`.  
- `34` — **Med:** dual-code numerator comes from **all** HL-coded patients but the denominator is the confirmed cohort — a population mismatch, and the console prints yet a third rate.  
- `35` — Low: `1:nrow(...)` / `1:min(...)` reverse-sequence footgun on empty frames.  
- `37.Rmd` — **Med:** reads `code_verification.xlsx` "Summary" whose merged-title layout means the `Investigation` column doesn't exist, so the guard silently renders garbled rows.  
- `38` — Low: manifest lists itself as MISSING (checked before write) and omits `death_cause_quality.xlsx`.  
- `39` — **High (ordering):** runs `101`/`104` (which consume `gantt_episodes.csv`/`gantt_lifespan.csv`) in Stage 2, but the only producer `52` doesn't run until Stage 4; `run_script()` swallows the error so the deliverables are silently omitted. Low: `58_` prefix collision; `03` ingest runs before `26`/`28`/`47` produce their RDS.  
- `31` — Low: `episode_start` not sentinel-guarded.

### Cancer site (`40`–`53`)

- `40`,`43`,`44`,`46` — `^[CD]` over-inclusion (pattern C); `43`/`44`/`46` TOTAL-row double counts (pattern A); `46` `total_records` inflation (finding \#4). `40` also runs ICD-O-3 topography through the ICD-10-CM classifier (C77/C42 divergence).  
- `41`, `45` — clean (`45` uses the correct `is_cancer_code`).  
- `42` — Low: dotted keys never match dot-stripped consumers (pattern B).  
- `47` — finding \#5.  
- `48` — **Med:** does **not** exclude HL anchor codes (C81 \+ 201.x) from the post-HL set, unlike `49`, so later HL rows count as "second cancers" (conflates HL recurrence with new malignancy). Inherits `47`'s anchor bug.  
- `49` — **Med:** category/total `both_count` is defined per-code (same code pre & post), so at category grain it isn't the pre∩post patient intersection and `pre + post − both` doesn't reconcile. Pre/post boundary logic itself is clean.  
- `50` — Low: grand-total `total_records` additive-with-overlap across category vectors; config auto-rewrite regex hazard.  
- `51`, `52_strange`, `54` — clean (minor `event_id` non-uniqueness in `51`).  
- `52_gantt_v2_export.R` — **Med:** descriptions containing commas are run through `clean_multi_value(sep=",")`, shattering each description into fragments that are then deduped/sorted independently — corrupting the Tableau column. Low: Death pseudo-rows mislabeled "Unlinked."  
- `53` — **Med:** no death-before-birth guard (pattern G); the impossible-date gatekeeper emits negative ages unflagged. Low: no 1900-birth sentinel; `DEATH_SOURCE = first()` may not match the chosen `min()` date.  
- `55` — **Med:** `n_long_chains` off-by-one (subtracts the cycle-info row even on a valid DAG where no such row was prepended). Low: category check only covers drug codes; missing-replacement-code pairs don't fail the verdict.

### Codes, death, drug groupings (`56`–`59`)

- `56` — **Med:** Table 2 `encounter_count` is actually an **episode** count (pattern H); Table 1 dedup contradicts the "no aggregation / row \= encounter" intent. Low: groups on raw comma-joined treatment strings (order/spacing variants fragment).  
- `57_drug_grouping_instances` — Low: `pivot_wider` \+ `rename(\`TRUE\`/\`FALSE\`)\` throws if a level is absent. (Tables themselves are correct encounter grain.)  
- `57_explore_dx_deduplication` — Low: episode-vs-encounter mislabel; before/after grouping keys differ so the "reduction" is understated.  
- `58_co_administration_analysis` — **Med/High:** co-admin pairs are filtered on **code** inequality, not drug identity, so one agent billed under two code systems within ±30 days is counted as co-administration (spurious `drug_A == drug_B` self-pairs). **Med:** directional double-count in `n_instances` (A→B and B→A both counted for single-agent dates).  
- `58_code_reference_tables`, `59` — clean (Low: `59` counts no-encounter patients as "death is last").

### Payer & overlap (`60`–`69`, `76`)

- `60` — Low: modal-payer ties broken alphabetically by label, not tier priority.  
- `61`, `69` — clean.  
- `62` — **Med:** grain mismatch — "date-level" outputs are patient×type×episode×date, so concurrent treatments double-count calendar dates (pattern H).  
- `63` — **Med:** the ID-skip regex `ID$` also drops every `*_VALID` flag column the script claims to audit (the logical branch is dead).  
- `64`, `65` — **Med:** `assert_df_valid(pcornet$ENROLLMENT, ...)` validates a table the scripts never read (they use ENCOUNTER \+ DEMOGRAPHIC, left unvalidated); the assertion may reference a nonexistent `PAYER_TYPE_PRIMARY` on ENROLLMENT. Low: `"OT"` (Other) counted as missing payer; unparsed `year(ADMIT_DATE)`.  
- `66` — Low: magrittr dot gotcha `n_distinct(.$ID)` evaluates as `n_distinct(df, df$ID)` (right answer only because DEMOGRAPHIC is 1 row/patient).  
- `67`→`68` — finding \#6. Also `68` **Med:** same-date `sd_pairs` self-join makes N×M pairs per source (no collapse to one representative), over-weighting high-volume patient-dates in the per-site profile.  
- `76` — **Med:** TR-vs-claims overlap uses exact same-day equality, so a 1-day-apart registry record is counted "TR-only" and inflates the data-loss estimate that drives the TR-removal decision (inconsistent with the ±7-day tolerance used in `67`/`68`).

### Outputs & viz (`70`–`79`)

- `70`, `77`, `78` — clean.  
- `71` — Low: any ≤10-patient category (incl. "Radiation only") relabeled "Multiple treatments" (factually wrong for single-modality strata).  
- `72_generate_pptx.R` — **Med (×3):** `rename_payer` maps `NA → "Missing"` before the "No Payer Assigned" rows are computed with `sum(is.na(...))`, so slides 2/4/6/8/10–13 report **0.0%** unassigned while genuinely-unassigned patients are absorbed into "Missing" (contradicts the slide-1 glossary); slide-14 "Had Follow-up Encounters" is derived as the complement of a date-equality test, miscounting patients whose last encounter precedes a TR-sourced treatment date. Low: writes to CWD not `output/`; empty factor bins dropped; `ggplot2` never `library()`\-ed; stale `16_encounter_analysis.R` references.  
- `73` — Low: figures/messages labeled "phase24" inside the Phase 19/20 deck.  
- `74` — finding \#1 (stray `n` aborts the doc build). Low: output filenames don't match the documented paths.  
- `75` — **Med (×2):** Total/grand-total rows put an *encounter ratio* in a column that is *percent-of-patients* elsewhere (not comparable, plus double `*100/100` rescale); weighted histograms are labeled "Number of Patients" but bar height is encounters/dates. Low: unmapped payer categories silently coerced to NA and dropped.  
- `79` — Low: summary buckets overlap (in-reference blanks counted twice).

### Tests & smoke tests (`80`–`89`)

- Stray `n` aborts `81`–`85` (finding \#1). Validators that can't fail: `81`, `82`/`83`, `88` (pattern E). `89` empty manual (finding \#7).  
- `80` — Low: header says `waldo::compare` but uses `setequal`; 3 of 6 predicates run full-cohort, not the 100-patient sample.  
- `84` — **Med:** bare `walk()` used but purrr not attached → `could not find function "walk"` crash on any triggered branch (`85` correctly uses `purrr::walk`).  
- `86`, `run_88_smoke_to_log.R` — clean.  
- `87` — Low: broken-`source()` scan doesn't exclude smoke-test files (false positives); loose decade thresholds.  
- `test_phase78_human.R` — **Med:** `source()`s `88`, which calls `quit(status=1)` on failure and would kill the whole UAT process (`run_88` warns 88 must run as a subprocess). Low: hardcoded expected column counts.

### Ad-hoc diagnostics (`90`–`99`)

- `90` — Low: non-Date/character date columns silently skipped in the audit; missing-value loop flags all columns despite "\>10% required" comment.  
- `91` — **Med:** `n_future_dates_after` / `n_pre1900_dates_after` are all-table grand totals but attributed to single-source rows; "Future prescribing dates" `count_after` is a 0/1 boolean, not a count.  
- `92` — **Med:** the "TR record exists but no dx codes" branch is unreachable (earlier `n_diagnoses == 0` branches catch every such row) — exactly the population the gap analysis should surface is mislabeled.  
- `93` — Low: NA treatment flags dropped from the no-treatment group.  
- `94`, `95_validate_dt_infrastructure`, `99_compare_drug_resolution` — clean.  
- `95_multi_source_overlap_av_th`→`96_overlap_classification_av_th` — finding \#6 (AV+TH copy). Low: "AV,TH" scope is ambulatory \+ **telehealth** (not hospital), excluding inpatient — confirm intended.  
- `96_validate_payer_dt` — **Med:** FLM-override test fixture is already Medicaid, so the override could be a no-op and still pass (pattern E).  
- `97_payer_code_frequency_av_th` — **Med:** join-key asymmetry (`trimws` on one side only) and numeric coercion dropping leading zeros → real codes falsely tagged "NOT IN XLSX"; no uniqueness guard on the lookup (fan-out risk).  
- `97_validate_r60_migration` — clean (a genuinely independent parity compare).  
- `98_radiation_cpt_audit` — **Med:** config auto-add builds a trailing-comma line the `,$` stripper never matches → parse error → guard rejects → new codes never added (pattern F); nuclear-medicine therapy 79005+ falls into an unclassified gap. Low: overlapping sub-ranges misassign `ama_category`.  
- `98_validate_r28_migration` — **Med:** self-comparison false-pass (pattern E).  
- `99_claude_diagnostics` — Low: `sink()` not closed on error (swallows all later console output); NA counted as a distinct value.  
- `99_validate_gantt_consolidation` — Low: NA-category rows skipped in the `is_hodgkin` checks.

### Post-renumber investigations (`100`–`112`)

- `100` — Low: `demo_zip` not de-duplicated to one row/PATID before the encounter/episode joins (fan-out risk if a patient has \>1 ZIP).  
- `101` — finding \#8.  
- `102` — **Med:** when the DEATH\_CAUSE table is absent, the DIAGNOSIS-history proxy (documented "off by default") fires automatically, silently changing the column's meaning to "NHL in diagnosis history."  
- `103` — **Med:** `s1_coverage` is computed over the full DEATH\_CAUSE table (incl. blanks) while TR coverage counts only non-null, so the "proceed with Source 1" recommendation can fire when Source 1 has zero usable causes.  
- `104` — Low: doc says "3 renames," only 2 happen; relies on `101` having excluded pseudo-rows (worth an assert).  
- `105` — **Med (×2):** in-place xlsx append is hardcoded to column **G** while columns are otherwise detected by name — misplaces/overwrites if the sheet isn't exactly 6 columns; transient RxNav outages are cached as `api_miss` indistinguishably from genuine misses and never re-queried (pattern D).  
- `106` — **Med:** `zip9_change_only` compares ZIP9 and ZIP5 distinct-counts computed over **different row subsets** → misclassification feeding the headline stat; Sheet-4 tie-break patient counts are written **without `suppress_small()`** (a small-cell disclosure the rest of the project suppresses).  
- `107` — clean (Low: PRESCRIBING-absent overcount in the headline).  
- `108` — **Med:** transient lookup failures conflated with genuine "no RxCUI" and dropped from the one-time crosswalk → permanent silent loss (pattern D). Also `utils_treatment::normalize_ndc()` mis-pads non-4-4-2 NDC layouts (below), which feeds this crosswalk.  
- `109` — **Med:** D-06 `n_episodes_after = before + n_flagged` adds the single global flagged-patient count to **every** regimen row, so "after"/"delta" repeat a constant and totals don't reconcile.  
- `110` — **Med:** a fallback branch uses the `.` pronoun inside `summarise()` (undefined) and `.data[["patient_id"]]` errors instead of returning NULL for the `%||%` fallback — both on secondary code paths.  
- `111` — clean (safe `substr(...) %in%` pushdown, correct mutual-exclusivity hard-stop).  
- `112` — **Med:** `treatment_date` from the RDS is never coerced/asserted to `Date` before ±90-day window arithmetic (errors if character, off-by-a-day if POSIXct).  
- `filter_strange_death_csvs.R` — clean.

### Utility modules (`utils_*.R`)

- `utils_dates.R` — **Med:** `parse_pcornet_date()` Attempt-4 Excel-serial branch is a catch-all over `(1, 100000)`, so a bare year or stray numeric ID silently becomes a \~1905 date; **Med:** `ymd()` runs first, so all-2-digit slash dates like `01/02/03` parse YMD, pre-empting the documented US-MDY intent. Low: 2-digit-year cutoff maps `07/15/45` → 2045\.  
- `utils_cancer.R` — **Med:** `classify_codes`/`is_cancer_code` don't `toupper()` (pattern B); ICD-O-3 support claimed but only ICD-10 prefix-matched; NA handling differs between the two functions.  
- `utils_icd.R` — **Med:** `is_hl_diagnosis()` DX\_TYPE gating is strict-equality on `"10"`/`"09"`, so `"9"` or integer `9`/`10` silently yields FALSE and drops real HL diagnoses. Low: histology extractor is position-fragile.  
- `utils_payer.R` — **Med:** dual-eligible ordering bug (mirrors `02`); `is_missing_payer()` hardcodes a sentinel list that can drift from `PAYER_MAPPING$sentinel_values`; `unlist(TIER_MAPPING[tier])` can misalign `tier_rank` if `TIER_MAPPING` is a list (the `_dt` keyed-join variant is immune → the two variants can diverge). Low: untrimmed sentinel test.  
- `utils_duckdb.R` — **Med:** `get_pcornet_table()` returns an eager tibble (RDS) vs a lazy `tbl_dbi` (DuckDB); base-R ops on the lazy object silently misbehave unless callers route through `materialize()`. Low: unquoted identifier interpolation in `verify_duckdb_roundtrip`.  
- `utils_treatment.R` — **Med:** `normalize_ndc()` front-pads non-4-4-2 NDC layouts wrongly → silent crosswalk misses (feeds `108`/`get_chemo_hits`); no match-rate logging so a total NDC miss is invisible; `%in%` type-coercion assumptions on CUI columns. **Note:** `suppress_small`/`clean_multi_value`/`union_field` are **not defined here** — locate them.  
- `utils_doi.R` — Low/Med: `classify_doi_codes()` doesn't uppercase (gate/classifier inconsistency); ICD-9/10 key partition on "first char is a digit" is a latent trap for V/E codes.  
- `utils_xlsx_lookups.R` — **Med:** the duplicate-code `stop()` is dead code (Step 2 already deduped first-wins), so conflicting `code_type`/`source_table` collisions are silently resolved and never surfaced. Low: `xlsx_path` arg ignored.  
- `utils_snapshot.R` — Low/Med: `save_output_data()` writes RDS non-atomically (an interrupt corrupts and clobbers the prior good snapshot); header claims timestamped filenames but they aren't; `save_output_data` and `build_output_path` root at different directories.  
- `utils_dt.R`, `utils_assertions.R`, `utils_attrition.R`, `utils_pptx.R` — no significant issues (only Low doc/behavior nits: `min_or_na` loses Date type on all-NA input; `assert_col_types` silently passes unrecognized expected types; `ensure_dt` empty-input warning is documented but not emitted; lookup DTs returned by reference without `copy()`).

---

## Suggested fix order

1. **Unblock the crashers** (5 min): delete the stray `n` in `74`, `81`, `82`, `83`, `84`, `85`; fix `84`'s `walk` → `purrr::walk`.  
2. **Fix the wrong published numbers**: `46` total\_records (\#4), `47` anchor date (\#5), `28` SCT string (\#2), `67`/`95` same-week desync (\#6).  
3. **Harden the ingest & make tests honest**: `03` (\#3); separate skip/pass counters and fix the can't-fail validators (`81`, `82`/`83`, `88`, `96_validate_payer_dt`, `98_validate_r28`).  
4. **Standardize the shared helpers once**: code normalization (dot/case/dotted-union) in `utils_cancer`/`utils_icd`/`utils_doi`; `^C|^D[0-4]` neoplasm filter; API error-vs-miss handling; `normalize_ndc`; `parse_pcornet_date` Excel/US-date branches. Fixing these at the utils layer resolves many of the per-script mediums at once.  
5. **Confirm the two loose ends**: where `suppress_small`/`clean_multi_value`/`union_field` are defined; and the `00_config` `date_range_max` vs. extract-date cutoff.

