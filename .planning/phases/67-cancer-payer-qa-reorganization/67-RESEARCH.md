# Phase 67: Post-Renumbering Inventory Cleanup - Research

**Researched:** 2026-06-01
**Domain:** File system operations, script archival, index regeneration
**Confidence:** HIGH

## Summary

Phase 67 addresses three post-renumbering cleanup operations: (1) resolve the 66-prefix script collision by moving the full-pipeline smoke test from `66_smoke_test_full_pipeline.R` to `87_smoke_test_full_pipeline.R` in the test decade, (2) archive 8 unnumbered scripts to `R/archive/` with a README explaining their purpose and status, and (3) regenerate `SCRIPT_INDEX.md` from the filesystem to guarantee accuracy after all moves.

This is purely organizational work with zero functional changes to R code. All operations are file moves, renames, and documentation updates. No source() cross-references need updating because (a) the smoke test scripts are never sourced by other scripts, and (b) the 8 unnumbered scripts have no source() callers (verified in Phase 66 work).

**Primary recommendation:** Execute in strict sequence: (1) move smoke test to 87, (2) create R/archive/ and move unnumbered scripts with README, (3) regenerate SCRIPT_INDEX.md using the Phase 66 pattern (filesystem scan + header extraction). Use git moves (`git mv`) for all renames to preserve history. Single-wave execution is safe — operations are independent and non-breaking.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Phase Repurposing:**
- **D-01:** Phase 67 is repurposed to "Post-Renumbering Inventory Cleanup" — a combined pass that fixes the 66 collision, syncs the index, archives unnumbered scripts, and creates R/archive/. All post-renumbering cleanup in one phase.

**Smoke Test Placement (66-Prefix Collision):**
- **D-02:** Move `66_smoke_test_full_pipeline.R` to `87_smoke_test_full_pipeline.R` in the test decade (80-89). It IS a test script and belongs alongside `86_smoke_test_foundation.R`. This frees position 66 for `66_all_site_duplicate_dates.R` with no collision. The payer/QA decade stays at 10 scripts (60-69).
- **D-03:** After moving the smoke test, no renumbering is needed in the payer/QA decade — `66_all_site_duplicate_dates.R` through `69_per_patient_source_detection.R` keep their current numbers.

**Unnumbered Script Archival:**
- **D-04:** All 8 unnumbered scripts in R/ move to `R/archive/` with a README explaining each script's purpose and why it was archived. This satisfies REORG-04 (deprecated/superseded scripts archived).
- **D-05:** Scripts to archive:
  - `check_deleted_proton_code.R` — one-off CPT 77521 check
  - `date_range_check.R` — quick date range diagnostic
  - `payer_frequency_from_resolved.R` — payer frequency from CSV output
  - `run_phase12_outputs.R` — HiPerGator orchestration helper
  - `sct_code_inventory.R` — SCT evidence inventory
  - `search_C8190.R` — one-off ICD code search
  - `tiered_payer_summary.R` — styled xlsx from payer CSV
  - `treatment_cross_reference.R` — gap report: reference docs vs config

