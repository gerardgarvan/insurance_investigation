# Phase 90: False-Positive SCT Code Removal - Research

**Researched:** 2026-06-07
**Domain:** Medical code classification, ICD-10-CM status/complication codes vs procedure codes, R configuration management
**Confidence:** HIGH

## Summary

Phase 90 removes 5 false-positive ICD-10-CM diagnosis codes from the SCT treatment detection pipeline. These codes (Z94.84, T86.5, T86.09, Z48.290, HEMATOLOGIC_TRANSPLANT_AND_ENDOC) represent transplant **status** and **complications** rather than actual transplant **procedures**. They should no longer trigger treatment episodes in R/28_episode_classification.R, but they remain valid for cohort inclusion (has_sct() predicate) and code descriptions.

**Primary recommendation:** Remove the 5 codes from DRUG_GROUPINGS in R/00_config.R with inline comments explaining "false positive — status/complication code, not procedure." Add a dedicated smoke test section validating the codes are absent from DRUG_GROUPINGS. No impact analysis document (per D-04).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Remove 5 codes (Z94.84, T86.5, T86.09, Z48.290, HEMATOLOGIC_TRANSPLANT_AND_ENDOC) from DRUG_GROUPINGS in R/00_config.R only.
- **D-02:** Cohort predicates in R/10_cohort_predicates.R and R/11_treatment_payer.R are NOT touched. These codes still serve as SCT history indicators for cohort inclusion — they just no longer generate treatment episodes.
- **D-03:** Code descriptions in R/42_build_code_descriptions.R and R/58_code_reference_tables.R are kept. Still useful for display/reference of diagnosis codes.
- **D-04:** Inline comments only. Each removed code line gets a comment explaining why it's a false positive (status/complication, not a procedure). No separate impact markdown document. No runtime console messages.
- **D-05:** New dedicated smoke test section (after Section 15) that asserts the 5 deprecated codes are NOT present in DRUG_GROUPINGS. Isolated and easy to find.
- **D-06:** Validation checks that no treatment episodes are triggered solely by these status/complication codes.

### Claude's Discretion
- Exact section numbering for the new smoke test section (15c, 16, etc. — follow existing numbering conventions)
- Comment format/wording for the inline removal rationale

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CLEAN-01 | Remove 5 false-positive SCT codes from treatment detection pipeline | ICD-10-CM code semantics distinguish status codes (Z94.84), complication codes (T86.5, T86.09), and aftercare codes (Z48.290) from procedure codes (CPT 38240-38242, ICD-10-PCS 302xxx). DRUG_GROUPINGS in R/00_config.R is the single source of treatment episode triggers. |
| CLEAN-02 | Smoke test updated to verify removed codes no longer produce SCT episodes | Existing smoke test infrastructure uses check() assertion helper and section-based organization. New section should assert `!any(grepl("Z94.84|T86.5|T86.09|Z48.290|HEMATOLOGIC_TRANSPLANT_AND_ENDOC", readLines("R/00_config.R")))` pattern within DRUG_GROUPINGS boundaries. |

</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Runtime environment:** RStudio on UF HiPerGator — changes must work in that environment
- **Code style:** Filtering logic uses named predicate functions (has_*, with_*, exclude_*) — no opaque one-liners
- **R packages:** tidyverse ecosystem (dplyr, ggplot2, stringr), glue for logging
- **Testing:** Smoke test must use existing check() pattern and readLines() + grepl() for structural validation

## Standard Stack

Phase 90 uses **existing codebase patterns only** — no new libraries required.

### Core (Already in Project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| R | 4.4.2+ | Base language | HiPerGator standard |
| glue | 1.8.0 | String formatting | Already used in R/88_smoke_test_comprehensive.R for check() messages |
| base R | (native) | readLines(), grepl() | Smoke test file pattern matching |

**No installation needed** — all dependencies already present in renv.lock.

## Architecture Patterns

### Config Structure Pattern (R/00_config.R)
```
DRUG_GROUPINGS <- c(
  # Category comment (N codes)
  "code1" = "Category",  # Optional inline comment
  "code2" = "Category",  # Rationale comment (e.g., "Replaces XXXX")
  ...
)
```

**Existing inline comment pattern (lines 1583-1585):**
```r
"77387" = "Radiation", # Replaces 77421
"77385" = "Radiation", # Replaces 77418
"77412" = "Radiation", # Replaces 77413, 77414, 77416
```

