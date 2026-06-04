# Phase 83: Environment Detection & Infrastructure - Research

**Researched:** 2026-06-03
**Domain:** R environment detection, cross-platform path handling, HPC configuration
**Confidence:** HIGH

## Summary

Phase 83 establishes environment detection and infrastructure for dual Windows (local testing) and HiPerGator Linux (production) execution. The core challenge is making R/00_config.R auto-detect the execution environment and configure appropriate paths (tests/fixtures/ locally, /orange/ paths on HPC) without breaking existing HiPerGator production workflows.

R provides robust built-in environment detection via `Sys.info()["sysname"]` (returns "Windows" or "Linux") and environment variable access via `Sys.getenv()`. The standard pattern is: detect OS → check for override env var → set flags and paths → log startup state. Cross-platform path construction must use `file.path()` exclusively (never paste0 with "/" or "\\") since it dynamically selects the correct separator.

DuckDB testing on Windows requires a separate database file in `tempdir()` to avoid file locking conflicts with the HiPerGator network-mounted production database. The .Renviron file enables per-developer environment overrides without modifying tracked code.

**Primary recommendation:** Add environment detection block to top of R/00_config.R that sets IS_LOCAL flag based on `Sys.info()["sysname"] == "Windows"` with override via `Sys.getenv("R_TESTING_ENV")`, then use IS_LOCAL to conditionally configure data_dir, cache paths, DuckDB path, and thread count. Log environment mode at startup. Audit all paste0-based path construction and replace with file.path().

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ENV-01 | Pipeline auto-detects local Windows vs HiPerGator Linux using Sys.info() | Sys.info()["sysname"] returns "Windows" or "Linux" — standard R detection pattern |
| ENV-02 | Environment overridable via R_TESTING_ENV environment variable | Sys.getenv("R_TESTING_ENV") reads env var, .Renviron provides project-level configuration |
| ENV-03 | Local mode configures tests/fixtures/ for data, tempdir() for DuckDB and RDS cache | file.path() constructs cross-platform paths, tempdir() provides OS-managed temporary directories |
| ENV-04 | HiPerGator production mode is the safe default — no behavior change when env var unset | Default to production if detection is ambiguous; require explicit opt-in to testing mode |
| ENV-05 | Environment detection logs which mode is active at startup | message() during config sourcing provides immediate feedback in RStudio console |
| ENV-06 | Local mode uses 1 thread; HiPerGator uses SLURM-allocated cores | Sys.getenv("SLURM_CPUS_PER_TASK") detects HPC allocation, default to 1 locally |
| INFRA-01 | All path construction uses file.path() — no paste0 with path separators | file.path() handles Windows \ vs Linux / automatically |
| INFRA-02 | .gitignore updated for .Renviron, .duckdb files, local output artifacts | Standard R .gitignore includes .Renviron, add .duckdb and tests/ output patterns |
| INFRA-03 | Local output directories created automatically when missing | dir.create(path, recursive = TRUE, showWarnings = FALSE) creates directories safely |
| INFRA-04 | .Renviron.example documents the override pattern | Template shows R_TESTING_ENV=local syntax with explanation |

## Standard Stack

### Core Detection and Configuration

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| base::Sys.info | Built-in | OS detection | Returns named vector with "sysname" field ("Windows", "Linux", "Darwin") |
| base::Sys.getenv | Built-in | Environment variable access | Reads R_TESTING_ENV and SLURM_CPUS_PER_TASK variables |
| base::file.path | Built-in | Cross-platform path construction | Automatically uses correct separator (\ on Windows, / on Unix) |
| base::tempdir | Built-in | Temporary directory location | OS-managed temp space for test DuckDB files, cleaned on R session exit |
| base::dir.create | Built-in | Directory creation | Creates missing output directories with recursive = TRUE |
| base::message | Built-in | Startup logging | Non-error console output during config sourcing |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| glue | 1.8.0 | String formatting for log messages | Already used in smoke test; provides readable startup messages |
| here | 1.0.2 (optional) | Project-relative paths | Alternative to getwd() + file.path(); not essential since config is always sourced from project root |

