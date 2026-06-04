# Project Research Summary

**Project:** PCORnet Payer Variable Investigation (R Pipeline) — v2.2 Local Testing Infrastructure
**Domain:** Clinical data pipeline testing infrastructure
**Researched:** 2026-06-03
**Confidence:** HIGH

## Executive Summary

Local testing infrastructure for R clinical data pipelines requires minimal new dependencies and leverages base R capabilities. The v2.2 milestone adds environment auto-detection using `Sys.info()["sysname"]` and `.Renviron` overrides (zero new packages), hand-crafted test fixtures covering 20 synthetic patients with clinical edge cases (base R data.frame + write.csv), and structured testing via testthat 3.3.2 (the ONLY new dependency). The existing architecture is already well-suited for this addition — R/00_config.R centralizes path configuration, R/01 handles CSV loading, R/03 manages DuckDB ingest, and R/88 provides comprehensive validation.

The recommended approach is environment-aware configuration with fail-safe production defaults. Windows OS detection auto-enables local mode (fixtures in tests/fixtures/, DuckDB in tempdir()), while Linux defaults to HiPerGator production paths (/blue/ and /orange/). Test fixtures should deliberately encode clinical edge cases (dual-eligible, NLPHL, orphan diagnosis codes, SCT patients, post-death activity) rather than realistic distributions, preventing both HIPAA re-identification risk and fixture blindness to pipeline failure modes.

Key risks center on cross-platform path handling (Windows backslash vs Linux forward slash), DuckDB file locking across OS boundaries, and fixture schema staleness as the pipeline evolves. Mitigation requires strict adherence to `file.path()` for all path construction, separate DuckDB files for local vs production, and schema validation tests that fail when fixtures drift from expected PCORnet CDM structure. All risks have well-documented prevention strategies from both R testing literature and HPC best practices.

## Key Findings

### Recommended Stack

The v2.2 milestone requires **one new package: testthat 3.3.2** (Jan 2026 release). All other features use base R or existing validated dependencies. Environment detection relies on `Sys.info()` (built into R since v1.0), fixture generation uses base R `data.frame()` + `write.csv()`, and path management uses the existing `here` package (validated in v1.0). The testthat dependency automatically includes withr 3.0.2 for scoped environment variable management.

**Core technologies:**
- **testthat 3.3.2**: Structured testing with fixtures and snapshots — industry standard (10K+ CRAN packages), part of tidyverse ecosystem, maintained by Posit
- **Base R Sys.info()**: OS and hostname detection — zero dependencies, stable API, cross-platform
- **Base R .Renviron**: Environment variable configuration — R-native, project-level overrides without code changes
- **here 1.0.2**: Project-relative path management — already in stack, works seamlessly with environment detection
- **DuckDB (existing)**: In-memory or file-based test database — reuses Phase 29-32 ingest infrastructure without modification

**Packages explicitly NOT needed:**
- config, dotenv: Binary local/HPC detection doesn't need YAML/env file parsing overhead
- charlatan, fabricatr, wakefield: Generic faker libraries don't understand PCORnet CDM edge cases; manual construction gives better control
- data.table: 10-50x faster than vroom but opaque syntax conflicts with "named predicate" requirement (existing architectural constraint)

### Expected Features

Local testing infrastructure has clear table stakes features (users expect these), differentiators (valuable but not expected), and anti-features (explicitly avoid).

**Must have (table stakes):**
- Environment auto-detection — can't manually configure every script; detection must be automatic and reliable
- Path abstraction layer — hard-coded paths break immediately on different systems
- Minimal test fixtures (~20 patients) — can't test clinical edge cases without data; production data too large/sensitive
- DuckDB ingest works with fixtures — existing R/03 ingest script must handle fixture CSVs without modification
- Existing smoke test (R/88) runs locally — 28-section structural validation must work against fixtures
- Local output directory — can't write to HiPerGator `/blue/` paths from Windows

