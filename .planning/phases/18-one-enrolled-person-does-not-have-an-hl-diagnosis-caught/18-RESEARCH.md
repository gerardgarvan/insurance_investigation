# Phase 18: One Enrolled Person Does Not Have an HL Diagnosis Caught - Research

**Researched:** 2026-04-07
**Domain:** Debugging single-patient exclusion in R-based ICD code matching pipeline
**Confidence:** HIGH

## Summary

Phase 18 addresses a single-patient investigation where one enrolled patient is classified as "Neither" (HL_VERIFIED=0) despite user expectation of HL evidence. The investigation workflow is HiPerGator-first: user runs existing gap analysis script (`09_dx_gap_analysis.R`), shares the diagnostic CSV output, and Claude diagnoses the root cause. The fix is targeted — either add the specific missing code or document correct exclusion.

This is a classic debugging pattern in clinical cohort pipelines where systematic code lists (149 HL codes) may miss edge cases (recent ICD variant additions, site-specific coding practices, or format mismatches). The research confirms all investigation tools already exist in the codebase; the task is diagnosing which of 5 possible root causes applies.

**Primary recommendation:** Execute gap analysis first to identify patient's exact ICD codes, then apply targeted fix (code addition, normalization fix, or documentation). No pipeline redesign needed.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** The patient is enrolled but classified as "Neither" — they have lymphoma/cancer codes visible in the gap analysis but the specific codes haven't been examined yet.
- **D-02:** The investigation starts by examining `neither_lymphoma_codes.csv` (output from `09_dx_gap_analysis.R`) to identify the patient's exact ICD codes. This is a HiPerGator-first step: user runs the gap analysis, shares the CSV, then Claude diagnoses the root cause.
- **D-03:** Possible root causes to check: (a) missing C81.xx variant in `ICD_CODES$hl_icd10`, (b) DX_TYPE mismatch preventing matching, (c) code normalization issue in `normalize_icd()`, (d) histology code outside 9650-9667 range, (e) patient has non-HL lymphoma codes and is correctly excluded.
- **D-04:** If root cause is a missing code in the ICD list, add just the specific missing code(s). No broad audit of all C81 variants — targeted fix only.
- **D-05:** If the patient turns out to have non-HL lymphoma codes (correctly excluded), document the finding and close — no code changes needed.
- **D-06:** If root cause is a normalization or matching bug (e.g., `normalize_icd()` failing on a specific format), fix the bug in `utils_icd.R`.
- **D-07:** After any fix, run a full pipeline rerun from `04_build_cohort.R` to verify the updated HL_SOURCE breakdown and cohort count. This confirms both the fix and no regressions.
- **D-08:** If the result is "document and close" (patient correctly excluded), update the gap analysis notes but no pipeline rerun needed.

### Claude's Discretion
- How to structure the diagnostic script changes if a code needs to be added
- Whether to update `09_dx_gap_analysis.R` with the findings
- Exact format of documentation if the exclusion is confirmed correct
</user_constraints>

## Standard Stack

### Core Debugging Tools (Already in Codebase)
| Component | Location | Purpose | Current State |
|-----------|----------|---------|---------------|
| Gap analysis script | `R/09_dx_gap_analysis.R` | Extracts all diagnosis codes for "Neither" patients, filters to lymphoma/cancer subset (C81-C96, 200-208), cross-references enrollment/TR | Already implemented (Phase 7 artifact, not executed) |
| ICD matching function | `R/utils_icd.R::is_hl_diagnosis()` | Compares DX against 149 HL codes with normalization | Already implemented |
| Normalization function | `R/utils_icd.R::normalize_icd()` | Removes dots from ICD codes (C81.00 → C8100) | Already implemented |
| HL code lists | `R/00_config.R::ICD_CODES` | 77 ICD-10 codes (C81.00-C81.99 + C81.xA variants), 72 ICD-9 codes (201.xx), 13 histology codes (9650-9667) | Already implemented with FY2025 updates |
| Cohort predicate | `R/03_cohort_predicates.R::has_hodgkin_diagnosis()` | Applies HL matching to DIAGNOSIS/TR, generates HL_SOURCE map, writes excluded "Neither" patients to CSV | Already implemented |

### Investigation Workflow (No New Libraries Needed)
1. **Trigger gap analysis:** User runs `source("R/09_dx_gap_analysis.R")` on HiPerGator (depends on full pipeline completion first via `source("R/04_build_cohort.R")`)
2. **Extract diagnostic CSV:** User shares `output/diagnostics/neither_lymphoma_codes.csv` containing all lymphoma/cancer codes for "Neither" patients
3. **Diagnose root cause:** Claude examines CSV to identify which of 5 root causes applies (D-03)
4. **Apply fix:** Targeted edit to `00_config.R` (add missing code), `utils_icd.R` (fix normalization), or documentation
5. **Validate:** Full pipeline rerun to verify cohort count change