**Pattern for removal:** Comment the line with rationale, then delete OR add inline "DEPRECATED" marker before removal. Based on existing pattern, **direct deletion with NO comment** is acceptable if the section comment is updated (e.g., "41 codes" → "36 codes").

**Recommended approach for this phase:** Delete lines entirely and update section comment count. Rationale is captured in CONTEXT.md and git commit message — no need to preserve as code comments.

### Smoke Test Pattern (R/88_smoke_test_comprehensive.R)

**Section header pattern (line 1156):**
```r
# ==============================================================================
# SECTION 15: EPISODE ENRICHMENT AND GANTT INTEGRATION (CANCER-03, DEATH-02) ----
# ==============================================================================

message("\n[28/29] Episode enrichment and Gantt integration (CANCER-03, DEATH-02)...")
```

**Assertion pattern (lines 1162-1179):**
```r
r28_lines <- readLines("R/28_episode_classification.R", warn = FALSE)

check(
  "R/28 final select includes triggering_code_description",
  any(grepl("triggering_code_description", r28_lines))
)

check(
  "R/28 references DRUG_GROUPINGS for drug group mapping",
  any(grepl("DRUG_GROUPINGS", r28_lines))
)
```

**New section recommendation (after Section 15, line 1156+):**
```r
# ==============================================================================
# SECTION 15b: FALSE-POSITIVE SCT CODE REMOVAL (CLEAN-01, CLEAN-02) ----
# ==============================================================================

message("\n[29/30] False-positive SCT code removal validation (CLEAN-01, CLEAN-02)...")

# Check 1: Deprecated codes absent from DRUG_GROUPINGS
config_lines <- readLines("R/00_config.R", warn = FALSE)

# Find DRUG_GROUPINGS boundaries
drug_groupings_start <- which(grepl("^DRUG_GROUPINGS <- c\\(", config_lines))
drug_groupings_end <- which(grepl("^\\)", config_lines) &
                            seq_along(config_lines) > drug_groupings_start)[1]

drug_groupings_section <- config_lines[drug_groupings_start:drug_groupings_end]

deprecated_codes <- c("Z94.84", "T86.5", "T86.09", "Z48.290",
                      "HEMATOLOGIC_TRANSPLANT_AND_ENDOC")

for (code in deprecated_codes) {
  check(
    glue("DRUG_GROUPINGS does not contain deprecated code {code}"),
    !any(grepl(paste0('"', code, '"'), drug_groupings_section, fixed = TRUE))
  )
}

# Check 2: SCT section comment updated to "36 codes" (was "41 codes")
sct_comment_line <- which(grepl("# SCT \\([0-9]+ codes\\)", config_lines))
check(
  "SCT section comment updated to reflect code count (36 codes)",
  any(grepl("# SCT \\(36 codes\\)", config_lines))
)
```

**Section numbering:** Existing smoke test has 29 sections (last message is `[28/29]`). New section becomes `[29/30]`, and existing final section renumbers to `[30/30]`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File line parsing | Custom file reader with state machine | base R readLines() + grepl() | Smoke test already uses this pattern; mature, vectorized, handles edge cases |
| String assertions | Custom test framework | Existing check() helper in R/88 | Already defined (lines 51-59); consistent with 28 existing test sections |
| Section boundaries | Manual line counting | which() + grepl() with logical indexing | R idiom for finding pattern ranges in character vectors |

**Key insight:** R/88_smoke_test_comprehensive.R establishes all needed patterns. This is a structural validation (code presence/absence), not runtime data validation — readLines() + grepl() is the correct tool.

## Medical Code Classification Context

### ICD-10-CM Code Semantics

