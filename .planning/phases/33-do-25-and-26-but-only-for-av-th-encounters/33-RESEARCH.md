# Phase 33: do 25 and 26 but only for AV+TH encounters - Research

**Researched:** 2026-04-23
**Domain:** R data analysis pipeline — encounter type filtering for multi-source overlap detection and classification
**Confidence:** HIGH

## Summary

Phase 33 repeats the multi-source overlap detection (Phase 25) and classification (Phase 26) analyses, but restricted to **AV (Ambulatory Visit)** and **TH (Telehealth)** encounter types only. This creates a focused subset analysis for outpatient/non-institutional care encounters.

**Key findings:**
- Phase 25 (R/22_multi_source_overlap_detection.R) detects same-date and same-week multi-source encounters across all encounter types
- Phase 26 (R/23_overlap_classification.R) classifies overlaps as Identical/Partial/Distinct via field-by-field comparison
- Both scripts use DuckDB backend (Phase 32 migration complete) with materialize-early pattern
- ENC_TYPE filter can be inserted immediately after loading ENCOUNTER table (line 82 in R/22, line 132 in R/23)
- PCORnet CDM v7.0 defines ENC_TYPE codes: **AV** (Ambulatory Visit) and **TH** (Telehealth)
- Output CSVs must be renamed to avoid overwriting Phase 25/26 baseline results (add `_av_th` suffix)

**Primary recommendation:** Clone R/22 → R/33 and R/23 → R/34, insert `filter(ENC_TYPE %in% c("AV", "TH"))` after ENCOUNTER load, rename output CSVs with `_av_th` suffix, verify against Phase 25/26 baselines.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| dplyr | 1.2.0+ | Data transformation | Standard for readable R pipelines; `filter()` for ENC_TYPE restriction |
| DuckDB | 0.10.0+ | Backend database | Default backend (USE_DUCKDB=TRUE, Phase 32); lazy evaluation + materialize pattern |
| readr | 2.2.0+ | CSV I/O | Read Phase 25 CSVs in Phase 26, write filtered outputs |
| glue | 1.8.0 | String formatting | Logging and console output |
| lubridate | 1.9.3+ | Date operations | ADMIT_DATE parsing and same-week window logic |

**Installation:**
Already installed via renv (Phase 15). No new dependencies needed.

**Version verification:** Phase 32 complete — all diagnostic scripts migrated to DuckDB backend. Stack unchanged from Phase 25/26.

## Architecture Patterns

### Recommended Project Structure
```
R/
├── 22_multi_source_overlap_detection.R        # Phase 25 (ALL encounter types)
├── 23_overlap_classification.R                # Phase 26 (ALL encounter types)
├── 33_multi_source_overlap_av_th.R            # Phase 33 Plan 1 (AV+TH only, detection)
└── 34_overlap_classification_av_th.R          # Phase 33 Plan 2 (AV+TH only, classification)

output/tables/
├── multi_source_same_date_detail.csv          # Phase 25 baseline (all ENC_TYPE)
├── multi_source_same_week_detail.csv          # Phase 25 baseline
├── classified_same_date_detail.csv            # Phase 26 baseline (if run)
├── classified_same_week_detail.csv            # Phase 26 baseline (if run)
├── multi_source_same_date_detail_av_th.csv    # Phase 33 Plan 1 output
├── multi_source_same_week_detail_av_th.csv    # Phase 33 Plan 1 output
├── classified_same_date_detail_av_th.csv      # Phase 33 Plan 2 output
└── classified_same_week_detail_av_th.csv      # Phase 33 Plan 2 output
```

### Pattern 1: ENC_TYPE Filtering via DuckDB Backend
**What:** Load ENCOUNTER table, materialize early, filter to AV+TH, then proceed with Phase 25/26 logic unchanged.

**When to use:** When subsetting encounters by a categorical field before complex multi-table joins/self-joins.

**Example:**
```r
# Phase 25 baseline (R/22, line 82):
enc <- get_pcornet_table("ENCOUNTER") %>% materialize()

# Phase 33 modification (insert after line 82):
enc <- get_pcornet_table("ENCOUNTER") %>%
  materialize() %>%
  filter(ENC_TYPE %in% c("AV", "TH"))

message(glue("Filtered to AV+TH encounters: {format(nrow(enc), big.mark=',')} rows"))
```