### No Installation Required
This is a debugging phase, not a feature addition. All necessary R packages are already loaded:
- **dplyr, stringr** (tidyverse) — data manipulation, string matching
- **readr** — CSV I/O for diagnostic outputs
- **glue** — logging messages
- **janitor** — tabyl() for gap classification crosstabs

## Architecture Patterns

### Recommended Investigation Structure
```
Phase 18 workflow:
1. User: source("R/04_build_cohort.R")          # Full pipeline to generate excluded_no_hl_evidence.csv
2. User: source("R/09_dx_gap_analysis.R")       # Gap analysis → neither_lymphoma_codes.csv
3. User shares: output/diagnostics/neither_lymphoma_codes.csv
4. Claude examines: specific DX codes for the 1 patient
5. Root cause diagnosis (one of 5 from D-03)
6. Targeted fix (code addition / normalization fix / document-only)
7. Validation: full pipeline rerun + cohort count check
```

### Root Cause Diagnosis Decision Tree
```
neither_lymphoma_codes.csv contains patient X with DX=Y, DX_TYPE=Z

├─ Is Y in ICD_CODES$hl_icd10 (if Z=10) or ICD_CODES$hl_icd9 (if Z=09)?
│  ├─ NO → Check normalized: normalize_icd(Y) in normalize_icd(ICD_CODES$hl_icd10)?
│  │  ├─ NO → ROOT CAUSE (a): Missing code variant (add Y to 00_config.R)
│  │  └─ YES → ROOT CAUSE (c): Normalization bug (fix utils_icd.R)
│  └─ YES → ROOT CAUSE (b): DX_TYPE mismatch (patient has ICD-10 code but DX_TYPE="09" or vice versa)
│
├─ Is Y a non-HL lymphoma code (C82-C96, 200/202-208)?
│  └─ YES → ROOT CAUSE (e): Correctly excluded (document and close)
│
└─ Does patient have TR histology code H outside 9650-9667?
   └─ YES → ROOT CAUSE (d): Histology outside HL range (document and close OR expand if HL-relevant)
```

### Pattern 1: Missing Code Addition (Root Cause a)
**What:** ICD code exists in data but not in `ICD_CODES$hl_icd10`/`hl_icd9`
**When to use:** CSV shows code like `C81.9A` (remission variant) or `201.2` (short form without 5th digit) that isn't in the 149-code list
**Example:**
```r
# In R/00_config.R, line 121-146
ICD_CODES <- list(
  hl_icd10 = c(
    # ... existing codes ...
    "C81.9A"  # Add missing remission variant
  ),
  # ...
)
```
**Historical precedent:** Phase 5-6 added C81.xA remission codes and 201.x short forms after gap analysis (see CONTEXT.md note: "15 'Neither' patients had C81.9A missed by original list")

### Pattern 2: Normalization Bug Fix (Root Cause c)
**What:** `normalize_icd()` fails to handle a specific format variation
**When to use:** CSV shows code in unusual format (e.g., lowercase, extra whitespace, non-standard delimiter)
**Example:**
```r
# In R/utils_icd.R, line 36-44
normalize_icd <- function(icd_code) {
  if (all(is.na(icd_code))) {
    return(icd_code)
  }
  # Uppercase, remove dots, PLUS trim whitespace and handle edge case X
  toupper(str_trim(str_remove_all(icd_code, "\\.")))
}
```