**Should have (differentiators):**
- Fixture generation script — reproducible fixture creation with documented clinical edge cases
- Clinical edge case coverage matrix — explicit documentation mapping patients to edge case scenarios
- Fast feedback loop (<2 min end-to-end) — instant validation vs 10+ min production HPC run
- Git-tracked fixture CSVs — version control for test data; fixture evolution visible in diffs
- Environment-specific tuning — local = 1 thread (small fixtures), HiPerGator = 16 threads (production scale)

**Defer (v2+):**
- Full synthetic data generation (Synthea) — over-engineered for v1; hard to guarantee edge cases appear
- Formal testthat unit test suite — pipeline is exploratory analysis, not package; smoke test pattern already works
- Docker/containerization — adds complexity without proportional value; R + DuckDB install easily on Windows
- Automatic fixture refresh from production — HIPAA risk (PHI leakage), complexity outweighs benefit
- Multi-environment CI/CD testing — not shipping software; exploratory pipeline for single research team

### Architecture Approach

Local testing infrastructure adds three layers to the existing pipeline: (1) environment detection in R/00_config.R using base R with .Renviron override capability, (2) test fixture CSVs in tests/fixtures/ matching PCORnet CDM schema, and (3) modified R/88 smoke test with environment-aware validation. **Zero changes to data loading or processing logic** — only configuration (R/00_config.R) and validation (R/88) modified.

**Major components:**
1. **Environment Detection (R/00_config.R SECTION 1A)** — Auto-detect Windows vs Linux, set IS_LOCAL flag, configure conditional paths; hierarchy: (1) R_TESTING_ENV env var override, (2) Sys.info()["sysname"] OS detection, (3) fallback to production mode (safe default)
2. **Path Configuration (R/00_config.R CONFIG list)** — Conditional path switching based on IS_LOCAL; local = tests/fixtures/ + tempdir(), HiPerGator = /orange/ + /blue/; existing scripts already use CONFIG paths (no changes needed)
3. **Test Fixtures (tests/fixtures/)** — 20 synthetic patients covering 18+ clinical edge cases; hand-crafted CSVs matching PCORnet CDM schema; documented in README.md with patient-to-edge-case mapping
4. **Smoke Test Validation (R/88)** — New sections for environment detection validation (Windows → IS_LOCAL=TRUE) and fixture schema validation (required CSVs present, columns match expected); conditional assertions for fixture vs production mode
5. **DuckDB Integration (unchanged)** — R/03 ingest works transparently with fixtures; local = tempdir()/pcornet.duckdb, HiPerGator = /blue/.../pcornet.duckdb; separate DB files prevent cross-OS file locking issues

**Build order:** Environment detection (foundation) → Fixtures (data layer) → Smoke test validation (testing layer) → End-to-end integration → Documentation. No circular dependencies; each phase validates previous phase.

### Critical Pitfalls

Top 5 pitfalls identified from R HPC testing literature and PCORnet clinical data domain:

1. **Path Separator Silent Failures (Windows \ vs Linux /)** — Code works locally with `paste0("data\\file.csv")` backslashes, silently fails on HiPerGator Linux. **Avoid:** Always use `file.path()` for path construction (platform-independent, faster than paste). Add lintr rule to detect paste() with path-like strings. Never use raw string concatenation for paths.

2. **.Renviron Project vs User Scope Conflicts** — Project-level `.Renviron` overrides user-level `~/.Renviron` (R stops at first match), blocking production paths on HiPerGator when local test paths committed. **Avoid:** Use environment variable override pattern (`Sys.getenv("DATA_DIR", default = "/blue/...")`), not project `.Renviron`. Add `.Renviron` to .gitignore. Document: local users set paths in user `~/.Renviron`, never commit project `.Renviron`.