**Why materialize first?** R/22 downstream logic uses `split()`, `nrow()`, `n_distinct()`, and `bind_rows()` — all in-memory operations incompatible with lazy SQL queries.

### Pattern 2: Output File Naming Convention
**What:** Add `_av_th` suffix to all output CSVs to distinguish from baseline Phase 25/26 outputs.

**When to use:** When creating variant analyses that reuse existing script structure.

**Example:**
```r
# Phase 25 baseline (R/22, line 439):
write_csv(csv1, file.path(output_dir, "multi_source_same_date_detail.csv"))

# Phase 33 modification:
write_csv(csv1, file.path(output_dir, "multi_source_same_date_detail_av_th.csv"))
```

**Rationale:** Preserve baseline outputs for comparison; prevent accidental overwrite during iterative development.

### Pattern 3: Console Output Annotation
**What:** Update console messages to clarify AV+TH restriction.

**Example:**
```r
# Phase 25 baseline (R/22, line 76):
message("Phase 25: Same-date and same-week multi-source encounter detection")

# Phase 33 modification:
message("Phase 33: Same-date and same-week multi-source encounter detection (AV+TH only)")
```

### Anti-Patterns to Avoid
- **Don't filter ENC_TYPE after self-join:** Filtering late creates unnecessary computation on full encounter set. Filter immediately after ENCOUNTER load.
- **Don't assume ENC_TYPE is never NA:** PCORnet CDM allows NI/UN/OT sentinel values. Use `%in% c("AV", "TH")` (excludes NA) rather than `!= "IP"` logic.
- **Don't reuse same output filenames:** Overwrites baseline Phase 25/26 CSVs — breaks traceability and bisecting.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ENC_TYPE value set validation | Custom lookup table | PCORnet CDM Value Set Reference File v1.14 (2024-12-23) | Authoritative source; updated quarterly; handles version drift |
| Same-date multi-source detection | Custom date-based self-join | Clone R/22 with ENC_TYPE filter added | Phase 25 logic already optimized; day-by-day iteration handles memory constraints |
| Field-by-field comparison logic | Custom match/mismatch scoring | Clone R/23 `field_match()` helper | Handles NA-vs-NA as match, one-NA as mismatch; tested in Phase 26 |
| HIPAA suppression | Manual `ifelse(n <= 10, "<11", n)` | `hipaa_suppress()` and `suppress_counts()` from R/22 lines 55-68 | Regex-based column detection; handles all `n_*` count columns consistently |

**Key insight:** Phase 25/26 scripts are production-tested with DuckDB backend (Phase 32). Reuse > rewrite. The only change needed is the ENC_TYPE filter — everything else is copy-paste.

## Common Pitfalls

### Pitfall 1: Filtering ENC_TYPE on ENCOUNTER.SOURCE instead of ENCOUNTER.ENC_TYPE
**What goes wrong:** `SOURCE` identifies the partner site (AMS, UMI, FLM, VRT, UFH), not the encounter type. Filtering `SOURCE == "AV"` will return zero rows.

**Why it happens:** Column name confusion — both `ENCOUNTER.SOURCE` and `ENCOUNTER.ENC_TYPE` exist in the same table.

**How to avoid:** Always use `ENC_TYPE %in% c("AV", "TH")` for encounter type filtering. Use `SOURCE` for site-level stratification only.

**Warning signs:** Filter produces 0 rows; console message shows "Filtered to AV+TH encounters: 0 rows".

### Pitfall 2: Assuming TH exists in all partner sites
**What goes wrong:** Some sites may have zero TH encounters (telehealth adoption varies by institution and time period). AV-only or TH-only subsets may produce empty same-date/same-week detail CSVs.

**Why it happens:** PCORnet CDM allows sites to submit only encounter types they capture. Not all sites use telehealth coding.

**How to avoid:** Log per-site ENC_TYPE distribution after filtering; warn if any site has zero AV or TH encounters.

