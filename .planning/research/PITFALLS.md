# Pitfalls Research

**Domain:** Local Windows testing infrastructure for Linux HPC R clinical data pipeline
**Researched:** 2026-06-03
**Confidence:** MEDIUM

## Critical Pitfalls

### Pitfall 1: Path Separator Silent Failures (Windows \ vs Linux /)

**What goes wrong:**
Code works on Windows during local testing with hardcoded paths using backslashes, then silently fails or creates nested directories on HiPerGator Linux when paths are interpreted incorrectly. `paste()` or string concatenation creates platform-specific paths like `"data\\test"` on Windows that break on Linux.

**Why it happens:**
R accepts forward slashes on Windows (Windows handles `/` without issues), creating false confidence. Developers test locally with `paste0()` or raw string paths, not realizing backslashes are platform-specific. The issue only surfaces on HiPerGator deployment.

**How to avoid:**
- **ALWAYS use `file.path()` for path construction** — it's faster than `paste()` and platform-independent
- Never construct paths with `paste()`, `paste0()`, or raw strings like `"data\\file.csv"`
- Add lintr rule to detect `paste()` calls with path-like strings
- Use `normalizePath()` when comparing paths or checking existence

**Warning signs:**
- `paste()` or `paste0()` calls containing directory separators
- Raw strings with `\\` in path definitions
- Tests pass locally but fail in HiPerGator SLURM jobs with "file not found" errors
- Unexpected nested directories like `data/test\fixtures` appearing on Linux

**Phase to address:**
Phase 1 (Environment Detection) — establish `file.path()` as standard, add code review checklist

---

### Pitfall 2: .Renviron Project vs User Scope Conflicts

**What goes wrong:**
Project-level `.Renviron` silently overrides user-level `~/.Renviron`, causing HiPerGator production runs to ignore user-configured paths (data directory, DuckDB location) because R only loads the first `.Renviron` found. Developer's local project `.Renviron` contains test paths that get committed, then blocks production paths on HiPerGator.

**Why it happens:**
R's startup sequence searches: (1) `R_ENVIRON_USER` env var, (2) `./.Renviron` (project), (3) `~/.Renviron` (user) — **stops at first match**. Most R developers don't know project-level `.Renviron` completely suppresses user-level. This is unlike `.Rprofile` where you can explicitly source the user file.

**How to avoid:**
- **Use environment variable override pattern**, not project `.Renviron`
- In `R/00_config.R`: `Sys.getenv("DATA_DIR", default = "/blue/...")` for HiPerGator defaults
- Document in README: local users set `DATA_DIR` in their user `~/.Renviron`, not project `.Renviron`
- Add `.Renviron` to `.gitignore` — it should NEVER be committed
- If project `.Renviron` exists (e.g., for testing), include `source("~/.Renviron")` at top to restore user scope

**Warning signs:**
- `.Renviron` file present in git tracked files
- Production jobs fail with "file not found" after local testing additions
- User environment variables mysteriously ignored on HiPerGator
- Different behavior between interactive RStudio sessions and SLURM jobs

**Phase to address:**
Phase 1 (Environment Detection) — document env var strategy, add `.Renviron` to `.gitignore`, verify no tracked `.Renviron`

---

### Pitfall 3: DuckDB File Locking Across Windows/Linux Sessions

**What goes wrong:**
DuckDB uses OS-level file locks for ACID compliance. A stale lock from a crashed local Windows session prevents HiPerGator production access, or vice versa. Network-mounted storage (OneDemand accessing HiPerGator `/blue/`) compounds this — DuckDB's lock mechanism fails with "Operation Not Supported" on Samba/NFS mounts.

**Why it happens:**
DuckDB is **single-writer, multiple-reader by design**. File locks don't cleanly release across OS boundaries or network mounts. Windows `.wal` and `.lock` files remain after crash; Linux can't interpret Windows file locks on network shares. Even `read_only=TRUE` fails if writer lock exists.