**Installation:**

No new packages required. All environment detection uses base R functions. The glue package is already installed (used in R/88_smoke_test_comprehensive.R).

**Version verification:**

Base R functions have no separate versioning (tied to R 4.4.2 installed on HiPerGator). No npm-style version checking needed.

## Architecture Patterns

### Recommended Configuration Structure

Add environment detection block at top of R/00_config.R (before SECTION 1: DATA PATHS):

```r
# ==============================================================================
# ENVIRONMENT DETECTION ----
# ==============================================================================
# Auto-detect local testing (Windows) vs production HiPerGator (Linux)
# Override: Set R_TESTING_ENV=local in .Renviron to force local mode on Linux

IS_LOCAL <- if (Sys.getenv("R_TESTING_ENV") != "") {
  # Explicit override from .Renviron or shell environment
  Sys.getenv("R_TESTING_ENV") == "local"
} else {
  # Auto-detect: Windows = local testing, Linux = HiPerGator production
  Sys.info()["sysname"] == "Windows"
}

# Log environment mode at startup
if (IS_LOCAL) {
  message("*** LOCAL TESTING MODE (Windows or R_TESTING_ENV=local) ***")
} else {
  message("*** PRODUCTION MODE (HiPerGator Linux) ***")
}

# Thread count: 1 core locally (avoid contention), SLURM allocation on HPC
THREAD_COUNT <- if (IS_LOCAL) {
  1L
} else {
  # Read SLURM allocation, fallback to 16 (Open OnDemand RStudio default)
  as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = "16"))
}
```

### Pattern 1: Conditional Path Configuration

**What:** Use IS_LOCAL flag to conditionally set data_dir, cache_dir, duckdb_path

**When to use:** Any path that differs between local testing and HiPerGator production

**Example:**

```r
# Source: Research-based pattern (not official docs)
CONFIG <- list(
  # Data directory: tests/fixtures/ locally, /orange/ production path on HPC
  data_dir = if (IS_LOCAL) {
    file.path("tests", "fixtures")
  } else {
    "/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915"
  },

  # Project directory (unchanged)
  project_dir = if (IS_LOCAL) {
    getwd()  # Local testing uses current working directory
  } else {
    "/blue/erin.mobley-hl.bcu/R"
  },

  # Output directory (unchanged — local path)
  output_dir = "output",

  # Performance tuning
  performance = list(
    num_threads = THREAD_COUNT
  ),

  cache = list(
    # Local: tempdir() for ephemeral test cache
    # HPC: /blue/ persistent storage
    cache_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_cache")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds"
    },

    force_reload = FALSE,

    # Subdirectories (append to cache_dir base)
    raw_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_cache", "raw")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds/raw"
    },

    cohort_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_cache", "cohort")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds/cohort"
    },

    outputs_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_cache", "outputs")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds/outputs"
    },

    # DuckDB: separate test database in tempdir() to avoid file locking
    duckdb_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_duckdb")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/duckdb"
    },

    duckdb_path = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_duckdb", "pcornet_test.duckdb")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb"
    }
  )
)
```

### Pattern 2: Cross-Platform Path Construction

**What:** Always use file.path() for path assembly, never paste0() with "/" or "\\"

**When to use:** Every path construction in the codebase

**Example:**

```r
# AVOID: Hardcoded separators (Linux-only)
path <- paste0(CONFIG$data_dir, "/ENROLLMENT_Mailhot_V1.csv")

# AVOID: Hardcoded separators (Windows-only)
path <- paste0(CONFIG$data_dir, "\\ENROLLMENT_Mailhot_V1.csv")

# PREFER: file.path() (cross-platform)
path <- file.path(CONFIG$data_dir, "ENROLLMENT_Mailhot_V1.csv")

# Current code (line 142 of R/00_config.R):
PCORNET_PATHS <- setNames(
  file.path(CONFIG$data_dir, paste0(PCORNET_TABLES, "_Mailhot_V1.csv")),
  PCORNET_TABLES
)
# ✓ Already uses file.path() correctly
```

