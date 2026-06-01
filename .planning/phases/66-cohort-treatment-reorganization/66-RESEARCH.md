# Phase 66: Cohort & Treatment Reorganization - Research

**Researched:** 2026-06-01
**Domain:** R codebase reorganization, file renaming, dependency graph management
**Confidence:** HIGH

## Summary

Phase 66 performs a comprehensive renumbering of ALL pipeline scripts (03-63) into their final decade positions in a single atomic pass. This is a scope expansion from the original "cohort and treatment only" design — the user decided during discuss-phase to place all evicted scripts into their final positions rather than use temporary numbers, eliminating the need for double-renumbering.

The primary technical challenge is managing 95+ source() cross-references across 73 R files while preserving the dependency graph. The codebase has a clear sequential dependency pattern (scripts source their upstream dependencies), which must be maintained through the renumbering. Phase 65 established the mechanical pattern (git mv + update references + atomic commit), which this phase applies at much larger scale.

**Primary recommendation:** Use a three-wave execution strategy (cohort helpers + treatment scripts + cancer/payer/outputs) with automated grep-based source() reference updates and comprehensive smoke testing after each wave. Reuse Phase 65's smoke test pattern extended to cover all decades.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Eviction Strategy:**
- **D-01:** All scripts from 03 through 62 (plus unnumbered ad-hoc scripts) get renumbered to their final decade positions in THIS phase. No temporary numbers. No double-renumbering.
- **D-02:** Scripts currently occupying target decade ranges (e.g., 11_generate_pptx in the 10-19 range, 17_value_audit in the 20-39 range) move directly to their final positions in the outputs, QA, or ad-hoc decades.

**Cohort Decade (10-19):**
- **D-03:** Helpers are numbered BEFORE the main build_cohort script (reflects dependency order):
  - 10 = cohort_predicates (from 03_cohort_predicates)
  - 11 = treatment_payer (from 10_treatment_payer)
  - 12 = surveillance (from 13_surveillance)
  - 13 = survivorship_encounters (from 14_survivorship_encounters)
  - 14 = build_cohort (from 04_build_cohort)
- **D-04:** Visualization scripts (05_visualize_waterfall, 06_visualize_sankey) are NOT cohort scripts — they go to 70-79 outputs decade.

**Treatment Decade (20-29):**
- **D-05:** Treatment analysis scripts numbered 20-29 in pipeline execution order:
  - 20 = treatment_inventory (from 38)
  - 21 = investigate_unmatched (from 39)
  - 22 = investigate_unmatched_ndc (from 40)
  - 23 = combine_reports (from 41)
  - 24 = treatment_codes_resolved (from 42)
  - 25 = treatment_durations (from 43a)
  - 26 = treatment_episodes (from 44a) — sources 25
  - 27 = drug_name_resolution (from 60)
  - 28 = episode_classification (from 61)
  - 29 = first_line_and_death_analysis (from 62)
- **D-06:** Treatment test scripts (43b_test_durations, 44b_test_episodes) move to 80-89 test decade, NOT treatment decade.

**Suffix Convention:**
- **D-07:** All a/b suffixes are eliminated in the new numbering. Every script gets a clean unique number. This applies to 43a/43b, 44a/44b, 45a/45b, 46a/46b, 48a/48b, and 22a/22b.

**Gantt Export Scripts:**
- **D-08:** Gantt data export scripts (49_gantt_data_export, 63_gantt_v2_export) stay with cancer analysis in the 40-59 decade, not outputs.

### Claude's Discretion

- Exact numbering within cancer decade (40-59): ordering of cancer site frequency, confirmation, summary, and gantt scripts
- Exact numbering within payer/QA decade (60-69): ordering of payer tiering, overlap, audit, diagnostics, and missingness scripts. NOTE: 10 slots may be insufficient for all payer/QA/diagnostic scripts — Claude may need to extend into 56-59 or reclassify some scripts as ad-hoc
- Exact numbering within outputs decade (70-79): ordering of visualization, PPTX, documentation, and encounter analysis scripts
- Exact numbering within tests decade (80-89): ordering of smoke tests, parity tests, benchmarks, and verification tests
- Exact numbering within ad-hoc decade (90-99): ordering of one-off diagnostic and exploratory scripts
- Which scripts qualify as "ad-hoc" vs "QA" when decade capacity is tight — Claude should prioritize placing active pipeline scripts in numbered decades and move one-off milestone investigation scripts to ad-hoc
- Smoke test implementation approach for validating the renumbering