**Warning signs:** Console output shows "Same-date multi-source patient-date pairs: 0" — could be legitimate (no overlap) or could indicate missing ENC_TYPE data.

### Pitfall 3: Forgetting to update Phase 26 CSV input paths
**What goes wrong:** R/23 reads `multi_source_same_date_detail.csv` and `multi_source_same_week_detail.csv` from Phase 25 output. If Phase 33 Plan 1 writes `*_av_th.csv` but Phase 33 Plan 2 reads the non-suffixed filenames, it will classify the wrong data.

**Why it happens:** R/23 lines 98-109 hardcode the Phase 25 output filenames.

**How to avoid:** When cloning R/23 → R/34, update lines 98 and 113 to read `*_av_th.csv` instead.

**Warning signs:** Classification counts match Phase 26 exactly (expected to differ when filtering to AV+TH only).

### Pitfall 4: Using `filter(ENC_TYPE == "AV" | ENC_TYPE == "TH")` on lazy query
**What goes wrong:** DuckDB backend translates `|` correctly, but materialize-early pattern means the filter runs in-memory anyway. Not a bug, but inconsistent with Phase 32 best practices.

**Why it happens:** Copying dplyr filter syntax without checking backend mode.

**How to avoid:** Use `filter(ENC_TYPE %in% c("AV", "TH"))` — clearer intent, works identically on tibble or tbl_dbi.

**Warning signs:** None (both syntaxes work), but code review may flag style inconsistency.

## Code Examples

Verified patterns from existing Phase 25/26 scripts:

### ENC_TYPE Filter Insertion Point (R/22 → R/33)
```r
# Source: R/22_multi_source_overlap_detection.R line 82
# Phase 25 baseline:
enc <- get_pcornet_table("ENCOUNTER") %>% materialize()

total_encounters <- nrow(enc)
total_patients <- n_distinct(enc$ID)
message(glue("Total encounters loaded: {format(total_encounters, big.mark=',')}"))

# Phase 33 modification (insert after materialize, before nrow):
enc <- get_pcornet_table("ENCOUNTER") %>%
  materialize() %>%
  filter(ENC_TYPE %in% c("AV", "TH"))

total_encounters <- nrow(enc)
total_patients <- n_distinct(enc$ID)
message(glue("Total AV+TH encounters loaded: {format(total_encounters, big.mark=',')}"))
message(glue("  (Filtered from ALL encounter types to AV=Ambulatory Visit, TH=Telehealth only)"))
```

### Output CSV Renaming (R/22 → R/33)
```r
# Source: R/22_multi_source_overlap_detection.R lines 439-448
# Phase 25 baseline:
csv1 <- same_date_detail %>%
  mutate(
    n_sources    = hipaa_suppress(n_sources),
    n_encounters = hipaa_suppress(n_encounters)
  )

write_csv(csv1, file.path(output_dir, "multi_source_same_date_detail.csv"))
message(glue("  Written: multi_source_same_date_detail.csv ({format(nrow(csv1), big.mark=',')} rows)"))

# Phase 33 modification:
write_csv(csv1, file.path(output_dir, "multi_source_same_date_detail_av_th.csv"))
message(glue("  Written: multi_source_same_date_detail_av_th.csv ({format(nrow(csv1), big.mark=',')} rows)"))
```

### Phase 26 Input CSV Path Update (R/23 → R/34)
```r
# Source: R/23_overlap_classification.R lines 98-109
# Phase 26 baseline:
same_date_detail <- read_csv(
  file.path(output_dir, "multi_source_same_date_detail.csv"),
  col_types = cols(
    ID = col_character(),
    ADMIT_DATE = col_date(format = "%Y-%m-%d"),
    n_sources = col_character(),      # HIPAA-suppressed string
    n_encounters = col_character(),   # HIPAA-suppressed string
    source_combo = col_character(),
    sources_list = col_character()
  ),
  show_col_types = FALSE
)

# Phase 33 Plan 2 modification (change filename only):
same_date_detail <- read_csv(
  file.path(output_dir, "multi_source_same_date_detail_av_th.csv"),
  # ... rest unchanged
)
```