**SCRIPT_INDEX Regeneration:**
- **D-06:** SCRIPT_INDEX.md is regenerated from the filesystem AFTER all moves/renames are complete. Use the same regeneration approach from Phase 66 (read R/*.R, extract header comments, rebuild the entire index). Guaranteed accurate — no manual patching.

### Claude's Discretion

- Archive README format and level of detail per script
- Whether to update source() references inside archived scripts (they won't be run from R/ anymore)
- Smoke test internal reference updates (if 87_smoke_test_full_pipeline.R references its own filename internally)
- Order of operations: move smoke test first, then archive, then regenerate index (or different sequence)

### Deferred Ideas (OUT OF SCOPE)

- Phase 68 was also marked "to be repurposed" — could become script documentation prep or additional cleanup if needed after Phase 67
- Cancer decade (40-53) SCRIPT_INDEX entries may have description inaccuracies beyond the position mismatches — full regeneration from filesystem will catch these
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REORG-04 | Deprecated/superseded scripts moved to R/archive/ folder with README explaining their status | R/archive/ directory creation pattern, README template structure, git mv preservation of history |
| REORG-05 | Smoke test validates no broken cross-references after each renumbering phase (RDS artifacts unchanged, source() calls resolve) | 66→87 rename preserves smoke test functionality; no source() callers to update; standalone test execution pattern |
</phase_requirements>

## Standard Stack

### Core Technologies

All operations use standard Unix/Windows file system commands and git operations. No R package dependencies beyond what's already in the project.

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| git | 2.x+ | File moves with history preservation | `git mv` preserves rename history for blame/log tracking |
| bash/cmd | system default | File system operations | mkdir, mv commands for directory/file operations |
| R (runtime) | 4.4.2+ | Header extraction for index regeneration | read.delim or readLines for parsing script headers |

### Supporting Operations

| Operation | Tool | Purpose | When to Use |
|-----------|------|---------|-------------|
| Directory creation | mkdir | Create R/archive/ | One-time setup before archival |
| File moves | git mv | Rename/move scripts | Preserves history; safer than mv + git add |
| Index regeneration | R script | Parse headers, rebuild markdown | After all moves complete |
| README creation | text editor | Document archived scripts | Standalone artifact in R/archive/ |

**Installation:** No new packages required. All tools already present in project environment.

## Architecture Patterns

### Recommended Operation Sequence

```
Phase 67 Execution Flow:
├── Wave 0-Prep: Verify current state
│   ├── Check: 66_smoke_test_full_pipeline.R exists
│   ├── Check: 87 slot is free (not occupied)
│   └── Check: 8 unnumbered scripts present in R/
├── Task 1: Move smoke test to test decade
│   ├── git mv R/66_smoke_test_full_pipeline.R R/87_smoke_test_full_pipeline.R
│   ├── Update header line 2 in 87_smoke_test_full_pipeline.R
│   ├── Verify: 66 slot now free, 87 exists
│   └── Commit: "feat(67): move full-pipeline smoke test to 87 (test decade)"
├── Task 2: Archive unnumbered scripts
│   ├── mkdir R/archive/
│   ├── git mv R/{8 scripts} R/archive/
│   ├── Create R/archive/README.md with per-script explanations
│   ├── Verify: 8 scripts in archive/, 0 unnumbered in R/
│   └── Commit: "feat(67): archive 8 unnumbered ad-hoc scripts to R/archive/"
└── Task 3: Regenerate SCRIPT_INDEX.md
    ├── Scan R/*.R for numbered scripts (pattern: ^[0-9]{2}_)
    ├── Extract header blocks (lines 1-20) from each script
    ├── Rebuild SCRIPT_INDEX.md using Phase 66 template structure
    ├── Verify: Decade counts correct, 66_smoke_test → 87_smoke_test, no unnumbered listed
    └── Commit: "docs(67): regenerate SCRIPT_INDEX.md after cleanup"
```

### Pattern 1: git mv for History Preservation

**What:** Use `git mv` instead of `mv` + `git add` for all file renames and moves.

**When to use:** Any file that's already tracked in git and needs to be renamed or moved.

**Why:** Preserves git blame and log history. When you later run `git log --follow R/87_smoke_test_full_pipeline.R`, git will show the full history including commits when it was named `66_smoke_test_full_pipeline.R`.

**Example:**
```bash
# GOOD: History preserved
git mv R/66_smoke_test_full_pipeline.R R/87_smoke_test_full_pipeline.R

# AVOID: History broken, appears as delete + add
mv R/66_smoke_test_full_pipeline.R R/87_smoke_test_full_pipeline.R
git add R/87_smoke_test_full_pipeline.R
```

### Pattern 2: README Template for Archived Scripts

**What:** A README.md in R/archive/ documenting each archived script's original purpose and archival reason.

**Structure:**
```markdown
# Archived R Scripts

Scripts in this directory are **no longer part of the active pipeline** but are preserved for reference. They represent one-off investigations, superseded implementations, or HiPerGator orchestration helpers that are environment-specific.

**Do not source() these scripts from active pipeline code.**

---

## Archived Scripts

### check_deleted_proton_code.R
- **Original Purpose:** One-off investigation checking for CPT 77521 (deleted proton therapy code) in PROCEDURES table
- **Why Archived:** Single-use diagnostic completed; findings documented elsewhere
- **Date Archived:** 2026-06-01 (Phase 67)
- **Dependencies:** 00_config, 01_load_pcornet
- **Can Be Deleted:** No (may be useful for future code deletion audits)

[... repeat for each of 8 scripts ...]
```

**When to use:** Any archival operation where scripts are being removed from active use but preserved for reference.

### Pattern 3: SCRIPT_INDEX Regeneration from Filesystem

**What:** Rebuild SCRIPT_INDEX.md by scanning R/ directory and extracting header comments from each script.

**When to use:** After any mass renumbering or reorganization to guarantee accuracy (no manual editing drift).

**Algorithm (from Phase 66):**
1. List all R/*.R files matching `^[0-9]{2}_` pattern
2. Group by decade: 00-09, 10-19, 20-29, 40-59, 60-69, 70-79, 80-89, 90-99
3. For each file, extract:
   - Script name (from filename)
   - Purpose (from header line ~4-6, usually after "# Purpose:" or "# Goal:")
   - Dependencies (from "source()" calls or "# Dependencies:" comments)
4. Rebuild markdown table for each decade
5. Add "Unnumbered Ad-hoc Scripts" section by listing R/*.R files NOT matching `^[0-9]{2}_`
6. Overwrite SCRIPT_INDEX.md

**Key insight:** Don't patch the existing index — regenerate from source of truth (the filesystem + script headers). This eliminates human error from manual updates.

### Anti-Patterns to Avoid

- **Don't manually edit SCRIPT_INDEX.md:** Regenerate from filesystem to avoid drift and errors
- **Don't use mv without git mv:** Loses history tracking; makes future investigation harder
- **Don't skip README in archive/:** Future developers won't know why scripts were archived or if they're safe to delete
- **Don't update source() calls inside archived scripts:** They're no longer run from R/, so internal references are irrelevant

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File rename tracking | Custom rename logger | `git mv` | Git's rename detection is mature and integrated with log/blame |
| Header parsing | Regex-based text extraction | R's `readLines()` + simple header extraction | Avoid over-engineering; headers are simple comment blocks |
| Directory scanning | Recursive file walker | R's `list.files(pattern = "^[0-9]{2}_.*\\.R$")` | Built-in glob patterns handle this perfectly |

**Key insight:** This is file organization work, not complex data processing. Use simple, standard tools (git mv, mkdir, list.files) rather than building abstractions.

## Runtime State Inventory

> This section is omitted — Phase 67 involves only filesystem reorganization (file moves, renames, directory creation). No runtime state (databases, services, OS registrations, secrets, build artifacts) is affected.

## Common Pitfalls

### Pitfall 1: Updating source() Calls That Don't Exist

**What goes wrong:** Spending time searching for source() calls to update when the scripts being moved are never sourced.

**Why it happens:** Habit from previous phases where renumbering required updating dozens of cross-references.

**How to avoid:** Before planning updates, grep for `source.*{script_name}` across R/ directory. If zero matches, no updates needed.

**Warning signs:** Phase 66 SUMMARY documents that unnumbered scripts have "no source() callers" and smoke tests are "standalone test execution" — this was already verified.

**Specific to Phase 67:**
```bash
# Verify no source() calls to smoke test or unnumbered scripts
grep -r "source.*66_smoke_test_full_pipeline" R/
grep -r "source.*check_deleted_proton_code" R/
grep -r "source.*treatment_cross_reference" R/
# All should return zero matches
```

### Pitfall 2: Breaking Smoke Test by Renaming Internal References

**What goes wrong:** The smoke test script may reference its own filename in comments or glue() messages. Renaming the file without updating these internal references creates misleading log output.

**Why it happens:** Scripts often include their own name in header comments or logging output.

**How to avoid:** After `git mv 66_smoke_test_full_pipeline.R 87_smoke_test_full_pipeline.R`, search the file for "66_smoke_test" and replace with "87_smoke_test".

**Warning signs:**
```r
# In header:
# 66_smoke_test_full_pipeline.R -- Full-Pipeline Renumbering Validation
# ^^^^ needs updating to 87

# In logging (less common but possible):
message(glue("Running {here('R/66_smoke_test_full_pipeline.R')}"))
#                              ^^^^^^^^^^^^^^ needs updating
```

**Verification:**
```bash
# After rename
grep -n "66_smoke_test" R/87_smoke_test_full_pipeline.R
# Should return zero matches
```

### Pitfall 3: Forgetting to Update SCRIPT_INDEX After Archive

**What goes wrong:** R/SCRIPT_INDEX.md still lists the 8 unnumbered scripts in the "Unnumbered Ad-hoc Scripts" section even after they've been moved to R/archive/.

**Why it happens:** Index regeneration is deferred to Task 3, but if it's forgotten, the index becomes stale.

**How to avoid:** Make SCRIPT_INDEX regeneration the FINAL task in the phase, after all moves are complete. Verify the "Unnumbered Ad-hoc Scripts" section is now empty (or explicitly states "None — all archived").

**Warning signs:** Running `diff <(grep -A 20 "Unnumbered Ad-hoc" R/SCRIPT_INDEX.md) <(ls R/*.R | grep -v "^[0-9]")` shows discrepancies.

### Pitfall 4: Archive README Too Vague or Too Detailed

**What goes wrong:** Either (a) README says "old scripts" with no detail (useless) or (b) README includes 500 lines of analysis per script (overkill).

**Why it happens:** Uncertainty about the right level of documentation.

**How to avoid:** For each archived script, document:
- One-sentence purpose (what it does)
- One-sentence archival reason (why it's archived)
- Date archived and phase
- Key dependencies (if someone wants to resurrect it)
- Safe to delete? (yes/no with brief rationale)

Target: 5-8 lines per script. Total README: ~60-80 lines for 8 scripts.

**Good example:**
```markdown
### check_deleted_proton_code.R
- **Purpose:** Checks PROCEDURES table for CPT 77521 (deleted proton code)
- **Why Archived:** One-off audit; no ongoing use
- **Archived:** 2026-06-01 (Phase 67)
- **Dependencies:** 00_config, 01_load_pcornet
- **Safe to Delete:** No (may be useful for future code deletion audits)
```

**Bad example (too vague):**
```markdown
### check_deleted_proton_code.R
Old diagnostic script. Not used anymore.
```

**Bad example (too detailed):**
```markdown
### check_deleted_proton_code.R
This script was created during Phase 23 when we needed to investigate whether any
patients had procedures coded with CPT 77521, which was deleted from the AMA CPT
code set before 2024. The script loads the PROCEDURES table using the standard
01_load_pcornet.R pipeline, filters for PX == "77521", and produces a summary...
[300 more words]
```

## Code Examples

### Move Smoke Test to Test Decade

```bash
# Verify current state
test -f R/66_smoke_test_full_pipeline.R && echo "Source exists"
test ! -f R/87_smoke_test_full_pipeline.R && echo "Target slot free"

# Rename with git mv
git mv R/66_smoke_test_full_pipeline.R R/87_smoke_test_full_pipeline.R

# Verify move
test ! -f R/66_smoke_test_full_pipeline.R && echo "Source removed"
test -f R/87_smoke_test_full_pipeline.R && echo "Target created"

# Git status should show rename, not delete + add
git status --short
# R  R/66_smoke_test_full_pipeline.R -> R/87_smoke_test_full_pipeline.R
```

### Update Internal References in Renamed Script

```r
# Open R/87_smoke_test_full_pipeline.R
# Update header (line 2):
# Before:
# 66_smoke_test_full_pipeline.R -- Full-Pipeline Renumbering Validation

# After:
# 87_smoke_test_full_pipeline.R -- Full-Pipeline Renumbering Validation

# Search for any other internal references:
grep -n "66_smoke_test" R/87_smoke_test_full_pipeline.R
# If matches found, replace with 87_smoke_test
```

### Archive Unnumbered Scripts

```bash
# Create archive directory
mkdir -p R/archive

# Move all 8 unnumbered scripts with git mv
git mv R/check_deleted_proton_code.R R/archive/
git mv R/date_range_check.R R/archive/
git mv R/payer_frequency_from_resolved.R R/archive/
git mv R/run_phase12_outputs.R R/archive/
git mv R/sct_code_inventory.R R/archive/
git mv R/search_C8190.R R/archive/
git mv R/tiered_payer_summary.R R/archive/
git mv R/treatment_cross_reference.R R/archive/

# Verify
ls R/archive/ | wc -l
# 8

ls R/ | grep -v "^[0-9]" | grep "\.R$" | wc -l
# 0 (no unnumbered .R files in R/ root)
```

### Regenerate SCRIPT_INDEX.md (Filesystem Scan Pattern)

```r
# R script to regenerate SCRIPT_INDEX.md
# Based on Phase 66 approach

library(glue)

# Scan for numbered scripts
scripts <- list.files("R", pattern = "^[0-9]{2}_.*\\.R$", full.names = FALSE)

# Group by decade
decades <- list(
  "Foundation (00-03)" = scripts[grepl("^0[0-3]_", scripts)],
  "Cohort Building (10-14)" = scripts[grepl("^1[0-4]_", scripts)],
  "Treatment Analysis (20-29)" = scripts[grepl("^2[0-9]_", scripts)],
  "Cancer Site Analysis (40-59)" = scripts[grepl("^[4-5][0-9]_", scripts)],
  "Payer & QA (60-69)" = scripts[grepl("^6[0-9]_", scripts)],
  "Output & Visualization (70-79)" = scripts[grepl("^7[0-9]_", scripts)],
  "Testing (80-89)" = scripts[grepl("^8[0-9]_", scripts)],
  "Ad-hoc & Diagnostics (90-99)" = scripts[grepl("^9[0-9]_", scripts)]
)

# For each script, extract header purpose (simplified example)
extract_purpose <- function(script_path) {
  lines <- readLines(file.path("R", script_path), n = 20)
  # Find line with "Purpose:" or "Goal:" (header comments)
  purpose_line <- lines[grepl("^#.*Purpose:|^#.*Goal:", lines)][1]
  if (!is.na(purpose_line)) {
    return(sub("^#.*Purpose:\\s*|^#.*Goal:\\s*", "", purpose_line))
  }
  return("(no header comment)")
}

# Build markdown
index_md <- "# R Script Index\n\nQuick-reference map...\n\n"
for (decade_name in names(decades)) {
  index_md <- paste0(index_md, "## ", decade_name, "\n\n")
  index_md <- paste0(index_md, "| Script | Purpose |\n")
  index_md <- paste0(index_md, "|--------|---------|\\n")
  for (script in decades[[decade_name]]) {
    purpose <- extract_purpose(script)
    index_md <- paste0(index_md, glue("| {script} | {purpose} |\n"))
  }
  index_md <- paste0(index_md, "\n")
}

# Add unnumbered section (should be empty after Phase 67)
unnumbered <- list.files("R", pattern = "^[^0-9].*\\.R$", full.names = FALSE)
index_md <- paste0(index_md, "## Unnumbered Ad-hoc Scripts\n\n")
if (length(unnumbered) == 0) {
  index_md <- paste0(index_md, "None — all unnumbered scripts archived to R/archive/.\n\n")
} else {
  for (script in unnumbered) {
    index_md <- paste0(index_md, glue("- {script}\n"))
  }
}

# Write
writeLines(index_md, "R/SCRIPT_INDEX.md")
message("SCRIPT_INDEX.md regenerated")
```

## Environment Availability

> Skipped — Phase 67 requires only git, bash/cmd, and R (all already present in project environment). No external dependencies, services, or runtimes beyond existing setup.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual index editing | Filesystem scan + header extraction regeneration | Phase 66 | Eliminates human error in index updates |
| mv + git add | git mv | Standard practice | Preserves rename history for git log/blame |

**Deprecated/outdated:** N/A — this is organizational work using stable, mature tools.

## Open Questions

None. All operations are straightforward file moves and documentation updates. Phase 66 already verified that:
- Unnumbered scripts have no source() callers
- Smoke test scripts are standalone (not sourced by other scripts)
- Test decade slots 87-89 are available
- SCRIPT_INDEX regeneration pattern works reliably

## Sources

### Primary (HIGH confidence)
- Phase 66 CONTEXT.md (D-01 through D-06) — locked decisions for this phase
- Phase 66 SUMMARY.md (66-03) — SCRIPT_INDEX regeneration pattern, smoke test structure
- REQUIREMENTS.md — REORG-04 (archival), REORG-05 (smoke test validation)
- Filesystem verification (ls, grep commands on current R/ directory)

### Secondary (MEDIUM confidence)
- Git documentation for `git mv` behavior and rename tracking
- R documentation for list.files(), readLines() (standard base R functions)

### Tertiary (LOW confidence)
- None — all guidance comes from project-specific verified sources

## Metadata

**Confidence breakdown:**
- Operations sequence: HIGH — verified from Phase 66 execution pattern
- git mv usage: HIGH — standard git operation with well-documented behavior
- SCRIPT_INDEX regeneration: HIGH — reusing exact pattern from Phase 66
- Archival approach: MEDIUM — README template is discretionary (user choice on detail level)

**Research date:** 2026-06-01
**Valid until:** 90+ days (stable file system operations; no API or library changes)