### Deferred Ideas (OUT OF SCOPE)

- Phases 67 and 68 need to be repurposed or dropped from the roadmap since Phase 66 now handles all renumbering. Possible repurposing: Phase 67 could become script documentation prep, Phase 68 could become the archive folder creation (REORG-04).

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REORG-01 | All R scripts renumbered sequentially using decade-based scheme (00-09 foundation, 10-19 cohort, 20-39 treatment, 40-59 cancer, 60-69 payer/QA, 70-79 outputs, 80-89 tests, 90-99 ad-hoc) with no gaps, duplicates, or sub-letter suffixes | Phase 65 established foundation decade (00-09) and renumbering pattern. This phase completes the decade allocation for all remaining scripts. |
| REORG-02 | All source() cross-references (95+) updated to match new script numbers and paths | Phase 65 demonstrated the mechanical pattern: grep-based search for all source() calls referencing old paths, update to new paths, verify zero stale references remain. Same approach scales to full-pipeline renumbering. |

</phase_requirements>

## Standard Stack

This phase operates on existing R infrastructure. No new packages or tools required.

### Core Tools
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| git mv | 2.x+ | Atomic file rename with history preservation | Git's built-in rename detection preserves blame/log across renames; superior to rm+add |
| grep / Grep tool | N/A | Find all source() cross-references | Pattern-based search for `source("R/XX_` paths is the only reliable way to find all references |
| R source() | 4.4.2+ | Cross-file dependency loading | PCORnet R pipeline uses explicit source() calls for dependency management, not package imports |

### Validation Tools
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| Smoke test pattern (from Phase 65) | N/A | Validate source() resolution and script execution | After each wave of renumbering; reuse 65_smoke_test_foundation.R pattern extended to cover all decades |
| RDS artifact parity check | N/A | Verify hl_cohort.rds and treatment_episodes.rds structure unchanged | After full renumbering; success criterion #4 requires bit-for-bit RDS parity |

**Installation:** None required — all tools present in project environment.

## Architecture Patterns

### Recommended Renumbering Strategy: Three-Wave Execution

**Why waves:** Renumbering 60+ scripts atomically is error-prone. Breaking into waves allows incremental validation and rollback points.

**Wave 1: Cohort Helpers (10-19 decade)**
- Evict 11, 12, 13, 14, 15, 16, 17, 18, 19 to their final destinations (outputs/QA/ad-hoc)
- Renumber cohort helper scripts to 10-14 per D-03, D-04
- Update source() calls in 04_build_cohort.R (becomes 14_build_cohort.R)
- Validate: cohort build still executes, hl_cohort.rds structure unchanged

**Wave 2: Treatment Scripts (20-29 decade)**
- Renumber 38-44a to 20-29 per D-05, eliminating a/b suffixes per D-07
- Move 60-62 into treatment decade as 27-29
- Move 43b, 44b to test decade (80-89)
- Update source() call in 44a → 26 that references 43a → 25
- Validate: treatment_episodes.rds structure unchanged

**Wave 3: Cancer, Payer, Outputs, Tests, Ad-hoc (40-99 decades)**
- Cancer decade (40-59): 47-54 cancer scripts, 49+63 gantt exports, 55-58 refinement scripts
- Payer/QA decade (60-69): 17, 18-24, 33-36, 45-46 (20 scripts competing for 10 slots — overflow to 56-59 or ad-hoc per discretion)
- Outputs decade (70-79): 05-06 visualizations, 11+22b PPTX, 15 docs, 16 encounter analysis
- Tests decade (80-89): 26-29 backend tests, 43b+44b treatment tests, 65 foundation smoke test
- Ad-hoc decade (90-99): 07-09 diagnostics, 99 claude_diagnostics, 12 no_treatment_medicaid, plus any payer/QA overflow
- Validate: full smoke test covering all decades

### Dependency Chain Preservation (CRITICAL)

The codebase has an explicit dependency graph enforced via source() calls. Renumbering MUST preserve these relationships.

**Foundation → Cohort chain:**
```
00_config.R (auto-sources utils/)
  ↓
01_load_pcornet.R (sources 00)
  ↓
02_harmonize_payer.R (sources 01)
  ↓
03_cohort_predicates.R → 10 (sources via 00 chain)
10_treatment_payer.R → 11 (sourced by build_cohort)
13_surveillance.R → 12 (sourced by build_cohort)
14_survivorship_encounters.R → 13 (sourced by build_cohort)
  ↓
04_build_cohort.R → 14 (sources 02, 10→11, 13→12, 14→13)
```