**How to avoid:**
- **Separate DuckDB files for local vs HiPerGator** — local testing uses `test.duckdb`, production uses `pcornet.duckdb`
- Store local test DuckDB in `tests/fixtures/`, never on network mount
- Add `.duckdb`, `.duckdb.wal`, `.duckdb.lock` to `.gitignore`
- Document in README: "Never access HiPerGator DuckDB file from Windows via OneDemand RStudio"
- Implement `FORCE_REBUILD_DUCKDB` env var for local testing to recreate DB if locked
- For concurrent testing, use read-only connections or in-memory DuckDB (`:memory:`)

**Warning signs:**
- "IO Error: Could not set lock on file" when switching between local/HiPerGator
- "The process cannot access the file because it is being used by another process" on Windows
- Persistent `.wal` files after R session terminates
- Tests hang indefinitely waiting for lock release
- Errors with "Operation Not Supported" on `/blue/` mounted shares

**Phase to address:**
Phase 2 (DuckDB Test Ingest) — implement separate test DB path, document lock behavior, add cleanup to test teardown

---

### Pitfall 4: Test Fixtures with Missing Clinical Edge Cases

**What goes wrong:**
Hand-crafted 20-patient test fixture passes all tests locally, but production breaks on real edge cases not represented in fixtures: orphan diagnosis codes (dx without matching encounter), dual-eligible switching mid-study, NLPHL vs classical HL ICD code conflicts, treatment dates before enrollment, death dates in 1900 (sentinel values), multiple overlapping SCT procedures same day.

**Why it happens:**
Fixture design focuses on "happy path" scenarios — one patient per category. Real PCORnet data has messy edge cases discovered through production failures. Creating realistic fixtures requires domain knowledge of clinical data quality issues that developers lack. Fixtures become "example data" not "stress test data."

**How to avoid:**
- **Design fixtures by documented failure modes**, not idealized scenarios
- Create `tests/fixtures/FIXTURE_DESIGN.md` documenting which edge case each patient represents
- Include patients with KNOWN problematic patterns:
  - Patient 1: Dual-eligible (Medicare+Medicaid same day)
  - Patient 2: NLPHL (C81.0x) + classical HL (C81.7x) — category conflict
  - Patient 3: Treatment before enrollment start (negative time-to-treatment)
  - Patient 4: Orphan diagnosis code (DIAGNOSIS.ENCOUNTERID not in ENCOUNTER table)
  - Patient 5: Death date = 1900-01-01 (sentinel for missing)
  - Patient 6: Multiple SCT codes same encounter (0362 + others)
  - Patient 7: Post-death encounters (ENCOUNTER.ADMIT_DATE > DEATH.DEATH_DATE)
  - Patient 8: Same-day multi-payer (Medicaid AM, Private PM) — resolution hierarchy test
- Validate fixture against production smoke test criteria before declaring "testing ready"
- Add test that verifies fixture exercises ALL code paths in filter predicates

**Warning signs:**
- Test suite passes 100% locally, fails in production on first real data run
- Code coverage high but doesn't include defensive checks
- Fixture patients all have "clean" data (no missing values, no conflicts)
- No documented rationale for fixture design choices
- Adding new filter predicate doesn't require new test cases

**Phase to address:**
Phase 3 (Edge Case Fixtures) — document fixture design, add edge cases from Phase 82 orphan dx investigation, verify against smoke test

---

### Pitfall 5: Config Changes That Silently Break HiPerGator Production

**What goes wrong:**
Adding `IS_LOCAL_ENV` detection logic to `R/00_config.R` inadvertently changes production behavior through cascading defaults. Example: local testing sets `USE_DUCKDB <- FALSE` for faster CSV loading, but developer forgets OS detection can misfire (HiPerGator node hostname changes), causing production to fall back to CSV mode and fail with "RDS not found" errors.