### Pattern 3: Automatic Directory Creation

**What:** Create output and cache directories at startup if they don't exist

**When to use:** After CONFIG definition, before any file operations

**Example:**

```r
# Source: R dir.create() best practices
# Create output directories automatically (local and HPC)
required_dirs <- c(
  CONFIG$output_dir,
  file.path(CONFIG$output_dir, "figures"),
  file.path(CONFIG$output_dir, "tables"),
  file.path(CONFIG$output_dir, "cohort"),
  file.path(CONFIG$output_dir, "diagnostics"),
  CONFIG$cache$cache_dir,
  CONFIG$cache$raw_dir,
  CONFIG$cache$cohort_dir,
  CONFIG$cache$outputs_dir,
  CONFIG$cache$duckdb_dir
)

for (dir_path in required_dirs) {
  if (!dir.exists(dir_path)) {
    dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
  }
}
```

### Pattern 4: .Renviron Override Configuration

**What:** Project-level .Renviron file for per-developer environment overrides

**When to use:** Developer wants to force local mode on Linux, or test production mode on Windows

**Example (.Renviron.example):**

```bash
# R Environment Configuration
# Copy to .Renviron (gitignored) and customize for your local setup

# Force local testing mode (overrides OS auto-detection)
# Uncomment to enable:
# R_TESTING_ENV=local

# Default: Auto-detect based on OS (Windows = local, Linux = production)
```

**Usage:**
1. Developer copies `.Renviron.example` to `.Renviron` (gitignored)
2. Uncomments `R_TESTING_ENV=local` if testing on Linux VM
3. Restarts R session — config auto-sources and detects override
4. .Renviron is per-developer, never committed to git

### Anti-Patterns to Avoid

- **Don't use setwd() for path resolution:** Use file.path() with CONFIG constants instead of changing working directory
- **Don't hardcode Windows paths with backslashes:** R accepts forward slashes on Windows, but file.path() is clearer
- **Don't check OS in multiple places:** Centralize detection in R/00_config.R, use IS_LOCAL flag downstream
- **Don't use paste0() for paths:** Brittle across platforms; file.path() handles separators automatically
- **Don't silently fail when fixture directory missing:** Check and create required directories at startup

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| OS detection | Custom version checks, R.version parsing | `Sys.info()["sysname"]` | Built-in, reliable, returns "Windows"/"Linux"/"Darwin" directly |
| Environment variables | Reading env files manually, custom parsers | `Sys.getenv("VAR_NAME")` | Built-in, handles missing vars with defaults |
| Cross-platform paths | Manual separator detection, OS-specific paste logic | `file.path()` | Built-in, automatically selects \ or / based on platform |
| Temporary directories | /tmp hardcoding, custom temp path logic | `tempdir()` | OS-managed, cleaned on session exit, handles permissions |
| Directory creation | Custom mkdir wrappers, system() calls | `dir.create(recursive = TRUE)` | Built-in, handles nested paths, cross-platform |
| HPC core detection | Parsing /proc/cpuinfo, nproc system calls | `Sys.getenv("SLURM_CPUS_PER_TASK")` | SLURM sets this automatically, no parsing needed |

**Key insight:** R's base package provides enterprise-grade environment detection and path handling. Custom solutions add complexity without benefit. The only "custom" logic needed is the conditional flag (IS_LOCAL) that drives path selection — everything else uses base R functions.

## Common Pitfalls

### Pitfall 1: Breaking HiPerGator Production with Default Changes

**What goes wrong:** Config changes default behavior → existing SLURM scripts fail

**Why it happens:** Adding IS_LOCAL detection could flip defaults if logic is wrong

**How to avoid:**
- Production must be the safe default (IS_LOCAL = FALSE when env var unset and OS detection fails)
- Test on HiPerGator before merging: source R/00_config.R interactively and check IS_LOCAL value
- Log environment mode at startup so failures are immediately visible