**Treatment chain:**
```
43a_treatment_durations.R → 25
  ↓
44a_treatment_episodes.R → 26 (sources 25)
```

**Key insight:** The 04_build_cohort.R script has 4 internal source() calls (lines 27, 277, 383, 396) that must ALL update when renumbering:
- Line 27: `source("R/03_cohort_predicates.R")` → `source("R/10_cohort_predicates.R")`
- Line 277: `source("R/10_treatment_payer.R")` → `source("R/11_treatment_payer.R")`
- Line 383: `source("R/13_surveillance.R")` → `source("R/12_surveillance.R")`
- Line 396: `source("R/14_survivorship_encounters.R")` → `source("R/13_survivorship_encounters.R")`

### Project Structure After Renumbering
```
R/
├── 00-09: Foundation (complete in Phase 65)
├── 10-19: Cohort (5 scripts)
├── 20-29: Treatment (10 scripts)
├── 40-59: Cancer + Gantt (15-18 scripts)
├── 60-69: Payer/QA (10 slots, ~20 candidates — need overflow strategy)
├── 70-79: Outputs (5-7 scripts)
├── 80-89: Tests (7-9 scripts)
├── 90-99: Ad-hoc (diagnostics, one-offs, payer overflow)
└── utils/ (8 modules, unchanged from Phase 65)
```

### Smoke Test Extension Pattern

Phase 65 created `65_smoke_test_foundation.R` validating:
1. Utils subfolder structure
2. Auto-sourcing via list.files()
3. Foundation script chain (00→01→02→03)

Extend this pattern to `66_smoke_test_full_pipeline.R` validating:
1. All scripts exist at new numbers (no gaps, no old numbers remain)
2. No stale source() references (grep for old-style paths returns zero)
3. Foundation chain still resolves (00→01→02→03)
4. Cohort chain resolves (02→10→11→12→13→14)
5. Treatment chain resolves (20-29 source order)
6. RDS artifacts load without error (hl_cohort.rds, treatment_episodes.rds)
7. SCRIPT_INDEX.md regenerated with new numbers

### Anti-Patterns to Avoid

**Don't rename scripts manually:**
```bash
# AVOID: cp or mv without git
mv R/38_treatment_inventory.R R/20_treatment_inventory.R
# PREFER: git mv preserves history
git mv R/38_treatment_inventory.R R/20_treatment_inventory.R
```

**Don't update source() calls before renaming files:**
```
# AVOID: Update references first → broken state between commits
# PREFER: Rename files first, update references second, commit atomically
```

**Don't renumber without updating self-reference comments:**
```r
# AVOID: File renamed but header still says "# 38_treatment_inventory.R"
# PREFER: Update header comment to match new filename
# 20_treatment_inventory.R -- Treatment inventory by source table
```

