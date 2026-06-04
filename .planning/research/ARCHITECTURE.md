# Architecture Patterns: Local Testing Infrastructure for R Pipeline

**Domain:** Clinical data pipeline testing
**Researched:** 2026-06-03
**Confidence:** HIGH

## Executive Summary

Local testing infrastructure for the PCORnet R pipeline requires three architectural layers: (1) environment auto-detection in R/00_config.R using `Sys.info()["sysname"]` with `.Renviron` override capability, (2) test fixture CSVs in `tests/fixtures/` matching PCORnet CDM schema with ~20 synthetic patients covering clinical edge cases, and (3) modified DuckDB ingest path (R/03) that accepts custom data sources. The existing architecture is well-suited for this addition — R/00_config.R already centralizes all paths, R/01_load_pcornet.R handles CSV-to-RDS conversion, and R/88_smoke_test_comprehensive.R validates pipeline integrity. No structural changes needed; only conditional path switching and fixture creation.

## Recommended Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Environment Detection (R/00_config.R SECTION 1)                 │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 1. Check Sys.getenv("R_TESTING_ENV")  [explicit override]   │ │
│ │ 2. Check Sys.info()["sysname"]         [Windows vs Linux]   │ │
│ │ 3. Check existence of test fixtures   [tests/fixtures/]    │ │
│ │ 4. Set IS_LOCAL flag + conditional paths                    │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Path Configuration (R/00_config.R CONFIG list)                  │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ IF IS_LOCAL:                                                 │ │
│ │   data_dir    = "tests/fixtures"                             │ │
│ │   cache_dir   = tempdir() / "rds"                            │ │
│ │   duckdb_path = tempdir() / "pcornet.duckdb"                 │ │
│ │ ELSE (HiPerGator):                                           │ │
│ │   data_dir    = "/orange/erin.mobley-hl.bcu/Mailhot_V1..."  │ │
│ │   cache_dir   = "/blue/erin.mobley-hl.bcu/clean/rds"         │ │
│ │   duckdb_path = "/blue/.../clean/duckdb/pcornet.duckdb"      │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Data Loading Pipeline (UNCHANGED FLOW)                          │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ R/01_load_pcornet.R                                          │ │
│ │   - Reads CSVs from CONFIG$data_dir (auto-resolves)         │ │
│ │   - Writes RDS cache to CONFIG$cache$raw_dir (auto-resolves)│ │
│ │   - NO CODE CHANGES (paths already configurable)            │ │
│ └─────────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ R/03_duckdb_ingest.R                                         │ │
│ │   - Reads RDS from CONFIG$cache$raw_dir                      │ │
│ │   - Writes DuckDB to CONFIG$cache$duckdb_path                │ │
│ │   - NO CODE CHANGES (paths already configurable)            │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Testing/Validation                                               │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ R/88_smoke_test_comprehensive.R                              │ │
│ │   - Add: Environment detection validation                    │ │
│ │   - Add: Test fixture schema validation                      │ │
│ │   - Add: DuckDB ingest success on fixtures                   │ │
│ │   - Existing: 27 structural checks (unchanged)               │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Component Boundaries

