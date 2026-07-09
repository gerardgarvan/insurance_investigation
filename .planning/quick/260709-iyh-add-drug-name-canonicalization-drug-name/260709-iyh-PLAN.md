---
phase: quick-260709-iyh
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - R/00_config.R
  - R/27_drug_name_resolution.R
  - R/88_smoke_test_comprehensive.R
autonomous: true
requirements: [IYH-01]

must_haves:
  truths:
    - "MEDICATION_LOOKUP display names for doxorubicin variants collapse to a single canonical form ('Doxorubicin Hydrochloride')"
    - "R/27 re-normalizes stale cached drug_name values to canonical forms before saving cache/CSV"
    - "Liposomal doxorubicin remains a distinct drug name (NOT collapsed into plain doxorubicin)"
    - "R/88 structurally asserts the canonicalization layer exists in R/00_config and is applied in R/27"
  artifacts:
    - path: "R/00_config.R"
      provides: "DRUG_NAME_ALIASES map + canonicalize_drug_name() helper, applied to MEDICATION_LOOKUP after J-code merge"
      contains: "canonicalize_drug_name <- function"
    - path: "R/27_drug_name_resolution.R"
      provides: "canonicalize_drug_name applied to all_lookups$drug_name before saveRDS/write.csv"
      contains: "mutate(drug_name = canonicalize_drug_name(drug_name))"
    - path: "R/88_smoke_test_comprehensive.R"
      provides: "Structural grep checks for canonicalization layer"
      contains: "canonicalize_drug_name"
  key_links:
    - from: "R/00_config.R DRUG_NAME_ALIASES"
      to: "MEDICATION_LOOKUP display values"
      via: "setNames(canonicalize_drug_name(unname(MEDICATION_LOOKUP)), names(MEDICATION_LOOKUP))"
      pattern: "MEDICATION_LOOKUP <- setNames\\(canonicalize_drug_name\\("
    - from: "R/27 all_lookups$drug_name"
      to: "canonical display names in cache/CSV"
      via: "mutate before saveRDS"
      pattern: "mutate\\(drug_name = canonicalize_drug_name\\(drug_name\\)\\)"
---

<objective>
Add a general, extensible drug-name canonicalization layer so same-drug/different-name
duplicates collapse in the Gantt `drug_names` field. First alias: all plain-doxorubicin
spellings ("doxorubicin", "doxorubicin hcl", "doxorubicin hydrochloride") →
"Doxorubicin Hydrochloride". Liposomal doxorubicin MUST stay separate (clinically distinct).

Root cause (already investigated): Gantt `drug_names` (R/26 SECTION 5B) coalesces
MEDICATION_LOOKUP (R/00_config) with the R/27 RxNorm cache. An episode can list BOTH
"Doxorubicin Hydrochloride" (J9000 supplement, R/00_config:2349) AND a stale lowercase
"doxorubicin" from the R/27 cache (D-09 only queries NEW codes, so old cached names never
got re-normalized after str_to_title was added). Case-folding alone won't merge these
because both sources title-case — a canonical ALIAS is required.

Purpose: Collapse duplicate drug names in the Gantt without touching schema, columns, or
the R/26 cascade. Provide a shared helper both R/00_config and R/27 call.
Output: Canonicalized MEDICATION_LOOKUP + re-normalized R/27 cache + R/88 structural check.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@./CLAUDE.md

<interfaces>
<!-- Exact anchors the executor edits against. No codebase exploration needed. -->

R/00_config.R (J-code supplement merge — insert canonicalization AFTER this block):
```r
# ~line 2348
MEDICATION_LOOKUP_JCODE_SUPPLEMENT <- c(
  "J9000" = "Doxorubicin Hydrochloride",
  ...
)
new_codes <- setdiff(names(MEDICATION_LOOKUP_JCODE_SUPPLEMENT), names(MEDICATION_LOOKUP))
MEDICATION_LOOKUP <- c(MEDICATION_LOOKUP, MEDICATION_LOOKUP_JCODE_SUPPLEMENT[new_codes])
message(glue("  MEDICATION_LOOKUP supplement: {length(new_codes)} J-codes added ..."))
# <-- INSERT canonicalization block HERE (before SECTION 6)
```
MEDICATION_LOOKUP is a NAMED character vector: names = codes (e.g. "J9000"),
values = display drug names. Canonicalization must preserve the code-key names.