**Warning signs:**
- IS_LOCAL defaults to TRUE on Linux without R_TESTING_ENV set
- Data paths default to tests/fixtures/ on HPC
- No startup logging message (silent failure mode)

### Pitfall 2: Path Separator Hardcoding

**What goes wrong:** Code works locally but fails on HiPerGator (or vice versa) due to "/" vs "\\" separator mismatches

**Why it happens:** paste0(dir, "/file.csv") looks correct and works on Linux, but breaks if dir is a Windows path; R accepts forward slashes on Windows but backslashes fail on Linux

**How to avoid:**
- Grep codebase for `paste0.*"/"` and `paste0.*"\\\\"` patterns (find all path construction)
- Replace with file.path() calls (one argument per path component)
- Review INFRA-01 compliance in code review

**Warning signs:**
- "cannot open file" errors that only appear on one platform
- Paths with mixed separators (e.g., "C:\Users/Owner/Documents")
- Tests pass locally but fail on HPC (or vice versa)

### Pitfall 3: Missing tests/fixtures/ Directory

**What goes wrong:** Developer pulls repo on Windows, sources R/00_config.R, gets error "cannot find tests/fixtures/"

**Why it happens:** tests/ directory doesn't exist yet (Phase 84 creates it), but IS_LOCAL sets data_dir = "tests/fixtures" immediately

**How to avoid:**
- Create tests/ directory structure in Phase 83 (even if empty)
- Add dir.create() calls for all CONFIG paths after CONFIG definition
- .gitkeep files in tests/fixtures/ ensure directory is tracked

**Warning signs:**
- "no such file or directory" error during config sourcing
- dir.exists(CONFIG$data_dir) returns FALSE on Windows
- Developer must manually mkdir tests/fixtures to run pipeline

### Pitfall 4: DuckDB File Locking Across Environments

**What goes wrong:** Local testing tries to connect to production DuckDB file over network mount → file lock conflict or corruption

**Why it happens:** Single duckdb_path for both environments, or local mode accidentally points to /blue/ path

**How to avoid:**
- Use separate DuckDB files: pcornet_test.duckdb locally, pcornet.duckdb on HPC
- Local DuckDB path must be in tempdir() (never on network mount)
- Test DuckDB connection after config change: `DBI::dbConnect(duckdb::duckdb(), CONFIG$cache$duckdb_path)` should succeed immediately

**Warning signs:**
- "database is locked" errors on Windows
- DuckDB corruption after local testing
- Extremely slow DuckDB queries on Windows (network I/O bottleneck)

### Pitfall 5: .Renviron Scope Confusion

**What goes wrong:** Developer sets R_TESTING_ENV=local in ~/.Renviron (user-level) → affects all R projects, not just this one

**Why it happens:** .Renviron search path is: R_ENVIRON_USER → ./.Renviron → ~/.Renviron (first match wins)

**How to avoid:**
- Document project-level .Renviron in INFRA-04 (.Renviron.example)
- .gitignore includes .Renviron (never commit)
- Instruct developers to create ./.Renviron in project root (not ~/)
- Startup logging confirms which mode is active (catches accidental overrides)

**Warning signs:**
- IS_LOCAL = TRUE in unrelated R projects
- Developer confused why "it works for me" but not others
- R_TESTING_ENV visible in other RStudio sessions

## Code Examples

### Environment Detection Block (R/00_config.R)