| Component | Responsibility | Modified? | Communicates With |
|-----------|---------------|-----------|-------------------|
| **R/00_config.R SECTION 1** | Environment detection, path switching | **YES** (new detection logic) | None (reads OS/env vars) |
| **R/00_config.R CONFIG list** | Path configuration based on IS_LOCAL | **YES** (conditional paths) | R/01, R/03, all scripts |
| **tests/fixtures/** | Hand-crafted PCORnet CSVs (~20 patients) | **NEW** | R/01_load_pcornet.R |
| **tests/fixtures/README.md** | Documentation of fixture edge cases | **NEW** | Human readers |
| **R/01_load_pcornet.R** | CSV → RDS conversion | NO (already uses CONFIG paths) | R/00_config.R, tests/fixtures/ |
| **R/03_duckdb_ingest.R** | RDS → DuckDB conversion | NO (already uses CONFIG paths) | R/00_config.R, RDS cache |
| **R/88_smoke_test_comprehensive.R** | Pipeline integrity validation | **YES** (add env + fixture checks) | R/00_config.R, tests/fixtures/ |
| **get_pcornet_table() dispatcher** | Backend-agnostic table access | NO (transparent to env) | DuckDB or RDS (unchanged) |
| **.Renviron (project-level, optional)** | Explicit environment override | **NEW** (optional) | R/00_config.R via Sys.getenv() |

## Data Flow

### Local Development Flow (Windows)

```
┌──────────────────┐
│ Developer laptop │
│ (Windows 10/11)  │
└────────┬─────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ R/00_config.R:                                        │
│   Sys.info()["sysname"] == "Windows"                 │
│   → IS_LOCAL = TRUE                                   │
│   → data_dir = "tests/fixtures"                       │
│   → cache_dir = tempdir() / "rds"                     │
│   → duckdb_path = tempdir() / "pcornet.duckdb"        │
└────────┬─────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ tests/fixtures/                                       │
│   ENROLLMENT_Mailhot_V1.csv     (~20 patients)       │
│   DIAGNOSIS_Mailhot_V1.csv      (HL dx codes)        │
│   ENCOUNTER_Mailhot_V1.csv      (multi-payer)        │
│   PROCEDURES_Mailhot_V1.csv     (treatment codes)    │
│   PRESCRIBING_Mailhot_V1.csv    (chemo RxNorm CUI)   │
│   DEMOGRAPHIC_Mailhot_V1.csv    (birth dates, race)  │
│   DEATH_Mailhot_V1.csv          (death dates)        │
│   + 8 more tables (minimal required rows)            │
└────────┬─────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ R/01_load_pcornet.R:                                  │
│   vroom(tests/fixtures/*.csv)                         │
│   → parse dates with parse_pcornet_date()            │
│   → saveRDS(tempdir()/rds/TABLE.rds)                 │
└────────┬─────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ R/03_duckdb_ingest.R:                                 │
│   readRDS(tempdir()/rds/*.rds)                        │
│   → DBI::dbWriteTable(tempdir()/pcornet.duckdb)      │
│   → CREATE INDEX on ID, ENCOUNTERID                   │
└────────┬─────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ R/88_smoke_test_comprehensive.R:                      │
│   ✓ Environment detected as local                     │
│   ✓ All 15 fixture CSVs present                       │
│   ✓ Schema matches PCORnet CDM                        │
│   ✓ DuckDB ingest successful                          │
│   ✓ get_pcornet_table() returns data                  │
└────────┬─────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ Developer validates key logic:                        │
│   - Payer harmonization (dual-eligible detection)    │
│   - ICD code normalization (NLPHL vs classical HL)   │
│   - Treatment episode grouping (28-day cycles)        │
│   - Cancer category linkage (encounter-level)        │
└───────────────────────────────────────────────────────┘
```

### HiPerGator Production Flow (UNCHANGED)

```
┌──────────────────┐
│ HiPerGator SLURM │
│ (Linux, RStudio) │
└────────┬─────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ R/00_config.R:                                        │
│   Sys.info()["sysname"] == "Linux"                   │
│   → IS_LOCAL = FALSE                                  │
│   → data_dir = "/orange/erin.mobley-hl.bcu/..."      │
│   → cache_dir = "/blue/.../clean/rds"                 │
│   → duckdb_path = "/blue/.../clean/duckdb/pcornet..."│
└────────┬─────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────┐
│ Production PCORnet CSVs (22 tables, 6300+ patients)  │
│   /orange/erin.mobley-hl.bcu/Mailhot_V1_20250915/    │
└────────┬─────────────────────────────────────────────┘
         │
         ▼
         (existing pipeline flow — no changes)
```

## New Components Detail

### 1. Environment Detection Code (R/00_config.R SECTION 1)

**Location:** R/00_config.R, immediately after SECTION 1 header (before CONFIG list)

**Purpose:** Auto-detect local vs HiPerGator and set IS_LOCAL flag

**Implementation:**
```r
# ==============================================================================
# SECTION 1A: ENVIRONMENT DETECTION ----
# ==============================================================================
# Auto-detect local development (Windows) vs HiPerGator production (Linux).
# Override via .Renviron: R_TESTING_ENV=local or R_TESTING_ENV=production
#
# Detection hierarchy:
#   1. R_TESTING_ENV environment variable (explicit override)
#   2. Sys.info()["sysname"] (Windows = local, Linux = HiPerGator)
#   3. Fallback to production mode if ambiguous

IS_LOCAL <- FALSE  # Default to production (safe fallback)

# Check for explicit override
env_override <- Sys.getenv("R_TESTING_ENV", unset = "")
if (env_override == "local") {
  IS_LOCAL <- TRUE
  message("[00_config] Environment: LOCAL (R_TESTING_ENV override)")
} else if (env_override == "production") {
  IS_LOCAL <- FALSE
  message("[00_config] Environment: PRODUCTION (R_TESTING_ENV override)")
} else {
  # Auto-detect based on OS
  os_type <- Sys.info()["sysname"]
  if (os_type == "Windows") {
    IS_LOCAL <- TRUE
    message("[00_config] Environment: LOCAL (Windows detected)")
  } else if (os_type == "Linux") {
    IS_LOCAL <- FALSE
    message("[00_config] Environment: PRODUCTION (Linux/HiPerGator detected)")
  } else {
    # Darwin (macOS) or other Unix-alike → assume local
    IS_LOCAL <- TRUE
    message(glue::glue("[00_config] Environment: LOCAL ({os_type} detected, assuming dev)"))
  }
}
```

**Why this approach:**
- **Sys.info()["sysname"]** is R's standard environment detection ([R manual](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Sys.info.html))
- **R_TESTING_ENV override** enables CI/CD or edge cases where OS detection is wrong
- **Safe fallback to production** prevents accidental fixture use on HiPerGator
- **Message logging** makes detection transparent in logs

### 2. Conditional Path Configuration (R/00_config.R CONFIG list)

**Location:** R/00_config.R, modify existing CONFIG list definition

**Changes:**
```r
CONFIG <- list(
  # Data directory: Raw PCORnet CDM CSV files
  # LOCAL: tests/fixtures/ (hand-crafted synthetic patients)
  # PRODUCTION: /orange/erin.mobley-hl.bcu/Mailhot_V1_20250915 (real cohort)
  data_dir = if (IS_LOCAL) {
    "tests/fixtures"
  } else {
    "/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915"
  },

  # Project directory: R scripts and workspace (unchanged)
  project_dir = if (IS_LOCAL) {
    getwd()  # Use current working directory on local
  } else {
    "/blue/erin.mobley-hl.bcu/R"
  },

  # Output directory: Figures, tables, cohort files (unchanged)
  output_dir = "output",

  # Performance tuning (vroom multi-threaded CSV loading)
  # LOCAL: Single-threaded (small fixtures load instantly)
  # PRODUCTION: Match SLURM --cpus-per-task allocation
  performance = list(
    num_threads = if (IS_LOCAL) 1 else 16
  ),

  # RDS Cache Settings
  cache = list(
    # LOCAL: Use R's temp directory (auto-cleaned on session end)
    # PRODUCTION: Persistent blue storage
    cache_dir = if (IS_LOCAL) {
      file.path(tempdir(), "rds_cache")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds"
    },

    force_reload = FALSE,

    raw_dir = if (IS_LOCAL) {
      file.path(tempdir(), "rds_cache", "raw")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds/raw"
    },

    cohort_dir = if (IS_LOCAL) {
      file.path(tempdir(), "rds_cache", "cohort")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds/cohort"
    },

    outputs_dir = if (IS_LOCAL) {
      file.path(tempdir(), "rds_cache", "outputs")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds/outputs"
    },

    duckdb_dir = if (IS_LOCAL) {
      file.path(tempdir(), "duckdb")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/duckdb"
    },

    duckdb_path = if (IS_LOCAL) {
      file.path(tempdir(), "duckdb", "pcornet.duckdb")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb"
    }
  )
)
```

**Why tempdir() for local:**
- Auto-cleaned on R session exit (no manual cleanup needed)
- Cross-platform (Windows/macOS/Linux)
- No gitignore pollution (not in repo)
- Matches R testing best practices ([testthat fixtures](https://testthat.r-lib.org/articles/test-fixtures.html))

### 3. Test Fixture Directory Structure (NEW)

```
tests/
├── fixtures/                               # NEW
│   ├── README.md                           # Edge case documentation
│   ├── ENROLLMENT_Mailhot_V1.csv          # 20 patients, multi-site
│   ├── DIAGNOSIS_Mailhot_V1.csv           # HL + NLPHL + other cancers
│   ├── ENCOUNTER_Mailhot_V1.csv           # Multi-payer, dual-eligible, same-day
│   ├── PROCEDURES_Mailhot_V1.csv          # Treatment codes (CPT/HCPCS)
│   ├── PRESCRIBING_Mailhot_V1.csv         # Chemo RxNorm CUIs (ABVD, BV+AVD, Nivo+AVD)
│   ├── DEMOGRAPHIC_Mailhot_V1.csv         # Birth dates, race, sex
│   ├── DEATH_Mailhot_V1.csv               # Death dates (5 patients)
│   ├── CONDITION_Mailhot_V1.csv           # Minimal (0 rows OK)
│   ├── DISPENSING_Mailhot_V1.csv          # Minimal (0 rows OK)
│   ├── MED_ADMIN_Mailhot_V1.csv           # Minimal (0 rows OK)
│   ├── LAB_RESULT_Mailhot_V1.csv          # Minimal (0 rows OK)
│   ├── PROVIDER_Mailhot_V1.csv            # Oncology specialty (5 providers)
│   ├── TUMOR_REGISTRY1_Mailhot_V1.csv     # HL morphology codes
│   ├── TUMOR_REGISTRY2_Mailhot_V1.csv     # Minimal (0 rows OK)
│   └── TUMOR_REGISTRY3_Mailhot_V1.csv     # Minimal (0 rows OK)
└── testthat/                               # FUTURE (out of scope for v2.2)
    └── (reserved for unit tests)
```

**Why this structure:**
- Matches testthat conventions ([test fixtures](https://testthat.r-lib.org/articles/test-fixtures.html))
- `tests/fixtures/` is discoverable (standard R pattern)
- `README.md` documents edge cases inline with data
- Filename pattern matches production (`{TABLE}_Mailhot_V1.csv`)

### 4. Test Fixture Content Strategy

**20 synthetic patients covering:**

| Edge Case | Patient IDs | Tables | Why Critical |
|-----------|-------------|--------|--------------|
| **Dual-eligible (Medicare+Medicaid)** | P001, P002 | ENCOUNTER | Tests hierarchical payer resolution (Medicaid priority) |
| **NLPHL vs classical HL** | P003 (NLPHL), P004 (classical) | DIAGNOSIS | Tests C81.0 breakout logic (Phase 75) |
| **Multiple cancers (HL + other)** | P005 | DIAGNOSIS | Tests encounter-level cancer linkage (Phase 61) |
| **SCT patient (code 0362)** | P006 | PROCEDURES | Tests SCT detection tightening (Phase 60) |
| **Death with post-death activity** | P007 | DEATH, ENCOUNTER | Tests death date validation (Phase 59) |
| **Same-day multi-payer encounters** | P008 | ENCOUNTER | Tests tiered same-day resolution (Phase 37) |
| **Orphan diagnosis code (no encounter)** | P009 | DIAGNOSIS | Tests orphan dx preservation (Phase 82) |
| **First-line regimen (ABVD)** | P010 | PRESCRIBING | Tests regimen detection (Phase 61) |
| **First-line regimen (BV+AVD)** | P011 | PRESCRIBING | Tests dropped-agent tolerance |
| **First-line regimen (Nivo+AVD)** | P012 | PRESCRIBING | Tests novel regimen detection |
| **Missing payer codes (NI, UN)** | P013 | ENCOUNTER | Tests payer sentinel value fallback |
| **Tumor registry dates only** | P014 | TUMOR_REGISTRY1 | Tests TR-sourced HL diagnosis |
| **Multi-site patient (AMS + UMI)** | P015 | ENROLLMENT | Tests primary site filtering |
| **7-day gap cancer confirmation** | P016 | DIAGNOSIS | Tests cancer summary refinement (Phase 77) |
| **1900 sentinel date** | P017 | DIAGNOSIS | Tests 1900 date filtering (Phase 17) |
| **HL in remission (C81.9A)** | P018 | DIAGNOSIS | Tests remission code coverage |
| **Bare 201 ICD-9 code** | P019 | DIAGNOSIS | Tests parent code matching |
| **Multi-source overlap (AV+TH)** | P020 | ENCOUNTER | Tests overlap classification (Phase 33-34) |
| **Minimal patients (valid, no edge)** | P021-P025 | ALL | Ensure pipeline runs without errors |

**CSV size estimates:**
- ENROLLMENT: 25 rows (20 patients + 5 duplicates for multi-site)
- DIAGNOSIS: 80 rows (~4 dx per patient average)
- ENCOUNTER: 150 rows (~7.5 encounters per patient)
- PRESCRIBING: 60 rows (chemo patients only)
- PROCEDURES: 40 rows (treatment codes)
- DEMOGRAPHIC: 20 rows (1 per patient)
- DEATH: 5 rows (P007, P017, P018, P019, P020)
- Others: 0-10 rows (minimal schema compliance)

**Total fixture size:** ~500 rows across 15 tables, <50KB total (trivial to version control)

### 5. Smoke Test Enhancements (R/88_smoke_test_comprehensive.R)

**New checks (add after SECTION 3):**

```r
# ==============================================================================
# SECTION 3B: ENVIRONMENT DETECTION VALIDATION ----
# ==============================================================================

message("\n[3B/30] Environment detection validation...")

check("IS_LOCAL flag exists in config", exists("IS_LOCAL"))

if (exists("IS_LOCAL")) {
  os_type <- Sys.info()["sysname"]

  # Validate Windows → IS_LOCAL = TRUE
  if (os_type == "Windows") {
    check("Windows detected → IS_LOCAL = TRUE", IS_LOCAL == TRUE)
  }

  # Validate Linux → IS_LOCAL = FALSE (unless overridden)
  if (os_type == "Linux") {
    env_override <- Sys.getenv("R_TESTING_ENV", unset = "")
    if (env_override == "local") {
      check("Linux + R_TESTING_ENV=local → IS_LOCAL = TRUE", IS_LOCAL == TRUE)
    } else {
      check("Linux → IS_LOCAL = FALSE", IS_LOCAL == FALSE)
    }
  }

  # Validate data_dir matches environment
  if (IS_LOCAL) {
    check(
      "IS_LOCAL → data_dir points to tests/fixtures",
      grepl("tests/fixtures", CONFIG$data_dir, fixed = TRUE)
    )
    check(
      "IS_LOCAL → cache_dir points to tempdir",
      grepl(tempdir(), CONFIG$cache$cache_dir, fixed = TRUE)
    )
  } else {
    check(
      "Production → data_dir points to /orange",
      grepl("/orange/erin.mobley", CONFIG$data_dir, fixed = TRUE)
    )
    check(
      "Production → cache_dir points to /blue",
      grepl("/blue/erin.mobley", CONFIG$cache$cache_dir, fixed = TRUE)
    )
  }
}

# ==============================================================================
# SECTION 3C: TEST FIXTURE SCHEMA VALIDATION ----
# ==============================================================================

message("\n[3C/30] Test fixture schema validation...")

if (exists("IS_LOCAL") && IS_LOCAL) {
  fixture_dir <- CONFIG$data_dir

  check(
    glue("Fixture directory exists: {fixture_dir}"),
    dir.exists(fixture_dir)
  )

  if (dir.exists(fixture_dir)) {
    # Check for required fixture CSVs (core tables only)
    required_fixtures <- c(
      "ENROLLMENT_Mailhot_V1.csv",
      "DIAGNOSIS_Mailhot_V1.csv",
      "ENCOUNTER_Mailhot_V1.csv",
      "DEMOGRAPHIC_Mailhot_V1.csv"
    )

    for (csv_name in required_fixtures) {
      csv_path <- file.path(fixture_dir, csv_name)
      check(glue("Fixture exists: {csv_name}"), file.exists(csv_path))
    }

    # Check README.md documents edge cases
    readme_path <- file.path(fixture_dir, "README.md")
    check("Fixture README.md exists", file.exists(readme_path))
  }
}
```

## Modified vs New Components Summary

| Component | Status | LOC Change | Risk |
|-----------|--------|------------|------|
| **R/00_config.R** | MODIFIED | +60 lines (env detection + conditional paths) | LOW (isolated, early exit on error) |
| **tests/fixtures/*.csv** | NEW | N/A (data files) | NONE (read-only) |
| **tests/fixtures/README.md** | NEW | ~100 lines (documentation) | NONE |
| **R/88_smoke_test_comprehensive.R** | MODIFIED | +50 lines (env + fixture checks) | NONE (test-only) |
| **R/01_load_pcornet.R** | UNCHANGED | 0 | NONE |
| **R/03_duckdb_ingest.R** | UNCHANGED | 0 | NONE |
| **All other R scripts** | UNCHANGED | 0 | NONE |

**Total code changes:** ~110 lines across 2 files (R/00_config.R, R/88_smoke_test_comprehensive.R)

**Zero changes to data loading or processing logic** — only configuration and validation

## Integration Points

### Entry Points to Modified Code

1. **R/00_config.R source()'d by all scripts**
   - Every script calls `source("R/00_config.R")`
   - Environment detection runs ONCE per R session
   - IS_LOCAL flag + CONFIG paths available globally

2. **R/01_load_pcornet.R reads CONFIG$data_dir**
   - Already uses `PCORNET_PATHS <- setNames(file.path(CONFIG$data_dir, ...))`
   - NO CODE CHANGE — data_dir auto-resolves to fixtures or production

3. **R/03_duckdb_ingest.R reads CONFIG$cache paths**
   - Already uses `CONFIG$cache$raw_dir`, `CONFIG$cache$duckdb_path`
   - NO CODE CHANGE — paths auto-resolve

4. **R/88_smoke_test_comprehensive.R validates config**
   - New sections 3B-3C validate environment detection and fixtures
   - Fails fast if environment misconfigured

### Data Dependencies

```
Fixture CSVs → R/01 → RDS cache → R/03 → DuckDB → get_pcornet_table() → Pipeline
     ↑                    ↑                  ↑
     │                    │                  │
  Hand-crafted      tempdir() on local   Single-writer
  (~20 patients)    /blue on HiPerGator  Read-only queries
```

**No circular dependencies** — linear data flow matches production

### Shared State

| Object | Scope | Mutated By | Read By |
|--------|-------|------------|---------|
| IS_LOCAL | Global (via 00_config.R) | 00_config.R SECTION 1A (once) | All scripts (conditional logic) |
| CONFIG | Global (via 00_config.R) | 00_config.R (once) | All scripts (path resolution) |
| pcornet_con | Global (via 01_load_pcornet.R) | 01_load_pcornet.R, 03_duckdb_ingest.R | get_pcornet_table() |
| pcornet (RDS mode) | Global (via 01_load_pcornet.R) | 01_load_pcornet.R | get_pcornet_table() (if USE_DUCKDB=FALSE) |

**No new shared state** — IS_LOCAL and CONFIG follow existing pattern

## Build Order

### Phase 1: Environment Detection (Foundation)

**Goal:** R/00_config.R detects environment, sets IS_LOCAL, configures paths

**Files:**
1. Modify R/00_config.R:
   - Add SECTION 1A (environment detection)
   - Convert CONFIG paths to conditional (if IS_LOCAL)

**Validation:**
- Source R/00_config.R on Windows → IS_LOCAL = TRUE, data_dir = "tests/fixtures"
- Source R/00_config.R on Linux → IS_LOCAL = FALSE, data_dir = "/orange/..."
- R_TESTING_ENV=local override works

**Deliverable:** R/00_config.R with environment-aware paths

**Risk:** LOW (single-file change, early in pipeline)

---

### Phase 2: Test Fixtures (Data Layer)

**Goal:** Create minimal PCORnet CSVs with clinical edge cases

**Files:**
1. Create tests/fixtures/ directory
2. Create tests/fixtures/README.md (edge case documentation)
3. Create 15 CSV files:
   - Start with ENROLLMENT.csv (20 patients)
   - Add DEMOGRAPHIC.csv (birth dates, race, sex)
   - Add DIAGNOSIS.csv (HL + NLPHL + other cancers)
   - Add ENCOUNTER.csv (multi-payer, dual-eligible, same-day)
   - Add 11 minimal tables (schema compliance)

**Validation:**
- All CSVs have correct column names (match PCORNET_PATHS)
- ID column present in all tables
- Date columns use YYYY-MM-DD format (compatible with parse_pcornet_date())
- Edge cases documented in README.md

**Deliverable:** tests/fixtures/ with 15 CSVs + README.md

**Risk:** LOW (data-only, no code)

---

### Phase 3: Smoke Test Validation (Testing Layer)

**Goal:** R/88 validates environment detection and fixture schema

**Files:**
1. Modify R/88_smoke_test_comprehensive.R:
   - Add SECTION 3B (environment detection validation)
   - Add SECTION 3C (test fixture schema validation)
   - Renumber subsequent sections (3→4, 4→5, etc.)

**Validation:**
- Run R/88 on Windows → passes env detection checks, fixture schema checks
- Run R/88 on Linux → passes env detection checks, skips fixture checks
- Run R/88 with R_TESTING_ENV=local on Linux → passes both

**Deliverable:** R/88_smoke_test_comprehensive.R with env + fixture validation

**Risk:** NONE (test-only, doesn't affect pipeline)

---

### Phase 4: End-to-End Local Pipeline Test (Integration)

**Goal:** Run full pipeline (01→03→88) on local fixtures

**Steps:**
1. On Windows developer laptop:
   ```r
   source("R/00_config.R")     # Detects Windows → IS_LOCAL = TRUE
   source("R/01_load_pcornet.R") # Loads tests/fixtures/*.csv → tempdir()/rds/
   source("R/03_duckdb_ingest.R") # Ingests RDS → tempdir()/pcornet.duckdb
   source("R/88_smoke_test_comprehensive.R") # Validates all
   ```

2. Verify outputs:
   - RDS cache created in tempdir()
   - DuckDB file created in tempdir()
   - get_pcornet_table("ENROLLMENT") returns 20 patients
   - No errors in smoke test

**Validation:**
- Full pipeline runs without errors
- DuckDB contains 15 tables
- Patient count matches fixtures (20)
- Key edge cases testable (dual-eligible, NLPHL, etc.)

**Deliverable:** Working local pipeline on test fixtures

**Risk:** LOW (no production impact, local-only)

---

### Phase 5: Documentation + Transition (Cleanup)

**Goal:** Document local testing workflow, update PROJECT.md

**Files:**
1. Update .planning/PROJECT.md:
   - Move v2.2 milestone to "Shipped"
   - Add key decisions (environment detection, fixture strategy)
   - Update constraints (add local testing capability)

2. Optional: Create .Renviron.example:
   ```
   # Local testing override (optional)
   # R_TESTING_ENV=local
   ```

**Deliverable:** PROJECT.md updated, optional .Renviron.example

**Risk:** NONE (documentation-only)

---

## Dependency Graph

```
Phase 1 (R/00_config.R env detection)
  └──> Phase 2 (tests/fixtures/ creation)
         └──> Phase 3 (R/88 validation)
                └──> Phase 4 (end-to-end test)
                       └──> Phase 5 (documentation)

No circular dependencies
Each phase validates previous phase
Can pause after Phase 1 and resume later
```

## Alternatives Considered

### Alternative 1: R_PROFILE_USER Instead of Sys.info()

**Approach:** Use `.Rprofile` to set IS_LOCAL flag instead of auto-detection

**Rejected because:**
- Requires manual `.Rprofile` creation (extra setup step)
- `.Rprofile` can be overridden by user-level `~/.Rprofile` ([R startup](https://cran.r-project.org/web/packages/startup/vignettes/startup-intro.html))
- Auto-detection via `Sys.info()` is zero-config

**Retained:** R_TESTING_ENV override via `.Renviron` for edge cases

### Alternative 2: Separate config_local.R File

**Approach:** Create `R/00_config_local.R` that sources `R/00_config.R` and overrides paths

**Rejected because:**
- Requires all scripts to source("R/00_config_local.R") instead of R/00_config.R
- 75+ scripts would need modification
- Breaks existing source() pattern

**Retained:** Single R/00_config.R with conditional logic

### Alternative 3: Full testthat Suite

**Approach:** Create `tests/testthat/` with unit tests for all functions

**Deferred because:**
- Out of scope for v2.2 (milestone goal is "local testing infrastructure")
- Existing R/88_smoke_test_comprehensive.R provides structural validation
- testthat requires refactoring scripts into functions (major effort)

**Retained for future:** tests/testthat/ directory reserved, Phase 4 can add unit tests later

### Alternative 4: DuckDB Memory Mode Instead of Temp File

**Approach:** Use `dbConnect(duckdb(), dbdir = ":memory:")` for local testing

**Rejected because:**
- Doesn't test DuckDB file I/O (atomic write, index creation)
- Phase 29 ingest logic assumes file-based DuckDB
- R/03_duckdb_ingest.R would need separate code path

**Retained:** tempdir() file-based DuckDB (matches production pattern)

## Concurrency and Safety

### DuckDB Single-Writer Pattern (UNCHANGED)

Per [DuckDB production guide](https://www.dench.com/blog/duckdb-in-production):
- **Single writer at a time** (local pipeline runs sequentially, no issue)
- **Multiple concurrent readers** (pipeline reads via get_pcornet_table(), safe)
- **MVCC for read isolation** (readers don't block during writes)

**Local testing impact:** NONE (sequential execution, no parallelism)

### Tempdir() Cleanup

**Automatic cleanup:**
- R's `tempdir()` is auto-deleted on R session exit (per OS)
- Windows: C:\Users\{USER}\AppData\Local\Temp\RtmpXXXXXX
- Linux: /tmp/RtmpXXXXXX

**Manual cleanup (optional):**
```r
# Clear all temp files
unlink(tempdir(), recursive = TRUE)

# Or just DuckDB
unlink(CONFIG$cache$duckdb_path)
```

### Production Safety Guarantees

**No production impact:**
- IS_LOCAL detection prevents fixture use on HiPerGator (Linux → IS_LOCAL = FALSE)
- R/88 smoke test validates data_dir points to /orange on Linux
- Explicit R_TESTING_ENV override required to use fixtures on Linux

**Fail-safe hierarchy:**
1. Production is default (IS_LOCAL = FALSE fallback)
2. Linux auto-detected as production
3. R_TESTING_ENV must explicitly set "local" to override

## Performance Considerations

### Local vs HiPerGator Speed

| Operation | Local (Windows) | HiPerGator (Linux) | Factor |
|-----------|-----------------|---------------------|--------|
| CSV load (vroom) | ~0.1s (20 patients) | ~60s (6300 patients) | 600x |
| DuckDB ingest | ~0.5s (15 tables) | ~300s (15 tables) | 600x |
| Full pipeline (01→03) | ~1s | ~6min | 360x |

**Why acceptable:**
- Local fixtures are 1/300th size of production data (20 vs 6300 patients)
- Purpose is logic validation, not performance testing
- HiPerGator performance unchanged (no code changes to data loading)

### Memory Usage

| Environment | RDS Cache | DuckDB File | Total |
|-------------|-----------|-------------|-------|
| Local (fixtures) | ~5MB (tempdir) | ~10MB (tempdir) | ~15MB |
| HiPerGator (production) | ~2GB (/blue) | ~1.5GB (/blue) | ~3.5GB |

**Local impact:** Negligible (15MB fits in L3 cache of modern CPUs)

## Sources

**Environment Detection:**
- [R Sys.info() documentation](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Sys.info.html) — Official R manual for system information extraction
- [Identifying the OS from R](https://www.r-bloggers.com/2015/06/identifying-the-os-from-r/) — Practical guide to OS detection in R
- [R config: Environment-Specific Configuration](https://www.appsilon.com/post/r-config) — Best practices for environment management

**R Environment Variables:**
- [Managing R Environments (RStudio)](https://docs.posit.co/ide/user/ide/guide/environments/r/managing-r.html) — .Renviron and .Rprofile hierarchy
- [R Configuration Best Practices](https://space-lab-msu.github.io/r_guide/configuration.html) — .Renviron vs .Rprofile usage patterns
- [startup package](https://cran.r-project.org/web/packages/startup/vignettes/startup-intro.html) — R startup sequence and override hierarchy

**Test Fixtures:**
- [testthat: Test fixtures](https://testthat.r-lib.org/articles/test-fixtures.html) — Official testthat fixture patterns
- [testthat: Special files](https://testthat.r-lib.org/articles/special-files.html) — tests/testthat/ directory structure
- [R Packages: Designing your test suite](https://r-pkgs.org/testing-design.html) — Test data organization best practices

**DuckDB Patterns:**
- [DuckDB in Production](https://www.dench.com/blog/duckdb-in-production) — Single-writer pattern, concurrency model
- [DuckDB R package](https://github.com/duckdb/duckdb-r) — Official R bindings and patterns
- [DuckDB Environment Performance](https://duckdb.org/docs/current/guides/performance/environment) — Configuration for local vs production

**Synthetic Clinical Data:**
- [Synthetic Data in Healthcare (2026)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9951365/) — Medical research testing patterns
- [Clinical Trial Data Analysis 2026](https://lifebit.ai/blog/clinical-trial-data-analysis-2026/) — Synthetic data acceptance criteria
- [HIPAA-Compliant Synthetic Data](https://www.seedlessdata.com/industries/healthcare-life-sciences) — Privacy validation for test data

**Confidence:** HIGH (official R documentation, established testthat patterns, DuckDB production guides)