### Pattern 3: Documentation-Only (Root Cause e)
**What:** Patient has non-HL lymphoma (e.g., C82.xx follicular, C83.xx non-follicular, 200.xx reticulosarcoma)
**When to use:** CSV confirms patient excluded correctly per clinical protocol
**Example:**
```r
# No code changes needed.
# Update gap analysis output or add inline comment to 09_dx_gap_analysis.R:
# "Patient X: C83.30 (diffuse large B-cell lymphoma, unspecified site) — correctly excluded (non-HL)"
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ICD code list expansion | Manual web scraping of ICD-10-CM 2026 codes | Targeted fix based on actual data gap | Pipeline already handles 99% of HL codes; only add codes that appear in this cohort |
| DX_TYPE validation | Cross-table DX_TYPE audit across all DIAGNOSIS records | Single-patient inspection via gap analysis CSV | This is a 1-patient bug, not a systematic data quality issue (full audit is Phase 7 scope) |
| Normalization testing | Comprehensive test suite for all ICD format variations | Fix specific observed failure case | `normalize_icd()` already handles dotted/undotted — only extend if CSV shows a missed case |
| Pipeline regression testing | Automated unit tests for is_hl_diagnosis() | Full pipeline rerun + manual cohort count check | Exploratory pipeline on HiPerGator (no testthat infrastructure per Out of Scope) |

**Key insight:** This is a single-patient debugging task, not a systematic data quality project. The gap analysis script already enumerates all diagnosis codes for excluded patients — the investigation is diagnostic analysis of that output, not building new infrastructure.

## Common Pitfalls

### Pitfall 1: Assuming Missing Code Without Checking Normalization
**What goes wrong:** Add ICD code to config when the real issue is format mismatch (e.g., DX_TYPE mislabeled)
**Why it happens:** Gap analysis CSV shows code not in list, tempting to immediately add it
**How to avoid:** Always check BOTH raw code and DX_TYPE in CSV. Verify `is_hl_diagnosis("C81.10", "10")` returns TRUE in R console before assuming code is missing
**Warning signs:** Code looks valid (C81.xx format) but DX_TYPE is "09" (should be "10")

### Pitfall 2: Broad Code List Expansion
**What goes wrong:** "While we're here, let's add all possible C81 variants from the ICD-10-CM 2026 spec"
**Why it happens:** Desire to prevent future similar issues
**How to avoid:** D-04 explicitly constrains to targeted fix. Only add codes that appear in THIS COHORT's data
**Warning signs:** Proposing to add >5 new codes when gap analysis shows only 1 patient with 1 missing code

### Pitfall 3: Skipping Full Pipeline Validation
**What goes wrong:** Fix the code, verify the specific patient now matches, but miss regression (other patients now incorrectly included)
**Why it happens:** Single-patient focus creates tunnel vision
**How to avoid:** D-07 requires full `04_build_cohort.R` rerun. Compare HL_SOURCE breakdown before/after (expect +1 in "DIAGNOSIS only" or "Both", -1 in "Neither")
**Warning signs:** Validation limited to `is_hl_diagnosis()` console test without cohort rebuild

### Pitfall 4: Confusing HL Variants with Non-HL Lymphomas
**What goes wrong:** Assume any C8x.xx code is HL (patient has C82.xx follicular lymphoma, not C81.xx HL)
**Why it happens:** Lymphoma codes cluster in C81-C96; easy to misread
**How to avoid:** C81.xx is HL ONLY. C82-C96 are non-HL lymphomas (correctly excluded). Confirm code starts with C81 before assuming it's a missing HL variant
**Warning signs:** CSV shows C82.xx, C83.xx, or C85.xx codes — these are non-HL

### Pitfall 5: Forgetting Histology Source
**What goes wrong:** Focus exclusively on DIAGNOSIS table codes, miss that patient has TR histology code outside 9650-9667 range
**Why it happens:** CONTEXT.md emphasizes DIAGNOSIS codes; TR is secondary
**How to avoid:** `has_hodgkin_diagnosis()` checks BOTH sources. If patient has no DIAGNOSIS match, check `neither_patient_summary.csv` for `has_tr_record=TRUE` and examine histology codes
**Warning signs:** Patient has TR record but zero lymphoma/cancer codes in DIAGNOSIS

## Code Examples

Verified patterns from existing codebase:

### Diagnose Root Cause in R Console
```r
# Load config and utils
source("R/00_config.R")

# Simulate patient's code from neither_lymphoma_codes.csv
patient_dx <- "C81.9A"     # Example: remission variant
patient_dx_type <- "10"

# Test current matching (should return FALSE if missing)
is_hl_diagnosis(patient_dx, patient_dx_type)
# => FALSE (confirms code not in list)

# Check if normalization is the issue
normalize_icd(patient_dx) %in% normalize_icd(ICD_CODES$hl_icd10)
# => FALSE (confirms missing code, not normalization bug)

# Root cause: Missing code variant (add to 00_config.R)
```

### Add Missing Code to Config (Root Cause a)
```r
# File: R/00_config.R
# Location: Line 143-145 (within hl_icd10 vector)

ICD_CODES <- list(
  hl_icd10 = c(
    # ... existing C81.0x through C81.9x codes ...

    # C81.xA: Hodgkin lymphoma, in remission (FY2025 ICD-10-CM, effective Oct 2024)
    # Found in OneFlorida+ data — 15 "Neither" patients had C81.9A missed by original list
    "C81.0A", "C81.1A", "C81.2A", "C81.3A", "C81.4A", "C81.7A", "C81.9A",

    # Phase 18: Add specific missing code found in gap analysis
    "C81.XY"  # <- EXAMPLE: replace with actual code from CSV
  ),
  # ...
)
```
**Source:** Existing pattern from Phase 5-6 C81.xA addition (lines 143-145 in `00_config.R`)

### Validate Fix with Full Pipeline
```r
# After code addition in 00_config.R, run full pipeline
source("R/04_build_cohort.R")