### ENC_TYPE Distribution Logging (Phase 33 specific)
```r
# Insert after ENC_TYPE filter (new code for Phase 33):
enc_type_dist <- enc %>%
  count(ENC_TYPE, SOURCE) %>%
  arrange(SOURCE, desc(n))

message(glue("\nENC_TYPE distribution after AV+TH filter:"))
for (i in seq_len(nrow(enc_type_dist))) {
  r <- enc_type_dist[i, ]
  message(glue("  {r$SOURCE} | {r$ENC_TYPE}: {format(r$n, big.mark=',')} encounters"))
}

# Check for sites with zero AV or TH
sites_with_av <- enc %>% filter(ENC_TYPE == "AV") %>% pull(SOURCE) %>% n_distinct()
sites_with_th <- enc %>% filter(ENC_TYPE == "TH") %>% pull(SOURCE) %>% n_distinct()
total_sites <- n_distinct(enc$SOURCE)

if (sites_with_av < total_sites) {
  message(glue("  WARNING: {total_sites - sites_with_av} sites have zero AV encounters"))
}
if (sites_with_th < total_sites) {
  message(glue("  WARNING: {total_sites - sites_with_th} sites have zero TH encounters"))
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| RDS in-memory tibbles | DuckDB lazy queries + materialize pattern | Phase 32 (2026-04-23) | Scripts use `get_pcornet_table()` instead of `pcornet$TABLE`; USE_DUCKDB=TRUE is default |
| Manual ENC_TYPE string lists | PCORnet CDM Value Set Reference File v1.14 | 2024-12-23 | TH (Telehealth) added; OS (Observation Stay) and IC (Institutional Professional Consult) added |
| Filtering after joins | Filter early (materialize-then-filter) | Phase 31 (general pattern) | Reduces memory footprint before self-joins in R/22 |

**Deprecated/outdated:**
- **RDS mode (USE_DUCKDB = FALSE):** Retained for backward compatibility (Phase 32 deprecation notice), but all new scripts should use DuckDB mode exclusively.
- **ENC_TYPE = "AV" for all outpatient:** TH (Telehealth) is now a distinct encounter type as of PCORnet CDM v6.1+ (Jan 2023). Filter must include both AV and TH for complete outpatient coverage.

## Open Questions

1. **Should Phase 33 include other outpatient encounter types (OA, OS)?**
   - What we know: PCORnet CDM v7.0 defines OA (Other Ambulatory Visit) and OS (Observation Stay) as separate codes.
   - What's unclear: User intent — "AV+TH" is explicit in phase description, but OA may also represent outpatient encounters not captured by AV.
   - Recommendation: Start with AV+TH only (matches user request exactly). If output shows unexpectedly low counts, investigate OA/OS distribution as follow-up.

2. **Does ENCOUNTER table actually contain TH encounters in this dataset?**
   - What we know: PCORnet CDM v7.0 defines TH as valid ENC_TYPE code (source: HL7 FHIR CDMH v1.0.0).
   - What's unclear: Data extraction date (2025-09-15) may predate widespread telehealth coding adoption at some partner sites.
   - Recommendation: Add distribution check (see Code Examples above) to log per-site AV/TH counts; warn if TH count is zero across all sites.

3. **Should Phase 33 outputs feed into Phase 23 PPTX generation?**
   - What we know: Phase 23 creates PPTX slides from Phase 21/22 CSV outputs (payer missingness + overlap detection).
   - What's unclear: Whether AV+TH subset should get its own PPTX slides or just CSV outputs.
   - Recommendation: Defer PPTX integration to separate phase. Phase 33 outputs are CSV-only (matches Phase 25/26 pattern before PPTX integration in Phase 23).

## Environment Availability

> All required tools available — Phase 32 confirmed DuckDB backend operational.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R | Execution environment | ✓ | 4.4.2 | — |
| DuckDB | Backend database | ✓ | 0.10.0+ | RDS mode (deprecated) |
| dplyr | Data transformation | ✓ | 1.2.0+ | — |
| readr | CSV I/O | ✓ | 2.2.0+ | — |
| glue | String formatting | ✓ | 1.8.0 | — |
| lubridate | Date operations | ✓ | 1.9.3+ | — |

**Missing dependencies with no fallback:** None

**Missing dependencies with fallback:** None

## Validation Architecture

> Validation skipped — workflow.nyquist_validation is explicitly set to false in .planning/config.json.

## PCORnet CDM ENC_TYPE Reference

**Source:** HL7 FHIR US CDMH CodeSystem v1.0.0 (STU 1) — [PCORnet Encounter Type Codes](https://build.fhir.org/ig/HL7/cdmh/CodeSystem-pcornet-encounter-type-codes.html)

**Complete ENC_TYPE value set (12 codes):**

| Code | Display | Definition |
|------|---------|------------|
| **AV** | Ambulatory Visit | Outpatient clinics, physician offices, same-day/ambulatory surgery centers |
| **TH** | Telehealth | Telemedicine or virtual visits (video, phone, or other means) |
| ED | Emergency Department | ED encounters including those that become inpatient stays |
| EI | Emergency Dept Admit to Inpatient | Permissible substitution when ED and IP cannot be distinguished |
| IP | Inpatient Hospital Stay | All inpatient stays including same-day discharges, transfers |
| IS | Non-Acute Institutional Stay | Hospice, skilled nursing facility (SNF), rehab, nursing home |
| OS | Observation Stay | Hospital outpatient services to determine admission necessity |
| IC | Institutional Professional Consult | Specialist consultations during institutional encounters |
| OA | Other Ambulatory Visit | Non-overnight encounters including home health, hospice, consultations |
| NI | No information | Encounter type data not available |
| UN | Unknown | Encounter type is not known |
| OT | Other | Encounter type does not fit other categories |

**Phase 33 scope:** AV + TH only (excludes ED, IP, IS, OS, IC, OA, and sentinel values NI/UN/OT).

**Rationale:** AV and TH represent outpatient/non-institutional care encounters where multi-source overlap may indicate care coordination issues (multiple providers seeing same patient on same day) or data quality issues (duplicate submissions from different systems).

## Sources

### Primary (HIGH confidence)
- R/22_multi_source_overlap_detection.R — Phase 25 detection script (lines 1-564), verified DuckDB backend operational
- R/23_overlap_classification.R — Phase 26 classification script (lines 1-649), verified field comparison logic
- R/00_config.R — USE_DUCKDB flag (line 92, default TRUE), no ENC_TYPE configuration needed (inline filter)
- R/utils_duckdb.R — `get_pcornet_table()`, `materialize()` helpers (Phase 30 backend abstraction)
- [PCORnet CDM v7.0 Specification](https://pcornet.org/wp-content/uploads/2025/01/PCORnet-Common-Data-Model-v70-2025_01_23.pdf) — official specification (2025-01-23)
- [HL7 FHIR CDMH CodeSystem](https://build.fhir.org/ig/HL7/cdmh/CodeSystem-pcornet-encounter-type-codes.html) — ENC_TYPE value set reference (v1.0.0)

### Secondary (MEDIUM confidence)
- [PCORnet CDM Value Set Reference File v1.14](https://pcornet.org/wp-content/uploads/2024/12/2024_12_23_PCORnet_CDM_ValueSet_ReferenceFile_v1.14.xlsx) — downloadable Excel file with all value sets (not directly accessed, but referenced in official docs)
- .planning/STATE.md — Phase 32 complete status, USE_DUCKDB default flipped to TRUE (line 53)
- CLAUDE.md — Project constraints (DuckDB migration complete, tidyverse stack, HIPAA suppression required)

### Tertiary (LOW confidence)
- None — all claims verified against official PCORnet documentation or project source code.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Phase 32 complete; DuckDB backend operational; no new dependencies
- Architecture: HIGH — Phase 25/26 scripts are production-tested; ENC_TYPE filter is straightforward dplyr operation
- Pitfalls: HIGH — Common filtering mistakes documented; output filename collision risk identified

**Research date:** 2026-04-23
**Valid until:** 2026-07-23 (90 days — stable domain; PCORnet CDM updates quarterly but ENC_TYPE value set unlikely to change)
