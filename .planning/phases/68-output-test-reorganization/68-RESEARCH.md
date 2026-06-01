# Phase 68: Output & Test Reorganization - Research

**Researched:** 2026-06-01
**Domain:** R script verification and documentation reorganization
**Confidence:** HIGH

## Summary

Phase 68 has been repurposed from its original scope (output/test/ad-hoc renumbering) to a **verification gate** for REORG-04 and REORG-05. The original work was absorbed by Phase 66 (comprehensive renumbering) and Phase 67 (cleanup). This phase performs structural validation, documentation reconciliation, and formal closure of the reorganization work stream.

Current state analysis reveals Phase 67 completed the heavy lifting (8 scripts archived, smoke test at position 87, SCRIPT_INDEX regenerated), but verification exposed documentation gaps that were closed via Plan 67-02. The codebase now has 67 numbered scripts across 8 decades, 8 archived scripts in R/archive/, and 8 utility modules in R/utils/.

**Primary recommendation:** Execute local structural checks (Windows-compatible subset of R/87 smoke test), create HiPerGator validation checklist for deferred data-dependent checks, scan for remaining loose ends, update ROADMAP/REQUIREMENTS to reflect repurposed scope, and formally close REORG-04/REORG-05 if current state is clean.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Run structural checks locally on Windows (file existence, source() parsing, sequential numbering validation — the parts of R/87 that don't require data)
- **D-02:** Create a HiPerGator verification checklist documenting what must be run on-cluster for full REORG-05 validation (data-dependent checks)
- **D-03:** Phase 68 does NOT require a successful HiPerGator run to close — the checklist is the deliverable for deferred execution
- **D-04:** Scan for additional scripts that may need archiving (beyond the 8 already in R/archive/)
- **D-05:** Verify R/87 smoke test coverage against REORG-05 criteria (sequential numbering, source() resolution, RDS dependency checks)
- **D-06:** Check for orphan output files that don't correspond to any active script
- **D-07:** If scan reveals gaps: create follow-up items (don't block Phase 68 completion for minor issues)
- **D-08:** If scan confirms current state is clean: mark REORG-04 and REORG-05 complete

### Claude's Discretion
- **Documentation updates:** Rewrite ROADMAP Phase 68 description/success criteria to reflect repurposed verification scope (current criteria reference absorbed original scope). Update REQUIREMENTS.md traceability. Update STATE.md. Claude decides the exact phrasing and level of detail.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REORG-04 | Deprecated/superseded scripts moved to R/archive/ folder with README explaining their status | Phase 67 completed baseline archival (8 scripts); Phase 68 scans for additional candidates |
| REORG-05 | Smoke test validates no broken cross-references after each renumbering phase (RDS artifacts unchanged, source() calls resolve) | R/87 smoke test provides structural validation; data-dependent checks deferred to HiPerGator checklist |
| REORG-01 | All R scripts renumbered sequentially using decade-based scheme with no gaps, duplicates, or sub-letter suffixes | Prerequisite completed by Phases 65-67; Phase 68 verifies final state |
| REORG-02 | All source() cross-references updated to match new script numbers and paths | Prerequisite completed by Phases 66-67; Phase 68 verifies no broken references remain |
</phase_requirements>

## Standard Stack

### Core Tools for Verification

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Windows Command Shell | Built-in | Local structural checks | Native environment for verification (no R data loading required) |
| R/87_smoke_test_full_pipeline.R | Current | Structural validation | Already implements 12 test categories (file existence, source() parsing, decade validation) |
| grep/findstr | Built-in | Pattern matching for source() calls | Cross-platform file content scanning |
| ls/dir + wc -l | Built-in | File counting and existence checks | Verify script counts per decade |

### Supporting Tools

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| git log --follow | Built-in | Archive verification | Confirm git history preserved for moved files |
| Node.js gsd-tools.cjs | GSD v2 | Update REQUIREMENTS.md traceability | Mark REORG-04/REORG-05 complete if validation passes |

### No Installation Required
All verification tools are already present:
- Windows shell commands (ls, wc, grep, find)
- Git (for commit verification)
- Existing R/87 smoke test script
- GSD toolkit (gsd-tools.cjs)

## Architecture Patterns

### Recommended Verification Structure

```
Phase 68 Verification Flow:
├── Step 1: Local Structural Checks (Windows-compatible)
│   ├── Script count validation (67 numbered + 8 utils + 8 archived)
│   ├── Decade boundaries (no gaps, no duplicates, no a/b suffixes)
│   ├── source() reference parsing (all targets exist on filesystem)
│   ├── Archive directory structure (8 scripts + README.md)
│   └── SCRIPT_INDEX.md alignment with filesystem
├── Step 2: HiPerGator Checklist Creation
│   ├── R/87 smoke test execution (full 12-test suite)
│   ├── RDS dependency checks (cache/ artifacts unchanged)
│   ├── Data-dependent script execution (smoke test backends, parity tests)
│   └── Integration validation (source() calls resolve at runtime)
├── Step 3: Additional Archival Candidates Scan
│   ├── Find scripts with zero source() references from active pipeline
│   ├── Identify one-off diagnostics not in ad-hoc decade (90-99)
│   ├── Flag superseded implementations (duplicated logic)
│   └── Document candidates with archival rationale
├── Step 4: Orphan Output Files Audit
│   ├── Map output/ files to generating scripts
│   ├── Identify outputs from archived scripts
│   ├── Flag outputs with no current generating script
│   └── Document disposition (safe to delete vs. historical reference)
└── Step 5: Documentation Reconciliation
    ├── Update ROADMAP.md Phase 68 to reflect repurposed scope
    ├── Update REQUIREMENTS.md traceability (REORG-04/REORG-05 status)
    ├── Update STATE.md current position
    └── Update .planning/phases/68-*/68-VERIFICATION.md template
```

### Pattern 1: Local Structural Validation (No R Data Loading)

**What:** Subset of R/87 smoke test that runs on Windows without loading PCORnet data.

**When to use:** Phase 68 verification gate (immediate validation before HiPerGator run).

**Example:**
```bash
# Count scripts per decade
ls R/0*.R | wc -l  # Foundation: expect 4 (00-03)
ls R/1*.R | wc -l  # Cohort: expect 5 (10-14)
ls R/2*.R | wc -l  # Treatment: expect 10 (20-29)
ls R/4*.R | wc -l  # Cancer: expect 14 (40-53)
ls R/5*.R | wc -l  # Cancer overflow: expect 0 (absorbed into 40-53)
ls R/6*.R | wc -l  # Payer/QA: expect 10 (60-69)
ls R/7*.R | wc -l  # Output: expect 6 (70-75)
ls R/8*.R | wc -l  # Test: expect 8 (80-87)
ls R/9*.R | wc -l  # Ad-hoc: expect 10 (90-99)

# Total: 67 numbered scripts

# Check for a/b suffixes (should be zero)
ls R/*[ab]_*.R 2>/dev/null | wc -l

# Check for unnumbered scripts (should be zero)
ls R/*.R | grep -v "^R/[0-9][0-9]_" | wc -l

# Verify archive
ls R/archive/*.R | wc -l  # Expect 8 scripts
test -f R/archive/README.md && echo "Archive README exists"

# Parse source() references (extract and verify targets exist)
for f in R/*.R; do
  grep 'source("R/' "$f" | sed 's/.*source("\(R\/[^"]*\)".*/\1/' | while read path; do
    test -f "$path" || echo "BROKEN: $f -> $path"
  done
done
```

### Pattern 2: HiPerGator Validation Checklist

**What:** Structured checklist documenting data-dependent checks that must run on HiPerGator for full REORG-05 validation.

**When to use:** Defer full validation when local structural checks pass but data loading requires HPC environment.

**Example checklist structure:**
```markdown
# HiPerGator Validation Checklist for REORG-05

**Purpose:** Full smoke test validation with PCORnet data (deferred from Phase 68)

**Prerequisites:**
- [ ] SSH to HiPerGator
- [ ] Load R/4.4.2 module
- [ ] Navigate to project directory
- [ ] Verify renv.lock in sync

**Validation Steps:**

## 1. Full Smoke Test Execution
- [ ] Run: `Rscript R/87_smoke_test_full_pipeline.R`
- [ ] Expected: All 12 test categories PASS
- [ ] Expected: Zero broken source() references
- [ ] Expected: Zero missing decade files

## 2. RDS Dependency Checks
- [ ] Verify cache/ directory unchanged (no new artifacts, no deletions)
- [ ] Run: `ls cache/*.rds | wc -l` (expect ~25 artifacts)
- [ ] Spot-check: `readRDS("cache/pcornet.rds")$ENROLLMENT` loads without error

## 3. Data-Dependent Script Execution
- [ ] Run: `Rscript R/80_smoke_test_backends.R` (backend parity test)
- [ ] Run: `Rscript R/81_parity_test_cohort.R` (cohort build parity)
- [ ] Expected: Zero parity violations (RDS vs DuckDB)

## 4. Integration Validation
- [ ] Source 00_config.R and verify utils auto-sourcing: `Rscript -e 'source("R/00_config.R"); ls()'`
- [ ] Expected: All 8 utils functions present in environment

**Completion Criteria:**
- All checkboxes ticked
- Zero test failures
- Documentation updated in .planning/phases/68-*/68-VERIFICATION.md

**Estimated Time:** 15 minutes (on HiPerGator with cached data)
```

### Pattern 3: Archival Candidate Identification

**What:** Scan for scripts that may need archiving based on usage patterns.

**When to use:** Phase 68 Step 3 (additional archival candidates).

**Example scan logic:**
```bash
# Find scripts with zero source() references from active pipeline
for script in R/*.R; do
  script_name=$(basename "$script")
  count=$(grep -l "source(\"R/${script_name}\")" R/*.R 2>/dev/null | wc -l)
  if [ "$count" -eq 0 ]; then
    echo "ORPHAN: $script_name (zero source() references)"
  fi
done

# Identify one-off diagnostics (grep for "one-off", "diagnostic", "temp" in headers)
grep -l "one-off\|diagnostic\|temporary" R/*.R

# Flag scripts with "DEPRECATED" or "SUPERSEDED" comments
grep -l "DEPRECATED\|SUPERSEDED" R/*.R
```

### Anti-Patterns to Avoid

- **Don't run data-dependent checks locally on Windows:** PCORnet CSVs are on HiPerGator filesystem only; local checks must be structural
- **Don't block Phase 68 completion waiting for HiPerGator access:** Checklist creation is the deliverable, not execution
- **Don't archive scripts without verifying zero runtime dependencies:** Use grep to confirm no active scripts source() the candidate
- **Don't delete orphan outputs without documenting their origin:** Historical reference value may exist even if generator is archived

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Source() reference parsing | Regex extraction from scratch | Existing R/87 smoke test logic (Test 11) | Already implements multi-pattern extraction with non-commented line filtering |
| Decade validation | Manual file listing per decade | Existing R/87 smoke test logic (Tests 1-8) | Already validates counts, boundaries, and a/b suffix absence |
| Archive README structure | Freeform markdown | Existing R/archive/README.md template | Established 5-field pattern (purpose, why archived, dependencies, safe-to-delete) for consistency |
| HiPerGator validation orchestration | Custom shell script | Markdown checklist with manual execution | SLURM batch jobs add complexity; manual validation is sufficient for one-time verification |

**Key insight:** Phase 67 already created the structural validation tools (R/87 smoke test) and archival documentation patterns (R/archive/README.md). Phase 68 leverages these assets rather than rebuilding.

## Runtime State Inventory

> Phase 68 is a verification/documentation phase with no runtime state changes. Omitting this section per research protocol (only required for rename/refactor/migration phases).

## Common Pitfalls

### Pitfall 1: Assuming Local Smoke Test Covers Full REORG-05

**What goes wrong:** Running R/87 smoke test locally on Windows without PCORnet data gives false confidence that REORG-05 is fully validated.

**Why it happens:** R/87 includes data-dependent checks (RDS loading, DuckDB connection) that will fail silently or be skipped on Windows.

**How to avoid:** Clearly separate structural checks (can run locally) from data-dependent checks (require HiPerGator). Document this split in the HiPerGator checklist.

**Warning signs:** Smoke test passes locally but fails on HiPerGator with "file not found" errors for cache/ RDS artifacts.

### Pitfall 2: Marking REORG-05 Complete Without On-Cluster Validation

**What goes wrong:** REQUIREMENTS.md updated to show REORG-05 complete, but smoke test has never been run successfully on HiPerGator with live data.

**Why it happens:** Verification gate focuses on Windows-compatible checks and assumes checklist creation = validation completion.

**How to avoid:** REORG-05 traceability should show "Phase 68 (structural validation) + Phase 74 (full smoke test execution)" not just "Phase 68 complete."

**Warning signs:** REQUIREMENTS.md shows REORG-05 complete but no VERIFICATION.md artifact documents successful R/87 execution.

### Pitfall 3: Archiving Scripts That Are Indirectly Sourced

**What goes wrong:** Script A sources Script B which sources Script C. Phase 68 scans for direct source() references, finds zero for Script C, and archives it. Pipeline breaks when Script B runs.

**Why it happens:** Scan logic checks for `source("R/script.R")` literals but misses transitive dependencies.

**How to avoid:** Before archiving, run `grep -r "script_name" R/*.R` to check for ANY reference (not just source() calls). Also grep output/ for RDS artifacts generated by the candidate.

**Warning signs:** Archival candidate appears unused but has dated comments like "called by utility module" or "generates intermediate cache file."

### Pitfall 4: Orphan Output Confusion (Historical vs Stale)

**What goes wrong:** output/ contains cancer_site_confirmation.xlsx generated by an archived script. Phase 68 flags it as "orphan" and recommends deletion. User deletes it, losing reference data from earlier analysis milestone.

**Why it happens:** Scan logic identifies "no current generator" but doesn't distinguish "stale from superseded implementation" from "historical reference from completed analysis."

**How to avoid:** When flagging orphan outputs, check git log for recent modifications. If output is >1 month old and untouched, likely historical reference. Document disposition recommendations, not just "safe to delete."

**Warning signs:** Orphan output filename matches archived script name (e.g., sct_code_inventory.R in archive, sct_code_inventory.csv in output/).

### Pitfall 5: ROADMAP Rewrite Breaks Milestone Tracking

**What goes wrong:** Updating ROADMAP.md Phase 68 description to "verification gate" but forgetting to update success criteria. Phase 69 planner reads stale criteria ("6 visualization scripts renumbered to 70-77") and creates tasks for work already done in Phase 66.

**Why it happens:** Description updated but success criteria section left unchanged.

**How to avoid:** When updating ROADMAP Phase 68, rewrite BOTH "Goal" and "Success Criteria" sections to reflect repurposed scope. Success criteria should reference verification deliverables (checklists, scans, documentation updates) not original renumbering tasks.

**Warning signs:** ROADMAP Phase 68 description says "verification gate" but success criteria still mention specific script renumbering targets.

## Code Examples

Verified patterns from existing project codebase:

### Structural Validation (from R/87_smoke_test_full_pipeline.R)

```r
# Source: R/87_smoke_test_full_pipeline.R lines 183-195
# Pattern: Detect stale old-numbered files that should have been renamed

message("\n[9/12] No stale old-numbered files...")

# Check for specific old numbers that should have been renamed
old_numbers <- c("05_visualize_waterfall.R", "11_generate_pptx.R",
                 "16_encounter_analysis.R", "26_smoke_test_backends.R",
                 "07_diagnostics.R", "19_flm_duplicate_dates.R",
                 "33_multi_source_overlap_av_th.R")
stale_files <- character(0)
for (old in old_numbers) {
  if (file.exists(file.path("R", old))) {
    stale_files <- c(stale_files, old)
  }
}
check(glue("No stale old-numbered files (found: {paste(stale_files, collapse=', ') %||% 'none'})"),
      length(stale_files) == 0)
```

### Source() Reference Validation (from R/87_smoke_test_full_pipeline.R)

```r
# Source: R/87_smoke_test_full_pipeline.R lines 211-238
# Pattern: Extract source("R/...") patterns and verify all targets exist

message("\n[11/12] No broken source() references...")

r_files_full <- list.files("R", pattern = "\\.R$", full.names = TRUE)
broken_refs <- character(0)
for (f in r_files_full) {
  lines <- readLines(f, warn = FALSE)
  # Extract source("R/...") patterns (ignore commented lines)
  source_lines <- grep('source\\("R/', lines, value = TRUE)
  source_lines <- grep('^[^#]*source\\("R/', lines, value = TRUE)  # Not commented

  for (line in source_lines) {
    # Extract path from source("R/...")
    matches <- regmatches(line, gregexpr('source\\("R/[^"]+\\.R"\\)', line))
    for (match_list in matches) {
      for (m in match_list) {
        path <- sub('source\\("', '', m)
        path <- sub('"\\)', '', path)
        if (!file.exists(path)) {
          broken_refs <- c(broken_refs, glue("{basename(f)}: {path}"))
        }
      }
    }
  }
}
check(glue("No broken source() calls (found: {paste(broken_refs, collapse=', ') %||% 'none'})"),
      length(broken_refs) == 0)
```

### Archive Documentation Pattern (from R/archive/README.md)

```markdown
# Source: R/archive/README.md lines 11-16
# Pattern: Consistent 5-field structure for archived script documentation

### check_deleted_proton_code.R
- **Purpose:** One-off check for deleted proton therapy CPT code 77521 in PROCEDURES table
- **Why Archived:** Single-use diagnostic; CPT code deletion date verified; no ongoing use
- **Archived:** 2026-06-01 (Phase 67)
- **Dependencies:** 00_config, 01_load_pcornet
- **Safe to Delete:** Yes (one-off audit, results already captured)
```

### Bash Script Count Validation

```bash
# Pattern: Decade-based script counting for boundary verification
# Expected counts based on SCRIPT_INDEX.md

# Foundation (00-09)
foundation_count=$(ls R/0*.R 2>/dev/null | wc -l)
echo "Foundation: $foundation_count (expect 4)"

# Cohort (10-19)
cohort_count=$(ls R/1*.R 2>/dev/null | wc -l)
echo "Cohort: $cohort_count (expect 5)"

# Treatment (20-39)
treatment_count=$(ls R/2*.R 2>/dev/null | wc -l)
echo "Treatment: $treatment_count (expect 10)"

# Cancer (40-59)
cancer_count=$(ls R/4*.R R/5*.R 2>/dev/null | wc -l)
echo "Cancer: $cancer_count (expect 14)"

# Payer/QA (60-69)
payer_count=$(ls R/6*.R 2>/dev/null | wc -l)
echo "Payer/QA: $payer_count (expect 10)"

# Output (70-79)
output_count=$(ls R/7*.R 2>/dev/null | wc -l)
echo "Output: $output_count (expect 6)"

# Test (80-89)
test_count=$(ls R/8*.R 2>/dev/null | wc -l)
echo "Test: $test_count (expect 8)"

# Ad-hoc (90-99)
adhoc_count=$(ls R/9*.R 2>/dev/null | wc -l)
echo "Ad-hoc: $adhoc_count (expect 10)"

# Total
total=$((foundation_count + cohort_count + treatment_count + cancer_count + payer_count + output_count + test_count + adhoc_count))
echo "TOTAL: $total (expect 67)"
```

## Environment Availability

> Phase 68 has no external dependencies beyond standard Windows shell commands and existing R scripts. All verification tools are already present in the environment. Skipping detailed audit per research protocol.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Windows Command Shell | Local structural checks | ✓ | Built-in | — |
| git | Archive verification | ✓ | Assumed present | Manual file inspection |
| R/87_smoke_test_full_pipeline.R | Smoke test reference | ✓ | Current | Manual test recreation |

**Missing dependencies:** None

## Open Questions

### Question 1: Should Phase 68 Update REQUIREMENTS.md Directly?

**What we know:** REQUIREMENTS.md shows REORG-04 and REORG-05 as "Pending" with Phase 68 as responsible phase.

**What's unclear:** Whether Phase 68 should mark these complete (if validation passes) or whether Phase 74 (comprehensive smoke testing) should own REORG-05 completion.

**Recommendation:** Phase 68 marks REORG-04 complete (archival finished in Phase 67). REORG-05 remains "Partial" with note "Phase 68: structural validation; Phase 74: full smoke test execution on HiPerGator."

### Question 2: What Defines "Orphan Output" for Archival?

**What we know:** output/ directory has ~100 files from various scripts. Some generators are now archived. Some outputs are from superseded implementations.

**What's unclear:** Criteria for "safe to delete" vs "historical reference" for orphan outputs.

**Recommendation:** Orphan output classification:
- **Safe to delete:** Generated by archived script, <100KB, no git activity in 30+ days, filename suggests diagnostic (e.g., "debug_", "test_")
- **Historical reference:** Generated by archived script but >1MB or tied to published analysis milestone (e.g., v1.6 cancer site analysis outputs)
- Document classification in Phase 68 verification report; defer actual deletion to human review

### Question 3: Are There Additional Archival Candidates Beyond the 8 from Phase 67?

**What we know:** Phase 67 archived 8 unnumbered scripts. Current pipeline has 67 numbered scripts, some of which may be one-off diagnostics that should live in archive instead.

**What's unclear:** Criteria for archiving numbered scripts (vs. keeping them in ad-hoc decade 90-99).

**Recommendation:** Numbered scripts are archival candidates if:
- Header comments say "one-off" or "diagnostic"
- Zero source() references from other active scripts
- Not listed in any ROADMAP phase deliverables
- Functionality superseded by a later-numbered script
- Phase 68 scans for candidates and documents rationale; actual archival is optional follow-up work

## Sources

### Primary (HIGH confidence)
- `.planning/phases/68-output-test-reorganization/68-CONTEXT.md` - Phase 68 repurposing decisions and scope
- `.planning/REQUIREMENTS.md` - REORG-04 and REORG-05 definitions, traceability table
- `.planning/STATE.md` - Phase 67 completion status, current project position
- `.planning/ROADMAP.md` - Phase 68 original scope vs. absorbed work
- `R/SCRIPT_INDEX.md` - Canonical script numbering reference (67 scripts across 8 decades)
- `R/archive/README.md` - Archive documentation pattern (8 scripts archived in Phase 67)
- `R/87_smoke_test_full_pipeline.R` - Existing smoke test with 12 validation categories
- `.planning/phases/67-cancer-payer-qa-reorganization/67-01-VERIFICATION.md` - Phase 67 gaps and closure

### Secondary (MEDIUM confidence)
- Project filesystem scan (67 numbered scripts, 8 archived, 8 utils verified via bash commands)
- Git commit history for Phase 67 (bceaa62, f60a9f1, de2b54e verified via git log)

### Tertiary (LOW confidence)
- None — all findings verified against project artifacts

## Metadata

**Confidence breakdown:**
- Phase 68 scope: HIGH (explicitly documented in CONTEXT.md and ROADMAP.md repurposing notes)
- REORG-04/REORG-05 requirements: HIGH (directly quoted from REQUIREMENTS.md)
- Existing smoke test coverage: HIGH (R/87 source code analyzed, 12 test categories enumerated)
- Archival patterns: HIGH (R/archive/README.md template extracted from Phase 67 artifacts)
- HiPerGator validation approach: MEDIUM (checklist structure inferred from typical HPC workflows, not project-specific)

**Research date:** 2026-06-01
**Valid until:** 2026-06-30 (stable — verification patterns and smoke test infrastructure unlikely to change)
