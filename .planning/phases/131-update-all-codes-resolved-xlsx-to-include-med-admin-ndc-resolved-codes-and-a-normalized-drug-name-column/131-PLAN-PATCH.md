# Phase 131 — Plan Patch Note

**Created:** 2026-07-22
**Applies to:** 131-01-PLAN.md, 131-02-PLAN.md, 131-03-PLAN.md, 131-04-PLAN.md
**Purpose:** Close two execution-blocking defects (a missing column rename in 131-02, two broken structural checks in 131-04) and surface one output-behavior change that must not ship silently. Apply before executing wave 1.

Nothing here changes the phase's architecture, file list, or dependency graph. These are corrections to strings/steps that are internally inconsistent across the plans as written.

---

## Patch 1 — 131-02 Task 2: make the `triggering_code -> code` rename explicit; nail down the RXNORM filter literal; flag the Records-count change

**Why:** `get_chemo_hits()` returns the match column as `triggering_code`, but Task 3's join filters `count_results` on a `code` column and does `select(code, records, patients, dyn_source_table = source_table)`. No step in Task 2 renames `triggering_code -> code`, and the numbered steps mix both names. Task 3 will fail on a missing join key. Separately, Task 2 step 2 never commits to a literal filter expression, which leaves 131-04 Check 4 (Patch 2) nothing deterministic to match. Finally, the new de-duplication silently changes the Records-column numbers for existing codes.

### 1a. Replace Task 2, step 2 (the `code_type_map` filter sentence) with:

> 2. Selects the four RXNORM vectors by filtering `code_type_map` with `filter(code_type == "RXNORM")` — use this exact literal. Do NOT hand-enumerate vector names, and do NOT retain the old `str_detect(source_table, "PRESCRIBING\\|MED_ADMIN")` selection form; 131-04 Section 15x Check 4 greps for `filter(code_type == "RXNORM")` specifically. This naturally covers chemo_rxnorm, sct_rxnorm, immunotherapy_rxnorm, supportive_care_rxnorm.

### 1b. Replace Task 2, steps 4-7 with:

> 4. Binds the three per-source results, then establishes a single canonical `code` column up front so every downstream step and the Task 3 join agree on it:
>    `all_hits <- bind_rows(...) %>% rename(code = triggering_code)`.
>    Do the rename ONCE, immediately after the bind — not per-branch. `get_chemo_hits()` always returns `triggering_code`, so one rename covers all three source calls. If any of the three results is NULL, `bind_rows()` drops it and the rename still applies to whatever columns survive.
>
> 5. De-duplicates the source-labelled set once, for the source aggregation only:
>    `hits_by_source <- all_hits %>% distinct(ID, treatment_date, code, source)`.
>
> 6. Computes `records`/`patients` from a SEPARATE, source-agnostic de-duplication, so an administration reachable via two paths is counted once:
>    `hits_dedup <- all_hits %>% distinct(ID, treatment_date, code)`, then
>    `counts <- hits_dedup %>% group_by(code) %>% summarise(records = n(), patients = n_distinct(ID), .groups = "drop")`.
>
>    **Behavioral change — document in the SUMMARY.** `records` now counts distinct `(ID, treatment_date, code)` administrations. The OLD loop counted raw joined rows (`group_by(code) %>% summarise(records = n())`, no `distinct()`). For existing single-source codes that had multiple same-day rows, the reported Records number will DROP relative to prior runs. This is the intended Pitfall-2 de-duplication fix, but because `all_codes_resolved.xlsx` is shared with collaborators, the change to existing numbers must be stated explicitly — not framed only as "new codes appear."
>
> 7. Computes the per-code source label from `hits_by_source`:
>    `source_labels <- hits_by_source %>% group_by(code) %>% summarise(source_table = paste(sort(unique(source)), collapse = ", "), .groups = "drop")`.
>    Joins it onto `counts` by `code`, then `mutate(vector_name = vec_name)`. The resulting per-vector frame (`code, records, patients, source_table, vector_name`) is `bind_rows()`-ed into `count_results`.
>    `count_results`'s initial tibble (~line 219) must add `source_table = character()` and already carry a `code` column, so the PROCEDURES/ENCOUNTER blocks (which set `code` but not `source_table`) still bind via NA-filling on `source_table`.

### 1c. Append to the 131-02 interface block, right after the `get_chemo_hits()` return-contract line:

> Every branch returns the match column as `triggering_code` (never `code`). R/50's new loop renames it to `code` exactly once after binding the three source results (Task 2 step 4). Task 3's `count_results` join key is therefore `code`.

### 1d. Add to the required content of 131-02-SUMMARY.md:

> Records-column values for existing single-source codes with multiple same-day rows will decrease relative to prior `all_codes_resolved.xlsx` runs, as a direct result of the `(ID, treatment_date, code)` de-duplication. Intended (Pitfall 2 fix), not a regression.