```r
# Source: Research-based pattern combining Sys.info() + Sys.getenv()
# ==============================================================================
# ENVIRONMENT DETECTION ----
# ==============================================================================
# Auto-detect local testing (Windows) vs production HiPerGator (Linux)
# Override: Set R_TESTING_ENV=local in .Renviron to force local mode on Linux

IS_LOCAL <- if (Sys.getenv("R_TESTING_ENV") != "") {
  # Explicit override from .Renviron or shell environment
  Sys.getenv("R_TESTING_ENV") == "local"
} else {
  # Auto-detect: Windows = local testing, Linux = HiPerGator production
  Sys.info()["sysname"] == "Windows"
}

# Log environment mode at startup (visible in RStudio console and SLURM logs)
if (IS_LOCAL) {
  message("================================================================================")
  message("LOCAL TESTING MODE")
  message("  OS: ", Sys.info()["sysname"])
  message("  Override: ", if (Sys.getenv("R_TESTING_ENV") != "") "R_TESTING_ENV=local" else "(auto-detected)")
  message("  Data: tests/fixtures/")
  message("  DuckDB: tempdir()/insurance_investigation_duckdb/pcornet_test.duckdb")
  message("  Threads: 1")
  message("================================================================================")
} else {
  message("================================================================================")
  message("PRODUCTION MODE (HiPerGator)")
  message("  OS: ", Sys.info()["sysname"])
  message("  Data: /orange/erin.mobley-hl.bcu/Mailhot_V1_20250915")
  message("  DuckDB: /blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb")
  message("  Threads: ", Sys.getenv("SLURM_CPUS_PER_TASK", unset = "16"), " (SLURM allocation)")
  message("================================================================================")
}

# Thread count for vroom and future parallel operations
THREAD_COUNT <- if (IS_LOCAL) {
  1L
} else {
  as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = "16"))
}
```

### Conditional Path Configuration

```r
# Source: Research-based pattern for dual-environment paths
CONFIG <- list(
  data_dir = if (IS_LOCAL) {
    file.path("tests", "fixtures")
  } else {
    "/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915"
  },

  project_dir = if (IS_LOCAL) {
    getwd()
  } else {
    "/blue/erin.mobley-hl.bcu/R"
  },

  output_dir = "output",  # Same for both (local relative path)

  performance = list(
    num_threads = THREAD_COUNT
  ),

  cache = list(
    cache_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_cache")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds"
    },

    force_reload = FALSE,

    raw_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_cache", "raw")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds/raw"
    },

    cohort_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_cache", "cohort")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds/cohort"
    },

    outputs_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_cache", "outputs")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/rds/outputs"
    },

    duckdb_dir = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_duckdb")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/duckdb"
    },

    duckdb_path = if (IS_LOCAL) {
      file.path(tempdir(), "insurance_investigation_duckdb", "pcornet_test.duckdb")
    } else {
      "/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb"
    }
  )
)
```

### Automatic Directory Creation

```r
# Source: R dir.create() best practices from web research
# Create all required output and cache directories at startup
required_dirs <- c(
  CONFIG$output_dir,
  file.path(CONFIG$output_dir, "figures"),
  file.path(CONFIG$output_dir, "tables"),
  file.path(CONFIG$output_dir, "cohort"),
  file.path(CONFIG$output_dir, "diagnostics"),
  CONFIG$cache$cache_dir,
  CONFIG$cache$raw_dir,
  CONFIG$cache$cohort_dir,
  CONFIG$cache$outputs_dir,
  CONFIG$cache$duckdb_dir
)

for (dir_path in required_dirs) {
  if (!dir.exists(dir_path)) {
    dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
  }
}

# Log directory creation for debugging
if (IS_LOCAL) {
  message("  Created cache directories in tempdir():")
  message("    ", CONFIG$cache$cache_dir)
  message("    ", CONFIG$cache$duckdb_dir)
}
```

### Smoke Test: Environment Detection Validation