**Why it happens:**
Environment detection relies on brittle heuristics (hostname matching, `Sys.info()["sysname"]`). HiPerGator nodes have dynamic hostnames (`c0801a-s7.ufhpc` vs `c0901a-s2.ufhpc`). macOS reports `"Darwin"` not `"macOS"`. Detection logic becomes nested if/else with untested branches. Adding local testing paths creates new code paths in production config.

**How to avoid:**
- **Require explicit opt-in for local mode** via env var, not auto-detection as default
- Pattern: `IS_LOCAL <- as.logical(Sys.getenv("PCORNET_LOCAL_MODE", "FALSE"))`
- HiPerGator production never sets `PCORNET_LOCAL_MODE`, so defaults to production paths
- Local testing requires: `Sys.setenv(PCORNET_LOCAL_MODE = "TRUE")` in `tests/testthat/setup.R`
- Add assertion at top of `R/00_config.R`: if HiPerGator detected (check for `/blue/` mount or `SLURM_JOB_ID`), error if conflicting local settings detected
- Document in comments: "NEVER change production defaults in this file for local testing convenience"

**Warning signs:**
- Complex nested if/else for environment detection
- Production paths defined inside conditionals, not as defaults
- hostname matching logic (brittle across HPC node changes)
- Local testing requires modifying `R/00_config.R` instead of setting env var
- No explicit error when conflicting settings detected

**Phase to address:**
Phase 1 (Environment Detection) — implement env var opt-in, add production path assertions, code review for default safety

---

### Pitfall 6: Forgetting testthat Doesn't Auto-Cleanup Environment State

**What goes wrong:**
Tests modify `options()` or global environment variables (`USE_DUCKDB`, `DATA_DIR`) for test isolation, but testthat doesn't automatically restore state between test files. Test A sets `options(duckdb.dir = "test/")`, Test B assumes default, inherits Test A's setting, fails with "path not found." Worse: test suite passes when run in one order, fails when files run alphabetically.

**Why it happens:**
Each test file runs in a clean *environment* but shares the same R *process* (same session). `options()`, `Sys.setenv()`, loaded packages, and attached data persist across files. Developers assume test isolation includes session state. `testthat` documentation warns: "doesn't automatically clean up after actions that affect filesystem, search path, or environment variables."

**How to avoid:**
- **Use `withr::local_*()` functions for ALL state changes** in tests
- Pattern: `withr::local_envvar(PCORNET_LOCAL_MODE = "TRUE")` instead of `Sys.setenv()`
- Pattern: `withr::local_options(duckdb.dir = "test/")` instead of `options()`
- Add `tests/testthat/setup.R`: capture baseline state with `set_state_inspector()`
- Use `teardown_env()` with `withr::defer()` for cleanup that must run even on error
- Run tests with `devtools::test()` then `test(stop_on_failure = FALSE)` to catch order dependencies

**Warning signs:**
- Tests pass in RStudio "Run Tests" but fail in `R CMD check`
- Different results when running test files individually vs. full suite
- Mysterious failures that disappear when test file renamed (alphabetical order change)
- Global state set in `expect_*()` blocks without corresponding reset
- `options()` or `Sys.setenv()` without `withr::` wrapper

**Phase to address:**
Phase 4 (Smoke Test Migration) — add state inspector, wrap all state changes with `withr::`, add order-independence check

---

### Pitfall 7: Test Data HIPAA Violations Through Re-Identification Risk

**What goes wrong:**
Synthetic test fixture uses real ICD codes, drug names, dates, and site codes (UFH, AMS) with realistic patient counts, creating a dataset that could be cross-referenced with public sources (ClinicalTrials.gov, published studies) to re-identify real patients. Even though PATIDs are fake, the *combination* of rare diagnosis (NLPHL), specific treatment (Nivo+AVD), UFH site, and 2024 dates narrows to <11 patients, violating HIPAA Safe Harbor.