3. **DuckDB File Locking Across Windows/Linux Sessions** — DuckDB uses OS-level file locks (single-writer design); stale lock from crashed Windows session prevents HiPerGator access. Network-mounted storage (/blue/ via OneDemand) compounds this. **Avoid:** Separate DuckDB files for local vs HiPerGator (test.duckdb vs pcornet.duckdb). Store local DB in tempdir(), never network mount. Add `.duckdb*` to .gitignore. Document: never access HiPerGator DuckDB from Windows.

4. **Test Fixtures with Missing Clinical Edge Cases** — Hand-crafted fixtures pass all tests locally, production breaks on edge cases not represented: orphan diagnosis codes, dual-eligible payer switching, NLPHL vs classical HL conflicts, 1900 sentinel dates, post-death activity. **Avoid:** Design fixtures by documented failure modes, not idealized scenarios. Create `FIXTURE_DESIGN.md` documenting which patient represents which edge case. Include patients with KNOWN problematic patterns (dual-eligible, NLPHL, orphan dx, death dates, SCT, multiple cancers, same-day multi-payer).

5. **Config Changes That Silently Break HiPerGator Production** — Adding IS_LOCAL detection inadvertently changes production behavior through cascading defaults or brittle hostname matching. **Avoid:** Require explicit opt-in for local mode via env var, not auto-detection as default. Pattern: `IS_LOCAL <- as.logical(Sys.getenv("PCORNET_LOCAL_MODE", "FALSE"))`. HiPerGator never sets env var, defaults to production. Add assertion: if HiPerGator detected (check for /blue/ mount), error if conflicting local settings.

**Also significant:** testthat state leakage (options()/Sys.setenv() without withr:: wrapper persists across test files), HIPAA violations (realistic fixture distributions enable re-identification via quasi-identifiers), committed production paths (hardcoded /blue/ paths pushed to GitHub), HPC detectCores() misuse (detects node CPUs, ignores SLURM allocation), fixture schema staleness (new columns added to pipeline but not to fixtures).

## Implications for Roadmap

Based on research, suggested phase structure follows dependency order: environment detection (foundation) → fixtures (data) → validation (testing) → integration (end-to-end) → documentation.

### Phase v2.2-01: Environment Detection
**Rationale:** Foundation for all other features; path switching must work before fixtures can be created or tests run.
**Delivers:** R/00_config.R with IS_LOCAL flag, conditional CONFIG paths, environment detection logging.
**Addresses:** Table stakes (environment auto-detection, path abstraction layer, local output directory).
**Avoids:** Pitfall #2 (.Renviron conflicts — uses env var override, adds .Renviron to .gitignore), Pitfall #5 (production breakage — production defaults unchanged, env var opt-in only).
**Implementation:** Add SECTION 1A to R/00_config.R with Sys.info() detection, convert CONFIG paths to conditional (if IS_LOCAL), add .Renviron to .gitignore, document env var strategy in README.
**Validation:** Source R/00_config.R on Windows → IS_LOCAL=TRUE + data_dir="tests/fixtures"; on Linux → IS_LOCAL=FALSE + data_dir="/orange/..."; R_TESTING_ENV override works.

### Phase v2.2-02: Install testthat
**Rationale:** Only new dependency for v2.2; install before fixture creation to enable test-driven fixture design.
**Delivers:** testthat 3.3.2 + withr 3.0.2 installed on both HiPerGator and local Windows, renv snapshot updated.
**Addresses:** Table stakes (structured testing framework).
**Uses:** testthat 3.3.2 (STACK.md recommendation), renv for package management (existing).
**Implementation:** On HiPerGator: `module load R/4.4.2`, `install.packages("testthat")`, `renv::snapshot()`. On local Windows: same. Verify `packageVersion("testthat")` returns 3.3.2.
**Validation:** testthat loads without errors, withr available as dependency, renv.lock updated with testthat 3.3.2.