---

## Patch 2 — 131-04 Task 1 Check 4: replace the newline-spanning pattern

**Why:** `r50_text_131` is built with `collapse = "\n"`. In R's `grepl`, `.` does not match newlines, so `'code_type_map.*filter\\(...\\)'` cannot match when the two tokens are on different lines (they will be). The first alternative is dead code; the check silently relies on the second, and hard-codes a filter string 131-02 didn't commit to (now fixed by Patch 1a).

### Replace Check 4 with:

> 4. R/50's RXNORM loop is generalized via a `code_type == "RXNORM"` filter (not hand-enumerated vector names). Do NOT use a `.*`-spanning pattern — `.` does not cross the `\n` in the collapsed text. Test for the filter call alone, allowing `.data$` and whitespace variation:
>
> ```r
> check(
>   "R/50 RXNORM loop filters code_type == RXNORM (Phase 131)",
>   grepl('filter\\(\\s*(\\.data\\$)?code_type\\s*==\\s*"RXNORM"\\s*\\)', r50_text_131)
> )
> ```
>
> After Patch 1a, 131-02 writes `filter(code_type == "RXNORM")` as an exact literal, so this pattern matches deterministically. Do not OR this with a `str_detect(source_table, ...)` alternative — a check that cannot fail validates nothing.

---

## Patch 3 — 131-04 Task 1 Check 11: fix the call-site count and its zero-match guard

**Why:** The helper is `resolved_xlsx_layout <- function(category)` (defined once) and called `resolved_xlsx_layout(category)` in both writers. The intended count is 2 call sites (the definition line is not a substring match). Two problems with the original check: (a) `gregexpr` returns `-1` as a length-1 vector on ZERO matches, so a total failure to wire the helper reads as "1 call site" and passes a `== 1`-adjacent reading or masks the real state; (b) the regex parens should be `fixed = TRUE`. The check must fail loudly if either writer is missing or abbreviates the argument.

### Replace Check 11 with:

> 11. The shared layout helper is consumed by BOTH writers (the "stay in sync" guarantee). Count call sites with `fixed = TRUE`, and guard the `gregexpr` zero-match case explicitly:
>
> ```r
> layout_matches <- gregexpr("resolved_xlsx_layout(category)", r50_text_131, fixed = TRUE)[[1]]
> n_layout_calls <- if (length(layout_matches) == 1 && layout_matches[1] == -1) 0L else length(layout_matches)
> check(
>   "resolved_xlsx_layout(category) called by both writers, 2 sites (Phase 131)",
>   n_layout_calls == 2
> )
> ```
>
> The definition line `resolved_xlsx_layout <- function(category)` is not counted (not a substring match). If 131-03 abbreviated the argument at either call site (e.g. `resolved_xlsx_layout(cat)`), this returns 1 and fails — correct, because the "both writers derive from one helper" guarantee requires both literal call sites. Keep the argument literally `category` at both call sites in 131-03 so this check and 131-03's own `grep -c "resolved_xlsx_layout(category)"` (expecting 2) agree.

---

## Non-blocking notes (no edit required, verify during execution)

- **131-01 fallback HCPCS branch may be near-dead in practice.** Branch 2 (`code_type == "CPT/HCPCS"`, `^Injection,` strip) is only reached when `code %in% names(MEDICATION_LOOKUP)` is FALSE. Per RESEARCH, Chemotherapy J-codes are already curated in `MEDICATION_LOOKUP`, and the new NDC-resolved misses are RXNORM-typed — so this branch's real hit rate may be ~0. Not a defect; keep it for correctness, but confirm during runtime whether any row with `code_type == "CPT/HCPCS"` ever misses the lookup before treating this branch as load-bearing.

- **131-01 Task 1 verify "grep sheet_df[[3]] -> 0" is file-global.** The replacement removes the `MEDICATION_LOOKUP` reference, but the grep scans the whole ~3400-line config. If any unrelated `sheet_df[[3]]` exists elsewhere, the "-> 0" expectation is wrong. Spot-check that no other occurrence exists before relying on the count.

- **Requirement IDs** (`MEDXLSX-01..07`, `SMOKE-131-01`, `DOI-QA-01/02`) are referenced in frontmatter/summaries but not defined in this bundle. Confirm they're tracked in the phase requirements doc.

---

## Apply order

1. Patch 1 (a-d) into 131-02-PLAN.md and its SUMMARY requirement.
2. Patch 2 and Patch 3 into 131-04-PLAN.md.
3. No changes to 131-01 or 131-03 plan bodies (notes only).
4. Re-confirm 131-03 Task 2/Task 3 verifies still read `resolved_xlsx_layout(category)` with the literal `category` argument — they already do; leave as-is.