**Why it happens:**
Developers focus on "no real PATIDs" but ignore quasi-identifiers (combinations of attributes). PCORnet data contains rich clinical detail — ICD codes, drug names, dates, sites. 20-patient fixture with realistic distributions accidentally mirrors actual cohort characteristics. HIPAA requires "no reasonable basis for re-identification," not just "no direct identifiers."

**How to avoid:**
- **Synthetic data strategy: plausible but NOT realistic distributions**
- Use wrong dates (all encounters in 2010-2015, before study period)
- Mix incompatible codes (adult + pediatric, male + pregnancy)
- Generic site codes (SITE_A, SITE_B), not real PCORnet sites (UFH, AMS)
- Document in `tests/fixtures/FIXTURE_DESIGN.md`: "Dates and combinations intentionally unrealistic to prevent re-identification"
- Never derive fixture from production data (no sampling, subsetting, or masking real data)
- Legal review: confirm synthetic fixture strategy with IRB or compliance officer

**Warning signs:**
- Fixture uses real site codes, real date ranges, real cohort size ratios
- Rare diagnoses (NLPHL) + rare treatments (Nivo+AVD) + real sites
- Fixture derived from production via `head(data, 20)` or similar
- No documented legal review of HIPAA compliance for test data
- Fixture dates overlap study period (2024-2026)

**Phase to address:**
Phase 3 (Edge Case Fixtures) — legal review before fixture creation, document anti-reidentification strategy, use obviously fake dates/sites

---

### Pitfall 8: Accidentally Committing Production Paths or Credentials

**What goes wrong:**
Developer troubleshoots local testing by temporarily hardcoding HiPerGator production path `/blue/erin.mobley-hl.bcu/` in `R/00_config.R` to compare outputs, commits without reverting, pushes to GitHub. Now all developers' local environments default to production path (fails unless they have VPN + `/blue/` mount). Worse: `.Renviron` with API keys (RxNorm API for drug name lookup) gets committed, exposing credentials publicly.

**Why it happens:**
Quick fixes during debugging ("just hardcode it to test") don't get reverted before commit. `.gitignore` doesn't cover new files (`.Renviron`, `config_local.R`). Git's `add .` or RStudio's "Stage All" includes everything. GitHub secret scanning detects API keys AFTER push, not before.

**How to avoid:**
- **Add pre-commit hook that blocks common mistakes**
  - Pattern match for `/blue/` in committed files (warn if outside comments)
  - Block commit if `.Renviron`, `.Rprofile`, `*_local.R` staged
  - Detect API key patterns (RxNorm API tokens, DuckDB connection strings with passwords)
- Update `.gitignore` proactively:
  ```
  .Renviron
  .Rprofile
  *_local.R
  *.duckdb*
  tests/fixtures/*.csv
  /blue/
  ```
- Use `usethis::git_vaccinate()` to add standard R `.gitignore` patterns
- Document in README: "Never hardcode production paths — use env vars"
- Code review checklist: "Any `/blue/` paths in diff? Should be config/env var."

**Warning signs:**
- Absolute paths in source code (not in comments or config files)
- API keys or credentials in tracked files
- `.Renviron` or `.Rprofile` in git status
- Pre-commit hook missing or disabled
- Developer says "just change line 42 to your path"

**Phase to address:**
Phase 1 (Environment Detection) — add `.gitignore` entries, install pre-commit hook, code review checklist

---

### Pitfall 9: HPC `detectCores()` Misuse Breaking SLURM Jobs

**What goes wrong:**
Local testing uses `future::plan(multisession, workers = parallel::detectCores())` for parallel processing. Works great on Windows laptop (8 cores). Deployed to HiPerGator SLURM job with `--cpus-per-task=4`, but `detectCores()` returns 64 (entire node), spawning 64 workers that exceed allocated resources. SLURM kills job for oversubscription. Or: job thrashes with context switching, taking 10x longer than serial execution.