# Check HL_SOURCE breakdown (expect +1 in DIAGNOSIS/Both, -1 in Neither)
# Output will show updated counts in console via has_hodgkin_diagnosis() logging

# Verify specific patient now included
cohort <- read_csv("output/cohort/hl_cohort.csv")
filter(cohort, ID == "PATIENT_ID_FROM_CSV")  # Should now appear in cohort
```

### Document Correct Exclusion (Root Cause e)
```r
# No code changes needed. Add comment to gap analysis output or script.

# Option 1: Inline comment in 09_dx_gap_analysis.R after Section 6 summary
# Line ~346, after recommendation message:
message("\n--- Phase 18 Investigation (2026-04-07) ---")
message("Patient X (ID: ABC123): C83.30 (diffuse large B-cell lymphoma, unspecified site)")
message("  Diagnosis: Non-HL lymphoma — correctly excluded from HL cohort")
message("  No pipeline changes needed.")

# Option 2: Update neither_patient_summary.csv with manual annotation
# Add column INVESTIGATION_NOTES: "Non-HL lymphoma (C83.30) - correct exclusion"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Static ICD code list (2024) | Dynamic expansion via gap analysis (2026) | Phase 5-6 (C81.xA variants) | Reduced "Neither" count from 34 to 19 patients |
| Manual code inspection in raw CSV | Gap analysis script with lymphoma subset filtering | Phase 7 (planned, implemented but not executed) | Automates diagnosis code extraction for excluded patients |
| DIAGNOSIS-only HL identification | Dual-source HL_SOURCE tracking (DIAGNOSIS + TR) | Phase 5-6 (D-20) | Captures HL patients with TR-only evidence (no DIAGNOSIS codes) |

**Current state (Phase 18):** Pipeline has 149 HL codes (77 ICD-10, 72 ICD-9) with FY2025 updates (C81.xA remission variants, 201.x short forms). Gap analysis tooling exists but hasn't been executed on current cohort. This phase applies that tooling to the single remaining "Neither" patient.

## Environment Availability

> No external dependencies for this phase — all tools are R scripts in the codebase.

**Step 2.6: SKIPPED (no external dependencies identified)**

This phase uses only existing R scripts (`09_dx_gap_analysis.R`, `utils_icd.R`, `00_config.R`) and base R/tidyverse functions already loaded by the pipeline. No CLIs, services, or runtimes beyond RStudio on HiPerGator (established in Phase 1).

## Validation Architecture

> Section omitted: `workflow.nyquist_validation` is explicitly set to false in `.planning/config.json`.

## Sources

### Primary (HIGH confidence)
- **Codebase inspection:** All 4 canonical reference files read (`R/utils_icd.R`, `R/00_config.R`, `R/03_cohort_predicates.R`, `R/09_dx_gap_analysis.R`)
- **CONTEXT.md:** User decisions D-01 through D-08 provide complete investigation workflow
- **Phase 5-6 precedent:** Historical example of missing code addition (C81.xA variants) documented in 00_config.R comments (lines 143-145)
- **ICD-10-CM 2026 spec:** Confirmed C81.xx code structure (subtypes 0-4, 7, 9 with anatomic sites 0-9 and remission variant A)

### Secondary (MEDIUM confidence)
- **Gap analysis script completeness:** `09_dx_gap_analysis.R` implements all 7 sections per Phase 7 design but hasn't been executed on current cohort (no `neither_lymphoma_codes.csv` in output/diagnostics/)
- **OneFlorida+ data context:** Comments in `00_config.R` reference 15 "Neither" patients with C81.9A and 3 with short-form 201.x codes found in prior gap analysis (specific IDs not in repo)

### Tertiary (LOW confidence)
- None — this is a codebase investigation phase with no external research needed

## Metadata

**Confidence breakdown:**
- Investigation workflow: HIGH - Complete gap analysis script exists, user decisions provide clear diagnostic tree
- Root cause taxonomy: HIGH - All 5 root causes are observable from existing codebase patterns
- Fix patterns: HIGH - Historical precedent for code addition (C81.xA), normalization is straightforward string manipulation

**Research date:** 2026-04-07
**Valid until:** 90 days (stable — ICD code lists only change annually in Oct, normalization logic is mature)