R/27_drug_name_resolution.R:
- `source("R/00_config.R")` at line 41 makes canonicalize_drug_name available.
- `all_lookups` is a data frame with a `drug_name` column.
- saveRDS(all_lookups, CACHE_FILE) at line ~457; write.csv(all_lookups, ...) at ~461.
  INSERT re-normalization BEFORE line 456 ("# Save RDS cache (per D-09)").

R/88_smoke_test_comprehensive.R:
- Uses helper `check("<label>", <boolean>)`.
- Reads files via `readLines("R/xx.R", warn = FALSE)` then greps with `grepl(...)`.
- Section 15j (line ~1758) is the Phase 114 drug-name-consistency section — natural home.
- Existing pattern example (line 1772-1775):
    r26_lines <- readLines("R/26_treatment_episodes.R", warn = FALSE)
    check("R/26 fills blank drug_names ...", any(grepl("MEDICATION_LOOKUP", r26_lines)) && ...)
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add canonicalization layer to R/00_config and apply in R/27</name>
  <files>R/00_config.R, R/27_drug_name_resolution.R</files>
  <read_first>
    - R/00_config.R lines 2347-2361 (J-code supplement merge — the insertion anchor)
    - R/27_drug_name_resolution.R lines 41 (source config) and 452-462 (save block)
  </read_first>
  <action>
### 1a. R/00_config.R — insert AFTER the J-code supplement merge

Locate the supplement merge block (ends ~line 2360 with the
`message(glue("  MEDICATION_LOOKUP supplement: ...` line) and BEFORE the
`# SECTION 6: ANALYSIS PARAMETERS` header. Insert this block there so BOTH the
reference-Excel entries AND the J-code supplement entries get canonicalized:

```r
# ==============================================================================
# Canonical drug-name aliases: collapse same-drug/different-name duplicates.
# ==============================================================================
# WHY (DOC-03): Gantt drug_names (R/26 SECTION 5B) unions MEDICATION_LOOKUP with the
# R/27 RxNorm cache. Both title-case, so "Doxorubicin" vs "Doxorubicin Hydrochloride"
# never merge on case alone. This alias map maps lowercased match-forms to a single
# canonical display name. Extend by adding rows. canonicalize_drug_name() is shared
# with R/27 (which re-normalizes its stale cache via the same helper).
# NOTE: liposomal doxorubicin is intentionally EXCLUDED — clinically distinct formulation.
DRUG_NAME_ALIASES <- c(
  "doxorubicin"               = "Doxorubicin Hydrochloride",
  "doxorubicin hcl"           = "Doxorubicin Hydrochloride",
  "doxorubicin hydrochloride" = "Doxorubicin Hydrochloride"
)

canonicalize_drug_name <- function(x) {
  key <- tolower(stringr::str_trim(x))
  hit <- DRUG_NAME_ALIASES[key]
  out <- ifelse(!is.na(hit), unname(hit), x)
  out[is.na(x)] <- NA_character_
  out
}

# Apply to MEDICATION_LOOKUP, preserving code-key names.
MEDICATION_LOOKUP <- setNames(canonicalize_drug_name(unname(MEDICATION_LOOKUP)), names(MEDICATION_LOOKUP))
```

Do NOT change normalize_med(). Do NOT alter code_descriptions / TREATMENT_CODES
description maps (out of scope — they feed triggering_code_descriptions, not drug_names).

### 1b. R/27_drug_name_resolution.R — re-normalize all_lookups before save