**Don't skip automated verification:**
```bash
# AVOID: Assume manual updates are complete
# PREFER: grep -rn 'source("R/38_' R/ to verify zero old references remain
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Finding all source() cross-references | Manual file-by-file search | `grep -rn 'source("R/XX_' R/*.R` | 95+ references across 73 files — manual search will miss references |
| Verifying no stale references remain | Visual inspection | Automated grep + count in smoke test | Stale references cause runtime errors; automated check is 100% reliable |
| Renaming files | Shell mv or IDE refactor | `git mv` | Git rename detection preserves blame/log; critical for audit trail |
| Smoke testing | Run each script manually | Automated smoke test sourcing all scripts in dependency order | 60+ scripts; manual execution is error-prone and time-consuming |
| RDS parity check | Manual comparison | `waldo::compare()` or `all.equal()` on loaded RDS objects | Bit-for-bit comparison detects unintended data changes from source() errors |

**Key insight:** The grep tool is the single source of truth for finding source() references. Trust it over IDE search, which may miss pattern variations or comments.

## Runtime State Inventory

> This section applies to rename/refactor/migration phases only.

**Phase 66 is a code-only reorganization with NO runtime state changes.** All scripts maintain their functional behavior — only file paths and numbers change.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — RDS artifacts (hl_cohort.rds, treatment_episodes.rds) are data outputs, not state stores. Content generated by scripts, not inputs to renaming. | None — parity test verifies structure unchanged |
| Live service config | None — R pipeline runs on HiPerGator RStudio interactively or via SLURM batch jobs. No persistent services or daemons. | None |
| OS-registered state | None — No Windows Task Scheduler, cron jobs, or systemd units reference R script paths. | None |
| Secrets/env vars | None — Configuration lives in R/00_config.R (paths, ICD codes, payer mappings). No env vars or secret keys reference script numbers. | None |
| Build artifacts | None — R scripts are interpreted, not compiled. No .egg-info, .so, or cached bytecode tied to filenames. | None |

**The canonical question:** *After every file in the repo is updated, what runtime systems still have the old string cached, stored, or registered?*

**Answer:** None. R scripts are interpreted on-demand via `source()`. Renaming a file breaks only other scripts' source() calls to that file — there is no OS-level, database-level, or service-level state to update.

## Common Pitfalls

### Pitfall 1: Incomplete source() Reference Updates
**What goes wrong:** Renumbering a script but missing one source() call to it → runtime error "cannot open file 'R/38_treatment_inventory.R': No such file or directory"

**Why it happens:** source() calls can appear in:
- Main script body (most common)
- Conditional blocks: `if (!exists("pcornet")) source("R/01_load_pcornet.R")`
- Comments documenting usage: `# Usage: source("R/36_tiered_same_day_payer.R")`
- Self-reference comments in headers: `#   source("R/03_duckdb_ingest.R")`

**How to avoid:**
1. Use grep with NO filters: `grep -rn 'source("R/XX_' R/` (captures comments + code)
2. Update ALL matches, including commented-out references
3. Verify zero matches remain: `grep -rn 'source("R/XX_' R/ | wc -l` must return 0

**Warning signs:**
- Error message "cannot open file" during smoke test
- `grep -rn 'source("R/38_' R/` returns >0 matches after renumbering wave complete

### Pitfall 2: Decade Capacity Overflow
**What goes wrong:** More scripts need to fit in a decade (e.g., 60-69 payer/QA) than there are slots (10) → forced to choose between gaps in numbering or overflowing into adjacent decades

**Why it happens:** The original script inventory has 20 payer/QA/diagnostic scripts competing for 10 slots in 60-69. User decision D-02 says "evict all" but didn't specify overflow strategy.

**How to avoid:**
1. Count scripts per category BEFORE assigning numbers
2. Payer/QA has ~20 candidates: 17 (value_audit), 18-24 (missingness/overlap/detection), 33-36 (AV+TH payer analysis), 45-46 (tiered payer)
3. Overflow strategies (Claude's discretion):
   - **Extend payer into cancer tail:** Use 56-59 for payer (cancer only needs 40-55 for 15 scripts)
   - **Classify marginal scripts as ad-hoc:** One-off diagnostics (07-09) and exploratory scripts (12, 55_search_C8190) go to 90-99

**Warning signs:**
- Gap in numbering: 60-64, 68-69 (suggests cramming)
- Duplicate numbers with suffixes reappearing: 60a, 60b (violates D-07)

### Pitfall 3: Breaking the Dependency Graph
**What goes wrong:** Renumbering upstream dependency to higher number than downstream consumer → creates circular dependency or "source not found" error

**Why it happens:** The codebase has implicit ordering: lower-numbered scripts are sourced by higher-numbered scripts. Violating this breaks the chain.

**Example:**
- 04_build_cohort.R sources 03_cohort_predicates.R, 10_treatment_payer.R, 13_surveillance.R, 14_survivorship_encounters.R
- Renumbering build_cohort to 14 and predicates to 10 maintains order (10 < 14) ✓
- Renumbering predicates to 15 and build_cohort to 14 breaks order (15 > 14) ✗

**How to avoid:**
1. Before renumbering, map all source() relationships (SCRIPT_INDEX.md already documents this)
2. Number helper scripts LOWER than their consumers
3. Validate dependency order in smoke test: source scripts in numerical order, verify no errors

**Warning signs:**
- Error "object 'has_hl_diagnosis' not found" (predicate not loaded before cohort build)
- Circular dependency: A sources B, B sources A

### Pitfall 4: Forgetting Self-Reference Comments
**What goes wrong:** File renamed but header comment still shows old number → confuses future developers, makes grepping for script purpose harder

**Why it happens:** Self-reference comments are not executable code, so script runs fine with stale header. Easy to miss during bulk renaming.

**How to avoid:**
1. Update header block as part of git mv workflow: rename file, update header, stage both changes
2. Include self-reference grep in smoke test: `grep -l "^# XX_" R/XX_*.R` should return zero (no mismatched headers)

**Warning signs:**
- `grep "^# 38_treatment_inventory" R/20_treatment_inventory.R` returns a match (header not updated)

### Pitfall 5: RDS Artifact Structure Drift
**What goes wrong:** Renumbering causes unintended logic changes (e.g., wrong source() call executed) → RDS outputs structurally different → downstream scripts break

**Why it happens:** R's source() is order-dependent. If predicates load in wrong order or wrong version loads, cohort logic changes silently.

**How to avoid:**
1. Load pre-renumbering RDS artifacts: `hl_cohort_before <- readRDS("output/hl_cohort.rds")`
2. Run cohort build with new script numbers: `source("R/14_build_cohort.R")`
3. Compare with `waldo::compare(hl_cohort_before, hl_cohort)` or `all.equal()`
4. Expect: "No differences" (bit-for-bit identical)

**Warning signs:**
- Different row counts before/after
- Different column names or types
- `waldo::compare()` reports differences in patient IDs or treatment flags

## Code Examples

Verified patterns from Phase 65 execution:

### Renaming a Script with git mv
```bash
# Source: .planning/phases/65-foundation-reorganization/65-01-PLAN.md Task 2

# Rename file preserving git history
git mv R/25_duckdb_ingest.R R/03_duckdb_ingest.R

# Verify old file gone, new file exists
test ! -f R/25_duckdb_ingest.R && echo "Old file removed"
test -f R/03_duckdb_ingest.R && echo "New file exists"
```

### Updating All source() References to a Renumbered Script
```bash
# Source: Phase 65 pattern, adapted for Phase 66 scale

# Find all references to old number
grep -rn 'source("R/38_' R/*.R

# Update each match (example for single file)
# Before: source("R/38_treatment_inventory.R")
# After:  source("R/20_treatment_inventory.R")

# Verify zero stale references remain
grep -rn 'source("R/38_' R/*.R | wc -l
# Expect: 0
```

### Updating Self-Reference Comments in Renamed Script Header
```r
# Source: R/03_duckdb_ingest.R (after Phase 65 renumbering)

# Before renumbering (in 25_duckdb_ingest.R):
# ==============================================================================
# 25_duckdb_ingest.R -- Ingest PCORnet CDM tables from RDS cache into DuckDB
# ==============================================================================
# ...
# Usage:
#   source("R/25_duckdb_ingest.R")

# After renumbering (in 03_duckdb_ingest.R):
# ==============================================================================
# 03_duckdb_ingest.R -- Ingest PCORnet CDM tables from RDS cache into DuckDB
# ==============================================================================
# ...
# Usage:
#   source("R/03_duckdb_ingest.R")
```

### Smoke Test Pattern: Validating source() Resolution
```r
# Source: R/65_smoke_test_foundation.R (Phase 65 smoke test)

# Check that no old-style source paths remain
r_files <- list.files("R", pattern = "\\.R$", full.names = TRUE)
stale_refs <- character(0)
for (f in r_files) {
  lines <- readLines(f, warn = FALSE)
  # Match source("R/utils_ but NOT source("R/utils/utils_
  hits <- grep('source\\("R/utils_', lines)
  if (length(hits) > 0) {
    stale_refs <- c(stale_refs, glue("{basename(f)}:{hits}"))
  }
}
check(glue("No old-style source() paths (found: {paste(stale_refs, collapse=', ') %||% 'none'})"),
      length(stale_refs) == 0)
```

Adapt this pattern for Phase 66 by checking for old script numbers:
```r
# Validate no references to 38_treatment_inventory.R remain
stale_refs <- character(0)
for (f in r_files) {
  lines <- readLines(f, warn = FALSE)
  hits <- grep('source\\("R/38_', lines)
  if (length(hits) > 0) {
    stale_refs <- c(stale_refs, glue("{basename(f)}:{hits}"))
  }
}
check("No references to old 38_ number", length(stale_refs) == 0)
```

### RDS Parity Check Pattern
```r
# Source: R/27_parity_test_cohort.R (backend parity test)

# Load pre-change artifact
hl_cohort_before <- readRDS("output/hl_cohort.rds")

# Run cohort build with new script numbers
source("R/14_build_cohort.R")  # Renumbered from 04

# Compare
library(waldo)
comparison <- waldo::compare(hl_cohort_before, hl_cohort)

if (length(comparison) == 0) {
  message("PASS: RDS artifacts identical")
} else {
  message("FAIL: RDS artifacts differ")
  print(comparison)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Ad-hoc numbering with a/b suffixes | Decade-based sequential numbering | Phase 65-66 (v2.0) | Eliminates numbering collisions (43a/43b), creates logical grouping (10-19 cohort, 20-29 treatment) |
| Utils in R/ root | Utils in R/utils/ subfolder | Phase 65 | Cleaner namespace, auto-discovery via list.files() |
| Manual source() call updates | Grep-based automated search + smoke test validation | Phase 65 pattern | Reduces human error in renumbering |

**Deprecated/outdated:**
- **Sub-letter suffixes (a/b):** Phase 65 decision D-07 eliminates all a/b suffixes. Every script gets unique number.
- **Manual file renaming:** `git mv` is now standard (preserves history).
- **Utils in R/ root:** All utils moved to R/utils/ in Phase 65.

## Open Questions

1. **Payer/QA Decade Overflow Strategy**
   - What we know: 20 payer/QA scripts compete for 10 slots (60-69)
   - What's unclear: Should overflow go to cancer tail (56-59), ad-hoc (90-99), or both?
   - Recommendation: Classify scripts by frequency of use. Core payer analysis (36 tiered_same_day_payer, 45-46 tiered payer levels) goes to 60-69. One-off diagnostics (18-19 missingness, 35 payer_code_frequency_av_th) go to 90-99. Overlap detection (22-24, 33-34) can go to 66-69 or ad-hoc depending on whether they're reusable or milestone-specific.

2. **Smoke Test Execution Order**
   - What we know: Smoke test must source scripts in dependency order
   - What's unclear: Should smoke test source ALL 60+ scripts, or just validate source() resolution without execution?
   - Recommendation: Two-tier smoke test. Tier 1 (fast): Validate file existence, no stale references, source() paths resolve. Tier 2 (slow): Execute foundation + cohort + treatment chain to verify RDS parity. Tier 2 is optional (can be manual verification before phase close).

3. **Ad-hoc Script Boundary**
   - What we know: Some scripts are exploratory (55_search_C8190, 12_no_treatment_medicaid, 07-09 diagnostics)
   - What's unclear: Which qualify as "ad-hoc" vs "QA pipeline"?
   - Recommendation: Ad-hoc = scripts written for one milestone and not reused (e.g., 55_search_C8190 was a one-time ICD code search). QA = scripts that validate outputs and could be rerun on new data (e.g., 17_value_audit, 26-28 backend tests). When in doubt, prioritize decade placement for reusable scripts, overflow one-offs to 90-99.

## Environment Availability

> Phase 66 is code reorganization only — no external dependencies beyond git and R interpreter.

**Step 2.6: SKIPPED** (no external dependencies identified)

All required tools (git, R, grep) are already present in the HiPerGator RStudio environment where this codebase runs. No installation or availability check required.

## Sources

### Primary (HIGH confidence)
- `.planning/phases/65-foundation-reorganization/65-01-PLAN.md` — Established renumbering pattern (git mv, grep-based reference updates, atomic commits)
- `.planning/phases/65-foundation-reorganization/65-CONTEXT.md` — Auto-sourcing mechanism, utils subfolder structure
- `R/SCRIPT_INDEX.md` — Complete script inventory with dependency chains (73 total scripts, 95+ source() calls documented)
- `R/65_smoke_test_foundation.R` — Smoke test pattern for validating source() resolution
- `R/04_build_cohort.R` lines 27, 277, 383, 396 — Confirms 4 internal source() calls that must update during renumbering

### Secondary (MEDIUM confidence)
- Git documentation (git-scm.com) — `git mv` preserves history via rename detection
- R language documentation — `source()` behavior and path resolution

### Tertiary (LOW confidence)
- None — all research based on project files and established patterns from Phase 65

## Metadata

**Confidence breakdown:**
- Standard stack (git, grep, R): **HIGH** — Tools already in use, Phase 65 established pattern
- Architecture (three-wave strategy): **HIGH** — Based on Phase 65 single-wave success scaled to multi-wave for safety
- Pitfalls (incomplete references, dependency graph breaks): **HIGH** — Known failure modes from source() dependency management
- Payer/QA decade overflow strategy: **MEDIUM** — User left to Claude's discretion; research recommends use-frequency classification but final decision during planning

**Research date:** 2026-06-01
**Valid until:** 2026-07-01 (30 days — stable domain, R language and git behavior unchanged)