### Phase v2.2-03: Test Fixture Design
**Rationale:** Before creating CSVs, design which patients represent which edge cases to ensure comprehensive coverage.
**Delivers:** tests/fixtures/FIXTURE_DESIGN.md documenting 20 patients mapped to 18+ clinical edge cases.
**Addresses:** Table stakes (minimal test fixtures), differentiator (clinical edge case coverage matrix).
**Avoids:** Pitfall #4 (missing edge cases — deliberate design by failure modes), Pitfall #7 (HIPAA violations — unrealistic dates/sites/combos documented).
**Implementation:** Create FIXTURE_DESIGN.md table: Patient ID → Edge Case → Tables → Why Critical. Cover: dual-eligible (P001-P002), NLPHL (P003), multiple cancers (P004), SCT (P005), death+post-death (P006), same-day multi-payer (P007), orphan dx (P008), first-line regimens ABVD/BV+AVD/Nivo+AVD (P009-P011), payer sentinels NI/UN (P012), tumor registry (P013), multi-site (P014), 7-day gap (P015), 1900 dates (P016), remission codes (P017), bare ICD-9 201 (P018), multi-source overlap (P019), minimal valid patients (P020-P025).
**Validation:** FIXTURE_DESIGN.md reviewed by clinical domain expert (or person who wrote filter predicates), all Phase 82 edge cases represented, dates/sites obviously unrealistic (2010-2015, SITE_A/SITE_B).

### Phase v2.2-04: Create Test Fixture CSVs
**Rationale:** Implement fixture design as actual CSVs matching PCORnet CDM schema.
**Delivers:** 15 CSV files in tests/fixtures/ (ENROLLMENT, DIAGNOSIS, ENCOUNTER, PROCEDURES, PRESCRIBING, DEMOGRAPHIC, DEATH, TUMOR_REGISTRY1, 7 minimal tables), tests/fixtures/README.md summarizing edge cases.
**Addresses:** Table stakes (minimal test fixtures, DuckDB ingest compatibility).
**Uses:** Base R data.frame() + write.csv() (STACK.md — no new packages needed), PCORnet CDM v7.0 schema.
**Implementation:** Hand-craft CSVs following FIXTURE_DESIGN.md. Use base R: `enrollment <- data.frame(PATID=sprintf("PT%03d", 1:25), ...)`, `write.csv(enrollment, here::here("tests/fixtures/ENROLLMENT_Mailhot_V1.csv"), row.names=FALSE)`. Verify column names match PCORNET_PATHS from R/01, dates in YYYY-MM-DD format (compatible with parse_pcornet_date()), ID columns present.
**Validation:** All 15 CSVs exist, schema matches expected (PATID, ENCOUNTERID, etc.), no PHI (obviously fake IDs), dates unrealistic (2010-2015), total size <1MB (git-trackable), vroom() can read without errors.

### Phase v2.2-05: DuckDB Ingest with Fixtures
**Rationale:** Verify existing R/03 ingest script works with fixture CSVs without code changes.
**Delivers:** Successful DuckDB ingest from tests/fixtures/ → tempdir()/duckdb/pcornet.duckdb on local Windows.
**Addresses:** Table stakes (DuckDB ingest works with fixtures).
**Avoids:** Pitfall #3 (DuckDB file locking — separate test DB path in tempdir(), not /blue/).
**Implementation:** On Windows: source("R/00_config.R") (detects IS_LOCAL=TRUE), source("R/01_load_pcornet.R") (loads fixtures → tempdir()/rds/), source("R/03_duckdb_ingest.R") (ingests RDS → tempdir()/pcornet.duckdb). Verify: RDS cache created, DuckDB file created, get_pcornet_table("ENROLLMENT") returns 20-25 rows, no errors.
**Validation:** DuckDB file exists in tempdir(), all 15 tables present (SELECT name FROM sqlite_master WHERE type='table'), patient count matches fixtures (20-25), key edge case patients queryable (PT001 has dual-eligible records).