Insert IMMEDIATELY BEFORE the `# Save RDS cache (per D-09)` comment (line ~456),
i.e. after `all_lookups` is fully assembled and before `saveRDS(...)`:

```r
# Re-normalize drug names to canonical forms (DOC-03). D-09 caches names and only
# queries NEW codes, so stale cached entries (e.g. lowercase "doxorubicin") never got
# re-normalized after str_to_title was added. This is the re-normalization point that
# fixes them. canonicalize_drug_name() comes from source("R/00_config.R") at top of file.
all_lookups <- all_lookups %>% mutate(drug_name = canonicalize_drug_name(drug_name))
```

Do NOT change the API lookup functions or normalize_rxnorm_drug_name.
  </action>
  <verify>
    <automated>grep -n "canonicalize_drug_name <- function" R/00_config.R &amp;&amp; grep -n "DRUG_NAME_ALIASES <- c(" R/00_config.R &amp;&amp; grep -n "MEDICATION_LOOKUP <- setNames(canonicalize_drug_name(" R/00_config.R &amp;&amp; grep -n "mutate(drug_name = canonicalize_drug_name(drug_name))" R/27_drug_name_resolution.R &amp;&amp; ! grep -i "liposomal" R/00_config.R</automated>
  </verify>
  <done>
    - R/00_config.R defines DRUG_NAME_ALIASES (3 plain-doxorubicin keys) and canonicalize_drug_name().
    - Canonicalization applied to MEDICATION_LOOKUP AFTER the J-code supplement merge, BEFORE SECTION 6.
    - Alias map contains NO "liposomal" key (case-insensitive grep returns nothing).
    - R/27 applies canonicalize_drug_name to all_lookups$drug_name immediately before saveRDS.
    - normalize_med, normalize_rxnorm_drug_name, and description maps untouched.
    - If Rscript is available: `Rscript --vanilla -e 'invisible(parse("R/00_config.R")); invisible(parse("R/27_drug_name_resolution.R"))'` parses cleanly.
  </done>
  <acceptance_criteria>
    - R/00_config.R contains `DRUG_NAME_ALIASES <- c(` and `canonicalize_drug_name <- function`
    - R/00_config.R contains `MEDICATION_LOOKUP <- setNames(canonicalize_drug_name(`
    - R/00_config.R does NOT contain "liposomal" (case-insensitive)
    - R/00_config.R still contains `normalize_med <- function` (unchanged)
    - R/27_drug_name_resolution.R contains `mutate(drug_name = canonicalize_drug_name(drug_name))`
    - R/27 insertion appears before `saveRDS(all_lookups, CACHE_FILE)`
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 2: Add R/88 structural checks for the canonicalization layer</name>
  <files>R/88_smoke_test_comprehensive.R</files>
  <read_first>
    - R/88_smoke_test_comprehensive.R lines 1758-1826 (Section 15j Phase 114 drug-name checks — the append target and the `check()` + `readLines`/`grepl` pattern)
  </read_first>
  <action>
Append TWO lightweight grep checks to the END of Section 15j (Phase 114 drug name
consistency remediation), immediately AFTER Check 14 (line ~1825, the
`R/79 outputs drug_name_consistency_audit.xlsx` check) and BEFORE the
`# SECTION 15k` header (~line 1827). Reuse the existing `check()` + `readLines`/`grepl`
pattern already used throughout this section:

```r
# Check 15: R/00_config defines the canonicalization layer (quick task 260709-iyh)
r00_lines <- readLines("R/00_config.R", warn = FALSE)
check("R/00_config defines DRUG_NAME_ALIASES + canonicalize_drug_name() and applies to MEDICATION_LOOKUP",
      any(grepl("DRUG_NAME_ALIASES <- c\\(", r00_lines)) &&
      any(grepl("canonicalize_drug_name <- function", r00_lines)) &&
      any(grepl("MEDICATION_LOOKUP <- setNames\\(canonicalize_drug_name\\(", r00_lines)) &&
      !any(grepl("liposomal", r00_lines, ignore.case = TRUE)))

# Check 16: R/27 applies canonicalize_drug_name to cached drug names (quick task 260709-iyh)
r27_lines <- readLines("R/27_drug_name_resolution.R", warn = FALSE)
check("R/27 re-normalizes all_lookups drug_name via canonicalize_drug_name before save",
      any(grepl("mutate\\(drug_name = canonicalize_drug_name\\(drug_name\\)\\)", r27_lines)))
```