**Why it happens:**
`detectCores()` detects physical CPUs on node, ignores SLURM allocation. HPC administrators explicitly warn against `detectCores()` in HPC environments. Developers test locally where "use all cores" is safe, don't realize HPC jobs run on shared nodes with resource limits enforced by scheduler.

**How to avoid:**
- **Read worker count from SLURM env var**, not `detectCores()`
- Pattern: `ncores <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", parallel::detectCores()))`
- Document in SLURM script header: `#SBATCH --cpus-per-task=4` must match code expectation
- Add assertion in R script: verify `ncores <= SLURM_CPUS_PER_TASK` if defined
- For local testing: `Sys.setenv(SLURM_CPUS_PER_TASK = "2")` to simulate HPC allocation
- Prefer explicit worker counts for small jobs: `workers = 4` instead of auto-detection

**Warning signs:**
- `parallel::detectCores()` or `future::availableCores()` called without SLURM env var override
- SLURM job killed with "exceeded memory limit" or "CPU time limit"
- Job walltime 10x longer than expected (context switching overhead)
- No `--cpus-per-task` in SLURM script but code uses parallelism
- Local testing doesn't set `SLURM_CPUS_PER_TASK` to simulate HPC

**Phase to address:**
Phase 5 (if adding parallel processing) — otherwise, defer to future work. Not needed for current serial pipeline.

---

### Pitfall 10: Fixture Staleness (Test Data Doesn't Evolve with Schema)

**What goes wrong:**
Pipeline adds new columns to outputs (e.g., `is_first_line` in `treatment_episodes.rds`, `category` in drug grouping tables). Fixture CSVs don't include these columns. Tests continue passing because they only check old columns. Production generates new columns with `NA` values, silently breaking downstream scripts. Discovered weeks later when analyst complains about "missing data."

**Why it happens:**
Fixtures are static CSVs created once, rarely updated. New features add columns to PCORnet tables or derived outputs. Test assertions check specific columns (`expect_true("PATID" %in% names(df))`), not schema completeness. No smoke test validates fixture schema matches production schema. **"Test data decay"** — common maintenance burden in 2026 testing literature.

**How to avoid:**
- **Version fixture schema in `tests/fixtures/SCHEMA_VERSION.txt`**
- Add test: compare fixture schema vs. expected production schema
  ```r
  expected_cols <- c("PATID", "ENCOUNTERID", "cancer_category", "is_first_line", ...)
  fixture_cols <- names(read_csv("tests/fixtures/ENCOUNTER.csv"))
  expect_equal(sort(fixture_cols), sort(expected_cols))
  ```
- Update fixture regeneration script whenever PCORnet table columns added
- Smoke test checklist: "Fixture schema reviewed after column additions?"
- Consider **fixture generator function** instead of static CSVs (generates fixtures programmatically, guarantees schema match)

**Warning signs:**
- Tests pass but production output has `NA` columns
- Fixture CSVs created >3 months ago without updates
- No schema validation test in test suite
- Pipeline adds columns but no fixture update in same commit
- Analyst reports "missing data" that's actually new columns with `NA`