### Phase v2.2-06: Smoke Test Adaptation
**Rationale:** Add environment detection validation and fixture schema checks to R/88 for local testing confidence.
**Delivers:** R/88_smoke_test_comprehensive.R with new SECTION 3B (environment detection validation) and SECTION 3C (fixture schema validation).
**Addresses:** Table stakes (smoke test runs locally), differentiator (fast feedback loop).
**Avoids:** Pitfall #6 (testthat state leakage — document withr:: best practices for future unit tests).
**Implementation:** Add after existing SECTION 3: (3B) validate IS_LOCAL flag exists, Windows→IS_LOCAL=TRUE, Linux→IS_LOCAL=FALSE (unless override), data_dir matches environment; (3C) if IS_LOCAL, check fixture directory exists, required CSVs present (ENROLLMENT, DIAGNOSIS, ENCOUNTER, DEMOGRAPHIC), README.md exists. Conditional assertions: if IS_LOCAL expect 20-25 patients, else expect >50K.
**Validation:** Run R/88 on Windows → passes all checks including 3B/3C, fixture count correct. Run R/88 on HiPerGator → passes 3B, skips 3C (not IS_LOCAL). Run with R_TESTING_ENV=local on Linux → passes both.

### Phase v2.2-07: End-to-End Local Pipeline Test
**Rationale:** Validate full pipeline (00→01→03→88) runs locally without errors, produces expected outputs.
**Delivers:** Confirmed working local pipeline on Windows with test fixtures, documented in tests/testthat/README.md (future location).
**Addresses:** Differentiator (fast feedback loop <2 min).
**Avoids:** Pitfall #1 (path separators — verify file.path() used throughout), Pitfall #10 (fixture staleness — establish schema validation baseline).
**Implementation:** On Windows: clear tempdir(), source all scripts sequentially (R/00, R/01, R/03, R/88), time execution. Verify: pipeline completes <2 min, DuckDB contains 15 tables, get_pcornet_table() queries work, no path errors, smoke test passes all checks, tempdir() cleanup on R session exit.
**Validation:** Full pipeline runs <2 min (vs 6+ min HiPerGator), patient count correct (20-25), no errors in smoke test, DuckDB queries return expected edge case patients (PT001 dual-eligible, PT003 NLPHL, PT008 orphan dx).

### Phase v2.2-08: Documentation & Cleanup
**Rationale:** Document local testing workflow for team, update PROJECT.md, finalize .gitignore.
**Delivers:** Updated .planning/PROJECT.md (v2.2 moved to "Shipped"), .gitignore with test paths, optional .Renviron.example.
**Addresses:** Knowledge transfer, prevent future pitfalls (committed paths, .Renviron conflicts).
**Avoids:** Pitfall #8 (committed production paths — .gitignore updated), Pitfall #2 (.Renviron conflicts — .Renviron.example shows pattern without committing actual file).
**Implementation:** Update PROJECT.md: move v2.2 to Shipped Milestones, add key decisions (environment detection strategy, fixture design approach, testthat 3.3.2 only new dependency), update constraints (add "local testing capability"). Add to .gitignore: `.Renviron`, `.Rprofile`, `*_local.R`, `*.duckdb*`, `tests/fixtures/*.csv` (optional, see note). Create .Renviron.example: `# R_TESTING_ENV=local` (commented). Document in README: local testing workflow, env var override pattern, never commit .Renviron.
**Validation:** PROJECT.md reflects v2.2 completion, .gitignore blocks accidental commits (test with `git add .Renviron`), .Renviron.example provides clear example without credentials.

### Phase Ordering Rationale