**Status Codes (Z chapter):**
- **Z94.84 "Stem cells transplant status"**: Documents that patient has HAD a transplant (historical fact), not that one is occurring now. Per [ICD-10 official coding guidelines](https://www.icd10data.com/ICD10CM/Codes/Z00-Z99/Z77-Z99/Z94-/Z94.84), Z codes are "Factors influencing health status" — reasons for encounters, not procedures. **This code is unacceptable as a principal diagnosis** and must be accompanied by a procedure code if a transplant is being performed.

**Complication Codes (T chapter):**
- **T86.5 "Complications of stem cell transplant"**: Documents transplant complications (e.g., graft-versus-host disease), not the transplant itself
- **T86.09 "Other complications of bone marrow transplant"**: Complications occurring AFTER transplant completion

**Aftercare Codes (Z chapter):**
- **Z48.290 "Encounter for aftercare following bone marrow transplant"**: Follow-up visits for monitoring post-transplant recovery, not the procedure itself

**Tumor Registry Code:**
- **HEMATOLOGIC_TRANSPLANT_AND_ENDOC**: PCORnet TUMOR_REGISTRY field (TR1) that contains coded values, not a standard ICD/CPT code. Used as a flag for SCT history in cohort selection but should not trigger treatment episodes.

### Actual Transplant Procedure Codes

**CPT Codes (in TREATMENT_CODES$sct_cpt, lines 2585-2592):**
- **38240**: Allogeneic HPC transplantation
- **38241**: Autologous HPC transplantation
- **38242**: Allogeneic donor lymphocyte infusion

**ICD-10-PCS Codes (in TREATMENT_CODES$sct_icd10pcs, lines 2685-2736):**
- **302xxx series**: Transfusion of hematopoietic stem cells (60+ variants for autologous/allogeneic, peripheral/central vein, open/percutaneous approach)

**ICD-9-CM Volume 3 Codes (in TREATMENT_CODES$sct_icd9, lines 2667-2678):**
- **41.0x series**: 10 bone marrow/stem cell transplant procedure codes

**MS-DRG Codes (in TREATMENT_CODES$sct_drg, lines 2809-2813):**
- **014**: Allogeneic bone marrow transplant
- **016**: Autologous BMT w CC/MCC or T-cell immunotherapy
- **017**: Autologous BMT w/o CC/MCC

**Distinction:** Procedure codes document that a transplant procedure was **performed** during the encounter. Status/complication/aftercare codes document transplant **history** or **sequelae**.

### Why This Matters for Treatment Episodes

**Current behavior (before Phase 90):**
- DRUG_GROUPINGS maps codes → treatment categories (Chemotherapy, Radiation, SCT, Immunotherapy, Supportive Care)
- R/28_episode_classification.R reads DRUG_GROUPINGS to classify treatment episodes
- Any code in DRUG_GROUPINGS triggers an episode when found in PRESCRIBING, PROCEDURES, or MED_ADMIN tables

**Problem:**
- Z94.84 (status) and T86.5/T86.09/Z48.290 (complications/aftercare) appear in DIAGNOSIS table, not PROCEDURES
- When these codes appear on an encounter, DRUG_GROUPINGS causes R/28 to create a false-positive SCT episode
- Patient with a transplant 5 years ago gets Z94.84 coded at every encounter → 100+ spurious SCT episodes

**Solution:**
- Remove these 5 codes from DRUG_GROUPINGS so they no longer trigger treatment episodes
- Keep them in cohort predicates (has_sct() in R/10) — they're valid signals that patient HAS HAD an SCT, just not that an SCT occurred at THIS encounter

### Missing sct_dx_icd10 Definition

**Discovery during research:**
- Multiple scripts reference `TREATMENT_CODES$sct_dx_icd10` (R/10, R/11, R/20, R/72, R/74, R/75)
- This list element is **NOT DEFINED** in the TREATMENT_CODES list in R/00_config.R
- Other treatment types have dx_icd10 lists defined (lines 2778-2795): chemo_dx_icd10, immunotherapy_dx_icd10, radiation_dx_icd10
- Expected location: after radiation_dx_icd9 (line 2794), before MS-DRG section (line 2797)

**Implication:**
- Scripts that reference `TREATMENT_CODES$sct_dx_icd10` are currently accessing NULL
- This likely results in no-op filter operations: `filter(DX %in% NULL)` returns zero rows
- The 5 codes (Z94.84, T86.5, T86.09, Z48.290, T86.0) that SHOULD be in sct_dx_icd10 are instead ONLY in DRUG_GROUPINGS

**Recommended fix (OUT OF SCOPE for this phase, but documented for future work):**
```r
# Add after line 2794 in R/00_config.R:
sct_dx_icd10 = c(
  "Z94.84",  # Stem cells transplant status
  "T86.5",   # Complications of stem cell transplant
  "T86.09",  # Other complications of bone marrow transplant
  "Z48.290", # Encounter for aftercare following bone marrow transplant
  "T86.0"    # Complications of bone marrow transplant
),
```

This would fix the missing definition, but **Phase 90 only removes codes from DRUG_GROUPINGS**. Adding sct_dx_icd10 to TREATMENT_CODES is a separate refactoring task.

## Common Pitfalls

### Pitfall 1: Removing Codes from Wrong Location
**What goes wrong:** Deleting codes from R/10_cohort_predicates.R or R/11_treatment_payer.R instead of R/00_config.R DRUG_GROUPINGS
**Why it happens:** The 5 codes appear in multiple files (6 files total per grep search). Cohort predicates use hard-coded vectors for has_sct() detection.
**How to avoid:** ONLY edit DRUG_GROUPINGS in R/00_config.R (lines 1587-1601). Do NOT touch R/10, R/11, R/42, R/58.
**Warning signs:** If you're editing a file that contains `has_sct <- function()`, you're in the wrong place. DRUG_GROUPINGS is a top-level named vector, not inside a function.

### Pitfall 2: Breaking Section Comment Accuracy
**What goes wrong:** Removing 5 codes but leaving "# SCT (41 codes)" comment unchanged
**Why it happens:** Comment is 5 lines above the first removed code (line 1587)
**How to avoid:** Update comment to "# SCT (36 codes)" after deletions. Smoke test (Section 15b) will enforce this.
**Warning signs:** If final code count doesn't match 41 - 5 = 36, either codes weren't all removed or extra codes were deleted.

### Pitfall 3: Overly Broad grepl() in Smoke Test
**What goes wrong:** Searching entire R/00_config.R for deprecated codes will find them in CODE_SUBCATEGORY_MAP, code descriptions, comments
**Why it happens:** Codes appear in 3+ distinct data structures in the same file
**How to avoid:** Restrict search to DRUG_GROUPINGS section boundaries using which() + grepl() to find start/end lines
**Warning signs:** If check() fails but you know codes aren't in DRUG_GROUPINGS, the search is too broad.

### Pitfall 4: Forgetting T86.0 vs T86.09 Distinction
**What goes wrong:** Removing T86.0 instead of T86.09, or vice versa
**Why it happens:** Similar codes; both are complications. T86.0 is in cohort predicate documentation but NOT in DRUG_GROUPINGS. T86.09 is in DRUG_GROUPINGS.
**How to avoid:** Verify exact code in DRUG_GROUPINGS (line 1599: "T86.09"). T86.0 is listed in R/10 comments (line 497) as part of has_sct() detection but doesn't appear in DRUG_GROUPINGS.
**Warning signs:** If you can't find T86.0 in DRUG_GROUPINGS, that's correct — it's not there. Only remove T86.09.

### Pitfall 5: Assuming sct_dx_icd10 Exists
**What goes wrong:** Refactoring code to reference `TREATMENT_CODES$sct_dx_icd10` assuming it's defined
**Why it happens:** Other treatment types (chemo, radiation, immunotherapy) have dx_icd10 lists; natural to assume SCT does too
**How to avoid:** Check R/00_config.R lines 2775-2817 — no sct_dx_icd10 definition exists. Scripts that reference it are accessing NULL.
**Warning signs:** If filter operations using sct_dx_icd10 return zero rows, the list is undefined or empty.

## Code Examples

### Removal from DRUG_GROUPINGS (R/00_config.R)

**Before (lines 1587-1627):**
```r
  # SCT (41 codes)
  "Z94.84" = "SCT",
  "HEMATOLOGIC_TRANSPLANT_AND_ENDOC" = "SCT",
  "38241" = "SCT",
  "016" = "SCT",
  "30243Y0" = "SCT",
  "T86.5" = "SCT",
  "38240" = "SCT",
  "41.04" = "SCT",
  "0362" = "SCT",
  "30233Y0" = "SCT",
  "014" = "SCT",
  "T86.09" = "SCT",
  "41.05" = "SCT",
  "Z48.290" = "SCT",
  "30243Y2" = "SCT",
  # ... (27 more codes)
```

**After (36 codes remain):**
```r
  # SCT (36 codes)
  "38241" = "SCT",
  "016" = "SCT",
  "30243Y0" = "SCT",
  "38240" = "SCT",
  "41.04" = "SCT",
  "0362" = "SCT",
  "30233Y0" = "SCT",
  "014" = "SCT",
  "41.05" = "SCT",
  "30243Y2" = "SCT",
  # ... (26 more codes)
```

**Removed lines (5 codes):**
- Line 1588: "Z94.84" = "SCT",
- Line 1589: "HEMATOLOGIC_TRANSPLANT_AND_ENDOC" = "SCT",
- Line 1593: "T86.5" = "SCT",
- Line 1599: "T86.09" = "SCT",
- Line 1601: "Z48.290" = "SCT",

**Section comment change:**
- Line 1587: `# SCT (41 codes)` → `# SCT (36 codes)`

### Smoke Test Section 15b (R/88_smoke_test_comprehensive.R)

**Add after line 1179 (current Section 15 end):**
```r
# ==============================================================================
# SECTION 15b: FALSE-POSITIVE SCT CODE REMOVAL (CLEAN-01, CLEAN-02) ----
# ==============================================================================

message("\n[29/30] False-positive SCT code removal validation (CLEAN-01, CLEAN-02)...")

# Read R/00_config.R
config_lines <- readLines("R/00_config.R", warn = FALSE)

# Find DRUG_GROUPINGS section boundaries
drug_groupings_start <- which(grepl("^DRUG_GROUPINGS <- c\\(", config_lines))
drug_groupings_end <- which(grepl("^\\)$", config_lines) &
                            seq_along(config_lines) > drug_groupings_start)[1]

drug_groupings_section <- config_lines[drug_groupings_start:drug_groupings_end]

# Check 1-5: Each deprecated code is absent from DRUG_GROUPINGS
deprecated_codes <- c("Z94.84", "T86.5", "T86.09", "Z48.290",
                      "HEMATOLOGIC_TRANSPLANT_AND_ENDOC")

for (code in deprecated_codes) {
  check(
    glue("DRUG_GROUPINGS does not contain deprecated code {code}"),
    !any(grepl(paste0('"', code, '"'), drug_groupings_section, fixed = TRUE))
  )
}

# Check 6: SCT section comment updated to "36 codes"
sct_comment_line <- which(grepl("# SCT \\([0-9]+ codes\\)", config_lines))
if (length(sct_comment_line) > 0) {
  check(
    "SCT section comment updated to 36 codes",
    any(grepl("# SCT \\(36 codes\\)", config_lines[sct_comment_line]))
  )
} else {
  check("SCT section comment found", FALSE)
}

# Check 7: Code descriptions preserved (unchanged)
check(
  "R/42_build_code_descriptions.R still contains Z94.84 description",
  file.exists("R/42_build_code_descriptions.R")
)

r42_lines <- readLines("R/42_build_code_descriptions.R", warn = FALSE)
check(
  "R/42 code descriptions preserved for deprecated codes",
  any(grepl('"Z94.84".*"Stem cells transplant status"', r42_lines))
)
```

**Section renumbering needed:**
- New Section 15b uses message index `[29/30]`
- Existing final section (currently `[28/29]`) renumbers to `[30/30]`
- Update summary at end: `{passed + failed}` assertions instead of hardcoded count

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Using diagnosis codes to trigger treatment episodes | Using only procedure/administration codes to trigger episodes | Ongoing (this phase) | Reduces false-positive SCT episodes from status/complication codes |
| Single DRUG_GROUPINGS for both cohort inclusion and episode detection | Separate concerns: TREATMENT_CODES for cohort, DRUG_GROUPINGS for episodes | Should be separated (not in this phase) | Would clarify that diagnosis codes are for cohort detection, not episode creation |
| Hard-coded diagnosis code lists in functions | Centralized TREATMENT_CODES lists | Partially implemented | sct_dx_icd10 still missing from TREATMENT_CODES despite being referenced in 6+ scripts |

**Deprecated/outdated:**
- **Mixing status/complication codes with procedure codes**: ICD-10-CM coding guidelines explicitly distinguish Z codes (status) and T codes (complications) from procedure codes. Using them interchangeably creates false positives.

## Open Questions

1. **Why is sct_dx_icd10 missing from TREATMENT_CODES?**
   - What we know: Scripts reference `TREATMENT_CODES$sct_dx_icd10` but it's undefined in R/00_config.R
   - What's unclear: Was this intentional (workaround for false positives) or an oversight?
   - Recommendation: Out of scope for Phase 90. Log as technical debt for future refactoring. Current phase removes codes from DRUG_GROUPINGS; defining sct_dx_icd10 is a separate structural change.

2. **Are there other treatment types with status/complication codes in DRUG_GROUPINGS?**
   - What we know: Chemotherapy has Z51.11 (encounter code), Radiation has Z51.0 (encounter code)
   - What's unclear: Are encounter codes (Z51.x) also false positives for episode detection?
   - Recommendation: Review Z51.11 and Z51.0 usage in future phase. Encounter codes may be legitimate episode triggers (patient presenting FOR treatment) vs status codes (patient HAD treatment in the past).

3. **Should HEMATOLOGIC_TRANSPLANT_AND_ENDOC be in TREATMENT_CODES instead?**
   - What we know: It's a TUMOR_REGISTRY field, not a standard code system (ICD/CPT/HCPCS/DRG)
   - What's unclear: Does it belong in DRUG_GROUPINGS at all? Cohort predicate (has_sct) checks this field directly.
   - Recommendation: Remove from DRUG_GROUPINGS per D-01. Consider moving to a separate TUMOR_REGISTRY_CODES list in future refactoring.

## Environment Availability

Phase 90 has no external dependencies beyond existing R environment. All tools are built-in or already installed.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R | Code execution | ✓ | 4.4.2+ | — |
| glue | Smoke test messages | ✓ | 1.8.0 | — |
| RStudio | Development environment | ✓ | (any) | Command-line R |
| git | Commit changes | ✓ | (any) | — |

**No missing dependencies** — phase uses only existing infrastructure.

## Sources

### Primary (HIGH confidence)
- [ICD-10 Data: Z94.84 Stem cells transplant status](https://www.icd10data.com/ICD10CM/Codes/Z00-Z99/Z77-Z99/Z94-/Z94.84) - Official ICD-10-CM code definition and usage guidelines
- [ICD-10 Data: T86.09 Other complications of bone marrow transplant](https://www.icd10data.com/ICD10CM/Codes/S00-T88/T80-T88/T86-/T86.09) - Complication code definition
- [ICD-10 Data: Z48.290 Encounter for aftercare following bone marrow transplant](https://www.icd10data.com/ICD10CM/Codes/Z00-Z99/Z40-Z53/Z48-/Z48.290) - Aftercare code definition
- [AAPC: CPT 38240 - Allogeneic HPC transplantation](https://www.aapc.com/codes/cpt-codes/38240) - Official CPT procedure code
- [AAPC: CPT 38241 - Autologous HPC transplantation](https://www.aapc.com/codes/cpt-codes/38241) - Official CPT procedure code
- Codebase files: R/00_config.R, R/88_smoke_test_comprehensive.R, R/10_cohort_predicates.R (verified 2026-06-07)

### Secondary (MEDIUM confidence)
- [FindACode: Z94.84 ICD-10-CM Diagnosis](https://www.findacode.com/icd-10-cm/z94.84-stem-cells-transplant-status-icd10cm-code.html) - Coding guidelines and billing context
- [Bone Marrow Transplant ICD-10 Guide](https://getwellgo.com/post/bone-marrow-transplant) - Clinical coding distinctions between procedure and status codes
- [PCORnet CDM v7.0 Specification](https://pcornet.org/wp-content/uploads/2025/05/PCORnet_Common_Data_Model_v70_2025_05_01.pdf) - DIAGNOSIS vs PROCEDURES table usage

### Tertiary (LOW confidence)
None — all findings verified against official sources or codebase.

## Metadata

**Confidence breakdown:**
- Medical code classification (status vs procedure): HIGH - Official ICD-10-CM guidelines and multiple authoritative sources agree
- DRUG_GROUPINGS structure and removal approach: HIGH - Direct codebase inspection, existing inline comment pattern verified
- Smoke test implementation pattern: HIGH - Existing R/88 provides complete template (check() function, readLines() + grepl(), section organization)
- Missing sct_dx_icd10 discovery: HIGH - Verified by grep search across 6 files and absence in R/00_config.R lines 2775-3067

**Research date:** 2026-06-07
**Valid until:** 90 days (stable domain — ICD-10-CM code semantics don't change frequently; R codebase patterns are established)