**Phase to address:**
Phase 3 (Edge Case Fixtures) — add schema validation test, document fixture update process. Phase 6+ (ongoing) — update fixtures when schema changes.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Auto-detect environment (hostname matching) | No env var required | Brittle across HPC node changes, misdetects on new systems | Never — use explicit env var opt-in |
| Commit `.Renviron` with test paths | Team gets consistent test paths | Silently breaks production, exposes credentials if API keys added | Never — use env var documentation instead |
| Derive fixtures from production `head(data, 20)` | Realistic data instantly | HIPAA violation risk, re-identification via quasi-identifiers | Never — hand-craft synthetic data |
| Use `paste0()` for paths (works on Windows) | Faster to write than `file.path()` | Silent failure on Linux, creates wrong directories | Never — `file.path()` is actually faster |
| Skip `withr::` in tests (cleanup manually) | Less boilerplate | Tests pass individually, fail in suite (order dependency) | Never — `withr::` is standard practice |
| Share DuckDB file Windows ↔ HiPerGator | One source of truth | File locking deadlock, corruption risk | Never — separate DBs for local/prod |
| Happy-path-only fixtures | Fast fixture creation | Misses edge cases, false confidence | Only for initial prototype, must evolve |
| `detectCores()` for parallelism | Uses available resources | Breaks SLURM jobs, thrashes on shared nodes | Only on confirmed local-only scripts |

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| DuckDB (local ↔ HPC) | Accessing same `.duckdb` file from Windows + Linux via network mount | Separate DB files: `test.duckdb` local, `pcornet.duckdb` on HiPerGator `/blue/` |
| RxNorm API (drug lookup) | Hardcoding API key in `R/00_config.R` | `Sys.getenv("RXNORM_API_KEY")` with key in user `~/.Renviron`, never committed |
| HiPerGator SLURM | Using `detectCores()` for worker allocation | Read `SLURM_CPUS_PER_TASK` env var, fall back to `detectCores()` only on local |
| OneDemand RStudio | Editing HiPerGator files via OneDemand web RStudio | SSH + command-line R, or local RStudio with explicit file sync (never concurrent) |
| PCORnet CSVs | Assuming column types (vroom auto-detect) | Explicit `col_types` spec in `vroom()` — PATID as character, dates as Date |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| In-memory fixture CSVs (read every test) | Slow test suite (30s → 5min) | Cache fixture load in `tests/testthat/helper-fixtures.R`, load once | >10 test files reading same CSV |
| Regenerating DuckDB from CSVs every test run | Tests take 2min for 30s of actual logic | Use persistent test DB, only rebuild if `FORCE_REBUILD=TRUE` | Fixture >100MB or >1000 rows |
| Full pipeline smoke test on every commit | CI times out after 10min | Local smoke test pre-commit, full CI on PR only | Pipeline >20 scripts or >5min runtime |
| Copying production DB to local for testing | Laptop runs out of disk (50GB DB) | Use subset fixture (20 patients) or read-only remote connection | Production DB >10GB |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Committing synthetic fixtures with realistic quasi-identifiers | HIPAA violation via re-identification (rare dx + site + date) | Use obviously fake dates (2010), generic sites (SITE_A), incompatible code combos |
| Storing API keys in `.Renviron` within project | Exposed on GitHub if `.Renviron` not gitignored, leaked to collaborators | User `~/.Renviron` only, never project `.Renviron`, add to `.gitignore` |
| Production paths in test code | Accidental data access from local test runs, audit log confusion | Env var for DATA_DIR, fail-safe: error if `/blue/` detected and `IS_LOCAL=TRUE` |
| Network-mounted DuckDB access from multiple OS | File corruption from incompatible lock mechanisms | Separate DB files per environment, document "never access prod DB from Windows" |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Environment detection:** Does code ERROR (not silently fallback) when detection conflicts? (e.g., `IS_LOCAL=TRUE` but `/blue/` path detected)
- [ ] **Test fixtures:** Does `FIXTURE_DESIGN.md` document which patient represents which edge case? (Orphan dx, dual-eligible, NLPHL, etc.)
- [ ] **DuckDB setup:** Are `.duckdb`, `.duckdb.wal`, `.duckdb.lock` in `.gitignore`? Is test DB path separate from prod?
- [ ] **Path construction:** Codebase search for `paste.*\\\\` or `paste.*"/"` — are all replaced with `file.path()`?
- [ ] **Credential handling:** Is `.Renviron` in `.gitignore`? Are API keys in user scope, not project scope?
- [ ] **State cleanup in tests:** Are all `options()` and `Sys.setenv()` calls wrapped in `withr::local_*()`?
- [ ] **HIPAA compliance:** Has fixture design been reviewed by IRB/compliance? Are dates/sites/combos unrealistic?
- [ ] **SLURM resource limits:** If using parallelism, does code read `SLURM_CPUS_PER_TASK` instead of `detectCores()`?
- [ ] **Pre-commit hooks:** Does hook block commits with `/blue/`, `.Renviron`, or API key patterns?
- [ ] **Fixture schema validation:** Do tests verify fixture columns match expected production schema?

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Committed production paths | LOW | 1. Revert commit, 2. Update `.gitignore`, 3. Force push (if not public), 4. Notify team to pull |
| DuckDB locked across OS | LOW | 1. Kill all R sessions, 2. Delete `.wal` and `.lock` files, 3. Restart R, 4. Document in README |
| Leaked API key in git history | HIGH | 1. Rotate key immediately, 2. Use BFG Repo-Cleaner to purge history, 3. Force push, 4. Notify all collaborators to re-clone |
| Test fixtures missing edge case | MEDIUM | 1. Add patient to fixture CSVs, 2. Document in `FIXTURE_DESIGN.md`, 3. Re-run full test suite, 4. Update schema version |
| `.Renviron` conflicts (project overrides user) | MEDIUM | 1. Delete project `.Renviron`, 2. Add to `.gitignore`, 3. Document env vars in README, 4. Team sets user `~/.Renviron` |
| SLURM job killed (too many workers) | LOW | 1. Fix worker count to read `SLURM_CPUS_PER_TASK`, 2. Resubmit job, 3. Add assertion to prevent recurrence |
| Fixture schema stale (missing new columns) | MEDIUM | 1. Regenerate fixtures with new schema, 2. Add schema validation test, 3. Document update process |
| HIPAA violation (realistic fixture) | HIGH | 1. Immediately delete fixture from all copies, 2. Legal review, 3. Redesign with unrealistic combos, 4. IRB notification if required |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Path separator failures | Phase 1 (Environment Detection) | Grep codebase for `paste.*"/"`, confirm all use `file.path()` |
| .Renviron scope conflicts | Phase 1 (Environment Detection) | Verify `.Renviron` in `.gitignore`, no project `.Renviron` exists |
| DuckDB file locking | Phase 2 (DuckDB Test Ingest) | Confirm separate DB paths in config, test from both environments |
| Missing edge cases in fixtures | Phase 3 (Edge Case Fixtures) | Review `FIXTURE_DESIGN.md`, confirm 1 patient per edge case type |
| Config breaking production | Phase 1 (Environment Detection) | Code review: production defaults unchanged, env var opt-in only |
| testthat state leakage | Phase 4 (Smoke Test Migration) | Search tests for `options(` and `Sys.setenv(`, confirm `withr::` wrappers |
| HIPAA fixture violations | Phase 3 (Edge Case Fixtures) | Legal/IRB review sign-off, unrealistic dates/sites confirmed |
| Committed production paths | Phase 1 (Environment Detection) | Pre-commit hook installed, test with staged `/blue/` path |
| HPC detectCores() misuse | (Out of scope — no parallelism in v2.2) | N/A — document for future if parallelism added |
| Fixture schema staleness | Phase 3 (Edge Case Fixtures) + ongoing | Schema validation test exists, passes with current fixture |