- **Environment detection first:** All other features depend on IS_LOCAL flag and CONFIG paths; must work before fixtures or tests can be created.
- **testthat install before fixtures:** Test-driven fixture design benefits from test framework; minimal overhead to install early.
- **Fixture design before fixture creation:** Deliberate edge case planning prevents fixture blindness to production failures (Pitfall #4).
- **DuckDB ingest before smoke test:** Smoke test validates loaded data; DuckDB must be populated first.
- **End-to-end test before documentation:** Validate workflow works before documenting it.
- **Architecture-driven grouping:** Foundation (Phases 1-2) → Data (Phases 3-4) → Testing (Phases 5-6) → Integration (Phase 7) → Documentation (Phase 8).
- **Pitfall avoidance:** Each phase explicitly addresses 1-2 critical pitfalls; prevention strategies implemented, not deferred.

### Research Flags

Phases with **standard patterns** (skip /gsd:research-phase):
- **Phase v2.2-01 (Environment Detection):** Well-documented base R Sys.info() pattern, official R documentation, HPC community consensus.
- **Phase v2.2-02 (Install testthat):** Standard R package installation, testthat is industry-standard, renv workflow established.
- **Phase v2.2-04 (Create Fixtures):** Base R data.frame() + write.csv(), no new technologies, CSV format straightforward.
- **Phase v2.2-05 (DuckDB Ingest):** Reuses existing R/03 infrastructure, no new integration patterns.
- **Phase v2.2-08 (Documentation):** Standard PROJECT.md updates, .gitignore patterns well-known.

Phases likely needing **deeper research** during planning:
- **Phase v2.2-03 (Fixture Design):** Clinical domain knowledge required to identify all edge cases; may need consultation with person who wrote filter predicates or clinical SME. Research: review all filter predicate functions (has_*, with_*, exclude_*) to enumerate edge cases.
- **Phase v2.2-06 (Smoke Test Adaptation):** Conditional test assertions based on environment; may need testthat best practices research for fixture-aware checks. Research: testthat conditional testing patterns, environment-specific expectations.
- **Phase v2.2-07 (End-to-End Test):** Performance troubleshooting if >2 min; may need DuckDB optimization research. Research: DuckDB in-memory mode vs file-based (if speed becomes issue), vroom threading on Windows.

**Overall assessment:** Most phases use well-established patterns; only clinical edge case enumeration (Phase 3) and conditional testing (Phase 6) may benefit from additional research during planning. All technology choices (testthat, base R, DuckDB) have high-confidence documentation.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| **Stack** | **HIGH** | testthat 3.3.2 verified from CRAN (Jan 2026 release), base R Sys.info() documented since R v1.0, here package already validated in v1.0. All version numbers verified against official sources. |
| **Features** | **HIGH** | Table stakes clearly identified from R testing literature (testthat fixtures, environment detection). Differentiators match community best practices (git-tracked fixtures, edge case documentation). Anti-features supported by HPC community (no Docker overhead, no synthetic data generators). |
| **Architecture** | **HIGH** | Existing pipeline architecture (R/00 config, R/01 CSV load, R/03 DuckDB ingest, R/88 smoke test) well-suited for extension. Zero changes to data processing logic. Only 110 LOC changes across 2 files (R/00_config.R, R/88). |
| **Pitfalls** | **MEDIUM-HIGH** | Top 5 pitfalls verified from official R documentation (file.path(), .Renviron scope, DuckDB concurrency), HPC best practices (detectCores() warning), HIPAA compliance literature (re-identification via quasi-identifiers). Some pitfalls domain-specific (clinical edge cases) rely on inference from project history (Phase 82 orphan dx). |

**Overall confidence:** **HIGH**

Research sources include official R documentation (Sys.info(), .Renviron, file.path()), CRAN package pages (testthat 3.3.2, withr 3.0.2), DuckDB official concurrency docs, testthat fixture patterns (r-pkgs.org), HPC best practices (multiple university HPC guides), HIPAA compliance literature (NCBI, clinical trial data management). All core technology decisions verified from primary sources.

### Gaps to Address

**Clinical edge case completeness:** Fixture design (Phase v2.2-03) requires domain expertise to enumerate all failure modes. **Resolution:** Review all filter predicate functions (R/10_cohort_predicates.R, R/11_payer_harmonization.R, etc.) to extract edge cases from code comments and conditional logic. Consult with person who wrote Phase 82 orphan diagnosis investigation for recent edge cases.

**Performance threshold for "fast feedback":** <2 min target for end-to-end local pipeline is estimated, not validated. **Resolution:** Measure during Phase v2.2-07; if >2 min, reduce fixture size (20→10 patients) or explore DuckDB in-memory mode (:memory:) instead of file-based. Not blocking — acceptable range is 30s-5min for local testing.

**HIPAA compliance sign-off:** Synthetic fixture strategy (unrealistic dates, generic sites, incompatible code combos) should be reviewed by IRB or compliance officer before fixture creation. **Resolution:** During Phase v2.2-03, document anti-reidentification strategy in FIXTURE_DESIGN.md, share with compliance contact for confirmation. If IRB review required, pause Phase v2.2-04 until approval.

**Fixture schema validation specifics:** What columns to validate, how to handle optional vs required PCORnet tables, whether to validate data types or just column names. **Resolution:** During Phase v2.2-06 (smoke test), implement minimal schema check (required CSVs exist, core columns present: PATID, ENCOUNTERID, DX, etc.). Defer comprehensive schema validation (data types, foreign keys) to v2.3+ if needed.

**Git tracking fixture CSVs:** Decision whether to commit ~500 rows of CSV data or generate fixtures programmatically. **Resolution:** Commit CSVs for v2.2 (text files, small size <50KB likely, easy to review diffs). If size grows >1MB or fixtures become burdensome to maintain, refactor to programmatic generation in v2.3. Add `tests/fixtures/*.csv` to .gitignore only if size becomes problematic.

## Sources

### Primary (HIGH confidence)
- **CRAN testthat 3.3.2** (https://cran.r-project.org/package=testthat) — Current version verification, Jan 2026 release
- **testthat fixtures documentation** (https://testthat.r-lib.org/articles/test-fixtures.html) — Official fixture patterns
- **R Sys.info() manual** (https://stat.ethz.ch/R-manual/R-devel/library/base/html/Sys.info.html) — Base R environment detection
- **R Startup documentation** (https://stat.ethz.ch/R-manual/R-devel/library/base/html/Startup.html) — .Renviron scope hierarchy
- **DuckDB concurrency docs** (https://duckdb.org/docs/current/connect/concurrency) — Single-writer pattern, file locking behavior
- **R Packages: Testing Design** (https://r-pkgs.org/testing-design.html) — testthat best practices, withr usage
- **file.path() documentation** (https://stat.ethz.ch/R-manual/R-devel/library/base/html/file.path.html) — Official R path construction

### Secondary (MEDIUM confidence)
- **HIPAA test data management** (https://www.accountablehq.com/post/hipaa-compliant-healthcare-test-data-management-best-practices-and-practical-steps) — Synthetic data compliance
- **HPC R Guide** (https://hpcwiki.pmacs.upenn.edu/wiki/index.php/HPC:R) — detectCores() warning for SLURM environments
- **DuckDB in Production** (https://www.dench.com/blog/duckdb-in-production) — Concurrency patterns, MVCC isolation
- **Test Automation Maintenance 2026** (https://bugbug.io/blog/software-testing/test-automation-maintenance/) — Fixture staleness patterns
- **R-bloggers path separators** (https://www.r-bloggers.com/2015/06/identifying-the-os-from-r/) — Cross-platform development
- **PCORnet Data Resources** (https://pcornet.org/news/category/domain/data/) — CDM schema expectations
- **Git credential security** (https://usethis.r-lib.org/articles/git-credentials.html) — .Renviron gitignore best practices

### Tertiary (MEDIUM-LOW confidence)
- **Clinical edge case strategies** — Inferred from PCORnet CDM v7.0 research and synthetic data literature (no direct R+PCORnet testing guide found)
- **Fixture size estimates** (~20 patients sufficient) — Community consensus from data pipeline testing guides, not R-specific validation
- **2 min performance target** — Estimated from DuckDB benchmarks and small dataset assumptions, not validated for this specific pipeline

---
*Research completed: 2026-06-03*
*Ready for roadmap: yes*