```r
# Source: Adaptation of existing R/88_smoke_test_comprehensive.R pattern
# Add to R/88_smoke_test_comprehensive.R as new section

message("\n[28/28] Environment detection...")

check("IS_LOCAL flag defined", exists("IS_LOCAL"))
check("IS_LOCAL is logical", is.logical(IS_LOCAL))

if (IS_LOCAL) {
  check(
    "Local mode: data_dir points to tests/fixtures",
    grepl("tests.*fixtures", CONFIG$data_dir, ignore.case = TRUE)
  )
  check(
    "Local mode: DuckDB in tempdir()",
    grepl(tempdir(), CONFIG$cache$duckdb_path, fixed = TRUE)
  )
  check(
    "Local mode: 1 thread configured",
    CONFIG$performance$num_threads == 1
  )
} else {
  check(
    "Production mode: data_dir points to /orange/",
    grepl("^/orange/", CONFIG$data_dir)
  )
  check(
    "Production mode: DuckDB in /blue/",
    grepl("^/blue/", CONFIG$cache$duckdb_path)
  )
  check(
    "Production mode: thread count >= 1",
    CONFIG$performance$num_threads >= 1
  )
}

# Validate file.path() usage in PCORNET_PATHS
for (table_name in names(PCORNET_PATHS)) {
  path <- PCORNET_PATHS[[table_name]]
  # Paths should not contain paste0'd separators
  has_hardcoded_sep <- grepl("\\\\", path) || grepl("//", path)
  check(
    glue("PCORNET_PATHS${table_name} uses file.path() (no hardcoded separators)"),
    !has_hardcoded_sep
  )
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hardcoded /orange/ paths in config | Conditional paths based on IS_LOCAL flag | Phase 83 (2026-06-03) | Enables local Windows testing without code changes |
| Manual env var checks scattered across scripts | Centralized detection in R/00_config.R | Phase 83 | Single source of truth for environment mode |
| paste0() for path construction | file.path() exclusively | Phase 83 (INFRA-01) | Cross-platform compatibility guaranteed |
| Assume 16 cores available | Detect SLURM_CPUS_PER_TASK or default to 1 locally | Phase 83 (ENV-06) | Avoids resource contention on Windows |
| No local testing infrastructure | Dual-mode config with tempdir() cache | Phase 83 | Developers can run pipeline locally against fixtures |

**Deprecated/outdated:**

- **Hardcoded path separators:** Any use of paste0(dir, "/file") or paste0(dir, "\\file") — should be file.path(dir, "file")
- **setwd() for path resolution:** Changing working directory is fragile; use file.path() with CONFIG constants instead
- **Assuming Linux environment:** Config must work on Windows for v2.2+ local testing
- **Single DuckDB file for all environments:** Causes file locking conflicts; local testing needs separate test database

## Open Questions

1. **Should tempdir() cache persist across R sessions?**
   - What we know: tempdir() is cleaned on R session exit, so local testing loses cache between runs
   - What's unclear: Is this acceptable for v2.2 scope? Or should local cache use a persistent directory like .cache/?
   - Recommendation: Accept ephemeral cache for v2.2 (fixtures are small, ingest is fast). If local performance becomes an issue, add persistent local cache in v2.3.

2. **Should local mode support SLURM on Linux?**
   - What we know: Some HPC users might want to test locally on a Linux VM with R_TESTING_ENV=local
   - What's unclear: Does local mode on Linux need to detect SLURM and use allocated cores, or always default to 1?
   - Recommendation: Local mode always uses 1 thread regardless of OS. SLURM core detection only applies to production mode (IS_LOCAL = FALSE). Keeps logic simple.

3. **Should .Renviron.example be tracked in git?**
   - What we know: .Renviron is gitignored (standard practice), but examples are often tracked
   - What's unclear: Project doesn't currently have .Renviron.example — should Phase 83 create it?
   - Recommendation: Yes, create .Renviron.example in project root with commented R_TESTING_ENV=local line. Documents override pattern for new developers.

## Environment Availability

> Phase 83 has no external dependencies beyond base R. All tools are built-in functions. This section documents baseline R version requirement.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| R | All environment detection | ✓ | 4.4.2 | — |
| base::Sys.info | OS detection (ENV-01) | ✓ | Built-in (R 4.4.2) | — |
| base::Sys.getenv | Env var reading (ENV-02) | ✓ | Built-in (R 4.4.2) | — |
| base::file.path | Path construction (INFRA-01) | ✓ | Built-in (R 4.4.2) | — |
| base::tempdir | Local cache location (ENV-03) | ✓ | Built-in (R 4.4.2) | — |
| base::dir.create | Directory creation (INFRA-03) | ✓ | Built-in (R 4.4.2) | — |
| base::message | Startup logging (ENV-05) | ✓ | Built-in (R 4.4.2) | — |
| glue | Log formatting (optional) | ✓ | 1.8.0 (already installed) | base::paste() if missing |

**Missing dependencies with no fallback:** None

**Missing dependencies with fallback:** None (all base R functions)

## Validation Architecture

> Validation section omitted: workflow.nyquist_validation is set to false in .planning/config.json.

## Sources

### Primary (HIGH confidence)

- [R Manual: Sys.info()](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Sys.info.html) - Official R documentation for OS detection
- [R Manual: file.path()](https://stat.ethz.ch/R-manual/R-devel/library/base/html/file.path.html) - Official R documentation for cross-platform paths
- [R Manual: Sys.getenv()](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Sys.getenv.html) - Official R documentation for environment variables
- [R Manual: dir.create()](https://stat.ethz.ch/R-manual/R-devel/library/base/html/files2.html) - Official R documentation for directory creation

### Secondary (MEDIUM confidence)

- [Identifying the OS from R | R-bloggers](https://www.r-bloggers.com/2015/06/identifying-the-os-from-r/) - Practical examples of Sys.info() usage patterns
- [Dealing with Windows File Paths in R | R-bloggers](https://www.r-bloggers.com/2024/10/dealing-with-windows-file-paths-in-r/) - file.path() best practices and cross-platform pitfalls
- [Mastering Software Development in R: Cross Platform Development](https://bookdown.org/rdpeng/RProgDA/cross-platform-development.html) - Environment detection patterns for dual-platform R packages
- [R and RStudio and UVA HPC | Research Computing](https://www.rc.virginia.edu/userinfo/hpc/software/r/) - SLURM environment variable usage in R on HPC systems
- [availableCores() documentation | parallelly](https://parallelly.futureverse.org/reference/availableCores.html) - SLURM_CPUS_PER_TASK detection for parallel R code
- [DuckDB Gitignore Guide](https://duckdb.org/docs/stable/operations_manual/footprint_of_duckdb/gitignore_for_duckdb) - Official DuckDB .gitignore patterns
- [GitHub R .gitignore template](https://github.com/github/gitignore/blob/main/R.gitignore) - Standard R project .gitignore including .Renviron
- [DuckDB R Package: cached_connection()](https://cran.r-project.org/web/packages/duckdbfs/news/news.html) - tempdir() usage for DuckDB testing
- [startup package CRAN](https://cran.r-project.org/web/packages/startup/vignettes/startup-intro.html) - .Renviron search path and environment variable precedence

### Tertiary (LOW confidence - general guidance)

- [Master R: Create Directories Like a Pro! | Eresources.blog](https://eresources.blog/create-directories-in-r-guide) - dir.create() parameter examples (showWarnings, recursive)
- [Getting started with logging in R | sellorm](https://blog.sellorm.com/2021/06/16/getting-started-with-logging-in-r/) - message() vs cat() vs print() for startup logging

## Metadata

**Confidence breakdown:**
- Environment detection (Sys.info, Sys.getenv): HIGH - Official R manual documentation, widely used pattern
- Cross-platform paths (file.path): HIGH - Official R manual, established best practice across R ecosystem
- HPC integration (SLURM_CPUS_PER_TASK): MEDIUM - Not official R documentation, but standard HPC pattern verified in multiple university HPC guides
- DuckDB testing patterns (tempdir): MEDIUM - Official DuckDB docs recommend it, but R-specific usage less documented
- .Renviron best practices: HIGH - Official R startup documentation, standard practice

**Research date:** 2026-06-03
**Valid until:** 30 days (2026-07-03) - stable domain, base R functions don't change frequently