## Sources

### Path Separators
- [R file.path() Documentation](https://stat.ethz.ch/R-manual/R-devel/library/base/html/file.path.html) - Official R manual (HIGH confidence)
- [Cross Platform Development in R](https://bookdown.org/rdpeng/RProgDA/cross-platform-development.html) - Mastering Software Development in R (HIGH confidence)
- [RStudio Path Separator Issues](https://github.com/rstudio/rstudio/issues/11307) - Windows backslash PATH bug (MEDIUM confidence)

### .Renviron Scope
- [R Startup Documentation](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Startup.html) - Official R startup sequence (HIGH confidence)
- [R Startup - What They Forgot](https://rstats.wtf/r-startup.html) - Hadley Wickham's guide (HIGH confidence)
- [testthat Test Design](https://r-pkgs.org/testing-design.html) - Environment cleanup warning (HIGH confidence)

### DuckDB File Locking
- [DuckDB Concurrency Documentation](https://duckdb.org/docs/current/connect/concurrency) - Official concurrency model (HIGH confidence)
- [DuckDB R Package Issue #56](https://github.com/duckdb/duckdb-r/issues/56) - "Cannot open file" Windows error (HIGH confidence)
- [DuckDB Issue #13017](https://github.com/duckdb/duckdb/issues/13017) - Network storage lock failure (HIGH confidence)

### Test Fixtures & HIPAA
- [Synthetic Test Data vs Production (2026)](https://totalshiftleft.ai/blog/synthetic-test-data-vs-production-data) - HIPAA compliance requirements (MEDIUM confidence)
- [HIPAA-Compliant Test Data Management](https://www.accountablehq.com/post/hipaa-compliant-healthcare-test-data-management-best-practices-and-practical-steps) - Best practices (MEDIUM confidence)
- [PCORnet CDM Sample Dataset](https://ieee-dataport.org/documents/pcornet-cdm-sample-dataset) - Official PCORnet test data (HIGH confidence)

### Test Automation Maintenance
- [Test Automation Maintenance 2026](https://bugbug.io/blog/software-testing/test-automation-maintenance/) - Fixture staleness patterns (MEDIUM confidence)
- [Test Maintenance Guide 2026](https://autify.com/blog/test-maintenance) - Test data decay (MEDIUM confidence)

### Git & Credential Security
- [Managing Git Credentials in R](https://usethis.r-lib.org/articles/git-credentials.html) - usethis package (HIGH confidence)
- [Exposed Git Repos Security](https://pentera.io/blog/git-repo-security-exposed-secrets/) - 39M leaked secrets in 2024 (MEDIUM confidence)
- [GitIgnore Best Practices 2026](https://gitignore.pro/guide) - Patterns for R projects (MEDIUM confidence)

### HPC & SLURM
- [HPC:R Guide](https://hpcwiki.pmacs.upenn.edu/wiki/index.php/HPC:R) - detectCores() warning for HPC (HIGH confidence)
- [SLURM Environment Variables](https://docs.hpc.shef.ac.uk/en/latest/referenceinfo/scheduler/SLURM/SLURM-environment-variables.html) - SLURM_CPUS_PER_TASK usage (HIGH confidence)
- [Using R on HPC Clusters](https://www.glennklockwood.com/data-intensive/r/on-hpc.html) - Common HPC R mistakes (HIGH confidence)

### R Environment Detection
- [Sys.info() Documentation](https://stat.ethz.ch/R-manual/R-devel/library/base/html/Sys.info.html) - OS detection (HIGH confidence)
- [Environment Variables in R](https://runebook.dev/en/docs/r/library/base/html/sys.getenv) - Best practices (MEDIUM confidence)

### testthat
- [testthat Test Fixtures](https://testthat.r-lib.org/articles/test-fixtures.html) - Setup/teardown (HIGH confidence)
- [testthat 3.3.2 Documentation](https://cran.r-project.org/web/packages/testthat/testthat.pdf) - Test environment isolation (HIGH confidence)

### Clinical Data Testing
- [R Programming in Clinical Trials](https://www.quanticate.com/blog/r-programming-in-clinical-trials) - Validation concerns (MEDIUM confidence)
- [False Positives in Testing 2026](https://testfully.io/blog/false-positive-false-negative/) - Edge case detection (MEDIUM confidence)

---
*Pitfalls research for: Local Windows testing infrastructure for Linux HPC R clinical data pipeline*
*Researched: 2026-06-03*