Do NOT restructure the section, renumber other checks, or touch the Section 16 summary
counts. This is an additive, minimal edit within an existing section.
  </action>
  <verify>
    <automated>grep -n "R/00_config defines DRUG_NAME_ALIASES" R/88_smoke_test_comprehensive.R &amp;&amp; grep -n "R/27 re-normalizes all_lookups drug_name via canonicalize_drug_name" R/88_smoke_test_comprehensive.R</automated>
  </verify>
  <done>
    - Section 15j has two new `check(...)` calls asserting the R/00_config layer and R/27 application.
    - The R/00_config check also asserts NO "liposomal" appears in that file (guards the exclusion).
    - No other checks renumbered; Section 16 summary untouched.
    - If Rscript is available: `Rscript --vanilla -e 'invisible(parse("R/88_smoke_test_comprehensive.R"))'` parses cleanly.
  </done>
  <acceptance_criteria>
    - R/88 contains a check referencing `DRUG_NAME_ALIASES` and `canonicalize_drug_name`
    - R/88 contains a check for `mutate\(drug_name = canonicalize_drug_name\(drug_name\)\)`
    - R/88 check for R/00_config asserts `ignore.case = TRUE` on "liposomal" (exclusion guard)
    - Edit is contained within Section 15j (between Check 14 and the `# SECTION 15k` header)
  </acceptance_criteria>
</task>

</tasks>

<verification>
Structural verification only (Windows-local executor, no HiPerGator data / reference Excel).
Do NOT run the pipeline. Grep-based checks:

1. R/00_config.R: `DRUG_NAME_ALIASES <- c(`, `canonicalize_drug_name <- function`,
   `MEDICATION_LOOKUP <- setNames(canonicalize_drug_name(` all present; NO "liposomal" (case-insensitive).
2. R/00_config.R still has `normalize_med <- function` (unchanged).
3. R/27_drug_name_resolution.R: `mutate(drug_name = canonicalize_drug_name(drug_name))` present, before saveRDS.
4. R/88: two new canonicalize_drug_name checks present in Section 15j.
5. If R available: `Rscript --vanilla -e 'invisible(parse("<file>"))'` parses each modified file.
</verification>

<success_criteria>
- Shared, extensible canonicalization layer (DRUG_NAME_ALIASES + canonicalize_drug_name) defined once in R/00_config.
- MEDICATION_LOOKUP display values canonicalized after the J-code merge, code-keys preserved.
- R/27 re-normalizes its (possibly stale) cache values via the same helper before saving.
- Liposomal doxorubicin explicitly excluded from the alias map and guarded by a smoke check.
- R/88 structurally asserts both edit sites.
- Only R/00_config.R, R/27_drug_name_resolution.R, R/88_smoke_test_comprehensive.R modified.
- No schema/column changes; R/26 SECTION 5B cascade untouched.
</success_criteria>

<output>
After completion, create `.planning/quick/260709-iyh-add-drug-name-canonicalization-drug-name/260709-iyh-SUMMARY.md`.

The SUMMARY MUST document the HiPerGator regeneration order (run there, not locally):
  1. R/27_drug_name_resolution.R — re-normalizes cached drug names to canonical forms
     (D-09: no new API calls; the mutate re-normalizes existing cache entries).
  2. R/26_treatment_episodes.R — rebuilds treatment_episodes with canonical drug_names.
  3. R/52 — regenerates gantt_episodes.csv.
  4. R/101 — regenerates gantt_lifespan.csv.
</output>
